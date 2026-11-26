extends Reference
## HUD parity probe for tests/full_drive.gd (--drive-hud, local server or
## solo only: it injects host RPCs into the world). Walks the HUD through
## its states on kbm, pad and touch, checks what each shows and saves a
## screenshot per state through the driver (`--drive-shots=DIR`).

const FAKE_MATE = 990001
const FAKE_MINI = 990002

var drive: Node
var _i = 0
var _t = 0.0
var _phase0 = []
var results = {}
var done = false
var _shot_taken = false
var _downed_prompt = ""
var _out_label = ""

# [tag, seconds, device]
const STEPS = [
	["hud_kbm", 1.2, "kbm"],
	["hud_boss", 0.9, "kbm"],
	["hud_boss_core", 0.9, "kbm"],
	["hud_downed", 0.9, "pad"],
	["hud_out", 0.9, "kbm"],
	["hud_pad_draft", 1.0, "pad"],
	["hud_pad_tape", 1.0, "pad"],
	["hud_scoreboard", 0.8, "kbm"],
	["hud_loadout", 1.0, "pad"],
	["hud_chat", 0.9, "kbm"],
	["hud_pause", 0.9, "pad"],
	["hud_touch_countdown", 1.0, "touch"],
	["hud_wavecard", 0.6, "kbm"],
]


func step(w, delta: float) -> void:
	if done:
		return
	var hud = drive.main.hud
	if _i >= STEPS.size():
		_cleanup(w, hud)
		done = true
		return
	var spec = STEPS[_i]
	if _t == 0.0:
		Controls.set_device(spec[2])
		_enter(spec[0], w, hud)
	_t += delta
	_hold(spec[0], w, hud)
	if _t >= spec[1] and not _shot_taken:
		_shot_taken = true
		_check(spec[0], w, hud)
		drive._shot(spec[0])
	elif _shot_taken and _t >= spec[1] + 0.2:
		# Leave only after the screenshot frame has been drawn.
		_shot_taken = false
		_leave(spec[0], w, hud)
		_i += 1
		_t = 0.0


func _ahead(w, d: float) -> Vector3:
	return w.me.feet() + w._view_dir() * Vector3(1, 0, 1) * d


func _enter(tag: String, w, hud) -> void:
	match tag:
		"hud_kbm":
			_phase0 = [w.phase_id, w.wave, w.phase_left]
			var at = _ahead(w, 6.0)
			w.handle_rpc("Main/Players/P_%d" % FAKE_MATE, "_relay_transform", [at + Vector3(2, 0, 0), 0.0, 0.0, Vector3.ZERO])
			w.handle_rpc("Main/Players/P_%d" % FAKE_MATE, "_apply_vitals", [62.0, 48.0, "ok", 20.0, false, 100.0, 0.0, false])
			w.squad[FAKE_MATE].name = "Zed"
			w.handle_rpc("Main/Enemies", "_spawn_enemy", [FAKE_MINI, 1, _ahead(w, 14.0), false, true, 3])
			w.handle_rpc("Main/Enemies", "_sync_miniboss_hp", [FAKE_MINI, 420.0, 600.0])
			w._show_ping(FAKE_MATE, "enemy", _ahead(w, 14.0))
			FullNet._on_net_rpc("_chat_rpc", ["Zed", "regroup on me"])
			w.handle_rpc("GameManager/Feats", "_feat_event", ["first_blood", 1])
			hud._panels.popup("+5 SCRAP", Color("#ffc365"))
			hud._on_killed("")
			hud._on_killed("")
		"hud_boss":
			w.handle_rpc("Main/Enemies", "_despawn_enemy", [FAKE_MINI, [], Vector3.ZERO, Vector3.ZERO, false])
			w.handle_rpc("GameManager", "_spawn_boss", [_ahead(w, 30.0) + Vector3(0, 12, 0)])
			w.handle_rpc("Main/Enemies/BossCumulus", "_sync", [_ahead(w, 30.0) + Vector3(0, 12, 0), [540.0, 540.0, 540.0, 1400.0], 3, 0.0])
			w.handle_rpc("Main/Enemies/BossCumulus", "_sync", [_ahead(w, 30.0) + Vector3(0, 12, 0), [540.0, 210.0, 0.0, 1400.0], 2, 0.0])
			w.handle_rpc("Main/Players/P_%d" % FAKE_MATE, "_apply_vitals", [0.0, 30.0, "downed", 12.0, false, 100.0, 0.0, false])
		"hud_boss_core":
			w.handle_rpc("Main/Enemies/BossCumulus", "_sync", [_ahead(w, 30.0) + Vector3(0, 12, 0), [0.0, 0.0, 0.0, 640.0], 0, 2.0])
		"hud_pad_draft":
			w.handle_rpc("GameManager/MutationRoll", "_deal_rpc", ["armor", ["reflex_tendons", "chitin_suit", "adrenaline_glands"]])
		"hud_pad_tape":
			w.handle_rpc("GameManager/MutationRoll", "_result_rpc", [1, ["armor"], ["chitin_suit"], ["chitin_suit"]])
			w.handle_rpc("GameManager", "_sync_tape_state", [true, false, true])
		"hud_scoreboard":
			Controls.touch_hold("scoreboard", true)
		"hud_loadout":
			hud.open_modal("loadout")
		"hud_chat":
			hud.open_modal("chat")
		"hud_pause":
			hud.toggle_menu()
		"hud_touch_countdown":
			w.handle_rpc("WeatherManager", "_receive_phase", [0, w.wave, 4.4])
		"hud_wavecard":
			w.handle_rpc("WeatherManager", "_receive_phase", [2, 3, 60.0])


