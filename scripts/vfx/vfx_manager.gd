extends Node3D
## Pooled visual effects: floating combat text, particle presets (pooled
## CPUParticles3D), glow flashes, shock rings, lightning / beam ribbons, ground
## decals, attack telegraphs that fill before the hit, hit / parry / block
## feedback, muzzle flashes, status overlays (frozen, cursed, stunned, burning,
## shielded, stasis, slowed time) and weapon swing trails.
## Budgets: Settings.vq("particles") scales counts, vq("fx") 0/1/2 drops
## secondary layers, vq("lights") caps live dynamic lights (never shadowed),
## vq("decals") toggles ground decals. Telegraphs and hit indicators are never
## dropped, only thinned.

const MAX_SYS := 72            # live one-shot particle systems
const STATUS_KINDS := ["freeze", "stasis", "curse", "burn", "stun", "magic_shield", "timeslow"]

var fx := 1
var light_cap := 8
var decals_on := true
var _labels: Array = []
var _label_i := 0
var _particle_budget := 1.0
var _sector_cache := {}
var _clock := 0.0
var _q_t := 0.0
# particle pool
var _free_sys: Array = []
var _live_sys: Array = []
var _live_end: PackedFloat32Array = PackedFloat32Array()
# deferred frees (detached trails, etc.)
var _reap_n: Array = []
var _reap_t: PackedFloat32Array = PackedFloat32Array()
# lights
var _lights_live := 0
# decals
var _decals: Array = []
var _decal_i := 0
var _stuck: Array = []
# slash arcs
var _arcs: Array = []
var _arc_i := 0
# status visuals / trails
var _status := {}
var _scan_t := 0.0
var _trail_scan_t := 0.0
var _trail_cands: Array = []
var _trails := {}

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
	_refresh_quality()
	_prewarm.call_deferred()

func _prewarm() -> void:
	# spread texture generation over a few frames so the first spell never hitches
	for k in ["soft", "ring", "smoke", "star", "flame", "scorch", "frost", "crack"]:
		MagicFX.tex(k)
		if not is_inside_tree():
			return
		await get_tree().process_frame

func _refresh_quality() -> void:
	fx = int(Settings.vq("fx", 1))
	light_cap = int(Settings.vq("lights", 8))
	while _pool.size() > light_cap:
		var l: OmniLight3D = _pool.pop_back()
		l.queue_free()
	decals_on = bool(Settings.vq("decals", true))
	_particle_budget = float(Settings.vq("particles", 0.7))
	if fx <= 0:
		_particle_budget *= 0.75

func _process(delta: float) -> void:
	_clock += delta
	_q_t -= delta
	if _q_t <= 0.0:
		_q_t = 2.0
		_refresh_quality()
	var i := _live_sys.size() - 1
	while i >= 0:
		if _clock >= _live_end[i]:
			var p: CPUParticles3D = _live_sys[i]
			_live_sys.remove_at(i)
			_live_end.remove_at(i)
			if is_instance_valid(p):
				p.emitting = false
				p.visible = false
				_free_sys.append(p)
		i -= 1
	var j := _reap_n.size() - 1
	while j >= 0:
		if _clock >= _reap_t[j]:
			var n = _reap_n[j]
			_reap_n.remove_at(j)
			_reap_t.remove_at(j)
			if is_instance_valid(n):
				n.queue_free()
		j -= 1
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_scan_status()
	_update_trails(delta)

## Free a node after `t` seconds without allocating a timer.
func reap(n: Node, t: float) -> void:
	_reap_n.append(n)
	_reap_t.append(_clock + t)

# ================================================================== text
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

# ============================================================== particles
## Configure an emitter from a preset dictionary. Keys: n, exact, life, lrand,
## mat (add/mix/star/flame/streak/shard/chunk/ringflat/ringv), col, ramp, size,
## svar, v0, v1, dir, spread, flat, grav, shape (point/sphere/ring/box), rad,
## box, expl, damp, ang, tan, radial, curve, local, basis.
func _config(p: CPUParticles3D, o: Dictionary, n: int) -> void:
	var mat: String = o.get("mat", "add")
	p.amount = n
	p.lifetime = maxf(0.02, float(o.get("life", 0.6)))
	p.explosiveness = float(o.get("expl", 0.92))
	p.randomness = 0.25
	p.lifetime_randomness = float(o.get("lrand", 0.3))
	p.local_coords = bool(o.get("local", false))
	p.direction = o.get("dir", Vector3.UP)
	p.spread = float(o.get("spread", 180.0))
	p.flatness = float(o.get("flat", 0.0))
	p.initial_velocity_min = float(o.get("v0", 2.0))
	p.initial_velocity_max = float(o.get("v1", 5.0))
	p.gravity = o.get("grav", Vector3(0, -9.0, 0))
	var dmp: float = o.get("damp", 0.0)
	p.damping_min = dmp * 0.8
	p.damping_max = dmp
	var av: float = o.get("ang", 0.0)
	p.angular_velocity_min = -av
	p.angular_velocity_max = av
	p.angle_min = 0.0
	p.angle_max = 360.0 if mat in ["add", "mix", "star", "shard", "chunk"] else 0.0
	var tg: float = o.get("tan", 0.0)
	p.tangential_accel_min = tg
	p.tangential_accel_max = tg
	var ra: float = o.get("radial", 0.0)
	p.radial_accel_min = ra
	p.radial_accel_max = ra
	p.particle_flag_align_y = mat == "streak"
	p.particle_flag_rotate_y = mat in ["shard", "chunk"]
	p.particle_flag_disable_z = false
	match str(o.get("shape", "point")):
		"sphere":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = maxf(0.01, float(o.get("rad", 0.5)))
		"ring":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = maxf(0.01, float(o.get("rad", 1.0)))
			p.emission_ring_inner_radius = 0.0
			p.emission_ring_height = 0.1
		"box":
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = o.get("box", Vector3.ONE)
		_:
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	p.mesh = MagicFX.pmesh(mat if mat in ["streak", "shard", "chunk", "ringflat"] else "quad")
	p.material_override = MagicFX.pmat(mat)
	p.color = o.get("col", Color.WHITE)
	var rp: String = o.get("ramp", "fade")
	p.color_ramp = MagicFX.ramp(rp)
	var sz: float = o.get("size", 0.3)
	var sv: float = o.get("svar", 0.4)
	p.scale_amount_min = sz * (1.0 - sv)
	p.scale_amount_max = sz
	var cv: String = o.get("curve", "")
	p.scale_amount_curve = MagicFX.curve(cv) if cv != "" else null
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _count(o: Dictionary) -> int:
	if o.get("exact", false):
		return maxi(1, int(o.get("n", 1)))
	return int(float(o.get("n", 10)) * _particle_budget)

