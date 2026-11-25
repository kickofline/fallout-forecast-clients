extends RefCounted
## Copies fonts, UI icons & map previews (plus PNG conversions of .webp previews
## for Godot 3.6 GLES2 compatibility), and all music/SFX audio files, and emits
## assets/audio/sound_map.json mapping every Sound cue name to its file & mix metadata.


func export_ui_and_audio(baker: RefCounted, out_dir: String) -> Dictionary:
	print("[UI & Audio] Copying fonts, UI art, audio, and building sound_map.json...")
	var game_root := ProjectSettings.globalize_path("res://")

	# 1. Fonts
	var fonts := _copy_dir_files(game_root.path_join("assets/fonts"), out_dir.path_join("fonts"), ["ttf", "otf", "txt"])

	# 2. UI icons & map previews
	var ui_items := _copy_dir_files(game_root.path_join("assets/ui/items"), out_dir.path_join("ui/items"), ["png"])
	var ui_root := _copy_dir_files(game_root.path_join("assets/ui"), out_dir.path_join("ui"), ["png", "webp"])
	# Also save PNG copies of any .webp map previews so Godot 3.6 can load PNG directly without webp quirks.
	for rel in ui_root.duplicate():
		if str(rel).ends_with(".webp"):
			var src_res := "res://assets/ui/" + str(rel).get_file()
			var tex := load(src_res) as Texture2D
			if tex != null:
				var img := tex.get_image()
				if img != null:
					if img.is_compressed():
						img.decompress()
					var png_name := str(rel).get_file().get_basename() + ".png"
					var png_abs := out_dir.path_join("ui/" + png_name)
					img.save_png(png_abs)
					ui_root.append("ui/" + png_name)

	# 3. Audio: music & sfx
	var music_files := _copy_dir_files(game_root.path_join("assets/audio/music"), out_dir.path_join("audio/music"), ["wav", "ogg"])
	var sfx_files := _copy_dir_files(game_root.path_join("assets/audio/sfx"), out_dir.path_join("audio/sfx"), ["wav", "ogg", "txt"])
	_copy_single(game_root.path_join("assets/audio/CREDITS.md"), out_dir.path_join("audio/CREDITS.md"))

	# 4. Build sound_map.json from game/sound.gd
	var sound_script: Script = load("res://game/sound.gd") as Script
	var sound_node := Node.new()
	sound_node.set_script(sound_script)

	var cue_source: Dictionary = sound_script.get("CUE_SOURCE")
	var cue_trim: Dictionary = sound_script.get("CUE_TRIM_DB")
	var cue_cap: Dictionary = sound_script.get("CUE_CAP_DB")
	var score_list: Array = sound_script.get("SCORE")
	var attack_tells: Array = sound_script.get("ATTACK_TELLS")
	var weapon_cap: float = float(sound_script.get("WEAPON_CAP_DB"))

	# Map stem -> relative audio path
	var sfx_by_stem := {}
	for f in sfx_files:
		var s := str(f)
		if s.ends_with(".wav") or s.ends_with(".ogg"):
			var stem := s.get_file().get_basename()
			# Match game/sound.gd: .wav preferred over .ogg if both exist
			if not sfx_by_stem.has(stem) or s.ends_with(".wav"):
				sfx_by_stem[stem] = s

	var cues := {}
	for stem in sfx_by_stem:
		cues[stem] = _build_cue_entry(sound_node, stem, sfx_by_stem[stem], cue_trim, cue_cap, attack_tells, weapon_cap)
	# Include aliased cue names from Sound.CUE_SOURCE (ui_focus -> reel_tick, ui_tick -> reel_tick)
	for alias in cue_source:
		var target := str(cue_source[alias])
		if sfx_by_stem.has(target):
			var e := _build_cue_entry(sound_node, str(alias), sfx_by_stem[target], cue_trim, cue_cap, attack_tells, weapon_cap)
			e["alias_of"] = target
			cues[str(alias)] = e

	var music_map := {}
	for m in score_list:
		var rel_m := "audio/music/%s.wav" % str(m)
		music_map[str(m)] = {"file": rel_m, "bus": "Music", "loop": true}

	var ambience_map := {
		"rain": {"file": "audio/sfx/rain.wav", "bus": "Rain", "loop": true, "gain": 0.50},
		"storm_wind": {"file": "audio/sfx/storm_wind.wav", "bus": "Rain", "loop": true},
		"gun_bait_loop": {"file": "audio/sfx/gun_bait_loop.wav", "bus": "Threats", "loop": true},
	}

	var sound_map := {
		"buses": ["Music", "Weapons", "Threats", "UI", "Ambience", "Rain", "Foley"],
		"music": music_map,
		"ambience_loops": ambience_map,
		"cues": cues,
		"synthesized_at_runtime": [],
		"runtime_dsp_effects_notes": [
			"All SFX and music stems are pre-rendered offline by tools/audio/gen_*.py into .wav/.ogg; zero audio waveforms are synthesized at runtime.",
			"Desktop-only runtime bus DSP in game/sound.gd (disabled on Web and optional on Android GLES2): AudioEffectLowPassFilter on Rain bus (16000 Hz outside -> 1500 Hz sheltered), AudioEffectCompressor sidechain on Music ducked by Weapons (-22 dB threshold, 3:1 ratio), AudioEffectHardLimiter on Master (-1.5 dB ceiling).",
		],
	}
	baker.write_json(out_dir.path_join("audio/sound_map.json"), sound_map)
	sound_node.free()

	print("  -> Copied %d fonts, %d UI files, %d music tracks, %d SFX cues" % [fonts.size(), ui_items.size() + ui_root.size(), music_files.size(), cues.size()])
	return {
		"fonts": fonts,
		"ui_items": ui_items,
		"ui_screens": ui_root,
		"music": music_files,
		"sfx_count": cues.size(),
		"sound_map": "audio/sound_map.json",
	}


