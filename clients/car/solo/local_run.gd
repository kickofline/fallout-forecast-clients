extends Reference

const Arena = preload("res://solo/arena.gd")
const Loot = preload("res://solo/loot.gd")

const GAME = "GameManager"
const WEATHER = "WeatherManager"
const MUTATION = "GameManager/MutationRoll"
const CRATES = "GameManager/CrateManager"
const LOOT = "Main/RunLoot"
const ENEMIES = "Main/Enemies"
const BOSS = "Main/Enemies/BossCumulus"
const PINGS = "Main/Pings"
const CALM = 0
const DRIZZLE = 2
const DOWNPOUR = 3
const CLEARING = 4

const COUNTERS = {
	"BLACKOUT": ["reflex_tendons", "chitin_suit", "adrenaline_glands"],
	"FLOOD": ["hydro_skin", "adrenaline_glands", "chitin_suit"],
	"SWARM": ["bone_piercer", "reflex_tendons", "vampiric_siphon"],
	"HEAVY WEATHER": ["chitin_suit", "voltaic_veins", "adrenaline_glands"]
}
const FORECAST_MUTATIONS = {"FLOOD": "undertow", "SWARM": "swarm", "HEAVY WEATHER": "conductors"}

var id: int
var map_id: String
var peer: int
var player_name: String
var player_path: String
var holder_path: String
var data: Dictionary
var markers: Dictionary
var rng: RandomNumberGenerator
var alive_cap: int
var level: Spatial
var navigation: Navigation
var space: PhysicsDirectSpaceState
var arena
var loot
var clock = 0.0
var paused = false
var finished = false

var pos = Vector3.ZERO
var vel = Vector3.ZERO
var yaw = 0.0
var pitch = 0.0
var hp = 100.0
var max_hp = 100.0
var suit = 100.0
var state = "ok"
var bleed = 0.0
var grace = 0.0
var revive_grace = 0.0
var self_revives = 1
var sheltered = false
var in_puddle = false
var has_tarp = false
var tarp = false
var decon = 4
var kills = 0
var cursed = 0
var weapon_name = ""

var phase = CALM
var wave = 1
var time_left = 12.0
var intensity = 0.0
var override = -1.0
var forecast = ""
var waves_cleared = 0
var endless = false
var score = 0
var tape = false
var locked = false
var puddles = {}
var player_mutations = []
var enemy_mutations = []

var _out = []
var _weather: Dictionary
var _lightning_at = INF
var _puddle_tick = 0.0
var _vitals_at = 0.0
var _last_ping = -1.0
var _tape_at = INF
var _draft = ""
var _draft_at = INF
var _draft_cards = []
var _draft_enemy = ""
var _draft_vote = -1
var _rain_warning = 0.8
var _rain_seen = false
var _acid_blood_at = 0.0
var _dry_wave = true
var _dragged_wave = false
var _wave_kills = 0
var _feats = {}
var _used_decon = false
var _took_acid = false


func _init(run_id: int, map: String, owner: int, callsign: String, catalog: Dictionary,
		level_markers: Dictionary, random: RandomNumberGenerator, cap: int) -> void:
	id = run_id
	map_id = map
	peer = owner
	player_name = callsign
	player_path = "Main/Players/P_%d" % peer
	holder_path = player_path + "/Head/Camera3D/WeaponHolder"
	data = catalog
	markers = level_markers.duplicate(true)
	for key in markers:
		if typeof(markers[key]) != TYPE_ARRAY:
			continue
		for marker in markers[key]:
			if marker.has("pos"):
				marker.pos = _vector(marker.pos)
			if marker.has("interact_pos"):
				marker.interact_pos = _vector(marker.interact_pos)
	_weather = data.weather
	time_left = _weather.first_calm_duration
	pos = markers.player_spawn[0].pos
	yaw = markers.player_spawn[0].yaw
	rng = random
	alive_cap = cap
	for marker in markers.puddles:
		puddles[NodePath(marker.sync_key)] = 0.0
	arena = Arena.new()
	arena.setup(self)
	loot = Loot.new()
	loot.setup(self)


