extends CanvasLayer
## Run HUD, panel-free like ui/hud.gd: compass + forecast chip (top centre),
## vitals (top left, clear of the move stick), hotbar (bottom centre), ammo
## (right, above the action buttons), reticle + prompt, banners, damage
## vignette and direction arcs, teammate names, and the draft / tape / menu
## overlays. Groups idle dim and come up when they matter.

const Compass = preload("res://ui/compass.gd")
const Reticle = preload("res://ui/reticle.gd")
const Hotbar = preload("res://ui/hotbar.gd")
const Touch = preload("res://ui/touch.gd")
const SettingsPanel = preload("res://ui/settings_panel.gd")
const FocusNav = preload("res://ui/focus_nav.gd")
const Panels = preload("res://ui/hud_panels.gd")
const Loadout = preload("res://ui/loadout.gd")
const QuickChat = preload("res://ui/quick_chat.gd")
const Scoreboard = preload("res://ui/scoreboard.gd")
const DAMAGE = preload("res://shaders/damage.shader")
const PHASE_NAMES = {"calm": "CALM", "drizzle": "DRIZZLE", "downpour": "DOWNPOUR", "acid_storm": "ACID STORM", "clearing": "CLEARING"}
const PHASE_COLORS = {"calm": Color("#66dfda"), "drizzle": Color("#9fd8ff"), "downpour": Color("#adbaff"), "acid_storm": Color("#b8e56d"), "clearing": Color("#b8e56d")}
const BAR_W = 200.0

var world: Node
var net: Node = null
var _menu_toggled_ms = -1000
var _menu_nav: Node
var _root = Control.new()
var _compass: Control
var _reticle: Control
var _hotbar: Control
var _touch: Control
var _draw = Control.new()
var _chip_phase: Label
var _chip_wave: Label
var _combat: Label
var _banner: Label
var _banner_left = 0.0
var _suit = ProgressBar.new()
var _health = ProgressBar.new()
var _suit_label: Label
var _health_label: Label
var _hazard: Label
var _decon: Label
var _vitals = VBoxContainer.new()
var _armory = VBoxContainer.new()
var _weapon: Label
var _ammo: Label
var _reserve: Label
var _pips = Control.new()
var _prompt: Label
var _state_label: Label
var _hurt_mat = ShaderMaterial.new()
var _acid_mat = ShaderMaterial.new()
var _hurt_rect = ColorRect.new()
var _draw_busy = true
var _acid_rect = ColorRect.new()
var _overlay: Control
var _overlay_kind = ""
var _menu: Control
var _signal: Control
var _damage_left = 0.0
var _suit_flash = 0.0
var _last_hp = -1.0
var _last_suit = -1.0
var _arcs = []                 # [angle, life]
var _numbers = []              # [world pos, text, life, color]
var _last_phase = ""
var _phase_flash = 0.0
var _name_left = 0.0
var _last_item = ""
var _vitals_hot = 0.0
var _clock = 0.0
var _draft = {}
var _draft_left = 0.0
var _toast_left = 0.0
var _panels: Control
var _hint: Label
var _board: Control
var _modal: Control              # loadout / quick chat (blocks gameplay input)
var _run_clock = 0.0
var _last_scrap = -1
var _kills = []                  # recent kill times (multikill popups)
var _feats_seen = 0
var _chat_seen = -1
var _last_countdown = -1
var _last_phase_id = ""
var _heart_left = 0.0
var _state_flash = 0.0
var _last_state = ""


func _ready() -> void:
	net = FullNet.current()
	net.set_meta("run_feats", [])
	layer = 5
	_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.theme()
	add_child(_root)
	_build_damage()
	_reticle = Reticle.new()
	_reticle.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_root.add_child(_reticle)
	_draw.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.connect("draw", self, "_on_draw")
	_root.add_child(_draw)
	_panels = Panels.new()
	_panels.world = world
	_panels.net = net
	_panels.hud = self
	_root.add_child(_panels)
	_compass = Compass.new()
	_compass.world = world
	UI.place(_compass, 0.5, 0.0, -180, 8)
	_root.add_child(_compass)
	_build_chip()
	_build_vitals()
	_build_armory()
	_build_center()
	_hotbar = Hotbar.new()
	_hotbar.world = world
	_root.add_child(_hotbar)
	UI.place(_hotbar, 0.5, 1.0, -_hotbar.width() * 0.5, -20 - Hotbar.CELL.y)
	_touch = Touch.new()
	_touch.world = world
	_touch.hud = self
	_touch.hotbar = _hotbar
	_root.add_child(_touch)
	_board = Scoreboard.new()
	_board.world = world
	_board.net = net
	UI.place(_board, 0.5, 0.0, -320, 96, 640, 300)
	_board.visible = false
	_root.add_child(_board)
	world.connect("hit_marker", self, "_on_hit_marker")
	world.connect("killed", self, "_on_killed")
	world.connect("hurt", self, "_on_hurt")
	world.connect("banner", self, "_on_banner")
	world.connect("picked", self, "_on_picked")
	net.connect("draft", self, "_on_draft")
	net.connect("draft_done", self, "_on_draft_done")
	net.connect("tape", self, "_on_tape")
	net.connect("events", self, "_on_events")
	if world.has_signal("group_warning"):
		world.connect("group_warning", _compass, "warn")
	# Test switch: --hud-hide=2,5 hides those _root children (on-car A/B).
	for a in Settings.args():
		if str(a).begins_with("--hud-hide="):
			var names = []
			for i in range(_root.get_child_count()):
				names.append("%d=%s" % [i, _root.get_child(i).get_class()])
			print("HUD children ", " ".join(names))
			for part in str(a).substr(11).split(","):
				var i = int(part)
				if i < _root.get_child_count():
					_root.get_child(i).set_meta("test_hidden", true)


func _build_damage() -> void:
	_hurt_mat.shader = DAMAGE
	_acid_mat.shader = DAMAGE
	_acid_mat.set_shader_param("tint", Vector3(0.65, 1.0, 0.08))
	for pair in [[_hurt_rect, _hurt_mat], [_acid_rect, _acid_mat]]:
		pair[0].set_anchors_and_margins_preset(Control.PRESET_WIDE)
		pair[0].mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair[0].material = pair[1]
		pair[0].visible = false
		_root.add_child(pair[0])


