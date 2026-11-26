class_name Props
## Procedural prop meshes (merged per material for MultiMesh instancing),
## settlement centrepieces and static decor for points of interest.

static var _cache := {}

## Merges many primitive parts into one ArrayMesh with one surface per material.
class Merger:
	var tools := {}
	var order: Array = []

	func add(mesh: Mesh, mat: Material, xf: Transform3D) -> void:
		var st: SurfaceTool = tools.get(mat)
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
			order.append(mat)
		st.append_from(mesh, 0, xf)

	func part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
		var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl)
		add(mesh, mat, Transform3D(b, pos))

	func is_empty() -> bool:
		return order.is_empty()

	func commit() -> ArrayMesh:
		var am := ArrayMesh.new()
		for m in order:
			var st: SurfaceTool = tools[m]
			st.set_material(m)
			am = st.commit(am)
		return am

static func xf(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl), pos)

static func category(t: String) -> String:
	if t.begins_with("tree_"):
		return "tree"
	if t in ["rock", "crystal", "coal_pile", "boulder", "outcrop"]:
		return "rock"
	if t in FOLIAGE or t.begins_with("grass") or t in ["mushrooms", "litter", "crystal_small", "pebbles"]:
		return "detail"
	if t in ["bush", "stump", "flowers", "vineyard", "dead_bush", "log", "haystack", "holo_plant"]:
		return "small"
	return "urban"

## Foliage drawn with the wind/fade shader and per-instance colour.
const FOLIAGE := ["grass", "flowerbed", "fern", "reeds"]

## Collision footprint for a prop: {shape: "cyl"|"box", r, h, size}
static func collider(t: String) -> Dictionary:
	match category(t):
		"tree":
			return {"shape": "cyl", "r": 0.35, "h": 3.0}
		"rock":
			return {"shape": "cyl", "r": 1.0, "h": 1.6}
	match t:
		"boulder": return {"shape": "cyl", "r": 1.5, "h": 2.2}
		"outcrop": return {"shape": "cyl", "r": 1.5, "h": 3.2}
		"log": return {"shape": "box", "size": Vector3(3.2, 0.6, 0.6)}
		"ruin_wall": return {"shape": "box", "size": Vector3(3.6, 2.0, 0.7)}
		"ruin_column": return {"shape": "cyl", "r": 0.42, "h": 2.2}
		"shed": return {"shape": "box", "size": Vector3(2.6, 2.4, 2.2)}
		"haystack": return {"shape": "cyl", "r": 1.0, "h": 1.6}
		"scrap_pile": return {"shape": "cyl", "r": 1.2, "h": 1.1}
		"crate": return {"shape": "box", "size": Vector3(0.9, 0.9, 0.9)}
		"barrel": return {"shape": "cyl", "r": 0.42, "h": 1.0}
		"lamppost_oil", "streetlight", "neon_pillar", "holo_sign": return {"shape": "cyl", "r": 0.18, "h": 3.0}
		"pipe": return {"shape": "box", "size": Vector3(6.0, 1.6, 0.9)}
		"chimney": return {"shape": "cyl", "r": 0.85, "h": 8.0}
		"car_wreck": return {"shape": "box", "size": Vector3(4.0, 1.4, 1.9)}
		"barrier": return {"shape": "box", "size": Vector3(2.0, 0.9, 0.6)}
		"container": return {"shape": "box", "size": Vector3(6.0, 2.6, 2.4)}
		"energy_pylon": return {"shape": "box", "size": Vector3(1.1, 6.0, 1.1)}
	return {}