## One-shot burst from the pool at `pos`. Returns null when culled.
func emit(pos: Vector3, o: Dictionary) -> CPUParticles3D:
	var critical: bool = o.get("critical", false)
	var n := _count(o)
	if n < 2 and not o.get("exact", false):
		if not critical:
			return null
		n = 2
	if _live_sys.size() >= MAX_SYS and not critical:
		return null
	if not critical and _far(pos):
		return null
	var p: CPUParticles3D
	if _free_sys.size() > 0:
		p = _free_sys.pop_back()
	else:
		p = CPUParticles3D.new()
		add_child(p)
	_config(p, o, n)
	p.one_shot = true
	var b: Basis = o.get("basis", Basis.IDENTITY)
	p.global_transform = Transform3D(b, pos)
	p.visible = true
	p.restart()
	p.emitting = true
	_live_sys.append(p)
	_live_end.append(_clock + p.lifetime * (1.0 + p.lifetime_randomness) + 0.15)
	return p

## Fresh looping emitter (not pooled): caller parents it and owns its life.
func make_emitter(o: Dictionary) -> CPUParticles3D:
	var n := _count(o)
	if n < 1:
		return null
	var p := CPUParticles3D.new()
	_config(p, o, maxi(1, n))
	p.one_shot = false
	p.emitting = false
	return p

func _far(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return false
	return cam.global_position.distance_squared_to(pos) > 4900.0

## Single additive glow sprite (fake bloom; also the low-quality flash).
func glow(pos: Vector3, c: Color, size: float, life: float) -> void:
	emit(pos, {"n": 1, "exact": true, "life": life, "lrand": 0.0, "mat": "add", "col": c, "size": size, "svar": 0.0, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "curve": "flash", "critical": true})

## Expanding flat shock ring on the ground.
func shock(pos: Vector3, r: float, c: Color, life: float) -> void:
	emit(pos + Vector3(0, 0.12, 0), {"n": 1, "exact": true, "life": life, "lrand": 0.0, "mat": "ringflat", "col": c, "size": r * 2.0, "svar": 0.0, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "curve": "grow", "critical": true})

## Expanding camera-facing ring (parry, heavy hit, time ripple).
func shock_v(pos: Vector3, r: float, c: Color, life: float, _dir: Vector3 = Vector3.ZERO) -> void:
	emit(pos, {"n": 1, "exact": true, "life": life, "lrand": 0.0, "mat": "ringv", "col": c, "size": r * 2.0, "svar": 0.0, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "curve": "grow", "critical": true})

func burst(pos: Vector3, c: Color, count: int, size: float) -> void:
	emit(pos, {"n": count, "life": 0.5, "mat": "streak", "col": c, "size": 0.25 + size * 0.5, "v0": 2.0, "v1": 5.5, "grav": Vector3(0, -9.0, 0), "curve": "shrink"})
	emit(pos, {"n": maxi(2, count / 2), "life": 0.55, "mat": "add", "col": c, "size": size * 1.2, "v0": 0.5, "v1": 2.0, "grav": Vector3(0, 0.5, 0), "damp": 2.0, "curve": "shrink"})
	glow(pos, c, 0.6 + size, 0.15)

func ring(pos: Vector3, r: float, c: Color, dur: float) -> void:
	shock(pos, r, c, dur * 1.2)
	if fx >= 1:
		shock(pos, r * 0.7, Color(c.r, c.g, c.b, 0.6), dur)

# ================================================================ lights
## Pool of short-lived magic lights: created once, reused, never shadowed.
## The pool size is the "lighting" budget (Settings: lights per profile /
## the separate lighting quality); when every light is busy the dimmest
## active one is taken over, so a big burst never adds lights beyond it.
var _pool: Array = []
var pool_peak := 0
var pool_reused := 0

func _pool_light() -> OmniLight3D:
	var cap := light_cap if fx > 0 else mini(light_cap, 2)
	for l in _pool:
		if not l.visible:
			return l
	if _pool.size() < cap:
		var nl := OmniLight3D.new()
		nl.shadow_enabled = false
		nl.visible = false
		nl.light_specular = 0.6
		add_child(nl)
		_pool.append(nl)
		return nl
	# all busy: steal the dimmest
	var best: OmniLight3D = null
	for l in _pool:
		if best == null or l.light_energy < best.light_energy:
			best = l
	if best != null:
		pool_reused += 1
		var tw0: Tween = best.get_meta("tw") if best.has_meta("tw") else null
		if tw0 and tw0.is_valid():
			tw0.kill()
	return best

func pool_active() -> int:
	var n := 0
	for l in _pool:
		if l.visible:
			n += 1
	return n

## Short flash light from the pool (never shadowed).
func light(pos: Vector3, c: Color, energy: float, rng: float, dur: float) -> void:
	if energy <= 0.0:
		return
	var l := _pool_light()
	if l == null:
		return
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.global_position = pos
	l.visible = true
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, maxf(0.03, dur)).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): l.visible = false)
	l.set_meta("tw", tw)
	pool_peak = maxi(pool_peak, pool_active())

