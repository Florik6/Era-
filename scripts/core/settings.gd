extends Node
## Player-facing settings: graphics profile, fog, audio, controls.
## Stored in user://settings.cfg (separate from game saves).

const PATH := "user://settings.cfg"

enum Quality { LOW, MEDIUM, HIGH, AUTO }

var quality: int = Quality.AUTO
var effective_quality: int = Quality.MEDIUM
var fog_enabled := true
var fog_density := 0.5          # legacy multiplier (kept for old settings files)
var fog_level := 2              # 0 off, 1 light, 2 standard (both are see-through)
var cinematics := 2             # 0 off, 1 short, 2 full
var effects_intensity := 1.0    # colour/screen effects of events (blood moon tint, flashes)
var music_vol := 0.7
var sfx_vol := 0.85
var render_scale := 1.0         # extra multiplier on top of quality profile
var show_fps := false
var joystick_size := 1.0
var button_size := 1.0
var camera_zoom := 1.0
var aim_assist := true
var auto_pickup := true
var dev_unlock_all := false     # test option: open all eras
var vibration := true

# Auto-quality runtime measurement
var _fps_samples: Array = []
var _auto_timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	_pick_auto_quality()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	quality = cf.get_value("gfx", "quality", quality)
	fog_enabled = cf.get_value("gfx", "fog_enabled", fog_enabled)
	fog_density = cf.get_value("gfx", "fog_density", fog_density)
	fog_level = cf.get_value("gfx", "fog_level", fog_level)
	cinematics = cf.get_value("gfx", "cinematics", cinematics)
	effects_intensity = cf.get_value("gfx", "effects_intensity", effects_intensity)
	render_scale = cf.get_value("gfx", "render_scale", render_scale)
	show_fps = cf.get_value("gfx", "show_fps", show_fps)
	music_vol = cf.get_value("audio", "music", music_vol)
	sfx_vol = cf.get_value("audio", "sfx", sfx_vol)
	joystick_size = cf.get_value("ctrl", "joystick", joystick_size)
	button_size = cf.get_value("ctrl", "buttons", button_size)
	camera_zoom = cf.get_value("ctrl", "zoom", camera_zoom)
	aim_assist = cf.get_value("ctrl", "aim_assist", aim_assist)
	auto_pickup = cf.get_value("ctrl", "auto_pickup", auto_pickup)
	vibration = cf.get_value("ctrl", "vibration", vibration)
	dev_unlock_all = cf.get_value("dev", "unlock_all", dev_unlock_all)

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("gfx", "quality", quality)
	cf.set_value("gfx", "fog_enabled", fog_enabled)
	cf.set_value("gfx", "fog_density", fog_density)
	cf.set_value("gfx", "fog_level", fog_level)
	cf.set_value("gfx", "cinematics", cinematics)
	cf.set_value("gfx", "effects_intensity", effects_intensity)
	cf.set_value("gfx", "render_scale", render_scale)
	cf.set_value("gfx", "show_fps", show_fps)
	cf.set_value("audio", "music", music_vol)
	cf.set_value("audio", "sfx", sfx_vol)
	cf.set_value("ctrl", "joystick", joystick_size)
	cf.set_value("ctrl", "buttons", button_size)
	cf.set_value("ctrl", "zoom", camera_zoom)
	cf.set_value("ctrl", "aim_assist", aim_assist)
	cf.set_value("ctrl", "auto_pickup", auto_pickup)
	cf.set_value("ctrl", "vibration", vibration)
	cf.set_value("dev", "unlock_all", dev_unlock_all)
	var tmp := PATH + ".tmp"
	if cf.save(tmp) == OK:
		DirAccess.rename_absolute(tmp, PATH)

func _pick_auto_quality() -> void:
	if quality != Quality.AUTO:
		effective_quality = quality
		return
	var cores := OS.get_processor_count()
	if OS.has_feature("mobile"):
		effective_quality = Quality.MEDIUM if cores >= 8 else Quality.LOW
	else:
		effective_quality = Quality.HIGH

func set_quality(q: int) -> void:
	quality = q
	_pick_auto_quality()
	apply()

## Profile parameters consumed by world/render code.
func profile() -> Dictionary:
	match effective_quality:
		Quality.LOW:
			return {"scale": 0.7, "shadows": false, "shadow_size": 1024, "chunk_radius": 2, "max_npcs": 12,
				"particles": 0.4, "props": 0.55, "lod_bias": 0.6, "glow": false,
				"grass": 0.35, "detail_dist": 28.0, "fx": 0, "lights": 4, "decals": false, "ambient_life": false}
		Quality.HIGH:
			return {"scale": 1.0, "shadows": true, "shadow_size": 2048, "chunk_radius": 3, "max_npcs": 26,
				"particles": 1.0, "props": 1.0, "lod_bias": 1.2, "glow": true,
				"grass": 1.0, "detail_dist": 55.0, "fx": 2, "lights": 12, "decals": true, "ambient_life": true}
		_:
			return {"scale": 0.85, "shadows": true, "shadow_size": 1024, "chunk_radius": 2, "max_npcs": 18,
				"particles": 0.7, "props": 0.8, "lod_bias": 1.0, "glow": true,
				"grass": 0.7, "detail_dist": 40.0, "fx": 1, "lights": 8, "decals": true, "ambient_life": true}

func apply() -> void:
	var p := profile()
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(p.scale * render_scale, 0.4, 1.0)
		vp.mesh_lod_threshold = 1.0 / p.lod_bias
	Events.settings_changed.emit()
	if has_node("/root/Audio"):
		get_node("/root/Audio").apply_volumes()

## Fog density actually used by the environment. Capped so the screen never
## becomes an opaque grey mass (see design requirement on fog).
func fog_value(base: float) -> float:
	if not fog_enabled or fog_level <= 0:
		return 0.0
	var k := 0.45 if fog_level == 1 else 1.0
	return clampf(base * k, 0.0, 0.012)

## Profile value with a default (Visual Quality Manager entry point).
func vq(key: String, default = null):
	return profile().get(key, default)

func _process(delta: float) -> void:
	if quality != Quality.AUTO:
		return
	_auto_timer += delta
	if _auto_timer < 1.0:
		return
	_auto_timer = 0.0
	if not has_node("/root/Game") or get_node("/root/Game").player == null:
		return
	_fps_samples.append(Engine.get_frames_per_second())
	if _fps_samples.size() < 8:
		return
	var avg := 0.0
	for f in _fps_samples:
		avg += f
	avg /= _fps_samples.size()
	_fps_samples.clear()
	if avg < 24.0 and effective_quality > Quality.LOW:
		effective_quality -= 1
		apply()
	elif avg > 57.0 and effective_quality < Quality.HIGH and not OS.has_feature("mobile"):
		effective_quality += 1
		apply()