func _build_cue_entry(sound_node: Node, cue: String, rel_path: String, cue_trim: Dictionary, cue_cap: Dictionary, attack_tells: Array, weapon_cap: float) -> Dictionary:
	var bus := str(sound_node.call("bus_for", cue))
	var is_fire := bool(sound_node.call("_is_fire", cue))
	var is_tell := cue in attack_tells
	var default_cap := weapon_cap if is_fire else (-6.0 if is_tell else -10.0)
	return {
		"file": rel_path,
		"bus": bus,
		"trim_db": float(cue_trim.get(cue, 0.0)),
		"cap_db": float(cue_cap.get(cue, default_cap)),
		"is_fire": is_fire,
		"is_attack_tell": is_tell,
	}


func _copy_dir_files(src_dir: String, dst_dir: String, exts: Array) -> Array:
	var copied := []
	var da := DirAccess.open(src_dir)
	if da == null:
		return copied
	DirAccess.make_dir_recursive_absolute(dst_dir)
	# Compute path prefix relative to assets out_dir (last 1 or 2 segments)
	var out_marker := "/assets/"
	var norm_dst := dst_dir.replace("\\", "/")
	var rel_prefix := ""
	var idx := norm_dst.rfind(out_marker)
	if idx >= 0:
		rel_prefix = norm_dst.substr(idx + out_marker.length())
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir():
			var ext := fname.get_extension().to_lower()
			if ext in exts:
				if _copy_single(src_dir.path_join(fname), dst_dir.path_join(fname)):
					copied.append(rel_prefix.path_join(fname) if not rel_prefix.is_empty() else fname)
		fname = da.get_next()
	da.list_dir_end()
	copied.sort()
	return copied


func _copy_single(src: String, dst: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var fin := FileAccess.open(src, FileAccess.READ)
	if fin == null:
		return false
	var bytes := fin.get_buffer(fin.get_length())
	fin.close()
	var fout := FileAccess.open(dst, FileAccess.WRITE)
	if fout == null:
		return false
	fout.store_buffer(bytes)
	fout.close()
	return true
