extends "res://world/world.gd"
## Full-tier run (docs/open-protocol/spec-full.md, client-responsibilities.md).
## Reuses the Thin world's renderer (low-res viewport + VHS post), map
## loader, weather, actors, viewmodel and fx, and fills the same `you`,
## `run`, `weather_state`, `others`, `enemy_points` and `pickups_list` the HUD
## reads. Unlike Thin it simulates the local player (world/full_player.gd),
## computes exposure, streams 20 Hz transforms and renders the host's RPCs.
##
## Input comes only from the Controls autoload (keyboard + mouse, gamepad and
## the touch layer all feed it). The test fields inherited from world.gd
## (auto_move, auto_bits, press_bits) are merged in for tests/full_drive.gd.

signal group_warning(at)

const FullPlayer = preload("res://world/full_player.gd")
const LevelPhysics = preload("res://world/level_physics.gd")
const FullFx = preload("res://world/full_fx.gd")
const Loadout = preload("res://core/loadout.gd")
const RECOIL_DEG = {"harpoon": 1.8, "hunting_rifle": 2.8, "pump_shotgun": 1.8, "rock_salt": 2.8, "spray_rifle": 0.7}
const STREAMS = ["wash", "gust", "zap", "suppress"]
const CASING_MECHANICS = ["", "pin", "hunt", "salt"]
const OFFER_RANGE = 9.0
const DROP_HEIGHT = 5.8
const KINDS = ["drip", "gutter", "mister", "sleet", "hailstone", "undertow", "static", "smog", "thunderhead"]
const PHASES = {0: "calm", 1: "calm", 2: "drizzle", 3: "downpour", 4: "clearing"}
const PUSH_DT = 0.05
const DEPLOY_PROPS = {"shield_dome": "shield_dome", "umbrella": "umbrella_open", "sandbag": "sandbag_wall",
	"lightning_rod": "lightning_rod_planted", "bug_bomb": "bug_bomb_canister"}
const BAYS = {"offer_1": Vector3(-0.62, 1.25, -0.58), "offer_2": Vector3(0.0, 1.25, -0.58),
	"offer_3": Vector3(0.62, 1.25, -0.58), "ammo": Vector3(-0.68, 0.56, -0.58)}
const SUPPLY_KIND = {"ammo": "ammo", "ammo_box": "ammo", "supply": "item", "health": "health", "suit": "suit",
	"scrap": "scrap", "scrap_large": "scrap", "tarp": "item", "decon": "item"}
const PING_SOUNDS = {"enemy": "ping_enemy", "go": "ping_go", "danger": "ping_danger", "revive": "ping_revive",
	"shelter": "ping_shelter"}

var net: Node                       # FullNet
var me: KinematicBody
var space: PhysicsDirectSpaceState
var lp_info = {}
var run_id = 0
var my_id = 0
var my_state = "ok"
var vit = {"hp": 100.0, "suit": 100.0, "bleed": 0.0, "max_hp": 100.0, "charge": 0.0, "invuln": false}
var tarp_up = false
var has_tarp = false
var inv = {"rev": -1, "rows": [[], [], [], [], []], "stash": {}, "slot": 0, "pouch": "", "scrap": 0, "frags": 0,
	"domes": 0, "reload_left": 0.0, "reload_total": 1.0, "jam_left": 0.0, "cooldown": 0.0}
var starter_state = 0               # 0 not sent, 1 sent, 2 accepted
var _starter_left = 0.0
var sheltered = false
var in_puddle = false
var _exposure_sent = false
var squad = {}                      # peer id -> {name, color, skin, state, tarp, target, vel, yaw, pitch, t, item, xform}
var _etarget = {}                   # enemy net id -> [pos, yaw]
var _tells = {}                     # enemy net id -> seconds left
var loot = {}                       # pickup id -> {node, pos, item, flavor, claim}
var effects = {}                    # seq -> {node, id, pos, vel, grav, deployed}
var cabinets = {}                   # key -> {node, pos, yaw, offers}
var drop = {}                       # airdrop: {node, pos, descent, t}
var clouds = {}
var spores = []
var puddles = []                    # {name, key, pos, max_r, grow, dry, growth, shown}
var shelters = []
var decons = []                     # {name, pos, path}
var player_mutations = []
var draft_hold = 0.0
var draft_active = false           # mutation draft dealt (inventory/interact blocked)
var phase_id = 0
var wave = 1
var phase_left = 0.0
var intensity = 0.0
var override = -1.0
var decon_charges = 0
var progress = {"wave": 1, "left": 0, "total": 0, "recovery": 0.0, "score": 0}
var endless = false
var tape_open = false
var pings = []                      # [pos, kind, life, peer]
# HUD read-only state (ui/hud.gd, ui/hud_panels.gd)
var boss = {}                       # Cumulus: {parts: [3 sacs + core], max: [...], sacs, burn}
var enemy_mutations = []            # active enemy mutation ids
var feat_log = []                   # [[id, amount], ...] from GameManager/Feats this run
var ready_tally = ""
var prompt = ""
var hold_progress = 0.0
var predicted_shots = 0
var accepted_shots = 0

var _push_left = 0.0
var _fire_left = 0.0
var _throw_left = 0.0
var _melee_left = 0.0
var _charge_left = -1.0
var _ping_left = 0.0
var _prev_bits = 0
var _hold_key = ""
var _hold_t = 0.0
var _hold_begun = false
var _hold_done = false
var _self_revive_wave = -1
var _puddle_left = 0.0
var _run_ready = false
var _ready_frames = 2
var _you_dirty = true
var _stats_left = 5.0
var ffx: Spatial                    # world/full_fx.gd
var spectate_id = 0
var _my_tarp: MeshInstance
var _kick = 0.0                     # camera recoil (rad), decays 8 deg/s
var _thunder = []                   # [seconds left, pos]
var _corpse_ms = []
var _was_airborne = false
var _cloud_mat = SpatialMaterial.new()
var _cloud_mesh = SphereMesh.new()


func _ready() -> void:
	net = FullNet
	my_id = net.you
	you = {"id": my_id, "state": "ok", "hp": 100.0, "hp_max": 100.0, "suit": 100.0, "suit_max": 100.0, "slot": 1,
		"slots": [null, null, null, null, null], "pos": [0, 0, 0], "vel": [0, 0, 0]}
	run = {"alive_enemies": 0, "wave": 1, "endless": false, "shared_decon": 0, "score": 0}
	weather_state = {"phase": "calm", "intensity": 0.0, "wave": 1, "phase_time_left": 0.0}
	_cloud_mat.flags_transparent = true
	_cloud_mat.flags_unshaded = true
	_cloud_mat.albedo_color = Color(0.55, 0.95, 0.35, 0.28)
	_cloud_mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	_cloud_mesh.radial_segments = 10
	_cloud_mesh.rings = 5


func _exit_tree() -> void:
	if net:
		net.unregister_world(self)
	Controls.capture_mouse(false)


func load_text() -> String:
	if loading:
		return "LOADING MAP  %d%%" % int(load_progress * 100.0)
	if not ready_to_play:
		if _warm_frames > 0:
			return "WARMING UP"
		return "CATCHING UP" if not net.run_ready else "TUNING"
	return ""


# ------------------------------------------------------------------ load
func _finish_load() -> void:
	._finish_load()
	var t = OS.get_ticks_msec()
	lp_info = LevelPhysics.new().build(level, map_id)
	space = scene.get_world().direct_space_state
	_load_ms["physics"] = OS.get_ticks_msec() - t
	var side = Assets.map_sidecar(map_id)
	for s in side.get("shelters", []):
		if s is Dictionary:
			var rot = s.get("rot", [0, 0, 0])
			shelters.append({"shape": str(s.get("shape", "box")), "pos": _v(s.get("pos")), "yaw": float(rot[1]) if rot is Array and rot.size() > 1 else 0.0,
				"size": _v(s.get("size")) if s.get("size") is Array else Vector3.ONE, "radius": float(s.get("radius", 1.0)), "height": float(s.get("height", 2.0))})
	for p in side.get("puddles", []):
		if p is Dictionary:
			var pos = _v(p.get("pos"))
			puddles.append({"name": str(p.get("name", "")), "key": "/root/Main/Level/Puddles/" + str(p.get("name", "")),
				"pos": pos, "floor": float(p.get("floor_y", pos.y)), "max_r": float(p.get("max_radius", 2.0)),
				"grow": float(p.get("grow_time", 45.0)), "dry": float(p.get("dry_time", 25.0)), "growth": 0.0, "shown": -1.0})
	for d in side.get("decon_showers", []):
		if d is Dictionary:
			var off = _v(d.get("interact_offset", [0, 1, 0]))
			decons.append({"name": str(d.get("name", "")), "pos": _v(d.get("pos")) + off, "radius": float(d.get("radius", 2.2)),
				"path": "/root/Main/Level/DeconShowers/%s/Interact" % str(d.get("name", ""))})
	me = FullPlayer.new()
	me.name = "Me"
	scene.add_child(me)
	ffx = FullFx.new()
	ffx.name = "FullFx"
	scene.add_child(ffx)
	_my_tarp = ffx.make_tarp()
	me.add_child(_my_tarp)
	var spawn = _spawn_for(my_id, net.roster_ids)
	me.teleport(spawn[0])
	yaw = spawn[1]
	pitch = 0.0
	look_ready = true
	print("FULL level ready map=%s physics=%s shelters=%d/%d puddles=%d decons=%d spawn=%s yaw=%.2f physics_ms=%d" % [map_id,
		str(lp_info.get("source", "?")), shelters.size(), (lp_info.get("shelters", []) as Array).size(), puddles.size(),
		decons.size(), str(spawn[0]), yaw, int(_load_ms.get("physics", 0))])
	net.register_world(self, map_id, level)


func _spawn_for(id: int, ids: Array) -> Array:
	var spawns = Assets.map_sidecar(map_id).get("player_spawns", [])
	var i = ids.find(id)
	if i < 0:
		i = 0
	if spawns is Array and not spawns.empty():
		var s = spawns[i % spawns.size()]
		return [_v(s.get("pos")), float(s.get("rot_y", 0.0))]
	return [Vector3(0, 0.5, 0), 0.0]


func _on_loading_frame() -> void:
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0:
			_warm.queue_free()
		return
	if not net.run_ready:
		return
	_ready_frames -= 1
	if _ready_frames <= 0:
		VisualServer.disconnect("frame_post_draw", self, "_on_loading_frame")
		ready_to_play = true
		print("LOAD done map=%s variant=%s read=%dms instance=%dms prepare=%dms physics=%dms extras=%dms total=%dms" % [
			map_id, _load_variant, int(_load_ms.get("read", 0)), int(_load_ms.get("instance", 0)),
			int(_load_ms.get("prepare", 0)), int(_load_ms.get("physics", 0)), int(_load_ms.get("extras", 0)), OS.get_ticks_msec() - _load_t0])
		get_parent().call_deferred("world_ready")