static func prop_mesh(t: String, era: int) -> ArrayMesh:
	var key := "%s|%d" % [t, era]
	if _cache.has(key):
		return _cache[key]
	if t in FOLIAGE or t.begins_with("grass:"):
		var tint := Color(0.4, 0.6, 0.3)
		if t.begins_with("grass:"):
			var gd: Dictionary = DBEras.era(era).ground
			var bn := t.get_slice(":", 1)
			tint = gd.get(bn if bn != "urban" else "plains", gd.plains)
		var fm := _foliage_mesh(t.get_slice(":", 0), era, tint)
		_cache[key] = fm
		return fm
	var m := Merger.new()
	var e: Dictionary = DBEras.era(era)
	var leaf: Color = e.ground.forest.lightened(0.05)
	var bark := MeshLib.mat(Color(0.36, 0.25, 0.15))
	var leaf_m := MeshLib.mat(leaf)
	var leaf2 := MeshLib.mat(leaf.lightened(0.15))
	var stone := MeshLib.mat(e.ground.mountain.lightened(0.1))
	match t:
		"tree_oak":
			m.part(MeshLib.cyl(0.18, 0.28, 2.4, 6), bark, Vector3(0, 1.2, 0))
			m.part(MeshLib.sphere(1.6, 8, 5), leaf_m, Vector3(0, 3.1, 0))
			m.part(MeshLib.sphere(1.15, 8, 5), leaf2, Vector3(0.8, 2.7, 0.35))
			m.part(MeshLib.sphere(1.05, 8, 5), leaf_m, Vector3(-0.7, 2.8, -0.45))
		"tree_pine":
			var pine := MeshLib.mat(leaf.darkened(0.25))
			m.part(MeshLib.cyl(0.14, 0.22, 1.8, 6), bark, Vector3(0, 0.9, 0))
			m.part(MeshLib.cyl(0.0, 1.5, 2.0, 7), pine, Vector3(0, 2.2, 0))
			m.part(MeshLib.cyl(0.0, 1.15, 1.8, 7), pine, Vector3(0, 3.3, 0))
			m.part(MeshLib.cyl(0.0, 0.75, 1.5, 7), pine, Vector3(0, 4.3, 0))
		"tree_cypress":
			m.part(MeshLib.cyl(0.12, 0.18, 1.2, 6), bark, Vector3(0, 0.6, 0))
			m.part(MeshLib.sphere(0.8, 7, 6), MeshLib.mat(leaf.darkened(0.3)), Vector3(0, 3.0, 0), Vector3.ZERO, Vector3(1.0, 3.0, 1.0))
		"tree_birch":
			m.part(MeshLib.cyl(0.11, 0.15, 3.2, 6), MeshLib.mat(Color(0.9, 0.9, 0.86)), Vector3(0, 1.6, 0))
			m.part(MeshLib.sphere(1.2, 8, 5), MeshLib.mat(leaf.lightened(0.25)), Vector3(0, 3.6, 0), Vector3.ZERO, Vector3(1.0, 1.4, 1.0))
		"tree_dead":
			var db := MeshLib.mat(Color(0.3, 0.26, 0.22))
			m.part(MeshLib.cyl(0.1, 0.25, 3.4, 5), db, Vector3(0, 1.7, 0))
			m.part(MeshLib.cyl(0.04, 0.09, 1.6, 4), db, Vector3(0.5, 2.6, 0), Vector3(0, 0, -50))
			m.part(MeshLib.cyl(0.04, 0.08, 1.3, 4), db, Vector3(-0.4, 3.0, 0.2), Vector3(20, 0, 45))
			m.part(MeshLib.cyl(0.03, 0.07, 1.0, 4), db, Vector3(0.1, 3.3, -0.4), Vector3(-40, 0, 0))
		"tree_synthetic":
			m.part(MeshLib.cyl(0.12, 0.2, 3.0, 6), MeshLib.mat(Color(0.5, 0.52, 0.58), 0.8, 0.3), Vector3(0, 1.5, 0))
			m.part(MeshLib.sphere(1.1, 8, 5), MeshLib.mat(Color(0.2, 0.9, 0.85), 0.0, 0.4, 1.4), Vector3(0, 3.5, 0), Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
			m.part(MeshLib.torus(1.25, 1.35), MeshLib.mat(Color(0.9, 0.3, 0.9), 0.0, 0.4, 2.5), Vector3(0, 3.5, 0))
		"rock":
			m.part(MeshLib.sphere(1.0, 6, 4), stone, Vector3(0, 0.25, 0), Vector3(0, 0, 0), Vector3(1.3, 0.75, 1.1))
			m.part(MeshLib.sphere(0.55, 6, 4), MeshLib.mat(e.ground.mountain.darkened(0.05)), Vector3(0.75, 0.2, 0.3), Vector3(0, 30, 0), Vector3(1.0, 0.8, 1.0))
		"bush":
			m.part(MeshLib.sphere(0.7, 7, 4), leaf_m, Vector3(0, 0.45, 0), Vector3.ZERO, Vector3(1.2, 0.8, 1.0))
			m.part(MeshLib.sphere(0.5, 7, 4), leaf2, Vector3(0.5, 0.35, 0.2))
		"stump":
			m.part(MeshLib.cyl(0.3, 0.38, 0.5, 7), bark, Vector3(0, 0.25, 0))
			m.part(MeshLib.cyl(0.29, 0.29, 0.02, 7), MeshLib.mat(Color(0.75, 0.62, 0.4)), Vector3(0, 0.51, 0))
		"flowers":
			var grass := MeshLib.mat(e.ground.plains.lightened(0.1))
			m.part(MeshLib.prism(Vector3(0.5, 0.35, 0.05)), grass, Vector3(0, 0.17, 0))
			m.part(MeshLib.prism(Vector3(0.5, 0.3, 0.05)), grass, Vector3(0.2, 0.15, 0.1), Vector3(0, 70, 0))
			var cols := [Color(0.95, 0.3, 0.3), Color(1.0, 0.9, 0.3), Color(0.95, 0.95, 1.0), Color(0.7, 0.4, 0.95)]
			for i in 5:
				var a := i * 1.3
				m.part(MeshLib.box(Vector3(0.09, 0.09, 0.09)), MeshLib.mat(cols[i % cols.size()]), Vector3(cos(a) * 0.3, 0.32, sin(a) * 0.3))
		"crate":
			m.part(MeshLib.box(Vector3(0.9, 0.9, 0.9)), MeshLib.mat(Color(0.55, 0.4, 0.22)), Vector3(0, 0.45, 0))
			m.part(MeshLib.box(Vector3(0.95, 0.1, 0.95)), MeshLib.mat(Color(0.4, 0.28, 0.15)), Vector3(0, 0.85, 0))
		"barrel":
			m.part(MeshLib.cyl(0.38, 0.42, 1.0, 9), MeshLib.mat(Color(0.5, 0.33, 0.18)), Vector3(0, 0.5, 0))
			m.part(MeshLib.torus(0.38, 0.44), MeshLib.mat(Color(0.3, 0.3, 0.3), 0.7, 0.4), Vector3(0, 0.25, 0))
			m.part(MeshLib.torus(0.38, 0.44), MeshLib.mat(Color(0.3, 0.3, 0.3), 0.7, 0.4), Vector3(0, 0.75, 0))
		"lamppost_oil", "streetlight":
			var pole := MeshLib.mat(Color(0.15, 0.15, 0.17), 0.6, 0.5)
			var hgt := 3.0 if t == "lamppost_oil" else 5.0
			m.part(MeshLib.cyl(0.06, 0.09, hgt, 6), pole, Vector3(0, hgt * 0.5, 0))
			if t == "streetlight":
				m.part(MeshLib.box(Vector3(1.2, 0.08, 0.1)), pole, Vector3(0.55, hgt, 0))
				m.part(MeshLib.box(Vector3(0.4, 0.12, 0.25)), MeshLib.mat(Color(1.0, 0.95, 0.8), 0.0, 0.5, 3.0), Vector3(1.1, hgt - 0.08, 0))
			else:
				m.part(MeshLib.box(Vector3(0.3, 0.4, 0.3)), MeshLib.mat(Color(1.0, 0.8, 0.45), 0.0, 0.5, 2.5), Vector3(0, hgt + 0.2, 0))
		"vineyard":
			var post := MeshLib.mat(Color(0.4, 0.3, 0.2))
			var vine := MeshLib.mat(leaf.lightened(0.1))
			for i in 3:
				m.part(MeshLib.cyl(0.04, 0.04, 1.3, 4), post, Vector3(-1.6 + i * 1.6, 0.65, 0))
			m.part(MeshLib.box(Vector3(3.6, 0.6, 0.45)), vine, Vector3(0, 0.9, 0))
			for i in 4:
				m.part(MeshLib.sphere(0.08, 5, 3), MeshLib.mat(Color(0.45, 0.15, 0.4)), Vector3(-1.2 + i * 0.8, 0.6, 0.25))
		"pipe":
			var rust := MeshLib.mat(Color(0.5, 0.3, 0.18), 0.6, 0.6)
			m.part(MeshLib.cyl(0.35, 0.35, 6.0, 10), rust, Vector3(0, 1.1, 0), Vector3(0, 0, 90))
			for sx in [-2.2, 2.2]:
				m.part(MeshLib.box(Vector3(0.2, 1.1, 0.7)), MeshLib.mat(Color(0.25, 0.25, 0.27), 0.6, 0.5), Vector3(sx, 0.55, 0))
		"chimney":
			m.part(MeshLib.cyl(0.6, 0.85, 8.0, 10), MeshLib.mat(Color(0.5, 0.25, 0.18)), Vector3(0, 4.0, 0))
			m.part(MeshLib.cyl(0.7, 0.7, 0.4, 10), MeshLib.mat(Color(0.2, 0.18, 0.17)), Vector3(0, 8.0, 0))
		"rails":
			var steel := MeshLib.mat(Color(0.45, 0.42, 0.4), 0.8, 0.4)
			var sleeper := MeshLib.mat(Color(0.3, 0.22, 0.15))
			for i in 9:
				m.part(MeshLib.box(Vector3(2.0, 0.12, 0.3)), sleeper, Vector3(0, 0.06, -4.0 + i))
			for sx in [-0.7, 0.7]:
				m.part(MeshLib.box(Vector3(0.1, 0.14, 8.6)), steel, Vector3(sx, 0.18, 0))
		"coal_pile":
			m.part(MeshLib.cyl(0.0, 1.6, 1.4, 7), MeshLib.mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0.7, 0))
		"car_wreck":
			var paint := MeshLib.mat(Color(0.45, 0.2, 0.15), 0.4, 0.7)
			m.part(MeshLib.box(Vector3(4.0, 0.8, 1.8)), paint, Vector3(0, 0.75, 0))
			m.part(MeshLib.box(Vector3(2.0, 0.65, 1.6)), MeshLib.mat(Color(0.2, 0.25, 0.3), 0.3, 0.3), Vector3(-0.3, 1.45, 0))
			for p in [Vector3(1.3, 0.38, 0.85), Vector3(-1.3, 0.38, 0.85), Vector3(1.3, 0.38, -0.85), Vector3(-1.3, 0.38, -0.85)]:
				m.part(MeshLib.cyl(0.38, 0.38, 0.25, 8), MeshLib.mat(Color(0.08, 0.08, 0.08)), p, Vector3(90, 0, 0))
		"barrier":
			m.part(MeshLib.box(Vector3(2.0, 0.85, 0.55)), MeshLib.mat(Color(0.75, 0.74, 0.7)), Vector3(0, 0.42, 0))
			m.part(MeshLib.box(Vector3(2.02, 0.12, 0.57)), MeshLib.mat(Color(0.9, 0.5, 0.1)), Vector3(0, 0.6, 0))
		"container":
			var cc: Color = [Color(0.65, 0.15, 0.12), Color(0.15, 0.35, 0.6), Color(0.2, 0.5, 0.25)][era % 3]
			m.part(MeshLib.box(Vector3(6.0, 2.6, 2.4)), MeshLib.mat(cc, 0.5, 0.6), Vector3(0, 1.3, 0))
			for i in 7:
				m.part(MeshLib.box(Vector3(0.08, 2.4, 2.45)), MeshLib.mat(cc.darkened(0.25), 0.5, 0.6), Vector3(-2.7 + i * 0.9, 1.3, 0))
		"crystal":
			var cm := MeshLib.mat(Color(0.6, 0.35, 1.0), 0.0, 0.2, 1.8)
			m.part(MeshLib.prism(Vector3(0.5, 2.2, 0.5)), cm, Vector3(0, 1.1, 0))
			m.part(MeshLib.prism(Vector3(0.4, 1.4, 0.4)), MeshLib.mat(Color(0.3, 0.9, 1.0), 0.0, 0.2, 1.8), Vector3(0.45, 0.6, 0.2), Vector3(0, 0, -25))
			m.part(MeshLib.prism(Vector3(0.35, 1.1, 0.35)), cm, Vector3(-0.4, 0.5, -0.1), Vector3(15, 0, 30))
		"neon_pillar":
			m.part(MeshLib.box(Vector3(0.35, 4.2, 0.35)), MeshLib.mat(Color(0.12, 0.12, 0.16), 0.6, 0.4), Vector3(0, 2.1, 0))
			m.part(MeshLib.box(Vector3(0.08, 3.6, 0.38)), MeshLib.mat(Color(1.0, 0.2, 0.75), 0.0, 0.4, 3.0), Vector3(0.15, 2.1, 0))
		"holo_sign":
			m.part(MeshLib.cyl(0.06, 0.08, 3.2, 6), MeshLib.mat(Color(0.2, 0.2, 0.24), 0.6, 0.4), Vector3(0, 1.6, 0))
			m.part(MeshLib.box(Vector3(1.8, 1.0, 0.04)), MeshLib.mat(Color(0.2, 0.9, 1.0, 0.55), 0.0, 0.3, 2.5), Vector3(0, 3.4, 0))
		"energy_pylon":
			m.part(MeshLib.box(Vector3(1.0, 6.0, 1.0)), MeshLib.mat(Color(0.25, 0.27, 0.32), 0.7, 0.35), Vector3(0, 3.0, 0))
			m.part(MeshLib.torus(0.9, 1.1), MeshLib.mat(Color(0.3, 0.8, 1.0), 0.0, 0.3, 3.0), Vector3(0, 4.5, 0))
			m.part(MeshLib.torus(0.9, 1.1), MeshLib.mat(Color(0.3, 0.8, 1.0), 0.0, 0.3, 3.0), Vector3(0, 2.5, 0))
		"log":
			m.part(MeshLib.cyl(0.26, 0.3, 3.2, 7), bark, Vector3(0, 0.27, 0), Vector3(0, 0, 90))
			m.part(MeshLib.cyl(0.25, 0.25, 0.02, 7), MeshLib.mat(Color(0.7, 0.56, 0.36)), Vector3(1.61, 0.27, 0), Vector3(0, 0, 90))
			m.part(MeshLib.cyl(0.04, 0.08, 0.9, 4), bark, Vector3(0.4, 0.55, 0.15), Vector3(30, 0, -20))
			m.part(MeshLib.sphere(0.22, 5, 3), MeshLib.mat(leaf.darkened(0.2)), Vector3(-0.8, 0.5, 0.1), Vector3.ZERO, Vector3(1.6, 0.5, 1.0))
		"boulder":
			m.part(MeshLib.sphere(1.4, 7, 5), stone, Vector3(0, 0.6, 0), Vector3(0, 0, 8), Vector3(1.25, 0.85, 1.05))
			m.part(MeshLib.sphere(0.7, 6, 4), MeshLib.mat(e.ground.mountain.darkened(0.08)), Vector3(1.2, 0.3, 0.6), Vector3(0, 40, 0))
			m.part(MeshLib.sphere(0.5, 6, 4), MeshLib.mat(leaf.darkened(0.35)), Vector3(-0.3, 1.45, 0.2), Vector3.ZERO, Vector3(1.4, 0.25, 1.2))
		"outcrop":
			var st2 := MeshLib.mat(e.ground.mountain.darkened(0.05))
			m.part(MeshLib.box(Vector3(1.4, 3.0, 1.2)), stone, Vector3(0, 1.3, 0), Vector3(6, 20, 9))
			m.part(MeshLib.box(Vector3(1.1, 2.0, 1.0)), st2, Vector3(1.0, 0.8, 0.4), Vector3(-8, 50, -12))
			m.part(MeshLib.box(Vector3(0.9, 1.3, 0.9)), stone, Vector3(-0.9, 0.5, -0.5), Vector3(10, 10, 14))
		"ruin_wall":
			var rs := MeshLib.mat(Color(0.58, 0.55, 0.5))
			m.part(MeshLib.box(Vector3(3.6, 1.0, 0.6)), rs, Vector3(0, 0.5, 0))
			m.part(MeshLib.box(Vector3(2.2, 0.8, 0.6)), rs, Vector3(-0.6, 1.4, 0))
			m.part(MeshLib.box(Vector3(0.8, 0.6, 0.6)), rs, Vector3(-1.2, 2.1, 0))
			m.part(MeshLib.box(Vector3(0.7, 0.4, 0.5)), rs, Vector3(1.4, 0.2, 0.9), Vector3(0, 30, 12))
			m.part(MeshLib.box(Vector3(1.6, 0.06, 0.62)), MeshLib.mat(leaf.darkened(0.15)), Vector3(-0.6, 1.82, 0))
		"ruin_column":
			var marble := MeshLib.mat(Color(0.82, 0.8, 0.74))
			m.part(MeshLib.box(Vector3(1.0, 0.3, 1.0)), marble, Vector3(0, 0.15, 0))
			m.part(MeshLib.cyl(0.32, 0.36, 1.9, 10), marble, Vector3(0, 1.25, 0))
			m.part(MeshLib.cyl(0.32, 0.32, 1.3, 10), marble, Vector3(1.3, 0.3, 0.4), Vector3(0, 30, 90))
		"fence_broken":
			var fw := MeshLib.mat(Color(0.42, 0.3, 0.18) if era < 3 else Color(0.5, 0.5, 0.52), 0.0 if era < 3 else 0.6, 0.7)
			for i in 3:
				m.part(MeshLib.box(Vector3(0.12, 1.1, 0.12)), fw, Vector3(-1.5 + i * 1.5, 0.55, 0), Vector3(0, 0, 0 if i != 2 else 18))
			m.part(MeshLib.box(Vector3(1.6, 0.08, 0.06)), fw, Vector3(-0.75, 0.8, 0))
			m.part(MeshLib.box(Vector3(1.6, 0.08, 0.06)), fw, Vector3(-0.75, 0.4, 0))
			m.part(MeshLib.box(Vector3(1.6, 0.08, 0.06)), fw, Vector3(0.8, 0.25, 0.2), Vector3(0, 15, 25))
		"shed":
			var sw := MeshLib.mat(Color(0.48, 0.36, 0.22) if era < 3 else Color(0.55, 0.56, 0.58), 0.0 if era < 2 else 0.4, 0.7)
			m.part(MeshLib.box(Vector3(2.5, 2.0, 2.1)), sw, Vector3(0, 1.0, 0))
			m.part(MeshLib.box(Vector3(2.9, 0.12, 2.6)), MeshLib.mat(Color(0.35, 0.25, 0.18) if era < 2 else Color(0.4, 0.3, 0.25), 0.3 if era >= 2 else 0.0, 0.7), Vector3(0, 2.25, 0), Vector3(12, 0, 0))
			m.part(MeshLib.box(Vector3(0.8, 1.6, 0.05)), MeshLib.mat(Color(0.25, 0.18, 0.12)), Vector3(0.4, 0.8, 1.06))
		"haystack":
			var hay := MeshLib.mat(Color(0.85, 0.72, 0.36))
			m.part(MeshLib.cyl(0.4, 1.0, 1.3, 9), hay, Vector3(0, 0.65, 0))
			m.part(MeshLib.sphere(0.45, 7, 4), hay, Vector3(0, 1.3, 0))
		"scrap_pile":
			var rust2 := MeshLib.mat(Color(0.45, 0.28, 0.18), 0.6, 0.7)
			var dark2 := MeshLib.mat(Color(0.22, 0.22, 0.24), 0.7, 0.5)
			m.part(MeshLib.cyl(0.0, 1.3, 0.9, 7), MeshLib.mat(Color(0.25, 0.22, 0.2)), Vector3(0, 0.45, 0))
			m.part(MeshLib.cyl(0.25, 0.25, 1.6, 8), rust2, Vector3(0.2, 0.8, 0.1), Vector3(70, 20, 0))
			m.part(MeshLib.box(Vector3(0.9, 0.5, 0.6)), dark2, Vector3(-0.5, 0.9, -0.2), Vector3(20, 35, 10))
			m.part(MeshLib.torus(0.25, 0.4), dark2, Vector3(0.6, 0.6, -0.5), Vector3(60, 0, 0))
		"litter":
			var pc := [Color(0.9, 0.88, 0.8), Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.7), Color(0.6, 0.6, 0.62)]
			for i in 5:
				var a2 := i * 1.9
				m.part(MeshLib.box(Vector3(0.22, 0.02, 0.3) if i % 2 == 0 else Vector3(0.07, 0.12, 0.07)), MeshLib.mat(pc[i % 4], 0.3 if i % 2 == 1 else 0.0, 0.7), Vector3(cos(a2) * 0.5, 0.03, sin(a2) * 0.4), Vector3(0, a2 * 40.0, 0 if i % 2 == 0 else 90))
		"crystal_small":
			var cg := MeshLib.mat(Color(0.35, 0.95, 1.0), 0.0, 0.2, 1.6)
			m.part(MeshLib.prism(Vector3(0.18, 0.7, 0.18)), cg, Vector3(0, 0.35, 0))
			m.part(MeshLib.prism(Vector3(0.14, 0.45, 0.14)), MeshLib.mat(Color(0.8, 0.4, 1.0), 0.0, 0.2, 1.6), Vector3(0.18, 0.2, 0.08), Vector3(0, 0, -30))
			m.part(MeshLib.prism(Vector3(0.12, 0.35, 0.12)), cg, Vector3(-0.15, 0.16, -0.05), Vector3(20, 0, 25))
		"holo_plant":
			m.part(MeshLib.cyl(0.03, 0.05, 1.2, 5), MeshLib.mat(Color(0.3, 0.32, 0.38), 0.7, 0.3), Vector3(0, 0.6, 0))
			for i in 4:
				var a3 := i * PI * 0.5 + 0.4
				m.part(MeshLib.box(Vector3(0.5, 0.03, 0.18)), MeshLib.mat(Color(0.3, 1.0, 0.7, 0.7), 0.0, 0.3, 2.0), Vector3(cos(a3) * 0.25, 0.9 + i * 0.12, sin(a3) * 0.25), Vector3(0, -a3 * 57.3, 25))
		"dead_bush":
			var tw := MeshLib.mat(Color(0.42, 0.34, 0.24))
			for i in 5:
				var a4 := i * 1.26
				m.part(MeshLib.cyl(0.01, 0.03, 0.8, 3), tw, Vector3(cos(a4) * 0.15, 0.35, sin(a4) * 0.15), Vector3(cos(a4) * 35.0, 0, sin(a4) * 35.0))
		"mushrooms":
			var cap := MeshLib.mat([Color(0.75, 0.25, 0.15), Color(0.8, 0.7, 0.55), Color(0.55, 0.4, 0.3), Color(0.5, 0.75, 0.8), Color(0.4, 0.9, 0.9)][era])
			var stem := MeshLib.mat(Color(0.9, 0.88, 0.8))
			for i in 3:
				var a5 := i * 2.1
				var p5 := Vector3(cos(a5) * 0.18, 0, sin(a5) * 0.18)
				m.part(MeshLib.cyl(0.025, 0.03, 0.14, 5), stem, p5 + Vector3(0, 0.07, 0))
				m.part(MeshLib.sphere(0.07, 6, 3), cap, p5 + Vector3(0, 0.15, 0), Vector3.ZERO, Vector3(1.0, 0.55, 1.0))
		"pebbles":
			for i in 4:
				var a6 := i * 1.7
				m.part(MeshLib.sphere(0.12, 5, 3), stone, Vector3(cos(a6) * 0.3, 0.04, sin(a6) * 0.25), Vector3.ZERO, Vector3(1.3, 0.6, 1.0))
		_:
			m.part(MeshLib.box(Vector3(0.6, 0.6, 0.6)), stone, Vector3(0, 0.3, 0))
	var mesh := m.commit()
	_cache[key] = mesh
	return mesh

