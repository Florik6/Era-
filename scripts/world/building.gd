class_name Building
extends Node3D
## Walk-in building with an era-specific style. Roof and upper walls cut away
## when the player is inside (no loading screens). Door is a Destructible that
## swings open for nearby actors. Optional secret room (behind a cracked wall)
## and a cellar reached through a trapdoor. Exposes navigation points for AI.

const CELLAR_Y := 45.0

static var _mesh_cache := {}

var id := ""
var kind := "house"
var era := 0
var w := 7.0
var d := 6.0
var wall_h := 3.2
var door_x := 0.0
var has_secret := false
var has_cellar := false
var settlement_id := ""
var state: Dictionary = {}
var lvl := 1
var door_out := Vector3.ZERO
var door_in := Vector3.ZERO
var interior_points: Array = []
var viewer: Node3D = null          # optional override for roof hiding (tests)
var _roof: MeshInstance3D
var _upper: MeshInstance3D
var _check := 0.0
var _inside := false
var _rng := RandomNumberGenerator.new()

func configure(b: Dictionary, era_i: int, st: Dictionary, settlement: String = "", level: int = 1) -> void:
	id = str(b.id)
	kind = str(b.kind)
	era = era_i
	state = st
	settlement_id = settlement
	lvl = level
	var sz: Vector2 = b.size
	w = sz.x
	d = sz.y
	_rng.seed = hash(id)
	match kind:
		"tower": wall_h = 6.5
		"hall": wall_h = 4.2
		"warehouse": wall_h = 4.0
		_: wall_h = 3.2
	if era >= 3 and kind in ["house", "shop", "inn"]:
		wall_h = 3.4
	door_x = 0.0
	has_secret = kind in ["house", "hall", "inn"] and _rng.randf() < 0.28 and w >= 6.0
	has_cellar = kind in ["house", "inn", "shop"] and _rng.randf() < 0.22 and not has_secret

func _ready() -> void:
	add_to_group("buildings")

## Builds all geometry. Must be called after the node is in the tree and positioned.
func build() -> void:
	var variant := _rng.randi() % 3
	var key := "%d|%s|%d|%d|%d|%s" % [era, kind, int(w * 10), int(d * 10), variant, has_secret]
	var meshes: Array
	if _mesh_cache.has(key):
		meshes = _mesh_cache[key]
	else:
		meshes = _make_meshes(variant)
		_mesh_cache[key] = meshes
	var base := MeshInstance3D.new()
	base.mesh = meshes[0]
	add_child(base)
	_upper = MeshInstance3D.new()
	_upper.mesh = meshes[1]
	add_child(_upper)
	_roof = MeshInstance3D.new()
	_roof.mesh = meshes[2]
	add_child(_roof)
	_build_collision()
	_build_dynamic()
	if has_cellar:
		_build_cellar()
	door_out = to_global(Vector3(door_x, 0.0, d * 0.5 + 1.4))
	door_in = to_global(Vector3(door_x, 0.0, d * 0.5 - 1.3))
	interior_points.clear()
	for p in [Vector3(-w * 0.25, 0, -d * 0.2), Vector3(w * 0.25, 0, -d * 0.2), Vector3(0, 0, 0), Vector3(-w * 0.2, 0, d * 0.2), Vector3(w * 0.2, 0, d * 0.2)]:
		interior_points.append(to_global(p))

