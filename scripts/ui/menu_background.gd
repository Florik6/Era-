class_name MenuBackground
extends Node3D
## Main-menu diorama: an era-themed scene, the hero on a stone dais,
## drifting temporal anomalies and a slowly swaying camera.

var era := 0
var rig: Node3D = null
var cam: Camera3D
var env: WorldEnvironment
var sun: DirectionalLight3D
var props_root: Node3D
var anomalies: Node3D
var sky_mat: ProceduralSkyMaterial
var focus_x := -1.15          # camera side shift: negative = hero right of centre
var _focus_target := -1.15
var _t := 0.0
var _action_cd := 5.0
var _action_len := 0.9
var _tori: Array = []
var _floaters: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_env()
	props_root = Node3D.new()
	add_child(props_root)
	anomalies = Node3D.new()
	add_child(anomalies)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.05
	cam.far = 200.0
	add_child(cam)
	cam.current = true

func _build_env() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.08
	e.fog_enabled = true
	e.fog_density = 0.012
	e.fog_aerial_perspective = 0.4
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, 145, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.5, 2.2, 2.5)
	fill.light_energy = 0.6
	fill.omni_range = 7.0
	fill.light_color = Color(0.7, 0.8, 1.0)
	add_child(fill)

func set_era(i: int) -> void:
	era = clampi(i, 0, DBEras.ERA_COUNT - 1)
	var e := DBEras.era(era)
	sky_mat.sky_top_color = e.sky_top
	sky_mat.sky_horizon_color = e.sky_horizon
	sky_mat.ground_horizon_color = e.sky_horizon.darkened(0.2)
	sky_mat.ground_bottom_color = Color(e.ground.plains).darkened(0.6)
	sky_mat.sun_angle_max = 30.0
	sun.light_color = e.sun.lerp(Color(1.0, 0.75, 0.5), 0.35)
	env.environment.fog_light_color = e.fog_color
	env.environment.ambient_light_color = e.ambient
	_build_props(e)
	_build_anomalies(e)

