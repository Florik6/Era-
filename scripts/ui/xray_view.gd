class_name XrayView
extends SubViewportContainer
## Stylised translucent 3D body for the Hardcore anatomy screen ("X-ray").
## The hero's body is rendered with an additive x-ray shader over a dark blue
## background; every injured zone carries a marker whose COLOUR shows the
## severity (yellow light, orange medium, red severe, purple magic) and whose
## SHAPE and label repeat it without colour (sphere = light, diamond =
## medium, cross = severe, ring = magic; label I / II / III / М plus КР for
## bleeding, ИНФ for infection, ПЕР for a fracture).
## Touch: one-finger drag rotates, pinch (or mouse wheel) zooms, a tap selects
## the zone under the finger (zone_tapped).

signal zone_tapped(zone: String)

const ANCHORS := {"head": ["head", Vector3(0, 0.05, 0)], "chest": ["chest", Vector3(0, 0.18, 0)],
	"abdomen": ["spine", Vector3(0, 0.04, 0)], "arm_l": ["elbow_l", Vector3(0, 0.02, 0)],
	"arm_r": ["elbow_r", Vector3(0, 0.02, 0)], "leg_l": ["knee_l", Vector3(0, 0.12, 0)], "leg_r": ["knee_r", Vector3(0, 0.12, 0)]}