func _build_chip() -> void:
	var chip = HBoxContainer.new()
	UI.place(chip, 0.5, 0.0, -220, 52)
	chip.rect_min_size = Vector2(440, 26)
	chip.alignment = BoxContainer.ALIGN_CENTER
	chip.add_constant_override("separation", 14)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(chip)
	_chip_phase = UI.hud("CALM", 24, UI.CYAN)
	chip.add_child(_chip_phase)
	_chip_wave = UI.hud("", 24, UI.PAPER)
	chip.add_child(_chip_wave)
	_combat = UI.hud("", 20, UI.PINK)
	UI.place(_combat, 0.5, 0.0, -150, 80)
	_combat.rect_size = Vector2(300, 22)
	_combat.align = Label.ALIGN_CENTER
	_root.add_child(_combat)
	_banner = UI.hud("", 34, UI.PAPER)
	UI.place(_banner, 0.5, 0.0, -330, 118)
	_banner.rect_size = Vector2(660, 40)
	_banner.align = Label.ALIGN_CENTER
	_banner.autowrap = true
	_banner.visible = false
	_root.add_child(_banner)


func _build_vitals() -> void:
	_vitals.rect_position = Vector2(20, 14)
	_vitals.add_constant_override("separation", 3)
	_vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vitals)
	_hazard = UI.hud("", 20, UI.ACID)
	_vitals.add_child(_hazard)
	_suit_label = UI.hud("SUIT  100%", 22, UI.CYAN)
	_vitals.add_child(_suit_label)
	_bar(_suit, UI.CYAN)
	_health_label = UI.hud("HEALTH  100", 22, UI.PINK)
	_vitals.add_child(_health_label)
	_bar(_health, UI.PINK)
	_decon = UI.hud("DECON  4", 20, UI.CYAN)
	_vitals.add_child(_decon)


func _bar(bar: ProgressBar, color: Color) -> void:
	bar.rect_min_size = Vector2(BAR_W, 6)
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.thin_bar(bar, color)
	_vitals.add_child(bar)


func _build_armory() -> void:
	UI.place(_armory, 1.0, 1.0, -340, -405)
	_armory.rect_min_size = Vector2(320, 100)
	_armory.alignment = BoxContainer.ALIGN_END
	_armory.add_constant_override("separation", 0)
	_armory.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_armory)
	_hint = UI.hud("", 18, UI.CYAN)
	_hint.align = Label.ALIGN_RIGHT
	_armory.add_child(_hint)
	_weapon = UI.hud("", 22, UI.PAPER)
	_weapon.align = Label.ALIGN_RIGHT
	_armory.add_child(_weapon)
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_END
	row.add_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_armory.add_child(row)
	_ammo = UI.hud("", 44, UI.PAPER)
	row.add_child(_ammo)
	_reserve = UI.hud("", 24, UI.MUTED)
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_reserve)
	_pips.rect_min_size = Vector2(320, 12)
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.connect("draw", self, "_draw_pips")
	_armory.add_child(_pips)


func _build_center() -> void:
	_prompt = UI.hud("", 26, UI.PAPER)
	UI.place(_prompt, 0.5, 0.5, -300, 44)
	_prompt.rect_size = Vector2(600, 30)
	_prompt.align = Label.ALIGN_CENTER
	_root.add_child(_prompt)
	_state_label = UI.hud("", 40, UI.PINK)
	UI.place(_state_label, 0.5, 0.5, -420, -110, 840, 48)
	_state_label.align = Label.ALIGN_CENTER
	_root.add_child(_state_label)


# ------------------------------------------------------------------ events
func _on_hit_marker(kill: bool, head: bool) -> void:
	_reticle.hit(kill, head)


func _on_events(list: Array) -> void:
	for ev in list:
		if ev is Dictionary and ev.get("e") == "hit" and ev.get("at") is Array and ev.get("dmg") != null:
			var head = bool(ev.get("head", false))
			_numbers.append([world._v(ev.at) + Vector3(rand_range(-0.2, 0.2), 0.2, 0), str(int(round(float(ev.dmg)))), 0.7,
				Color("#ffd56a") if head else UI.PAPER])
			if _numbers.size() > 12:
				_numbers.pop_front()


func _on_hurt(dir, amount: float) -> void:
	_damage_left = 0.65
	_vitals_hot = 3.0
	Sound.play("player_hurt", -7.0)
	if dir is Vector3 and dir.length() > 0.01:
		var local: Vector3 = world.camera.global_transform.basis.xform_inv(dir)
		_arcs.append([atan2(local.x, -local.z), 1.0])
		if _arcs.size() > 4:
			_arcs.pop_front()


func _on_banner(text: String) -> void:
	_banner.text = text.to_upper()
	_banner.add_color_override("font_color", UI.PAPER)
	_banner_left = 3.0
	_banner.modulate.a = 0.0


func _on_picked(item: String) -> void:
	_hotbar.flash()
	var meta = Assets.weapon(item)
	var nm = str(meta.get("name", item.replace("_", " ")))
	if item in ["scrap", "scrap_large"]:
		return  # the scrap counter popup covers it
	_panels.popup("+ " + nm.to_upper(), UI.AMBER)


func _on_killed(_type) -> void:
	var now = _run_clock
	_kills.append(now)
	while not _kills.empty() and now - _kills[0] > 1.6:
		_kills.pop_front()
	if _kills.size() >= 2:
		_panels.popup("x%d" % _kills.size(), UI.PINK if _kills.size() < 4 else UI.AMBER)


func _on_draft(data: Dictionary) -> void:
	_draft = data
	_draft_left = float(data.get("time_left", 15.0)) if data.get("time_left") != null else 15.0
	_show_overlay("draft")


func _on_draft_done() -> void:
	# Also sent when the host closes the tape choice (another player chose).
	if _overlay_kind in ["draft", "tape"]:
		_show_overlay("")


func _on_tape(data: Dictionary) -> void:
	_draft = data
	_show_overlay("tape")