# ---------------------------------------------------------------- settlement decor
static func centerpiece(era: int) -> Node3D:
	var n := Node3D.new()
	n.name = "Centerpiece"
	var e: Dictionary = DBEras.era(era)
	var stone := MeshLib.mat(Color(0.6, 0.58, 0.55))
	var water := MeshLib.mat(Color(e.water.r, e.water.g, e.water.b, 0.85), 0.0, 0.2)
	match era:
		0:
			MeshLib.part(n, MeshLib.cyl(1.2, 1.3, 0.9, 12), stone, Vector3(0, 0.45, 0))
			MeshLib.part(n, MeshLib.cyl(1.0, 1.0, 0.05, 12), water, Vector3(0, 0.8, 0))
			for sx in [-1.0, 1.0]:
				MeshLib.part(n, MeshLib.box(Vector3(0.15, 2.0, 0.15)), MeshLib.mat(Color(0.4, 0.28, 0.16)), Vector3(sx, 1.4, 0))
			MeshLib.part(n, MeshLib.prism(Vector3(2.6, 0.8, 1.6)), MeshLib.mat(Color(0.45, 0.25, 0.18)), Vector3(0, 2.7, 0))
		1:
			MeshLib.part(n, MeshLib.cyl(2.4, 2.6, 0.6, 16), stone, Vector3(0, 0.3, 0))
			MeshLib.part(n, MeshLib.cyl(2.2, 2.2, 0.05, 16), water, Vector3(0, 0.55, 0))
			MeshLib.part(n, MeshLib.cyl(0.35, 0.5, 2.0, 10), stone, Vector3(0, 1.4, 0))
			MeshLib.part(n, MeshLib.sphere(0.6, 10, 6), MeshLib.mat(Color(0.85, 0.75, 0.45), 0.8, 0.35), Vector3(0, 2.7, 0))
		2:
			MeshLib.part(n, MeshLib.box(Vector3(2.0, 1.2, 2.0)), stone, Vector3(0, 0.6, 0))
			MeshLib.part(n, MeshLib.cyl(0.3, 0.3, 2.8, 10), MeshLib.mat(Color(0.55, 0.4, 0.25), 0.8, 0.4), Vector3(0, 2.6, 0))
			MeshLib.part(n, MeshLib.cyl(0.9, 0.9, 0.3, 12), MeshLib.mat(Color(0.2, 0.2, 0.2), 0.6, 0.4), Vector3(0, 4.0, 0))
			MeshLib.part(n, MeshLib.box(Vector3(1.0, 0.8, 0.1)), MeshLib.mat(Color(0.95, 0.9, 0.75), 0.0, 0.5, 1.0), Vector3(0, 4.0, 0.45))
		3:
			MeshLib.part(n, MeshLib.box(Vector3(3.0, 0.5, 3.0)), MeshLib.mat(Color(0.7, 0.7, 0.72)), Vector3(0, 0.25, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.6, 4.5, 0.6)), MeshLib.mat(Color(0.55, 0.57, 0.6), 0.7, 0.3), Vector3(0, 2.7, 0))
			MeshLib.part(n, MeshLib.box(Vector3(2.2, 1.2, 0.08)), MeshLib.mat(Color(0.3, 0.6, 0.9), 0.0, 0.4, 1.5), Vector3(0, 4.0, 0.35))
		_:
			MeshLib.part(n, MeshLib.cyl(2.0, 2.2, 0.4, 6), MeshLib.mat(Color(0.2, 0.2, 0.26), 0.7, 0.3), Vector3(0, 0.2, 0))
			MeshLib.part(n, MeshLib.prism(Vector3(0.9, 5.0, 0.9)), MeshLib.mat(Color(0.35, 0.9, 1.0), 0.0, 0.2, 2.2), Vector3(0, 2.9, 0))
			MeshLib.part(n, MeshLib.torus(1.5, 1.65), MeshLib.mat(Color(1.0, 0.3, 0.8), 0.0, 0.3, 3.0), Vector3(0, 1.5, 0))
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 1.3 if era != 1 else 2.5
	sh.height = 3.0
	cs.shape = sh
	cs.position.y = 1.5
	sb.add_child(cs)
	n.add_child(sb)
	return n

