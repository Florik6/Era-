class_name GearPreview
extends SubViewportContainer
## 3D preview of the hero with the current (or tried-on) equipment, in its
## own small world: drag to rotate, pinch/wheel to zoom. Used by the
## inventory for try-on, helmet show/hide and dye colours.

var vp: SubViewport
var rig: HumanoidRig
var cam: Camera3D
var _yaw := 0.4
var _dist := 3.2
var _drag := false
var _touches := {}
var _pinch0 := 0.0
var equip_override := {}        # slot -> item (try-on)

func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(300, 360)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(300, 360)
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(30), 0)
	sun.light_energy = 1.2
	root.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 35.0
	root.add_child(cam)
	cam.current = true
	rig = HumanoidRig.new()
	rig.setup(Player.look_from(Profile.char))     # the body is built once
	root.add_child(rig)
	refresh()
	_place_cam()

func refresh() -> void:
	if rig == null:
		return
	var pd: CharData = Profile.char
	var look: Dictionary = Player.look_from(pd)
	for k in ["hide_helm", "dye"]:
		if look.has(k):
			rig.look[k] = look[k]
		else:
			rig.look.erase(k)
	var eq: Dictionary = pd.inv.equip.duplicate()
	for k in equip_override:
		eq[k] = equip_override[k]
	rig.class_hint = pd.class_id
	rig.set_gear(eq, Color(0, 0, 0, 0), false)

func try_on(it: Dictionary) -> void:
	var slot: String = ItemDB.base(it.base).get("slot", "")
	if slot == "":
		return
	equip_override = {slot: it}
	refresh()

func clear_try_on() -> void:
	equip_override = {}
	refresh()

func _place_cam() -> void:
	if cam == null:
		return
	cam.position = Vector3(sin(_yaw) * _dist, 1.15, cos(_yaw) * _dist)
	cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_drag = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist - 0.2, 1.6, 5.0)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist + 0.2, 1.6, 5.0)
		_place_cam()
	elif ev is InputEventMouseMotion and _drag:
		_yaw -= ev.relative.x * 0.012
		_place_cam()
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
		if _touches.size() == 2:
			var v: Array = _touches.values()
			_pinch0 = (v[0] as Vector2).distance_to(v[1])
	elif ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if _touches.size() == 1:
			_yaw -= ev.relative.x * 0.012
		elif _touches.size() == 2:
			var v2: Array = _touches.values()
			var d: float = (v2[0] as Vector2).distance_to(v2[1])
			if _pinch0 > 1.0:
				_dist = clampf(_dist * _pinch0 / d, 1.6, 5.0)
			_pinch0 = d
		_place_cam()