## Net._confirm_run_ready (spec-full §5 step 5): gameplay requests may start.
func on_run_ready() -> void:
	if _run_ready:
		return
	_run_ready = true
	_exposure_sent = false
	_send_exposure()
	_starter_left = 0.3


# ------------------------------------------------------------------ roster
func on_roster(ids: Array, roster: Dictionary) -> void:
	for id in ids:
		var r = roster.get(id, {})
		var e = squad.get(id)
		if e == null:
			var sp = _spawn_for(id, ids)
			e = {"name": "", "state": "ok", "tarp": false, "target": sp[0], "vel": Vector3.ZERO, "yaw": sp[1], "pitch": 0.0,
				"t": 0, "item": "", "pos": sp[0], "color": 1, "skin": 0}
			squad[id] = e
		e.name = str(r.get("name", "PLAYER")) if r is Dictionary else "PLAYER"
		e.color = int(r.get("color", 1)) if r is Dictionary else 1
		e.skin = int(r.get("skin", 0)) if r is Dictionary else 0
		if id != my_id:
			_ensure_actor(id)
	for id in squad.keys():
		if not (id in ids):
			squad.erase(id)
			var a = players.get(id)
			if a and is_instance_valid(a):
				a.queue_free()
			players.erase(id)


func _ensure_actor(id: int) -> void:
	var e = squad.get(id)
	if e == null:
		return
	var colors = net.data.get("cosmetics", {}).get("colors", [])
	var skins = net.data.get("cosmetics", {}).get("skins", [])
	var hexc = str(colors[e.color].get("hex", "#2ec9c9")) if e.color >= 0 and e.color < colors.size() else "#2ec9c9"
	var skin = str(skins[e.skin].get("name", "STANDARD")) if e.skin >= 0 and e.skin < skins.size() else "STANDARD"
	var model_id = Assets.player_model_id(skin, hexc)
	if e.state == "turned" and Assets.enemy_scene("turned"):
		model_id = "turned"
	var actor = players.get(id)
	if actor and is_instance_valid(actor) and actor.get_meta("model") == model_id:
		return
	if actor and is_instance_valid(actor):
		actor.queue_free()
	actor = Actor.new()
	actor.id = id
	actor.set_meta("model", model_id)
	scene.add_child(actor)
	if model_id == "turned":
		actor.setup_enemy("turned")
		actor.spawn_left = 0.0
	else:
		actor.setup_player(model_id, Weather.hex(hexc, Color("#2ec9c9")))
	if ffx:
		actor.tarp = ffx.make_tarp()
		actor.add_child(actor.tarp)
	actor.translation = e.pos
	actor.rotation.y = e.yaw
	actor.set_item(e.item if e.state != "turned" else "")
	players[id] = actor
	e["hex"] = hexc


func _player_entry(id: int) -> Dictionary:
	if not squad.has(id):
		squad[id] = {"name": "", "state": "ok", "tarp": false, "target": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0,
			"t": 0, "item": "", "pos": Vector3.ZERO, "color": 1, "skin": 0, "unseen": true}
	return squad[id]


# ------------------------------------------------------------------ RPC dispatch
func handle_rpc(node: String, method: String, args: Array) -> void:
	var _t = OS.get_ticks_usec()
	if node.begins_with("Main/Players/P_"):
		var rest = node.substr(15)
		var slash = rest.find("/")
		var id = int(rest if slash < 0 else rest.substr(0, slash))
		if slash < 0:
			_player_rpc(id, method, args)
		elif rest.ends_with("WeaponHolder"):
			_holder_rpc(id, method, args)
	else:
		match node:
			"Main/Enemies":
				_enemies_rpc(method, args)
			"Main/Enemies/BossCumulus":
				_boss_rpc(method, args)
			"Main/RunLoot":
				_loot_rpc(method, args)
			"Main/Pings":
				if method == "_show_ping" and args.size() >= 3:
					_show_ping(int(args[0]), str(args[1]), args[2])
			"GameManager":
				_gm_rpc(method, args)
			"GameManager/MutationRoll":
				_mutation_rpc(method, args)
			"GameManager/CrateManager":
				_crate_rpc(method, args)
			"WeatherManager":
				_weather_rpc(method, args)
			"GameManager/Feats":
				if method == "_feat_event" and args.size() >= 2:
					feat_log.append([str(args[0]), int(args[1])])
					for reward in Loadout.feat_event(str(args[0]), int(args[1])):
						emit_signal("banner", "UNLOCKED " + str(reward))
						print("FULL feat unlock %s" % str(reward))
			_:
				if method == "play_spray":
					for d in decons:
						if node.find("/" + d.name + "/") >= 0:
							Sound.play_at("decon_spray", d.pos)
							fx.spark(d.pos + Vector3(0, 0.6, 0), Color(0.5, 0.95, 1.0), 1.6)
	Settings.prof_add("w_rpc", OS.get_ticks_usec() - _t)


func _run_ok(args: Array) -> bool:
	if args.empty():
		return false
	var r = int(args[0])
	if run_id == 0:
		run_id = r
		print("FULL run id=%d" % run_id)
	return r == run_id


func _player_rpc(id: int, method: String, args: Array) -> void:
	var e = _player_entry(id)
	match method:
		"_relay_transform":
			if id == my_id or args.size() < 4:
				return
			e.target = args[0]
			e.yaw = float(args[1])
			e.pitch = float(args[2])
			e.vel = args[3]
			e.t = OS.get_ticks_msec()
			if e.get("unseen", false) or not e.has("seen"):
				e.erase("unseen")
				e["seen"] = true
				e.pos = e.target
		"_apply_vitals":
			if args.size() < 5:
				return
			var st = str(args[2])
			if id != my_id and (st == "turned") != (str(e.state) == "turned"):
				e.state = st
				_ensure_actor(id)
			e.state = st
			e.tarp = bool(args[4])
			e.hp = float(args[0])
			e.suit = float(args[1])
			e.max_hp = float(args[5]) if args.size() > 5 else 100.0
			if id == my_id:
				var old_state = my_state
				vit.hp = float(args[0])
				vit.suit = float(args[1])
				vit.bleed = float(args[3])
				vit.max_hp = float(args[5]) if args.size() > 5 else 100.0
				vit.charge = float(args[6]) if args.size() > 6 else 0.0
				vit.invuln = bool(args[7]) if args.size() > 7 else false
				tarp_up = bool(args[4])
				my_state = st
				if st != old_state:
					print("FULL state %s -> %s hp=%.0f" % [old_state, st, vit.hp])
					if st == "downed":
						Sound.play("downed")
					elif st == "turned":
						Sound.play("turned")
					elif st == "ok" and old_state == "downed":
						Sound.play("revive")
		"_apply_tarp":
			e.tarp = bool(args[0]) if not args.empty() else false
			if id == my_id:
				tarp_up = e.tarp
		"_receive_hurt_from":
			if id == my_id and not args.empty() and args[0] is Vector3:
				var d: Vector3 = args[0] - me.feet()
				emit_signal("hurt", d.normalized() if d.length() > 0.01 else null, 8.0)
				shake = min(1.0, shake + 0.3)
		"_receive_hits":
			if id == my_id and _run_ok(args) and args.size() > 1:
				_on_hits(args[1])
		"_teleport":
			if id == my_id and not args.empty() and args[0] is Transform:
				var xf: Transform = args[0]
				me.teleport(xf.origin)
				yaw = xf.basis.get_euler().y
				print("FULL teleport %s" % str(xf.origin))
		"_receive_enemy_pull":
			if id == my_id and not args.empty() and args[0] is Vector3:
				me.enemy_pull += args[0]
		"_grant_tarp":
			if id == my_id:
				has_tarp = true
				emit_signal("banner", "TARP READY")


func _holder_rpc(id: int, method: String, args: Array) -> void:
	match method:
		"_private_state":
			if id != my_id or args.size() < 13 or not _run_ok(args):
				return
			var rev = int(args[1])
			if rev <= int(inv.rev):
				return
			var old_rows = inv.rows
			inv.rev = rev
			inv.rows = args[2] if args[2] is Array else [[], [], [], [], []]
			inv.stash = args[3] if args[3] is Dictionary else {}
			inv.slot = int(args[4])
			inv.pouch = str(args[5])
			inv.scrap = int(args[6])
			inv.frags = int(args[7])
			inv.domes = int(args[8])
			inv.reload_left = float(args[9])
			inv.reload_total = max(0.01, float(args[10]))
			inv.jam_left = float(args[11])
			inv.cooldown = float(args[12])
			for i in min(5, inv.rows.size()):
				var row = inv.rows[i]
				var old = old_rows[i] if i < old_rows.size() else []
				if row is Array and row.size() >= 4 and (not (old is Array) or old.size() < 4 or old[0] != row[0]):
					emit_signal("picked", str(row[1]))
			_you_dirty = true
		"_equip_state":
			if id == my_id or args.size() < 3:
				return
			var e = _player_entry(id)
			e.item = str(args[2])
			var a = players.get(id)
			if a and is_instance_valid(a):
				a.set_item(e.item)
		"_shot_fx":
			if args.size() >= 7:
				_on_shot_fx(id, str(args[1]), args[2], args[3], args[4], bool(args[6]))
		"_throw_fx":
			if args.size() >= 5 and not (id == my_id and bool(args[4])):
				var sfx = str(Assets.weapon(str(args[1])).get("shot_sound", "throw_bomb"))
				if args[2] is Vector3:
					Sound.play_at(sfx, args[2])
		"_jam":
			if id == my_id:
				Sound.play("jam")
				emit_signal("banner", "JAMMED")
		"_play_charge":
			if id == my_id:
				Sound.play("gun_disruptor_charge")
		"_pouch_full_feedback":
			if id == my_id:
				emit_signal("banner", "POUCH FULL")
		"_scrap_feedback":
			if id == my_id and args.size() > 1:
				Sound.play("pickup", -6.0)


func _on_hits(hits) -> void:
	if not (hits is Array):
		return
	var evs = []
	for h in hits:
		if not (h is Array) or h.size() < 5:
			continue
		var killed = bool(h[0])
		var crit = bool(h[1])
		var at: Vector3 = h[2] if h[2] is Vector3 else Vector3.ZERO
		emit_signal("hit_marker", killed, crit)
		evs.append({"e": "hit", "at": [at.x, at.y, at.z], "dmg": int(h[3]), "head": crit})
		var a = enemies.get(int(h[4]))
		if a and is_instance_valid(a):
			a.hurt(crit)
		fx.spark(at, Color(1.0, 0.85, 0.4) if crit else Color(0.62, 1.0, 0.35))
		Sound.play("headshot" if crit else "hit_enemy", -6.0)
		if killed:
			Sound.play("kill_confirm", -8.0)
			emit_signal("killed", "")
	if not evs.empty():
		net.emit_events(evs)


