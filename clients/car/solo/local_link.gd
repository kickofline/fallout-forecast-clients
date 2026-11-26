extends "res://core/full_link.gd"
## FullLink backed by a single-player game authority. Only poll emits signals.

const Run = preload("res://solo/local_run.gd")
const GAME_PROTOCOL = 19
const DEFAULT_MAP = "pinecrest"
const RESULTS_DELAY = 5.0

# Keep the default modest for clients where rendering shares the same CPU.
var max_alive = 18
# A negative seed lets the RNG choose a random seed.
var rng_seed = -1

var _rng = RandomNumberGenerator.new()
var _state = "closed"
var _queue = []
var _incoming = []
var _close_reason = ""
var _close_at = 0.0
var _clock = 0.0
var _next_probe = 0.0
var _probe = 0
var _last_chat = -1.0
var _ready = false
var _vote = ""
var _profile = {}
var _maps = []
var _data = {}
var _markers = {}
var _requests = {}
var _run = null
var _run_id = 0
var _finish_at = 0.0
var _pending_start = false


func is_local() -> bool:
	return true


func open(hello: Dictionary) -> void:
	close()
	_clock = 0.0
	_next_probe = 0.15
	_probe = 0
	_last_chat = -1.0
	_run_id = 0
	_rng.randomize()
	if rng_seed >= 0:
		_rng.seed = rng_seed
	var encoding = hello.get("enc", "json")
	if hello.get("t", "hello") != "hello" or hello.get("v") != 1:
		_terminal("Expected hello with Open Protocol v1")
	elif encoding != "json" and encoding != "bin":
		_terminal("Unsupported encoding")
	elif hello.get("tier", "thin") != "full":
		_terminal("Unsupported tier")
	else:
		if _data.empty():
			_data = _read("res://data/game_data.json")
			_markers = _read("res://solo/level_markers.json").get("maps", {})
			_requests = _read("res://solo/rpc_requests.json")
		if _data.get("game_protocol") != GAME_PROTOCOL or _markers.empty() or _requests.empty():
			_terminal("Full tier solo data unavailable")
			return
		_maps = []
		for map in _data.maps:
			_maps.append({"id": map.id, "name": map.name})
		_state = "welcomed"
		you = 2
		_queue.append({"t": "welcome", "v": 1, "tier": "full", "enc": encoding,
			"you": you, "game_protocol": GAME_PROTOCOL, "maps": _maps.duplicate(true)})


func send(msg: Dictionary) -> void:
	if _state != "closed" and _state != "closing":
		_incoming.append(msg)


func poll(delta: float) -> void:
	if _state == "closed":
		return
	var dt = max(0.0, delta)
	_clock += dt
	var incoming = _incoming
	_incoming = []
	for msg in incoming:
		if _state == "closed" or _state == "closing":
			break
		_receive(msg)
	if _state == "welcomed" and _clock >= 10.0:
		_terminal("Full tier join timed out")
	if _state in ["welcomed", "lobby", "loading", "run", "results"] and _clock >= _next_probe:
		_next_probe = _clock + 1.0
		_probe += 1
		_rpc("Net", "_rtt_ping", [_probe, 0.0], false)
	if _state == "run":
		_run.step(min(dt, 0.25))
		_queue.append_array(_run.take_messages())
		if _run.finished:
			_state = "results"
			_finish_at = _clock + RESULTS_DELAY
			_ready = false
			_vote = ""
			_push_roster()
	if _state == "results" and _clock >= _finish_at:
		_state = "lobby"
		_run = null
		if _ready or _pending_start:
			_start()
	var messages = _queue
	_queue = []
	for msg in messages:
		if _state == "closed":
			return
		emit_signal("message", msg)
	if _state == "closing" and _clock >= _close_at:
		var reason = _close_reason
		close()
		emit_signal("closed", 1000, reason)