func blocks_touch(at: Vector2) -> bool:
	if _menu and is_instance_valid(_menu) and _menu.visible:
		return true
	if _modal and is_instance_valid(_modal):
		return true
	if _overlay and is_instance_valid(_overlay):
		for c in _overlay.get_children():
			if c is Control and c.get_global_rect().has_point(at) and c.mouse_filter == Control.MOUSE_FILTER_STOP:
				return true
	return false


func toggle_menu() -> void:
	# The touch layer and Controls can both report the same key press.
	var now = OS.get_ticks_msec()
	if now - _menu_toggled_ms < 150:
		return
	_menu_toggled_ms = now
	if _modal and is_instance_valid(_modal):
		_modal.close()
		return
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
		_set_solo_paused(false)
		return
	_touch.cancel_all()
	_set_solo_paused(true)
	_menu = Control.new()
	_menu.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_menu)
	var shade = ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.075, 0.8)
	shade.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_menu.add_child(shade)
	var box = VBoxContainer.new()
	box.rect_position = Vector2(80, 70)
	box.add_constant_override("separation", 10)
	_menu.add_child(box)
	box.add_child(UI.label("PAUSE", 26, UI.MUTED))
	if net != FullNet or FullNet.mode != "solo":
		box.add_child(UI.label("CLOUD PLAY KEEPS RUNNING", 22, UI.AMBER))
	var first: Button
	var specs = [["RESUME", "toggle_menu"]]
	if _full():
		specs.append(["LOADOUT", "_menu_modal", "loadout"])
		specs.append(["SQUAD CHAT", "_menu_modal", "chat"])
	specs += [["SETTINGS", "_open_settings"], ["LEAVE RUN", "_leave"]]
	for spec in specs:
		var b = UI.button(spec[0], self, spec[1], [spec[2]] if spec.size() > 2 else [])
		b.rect_min_size = Vector2(420, 60)
		b.align = Button.ALIGN_LEFT
		if spec[0] == "RESUME":
			UI.primary(b)
			first = b
		box.add_child(b)
	var hints = UI.label(_controls_line(), 20, UI.MUTED)
	box.add_child(hints)
	var board = Scoreboard.new()
	board.world = world
	board.net = net
	board.run_seconds = _run_clock
	UI.place(board, 1.0, 0.0, -680, 100, 640, 300)
	_menu.add_child(board)
	UI.focusable(_menu)
	_menu_nav = FocusNav.new().attach(_menu)
	_menu_nav.first = first
	_menu_nav.connect("back", self, "toggle_menu")


func _full() -> bool:
	return net == FullNet and "inv" in world


## One line of the current device's run controls for the pause menu.
func _controls_line() -> String:
	match Controls.device:
		"pad":
			return "HOLD BACK SQUAD  ·  D-DOWN PING  ·  D-UP TARP  ·  Y USE"
		"kbm":
			return "TAB SQUAD  ·  %s LOADOUT  ·  ENTER CHAT  ·  Z PING  ·  T TARP" % Controls.hint("inventory")
	return "MENU  ·  READY  ·  USE / ITEM ON SCREEN"


func _menu_modal(kind: String) -> void:
	if _menu and is_instance_valid(_menu):
		toggle_menu()
		_menu_toggled_ms = -1000
	call_deferred("open_modal", kind)


## Loadout or quick chat over the run. Gameplay input stops while it is up.
func open_modal(kind: String) -> void:
	if _modal and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	if not _full() or (_menu and is_instance_valid(_menu)):
		return
	_touch.cancel_all()
	if kind == "loadout":
		_modal = Loadout.new()
		_modal.world = world
	else:
		_modal = QuickChat.new()
	_modal.net = net
	_modal.connect("closed", self, "_on_modal_closed")
	_root.add_child(_modal)


func _on_modal_closed() -> void:
	_modal = null


func modal_kind() -> String:
	if _modal and is_instance_valid(_modal):
		return "loadout" if _modal is Loadout else "chat"
	return ""


func _set_solo_paused(value: bool) -> void:
	if net == FullNet and FullNet.mode == "solo" and FullNet.rpc_send("GameManager", "_request_pause_rpc", [value, Settings.player_name]):
		world.set_process(not value)
		if value:
			Controls.capture_mouse(false)


func _open_settings() -> void:
	var s = SettingsPanel.new()
	_root.add_child(s)
	if _menu_nav and is_instance_valid(_menu_nav):
		_menu_nav.screen = null
		s.connect("tree_exited", self, "_on_settings_closed")


func _on_settings_closed() -> void:
	if _menu_nav and is_instance_valid(_menu_nav) and _menu and is_instance_valid(_menu):
		_menu_nav.screen = _menu


func _leave() -> void:
	net.leave()