## Persistent light parented to an effect; counted against the budget until freed.
func attach_light(parent: Node3D, c: Color, energy: float, rng: float, offset: Vector3) -> OmniLight3D:
	var cap := light_cap if fx > 0 else mini(light_cap, 2)
	if _lights_live + pool_active() >= cap or parent == null:
		return null
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.position = offset
	parent.add_child(l)
	_lights_live += 1
	l.tree_exiting.connect(func(): _lights_live -= 1)
	return l

func flash(pos: Vector3, c: Color, dur: float, energy: float) -> void:
	light(pos, c, energy, 5.0 + energy * 0.4, dur + 0.05)
	glow(pos, c, 0.8 + energy * 0.15, maxf(0.08, dur))

# ========================================================= ribbons / bolts
## Camera-facing ribbon: straight beam, jagged lightning or a beam between two
## moving nodes. Rebuilt per frame only while alive.
class FXStrip extends MeshInstance3D:
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var a_node: Node3D = null
	var b_node: Node3D = null
	var a_off := Vector3.ZERO
	var b_off := Vector3.ZERO
	var col := Color.WHITE
	var width := 0.1
	var life := 0.2
	var t := 0.0
	var jag := false
	var branches := 0
	var _ft := 0.0
	var _paths: Array = []
	var _pw: PackedFloat32Array = PackedFloat32Array()
	var _im: ImmediateMesh

	func _ready() -> void:
		_im = ImmediateMesh.new()
		mesh = _im
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_regen()

	func _process(dt: float) -> void:
		t += dt
		if t >= life:
			queue_free()
			return
		var moved := false
		if a_node != null:
			if is_instance_valid(a_node) and a_node.is_inside_tree():
				a = a_node.global_position + a_off
				moved = true
			else:
				a_node = null
		if b_node != null:
			if is_instance_valid(b_node) and b_node.is_inside_tree():
				b = b_node.global_position + b_off
				moved = true
			else:
				b_node = null
		if jag:
			_ft -= dt
			if _ft <= 0.0:
				_ft = 0.045
				_regen()
		elif moved:
			_regen()
		_draw(1.0 - t / life)

	func _regen() -> void:
		_paths.clear()
		_pw.clear()
		var L := a.distance_to(b)
		if not jag:
			_paths.append(PackedVector3Array([a, a.lerp(b, 0.5), b]))
			_pw.append(1.0)
			return
		var main := jag_path(a, b, L * 0.12, clampi(int(L / 1.5) + 2, 3, 5))
		_paths.append(main)
		_pw.append(1.0)
		for k in branches:
			if main.size() < 6:
				break
			var i := randi_range(2, main.size() - 3)
			var s: Vector3 = main[i]
			var d: Vector3 = (main[i + 1] - main[i - 1]).normalized()
			var side := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			d = (d + side * randf_range(-0.9, 0.9) + Vector3(0, randf_range(-0.4, 0.3), 0)).normalized()
			var bl := L * randf_range(0.15, 0.32)
			_paths.append(jag_path(s, s + d * bl, bl * 0.2, 3))
			_pw.append(0.5)

	static func jag_path(p0: Vector3, p1: Vector3, disp: float, depth: int) -> PackedVector3Array:
		var pts := PackedVector3Array([p0, p1])
		var dsp := disp
		for lvl in depth:
			var np := PackedVector3Array()
			for i in pts.size() - 1:
				var q0: Vector3 = pts[i]
				var q1: Vector3 = pts[i + 1]
				np.append(q0)
				var dir := (q1 - q0).normalized()
				var pr := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
				var pr2 := dir.cross(pr)
				np.append((q0 + q1) * 0.5 + pr * randf_range(-dsp, dsp) + pr2 * randf_range(-dsp, dsp))
			np.append(pts[pts.size() - 1])
			pts = np
			dsp *= 0.55
		return pts

	func _draw(fade: float) -> void:
		_im.clear_surfaces()
		var cam := get_viewport().get_camera_3d()
		var eye: Vector3 = cam.global_position if cam else a + Vector3(0, 10, 0)
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for pi in _paths.size():
			var pts: PackedVector3Array = _paths[pi]
			var w: float = width * _pw[pi] * (0.55 + 0.45 * fade)
			_strip(pts, eye, w * 3.2, Color(col.r, col.g, col.b, 0.42 * fade * col.a))
			_strip(pts, eye, w, Color(lerpf(col.r, 1.0, 0.7), lerpf(col.g, 1.0, 0.7), lerpf(col.b, 1.0, 0.7), fade))
		_im.surface_end()

	func _strip(pts: PackedVector3Array, eye: Vector3, w: float, c: Color) -> void:
		var n := pts.size()
		if n < 2:
			return
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for i in n:
			var p: Vector3 = pts[i]
			var tng: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)])
			var side := tng.cross(eye - p).normalized() * w
			var l := p - side
			var r := p + side
			if i > 0:
				var u0 := float(i - 1) / (n - 1)
				var u1 := float(i) / (n - 1)
				_v(prev_l, Vector2(u0, 0), c)
				_v(prev_r, Vector2(u0, 1), c)
				_v(r, Vector2(u1, 1), c)
				_v(prev_l, Vector2(u0, 0), c)
				_v(r, Vector2(u1, 1), c)
				_v(l, Vector2(u1, 0), c)
			prev_l = l
			prev_r = r

	func _v(p: Vector3, uv: Vector2, c: Color) -> void:
		_im.surface_set_color(c)
		_im.surface_set_uv(uv)
		_im.surface_add_vertex(p)

func _strip_mat() -> Material:
	return MagicFX.smat("beam", {"flow": 0.0, "grain": 0.0}, "strip")

func _new_strip(a: Vector3, b: Vector3, c: Color, dur: float, width: float) -> FXStrip:
	var s := FXStrip.new()
	s.a = a
	s.b = b
	s.col = c
	s.life = maxf(0.05, dur)
	s.width = width
	s.material_override = _strip_mat()
	return s

