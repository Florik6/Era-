extends Node
## Loads every script in the project to surface parse/compile errors.
func _ready() -> void:
	var bad := 0
	var files: Array = []
	_collect("res://scripts", files)
	for f in files:
		var s = load(f)
		if s == null or (s is GDScript and not s.can_instantiate() and not f.ends_with("_db.gd")):
			print("FAILED: ", f)
			bad += 1
	print("LOAD_ALL_DONE files=%d bad=%d" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)

func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)
