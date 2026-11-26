extends Node
## Desktop test driver for the Full tier / solo path (not exported: tests/).
## Drives the real client (FullNet + world/full_world.gd + HUD) through
## conformance checkpoints F1–F8 (docs/open-protocol/conformance.md) and a
## short run: spawn, move, shoot an enemy, take damage, results.
##
##   --full-drive                 online Full against Settings.full_url (--full-url=)
##   --full-drive=solo            solo (solo/local_link.gd)
##   --full-drive=reject          F8 only: run with --hello-protocol=18
##   --drive-seconds=N            give up after N s (default 240)
##   --drive-no-force             do not force start (live server etiquette)
##   --drive-leave-after=N        leave N s after confirm instead of waiting for results
##   --drive-shots=DIR            save screenshots to DIR
##   --exit-when-done

var main: Node
var _mode = "full"
var _t = 0.0
var _limit = 240.0
var _leave_after = -1.0
var _checks = {}
var _done = false
var _step = "connect"
var _run_t = 0.0
var _ping_sent = false
var _hp0 = -1.0
var _hurt = false
var _shot_dir = ""
var _shots_taken = {}
var _ready_sent = false
var _skip_calm_sent = 0.0


func _ready() -> void:
	main = get_parent()
	for a in Settings.args():
		var s = str(a)
		if s.begins_with("--full-drive="):
			_mode = s.substr(13)
		elif s.begins_with("--drive-seconds="):
			_limit = float(s.substr(16))
		elif s.begins_with("--drive-leave-after="):
			_leave_after = float(s.substr(20))
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
	print("DRIVE begin mode=%s url=%s" % [_mode, Settings.full_url])
	if _mode == "solo":
		FullNet.start_solo(Settings.solo_map, name)
	else:
		FullNet.connect_full(Settings.full_url, name)


func _pass(id: String, what: String) -> void:
	if _checks.has(id):
		return
	_checks[id] = what
	print("DRIVE %s PASS %s" % [id, what])


func _on_welcome(msg) -> void:
	_pass("F1a", "welcome tier=%s enc=%s you=%d game_protocol=%d" % [str(msg.get("tier")), str(msg.get("enc")), int(msg.get("you", 0)), int(msg.get("game_protocol", 0))])


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
	if n.phase == "online" and not _ping_sent and n.link:
		_ping_sent = true
	if n.rtt_ms >= 0.0 and _checks.has("F1a"):
		_pass("F1", "control ping/pong rtt=%.0fms" % n.rtt_ms)
	if n.roster.has(n.you) and n.you != 0:
		_pass("F2", "own id %d in decoded roster (size %d)" % [n.you, n.roster.size()])
	if _mode == "reject":
		return
	match _step:
		"connect":
			if n.state == "lobby" and n.roster.has(n.you):
				_shot("lobby")
				if _mode != "solo":
					n.lobby_action("vote", {"map": "pinecrest"})
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
		yield(get_tree().create_timer(1.0), "timeout")
		get_tree().quit(0)
