class_name FurnitureLib
## Procedural home furniture, styled per era (wood and iron → brass → steel
## and gas light → plastic and screens → alloy and holograms). Weapon racks
## and displays show the weapons actually mounted on them.

static func _wood(era: int) -> StandardMaterial3D:
	return MeshLib.mat([Color(0.45, 0.3, 0.17), Color(0.5, 0.32, 0.18), Color(0.35, 0.24, 0.16), Color(0.75, 0.75, 0.78), Color(0.25, 0.27, 0.34)][clampi(era, 0, 4)],
		0.5 if era >= 3 else 0.0, 0.6 if era < 3 else 0.35)

static func _metal(era: int) -> StandardMaterial3D:
	return MeshLib.mat([Color(0.35, 0.35, 0.38), Color(0.78, 0.6, 0.3), Color(0.45, 0.45, 0.48), Color(0.6, 0.62, 0.66), Color(0.7, 0.75, 0.85)][clampi(era, 0, 4)], 0.8, 0.35)

static func _glow(era: int) -> StandardMaterial3D:
	return MeshLib.glow(Color(1.0, 0.55, 0.2) if era <= 1 else (Color(1.0, 0.8, 0.45) if era == 2 else Color(0.35, 0.85, 1.0)), 1.6)

static func build(furn: String, era: int, items: Array = [], tier := 1) -> Node3D:
	var n := Node3D.new()
	var wood := _wood(era)
	var metal := _metal(era)
	match furn:
		"bed":
			MeshLib.part(n, MeshLib.box(Vector3(1.0, 0.35, 2.0)), wood, Vector3(0, 0.18, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.92, 0.14, 1.9)), MeshLib.mat(Color(0.9, 0.88, 0.8)), Vector3(0, 0.42, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.94, 0.06, 1.2)), MeshLib.mat(Color(0.55, 0.2, 0.18) if era < 3 else Color(0.25, 0.35, 0.55)), Vector3(0, 0.5, 0.3))
			MeshLib.part(n, MeshLib.box(Vector3(0.6, 0.12, 0.3)), MeshLib.mat(Color(0.95, 0.95, 0.92)), Vector3(0, 0.52, -0.75))
			MeshLib.part(n, MeshLib.box(Vector3(1.0, 0.7, 0.08)), wood, Vector3(0, 0.35, -1.0))
		"chest":
			if era <= 1:
				MeshLib.part(n, MeshLib.box(Vector3(0.9, 0.5, 0.55)), wood, Vector3(0, 0.25, 0))
				MeshLib.part(n, MeshLib.box(Vector3(0.92, 0.12, 0.57)), wood, Vector3(0, 0.56, 0))
				for x in [-0.3, 0.3]:
					MeshLib.part(n, MeshLib.box(Vector3(0.06, 0.64, 0.6)), metal, Vector3(x, 0.31, 0))
				MeshLib.part(n, MeshLib.box(Vector3(0.12, 0.12, 0.05)), MeshLib.mat(Color(0.85, 0.7, 0.3), 0.8, 0.3), Vector3(0, 0.45, 0.29))
			else:
				MeshLib.part(n, MeshLib.box(Vector3(0.75, 1.0 if era >= 3 else 0.8, 0.6)), metal, Vector3(0, 0.5 if era >= 3 else 0.4, 0))
				MeshLib.part(n, MeshLib.cyl(0.09, 0.09, 0.04, 12), _glow(era) if era >= 3 else wood, Vector3(0.18, 0.6, 0.31), Vector3(90, 0, 0))
				if era == 4:
					MeshLib.part(n, MeshLib.box(Vector3(0.77, 0.03, 0.62)), _glow(era), Vector3(0, 0.98, 0))
		"wardrobe":
			MeshLib.part(n, MeshLib.box(Vector3(1.1, 1.9, 0.55)), wood, Vector3(0, 0.95, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.02, 1.7, 0.02)), metal, Vector3(0, 0.95, 0.28))
			for x in [-0.08, 0.08]:
				MeshLib.part(n, MeshLib.box(Vector3(0.04, 0.12, 0.04)), metal, Vector3(x, 1.0, 0.3))
		"hearth":
			var stone := MeshLib.mat(Color(0.45, 0.43, 0.4)) if era <= 1 else metal
			MeshLib.part(n, MeshLib.box(Vector3(1.1, 0.9, 0.6)), stone, Vector3(0, 0.45, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.6, 0.3, 0.2)), MeshLib.mat(Color(1.0, 0.45, 0.12), 0.0, 0.5, 3.0), Vector3(0, 0.25, 0.22))
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.3)
			l.light_energy = 0.9
			l.omni_range = 4.0
			l.position = Vector3(0, 0.5, 0.5)
			l.shadow_enabled = false
			n.add_child(l)
		"alchemy":
			_table(n, wood, Vector3(1.2, 0.8, 0.6))
			for i in 4:
				MeshLib.part(n, MeshLib.cyl(0.05, 0.06, 0.18 + 0.04 * (i % 2), 8), MeshLib.glow([Color(0.4, 1.0, 0.5), Color(0.9, 0.4, 1.0), Color(1.0, 0.7, 0.3), Color(0.4, 0.7, 1.0)][i], 1.2), Vector3(-0.4 + i * 0.26, 0.92, 0))
		"workbench":
			_table(n, wood, Vector3(1.4, 0.85, 0.7))
			MeshLib.part(n, MeshLib.box(Vector3(0.2, 0.15, 0.25)), metal, Vector3(0.45, 0.95, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.4, 0.04, 0.08)), metal, Vector3(-0.3, 0.9, 0.15), Vector3(0, 30, 0))
			if era >= 3:
				MeshLib.part(n, MeshLib.box(Vector3(0.5, 0.35, 0.04)), _glow(era), Vector3(0, 1.15, -0.3))
		"map":
			MeshLib.part(n, MeshLib.box(Vector3(0.08, 1.2, 0.08)), wood, Vector3(-0.55, 0.6, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.08, 1.2, 0.08)), wood, Vector3(0.55, 0.6, 0))
			MeshLib.part(n, MeshLib.box(Vector3(1.2, 0.85, 0.04)), MeshLib.mat(Color(0.85, 0.78, 0.6)) if era < 3 else _glow(era), Vector3(0, 1.2, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.5, 0.3, 0.05)), MeshLib.mat(Color(0.35, 0.55, 0.35)), Vector3(-0.2, 1.25, 0.01))
		"med_station":
			if tier >= 3:
				# future medical capsule: a glass pod
				MeshLib.part(n, MeshLib.box(Vector3(0.9, 0.35, 2.1)), metal, Vector3(0, 0.18, 0))
				var pod := MeshLib.mat(Color(0.5, 0.9, 1.0, 0.35))
				pod.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				MeshLib.part(n, MeshLib.capsule(0.42, 2.0), pod, Vector3(0, 0.6, 0), Vector3(90, 0, 0))
				MeshLib.part(n, MeshLib.box(Vector3(0.8, 0.03, 1.9)), _glow(4), Vector3(0, 0.37, 0))
			else:
				MeshLib.part(n, MeshLib.box(Vector3(0.9, 1.5, 0.5)), MeshLib.mat(Color(0.92, 0.94, 0.95), 0.2, 0.4), Vector3(0, 0.75, 0))
				MeshLib.part(n, MeshLib.box(Vector3(0.3, 0.08, 0.02)), MeshLib.glow(Color(1.0, 0.2, 0.2), 1.5), Vector3(0, 1.2, 0.26))
				MeshLib.part(n, MeshLib.box(Vector3(0.08, 0.3, 0.02)), MeshLib.glow(Color(1.0, 0.2, 0.2), 1.5), Vector3(0, 1.2, 0.26))
				MeshLib.part(n, MeshLib.box(Vector3(0.45, 0.3, 0.03)), _glow(3), Vector3(0, 0.8, 0.26))
		"weapon_rack":
			for x in [-0.6, 0.6]:
				MeshLib.part(n, MeshLib.box(Vector3(0.08, 1.6, 0.08)), wood if era < 4 else metal, Vector3(x, 0.8, 0))
			for y in [0.5, 1.35]:
				MeshLib.part(n, MeshLib.box(Vector3(1.3, 0.06, 0.1)), wood if era < 4 else _glow(4), Vector3(0, y, 0))
			_mount(n, items, 1.2, era)
		"display":
			MeshLib.part(n, MeshLib.box(Vector3(1.0, 0.8, 0.5)), wood, Vector3(0, 0.4, 0))
			var glass := MeshLib.mat(Color(0.7, 0.9, 1.0, 0.18) if era < 4 else Color(0.3, 0.9, 1.0, 0.25))
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			MeshLib.part(n, MeshLib.box(Vector3(1.0, 0.7, 0.5)), glass, Vector3(0, 1.15, 0))
			_mount(n, items, 0.9, era, 1.15, true)
		_:
			MeshLib.part(n, MeshLib.box(Vector3(0.6, 0.6, 0.6)), wood, Vector3(0, 0.3, 0))
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

