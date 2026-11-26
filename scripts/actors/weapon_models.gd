class_name WeaponModels
## Procedural weapon/offhand models. Grip at origin, the business end points
## along local -Z. Detail scales with rarity: common = plain steel and wood,
## rare = trims, epic = runic accents, legendary = gold guard, gem and runes,
## mythic = crimson blade with glowing runes. Living weapons change shape per
## stage and evolution path. Every model carries a "tip" marker (meta) at the
## blade tip / muzzle / staff gem for VFX; bows expose string pivots so the
## rig can animate the draw.

const WOOD := Color(0.45, 0.3, 0.17)
const WOOD_DARK := Color(0.3, 0.19, 0.11)
const LEATHER := Color(0.32, 0.2, 0.12)
const DARK := Color(0.16, 0.14, 0.13)
const STEEL := Color(0.8, 0.82, 0.86)
const IRON := Color(0.5, 0.5, 0.52)
const GOLD := Color(0.95, 0.75, 0.25)
const BRASS := Color(0.8, 0.6, 0.3)
const BLACK := Color(0.08, 0.08, 0.09)
const POLY := Color(0.2, 0.22, 0.24)
const CRIMSON := Color(0.55, 0.06, 0.1)

static func _tip(root: Node3D, pos: Vector3) -> void:
	var t := Node3D.new()
	t.name = "Tip"
	t.position = pos
	root.add_child(t)
	root.set_meta("tip", t)