func _show_overlay(kind: String) -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_overlay_kind = kind
	if kind == "":
		return
	_overlay = Control.new()
	_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_overlay)
	_root.move_child(_overlay, _root.get_child_count() - 1)
	if kind == "draft":
		var head = UI.label("PICK A SQUAD MUTATION", 28, UI.PAPER)
		head.add_stylebox_override("normal", UI.panel(UI.OVERLAY, UI.CYAN))
		UI.place(head, 0.5, 0.5, -460, -215)
		_overlay.add_child(head)
		var how = UI.hud(_pick_hint(3), 20, UI.MUTED)
		UI.place(how, 0.5, 0.5, -100, -196, 560, 24)
		how.align = Label.ALIGN_RIGHT
		_overlay.add_child(how)
		var enemy = str(_draft.get("enemy", ""))
		if not enemy.empty():
			var fc = UI.hud("FORECAST  ·  INFECTED GAIN " + enemy.to_upper(), 20, UI.PINK)
			UI.place(fc, 0.5, 0.5, -460, 20, 920, 24)
			_overlay.add_child(fc)
		var cards: Array = _draft.get("cards", []) if _draft.get("cards") is Array else []
		var colors = [UI.ACID, UI.CYAN, Color("#7fb2ff")]
		for i in cards.size():
			var card = cards[i]
			if not (card is Dictionary):
				continue
			var b = Button.new()
			b.focus_mode = Control.FOCUS_ALL
			UI.place(b, 0.5, 0.5, -460 + i * 310, -140)
			b.rect_size = Vector2(300, 150)
			var c: Color = colors[i % 3]
			var box = StyleBoxFlat.new()
			box.bg_color = Color(0.047, 0.078, 0.133, 0.92)
			box.border_color = c
			box.border_width_top = 4
			for st in ["normal", "hover", "pressed"]:
				b.add_stylebox_override(st, box)
			b.connect("pressed", self, "_choose", ["mutation", i])
			_overlay.add_child(b)
			var col = VBoxContainer.new()
			col.set_anchors_and_margins_preset(Control.PRESET_WIDE)
			col.margin_left = 12
			col.margin_top = 10
			col.margin_right = -12
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(col)
			var num = UI.label(" %s " % (str(i + 1) if Controls.device == "kbm" else "·"), 22, UI.INK)
			var nb = StyleBoxFlat.new()
			nb.bg_color = c
			num.add_stylebox_override("normal", nb)
			num.size_flags_horizontal = 0
			col.add_child(num)
			col.add_child(UI.label(str(card.get("title", "")).to_upper(), 28, c))
			var desc = UI.label(str(card.get("desc", "")), 20, UI.PAPER)
			desc.autowrap = true
			desc.rect_min_size = Vector2(276, 0)
			col.add_child(desc)
	elif kind == "tape":
		var can = _draft.get("can_choose") != false
		var head2 = UI.label("CUMULUS IS DOWN  ·  END OF TAPE" if can else "WAITING FOR THE HOST TO CHOOSE", 40, UI.AMBER)
		var sub = UI.hud("KEEP RECORDING FOR AN ENDLESS SCORE, OR END THE TAPE AS A WIN" if can else "", 20, UI.PAPER)
		UI.place(sub, 0.5, 0.5, -400, -62, 800, 24)
		sub.align = Label.ALIGN_CENTER
		_overlay.add_child(sub)
		if can:
			var how2 = UI.hud(_pick_hint(2), 20, UI.MUTED)
			UI.place(how2, 0.5, 0.5, -400, 50, 800, 24)
			how2.align = Label.ALIGN_CENTER
			_overlay.add_child(how2)
		UI.place(head2, 0.5, 0.5, -400, -116, 800, 50)
		head2.align = Label.ALIGN_CENTER
		_overlay.add_child(head2)
		if can:
			var keys = Controls.device == "kbm"
			var specs = [[("[1]  " if keys else "") + "CONTINUE  >>", 0, UI.ACID], [("[2]  " if keys else "") + "END TAPE", 1, UI.PINK]]
			for j in 2:
				var b2 = UI.button(specs[j][0], self, "_choose", ["tape", specs[j][1]])
				UI.place(b2, 0.5, 0.5, -310 + j * 320, -40)
				b2.rect_size = Vector2(300, 80)
				b2.add_font_override("font", UI.font(34))
				UI.accent(b2, specs[j][2])
				_overlay.add_child(b2)

	UI.focusable(_overlay)
	var onav = FocusNav.new().attach(_overlay)
	for c in _overlay.get_children():
		if c is BaseButton:
			onav.first = c
			break
	if Controls.device == "pad" and onav.first:
		onav.first.call_deferred("grab_focus")


func _pick_hint(n: int) -> String:
	match Controls.device:
		"kbm":
			return "PRESS 1-%d  ·  OR ARROWS + ENTER" % n
		"pad":
			return "D-PAD CHOOSE  ·  A PICK"
	return "TAP TO PICK"


func _choose(kind: String, i: int) -> void:
	net.choose(kind, i)
	Sound.play("ui_click")
	if kind == "tape":
		_show_overlay("")
	elif _overlay:
		# Mark the pick; the bridge closes the draft with draft_done.
		var idx = 0
		for c in _overlay.get_children():
			if c is Button:
				c.modulate = Color(1, 1, 1, 1.0 if idx == i else 0.45)
				idx += 1


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	var _pt = OS.get_ticks_usec()
	_process_body(delta)
	Settings.prof_add("hud", OS.get_ticks_usec() - _pt)


func _process_body(delta: float) -> void:
	if world == null:
		return
	_clock += delta
	var you: Dictionary = world.you
	var state = str(you.get("state", "ok"))
	_update_forecast(delta)
	_update_vitals(you, state, delta)
	_update_armory(you, state, delta)
	_update_center(you, state)
	_banner_left = max(0.0, _banner_left - delta)
	_banner.visible = _banner_left > 0.0
	if _banner.visible:
		_banner.modulate.a = min(min(1.0, _banner.modulate.a + delta * 6.0), _banner_left * 2.5)
	_damage_left = max(0.0, _damage_left - delta)
	_suit_flash = max(0.0, _suit_flash - delta)
	var hurt_s: float = min(_damage_left * 2.0, 0.85) * Settings.flash_scale()
	var acid_s = _suit_flash * 0.5 * Settings.flash_scale()
	world.set_edge_tints(hurt_s, acid_s)
	for a in _arcs:
		a[1] -= delta * 1.2
	while not _arcs.empty() and _arcs[0][1] <= 0.0:
		_arcs.pop_front()
	for n in _numbers:
		n[2] -= delta
		n[0].y += delta * 0.8
	while not _numbers.empty() and _numbers[0][2] <= 0.0:
		_numbers.pop_front()
	if _overlay_kind == "draft":
		_draft_left = max(0.0, _draft_left - delta)
	var lost = net.phase == "retuning"
	if lost and (_signal == null or not is_instance_valid(_signal)):
		_signal = UI.label("SIGNAL LOST  ·  RETUNING  ·  " + net.last_error, 40, UI.PINK, 2)
		UI.place(_signal, 0.5, 0.5, -250, -160)
		_root.add_child(_signal)
	elif not lost and _signal and is_instance_valid(_signal):
		_signal.queue_free()
		_signal = null
	var menu_open = _menu != null and is_instance_valid(_menu)
	var modal_open = _modal != null and is_instance_valid(_modal)
	_update_run_ui(delta, you, state, menu_open, modal_open)
	world.input_blocked = menu_open or modal_open or _overlay_kind == "tape"
	world.draft_open = _overlay_kind == "draft"
	_touch.visible = not menu_open and not modal_open and net.state == "run" and Controls.device == "touch" and not Settings.has_arg("--no-touch")
	if Settings.has_arg("--no-compass"):
		_compass.visible = false
	for c in _root.get_children():
		if c.has_meta("test_hidden"):
			c.visible = false
	_touch.update()
	# The overlay only has content with arcs, teammates, numbers or a draft.
	var busy = not _arcs.empty() or not world.others.empty() or not _numbers.empty() or _overlay_kind == "draft" 		or ("pings" in world and not world.pings.empty()) or not _drop_marker().empty()
	if busy or _draw_busy:
		_draw.update()
	_draw_busy = busy


