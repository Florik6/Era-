extends Node
## Local save system: versioned JSON, atomic writes (tmp + rename) and a
## rotating backup so a crash or app kill never leaves a corrupt save.

const VERSION := 3
const PROFILE := "user://profile.json"
const WORLD_FMT := "user://world_era%d.json"

var last_save_time := 0.0
var autosave_interval := 90.0
var _timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if Game.world == null or Game.player == null or Game.mode != "world":
		return
	_timer += delta
	if _timer >= autosave_interval:
		_timer = 0.0
		save_game()

func write_json(path: String, data: Dictionary) -> bool:
	data["_version"] = VERSION
	data["_saved"] = Time.get_datetime_string_from_system()
	var text := JSON.stringify(data)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Save failed: cannot open " + tmp)
		return false
	f.store_string(text)
	f.flush()
	f.close()
	# verify what we wrote parses back before replacing the old save
	var check := FileAccess.get_file_as_string(tmp)
	if JSON.parse_string(check) == null:
		push_error("Save verification failed for " + path)
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(path + ".bak")
		DirAccess.rename_absolute(path, path + ".bak")
	var err := DirAccess.rename_absolute(tmp, path)
	return err == OK

func read_json(path: String) -> Dictionary:
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			return migrate(parsed)
		push_warning("Corrupt save, trying backup: " + p)
	return {}

func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("_version", 1))
	if v < 2:
		# v1 -> v2: legacy dictionary gained "destroyed" list
		if d.has("legacy") and not d.legacy.has("destroyed"):
			d.legacy.destroyed = []
	if v < 3:
		if d.has("witness") and not d.witness.has("trades"):
			d.witness.trades = 0
	d["_version"] = VERSION
	return d

func has_save() -> bool:
	return FileAccess.file_exists(PROFILE) or FileAccess.file_exists(PROFILE + ".bak")

func save_game() -> bool:
	if not Profile.has_character:
		return false
	if Game.world and Game.world.has_method("sync_to_state") and Game.mode == "world":
		Game.world.sync_to_state()
	var pd := Profile.to_dict()
	pd["chronicle"] = Chronicle.to_dict()
	var ok := write_json(PROFILE, pd)
	if Game.world_state.size() > 0 and Game.mode == "world":
		ok = write_json(WORLD_FMT % Profile.current_era, Game.world_state) and ok
	last_save_time = Time.get_unix_time_from_system()
	return ok

func load_profile() -> bool:
	var d := read_json(PROFILE)
	if d.is_empty():
		return false
	Profile.from_dict(d)
	Chronicle.from_dict(d.get("chronicle", {}))
	return Profile.has_character

func load_world_state(era_i: int) -> Dictionary:
	return read_json(WORLD_FMT % era_i)

func delete_all() -> void:
	for p in [PROFILE] + range(5).map(func(i): return WORLD_FMT % i):
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(p + suffix):
				DirAccess.remove_absolute(p + suffix)