func _build_props(e: Dictionary) -> void:
	for c in props_root.get_children():
		c.queue_free()
	var g: Dictionary = e.ground
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + era
	MeshLib.part(props_root, MeshLib.cyl(26.0, 26.0, 0.2, 48), MeshLib.mat(Color(g.plains)), Vector3(0, -0.1, 0))
	# grass/ground patches
	for k in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, 14.0)
		var c: Color = Color(g.forest) if rng.randf() < 0.6 else Color(g.road)
		MeshLib.part(props_root, MeshLib.cyl(1.0, 1.0, 0.02, 12), MeshLib.mat(c), Vector3(cos(a) * r, 0.01, sin(a) * r), Vector3.ZERO, Vector3(rng.randf_range(0.8, 2.4), 1, rng.randf_range(0.8, 2.4)), false)
	# dais
	var stone := MeshLib.mat(Color(0.48, 0.46, 0.44) if era < 4 else Color(0.2, 0.22, 0.28), 0.0 if era < 4 else 0.6, 0.8 if era < 4 else 0.35)
	MeshLib.part(props_root, MeshLib.cyl(1.7, 1.9, 0.22, 24), stone, Vector3(0, 0.11, 0))
	MeshLib.part(props_root, MeshLib.cyl(1.35, 1.35, 0.04, 32), stone, Vector3(0, 0.23, 0))
	MeshLib.part(props_root, MeshLib.torus(1.28, 1.36), MeshLib.mat(Color(e.sky_horizon).lerp(UITheme.GOLD, 0.6), 0.0, 1.0, 1.6, true), Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 0.3, 1), false)
	match e.style:
		"medieval":
			_pillars(stone, rng, true)
			for k in 14:
				_tree(rng, Color(g.forest), "oak" if rng.randf() < 0.5 else "pine")
			_rocks(rng, 8)
			_arch(stone, Vector3(-4.5, 0, -6.5))
		"renaissance":
			_pillars(MeshLib.mat(Color(0.86, 0.82, 0.72)), rng, false)
			for k in 10:
				_tree(rng, Color(g.forest), "cypress")
			_rocks(rng, 5)
			_arch(MeshLib.mat(Color(0.86, 0.82, 0.72)), Vector3(4.5, 0, -6.0))
		"industrial":
			var brick := MeshLib.mat(Color(0.45, 0.22, 0.16))
			for p in [Vector3(-6, 0, -7), Vector3(5.5, 0, -8.5), Vector3(-9, 0, -3)]:
				MeshLib.part(props_root, MeshLib.cyl(0.55, 0.75, 7.5, 12), brick, p + Vector3(0, 3.75, 0))
				MeshLib.part(props_root, MeshLib.cyl(0.62, 0.62, 0.3, 12), MeshLib.mat(Color(0.15, 0.15, 0.15)), p + Vector3(0, 7.5, 0))
			for k in 6:
				var a := rng.randf_range(PI * 0.9, PI * 2.1)
				var r := rng.randf_range(4.0, 9.0)
				MeshLib.part(props_root, MeshLib.cyl(0.18, 0.18, 4.0, 8), MeshLib.mat(Color(0.5, 0.4, 0.3), 0.7, 0.4), Vector3(cos(a) * r, 0.4, sin(a) * r), Vector3(0, rng.randf() * 180.0, 90))
			_gear(Vector3(3.2, 1.6, -3.0), 1.2)
			for k in 7:
				_tree(rng, Color(0.3, 0.26, 0.2), "dead")
		"modern":
			for k in 4:
				var a := PI + k * 0.55 - 0.8
				var p := Vector3(cos(a) * 5.0, 0, sin(a) * 5.0)
				MeshLib.part(props_root, MeshLib.cyl(0.06, 0.08, 4.0, 8), MeshLib.mat(Color(0.25, 0.26, 0.28), 0.7, 0.4), p + Vector3(0, 2, 0))
				MeshLib.part(props_root, MeshLib.box(Vector3(0.5, 0.12, 0.25)), MeshLib.glow(Color(1.0, 0.92, 0.7), 2.0), p + Vector3(0, 4.0, 0))
			for p in [Vector3(-6, 0, -6), Vector3(6, 0, -7)]:
				MeshLib.part(props_root, MeshLib.box(Vector3(2.4, 2.4, 6.0)), MeshLib.mat(Color(0.6, 0.25, 0.15), 0.4, 0.6), p + Vector3(0, 1.2, 0), Vector3(0, 30, 0))
			for k in 8:
				_tree(rng, Color(g.forest), "oak")
			_rocks(rng, 4)
		"future":
			for k in 7:
				var a := PI + k * 0.45 - 1.3
				var r := rng.randf_range(5.0, 8.0)
				var col = [Color(0.3, 0.9, 1.0), Color(1.0, 0.3, 0.8), Color(0.6, 0.4, 1.0)][k % 3]
				var h := rng.randf_range(2.5, 6.0)
				MeshLib.part(props_root, MeshLib.box(Vector3(0.35, h, 0.35)), MeshLib.mat(Color(0.12, 0.13, 0.18), 0.7, 0.3), Vector3(cos(a) * r, h * 0.5, sin(a) * r))
				MeshLib.part(props_root, MeshLib.box(Vector3(0.38, 0.08, 0.38)), MeshLib.glow(col, 3.0), Vector3(cos(a) * r, h, sin(a) * r))
				MeshLib.part(props_root, MeshLib.box(Vector3(0.05, h * 0.9, 0.37)), MeshLib.glow(col, 1.5), Vector3(cos(a) * r, h * 0.5, sin(a) * r))
			for k in 6:
				var a2 := rng.randf() * TAU
				var r2 := rng.randf_range(3.5, 10.0)
				MeshLib.part(props_root, MeshLib.prism(Vector3(0.6, rng.randf_range(1.0, 2.6), 0.6)), MeshLib.mat(Color(0.5, 0.9, 1.0, 0.85), 0.3, 0.1, 1.2), Vector3(cos(a2) * r2, 0.6, sin(a2) * r2), Vector3(0, rng.randf() * 90.0, rng.randf_range(-12, 12)))

func _pillars(m: Material, rng: RandomNumberGenerator, broken: bool) -> void:
	for k in 7:
		var a := PI + 0.35 + k * (PI * 1.3 / 6.0) - 0.65
		var p := Vector3(cos(a) * 4.2, 0, sin(a) * 4.2)
		var h := 3.2
		if broken and k % 3 == 1:
			h = rng.randf_range(0.8, 1.8)
		MeshLib.part(props_root, MeshLib.cyl(0.32, 0.36, h, 10), m, p + Vector3(0, h * 0.5, 0))
		MeshLib.part(props_root, MeshLib.box(Vector3(0.85, 0.22, 0.85)), m, p + Vector3(0, 0.11, 0))
		if h > 3.0:
			MeshLib.part(props_root, MeshLib.box(Vector3(0.85, 0.24, 0.85)), m, p + Vector3(0, h + 0.1, 0))

func _arch(m: Material, p: Vector3) -> void:
	MeshLib.part(props_root, MeshLib.box(Vector3(0.7, 4.0, 0.7)), m, p + Vector3(-1.5, 2.0, 0))
	MeshLib.part(props_root, MeshLib.box(Vector3(0.7, 4.0, 0.7)), m, p + Vector3(1.5, 2.0, 0))
	MeshLib.part(props_root, MeshLib.box(Vector3(4.0, 0.7, 0.8)), m, p + Vector3(0, 4.3, 0))

