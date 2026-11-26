class_name AmbientLife
## Cheap ambient life for streamed chunks: butterflies over meadows, falling
## leaves in forests, circling bird flocks, road dust, chimney / campfire smoke
## and sparks. GPU particles with shared materials, no lights, small amounts
## scaled by the Visual Quality "particles" factor; gated by "ambient_life".

static var _mats := {}

static func populate(streamer, node: Node3D, k: Vector2i, rng: RandomNumberGenerator) -> void:
	var gen = streamer.gen
	var q: Dictionary = streamer.quality()
	var pf: float = clampf(float(q.get("particles", 0.7)), 0.0, 1.5)
	if pf <= 0.05:
		return
	var cx: float = k.x * 64.0 + 32.0
	var cz: float = k.y * 64.0 + 32.0
	var b: String = gen.biome(cx, cz)
	var era: int = gen.era
	var h: float = gen.height(cx, cz)
	if h < gen.water_level:
		return
	var roll := rng.randf()
	if b in ["plains", "urban", "forest"] and roll < (0.55 if b == "plains" else 0.3):
		var c := Vector3(32.0 + rng.randf_range(-12, 12), h + 1.2, 32.0 + rng.randf_range(-12, 12))
		node.add_child(_emitter("butterfly" if era != 4 else "firefly", c, pf))
	if b in ["forest", "swamp"] and rng.randf() < 0.55:
		node.add_child(_emitter("leaves" if era != 4 else "spores", Vector3(32, h + 7.0, 32), pf))
	if rng.randf() < 0.1 and b != "urban":
		var fl := Flock.new()
		fl.setup(era, rng)
		fl.position = Vector3(32, h + rng.randf_range(16.0, 24.0), 32)
		node.add_child(fl)
	# dust drifting over main roads in dry places
	if era in [0, 2] or b == "sand":
		var net: RoadNet = gen.net
		var segs = net.coarse.get(k)
		if segs != null and rng.randf() < 0.4:
			for si in segs:
				if net.s_type[si] != RoadNet.MAIN or net.s_flag[si] != RoadNet.FLAG_ROAD:
					continue
				var m: Vector2 = (net.sa[si] + net.sb[si]) * 0.5
				if ChunkStreamer.key_of(m) != k:
					continue
				var e := _emitter("dust", Vector3(m.x - k.x * 64.0, gen.height(m.x, m.y) + 0.3, m.y - k.y * 64.0), pf)
				var d: Vector2 = net.sb[si] - net.sa[si]
				e.rotation.y = atan2(d.x, d.y)
				node.add_child(e)
				break

static func smoke(parent: Node3D, local: Vector3, pf: float = 0.7, scl: float = 1.0) -> GPUParticles3D:
	var e := _emitter("smoke", local, pf)
	e.scale = Vector3.ONE * scl
	parent.add_child(e)
	return e

static func sparks(parent: Node3D, local: Vector3, pf: float = 0.7) -> GPUParticles3D:
	var e := _emitter("sparks", local, pf)
	parent.add_child(e)
	return e

