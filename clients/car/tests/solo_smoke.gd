extends SceneTree
## Run from the repository root:
## godot --path clients/car --no-window --fixed-fps 60 -s res://tests/solo_smoke.gd
## The bot knows only FullLink messages, the published schema, and level collision.

const Link = preload("res://solo/local_link.gd")
const Physics = preload("res://world/level_physics.gd")
const MAPS = ["pinecrest", "harbor", "maple_hollow"]
const DT = 1.0 / 60.0
const GRID = 2.5
const HEAD = [1.54, 1.28, 1.75, 1.07, 1.80, 1.37, 1.44, 1.75, 1.67]
const CATCH_UP = ["_sync_tape_state", "_receive_phase", "_receive_intensity", "_override", "_sync_decon",
	"_sync_active", "_snapshot", "_sync_progress", "_sync_puddles", "_snapshot",
	"_equip_state", "_private_state", "_confirm_run_ready"]

var _schema = {}
var _data = {}
var _maps = {}
var _errors = []
var _unknown = {}
var _index = -1
var _selected_maps = MAPS.duplicate()
var _seed_offset = 0
var _id = ""
var _link
var _level
var _space
var _peer = 0
var _holder = ""
var _player = ""
var _run = 0
var _clock = 0.0
var _join = false
var _load_pending = false
var _active = false
var _catch_up = []
var _ready_checked = false
var _phase = 0
var _wave = 1
var _phase_left = 12.0
var _done_draft = true
var _recheck_ready = 0.0
var _result = {}
var _start_pending = false
var _pause_echo = false
var _pause_test = 0.0
var _paused_packets = 0
var _pos = Vector3.ZERO
var _move = Vector3.ZERO
var _yaw = 0.0
var _cooldown = 0.0
var _reload = 0.0
var _slot = 0
var _rows = [[], [], [], [], []]
var _stash = {}
var _scrap = 0
var _hp = 100.0
var _suit = 100.0
var _life = "ok"
var _saw_down = false
var _saw_revive = false
var _saw_out = false
var _revive_at = INF
var _repaired = false
var _score = 0
var _observed_kills = 0
var _critical_hits = 0
var _enemies = {}
var _supplies = {}
var _cabinets = {}
var _airdrop = []
var _supply_hold = []
var _puddle_wet = {}
var _last_exposure = []
var _puddles = 0.0
var _routing = AStar.new()
var _grid_lookup = {}
var _route = PoolVector3Array()
var _route_i = 0
var _route_at = 0.0
var _goal_at = 0.0
var _goal = Vector3.INF
var _next_shot = 0.0
var _next_transform = 0.0
var _receiver_usec = 0
var _times = {}
var _peak = 0
var _frames = 0
var _map_limit = 3
var _configured_cap = 0
var _test_cap = 0
var _landed = {}
var _meds_used = 0
var _campaign = false
var _endless = false
var _boss_pos = Vector3.INF
var _boss_parts = []
var _tape_seen = false
var _cap_wait_until = 0.0
var _load_test = false
var _reset_phase = 0
var _previous_run = 0
var _probe_packets = {}
var _revive_wave = 0


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	var schema = _read("res://../../docs/open-protocol/open-protocol-schema.json")
	for signature in schema.get("rpcs", []):
		_schema[signature.node + "." + signature.method] = signature
	var markers = _read("res://../../docs/open-protocol/level-markers.json")
	_maps = markers.get("maps", {})
	for item in _read("res://../../docs/open-protocol/game-data.json").get("items", []):
		_data[item.id] = item
	if _schema.empty() or _maps.empty() or _data.empty():
		printerr("SOLO test cannot load protocol docs")
		quit(1)
		return
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--solo-waves="):
			_map_limit = int(arg.substr(13))
		elif arg.begins_with("--solo-map=") and arg.substr(11) in MAPS:
			_selected_maps = [arg.substr(11)]
		elif arg.begins_with("--solo-seed-offset="):
			_seed_offset = int(arg.substr(19))
		elif arg.begins_with("--solo-cap="):
			_configured_cap = int(clamp(int(arg.substr(11)), 1, 60))
		elif arg == "--solo-load":
			_load_test = true
		elif arg == "--solo-campaign":
			_campaign = true
		elif arg == "--solo-endless":
			_campaign = true
			_endless = true
	_test_handshake()
	_next_map()
	connect("physics_frame", self, "_frame")


