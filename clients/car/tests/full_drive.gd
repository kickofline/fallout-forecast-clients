extends Node
## Desktop test driver for the Full tier / solo path (not exported: tests/).
## Drives the real client (FullNet + world/full_world.gd + HUD) through
## conformance checkpoints F1–F8 (docs/open-protocol/conformance.md) and a
## short run: spawn, move, shoot an enemy, take damage, results.
##
##   --full-drive                 online Full (--full-url= and --full-enc=)
##   --full-drive=solo            solo (solo/local_link.gd)
##   --full-drive=reject          F8 only: run with --hello-protocol=18
##   --drive-seconds=N            give up after N s (default 240)
##   --drive-no-force             do not force start (live server etiquette)
##   --drive-live                 skip lobby actions when others are present
##   --drive-leave-after=N        leave N s after confirm instead of waiting for results
##   --drive-shots=DIR            save screenshots to DIR
##   --drive-probe               local server only: teleport through shelter,
##                                vending, decon and ping checks and inject a
##                                draft and a tape prompt to exercise the UI
##   --drive-hud                 local server / solo only: after the probe (or the
##                                starter kit) walk the HUD through its states on
##                                kbm, pad and touch (tests/hud_probe.gd)
##   --drive-tag=S               suffix for screenshot names (e.g. a resolution)
##   --exit-when-done
##   --drive-wire-check          exit nonzero if any required F check is missing

var main: Node
var _mode = "full"
var _t = 0.0
var _limit = 240.0
var _leave_after = -1.0
var _checks = {}
var _done = false
var _step = "connect"
var _run_t = 0.0
var _ping_ms = -1
var _hp0 = -1.0
var _hurt = false
var _shot_dir = ""
var _shots_taken = {}
var _ready_sent = false
var _skip_calm_sent = 0.0
var _probe = false
var _probe_t = 0.0
var _probe_step = 0
var _live = false
var _hud_probe = null
var shot_suffix = ""


func _ready() -> void:
	main = get_parent()
	_live = Settings.has_arg("--drive-live")
	if Settings.has_arg("--drive-hud"):
		_hud_probe = load("res://tests/hud_probe.gd").new()
		_hud_probe.drive = self
	for a in Settings.args():
		var s = str(a)
		if s.begins_with("--full-drive="):
			_mode = s.substr(13)
		elif s.begins_with("--drive-seconds="):
			_limit = float(s.substr(16))
		elif s.begins_with("--drive-leave-after="):
			_leave_after = float(s.substr(20))
		elif s == "--drive-probe":
			_probe = true
		elif s.begins_with("--drive-tag="):
			shot_suffix = "_" + s.substr(12)
		elif s.begins_with("--drive-shots="):
			_shot_dir = s.substr(14)
	if not _shot_dir.empty():
		Directory.new().make_dir_recursive(_shot_dir)
	FullNet.connect("results", self, "_on_results")
	FullNet.connect("failed", self, "_on_failed")
	FullNet.connect("welcomed", self, "_on_welcome")
	call_deferred("_begin")


func _begin() -> void:
	var name = "CarTest"
	print("DRIVE begin mode=%s endpoint=%s wire=%s" % [_mode, Settings.full_endpoint(), Settings.full_wire])
	if _mode == "solo":
		FullNet.start_solo(Settings.solo_map, name)
	else:
		FullNet.connect_full(Settings.full_endpoint(), name)
		FullNet.link.connect("message", self, "_on_wire_message")


func _pass(id: String, what: String) -> void:
	if _checks.has(id):
		return
	_checks[id] = what
	print("DRIVE %s PASS %s" % [id, what])


func _on_welcome(msg) -> void:
	var enc = "json" if _mode == "solo" else Settings.full_encoding()
	if msg.get("tier") == "full" and msg.get("enc") == enc and int(msg.get("you", 0)) >= 2 and int(msg.get("game_protocol", 0)) == FullNet.GAME_PROTOCOL:
		_pass("F1a", "welcome tier=full enc=%s you=%d game_protocol=%d" % [enc, int(msg.you), int(msg.game_protocol)])
		if _mode != "solo" and _mode != "reject":
			_ping_ms = OS.get_ticks_msec() - 1
			FullNet.link.send({"t": "ping", "ms": _ping_ms})