static func _table(n: Node3D, wood: Material, size: Vector3) -> void:
	MeshLib.part(n, MeshLib.box(Vector3(size.x, 0.08, size.z)), wood, Vector3(0, size.y, 0))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			MeshLib.part(n, MeshLib.box(Vector3(0.07, size.y, 0.07)), wood, Vector3(sx * (size.x * 0.5 - 0.06), size.y * 0.5, sz * (size.z * 0.5 - 0.06)))

## Mounted weapons: real weapon models standing in the rack / lying in the case.
static func _mount(n: Node3D, items: Array, width: float, era: int, y := 0.9, lying := false) -> void:
	var k := items.size()
	for i in k:
		var it: Dictionary = items[i]
		var b := ItemDB.base(str(it.get("base", "")))
		var model: String = str(b.get("model", "sword"))
		var wn := WeaponModels.build(model, it)
		n.add_child(wn)
		var x := -width * 0.5 + width * (i + 0.5) / maxf(1.0, float(k))
		if lying:
			wn.position = Vector3(x * 0.8, y - 0.25, 0)
			wn.rotation_degrees = Vector3(0, 90, 90)
			wn.scale = Vector3.ONE * 0.6
		else:
			wn.position = Vector3(x, y, 0.08)
			wn.rotation_degrees = Vector3(-90, 0, 0)

## «Дом продаётся» sign / the owner's nameplate on a post.
static func sign(era: int, for_sale: bool) -> Node3D:
	var n := Node3D.new()
	var wood := _wood(era)
	MeshLib.part(n, MeshLib.box(Vector3(0.1, 1.5, 0.1)), wood, Vector3(0, 0.75, 0))
	MeshLib.part(n, MeshLib.box(Vector3(0.8, 0.5, 0.05)), MeshLib.mat(Color(0.85, 0.75, 0.5)) if era < 3 else MeshLib.mat(Color(0.2, 0.22, 0.26), 0.5, 0.4), Vector3(0, 1.45, 0))
	var lbl := Label3D.new()
	lbl.text = "ПРОДАЁТСЯ" if for_sale else "МОЙ ДОМ"
	lbl.font = UITheme.font("bold")
	lbl.font_size = 48
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.25, 0.1, 0.05) if era < 3 else Color(0.5, 0.9, 1.0)
	lbl.position = Vector3(0, 1.45, 0.03)
	n.add_child(lbl)
	var lbl2 := lbl.duplicate()
	lbl2.position = Vector3(0, 1.45, -0.03)
	lbl2.rotation_degrees = Vector3(0, 180, 0)
	n.add_child(lbl2)
	return n