func beam(a: Vector3, b: Vector3, c: Color, dur: float, width: float, jagged: bool) -> void:
	if jagged:
		bolt(a, b, c, dur, width, 1)
		return
	var s := _new_strip(a, b, c, dur, width)
	add_child(s)
	glow(b, c, 0.5 + width * 3.0, minf(0.3, dur))

## Branching lightning bolt (re-jagged every ~45 ms while it lives).
func bolt(a: Vector3, b: Vector3, c: Color, dur: float, width: float, branches: int = 2) -> void:
	var s := _new_strip(a, b, c, dur, maxf(0.02, width))
	s.jag = true
	s.branches = branches if fx >= 1 else mini(branches, 1)
	add_child(s)
	if a.distance_to(b) > 3.0:
		light((a + b) * 0.5, c, 3.0, 8.0, dur)

## Beam glued to two actors' chests (drain, tethers).
func beam_follow(from_a, to_a, c: Color, dur: float, width: float) -> void:
	if not is_instance_valid(from_a) or not is_instance_valid(to_a):
		return
	var s := _new_strip(from_a.chest(), to_a.chest(), c, dur, width)
	s.a_node = from_a
	s.b_node = to_a
	s.a_off = from_a.chest() - from_a.global_position
	s.b_off = to_a.chest() - to_a.global_position
	add_child(s)

## Screen-space ripple ring (fx 2 only; additive ring otherwise).
func distort(pos: Vector3, size: float, life: float, tint: Color, billboard: bool) -> void:
	if fx < 2:
		if billboard:
			shock_v(pos, size * 0.5, Color(tint.r, tint.g, tint.b, 0.7), minf(life, 0.6))
		else:
			shock(pos, size * 0.5, Color(tint.r, tint.g, tint.b, 0.7), minf(life, 0.6))
		return
	var mi := MeshInstance3D.new()
	mi.mesh = MagicFX.pmesh("quad")
	var m := MagicFX.smat("distort", {"tint": tint, "strength": 0.03, "billboard": 1 if billboard else 0})
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	if not billboard:
		mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.scale = Vector3.ONE * size * 0.2
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size, minf(0.4, life)).set_ease(Tween.EASE_OUT)
	if life > 0.5:
		tw.tween_interval(life - 0.5)
	tw.tween_method(func(v: float): m.set_shader_parameter("strength", v), 0.03, 0.0, 0.25)
	tw.tween_callback(mi.queue_free)

func explosion(pos: Vector3, r: float, c: Color) -> void:
	MagicFX.explode(pos, r, c)

# ============================================================= telegraphs
## Ground warning conformed to the terrain that fills until the attack lands.
## Always drawn (never budgeted away) and depth-tested so actors stay visible.
func telegraph(pos: Vector3, r: float, dur: float, c: Color, shape: String, dir: Vector3, arc: float, length: float) -> void:
	var root := MeshInstance3D.new()
	add_child(root)
	root.global_position = pos
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		d = Vector3.FORWARD
	if shape == "line" or shape == "cone":
		root.look_at(pos + d.normalized(), Vector3.UP)
	var shp := 0
	match shape:
		"line":
			shp = 2
			var L := maxf(length, 1.0)
			root.mesh = _conform_grid(root, r, 0.0, -L, 3, clampi(int(L / 1.3), 2, 24), true)
		"cone":
			shp = 1
			var n := clampi(int(r * 1.6), 6, 18)
			root.mesh = _conform_grid(root, r, -r, r, n, n, false)
		_:
			var n2 := clampi(int(r * 1.6), 6, 18)
			root.mesh = _conform_grid(root, r, -r, r, n2, n2, false)
	var m := ShaderMaterial.new()
	m.shader = MagicFX.shader("telegraph")
	m.set_shader_parameter("col", Color(c.r, c.g, c.b, 1.0))
	m.set_shader_parameter("shape", shp)
	m.set_shader_parameter("half_arc", deg_to_rad(clampf(arc, 1.0, 360.0) * 0.5))
	m.set_shader_parameter("aspect", maxf(1.0, length / maxf(0.2, r * 2.0)))
	m.set_shader_parameter("progress", 0.0)
	m.render_priority = -1
	root.material_override = m
	root.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := root.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, maxf(0.05, dur))
	tw.tween_method(func(v: float): m.set_shader_parameter("done", v), 0.0, 1.0, 0.06)
	tw.tween_interval(0.06)
	tw.tween_callback(root.queue_free)

func _conform_grid(root: Node3D, xr: float, z0: float, z1: float, nx: int, nz: int, line: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xf := root.global_transform
	var base_y := xf.origin.y
	var has_gh: bool = Game.world != null and is_instance_valid(Game.world) and Game.world.has_method("ground_height")
	for iz in nz + 1:
		for ix in nx + 1:
			var lx := lerpf(-xr, xr, float(ix) / nx)
			var lz := lerpf(z0, z1, float(iz) / nz)
			var dy := 0.0
			if has_gh:
				var wp := xf * Vector3(lx, 0, lz)
				var gh: float = Game.world.ground_height(wp)
				dy = gh - base_y
				if dy < -0.9 or dy > 4.0:
					dy = 0.0
			if line:
				st.set_uv(Vector2(lx / xr, lz / z1))
			else:
				st.set_uv(Vector2(lx / xr, lz / xr))
			st.add_vertex(Vector3(lx, dy + 0.14, lz))
	for iz in nz:
		for ix in nx:
			var i0 := iz * (nx + 1) + ix
			var i1 := i0 + 1
			var i2 := i0 + nx + 1
			var i3 := i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)
	return st.commit()

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