func close() -> void:
	level_unloaded()
	_run = null
	_state = "closed"
	_close_reason = ""
	you = 0
	_queue = []
	_incoming = []
	_profile = {}
	_ready = false
	_vote = ""
	_pending_start = false


func level_ready(map_id: String, level_root: Spatial, _world: Node) -> void:
	if _state == "loading" and _run.map_id == map_id and is_instance_valid(level_root) and level_root.is_inside_tree():
		_run.attach(level_root)


func level_unloaded() -> void:
	if _run != null:
		_run.detach()
	if _state == "run":
		_state = "loading"


func _receive(msg: Dictionary) -> void:
	var kind = msg.get("t")
	if typeof(kind) != TYPE_STRING:
		_error("Expected JSON object with string 't'")
		return
	match kind:
		"leave":
			close()
		"ping":
			var ms = msg.get("ms")
			if _number(ms):
				var value = int(ms) if ms == floor(ms) and abs(ms) < 9.22e18 else ms
				_queue.append({"t": "pong", "ms": value})
		"rpc":
			_receive_rpc(msg)
		"raw":
			if typeof(msg.get("data")) != TYPE_STRING:
				_error("Invalid raw message (expected base64 'data')")
		_:
			_error("Unknown message type '%s'" % kind)


func _receive_rpc(msg: Dictionary) -> void:
	var node = msg.get("node")
	var method = msg.get("method")
	var args = msg.get("args", [])
	if typeof(node) != TYPE_STRING or typeof(method) != TYPE_STRING or typeof(args) != TYPE_ARRAY:
		_error("Invalid rpc fields (expected node:String, method:String, args:Array)")
		return
	node = _relative(node)
	var pattern = node
	if node != "Net" and not (node == "WeatherManager" or node == "GameManager" or node.begins_with("GameManager/")):
		if _run == null or not (_state in ["run", "loading", "results"]):
			return
		pattern = _run.node_pattern(node)
	var methods = _requests.get(pattern)
	if methods == null:
		return
	if not methods.has(method):
		_error("Unknown RPC method '%s' on %s" % [method, node])
		return
	var signature = methods[method]
	if typeof(signature) != TYPE_ARRAY or not _valid(args, signature):
		return
	var defaults = signature[1]
	if args.size() < signature[0].size():
		var missing = signature[0].size() - args.size()
		args = args + defaults.slice(defaults.size() - missing, defaults.size() - 1)
	if node == "Net":
		_net(method, args)
	elif _state == "run":
		_run.request(node, method, args)


func _valid(args: Array, signature: Array) -> bool:
	var types = signature[0]
	if args.size() > types.size() or args.size() < types.size() - signature[1].size():
		return false
	for i in range(args.size()):
		var val = args[i]
		match types[i]:
			"int":
				if not _number(val) or val != floor(val) or abs(val) >= 9.22e18:
					return false
			"float":
				if not _number(val):
					return false
			"bool":
				if typeof(val) != TYPE_BOOL:
					return false
			"String":
				if typeof(val) != TYPE_STRING:
					return false
			"Array":
				if typeof(val) != TYPE_ARRAY and not (val == null and i == types.size() - 1):
					return false
			"NodePath":
				if typeof(val) != TYPE_NODE_PATH:
					return false
			"Vector3":
				if typeof(val) != TYPE_VECTOR3 or not _number(val.x) or not _number(val.y) or not _number(val.z):
					return false
	return true