# ---------------------------------------------------------------- style
func _palette(variant: int) -> Dictionary:
	match era:
		0:
			var walls := [Color(0.86, 0.8, 0.66), Color(0.62, 0.6, 0.57), Color(0.8, 0.74, 0.6)]
			var roofs := [Color(0.62, 0.5, 0.3), Color(0.36, 0.34, 0.4), Color(0.58, 0.28, 0.2)]
			return {"wall": walls[variant], "trim": Color(0.34, 0.23, 0.13), "roof": roofs[variant], "floor": Color(0.45, 0.33, 0.2), "roof_type": "steep", "beams": variant != 1, "window": Color(0.25, 0.2, 0.15)}
		1:
			var walls1 := [Color(0.9, 0.74, 0.5), Color(0.93, 0.87, 0.72), Color(0.82, 0.52, 0.36)]
			return {"wall": walls1[variant], "trim": Color(0.95, 0.92, 0.85), "roof": Color(0.76, 0.38, 0.22), "floor": Color(0.62, 0.42, 0.3), "roof_type": "low", "beams": false, "window": Color(0.2, 0.42, 0.35)}
		2:
			var walls2 := [Color(0.56, 0.28, 0.2), Color(0.46, 0.25, 0.2), Color(0.42, 0.4, 0.38)]
			return {"wall": walls2[variant], "trim": Color(0.3, 0.28, 0.26), "roof": Color(0.22, 0.21, 0.21), "floor": Color(0.35, 0.3, 0.26), "roof_type": "flat", "beams": false, "window": Color(0.18, 0.22, 0.25), "chimney": true}
		3:
			var walls3 := [Color(0.78, 0.78, 0.77), Color(0.62, 0.64, 0.67), Color(0.86, 0.82, 0.74)]
			return {"wall": walls3[variant], "trim": Color(0.5, 0.52, 0.55), "roof": Color(0.4, 0.4, 0.42), "floor": Color(0.55, 0.55, 0.58), "roof_type": "flat", "beams": false, "window": Color(0.35, 0.55, 0.75), "glass": true}
		_:
			var walls4 := [Color(0.22, 0.24, 0.3), Color(0.32, 0.34, 0.4), Color(0.8, 0.82, 0.88)]
			var neon := [Color(0.25, 0.9, 1.0), Color(1.0, 0.25, 0.8), Color(0.5, 1.0, 0.4)]
			return {"wall": walls4[variant], "trim": Color(0.15, 0.15, 0.2), "roof": Color(0.18, 0.18, 0.22), "floor": Color(0.25, 0.26, 0.3), "roof_type": "flat", "beams": false, "window": Color(0.4, 0.8, 1.0), "glass": true, "neon": neon[variant]}