# ---------------------------------------------------------------- POI decor
## Static, non-interactive structure for a point of interest. Gameplay logic
## (capture, portals, altars, bosses...) is attached separately by the world.
static func poi_decor(poi: Dictionary, era: int) -> Node3D:
	var n := Node3D.new()
	n.name = "Decor_" + str(poi.type)
	var e: Dictionary = DBEras.era(era)
	var stone := MeshLib.mat(Color(0.55, 0.54, 0.52))
	var dark := MeshLib.mat(Color(0.18, 0.17, 0.18))
	var wood := MeshLib.mat(Color(0.45, 0.31, 0.18))
	var metal := MeshLib.mat(Color(0.45, 0.47, 0.5), 0.75, 0.35)
	var glow_c := Color(0.4, 1.0, 0.85)
	var cols: Array = []  # [shape, pos, size/r, h]
	match poi.type:
		"lair":
			MeshLib.part(n, MeshLib.cyl(16.0, 16.5, 0.15, 32), MeshLib.mat(e.ground.mountain.darkened(0.25)), Vector3(0, 0.05, 0))
			for i in 8:
				var a := i * TAU / 8.0
				var p := Vector3(cos(a), 0, sin(a)) * 17.5
				if i == 2:
					continue
				MeshLib.part(n, MeshLib.box(Vector3(1.4, 4.5, 1.4)), dark, p + Vector3(0, 2.25, 0), Vector3(0, -rad_to_deg(a), 0))
				MeshLib.part(n, MeshLib.cyl(0.4, 0.5, 0.5, 8), MeshLib.mat(Color(1.0, 0.45, 0.15), 0.0, 0.5, 2.5), p + Vector3(0, 4.7, 0))
				cols.append(["box", p + Vector3(0, 2.25, 0), Vector3(1.4, 4.5, 1.4)])
		"trial":
			MeshLib.part(n, MeshLib.cyl(14.0, 14.5, 0.3, 32), MeshLib.mat(Color(0.75, 0.7, 0.6)), Vector3(0, 0.15, 0))
			MeshLib.part(n, MeshLib.torus(12.5, 13.0), MeshLib.mat(Color(1.0, 0.85, 0.3), 0.0, 0.4, 2.0), Vector3(0, 0.32, 0), Vector3.ZERO, Vector3(1, 0.2, 1))
			for i in 4:
				var a2 := i * TAU / 4.0 + PI / 4.0
				var p2 := Vector3(cos(a2), 0, sin(a2)) * 15.5
				MeshLib.part(n, MeshLib.prism(Vector3(1.6, 7.0, 1.6)), MeshLib.mat(Color(0.85, 0.8, 0.65)), p2 + Vector3(0, 3.5, 0))
				MeshLib.part(n, MeshLib.sphere(0.4, 8, 5), MeshLib.mat(Color(1.0, 0.85, 0.3), 0.0, 0.4, 3.0), p2 + Vector3(0, 7.3, 0))
				cols.append(["cyl", p2 + Vector3(0, 3.5, 0), 0.8, 7.0])
		"rift":
			MeshLib.part(n, MeshLib.cyl(4.5, 4.8, 0.12, 20), MeshLib.mat(Color(0.25, 0.22, 0.3)), Vector3(0, 0.06, 0))
			for i in 6:
				var a3 := i * TAU / 6.0
				MeshLib.part(n, MeshLib.box(Vector3(0.5, 1.4, 0.5)), stone, Vector3(cos(a3) * 4.2, 0.7, sin(a3) * 4.2), Vector3(0, 0, 12))
				MeshLib.part(n, MeshLib.box(Vector3(0.3, 0.3, 0.05)), MeshLib.mat(glow_c, 0.0, 0.4, 2.0), Vector3(cos(a3) * 4.2, 1.0, sin(a3) * 4.2 + 0.26))
		"cp":
			_cp_decor(n, str(poi.data.get("cp_type", "watchtower")), era, cols)
		"camp":
			for i in 3:
				var a4 := i * TAU / 3.0 + 0.6
				var tp := Vector3(cos(a4), 0, sin(a4)) * 6.0
				MeshLib.part(n, MeshLib.prism(Vector3(3.2, 2.2, 3.4)), MeshLib.mat([Color(0.55, 0.45, 0.3), Color(0.6, 0.2, 0.2), Color(0.35, 0.35, 0.3), Color(0.3, 0.35, 0.25), Color(0.2, 0.2, 0.25)][era]), tp + Vector3(0, 1.1, 0), Vector3(0, rad_to_deg(-a4), 0))
				cols.append(["box", tp + Vector3(0, 1.0, 0), Vector3(2.6, 2.0, 2.6)])
			MeshLib.part(n, MeshLib.cyl(0.8, 0.9, 0.25, 10), stone, Vector3(0, 0.12, 0))
			MeshLib.part(n, MeshLib.cyl(0.0, 0.5, 0.9, 6), MeshLib.mat(Color(1.0, 0.55, 0.15), 0.0, 0.5, 3.0), Vector3(0, 0.6, 0), Vector3.ZERO, Vector3.ONE, false)
			var fl := OmniLight3D.new()
			fl.light_color = Color(1.0, 0.6, 0.3)
			fl.light_energy = 1.4
			fl.omni_range = 9.0
			fl.position = Vector3(0, 1.2, 0)
			fl.shadow_enabled = false
			n.add_child(fl)
		"dungeon":
			MeshLib.part(n, MeshLib.box(Vector3(5.0, 0.6, 4.0)), stone, Vector3(0, 0.3, 0))
			for sx in [-1.6, 1.6]:
				MeshLib.part(n, MeshLib.box(Vector3(0.8, 3.2, 0.8)), stone, Vector3(sx, 1.6, -1.2))
				cols.append(["box", Vector3(sx, 1.6, -1.2), Vector3(0.8, 3.2, 0.8)])
			MeshLib.part(n, MeshLib.box(Vector3(4.0, 0.8, 0.9)), stone, Vector3(0, 3.4, -1.2))
			MeshLib.part(n, MeshLib.box(Vector3(2.4, 0.05, 2.0)), MeshLib.mat(Color(0.03, 0.03, 0.04)), Vector3(0, 0.62, -0.4))
		"altar", "shrine":
			MeshLib.part(n, MeshLib.cyl(2.6, 2.8, 0.25, 16), stone, Vector3(0, 0.12, 0))
			MeshLib.part(n, MeshLib.box(Vector3(2.0, 1.0, 1.0)), stone, Vector3(0, 0.75, 0))
			var rc := Color(0.5, 0.8, 1.0) if poi.type == "altar" else Color(1.0, 0.9, 0.6)
			MeshLib.part(n, MeshLib.box(Vector3(1.6, 0.06, 0.7)), MeshLib.mat(rc, 0.0, 0.4, 2.0), Vector3(0, 1.28, 0))
			cols.append(["box", Vector3(0, 0.75, 0), Vector3(2.0, 1.0, 1.0)])
			var al := OmniLight3D.new()
			al.light_color = rc
			al.light_energy = 0.9
			al.omni_range = 6.0
			al.position = Vector3(0, 1.8, 0)
			al.shadow_enabled = false
			n.add_child(al)
		"mirror":
			MeshLib.part(n, MeshLib.box(Vector3(2.4, 3.6, 0.3)), MeshLib.mat(Color(0.75, 0.6, 0.3), 0.8, 0.3), Vector3(0, 1.9, 0))
			MeshLib.part(n, MeshLib.box(Vector3(2.0, 3.1, 0.32)), MeshLib.mat(Color(0.7, 0.85, 0.95), 1.0, 0.05, 0.4), Vector3(0, 1.9, 0))
			MeshLib.part(n, MeshLib.box(Vector3(3.0, 0.3, 1.2)), stone, Vector3(0, 0.15, 0))
			cols.append(["box", Vector3(0, 1.9, 0), Vector3(2.4, 3.6, 0.4)])
		"ruins":
			for i in 7:
				var a5 := i * 0.9
				var rp := Vector3(cos(a5) * rng_off(i, 7.0), 0, sin(a5) * rng_off(i + 3, 7.0))
				var hh := 1.0 + float((i * 37) % 30) / 10.0
				MeshLib.part(n, MeshLib.box(Vector3(3.5, hh, 0.7)), stone, rp + Vector3(0, hh * 0.5, 0), Vector3(0, i * 40, 0))
				cols.append(["box", rp + Vector3(0, hh * 0.5, 0), Vector3(3.0, hh, 0.7)])
			MeshLib.part(n, MeshLib.cyl(0.5, 0.5, 4.0, 10), stone, Vector3(2.0, 0.5, 3.0), Vector3(0, 0, 90))
		"fortress":
			for i in 4:
				var a6 := i * TAU / 4.0 + PI / 4.0
				var tp2 := Vector3(cos(a6), 0, sin(a6)) * 20.0
				var th := 4.0 + i * 1.5
				MeshLib.part(n, MeshLib.cyl(2.2, 2.6, th, 10), stone, tp2 + Vector3(0, th * 0.5, 0))
				cols.append(["cyl", tp2 + Vector3(0, th * 0.5, 0), 2.4, th])
				var a7 := a6 + PI / 4.0
				if i != 1:
					var wp := Vector3(cos(a7), 0, sin(a7)) * 19.0
					MeshLib.part(n, MeshLib.box(Vector3(22.0, 3.0, 1.2)), stone, wp + Vector3(0, 1.5, 0), Vector3(0, -rad_to_deg(a7) + 90.0, 0))
					cols.append(["boxr", wp + Vector3(0, 1.5, 0), Vector3(22.0, 3.0, 1.2), -a7 + PI / 2.0])
		"witness":
			MeshLib.part(n, MeshLib.cyl(1.6, 2.0, 2.2, 8), wood, Vector3(0, 1.1, 0))
			MeshLib.part(n, MeshLib.cyl(0.0, 2.6, 1.6, 8), MeshLib.mat(Color(0.35, 0.3, 0.25)), Vector3(0, 3.0, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.25, 0.35, 0.25)), MeshLib.mat(Color(0.4, 1.0, 0.85), 0.0, 0.4, 3.0), Vector3(2.2, 1.6, 0))
			cols.append(["cyl", Vector3(0, 1.1, 0), 1.9, 2.2])
		"tourney":
			for i in 10:
				var x := -10.0 + i * 2.2
				MeshLib.part(n, MeshLib.box(Vector3(2.2, 1.0, 0.15)), wood, Vector3(x, 0.5, 0))
			MeshLib.part(n, MeshLib.box(Vector3(10.0, 2.5, 3.0)), wood, Vector3(0, 1.25, -14.0))
			MeshLib.part(n, MeshLib.box(Vector3(10.4, 0.3, 3.4)), MeshLib.mat(Color(0.7, 0.15, 0.15)), Vector3(0, 3.6, -14.0))
			cols.append(["box", Vector3(0, 1.25, -14.0), Vector3(10.0, 2.5, 3.0)])
		"forge":
			MeshLib.part(n, MeshLib.box(Vector3(1.6, 1.0, 1.2)), stone, Vector3(0, 0.5, 0))
			MeshLib.part(n, MeshLib.box(Vector3(1.0, 0.1, 0.7)), MeshLib.mat(Color(1.0, 0.5, 0.15), 0.0, 0.5, 3.0), Vector3(0, 1.02, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.6, 0.6, 0.3)), dark, Vector3(1.4, 0.3, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.0))
			MeshLib.part(n, MeshLib.box(Vector3(0.9, 0.2, 0.35)), metal, Vector3(1.4, 0.7, 0))
			cols.append(["box", Vector3(0.5, 0.5, 0), Vector3(2.6, 1.0, 1.2)])
		"lab":
			MeshLib.part(n, MeshLib.box(Vector3(2.4, 0.9, 1.0)), wood, Vector3(0, 0.45, 0))
			var fc := [Color(0.3, 1.0, 0.4), Color(1.0, 0.4, 0.3), Color(0.4, 0.6, 1.0), Color(1.0, 0.9, 0.3)]
			for i in 4:
				MeshLib.part(n, MeshLib.sphere(0.14, 8, 5), MeshLib.mat(fc[i], 0.0, 0.2, 1.6), Vector3(-0.8 + i * 0.5, 1.05, 0))
			cols.append(["box", Vector3(0, 0.45, 0), Vector3(2.4, 0.9, 1.0)])
		"workshop":
			MeshLib.part(n, MeshLib.box(Vector3(2.6, 0.9, 1.2)), wood, Vector3(0, 0.45, 0))
			for i in 3:
				MeshLib.part(n, MeshLib.torus(0.15, 0.3), MeshLib.mat(Color(0.8, 0.6, 0.3), 0.8, 0.35), Vector3(-0.7 + i * 0.7, 0.95, 0), Vector3(90, 0, 0))
			cols.append(["box", Vector3(0, 0.45, 0), Vector3(2.6, 0.9, 1.2)])
		"terminal":
			MeshLib.part(n, MeshLib.box(Vector3(1.0, 1.4, 0.6)), MeshLib.mat(Color(0.2, 0.22, 0.26), 0.6, 0.4), Vector3(0, 0.7, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.8, 0.55, 0.05)), MeshLib.mat(Color(0.3, 0.9, 0.6), 0.0, 0.4, 2.2), Vector3(0, 1.1, -0.31), Vector3(-15, 0, 0))
			cols.append(["box", Vector3(0, 0.7, 0), Vector3(1.0, 1.4, 0.6)])
	if not cols.is_empty():
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		for c in cols:
			var cs := CollisionShape3D.new()
			if c[0] == "cyl":
				var cy := CylinderShape3D.new()
				cy.radius = c[2]
				cy.height = c[3]
				cs.shape = cy
			else:
				var bx := BoxShape3D.new()
				bx.size = c[2]
				cs.shape = bx
				if c[0] == "boxr":
					cs.rotation.y = c[3]
			cs.position = c[1]
			sb.add_child(cs)
		n.add_child(sb)
	return n