## Scoreboard hold, loadout / chat keys, countdown, wave card, popups, feed,
## downed heartbeat and the boss strip / banner layout.
func _update_run_ui(delta: float, you: Dictionary, state: String, menu_open: bool, modal_open: bool) -> void:
	_run_clock += delta
	var free = not menu_open and not modal_open and _overlay_kind == ""
	_board.visible = free and Controls.held("scoreboard")
	_board.run_seconds = _run_clock
	if free and _full() and net.state == "run":
		if Controls.pressed("inventory"):
			Controls.eat("inventory")
			open_modal("loadout")
		elif Controls.device == "kbm" and Controls.pressed("menu_accept"):
			Controls.eat("menu_accept")
			open_modal("chat")
	if _overlay_kind == "tape" and _draft.get("can_choose") != false:
		for n in 2:
			if Controls.pressed("draft_%d" % (n + 1)):
				Controls.eat("draft_%d" % (n + 1))
				_choose("tape", n)
				return
	# Calm countdown (last 5 s) with the native tick.
	var phase = str(world.weather_state.get("phase", "calm"))
	var left = int(ceil(float(world.weather_state.get("phase_time_left", 0.0)))) if world.weather_state.get("phase_time_left") != null else 0
	var cd = left if phase == "calm" and left in [1, 2, 3, 4, 5] and not (world.get("draft_active") == true) else 0
	_panels.set_countdown(cd)
	if cd > 0 and cd != _last_countdown:
		Sound.play("storm_countdown", -15.0, lerp(0.88, 1.16, (5.0 - cd) / 4.0))
	_last_countdown = cd
	# Wave intro card as the storm arrives.
	if phase != _last_phase_id:
		if phase == "drizzle" and _last_phase_id != "":
			var wave = int(world.weather_state.get("wave", 1))
			var endless = bool(world.run.get("endless", false))
			var sub = "THE STORM IS HERE  ·  GET UNDER COVER"
			if wave >= 5 and not endless:
				sub = "ACID STORM  ·  CUMULUS INBOUND"
			elif wave == 3:
				sub = "FLOOD WAVE  ·  PUDDLES GROW FAST"
			_panels.card("ENDLESS %d" % max(1, wave - 5) if endless else "WAVE %d" % wave, sub, UI.ACID if wave >= 5 else UI.PAPER)
		_last_phase_id = phase
	# Scrap popups.
	var scrap = int(you.get("scrap", 0)) if you.get("scrap") != null else 0
	if _last_scrap >= 0 and scrap > _last_scrap:
		_panels.popup("+%d SCRAP" % (scrap - _last_scrap), Color("#ffc365"))
	_last_scrap = scrap
	# Feats (Full): popup per progress award.
	var feats = world.get("feat_log")
	if feats is Array:
		while _feats_seen < feats.size():
			var f = feats[_feats_seen]
			_feats_seen += 1
			_panels.popup("FEAT  " + str(f[0]).replace("_", " ").to_upper(), UI.ACID)
			Sound.play("ui_achievement", -14.0)
		if feats.size() != int(net.get_meta("run_feats").size() if net.has_meta("run_feats") else -1):
			net.set_meta("run_feats", feats.duplicate())
	# Chat + pings feed.
	var chat = net.get("chat")
	if chat is Array:
		if _chat_seen < 0:
			_chat_seen = chat.size()
		while _chat_seen < chat.size():
			var m = chat[_chat_seen]
			_chat_seen += 1
			if m is Dictionary:
				_panels.feed("%s: %s" % [str(m.get("from", "")).to_upper(), str(m.get("text", ""))], UI.PAPER)
	if "pings" in world:
		for pg in world.pings:
			if pg.size() == 4:
				pg.append(true)   # seen marker (world reads indices 0-3 only)
				var bad = pg[1] in ["enemy", "danger"]
				_panels.feed("%s PINGED %s" % [_peer_name(int(pg[3])), str(pg[1]).to_upper()], UI.PINK if bad else UI.AMBER)
	# Downed heartbeat.
	if state == "downed":
		_heart_left -= delta
		if _heart_left <= 0.0:
			_heart_left = 1.1
			Sound.play("heartbeat", -12.0)
	else:
		_heart_left = 0.0
	# Health trail + layout: the banner drops below the boss strip.
	_panels.trail_rect = _health.get_global_rect()
	var hp_max: float = max(1.0, float(you.get("hp_max", 100.0)) if you.get("hp_max") != null else 100.0)
	_panels.set_health(clamp(float(you.get("hp", 100.0)) / hp_max, 0.0, 1.0) if you.get("hp") != null else 1.0)
	var boss_up = false
	for e in world.enemy_points:
		if e[1] in ["cumulus", "cloudburst"]:
			boss_up = true
	_banner.margin_top = 150 if boss_up else 118
	_banner.margin_bottom = _banner.margin_top + 40


func _peer_name(id: int) -> String:
	if net.get("you") != null and id == int(net.you):
		return "YOU"
	var r = net.roster.get(id) if net.get("roster") is Dictionary else null
	return str(r.get("name", "")).to_upper() if r is Dictionary else "SQUAD"