func _make_meshes(variant: int) -> Array:
	var pal := _palette(variant)
	var base := Props.Merger.new()
	var upper := Props.Merger.new()
	var roof := Props.Merger.new()
	var wall_m := MeshLib.mat(pal.wall, 0.4 if era == 4 else 0.0, 0.8)
	var trim_m := MeshLib.mat(pal.trim)
	var floor_m := MeshLib.mat(pal.floor)
	var stone_m := MeshLib.mat(Color(0.5, 0.48, 0.45))
	var t := 0.3
	var low := 1.1
	var up_h := wall_h - low
	# foundation + floor
	base.part(MeshLib.box(Vector3(w + 0.4, 1.6, d + 0.4)), stone_m, Vector3(0, -0.79, 0))
	base.part(MeshLib.box(Vector3(w - 0.1, 0.06, d - 0.1)), floor_m, Vector3(0, 0.0, 0))
	# walls: back (maybe split for secret), left, right, front split around the door
	var gap := 1.7
	var segs: Array = []   # [center_x, center_z, len_x, len_z]
	if has_secret:
		var side := (w - 1.8) * 0.5
		segs.append([-(w * 0.5) + side * 0.5, -d * 0.5, side, t])
		segs.append([(w * 0.5) - side * 0.5, -d * 0.5, side, t])
	else:
		segs.append([0.0, -d * 0.5, w, t])
	segs.append([-w * 0.5, 0.0, t, d])
	segs.append([w * 0.5, 0.0, t, d])
	var fl := (w - gap) * 0.5
	segs.append([-(w * 0.5) + fl * 0.5, d * 0.5, fl, t])
	segs.append([(w * 0.5) - fl * 0.5, d * 0.5, fl, t])
	for s in segs:
		base.part(MeshLib.box(Vector3(s[2], low, s[3])), wall_m, Vector3(s[0], low * 0.5, s[1]))
		upper.part(MeshLib.box(Vector3(s[2], up_h, s[3])), wall_m, Vector3(s[0], low + up_h * 0.5, s[1]))
	if has_secret:
		# the hidden room behind the back wall
		var sd := 2.6
		var bz := -d * 0.5 - sd * 0.5
		base.part(MeshLib.box(Vector3(3.2, 0.06, sd)), floor_m, Vector3(0, 0.0, bz))
		base.part(MeshLib.box(Vector3(3.4, 1.6, sd + 0.2)), stone_m, Vector3(0, -0.79, bz))
		for s2 in [[-1.6, bz, t, sd], [1.6, bz, t, sd], [0.0, -d * 0.5 - sd, 3.4, t]]:
			base.part(MeshLib.box(Vector3(s2[2], low, s2[3])), wall_m, Vector3(s2[0], low * 0.5, s2[1]))
			upper.part(MeshLib.box(Vector3(s2[2], up_h, s2[3])), wall_m, Vector3(s2[0], low + up_h * 0.5, s2[1]))
		roof.part(MeshLib.box(Vector3(3.6, 0.25, sd + 0.3)), MeshLib.mat(pal.roof), Vector3(0, wall_h + 0.12, bz))
	# lintel over the door
	upper.part(MeshLib.box(Vector3(gap, wall_h - 2.4, t)), wall_m, Vector3(door_x, 2.4 + (wall_h - 2.4) * 0.5, d * 0.5))
	# door frame
	base.part(MeshLib.box(Vector3(0.12, 2.45, t + 0.08)), trim_m, Vector3(door_x - gap * 0.5, 1.22, d * 0.5))
	base.part(MeshLib.box(Vector3(0.12, 2.45, t + 0.08)), trim_m, Vector3(door_x + gap * 0.5, 1.22, d * 0.5))
	upper.part(MeshLib.box(Vector3(gap + 0.2, 0.14, t + 0.08)), trim_m, Vector3(door_x, 2.45, d * 0.5))
	# corner posts / beams (timber framing)
	if pal.get("beams", false):
		for cx in [-w * 0.5, w * 0.5]:
			for cz in [-d * 0.5, d * 0.5]:
				base.part(MeshLib.box(Vector3(0.22, low, 0.22)), trim_m, Vector3(cx, low * 0.5, cz))
				upper.part(MeshLib.box(Vector3(0.22, up_h, 0.22)), trim_m, Vector3(cx, low + up_h * 0.5, cz))
		upper.part(MeshLib.box(Vector3(w + 0.05, 0.16, t + 0.06)), trim_m, Vector3(0, wall_h - 0.1, d * 0.5))
		upper.part(MeshLib.box(Vector3(w + 0.05, 0.16, t + 0.06)), trim_m, Vector3(0, wall_h - 0.1, -d * 0.5))
		upper.part(MeshLib.box(Vector3(w + 0.05, 0.12, t + 0.06)), trim_m, Vector3(0, 1.15, d * 0.5))
	# windows on side walls and the front
	var win_m := MeshLib.mat(pal.window, 0.3 if pal.get("glass", false) else 0.0, 0.3, 0.5 if era >= 3 else 0.0)
	var wy := low + minf(1.2, up_h * 0.5)
	var nwin := maxi(1, int(d / 3.5))
	for i in nwin:
		var z := -d * 0.5 + d * (i + 0.5) / nwin
		for sx in [-1.0, 1.0]:
			upper.part(MeshLib.box(Vector3(0.06, 0.9, 0.8)), win_m, Vector3(sx * (w * 0.5 + 0.16), wy, z))
	for sx2 in [-1.0, 1.0]:
		if fl > 1.6:
			upper.part(MeshLib.box(Vector3(0.8, 0.9, 0.06)), win_m, Vector3(sx2 * (gap * 0.5 + fl * 0.5), wy, d * 0.5 + 0.16))
	if kind == "tower":
		for i in 2:
			upper.part(MeshLib.box(Vector3(0.6, 0.8, 0.06)), win_m, Vector3(0, low + 2.8 + i * 1.6, d * 0.5 + 0.16))
	if pal.has("neon"):
		var nm := MeshLib.mat(pal.neon, 0.0, 0.4, 3.0)
		upper.part(MeshLib.box(Vector3(w + 0.1, 0.08, 0.08)), nm, Vector3(0, wall_h - 0.05, d * 0.5 + 0.18))
		upper.part(MeshLib.box(Vector3(0.08, up_h, 0.08)), nm, Vector3(-w * 0.5 - 0.15, low + up_h * 0.5, d * 0.5 + 0.15))
		upper.part(MeshLib.box(Vector3(0.08, up_h, 0.08)), nm, Vector3(w * 0.5 + 0.15, low + up_h * 0.5, d * 0.5 + 0.15))
	# shop signs
	if kind in ["inn", "shop", "smithy"]:
		var sc: Color = {"inn": Color(0.75, 0.55, 0.2), "shop": Color(0.25, 0.45, 0.7), "smithy": Color(0.35, 0.35, 0.38)}[kind]
		upper.part(MeshLib.box(Vector3(1.0, 0.6, 0.06)), MeshLib.mat(sc, 0.0, 0.6, 0.6 if era >= 3 else 0.0), Vector3(door_x + gap * 0.5 + 0.7, 2.6, d * 0.5 + 0.35))
	# roof
	var roof_m := MeshLib.mat(pal.roof, 0.3 if era == 4 else 0.0, 0.8)
	match pal.roof_type:
		"steep", "low":
			var rh := (minf(w, d) * (0.62 if pal.roof_type == "steep" else 0.36))
			if kind == "tower":
				roof.part(MeshLib.cyl(0.0, maxf(w, d) * 0.75, rh * 1.5, 8), roof_m, Vector3(0, wall_h + rh * 0.75, 0), Vector3(0, 22.5, 0))
			elif w >= d:
				roof.part(MeshLib.prism(Vector3(d + 0.9, rh, w + 0.7)), roof_m, Vector3(0, wall_h + rh * 0.5, 0), Vector3(0, 90, 0))
				for sx3 in [-1.0, 1.0]:
					roof.part(MeshLib.prism(Vector3(d - 0.2, rh * 0.9, 0.25)), wall_m, Vector3(sx3 * (w * 0.5 - 0.05), wall_h + rh * 0.45, 0), Vector3(0, 90, 0))
			else:
				roof.part(MeshLib.prism(Vector3(w + 0.9, rh, d + 0.7)), roof_m, Vector3(0, wall_h + rh * 0.5, 0))
				for sz in [-1.0, 1.0]:
					roof.part(MeshLib.prism(Vector3(w - 0.2, rh * 0.9, 0.25)), wall_m, Vector3(0, wall_h + rh * 0.45, sz * (d * 0.5 - 0.05)))
			if kind == "smithy" or (kind == "inn" and era == 0):
				roof.part(MeshLib.box(Vector3(0.7, 1.6, 0.7)), stone_m, Vector3(w * 0.3, wall_h + rh * 0.6, -d * 0.2))
		_:
			roof.part(MeshLib.box(Vector3(w + 0.3, 0.3, d + 0.3)), roof_m, Vector3(0, wall_h + 0.15, 0))
			for s3 in [[0.0, d * 0.5 + 0.1, w + 0.4, 0.2], [0.0, -d * 0.5 - 0.1, w + 0.4, 0.2], [w * 0.5 + 0.1, 0.0, 0.2, d + 0.4], [-w * 0.5 - 0.1, 0.0, 0.2, d + 0.4]]:
				roof.part(MeshLib.box(Vector3(s3[2], 0.45, s3[3])), MeshLib.mat(pal.wall.darkened(0.15)), Vector3(s3[0], wall_h + 0.4, s3[1]))
			if pal.get("chimney", false) or kind == "smithy":
				roof.part(MeshLib.cyl(0.35, 0.45, 2.8, 8), MeshLib.mat(Color(0.5, 0.26, 0.18)), Vector3(w * 0.3, wall_h + 1.5, -d * 0.25))
			if era == 3:
				roof.part(MeshLib.box(Vector3(1.2, 0.7, 1.0)), MeshLib.mat(Color(0.7, 0.72, 0.74), 0.5, 0.5), Vector3(-w * 0.2, wall_h + 0.65, d * 0.1))
			if era == 4:
				roof.part(MeshLib.cyl(0.04, 0.05, 2.5, 4), MeshLib.mat(Color(0.5, 0.5, 0.55), 0.8, 0.3), Vector3(w * 0.3, wall_h + 1.5, 0))
				roof.part(MeshLib.sphere(0.12, 6, 4), MeshLib.mat(pal.neon, 0.0, 0.4, 3.0), Vector3(w * 0.3, wall_h + 2.8, 0))
	_static_furniture(base, pal)
	return [base.commit(), upper.commit(), roof.commit()]