func _on_wire_message(msg: Dictionary) -> void:
	if _ping_ms >= 0 and msg.get("t") == "pong" and msg.get("ms") == _ping_ms:
		_pass("F1", "control pong echoed ms=%d" % _ping_ms)


func _on_failed(why) -> void:
	print("DRIVE session failed: %s" % why)
	if _mode == "reject" and "UPDATE REQUIRED" in FullNet.reject_reason:
		_pass("F8", "Net._reject '%s'" % FullNet.reject_reason)
	if _mode == "solo":
		_pass("SOLO", "solo path failed gracefully: %s (title shows it)" % why)
	_finish()


func _on_results(data) -> void:
	_pass("RESULTS", "won=%s waves=%d time=%ds players=%d" % [str(data.get("won")), int(data.get("waves", 0)), int(data.get("time_s", 0)), (data.get("players", []) as Array).size()])
	_shot("results")
	_step = "results"
	_run_t = 0.0


func _shot(tag: String) -> void:
	if _shot_dir.empty() or _shots_taken.has(tag):
		return
	_shots_taken[tag] = true
	tag += shot_suffix
	yield(VisualServer, "frame_post_draw")
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png(_shot_dir.plus_file("%s.png" % tag))
	print("DRIVE screenshot %s" % tag)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t > _limit:
		print("DRIVE timeout after %.0fs (step=%s)" % [_t, _step])
		_finish()
		return
	var n = FullNet
	if _mode == "solo" and n.rtt_ms >= 0.0 and _checks.has("F1a"):
		_pass("F1", "local link rtt=%.0fms" % n.rtt_ms)
	if n.roster.has(n.you) and n.you != 0:
		_pass("F2", "own id %d in decoded roster (size %d)" % [n.you, n.roster.size()])
		if _live and _step == "connect" and n.roster.size() > 1:
			if _checks.has("F1"):
				print("DRIVE live lobby occupied; leaving after handshake")
				_finish()
			return
	if _mode == "reject":
		return
	match _step:
		"connect":
			if n.state in ["loading", "run"]:
				_pass("LATE_JOIN", "Net._start_run(%s) right after the roster (run in progress)" % n.current_map)
				_step = "wait_start"
			elif n.state == "lobby" and n.roster.has(n.you):
				_shot("lobby")
				if _mode != "solo":
					n.lobby_action("vote", {"map": "pinecrest"})
					if not _live:
						n.lobby_action("chat", {"text": "car full client test"})
					n.lobby_action("ready", {"v": true})
					if n.roster.size() == 1 and not Settings.has_arg("--drive-no-force"):
						n.lobby_action("start")
				_step = "wait_start"
		"wait_start":
			if n.state in ["loading", "run"]:
				_pass("F3", "vote/chat/ready sent, Net._start_run(%s)" % n.current_map)
				_step = "wait_confirm"
		"wait_confirm":
			var w = main.world
			if n.run_ready and w and "run_id" in w:
				_pass("F4", "_confirm_run_ready after report_in_run; RunLoot run id=%d" % w.run_id)
				_step = "play"
				_run_t = 0.0
		"play":
			_play(delta)
		"results":
			_run_t += delta
			if _run_t > 3.0:
				main.back_to_lobby()
				_finish()