func _update_forecast(delta: float) -> void:
	var w: Dictionary = world.weather_state
	var phase = str(w.get("phase", "calm"))
	if phase != _last_phase:
		_last_phase = phase
		_phase_flash = 3.0
	_phase_flash = max(0.0, _phase_flash - delta)
	var color: Color = PHASE_COLORS.get(phase, UI.CYAN)
	var left = int(ceil(float(w.get("phase_time_left", 0.0)))) if w.get("phase_time_left") != null else 0
	var countdown = phase == "calm" and left in [1, 2, 3, 4, 5]
	_chip_phase.text = PHASE_NAMES.get(phase, phase.to_upper())
	_chip_phase.add_color_override("font_color", UI.AMBER if countdown else color)
	var wave = int(w.get("wave", world.run.get("wave", 1)))
	var endless = bool(world.run.get("endless", false))
	var timer = ""
	if phase == "calm" and left > 0:
		timer = "  %d:%02d" % [left / 60, left % 60]
	_chip_wave.text = ("ENDLESS %d" % max(1, wave - 5) if endless else "WAVE %d/5" % wave) + timer
	var can_ready = phase in ["calm", "clearing"] and float(w.get("phase_time_left", 0.0) if w.get("phase_time_left") != null else 0.0) > 3.0 		and str(world.you.get("state", "ok")) == "ok" and Controls.device != "touch" and not (world.get("draft_active") == true)
	if can_ready:
		var tally = str(world.get("ready_tally")) if world.get("ready_tally") else ""
		_chip_wave.text += "    [%s] READY%s" % [Controls.hint("ready_up"), ("  " + tally.substr(6)) if tally.begins_with("READY ") else ""]
	_chip_phase.get_parent().modulate.a = move_toward(_chip_phase.get_parent().modulate.a, 1.0 if _phase_flash > 0.0 or countdown else 0.7, delta * 3.0)
	var alive = int(world.run.get("alive_enemies", 0))
	_combat.visible = phase in ["drizzle", "downpour", "acid_storm"] and alive > 0
	_combat.text = "%d INFECTED LEFT" % alive
	if endless:
		_combat.text += "   CNT %08d" % int(world.run.get("score", 0))
		_combat.visible = true


func _update_vitals(you: Dictionary, state: String, delta: float) -> void:
	var hp = float(you.get("hp", 100.0)) if you.get("hp") != null else 100.0
	var hp_max: float = max(1.0, float(you.get("hp_max", 100.0)) if you.get("hp_max") != null else 100.0)
	var suit = float(you.get("suit", 100.0)) if you.get("suit") != null else 100.0
	var suit_max: float = max(1.0, float(you.get("suit_max", 100.0)) if you.get("suit_max") != null else 100.0)
	if _last_hp >= 0.0 and hp < _last_hp - 0.5 and _damage_left <= 0.0:
		_damage_left = 0.4
		_vitals_hot = 3.0
	if _last_suit >= 0.0 and suit < _last_suit - 0.05:
		_suit_flash = max(_suit_flash, 0.35)
	_last_hp = hp
	_last_suit = suit
	_health.max_value = hp_max
	_health.value = lerp(_health.value, hp, 1.0 - exp(-12.0 * delta))
	_suit.max_value = suit_max
	_suit.value = suit
	_suit_label.text = "SUIT  %d%%" % int(round(suit / suit_max * 100.0))
	_health_label.text = "HEALTH  %d" % int(round(hp))
	var raining = str(world.weather_state.get("phase", "calm")) in ["drizzle", "downpour", "acid_storm"]
	var hazard = ""
	var hcolor = UI.ACID
	if bool(you.get("in_puddle", false)):
		hazard = "ACID POOL"
		hcolor = UI.PINK
	elif raining and bool(you.get("sheltered", false)):
		hazard = "DRY"
		hcolor = UI.CYAN
	elif raining and bool(you.get("exposed", false)):
		hazard = "ACID RAIN"
	if suit < 25.0 and (hazard == "ACID RAIN" or hazard == "ACID POOL"):
		hazard = "SUIT BREACH"
		hcolor = UI.PINK
	_hazard.text = hazard
	_hazard.visible = not hazard.empty()
	_hazard.add_color_override("font_color", hcolor)
	var pulse = 1.0 if Settings.reduced_flash else 0.65 + 0.35 * sin(_clock * 6.0)
	_hazard.modulate.a = pulse if hcolor == UI.PINK else 1.0
	var util = ["DECON  %d" % int(world.run.get("shared_decon", 0))] if world.run.get("shared_decon") != null else []
	if bool(you.get("tarp", false)):
		util.append("TARP UP")
	elif bool(you.get("has_tarp", false)):
		util.append("TARP" + ("  [%s]" % Controls.hint("tarp") if Controls.device != "touch" else ""))
	var vit = world.get("vit")
	if vit is Dictionary:
		var pm = world.get("player_mutations")
		if pm is Array and "static_charge" in pm and float(vit.get("charge", 0.0)) > 0.01:
			util.append("STATIC %d%%" % int(round(float(vit.charge) * 100.0)))
		_health.modulate = UI.CYAN.lightened(0.35) if bool(vit.get("invuln", false)) else Color.white
	_decon.text = "   ".join(util)
	_vitals_hot = max(0.0, _vitals_hot - delta)
	var hot = not hazard.empty() or _vitals_hot > 0.0 or hp < hp_max * 0.5 or suit < 50.0 or state != "ok"
	_vitals.modulate.a = move_toward(_vitals.modulate.a, 1.0 if hot else 0.6, delta * 3.0)