## HOLDER._shot_fx (weapon_combat.gd play_fx): streams draw beams with no
## flash, the harpoon flies and reels on its cable, pellets fan out, impacts
## puff by surface (2 = flesh) and sparks on metal.
func _on_shot_fx(id: int, item_id: String, origin, dir, traces, predicted: bool) -> void:
	if not (origin is Vector3):
		return
	var meta = Assets.weapon(item_id)
	var w = net.item(item_id).get("weapon", {})
	w = w if w is Dictionary else {}
	var mech = str(w.get("mechanic", ""))
	var stream = mech in STREAMS
	var color: Color = Color(meta.get("tracer_color")) if meta.get("tracer_color") is String else Color(1.0, 0.85, 0.5)
	var mine = id == my_id
	var from: Vector3 = origin + (dir * 0.55 if dir is Vector3 else Vector3.ZERO)
	var fresh = not (mine and predicted)
	if mine:
		accepted_shots += 1
		from = viewmodel.muzzle_position()
		if not predicted:
			viewmodel.fire()
			_shot_juice(item_id, w)
	if fresh:
		if not stream:
			fx.flash(from, 0.35 if mine else 0.45, color.lightened(0.3))
		var cue = str(meta.get("shot_sound", ""))
		if mine:
			Sound.play(cue, -2.5)
		else:
			Sound.play_at(cue, from, -4.5)
	if not (traces is Array) or str(w.get("fire_kind", "hitscan")) != "hitscan":
		return
	if mech == "reel":
		if not traces.empty() and traces[0] is Array and traces[0].size() >= 2 and traces[0][0] is Vector3:
			var bolt = _make_projectile("harpoon")
			ffx.harpoon(bolt, from, traces[0][0], color)
			_impact(int(traces[0][1]), traces[0][0], from, false)
		return
	var n = 0
	var flesh = 0
	for tr in traces:
		if not (tr is Array) or tr.size() < 2 or not (tr[0] is Vector3):
			continue
		n += 1
		if n > 10:
			break
		if stream:
			fx.tracer(from, tr[0], color, 0.14 if mech in ["wash", "gust"] else 0.06, true)
		else:
			fx.tracer(from, tr[0], color)
		var impact = int(tr[1])
		if impact == 2:
			flesh += 1
		if n <= 3:
			_impact(impact, tr[0], from, stream)
	if flesh > 0 and not stream:
		Sound.play_at("hit_flesh", from, -18.0 + min(6.0, 2.0 * (flesh - 1)))


func _impact(impact: int, at: Vector3, from: Vector3, stream: bool) -> void:
	match impact:
		1:
			fx.flash(at, 0.22, Color("#bbad99"), 0.17)
		2:
			fx.flash(at, 0.22, Color("#b0f580"), 0.17)
		3:
			if stream:
				fx.flash(at, 0.22, Color("#bbad99"), 0.17)
			else:
				fx.spark(at, Color(1.0, 0.9, 0.55), 0.6)


## Local shot feel (weapon_holder _local_shot_motion / _shot_juice): camera
## kick by the weapon's recoil, shake for pellets, ejected casing, pump.
func _shot_juice(item_id: String, w: Dictionary) -> void:
	var mech = str(w.get("mechanic", ""))
	var ads = _aiming()
	var k = (0.5 if "hyper_focus" in player_mutations else 0.65) if ads else 1.0
	_kick = min(_kick + deg2rad(float(RECOIL_DEG.get(item_id, 0.6))) * k, deg2rad(5.0))
	var heavy = int(w.get("pellets", 1)) > 1
	if mech == "reel":
		shake = min(1.0, shake + 0.36)
		return
	if str(w.get("fire_kind", "hitscan")) != "hitscan" or not (mech in CASING_MECHANICS):
		return
	shake = min(1.0, shake + (0.28 if heavy else 0.05))
	var right = camera.global_transform.basis.x
	ffx.casing(viewmodel.muzzle_position() - camera.global_transform.basis.z * -0.25 + right * 0.05, right, heavy)
	if item_id == "pump_shotgun":
		get_tree().create_timer(float(w.get("fire_interval", 0.85)) * 0.2).connect("timeout", Sound, "play", ["shotgun_pump", -11.0])


func _enemies_rpc(method: String, args: Array) -> void:
	match method:
		"_spawn_enemy":
			if args.size() < 4:
				return
			var id = int(args[0])
			var kind = int(args[1])
			var mb = int(args[5]) if args.size() > 5 else 0
			var type = "cloudburst" if mb == 3 else (KINDS[kind] if kind >= 0 and kind < KINDS.size() else "gutter")
			var old = enemies.get(id)
			if old and is_instance_valid(old):
				old.queue_free()
			var a = Actor.new()
			a.id = id
			scene.add_child(a)
			a.setup_enemy(type)
			if bool(args[3]):
				a.scale = Vector3.ONE * 0.65
			var at: Vector3 = args[2] if args[2] is Vector3 else Vector3.ZERO
			a.translation = at
			if args.size() > 4 and bool(args[4]):
				a.scale *= 1.12
				a.set_meta("elite", true)
			enemies[id] = a
			_etarget[id] = [at, 0.0]
			Settings.spike_ctx.append("spawn:" + type)
		"_sync_enemies":
			if args.size() < 3:
				return
			var ids = args[0]
			var places = args[1]
			var yaws = args[2]
			var n = min(ids.size(), min(places.size(), yaws.size()))
			for i in n:
				var id = int(ids[i])
				if _etarget.has(id):
					_etarget[id] = [places[i], float(yaws[i])]
		"_despawn_enemy":
			if args.empty():
				return
			var id = int(args[0])
			var a = enemies.get(id)
			enemies.erase(id)
			_etarget.erase(id)
			_tells.erase(id)
			if a and is_instance_valid(a):
				var throw: Vector3 = args[3] if args.size() > 3 and args[3] is Vector3 else Vector3.ZERO
				var crit = args.size() > 4 and bool(args[4])
				var at2: Vector3 = args[2] if args.size() > 2 and args[2] is Vector3 else a.translation
				var now = OS.get_ticks_msec()
				while not _corpse_ms.empty() and now - int(_corpse_ms[0]) > 4000:
					_corpse_ms.pop_front()
				var linger = 2.4 if _corpse_ms.size() < 6 else 0.0
				if linger > 0.0:
					_corpse_ms.append(now)
				a.kill(throw, linger)
				ffx.fragments(at2, throw, crit)
				ffx.splat(at2, 0.55 if a.scale.x < 0.9 else 0.8)
				Sound.play_at("enemy_death", a.translation, -4.0)
		"_retire_enemies":
			if args.empty():
				return
			for id in args[0]:
				var a = enemies.get(int(id))
				enemies.erase(int(id))
				_etarget.erase(int(id))
				if a and is_instance_valid(a):
					a.queue_free()
		"_play_enemy_tell":
			if args.size() >= 3:
				var a = enemies.get(int(args[0]))
				if a and is_instance_valid(a):
					a.set_anim("windup")
					_tells[int(args[0])] = max(0.2, float(args[2]))
					Sound.play_at(str(args[1]), a.translation + Vector3(0, 0.2 if a.type == "gutter" else 1.0, 0), float(args[3]) if args.size() > 3 else 0.0)
					if float(args[2]) > 0.0:
						ffx.tell(a, a.type, float(args[2]), _tell_radius(a.type) * a.scale.x)
		"_play_enemy_molt":
			var a = enemies.get(int(args[0])) if not args.empty() else null
			if a and is_instance_valid(a):
				fx.spark(a.translation + Vector3(0, 1.1, 0), Color(0.8, 0.9, 1.0), 1.2)
				Sound.play_at("hit_flesh", a.translation + Vector3(0, 1, 0), -12.0)
		"_enemy_impacts":
			if not args.empty() and args[0] is Array:
				for row in args[0]:
					if row is Array and row.size() >= 3:
						var a = enemies.get(int(row[0]))
						if a and is_instance_valid(a):
							a.hurt(bool(row[2]))
		"_sync_miniboss_hp":
			if args.size() >= 3:
				var a = enemies.get(int(args[0]))
				if a and is_instance_valid(a):
					a.hp = float(args[1]) / max(1.0, float(args[2]))
		"_receive_group_warning":
			if not args.empty() and args[0] is Vector3:
				emit_signal("group_warning", args[0])
				Sound.play("incoming_group", -6.0)
		"_sync_progress":
			if args.size() >= 5:
				progress = {"wave": int(args[0]), "left": int(args[1]), "total": int(args[2]), "recovery": float(args[3]), "score": int(args[4])}


func _tell_radius(type: String) -> float:
	for k in net.data.get("enemy_kinds", []):
		if k is Dictionary and str(k.get("id", "")) == type:
			return clamp(float(k.get("attack_range", 1.6)), 1.0, 6.0)
	return 1.6


func _boss_rpc(method: String, args: Array) -> void:
	var a = enemies.get(0)
	match method:
		"_sync":
			if a and is_instance_valid(a) and args.size() >= 3 and args[0] is Vector3:
				_etarget[0] = [args[0], a.rotation.y]
				var sacs = int(args[2])
				a.hp = [0.2, 0.4, 0.75, 1.0][int(clamp(sacs, 0, 3))]
			if args.size() >= 4 and args[1] is Array:
				var mx = boss.get("max", [1.0, 1.0, 1.0, 1.0])
				for i in min(4, args[1].size()):
					mx[i] = max(float(mx[i]), float(args[1][i]))
				boss = {"parts": args[1], "max": mx, "sacs": int(args[2]), "burn": float(args[3])}
		"_died":
			if a and is_instance_valid(a):
				a.kill()
				Sound.play("explosion_big")
			enemies.erase(0)
			_etarget.erase(0)
			boss = {}