func _test_handshake() -> void:
	var probe = Link.new()
	var events = []
	probe.connect("message", self, "_collect", [events])
	probe.connect("closed", self, "_closed", [events])
	probe.open({"v": 2, "tier": "full"})
	_expect(events.empty(), "open emitted outside poll")
	probe.poll(0.0)
	_expect(events.size() == 2 and events[0].msg == "Expected hello with Open Protocol v1" and events[1].t == "closed",
		"transport version rejection")
	events.clear()
	probe.open({"v": 1, "tier": "full"})
	probe.poll(0.0)
	probe.send({"t": "rpc", "node": "Net", "method": "_hello", "args": ["{}", 18]})
	probe.poll(0.0)
	_expect(events.size() == 2 and events[1].method == "_reject", "game protocol rejection")
	probe.poll(0.5)
	_expect(events.back().t == "closed", "rejected game link closed")
	events.clear()
	probe.open({"v": 1, "tier": "full"})
	probe.poll(10.1)
	_expect(events.size() >= 3 and events[1].msg == "Full tier join timed out", "game handshake timeout")
	probe.close()


func _collect(message: Dictionary, events: Array) -> void:
	events.append(message)


func _closed(_code: int, reason: String, events: Array) -> void:
	events.append({"t": "closed", "reason": reason})


func _next_map() -> void:
	if is_instance_valid(_level):
		_level.queue_free()
	if _link != null:
		_link.close()
	_index += 1
	if _index >= _selected_maps.size():
		print("SOLO checks errors=", _errors, " unknown=", _unknown)
		quit(0 if _errors.empty() and _unknown.empty() else 1)
		return
	_id = _selected_maps[_index]
	_link = Link.new()
	var map_index = MAPS.find(_id)
	_link.rng_seed = 195700 + map_index + (_seed_offset + 2 if _id == "harbor" else _seed_offset)
	_test_cap = _configured_cap
	if _test_cap == 0:
		_test_cap = 18 if _load_test else (12 if _id == "pinecrest" else 8)
	_link.max_alive = _test_cap
	_reset_phase = 0
	_link.connect("message", self, "_message")
	_join = false
	_load_pending = false
	_start_pending = false
	_active = false
	_result = {}
	_catch_up = []
	_ready_checked = false
	_clock = 0.0
	_frames = 0
	_phase = 0
	_wave = 1
	_recheck_ready = 0.0
	_done_draft = true
	_pause_test = 0.0
	_paused_packets = 0
	_rows = [[], [], [], [], []]
	_stash = {}
	_life = "ok"
	_hp = 100.0
	_suit = 100.0
	_saw_down = false
	_saw_revive = false
	_revive_wave = 0
	_saw_out = false
	_revive_at = INF
	_repaired = false
	_observed_kills = 0
	_critical_hits = 0
	_enemies.clear()
	_landed.clear()
	_meds_used = 0
	_supplies.clear()
	_cabinets.clear()
	_airdrop = []
	_supply_hold = []
	_last_exposure = []
	_puddle_wet.clear()
	_puddles = 0.0
	_score = 0
	_boss_pos = Vector3.INF
	_boss_parts = []
	_tape_seen = false
	_route_at = 0.0
	_goal_at = 0.0
	_next_shot = 0.0
	_next_transform = 0.0
	_times = {}
	_peak = 0
	_cap_wait_until = INF
	_link.open({"v": 1, "tier": "full", "enc": "json"})


func _frame() -> void:
	if _index >= _selected_maps.size():
		return
	if _load_pending:
		_load_pending = false
		_make_level()
		return
	if _start_pending:
		_start_pending = false
		_space = _level.get_world().direct_space_state
		_build_routes()
		_link.level_ready(_id, _level, _level)
		_rpc("Net", "_report_in_run", [true])
	for _step in range(36):
		var alive = _enemies.size()
		_receiver_usec = 0
		var start = OS.get_ticks_usec()
		_link.poll(DT)
		var usec = max(0, OS.get_ticks_usec() - start - _receiver_usec)
		if _active and not _pause_echo:
			var record = _times.get(alive, [0, 0, 0])
			record[0] += usec
			record[1] = max(record[1], usec)
			record[2] += 1
			_times[alive] = record
			_frames += 1
		_peak = max(_peak, _enemies.size())
		_clock += DT
		if not _result.empty():
			_summarize()
			_test_restart()
			_next_map()
			return
		if _active:
			_space = _level.get_world().direct_space_state
			_bot()
		if _load_pending:
			return
		if _clock >= 940.0:
			_expect(false, "timed out at wave %d phase %d alive %d kills %d scrap %d pos=%s hp=%.1f suit=%.1f" \
				% [_wave, _phase, _enemies.size(), _observed_kills, _scrap, str(_pos), _hp, _suit])
			_next_map()
			return