func _static_furniture(m: Props.Merger, pal: Dictionary) -> void:
	var wood := MeshLib.mat(Color(0.45, 0.3, 0.17) if era <= 2 else (Color(0.55, 0.56, 0.6) if era == 3 else Color(0.3, 0.32, 0.4)), 0.5 if era >= 3 else 0.0, 0.6)
	var cloth := MeshLib.mat(Color(0.65, 0.2, 0.2) if era < 4 else Color(0.2, 0.5, 0.8))
	var stone := MeshLib.mat(Color(0.45, 0.43, 0.4))
	var ember := MeshLib.mat(Color(1.0, 0.45, 0.12), 0.0, 0.5, 3.0)
	var screen := MeshLib.mat(Color(0.3, 0.8, 1.0), 0.0, 0.4, 2.0)
	var hw := w * 0.5
	var hd := d * 0.5
	m.part(MeshLib.box(Vector3(minf(w * 0.5, 3.0), 0.02, minf(d * 0.45, 2.4))), cloth, Vector3(0, 0.04, 0.1))
	match kind:
		"house":
			m.part(MeshLib.box(Vector3(1.0, 0.45, 2.0)), wood, Vector3(-hw + 0.75, 0.23, -hd + 1.2))
			m.part(MeshLib.box(Vector3(0.9, 0.12, 1.4)), MeshLib.mat(Color(0.9, 0.88, 0.8)), Vector3(-hw + 0.75, 0.5, -hd + 1.45))
			if era <= 2:
				m.part(MeshLib.box(Vector3(1.4, 1.2, 0.6)), stone, Vector3(hw - 1.0, 0.6, -hd + 0.45))
				m.part(MeshLib.box(Vector3(0.8, 0.3, 0.3)), ember, Vector3(hw - 1.0, 0.3, -hd + 0.7))
			else:
				m.part(MeshLib.box(Vector3(1.4, 0.75, 0.6)), wood, Vector3(hw - 1.0, 0.38, -hd + 0.45))
				m.part(MeshLib.box(Vector3(0.6, 0.4, 0.05)), screen, Vector3(hw - 1.0, 1.0, -hd + 0.35))
		"inn":
			m.part(MeshLib.box(Vector3(w * 0.5, 1.05, 0.6)), wood, Vector3(0, 0.52, -hd + 1.4))
			for i in 3:
				m.part(MeshLib.cyl(0.35, 0.38, 0.9, 8), MeshLib.mat(Color(0.48, 0.32, 0.18)), Vector3(-w * 0.2 + i * w * 0.2, 0.45, -hd + 0.5))
			m.part(MeshLib.box(Vector3(1.4, 1.2, 0.6)), stone, Vector3(hw - 1.0, 0.6, -hd + 0.45))
			m.part(MeshLib.box(Vector3(0.8, 0.3, 0.3)), ember, Vector3(hw - 1.0, 0.3, -hd + 0.7))
		"shop":
			m.part(MeshLib.box(Vector3(w * 0.55, 1.0, 0.6)), wood, Vector3(0, 0.5, -hd + 1.3))
			if era >= 3:
				m.part(MeshLib.box(Vector3(0.5, 0.35, 0.05)), screen, Vector3(0.6, 1.25, -hd + 1.2))
		"smithy":
			m.part(MeshLib.box(Vector3(0.5, 0.7, 0.9)), MeshLib.mat(Color(0.2, 0.2, 0.22), 0.6, 0.4), Vector3(0.5, 0.35, -0.3))
			m.part(MeshLib.box(Vector3(1.6, 1.0, 1.1)), stone, Vector3(hw - 1.1, 0.5, -hd + 0.75))
			m.part(MeshLib.box(Vector3(1.1, 0.12, 0.7)), ember, Vector3(hw - 1.1, 1.02, -hd + 0.75))
		"hall":
			m.part(MeshLib.box(Vector3(1.4, 0.8, d * 0.55)), wood, Vector3(0, 0.4, -0.3))
			m.part(MeshLib.box(Vector3(1.2, 1.6, 0.8)), MeshLib.mat(Color(0.6, 0.45, 0.2), 0.6, 0.4), Vector3(0, 0.8, -hd + 0.7))
			for sx in [-1.0, 1.0]:
				m.part(MeshLib.box(Vector3(0.05, 1.8, 0.9)), cloth, Vector3(sx * (hw - 0.2), 2.2, -0.5))
		"tower":
			m.part(MeshLib.box(Vector3(0.5, 0.08, 2.6)), wood, Vector3(hw - 0.6, 1.3, 0), Vector3(-55, 0, 0))
			m.part(MeshLib.box(Vector3(1.6, 1.4, 0.3)), wood, Vector3(-hw + 1.1, 0.7, -hd + 0.4))
		"warehouse":
			m.part(MeshLib.box(Vector3(w * 0.7, 0.15, 1.2)), wood, Vector3(0, 0.08, -hd + 1.0))