static func _small(mi: MeshInstance3D, dist: float = 26.0) -> MeshInstance3D:
	mi.visibility_range_end = dist
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## accent: optional emblem colour (shields use the faction colour).
static func build(model: String, item: Dictionary = {}, accent_override: Color = Color(0, 0, 0, 0)) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon"
	var rarity: int = item.get("rarity", 0)
	var accent: Color = ItemDB.RARITY_COLORS[clampi(rarity, 0, 5)]
	var lv: Dictionary = item.get("living", {})
	var stage: int = int(lv.get("stage", 0)) if lv.size() > 0 else -1
	var path: String = lv.get("path", "") if lv.size() > 0 else ""
	var blade_mat: Material = MeshLib.mat(STEEL, 0.85, 0.28)
	var rune_mat: Material = null
	if stage >= 0:
		var gc := Color(0.3, 1.0, 0.8)
		if path == "dawn":
			gc = Color(1.0, 0.82, 0.35)
		elif path == "dusk":
			gc = Color(0.65, 0.25, 1.0)
		if stage == 0:
			blade_mat = MeshLib.mat(Color(0.55, 0.57, 0.6), 0.7, 0.55)
		else:
			blade_mat = MeshLib.mat(gc.lerp(STEEL, 0.55 if stage == 1 else 0.3), 0.7, 0.3, 0.25 * stage)
			rune_mat = MeshLib.glow(gc, 1.6 + stage)
	elif rarity == 5 or item.get("mythic", "") != "":
		blade_mat = MeshLib.mat(CRIMSON.lerp(STEEL, 0.25), 0.8, 0.3)
		rune_mat = MeshLib.glow(Color(1.0, 0.2, 0.25), 2.6)
	elif rarity >= 3:
		blade_mat = MeshLib.mat(STEEL.lerp(accent, 0.22), 0.85, 0.28)
		rune_mat = MeshLib.glow(accent, 1.2 + (rarity - 3) * 0.8)
	var trim_c := IRON
	if rarity >= 4 or path == "dawn":
		trim_c = GOLD
	elif rarity >= 2:
		trim_c = BRASS
	if path == "dusk":
		trim_c = Color(0.3, 0.18, 0.4)
	var trim := MeshLib.mat(trim_c, 0.85, 0.32)
	var wood := MeshLib.mat(WOOD)
	var wood_d := MeshLib.mat(WOOD_DARK)
	var leather := MeshLib.mat(LEATHER, 0.0, 0.8)
	var dark := MeshLib.mat(DARK, 0.2, 0.7)
	var energy_c := accent if rarity >= 2 else Color(0.3, 0.8, 1.0)
	var s := 1.0 + 0.14 * maxf(0.0, stage)
	var gem_c := accent if rarity >= 3 else Color(0.9, 0.2, 0.2)
	match model:
		"sword", "saber", "katana", "rapier":
			var blen: float = {"sword": 0.82, "saber": 0.78, "katana": 0.92, "rapier": 0.98}[model] * s
			var bw: float = {"sword": 0.075, "saber": 0.08, "katana": 0.05, "rapier": 0.024}[model] * (1.0 + 0.25 * maxf(0.0, stage))
			# grip (wrapped), pommel, guard
			MeshLib.part(root, MeshLib.cyl(0.022, 0.024, 0.19, 6), leather, Vector3(0, 0, 0.03), Vector3(90, 0, 0))
			MeshLib.part(root, MeshLib.sphere(0.034, 8, 5), trim, Vector3(0, 0, 0.14))
			if model == "katana":
				MeshLib.part(root, MeshLib.cyl(0.05, 0.05, 0.015, 10), trim, Vector3(0, 0, -0.075), Vector3(90, 0, 0))
			elif model == "rapier":
				MeshLib.part(root, MeshLib.box(Vector3(0.16, 0.022, 0.022)), trim, Vector3(0, 0, -0.075))
				MeshLib.part(root, MeshLib.torus(0.05, 0.068), trim, Vector3(0, 0.0, -0.05), Vector3(0, 90, 0))
			else:
				var gw := 0.24 if model == "sword" else 0.15
				if path == "dawn":
					gw = 0.3
				MeshLib.part(root, MeshLib.box(Vector3(gw, 0.034, 0.042)), trim, Vector3(0, 0, -0.08))
				_small(MeshLib.part(root, MeshLib.sphere(0.024, 6, 4), trim, Vector3(gw * 0.5, 0, -0.08)))
				_small(MeshLib.part(root, MeshLib.sphere(0.024, 6, 4), trim, Vector3(-gw * 0.5, 0, -0.08)))
				if model == "saber":
					MeshLib.part(root, MeshLib.torus(0.04, 0.05), trim, Vector3(0.0, -0.035, -0.0), Vector3(0, 0, 90))
			var b := MeshLib.part(root, MeshLib.box(Vector3(bw, 0.016, blen)), blade_mat, Vector3(0, 0, -0.1 - blen * 0.5))
			if model in ["saber", "katana"]:
				b.rotation_degrees.y = 4.0
			# tapered point
			MeshLib.part(root, MeshLib.prism(Vector3(bw, bw * 1.6, 0.016)), blade_mat, Vector3(0, 0, -0.1 - blen - bw * 0.75), Vector3(-90, 0, 0))
			# fuller / runes
			if rune_mat != null:
				_small(MeshLib.part(root, MeshLib.box(Vector3(bw * 0.28, 0.02, blen * 0.72)), rune_mat, Vector3(0, 0, -0.14 - blen * 0.38)), 30.0)
			elif model == "sword":
				_small(MeshLib.part(root, MeshLib.box(Vector3(bw * 0.22, 0.018, blen * 0.6)), MeshLib.mat(IRON, 0.8, 0.35), Vector3(0, 0, -0.14 - blen * 0.32)))
			if rarity >= 4 or stage >= 1:
				_small(MeshLib.part(root, MeshLib.sphere(0.022, 6, 4), MeshLib.glow(gem_c if stage < 0 else Color(0.4, 1.0, 0.85), 2.0), Vector3(0, 0.025, -0.08)))
			if path == "dusk":
				for i in 3:
					_small(MeshLib.part(root, MeshLib.prism(Vector3(0.05, 0.08, 0.015)), blade_mat, Vector3(bw * 0.6, 0, -0.3 - i * 0.22), Vector3(0, 0, -90)))
			_tip(root, Vector3(0, 0, -0.1 - blen - bw * 1.4))
		"greatsword":
			MeshLib.part(root, MeshLib.cyl(0.025, 0.027, 0.36, 6), leather, Vector3(0, 0, 0.08), Vector3(90, 0, 0))
			MeshLib.part(root, MeshLib.sphere(0.04, 8, 5), trim, Vector3(0, 0, 0.27))
			MeshLib.part(root, MeshLib.box(Vector3(0.36, 0.04, 0.05)), trim, Vector3(0, 0, -0.11))
			MeshLib.part(root, MeshLib.box(Vector3(0.07, 0.03, 0.12)), trim, Vector3(0, 0, -0.18))
			MeshLib.part(root, MeshLib.box(Vector3(0.11, 0.022, 1.18 * s)), blade_mat, Vector3(0, 0, -0.24 - 0.59 * s))
			MeshLib.part(root, MeshLib.prism(Vector3(0.11, 0.16, 0.022)), blade_mat, Vector3(0, 0, -0.24 - 1.18 * s - 0.08), Vector3(-90, 0, 0))
			if rune_mat != null:
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.03, 0.026, 0.9 * s)), rune_mat, Vector3(0, 0, -0.3 - 0.45 * s)), 30.0)
			_tip(root, Vector3(0, 0, -0.24 - 1.18 * s - 0.16))
		"dagger":
			MeshLib.part(root, MeshLib.cyl(0.018, 0.02, 0.12, 6), leather, Vector3(0, 0, 0.0), Vector3(90, 0, 0))
			_small(MeshLib.part(root, MeshLib.sphere(0.024, 6, 4), trim, Vector3(0, 0, 0.07)))
			MeshLib.part(root, MeshLib.box(Vector3(0.11, 0.024, 0.03)), trim, Vector3(0, 0, -0.06))
			MeshLib.part(root, MeshLib.box(Vector3(0.046, 0.012, 0.26)), blade_mat, Vector3(0, 0, -0.2))
			MeshLib.part(root, MeshLib.prism(Vector3(0.046, 0.08, 0.012)), blade_mat, Vector3(0, 0, -0.37), Vector3(-90, 0, 0))
			if rune_mat != null:
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.012, 0.016, 0.18)), rune_mat, Vector3(0, 0, -0.2)))
			_tip(root, Vector3(0, 0, -0.41))
		"energy_blade":
			MeshLib.part(root, MeshLib.cyl(0.026, 0.026, 0.24, 8), MeshLib.mat(POLY, 0.6, 0.4), Vector3(0, 0, 0.02), Vector3(90, 0, 0))
			for i in 2:
				_small(MeshLib.part(root, MeshLib.torus(0.024, 0.034), MeshLib.mat(Color(0.7, 0.72, 0.78), 0.8, 0.3), Vector3(0, 0, -0.06 - i * 0.06), Vector3(90, 0, 0)))
			MeshLib.part(root, MeshLib.box(Vector3(0.022, 0.012, 1.0)), MeshLib.mat(Color(1, 1, 1), 0.0, 1.0, 3.0, true), Vector3(0, 0, -0.62))
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.024, 1.04)), MeshLib.mat(Color(energy_c.r, energy_c.g, energy_c.b, 0.55), 0.0, 1.0, 2.5, true), Vector3(0, 0, -0.62), Vector3.ZERO, Vector3.ONE, false)
			_tip(root, Vector3(0, 0, -1.14))
		"spear", "halberd":
			var shaft := 1.9
			MeshLib.part(root, MeshLib.cyl(0.021, 0.024, shaft, 6), wood, Vector3(0, 0, -0.5), Vector3(90, 0, 0))
			_small(MeshLib.part(root, MeshLib.cyl(0.03, 0.03, 0.12, 6), leather, Vector3(0, 0, 0.0), Vector3(90, 0, 0)))
			MeshLib.part(root, MeshLib.cyl(0.03, 0.022, 0.1, 6), trim, Vector3(0, 0, -1.47), Vector3(90, 0, 0))
			MeshLib.part(root, MeshLib.prism(Vector3(0.09, 0.32, 0.022)), blade_mat, Vector3(0, 0, -1.68), Vector3(-90, 0, 0))
			if model == "halberd":
				MeshLib.part(root, MeshLib.box(Vector3(0.3, 0.02, 0.22)), blade_mat, Vector3(0.13, 0, -1.4))
				MeshLib.part(root, MeshLib.prism(Vector3(0.08, 0.14, 0.02)), blade_mat, Vector3(-0.08, 0, -1.4), Vector3(0, 0, 90))
			if rune_mat != null:
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.022, 0.026, 0.16)), rune_mat, Vector3(0, 0, -1.66)))
			_tip(root, Vector3(0, 0, -1.86))
		"axe", "greataxe":
			var big := model == "greataxe"
			var hl := 1.15 if big else 0.72
			MeshLib.part(root, MeshLib.cyl(0.024, 0.028, hl, 6), wood, Vector3(0, 0, -hl * 0.4), Vector3(90, 0, 0))
			_small(MeshLib.part(root, MeshLib.cyl(0.032, 0.032, 0.12, 6), leather, Vector3(0, 0, 0.02), Vector3(90, 0, 0)))
			var hz := -hl * 0.84
			MeshLib.part(root, MeshLib.box(Vector3(0.07, 0.05, 0.1)), MeshLib.mat(IRON, 0.7, 0.4), Vector3(0, 0, hz))
			MeshLib.part(root, MeshLib.box(Vector3(0.26 if big else 0.17, 0.028, 0.2 if big else 0.13)), blade_mat, Vector3(0.14 if big else 0.1, 0, hz))
			MeshLib.part(root, MeshLib.prism(Vector3(0.1, 0.12, 0.028)), blade_mat, Vector3(0.24 if big else 0.17, 0, hz + 0.06), Vector3(-90, 0, 0))
			if big:
				MeshLib.part(root, MeshLib.box(Vector3(0.22, 0.028, 0.17)), blade_mat, Vector3(-0.12, 0, hz))
			else:
				MeshLib.part(root, MeshLib.prism(Vector3(0.05, 0.1, 0.03)), MeshLib.mat(IRON, 0.7, 0.4), Vector3(-0.08, 0, hz), Vector3(0, 0, 90))
			if rune_mat != null:
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.12, 0.032, 0.025)), rune_mat, Vector3(0.12, 0, hz)))
			_tip(root, Vector3(0.22 if big else 0.16, 0, hz))
		"hammer", "steam_hammer", "baton":
			var hl2 := 0.55 if model == "baton" else 1.1
			MeshLib.part(root, MeshLib.cyl(0.024, 0.028, hl2, 6), wood if model == "hammer" else dark, Vector3(0, 0, -hl2 * 0.4), Vector3(90, 0, 0))
			if model == "hammer":
				var hm := MeshLib.mat(IRON, 0.75, 0.38)
				MeshLib.part(root, MeshLib.box(Vector3(0.3, 0.15, 0.15)), hm, Vector3(0, 0, -hl2 * 0.86))
				MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.18, 0.18)), hm, Vector3(0.16, 0, -hl2 * 0.86))
				MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.18, 0.18)), hm, Vector3(-0.16, 0, -hl2 * 0.86))
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.04, 0.03, 0.22)), trim, Vector3(0, 0, -hl2 * 0.72)))
				if rune_mat != null:
					_small(MeshLib.part(root, MeshLib.box(Vector3(0.26, 0.04, 0.03)), rune_mat, Vector3(0, 0.07, -hl2 * 0.86)))
			elif model == "steam_hammer":
				MeshLib.part(root, MeshLib.cyl(0.12, 0.12, 0.38, 10), MeshLib.mat(BRASS, 0.8, 0.35), Vector3(0, 0, -hl2 * 0.85), Vector3(0, 0, 90))
				MeshLib.part(root, MeshLib.cyl(0.13, 0.13, 0.04, 10), MeshLib.mat(IRON, 0.8, 0.35), Vector3(0.2, 0, -hl2 * 0.85), Vector3(0, 0, 90))
				MeshLib.part(root, MeshLib.cyl(0.03, 0.03, 0.2, 6), dark, Vector3(0, 0.12, -hl2 * 0.75))
				_small(MeshLib.part(root, MeshLib.sphere(0.04, 6, 4), MeshLib.glow(Color(1.0, 0.5, 0.2), 2.0), Vector3(0, 0.0, -hl2 * 0.68)))
			else:
				MeshLib.part(root, MeshLib.cyl(0.035, 0.035, 0.3, 8), MeshLib.glow(Color(0.5, 0.7, 1.0), 1.5), Vector3(0, 0, -0.5), Vector3(90, 0, 0))
			_tip(root, Vector3(0, 0, -hl2 * 0.95))
		"bow", "longbow":
			var h := 1.25 if model == "longbow" else 0.98
			var bmat: Material = wood if rarity < 3 else MeshLib.mat(WOOD.lerp(accent, 0.25))
			for sgn in [-1.0, 1.0]:
				# recurve limbs: inner + outer segment
				MeshLib.part(root, MeshLib.cyl(0.02, 0.028, h * 0.3, 5), bmat, Vector3(0, sgn * h * 0.14, -0.05), Vector3(sgn * 14.0, 0, 0))
				MeshLib.part(root, MeshLib.cyl(0.012, 0.02, h * 0.26, 5), bmat, Vector3(0, sgn * h * 0.38, -0.04), Vector3(-sgn * 12.0, 0, 0))
			MeshLib.part(root, MeshLib.cyl(0.03, 0.03, 0.12, 6), leather, Vector3(0, 0, -0.06))
			if rune_mat != null:
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.03, h * 0.5, 0.02)), rune_mat, Vector3(0, 0, -0.08)))
			# string in two halves meeting at the nock (rig animates the draw)
			var top := MeshLib.pivot(root, Vector3(0, h * 0.5, -0.02), "StringTop")
			var bot := MeshLib.pivot(root, Vector3(0, -h * 0.5, -0.02), "StringBot")
			var smat := MeshLib.mat(Color(0.92, 0.9, 0.82))
			var st := MeshLib.part(top, MeshLib.box(Vector3(0.008, 1.0, 0.008)), smat, Vector3(0, -0.5, 0), Vector3.ZERO, Vector3.ONE, false)
			var sb := MeshLib.part(bot, MeshLib.box(Vector3(0.008, 1.0, 0.008)), smat, Vector3(0, 0.5, 0), Vector3.ZERO, Vector3.ONE, false)
			root.set_meta("string_top", top)
			root.set_meta("string_bot", bot)
			root.set_meta("string_len", h * 0.5)
			top.scale = Vector3(1, h * 0.5, 1)
			bot.scale = Vector3(1, h * 0.5, 1)
			# nocked arrow, shown by the rig only while drawing
			var arrow := MeshLib.pivot(root, Vector3(0, 0, -0.02), "Arrow")
			MeshLib.part(arrow, MeshLib.box(Vector3(0.012, 0.012, 0.76)), MeshLib.mat(Color(0.62, 0.5, 0.32)), Vector3(0, 0, -0.38), Vector3.ZERO, Vector3.ONE, false)
			MeshLib.part(arrow, MeshLib.prism(Vector3(0.03, 0.07, 0.012)), MeshLib.mat(IRON, 0.7, 0.4), Vector3(0, 0, -0.79), Vector3(-90, 0, 0), Vector3.ONE, false)
			_small(MeshLib.part(arrow, MeshLib.box(Vector3(0.004, 0.04, 0.09)), MeshLib.mat(Color(0.9, 0.9, 0.85)), Vector3(0, 0, -0.05)))
			arrow.visible = false
			root.set_meta("arrow", arrow)
			_tip(root, Vector3(0, 0, -0.1))
		"crossbow":
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.07, 0.66)), wood, Vector3(0, 0, -0.22))
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.1, 0.16)), wood_d, Vector3(0, -0.06, 0.12))
			MeshLib.part(root, MeshLib.box(Vector3(0.72, 0.04, 0.05)), MeshLib.mat(IRON, 0.6, 0.4), Vector3(0, 0.02, -0.5))
			_small(MeshLib.part(root, MeshLib.box(Vector3(0.7, 0.008, 0.008)), MeshLib.mat(Color(0.9, 0.88, 0.8)), Vector3(0, 0.03, -0.42)))
			_small(MeshLib.part(root, MeshLib.box(Vector3(0.018, 0.018, 0.4)), MeshLib.mat(LEATHER), Vector3(0, 0.06, -0.32)))
			_tip(root, Vector3(0, 0.05, -0.58))
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
				MeshLib.part(root, MeshLib.cyl(0.03, 0.04, 0.3, 8), MeshLib.mat(POLY, 0.6, 0.4), Vector3(0, 0, -0.1), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.torus(0.07, 0.09), MeshLib.mat(Color(0.75, 0.78, 0.82), 0.8, 0.3), Vector3(0, 0, -0.3), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.sphere(0.075, 8, 6), MeshLib.glow(gem, 2.5), Vector3(0, 0, -0.32))
				_tip(root, Vector3(0, 0, -0.34))
			else:
				var shaft_m: Material = wood if model == "staff" else MeshLib.mat(BRASS if model != "staff_chrono" else Color(0.85, 0.85, 0.95), 0.8, 0.35)
				MeshLib.part(root, MeshLib.cyl(0.02, 0.03, 1.72, 6), shaft_m, Vector3(0, 0, -0.45), Vector3(90, 0, 0))
				_small(MeshLib.part(root, MeshLib.cyl(0.032, 0.032, 0.14, 6), leather, Vector3(0, 0, -0.02), Vector3(90, 0, 0)))
				if model == "staff":
					# gnarled head: prongs cradling a crystal
					for i in 3:
						var a := TAU * i / 3.0
						MeshLib.part(root, MeshLib.cyl(0.012, 0.02, 0.24, 4), wood_d, Vector3(cos(a) * 0.05, sin(a) * 0.05, -1.36), Vector3(90 + cos(a) * 18.0, 0, sin(a) * 18.0))
					MeshLib.part(root, MeshLib.prism(Vector3(0.09, 0.18, 0.09)), MeshLib.glow(gem, 2.4), Vector3(0, 0, -1.4), Vector3(-90, 0, 0))
				else:
					MeshLib.part(root, MeshLib.sphere(0.08, 8, 6), MeshLib.glow(gem, 2.5), Vector3(0, 0, -1.38))
					MeshLib.part(root, MeshLib.torus(0.06, 0.09), trim, Vector3(0, 0, -1.28), Vector3(90, 0, 0))
				if model == "staff_chrono" or rarity >= 3:
					var ring := MeshLib.part(root, MeshLib.torus(0.12, 0.14), MeshLib.glow(gem, 1.5), Vector3(0, 0, -1.38), Vector3(90, 0, 0))
					ring.name = "Orbit"
				_tip(root, Vector3(0, 0, -1.42))
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
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.13, 0.27)), bm, Vector3(0, -0.05, 0.23), Vector3(-8, 0, 0))
			_small(MeshLib.part(root, MeshLib.torus(0.02, 0.03), met, Vector3(0, -0.08, -0.02), Vector3(0, 90, 0)))
			if model == "plasma_cannon":
				MeshLib.part(root, MeshLib.cyl(0.08, 0.08, blen2, 10), met, Vector3(0, 0.02, -0.5), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.cyl(0.06, 0.06, 0.08, 10), MeshLib.glow(Color(1.0, 0.45, 0.15), 3.0), Vector3(0, 0.02, -0.78), Vector3(90, 0, 0))
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.05, 0.2)), MeshLib.glow(Color(1.0, 0.55, 0.2), 2.0), Vector3(0.06, 0.04, -0.2)))
			elif model == "tesla_gun":
				MeshLib.part(root, MeshLib.cyl(0.03, 0.03, blen2, 6), met, Vector3(0, 0.02, -0.5), Vector3(90, 0, 0))
				for i in 3:
					MeshLib.part(root, MeshLib.torus(0.035, 0.06), MeshLib.mat(Color(0.85, 0.5, 0.25), 0.9, 0.3), Vector3(0, 0.02, -0.38 - i * 0.12), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.sphere(0.05, 8, 4), MeshLib.glow(Color(0.6, 0.8, 1.0), 3.0), Vector3(0, 0.02, -0.76))
			else:
				MeshLib.part(root, MeshLib.cyl(0.02, 0.022, blen2, 6), met, Vector3(0, 0.02, -0.33 - blen2 * 0.5), Vector3(90, 0, 0))
				if model == "shotgun":
					MeshLib.part(root, MeshLib.cyl(0.02, 0.022, blen2, 6), met, Vector3(0, -0.02, -0.33 - blen2 * 0.5), Vector3(90, 0, 0))
					MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.05, 0.16)), bm, Vector3(0, -0.06, -0.42))
				if model in ["musket", "rifle"]:
					_small(MeshLib.part(root, MeshLib.box(Vector3(0.012, 0.02, 0.7)), met, Vector3(0, -0.035, -0.62)))
				if model == "carbine":
					MeshLib.part(root, MeshLib.box(Vector3(0.04, 0.16, 0.06)), bm, Vector3(0, -0.12, -0.12), Vector3(10, 0, 0))
					_small(MeshLib.part(root, MeshLib.cyl(0.025, 0.025, 0.16, 8), MeshLib.mat(BLACK, 0.5, 0.4), Vector3(0, 0.08, -0.1), Vector3(90, 0, 0)))
				if model == "pulse_rifle":
					MeshLib.part(root, MeshLib.box(Vector3(0.075, 0.03, 0.4)), MeshLib.glow(energy_c, 2.5), Vector3(0, 0.05, -0.15))
					_small(MeshLib.part(root, MeshLib.cyl(0.03, 0.03, 0.18, 8), MeshLib.mat(BLACK, 0.5, 0.4), Vector3(0, 0.09, -0.05), Vector3(90, 0, 0)))
				if model == "rifle":
					_small(MeshLib.part(root, MeshLib.box(Vector3(0.02, 0.05, 0.05)), met, Vector3(0, 0.05, -0.05)))
			if rune_mat != null:
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.074, 0.02, 0.3)), rune_mat, Vector3(0, 0.035, -0.1)))
			_tip(root, Vector3(0, 0.02, -WeaponModels.muzzle_length(model)))
		"pistol_old", "revolver", "pistol", "smg", "smart_gun":
			var c2 := WOOD if model == "pistol_old" else (POLY if model in ["pistol", "smg"] else Color(0.85, 0.85, 0.9))
			if model == "revolver":
				c2 = IRON
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.13, 0.07)), MeshLib.mat(c2.darkened(0.2)), Vector3(0, -0.06, 0.02), Vector3(-15, 0, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.06, 0.26 if model != "smg" else 0.34)), MeshLib.mat(c2, 0.5, 0.45), Vector3(0, 0.03, -0.1))
			_small(MeshLib.part(root, MeshLib.torus(0.016, 0.026), MeshLib.mat(IRON, 0.8, 0.3), Vector3(0, -0.02, -0.02), Vector3(0, 90, 0)))
			if model == "revolver":
				MeshLib.part(root, MeshLib.cyl(0.035, 0.035, 0.06, 8), MeshLib.mat(IRON, 0.8, 0.3), Vector3(0, 0.03, -0.03), Vector3(90, 0, 0))
				MeshLib.part(root, MeshLib.cyl(0.014, 0.014, 0.16, 6), MeshLib.mat(IRON, 0.8, 0.3), Vector3(0, 0.045, -0.2), Vector3(90, 0, 0))
			if model == "pistol_old":
				MeshLib.part(root, MeshLib.cyl(0.018, 0.022, 0.3, 6), MeshLib.mat(IRON, 0.8, 0.35), Vector3(0, 0.04, -0.3), Vector3(90, 0, 0))
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.02, 0.04, 0.04)), trim, Vector3(0, 0.07, -0.02)))
			if model == "smart_gun":
				MeshLib.part(root, MeshLib.box(Vector3(0.055, 0.02, 0.2)), MeshLib.glow(energy_c, 2.5), Vector3(0, 0.065, -0.1))
			if model == "smg":
				MeshLib.part(root, MeshLib.box(Vector3(0.035, 0.14, 0.04)), MeshLib.mat(BLACK), Vector3(0, -0.09, -0.12))
			_tip(root, Vector3(0, 0.04, -WeaponModels.muzzle_length(model)))
		# ---------------- offhand
		"shield_round":
			var face_c: Color = accent_override if accent_override.a > 0.5 else (Color(0.5, 0.33, 0.18) if rarity < 3 else accent.darkened(0.35))
			MeshLib.part(root, MeshLib.cyl(0.32, 0.32, 0.05, 14), MeshLib.mat(face_c.darkened(0.15) if accent_override.a > 0.5 else WOOD), Vector3(0, 0, 0), Vector3(0, 0, 90))
			MeshLib.part(root, MeshLib.torus(0.3, 0.335), MeshLib.mat(IRON, 0.75, 0.4), Vector3(0, 0, 0), Vector3(0, 0, 90))
			if accent_override.a > 0.5:
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.012, 0.44, 0.1)), MeshLib.mat(face_c.lightened(0.25)), Vector3(0.03, 0, 0)))
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.012, 0.1, 0.44)), MeshLib.mat(face_c.lightened(0.25)), Vector3(0.03, 0, 0)))
			MeshLib.part(root, MeshLib.sphere(0.07, 8, 4), trim, Vector3(0.04, 0, 0))
		"shield_kite":
			var kc: Color = accent_override if accent_override.a > 0.5 else (Color(0.65, 0.12, 0.12) if rarity < 3 else accent.darkened(0.3))
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.55, 0.42)), MeshLib.mat(kc, 0.3, 0.6), Vector3(0, 0.0, 0))
			MeshLib.part(root, MeshLib.prism(Vector3(0.42, 0.26, 0.05)), MeshLib.mat(kc, 0.3, 0.6), Vector3(0, -0.4, 0), Vector3(180, 90, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.5, 0.05)), trim, Vector3(0.012, -0.05, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.05, 0.36)), trim, Vector3(0.012, 0.1, 0))
			_small(MeshLib.part(root, MeshLib.box(Vector3(0.058, 0.04, 0.44)), MeshLib.mat(IRON, 0.75, 0.4), Vector3(0.004, 0.27, 0)))
		"shield_energy":
			MeshLib.part(root, MeshLib.cyl(0.42, 0.42, 0.02, 6), MeshLib.mat(Color(0.3, 0.8, 1.0, 0.4), 0.0, 0.3, 1.5), Vector3(0.04, 0, 0), Vector3(0, 0, 90))
			MeshLib.part(root, MeshLib.torus(0.4, 0.43), MeshLib.glow(Color(0.4, 0.85, 1.0), 2.0), Vector3(0.04, 0, 0), Vector3(0, 0, 90))
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.14, 0.07)), MeshLib.mat(POLY, 0.6, 0.4))
		"book":
			var bc: Color = Color(0.35, 0.12, 0.15) if rarity < 3 else accent.darkened(0.4)
			MeshLib.part(root, MeshLib.box(Vector3(0.08, 0.3, 0.22)), MeshLib.mat(bc), Vector3(0, 0, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.07, 0.28, 0.2)), MeshLib.mat(Color(0.92, 0.88, 0.75)), Vector3(0.006, 0, 0.012))
			_small(MeshLib.part(root, MeshLib.box(Vector3(0.085, 0.07, 0.07)), MeshLib.glow(Color(1.0, 0.8, 0.4), 1.4), Vector3(0, 0, 0)))
			_small(MeshLib.part(root, MeshLib.box(Vector3(0.09, 0.31, 0.02)), trim, Vector3(0, 0, -0.11)))
		_:
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.05, 0.4)), MeshLib.mat(IRON), Vector3(0, 0, -0.2))
			_tip(root, Vector3(0, 0, -0.4))
	if (rarity >= 5 or item.get("mythic", "") != "") and Settings.vq("lights", 8) >= 8:
		var aura := OmniLight3D.new()
		aura.light_color = accent
		aura.light_energy = 0.6
		aura.omni_range = 2.2
		aura.position = Vector3(0, 0, -0.4)
		aura.shadow_enabled = false
		root.add_child(aura)
	if not root.has_meta("tip"):
		_tip(root, Vector3(0, 0, -0.3))
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

