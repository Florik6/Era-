class_name SwingTrail
extends MeshInstance3D
## Blade ribbon that follows a weapon while `active` and fades out after.
## The ribbon spans from `base` (grip, offset toward the tip) to `target`
## (tip marker); without a base it is a flat ribbon of `width` around the tip.
## Fixed-size ring buffer: no per-frame allocations besides the immediate
## mesh rebuild. Robust when the target is freed (it just fades).

const MAX_PTS := 16

var target: Node3D = null
var base: Node3D = null
var active := false
var color := Color(0.85, 0.92, 1.0, 0.6)
var width := 0.18
var point_life := 0.16
var base_frac := 0.35         # how far along grip→tip the inner edge starts

var _tips := PackedVector3Array()
var _bases := PackedVector3Array()
var _ages := PackedFloat32Array()
var _head := 0
var _count := 0
var _idle := 0.0
var _im: ImmediateMesh

func _ready() -> void:
	top_level = true
	_tips.resize(MAX_PTS)
	_bases.resize(MAX_PTS)
	_ages.resize(MAX_PTS)
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _material()
	global_transform = Transform3D.IDENTITY

static var _mat: StandardMaterial3D = null

static func _material() -> StandardMaterial3D:
	if _mat:
		return _mat
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = MagicFX.tex("trail")
	m.disable_fog = true
	_mat = m
	return m

func idle_time() -> float:
	return _idle

func _process(delta: float) -> void:
	var valid := target != null and is_instance_valid(target) and target.is_inside_tree()
	if not valid:
		target = null
		active = false
	# age out old points
	for i in _count:
		var k := (_head - 1 - i + MAX_PTS) % MAX_PTS
		_ages[k] += delta
	while _count > 0:
		var oldest := (_head - _count + MAX_PTS) % MAX_PTS
		if _ages[oldest] > point_life:
			_count -= 1
		else:
			break
	if active and valid:
		_idle = 0.0
		var tip := target.global_position
		var bp: Vector3
		if base != null and is_instance_valid(base) and base.is_inside_tree():
			bp = base.global_position.lerp(tip, base_frac)
		else:
			var cam := get_viewport().get_camera_3d()
			var up := Vector3.UP
			if cam:
				up = (tip - cam.global_position).cross(Vector3.UP).normalized()
			bp = tip - up * width
		var last := (_head - 1 + MAX_PTS) % MAX_PTS
		if _count == 0 or _tips[last].distance_squared_to(tip) > 0.0004:
			_tips[_head] = tip
			_bases[_head] = bp
			_ages[_head] = 0.0
			_head = (_head + 1) % MAX_PTS
			_count = mini(_count + 1, MAX_PTS)
	else:
		_idle += delta
	_rebuild()

func _rebuild() -> void:
	_im.clear_surfaces()
	if _count < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _count:
		var k := (_head - _count + i + MAX_PTS) % MAX_PTS
		var f := clampf(1.0 - _ages[k] / point_life, 0.0, 1.0)
		var t := float(i) / float(_count - 1)
		var a := color.a * f * (0.25 + 0.75 * t)
		_im.surface_set_color(Color(color.r, color.g, color.b, a))
		_im.surface_set_uv(Vector2(t, 0.0))
		_im.surface_add_vertex(_bases[k])
		_im.surface_set_color(Color(color.r, color.g, color.b, a))
		_im.surface_set_uv(Vector2(t, 1.0))
		_im.surface_add_vertex(_tips[k])
	_im.surface_end()