func attach(root: Spatial) -> void:
	level = root
	navigation = level.get_node_or_null("LevelNavigation") as Navigation


func detach() -> void:
	loot.detach()
	space = null
	level = null
	navigation = null


func attached() -> bool:
	return is_instance_valid(level) and level.is_inside_tree()


func catch_up() -> void:
	# The ordering is the server's Ã‚Â§5 catch-up burst. No run RPCs precede it.
	rpc(GAME, "_sync_tape_state", [tape, endless, locked])
	rpc(WEATHER, "_receive_phase", [phase, wave, time_left])
	rpc(WEATHER, "_receive_intensity", [intensity])
	rpc(WEATHER, "_override", [override])
	rpc(GAME, "_sync_decon", [decon])
	rpc(MUTATION, "_sync_active", [enemy_mutations.duplicate(), player_mutations.duplicate()])
	if _draft == "voting":
		rpc(MUTATION, "_deal_rpc", [_draft_enemy, _draft_cards.duplicate()])
	loot.crate_snapshot(self)
	arena.catch_up(self)
	rpc(WEATHER, "_sync_puddles", [puddles.duplicate()])
	loot.snapshot(self)
	loot.send_state(self, true, false)
	rpc("Net", "_confirm_run_ready", [])


func take_messages() -> Array:
	var messages = _out
	_out = []
	return messages


func rpc(node: String, method: String, args: Array, reliable = true) -> void:
	_out.append({"t": "rpc", "node": node, "method": method, "args": args, "ch": 0, "rel": reliable})


func node_pattern(node: String) -> String:
	if node == player_path:
		return "Main/Players/P_<peer_id>"
	if node == holder_path:
		return "Main/Players/P_<peer_id>/Head/Camera3D/WeaponHolder"
	if node == BOSS:
		return BOSS if arena.boss_alive() else ""
	if node.begins_with("Main/Level/DeconShowers/"):
		for marker in markers.decon_showers:
			if node == marker.interact_path:
				return "Main/Level/DeconShowers/<decon_marker>/Interact"
		return ""
	if node in [GAME, WEATHER, MUTATION, CRATES, LOOT, ENEMIES, PINGS, "GameManager/Feats"]:
		return node
	return ""


func request(node: String, method: String, args: Array) -> void:
	if finished or not attached():
		return
	# A poll can process requests before its first simulation step.
	space = level.get_world().direct_space_state
	if node == player_path:
		_player_request(method, args)
		return
	if node == holder_path or node == LOOT or node == CRATES:
		if can_act() and args.size() > 0 and args[0] == id:
			loot.request(self, method, args)
		return
	match node:
		GAME:
			_game_request(method, args)
		MUTATION:
			if not paused and method == "_request_vote" and _draft == "voting" and not _draft_cards.empty():
				_draft_vote = int(clamp(args[0], 0, _draft_cards.size() - 1))
				var counts = [0, 0, 0]
				counts[_draft_vote] = 1
				rpc(MUTATION, "_votes_rpc", [counts])
				_resolve_draft()
		PINGS:
			if method == "_request_ping" and not paused and clock - _last_ping >= 0.6 \
					and (args[0] != "revive" or state == "downed") and args[0] in ["enemy", "go", "revive", "shelter", "danger", "crate", "decon", "ammo", "health", "suit", "supply", "ammo_box", "tarp"] \
					and pos.distance_squared_to(args[1]) < 120.0 * 120.0:
				_last_ping = clock
				rpc(PINGS, "_show_ping", [peer, args[0], args[1], int(args[2])])


func step(dt: float) -> void:
	if paused or finished or not attached() or dt <= 0.0:
		return
	space = level.get_world().direct_space_state
	clock += dt
	if _draft != "" and clock >= _draft_at:
		if _draft == "voting":
			_resolve_draft()
		else:
			_draft = ""
	if clock >= _tape_at:
		_tape_at = INF
		tape = true
		rpc(GAME, "_sync_tape_state", [tape, endless, locked])
	_tick_weather(dt)
	_tick_player(dt)
	if finished:
		return
	loot.step(self, dt)
	arena.step(self, dt)
	if clock >= _vitals_at and not finished:
		send_vitals()