func _build_collision() -> void:
	var sb := StaticBody3D.new()
	sb.name = "Walls"
	sb.collision_layer = 1
	sb.collision_mask = 0
	add_child(sb)
	var t := 0.3
	var gap := 1.7
	var fl := (w - gap) * 0.5
	var boxes: Array = []
	boxes.append([Vector3(0, -0.4, 0), Vector3(w, 0.84, d)])
	if has_secret:
		var side := (w - 1.8) * 0.5
		boxes.append([Vector3(-(w * 0.5) + side * 0.5, wall_h * 0.5, -d * 0.5), Vector3(side, wall_h, t)])
		boxes.append([Vector3((w * 0.5) - side * 0.5, wall_h * 0.5, -d * 0.5), Vector3(side, wall_h, t)])
		var sd := 2.6
		var bz := -d * 0.5 - sd * 0.5
		boxes.append([Vector3(0, -0.4, bz), Vector3(3.2, 0.84, sd)])
		boxes.append([Vector3(-1.6, wall_h * 0.5, bz), Vector3(t, wall_h, sd)])
		boxes.append([Vector3(1.6, wall_h * 0.5, bz), Vector3(t, wall_h, sd)])
		boxes.append([Vector3(0, wall_h * 0.5, -d * 0.5 - sd), Vector3(3.4, wall_h, t)])
	else:
		boxes.append([Vector3(0, wall_h * 0.5, -d * 0.5), Vector3(w, wall_h, t)])
	boxes.append([Vector3(-w * 0.5, wall_h * 0.5, 0), Vector3(t, wall_h, d)])
	boxes.append([Vector3(w * 0.5, wall_h * 0.5, 0), Vector3(t, wall_h, d)])
	boxes.append([Vector3(-(w * 0.5) + fl * 0.5, wall_h * 0.5, d * 0.5), Vector3(fl, wall_h, t)])
	boxes.append([Vector3((w * 0.5) - fl * 0.5, wall_h * 0.5, d * 0.5), Vector3(fl, wall_h, t)])
	boxes.append([Vector3(door_x, 2.4 + (wall_h - 2.4) * 0.5, d * 0.5), Vector3(gap, wall_h - 2.4, t)])
	# solid furniture
	var hw := w * 0.5
	var hd := d * 0.5
	match kind:
		"house":
			boxes.append([Vector3(-hw + 0.75, 0.25, -hd + 1.2), Vector3(1.0, 0.5, 2.0)])
		"inn":
			boxes.append([Vector3(0, 0.52, -hd + 1.4), Vector3(w * 0.5, 1.05, 0.6)])
		"shop":
			boxes.append([Vector3(0, 0.5, -hd + 1.3), Vector3(w * 0.55, 1.0, 0.6)])
		"hall":
			boxes.append([Vector3(0, 0.4, -0.3), Vector3(1.4, 0.8, d * 0.55)])
		"smithy":
			boxes.append([Vector3(hw - 1.1, 0.5, -hd + 0.75), Vector3(1.6, 1.0, 1.1)])
	for b in boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		sb.add_child(cs)

