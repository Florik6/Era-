class_name DayNight
extends Node
## Smooth dawn / day / sunset / night cycle driven by Game.hour(). Night uses
## moonlight so the battlefield stays readable. Supports a blood-moon override.

var env: WorldEnvironment
var sun: DirectionalLight3D
var era := 0
var sky_mat: ProceduralSkyMaterial
var overrides := {}
var weather = null              # optional Weather reference (sun multiplier)
var time_override := -1.0       # tests: fixed hour
var _lf := 1.0
var _first := true

func setup(world_env: WorldEnvironment, sun_light: DirectionalLight3D, era_i: int) -> void:
	env = world_env
	sun = sun_light
	era = era_i
	if env.environment == null:
		env.environment = Environment.new()
	var e := env.environment
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.18
	e.adjustment_contrast = 1.06
	if not Events.settings_changed.is_connected(_apply_settings):
		Events.settings_changed.connect(_apply_settings)
	_apply_settings()
	_first = true
	_update(1.0)

func _apply_settings() -> void:
	if sun == null:
		return
	var p := Settings.profile()
	sun.shadow_enabled = p.get("shadows", true)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.05
	if env and env.environment:
		env.environment.glow_enabled = p.get("glow", false)
		env.environment.glow_intensity = 0.6
		env.environment.glow_bloom = 0.05

func set_override(nm: String, on: bool) -> void:
	if on:
		overrides[nm] = true
	else:
		overrides.erase(nm)

func light_factor() -> float:
	return _lf

func hour() -> float:
	return time_override if time_override >= 0.0 else Game.hour()

func _process(delta: float) -> void:
	_update(minf(1.0, delta * 1.5))

func _update(k: float) -> void:
	if sun == null or env == null or env.environment == null:
		return
	if _first:
		k = 1.0
		_first = false
	var e: Dictionary = DBEras.era(era)
	var h := hour()
	var t := (h - 6.0) / 12.0
	var elev := sin(t * PI) if t >= 0.0 and t <= 1.0 else -0.4
	var day := clampf(elev * 3.0, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0) if t > -0.1 and t < 1.1 else 0.0
	var blood := overrides.has("blood_moon")
	var sun_c: Color = e.sun
	var moon_c := Color(0.55, 0.64, 0.9)
	if blood:
		moon_c = Color(1.0, 0.32, 0.25)
	var col := moon_c.lerp(sun_c, day).lerp(Color(1.0, 0.6, 0.35), dusk * 0.6)
	var energy := lerpf(0.5 if not blood else 0.55, 1.4, day)
	var wm := 1.0
	var w = weather
	if w == null and Game.world and Game.world.get("weather"):
		w = Game.world.weather
	if w != null and w.get("sun_mult") != null:
		wm = w.sun_mult
	energy *= wm
	var in_dim := false
	if Game.world != null and is_instance_valid(Game.world):
		var dimv = Game.world.get("dimension")
		in_dim = dimv != null and str(dimv) != ""
	if in_dim:
		# a rift / pocket dimension owns its sky and light colour
		sun.light_energy = lerpf(sun.light_energy, 1.0, k)
		_lf = 0.8
		return
	sun.light_color = sun.light_color.lerp(col, k)
	sun.light_energy = lerpf(sun.light_energy, energy, k)
	var target_rot: Vector3
	if day > 0.0:
		target_rot = Vector3(deg_to_rad(-(18.0 + 55.0 * maxf(elev, 0.0))), deg_to_rad(lerpf(-70.0, 70.0, clampf(t, 0.0, 1.0))), 0.0)
	else:
		target_rot = Vector3(deg_to_rad(-55.0), deg_to_rad(25.0), 0.0)
	if k >= 1.0 or absf(day - _lf) > 0.5:
		sun.rotation = target_rot
	else:
		sun.rotation = sun.rotation.lerp(target_rot, k)
	var en := env.environment
	var amb: Color = (e.ambient as Color).lerp(e.sun as Color, 0.35)
	var night_amb := Color(0.36, 0.42, 0.62) if not blood else Color(0.55, 0.25, 0.25)
	en.ambient_light_color = en.ambient_light_color.lerp(night_amb.lerp(amb, day), k)
	var amb_boost := 0.22 if era == 4 else (0.08 if era == 2 else 0.0)
	en.ambient_light_energy = lerpf(en.ambient_light_energy, (lerpf(0.62, 0.48, day) + amb_boost) * (0.85 + 0.15 * wm), k)
	var top: Color = e.sky_top
	var hor: Color = e.sky_horizon
	var n_top := Color(0.04, 0.06, 0.16)
	var n_hor := Color(0.12, 0.15, 0.28)
	if blood:
		n_top = Color(0.22, 0.02, 0.04)
		n_hor = Color(0.55, 0.1, 0.08)
	var s_top := n_top.lerp(top, day).lerp(Color(0.35, 0.25, 0.5), dusk * 0.5)
	var s_hor := n_hor.lerp(hor, day).lerp(Color(0.98, 0.55, 0.32), dusk * 0.7)
	if wm < 0.9:
		var grey := Color(0.5, 0.52, 0.55) * (0.3 + 0.7 * day)
		s_top = s_top.lerp(grey, (1.0 - wm) * 1.2)
		s_hor = s_hor.lerp(grey.lightened(0.1), (1.0 - wm) * 1.2)
	sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(s_top, k)
	sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(s_hor, k)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	sky_mat.ground_bottom_color = s_hor.darkened(0.6)
	sky_mat.sun_angle_max = 25.0
	_lf = clampf(0.25 + 0.75 * day, 0.25, 1.0)
