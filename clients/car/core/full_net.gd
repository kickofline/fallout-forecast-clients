extends Node
## Full-tier session (autoload `FullNet`): Open Protocol handshake, the game
## handshake (Net._hello), roster/lobby, RTT answers and the run lifecycle of
## spec-full.md §5. The session talks to a FullLink for WebSocket, TCP or solo.
##
## It exposes the same surface as the Thin `Net` autoload (phase, state,
## lobby, maps, signals, lobby_action, choose, leave) so the shared screens and
## HUD work for both tiers. UI code picks the active one with FullNet.current().
##
## Run RPCs (anything not on node "Net") go to the registered run world
## (world/full_world.gd). Between Net._start_run and the world registering
## they are queued; after GameManager._finish they are dropped until the next
## _start_run (KNOWN_ISSUES §3).

signal phase_changed(phase)
signal welcomed(data)
signal status_changed(state, msg)
signal lobby_updated(data)
signal load_requested(map_id)
signal results(data)
signal failed(msg)
signal draft(data)
signal draft_done
signal tape(data)
signal events(list)
signal roster_changed(roster)

const GAME_PROTOCOL = 19
const CLIENT = "fallout-car/0.2"
const JOIN_DEADLINE = 10.0
const WsLink = preload("res://core/ws_full_link.gd")
const TcpLink = preload("res://core/tcp_full_link.gd")
const LocalLink = preload("res://solo/local_link.gd")
const Loadout = preload("res://core/loadout.gd")
const GAME_DATA = "res://data/game_data.json"

## true once the user picked CLOUD FULL / SOLO (until they pick Thin again).
var active = false
var mode = "full"                # "full" | "solo"
var phase = "offline"            # offline | connecting | online
var state = "disconnected"       # disconnected | joining | lobby | loading | run | results
var status_msg = ""
var you = 0
var maps = []
var lobby = {}
var last_error = ""
var rtt_ms = -1.0
var server_rtt = -1.0
var current_map = ""
var roster = {}                  # int peer id -> {name, ready, color, skin}
var roster_ids = []              # ascending
var first_peer = 0               # first roster key (tape chooser)
var default_map = ""
var my_vote = ""
var vote_counts = {}
var chat = []
var run_ready = false
var finished = false
var run_count = 0
var data = {}                    # res://data/game_data.json
var items = {}                   # id -> game_data item
var player_mutations = {}        # id -> {name, desc, color}
var enemy_mutations = {}

var link
var world                        # registered run world (world/full_world.gd)
var _url = ""
var _name = ""
var _solo_map = ""
var _join_left = -1.0
var _pending = []
var _reported_in = false
var _ping_left = 0.0
var _solo_started = false
var _ready_flag = false
var rpc_in = {}                  # method -> count (debug / conformance log)
var errors = 0                   # non-terminal server error messages this session
var reject_reason = ""
var rpc_out = {}


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	var f = File.new()
	if f.open(GAME_DATA, File.READ) == OK:
		var p = JSON.parse(f.get_as_text())
		f.close()
		if p.error == OK and p.result is Dictionary:
			data = p.result
	for it in data.get("items", []):
		if it is Dictionary:
			items[str(it.get("id", ""))] = it
	for m in data.get("player_mutations", []):
		if m is Dictionary:
			player_mutations[str(m.get("id", ""))] = m
	for m in data.get("enemy_mutations", []):
		if m is Dictionary:
			enemy_mutations[str(m.get("id", ""))] = m


## The session the UI should read: this one while a Full/Solo mode is
## selected, else the Thin `Net` autoload.
func current() -> Node:
	return self if active else Net


func item(id: String) -> Dictionary:
	return items.get(id, {})


func is_online() -> bool:
	return phase == "online"


# ------------------------------------------------------------------ connect
func connect_full(url: String, player_name: String) -> void:
	mode = "full"
	_url = url
	var tcp = url.begins_with("tcp://") or Settings.full_uses_tcp()
	_start(TcpLink.new(url) if tcp else WsLink.new(url), player_name, "")


func start_solo(map_id: String, player_name: String) -> void:
	mode = "solo"
	_start(LocalLink.new(), player_name, map_id)


