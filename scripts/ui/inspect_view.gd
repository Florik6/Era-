class_name InspectView
extends SubViewportContainer
## 3D model of an item for the study screen, in its own small world: drag to
## rotate, pinch / wheel / buttons to zoom. Interactive parts are shown as
## numbered markers projected from points along the model.

signal part_pressed(part_id: String)

var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var model: Node3D
var item: Dictionary = {}
var _yaw := 0.6
var _pitch := -0.25
var _dist := 2.2
var _base_dist := 2.2
var _drag := false
var _touches := {}
var _pinch0 := 0.0
var _parts: Array = []           # [[id, label, frac, known]]
var _markers := {}               # id -> Button
var _aabb := AABB(Vector3(-0.1, -0.1, -0.5), Vector3(0.2, 0.2, 1.0))
var _axis := 2

func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(420, 320)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(420, 320)
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.environment.ambient_light_energy = 0.9
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(25), 0)
	sun.light_energy = 1.3
	root.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.2, 0.8, -1.5)
	rim.light_color = Color(0.5, 0.75, 1.0)
	rim.light_energy = 0.8
	rim.omni_range = 5.0
	root.add_child(rim)
	pivot = Node3D.new()
	root.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 32.0
	root.add_child(cam)
	cam.current = true
	_build_model()
	_place_cam()

func set_item(it: Dictionary) -> void:
	item = it
	if is_inside_tree():
		_build_model()
		_place_cam()

func set_parts(parts: Array) -> void:
	_parts = parts
	for k in _markers:
		if is_instance_valid(_markers[k]):
			_markers[k].queue_free()
	_markers.clear()
	var i := 0
	for p in parts:
		i += 1
		var b := Button.new()
		b.text = str(i)
		b.custom_minimum_size = Vector2(46, 46)
		b.focus_mode = Control.FOCUS_NONE
		var pid: String = p[0]
		b.pressed.connect(func(): part_pressed.emit(pid))
		b.tooltip_text = str(p[1])
		b.modulate = Color(0.55, 1.0, 0.6) if bool(p[3]) else Color(1.0, 0.85, 0.4)
		add_child(b)
		_markers[pid] = b

func _build_model() -> void:
	if pivot == null:
		return
	if model and is_instance_valid(model):
		model.queue_free()
	model = null
	if item.is_empty():
		return
	var b := ItemDB.base(str(item.get("base", "")))
	model = WeaponModels.build(str(b.get("model", "sword")), item)
	pivot.add_child(model)
	# centre the model and find its long axis (markers sit along it)
	var bb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var xf := pivot.global_transform.affine_inverse() * m.global_transform
		var a := xf * m.get_aabb()
		if first:
			bb = a
			first = false
		else:
			bb = bb.merge(a)
	if not first:
		_aabb = bb
		model.position = -bb.get_center()
		_aabb.position -= bb.get_center()
	var sz := _aabb.size
	_axis = 0 if sz.x >= sz.y and sz.x >= sz.z else (1 if sz.y >= sz.z else 2)
	_base_dist = clampf(maxf(sz.x, maxf(sz.y, sz.z)) * 1.9, 0.9, 5.0)
	_dist = _base_dist

## Point of a part (0..1 along the long axis) in the model's space.
func part_point(frac: float) -> Vector3:
	var p := _aabb.get_center()
	var lo: float = _aabb.position[_axis]
	var hi: float = lo + _aabb.size[_axis]
	# weapon models point their muzzle to -Z / +X: 0 = the back (stock, grip), 1 = the muzzle / tip
	var f := clampf(frac, 0.0, 1.0)
	p[_axis] = lerpf(hi, lo, f) if _axis == 2 else lerpf(lo, hi, f)
	return p

func zoom(k: float) -> void:
	_dist = clampf(_dist * k, _base_dist * 0.45, _base_dist * 1.8)
	_place_cam()

func _place_cam() -> void:
	if cam == null:
		return
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(-_pitch), cos(_yaw) * cos(_pitch))
	cam.position = dir * _dist
	cam.look_at(Vector3.ZERO, Vector3.UP)

func _process(_delta: float) -> void:
	if cam == null:
		return
	var vsz := Vector2(vp.size)
	var csz := size
	for p in _parts:
		var b: Button = _markers.get(str(p[0]))
		if b == null or not is_instance_valid(b):
			continue
		var wp := pivot.global_transform * part_point(float(p[2]))
		if cam.is_position_behind(wp):
			b.visible = false
			continue
		b.visible = true
		var sp := cam.unproject_position(wp)
		var k := Vector2(csz.x / maxf(1.0, vsz.x), csz.y / maxf(1.0, vsz.y))
		b.position = sp * k - b.size * 0.5

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom(1.1)
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_rotate(mm.relative)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		if _touches.size() == 2:
			var ks: Array = _touches.keys()
			_pinch0 = (_touches[ks[0]] as Vector2).distance_to(_touches[ks[1]])
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var ks2: Array = _touches.keys()
			var d := (_touches[ks2[0]] as Vector2).distance_to(_touches[ks2[1]])
			if _pinch0 > 1.0:
				zoom(_pinch0 / maxf(1.0, d))
			_pinch0 = d
		else:
			_rotate(sd.relative)

func _rotate(rel: Vector2) -> void:
	_yaw -= rel.x * 0.012
	_pitch = clampf(_pitch + rel.y * 0.008, -1.2, 1.2)
	_place_cam()

## Tests: turn the model by an angle.
func spin(dyaw: float, dpitch := 0.0) -> void:
	_yaw += dyaw
	_pitch = clampf(_pitch + dpitch, -1.2, 1.2)
	_place_cam()