func _loot_rpc(method: String, args: Array) -> void:
	if not _run_ok(args):
		return
	match method:
		"_snapshot":
			for row in args[1] if args.size() > 1 and args[1] is Array else []:
				if row is Array and row.size() >= 2:
					_spawn_loot(int(row[0]), row[1])
			for row in args[2] if args.size() > 2 and args[2] is Array else []:
				if row is Array and row.size() >= 2:
					_effect_spawn(int(row[0]), row[1])
			if args.size() > 4 and bool(args[4]):
				starter_state = 2
			print("FULL loot snapshot pickups=%d effects=%d chosen=%s" % [loot.size(), effects.size(), str(starter_state == 2)])
		"_spawn":
			if args.size() >= 3:
				_spawn_loot(int(args[1]), args[2])
		"_remove":
			if args.size() >= 2:
				var id = int(args[1])
				var l = loot.get(id)
				if l:
					if args.size() > 2 and int(args[2]) == my_id:
						Sound.play("pickup", -4.0)
						if not str(l.flavor).empty():
							emit_signal("picked", str(l.flavor))
					if is_instance_valid(l.node):
						l.node.queue_free()
					loot.erase(id)
					_rebuild_pickups_list()
		"_release":
			var l2 = loot.get(int(args[1])) if args.size() > 1 else null
			if l2:
				l2.claim = 0
		"_starter_accepted":
			starter_state = 2
			print("FULL starter accepted")
		"_effect_spawn":
			if args.size() >= 3:
				_effect_spawn(int(args[1]), args[2])
		"_flight":
			if args.size() >= 2 and args[1] is Array:
				for row in args[1]:
					if row is Array and row.size() >= 3:
						var ef = effects.get(int(row[0]))
						if ef and row[1] is Vector3:
							ef.pos = row[1]
							ef.vel = row[2] if row[2] is Vector3 else Vector3.ZERO
		"_effect_deploy":
			if args.size() >= 3:
				var ef = effects.get(int(args[1]))
				if ef:
					ef.deployed = true
					ef.pos = args[2] if args[2] is Vector3 else ef.pos
					ef.vel = Vector3.ZERO
					var prop = DEPLOY_PROPS.get(ef.id, "")
					var packed = Assets.prop_scene(prop) if not prop.empty() else null
					if packed:
						if is_instance_valid(ef.node):
							ef.node.queue_free()
						ef.node = packed.instance()
						RetroMat.prepare(ef.node)
						scene.add_child(ef.node)
					ef.node.translation = ef.pos
					if args.size() > 4:
						ef.node.rotation = Vector3(0, float(args[4]), 0)
					ef["yaw"] = float(args[4]) if args.size() > 4 else 0.0
					_open_zone(int(args[1]), ef, float(args[3]) if args.size() > 3 else 0.0)
					var ds = str(Assets.weapon(ef.id).get("deploy_sound", ""))
					Sound.play_at("dome_deploy" if ef.id == "shield_dome" else (ds if not ds.empty() else "gun_field_deploy"), ef.pos)
		"_effect_end":
			if args.size() >= 2:
				var seq = int(args[1])
				var ef = effects.get(seq)
				effects.erase(seq)
				var at: Vector3 = args[2] if args.size() > 2 and args[2] is Vector3 else (ef.pos if ef else Vector3.ZERO)
				if ef and is_instance_valid(ef.node):
					ef.node.queue_free()
				ffx.zone_close(seq)
				if ef and ef.id == "shield_dome" and ef.deployed and not (args.size() > 3 and bool(args[3])):
					Sound.play_at("dome_collapse", at, -10.0)
				if args.size() > 3 and bool(args[3]):
					var col = Color(1.0, 0.6, 0.25)
					fx.spark(at, col, 2.2)
					fx.flash(at, 3.0, col)
					var bs = str(Assets.weapon(ef.id if ef else "").get("blast_sound", "explosion"))
					Sound.play_at(bs if not bs.empty() else "explosion", at)
					if me and at.distance_to(me.feet()) < 12.0:
						shake = min(1.0, shake + 0.5)


func _spawn_loot(id: int, row) -> void:
	if not (row is Array) or row.size() < 3:
		return
	var old = loot.get(id)
	if old and is_instance_valid(old.node):
		old.node.queue_free()
	var pos: Vector3 = row[0] if row[0] is Vector3 else Vector3.ZERO
	var item = row[1] if row[1] is Array else []
	var flavor = str(row[2])
	var item_id = str(item[1]) if item.size() >= 4 else ""
	var kind = "item"
	if flavor.empty():
		kind = "weapon" if str(net.item(item_id).get("kind", "")) == "gun" else "item"
	else:
		kind = SUPPLY_KIND.get(flavor, "item")
	var node = _make_pickup({"kind": kind, "item": item_id if flavor.empty() else flavor})
	scene.add_child(node)
	node.translation = pos
	loot[id] = {"node": node, "pos": pos, "item": item, "flavor": flavor, "claim": int(row[3]) if row.size() > 3 else 0,
		"kind": kind, "id_s": item_id}
	_rebuild_pickups_list()


func _rebuild_pickups_list() -> void:
	pickups_list = []
	for id in loot:
		var l = loot[id]
		pickups_list.append({"id": id, "item": l.id_s if l.flavor.empty() else l.flavor, "kind": l.kind, "pos": [l.pos.x, l.pos.y, l.pos.z]})
	for key in cabinets:
		var c = cabinets[key]
		pickups_list.append({"id": key, "item": "station", "kind": "station", "pos": [c.pos.x, c.pos.y, c.pos.z]})
	if not drop.empty():
		pickups_list.append({"id": "airdrop", "item": "airdrop", "kind": "airdrop", "pos": [drop.pos.x, drop.pos.y, drop.pos.z]})


func _effect_spawn(seq: int, row) -> void:
	if not (row is Array) or row.size() < 5:
		return
	var id = str(row[0])
	var old = effects.get(seq)
	if old and is_instance_valid(old.node):
		old.node.queue_free()
	var deployed = bool(row[4])
	var node: Spatial = null
	if deployed and DEPLOY_PROPS.has(id):
		var packed = Assets.prop_scene(DEPLOY_PROPS[id])
		if packed:
			node = packed.instance()
			RetroMat.prepare(node)
	if node == null:
		node = _make_projectile(id)
	scene.add_child(node)
	var pos: Vector3 = row[1] if row[1] is Vector3 else Vector3.ZERO
	node.translation = pos
	if row.size() > 6:
		node.rotation.y = float(row[6])
	var w = net.item(id).get("weapon", {})
	effects[seq] = {"node": node, "id": id, "pos": pos, "vel": row[2] if row[2] is Vector3 else Vector3.ZERO,
		"grav": float(w.get("projectile_gravity", 1.0)) if w is Dictionary else 1.0, "deployed": deployed,
		"yaw": float(row[6]) if row.size() > 6 else 0.0}
	if deployed:
		_open_zone(seq, effects[seq], float(row[5]) if row.size() > 5 else 0.0)


## projectile.gd deploy/_build_zone: rim + dome/sweep sized by effect_radius.
func _open_zone(seq: int, ef: Dictionary, life: float) -> void:
	var w = net.item(ef.id).get("weapon", {})
	var radius = float(w.get("effect_radius", 0.0)) if w is Dictionary else 0.0
	if ef.id == "sandbag":
		radius = 0.0
	var meta = Assets.weapon(ef.id)
	var color: Color = Color(meta.get("tracer_color")) if meta.get("tracer_color") is String else Color(0.7, 0.9, 1.0)
	ffx.zone_open(seq, ef.id, ef.pos, float(ef.get("yaw", 0.0)), radius, color, life)
	if ef.id == "lightning_rod":
		Sound.play_at("static_power", ef.pos + Vector3(0, 0.95, 0), -4.0)
	elif ef.id == "bait_radio":
		Sound.play_at("gun_bait_loop", ef.pos, -10.0)


func _gm_rpc(method: String, args: Array) -> void:
	match method:
		"_banner":
			if not args.empty():
				emit_signal("banner", str(args[0]))
		"_sync_decon":
			decon_charges = int(args[0]) if not args.empty() else 0
		"_sync_tape_state":
			if args.size() >= 3:
				endless = bool(args[1])
				var open = bool(args[0])
				if open != tape_open:
					tape_open = open
					if open:
						net.emit_signal("tape", {"can_choose": net.first_peer == my_id})
					else:
						net.emit_signal("draft_done")
		"_ready_changed":
			if args.size() >= 2:
				ready_tally = "READY %d/%d" % [int(args[0]), int(args[1])] if int(args[0]) > 0 else ""
				if int(args[0]) > 0:
					emit_signal("banner", ready_tally)
		"_spawn_boss":
			if not args.empty() and args[0] is Vector3:
				var old = enemies.get(0)
				if old and is_instance_valid(old):
					old.queue_free()
				var a = Actor.new()
				a.id = 0
				scene.add_child(a)
				a.setup_enemy("cumulus")
				a.translation = args[0]
				enemies[0] = a
				_etarget[0] = [args[0], 0.0]
		"_spawn_cloud":
			if args.size() >= 4 and args[1] is Vector3:
				var mi = MeshInstance.new()
				mi.mesh = _cloud_mesh
				mi.material_override = _cloud_mat
				var r = max(0.5, float(args[3]))
				mi.transform = Transform(Basis().scaled(Vector3(r, r * 0.45, r)), args[1] + Vector3(0, r * 0.2, 0))
				scene.add_child(mi)
				var old = clouds.get(int(args[0]))
				if old and is_instance_valid(old):
					old.queue_free()
				clouds[int(args[0])] = mi
		"_disperse_cloud":
			var c = clouds.get(int(args[0])) if not args.empty() else null
			if c and is_instance_valid(c):
				c.queue_free()
			if not args.empty():
				clouds.erase(int(args[0]))
		"_spawn_spore":
			if args.size() >= 4 and args[1] is Vector3 and args[2] is Vector3:
				var acid = args.size() > 5 and bool(args[5])
				var node = _make_projectile("acid_glob" if acid else "spore_glob")
				scene.add_child(node)
				node.translation = args[1]
				spores.append({"node": node, "from": args[1], "to": args[2], "flight": max(0.1, float(args[3])), "t": 0.0})
				if args.size() > 6 and bool(args[6]):
					ffx.ground_ring(args[2], 3.0, max(0.1, float(args[3])), Color(0.72, 0.55, 1.0) if not acid else Color(0.72, 1.0, 0.34))
				Sound.play_at("smog_spit", args[1], -4.0)
		"_draw_arc":
			if not args.empty() and args[0] is Array:
				var col = args[1] if args.size() > 1 and args[1] is Color else Color(0.7, 0.9, 1.0)
				var pts = args[0]
				for i in range(1, pts.size()):
					if pts[i - 1] is Vector3 and pts[i] is Vector3:
						fx.tracer(pts[i - 1], pts[i], col)
		"_draw_blast":
			if args.size() >= 2 and args[0] is Vector3:
				var col2 = args[2] if args.size() > 2 and args[2] is Color else Color(1.0, 0.6, 0.25)
				fx.spark(args[0], col2, clamp(float(args[1]) * 0.4, 0.6, 2.5))
				fx.flash(args[0], clamp(float(args[1]), 0.5, 4.0), col2)
		"_sync_pause":
			if args.size() >= 1:
				emit_signal("banner", ("PAUSED BY " + str(args[1]) if args.size() > 1 else "PAUSED") if bool(args[0]) else "RESUMED")
		"_weapon_unlocked":
			if not args.empty():
				emit_signal("banner", "UNLOCKED " + str(args[0]))


