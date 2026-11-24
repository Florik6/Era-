class_name WeaponModels
## Procedural weapon/offhand models. Grip at origin, the business end points
## along local -Z. Rarity adds emissive accents; living weapons glow by stage.

const WOOD := Color(0.45, 0.3, 0.17)
const DARK := Color(0.16, 0.14, 0.13)
const STEEL := Color(0.78, 0.8, 0.84)
const IRON := Color(0.5, 0.5, 0.52)
const GOLD := Color(0.95, 0.75, 0.25)
const BRASS := Color(0.8, 0.6, 0.3)
const BLACK := Color(0.08, 0.08, 0.09)
const POLY := Color(0.2, 0.22, 0.24)

static func build(model: String, item: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon"
	var rarity: int = item.get("rarity", 0)
	var accent: Color = ItemDB.RARITY_COLORS[rarity]
	var blade_mat: Material = MeshLib.mat(STEEL, 0.85, 0.3)
	var lv: Dictionary = item.get("living", {})
	if lv.size() > 0:
		var st: int = lv.get("stage", 0)
		var gc := Color(0.3, 1.0, 0.8)
		if lv.get("path", "") == "dawn":
			gc = Color(1.0, 0.8, 0.3)
		elif lv.get("path", "") == "dusk":
			gc = Color(0.65, 0.25, 1.0)
		if st > 0:
			blade_mat = MeshLib.mat(gc.lerp(STEEL, 0.4), 0.6, 0.3, 0.6 + st * 1.2)
	elif rarity >= 3:
		blade_mat = MeshLib.mat(STEEL.lerp(accent, 0.45), 0.8, 0.3, 0.5 + (rarity - 3) * 0.8)
	var trim := MeshLib.mat(GOLD if rarity >= 4 else BRASS if rarity >= 2 else IRON, 0.8, 0.35)
	var wood := MeshLib.mat(WOOD)
	var dark := MeshLib.mat(DARK, 0.2, 0.7)
	var energy_c := accent if rarity >= 2 else Color(0.3, 0.8, 1.0)
	var s := 1.0
	if lv.size() > 0:
		s = 1.0 + 0.12 * lv.get("stage", 0)
	match model:
		"sword", "saber", "katana", "rapier":
			var blen = {"sword": 0.85, "saber": 0.8, "katana": 0.95, "rapier": 1.0}[model] * s
			var bw = {"sword": 0.07, "saber": 0.075, "katana": 0.05, "rapier": 0.025}[model]
			MeshLib.part(root, MeshLib.box(Vector3(0.04, 0.04, 0.18)), dark, Vector3(0, 0, 0.02))
			MeshLib.part(root, MeshLib.box(Vector3(0.22 if model != "katana" else 0.08, 0.035, 0.04)), trim, Vector3(0, 0, -0.08))
			var b := MeshLib.part(root, MeshLib.box(Vector3(bw, 0.015, blen)), blade_mat, Vector3(0, 0, -0.1 - blen * 0.5))
			if model == "saber" or model == "katana":
				b.rotation_degrees.y = 4.0
			MeshLib.part(root, MeshLib.sphere(0.03, 6, 4), trim, Vector3(0, 0, 0.12))
			if model == "rapier":
				MeshLib.part(root, MeshLib.torus(0.05, 0.075), trim, Vector3(0, 0, -0.06), Vector3(90, 0, 0))
		"greatsword":
			MeshLib.part(root, MeshLib.box(Vector3(0.045, 0.045, 0.34)), dark, Vector3(0, 0, 0.08))
			MeshLib.part(root, MeshLib.box(Vector3(0.32, 0.04, 0.05)), trim, Vector3(0, 0, -0.1))
			MeshLib.part(root, MeshLib.box(Vector3(0.1, 0.02, 1.25 * s)), blade_mat, Vector3(0, 0, -0.12 - 0.62 * s))
		"dagger":
			MeshLib.part(root, MeshLib.box(Vector3(0.035, 0.035, 0.12)), dark)
			MeshLib.part(root, MeshLib.box(Vector3(0.1, 0.025, 0.03)), trim, Vector3(0, 0, -0.06))
			MeshLib.part(root, MeshLib.box(Vector3(0.045, 0.012, 0.32)), blade_mat, Vector3(0, 0, -0.23))
		"energy_blade":
			MeshLib.part(root, MeshLib.cyl(0.025, 0.025, 0.22), MeshLib.mat(POLY, 0.6, 0.4), Vector3(0, 0, 0.02), Vector3(90, 0, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.02, 1.0)), MeshLib.glow(energy_c, 3.0), Vector3(0, 0, -0.6))
		"spear", "halberd":
			var shaft := 1.9
			MeshLib.part(root, MeshLib.cyl(0.022, 0.022, shaft, 6), wood, Vector3(0, 0, -0.5), Vector3(90, 0, 0))
			MeshLib.part(root, MeshLib.prism(Vector3(0.08, 0.3, 0.02)), blade_mat, Vector3(0, 0, -1.6), Vector3(-90, 0, 0))
			if model == "halberd":
				MeshLib.part(root, MeshLib.box(Vector3(0.28, 0.02, 0.22)), blade_mat, Vector3(0.12, 0, -1.35))
		"axe", "greataxe":
			var big := model == "greataxe"
			var hl := 1.15 if big else 0.7
			MeshLib.part(root, MeshLib.cyl(0.025, 0.025, hl, 6), wood, Vector3(0, 0, -hl * 0.4), Vector3(90, 0, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.32 if big else 0.2, 0.03, 0.22 if big else 0.14)), blade_mat, Vector3(0.12 if big else 0.08, 0, -hl * 0.82))
			if big:
				MeshLib.part(root, MeshLib.box(Vector3(0.22, 0.03, 0.18)), blade_mat, Vector3(-0.1, 0, -hl * 0.82))
		"hammer", "steam_hammer", "baton":
			var hl2 := 0.55 if model == "baton" else 1.1
			MeshLib.part(root, MeshLib.cyl(0.025, 0.025, hl2, 6), wood if model == "hammer" else dark, Vector3(0, 0, -hl2 * 0.4), Vector3(90, 0, 0))
			if model == "hammer":
				MeshLib.part(root, MeshLib.box(Vector3(0.3, 0.16, 0.16)), MeshLib.mat(IRON, 0.7, 0.4), Vector3(0, 0, -hl2 * 0.85))
			elif model == "steam_hammer":
				MeshLib.part(root, MeshLib.cyl(0.12, 0.12, 0.38, 10), MeshLib.mat(BRASS, 0.8, 0.35), Vector3(0, 0, -hl2 * 0.85), Vector3(0, 0, 90))
				MeshLib.part(root, MeshLib.cyl(0.03, 0.03, 0.2), dark, Vector3(0, 0.12, -hl2 * 0.75))
			else:
				MeshLib.part(root, MeshLib.cyl(0.035, 0.035, 0.3), MeshLib.glow(Color(0.5, 0.7, 1.0), 1.5), Vector3(0, 0, -0.5), Vector3(90, 0, 0))
		"bow", "longbow":
			var h := 1.25 if model == "longbow" else 0.95
			for sgn in [-1.0, 1.0]:
				MeshLib.part(root, MeshLib.cyl(0.018, 0.026, h * 0.52, 5), wood, Vector3(0, sgn * h * 0.24, -0.06), Vector3(sgn * 12.0, 0, 0))
			MeshLib.part(root, MeshLib.cyl(0.004, 0.004, h * 0.98, 3), MeshLib.mat(Color(0.9, 0.88, 0.8)), Vector3(0, 0, 0.04))
			if rarity >= 3:
				MeshLib.part(root, MeshLib.box(Vector3(0.04, 0.12, 0.04)), trim, Vector3(0, 0, -0.07))
		"crossbow":
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.07, 0.65)), wood, Vector3(0, 0, -0.22))
			MeshLib.part(root, MeshLib.box(Vector3(0.7, 0.04, 0.05)), MeshLib.mat(IRON, 0.6, 0.4), Vector3(0, 0.02, -0.48))
		"staff", "staff_alch", "staff_tech", "staff_chrono", "focus":
			var gem := Color(1.0, 0.5, 0.2)
			if model == "staff_alch":
				gem = Color(0.4, 1.0, 0.5)
			elif model == "staff_tech" or model == "focus":
				gem = Color(0.5, 0.75, 1.0)
			elif model == "staff_chrono":
				gem = Color(0.4, 1.0, 0.9)
			if rarity >= 3:
				gem = gem.lerp(accent, 0.5)
			if model == "focus":
				MeshLib.part(root, MeshLib.cyl(0.03, 0.04, 0.3), MeshLib.mat(POLY, 0.6, 0.4), Vector3(0, 0, -0.1), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.sphere(0.09, 8, 6), MeshLib.glow(gem, 2.5), Vector3(0, 0, -0.32))
			else:
				var shaft_m: Material = wood if model == "staff" else MeshLib.mat(BRASS if model != "staff_chrono" else Color(0.85, 0.85, 0.95), 0.8, 0.35)
				MeshLib.part(root, MeshLib.cyl(0.022, 0.028, 1.7, 6), shaft_m, Vector3(0, 0, -0.45), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.sphere(0.08, 8, 6), MeshLib.glow(gem, 2.5), Vector3(0, 0, -1.36))
				if model == "staff_chrono":
					MeshLib.part(root, MeshLib.torus(0.11, 0.14), MeshLib.glow(gem, 1.5), Vector3(0, 0, -1.36), Vector3(90, 0, 0))
				else:
					MeshLib.part(root, MeshLib.torus(0.06, 0.09), trim, Vector3(0, 0, -1.28), Vector3(90, 0, 0))
		"musket", "rifle", "carbine", "shotgun", "pulse_rifle", "plasma_cannon", "tesla_gun":
			var body_c := WOOD
			var met := MeshLib.mat(IRON, 0.8, 0.35)
			var blen2 := 0.9
			if model in ["carbine", "pulse_rifle"]:
				body_c = POLY
				blen2 = 0.55
			elif model == "plasma_cannon":
				body_c = Color(0.25, 0.27, 0.32)
				blen2 = 0.5
			elif model == "shotgun":
				blen2 = 0.6
			elif model == "tesla_gun":
				body_c = BRASS
				blen2 = 0.45
			var bm := MeshLib.mat(body_c, 0.3 if body_c != WOOD else 0.0, 0.6)
			MeshLib.part(root, MeshLib.box(Vector3(0.07, 0.11, 0.5)), bm, Vector3(0, -0.02, -0.08))
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.12, 0.25)), bm, Vector3(0, -0.04, 0.22))
			if model == "plasma_cannon":
				MeshLib.part(root, MeshLib.cyl(0.08, 0.08, blen2, 10), met, Vector3(0, 0.02, -0.5), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.cyl(0.06, 0.06, 0.08, 10), MeshLib.glow(Color(1.0, 0.45, 0.15), 3.0), Vector3(0, 0.02, -0.78), Vector3(90, 0, 0))
			elif model == "tesla_gun":
				MeshLib.part(root, MeshLib.cyl(0.03, 0.03, blen2, 6), met, Vector3(0, 0.02, -0.5), Vector3(90, 0, 0))
				for i in 3:
					MeshLib.part(root, MeshLib.torus(0.035, 0.06), MeshLib.mat(Color(0.85, 0.5, 0.25), 0.9, 0.3), Vector3(0, 0.02, -0.38 - i * 0.12), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.sphere(0.05, 8, 4), MeshLib.glow(Color(0.6, 0.8, 1.0), 3.0), Vector3(0, 0.02, -0.76))
			else:
				MeshLib.part(root, MeshLib.cyl(0.02, 0.02, blen2, 6), met, Vector3(0, 0.02, -0.33 - blen2 * 0.5), Vector3(90, 0, 0))
				if model == "shotgun":
					MeshLib.part(root, MeshLib.cyl(0.02, 0.02, blen2, 6), met, Vector3(0, -0.02, -0.33 - blen2 * 0.5), Vector3(90, 0, 0))
				if model == "carbine":
					MeshLib.part(root, MeshLib.box(Vector3(0.04, 0.16, 0.06)), bm, Vector3(0, -0.12, -0.12))
				if model == "pulse_rifle":
					MeshLib.part(root, MeshLib.box(Vector3(0.075, 0.03, 0.4)), MeshLib.glow(energy_c, 2.5), Vector3(0, 0.05, -0.15))
		"pistol_old", "revolver", "pistol", "smg", "smart_gun":
			var c2 := WOOD if model == "pistol_old" else (POLY if model in ["pistol", "smg"] else Color(0.85, 0.85, 0.9))
			if model == "revolver":
				c2 = IRON
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.13, 0.07)), MeshLib.mat(c2.darkened(0.2)), Vector3(0, -0.06, 0.02), Vector3(-15, 0, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.06, 0.26 if model != "smg" else 0.34)), MeshLib.mat(c2, 0.5, 0.45), Vector3(0, 0.03, -0.1))
			if model == "revolver":
				MeshLib.part(root, MeshLib.cyl(0.035, 0.035, 0.06, 8), MeshLib.mat(IRON, 0.8, 0.3), Vector3(0, 0.03, -0.03), Vector3(90, 0, 0))
			if model == "pistol_old":
				MeshLib.part(root, MeshLib.cyl(0.018, 0.018, 0.3, 6), MeshLib.mat(IRON, 0.8, 0.35), Vector3(0, 0.04, -0.3), Vector3(90, 0, 0))
			if model == "smart_gun":
				MeshLib.part(root, MeshLib.box(Vector3(0.055, 0.02, 0.2)), MeshLib.glow(energy_c, 2.5), Vector3(0, 0.065, -0.1))
			if model == "smg":
				MeshLib.part(root, MeshLib.box(Vector3(0.035, 0.14, 0.04)), MeshLib.mat(BLACK), Vector3(0, -0.09, -0.12))
		# ---------------- offhand
		"shield_round":
			MeshLib.part(root, MeshLib.cyl(0.32, 0.32, 0.05, 12), wood, Vector3(0, 0, 0), Vector3(0, 0, 90))
			MeshLib.part(root, MeshLib.sphere(0.07, 8, 4), trim, Vector3(0.03, 0, 0))
		"shield_kite":
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.62, 0.42)), MeshLib.mat(Color(0.65, 0.12, 0.12) if rarity < 3 else accent.darkened(0.3), 0.3, 0.6), Vector3(0, -0.05, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.5, 0.06)), trim, Vector3(0.01, -0.05, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.06, 0.34)), trim, Vector3(0.01, 0.08, 0))
		"shield_energy":
			MeshLib.part(root, MeshLib.cyl(0.42, 0.42, 0.02, 6), MeshLib.mat(Color(0.3, 0.8, 1.0, 0.45), 0.0, 0.3, 1.5), Vector3(0.04, 0, 0), Vector3(0, 0, 90))
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.12, 0.06)), MeshLib.mat(POLY, 0.6, 0.4))
		"book":
			MeshLib.part(root, MeshLib.box(Vector3(0.08, 0.3, 0.22)), MeshLib.mat(Color(0.35, 0.12, 0.15) if rarity < 3 else accent.darkened(0.4)), Vector3(0, 0, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.085, 0.06, 0.06)), MeshLib.glow(Color(1.0, 0.8, 0.4), 1.2), Vector3(0, 0, 0))
		_:
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.05, 0.4)), MeshLib.mat(IRON), Vector3(0, 0, -0.2))
	if rarity >= 5 or item.get("mythic", "") != "":
		var aura := OmniLight3D.new()
		aura.light_color = accent
		aura.light_energy = 0.8
		aura.omni_range = 2.5
		aura.position = Vector3(0, 0, -0.4)
		aura.shadow_enabled = false
		root.add_child(aura)
	return root

## Where a projectile leaves the weapon (local, along -Z).
static func muzzle_length(model: String) -> float:
	match model:
		"musket", "rifle": return 1.3
		"carbine", "pulse_rifle", "shotgun": return 0.95
		"plasma_cannon", "tesla_gun": return 0.85
		"pistol_old", "revolver", "pistol", "smg", "smart_gun": return 0.35
		"staff", "staff_alch", "staff_tech", "staff_chrono": return 1.36
		"focus": return 0.35
	return 0.5