func _net(method: String, args: Array) -> void:
	if method == "_rtt_pong":
		return
	if _state == "welcomed":
		if method == "_hello":
			_join(args[0], int(args[1]))
		return
	match method:
		"_report_in_run":
			if args[0] and _state == "loading" and _run.attached():
				_state = "run"
				_run.catch_up()
			elif not args[0] and _state == "run":
				level_unloaded()
		"_request_chat":
			var line = _clean(args[0], 100)
			if line != "" and _clock - _last_chat >= 0.7:
				_last_chat = _clock
				_rpc("Net", "_chat_rpc", [_profile.name, line])
	if not (_state in ["lobby", "results"]):
		return
	match method:
		"_request_map_vote":
			if args[0] == "random" or _markers.has(args[0]):
				_vote = args[0]
				_push_roster()
		"_request_ready":
			_ready = args[0]
			_push_roster()
			if _ready and _state == "lobby":
				_start()
		"_request_force_start":
			if _state == "lobby":
				_start()
			else:
				_pending_start = true
		"_request_name":
			var name = _clean(args[0], 18)
			if not name.empty():
				_profile.name = name
				_push_roster()
		"_request_cosmetic":
			_cosmetics(args[0], args[1], args[2])
			_push_roster()


func _join(hello: String, version: int) -> void:
	if version != GAME_PROTOCOL:
		_close_reason = "UPDATE REQUIRED (v%d, YOU HAVE v%d)" % [GAME_PROTOCOL, version]
		_rpc("Net", "_reject", [_close_reason])
		_state = "closing"
		_close_at = _clock + 0.5
		return
	var parsed = JSON.parse(hello)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return
	var profile = parsed.result
	var name = _clean(profile.get("name"), 32)
	_profile = {"name": "PLAYER" if name.empty() else name, "ready": false, "color": 0, "skin": 0}
	_cosmetics(profile.get("color", 0), profile.get("skin", 0), profile.get("colors", []))
	_state = "lobby"
	_push_roster()


func _cosmetics(color, skin, allowed) -> void:
	color = posmod(int(color), 10) if _number(color) else 0
	skin = posmod(int(skin), 5) if _number(skin) else 0
	var unlocked = []
	if typeof(allowed) == TYPE_ARRAY:
		for value in allowed:
			if _number(value) and value == floor(value) and value >= 0 and value < 10:
				unlocked.append(int(value))
	_profile.color = color if unlocked.empty() or color in unlocked else unlocked[0]
	_profile.skin = skin


func _push_roster() -> void:
	_profile.ready = _ready
	var counts = {}
	if _vote != "":
		counts[_vote] = 1
	_rpc("Net", "_push_roster", [{you: _profile.duplicate()}, DEFAULT_MAP, true, counts, _vote])


func _start() -> void:
	var selected = DEFAULT_MAP if _vote == "" else _vote
	if selected == "random":
		selected = _maps[_rng.randi_range(0, _maps.size() - 1)].id
	_pending_start = false
	_ready = false
	_push_roster()
	_run_id += 1
	_run = Run.new(_run_id, selected, you, _profile.name, _data, _markers[selected], _rng, clamp(int(max_alive), 1, 60))
	_state = "loading"
	_rpc("Net", "_start_run", [selected])


func _rpc(node: String, method: String, args: Array, reliable = true) -> void:
	_queue.append({"t": "rpc", "node": node, "method": method, "args": args, "ch": 0, "rel": reliable})


func _error(reason: String) -> void:
	_queue.append({"t": "error", "msg": reason})


func _terminal(reason: String) -> void:
	_error(reason)
	_state = "closing"
	_close_at = _clock
	_close_reason = reason


static func _relative(path: String) -> String:
	if path.begins_with("/root/"):
		return path.substr(6)
	return path.substr(1) if path.begins_with("/") else path


static func _number(value) -> bool:
	return (typeof(value) == TYPE_REAL or typeof(value) == TYPE_INT) and not is_nan(value) and not is_inf(value)


static func _clean(value, limit: int) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var cleaned = ""
	for i in range(min(value.length(), 512)):
		var c = value.ord_at(i)
		if c >= 32 and not (c >= 127 and c <= 159) and not (c >= 0x202a and c <= 0x202e) and not (c >= 0x2066 and c <= 0x2069):
			cleaned += value[i]
	return cleaned.replace("[", "(").replace("]", ")").strip_edges().substr(0, limit)


static func _read(path: String) -> Dictionary:
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return {}
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	return parsed.result if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY else {}