func _free_spots() -> Array:
	var spots: Array = []
	var hw := w * 0.5
	var hd := d * 0.5
	var z := -hd + 1.0
	while z < hd - 1.6:
		for sx in [-1.0, 1.0]:
			spots.append(Vector3(sx * (hw - 0.65), 0.0, z))
		z += 1.3
	if w >= 8.0:
		spots.append(Vector3(-w * 0.2, 0, d * 0.05))
		spots.append(Vector3(w * 0.2, 0, d * 0.05))
	# remove spots taken by static furniture
	var out: Array = []
	for s in spots:
		if kind == "house" and s.x < 0 and s.z < -hd + 2.4:
			continue
		if kind in ["house", "inn"] and s.x > 0 and s.z < -hd + 1.2:
			continue
		if kind == "smithy" and s.x > 0 and s.z < -hd + 1.6:
			continue
		if kind in ["inn", "shop"] and absf(s.z - (-hd + 1.4)) < 0.7 and absf(s.x) < w * 0.3:
			continue
		out.append(s)
	return out

func _build_dynamic() -> void:
	var gap := 1.7
	# door
	var door := Destructible.new()
	door.configure("door", id + "_door", state, era, Vector3(gap - 0.06, 2.4, 0.12))
	door.position = Vector3(door_x, 0.0, d * 0.5)
	add_child(door)
	var spots := _free_spots()
	_shuffle(spots)
	var n_chest := 0
	match kind:
		"house": n_chest = 1 if _rng.randf() < 0.55 else 0
		"inn", "shop", "warehouse", "smithy": n_chest = 1 + (1 if _rng.randf() < 0.3 else 0)
		"hall", "tower": n_chest = 1 + (1 if _rng.randf() < 0.5 else 0)
	var tier := "rich" if kind == "hall" else "normal"
	for i in n_chest:
		if spots.is_empty():
			break
		var p: Vector3 = spots.pop_back()
		var c := Chest.new()
		c.configure("%s_ch%d" % [id, i], state, era, tier, lvl, _rng.randf())
		c.position = p
		c.rotation.y = -PI * 0.5 if p.x > 0 else PI * 0.5
		add_child(c)
	var n_dest: int = {"house": 2, "inn": 4, "shop": 3, "smithy": 2, "hall": 3, "tower": 3, "warehouse": 7}.get(kind, 2)
	for i in n_dest:
		if spots.is_empty():
			break
		var p2: Vector3 = spots.pop_back()
		var dk := "crate"
		var r := _rng.randf()
		match kind:
			"inn": dk = "table" if r < 0.6 else "barrel"
			"shop": dk = "shelf" if r < 0.6 else "crate"
			"house": dk = "table" if r < 0.4 else ("shelf" if r < 0.7 else "barrel")
			"hall": dk = "table" if r < 0.5 else "shelf"
			_: dk = "crate" if r < 0.6 else "barrel"
		var de := Destructible.new()
		de.configure(dk, "%s_d%d" % [id, i], state, era)
		if dk == "barrel" and era >= 1 and _rng.randf() < 0.2:
			de.explosive = true
		de.position = p2
		if dk == "shelf":
			de.rotation.y = -PI * 0.5 if p2.x > 0 else PI * 0.5
		add_child(de)
	if has_secret:
		var cw := Destructible.new()
		cw.configure("cracked_wall", id + "_crack", state, era, Vector3(1.8, wall_h, 0.32))
		cw.position = Vector3(0, 0, -d * 0.5)
		add_child(cw)
		var sc := Chest.new()
		sc.configure(id + "_secret", state, era, "rich", lvl + 1, 1.0)
		sc.position = Vector3(0, 0, -d * 0.5 - 1.6)
		add_child(sc)
	if has_cellar:
		var td := Trapdoor.new()
		td.building = self
		td.down = true
		var tp := Vector3(0.0, 0.0, -0.2)
		td.position = tp
		add_child(td)

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp

func _build_cellar() -> void:
	var c := Node3D.new()
	c.name = "Cellar"
	c.position = Vector3(0, CELLAR_Y, 0)
	add_child(c)
	var earth := MeshLib.mat(Color(0.08, 0.07, 0.06))
	var stone := MeshLib.mat(Color(0.4, 0.37, 0.34))
	var floor_m := MeshLib.mat(Color(0.3, 0.27, 0.24))
	var cw := 7.0
	var cd := 6.0
	for mi in [MeshLib.part(c, MeshLib.box(Vector3(46, 0.4, 46)), earth, Vector3(0, -0.25, 0)),
			MeshLib.part(c, MeshLib.box(Vector3(cw, 0.06, cd)), floor_m, Vector3(0, 0.0, 0))]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var walls := [[0.0, -cd * 0.5, cw, 0.4], [0.0, cd * 0.5, cw, 0.4], [-cw * 0.5, 0.0, 0.4, cd], [cw * 0.5, 0.0, 0.4, cd]]
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	c.add_child(sb)
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(cw, 0.4, cd)
	fcs.shape = fb
	fcs.position.y = -0.2
	sb.add_child(fcs)
	for wl in walls:
		var mi2 := MeshLib.part(c, MeshLib.box(Vector3(wl[2], 1.6, wl[3])), stone, Vector3(wl[0], 0.8, wl[1]))
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(wl[2], 3.0, wl[3])
		cs.shape = bs
		cs.position = Vector3(wl[0], 1.5, wl[1])
		sb.add_child(cs)
	for i in 3:
		var bm := MeshLib.part(c, MeshLib.cyl(0.35, 0.38, 0.9, 8), MeshLib.mat(Color(0.45, 0.3, 0.17)), Vector3(-cw * 0.5 + 0.7, 0.45, -cd * 0.5 + 0.8 + i * 0.9))
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.35)
	l.light_energy = 1.6
	l.omni_range = 8.0
	l.position = Vector3(cw * 0.3, 2.0, 0)
	l.shadow_enabled = false
	c.add_child(l)
	MeshLib.part(c, MeshLib.box(Vector3(0.15, 0.35, 0.15)), MeshLib.mat(Color(1.0, 0.6, 0.25), 0.0, 0.5, 3.0), Vector3(cw * 0.5 - 0.3, 1.6, 0))
	var ch := Chest.new()
	ch.configure(id + "_cellar", state, era, "rich" if _rng.randf() < 0.4 else "normal", lvl, 1.0)
	ch.position = Vector3(cw * 0.25, 0.0, -cd * 0.5 + 0.7)
	c.add_child(ch)
	var up := Trapdoor.new()
	up.building = self
	up.down = false
	up.position = Vector3(-cw * 0.25, 0.0, cd * 0.5 - 1.0)
	c.add_child(up)

