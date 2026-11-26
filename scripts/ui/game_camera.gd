class_name GameCamera
extends Camera3D
## High-angle follow camera: closer default framing so the hero, gear and
## attacks are readable; look-ahead in the movement direction; gentle pull-
## back in crowded fights and a larger pull-back when a big boss is engaged
## so its telegraphs stay on screen. Zoom comes from Settings.camera_zoom.
## Never locks input; cinematic offsets are additive and short.

var target: Node3D = null
var yaw := 0.0
var pitch_deg := 50.0
var base_dist := 10.5
var _focus := Vector3.ZERO
var _shake := 0.0
var _snap := true
var _dist_k := 1.0
var _look := Vector3.ZERO
var _scan_t := 0.0
var _want_k := 1.0
var cine_offset := Vector3.ZERO      # temporary offset from the cinematic director
var _punch := 0.0                    # >0 punch-in, <0 pull-out (fraction of distance)
var _punch_t := 0.0
var _punch_dur := 0.25
var _kick := Vector3.ZERO
var cine_focus = null                # optional Vector3 to bias the focus toward

func _ready() -> void:
	fov = 45.0
	near = 0.3
	far = 240.0
	current = true

func snap() -> void:
	_snap = true

## Camera director mode multiplier: Minimal 0 · Standard 1 · Cinematic 2.
static func mode_k() -> float:
	return [0.35, 1.0, 1.3][clampi(Settings.camera_mode, 0, 2)]

func shake(a: float) -> void:
	if not Settings.camera_shake:
		return
	_shake = maxf(_shake, a * mode_k() * clampf(Settings.effects_intensity * 1.2, 0.3, 1.2))

## Brief zoom accent: amount > 0 moves in, < 0 pulls out (fraction of distance).
func punch(amount: float, dur: float = 0.25) -> void:
	_punch = clampf(amount * mode_k(), -0.3, 0.3)
	_punch_dur = maxf(0.05, dur)
	_punch_t = _punch_dur

## Directional camera jolt (e.g. the weight of a hit).
func kick(dir: Vector3, amount: float) -> void:
	dir.y = 0
	if dir.length() > 0.01:
		_kick += dir.normalized() * clampf(amount * mode_k(), 0.0, 0.5)

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var tp: Vector3 = target.get_global_transform_interpolated().origin if target.is_inside_tree() else target.global_position
	# framing: crowded fight → slight pull-back; big boss → larger pull-back
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.4
		_want_k = 1.0
		var foes := 0
		for a in Game.actors_near(tp, 22.0):
			if a == target or a.is_dead:
				continue
			if a.kind == "boss" and a.global_position.distance_to(tp) < 30.0:
				_want_k = maxf(_want_k, 1.25 + 0.08 * a.def.get("scale", 1.5))
			elif target.get("actor_id") != null and Game.is_enemy(target, a) and a.global_position.distance_to(tp) < 12.0:
				foes += 1
		if foes >= 3:
			_want_k = maxf(_want_k, 1.12)
	_dist_k = lerpf(_dist_k, _want_k, 1.0 - exp(-delta * 1.8))
	# look-ahead in the movement direction
	var vel := Vector3.ZERO
	if target is CharacterBody3D:
		vel = (target as CharacterBody3D).velocity
		vel.y = 0
	_look = _look.lerp((vel * 0.28).limit_length(2.2), 1.0 - exp(-delta * 3.0))
	var focus_target := tp + Vector3(0, 1.0, 0) + _look
	if cine_focus != null:
		focus_target = focus_target.lerp(cine_focus, 0.45)
	if _snap:
		_focus = focus_target
		_snap = false
	else:
		_focus = _focus.lerp(focus_target, 1.0 - exp(-delta * 8.0))
	var dist := base_dist * _dist_k / clampf(Settings.camera_zoom, 0.6, 1.6)
	if _punch_t > 0.0:
		_punch_t = maxf(0.0, _punch_t - delta)
		var pk := _punch_t / _punch_dur
		dist *= 1.0 - _punch * sin(pk * PI)
	_kick = _kick.lerp(Vector3.ZERO, 1.0 - exp(-delta * 14.0))
	var p := deg_to_rad(pitch_deg + (_dist_k - 1.0) * 10.0)
	var off := Vector3(0, sin(p) * dist, cos(p) * dist).rotated(Vector3.UP, yaw)
	var sh := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.8)
		sh = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.45
	global_position = _focus + off + sh + cine_offset * mode_k() + _kick
	look_at(_focus + sh * 0.5, Vector3.UP)