## States the host keeps overwriting at 5 Hz are re-injected every frame.
func _hold(tag: String, w, hud) -> void:
	match tag:
		"hud_downed":
			w.handle_rpc("Main/Players/P_%d" % w.my_id, "_apply_vitals", [0.0, 40.0, "downed", 13.2, false, 100.0, 0.0, false])
			# The host's own 5 Hz vitals race the injection; keep what the HUD showed while downed.
			if hud._reticle.downed and hud._prompt.visible:
				_downed_prompt = hud._prompt.text
		"hud_out":
			w.handle_rpc("Main/Players/P_%d" % w.my_id, "_apply_vitals", [0.0, 40.0, "out", 0.0, false, 100.0, 0.0, false])
			if "SPECTATING" in hud._state_label.text:
				_out_label = hud._state_label.text
	if tag in ["hud_kbm", "hud_boss", "hud_boss_core", "hud_downed", "hud_out", "hud_scoreboard"]:
		w.handle_rpc("Main/Players/P_%d" % FAKE_MATE, "_relay_transform", [_ahead(w, 6.0) + Vector3(2, 0, 0), 0.0, 0.0, Vector3.ZERO])


func _check(tag: String, w, hud) -> void:
	var ok = false
	var info = ""
	match tag:
		"hud_kbm":
			var b = hud._panels._boss()
			ok = b.get("name") == "CLOUDBURST" and w.others.size() >= 1 and not hud._panels._feed.empty() and not hud._panels._pops.empty()
			# Reticle spread is the native projection of the held weapon's spread.
			var held = str(w.current_slot().get("item", ""))
			var want = "shotgun" if int(FullNet.item(held).get("weapon", {}).get("pellets", 1)) > 1 else "cross"
			ok = ok and (held.empty() or hud._reticle.style == want) and hud._reticle.target_spread > 0.0
			info = "miniboss=%s frac=%.2f mates=%d feed=%d pops=%d chip='%s' reticle=%s/%.1fpx (%s)" % [str(b.get("name")), float(b.get("frac", 0)), w.others.size(), hud._panels._feed.size(), hud._panels._pops.size(), hud._chip_wave.text, hud._reticle.style, hud._reticle.target_spread, held]
		"hud_boss":
			var b2 = hud._panels._boss()
			ok = b2.get("name") == "CUMULUS" and b2.sacs.size() == 3
			info = "sacs=%s" % str(b2.get("sacs"))
		"hud_boss_core":
			var b3 = hud._panels._boss()
			ok = b3.get("sacs", [1]).empty() and abs(float(b3.frac) - 640.0 / 1400.0) < 0.01 and b3.burn
			info = "core=%.2f burn=%s" % [float(b3.get("frac", 0)), str(b3.get("burn"))]
		"hud_downed":
			# Solo / one player: the prompt is SELF REVIVE, else the ping call for help.
			ok = hud._reticle.bleed_seconds == 14 and ("[D-DOWN]" in _downed_prompt or "[Y]" in _downed_prompt)
			info = "bleed=%ds prompt='%s'" % [hud._reticle.bleed_seconds, _downed_prompt]
		"hud_out":
			ok = "SPECTATING ZED" in _out_label
			info = "label='%s'" % _out_label
		"hud_pad_draft":
			var f = hud._root.get_focus_owner()
			ok = hud._overlay_kind == "draft" and f is Button
			info = "overlay=%s focus=%s" % [hud._overlay_kind, str(f)]
		"hud_pad_tape":
			ok = hud._overlay_kind == "tape" and w.input_blocked
			info = "overlay=%s blocked=%s enemy_mut=%s" % [hud._overlay_kind, str(w.input_blocked), str(w.enemy_mutations)]
		"hud_scoreboard":
			ok = hud._board.visible
			info = "board=%s" % str(hud._board.visible)
		"hud_loadout":
			var f2 = hud._root.get_focus_owner()
			ok = hud.modal_kind() == "loadout" and w.input_blocked and f2 is Button
			info = "modal=%s focus=%s" % [hud.modal_kind(), str(f2)]
		"hud_chat":
			ok = hud.modal_kind() == "chat"
			info = "modal=%s" % hud.modal_kind()
		"hud_pause":
			ok = hud._menu != null and is_instance_valid(hud._menu)
			info = "menu=%s" % str(ok)
		"hud_touch_countdown":
			ok = hud._panels._countdown in [1, 2, 3, 4, 5] and hud._touch.visible
			info = "countdown=%d touch=%s" % [hud._panels._countdown, str(hud._touch.visible)]
		"hud_wavecard":
			ok = hud._panels._card_left > 0.0 and hud._panels._card_title == "WAVE 3"
			info = "card='%s' / '%s'" % [hud._panels._card_title, hud._panels._card_sub]
	results[tag] = ok
	print("DRIVE HUD %s %s %s" % [tag, "ok" if ok else "FAIL", info])


