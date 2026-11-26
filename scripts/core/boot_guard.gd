class_name BootGuard
extends RefCounted
## Start-up safety net. Writes the boot stage to user://boot_state.cfg:
## if the previous launch never reached the main menu (crash or hang on a
## heavy graphics setting), the next launch switches to safe graphics
## automatically. Also keeps a short user://boot.log for diagnostics.

const PATH := "user://boot_state.cfg"
const LOG := "user://boot.log"

static func _cf() -> ConfigFile:
	var cf := ConfigFile.new()
	cf.load(PATH)
	return cf

static func previous_failed() -> bool:
	var cf := _cf()
	return String(cf.get_value("boot", "stage", "ok")) == "booting"

static func fail_count() -> int:
	return int(_cf().get_value("boot", "fails", 0))

static func mark(stage: String) -> void:
	var cf := _cf()
	if stage == "booting" and String(cf.get_value("boot", "stage", "ok")) == "booting":
		cf.set_value("boot", "fails", int(cf.get_value("boot", "fails", 0)) + 1)
	elif stage == "ok":
		cf.set_value("boot", "fails", 0)
	cf.set_value("boot", "stage", stage)
	cf.set_value("boot", "time", Time.get_datetime_string_from_system())
	cf.save(PATH)

static func log_line(text: String) -> void:
	var f: FileAccess
	if FileAccess.file_exists(LOG):
		f = FileAccess.open(LOG, FileAccess.READ_WRITE)
		if f and f.get_length() > 24000:
			f.close()
			f = FileAccess.open(LOG, FileAccess.WRITE)
		elif f:
			f.seek_end()
	else:
		f = FileAccess.open(LOG, FileAccess.WRITE)
	if f:
		f.store_line("[%s] %s" % [Time.get_time_string_from_system(), text])
		f.close()

## Lightest graphics that still keep every gameplay cue.
static func apply_safe_graphics() -> void:
	Settings.quality = Settings.Quality.LOW
	Settings.render_scale = 0.75
	Settings.fog_level = 1
	Settings.effects_intensity = minf(Settings.effects_intensity, 0.7)
	Settings.cinematics = mini(Settings.cinematics, 1)
	Settings.save_settings()
