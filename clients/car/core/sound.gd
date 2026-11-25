extends Node
## Cue playback from the exported assets/audio/sound_map.json:
## cues {name: {file, trim_db, cap_db}}, music {name: {file, loop}},
## ambience_loops {name: {file, gain}}. Unknown cues are ignored.
##
## Car notes: Godot 3's importer marks every .ogg as looping, so one-shot
## cues (footsteps, gunshots, hits) used to loop until their voice was
## reused; with every voice busy that was a constant buzz and 20+ Vorbis
## decoders on the audio thread. One-shots are forced to not loop, prefer the
## PCM .wav that tools/sync_assets.py decodes beside each .ogg, and reuse a
## voice that already holds the stream (assigning .stream takes the audio
## driver lock; the OpenSL callback outputs silence when it can't get it).

const VOICES = 10
const VOICES_3D = 8
const MAX_SAME_CUE = 3          # concurrent voices per stream

var _players = []
var _players_3d = []
var _streams = {}
var _cues = {}
var _music_specs = {}
var _loops = {}
var _music: AudioStreamPlayer
var _ambience = {}
var _recent = {}
var _started = {}               # player -> start ms (voice stealing)


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	for i in VOICES:
		var p = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	reload()
	print("AUDIO mix_rate=%d latency=%.1fms voices=%d+%d" % [AudioServer.get_mix_rate(),
		AudioServer.get_output_latency() * 1000.0, VOICES, VOICES_3D])


func reload() -> void:
	var sm: Dictionary = Assets.sound_map()
	_cues = sm.get("cues", {}) if sm.get("cues") is Dictionary else {}
	_music_specs = sm.get("music", {}) if sm.get("music") is Dictionary else {}
	_loops = sm.get("ambience_loops", {}) if sm.get("ambience_loops") is Dictionary else {}
	_streams.clear()


## 3D voices live under the world so they can be positioned.
func attach_world(world: Node) -> void:
	_started.clear()
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
		# The distance low-pass costs a filter per voice on the car's CPU.
		p.attenuation_filter_db = 0.0
		world.add_child(p)
		_players_3d.append(p)


func _stream(file: String, loop := false) -> AudioStream:
	var p = Assets.path(file)
	var key = p + ("#loop" if loop else "")
	if not _streams.has(key):
		var src = p
		if p.ends_with(".ogg") and ResourceLoader.exists(p.get_basename() + ".wav"):
			src = p.get_basename() + ".wav"
		var t0 = OS.get_ticks_msec()
		var s = load(src) if ResourceLoader.exists(src) else null
		if OS.get_ticks_msec() - t0 > 30:
			print("AUDIO slow load %s %dms" % [src, OS.get_ticks_msec() - t0])
		if s:
			# Loop flags live on the shared resource: loops get their own copy.
			if loop:
				s = s.duplicate()
			if s is AudioStreamSample:
				s.loop_mode = AudioStreamSample.LOOP_FORWARD if loop else AudioStreamSample.LOOP_DISABLED
				if loop:
					s.loop_begin = 0
					s.loop_end = int(s.get_length() * s.mix_rate)
			elif s is AudioStreamOGGVorbis:
				s.loop = loop
		_streams[key] = s
	return _streams[key]


## A free voice, preferring one that already holds `stream` (no set_stream
## lock); caps concurrent copies of one stream by restarting its oldest.
func _voice(pool: Array, stream: AudioStream):
	var same = []
	var free_same = null
	var free_any = null
	var oldest = null
	for p in pool:
		if not is_instance_valid(p):
			continue
		var busy = p.playing
		if p.stream == stream:
			if busy:
				same.append(p)
			elif free_same == null:
				free_same = p
		if not busy and free_any == null:
			free_any = p
		if oldest == null or int(_started.get(p, 0)) < int(_started.get(oldest, 0)):
			oldest = p
	if same.size() >= MAX_SAME_CUE:
		var o = same[0]
		for p in same:
			if int(_started.get(p, 0)) < int(_started.get(o, 0)):
				o = p
		return o
	if free_same:
		return free_same
	return free_any if free_any else oldest


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
	var p: AudioStreamPlayer = _voice(_players, r[0])
	if p == null:
		return
	if p.stream != r[0]:
		p.stream = r[0]
	_started[p] = now
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
	var p = _voice(_players_3d, r[0])
	if p == null or not p.is_inside_tree():
		return
	p.global_transform.origin = at
	if p.stream != r[0]:
		p.stream = r[0]
	_started[p] = OS.get_ticks_msec()
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