func _tree(rng: RandomNumberGenerator, leaf: Color, kind: String) -> void:
	var a := rng.randf_range(PI * 0.75, PI * 2.25)
	var r := rng.randf_range(6.0, 15.0)
	var p := Vector3(cos(a) * r, 0, sin(a) * r)
	var s := rng.randf_range(0.8, 1.4)
	var trunk := MeshLib.mat(Color(0.35, 0.24, 0.15))
	var lm := MeshLib.mat(leaf.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.08))
	match kind:
		"pine":
			MeshLib.part(props_root, MeshLib.cyl(0.12, 0.18, 1.2, 6), trunk, p + Vector3(0, 0.6, 0) * s, Vector3.ZERO, Vector3.ONE * s)
			MeshLib.part(props_root, MeshLib.cyl(0.0, 1.1, 2.6, 8), lm, p + Vector3(0, 2.2, 0) * s, Vector3.ZERO, Vector3.ONE * s)
			MeshLib.part(props_root, MeshLib.cyl(0.0, 0.8, 1.8, 8), lm, p + Vector3(0, 3.3, 0) * s, Vector3.ZERO, Vector3.ONE * s)
		"cypress":
			MeshLib.part(props_root, MeshLib.cyl(0.1, 0.14, 0.8, 6), trunk, p + Vector3(0, 0.4, 0) * s, Vector3.ZERO, Vector3.ONE * s)
			MeshLib.part(props_root, MeshLib.sphere(0.6, 8, 6), lm, p + Vector3(0, 2.4, 0) * s, Vector3.ZERO, Vector3(1, 3.2, 1) * s)
		"dead":
			MeshLib.part(props_root, MeshLib.cyl(0.08, 0.16, 2.6, 6), trunk, p + Vector3(0, 1.3, 0) * s, Vector3(0, 0, rng.randf_range(-8, 8)), Vector3.ONE * s)
			MeshLib.part(props_root, MeshLib.cyl(0.04, 0.07, 1.2, 5), trunk, p + Vector3(0.3, 2.0, 0) * s, Vector3(0, 0, -40), Vector3.ONE * s)
		_:
			MeshLib.part(props_root, MeshLib.cyl(0.14, 0.22, 1.6, 6), trunk, p + Vector3(0, 0.8, 0) * s, Vector3.ZERO, Vector3.ONE * s)
			MeshLib.part(props_root, MeshLib.sphere(1.2, 9, 6), lm, p + Vector3(0, 2.3, 0) * s, Vector3.ZERO, Vector3(1.1, 0.9, 1.1) * s)
			MeshLib.part(props_root, MeshLib.sphere(0.8, 8, 5), lm, p + Vector3(0.5, 2.9, 0.2) * s, Vector3.ZERO, Vector3.ONE * s)

func _rocks(rng: RandomNumberGenerator, n: int) -> void:
	for k in n:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.6, 11.0)
		var s := rng.randf_range(0.3, 0.9)
		MeshLib.part(props_root, MeshLib.sphere(1.0, 6, 4), MeshLib.mat(Color(0.45, 0.44, 0.42)), Vector3(cos(a) * r, s * 0.3, sin(a) * r), Vector3(rng.randf() * 40, rng.randf() * 180, 0), Vector3(s * 1.3, s * 0.8, s))

func _gear(p: Vector3, r: float) -> void:
	var g := Node3D.new()
	g.position = p
	g.rotation_degrees.x = 90
	props_root.add_child(g)
	var m := MeshLib.mat(Color(0.75, 0.55, 0.3), 0.8, 0.35)
	MeshLib.part(g, MeshLib.cyl(r, r, 0.18, 16), m)
	for k in 10:
		var a := k * TAU / 10.0
		MeshLib.part(g, MeshLib.box(Vector3(0.28, 0.18, 0.3)), m, Vector3(cos(a) * (r + 0.12), 0, sin(a) * (r + 0.12)), Vector3(0, -rad_to_deg(a), 0))
	_floaters.append({"node": g, "spin": 0.25, "axis": Vector3.UP, "base": p, "bob": 0.0})

