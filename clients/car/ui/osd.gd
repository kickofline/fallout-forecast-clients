extends CanvasLayer
## VHS on-screen display: blinking "● REC ▶", timestamp counting from
## OCT 31 1987 11:47 PM, and the FPS / ping overlay.

const START_SECONDS = 23 * 3600 + 47 * 60

var _root = Control.new()
const Glyph = preload("res://ui/glyph.gd")

var _rec: Label
var _rec_row: HBoxContainer
var _dot: Control
var _stamp: Label
var _perf: Label
var _clock = 0.0
var _mode = "menu"
var _fps_acc = 0.0
var _fps_frames = 0
var _fps = 0.0
var _worst = 0.0
var _log_left = 5.0
var _log_frames = 0
var _last_us = 0
var _d2 = 0.0
var _i2 = 0.0
var spikes = 0
var spike_ms = 0
var _log_us = 0


func _ready() -> void:
	layer = 20
	_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_rec_row = HBoxContainer.new()
	_rec_row.add_constant_override("separation", 8)
	_rec_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rec_row)
	_dot = Glyph.new("rec", UI.PAPER, 18.0)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rec_row.add_child(_dot)
	_rec = UI.hud("REC", 28, UI.PAPER)
	_rec_row.add_child(_rec)
	var play = Glyph.new("play", UI.PAPER, 20.0)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rec_row.add_child(play)
	_stamp = UI.hud("", 22, UI.PAPER)
	_stamp.align = Label.ALIGN_RIGHT
	_root.add_child(_stamp)
	_perf = UI.hud("", 18, UI.ACID)
	_perf.align = Label.ALIGN_RIGHT
	_root.add_child(_perf)
	set_mode("menu")
	VisualServer.connect("frame_pre_draw", self, "_on_pre_draw")
	VisualServer.connect("frame_post_draw", self, "_on_post_draw")


var _pre_us = 0


func _on_pre_draw() -> void:
	_pre_us = OS.get_ticks_usec()


## Time inside VisualServer.draw(): render submission plus any GPU stalls.
func _on_post_draw() -> void:
	if _pre_us > 0:
		Settings.prof_add("render", OS.get_ticks_usec() - _pre_us)


func set_mode(mode: String) -> void:
	_mode = mode
	# In a run the MENU / READY buttons own the top-right corner.
	var right = -250.0 if mode == "run" else -40.0
	UI.place(_rec_row, 1.0, 0.0, right - 110, 14, 110, 30)
	UI.place(_stamp, 1.0, 0.0, right - 170, 46, 170, 50)
	UI.place(_perf, 1.0, 0.0, right - 300, 68 if mode == "run" else 100, 300, 24)
	_stamp.visible = false


func fps() -> float:
	return _fps


func _process(delta: float) -> void:
	var spike = Settings.prof_frame_take()
	var now_us = OS.get_ticks_usec()
	if _mode == "run" and _last_us > 0 and now_us - _last_us > 250000:
		spikes += 1
		spike_ms += (now_us - _last_us) / 1000
	if _last_us > 0 and now_us - _last_us > 250000:
		print("SPIKE frame=%dms delta=%dms nodes=%d %s" % [(now_us - _last_us) / 1000, int(delta * 1000.0),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), spike])
	_last_us = now_us
	_clock += delta
	_fps_acc += delta
	_fps_frames += 1
	_worst = max(_worst, delta)
	if _fps_acc >= 0.5:
		_fps = _fps_frames / _fps_acc
		_fps_acc = 0.0
		_fps_frames = 0
		var rtt = ("%d" % int(Net.rtt_ms)) if Net.rtt_ms >= 0.0 else "--"
		_perf.text = "%d FPS  %d MS  PING %s" % [int(round(_fps)), int(_worst * 1000.0), rtt]
		_worst = 0.0
	_perf.visible = Settings.fps_overlay and not Settings.has_arg("--no-osd")
	_root.visible = not Settings.has_arg("--no-osd")
	_log_left -= delta
	_log_frames += 1
	_d2 += Performance.get_monitor(Performance.RENDER_2D_DRAW_CALLS_IN_FRAME)
	_i2 += Performance.get_monitor(Performance.RENDER_2D_ITEMS_IN_FRAME)
	if _log_left <= 0.0:
		_log_left = 5.0
		print("PROF frame=%.1f items2d=%.0f draws2d=%.0f %s" % [5000.0 / max(1, _log_frames),
			_i2 / max(1, _log_frames), _d2 / max(1, _log_frames), Settings.prof_take(_log_frames)])
		_d2 = 0.0
		_i2 = 0.0
		_log_frames = 0
		# Grepable perf line for adb logcat / desktop stdout.
		print("PERF fps=%.1f mode=%s retro=%s scale=%.2f rtt=%d proc=%.1fms draws=%d verts=%d objs=%d nodes=%d" % [_fps, _mode,
			str(Settings.retro_enabled), Settings.render_scale, int(Net.rtt_ms),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var recording = Settings.reduced_flash or fmod(_clock, 1.0) < 0.6
	_dot.visible = recording
	# The original shows REC only over gameplay (title/lobby have their own OSD).
	_rec_row.visible = Settings.retro_enabled and _mode == "run"
	var s = START_SECONDS + int(_clock)
	var day = 31 + s / 86400
	s %= 86400
	var hour = s / 3600
	var h12 = hour % 12
	if h12 == 0:
		h12 = 12
	var month = "OCT" if day <= 31 else "NOV"
	if day > 31:
		day -= 31
	_stamp.text = "%s %02d 1987\n%2d:%02d:%02d %s" % [month, day, h12, (s / 60) % 60, s % 60, "PM" if hour >= 12 else "AM"]