func _start(new_link, player_name: String, solo_map: String) -> void:
	if link:
		link.close()
	_drop_link()
	active = true
	_name = player_name.strip_edges()
	if _name.empty():
		_name = "Honda"
	_solo_map = solo_map
	_solo_started = false
	last_error = ""
	you = 0
	roster = {}
	roster_ids = []
	chat = []
	my_vote = ""
	vote_counts = {}
	lobby = {}
	rtt_ms = -1.0
	run_ready = false
	finished = false
	_pending = []
	_reported_in = false
	_ready_flag = false
	rpc_in = {}
	rpc_out = {}
	errors = 0
	reject_reason = ""
	link = new_link
	if "no_thread" in link:
		link.no_thread = Settings.has_arg("--net-no-thread")
	link.connect("message", self, "_on_message")
	link.connect("closed", self, "_on_closed")
	state = "joining"
	status_msg = "SOLO" if mode == "solo" else ""
	_set_phase("connecting")
	link.open({"v": 1, "tier": "full", "enc": "json" if link.is_local() else Settings.full_encoding(), "client": CLIENT})


func _exit_tree() -> void:
	if link:
		link.close()


func leave() -> void:
	if link:
		print("FULL leave (state=%s)" % state)
		link.close()
	_drop_link()
	state = "disconnected"
	_set_phase("offline")
	emit_signal("status_changed", state, "")


func _drop_link() -> void:
	if world and is_instance_valid(world):
		world = null
	if link:
		if link.is_connected("message", self, "_on_message"):
			link.disconnect("message", self, "_on_message")
		if link.is_connected("closed", self, "_on_closed"):
			link.disconnect("closed", self, "_on_closed")
	link = null
	_join_left = -1.0


func _fail(why: String) -> void:
	last_error = why.to_upper()
	print("FULL failed: %s" % last_error)
	if link:
		link.close()
	_drop_link()
	state = "disconnected"
	_set_phase("offline")
	emit_signal("failed", last_error)


func _on_closed(code: int, reason: String) -> void:
	var why = reason.strip_edges()
	if code >= 0:
		why = "CLOSED %d%s" % [code, (" - " + why) if not why.empty() else ""]
	_fail(why if not why.empty() else "SIGNAL LOST")


func _set_phase(p: String) -> void:
	if p != phase:
		phase = p
		emit_signal("phase_changed", p)


func _process(delta: float) -> void:
	if link == null:
		return
	var _pt = OS.get_ticks_usec()
	link.poll(delta)
	Settings.prof_add("net", OS.get_ticks_usec() - _pt)
	if link == null:
		return
	if _join_left >= 0.0:
		_join_left -= delta
		if _join_left < 0.0:
			_fail("NO ROSTER (SOLO AUTHORITY NOT READY)" if mode == "solo" else "JOIN TIMED OUT (NO ROSTER)")
			return
	if phase == "online" and not link.is_local():
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = 2.0
			link.send({"t": "ping", "ms": OS.get_ticks_msec()})


# ------------------------------------------------------------------ send
## Send an RPC. Run-scoped RPCs (not on "Net") are dropped before
## Net._confirm_run_ready and after _finish (spec-full §5 gate).
func rpc_send(node: String, method: String, args := [], reliable := true) -> bool:
	if link == null:
		return false
	if node != "Net" and (not run_ready or finished):
		return false
	link.send({"t": "rpc", "node": node, "method": method, "args": args, "rel": reliable})
	rpc_out[method] = int(rpc_out.get(method, 0)) + 1
	return true


func me_path() -> String:
	return "Main/Players/P_%d" % you


func holder_path() -> String:
	return "Main/Players/P_%d/Head/Camera3D/WeaponHolder" % you


# ------------------------------------------------------------------ receive
func _on_message(msg: Dictionary) -> void:
	var t = str(msg.get("t", ""))
	match t:
		"welcome":
			_on_welcome(msg)
		"error":
			# After welcome, Full errors for bad frames are non-terminal (§11).
			var m = str(msg.get("msg", "ERROR"))
			print("FULL server error: %s" % m)
			errors += 1
			if phase != "online":
				_fail(m)
		"pong":
			var sample = OS.get_ticks_msec() - float(msg.get("ms", 0))
			rtt_ms = sample if rtt_ms < 0.0 else lerp(rtt_ms, sample, 0.25)
		"ping":
			link.send({"t": "pong", "ms": msg.get("ms", 0)})
		"rpc":
			var method = str(msg.get("method", ""))
			rpc_in[method] = int(rpc_in.get(method, 0)) + 1
			var _t = OS.get_ticks_usec()
			if str(msg.get("node", "")) == "Net":
				_on_net_rpc(method, msg.get("args", []), msg.get("rtt_answered", false))
			else:
				_route(msg)
			Settings.prof_add("n_rpc", OS.get_ticks_usec() - _t)