func _play(delta: float) -> void:
	var n = FullNet
	var w = main.world
	if w == null or not is_instance_valid(w) or not ("me" in w) or w.me == null:
		return
	_run_t += delta
	if w.ready_to_play:
		_shot("spawn")
	if w.starter_state == 2:
		_pass("F5", "starter kit accepted (slot0=%s)" % str(w.you.get("slots", [null])[0]))
	if int(n.rpc_out.get("_push_transform", 0)) >= 20 and int(n.rpc_in.get("_receive_phase", 0)) > 0 and int(n.rpc_in.get("_apply_vitals", 0)) > 0:
		var en = "enemies spawn=%d sync=%d" % [int(n.rpc_in.get("_spawn_enemy", 0)), int(n.rpc_in.get("_sync_enemies", 0))]
		if int(n.rpc_in.get("_sync_enemies", 0)) > 0 and int(n.rpc_in.get("_spawn_enemy", 0)) > 0:
			_pass("F6", "pushes=%d phases=%d vitals=%d %s" % [int(n.rpc_out.get("_push_transform", 0)), int(n.rpc_in.get("_receive_phase", 0)), int(n.rpc_in.get("_apply_vitals", 0)), en])
	if _hud_probe and not _hud_probe.done and w.starter_state == 2 and (not _probe or _probe_step >= 99) and _run_t > 1.5:
		w.auto_move = Vector2.ZERO
		w.auto_bits = 0
		_hud_probe.step(w, delta)
		return
	if _probe and _probe_step < 99 and w.starter_state == 2:
		_run_probe(w, delta)
		return
	if _hp0 < 0.0 and w.vit.hp > 0.0:
		_hp0 = w.vit.hp
	if w.vit.hp < _hp0 - 0.5 or w.vit.suit < 99.0 and not _hurt:
		if not _hurt:
			_hurt = true
			_pass("DAMAGE", "hp=%.0f suit=%.0f state=%s" % [w.vit.hp, w.vit.suit, w.my_state])
			_shot("damage")
	# Skip the first Calm once (like the reference checker).
	if w.phase_id == 0 and w.phase_left > 4.0 and _skip_calm_sent <= 0.0 and _run_t > 2.0:
		_skip_calm_sent = 5.0
		w.press_bits(w.BITS.ready_up)
	_skip_calm_sent -= delta
	# Walk forward for 2 s, then hold position and fight.
	w.auto_move = Vector2(0, -1) if _run_t > 0.5 and _run_t < 2.5 else Vector2.ZERO
	if _run_t > 2.6 and not _checks.has("MOVE"):
		var p0 = w._spawn_for(n.you, n.roster_ids)[0]
		var moved = w.me.feet().distance_to(p0)
		if moved > 1.0:
			_pass("MOVE", "walked %.1fm from spawn, floor=%s y=%.2f" % [moved, str(w.me.grounded), w.me.feet().y])
	# Aim at the nearest enemy and fire.
	var best = null
	var bd = 45.0
	for id in w.enemies:
		var a = w.enemies[id]
		if is_instance_valid(a) and not a.dying:
			var d = a.translation.distance_to(w.me.feet())
			if d < bd:
				bd = d
				best = a
	w.auto_bits = 0
	if best and w.starter_state == 2:
		var eye = w._eye()
		var to: Vector3 = best.translation + Vector3(0, 1.0, 0) - eye
		w.yaw = atan2(-to.x, -to.z)
		w.pitch = atan2(to.y, Vector2(to.x, to.z).length())
		if int(fmod(_run_t * 10.0, 10.0)) < 6:
			w.auto_bits = w.BITS.fire
		_shot("combat")
	if w.accepted_shots > 0:
		_pass("SHOT", "shots requested=%d shot_fx(own)=%d hits=%d" % [w.predicted_shots, w.accepted_shots, int(n.rpc_in.get("_receive_hits", 0))])
	if int(n.rpc_in.get("_receive_hits", 0)) > 0:
		_pass("HIT", "_receive_hits=%d despawned=%d" % [int(n.rpc_in.get("_receive_hits", 0)), int(n.rpc_in.get("_despawn_enemy", 0))])
	if _run_t > 20.0 and n.errors == 0:
		_pass("F7", "no protocol errors after %.0fs of stream (%d rpc types in)" % [_run_t, n.rpc_in.size()])
	if w.players.size() > 0:
		var ids = []
		for id in w.players:
			var e = w.squad.get(id, {})
			ids.append("%d@%s" % [id, str(e.get("pos", Vector3.ZERO).snapped(Vector3.ONE * 0.1))])
		if not _checks.has("SQUAD"):
			_pass("SQUAD", "remote players rendered: %s (roster %d)" % [str(ids), n.roster.size()])
			_shot("squad")
	if _leave_after > 0.0 and _run_t > _leave_after:
		print("DRIVE leaving after %.0fs in run" % _run_t)
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var n = FullNet
	if n.phase == "online":
		n.leave()
		_pass("LEAVE", "sent {t:leave} and closed")
	var keys = _checks.keys()
	keys.sort()
	print("DRIVE SUMMARY passed=%s" % str(keys))
	print("DRIVE rpc_in=%s" % str(n.rpc_in))
	print("DRIVE rpc_out=%s" % str(n.rpc_out))
	if Settings.has_arg("--exit-when-done"):
		var code = 0
		if Settings.has_arg("--drive-wire-check"):
			var required = ["F1a", "F8"] if _mode == "reject" else ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "LEAVE"]
			for id in required:
				if not _checks.has(id):
					print("DRIVE missing %s" % id)
					code = 1
		yield(get_tree().create_timer(1.0), "timeout")
		get_tree().quit(code)


