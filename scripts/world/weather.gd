class_name Weather
extends Node3D
## Weather states with smooth transitions and auto-cycling: clear, cloudy,
## rain, storm, fog, snow, wind. Precipitation follows the camera target and
## hides indoors. Rain makes actors wet (lightning bonus); storms flash and
## occasionally strike. Fog density goes through Settings.fog_value(), which is
## capped so the screen never turns into an opaque grey mass.

const KINDS := ["clear", "cloudy", "rain", "storm", "fog", "snow", "wind"]
const NAMES := {"clear": "Ясно", "cloudy": "Облачно", "rain": "Дождь", "storm": "Гроза", "fog": "Туман", "snow": "Снег", "wind": "Ветер"}
const WEIGHTS := {"clear": 34.0, "cloudy": 20.0, "rain": 14.0, "storm": 6.0, "fog": 10.0, "snow": 6.0, "wind": 10.0}
const FOG_ADD := {"clear": 0.0, "cloudy": 0.0008, "rain": 0.002, "storm": 0.003, "fog": 0.0055, "snow": 0.003, "wind": 0.0005}
const FOG_SCALE := 0.24
## Hard ceiling for the combined atmosphere (weather + cursed fog + night):
## nearby enemies, attacks and roads must always stay visible.
const MAX_FOG := 0.0026
const SUN := {"clear": 1.0, "cloudy": 0.78, "rain": 0.62, "storm": 0.48, "fog": 0.72, "snow": 0.8, "wind": 0.95}

var current := "clear"
var env: WorldEnvironment
var era := 0
var streamer = null             # ChunkStreamer (for indoor checks)
var day_night = null
var follow: Node3D = null       # camera target override
var overrides := {}
var sun_mult := 1.0
var auto_cycle := true
var _timer := 0.0
var _duration := 150.0
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _wind: GPUParticles3D
var _bolt_light: DirectionalLight3D
var _lightning_t := 8.0
var _flash_t := 0.0
var _wet_t := 0.0
var _indoor_t := 0.0
var _indoor := false
var _amb := {}
var _fog_cur := 0.0
var _rng := RandomNumberGenerator.new()

func setup(world_env: WorldEnvironment, era_i: int) -> void:
	env = world_env
	era = era_i
	_rng.randomize()
	_rain = _make_particles("rain")
	_snow = _make_particles("snow")
	_wind = _make_particles("wind")
	_bolt_light = DirectionalLight3D.new()
	_bolt_light.light_energy = 0.0
	_bolt_light.light_color = Color(0.8, 0.85, 1.0)
	_bolt_light.rotation = Vector3(deg_to_rad(-70), deg_to_rad(20), 0)
	_bolt_light.shadow_enabled = false
	add_child(_bolt_light)
	if not Events.settings_changed.is_connected(_on_settings):
		Events.settings_changed.connect(_on_settings)
	set_weather("clear", 120.0)
	_apply_fog(1.0)