func can_act() -> bool:
	return state == "ok" and not paused and _draft != "voting" and not locked and not finished


func eye() -> Vector3:
	return pos + Vector3.UP * (0.55 if state == "downed" else 1.65)


func direction() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func ray(a: Vector3, b: Vector3) -> Dictionary:
	if space == null or a.distance_squared_to(b) < 0.000001:
		return {}
	return space.intersect_ray(a, b, [], 1, true, false)


func clear_path(a: Vector3, b: Vector3) -> bool:
	return ray(a, b).empty()


func ground(at: Vector3, above = 1.4, below = 5.0) -> Vector3:
	var hit = ray(at + Vector3.UP * above, at - Vector3.UP * below)
	return hit.position + Vector3.UP * 0.04 if not hit.empty() else at


func enemy_buff() -> float:
	if intensity >= 0.999:
		return 1.5
	if intensity >= 0.699:
		return 1.3
	return 1.0


func raining() -> bool:
	return intensity > 0.02 and (override > 0.001 if override >= 0.0 else phase in [DRIZZLE, DOWNPOUR])


func send_vitals() -> void:
	_vitals_at = clock + 0.1
	rpc(player_path, "_apply_vitals", [hp, suit, state, max(bleed, 0.0), tarp, max_hp, 0.0, grace > 0.0], false)


func damage(amount: float, at: Vector3, continuous = false) -> void:
	if amount <= 0.0 or state != "ok" or grace > 0.0 or finished or locked:
		return
	hp = max(0.0, hp - amount)
	if at != Vector3.INF and amount >= 1.0:
		rpc(player_path, "_receive_hurt_from", [at], false)
	if not continuous and hp > 0.0:
		grace = 0.65
		if player_mutations.has("acid_blood") and amount >= 2.0 and clock >= _acid_blood_at:
			_acid_blood_at = clock + 1.5
			arena.blast(self, pos, 4.0, 28.0, 5.0, false)
			rpc(GAME, "_draw_blast", [pos + Vector3.UP * 0.9, 1.4, Color("#9eff40")], false)
	if hp == 0.0:
		state = "downed"
		bleed = data.player.bleed_out_time
		tarp = false
		send_vitals()
		if self_revives <= 0:
			_go_out()


func heal(amount: float) -> void:
	if state == "ok":
		hp = min(hp + amount, max_hp)


func record_kill(elite: bool, at: Vector3) -> void:
	kills += 1
	_wave_kills += 1
	if kills == 100:
		feat("sweeps_week")
	if endless:
		score += 250 if elite else 100
	if player_mutations.has("vampiric_siphon"):
		heal(5.0)
		suit = min(100.0, suit + 6.0)
	if player_mutations.has("blast_glands") and rng.randf() < 0.25:
		arena.queue_pop(at)


func feat(key: String) -> void:
	if not _feats.has(key):
		_feats[key] = true
		rpc("GameManager/Feats", "_feat_event", [key, 1])


func mark_dragged() -> void:
	_dragged_wave = true


func boss_defeated() -> void:
	waves_cleared = int(_weather.final_wave)
	locked = true
	_tape_at = clock + 2.6
	feat("silver_lining")
	var map_feats = {"pinecrest": "main_street", "harbor": "low_tide", "maple_hollow": "sunday_service"}
	if map_feats.has(map_id):
		feat(map_feats[map_id])
	if not _took_acid:
		feat("clean_bill")
	if not _used_decon:
		feat("dry_cleaning")
	rpc(GAME, "_sync_tape_state", [false, endless, locked])
	set_override(0.0)
	rpc(GAME, "_banner", ["STORM CLEARED", Color("#66ff99"), 2.5])
	arena.retire(self)