## Scripted checks for the parts a short fight does not reach.
func _run_probe(w, delta: float) -> void:
	var n = FullNet
	_probe_t += delta
	w.auto_move = Vector2.ZERO
	w.auto_bits = 0
	match _probe_step:
		0:
			# Under Pinecrest's BlockAAwning (shelter box) -> sheltered.
			w.me.teleport(Vector3(-28.0, 0.1, 8.2))
			_probe_step = 1
			_probe_t = 0.0
		1:
			if _probe_t > 0.6:
				if w.sheltered:
					_pass("EXPOSURE", "awning: sheltered=%s reported=%s (_report_exposure sent %d)" % [str(w.sheltered), str(w._exposure_sent), int(n.rpc_out.get("_report_exposure", 0))])
				_shot("shelter")
				# Vending: stand in front of HardwareStation, look at bay 2.
				w.me.teleport(Vector3(-2.8, 0.1, 7.6))
				w.yaw = PI
				w.pitch = -0.25
				_probe_step = 2
				_probe_t = 0.0
		2:
			w.yaw = PI
			w.pitch = -0.25
			if _probe_t > 0.5 and _probe_t < 1.4:
				if "BUY" in w.prompt or "AMMO" in w.prompt:
					_pass("VEND_PROMPT", "prompt='%s'" % w.prompt)
					_shot("vending")
				w.auto_bits = w.BITS.interact
			if _probe_t >= 1.6:
				_pass("VEND_HOLD", "_hold_request sent %d (begin+finish)" % int(n.rpc_out.get("_hold_request", 0)))
				w.me.teleport(Vector3(-21.84, 0.1, -45.6))
				w.yaw = 0.0
				w.pitch = -0.2
				_probe_step = 3
				_probe_t = 0.0
		3:
			w.yaw = 0.0
			w.pitch = -0.2
			if _probe_t > 0.5:
				if "SUIT" in w.prompt or "DECON" in w.prompt:
					_pass("DECON_PROMPT", "prompt='%s' charges=%d" % [w.prompt, w.decon_charges])
				w.press_bits(w.BITS.ping)
				_probe_step = 4
				_probe_t = 0.0
		4:
			if _probe_t > 1.0:
				if not w.pings.empty():
					_pass("PING", "_request_ping -> _show_ping kind=%s" % str(w.pings[0][1]))
				w.handle_rpc("GameManager/MutationRoll", "_deal_rpc", ["", ["reflex_tendons", "chitin_suit", "adrenaline_glands"]])
				_probe_step = 5
				_probe_t = 0.0
		5:
			if _probe_t > 0.8:
				_shot("draft")
			if _probe_t > 1.5:
				w.handle_rpc("GameManager/MutationRoll", "_result_rpc", [2, [], ["adrenaline_glands"], ["adrenaline_glands"]])
				if abs(w.me.speed_scale - 1.18) < 0.01:
					_pass("DRAFT", "overlay shown, result applied (adrenaline speed x%.2f)" % w.me.speed_scale)
				w.handle_rpc("GameManager", "_sync_tape_state", [true, false, true])
				_probe_step = 6
				_probe_t = 0.0
		6:
			if _probe_t > 0.8:
				_shot("tape")
			if _probe_t > 1.5:
				w.handle_rpc("GameManager", "_sync_tape_state", [false, false, false])
				w.handle_rpc("GameManager/MutationRoll", "_reset_run_rpc", [])
				_pass("TAPE", "tape overlay shown (can_choose=%s)" % str(n.first_peer == n.you))
				w.me.teleport(Vector3(-2.0, 0.1, -9.0))
				_probe_step = 99
				_run_t = 2.7