## Small sheathed / stowed versions for belts and backs (no rarity effects).
static func stowed(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Stowed"
	var leather := MeshLib.mat(LEATHER, 0.0, 0.8)
	var iron := MeshLib.mat(IRON, 0.75, 0.4)
	match kind:
		"scabbard":
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.035, 0.72)), leather, Vector3(0, 0, -0.36))
			_small(MeshLib.part(root, MeshLib.box(Vector3(0.07, 0.04, 0.06)), iron, Vector3(0, 0, -0.71)))
			_small(MeshLib.part(root, MeshLib.box(Vector3(0.07, 0.04, 0.05)), iron, Vector3(0, 0, -0.02)))
		"quiver":
			MeshLib.part(root, MeshLib.cyl(0.07, 0.055, 0.52, 8), leather, Vector3(0, 0, 0))
			_small(MeshLib.part(root, MeshLib.torus(0.06, 0.078), MeshLib.mat(BRASS, 0.8, 0.35), Vector3(0, 0.22, 0)))
			MeshLib.part(root, MeshLib.box(Vector3(0.07, 0.16, 0.06)), MeshLib.mat(Color(0.6, 0.48, 0.3)), Vector3(0, 0.33, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.11, 0.09, 0.09)), MeshLib.mat(Color(0.85, 0.2, 0.15)), Vector3(0, 0.44, 0))
		"dagger_sheath":
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.03, 0.3)), leather, Vector3(0, 0, -0.15))
			_small(MeshLib.part(root, MeshLib.cyl(0.018, 0.018, 0.1, 6), MeshLib.mat(DARK), Vector3(0, 0, 0.05), Vector3(90, 0, 0)))
		"holster":
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.18, 0.1)), leather, Vector3(0, 0, 0))
		"bandolier":
			MeshLib.part(root, MeshLib.box(Vector3(0.06, 0.62, 0.02)), leather, Vector3(0, 0, 0))
			for i in 4:
				_small(MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.04, 0.03)), MeshLib.mat(BRASS, 0.8, 0.35), Vector3(0, -0.2 + i * 0.13, -0.015)))
	return root