func _on_welcome(msg: Dictionary) -> void:
	you = int(msg.get("you", 0))
	maps = msg.get("maps", []) if msg.get("maps") is Array else []
	var gp = int(msg.get("game_protocol", -1))
	print("FULL welcome you=%d tier=%s enc=%s game_protocol=%d maps=%d" % [you, str(msg.get("tier", "")), str(msg.get("enc", "")), gp, maps.size()])
	if str(msg.get("tier", "full")) != "full":
		_fail("SERVER DID NOT ACCEPT TIER FULL")
		return
	if gp != GAME_PROTOCOL:
		_fail("UPDATE REQUIRED (SERVER v%d, CLIENT v%d)" % [gp, GAME_PROTOCOL])
		return
	_set_phase("online")
	emit_signal("welcomed", msg)
	var hello = {"name": _name.substr(0, 32), "color": int(Settings.suit_color), "skin": int(Settings.suit_skin), "colors": Loadout.unlocked_colors()}
	var proto = GAME_PROTOCOL
	for a in Settings.args():
		if str(a).begins_with("--hello-protocol="):  # test switch (conformance F8)
			proto = int(str(a).substr(17))
	link.send({"t": "rpc", "node": "Net", "method": "_hello", "args": [to_json(hello), proto], "rel": true})
	_join_left = JOIN_DEADLINE
	status_msg = "JOINING SQUAD"
	emit_signal("status_changed", state, status_msg)


func _on_net_rpc(method: String, args: Array, rtt_answered := false) -> void:
	match method:
		"_rtt_ping":
			if args.size() >= 1:
				if not rtt_answered:
					link.send({"t": "rpc", "node": "Net", "method": "_rtt_pong", "args": [int(args[0])], "rel": false, "mode": 0})
				if args.size() >= 2:
					server_rtt = float(args[1])
					if link.is_local() or rtt_ms < 0.0:
						rtt_ms = server_rtt
		"_push_roster":
			_on_roster(args)
		"_reject":
			reject_reason = str(args[0]) if args.size() > 0 else "REJECTED"
			print("FULL rejected: %s" % reject_reason)
			_fail(reject_reason)
		"_chat_rpc":
			if args.size() >= 2:
				chat.append({"from": str(args[0]), "text": str(args[1])})
				while chat.size() > 30:
					chat.pop_front()
				_build_lobby()
		"_start_run":
			_on_start_run(str(args[0]) if args.size() > 0 else "")
		"_confirm_run_ready":
			_on_confirm()


func _on_roster(args: Array) -> void:
	if args.empty() or not (args[0] is Dictionary):
		return
	var was_joined = roster.has(you)
	roster = args[0]
	roster_ids = []
	first_peer = 0
	for k in roster:
		if first_peer == 0:
			first_peer = int(k)
		roster_ids.append(int(k))
	roster_ids.sort()
	default_map = str(args[1]) if args.size() > 1 else ""
	vote_counts = args[3] if args.size() > 3 and args[3] is Dictionary else {}
	my_vote = str(args[4]) if args.size() > 4 and args[4] != null else ""
	if roster.has(you):
		_join_left = -1.0
		_ready_flag = bool(roster[you].get("ready", false))
		if not was_joined:
			print("FULL joined roster size=%d first=%d" % [roster.size(), first_peer])
			if state == "joining":
				state = "lobby"
				status_msg = ""
				emit_signal("status_changed", state, status_msg)
	_build_lobby()
	emit_signal("roster_changed", roster)
	if world and is_instance_valid(world):
		world.on_roster(roster_ids, roster)
	if mode == "solo" and not _solo_started and roster.has(you) and state == "lobby":
		_solo_started = true
		if not _solo_map.empty():
			rpc_send("Net", "_request_map_vote", [_solo_map])
		rpc_send("Net", "_request_force_start", [])


func _build_lobby() -> void:
	var players = []
	for k in roster:
		var r = roster[k]
		if r is Dictionary:
			players.append({"id": int(k), "name": str(r.get("name", "PLAYER")), "ready": bool(r.get("ready", false)),
				"vote": my_vote if int(k) == you else null, "car": int(k) == you, "color": int(r.get("color", 1)),
				"skin": int(r.get("skin", 0))})
	lobby = {"players": players, "chat": chat, "vote_counts": vote_counts, "maps": maps}
	emit_signal("lobby_updated", lobby)