func _build_anomalies(e: Dictionary) -> void:
	for c in anomalies.get_children():
		c.queue_free()
	_tori.clear()
	var gold := Color(1.0, 0.82, 0.4)
	var tc := Color(e.sky_horizon).lerp(Color(0.4, 1.0, 0.9), 0.5)
	# great clock ring behind the hero
	var clock := Node3D.new()
	clock.position = Vector3(0, 2.2, -3.4)
	anomalies.add_child(clock)
	MeshLib.part(clock, MeshLib.torus(2.1, 2.15), MeshLib.mat(Color(gold.r, gold.g, gold.b, 0.75), 0.0, 1.0, 1.4, true), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
	MeshLib.part(clock, MeshLib.torus(1.57, 1.6), MeshLib.mat(Color(tc.r, tc.g, tc.b, 0.6), 0.0, 1.0, 1.2, true), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
	for k in 12:
		var a := k * TAU / 12.0
		MeshLib.part(clock, MeshLib.box(Vector3(0.06, 0.22 if k % 3 == 0 else 0.12, 0.04)), MeshLib.mat(gold, 0.0, 1.0, 2.5, true), Vector3(sin(a) * 1.85, cos(a) * 1.85, 0), Vector3(0, 0, -rad_to_deg(a)), Vector3.ONE, false)
	var hand := Node3D.new()
	clock.add_child(hand)
	MeshLib.part(hand, MeshLib.box(Vector3(0.05, 1.2, 0.03)), MeshLib.mat(gold, 0.0, 1.0, 2.5, true), Vector3(0, 0.55, 0.02), Vector3.ZERO, Vector3.ONE, false)
	_tori.append({"node": hand, "axis": Vector3(0, 0, 1), "speed": -0.35})
	_tori.append({"node": clock, "axis": Vector3(0, 0, 1), "speed": 0.0})
	# floating anomaly rings
	for k in 4:
		var n := Node3D.new()
		var a := -0.9 + k * 0.6
		n.position = Vector3(sin(a) * 5.5, 2.2 + k * 0.7, -3.5 - cos(a) * 3.0)
		anomalies.add_child(n)
		var rr := 0.4 + 0.25 * k
		MeshLib.part(n, MeshLib.torus(rr * 0.85, rr), MeshLib.mat(tc if k % 2 == 0 else gold, 0.0, 1.0, 2.0, true), Vector3.ZERO, Vector3(randf() * 90, 0, randf() * 90), Vector3.ONE, false)
		MeshLib.part(n, MeshLib.sphere(rr * 0.25, 8, 6), MeshLib.mat(tc, 0.0, 1.0, 3.0, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		_tori.append({"node": n, "axis": Vector3(randf() - 0.5, 1, randf() - 0.5).normalized(), "speed": 0.4 + 0.2 * k})
		_floaters.append({"node": n, "spin": 0.0, "axis": Vector3.UP, "base": n.position, "bob": k * 1.3})
	# drifting sparks
	var p := CPUParticles3D.new()
	p.amount = int(80 * maxf(0.4, Settings.profile().particles))
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(9, 0.5, 5)
	p.position = Vector3(0, 0.5, -4)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 0.05, 0)
	p.mesh = MeshLib.sphere(0.018, 4, 2)
	p.material_override = MeshLib.mat(tc, 0.0, 1.0, 3.0, true)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	anomalies.add_child(p)

func set_character(look: Dictionary, equip: Dictionary, cape: bool = true) -> void:
	if rig and is_instance_valid(rig):
		rig.queue_free()
	var r := HumanoidRig.new()
	add_child(r)
	r.setup(look)
	r.set_gear(equip, Color(0, 0, 0, 0), cape)
	r.position = Vector3(0, 0.27, 0)
	r.rotation.y = PI
	rig = r
	_action_cd = 2.5

func set_framing(x: float) -> void:
	_focus_target = x

func _process(delta: float) -> void:
	_t += delta
	focus_x = lerpf(focus_x, _focus_target, minf(1.0, delta * 3.0))
	var a := sin(_t * 0.12) * 0.32 + 0.12
	var radius := 5.2
	var target := Vector3(0, 1.05, 0)
	cam.position = Vector3(sin(a) * radius, 1.7 + sin(_t * 0.2) * 0.05, cos(a) * radius)
	cam.look_at(target, Vector3.UP)
	cam.position += cam.global_transform.basis.x * focus_x
	for t in _tori:
		if is_instance_valid(t.node) and t.speed != 0.0:
			t.node.rotate(t.axis, delta * t.speed)
	for f in _floaters:
		if not is_instance_valid(f.node):
			continue
		if f.spin != 0.0:
			f.node.rotate_object_local(f.axis, delta * f.spin)
		else:
			f.node.position = f.base + Vector3(0, sin(_t * 0.8 + f.bob) * 0.25, 0)
	# hero shows off occasionally
	if rig and is_instance_valid(rig):
		if rig.action != "":
			rig.action_p += delta / _action_len
			if rig.action_p >= 1.0:
				rig.action = ""
				rig.action_p = 0.0
		else:
			_action_cd -= delta
			if _action_cd <= 0.0:
				_action_cd = randf_range(6.0, 10.0)
				var acts := ["cheer", "slash", "thrust", "spin", "cast"]
				var cat: String = rig.weapon_cat
				if cat == "bow" or cat == "firearm":
					acts = ["shoot", "cheer"]
				elif cat == "staff":
					acts = ["cast", "cheer"]
				var act: String = acts[randi() % acts.size()]
				_action_len = 1.1 if act in ["cheer", "spin"] else 0.8
				rig.trigger(act)