func cellar_entry() -> Vector3:
	return to_global(Vector3(0.0, CELLAR_Y + 0.1, 1.2))

func cellar_exit() -> Vector3:
	return to_global(Vector3(0.9, 0.1, -0.2))

## True if a world point lies inside the main room (navigation / roof logic).
func contains(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) < w * 0.5 - 0.1 and absf(l.z) < d * 0.5 - 0.1 and l.y > -1.5 and l.y < wall_h + 0.5

func in_cellar(p: Vector3) -> bool:
	if not has_cellar:
		return false
	var l := to_local(p)
	return absf(l.x) < 4.0 and absf(l.z) < 3.5 and l.y > CELLAR_Y - 2.0 and l.y < CELLAR_Y + 4.0

func _covers(p: Vector3) -> bool:
	var l := to_local(p)
	if l.y < -1.5 or l.y > wall_h + 0.5:
		return false
	if absf(l.x) < w * 0.5 + 0.2 and absf(l.z) < d * 0.5 + 0.2:
		return true
	return has_secret and absf(l.x) < 1.8 and l.z < -d * 0.5 and l.z > -d * 0.5 - 2.9

func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.15
	var v: Node3D = viewer
	if v == null and Game.player != null and is_instance_valid(Game.player):
		v = Game.player
	if v == null:
		return
	var inside := false
	if v.global_position.distance_squared_to(global_position) < (w + d) * (w + d):
		inside = _covers(v.global_position)
	if inside != _inside:
		_inside = inside
		_roof.visible = not inside
		_upper.visible = not inside

## Interactable hatch between the house and its cellar (player only).
class Trapdoor extends Node3D:
	var building: Building
	var down := true
	var interact_radius := 1.6
	var bot_ignore := true
	var _registered := false

	func _ready() -> void:
		var m := MeshLib.part(self, MeshLib.box(Vector3(1.1, 0.06, 1.1)), MeshLib.mat(Color(0.35, 0.24, 0.14)), Vector3(0, 0.05, 0))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		MeshLib.part(self, MeshLib.torus(0.06, 0.1), MeshLib.mat(Color(0.3, 0.3, 0.3), 0.7, 0.4), Vector3(0.3, 0.1, 0))
		if not down:
			MeshLib.part(self, MeshLib.box(Vector3(0.6, 2.4, 0.08)), MeshLib.mat(Color(0.4, 0.3, 0.2)), Vector3(0, 1.2, -0.3), Vector3(-15, 0, 0))
		Game.grid.insert_deferred(self, "interact")
		_registered = true

	func _exit_tree() -> void:
		if _registered:
			Game.grid.remove(self, "interact")
			_registered = false

	func interact_label() -> String:
		return "Спуститься в погреб" if down else "Подняться наверх"

	func can_interact(actor = null) -> bool:
		return actor == null or actor.get("is_player") == true

	func interact(actor) -> void:
		if actor == null or not actor.get("is_player"):
			return
		var dest: Vector3 = building.cellar_entry() if down else building.cellar_exit()
		actor.global_position = dest
		if actor.has_method("reset_physics_interpolation"):
			actor.reset_physics_interpolation()
		Audio.play_sfx("ui_open", dest, -6.0)
		if Game.world and Game.world.has_method("camera_snap"):
			Game.world.camera_snap()