func _test_restart() -> void:
	_previous_run = _run
	_reset_phase = 1
	_rpc("Net", "_request_map_vote", [_id])
	_rpc("Net", "_request_ready", [true])
	_link.poll(0.5)
	_expect(_reset_phase == 1, "results reset delay")
	_link.poll(4.6)
	_expect(_reset_phase == 2, "results return and deferred lobby start")
	_link.level_ready(_id, _level, _level)
	_rpc("Net", "_report_in_run", [true])
	_link.poll(0.0)
	_expect(_reset_phase == 3 and _run == _previous_run + 1, "next run has a new run id")
	if _reset_phase == 3:
		_test_actions()


func _test_actions() -> void:
	_probe_packets.clear()
	_rpc("Main/RunLoot", "_request_starter", [_run, 2])
	_rpc(_player, "_report_exposure", [false, true])
	_rpc("GameManager", "_request_ready", [])
	for _step in range(32):
		_link.poll(0.25)
	var vitals = _probe_packets.get("_apply_vitals", [])
	_expect(not vitals.empty() and vitals[1] < 98.0, "reported exposure drains the suit")
	var shower = _maps[_id].decon_showers[0]
	var at = _vector(shower.pos)
	_rpc(_player, "_push_transform", [at, 0.0, 0.0, Vector3.ZERO])
	_rpc("GameManager", "_request_interact", [NodePath("/root/" + shower.interact_path)])
	_link.poll(0.0)
	_expect(_probe_packets.has("play_spray") and _probe_packets.get("_sync_decon") == [3]
		and _probe_packets.get("_apply_vitals", [0.0, 0.0])[1] == 100.0, "decon repairs and consumes a charge")
	_rpc(_player, "_report_exposure", [true, false])
	_rpc(_holder, "_action", [_run, "select_pouch", 0, 0])
	_link.poll(0.25)
	var eye = at + Vector3.UP * 1.65
	_rpc(_holder, "_request_throw", [_run, "frag", eye, Vector3.UP])
	_link.poll(0.0)
	var spawn = _probe_packets.get("_effect_spawn", [])
	_expect(not spawn.empty() and spawn[2][0] == "frag" and _probe_packets.has("_throw_fx")
		and _probe_packets.get("_private_state")[7] == 1, "pouch throw consumes a frag and spawns a projectile")
	for _step in range(28):
		_link.poll(0.1)
	_expect(_probe_packets.has("_effect_end"), "grenade ends")


func _message(msg: Dictionary) -> void:
	var start = OS.get_ticks_usec()
	_handle(msg)
	_receiver_usec += OS.get_ticks_usec() - start