# ========================================================= combat feedback
## Hit feedback by damage type; heavy hits add a shock ring, metal adds sparks.
func hit_fx(pos: Vector3, dir: Vector3, dtype: String, heavy: bool, metal: bool) -> void:
	var d := dir
	if d.length() < 0.01:
		d = Vector3.UP
	d = d.normalized()
	var s := 1.45 if heavy else 1.0
	var sch := MagicFX.school(dtype)
	if sch != "":
		MagicFX.hit(pos, d, sch, heavy)
	else:
		match dtype:
			"pierce":
				emit(pos, {"n": int(8 * s), "life": 0.3, "mat": "streak", "col": Color(1.0, 0.92, 0.8), "size": 0.3, "v0": 4.0, "v1": 8.0, "dir": d, "spread": 22.0, "grav": Vector3(0, -8, 0), "curve": "shrink", "critical": true})
				emit(pos, {"n": int(4 * s), "life": 0.5, "mat": "mix", "col": Color(0.4, 0.05, 0.05, 0.9), "size": 0.2, "v0": 1.5, "v1": 3.5, "dir": d, "spread": 30.0, "grav": Vector3(0, -9, 0), "ramp": "late"})
			"blunt":
				emit(pos, {"n": int(7 * s), "life": 0.6, "mat": "mix", "col": Color(0.75, 0.68, 0.58, 0.7), "ramp": "smoke", "size": 0.55 * s, "v0": 1.0, "v1": 2.5, "dir": d, "spread": 70.0, "damp": 3.0, "grav": Vector3(0, 0.3, 0), "curve": "puff", "critical": true})
				shock_v(pos, 0.7 * s, Color(1.0, 0.95, 0.85, 0.8), 0.18, d)
			_:
				emit(pos, {"n": int(9 * s), "life": 0.28, "mat": "streak", "col": Color(1.0, 0.95, 0.88), "size": 0.32, "v0": 3.0, "v1": 7.0, "dir": d, "spread": 55.0, "grav": Vector3(0, -6, 0), "curve": "shrink", "critical": true})
				if not metal:
					emit(pos, {"n": int(5 * s), "life": 0.55, "mat": "mix", "col": Color(0.42, 0.04, 0.04, 0.9), "size": 0.18, "v0": 1.5, "v1": 3.5, "dir": d, "spread": 45.0, "grav": Vector3(0, -10, 0), "ramp": "late"})
		glow(pos, Color(1.0, 0.96, 0.9), 0.55 * s, 0.1)
	if metal:
		emit(pos, {"n": int(12 * s), "life": 0.35, "mat": "streak", "col": Color(1.0, 0.85, 0.45), "size": 0.3, "v0": 5.0, "v1": 10.0, "dir": d, "spread": 75.0, "grav": Vector3(0, -14, 0), "curve": "shrink", "critical": true})
		glow(pos, Color(1.0, 0.9, 0.6), 0.7 * s, 0.08)
	if heavy:
		shock_v(pos, 1.1, Color(1.0, 0.95, 0.85, 0.9), 0.22, d)
		if fx >= 1 and dtype in ["slash", "pierce"] and not metal and decals_on:
			decal(Vector3(pos.x, MagicFX.ground_y(pos - Vector3(0, 1.0, 0)), pos.z) + d * 0.6, "blood", 0.8, 14.0, randf() * TAU)

## Parry: weapon clash — bright sparks both ways, flash, expanding ring.
func parry_fx(pos: Vector3, dir: Vector3) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	emit(pos, {"n": 24, "life": 0.4, "mat": "streak", "col": Color(1.0, 0.92, 0.55), "size": 0.42, "v0": 6.0, "v1": 12.0, "dir": d, "spread": 85.0, "grav": Vector3(0, -14, 0), "curve": "shrink", "critical": true})
	emit(pos, {"n": 12, "life": 0.35, "mat": "streak", "col": Color(1.0, 1.0, 0.9), "size": 0.35, "v0": 4.0, "v1": 8.0, "dir": -d, "spread": 80.0, "grav": Vector3(0, -14, 0), "curve": "shrink", "critical": true})
	emit(pos, {"n": 4, "exact": true, "life": 0.3, "mat": "star", "col": Color(1, 1, 0.85), "size": 0.9, "v0": 0.0, "v1": 0.3, "grav": Vector3.ZERO, "curve": "flash", "critical": true})
	glow(pos, Color(1.0, 0.95, 0.7), 1.6, 0.16)
	shock_v(pos, 1.4, Color(1.0, 0.9, 0.55), 0.25, d)
	light(pos, Color(1.0, 0.9, 0.6), 4.0, 6.0, 0.12)

## Block: shield ripple + a few sparks.
func block_fx(pos: Vector3, dir: Vector3) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	shock_v(pos, 0.9, Color(0.7, 0.85, 1.0, 0.9), 0.22, d)
	emit(pos, {"n": 8, "life": 0.3, "mat": "streak", "col": Color(1.0, 0.9, 0.65), "size": 0.3, "v0": 3.0, "v1": 6.0, "dir": d, "spread": 70.0, "grav": Vector3(0, -12, 0), "curve": "shrink", "critical": true})
	glow(pos, Color(0.85, 0.92, 1.0), 0.8, 0.1)

## Heavy landing: dust ring rolling outward, debris, shock wave, crack decal.
func ground_impact(pos: Vector3, r: float) -> void:
	var gp := MagicFX.ground_point(pos)
	var k := clampf(r, 0.6, 8.0)
	emit(gp + Vector3(0, 0.25, 0), {"n": int(8 + k * 6), "life": 1.0, "mat": "mix", "col": Color(0.72, 0.64, 0.52, 0.75), "ramp": "smoke", "size": 0.9 + k * 0.25, "shape": "ring", "rad": maxf(0.3, k * 0.35), "v0": 1.5, "v1": 2.5 + k, "radial": 3.0 + k, "dir": Vector3.UP, "spread": 25.0, "flat": 0.8, "damp": 2.5, "grav": Vector3(0, 0.2, 0), "curve": "puff", "critical": true})
	emit(gp + Vector3(0, 0.2, 0), {"n": int(5 + k * 3), "life": 0.9, "mat": "chunk", "col": Color(0.42, 0.36, 0.3), "size": 0.12 + k * 0.03, "v0": 3.0, "v1": 5.0 + k, "dir": Vector3.UP, "spread": 50.0, "grav": Vector3(0, -16, 0), "ang": 400.0})
	shock(gp, k * 1.15, Color(1.0, 0.9, 0.75, 0.7), 0.35)
	decal(gp, "crack", 1.2 + k * 1.1, 16.0, randf() * TAU)