func _make_particles(kind: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "P_" + kind
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	var mesh: Mesh
	var mat: StandardMaterial3D
	match kind:
		"rain":
			pm.emission_box_extents = Vector3(24, 1, 24)
			pm.direction = Vector3(0.12, -1, 0.05)
			pm.spread = 3.0
			pm.initial_velocity_min = 24.0
			pm.initial_velocity_max = 30.0
			pm.gravity = Vector3(0, -12, 0)
			p.lifetime = 1.0
			mesh = MeshLib.box(Vector3(0.025, 0.7, 0.025))
			mat = MeshLib.mat(Color(0.75, 0.82, 0.95, 0.45), 0.0, 1.0, 0.0, true)
		"snow":
			pm.emission_box_extents = Vector3(24, 1, 24)
			pm.direction = Vector3(0.2, -1, 0.1)
			pm.spread = 25.0
			pm.initial_velocity_min = 2.5
			pm.initial_velocity_max = 4.0
			pm.gravity = Vector3(0, -1.5, 0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 0.6
			p.lifetime = 5.5
			mesh = MeshLib.box(Vector3(0.16, 0.16, 0.16))
			mat = MeshLib.mat(Color(0.97, 0.98, 1.0, 0.9), 0.0, 1.0, 0.0, true)
		_:
			pm.emission_box_extents = Vector3(22, 4, 22)
			pm.direction = Vector3(1, -0.05, 0.3)
			pm.spread = 15.0
			pm.initial_velocity_min = 7.0
			pm.initial_velocity_max = 12.0
			pm.gravity = Vector3(0, -0.4, 0)
			pm.angular_velocity_min = -180.0
			pm.angular_velocity_max = 180.0
			p.lifetime = 3.5
			mesh = MeshLib.box(Vector3(0.12, 0.02, 0.08))
			var lc: Color = DBEras.era(era).ground.forest.lightened(0.2) if era <= 1 else Color(0.6, 0.55, 0.45)
			mat = MeshLib.mat(lc, 0.0, 1.0, 0.0, true)
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.material_override = mat
	add_child(p)
	_set_amount(p, kind)
	return p

func _set_amount(p: GPUParticles3D, kind: String) -> void:
	var f: float = Settings.profile().get("particles", 1.0) * clampf(Settings.weather_density, 0.1, 1.0)
	var base: int = {"rain": 900, "snow": 600, "wind": 90}[kind]
	p.amount = maxi(16, int(base * f))

func _on_settings() -> void:
	if _rain:
		_set_amount(_rain, "rain")
		_set_amount(_snow, "snow")
		_set_amount(_wind, "wind")
	_apply_fog(1.0)

func set_weather(kind: String, duration: float = -1.0) -> void:
	if not kind in KINDS:
		return
	current = kind
	_timer = 0.0
	_duration = duration if duration > 0.0 else _rng.randf_range(100.0, 220.0)
	_lightning_t = _rng.randf_range(3.0, 8.0)

func set_override(nm: String, on: bool) -> void:
	if on:
		overrides[nm] = true
	else:
		overrides.erase(nm)
	_apply_fog(0.5)

func is_raining() -> bool:
	return current == "rain" or current == "storm"

func display_name() -> String:
	return NAMES.get(current, current)

func _pick_next() -> String:
	var total := 0.0
	for k in WEIGHTS:
		total += WEIGHTS[k]
	var r := _rng.randf() * total
	for k in WEIGHTS:
		r -= WEIGHTS[k]
		if r <= 0.0:
			return k
	return "clear"

func _target() -> Node3D:
	if follow != null and is_instance_valid(follow):
		return follow
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	return cam

func _process(delta: float) -> void:
	if env == null:
		return
	if auto_cycle:
		_timer += delta
		if _timer >= _duration:
			set_weather(_pick_next())
	sun_mult = lerpf(sun_mult, SUN.get(current, 1.0), minf(1.0, delta * 0.4))
	var tgt := _target()
	var tp := tgt.global_position if tgt else Vector3.ZERO
	if tgt is Camera3D:
		tp = tgt.global_position + (-tgt.global_transform.basis.z) * 14.0
	_indoor_t -= delta
	if _indoor_t <= 0.0:
		_indoor_t = 0.5
		var s = streamer
		if s == null and Game.world and Game.world.get("terrain"):
			s = Game.world.terrain
		_indoor = s != null and s.has_method("building_at") and s.building_at(tp) != null
	_rain.global_position = tp + Vector3(0, 16, 0)
	_snow.global_position = tp + Vector3(0, 11, 0)
	_wind.global_position = tp + Vector3(-10, 2, 0)
	var in_dim := _in_dimension()
	_rain.emitting = is_raining() and not _indoor and not in_dim
	_snow.emitting = current == "snow" and not _indoor and not in_dim
	_wind.emitting = (current == "wind" or current == "storm") and not _indoor and not in_dim
	_apply_fog(minf(1.0, delta * 0.5))
	if in_dim:
		_bolt_light.light_energy = 0.0
		_ambient("rain_loop", false)
		_ambient("wind_loop", false)
		_update_surfaces(delta, true)
		return
	# storm lightning
	if current == "storm":
		_lightning_t -= delta
		if _lightning_t <= 0.0:
			_lightning_t = _rng.randf_range(5.0, 14.0)
			_flash_t = 0.18
			get_tree().create_timer(0.45, false).timeout.connect(func(): Audio.play_sfx("thunder", null, -4.0))
			if _rng.randf() < 0.4:
				_strike(tp + Vector3(_rng.randf_range(-20, 20), 0, _rng.randf_range(-20, 20)))
	if _flash_t > 0.0:
		_flash_t -= delta
		# a lightning flash lights the whole street; with "no flicker" it is a
		# single soft pulse instead of a double strobe
		var fk := Settings.flash_k()
		if Settings.no_flicker:
			_bolt_light.light_energy = 1.2 * fk * clampf(_flash_t / 0.18, 0.0, 1.0)
		else:
			_bolt_light.light_energy = (2.4 if _flash_t > 0.09 else 1.0) * fk
	else:
		_bolt_light.light_energy = 0.0
	_update_surfaces(delta, in_dim)
	# wet status
	if is_raining():
		_wet_t -= delta
		if _wet_t <= 0.0:
			_wet_t = 1.0
			for a in Game.actors_near(tp, 35.0):
				if a.is_dead or not a.has_method("apply_status"):
					continue
				var s2 = streamer if streamer != null else (Game.world.terrain if Game.world and Game.world.get("terrain") else null)
				if s2 != null and s2.has_method("building_at") and s2.building_at(a.global_position) != null:
					continue
				a.apply_status("wet", 3.0)
	_ambient("rain_loop", is_raining() and not _indoor)
	_ambient("wind_loop", current in ["wind", "storm", "snow"])
	_ambient("night_loop", Game.is_night() and current in ["clear", "cloudy", "fog"])

## Surface state for the terrain/road shaders (global shader parameters):
## wetness rises in rain within ~20 s and dries over ~70 s; snow cover
## builds up over ~45 s of snowfall and melts slowly afterwards.
var wetness := 0.0
var snow_cover := 0.0
func _update_surfaces(delta: float, in_dim: bool) -> void:
	var want_wet := 1.0 if (is_raining() and not in_dim) else 0.0
	wetness = move_toward(wetness, want_wet, delta / (20.0 if want_wet > wetness else 70.0))
	var want_snow := 1.0 if (current == "snow" and not in_dim) else 0.0
	snow_cover = move_toward(snow_cover, want_snow, delta / (45.0 if want_snow > snow_cover else 120.0))
	if Engine.get_process_frames() % 6 == 0:
		RenderingServer.global_shader_parameter_set("weather_wet", wetness)
		RenderingServer.global_shader_parameter_set("weather_snow", snow_cover)

func _ambient(nm: String, on: bool) -> void:
	if _amb.get(nm, false) == on:
		return
	_amb[nm] = on
	if has_node("/root/Audio") and Audio.has_method("set_ambient"):
		Audio.set_ambient(nm, on)

func _strike(p: Vector3) -> void:
	var gh := p.y
	var s = streamer if streamer != null else (Game.world.terrain if Game.world and Game.world.get("terrain") else null)
	if s != null and s.has_method("ground_height"):
		gh = s.ground_height(p)
	var gp := Vector3(p.x, gh, p.z)
	if s != null and s.has_method("building_at") and s.building_at(gp) != null:
		return
	VFX.beam(gp + Vector3(0, 30, 0), gp, Color(0.85, 0.9, 1.0), 0.2, 0.25, true)
	VFX.flash(gp + Vector3(0, 2, 0), Color(0.8, 0.85, 1.0), 0.15, 6.0)
	VFX.burst(gp + Vector3(0, 0.3, 0), Color(0.85, 0.9, 1.0), 12, 0.3)
	for a in Game.actors_near(gp, 3.0):
		if not a.is_dead and a.global_position.distance_to(gp) < 2.2:
			Combat.deal(null, a, {"amount": 14.0 + era * 10.0, "dtype": "lightning", "status": {"stun": 0.4}, "proc": true})
	for d in Game.grid.query(gp, 2.5, "destructible"):
		if is_instance_valid(d) and d.has_method("take_hit"):
			d.take_hit(15.0, "fire", null)

## Inside a rift / pocket dimension the world controls sky & fog colour; the
## weather only keeps the density readable and stops precipitation.
func _in_dimension() -> bool:
	if Game.world == null or not is_instance_valid(Game.world):
		return false
	var d = Game.world.get("dimension")
	return d != null and str(d) != ""

func fog_base() -> float:
	var base: float = DBEras.era(era).fog_base + FOG_ADD.get(current, 0.0)
	if overrides.has("cursed_fog"):
		base += 0.006
	return base

func _apply_fog(k: float) -> void:
	if env == null or env.environment == null:
		return
	var en := env.environment
	# Godot's exponential fog is strong: scale the (already capped) setting so the
	# heaviest fog still keeps the hero, roads and nearby enemies clearly visible.
	var in_dim := _in_dimension()
	var dens := Settings.fog_value(0.004 if in_dim else fog_base()) * FOG_SCALE
	var dn0 = day_night if day_night != null else (Game.world.day_night if Game.world and Game.world.get("day_night") else null)
	if dn0 != null and dn0.has_method("light_factor") and dn0.light_factor() < 0.4:
		dens *= 0.7   # darkness already limits view; don't stack thick fog on top
	dens = minf(dens, MAX_FOG)
	if en.fog_mode != Environment.FOG_MODE_EXPONENTIAL:
		en.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_fog_cur = lerpf(_fog_cur, dens, k)
	en.fog_enabled = _fog_cur > 0.0001
	en.fog_density = _fog_cur
	en.fog_sky_affect = 0.35
	en.fog_aerial_perspective = 0.0
	if in_dim:
		return
	var c: Color = DBEras.era(era).fog_color
	if is_raining():
		c = c.lerp(Color(0.55, 0.58, 0.62), 0.6)
	if overrides.has("cursed_fog"):
		c = Color(0.45, 0.62, 0.42)
	var lf := 1.0
	var dn = day_night if day_night != null else (Game.world.day_night if Game.world and Game.world.get("day_night") else null)
	if dn != null and dn.has_method("light_factor"):
		lf = dn.light_factor()
	c = c * (0.35 + 0.65 * lf)
	if dn != null and dn.get("blood") != null and float(dn.blood) > 0.0:
		# far horizon reddens slightly during the blood moon
		c = c.lerp(Color(0.42, 0.1, 0.09), float(dn.blood) * 0.45 * clampf(Settings.effects_intensity, 0.0, 1.0))
	c.a = 1.0
	en.fog_light_color = en.fog_light_color.lerp(c, k)
	en.fog_light_energy = 1.0
