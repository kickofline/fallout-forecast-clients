extends Node
## App shell: picks the screen from the active session (Thin `Net` or the
## Full/Solo `FullNet`, see FullNet.current()), owns the run World, the HUD,
## the always-on OSD (REC, clock, FPS, ping) and menu navigation.

const Title = preload("res://ui/title.gd")
const Lobby = preload("res://ui/lobby.gd")
const Card = preload("res://ui/card.gd")
const Results = preload("res://ui/results.gd")
const WorldScene = preload("res://world/world.gd")
const FullWorld = preload("res://world/full_world.gd")
const Hud = preload("res://ui/hud.gd")
const Osd = preload("res://ui/osd.gd")
const Backdrop = preload("res://ui/backdrop.gd")
const MenuNav = preload("res://ui/menu_nav.gd")

var world: Node
var hud: Node
var _ui_layer = CanvasLayer.new()
var _nav_layer = CanvasLayer.new()
var _screen_root = Control.new()
var _backdrop: Control
var _screen: Control
var _screen_kind = ""
var _osd: Node
var _nav: Control
var _results_data = {}
var _show_results = false
var _pending_map = ""
var _load_wait = 0


func _ready() -> void:
	# Run after the world/HUD each frame so Controls edges are seen first.
	process_priority = 100
	Settings.apply_cmdline()
	print("DISPLAY window=%s stretch=%s base=%dx%d batching=%s" % [str(OS.window_size),
		ProjectSettings.get_setting("display/window/stretch/mode"),
		ProjectSettings.get_setting("display/window/size/width"), ProjectSettings.get_setting("display/window/size/height"),
		str(ProjectSettings.get_setting("rendering/batching/options/use_batching"))])
	OS.low_processor_usage_mode = false
	_ui_layer.layer = 10
	add_child(_ui_layer)
	_screen_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_screen_root.theme = UI.theme()
	_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_screen_root)
	_backdrop = Backdrop.new()
	_screen_root.add_child(_backdrop)
	_osd = Osd.new()
	add_child(_osd)
	_nav_layer.layer = 20
	add_child(_nav_layer)
	_nav = MenuNav.new()
	_nav_layer.add_child(_nav)
	for n in [Net, FullNet]:
		n.connect("phase_changed", self, "_on_phase")
		n.connect("status_changed", self, "_on_status")
		n.connect("load_requested", self, "_on_load")
		n.connect("results", self, "_on_results")
		n.connect("failed", self, "_on_failed")
	get_tree().connect("screen_resized", self, "_on_resized")
	if "--capture" in Settings.args() or _has_arg("--capture="):
		var cap = load("res://core/capture.gd").new()
		cap.name = "Capture"
		add_child(cap)
	if _has_arg("--full-drive"):
		# Desktop test driver (tests/ is not exported).
		var drv = load("res://tests/full_drive.gd")
		if drv:
			var d = drv.new()
			d.name = "FullDrive"
			add_child(d)
	if _has_arg("--autoconnect"):
		Net.connect_to(Settings.server_url, Settings.player_name)
	_refresh()


func _has_arg(prefix: String) -> bool:
	for a in Settings.args():
		if str(a).begins_with(prefix):
			return true
	return false


func session() -> Node:
	return FullNet.current()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android back: leave overlays / step back, never quit mid-run.
		if hud and hud.has_method("toggle_menu"):
			hud.toggle_menu()
		elif _screen_kind == "results":
			back_to_lobby()


func _on_resized() -> void:
	if world:
		world.resize()


func _on_phase(_p) -> void:
	_refresh()


func _on_status(state, _msg) -> void:
	if state == "results":
		_show_results = true
	if state in ["lobby", "connecting", "disconnected", "joining"] and world and not _show_results:
		_end_run()
	_refresh()


func _on_failed(_why) -> void:
	_end_run()
	_refresh()


func _on_results(data) -> void:
	_results_data = data
	_show_results = true
	_screen_kind = ""  # rebuild even if status "results" already showed it
	_end_run()
	_refresh()


func back_to_lobby() -> void:
	_show_results = false
	_results_data = {}
	if FullNet.active:
		FullNet.back_to_lobby()
	_refresh()


func _on_load(map_id) -> void:
	_end_run()
	_show_results = false
	_pending_map = str(map_id)
	_load_wait = 2
	_refresh()


