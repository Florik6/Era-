class_name BeastRig
extends CreatureRig
## «Beasts of the Ages»: one procedural rig, many body plans. Each species
## gives a plan and a few proportions / features, so silhouettes really
## differ (a scavenger is low and long, a troll is a hunched giant, a drake
## has a neck, wings and a tail, a worm is a chain of segments…).
##
## Plans: quad, drake, arach, insect, worm, flyer, giant, tree, blob, orb,
## construct. Features (look.f): horns, spikes, plates, mane, crystals,
## gears, runes, mandibles, stinger, wings, tail_club, eyes (count), core.
## Breakable parts (bosses): named nodes in `parts`, see break_part().
## Shared meshes come from MeshLib (cached); materials are shared per colour.

var plan := "quad"
var f := {}                 # features
var parts := {}             # name -> Node3D (breakable)
var broken := {}
var crack_mat: Material
var glow_m: StandardMaterial3D
var _segs: Array = []       # worm segments
var _wings: Array = []
var _legs: Array = []
var _orbit: Node3D = null
var _hover := 0.0
var size := 1.0

func setup(l: Dictionary) -> void:
	look = l
	plan = str(l.get("plan", "quad"))
	kind = "beast_" + plan
	f = l.get("f", {})
	var col: Color = l.get("body", Color(0.5, 0.45, 0.4))
	var metal: bool = l.get("metal", false)
	body_mat = MeshLib.mat(col, 0.7 if metal else 0.0, 0.4 if metal else 0.85, 0.0)
	var acc: Color = l.get("accent", col.darkened(0.35))
	var acc_mat := MeshLib.mat(acc, 0.6 if metal else 0.0, 0.5 if metal else 0.8)
	var glow_c: Color = l.get("glow", Color(1.0, 0.6, 0.2))
	glow_m = MeshLib.glow(glow_c, 2.5)
	var glow_mat: StandardMaterial3D = glow_m
	crack_mat = MeshLib.glow(glow_c, 3.5)
	var b := MeshLib.pivot(self, Vector3.ZERO, "body")
	j.body = b
	match plan:
		"quad", "drake": _build_quad(b, acc_mat, glow_mat)
		"arach": _build_arach(b, acc_mat, glow_mat)
		"insect": _build_insect(b, acc_mat, glow_mat)
		"worm": _build_worm(b, acc_mat, glow_mat)
		"flyer": _build_flyer(b, acc_mat, glow_mat)
		"giant": _build_giant(b, acc_mat, glow_mat)
		"tree": _build_tree(b, acc_mat, glow_mat)
		"blob": _build_blob2(b, acc_mat, glow_mat)
		"orb": _build_orb(b, acc_mat, glow_mat)
		"construct": _build_construct(b, acc_mat, glow_mat)
		_: _build_quad(b, acc_mat, glow_mat)
	size = float(l.get("scale", 1.0))
	scale = Vector3.ONE * size

func _feat(k: String, d = 0):
	return f.get(k, d)

func _eyes(head: Node3D, z: float, y: float, w: float, glow_mat: Material) -> void:
	var n := int(_feat("eyes", 2))
	for i in n:
		var x := -w * 0.5 + (w * float(i) / maxf(1.0, n - 1)) if n > 1 else 0.0
		var row := 0.0 if n <= 4 else (0.05 if i % 2 == 0 else -0.03)
		MeshLib.part(head, MeshLib.sphere(0.03 + 0.01 * (1 if n <= 2 else 0), 6, 4), glow_mat, Vector3(x, y + row, z), Vector3.ZERO, Vector3.ONE, false)

func _horns(head: Node3D, y: float, acc_mat: Material) -> void:
	var h := int(_feat("horns", 0))
	for i in h:
		var side := -1.0 if i % 2 == 0 else 1.0
		var k := float(i / 2)
		var hp := MeshLib.pivot(head, Vector3(0.09 * side + 0.04 * side * k, y, 0.02 + 0.06 * k), "horn%d" % i)
		hp.rotation = Vector3(-0.5, 0, -0.5 * side)
		MeshLib.part(hp, MeshLib.cyl(0.0, 0.045, 0.28 + 0.06 * k, 5), acc_mat, Vector3(0, 0.14, 0))

func _spikes(parent: Node3D, from_z: float, to_z: float, y: float, acc_mat: Material) -> void:
	var n := int(_feat("spikes", 0))
	for i in n:
		var z := lerpf(from_z, to_z, float(i) / maxf(1.0, n - 1))
		MeshLib.part(parent, MeshLib.cyl(0.0, 0.06, 0.22, 4), acc_mat, Vector3(0, y, z), Vector3(-15, 0, 0))