static func rng_off(i: int, base: float) -> float:
	return base * (0.6 + float((i * 53) % 40) / 100.0)

static func _cp_decor(n: Node3D, cp_type: String, era: int, cols: Array) -> void:
	var wood := MeshLib.mat(Color(0.45, 0.31, 0.18))
	var stone := MeshLib.mat(Color(0.55, 0.54, 0.52))
	var metal := MeshLib.mat(Color(0.42, 0.44, 0.48), 0.75, 0.35)
	MeshLib.part(n, MeshLib.cyl(5.0, 5.2, 0.1, 20), MeshLib.mat(Color(0.4, 0.38, 0.34)), Vector3(0, 0.05, 0))
	match cp_type:
		"watchtower", "comm_tower", "outpost", "checkpoint", "defense_turret":
			var m: Material = wood if era <= 1 else metal
			for p in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
				MeshLib.part(n, MeshLib.box(Vector3(0.25, 6.0, 0.25)), m, p * 1.2 + Vector3(0, 3.0, 0))
				cols.append(["box", p * 1.2 + Vector3(0, 3.0, 0), Vector3(0.3, 6.0, 0.3)])
			MeshLib.part(n, MeshLib.box(Vector3(3.4, 0.3, 3.4)), m, Vector3(0, 6.0, 0))
			if era <= 1:
				MeshLib.part(n, MeshLib.prism(Vector3(3.6, 1.4, 3.6)), MeshLib.mat(Color(0.5, 0.2, 0.15)), Vector3(0, 7.0, 0))
			else:
				MeshLib.part(n, MeshLib.cyl(0.05, 0.05, 4.0, 4), metal, Vector3(0, 8.0, 0))
				MeshLib.part(n, MeshLib.sphere(0.2, 6, 4), MeshLib.mat(Color(1.0, 0.2, 0.2), 0.0, 0.4, 3.0), Vector3(0, 10.0, 0))
		"altar", "rift_anchor":
			var c := Color(0.5, 0.8, 1.0) if cp_type == "altar" else Color(0.4, 1.0, 0.85)
			MeshLib.part(n, MeshLib.box(Vector3(1.8, 1.0, 1.0)), stone, Vector3(0, 0.5, 0))
			MeshLib.part(n, MeshLib.prism(Vector3(0.8, 3.0, 0.8)), MeshLib.mat(c, 0.0, 0.3, 1.8), Vector3(0, 2.5, 0))
			cols.append(["box", Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 1.0)])
		"warehouse", "harbor", "factory", "lab", "data_node":
			var wc := Color(0.5, 0.36, 0.22) if era <= 1 else (Color(0.5, 0.25, 0.18) if era == 2 else Color(0.6, 0.62, 0.66))
			MeshLib.part(n, MeshLib.box(Vector3(5.0, 3.0, 3.5)), MeshLib.mat(wc), Vector3(0, 1.5, -1.0))
			MeshLib.part(n, MeshLib.box(Vector3(5.4, 0.3, 3.9)), MeshLib.mat(wc.darkened(0.3)), Vector3(0, 3.1, -1.0))
			cols.append(["box", Vector3(0, 1.5, -1.0), Vector3(5.0, 3.0, 3.5)])
			if cp_type == "factory":
				MeshLib.part(n, MeshLib.cyl(0.5, 0.6, 6.0, 8), MeshLib.mat(Color(0.5, 0.25, 0.18)), Vector3(1.8, 5.0, -1.8))
			if cp_type == "data_node":
				MeshLib.part(n, MeshLib.box(Vector3(5.02, 0.15, 3.52)), MeshLib.mat(Color(0.3, 0.8, 1.0), 0.0, 0.4, 2.5), Vector3(0, 2.0, -1.0))
		"resource_camp", "coal_mine", "alchemy_lab":
			MeshLib.part(n, MeshLib.cyl(0.0, 1.8, 1.6, 7), MeshLib.mat(Color(0.12, 0.12, 0.12) if cp_type == "coal_mine" else Color(0.5, 0.45, 0.4)), Vector3(-1.5, 0.8, 0))
			for i in 3:
				MeshLib.part(n, MeshLib.box(Vector3(0.9, 0.9, 0.9)), wood, Vector3(1.5, 0.45 + i * 0.9 * float(i == 2), -1.0 + i * 0.95 * float(i < 2)))
			cols.append(["cyl", Vector3(-1.5, 0.8, 0), 1.4, 1.6])
		_:
			MeshLib.part(n, MeshLib.box(Vector3(1.6, 3.5, 1.6)), metal, Vector3(0, 1.75, 0))
			MeshLib.part(n, MeshLib.torus(1.2, 1.4), MeshLib.mat(Color(0.3, 0.8, 1.0), 0.0, 0.3, 3.0), Vector3(0, 2.5, 0))
			cols.append(["box", Vector3(0, 1.75, 0), Vector3(1.6, 3.5, 1.6)])
	# flag pole (the world may recolour "Flag" by owner)
	MeshLib.part(n, MeshLib.cyl(0.05, 0.06, 5.0, 5), MeshLib.mat(Color(0.3, 0.3, 0.3)), Vector3(3.5, 2.5, 3.5))
	var flag := MeshLib.part(n, MeshLib.box(Vector3(1.2, 0.7, 0.03)), MeshLib.mat(Color(0.85, 0.85, 0.85)), Vector3(4.1, 4.6, 3.5))
	flag.name = "Flag"