func _handle(msg: Dictionary) -> void:
	if msg.t == "welcome":
		_peer = msg.you
		_player = "Main/Players/P_%d" % _peer
		_holder = _player + "/Head/Camera3D/WeaponHolder"
		_expect(_peer > 1 and msg.game_protocol == 19 and msg.maps.size() == 3, "Full welcome")
		_rpc("Net", "_hello", ['{"name":"Solo [Bot]","color":3,"skin":1,"colors":[3]}', 19])
		return
	if msg.t != "rpc":
		_expect(false, "unexpected control " + str(msg))
		return
	_validate(msg)
	var a = msg.args
	if _reset_phase > 0:
		_probe_packets[msg.method] = a
		if msg.method == "_start_run" and a[0] == _id:
			_reset_phase = 2
		elif msg.method == "_snapshot":
			_run = a[0]
		elif msg.method == "_confirm_run_ready":
			_reset_phase = 3
		return
	if not _ready_checked and _active == false and _level != null and not _start_pending \
			and msg.method != "_rtt_ping" and msg.node != "Net":
		_catch_up.append(msg.method)
	if _pause_echo and msg.node != "Net" and msg.method != "_sync_pause":
		_paused_packets += 1
	match msg.method:
		"_push_roster":
			if not _join:
				_join = true
				_expect(a[0].has(_peer) and a[0][_peer].name == "Solo (Bot)", "sanitized roster")
				_rpc("Net", "_request_map_vote", [_id])
			elif a[4] == _id and not _load_pending and not _active and not a[0][_peer].ready and not _ready_checked:
				_rpc("Net", "_request_ready", [true])
				_ready_checked = true
		"_rtt_ping":
			_rpc("Net", "_rtt_pong", [a[0]])
		"_start_run":
			_expect(a[0] == _id, "map vote selected")
			_ready_checked = false
			_load_pending = true
		"_confirm_run_ready":
			_catch_up.append(msg.method)
			_expect(_catch_up == CATCH_UP, "catch-up order " + str(_catch_up))
			_ready_checked = true
			_active = true
			_rpc("Main/RunLoot", "_request_starter", [_run + 1, 0])
			_rpc("Main/RunLoot", "_request_starter", [_run, 2])
			_rpc("Main/RunLoot", "_request_starter", [_run, 0])
			_rpc("GameManager", "_request_pause_rpc", [true, "Bogus callsign"])
			_pause_test = _clock + 1.2
		"_starter_accepted":
			_expect(a[0] == _run and _rows[0][1] == "service_revolver", "only one valid starter")
		"_sync_pause":
			_pause_echo = a[0]
			_expect(a[1] == "Solo (Bot)", "pause callsign")
		"_receive_phase":
			_phase = a[0]
			_wave = a[1]
			_phase_left = a[2]
			_recheck_ready = _clock + 0.1
		"_sync_puddles":
			for key in a[0]:
				_expect(typeof(key) == TYPE_NODE_PATH, "puddle key is NodePath")
			_puddle_wet = a[0].duplicate()
		"_snapshot":
			_run = a[0]
			if msg.node == "GameManager/CrateManager":
				_cabinets = a[1]
		"_stock":
			_cabinets[a[1]] = a[2]
		"_airdrop_spawn":
			_airdrop = [a[1], _clock + a[2]]
		"_remove_drop":
			_airdrop = []
		"_private_state":
			_rows = a[2]
			_stash = a[3]
			_slot = a[4]
			_scrap = a[6]
			_reload = a[9]
			_cooldown = a[12]
		"_apply_vitals":
			_hp = a[0]
			_suit = a[1]
			if a[2] == "downed" and _life != "downed":
				_saw_down = true
				_revive_at = _clock + 3.05
			if a[2] == "ok" and _life == "downed":
				_saw_revive = true
			_saw_out = _saw_out or a[2] == "out"
			_life = a[2]
		"_spawn_enemy":
			_enemies[a[0]] = [a[2], a[1], 2.5 if a[5] > 0 else (0.6 if a[3] else 1.0)]
		"_sync_enemies":
			for i in range(a[0].size()):
				if _enemies.has(a[0][i]):
					_enemies[a[0][i]][0] = a[1][i]
		"_despawn_enemy":
			_enemies.erase(a[0])
		"_retire_enemies":
			for id in a[0]:
				_enemies.erase(id)
		"_receive_hits":
			for hit in a[1]:
				_critical_hits += int(hit[1])
				if hit[0] and hit[4] < 900000:
					_observed_kills += 1
		"_sync_progress":
			_score = a[4]
		"_spawn":
			_supplies[a[1]] = a[2]
		"_remove":
			_supplies.erase(a[1])
		"_deal_rpc":
			_done_draft = false
			if not a[1].empty():
				var pick = a[1].find("vampiric_siphon")
				_rpc("GameManager/MutationRoll", "_request_vote", [max(0, pick)])
		"_result_rpc":
			_recheck_ready = _clock + 2.3
			_done_draft = true
		"_spawn_spore":
			_landed[a[0]] = [a[2], _clock + a[3], 3.4 if a[5] else 2.9]
		"_spawn_cloud":
			_landed[a[0]] = [a[1], _clock, a[3] + 0.4]
		"_disperse_cloud":
			_landed.erase(a[0])
		"_spawn_boss":
			_boss_pos = a[0]
		"_sync":
			_boss_pos = a[0]
			_boss_parts = a[1]
		"_died":
			_boss_pos = Vector3.INF
		"_sync_tape_state":
			if a[0]:
				_tape_seen = true
				_rpc("GameManager", "_request_tape_choice", [_endless])
		"play_spray":
			_repaired = true
		"_finish":
			_result = a[1]
			_active = false
			_rpc("Net", "_report_in_run", [false])
			_link.level_unloaded()