func _mutation_rpc(method: String, args: Array) -> void:
	match method:
		"_deal_rpc":
			if args.size() >= 2 and args[1] is Array:
				draft_active = true
				draft_hold = 9999.0
				var cards = []
				for id in args[1]:
					var m = net.player_mutations.get(str(id), {})
					cards.append({"id": str(id), "title": str(m.get("name", str(id).replace("_", " "))), "desc": str(m.get("desc", ""))})
				var em = net.enemy_mutations.get(str(args[0]), {})
				net.emit_signal("draft", {"cards": cards, "time_left": max(5.0, phase_left), "enemy": str(em.get("name", ""))})
				print("FULL draft dealt %s enemy=%s" % [str(args[1]), str(args[0])])
		"_votes_rpc":
			pass
		"_result_rpc":
			draft_active = false
			draft_hold = 2.2
			if args.size() >= 3 and args[2] is Array:
				_set_mutations(args[2])
			if args.size() >= 2 and args[1] is Array:
				enemy_mutations = Array(args[1])
			net.emit_signal("draft_done")
		"_sync_active":
			if args.size() >= 2 and args[1] is Array:
				_set_mutations(args[1])
			if not args.empty() and args[0] is Array:
				enemy_mutations = Array(args[0])
		"_reset_run_rpc":
			_set_mutations([])
			enemy_mutations = []
		"_clear_rpc":
			enemy_mutations = []


func _set_mutations(list: Array) -> void:
	player_mutations = []
	for m in list:
		player_mutations.append(str(m))
	if me:
		var adr = "adrenaline_glands" in player_mutations
		me.speed_scale = 1.18 if adr else 1.0
		me.jump_scale = 1.2 if adr else 1.0


func _crate_rpc(method: String, args: Array) -> void:
	if not _run_ok(args):
		return
	match method:
		"_snapshot":
			if args.size() > 1 and args[1] is Dictionary:
				for key in args[1]:
					_cabinet(str(key), args[1][key])
			if args.size() > 2 and args[2] is Array and args[2].size() >= 2 and args[2][0] is Vector3:
				_airdrop(args[2][0], float(args[2][1]))
			_rebuild_pickups_list()
		"_stock":
			if args.size() >= 3:
				_cabinet(str(args[1]), args[2])
		"_reveal":
			if args.size() >= 5:
				emit_signal("banner", str(args[4]))
		"_announce_drop":
			emit_signal("banner", "AIRDROP INBOUND")
		"_airdrop_spawn":
			if args.size() >= 3 and args[1] is Vector3:
				_airdrop(args[1], float(args[2]))
				_rebuild_pickups_list()
		"_remove_drop":
			if not drop.empty() and is_instance_valid(drop.node):
				drop.node.queue_free()
			drop = {}
			ffx.beacon(null, false)
			_rebuild_pickups_list()


func _cabinet(key: String, offers) -> void:
	var c = cabinets.get(key)
	if c == null:
		var pos = Vector3.ZERO
		var y = 0.0
		for s in Assets.map_sidecar(map_id).get("vending_stations", []):
			if s is Dictionary and str(s.get("name", "")) == key:
				pos = _v(s.get("pos"))
				y = float(s.get("rot_y", 0.0))
		var node = _make_pickup({"kind": "station", "item": "station"})
		scene.add_child(node)
		node.translation = pos
		node.rotation.y = y
		c = {"node": node, "pos": pos, "yaw": y, "offers": [], "shown": [], "mounts": []}
		cabinets[key] = c
	c.offers = offers if offers is Array else []
	c.shown = []      # rebuild the bay models next time the player is near


## Native supply_station set_offers: each bay shows its item at 0.44 scale.
## Built (merged per material) only within OFFER_RANGE, freed beyond it.
func _update_offers() -> void:
	if me == null or Engine.get_frames_drawn() % 10 != 0:
		return
	var feet = me.feet()
	for key in cabinets:
		var c = cabinets[key]
		var near = feet.distance_to(c.pos) < OFFER_RANGE
		var want = []
		if near:
			for off in c.offers:
				want.append(str(off[0]) if off is Array and off.size() >= 1 else "")
		if want == c.shown:
			continue
		for m in c.mounts:
			if is_instance_valid(m):
				m.queue_free()
		c.mounts = []
		c.shown = want
		var basis = Basis(Vector3.UP, c.yaw)
		for i in min(3, want.size()):
			if want[i].empty():
				continue
			var packed = Assets.weapon_pickup(want[i])
			if packed == null:
				continue
			var item: Spatial = RetroMat.instance_merged(packed, [])
			RetroMat.prepare(item)
			item.transform = Transform(basis * Basis(Vector3(deg2rad(0.0), deg2rad(-75.0), deg2rad(6.0))).scaled(Vector3.ONE * 0.44),
				c.pos + basis.xform(Vector3([-0.62, 0.0, 0.62][i], 1.24, -0.50)))
			scene.add_child(item)
			c.mounts.append(item)


func _airdrop(at: Vector3, descent: float) -> void:
	if not drop.empty() and is_instance_valid(drop.node):
		drop.node.queue_free()
	var node = _make_pickup({"kind": "airdrop", "item": "airdrop"})
	scene.add_child(node)
	drop = {"node": node, "pos": at, "descent": max(0.0, descent), "t": max(0.0, descent), "chute": node.find_node("Parachute", true, false)}
	node.translation = at + Vector3(0, drop.t * DROP_HEIGHT, 0)
	_was_airborne = drop.t > 0.0


func _weather_rpc(method: String, args: Array) -> void:
	match method:
		"_receive_phase":
			if args.size() >= 3:
				var old = phase_id
				phase_id = int(args[0])
				wave = max(1, int(args[1]))
				phase_left = float(args[2])
				if old != phase_id:
					print("FULL phase %s wave=%d left=%.1f" % [PHASES.get(phase_id, "?"), wave, phase_left])
					if phase_id in [2, 3] and not (old in [2, 3]):
						Sound.play("storm_arrival", -4.0)
					elif phase_id == 4:
						Sound.play("storm_clear", -4.0)
		"_receive_intensity":
			if not args.empty():
				intensity = float(args[0])
		"_override":
			if not args.empty():
				override = float(args[0])
		"_strike":
			if not args.empty() and args[0] is Vector3:
				weather.strike(args[0])
				glitch = max(glitch, Settings.flash_scale())
				var tactical = args.size() > 1 and int(args[1]) >= 0
				var dist = args[0].distance_to(me.feet()) if me else 0.0
				if tactical:
					fx.spark(args[0] + Vector3(0, 0.3, 0), Color("#9fd8ff"), 2.0)
					fx.flash(args[0] + Vector3(0, 1.0, 0), 4.0, Color("#9fd8ff"), 0.15)
					if dist < 14.0:
						shake = min(1.0, shake + 0.6)
				_thunder.append([clamp(dist / 343.0, 0.0, 2.5), -2.0 if dist < 30.0 else -8.0])
		"_sync_puddles":
			if not args.empty() and args[0] is Dictionary:
				for k in args[0]:
					var ks = str(k)
					for p in puddles:
						if p.key == ks:
							p.growth = clamp(float(args[0][k]), 0.0, 1.0)


func _show_ping(peer: int, kind: String, pos) -> void:
	if not (pos is Vector3):
		return
	pings.append([pos, kind, 6.0, peer])
	if ffx:
		ffx.ping(pos, kind)
	while pings.size() > 8:
		pings.pop_front()
	Sound.play(PING_SOUNDS.get(kind, "ping_item"), -6.0)


# ------------------------------------------------------------------ frame
func _process_body(delta: float) -> void:
	_anim_time += delta
	if loading:
		_step_load()
		return
	if level == null or me == null:
		return
	var _t = OS.get_ticks_usec()
	_update_weather(delta)
	_update_remote(delta)
	_update_effects(delta)
	Settings.prof_add("w_sync", OS.get_ticks_usec() - _t)
	_t = OS.get_ticks_usec()
	var inp = _full_input()
	if ready_to_play and not net.finished:
		_local_sim(delta, inp)
	Settings.prof_add("w_local", OS.get_ticks_usec() - _t)
	_full_camera(delta, inp)
	_t = OS.get_ticks_usec()
	weather.update(delta, weather_state)
	Settings.prof_add("w_weather", OS.get_ticks_usec() - _t)
	run["shared_decon"] = decon_charges
	_update_decon()
	glitch = max(move_toward(glitch, 0.0, delta * 1.6), 0.45 * Settings.flash_scale() if my_state == "downed" else 0.0)
	var mat = post_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_param("glitch", glitch)
	_build_hud_state(inp)
	for i in range(pings.size() - 1, -1, -1):
		pings[i][2] -= delta
		if pings[i][2] <= 0.0:
			pings.remove(i)
	_stats_left -= delta
	if _stats_left <= 0.0:
		_stats_left = 5.0
		print("FULLSTAT state=%s hp=%.0f suit=%.0f pos=%s shelter=%s puddle=%s enemies=%d players=%d loot=%d effects=%d shots=%d/%d phase=%s wave=%d rtt=%.0f" % [
			my_state, vit.hp, vit.suit, str(me.feet().snapped(Vector3.ONE * 0.1)), str(sheltered), str(in_puddle), enemies.size(),
			squad.size(), loot.size(), effects.size(), accepted_shots, predicted_shots, weather_state.phase, wave, net.rtt_ms])


func _update_weather(delta: float) -> void:
	draft_hold = max(0.0, draft_hold - delta) if not draft_active else draft_hold
	if draft_hold <= 0.0 or phase_id != 0:
		phase_left = max(0.0, phase_left - delta)
	var target = 0.0
	match phase_id:
		2:
			target = 0.3
		3:
			target = 1.0 if wave >= 5 else 0.7
	if override >= 0.0:
		target = override
	intensity = move_toward(intensity, target, 0.1 * delta)
	var pname = PHASES.get(phase_id, "calm")
	if phase_id == 3 and wave >= 5 and intensity > 0.85:
		pname = "acid_storm"
	weather_state = {"phase": pname, "intensity": intensity, "wave": wave, "phase_time_left": phase_left}
	# Puddles: local growth at 10 Hz (client-responsibilities §10).
	_puddle_left -= delta
	if _puddle_left <= 0.0:
		var dt = 0.1 - _puddle_left
		_puddle_left = 0.1
		var raining = (intensity > 0.02 and phase_id in [2, 3]) or override > 0.001
		var rate = 3.0 if _modifier(wave) == "FLOOD" else 1.0
		var walls = []
		for seq in effects:
			if effects[seq].id == "sandbag" and effects[seq].deployed:
				walls.append(effects[seq])
		for p in puddles:
			if raining:
				var cap = 1.0
				for wl in walls:
					var lo: Vector3 = (p.pos - wl.pos).rotated(Vector3.UP, -float(wl.get("yaw", 0.0)))
					if abs(lo.y) <= 0.7:
						var edge = Vector2(max(abs(lo.x) - 0.9, 0.0), max(abs(lo.z) - 0.36, 0.0)).length()
						cap = min(cap, clamp(edge / max(p.max_r, 0.01), 0.0, 1.0))
				p.growth = min(p.growth + intensity * rate * dt / max(1.0, p.grow), cap)
			else:
				p.growth = max(p.growth - dt / max(1.0, p.dry), 0.0)
			var r = p.max_r * p.growth
			if abs(r - p.shown) > 0.08 or (r <= 0.25) != (p.shown <= 0.25):
				p.shown = r
				weather.puddle({"id": p.name, "on": r > 0.25, "pos": [p.pos.x, p.floor, p.pos.z], "radius": r})