func _plates(parent: Node3D, from_z: float, to_z: float, y: float, w: float, acc_mat: Material, names: Array) -> void:
	var n := int(_feat("plates", 0))
	for i in n:
		var z := lerpf(from_z, to_z, float(i) / maxf(1.0, n - 1))
		var nm: String = names[i] if i < names.size() else "plate%d" % i
		var p := MeshLib.pivot(parent, Vector3(0, y, z), nm)
		MeshLib.part(p, MeshLib.box(Vector3(w, 0.12, 0.3)), acc_mat, Vector3.ZERO, Vector3(randf_range(-6, 6), 0, randf_range(-8, 8)))
		parts[nm] = p

func _crystals(parent: Node3D, center: Vector3, spread: float, glow_mat: Material) -> void:
	var n := int(_feat("crystals", 0))
	for i in n:
		var a := TAU * i / maxf(1.0, n)
		MeshLib.part(parent, MeshLib.cyl(0.0, 0.07, 0.35, 5), glow_mat, center + Vector3(cos(a) * spread, 0.05, sin(a) * spread), Vector3(cos(a) * 25.0, 0, sin(a) * 25.0), Vector3.ONE, false)

# ------------------------------------------------------------------ plans
func _build_quad(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	var L: float = float(_feat("len", 1.0))
	var H: float = float(_feat("height", 0.62))
	var G: float = float(_feat("girth", 0.22))
	var torso := MeshLib.pivot(b, Vector3(0, H, 0), "torso")
	j.torso = torso
	MeshLib.part(torso, MeshLib.capsule(G, L), body_mat, Vector3.ZERO, Vector3(90, 0, 0))
	if float(_feat("hump", 0.0)) > 0.0:
		MeshLib.part(torso, MeshLib.sphere(G * 1.2, 10, 6), body_mat, Vector3(0, G * 0.6, -L * 0.15), Vector3.ZERO, Vector3(1.0, float(_feat("hump")), 1.2))
	var neck_len: float = float(_feat("neck", 0.0))
	var hp := Vector3(0, G * 0.5, -L * 0.5)
	if neck_len > 0.0:
		var neck := MeshLib.pivot(torso, Vector3(0, G * 0.4, -L * 0.45), "neck")
		neck.rotation.x = -0.7
		MeshLib.part(neck, MeshLib.capsule(G * 0.45, neck_len), body_mat, Vector3(0, 0, -neck_len * 0.45), Vector3(90, 0, 0))
		hp = Vector3(0, G * 0.4 + neck_len * 0.55, -L * 0.45 - neck_len * 0.75)
	var head := MeshLib.pivot(torso, hp, "head")
	j.head = head
	var hs: float = float(_feat("head", 1.0))
	MeshLib.part(head, MeshLib.box(Vector3(0.24, 0.22, 0.26) * hs), body_mat)
	MeshLib.part(head, MeshLib.box(Vector3(0.14, 0.11, 0.24) * hs), body_mat, Vector3(0, -0.04 * hs, -0.22 * hs))
	MeshLib.part(head, MeshLib.prism(Vector3(0.12, 0.06, 0.18) * hs), MeshLib.mat(Color(0.92, 0.9, 0.82)), Vector3(0, -0.1 * hs, -0.22 * hs), Vector3(180, 0, 0), Vector3.ONE, false)
	_eyes(head, -0.14 * hs, 0.05 * hs, 0.14 * hs, glow_mat)
	_horns(head, 0.12 * hs, acc_mat)
	if _feat("mane", false):
		for i in 5:
			MeshLib.part(torso, MeshLib.cyl(0.0, 0.07, 0.25, 4), acc_mat, Vector3(randf_range(-0.08, 0.08), G * 0.8, -L * 0.4 + i * 0.08), Vector3(-30, 0, randf_range(-20, 20)))
	_spikes(torso, -L * 0.35, L * 0.35, G * 0.85, acc_mat)
	_plates(torso, -L * 0.3, L * 0.3, G * 0.9, G * 2.1, acc_mat, f.get("plate_names", []))
	_crystals(torso, Vector3(0, G * 0.8, 0), G * 0.6, glow_mat)
	if plan == "drake" or _feat("wings", false):
		for side in [-1.0, 1.0]:
			var wp := MeshLib.pivot(torso, Vector3(G * 0.8 * side, G * 0.7, -L * 0.15), "wing%d" % (0 if side < 0 else 1))
			MeshLib.part(wp, MeshLib.box(Vector3(1.3 * L, 0.03, 0.75 * L)), acc_mat, Vector3(0.65 * L * side, 0, 0.15), Vector3(0, 0, 8 * side))
			MeshLib.part(wp, MeshLib.cyl(0.03, 0.05, 1.3 * L, 5), body_mat, Vector3(0.65 * L * side, 0.02, -0.2), Vector3(0, 0, 90))
			_wings.append([wp, side])
	var tail := MeshLib.pivot(torso, Vector3(0, G * 0.3, L * 0.5), "tail")
	j.tail = tail
	var tl: float = float(_feat("tail", 0.4))
	MeshLib.part(tail, MeshLib.capsule(G * 0.25, tl), body_mat, Vector3(0, 0, tl * 0.45), Vector3(70 if tl < 0.8 else 85, 0, 0))
	if _feat("tail_club", false):
		MeshLib.part(tail, MeshLib.sphere(G * 0.5, 8, 6), acc_mat, Vector3(0, -0.05, tl * 0.95))
	var legs := int(_feat("legs", 4))
	var lt: float = float(_feat("leg", 0.045)) * (G / 0.22)
	for i in legs:
		var row := float(i / 2) / maxf(1.0, legs / 2 - 1) if legs > 2 else 0.0
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(G * 0.6 * side, -G * 0.2, lerpf(-L * 0.32, L * 0.32, row))
		var leg := MeshLib.pivot(torso, pos, "leg%d" % i)
		j["leg%d" % i] = leg
		MeshLib.part(leg, MeshLib.capsule(lt, H - 0.05), body_mat, Vector3(0, -(H - 0.05) * 0.5, 0))
		_legs.append(leg)

func _build_arach(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	var torso := MeshLib.pivot(b, Vector3(0, 0.55, 0), "torso")
	j.torso = torso
	var ab: float = float(_feat("abdomen", 1.0))
	MeshLib.part(torso, MeshLib.sphere(0.28, 10, 6), body_mat, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.6, 1.1))
	var abd := MeshLib.pivot(torso, Vector3(0, 0.1, 0.48 * ab), "abdomen")
	MeshLib.part(abd, MeshLib.sphere(0.4 * ab, 12, 8), body_mat, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.8, 1.15))
	if _feat("markings", false):
		MeshLib.part(abd, MeshLib.box(Vector3(0.12, 0.02, 0.3) * ab), glow_mat, Vector3(0, 0.3 * ab, 0), Vector3.ZERO, Vector3.ONE, false)
	_crystals(abd, Vector3(0, 0.28 * ab, 0), 0.18 * ab, glow_mat)
	var head := MeshLib.pivot(torso, Vector3(0, 0.02, -0.3), "head")
	j.head = head
	_eyes(head, -0.06, 0.06, 0.16, glow_mat)
	for side in [-1.0, 1.0]:
		MeshLib.part(head, MeshLib.cyl(0.0, 0.03, 0.16, 4), acc_mat, Vector3(0.05 * side, -0.06, -0.06), Vector3(-160, 0, 0))
	var n := int(_feat("legs", 8))
	for k in n:
		var side := -1.0 if k < n / 2 else 1.0
		var zi := (float(k % (n / 2)) / maxf(1.0, n / 2 - 1) - 0.5) * 0.55
		var leg := MeshLib.pivot(torso, Vector3(0.2 * side, 0, zi), "leg%d" % k)
		j["leg%d" % k] = leg
		var up := MeshLib.pivot(leg, Vector3.ZERO, "up%d" % k)
		up.rotation.z = -0.7 * side
		MeshLib.part(up, MeshLib.cyl(0.035, 0.03, 0.55, 5), body_mat, Vector3(0.27 * side, 0, 0), Vector3(0, 0, 90))
		var low := MeshLib.pivot(up, Vector3(0.55 * side, 0, 0), "low%d" % k)
		low.rotation.z = 1.75 * side
		MeshLib.part(low, MeshLib.cyl(0.028, 0.01, 0.7, 5), body_mat, Vector3(0.35 * side, 0, 0), Vector3(0, 0, 90))
		_legs.append(leg)