func _leave(tag: String, w, hud) -> void:
	match tag:
		"hud_pad_tape":
			w.handle_rpc("GameManager", "_sync_tape_state", [false, false, false])
		"hud_scoreboard":
			Controls.touch_hold("scoreboard", false)
		"hud_loadout", "hud_chat":
			if hud._modal and is_instance_valid(hud._modal):
				hud._modal.close()
		"hud_pause":
			hud._menu_toggled_ms = -1000
			hud.toggle_menu()
		"hud_downed", "hud_out":
			w.handle_rpc("Main/Players/P_%d" % w.my_id, "_apply_vitals", [100.0, 100.0, "ok", 20.0, false, 100.0, 0.0, false])


func _cleanup(w, hud) -> void:
	w.handle_rpc("Main/Enemies/BossCumulus", "_died", [])
	w.handle_rpc("Main/Enemies", "_despawn_enemy", [FAKE_MINI, [], Vector3.ZERO, Vector3.ZERO, false])
	w.squad.erase(FAKE_MATE)
	w.handle_rpc("GameManager/MutationRoll", "_reset_run_rpc", [])
	if not _phase0.empty():
		w.handle_rpc("WeatherManager", "_receive_phase", _phase0)
	Controls.set_device("kbm")
	var bad = []
	for k in results:
		if not results[k]:
			bad.append(k)
	if bad.empty():
		drive._pass("HUD", "%d HUD states checked" % results.size())
	else:
		print("DRIVE HUD FAILED %s" % str(bad))