func _update_armory(you: Dictionary, state: String, delta: float) -> void:
	var item: Dictionary = world.current_slot()
	_armory.visible = state == "ok" and not item.empty()
	_hotbar.visible = state == "ok"
	var id = str(item.get("item", ""))
	if id != _last_item:
		_last_item = id
		_name_left = 2.4
	_name_left = max(0.0, _name_left - delta)
	_weapon.text = str(item.get("name", id)).to_upper()
	_weapon.modulate.a = max(0.55, clamp(_name_left * 2.0, 0.0, 1.0))
	if item.get("ammo") != null:
		_ammo.text = "%d / %d" % [int(item.ammo), int(item.get("reserve", 0)) if item.get("reserve") != null else 0]
		_reserve.text = ""
		var low = int(item.ammo) <= max(1, int(item.get("mag", 6)) / 4) if item.get("mag") != null else false
		_ammo.add_color_override("font_color", UI.PINK if int(item.ammo) == 0 else (UI.AMBER if low else UI.PAPER))
	else:
		_ammo.text = "x%d" % int(item.get("count", 1)) if not item.empty() else ""
		_reserve.text = ""
		_ammo.add_color_override("font_color", UI.PAPER)
	var inv = world.get("inv")
	var jammed = inv is Dictionary and float(inv.get("jam_left", 0.0)) > 0.0
	if jammed:
		_ammo.add_color_override("font_color", UI.PINK)
	_reticle.jammed = jammed
	var pouch = str(you.get("pouch", "")) if you.get("pouch") != null else ""
	var hint = ""
	if Controls.device != "touch":
		if not pouch.empty():
			hint = "[%s] THROW  ·  [%s] STOW" % [Controls.hint("fire"), Controls.hint("throw_grenade" if pouch == "frag" else "throw_dome")]
		elif not item.empty() and item.get("ammo") == null:
			hint = "[%s] USE" % Controls.hint("fire")
		elif jammed:
			hint = "JAMMED"
	_hint.text = hint
	_hint.visible = not hint.empty()
	if inv is Dictionary and float(inv.get("reload_left", 0.0)) > 0.0:
		_reticle.reload_frac = 1.0 - float(inv.reload_left) / max(0.01, float(inv.get("reload_total", 1.0)))
	else:
		_reticle.reload_frac = -1.0
	var cl = world.get("_charge_left")
	var ct = float(net.item(id).get("weapon", {}).get("charge_time", 0.0)) if net.has_method("item") and net.item(id).get("weapon") is Dictionary else 0.0
	_reticle.charging = cl != null and float(cl) >= 0.0 and ct > 0.0
	_reticle.charge = clamp(1.0 - float(cl) / ct, 0.0, 1.0) if _reticle.charging else 0.0
	_pips.update()
	# Reticle style from the weapon.
	var meta = Assets.weapon(id)
	var cat = str(meta.get("category", "gun"))
	_reticle.style = "shotgun" if ("shotgun" in id or "rock_salt" in id) else ("launcher" if cat != "gun" or "launcher" in id or id in ["harpoon", "flare_launcher"] else "cross")
	var moving: float = world._v(you.get("vel")).length()
	var aiming = bool(you.get("aiming", false))
	var base = 26.0 if _reticle.style == "shotgun" else 6.0
	_reticle.target_spread = base * (0.55 if aiming else 1.0) + moving * (2.2 if _reticle.style == "shotgun" else 1.6) + world.viewmodel.recoil * 10.0
	_reticle.ads = aiming
	_reticle.reload = bool(you.get("reloading", false))


func _draw_pips() -> void:
	var item: Dictionary = world.current_slot()
	if item.get("mag") == null or item.get("ammo") == null:
		return
	var mag = int(item.mag)
	if mag <= 0 or mag > 40:
		return
	var w = _pips.rect_size.x
	var step: float = min(26.0, w / mag)
	var pw: float = max(2.0, step - 4.0)
	for i in mag:
		var x = w - (mag - i) * step
		var full = i < int(item.ammo)
		_pips.draw_rect(Rect2(Vector2(x, 2), Vector2(pw, 6)), UI.PAPER if full else Color(UI.MUTED.r, UI.MUTED.g, UI.MUTED.b, 0.3))


func _update_center(you: Dictionary, state: String) -> void:
	if state != _last_state:
		_last_state = state
		_state_flash = 2.5
	_state_flash = max(0.0, _state_flash - get_process_delta_time())
	var prompt = str(you.get("prompt", "")) if you.get("prompt") != null else ""
	if prompt.begins_with("["):
		var close = prompt.find("]")
		if close > 0:
			prompt = prompt.substr(close + 1).strip_edges()
	var touch = Controls.device == "touch"
	var interacting = not prompt.empty() and state in ["ok", "downed"]
	var text = ""
	var color = UI.PAPER
	if interacting:
		text = ("" if touch else "[%s]  " % Controls.hint("interact")) + prompt.to_upper()
		# Vending: "BUY X · N SCRAP" turns pink when it can't be afforded.
		var at = prompt.find("· ")
		if prompt.begins_with("BUY") and at > 0:
			var price = int(prompt.substr(at + 2).split(" ")[0])
			var scrap = int(you.get("scrap", 0)) if you.get("scrap") != null else 0
			if price > scrap:
				color = UI.PINK
				text += "  ·  NEED %d MORE" % (price - scrap)
			else:
				color = UI.AMBER
		elif prompt in ["SUIT FULL", "NO DECON CHARGES"]:
			text = prompt.to_upper()
			color = UI.MUTED
	elif state == "turned":
		text = ("BITE" if touch else "[%s]" % Controls.hint("fire")) + "  ATTACK"
		color = Color(0.55, 1.0, 0.3)
	elif state == "downed" and not touch:
		text = "[%s]  CALL FOR HELP" % Controls.hint("ping")
		color = UI.PINK
	elif state == "ok":
		# Empty magazine with reserve: reload prompt (native hud.gd).
		var item: Dictionary = world.current_slot()
		var inv = world.get("inv")
		var reloading = inv is Dictionary and float(inv.get("reload_left", 0.0)) > 0.0
		if item.get("ammo") != null and int(item.ammo) == 0 and int(item.get("reserve", 0) if item.get("reserve") != null else 0) > 0 and not reloading:
			text = ("RELOAD" if touch else "[%s]  RELOAD" % Controls.hint("reload"))
			color = UI.AMBER
	_prompt.visible = not text.empty()
	_prompt.text = text
	_prompt.add_color_override("font_color", color)
	_reticle.targeted = interacting
	_reticle.downed = state == "downed"
	var vit = world.get("vit")
	if state == "downed" and vit is Dictionary:
		var bl = float(vit.get("bleed", 0.0))
		_reticle.bleed = clamp(bl / 20.0, 0.0, 1.0)
		_reticle.bleed_seconds = int(ceil(bl))
	else:
		_reticle.bleed = -1.0
	var prog = float(you.get("interact_progress", 0.0)) if you.get("interact_progress") != null else 0.0
	prog = max(prog, float(you.get("revive", 0.0)) if you.get("revive") != null else 0.0)
	_reticle.progress = prog
	_reticle.visible = state in ["ok", "turned", "downed"] and world.viewmodel.aim < 0.7
	_state_label.text = ""
	match state:
		"turned":
			if _state_flash > 0.0:
				_state_label.text = "TURNED"
			_state_label.add_color_override("font_color", Color(0.55, 1.0, 0.3))
		"out":
			var target = ""
			for o in world.others:
				if o.state in ["ok", "downed"]:
					target = str(o.name).to_upper()
					break
			_state_label.text = ("OUT  ·  SPECTATING " + target) if not target.empty() else "OUT  ·  BACK AT CLEARING"
			_state_label.add_color_override("font_color", UI.PINK)
		"downed":
			if _state_flash > 0.0:
				_state_label.text = "DOWNED"
			_state_label.add_color_override("font_color", UI.PINK)
	_state_label.visible = not _state_label.text.empty()