func set_override(value: float) -> void:
	override = value
	rpc(WEATHER, "_override", [value])


func dry_puddles(at: Vector3, radius: float) -> void:
	var changed = false
	for marker in markers.puddles:
		if marker.pos.distance_squared_to(at) <= radius * radius:
			puddles[NodePath(marker.sync_key)] = 0.0
			changed = true
	if changed:
		rpc(WEATHER, "_sync_puddles", [puddles.duplicate()])


func _game_request(method: String, args: Array) -> void:
	if method == "_request_pause_rpc":
		paused = args[0]
		rpc(GAME, "_sync_pause", [paused, player_name])
		return
	if paused:
		return
	match method:
		"_request_ready":
			if not locked and _draft == "" and (phase == CALM or phase == CLEARING) and time_left > 3.0:
				rpc(GAME, "_ready_changed", [1, 1])
				time_left = 3.0
				rpc(WEATHER, "_receive_phase", [phase, wave, time_left])
		"_request_interact":
			if _draft != "voting" and not locked:
				_interact(str(args[0]))
		"_request_tape_choice":
			if tape:
				tape = false
				if args[0]:
					endless = true
					locked = false
					score = 0
					self_revives = 1
					if state == "downed":
						_revive()
						self_revives = 1
					feat("stay_tuned")
					rpc(GAME, "_sync_tape_state", [false, true, false])
					set_override(-1.0)
					_set_phase(CALM, wave + 1)
				else:
					rpc(GAME, "_sync_tape_state", [false, false, true])
					_finish(true)


func _player_request(method: String, args: Array) -> void:
	match method:
		"_push_transform":
			if not paused and state != "out":
				pos = args[0]
				yaw = fposmod(args[1] + PI, TAU) - PI
				pitch = clamp(args[2], -1.536, 1.536)
				vel = args[3].normalized() * 24.0 if args[3].length_squared() > 576.0 else args[3]
				rpc(player_path, "_relay_transform", [pos, yaw, pitch, vel], false)
		"_report_exposure":
			sheltered = args[0]
			in_puddle = args[1]
		"_push_tarp":
			tarp = args[0] and has_tarp and can_act()
			rpc(player_path, "_apply_tarp", [tarp])
		"_request_melee":
			# The native RPC is restricted to Turned players. Solo goes out.
			pass


func _interact(path: String) -> void:
	if path.begins_with("/root/"):
		path = path.substr(6)
	if path == player_path + "/ReviveSpot" and state == "downed" and self_revives > 0:
		_revive()
		return
	if state != "ok" or decon <= 0 or suit >= 99.0:
		return
	for marker in markers.decon_showers:
		var reach = marker.radius + 1.5
		if path == marker.interact_path and pos.distance_squared_to(marker.interact_pos) <= reach * reach:
			_used_decon = true
			suit = 100.0
			decon -= 1
			rpc(GAME, "_sync_decon", [decon])
			rpc(path, "play_spray", [])
			send_vitals()
			return


func _revive() -> void:
	state = "ok"
	self_revives -= 1
	hp = data.player.revive_health
	suit = max(suit, 30.0)
	bleed = 0.0
	grace = 3.0
	revive_grace = 3.0
	send_vitals()


func _go_out() -> void:
	state = "out"
	send_vitals()
	_finish(false)