## enemies/wave_plan.gd modifier(): waves 1-5 then endless rotation.
func _modifier(w: int) -> String:
	var mods = net.data.get("weather", {}).get("wave_modifiers", ["", "BLACKOUT", "FLOOD", "SWARM", "HEAVY WEATHER"])
	var endl = net.data.get("weather", {}).get("endless_modifiers", ["HEAVY WEATHER", "FLOOD", "BLACKOUT", "SWARM"])
	if w <= mods.size():
		return str(mods[max(0, w - 1)])
	return str(endl[(w - mods.size() - 1) % endl.size()])


func _update_remote(delta: float) -> void:
	var now = OS.get_ticks_msec()
	var k = 1.0 - exp(-14.0 * delta)
	others.clear()
	for id in squad:
		if id == my_id:
			continue
		var e = squad[id]
		var age = clamp((now - int(e.t)) / 1000.0, 0.0, 0.1)
		var goal: Vector3 = e.target + e.vel * age
		if e.pos.distance_to(goal) > 4.0:
			e.pos = goal
		else:
			e.pos = e.pos.linear_interpolate(goal, k)
		var a = players.get(id)
		if a and is_instance_valid(a):
			a.translation = e.pos
			a.rotation.y = lerp_angle(a.rotation.y, e.yaw, k)
			a.pitch = e.pitch
			a.state = e.state
			a.visible = e.state != "out"
			if a.tarp:
				a.tarp.visible = e.tarp and e.state == "ok"
		others.append({"id": id, "name": e.name, "pos": e.pos, "state": e.state, "color": Weather.hex(e.get("hex", "#66dfda"), Color("#66dfda")),
			"hp": e.get("hp", 100.0), "suit": e.get("suit", 100.0), "max_hp": e.get("max_hp", 100.0), "item": e.get("item", "")})
	enemy_points.clear()
	for id in _etarget:
		var a = enemies.get(id)
		if a == null or not is_instance_valid(a):
			continue
		var tg = _etarget[id]
		var p: Vector3 = tg[0]
		if a.translation.distance_to(p) > 4.0:
			a.translation = p
		else:
			a.translation = a.translation.linear_interpolate(p, k)
		a.rotation.y = lerp_angle(a.rotation.y, float(tg[1]), k)
		if _tells.has(id):
			_tells[id] -= delta
			if _tells[id] <= 0.0:
				_tells.erase(id)
				a.set_anim("attack")
		elif a.anim != "walk":
			a.set_anim("walk")
		enemy_points.append([a.translation, a.type, a.hp])


func _update_effects(delta: float) -> void:
	for seq in effects:
		var ef = effects[seq]
		if ef.deployed:
			continue
		ef.vel.y -= 9.8 * ef.grav * delta
		ef.pos += ef.vel * delta
		if is_instance_valid(ef.node):
			ef.node.translation = ef.pos
			if ef.vel.length_squared() > 0.01:
				var up = Vector3.UP if abs(ef.vel.normalized().y) < 0.95 else Vector3.RIGHT
				ef.node.look_at(ef.pos + ef.vel, up)
	for i in range(spores.size() - 1, -1, -1):
		var s = spores[i]
		s.t += delta
		var f = clamp(s.t / s.flight, 0.0, 1.0)
		if is_instance_valid(s.node):
			s.node.translation = s.from.linear_interpolate(s.to, f) + Vector3(0, sin(f * PI) * 3.0, 0)
		if f >= 1.0:
			if is_instance_valid(s.node):
				s.node.queue_free()
			fx.spark(s.to, Color(0.55, 1.0, 0.3), 1.2)
			spores.remove(i)
	if not drop.empty():
		drop.t = max(0.0, drop.t - delta)
		if is_instance_valid(drop.node):
			drop.node.translation = drop.pos + Vector3(0, drop.t * DROP_HEIGHT, 0)
			var chute = drop.get("chute")
			if chute and is_instance_valid(chute) and drop.t <= 0.0:
				chute.rotation = Vector3(sin(_anim_time * 1.15) * 0.024, chute.rotation.y, sin(_anim_time * 0.84) * 0.032)
		if _was_airborne and drop.t <= 0.0:
			_was_airborne = false
			Sound.play_at("airdrop_land", drop.pos, -4.0)
			fx.flash(drop.pos + Vector3(0, 0.25, 0), 1.9, Color(0.67, 0.50, 0.35), 0.5)
		ffx.beacon(drop.pos, drop.t > 0.0)
	_update_offers()
	for i in range(_thunder.size() - 1, -1, -1):
		_thunder[i][0] -= delta
		if _thunder[i][0] <= 0.0:
			Sound.play("thunder", float(_thunder[i][1]))
			_thunder.remove(i)
	ffx.tick(delta, fx)
	for id in loot:
		var n = loot[id].node
		if is_instance_valid(n) and n.get_meta("spin"):
			n.rotation.y = _anim_time * 1.6 + float(id % 10)
			n.get_child(0).translation.y = 0.25 + sin(_anim_time * 2.0 + float(id % 7)) * 0.06


# ------------------------------------------------------------------ input
func _full_input() -> Dictionary:
	var lk = Controls.take_look()
	var blocked = input_blocked
	if lk != Vector2.ZERO and not blocked:
		var k = 0.6 if _aiming() else 1.0
		yaw = wrapf(yaw - lk.x * k, -PI, PI)
		pitch = clamp(pitch + lk.y * k, -MAX_PITCH, MAX_PITCH)
	var mv = Vector2.ZERO if blocked else Controls.move_vector()
	mv += Vector2(auto_move.x, -auto_move.y)
	var bits = auto_bits | _latched_bits
	_latched_bits = 0
	var edge = bits & ~_prev_bits
	_prev_bits = bits
	var inp = {"move": mv.limit_length(1.0)}
	for a in ["fire", "aim", "jump", "crouch", "sprint", "reload", "interact"]:
		inp[a] = (Controls.held(a) and not blocked) or (bits & BITS[a]) != 0
		inp[a + "_p"] = (Controls.pressed(a) and not blocked) or (edge & BITS[a]) != 0
	var ok = not blocked
	inp["tarp_p"] = ok and Controls.pressed("tarp") or (edge & BITS.use_item) != 0
	inp["ping_p"] = ok and Controls.pressed("ping") or (edge & BITS.ping) != 0
	inp["ready_p"] = ok and Controls.pressed("ready_up") or (edge & BITS.ready_up) != 0
	inp["frag_p"] = ok and Controls.pressed("throw_grenade") or (edge & BITS.throw_grenade) != 0
	inp["dome_p"] = ok and Controls.pressed("throw_dome") or (edge & BITS.throw_dome) != 0
	inp["drop_p"] = ok and Controls.pressed("drop_item") or (edge & BITS.drop_item) != 0
	var slot = -1
	if ok and not draft_active:
		for i in 5:
			if Controls.pressed("slot_%d" % (i + 1)):
				slot = i
	if _slot_frames > 0:
		slot = _slot_pulse - 1
		_slot_frames = 0
	if ok and (Controls.pressed("next_weapon") or _wheel > 0):
		slot = _cycle_slot(1)
	elif ok and (Controls.pressed("prev_weapon") or _wheel < 0):
		slot = _cycle_slot(-1)
	_wheel = 0
	inp["slot"] = slot
	if ok:
		for i in 3:
			if Controls.pressed("draft_%d" % (i + 1)):
				inp["draft"] = i
	return inp


func _aiming() -> bool:
	return my_state == "ok" and ((Controls.held("aim") and not input_blocked) or (auto_bits & BITS.aim) != 0)


func _cycle_slot(d: int) -> int:
	var cur = int(inv.slot)
	for i in range(1, 6):
		var s = posmod(cur + d * i, 5)
		var row = inv.rows[s] if s < inv.rows.size() else []
		if row is Array and row.size() >= 4:
			return s
	return -1


func held_row() -> Array:
	var s = int(inv.slot)
	if s >= 0 and s < inv.rows.size() and inv.rows[s] is Array and inv.rows[s].size() >= 4:
		return inv.rows[s]
	return []


func _eye() -> Vector3:
	return camera.global_transform.origin


func _view_dir() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


# ------------------------------------------------------------------ local sim
func _local_sim(delta: float, inp: Dictionary) -> void:
	var aiming = _aiming()
	inp["aiming"] = aiming
	me.step(delta, {"move": inp.move if my_state != "out" else Vector2.ZERO, "jump": inp.jump_p, "crouch": inp.crouch,
		"sprint": inp.sprint, "aiming": aiming, "tarp": tarp_up, "state": my_state, "yaw": yaw})
	_update_exposure()
	if net.run_ready:
		_push_left -= delta
		if _push_left <= 0.0 and my_state != "out":
			_push_left += PUSH_DT
			if _push_left < 0.0:
				_push_left = PUSH_DT
			net.rpc_send(net.me_path(), "_push_transform", [me.feet(), yaw, pitch, me.vel], false)
		_starter(delta)
		_combat(delta, inp)
		_interact(delta, inp)
		_misc_actions(inp)
	inv.reload_left = max(0.0, float(inv.reload_left) - delta)
	inv.jam_left = max(0.0, float(inv.jam_left) - delta)


func _starter(delta: float) -> void:
	if starter_state == 2 or run_id == 0:
		return
	_starter_left -= delta
	if _starter_left > 0.0:
		return
	var empty = true
	for r in inv.rows:
		if r is Array and r.size() >= 4:
			empty = false
	if not empty and starter_state == 1:
		starter_state = 2
		return
	if my_state == "ok" and not draft_active and not tape_open:
		var idx = clamp(Settings.starter_index, 0, 2)
		net.rpc_send("Main/RunLoot", "_request_starter", [run_id, idx])
		print("FULL request_starter run=%d index=%d" % [run_id, idx])
		starter_state = 1
	_starter_left = 3.0


