class_name MeshLib
## Shared, cached primitive meshes and materials. All procedural models are
## composed from these so mesh/material resources are reused (fewer GPU
## state changes, lower memory on mobile).

static var _mats := {}
static var _meshes := {}

static func mat(c: Color, metallic: float = 0.0, rough: float = 0.85, emission: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f|%s" % [c.to_html(true), metallic, rough, emission, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	if c.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = emission
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m

static func glow(c: Color, energy: float = 2.0) -> StandardMaterial3D:
	return mat(c, 0.0, 0.5, energy, false)

static func box(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]

static func cyl(top: float, bottom: float, h: float, seg: int = 8) -> CylinderMesh:
	var key := "cyl%.3f_%.3f_%.3f_%d" % [top, bottom, h, seg]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]

static func sphere(r: float, seg: int = 10, rings: int = 6) -> SphereMesh:
	var key := "sph%.3f_%d_%d" % [r, seg, rings]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = seg
		m.rings = rings
		_meshes[key] = m
	return _meshes[key]

static func capsule(r: float, h: float) -> CapsuleMesh:
	var key := "cap%.3f_%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 8
		m.rings = 2
		_meshes[key] = m
	return _meshes[key]

static func prism(size: Vector3) -> PrismMesh:
	var key := "prism%s" % size
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]

static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "tor%.3f_%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 12
		m.ring_segments = 6
		_meshes[key] = m
	return _meshes[key]

static func quad(size: Vector2) -> QuadMesh:
	var key := "quad%s" % size
	if not _meshes.has(key):
		var m := QuadMesh.new()
		m.size = size
		_meshes[key] = m
	return _meshes[key]

## Create a MeshInstance3D child with transform.
static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func pivot(parent: Node3D, pos: Vector3, nm: String = "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	if nm != "":
		n.name = nm
	parent.add_child(n)
	return n