## Temporary ground decal (scorch, frost, crack, footprint, blood, oil, hole).
func decal(pos: Vector3, kind: String, size: float, life: float, rot: float) -> void:
	if not decals_on or size <= 0.05:
		return
	var cap := 40 if fx >= 2 else 24
	var mi: MeshInstance3D = null
	var mat: StandardMaterial3D = null
	if _decals.size() < cap:
		mi = MeshInstance3D.new()
		mi.mesh = MagicFX.pmesh("plane")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 1.0
		mat.render_priority = -2
		mi.material_override = mat
		add_child(mi)
		_decals.append(mi)
	else:
		mi = _decals[_decal_i % _decals.size()]
		_decal_i += 1
		mat = mi.material_override
		var old: Tween = mi.get_meta("tw") if mi.has_meta("tw") else null
		if old and old.is_valid():
			old.kill()
	mat.albedo_texture = MagicFX.tex(kind)
	var tint := Color(1, 1, 1, 1)
	mat.emission_enabled = kind in ["frost", "rune", "electric"]
	mat.metallic_specular = 0.9 if kind == "wet" else 0.5
	mat.roughness = 0.08 if kind == "wet" else 1.0
	match kind:
		"frost":
			mat.emission = Color(0.3, 0.5, 0.7)
			mat.emission_energy_multiplier = 0.5
		"rune":
			mat.emission = Color(0.45, 0.25, 0.7)
			mat.emission_energy_multiplier = 0.45
		"electric":
			mat.emission = Color(0.4, 0.6, 1.0)
			mat.emission_energy_multiplier = 1.0
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.0)
	var p := pos
	var nrm := Vector3.UP
	var sp := Combat.space()
	if sp:
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 1.5, 0), pos - Vector3(0, 3.0, 0), Actor.LAYER_WORLD)
		var hit := sp.intersect_ray(q)
		if not hit.is_empty():
			p = hit.position
			nrm = hit.normal
	elif Game.world and Game.world.has_method("ground_height"):
		p.y = MagicFX.ground_y(pos)
	var bx := nrm.cross(Vector3.FORWARD if absf(nrm.z) < 0.9 else Vector3.RIGHT).normalized()
	var bz := bx.cross(nrm).normalized()
	var b := Basis(bx, nrm, bz).rotated(nrm, rot)
	mi.visible = true
	mi.global_transform = Transform3D(b.scaled(Vector3(size, 1.0, size)), p + nrm * (0.03 + 0.002 * (_decal_i % 8)))
	var tw := mi.create_tween()
	mi.set_meta("tw", tw)
	tw.tween_property(mat, "albedo_color:a", 1.0, 0.12)
	tw.tween_interval(maxf(0.0, life - 1.8))
	tw.tween_property(mat, "albedo_color:a", 0.0, minf(1.6, life * 0.4))
	tw.tween_callback(func(): mi.visible = false)