func _validate(msg: Dictionary) -> void:
	var node = msg.node.replace(_player, "Main/Players/P_<peer_id>")
	if node.begins_with("Main/Level/DeconShowers/"):
		node = "Main/Level/DeconShowers/<decon_marker>/Interact"
	var key = node + "." + msg.method
	if not _schema.has(key):
		_unknown[key] = true
		return
	var s = _schema[key]
	var minimum = 0
	for arg in s.args:
		minimum += int(not arg.optional)
	_expect(s.direction != "client->host" and s.reliable == msg.rel and s.channel == msg.ch \
		and msg.args.size() >= minimum and msg.args.size() <= s.args.size(), "signature " + key)
	for i in range(min(msg.args.size(), s.args.size())):
		var type = s.args[i].type
		var types = {"int": TYPE_INT, "float": TYPE_REAL, "String": TYPE_STRING, "bool": TYPE_BOOL,
			"Vector3": TYPE_VECTOR3, "Dictionary": TYPE_DICTIONARY, "Array": TYPE_ARRAY, "Color": TYPE_COLOR,
			"Transform3D": TYPE_TRANSFORM, "PackedInt32Array": TYPE_INT_ARRAY,
			"PackedFloat32Array": TYPE_REAL_ARRAY, "PackedVector3Array": TYPE_VECTOR3_ARRAY}
		var v = typeof(msg.args[i])
		_expect(types.get(type, -1) == v, "argument %d %s expected %s, got %d" % [i, key, type, v])


func _rpc(node: String, method: String, args: Array) -> void:
	_link.send({"t": "rpc", "node": node, "method": method, "args": args})


func _make_level() -> void:
	_level = load("res://assets/maps/%s.glb" % _id).instance()
	root.add_child(_level, true)
	_level.hide()
	Physics.new().build(_level, _id)
	_pos = _vector(_maps[_id].player_spawn[0].pos)
	_move = Vector3.ZERO
	_goal = _pos
	_level.set_process(false)
	_start_pending = true


func _bot() -> void:
	_phase_left = max(0.0, _phase_left - DT)
	if _pause_echo:
		if _clock >= _pause_test:
			_expect(_paused_packets == 0, "paused simulation emitted run state")
			_rpc("GameManager", "_request_pause_rpc", [false, ""])
		return
	_reload = max(0.0, _reload - DT)
	_cooldown = max(0.0, _cooldown - DT)
	if _done_draft and (_phase == 0 or _phase == 4) and _clock >= _recheck_ready:
		_recheck_ready = _clock + 0.8
		if _airdrop.empty() or _phase == 4:
			_rpc("GameManager", "_request_ready", [])
	var surrender = _should_surrender()
	if _life == "downed":
		if _clock >= _revive_at and _revive_wave != _wave:
			_rpc("GameManager", "_request_interact", [NodePath("/root/" + _player + "/ReviveSpot")])
			_revive_at = INF
			_revive_wave = _wave
		return
	if _life != "ok":
		return
	var hold_for_cap = _load_test and _wave == 1 and _peak < _test_cap and _clock < 65.0 and not surrender
	if not hold_for_cap and _cap_wait_until == INF and _peak == _test_cap:
		_cap_wait_until = _clock + 0.7
	hold_for_cap = _load_test and (hold_for_cap or _clock < _cap_wait_until and _cap_wait_until != INF)
	var enemy = _nearest_enemy()
	var target = enemy[0] if not enemy.empty() else Vector3.INF
	if _clock >= _goal_at:
		_goal_at = _clock + 0.23
		_goal = _choose_goal(enemy, surrender, hold_for_cap)
	if _clock >= _route_at:
		_route_at = _clock + 0.55
		_update_route(_goal)
	_walk(_goal)
	var aim = _eye() + Vector3.FORWARD
	if target != Vector3.INF:
		aim = target
	if _boss_pos != Vector3.INF and _campaign:
		var part = _boss_target()
		if part != Vector3.INF:
			aim = part
	var direction = (aim - _eye()).normalized()
	if direction == Vector3.ZERO:
		direction = Vector3.FORWARD
	_yaw = atan2(-direction.x, -direction.z)
	if _clock >= _next_transform:
		_next_transform += 0.05
		_rpc(_player, "_push_transform", [_pos, _yaw, asin(direction.y), _move])
		_exposure(surrender, hold_for_cap)
	_supply_actions()
	if not surrender and not hold_for_cap:
		_fire(aim, direction, enemy)


func _should_surrender() -> bool:
	return (_wave > _map_limit and not _campaign) or (_endless and _wave > 6)


func _exposure(surrender: bool, _holding: bool) -> void:
	# Keep combat and damage paths independently reproducible. This bot reports
	# shelter during combat, then deliberately reports exposure to test acid loss.
	var report = [not surrender, false]
	if report != _last_exposure:
		_last_exposure = report
		_rpc(_player, "_report_exposure", report)


