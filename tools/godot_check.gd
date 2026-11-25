extends SceneTree
# Compile every client script (CLI: godot --path client --no-window -s ../tools/godot_check.gd)
func _init():
	var bad := 0
	var dirs := ["res://core", "res://ui", "res://world", "res://"]
	for d in dirs:
		var dir := Directory.new()
		if dir.open(d) != OK:
			continue
		dir.list_dir_begin(true, true)
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".gd"):
				var path: String = d.plus_file(f)
				var s = load(path)
				if s == null or not s.can_instance():
					print("BAD ", path)
					bad += 1
			f = dir.get_next()
	print("CHECK done, bad=", bad)
	quit(1 if bad else 0)
