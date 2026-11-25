extends Node
## App shell: picks the screen from the connection phase and bridge status,
## owns the run World, the HUD and the always-on OSD (REC, clock, FPS, ping).

const Title = preload("res://ui/title.gd")
const Lobby = preload("res://ui/lobby.gd")
const Card = preload("res://ui/card.gd")
const Results = preload("res://ui/results.gd")
const WorldScene = preload("res://world/world.gd")
const Hud = preload("res://ui/hud.gd")
const Osd = preload("res://ui/osd.gd")
const Backdrop = preload("res://ui/backdrop.gd")

var world: Node
var hud: Node
var _ui_layer = CanvasLayer.new()
var _screen_root = Control.new()
var _backdrop: Control
var _screen: Control
var _screen_kind = ""
var _osd: Node
var _results_data = {}
var _show_results = false
var _pending_map = ""
var _load_wait = 0


func _ready() -> void:
	Settings.apply_cmdline()
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
	Net.connect("phase_changed", self, "_on_phase")
	Net.connect("status_changed", self, "_on_status")
	Net.connect("load_requested", self, "_on_load")
	Net.connect("results", self, "_on_results")
	Net.connect("failed", self, "_on_failed")
	get_tree().connect("screen_resized", self, "_on_resized")
	if "--capture" in OS.get_cmdline_args() or _has_arg("--capture="):
		var cap = load("res://core/capture.gd").new()
		cap.name = "Capture"
		add_child(cap)
	if _has_arg("--autoconnect"):
		Net.connect_to(Settings.server_url, Settings.player_name)
	_refresh()


func _has_arg(prefix: String) -> bool:
	for a in OS.get_cmdline_args():
		if str(a).begins_with(prefix):
			return true
	return false


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
	if state in ["lobby", "connecting", "disconnected"] and world and not _show_results:
		_end_run()
	_refresh()


func _on_failed(_why) -> void:
	_end_run()
	_refresh()


func _on_results(data) -> void:
	_results_data = data
	_show_results = true
	_end_run()
	_refresh()


func back_to_lobby() -> void:
	_show_results = false
	_results_data = {}
	_refresh()


func _on_load(map_id) -> void:
	_end_run()
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


func _start_run(map_id: String) -> void:
	_end_run()
	world = WorldScene.new()
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
		world.queue_free()
		world = null
		Sound.attach_world(null)


func _refresh() -> void:
	var kind = "title"
	match Net.phase:
		"offline":
			kind = "results" if _show_results else "title"
		"connecting":
			kind = "title"
		"retuning":
			kind = "retuning" if world == null else ""
		"online":
			match Net.state:
				"lobby":
					kind = "results" if _show_results else "lobby"
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
		hud.visible = kind == ""
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
			var map_name = _map_name(_pending_map if not _pending_map.empty() else Net.current_map)
			_screen = Card.new()
			_screen.setup("TUNING IN", map_name.to_upper(), Net.status_msg)
		"joining":
			_screen = Card.new()
			_screen.setup("JOINING", "CLOUD PLAY", Net.status_msg if not Net.status_msg.empty() else "CONNECTING TO THE STORM")
		"retuning":
			_screen = Card.new()
			_screen.setup("SIGNAL LOST", "RETUNING", Net.last_error)
	if _screen:
		_screen.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		_screen_root.add_child(_screen)


func _map_name(id: String) -> String:
	for m in Net.maps:
		if m is Dictionary and str(m.get("id", "")) == id:
			return str(m.get("name", id))
	return id.replace("_", " ")


## Called by the world once the map is in and the first snapshot arrived.
func world_ready() -> void:
	_refresh()