func _nearest_enemy() -> Array:
	var nearest = []
	var score = INF
	for id in _enemies:
		var e = _enemies[id]
		var aim = e[0] + Vector3.UP * HEAD[e[1]] * e[2]
		var d = _pos.distance_to(e[0])
		var clear = _clear(_eye(), aim)
		var cost = d + (0.0 if clear else 25.0)
		if cost < score:
			score = cost
			nearest = [aim, e[0], d, clear]
	return nearest


func _choose_goal(enemy: Array, surrender: bool, hold_for_cap: bool) -> Vector3:
	if surrender:
		return _pos
	for id in _landed:
		var cloud = _landed[id]
		var outward = _pos - cloud[0]
		outward.y = 0.0
		if _clock + 0.35 >= cloud[1] and outward.length_squared() < cloud[2] * cloud[2]:
			return _pos + (outward.normalized() if outward.length_squared() > 0.01 else Vector3.RIGHT) * 6.0
	if _suit < 65.0 and not _repaired:
		var showers = _maps[_id].decon_showers
		var best = INF
		var target = _pos
		for shower in showers:
			var at = _vector(shower.pos)
			if _pos.distance_squared_to(at) < best:
				best = _pos.distance_squared_to(at)
				target = at
		return target
	var gun = _data[_rows[_slot][1]] if not _rows[_slot].empty() else null
	var low = gun != null and gun.kind == "gun" and _stash.get(gun.ammo_type, 0) + _rows[_slot][3] < 10
	var enemy_near = INF if enemy.empty() else enemy[2]
	if not _airdrop.empty() and _phase <= 2 and enemy_near > 8.0:
		return _airdrop[0]
	if low and _scrap >= 5 and not _cabinets.empty() and enemy_near > 5.0:
		return _closest_ammo_pad()
	if not hold_for_cap:
		var loot = _desired_loot(low, enemy_near)
		if loot != Vector3.INF:
			return loot
	if not enemy.empty():
		if hold_for_cap or enemy_near < 6.3:
			var away = enemy[1].direction_to(_pos)
			away.y = 0
			return _pos + away.normalized() * 7.0
		if enemy[2] > 14.0 or not enemy[3]:
			return enemy[1]
	return _pos


func _desired_loot(low: bool, enemy_distance: float) -> Vector3:
	var best = INF
	var target = Vector3.INF
	for id in _supplies:
		var row = _supplies[id]
		var useful = row[2] in ["ammo", "ammo_box"] and low or row[2] == "health" and _hp < 80.0 \
			or row[2].begins_with("scrap") and enemy_distance > 8.0 or not row[1].empty() and _phase == 0 and _rows.find([]) >= 0
		var distance = _pos.distance_squared_to(row[0])
		if useful and distance < best and distance < (1200.0 if low or _phase == 0 else 100.0):
			best = distance
			target = row[0]
	return target


func _supply_actions() -> void:
	if _suit < 90.0 and not _repaired:
		for shower in _maps[_id].decon_showers:
			if _pos.distance_to(_vector(shower.interact_pos)) < 3.5:
				_rpc("GameManager", "_request_interact", [NodePath("/root/" + shower.interact_path)])
				break
	if not _supply_hold.empty():
		if _clock >= _supply_hold[2]:
			_rpc("GameManager/CrateManager", "_hold_request", [_run, _supply_hold[0], _supply_hold[1], "finish", 0])
			_supply_hold = []
	elif not _airdrop.empty() and _clock >= _airdrop[1] and _reachable(_airdrop[0] + Vector3.UP * 0.85):
		_begin_hold("Airdrop", "airdrop")
	elif _scrap >= 5:
		for stall in _maps[_id].vending_stations:
			if _cabinets.has(stall.key) and _reachable(_ammo_pad(stall)) and not _rows[_slot].empty():
				var def = _data[_rows[_slot][1]]
				if _stash.get(def.ammo_type, 0) < min(10, def.get("reserve_cap", 0)):
					_begin_hold(stall.key, "ammo")
					break
	for id in _supplies:
		var row = _supplies[id]
		if not row[1].empty() and _pos.distance_squared_to(row[0]) < 2.5 * 2.5 \
				and _clear(_eye(), row[0] + Vector3.UP * 0.28) and _rows.find([]) >= 0:
			var held_serial = 0 if _rows[_slot].empty() else _rows[_slot][0]
			_rpc("Main/RunLoot", "_claim", [_run, id, held_serial, _slot])
			break