func _update_exposure() -> void:
	var feet = me.feet()
	var eye = feet + Vector3(0, me.eye_height(), 0)
	var roof = not space.intersect_ray(feet + Vector3(0, 1.0, 0), feet + Vector3(0, 41.0, 0), [me], 1).empty()
	var shel = roof
	if not shel and not (lp_info.get("shelters", []) as Array).empty():
		shel = not space.intersect_point(eye, 1, [], 8, false, true).empty()
	if not shel:
		for s in shelters:
			var d: Vector3 = eye - s.pos
			if s.shape == "cylinder":
				if abs(d.y) <= s.height * 0.5 and d.x * d.x + d.z * d.z <= s.radius * s.radius:
					shel = true
					break
			else:
				var l = d.rotated(Vector3.UP, -s.yaw)
				if abs(l.x) <= s.size.x * 0.5 and abs(l.y) <= s.size.y * 0.5 and abs(l.z) <= s.size.z * 0.5:
					shel = true
					break
	if not shel:
		for id in squad:
			var e = squad[id]
			var tp = e.pos if id != my_id else feet
			if (e.tarp if id != my_id else tarp_up) and (e.state if id != my_id else my_state) == "ok":
				var d2: Vector3 = eye - tp
				if d2.y >= 0.0 and d2.y <= 2.6 and d2.x * d2.x + d2.z * d2.z <= 4.0:
					shel = true
					break
	var pud = false
	var fp = feet + Vector3(0, 0.05, 0)
	for p in puddles:
		var r = p.max_r * p.growth
		if r > 0.25:
			var d3: Vector3 = fp - p.pos
			if abs(d3.y) <= 0.2 and d3.x * d3.x + d3.z * d3.z <= r * r:
				pud = true
				break
	if shel != sheltered or pud != in_puddle:
		sheltered = shel
		in_puddle = pud
		_exposure_sent = false
		if pud and (intensity > 0.02):
			Sound.play("splash_0", -11.0, 0.75)
	_send_exposure()


func _send_exposure() -> void:
	if _exposure_sent or not net.run_ready:
		return
	if net.rpc_send(net.me_path(), "_report_exposure", [sheltered, in_puddle]):
		_exposure_sent = true
		print("FULL report_exposure sheltered=%s puddle=%s" % [str(sheltered), str(in_puddle)])


func _hold_send(action: String, expected: int, slot: int) -> void:
	net.rpc_send(net.holder_path(), "_action", [run_id, action, expected, slot])


func _combat(delta: float, inp: Dictionary) -> void:
	_fire_left = max(0.0, _fire_left - delta)
	_throw_left = max(0.0, _throw_left - delta)
	_melee_left = max(0.0, _melee_left - delta)
	if my_state == "turned":
		if inp.fire_p and _melee_left <= 0.0:
			_melee_left = 0.9
			net.rpc_send(net.me_path(), "_request_melee", [])
		return
	if my_state != "ok" or draft_active or tape_open:
		_charge_left = -1.0
		return
	var row = held_row()
	var serial = int(row[0]) if not row.empty() else 0
	# Slot selection.
	if inp.slot >= 0 and (inp.slot != int(inv.slot) or not str(inv.pouch).empty()):
		_hold_send("select", serial, inp.slot)
		inv.slot = inp.slot
		inv.pouch = ""
		Sound.play("ui_tick", -10.0)
		_you_dirty = true
		return
	# Quick pouch throws (Thin-style frag / dome buttons).
	if (inp.frag_p or inp.dome_p) and _throw_left <= 0.0 and not tarp_up:
		var pid = "frag" if inp.frag_p else "shield_dome"
		var have = int(inv.frags) if pid == "frag" else int(inv.domes)
		if have > 0:
			_hold_send("select_pouch", 0, 0 if pid == "frag" else 1)
			net.rpc_send(net.holder_path(), "_request_throw", [run_id, pid, _eye(), _view_dir()])
			_hold_send("select", serial, int(inv.slot))
			_throw_left = 0.35
			viewmodel.fire()
			Sound.play("gun_frag_throw" if pid == "frag" else "gun_dome_throw")
			if pid == "frag":
				inv.frags = have - 1
			else:
				inv.domes = have - 1
		return
	if inp.drop_p and serial != 0:
		_hold_send("drop", serial, -1)
		return
	# Selected pouch: fire throws it.
	if not str(inv.pouch).empty():
		if inp.fire_p and _throw_left <= 0.0 and not tarp_up and not me.sprinting:
			net.rpc_send(net.holder_path(), "_request_throw", [run_id, str(inv.pouch), _eye(), _view_dir()])
			_throw_left = 0.35
			viewmodel.fire()
			Sound.play("gun_frag_throw" if inv.pouch == "frag" else "gun_dome_throw")
		return
	if row.empty():
		return
	var id = str(row[1])
	var it = net.item(id)
	var w: Dictionary = it.get("weapon", {}) if it.get("weapon") is Dictionary else {}
	var is_gun = str(it.get("kind", "")) == "gun"
	var count = int(row[3])
	var mag = int(w.get("mag_size", 1))
	var reserve = int(inv.stash.get(str(it.get("ammo_type", "")), 0))
	if inp.reload_p and is_gun and count < mag and reserve > 0 and float(inv.reload_left) <= 0.0:
		_hold_send("reload", serial, -1)
		inv.reload_left = float(w.get("reload_time", 1.0))
		inv.reload_total = inv.reload_left
		Sound.play("reload", -6.0)
		return
	var interval = float(w.get("fire_interval", 0.3)) * (0.8 if "reflex_tendons" in player_mutations else 1.0)
	var shell = bool(w.get("shell_reload", false))
	var blocked = tarp_up or me.sprinting or float(inv.jam_left) > 0.0 or (float(inv.reload_left) > 0.0 and not shell)
	var want = inp.fire if (is_gun and bool(w.get("automatic", false))) else inp.fire_p
	var charge = float(w.get("charge_time", 0.0))
	if charge > 0.0:
		if inp.fire_p and not blocked and _fire_left <= 0.0 and count > 0:
			_hold_send("charge", serial, -1)
			_charge_left = charge
			Sound.play("gun_disruptor_charge", -4.0)
		if _charge_left >= 0.0:
			if not inp.fire:
				_charge_left = -1.0
			else:
				_charge_left -= delta
				if _charge_left <= 0.0:
					_charge_left = -1.0
					_shoot(serial, id, w, is_gun, interval)
		return
	if want and not blocked and _fire_left <= 0.0:
		if is_gun and count <= 0:
			if inp.fire_p and reserve > 0 and float(inv.reload_left) <= 0.0:
				_hold_send("reload", serial, -1)
				inv.reload_left = float(w.get("reload_time", 1.0))
				inv.reload_total = inv.reload_left
			elif inp.fire_p:
				Sound.play("ui_tick", -6.0)
			return
		_shoot(serial, id, w, is_gun, interval)


func _shoot(serial: int, id: String, w: Dictionary, is_gun: bool, interval: float) -> void:
	_fire_left = interval
	var eye = _eye()
	net.rpc_send(net.holder_path(), "_request_shot", [run_id, serial, eye, _view_dir(), _aiming(), true])
	predicted_shots += 1
	viewmodel.fire()
	var muzzle = viewmodel.muzzle_position()
	if not (str(w.get("mechanic", "")) in STREAMS):
		fx.flash(muzzle, 0.35, viewmodel.tracer_color().lightened(0.3))
	var cue = str(Assets.weapon(id).get("shot_sound", w.get("shot_sound", "")))
	if not cue.empty():
		Sound.play(cue, -2.5)
	_shot_juice(id, w)
	var row = held_row()
	if is_gun and not row.empty():
		row[3] = max(0, int(row[3]) - 1)
		_you_dirty = true


func _misc_actions(inp: Dictionary) -> void:
	if inp.tarp_p and has_tarp and my_state == "ok" and not draft_active:
		net.rpc_send(net.me_path(), "_push_tarp", [not tarp_up])
	if inp.ready_p and my_state == "ok" and phase_id in [0, 4] and phase_left > 3.0:
		net.rpc_send("GameManager", "_request_ready", [])
		Sound.play("ui_click", -8.0)
	if inp.has("draft") and draft_active:
		net.choose("mutation", int(inp.draft))
	elif inp.has("draft") and tape_open and net.first_peer == my_id:
		net.choose("tape", int(inp.draft))
	_ping_left = max(0.0, _ping_left - get_process_delta_time())
	if inp.ping_p and _ping_left <= 0.0:
		_ping_left = 0.3
		_send_ping()


func _send_ping() -> void:
	var eye = _eye()
	var dir = _view_dir()
	var kind = "revive" if my_state == "downed" else "go"
	var enemy_id = 0
	var best = 0.97
	for id in enemies:
		var a = enemies[id]
		if is_instance_valid(a) and not a.dying:
			var to: Vector3 = a.translation + Vector3(0, 1.0, 0) - eye
			var dist = to.length()
			if dist < 120.0 and dist > 0.5:
				var dot = dir.dot(to / dist)
				if dot > best:
					best = dot
					enemy_id = int(id)
	var pos = eye + dir * 60.0
	var hit = space.intersect_ray(eye, eye + dir * 120.0, [me], 1)
	if not hit.empty():
		pos = hit.position
	if enemy_id != 0 and kind != "revive":
		kind = "enemy"
		pos = enemies[enemy_id].translation
	net.rpc_send("Main/Pings", "_request_ping", [kind, pos, enemy_id])


# ------------------------------------------------------------------ interact
func _interact(delta: float, inp: Dictionary) -> void:
	var cand = _best_interact()
	var key = cand.get("key", "")
	if key != _hold_key:
		if _hold_begun and not _hold_done and _hold_key.begins_with("bay:"):
			_vend_step(_hold_key, "cancel")
		_hold_key = key
		_hold_t = 0.0
		_hold_begun = false
		_hold_done = false
	prompt = str(cand.get("text", ""))
	hold_progress = 0.0
	if key.empty():
		return
	var need = float(cand.get("hold", 0.0))
	if inp.interact and not _hold_done:
		if not _hold_begun:
			_hold_begun = true
			if key.begins_with("bay:"):
				_vend_step(key, "begin")
		_hold_t += delta
		hold_progress = clamp(_hold_t / max(0.01, need), 0.0, 1.0) if need > 0.0 else 1.0
		if _hold_t >= need:
			_hold_done = true
			_finish_interact(cand)
	elif not inp.interact:
		if _hold_begun and not _hold_done and key.begins_with("bay:"):
			_vend_step(key, "cancel")
		_hold_t = 0.0
		_hold_begun = false
		_hold_done = false