## Arrow / bolt left sticking in the world (or an actor) for a few seconds.
func stuck_arrow(pos: Vector3, dir: Vector3, length: float, host: Node3D = null) -> void:
	if fx <= 0 and host == null:
		return
	if _stuck.size() >= 18:
		var old = _stuck.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.box(Vector3(0.03, 0.03, length))
	mi.material_override = MeshLib.mat(Color(0.5, 0.36, 0.22))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fl := MeshInstance3D.new()
	fl.mesh = MeshLib.box(Vector3(0.09, 0.005, 0.14))
	fl.material_override = MeshLib.mat(Color(0.85, 0.85, 0.8))
	fl.position = Vector3(0, 0, length * 0.45)
	mi.add_child(fl)
	var parent: Node3D = host if host != null and is_instance_valid(host) else self
	parent.add_child(mi)
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	mi.global_position = pos - d * length * 0.3
	mi.look_at(mi.global_position + d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
	_stuck.append(mi)
	var tw := mi.create_tween()
	tw.tween_interval(3.0 if host != null else 6.0)
	tw.tween_property(mi, "scale", Vector3(1, 1, 0.01), 0.3)
	tw.tween_callback(mi.queue_free)

## Ranged impact on world geometry (dust/sparks by projectile kind).
func world_impact(pos: Vector3, nrm: Vector3, kind: String, vel: Vector3) -> void:
	var n := nrm if nrm.length() > 0.01 else -vel.normalized()
	match kind:
		"arrow", "bolt":
			emit(pos, {"n": 5, "life": 0.5, "mat": "mix", "col": Color(0.7, 0.62, 0.5, 0.7), "ramp": "smoke", "size": 0.35, "v0": 0.5, "v1": 1.5, "dir": n, "spread": 50.0, "grav": Vector3(0, -1, 0), "curve": "puff"})
			stuck_arrow(pos, vel, 0.7 if kind == "arrow" else 0.45)
		"bullet", "pellet":
			emit(pos, {"n": 6, "life": 0.25, "mat": "streak", "col": Color(1.0, 0.85, 0.5), "size": 0.25, "v0": 3.0, "v1": 7.0, "dir": n, "spread": 45.0, "grav": Vector3(0, -12, 0), "curve": "shrink"})
			emit(pos, {"n": 4, "life": 0.6, "mat": "mix", "col": Color(0.65, 0.6, 0.55, 0.7), "ramp": "smoke", "size": 0.35, "v0": 0.5, "v1": 1.2, "dir": n, "spread": 30.0, "grav": Vector3(0, 0.3, 0), "curve": "puff"})
			if absf(n.y) > 0.6:
				decal(pos, "hole", 0.3, 10.0, randf() * TAU)
		_:
			emit(pos, {"n": 6, "life": 0.3, "mat": "streak", "col": Color(1, 0.95, 0.85), "size": 0.25, "v0": 2.0, "v1": 5.0, "dir": n, "spread": 60.0, "grav": Vector3(0, -10, 0)})

## Muzzle flash by weapon type.
func muzzle(pos: Vector3, dir: Vector3, model: String, kind: String) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	match kind:
		"arrow", "bolt":
			emit(pos, {"n": 3, "life": 0.25, "mat": "add", "col": Color(1, 1, 1, 0.5), "size": 0.15, "v0": 1.0, "v1": 2.0, "dir": d, "spread": 30.0, "grav": Vector3.ZERO})
		"bullet", "pellet":
			var flint := model in ["musket", "pistol_old"]
			var big := flint or kind == "pellet" or model == "rifle"
			glow(pos, Color(1.0, 0.82, 0.45), 0.9 if big else 0.6, 0.07)
			emit(pos, {"n": 4, "exact": true, "life": 0.06, "lrand": 0.0, "mat": "star", "col": Color(1.0, 0.85, 0.5), "size": 0.8 if big else 0.55, "v0": 0.0, "v1": 0.0, "grav": Vector3.ZERO, "critical": true})
			emit(pos, {"n": 10 if big else 6, "life": 0.12, "mat": "streak", "col": Color(1.0, 0.75, 0.35), "size": 0.35, "v0": 6.0, "v1": 12.0, "dir": d, "spread": 14.0 if kind != "pellet" else 22.0, "grav": Vector3.ZERO})
			emit(pos, {"n": 14 if flint else 5, "life": 1.6 if flint else 0.7, "mat": "mix", "col": Color(0.75, 0.73, 0.7, 0.75 if flint else 0.5), "ramp": "smoke", "size": 0.9 if flint else 0.45, "v0": 0.8, "v1": 2.2 if flint else 1.2, "dir": d, "spread": 25.0, "damp": 2.0, "grav": Vector3(0, 0.4, 0), "curve": "puff"})
			light(pos, Color(1.0, 0.8, 0.45), 2.5 if big else 1.6, 5.0, 0.06)
		"pulse":
			glow(pos, Color(0.4, 0.85, 1.0), 0.7, 0.08)
			shock_v(pos, 0.35, Color(0.4, 0.85, 1.0), 0.12, d)
			emit(pos, {"n": 6, "life": 0.15, "mat": "streak", "col": Color(0.5, 0.9, 1.0), "size": 0.3, "v0": 4.0, "v1": 8.0, "dir": d, "spread": 30.0, "grav": Vector3.ZERO})
		"plasma":
			glow(pos, Color(1.0, 0.6, 0.3), 1.1, 0.12)
			shock_v(pos, 0.5, Color(1.0, 0.55, 0.25), 0.16, d)
			light(pos, Color(1.0, 0.55, 0.25), 2.0, 5.0, 0.1)
		"spark":
			glow(pos, Color(0.7, 0.8, 1.0), 0.7, 0.08)
			bolt(pos, pos + d * 1.2 + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3)), Color(0.6, 0.7, 1.0), 0.07, 0.03, 0)
		_:
			glow(pos, Color(1.0, 0.9, 0.7), 0.5, 0.06)

## Crescent swing arc in front of an attacker (claws, big sweeps, spins).
func slash_arc(origin: Vector3, facing: Vector3, rng: float, arc_deg: float, anim: String, c: Color) -> void:
	if not is_inside_tree():
		return
	var f := Vector3(facing.x, 0, facing.z)
	if f.length() < 0.01:
		f = Vector3.FORWARD
	f = f.normalized()
	var arc := clampf(arc_deg, 30.0, 360.0)
	var tilt := 0.0
	match anim:
		"slash": tilt = 22.0
		"slash2": tilt = -22.0
		"overhead", "slam": tilt = 80.0
		"thrust", "stab":
			arc = 26.0
	var mi: MeshInstance3D
	var mat: StandardMaterial3D
	if _arcs.size() < 12:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		mat.disable_fog = true
		mi.material_override = mat
		add_child(mi)
		_arcs.append(mi)
	else:
		mi = _arcs[_arc_i % _arcs.size()]
		_arc_i += 1
		mat = mi.material_override
		var old: Tween = mi.get_meta("tw") if mi.has_meta("tw") else null
		if old and old.is_valid():
			old.kill()
	mi.mesh = _crescent(int(arc))
	mat.albedo_color = Color(c.r, c.g, c.b, 0.9)
	var b := Basis.looking_at(f, Vector3.UP)
	b = b * Basis(Vector3.BACK, deg_to_rad(tilt))
	mi.visible = true
	mi.global_transform = Transform3D(b.scaled(Vector3.ONE * rng * 1.05), origin)
	var tw := mi.create_tween()
	mi.set_meta("tw", tw)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mi, "scale", mi.scale * 1.12, 0.2)
	tw.tween_callback(func(): mi.visible = false)