static func _emitter(kind: String, pos: Vector3, pf: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Amb_" + kind
	p.position = pos
	var cfg: Dictionary = _config(kind)
	p.amount = maxi(1, int(round(float(cfg.amount) * pf)))
	p.lifetime = cfg.life
	p.preprocess = cfg.life
	p.process_material = cfg.pm
	p.draw_pass_1 = cfg.mesh
	p.visibility_aabb = cfg.aabb
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_range_end = cfg.get("range", 70.0)
	return p

static func _config(kind: String) -> Dictionary:
	if _mats.has(kind):
		return _mats[kind]
	var pm := ParticleProcessMaterial.new()
	var amount := 8
	var life := 6.0
	var size := 0.15
	var col := Color(1, 1, 1)
	var emissive := false
	var aabb := AABB(Vector3(-16, -4, -16), Vector3(32, 10, 32))
	var grad := Gradient.new()
	match kind:
		"butterfly", "firefly":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(12, 0.8, 12)
			pm.direction = Vector3(1, 0.2, 0)
			pm.spread = 180.0
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 1.1
			pm.gravity = Vector3(0, 0.03, 0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 2.5
			pm.turbulence_noise_scale = 3.0
			pm.turbulence_influence_min = 0.25
			pm.turbulence_influence_max = 0.45
			amount = 7
			life = 9.0
			size = 0.14 if kind == "butterfly" else 0.09
			grad.colors = PackedColorArray([Color(1, 0.95, 0.4), Color(1, 1, 1), Color(0.95, 0.5, 0.25), Color(0.6, 0.75, 1.0)]) if kind == "butterfly" else PackedColorArray([Color(0.4, 1.0, 0.8), Color(0.8, 0.5, 1.0)])
			grad.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0]) if kind == "butterfly" else PackedFloat32Array([0.0, 1.0])
			var gt := GradientTexture1D.new()
			gt.gradient = grad
			pm.color_initial_ramp = gt
			emissive = kind == "firefly"
		"leaves", "spores":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(14, 2.5, 14)
			pm.direction = Vector3(0.3, -1, 0.1)
			pm.spread = 30.0
			pm.initial_velocity_min = 0.2
			pm.initial_velocity_max = 0.5
			pm.gravity = Vector3(0.35, -0.45, 0.15)
			pm.angular_velocity_min = -90.0
			pm.angular_velocity_max = 90.0
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 1.2
			pm.turbulence_influence_min = 0.1
			pm.turbulence_influence_max = 0.2
			amount = 12
			life = 12.0
			size = 0.13
			grad.colors = PackedColorArray([Color(0.75, 0.55, 0.15), Color(0.55, 0.65, 0.2), Color(0.8, 0.35, 0.12)]) if kind == "leaves" else PackedColorArray([Color(0.5, 1.0, 0.9), Color(0.9, 0.6, 1.0)])
			grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0]) if kind == "leaves" else PackedFloat32Array([0.0, 1.0])
			var gt2 := GradientTexture1D.new()
			gt2.gradient = grad
			pm.color_initial_ramp = gt2
			emissive = kind == "spores"
			aabb = AABB(Vector3(-18, -10, -18), Vector3(36, 14, 36))
		"dust":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3(1.8, 0.2, 9.0)
			pm.direction = Vector3(1, 0.4, 0)
			pm.spread = 60.0
			pm.initial_velocity_min = 0.3
			pm.initial_velocity_max = 0.8
			pm.gravity = Vector3(0.2, 0.05, 0)
			pm.scale_min = 0.8
			pm.scale_max = 1.6
			amount = 5
			life = 4.0
			size = 1.1
			grad.colors = PackedColorArray([Color(0.75, 0.65, 0.48, 0.0), Color(0.75, 0.65, 0.48, 0.28), Color(0.75, 0.65, 0.48, 0.0)])
			grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
			var gt3 := GradientTexture1D.new()
			gt3.gradient = grad
			pm.color_ramp = gt3
			aabb = AABB(Vector3(-6, -1, -12), Vector3(12, 5, 24))
		"smoke":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.15
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 12.0
			pm.initial_velocity_min = 0.6
			pm.initial_velocity_max = 1.0
			pm.gravity = Vector3(0.25, 0.2, 0.08)
			pm.scale_min = 0.6
			pm.scale_max = 1.0
			var sc := Curve.new()
			sc.add_point(Vector2(0, 0.35))
			sc.add_point(Vector2(1, 1.6))
			var sct := CurveTexture.new()
			sct.curve = sc
			pm.scale_curve = sct
			amount = 9
			life = 4.5
			size = 0.9
			grad.colors = PackedColorArray([Color(0.55, 0.55, 0.55, 0.0), Color(0.5, 0.5, 0.5, 0.42), Color(0.6, 0.6, 0.6, 0.0)])
			grad.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
			var gt4 := GradientTexture1D.new()
			gt4.gradient = grad
			pm.color_ramp = gt4
			aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 9, 8))
		"sparks":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.25
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 25.0
			pm.initial_velocity_min = 1.2
			pm.initial_velocity_max = 2.6
			pm.gravity = Vector3(0, -1.2, 0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 1.5
			pm.turbulence_influence_min = 0.1
			pm.turbulence_influence_max = 0.25
			amount = 12
			life = 1.3
			size = 0.05
			grad.colors = PackedColorArray([Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.45, 0.1, 1.0), Color(0.8, 0.2, 0.05, 0.0)])
			grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			var gt5 := GradientTexture1D.new()
			gt5.gradient = grad
			pm.color_ramp = gt5
			emissive = true
			aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = col
	if emissive:
		mat.albedo_color = Color(1.6, 1.6, 1.6)
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size * (0.7 if kind == "butterfly" else 1.0))
	qm.material = mat
	var cfg := {"pm": pm, "mesh": qm, "amount": amount, "life": life, "aabb": aabb}
	_mats[kind] = cfg
	return cfg

## A few birds circling high above; wings flap in the vertex shader.
class Flock:
	extends MultiMeshInstance3D
	const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 col : source_color = vec3(0.08, 0.08, 0.1);
void vertex() {
	float ph = float(INSTANCE_ID) * 1.7;
	VERTEX.y += sin(TIME * 9.0 + ph) * abs(VERTEX.x) * 0.7;
}
void fragment() { ALBEDO = col; }
"""
	static var _mesh: ArrayMesh
	var speed := 0.25

	func setup(era: int, rng: RandomNumberGenerator) -> void:
		if _mesh == null:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for sx in [-1.0, 1.0]:
				st.add_vertex(Vector3(0, 0, 0.12))
				st.add_vertex(Vector3(sx * 0.6, 0.05, -0.05))
				st.add_vertex(Vector3(0, 0, -0.18))
			_mesh = st.commit()
			var sh := Shader.new()
			sh.code = SHADER
			var m := ShaderMaterial.new()
			m.shader = sh
			_mesh.surface_set_material(0, m)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh
		var n := rng.randi_range(4, 8)
		mm.instance_count = n
		var rad := rng.randf_range(10.0, 18.0)
		for i in n:
			var a := float(i) / n * 0.9 + rng.randf() * 0.15
			var p := Vector3(cos(a) * rad, rng.randf_range(-1.5, 1.5), sin(a) * rad)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, -a).scaled(Vector3.ONE * (1.4 if era != 4 else 1.0)), p))
		multimesh = mm
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visibility_range_end = 120.0
		speed = rng.randf_range(0.18, 0.35) * (1.0 if rng.randf() < 0.5 else -1.0)

	func _process(delta: float) -> void:
		rotate_y(speed * delta)