func _on_draw() -> void:
	var _pt = OS.get_ticks_usec()
	_on_draw_body()
	Settings.prof_add("hud_draw", OS.get_ticks_usec() - _pt)


func _on_draw_body() -> void:
	var size = _draw.rect_size
	var c = size * 0.5
	UI.defer_text(_draw)
	# Damage direction wedges (screen-space, from _receive_hurt_from).
	for a in _arcs:
		var ang: float = a[0] - PI / 2
		var alpha: float = clamp(a[1], 0.0, 1.0)
		UI.ring(_draw, c, 120, ang - 0.4, ang + 0.4, Color(UI.PINK.r, UI.PINK.g, UI.PINK.b, alpha * 0.9), 6, 10)
		var d = Vector2(cos(ang), sin(ang))
		_draw.draw_colored_polygon(PoolVector2Array([c + d * 136, c + d * 126 + d.tangent() * 9, c + d * 126 - d.tangent() * 9]),
			Color(UI.PINK.r, UI.PINK.g, UI.PINK.b, alpha))
	# Teammate name tags with distance; downed teammates off screen get an edge arrow.
	var cam: Vector3 = world.camera.global_transform.origin
	for o in world.others:
		if o.state == "out":
			continue
		var col: Color = UI.PINK if o.state == "downed" else UI.CYAN
		var dist = int(round(cam.distance_to(o.pos)))
		var p = world.to_screen(o.pos + Vector3(0, 2.15, 0), size)
		if p == null or not Rect2(Vector2(20, 20), size - Vector2(40, 40)).has_point(p):
			if o.state == "downed":
				_edge_marker(o.pos, "%s  %dm" % [str(o.name).to_upper(), dist], col, size)
			continue
		var txt: String = str(o.name).to_upper() + ("  DOWN" if o.state == "downed" else "") + ("  %dm" % dist if dist > 8 else "")
		UI.draw_text_centered(_draw, p.x, p.y, txt, 20, col)
		_draw.draw_colored_polygon(PoolVector2Array([p + Vector2(-4, 4), p + Vector2(4, 4), p + Vector2(0, 9)]), col)
	# Supply drop plate (on screen) or edge arrow (off screen).
	var dm = _drop_marker()
	if not dm.empty():
		var dp = world.to_screen(dm.pos + Vector3(0, 1.6, 0), size)
		var dtxt = "DROP  %dm" % int(round(cam.distance_to(dm.pos))) + ("  INBOUND" if dm.air else "")
		if dp == null or not Rect2(Vector2(20, 20), size - Vector2(40, 40)).has_point(dp):
			_edge_marker(dm.pos, dtxt, Color("#ffd56a"), size)
		else:
			_diamond(dp, 7.0, Color("#ffd56a"))
			UI.draw_text_centered(_draw, dp.x, dp.y - 12, dtxt, 18, Color("#ffd56a"))
	# Squad pings (Full tier).
	if "pings" in world:
		for pg in world.pings:
			var pp = world.to_screen(pg[0] + Vector3(0, 0.6, 0), size)
			if pp == null:
				continue
			var pc: Color = UI.PINK if pg[1] in ["enemy", "danger"] else (UI.ACID if pg[1] in ["go", "shelter"] else UI.AMBER)
			pc.a = clamp(pg[2], 0.0, 1.0)
			_diamond(pp, 9.0, pc)
			UI.draw_text_centered(_draw, pp.x, pp.y - 14, str(pg[1]).to_upper(), 18, pc)
	# Damage numbers.
	for n in _numbers:
		var p2 = world.to_screen(n[0], size)
		if p2 != null:
			var col2: Color = n[3]
			col2.a = clamp(n[2] * 2.0, 0.0, 1.0)
			UI.draw_text_centered(_draw, p2.x, p2.y, n[1], 22, col2)
	# Draft timer bar.
	if _overlay_kind == "draft":
		var total = float(_draft.get("time_left", 15.0)) if _draft.get("time_left") != null else 15.0
		var k: float = clamp(_draft_left / max(1.0, total), 0.0, 1.0)
		_draw.draw_rect(Rect2(Vector2(c.x - 460, c.y + 18), Vector2(920 * k, 4)), UI.CYAN)
	UI.flush_text(_draw)


## Airdrop marker for the HUD: {pos, air} or {} (Full tier only).
func _drop_marker() -> Dictionary:
	var d = world.get("drop")
	if d is Dictionary and not d.empty() and d.get("pos") is Vector3:
		return {"pos": d.pos, "air": float(d.get("t", 0.0)) > 0.0}
	return {}


## Arrow + label clamped to the screen edge toward a world position.
func _edge_marker(at: Vector3, text: String, color: Color, size: Vector2) -> void:
	var local: Vector3 = world.camera.global_transform.basis.xform_inv(at - world.camera.global_transform.origin)
	var dir = Vector2(local.x, -local.y)
	if local.z > 0.0 and dir.length() < 0.01:
		dir = Vector2(0, 1)
	if local.z > 0.0:
		dir = Vector2(dir.x, abs(dir.y) * 0.3 + 0.2) if abs(dir.x) < 0.01 else dir
	dir = dir.normalized()
	var c = size * 0.5
	var half = c - Vector2(70, 60)
	var k = min(half.x / max(0.001, abs(dir.x)), half.y / max(0.001, abs(dir.y)))
	var p = c + dir * k
	var t = dir.tangent()
	_draw.draw_colored_polygon(PoolVector2Array([p + dir * 12, p + t * 8, p - t * 8]), color)
	UI.draw_text_centered(_draw, clamp(p.x, 80, size.x - 80), p.y - dir.y * 18 + 6, text, 18, color)


func _diamond(at: Vector2, r: float, color: Color) -> void:
	_draw.draw_colored_polygon(PoolVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), color)
