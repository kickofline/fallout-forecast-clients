extends Node
## Cue playback from the exported assets/audio/sound_map.json:
## cues {name: {file, trim_db, cap_db}}, music {name: {file, loop}},
## ambience_loops {name: {file, gain}}. Unknown cues are ignored.

const VOICES = 12
const VOICES_3D = 10

var _players = []
var _players_3d = []
var _next = 0
var _next_3d = 0
var _streams = {}
var _cues = {}
var _music_specs = {}
var _loops = {}
var _music: AudioStreamPlayer
var _ambience = {}
var _recent = {}


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	for i in VOICES:
		var p = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	reload()


func reload() -> void:
	var sm: Dictionary = Assets.sound_map()
	_cues = sm.get("cues", {}) if sm.get("cues") is Dictionary else {}
	_music_specs = sm.get("music", {}) if sm.get("music") is Dictionary else {}
	_loops = sm.get("ambience_loops", {}) if sm.get("ambience_loops") is Dictionary else {}
	_streams.clear()


## 3D voices live under the world so they can be positioned.
func attach_world(world: Node) -> void:
	for p in _players_3d:
		if is_instance_valid(p):
			p.queue_free()
	_players_3d.clear()
	for k in _ambience.keys():
		if is_instance_valid(_ambience[k]):
			_ambience[k].queue_free()
	_ambience.clear()
	if world == null:
		return
	for i in VOICES_3D:
		var p = AudioStreamPlayer3D.new()
		p.unit_size = 10.0
		p.max_distance = 80.0
		p.attenuation_filter_db = -10.0
		world.add_child(p)
		_players_3d.append(p)


func _stream(file: String, loop := false) -> AudioStream:
	var p = Assets.path(file)
	if not _streams.has(p):
		var s = load(p) if ResourceLoader.exists(p) else null
		if s and loop:
			if s is AudioStreamSample:
				s.loop_mode = AudioStreamSample.LOOP_FORWARD
				s.loop_end = int(s.get_length() * s.mix_rate)
			elif s is AudioStreamOGGVorbis:
				s.loop = true
		_streams[p] = s
	return _streams[p]


func _resolve(cue: String) -> Array:
	var spec = _cues.get(cue)
	if spec == null:
		return []
	var file = ""
	var db = 0.0
	if spec is String:
		file = spec
	elif spec is Dictionary:
		file = str(spec.get("file", ""))
		db = float(spec.get("trim_db", 0.0))
	if file.empty():
		return []
	var s = _stream(file)
	return [] if s == null else [s, db]


func play(cue: String, db := 0.0, pitch := 1.0) -> void:
	# Drop exact repeats inside 40 ms (batched duplicate events).
	var now = OS.get_ticks_msec()
	if now - int(_recent.get(cue, -1000)) < 40:
		return
	_recent[cue] = now
	var r = _resolve(cue)
	if r.empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = r[0]
	p.volume_db = db + r[1]
	p.pitch_scale = pitch * rand_range(0.97, 1.03)
	p.play()


func play_at(cue: String, at: Vector3, db := 0.0) -> void:
	if _players_3d.empty():
		play(cue, db - 4.0)
		return
	var r = _resolve(cue)
	if r.empty():
		return
	var p: AudioStreamPlayer3D = _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _players_3d.size()
	if not is_instance_valid(p) or not p.is_inside_tree():
		return
	p.global_transform.origin = at
	p.stream = r[0]
	p.unit_db = db + r[1]
	p.pitch_scale = rand_range(0.96, 1.04)
	p.play()


func music(name: String, db := -14.0) -> void:
	var spec = _music_specs.get(name)
	if not (spec is Dictionary):
		_music.stop()
		return
	var s = _stream(str(spec.get("file", "")), true)
	if s == null:
		return
	if _music.stream == s and _music.playing:
		return
	_music.stream = s
	_music.volume_db = db
	_music.play()


func stop_music() -> void:
	_music.stop()


## Looping ambience (rain / storm wind) with a target volume; 0 stops it.
func ambience(name: String, level: float) -> void:
	var p: AudioStreamPlayer = _ambience.get(name)
	if level <= 0.01:
		if p and p.playing:
			p.stop()
		return
	if p == null:
		var spec = _loops.get(name)
		if not (spec is Dictionary):
			return
		var s = _stream(str(spec.get("file", "")), true)
		if s == null:
			return
		p = AudioStreamPlayer.new()
		p.stream = s
		add_child(p)
		_ambience[name] = p
	p.volume_db = linear2db(clamp(level, 0.001, 1.0)) - 6.0
	if not p.playing:
		p.play()