func _on_start_run(map_id: String) -> void:
	print("FULL start_run map=%s (state=%s)" % [map_id, state])
	if world and is_instance_valid(world):
		unregister_world(world)
	current_map = map_id
	run_ready = false
	finished = false
	_pending = []
	_reported_in = false
	run_count += 1
	state = "loading"
	status_msg = ""
	emit_signal("status_changed", state, status_msg)
	emit_signal("load_requested", map_id)


func _on_confirm() -> void:
	print("FULL confirm_run_ready (pending=%d)" % _pending.size())
	run_ready = true
	state = "run"
	if world and is_instance_valid(world):
		world.on_run_ready()
	emit_signal("status_changed", state, "")


func _route(msg: Dictionary) -> void:
	if str(msg.method) == "_finish" and str(msg.node) == "GameManager":
		var a: Array = msg.get("args", [])
		on_finish(bool(a[0]) if a.size() > 0 else false, a[1] if a.size() > 1 and a[1] is Dictionary else {})
		return
	if finished or state in ["lobby", "joining", "results", "disconnected"]:
		return
	if world and is_instance_valid(world):
		world.handle_rpc(str(msg.node), str(msg.method), msg.get("args", []))
	elif state in ["loading", "run"]:
		_pending.append(msg)


## Called by the run world once the level, its physics and every player
## entity exist (spec-full §5 step 3).
func register_world(w: Node, map_id: String, level_root: Spatial) -> void:
	world = w
	if link:
		link.level_ready(map_id, level_root, w)
	if not _reported_in:
		_reported_in = true
		rpc_send("Net", "_report_in_run", [true])
		print("FULL report_in_run(true) map=%s" % map_id)
	w.on_roster(roster_ids, roster)
	var q = _pending
	_pending = []
	for m in q:
		w.handle_rpc(str(m.node), str(m.method), m.get("args", []))
	if run_ready:
		w.on_run_ready()


## Called when the run world is freed (results, leave, new run).
func unregister_world(w: Node) -> void:
	if world != w:
		return
	world = null
	if link:
		link.level_unloaded()
	if _reported_in and phase == "online":
		_reported_in = false
		rpc_send("Net", "_report_in_run", [false])
		print("FULL report_in_run(false)")
	run_ready = false


## GameManager._finish (forwarded by the world, or handled here when no
## world is up yet).
func on_finish(won: bool, res: Dictionary) -> void:
	if finished:
		return
	finished = true
	run_ready = false
	print("FULL finish won=%s" % str(won))
	var players = []
	var kills = 0
	var pl = res.get("players", {})
	if pl is Dictionary:
		for k in pl:
			var p = pl[k]
			if p is Dictionary:
				kills += int(p.get("kills", 0))
				players.append({"name": str(p.get("name", "")), "kills": int(p.get("kills", 0)),
					"downs": int(p.get("turned", 0)), "revives": int(p.get("revives", 0)), "weapon": str(p.get("weapon", ""))})
	var out = {"won": won, "time_s": int(res.get("seconds", 0)), "waves": int(res.get("waves", 0)), "kills": kills,
		"score": int(res.get("endless_score", 0)), "players": players, "map": str(res.get("map_id", current_map)),
		"mutations": res.get("squad_mutations", [])}
	state = "results"
	emit_signal("status_changed", state, "")
	emit_signal("results", out)


## Back in the lobby UI after results.
func back_to_lobby() -> void:
	if state == "results":
		state = "lobby"
		emit_signal("status_changed", state, "")


# ------------------------------------------------------------------ lobby API (Thin Net-compatible)
func lobby_action(action: String, extra := {}) -> void:
	match action:
		"vote":
			my_vote = str(extra.get("map", ""))
			rpc_send("Net", "_request_map_vote", [my_vote])
		"ready":
			_ready_flag = bool(extra.get("v", true))
			rpc_send("Net", "_request_ready", [_ready_flag])
		"start":
			rpc_send("Net", "_request_force_start", [])
		"chat":
			rpc_send("Net", "_request_chat", [str(extra.get("text", "")).substr(0, 100)])
		"cosmetic":
			rpc_send("Net", "_request_cosmetic", [int(Settings.suit_color), int(Settings.suit_skin), Loadout.unlocked_colors()])


## Draft / tape choices from the HUD overlays.
func choose(kind: String, index: int) -> void:
	match kind:
		"mutation":
			rpc_send("GameManager/MutationRoll", "_request_vote", [index])
		"tape":
			rpc_send("GameManager", "_request_tape_choice", [index == 0])


func emit_events(list: Array) -> void:
	emit_signal("events", list)