func _process(_delta: float) -> void:
	# Build the world a couple of frames after the loading card is up so the
	# card actually draws before the (blocking) map load.
	if _load_wait > 0:
		_load_wait -= 1
		if _load_wait == 0:
			_start_run(_pending_map)
	_nav.set_root(_nav_root())
	if hud and is_instance_valid(hud) and Controls.pressed("pause") and hud.has_method("toggle_menu"):
		hud.toggle_menu()
	Controls.consume_frame()


func _nav_root() -> Control:
	var r: Control = null
	if hud and is_instance_valid(hud) and hud.visible and hud.has_method("nav_root"):
		r = hud.nav_root()
	elif _screen and is_instance_valid(_screen):
		r = _screen
	if r:
		# A settings sheet opened on top takes over.
		for i in range(r.get_child_count() - 1, -1, -1):
			var c = r.get_child(i)
			if c is Control and c.visible and c.get_script() == preload("res://ui/settings_panel.gd"):
				return c
	return r


func _start_run(map_id: String) -> void:
	_end_run()
	world = FullWorld.new() if FullNet.active else WorldScene.new()
	world.name = "World"
	add_child(world)
	move_child(world, 0)
	world.load_map(map_id)
	hud = Hud.new()
	hud.name = "Hud"
	hud.world = world
	add_child(hud)
	_refresh()


func _end_run() -> void:
	if hud:
		hud.queue_free()
		hud = null
	if world:
		if FullNet.active and FullNet.world == world:
			FullNet.unregister_world(world)
		world.queue_free()
		world = null
		Sound.attach_world(null)
	Controls.capture_mouse(false)


func _refresh() -> void:
	var kind = "title"
	var net = session()
	var full = FullNet.active
	match net.phase:
		"offline":
			kind = "results" if _show_results else "title"
		"connecting":
			kind = "joining" if full and FullNet.mode == "solo" else "title"
		"retuning":
			kind = "retuning" if world == null else ""
		"online":
			match net.state:
				"lobby":
					kind = "results" if _show_results else ("joining" if full and FullNet.mode == "solo" else "lobby")
				"loading":
					kind = "loading"
				"run":
					kind = "loading" if world == null or not world.ready_to_play else ""
				"results":
					kind = "results" if _show_results else "loading"
				_:
					kind = "joining"
	if _load_wait > 0:
		kind = "loading"
	_set_screen(kind)
	if hud:
		hud.visible = kind == "" and not Settings.has_arg("--no-hud")
	_backdrop.visible = kind != "" and kind != "loading_world"
	_osd.set_mode("run" if kind == "" else "menu")


func _set_screen(kind: String) -> void:
	if kind == _screen_kind and _screen and is_instance_valid(_screen):
		if _screen.has_method("refresh"):
			_screen.refresh()
		return
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null
	_screen_kind = kind
	var net = session()
	match kind:
		"title":
			_screen = Title.new()
		"lobby":
			_screen = Lobby.new()
		"results":
			_screen = Results.new()
			_screen.data = _results_data
			_screen.main = self
		"loading":
			var map_name = _map_name(_pending_map if not _pending_map.empty() else net.current_map)
			_screen = Card.new()
			_screen.setup("TUNING IN", map_name.to_upper(), net.status_msg)
			_screen.provider = self
		"joining":
			_screen = Card.new()
			var what = "CLOUD PLAY"
			if FullNet.active:
				what = "SOLO" if FullNet.mode == "solo" else "CLOUD FULL"
			_screen.setup("JOINING", what, net.status_msg if not net.status_msg.empty() else "CONNECTING TO THE STORM")
		"retuning":
			_screen = Card.new()
			_screen.setup("SIGNAL LOST", "RETUNING", net.last_error)

	if _screen:
		_screen.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		_screen_root.add_child(_screen)


func load_text() -> String:
	if world and is_instance_valid(world):
		return world.load_text()
	return "LOADING MAP" if _load_wait > 0 else ""


func _map_name(id: String) -> String:
	for m in session().maps:
		if m is Dictionary and str(m.get("id", "")) == id:
			return str(m.get("name", id))
	return id.replace("_", " ")


## Called by the world once the map is in and it is ready to play.
func world_ready() -> void:
	_refresh()