func _crescent(arc: int) -> ArrayMesh:
	var key := "cres%d" % arc
	if _sector_cache.has(key):
		return _sector_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := clampi(arc / 10, 4, 28)
	var half := deg_to_rad(arc * 0.5)
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var a0 := -half + 2.0 * half * t0
		var a1 := -half + 2.0 * half * t1
		var w0 := sin(t0 * PI) * 0.9 + 0.1
		var w1 := sin(t1 * PI) * 0.9 + 0.1
		var in0 := 1.0 - 0.38 * w0
		var in1 := 1.0 - 0.38 * w1
		var o0 := Vector3(sin(a0), 0, -cos(a0))
		var o1 := Vector3(sin(a1), 0, -cos(a1))
		var ca0 := Color(1, 1, 1, t0 * 0.95)
		var ca1 := Color(1, 1, 1, t1 * 0.95)
		var ci0 := Color(1, 1, 1, 0.0)
		var ci1 := Color(1, 1, 1, 0.0)
		st.set_color(ci0)
		st.add_vertex(o0 * in0)
		st.set_color(ca0)
		st.add_vertex(o0)
		st.set_color(ca1)
		st.add_vertex(o1)
		st.set_color(ci0)
		st.add_vertex(o0 * in0)
		st.set_color(ca1)
		st.add_vertex(o1)
		st.set_color(ci1)
		st.add_vertex(o1 * in1)
	var m := st.commit()
	_sector_cache[key] = m
	return m

# ========================================================= status visuals
func _scan_status() -> void:
	var center := Vector3.ZERO
	var pl = Game.player
	if pl and is_instance_valid(pl):
		center = pl.global_position
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		center = cam.global_position
	var seen := {}
	var count := 0
	for a in Game.actors_near(center, 34.0):
		if count >= 48:
			break
		if not is_instance_valid(a) or a.is_dead:
			continue
		count += 1
		var aid = a.actor_id
		seen[aid] = true
		var e: Dictionary = _status.get(aid, {})
		if e.is_empty():
			var any := false
			for k in STATUS_KINDS:
				if a.statuses.has(k):
					any = true
					break
			if not any:
				continue
			e = {"a": a, "n": {}, "ov": ""}
			_status[aid] = e
		_sync_status(a, e)
	for aid in _status.keys():
		var e2: Dictionary = _status[aid]
		var a2 = e2.a
		if not seen.has(aid) or not is_instance_valid(a2) or a2.is_dead:
			_clear_status(e2)
			_status.erase(aid)

func _sync_status(a, e: Dictionary) -> void:
	var nodes: Dictionary = e.n
	var s: float = clampf(a._scale(), 0.5, 4.0)
	for k in STATUS_KINDS:
		var has: bool = a.statuses.has(k)
		var nd = nodes.get(k)
		if nd != null and not is_instance_valid(nd):
			nodes.erase(k)
			nd = null
		if has and nd == null:
			if k == "magic_shield" and a.get("shield_hp") != null and float(a.shield_hp) <= 0.0:
				continue
			var made: Node3D = MagicFX.status_node(a, k, s)
			if made:
				nodes[k] = made
		elif not has and nd != null:
			MagicFX.end_status_node(nd, a)
			nodes.erase(k)
	var want := ""
	for k2 in ["freeze", "stasis", "curse", "timeslow"]:
		if a.statuses.has(k2):
			want = k2
			break
	if want != e.ov:
		_set_overlay(a, MagicFX.overlay_mat(want) if want != "" else null)
		e.ov = want

func _set_overlay(a, m: Material) -> void:
	var rig = a.get("rig")
	if rig == null or not is_instance_valid(rig):
		return
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var cur: Material = mi.material_overlay
		if cur == null or cur.has_meta("fx_overlay"):
			mi.material_overlay = m

func _clear_status(e: Dictionary) -> void:
	var a = e.a
	for nd in e.n.values():
		if is_instance_valid(nd):
			nd.queue_free()
	if e.ov != "" and is_instance_valid(a):
		_set_overlay(a, null)

# ============================================================ swing trails
func _update_trails(delta: float) -> void:
	_trail_scan_t -= delta
	if _trail_scan_t <= 0.0:
		_trail_scan_t = 0.25
		_trail_cands.clear()
		var pl = Game.player
		if pl and is_instance_valid(pl):
			if fx <= 0:
				_trail_cands.append(pl)
			else:
				for a in Game.actors_near(pl.global_position, 24.0):
					if _trail_cands.size() >= 16:
						break
					if is_instance_valid(a) and not a.is_dead and a.get("rig") != null:
						_trail_cands.append(a)
		for aid in _trails.keys():
			var tr = _trails[aid]
			if not is_instance_valid(tr):
				_trails.erase(aid)
			elif not tr.active and tr.idle_time() > 3.0:
				tr.queue_free()
				_trails.erase(aid)
	for a in _trail_cands:
		if not is_instance_valid(a) or a.is_dead:
			continue
		var act: Dictionary = a.act
		var swing := false
		if not act.is_empty() and str(act.get("name", "")) in ["melee", "skill"]:
			var anim: String = act.get("data", {}).get("anim", "")
			swing = not (anim in ["shoot", "cast", "roar", "throw", "kick"]) and float(act.t) < float(act.dur) * 0.8
		var aid = a.actor_id
		var tr = _trails.get(aid)
		if tr != null and not is_instance_valid(tr):
			tr = null
		if swing:
			var wn = a.rig.get("weapon_node")
			if not is_instance_valid(wn) or not wn.has_meta("tip"):
				continue
			var tip = wn.get_meta("tip")
			if not is_instance_valid(tip):
				continue
			if tr == null:
				tr = SwingTrail.new()
				add_child(tr)
				_trails[aid] = tr
			if tr.target != tip:
				tr.target = tip
				tr.base = wn
				tr.color = _trail_color(a)
			tr.active = true
		elif tr != null:
			tr.active = false

func _trail_color(a) -> Color:
	var w: Dictionary = a.weapon()
	if w.get("mythic", "") != "":
		return Color(1.0, 0.25, 0.3, 0.75)
	var r: int = w.get("rarity", 0)
	if r >= 4:
		return Color(1.0, 0.85, 0.4, 0.75)
	if r == 3:
		return Color(0.8, 0.5, 1.0, 0.7)
	if a.kind == "boss":
		return Color(1.0, 0.45, 0.3, 0.7)
	return Color(0.85, 0.92, 1.0, 0.55)