func _best_interact() -> Dictionary:
	if not (my_state in ["ok", "downed"]) or draft_active or tape_open:
		return {}
	var feet = me.feet()
	var eye = _eye()
	var fwd = _view_dir()
	var holding = _hold_t > 0.0
	var best = {}
	var best_score = INF
	if my_state == "downed":
		if net.roster_ids.size() <= 1 and _self_revive_wave != wave:
			return {"key": "self", "text": "SELF REVIVE", "hold": 3.0, "path": "/root/Main/Players/P_%d/ReviveSpot" % my_id}
		return {}
	for id in squad:
		var e = squad[id]
		if id != my_id and e.state == "downed":
			var d = feet.distance_to(e.pos)
			if d <= 2.2 + (0.6 if holding and _hold_key == "rev:%d" % id else 0.0) and d < best_score:
				best_score = d
				best = {"key": "rev:%d" % id, "text": "REVIVE " + str(e.name).to_upper(), "hold": 3.0,
					"path": "/root/Main/Players/P_%d/ReviveSpot" % id}
	if not best.empty():
		return best
	for dc in decons:
		var d2 = feet.distance_to(dc.pos - Vector3(0, 1.0, 0))
		var k = "decon:" + dc.name
		if d2 > dc.radius + (0.6 if _hold_key == k else 0.0):
			continue
		if not (_hold_key == k and holding) and not _in_view(eye, fwd, dc.pos, d2):
			continue
		var text = "REPAIR SUIT" if vit.suit < 99.0 and decon_charges > 0 else ("SUIT FULL" if decon_charges > 0 else "NO DECON CHARGES")
		var score = d2 - fwd.dot((dc.pos - eye).normalized())
		if score < best_score:
			best_score = score
			best = {"key": k if text == "REPAIR SUIT" else "", "text": text, "hold": 1.0, "path": dc.path}
	for id in loot:
		var l = loot[id]
		if not l.flavor.empty() or (int(l.claim) != 0 and int(l.claim) != my_id):
			continue
		var target: Vector3 = l.pos + Vector3(0, 0.28, 0)
		var d3 = feet.distance_to(l.pos)
		if d3 > 2.55 or not _in_view(eye, fwd, target, d3):
			continue
		var score2 = d3 - fwd.dot((target - eye).normalized())
		if score2 < best_score:
			best_score = score2
			var nm = str(net.item(l.id_s).get("name", l.id_s.replace("_", " ")))
			best = {"key": "loot:%d" % id, "text": "PICK UP " + nm.to_upper(), "hold": 0.0, "loot": id}
	for key in cabinets:
		var c = cabinets[key]
		if feet.distance_to(c.pos) > 4.5:
			continue
		var basis = Basis(Vector3.UP, c.yaw)
		var i = 0
		for mode in ["offer_1", "offer_2", "offer_3", "ammo"]:
			var pad: Vector3 = c.pos + basis.xform(BAYS[mode])
			var dp = feet.distance_to(Vector3(pad.x, feet.y, pad.z))
			if dp > 2.8:
				i += 1
				continue
			var al = fwd.dot((pad - eye).normalized())
			var kb = "bay:%s:%s" % [key, mode]
			if al < 0.6 and not (_hold_key == kb and holding):
				i += 1
				continue
			var score3 = dp * 0.2 - al + (1.0 - al) * 5.0
			if score3 < best_score:
				var text3 = "AMMO REFILL"
				var serial = 0
				if mode != "ammo":
					var off = c.offers[i] if i < c.offers.size() else null
					if not (off is Array) or off.size() < 4 or str(off[0]).empty():
						i += 1
						continue
					serial = int(off[3])
					var nm2 = str(net.item(str(off[0])).get("name", str(off[0]))).to_upper()
					text3 = "BUY %s  ·  %d SCRAP" % [nm2, int(off[2])]
				best_score = score3
				best = {"key": kb, "text": text3, "hold": 0.6, "cab": key, "mode": mode, "serial": serial}
			i += 1
	if not drop.empty() and drop.t <= 0.0:
		var dd = feet.distance_to(drop.pos)
		if dd <= 2.8 and dd < best_score + 1.0:
			best = {"key": "bay:Airdrop:airdrop", "text": "OPEN AIRDROP", "hold": 0.6, "cab": "Airdrop", "mode": "airdrop", "serial": 0}
	return best


func _in_view(eye: Vector3, fwd: Vector3, target: Vector3, dist: float) -> bool:
	var to = target - eye
	if to.length() < 0.01:
		return true
	var cone = lerp(0.25, 0.65, clamp((dist - 0.6) / 1.4, 0.0, 1.0))
	if fwd.dot(to.normalized()) < cone:
		return false
	var hit = space.intersect_ray(eye, target, [me], 1)
	return hit.empty() or hit.position.distance_to(target) < 0.5


func _vend_step(key: String, step: String) -> void:
	var parts = key.split(":")
	if parts.size() < 3:
		return
	var serial = 0
	var c = cabinets.get(parts[1])
	if c and parts[2].begins_with("offer_"):
		var i = int(parts[2].substr(6)) - 1
		if i >= 0 and i < c.offers.size() and c.offers[i] is Array and c.offers[i].size() >= 4:
			serial = int(c.offers[i][3])
	net.rpc_send("GameManager/CrateManager", "_hold_request", [run_id, parts[1], parts[2], step, serial])


func _finish_interact(cand: Dictionary) -> void:
	var key: String = cand.key
	print("FULL interact %s" % key)
	if key.begins_with("bay:"):
		_vend_step(key, "finish")
	elif key.begins_with("loot:"):
		var row = held_row()
		net.rpc_send("Main/RunLoot", "_claim", [run_id, int(cand.loot), int(row[0]) if not row.empty() else 0, int(inv.slot)])
	elif cand.has("path"):
		if key == "self":
			_self_revive_wave = wave
		net.rpc_send("GameManager", "_request_interact", [NodePath(str(cand.path))])
		if key.begins_with("decon:"):
			Sound.play("decon", -6.0)


# ------------------------------------------------------------------ camera + HUD state
func _full_camera(delta: float, inp: Dictionary) -> void:
	var feet = me.feet()
	var origin = feet + Vector3(0, me.eye_height(), 0)
	_kick = move_toward(_kick, 0.0, delta * deg2rad(8.0))
	var basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch + _kick)
	if _my_tarp:
		_my_tarp.visible = tarp_up and my_state == "ok"
	if my_state == "out":
		var target = _spectate_target(inp.get("fire_p", false) or inp.get("jump_p", false))
		if not target.empty():
			var look = Basis(Vector3.UP, yaw)
			origin = target.pos + Vector3(0, 2.6, 0) + look.z * 4.0
			basis = look * Basis(Vector3.RIGHT, -0.3)
			prompt = "SPECTATING " + str(target.name).to_upper()
	shake = max(0.0, shake - delta * 3.0)
	if shake > 0.0 and not Settings.reduced_flash:
		origin += Vector3(rand_range(-1, 1), rand_range(-1, 1), 0) * shake * 0.03
	camera.global_transform = Transform(basis, origin)
	var row = held_row()
	var id = str(row[1]) if not row.empty() else ""
	if not str(inv.pouch).empty():
		id = str(inv.pouch)
	var meta = Assets.weapon(id)
	var aiming = _aiming()
	var hv = Vector2(me.vel.x, me.vel.z).length()
	var want = HIP_FOV + (6.0 if me.sprinting and hv > 5.5 else 0.0)
	if aiming and meta.get("ads_fov") != null:
		want = float(meta.ads_fov)
	_fov = lerp(_fov, want, 1.0 - exp(-12.0 * delta))
	camera.fov = _fov
	viewmodel.visible = my_state == "ok" and not id.empty()
	viewmodel.set_item(id if not id.empty() else null)
	viewmodel.aim = lerp(viewmodel.aim, 1.0 if aiming else 0.0, 1.0 - exp(-14.0 * delta))
	viewmodel.reloading = float(inv.reload_left) > 0.0
	viewmodel.speed = hv
	if ready_to_play:
		var want_capture = Controls.device == "kbm" and not input_blocked and OS.is_window_focused() and not net.finished
		if want_capture != (Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED):
			Controls.capture_mouse(want_capture)


## Out: follow a living teammate; fire / jump cycles to the next one.
func _spectate_target(next: bool) -> Dictionary:
	var alive = []
	for o in others:
		if o.state in ["ok", "downed"]:
			alive.append(o)
	if alive.empty():
		spectate_id = 0
		return {}
	var idx = 0
	for i in alive.size():
		if alive[i].id == spectate_id:
			idx = i
	if next:
		idx = (idx + 1) % alive.size()
		Sound.play("ui_tick", -8.0)
	spectate_id = alive[idx].id
	return alive[idx]


func current_slot() -> Dictionary:
	var s = int(you.get("slot", 1)) - 1
	var slots = you.get("slots", [])
	if s >= 0 and s < slots.size() and slots[s] is Dictionary:
		return slots[s]
	return {}


static func _v(a) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func _build_hud_state(inp: Dictionary) -> void:
	var f = me.feet()
	you["pos"] = [f.x, f.y, f.z]
	you["vel"] = [me.vel.x, me.vel.y, me.vel.z]
	you["yaw"] = yaw
	you["pitch"] = pitch
	you["state"] = my_state
	you["hp"] = vit.hp
	you["hp_max"] = vit.max_hp
	you["suit"] = vit.suit
	you["sheltered"] = sheltered
	you["in_puddle"] = in_puddle
	you["exposed"] = not sheltered or in_puddle
	you["crouch"] = me.crouching
	you["aiming"] = _aiming()
	you["reloading"] = float(inv.reload_left) > 0.0
	you["prompt"] = prompt
	you["interact_progress"] = hold_progress
	you["revive"] = hold_progress if _hold_key.begins_with("rev:") else 0.0
	you["scrap"] = int(inv.scrap)
	you["pouch"] = str(inv.pouch)
	you["grenades"] = int(inv.frags)
	you["domes"] = int(inv.domes)
	you["slot"] = int(inv.slot) + 1
	you["tarp"] = tarp_up
	you["has_tarp"] = has_tarp
	if _you_dirty or Engine.get_frames_drawn() % 6 == 0:
		_you_dirty = false
		var slots = []
		for i in 5:
			var row = inv.rows[i] if i < inv.rows.size() else []
			if not (row is Array) or row.size() < 4:
				slots.append(null)
				continue
			var id = str(row[1])
			var it = net.item(id)
			var d = {"item": id, "name": str(it.get("name", id)), "tier": int(row[2]), "count": int(row[3]), "serial": int(row[0])}
			if str(it.get("kind", "")) == "gun":
				var w = it.get("weapon", {})
				d["ammo"] = int(row[3])
				d["count"] = 1
				d["mag"] = int(w.get("mag_size", 1)) if w is Dictionary else 1
				d["reserve"] = int(inv.stash.get(str(it.get("ammo_type", "")), 0))
			slots.append(d)
		you["slots"] = slots
	run["alive_enemies"] = int(progress.left)
	run["wave"] = wave
	run["endless"] = endless
	run["score"] = int(progress.score)
