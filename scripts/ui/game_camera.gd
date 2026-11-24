class_name GameCamera
extends Camera3D
## Isometric-style follow camera (high angle), smoothed on the interpolated
## player transform, with zoom setting and screen shake.

var target: Node3D = null
var yaw := 0.0
var pitch_deg := 54.0
var base_dist := 14.0
var _focus := Vector3.ZERO
var _shake := 0.0
var _snap := true

func _ready() -> void:
	fov = 48.0
	near = 0.3
	far = 260.0
	current = true

func snap() -> void:
	_snap = true

func shake(a: float) -> void:
	_shake = maxf(_shake, a)

func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var tp: Vector3 = target.get_global_transform_interpolated().origin if target.is_inside_tree() else target.global_position
	var focus_target := tp + Vector3(0, 1.0, 0)
	if _snap:
		_focus = focus_target
		_snap = false
	else:
		_focus = _focus.lerp(focus_target, 1.0 - exp(-delta * 9.0))
	var dist := base_dist / clampf(Settings.camera_zoom, 0.6, 1.6)
	var p := deg_to_rad(pitch_deg)
	var off := Vector3(0, sin(p) * dist, cos(p) * dist).rotated(Vector3.UP, yaw)
	var sh := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.8)
		sh = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.5
	global_position = _focus + off + sh
	look_at(_focus + sh * 0.5, Vector3.UP)