func _tick_player(dt: float) -> void:
	grace = max(0.0, grace - dt)
	revive_grace = max(0.0, revive_grace - dt)
	var protection = loot.protection(self, pos + Vector3.UP)
	if phase in [DRIZZLE, DOWNPOUR] and (sheltered or tarp or protection == 2) and not in_puddle:
		_dry_wave = false
	var exposed = raining() and protection != 2 and (in_puddle or not (sheltered or tarp))
	if exposed:
		if not in_puddle and not _rain_seen:
			_rain_seen = true
			_rain_warning = 0.8
	_rain_warning = max(0.0, _rain_warning - dt)
	if state == "downed":
		bleed -= dt * (2.0 if exposed else 1.0)
		if bleed <= 0.0:
			_go_out()
		return
	if state != "ok" or revive_grace > 0.0 or locked:
		return
	var drain = 0.0
	if exposed and (in_puddle or _rain_warning <= 0.0):
		if player_mutations.has("hydro_skin") and not in_puddle and suit > 0.0:
			heal(2.5 * dt)
		if intensity <= 0.3:
			drain = intensity / 0.3
		elif intensity <= 0.7:
			drain = lerp(1.0, 4.0, (intensity - 0.3) / 0.4)
		else:
			drain = lerp(4.0, 6.0, (intensity - 0.7) / 0.3)
		if player_mutations.has("chitin_suit"):
			drain *= 0.65
		if protection == 1:
			drain *= 0.25
	if loot.held_id() == "leaky_nailgun":
		drain = max(drain, 2.0)
	if drain > 0.0:
		_took_acid = _took_acid or exposed
		if suit > 0.0:
			suit = max(0.0, suit - drain * dt)
		else:
			damage(drain * dt, Vector3.INF, true)


func _tick_weather(dt: float) -> void:
	var target = 0.0
	if phase == DRIZZLE:
		target = 0.3
	elif phase == DOWNPOUR:
		target = 1.0 if wave >= _weather.final_wave else 0.7
	intensity = move_toward(intensity, override if override >= 0.0 else target, dt * _weather.intensity_ramp_per_second)
	_puddle_tick += dt
	if _puddle_tick >= 0.1:
		_grow_puddles(_puddle_tick)
		_puddle_tick = 0.0
	if raining() and clock >= _lightning_at:
		var marker = markers.enemy_spawn[rng.randi_range(0, markers.enemy_spawn.size() - 1)].pos
		var at = marker + Vector3(rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-6.0, 6.0))
		rpc(WEATHER, "_strike", [at, -rng.randi_range(1, 2147483646)])
		arena.ambient_lightning(self, at)
		_lightning_at = clock + _lightning_interval() * rng.randf_range(0.6, 1.4)
	if _draft != "" or locked or arena.boss_alive():
		return
	time_left = max(0.0, time_left - dt)
	if time_left > 0.0:
		return
	match phase:
		CALM:
			_set_phase(DRIZZLE, wave)
		DRIZZLE:
			_set_phase(DOWNPOUR, wave)
		DOWNPOUR:
			if arena.wave_complete(wave):
				_set_phase(CLEARING, wave)
		CLEARING:
			_set_phase(CALM, wave + 1)


func _grow_puddles(dt: float) -> void:
	var wet = raining()
	var flood = 3.0 if forecast == "FLOOD" else 1.0
	for marker in markers.puddles:
		var key = NodePath(marker.sync_key)
		var change = intensity * flood * dt / marker.grow_time if wet else -dt / marker.dry_time
		puddles[key] = clamp(puddles[key] + change, 0.0, 1.0)


func _lightning_interval() -> float:
	var bases = [18.0, 13.0, 9.5, 6.8, 4.4]
	var interval = bases[wave - 1] if wave <= bases.size() else max(2.6, 4.4 - 0.45 * (wave - 5))
	return interval * lerp(1.75, 1.0, clamp((intensity - 0.25) / 0.75, 0.0, 1.0)) \
		* (0.68 if forecast == "HEAVY WEATHER" else 1.0)