# ---------------------------------------------------------------- foliage + landscape tables
const FOLIAGE_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
uniform float fade_end = 40.0;
uniform float wind = 1.0;
void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float ph = org.x * 0.37 + org.z * 0.29;
	float sway = (sin(TIME * 1.6 + ph) * 0.7 + sin(TIME * 2.7 + ph * 1.9) * 0.3) * wind * h * h * 0.16;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.55;
	float d = length(org - CAMERA_POSITION_WORLD);
	float f = 1.0 - smoothstep(fade_end * 0.62, fade_end, d);
	VERTEX *= vec3(mix(0.2, 1.0, f), f, mix(0.2, 1.0, f));
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() {
	vec3 c = COLOR.rgb;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = c * 0.8;
#else
	ALBEDO = c * c * 1.1;
#endif
	ROUGHNESS = 0.92;
	BACKLIGHT = vec3(0.18, 0.22, 0.1);
}
"""

static var _foliage_mat: ShaderMaterial

static func foliage_material() -> ShaderMaterial:
	if _foliage_mat == null:
		var sh := Shader.new()
		sh.code = FOLIAGE_SHADER
		_foliage_mat = ShaderMaterial.new()
		_foliage_mat.shader = sh
	return _foliage_mat

static func _blade(st: SurfaceTool, base: Vector3, ang: float, w: float, h: float, lean: float, c0: Color, c1: Color) -> void:
	var side := Vector3(cos(ang), 0, sin(ang)) * w * 0.5
	var tip := base + Vector3(-sin(ang) * lean, h, cos(ang) * lean)
	st.set_color(c0)
	st.add_vertex(base - side)
	st.set_color(c0)
	st.add_vertex(base + side)
	st.set_color(c1)
	st.add_vertex(tip)

static func _foliage_mesh(t: String, era: int, tint: Color = Color(0.4, 0.6, 0.3)) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = hash(t) + era
	match t:
		"grass":
			for i in 11:
				var a := r.randf() * TAU
				var p := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.42)
				var v := r.randf_range(-0.12, 0.12)
				var tip := tint.lightened(0.16 + v) if v > -0.06 else tint.lerp(Color(0.75, 0.68, 0.4), 0.25)
				_blade(st, p, r.randf() * TAU, r.randf_range(0.08, 0.13), r.randf_range(0.24, 0.52), r.randf_range(0.05, 0.2), tint.darkened(0.38), tip)
		"flowerbed":
			var pal := [Color(0.95, 0.85, 0.3), Color(0.95, 0.95, 0.98), Color(0.85, 0.35, 0.4), Color(0.65, 0.45, 0.95), Color(0.98, 0.6, 0.25)]
			if era == 4:
				pal = [Color(0.3, 1.0, 0.9), Color(1.0, 0.4, 0.9), Color(0.6, 0.8, 1.0)]
			var green := Color(0.42, 0.62, 0.3) if era != 4 else Color(0.3, 0.55, 0.6)
			for i in 7:
				var a2 := r.randf() * TAU
				var p2 := Vector3(cos(a2), 0, sin(a2)) * r.randf_range(0.0, 0.38)
				var hh := r.randf_range(0.22, 0.42)
				_blade(st, p2, r.randf() * TAU, 0.05, hh, 0.04, green.darkened(0.3), green)
				var fc: Color = pal[r.randi() % pal.size()]
				var top := p2 + Vector3(0, hh, 0)
				for q in 2:
					var fa := r.randf() * TAU + q * PI * 0.5
					var fs := Vector3(cos(fa), 0, sin(fa)) * 0.06
					st.set_color(fc)
					st.add_vertex(top - fs)
					st.set_color(fc)
					st.add_vertex(top + fs)
					st.set_color(fc.lightened(0.2))
					st.add_vertex(top + Vector3(0, 0.07, 0))
		"fern":
			var fc2 := Color(0.3, 0.52, 0.24) if era != 4 else Color(0.2, 0.55, 0.55)
			for i in 8:
				var a3 := float(i) / 8.0 * TAU + r.randf() * 0.4
				var dir := Vector3(cos(a3), 0, sin(a3))
				var mid := dir * 0.35 + Vector3(0, 0.35, 0)
				var tip := dir * 0.75 + Vector3(0, 0.18, 0)
				var side := Vector3(-dir.z, 0, dir.x) * 0.1
				st.set_color(fc2.darkened(0.35))
				st.add_vertex(Vector3.ZERO)
				st.set_color(fc2)
				st.add_vertex(mid + side)
				st.set_color(fc2)
				st.add_vertex(mid - side)
				st.set_color(fc2)
				st.add_vertex(mid + side)
				st.set_color(fc2.lightened(0.15))
				st.add_vertex(tip)
				st.set_color(fc2)
				st.add_vertex(mid - side)
		"reeds":
			var rc := Color(0.5, 0.55, 0.3)
			for i in 10:
				var a4 := r.randf() * TAU
				var p4 := Vector3(cos(a4), 0, sin(a4)) * r.randf_range(0.0, 0.3)
				var hh2 := r.randf_range(0.9, 1.6)
				_blade(st, p4, r.randf() * TAU, 0.06, hh2, r.randf_range(0.05, 0.25), rc.darkened(0.35), rc.lightened(0.2))
				if i % 3 == 0:
					var top2 := p4 + Vector3(0, hh2, 0)
					_blade(st, top2 - Vector3(0, 0.25, 0), a4, 0.07, 0.25, 0.0, Color(0.4, 0.28, 0.16), Color(0.45, 0.3, 0.18))
	st.set_material(foliage_material())
	return st.commit()

## Vegetation / landscape detail per biome for an era:
## {biome: {"big": [[type, weight, smin, smax]], "bd": density, "small": [...], "sd": density, "grass": density}}
static func veg_table(era: int) -> Dictionary:
	var e: Dictionary = DBEras.era(era)
	var trees: Array = []
	for t in e.props:
		if category(t) == "tree":
			trees.append(t)
	if trees.is_empty():
		trees = ["tree_dead"]
	var forest_big: Array = []
	var plains_big: Array = []
	for t in trees:
		forest_big.append([t, 4.0, 0.85, 1.35])
		forest_big.append([t, 1.4, 0.5, 0.72])     # young
		forest_big.append([t, 0.8, 1.4, 1.7])      # old giants
		plains_big.append([t, 0.6, 0.8, 1.4])
	forest_big.append_array([["log", 0.9, 0.8, 1.2], ["stump", 0.7, 0.8, 1.3], ["boulder", 0.35, 0.6, 1.0], ["bush", 1.8, 0.8, 1.4], ["tree_dead", 0.35, 0.8, 1.2]])
	plains_big.append_array([["bush", 2.2, 0.7, 1.3], ["rock", 0.9, 0.6, 1.3], ["boulder", 0.25, 0.6, 1.1], ["fence_broken", 0.35, 0.9, 1.1]])
	var plains_small: Array = [["flowerbed", 3.0, 0.8, 1.3], ["pebbles", 0.6, 0.8, 1.3], ["dead_bush", 0.3, 0.8, 1.2]]
	var forest_small: Array = [["fern", 4.0, 0.7, 1.3], ["mushrooms", 1.0, 0.8, 1.5], ["flowerbed", 0.5, 0.8, 1.1], ["pebbles", 0.4, 0.8, 1.2]]
	match era:
		0:
			plains_big.append_array([["haystack", 0.5, 0.8, 1.2], ["shed", 0.12, 0.9, 1.1], ["ruin_wall", 0.12, 0.8, 1.1], ["stump", 0.4, 0.8, 1.2]])
		1:
			plains_big.append_array([["vineyard", 1.2, 0.9, 1.1], ["ruin_column", 0.3, 0.8, 1.1], ["ruin_wall", 0.15, 0.8, 1.1], ["haystack", 0.2, 0.8, 1.1]])
		2:
			plains_big.append_array([["scrap_pile", 0.6, 0.8, 1.2], ["coal_pile", 0.3, 0.6, 1.0], ["tree_dead", 0.8, 0.8, 1.2], ["shed", 0.15, 0.9, 1.1], ["pipe", 0.1, 1.0, 1.0]])
			forest_small.append(["dead_bush", 0.8, 0.8, 1.2])
		3:
			plains_big.append_array([["car_wreck", 0.12, 1.0, 1.0], ["barrier", 0.25, 1.0, 1.0], ["shed", 0.12, 0.9, 1.1]])
			plains_small.append(["litter", 1.2, 0.8, 1.2])
			forest_small.append(["litter", 0.3, 0.8, 1.2])
		4:
			plains_big.append_array([["crystal", 0.5, 0.5, 1.0], ["holo_plant", 0.6, 0.8, 1.3], ["energy_pylon", 0.04, 1.0, 1.0]])
			plains_small.append(["crystal_small", 1.5, 0.7, 1.4])
			forest_small.append(["crystal_small", 0.8, 0.7, 1.3])
	var pine: String = "tree_pine" if "tree_pine" in trees else trees[0]
	return {
		"forest": {"big": forest_big, "bd": 0.62, "small": forest_small, "sd": 0.34, "grass": 0.75},
		"plains": {"big": plains_big, "bd": 0.13, "small": plains_small, "sd": 0.2, "grass": 1.0},
		"swamp": {"big": [[trees[0], 1.2, 0.7, 1.2], ["tree_dead", 1.6, 0.8, 1.3], ["log", 1.0, 0.8, 1.2], ["bush", 1.0, 0.7, 1.2], ["stump", 0.6, 0.8, 1.2]], "bd": 0.24,
			"small": [["reeds", 4.0, 0.8, 1.3], ["fern", 1.0, 0.7, 1.1], ["mushrooms", 0.8, 0.8, 1.4]], "sd": 0.4, "grass": 0.55},
		"sand": {"big": [["rock", 2.0, 0.6, 1.4], ["boulder", 0.8, 0.6, 1.1], ["outcrop", 0.5, 0.7, 1.1], ["dead_bush", 1.6, 0.8, 1.3], ["tree_dead", 0.4, 0.7, 1.1]], "bd": 0.08,
			"small": [["pebbles", 1.0, 0.8, 1.4], ["dead_bush", 1.0, 0.6, 1.0]], "sd": 0.06, "grass": 0.1},
		"mountain": {"big": [["rock", 3.0, 0.7, 1.6], ["boulder", 2.0, 0.7, 1.3], ["outcrop", 1.8, 0.7, 1.3], [pine, 1.0, 0.7, 1.2]], "bd": 0.22,
			"small": [["pebbles", 1.0, 0.8, 1.5]], "sd": 0.05, "grass": 0.22},
		"snow": {"big": [["rock", 1.0, 0.7, 1.4], ["outcrop", 1.0, 0.7, 1.2], [pine, 1.0, 0.7, 1.1]], "bd": 0.1, "small": [], "sd": 0.0, "grass": 0.0},
		"urban": {"big": [], "bd": 0.0, "small": [["flowerbed", 1.0, 0.8, 1.1], ["pebbles", 0.5, 0.8, 1.2]], "sd": 0.05, "grass": 0.3},
	}
