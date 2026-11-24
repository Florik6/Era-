extends Node3D
## Pooled visual effects: floating combat text, particle bursts, rings, beams,
## muzzle flashes, explosions and boss attack telegraphs.

var _labels: Array = []
var _label_i := 0
var _particle_budget := 1.0
var _sector_cache := {}

func _ready() -> void:
	for i in 36:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.font_size = 64
		l.pixel_size = 0.006
		l.outline_size = 14
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.visible = false
		l.render_priority = 10
		add_child(l)
		_labels.append(l)
	_particle_budget = Settings.profile().particles

func text(pos: Vector3, s: String, c: Color, scl: float) -> void:
	var l: Label3D = _labels[_label_i]
	_label_i = (_label_i + 1) % _labels.size()
	l.text = s
	l.modulate = c
	l.global_position = pos
	l.scale = Vector3.ONE * scl
	l.visible = true
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.1, 0), 0.8).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.35)
	tw.tween_callback(func(): l.visible = false)

func burst(pos: Vector3, c: Color, count: int, size: float) -> void:
	var n := int(count * _particle_budget)
	if n < 2:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = n
	p.lifetime = 0.5
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var m := MeshLib.box(Vector3(size, size, size) * 0.35)
	p.mesh = m
	p.material_override = MeshLib.mat(c, 0.0, 1.0, 2.0, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.0, false).timeout.connect(p.queue_free)

func ring(pos: Vector3, r: float, c: Color, dur: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.torus(0.85, 1.0)
	mi.material_override = MeshLib.mat(Color(c.r, c.g, c.b, 0.7), 0.0, 1.0, 2.5, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos + Vector3(0, 0.15, 0)
	mi.scale = Vector3(0.2, 0.3, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(r, 0.5, r), dur).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)

func beam(a: Vector3, b: Vector3, c: Color, dur: float, width: float, jagged: bool) -> void:
	var pts: Array = [a]
	if jagged:
		var segs := 5
		for i in range(1, segs):
			var t := float(i) / segs
			pts.append(a.lerp(b, t) + Vector3(randf_range(-0.4, 0.4), randf_range(-0.3, 0.3), randf_range(-0.4, 0.4)))
	pts.append(b)
	var holder := Node3D.new()
	add_child(holder)
	for i in pts.size() - 1:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var len := p0.distance_to(p1)
		if len < 0.01:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.box(Vector3(width, width, 1.0))
		mi.material_override = MeshLib.mat(c, 0.0, 1.0, 4.0, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		mi.global_position = (p0 + p1) * 0.5
		mi.look_at(p1, Vector3.UP if absf((p1 - p0).normalized().y) < 0.95 else Vector3.RIGHT)
		mi.scale = Vector3(1, 1, len)
	get_tree().create_timer(dur, false).timeout.connect(holder.queue_free)

func flash(pos: Vector3, c: Color, dur: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = 5.0
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos
	get_tree().create_timer(dur, false).timeout.connect(l.queue_free)

func explosion(pos: Vector3, r: float, c: Color) -> void:
	burst(pos + Vector3(0, 0.5, 0), c, int(18 + r * 4), 0.5)
	burst(pos + Vector3(0, 0.3, 0), Color(0.3, 0.28, 0.25, 0.8), 10, 0.6)
	ring(pos, r, c, 0.35)
	flash(pos + Vector3(0, 1, 0), c, 0.15, 5.0)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.sphere(1.0, 12, 8)
	mi.material_override = MeshLib.mat(Color(c.r, c.g, c.b, 0.55), 0.0, 1.0, 3.0, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.3
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * r, 0.25)
	tw.tween_callback(mi.queue_free)
	if r >= 3.0:
		VFX.shake(minf(0.6, r * 0.08))

## Ground warning that fills up until the attack lands.
func telegraph(pos: Vector3, r: float, dur: float, c: Color, shape: String, dir: Vector3, arc: float, length: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos + Vector3(0, 0.08, 0)
	var outer := MeshInstance3D.new()
	var inner := MeshInstance3D.new()
	var mo := MeshLib.mat(Color(c.r, c.g, c.b, 0.22), 0.0, 1.0, 0.0, true)
	var mf := MeshLib.mat(Color(c.r, c.g, c.b, 0.45), 0.0, 1.0, 1.0, true)
	outer.material_override = mo
	inner.material_override = mf
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match shape:
		"line":
			var m := MeshLib.box(Vector3(r * 2.0, 0.02, 1.0))
			outer.mesh = m
			inner.mesh = m
			outer.scale = Vector3(1, 1, length)
			outer.position = Vector3(0, 0, -length * 0.5)
			inner.position = Vector3(0, 0.01, 0)
			inner.scale = Vector3(1, 1, 0.01)
			root.look_at(root.global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)
		"cone":
			var sm := _sector_mesh(arc)
			outer.mesh = sm
			inner.mesh = sm
			outer.scale = Vector3(r, 1, r)
			inner.scale = Vector3(0.01, 1, 0.01)
			root.look_at(root.global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)
		_:
			var cm := MeshLib.cyl(1.0, 1.0, 0.02, 24)
			outer.mesh = cm
			inner.mesh = cm
			outer.scale = Vector3(r, 1, r)
			inner.scale = Vector3(0.01, 1, 0.01)
	root.add_child(outer)
	root.add_child(inner)
	var tw := root.create_tween()
	if shape == "line":
		tw.tween_property(inner, "scale", Vector3(1, 1, length), dur)
		tw.parallel().tween_property(inner, "position", Vector3(0, 0.01, -length * 0.5), dur)
	else:
		tw.tween_property(inner, "scale", Vector3(r, 1, r), dur)
	tw.tween_callback(root.queue_free)

func _sector_mesh(arc: float) -> ArrayMesh:
	var key := int(arc)
	if _sector_cache.has(key):
		return _sector_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	var half := deg_to_rad(arc * 0.5)
	for i in segs:
		var a0 := -half + (2.0 * half) * i / segs
		var a1 := -half + (2.0 * half) * (i + 1) / segs
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a1), 0, -cos(a1)))
		st.add_vertex(Vector3(sin(a0), 0, -cos(a0)))
	var m := st.commit()
	_sector_cache[key] = m
	return m
