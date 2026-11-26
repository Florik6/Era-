class_name DynamicQuality
extends Node
## Dynamic Combat Quality: watches real frame time and, under sustained
## load, lowers secondary visual cost one step at a time; when the frame
## rate is stable again it restores quality step by step.
##   level 1: fewer secondary particles, shorter ambient particle radius
##   level 2: shorter shadow distance, fewer characters cast shadows
##   level 3: decorative effects off (ambient particles, decals, distant
##            enemy spell decoration), gear details closer
##   level 4: render resolution -10 %, detail draw distance x0.75
##   level 5: render resolution -20 %, detail draw distance x0.55, particles x0.5
## Never touched: hitboxes, damage, danger telegraphs, the hero's own
## spell cores, UI. Hysteresis: degrade after 3 s below 90 % of the
## target, restore after 8 s above 120 %, at least 5 s between changes.

static var level := 0
const MAX_LEVEL := 5

var world
var _ema := 1.0 / 60.0
var _below_t := 0.0
var _above_t := 0.0
var _cool := 0.0
var _base_scale := 1.0
var _base_shadow := 60.0
var changes := 0

func setup(w) -> void:
	world = w
	level = 0
	_base_scale = get_viewport().scaling_3d_scale
	if world.get("day_night") and world.day_night and world.day_night.sun:
		_base_shadow = world.day_night.sun.directional_shadow_max_distance

func target_fps() -> float:
	return float(Settings.target_fps)

func _process(delta: float) -> void:
	if world == null or not Settings.dynamic_quality:
		if level != 0:
			set_level(0)
		return
	var real := delta / maxf(0.05, Engine.time_scale)
	if real <= 0.0 or real > 0.5:
		return    # hitches from loading/pausing don't count
	_ema = lerpf(_ema, real, 0.05)
	var fps := 1.0 / maxf(0.001, _ema)
	var tgt := target_fps()
	_cool = maxf(0.0, _cool - real)
	if fps < tgt * 0.9:
		_below_t += real
		_above_t = 0.0
	elif fps > tgt * 1.2:
		_above_t += real
		_below_t = 0.0
	else:
		_below_t = maxf(0.0, _below_t - real * 0.5)
		_above_t = maxf(0.0, _above_t - real * 0.5)
	if _cool > 0.0:
		return
	if _below_t > 3.0 and level < MAX_LEVEL:
		set_level(level + 1)
	elif _above_t > 8.0 and level > 0:
		set_level(level - 1)

func fps_estimate() -> float:
	return 1.0 / maxf(0.001, _ema)

func set_level(l: int) -> void:
	level = clampi(l, 0, MAX_LEVEL)
	changes += 1
	_cool = 5.0
	_below_t = 0.0
	_above_t = 0.0
	_apply()

func _apply() -> void:
	var lod = world.sys("perf_lod") if world.has_method("sys") else null
	if lod:
		lod.ambient_r = [42.0, 30.0, 26.0, 0.0, 0.0, 0.0][level]
		lod.ambient_on = level < 3
		lod.rig_shadow_r = [22.0, 22.0, 12.0, 10.0, 8.0, 6.0][level]
		lod.rig_detail_r = [40.0, 40.0, 34.0, 26.0, 22.0, 18.0][level]
		lod.detail_k = [1.0, 1.0, 1.0, 0.9, 0.75, 0.55][level]
	var mg = VFX._m()
	if mg:
		mg._refresh_quality()
		mg._particle_budget *= [1.0, 0.75, 0.7, 0.6, 0.55, 0.5][level]
		if level >= 3:
			mg.decals_on = false
	if world.get("day_night") and world.day_night and world.day_night.sun:
		world.day_night.sun.directional_shadow_max_distance = _base_shadow * [1.0, 1.0, 0.6, 0.55, 0.5, 0.45][level]
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(_base_scale * [1.0, 1.0, 1.0, 1.0, 0.9, 0.8][level], 0.5, 1.0)