func _closest_ammo_pad() -> Vector3:
	var best = INF
	var target = _pos
	for stall in _maps[_id].vending_stations:
		var point = _ammo_pad(stall)
		var direction = Vector3(0, 0, -1).rotated(Vector3.UP, stall.yaw)
		var approach = point + direction * 1.35
		var distance = _pos.distance_squared_to(approach)
		if not _clear(approach + Vector3.UP * 0.65, point) or not _clear(approach + Vector3.UP * 1.0, approach):
			distance += 500.0
		if distance < best:
			best = distance
			target = approach
	return target


func _begin_hold(key: String, mode: String) -> void:
	_rpc("GameManager/CrateManager", "_hold_request", [_run, key, mode, "begin", 0])
	_supply_hold = [key, mode, _clock + 0.6]


func _ammo_pad(stall: Dictionary) -> Vector3:
	return _vector(stall.pos) + Vector3(-0.68, 0.56, -0.58).rotated(Vector3.UP, stall.yaw)


func _reachable(point: Vector3) -> bool:
	return _pos.distance_squared_to(point) < 2.7 * 2.7 and _clear(_eye(), point)


func _fire(aim: Vector3, direction: Vector3, enemy: Array) -> void:
	if _clock < _next_shot or _cooldown > DT:
		return
	var item = _rows[_slot]
	if item.empty():
		_select_gun(0)
		return
	var def = _data[item[1]]
	if def.kind == "consumable":
		if (_hp < 75.0 and item[1] == "med_tin") or (_suit < 75.0 and item[1] == "suit_patch"):
			_rpc(_holder, "_request_shot", [_run, item[0], _eye(), direction, true, false])
			_next_shot = _clock + 0.2
			_meds_used += 1
			return
		_select_gun(item[0])
		return
	elif def.kind != "gun":
		_select_gun(item[0])
		return
	elif _hp < 62.0:
		for i in range(_rows.size()):
			if not _rows[i].empty() and _rows[i][1] == "med_tin":
				_rpc(_holder, "_action", [_run, "select", item[0], i])
				_next_shot = _clock + 0.24
				return
	var ammo = _stash.get(def.ammo_type, 0) + item[3]
	if ammo <= 0 or _boss_pos != Vector3.INF and def.weapon.damage * def.weapon.pellets / def.weapon.fire_interval < 100.0:
		for i in range(_rows.size()):
			if i == _slot or _rows[i].empty():
				continue
			var other = _data[_rows[i][1]]
			if other.kind == "gun" and _rows[i][3] + _stash.get(other.ammo_type, 0) > 0 \
					and (ammo <= 0 or other.weapon.damage * other.weapon.pellets / other.weapon.fire_interval > 120.0):
				_rpc(_holder, "_action", [_run, "select", item[0], i])
				_next_shot = _clock + 0.24
				return
	var quiet = enemy.empty() or enemy[2] > 15.0
	if item[3] == 0 or (item[3] < min(3, def.weapon.mag_size) and quiet and _stash.get(def.ammo_type, 0) > 0):
		if _reload <= DT and ammo > item[3]:
			_rpc(_holder, "_action", [_run, "reload", item[0], -1])
			_next_shot = _clock + 0.13
		return
	if aim != _eye() + Vector3.FORWARD and _eye().distance_to(aim) < min(33.0, def.weapon.max_range) \
			and _clear(_eye(), aim):
		_rpc(_holder, "_request_shot", [_run, item[0], _eye(), direction, true, false])
		_next_shot = _clock + max(def.weapon.fire_interval * 0.84, 0.085)


func _select_gun(held_serial: int) -> void:
	var best = -1
	var rounds = -1
	for i in range(_rows.size()):
		if _rows[i].empty():
			continue
		var def = _data[_rows[i][1]]
		if def.kind == "gun":
			var ammo = _rows[i][3] + _stash.get(def.ammo_type, 0)
			if ammo > rounds:
				best = i
				rounds = ammo
	if best != -1:
		_rpc(_holder, "_action", [_run, "select", held_serial, best])
		_next_shot = _clock + 0.24


func _boss_target() -> Vector3:
	if _boss_parts.empty():
		return Vector3.INF
	var at = Vector3.INF
	var lowest = INF
	for i in range(4):
		if _boss_parts[i] <= 0.0 or i == 3 and at != Vector3.INF:
			continue
		var candidate = _boss_pos - Vector3.UP * 2.556
		if i < 3:
			var angle = i * TAU / 3.0
			candidate = _boss_pos + Vector3(cos(angle) * 7.1, -1.704, sin(angle) * 7.1)
		if _boss_parts[i] < lowest and _clear(_eye(), candidate):
			lowest = _boss_parts[i]
			at = candidate
	return at