func _set_phase(next_phase: int, next_wave: int) -> void:
	phase = next_phase
	wave = next_wave
	if wave <= _weather.wave_modifiers.size():
		forecast = _weather.wave_modifiers[wave - 1]
	else:
		forecast = _weather.endless_modifiers[(wave - _weather.wave_modifiers.size() - 1) % _weather.endless_modifiers.size()]
	match phase:
		CALM:
			time_left = _weather.calm_duration
			_lightning_at = INF
		DRIZZLE:
			time_left = _weather.drizzle_duration
			_lightning_at = clock + _lightning_interval() * rng.randf_range(0.55, 0.95)
		DOWNPOUR:
			time_left = rng.randf_range(_weather.downpour_min_duration, _weather.downpour_max_duration)
			_lightning_at = clock + _lightning_interval() * rng.randf_range(0.55, 0.95)
		CLEARING:
			time_left = _weather.clearing_duration
			_lightning_at = INF
	rpc(WEATHER, "_receive_phase", [phase, wave, time_left])
	rpc(GAME, "_ready_changed", [0, 1])
	arena.on_phase(self)
	loot.on_phase(self)
	match phase:
		CALM:
			_dry_wave = true
			_dragged_wave = false
			_wave_kills = 0
			if decon < 4:
				decon += 1
				rpc(GAME, "_sync_decon", [decon])
			_deal_draft()
		DOWNPOUR:
			if wave == _weather.final_wave:
				arena.spawn_boss(self)
		CLEARING:
			waves_cleared = wave
			if endless:
				score += 500 + 100 * (wave - int(_weather.final_wave))
			rpc(GAME, "_banner", ["WAVE %d CLEAR" % wave, Color("#66dfda"), 2.2])
			if state == "ok" and _dry_wave:
				feat("no_roof")
			if state == "ok" and _dragged_wave:
				feat("not_today_undertow")
			if state == "ok" and _wave_kills == 0:
				feat("conscientious_objector")
			if state == "ok" and wave == 1 and suit < 10.0:
				feat("just_a_drizzle")
			if not endless:
				enemy_mutations.clear()
				rpc(MUTATION, "_clear_rpc", [])
			self_revives = 1


func _deal_draft() -> void:
	_draft_cards = []
	_draft_vote = -1
	_draft_enemy = str(FORECAST_MUTATIONS.get(forecast, ""))
	for mutation in COUNTERS.get(forecast, []):
		if not player_mutations.has(mutation):
			_draft_cards.append(mutation)
	var pool = []
	for mutation in data.player_mutations:
		if not player_mutations.has(mutation.id) and not _draft_cards.has(mutation.id):
			pool.append(mutation.id)
	while _draft_cards.size() < 3 and not pool.empty():
		var pick = rng.randi_range(0, pool.size() - 1)
		_draft_cards.append(pool[pick])
		pool.remove(pick)
	_draft = "voting"
	_draft_at = clock + (1.5 if _draft_cards.empty() else 14.0)
	rpc(MUTATION, "_deal_rpc", [_draft_enemy, _draft_cards.duplicate()])


func _resolve_draft() -> void:
	var granted = []
	if _draft_enemy != "" and not enemy_mutations.has(_draft_enemy):
		enemy_mutations.append(_draft_enemy)
	var pick = _draft_vote
	if not _draft_cards.empty():
		if pick < 0:
			pick = rng.randi_range(0, _draft_cards.size() - 1)
		var mutation = _draft_cards[pick]
		player_mutations.append(mutation)
		granted.append(mutation)
		if mutation == "chitin_suit":
			max_hp += 25.0
			heal(25.0)
	rpc(MUTATION, "_result_rpc", [pick, enemy_mutations.duplicate(), player_mutations.duplicate(), granted])
	_draft = "result"
	_draft_at = clock + 2.2


func _finish(won: bool) -> void:
	if finished:
		return
	finished = true
	feat("cable_subscriber")
	var names = []
	for mutation in data.player_mutations:
		if player_mutations.has(mutation.id):
			names.append(mutation.name)
	var held = loot.held_id()
	if loot.items.has(held) and loot.items[held].kind == "gun":
		weapon_name = loot.items[held].name
	var stats = {"name": player_name, "kills": kills, "revives": 0, "turned": 0, "cursed": cursed, "weapon": weapon_name}
	rpc(GAME, "_finish", [won, {"won": won, "map_id": map_id, "waves": waves_cleared, "wave_reached": wave,
		"endless": endless, "endless_score": score, "seconds": int(clock), "squad_mutations": names, "players": {peer: stats}}])


static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