func _build_insect(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	_build_arach(b, acc_mat, glow_mat)
	var torso: Node3D = j.torso
	# pincers
	for side in [-1.0, 1.0]:
		var arm := MeshLib.pivot(torso, Vector3(0.16 * side, 0.02, -0.3), "claw%d" % (0 if side < 0 else 1))
		MeshLib.part(arm, MeshLib.capsule(0.04, 0.35), body_mat, Vector3(0.05 * side, 0, -0.17), Vector3(90, 0, 0))
		MeshLib.part(arm, MeshLib.box(Vector3(0.1, 0.06, 0.16)), acc_mat, Vector3(0.06 * side, 0, -0.38))
		j["claw%d" % (0 if side < 0 else 1)] = arm
	# segmented tail with a stinger arching over the back
	var tail := MeshLib.pivot(torso, Vector3(0, 0.15, 0.55), "tail")
	j.tail = tail
	var prev := tail
	for i in 5:
		var seg := MeshLib.pivot(prev, Vector3(0, 0.12, 0.08), "tseg%d" % i)
		seg.rotation.x = -0.45
		MeshLib.part(seg, MeshLib.sphere(0.08 - i * 0.008, 8, 5), body_mat)
		prev = seg
	MeshLib.part(prev, MeshLib.cyl(0.0, 0.04, 0.2, 5), glow_mat if _feat("stinger", true) else acc_mat, Vector3(0, 0.05, -0.08), Vector3(-120, 0, 0), Vector3.ONE, false)

func _build_worm(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	var n := int(_feat("segments", 8))
	var r: float = float(_feat("girth", 0.25))
	var torso := MeshLib.pivot(b, Vector3(0, r, 0), "torso")
	j.torso = torso
	for i in n:
		var seg := MeshLib.pivot(torso, Vector3(0, 0, r * 1.5 * i), "seg%d" % i)
		var sr := r * (1.0 - 0.6 * float(i) / float(n))
		MeshLib.part(seg, MeshLib.sphere(sr, 10, 6), body_mat if i % 2 == 0 else acc_mat)
		if int(_feat("spikes", 0)) > 0 and i % 2 == 1:
			MeshLib.part(seg, MeshLib.cyl(0.0, sr * 0.3, sr * 0.9, 4), acc_mat, Vector3(0, sr * 0.9, 0))
		_segs.append(seg)
	var head: Node3D = _segs[0]
	j.head = head
	for side in [-1.0, 1.0]:
		MeshLib.part(head, MeshLib.cyl(0.0, r * 0.25, r * 1.1, 4), MeshLib.mat(Color(0.92, 0.9, 0.82)), Vector3(r * 0.5 * side, -r * 0.2, -r * 0.9), Vector3(-80, 0, 20 * side), Vector3.ONE, false)
	_eyes(head, -r * 0.85, r * 0.3, r * 0.8, glow_mat)

func _build_flyer(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	_hover = float(_feat("hover", 1.6))
	var torso := MeshLib.pivot(b, Vector3(0, _hover, 0), "torso")
	j.torso = torso
	var bl: float = float(_feat("len", 0.5))
	MeshLib.part(torso, MeshLib.capsule(0.13, bl), body_mat, Vector3.ZERO, Vector3(80, 0, 0))
	var head := MeshLib.pivot(torso, Vector3(0, 0.12, -bl * 0.55), "head")
	j.head = head
	MeshLib.part(head, MeshLib.sphere(0.11, 8, 6), body_mat)
	MeshLib.part(head, MeshLib.cyl(0.0, 0.04, 0.16, 4), acc_mat, Vector3(0, -0.02, -0.14), Vector3(-90, 0, 0))
	_eyes(head, -0.08, 0.03, 0.1, glow_mat)
	var span: float = float(_feat("span", 0.9))
	for side in [-1.0, 1.0]:
		var wp := MeshLib.pivot(torso, Vector3(0.1 * side, 0.05, -0.05), "wing%d" % (0 if side < 0 else 1))
		MeshLib.part(wp, MeshLib.box(Vector3(span, 0.02, 0.4)), acc_mat, Vector3(span * 0.5 * side, 0, 0.05))
		if _feat("feathers", false):
			for i in 3:
				MeshLib.part(wp, MeshLib.box(Vector3(0.18, 0.015, 0.22)), body_mat, Vector3((span * 0.7 + i * 0.1) * side, 0, 0.2 + i * 0.03))
		_wings.append([wp, side])
	for side in [-1.0, 1.0]:
		MeshLib.part(torso, MeshLib.cyl(0.015, 0.01, 0.3, 4), acc_mat, Vector3(0.05 * side, -0.2, 0.1))
	var tail := MeshLib.pivot(torso, Vector3(0, 0, bl * 0.5), "tail")
	j.tail = tail
	MeshLib.part(tail, MeshLib.box(Vector3(0.18, 0.02, 0.25)), acc_mat, Vector3(0, 0, 0.12))

func _build_giant(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	var hip := MeshLib.pivot(b, Vector3(0, 0.95, 0), "hip")
	j.hip = hip
	var torso := MeshLib.pivot(hip, Vector3(0, 0.1, 0), "torso")
	j.torso = torso
	var w: float = float(_feat("width", 0.75))
	var hunch: float = float(_feat("hunch", 0.25))
	torso.rotation.x = -hunch
	var rocky: bool = _feat("rocky", false)
	if rocky:
		for i in 6:
			MeshLib.part(torso, MeshLib.box(Vector3(w * 0.5, 0.35, 0.4)), body_mat if i % 2 == 0 else acc_mat, Vector3((i % 2 - 0.5) * w * 0.45, 0.3 + (i / 2) * 0.3, randf_range(-0.05, 0.05)), Vector3(randf_range(-10, 10), randf_range(-15, 15), randf_range(-10, 10)))
	else:
		MeshLib.part(torso, MeshLib.capsule(w * 0.42, 1.0), body_mat, Vector3(0, 0.45, 0))
	if _feat("veins", false):
		for i in 5:
			MeshLib.part(torso, MeshLib.box(Vector3(0.04, 0.4, 0.02)), crack_mat, Vector3(randf_range(-w * 0.35, w * 0.35), 0.45 + randf_range(-0.2, 0.3), -w * 0.42), Vector3(0, 0, randf_range(-40, 40)), Vector3.ONE, false)
	_plates(torso, -0.1, 0.25, 0.85, w * 0.9, acc_mat, f.get("plate_names", []))
	for nm in parts:
		parts[nm].position = Vector3((0.5 if nm.ends_with("r") else (-0.5 if nm.ends_with("l") else 0.0)) * w * 0.6, parts[nm].position.y, -w * 0.25 if not nm.ends_with("back") else w * 0.35)
	_crystals(torso, Vector3(0, 0.95, 0.1), w * 0.4, glow_mat)
	if int(_feat("gears", 0)) > 0:
		for i in int(_feat("gears", 0)):
			var g := MeshLib.pivot(torso, Vector3((i % 2 - 0.5) * w * 0.9, 0.6 + 0.25 * i, 0.3), "gear%d" % i)
			MeshLib.part(g, MeshLib.cyl(0.18, 0.18, 0.05, 10), acc_mat, Vector3.ZERO, Vector3(90, 0, 0))
			j["gear%d" % i] = g
	var head := MeshLib.pivot(torso, Vector3(0, 1.05, -0.12), "head")
	j.head = head
	MeshLib.part(head, MeshLib.box(Vector3(0.3, 0.28, 0.3) * float(_feat("head", 1.0))), body_mat)
	_eyes(head, -0.16, 0.03, 0.14, glow_mat)
	_horns(head, 0.12, acc_mat)
	if _feat("runes", false):
		MeshLib.part(torso, MeshLib.box(Vector3(0.3, 0.3, 0.02)), glow_mat, Vector3(0, 0.6, -w * 0.43), Vector3.ZERO, Vector3.ONE, false)
	var arm_l: float = float(_feat("arm", 1.0))
	for side in [-1.0, 1.0]:
		var sh := MeshLib.pivot(torso, Vector3((w * 0.55) * side, 0.85, 0), "arm%d" % (0 if side < 0 else 1))
		j["arm%d" % (0 if side < 0 else 1)] = sh
		MeshLib.part(sh, MeshLib.capsule(0.13 * w / 0.75, 0.8 * arm_l), body_mat, Vector3(0, -0.4 * arm_l, 0))
		MeshLib.part(sh, MeshLib.box(Vector3(0.28, 0.26, 0.3) * (w / 0.75)), acc_mat if rocky else body_mat, Vector3(0, -0.85 * arm_l, 0))
	for side in [-1.0, 1.0]:
		var lg := MeshLib.pivot(hip, Vector3(0.22 * side * w / 0.75, 0, 0), "leg%d" % (0 if side < 0 else 1))
		j["leg%d" % (0 if side < 0 else 1)] = lg
		MeshLib.part(lg, MeshLib.capsule(0.13 * w / 0.75, 0.85), body_mat, Vector3(0, -0.45, 0))
		_legs.append(lg)

func _build_tree(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	var torso := MeshLib.pivot(b, Vector3(0, 0.9, 0), "torso")
	j.torso = torso
	var bark := body_mat
	MeshLib.part(torso, MeshLib.cyl(0.28, 0.42, 1.6, 8), bark, Vector3(0, 0.6, 0))
	var head := MeshLib.pivot(torso, Vector3(0, 1.45, -0.1), "head")
	j.head = head
	_eyes(head, -0.3, 0.0, 0.18, glow_mat)
	for i in int(_feat("antlers", 4)):
		var side := -1.0 if i % 2 == 0 else 1.0
		var br := MeshLib.pivot(head, Vector3(0.12 * side, 0.1, 0), "branch%d" % i)
		br.rotation = Vector3(-0.3, 0, -0.6 * side - 0.2 * (i / 2) * side)
		MeshLib.part(br, MeshLib.cyl(0.02, 0.06, 0.7, 5), bark, Vector3(0, 0.35, 0))
		MeshLib.part(br, MeshLib.sphere(0.18, 6, 4), acc_mat, Vector3(0, 0.75, 0))
	for side in [-1.0, 1.0]:
		var arm := MeshLib.pivot(torso, Vector3(0.38 * side, 1.1, 0), "arm%d" % (0 if side < 0 else 1))
		j["arm%d" % (0 if side < 0 else 1)] = arm
		MeshLib.part(arm, MeshLib.cyl(0.06, 0.12, 1.1, 6), bark, Vector3(0, -0.55, 0))
		for k in 3:
			MeshLib.part(arm, MeshLib.cyl(0.0, 0.03, 0.3, 4), bark, Vector3(0.05 * (k - 1), -1.1, 0), Vector3(0, 0, (k - 1) * 30))
	for side in [-1.0, 1.0]:
		var lg := MeshLib.pivot(torso, Vector3(0.2 * side, 0, 0), "leg%d" % (0 if side < 0 else 1))
		j["leg%d" % (0 if side < 0 else 1)] = lg
		MeshLib.part(lg, MeshLib.cyl(0.1, 0.16, 0.9, 6), bark, Vector3(0, -0.45, 0))
		for k in 3:
			MeshLib.part(lg, MeshLib.cyl(0.03, 0.06, 0.4, 4), bark, Vector3(0, -0.9, 0), Vector3(60, k * 120, 0))
		_legs.append(lg)
	if int(_feat("growths", 0)) > 0:
		for i in int(_feat("growths", 0)):
			var nm := "growth%d" % i
			var g := MeshLib.pivot(torso, Vector3((i % 2 - 0.5) * 0.5, 0.5 + 0.3 * i, -0.3), nm)
			MeshLib.part(g, MeshLib.sphere(0.16, 8, 6), glow_mat)
			parts[nm] = g

func _build_blob2(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	var torso := MeshLib.pivot(b, Vector3(0, 0.45, 0), "torso")
	j.torso = torso
	var c: Color = look.get("body", Color(0.5, 0.6, 0.4))
	var m := MeshLib.mat(Color(c.r, c.g, c.b, 0.82), 0.0, 0.15, 0.3)
	var sq: float = float(_feat("squash", 0.85))
	MeshLib.part(torso, MeshLib.sphere(0.5, 12, 8), m, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, sq, 1.0))
	MeshLib.part(torso, MeshLib.sphere(0.18, 8, 6), glow_mat if _feat("core", true) else acc_mat, Vector3(0, 0, 0))
	if _feat("rocky", false):
		for i in 5:
			MeshLib.part(torso, MeshLib.box(Vector3(0.22, 0.16, 0.2)), acc_mat, Vector3(cos(i * 1.3) * 0.32, 0.25, sin(i * 1.3) * 0.32), Vector3(randf() * 40, randf() * 360, 0))
	_crystals(torso, Vector3(0, 0.3, 0), 0.25, glow_mat)
	_eyes(torso, -0.42, 0.15, 0.25, MeshLib.mat(Color(0.05, 0.05, 0.05)))

func _build_orb(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	_hover = float(_feat("hover", 1.3))
	var torso := MeshLib.pivot(b, Vector3(0, _hover, 0), "torso")
	j.torso = torso
	var core_r: float = float(_feat("core_r", 0.3))
	MeshLib.part(torso, MeshLib.sphere(core_r, 12, 8), glow_mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	MeshLib.part(torso, MeshLib.sphere(core_r * 1.35, 10, 6), MeshLib.mat(Color(look.get("body", Color(0.5, 0.5, 0.6)).r, look.get("body", Color(0.5, 0.5, 0.6)).g, look.get("body", Color(0.5, 0.5, 0.6)).b, 0.35), 0.0, 0.2, 0.6, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	_orbit = MeshLib.pivot(torso, Vector3.ZERO, "orbit")
	var shards := int(_feat("shards", 6))
	for i in shards:
		var a := TAU * i / maxf(1.0, shards)
		MeshLib.part(_orbit, MeshLib.box(Vector3(0.1, 0.22, 0.06)) if not _feat("gears", false) else MeshLib.cyl(0.1, 0.1, 0.04, 8), acc_mat, Vector3(cos(a) * core_r * 2.2, sin(a * 2.0) * 0.12, sin(a) * core_r * 2.2), Vector3(randf() * 90, randf() * 360, 0))
	if _feat("ring", false):
		MeshLib.part(torso, MeshLib.torus(core_r * 1.9, core_r * 2.05), glow_mat, Vector3.ZERO, Vector3(80, 0, 0), Vector3.ONE, false)
	var light := OmniLight3D.new()
	light.light_color = look.get("glow", Color(0.6, 0.8, 1.0))
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.shadow_enabled = false
	torso.add_child(light)

func _build_construct(b: Node3D, acc_mat: Material, glow_mat: Material) -> void:
	var legs := int(_feat("legs", 4))
	var torso := MeshLib.pivot(b, Vector3(0, 0.7, 0), "torso")
	j.torso = torso
	var L: float = float(_feat("len", 0.9))
	MeshLib.part(torso, MeshLib.box(Vector3(0.55, 0.35, L)), body_mat)
	MeshLib.part(torso, MeshLib.box(Vector3(0.45, 0.1, L * 0.8)), acc_mat, Vector3(0, 0.22, 0))
	if _feat("chimney", false):
		MeshLib.part(torso, MeshLib.cyl(0.07, 0.07, 0.4, 8), acc_mat, Vector3(0.15, 0.4, L * 0.3))
	var head := MeshLib.pivot(torso, Vector3(0, 0.1, -L * 0.55), "head")
	j.head = head
	MeshLib.part(head, MeshLib.box(Vector3(0.3, 0.22, 0.25)), body_mat)
	MeshLib.part(head, MeshLib.box(Vector3(0.22, 0.05, 0.02)), glow_mat, Vector3(0, 0.02, -0.13), Vector3.ZERO, Vector3.ONE, false)
	if _feat("drill", false):
		var dr := MeshLib.pivot(head, Vector3(0, -0.02, -0.15), "drill")
		MeshLib.part(dr, MeshLib.cyl(0.0, 0.14, 0.5, 8), acc_mat, Vector3(0, 0, -0.25), Vector3(-90, 0, 0))
		j.drill = dr
	if int(_feat("gears", 0)) > 0:
		for i in int(_feat("gears", 0)):
			var g := MeshLib.pivot(torso, Vector3(0.3 * (1 if i % 2 == 0 else -1), 0.0, -L * 0.2 + i * 0.25), "gear%d" % i)
			MeshLib.part(g, MeshLib.cyl(0.15, 0.15, 0.05, 10), acc_mat, Vector3.ZERO, Vector3(0, 0, 90))
			j["gear%d" % i] = g
	for i in legs:
		var side := -1.0 if i % 2 == 0 else 1.0
		var row := float(i / 2) / maxf(1.0, legs / 2 - 1) if legs > 2 else 0.5
		var leg := MeshLib.pivot(torso, Vector3(0.32 * side, -0.1, lerpf(-L * 0.4, L * 0.4, row)), "leg%d" % i)
		j["leg%d" % i] = leg
		MeshLib.part(leg, MeshLib.cyl(0.04, 0.04, 0.6, 6), acc_mat, Vector3(0.05 * side, -0.3, 0), Vector3(0, 0, 10 * side))
		MeshLib.part(leg, MeshLib.box(Vector3(0.1, 0.05, 0.14)), body_mat, Vector3(0.1 * side, -0.6, 0))
		_legs.append(leg)

# ------------------------------------------------------------------ parts
## A boss part is destroyed: it falls off, the cracks under it glow.
func break_part(p: String) -> void:
	if not parts.has(p) or broken.has(p):
		return
	broken[p] = true
	var n: Node3D = parts[p]
	if is_instance_valid(n):
		var gp := n.global_position
		var tw := n.create_tween()
		tw.tween_property(n, "position", n.position + Vector3(0, -0.6, 0.3), 0.35).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.1, 0.35)
		tw.tween_callback(n.queue_free)
		VFX.burst(gp, Color(0.5, 0.45, 0.38), 12, 0.3)
		if n.get_parent() is Node3D:
			MeshLib.part(n.get_parent(), MeshLib.box(Vector3(0.3, 0.05, 0.25)), crack_mat, n.position, Vector3.ZERO, Vector3.ONE, false)

func parts_left() -> int:
	return parts.size() - broken.size()

# ------------------------------------------------------------------ animation
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not dead:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d2 := cam.global_position.distance_squared_to(global_position)
			if d2 > 1600.0:
				_lod_acc += delta
				if _lod_acc < (0.066 if d2 < 4900.0 else 0.15):
					return
				delta = _lod_acc
				_lod_acc = 0.0
	_t += delta
	hit_t = maxf(0.0, hit_t - delta)
	var sp := clampf(move_speed, 0.0, 2.0)
	_phase += delta * (4.0 + 6.0 * sp)
	var s := sin(_phase)
	var body: Node3D = j.body
	if dead:
		_dead_t = minf(1.0, _dead_t + delta * 1.5)
		match plan:
			"flyer", "orb":
				body.position.y = lerpf(0.0, -_hover, _dead_t)
				body.rotation.z = _dead_t * 1.2
			"blob":
				body.scale = Vector3(1.0 + _dead_t, maxf(0.1, 1.0 - _dead_t), 1.0 + _dead_t)
			"giant", "tree":
				body.rotation.x = lerpf(0.0, -1.45, _dead_t)
			_:
				body.rotation.z = lerpf(0.0, 1.5, _dead_t)
		return
	var atk := 0.0
	if action != "":
		action_p += delta * 2.2
		atk = sin(clampf(action_p, 0.0, 1.0) * PI)
		if action_p >= 1.0:
			action = ""
	var torso: Node3D = j.torso
	match plan:
		"quad", "drake":
			for i in _legs.size():
				var ph := s if (i % 4) in [0, 3] else -s
				_legs[i].rotation.x = ph * 0.6 * minf(sp, 1.3)
			if j.has("tail"):
				j.tail.rotation.y = sin(_t * 3.0) * 0.3
			torso.position.z = -atk * 0.4
			j.head.rotation.x = -atk * 0.5 + hit_t
			for w in _wings:
				w[0].rotation.z = (sin(_t * (6.0 if sp > 0.2 else 2.0)) * 0.35 + 0.15) * w[1]
		"arach", "insect":
			for i in _legs.size():
				var ph2 := s if i % 2 == 0 else -s
				_legs[i].rotation.y = ph2 * 0.35 * minf(sp, 1.4)
				_legs[i].rotation.x = maxf(0.0, ph2) * 0.25 * sp
			torso.rotation.x = -atk * 0.35 + hit_t
			if j.has("claw0"):
				j.claw0.rotation.y = atk * 0.6
				j.claw1.rotation.y = -atk * 0.6
		"worm":
			for i in _segs.size():
				_segs[i].position.x = sin(_t * 4.0 + i * 0.7) * 0.12 * (0.3 + sp)
				_segs[i].position.y = maxf(0.0, sin(_t * 2.0 + i * 0.5)) * 0.05
			torso.position.y = float(_feat("girth", 0.25)) + atk * 0.5
			j.head.rotation.x = -atk * 0.6
		"flyer":
			for w in _wings:
				w[0].rotation.z = sin(_t * 14.0) * 0.6 * w[1]
			torso.position.y = _hover + sin(_t * 3.0) * 0.12 - atk * 0.6
			torso.rotation.x = 0.2 * minf(sp, 1.0) + atk * 0.5
		"giant":
			j.leg0.rotation.x = s * 0.45 * minf(sp, 1.2)
			j.leg1.rotation.x = -s * 0.45 * minf(sp, 1.2)
			j.arm0.rotation.x = -s * 0.25 * sp - atk * 1.9
			j.arm1.rotation.x = s * 0.25 * sp - atk * 1.6
			j.hip.position.y = 0.95 + absf(s) * 0.05 * sp - atk * 0.1
			for k in 4:
				if j.has("gear%d" % k):
					j["gear%d" % k].rotation.z += delta * (3.0 + sp * 6.0) * (1 if k % 2 == 0 else -1)
		"tree":
			j.leg0.rotation.x = s * 0.25 * minf(sp, 1.0)
			j.leg1.rotation.x = -s * 0.25 * minf(sp, 1.0)
			j.arm0.rotation.x = sin(_t * 1.5) * 0.1 - atk * 1.4
			j.arm1.rotation.x = sin(_t * 1.5 + 1.0) * 0.1 - atk * 1.2
			torso.rotation.z = sin(_t * 0.8) * 0.04
		"blob":
			var sq2 := sin(_t * 6.0) * 0.08 * (0.5 + sp)
			torso.scale = Vector3(1.0 + sq2 + atk * 0.3, 1.0 - sq2 - atk * 0.2, 1.0 + sq2 + atk * 0.3)
			torso.position.y = 0.45 + absf(sin(_t * 6.0)) * 0.15 * sp
		"orb":
			torso.position.y = _hover + sin(_t * 2.0) * 0.15
			if _orbit:
				_orbit.rotation.y += delta * (1.5 + atk * 6.0)
				_orbit.scale = Vector3.ONE * (1.0 + atk * 0.4)
		"construct":
			for i in _legs.size():
				_legs[i].rotation.x = (s if i % 2 == 0 else -s) * 0.4 * minf(sp, 1.3)
			torso.position.y = 0.7 + absf(s) * 0.03 * sp
			j.head.rotation.x = -atk * 0.4 + hit_t
			if j.has("drill"):
				j.drill.rotation.z += delta * (4.0 + atk * 30.0)
			for k in 4:
				if j.has("gear%d" % k):
					j["gear%d" % k].rotation.x += delta * 4.0

## Re-tint the glowing parts (rare variants: Альфа, Кристальный…).
func set_glow(c: Color) -> void:
	for m in [glow_m, crack_mat]:
		if m is StandardMaterial3D:
			(m as StandardMaterial3D).albedo_color = c
			(m as StandardMaterial3D).emission = c