func _build_routes() -> void:
	_routing.clear()
	_grid_lookup.clear()
	for y in range(-27, 28):
		for x in range(-27, 28):
			var at = Vector3(x * GRID, 0.12, y * GRID)
			var ray = _ray(at + Vector3.UP * 1.0, at - Vector3.UP * 1.6)
			if ray.empty() or ray.normal.y < 0.67:
				continue
			at = ray.position + Vector3.UP * 0.04
			if not _clear(at + Vector3.UP * 0.1, at + Vector3.UP * 1.7):
				continue
			var id = _routing.get_available_point_id()
			_routing.add_point(id, at)
			_grid_lookup[Vector2(x, y)] = id
	for key in _grid_lookup:
		var id = _grid_lookup[key]
		var from = _routing.get_point_position(id)
		for offset in [Vector2.RIGHT, Vector2.DOWN, Vector2(1, 1), Vector2(1, -1)]:
			if not _grid_lookup.has(key + offset):
				continue
			var other = _grid_lookup[key + offset]
			var to = _routing.get_point_position(other)
			if abs(from.y - to.y) < 0.65 and _clear(from + Vector3.UP * 0.65, to + Vector3.UP * 0.65):
				_routing.connect_points(id, other)


func _update_route(goal: Vector3) -> void:
	_route = PoolVector3Array()
	_route_i = 0
	if _pos.distance_squared_to(goal) < 1.0 or _clear(_pos + Vector3.UP * 0.65, goal + Vector3.UP * 0.65):
		return
	if _routing.get_point_count() > 0:
		var from = _routing.get_closest_point(_pos)
		var to = _routing.get_closest_point(goal)
		_route = _routing.get_point_path(from, to)


func _walk(goal: Vector3) -> void:
	var previous = _pos
	var target = goal
	while _route_i < _route.size() and _pos.distance_squared_to(_route[_route_i]) < 0.65 * 0.65:
		_route_i += 1
	if _route_i < _route.size():
		target = _route[_route_i]
	var flat = target - _pos
	flat.y = 0.0
	if flat.length_squared() > 0.16:
		var step = flat.normalized() * min(flat.length(), 5.25 * DT)
		for angle in [0.0, 0.75, -0.75, 1.4, -1.4]:
			var wanted = _pos + step.rotated(Vector3.UP, angle)
			var at = _pos + Vector3.UP * 0.65
			if not _clear(at, wanted + Vector3.UP * 0.65 + (wanted - _pos).normalized() * 0.22):
				continue
			var hit = _ray(wanted + Vector3.UP * 0.53, wanted - Vector3.UP * 1.1)
			if not hit.empty():
				_pos = hit.position + Vector3.UP * 0.04
				break
	_move = (_pos - previous) / DT


func _eye() -> Vector3:
	return _pos + Vector3.UP * 1.65


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	return _space.intersect_ray(a, b, [], 1, true, false)


func _clear(a: Vector3, b: Vector3) -> bool:
	return a.distance_squared_to(b) < 0.00001 or _ray(a, b).empty()


func _summarize() -> void:
	var stats = _result.players[_peer]
	var time = _times.get(_peak, [0, 0, 1])
	var average = time[0] / float(max(1, time[2])) / 1000.0
	print("SOLO ", _id, " waves=", _result.waves, " reached=", _result.wave_reached, " won=", _result.won,
		" kills=", stats.kills, " critical=", _critical_hits, " peak=", _peak, " sim_ms(avg/max)=",
		"%.3f/%.3f" % [average, time[1] / 1000.0], " peak_samples=", time[2],
		" meds=", _meds_used, " self_revive=", _saw_revive, " out=", _saw_out, " seconds=", _result.seconds)
	_expect(_result.map_id == _id and stats.kills == _observed_kills and _critical_hits > 0, "results and criticals")
	_expect(_peak <= _test_cap, "alive cap")
	if not _load_test:
		_expect(_result.waves >= (_map_limit if not _campaign else 5), "required waves cleared")
	if _load_test:
		_expect(_peak == _test_cap, "load cap reached")
	elif _campaign:
		_expect(_tape_seen, "campaign tape")
	else:
		_expect(_saw_down and _saw_revive and _saw_out, "solo wounded states")


func _expect(ok: bool, detail: String) -> void:
	if not ok:
		var error = "%s %s" % [_id, detail]
		if not error in _errors:
			_errors.append(error)
			printerr("SOLO ERROR ", error)


static func _read(path: String) -> Dictionary:
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error == OK else {}


static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