const XRAY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_add;
uniform vec4 col : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float fill = 0.07;
void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
	ALBEDO = col.rgb * (fill + rim * 0.75);
}
"""

var vp: SubViewport
var root: Node3D
var rig: HumanoidRig
var cam: Camera3D
var markers := {}          # zone -> Node3D
var selected := ""
var _yaw := 0.0
var _dist := 3.7
var _touches := {}
var _pinch0 := 0.0
var _press_pos := Vector2.ZERO
var _moved := 0.0
var _mouse_down := false
var _t := 0.0

func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(320, 420)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.size = Vector2i(360, 460)
	vp.msaa_3d = Viewport.MSAA_2X
	add_child(vp)
	root = Node3D.new()
	vp.add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.015, 0.04, 0.07)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.6, 0.7)
	root.add_child(env)
	cam = Camera3D.new()
	cam.fov = 34.0
	root.add_child(cam)
	cam.current = true
	_build_grid()
	rig = HumanoidRig.new()
	var look: Dictionary = Player.look_from(Profile.char)
	look.erase("dye")
	rig.setup(look)
	root.add_child(rig)
	var sh := Shader.new()
	sh.code = XRAY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in ["hair", "beard"]:
		if rig.parts.has(k) and is_instance_valid(rig.parts[k]):
			rig.parts[k].visible = false
	_build_bones()
	_place_cam()
	refresh()

## Faint floor grid and scan lines — the medical-display look.
func _build_grid() -> void:
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.2, 0.55, 0.8, 0.35)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(-4, 5):
		MeshLib.part(root, MeshLib.box(Vector3(2.4, 0.004, 0.006)), gm, Vector3(0, 0, i * 0.3), Vector3.ZERO, Vector3.ONE, false)
		MeshLib.part(root, MeshLib.box(Vector3(0.006, 0.004, 2.4)), gm, Vector3(i * 0.3, 0, 0), Vector3.ZERO, Vector3.ONE, false)

## Simple skeleton inside the translucent body: spine, ribs, limb bones, skull.
func _build_bones() -> void:
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var j: Dictionary = rig.j
	if j.has("head"):
		MeshLib.part(j.head, MeshLib.sphere(0.085, 10, 6), bm, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	if j.has("chest"):
		MeshLib.part(j.chest, MeshLib.box(Vector3(0.025, 0.42, 0.025)), bm, Vector3(0, 0.1, 0.05), Vector3.ZERO, Vector3.ONE, false)
		for i in 4:
			MeshLib.part(j.chest, MeshLib.torus(0.1, 0.112), bm, Vector3(0, 0.25 - i * 0.07, 0), Vector3.ZERO, Vector3(1.3, 1.0, 0.75), false)
	if j.has("hips"):
		MeshLib.part(j.hips, MeshLib.box(Vector3(0.24, 0.05, 0.08)), bm, Vector3(0, -0.02, 0), Vector3.ZERO, Vector3.ONE, false)
	for side in ["l", "r"]:
		for pair in [["arm_", -0.14, 0.26], ["elbow_", -0.13, 0.24], ["leg_", -0.21, 0.42], ["knee_", -0.2, 0.38]]:
			var key: String = String(pair[0]) + side
			if j.has(key):
				MeshLib.part(j[key], MeshLib.box(Vector3(0.022, float(pair[2]), 0.022)), bm, Vector3(0, float(pair[1]), 0), Vector3.ZERO, Vector3.ONE, false)

## Rebuild the zone markers from the current injuries.
func refresh() -> void:
	if rig == null:
		return
	for z in markers:
		if is_instance_valid(markers[z]):
			markers[z].queue_free()
	markers.clear()
	var hc = Hardcore.inst
	for zone in Hardcore.ZONES:
		var w: Dictionary = hc.worst(zone) if hc != null else {}
		var holder := Node3D.new()
		var anchor: Node3D = rig.j.get(ANCHORS[zone][0])
		if anchor == null:
			continue
		anchor.add_child(holder)
		holder.position = ANCHORS[zone][1]
		markers[zone] = holder
		var sel: bool = zone == selected
		if w.is_empty():
			# healthy zone: a faint ring so it can still be tapped
			var hm := _mat(Color(0.3, 0.8, 1.0, 0.22 if not sel else 0.7))
			MeshLib.part(holder, MeshLib.torus(0.07, 0.08), hm, Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
			continue
		var c: Color = Hardcore.color_of(w)
		var m := _mat(Color(c.r, c.g, c.b, 0.85))
		var shape: String = "magic" if w.type == "magic" else ["", "light", "medium", "severe"][clampi(int(w.sev), 1, 3)]
		match shape:
			"light":
				MeshLib.part(holder, MeshLib.sphere(0.06, 10, 6), m, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			"medium":
				MeshLib.part(holder, MeshLib.box(Vector3(0.09, 0.09, 0.09)), m, Vector3.ZERO, Vector3(45, 0, 45), Vector3.ONE, false)
			"severe":
				MeshLib.part(holder, MeshLib.box(Vector3(0.16, 0.045, 0.045)), m, Vector3.ZERO, Vector3(0, 0, 45), Vector3.ONE, false)
				MeshLib.part(holder, MeshLib.box(Vector3(0.16, 0.045, 0.045)), m, Vector3.ZERO, Vector3(0, 0, -45), Vector3.ONE, false)
			"magic":
				MeshLib.part(holder, MeshLib.torus(0.06, 0.085), m, Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
				MeshLib.part(holder, MeshLib.sphere(0.03, 8, 5), m, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		if sel:
			MeshLib.part(holder, MeshLib.torus(0.11, 0.125), _mat(Color(1, 1, 1, 0.9)), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
		var tags: Array = ["М" if w.type == "magic" else ["", "I", "II", "III"][clampi(int(w.sev), 1, 3)]]
		var bleed := false
		var inf := false
		var frac := false
		for inj in hc.of_zone(zone):
			bleed = bleed or (int(inj.bleed) > 0 and not inj.bandaged)
			inf = inf or inj.infected
			frac = frac or inj.type == "fracture"
		if bleed:
			tags.append("КР")
		if inf:
			tags.append("ИНФ")
		if frac:
			tags.append("ПЕР")
		var lbl := Label3D.new()
		lbl.text = " ".join(PackedStringArray(tags))
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.pixel_size = 0.0022
		lbl.font_size = 26
		lbl.outline_size = 8
		lbl.modulate = c.lightened(0.2)
		lbl.outline_modulate = Color(0, 0, 0, 0.9)
		lbl.font = UITheme.font("bold")
		lbl.position = Vector3(0.12 if zone.ends_with("_r") else (-0.12 if zone.ends_with("_l") else 0.0), 0.1, 0)
		holder.add_child(lbl)
		if bleed:
			holder.set_meta("pulse", true)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 2
	return m

func select(zone: String) -> void:
	selected = zone
	refresh()

func _process(delta: float) -> void:
	_t += delta
	for z in markers:
		var h = markers[z]
		if is_instance_valid(h) and h.has_meta("pulse"):
			var k := 1.0 + 0.18 * sin(_t * 6.0)
			h.scale = Vector3(k, k, k)

func _place_cam() -> void:
	if cam == null:
		return
	cam.position = Vector3(sin(_yaw) * _dist, 1.0, -cos(_yaw) * _dist)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)

## Screen position (in this control) of a zone anchor.
func zone_screen_pos(zone: String) -> Vector2:
	var h = markers.get(zone)
	if h == null or not is_instance_valid(h) or cam == null:
		return Vector2(-1000, -1000)
	var p: Vector2 = cam.unproject_position(h.global_position)
	var k := size / Vector2(vp.size) if vp.size.x > 0 else Vector2.ONE
	return p * k

func zone_at(pos: Vector2) -> String:
	var best := ""
	var bd := 70.0
	for z in markers:
		var d := zone_screen_pos(z).distance_to(pos)
		if d < bd:
			bd = d
			best = z
	return best

func _tap(pos: Vector2) -> void:
	var z := zone_at(pos)
	if z != "":
		select(z)
		zone_tapped.emit(z)

func rotate_by(px: float) -> void:
	_yaw -= px * 0.012
	_place_cam()

func zoom_by(f: float) -> void:
	_dist = clampf(_dist * f, 1.4, 4.5)
	_place_cam()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_mouse_down = true
				_press_pos = ev.position
				_moved = 0.0
			else:
				_mouse_down = false
				if _moved < 12.0:
					_tap(ev.position)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			zoom_by(0.92)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom_by(1.08)
	elif ev is InputEventMouseMotion and _mouse_down and _touches.is_empty():
		_moved += ev.relative.length()
		rotate_by(ev.relative.x)
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
			if _touches.size() == 1:
				_press_pos = ev.position
				_moved = 0.0
		else:
			if _touches.size() == 1 and _moved < 12.0:
				_tap(ev.position)
			_touches.erase(ev.index)
		if _touches.size() == 2:
			var v: Array = _touches.values()
			_pinch0 = (v[0] as Vector2).distance_to(v[1])
			_moved = 999.0
	elif ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if _touches.size() == 1:
			_moved += ev.relative.length()
			rotate_by(ev.relative.x)
		elif _touches.size() == 2:
			var v2: Array = _touches.values()
			var d: float = (v2[0] as Vector2).distance_to(v2[1])
			if _pinch0 > 1.0 and d > 1.0:
				zoom_by(_pinch0 / d)
			_pinch0 = d
