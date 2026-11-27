class_name Icons
## Vector icons drawn with CanvasItem primitives (no texture assets):
## weapons, actions, menu buttons, magic schools and techniques.

const SKILL_ICONS := {
	"sw_quick": "slash2", "sw_heavy": "slam", "sw_whirl": "whirl", "dg_flurry": "dagger", "dg_stealth": "stealth",
	"dg_shadowstep": "shadowstep", "sp_lunge": "spear", "sp_sweep": "sweep", "sp_wall": "spear", "hv_slam": "slam",
	"hv_unstoppable": "rage", "hv_quake": "quake", "bw_aimed": "aim", "bw_rapid": "arrows", "bw_special": "arrows",
	"fa_burst": "burst", "fa_special": "bomb", "st_shield": "bubble", "st_overload": "burst", "ua_kick": "kick",
	"fireball": "fire", "ignite": "fire", "firewall": "fire", "meteor": "meteor",
	"frostbolt": "ice", "freeze": "ice", "icewall": "icewall", "blizzard": "snow",
	"spark": "lightning", "chain": "lightning", "thunderclap": "lightning", "storm": "lightning",
	"curse": "skull", "drain": "drain", "summon": "skull", "nova": "dark",
	"blink": "time", "timeslow": "time", "timetrap": "time", "riftdash": "shadowstep",
}

static func for_skill(id: String) -> String:
	if SKILL_ICONS.has(id):
		return SKILL_ICONS[id]
	var e: Dictionary = DBAbilities.get_ab(id)
	if e.is_empty():
		return "star"
	if e.kind == "spell":
		var sh := str(e.get("vis", {}).get("shape", ""))
		if sh in ["construct", "raise", "march"]:
			return "skull" if e.school == "necro" else "quake"
		if sh in ["crystal_shell", "bone_orbit", "light_dome", "air_dome"]:
			return "bubble"
		match str(e.school):
			"fire": return "meteor" if int(e.tier) >= 5 else "fire"
			"ice": return "snow" if int(e.tier) >= 5 else "ice"
			"lightning": return "lightning"
			"dark": return "dark"
			"spacetime": return "time"
			"earth": return "quake" if int(e.tier) >= 3 else "slam"
			"necro": return "skull"
			"heal": return "potion"
			"air": return "whirl"
			"light": return "star"
	match str(e.fx[0].c) if not e.fx.is_empty() else "":
		"melee", "melee_seq":
			var arc := float(e.fx[0].get("arc", 100.0)) if e.fx[0].c == "melee" else float(e.fx[0].seq[0][2])
			return "whirl" if arc >= 300.0 else "slash2"
		"shots", "sky_volley": return "arrows"
		"move", "behind", "shadow_dance": return "shadowstep"
		"buff": return "rage"
		"nova", "blast": return "slam"
		"cone": return "sweep"
		"decoy": return "stealth"
		"debuff": return "aim"
		"zone": return "spear"
		"reveal": return "aim"
	return "star"

static func for_weapon(cat: String) -> String:
	match cat:
		"sword": return "sword"
		"dagger": return "dagger"
		"spear": return "spear"
		"heavy": return "axe"
		"bow": return "bow"
		"firearm": return "gun"
		"staff": return "staff"
	return "fist"

static func _poly(ci: CanvasItem, pts: Array, c: Vector2, s: float, col: Color) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(c + Vector2(v) * s)
	ci.draw_colored_polygon(p, col)

static func _line(ci: CanvasItem, pts: Array, c: Vector2, s: float, col: Color, w: float) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(c + Vector2(v) * s)
	ci.draw_polyline(p, col, w, true)

## Draw icon `kind` centred at c with half-size s.
static func draw(ci: CanvasItem, kind: String, c: Vector2, s: float, col: Color = Color(1, 1, 1)) -> void:
	var w := maxf(2.0, s * 0.14)
	match kind:
		"sword":
			_poly(ci, [Vector2(-0.12, 0.35), Vector2(0.12, 0.35), Vector2(0.1, -0.75), Vector2(0, -0.95), Vector2(-0.1, -0.75)], c, s, col)
			_line(ci, [Vector2(-0.42, 0.38), Vector2(0.42, 0.38)], c, s, col, w * 1.2)
			_line(ci, [Vector2(0, 0.4), Vector2(0, 0.85)], c, s, col, w * 1.3)
		"slash2":
			_line(ci, [Vector2(-0.8, 0.5), Vector2(-0.2, -0.1), Vector2(0.7, -0.8)], c, s, col, w * 1.4)
			_line(ci, [Vector2(-0.5, 0.8), Vector2(0.1, 0.25), Vector2(0.85, -0.3)], c, s, col.darkened(0.15), w)
		"dagger":
			_poly(ci, [Vector2(-0.1, 0.15), Vector2(0.1, 0.15), Vector2(0, -0.75)], c, s, col)
			_line(ci, [Vector2(-0.3, 0.18), Vector2(0.3, 0.18)], c, s, col, w)
			_line(ci, [Vector2(0, 0.2), Vector2(0, 0.6)], c, s, col, w * 1.3)
		"spear":
			_line(ci, [Vector2(-0.7, 0.7), Vector2(0.5, -0.5)], c, s, col, w)
			_poly(ci, [Vector2(0.45, -0.3), Vector2(0.3, -0.45), Vector2(0.85, -0.85)], c, s, col)
		"axe":
			_line(ci, [Vector2(-0.5, 0.8), Vector2(0.25, -0.6)], c, s, col, w * 1.2)
			_poly(ci, [Vector2(0.1, -0.75), Vector2(0.75, -0.55), Vector2(0.7, 0.05), Vector2(0.25, -0.2)], c, s, col)
		"bow":
			ci.draw_arc(c + Vector2(-0.35, 0) * s, s * 0.85, -1.2, 1.2, 16, col, w)
			_line(ci, [Vector2(0.0, -0.78), Vector2(0.0, 0.78)], c, s, col.darkened(0.2), maxf(1.0, w * 0.5))
			_line(ci, [Vector2(-0.6, 0), Vector2(0.75, 0)], c, s, col, w * 0.8)
			_poly(ci, [Vector2(0.75, -0.12), Vector2(0.95, 0), Vector2(0.75, 0.12)], c, s, col)
		"gun":
			_poly(ci, [Vector2(-0.8, -0.3), Vector2(0.75, -0.3), Vector2(0.75, -0.05), Vector2(-0.2, -0.05), Vector2(-0.35, 0.6), Vector2(-0.65, 0.6), Vector2(-0.55, -0.05), Vector2(-0.8, -0.05)], c, s, col)
		"staff":
			_line(ci, [Vector2(-0.45, 0.85), Vector2(0.3, -0.45)], c, s, col, w)
			ci.draw_circle(c + Vector2(0.4, -0.6) * s, s * 0.24, col)
			ci.draw_arc(c + Vector2(0.4, -0.6) * s, s * 0.38, 0, TAU, 16, col.darkened(0.2), maxf(1.0, w * 0.5))
		"fist":
			ci.draw_circle(c, s * 0.45, col)
			_line(ci, [Vector2(-0.3, -0.1), Vector2(0.3, -0.1)], c, s, Color(0, 0, 0, 0.5), maxf(1.0, w * 0.5))
		"shield":
			_poly(ci, [Vector2(-0.6, -0.65), Vector2(0.6, -0.65), Vector2(0.55, 0.1), Vector2(0, 0.85), Vector2(-0.55, 0.1)], c, s, col)
			_line(ci, [Vector2(0, -0.55), Vector2(0, 0.6)], c, s, Color(0, 0, 0, 0.35), maxf(1.0, w * 0.6))
		"dodge":
			for i in 3:
				var y := -0.45 + i * 0.45
				_line(ci, [Vector2(-0.8, y), Vector2(0.4, y)], c, s, Color(col.r, col.g, col.b, 0.5 + 0.25 * i), w)
			_poly(ci, [Vector2(0.35, -0.4), Vector2(0.9, 0), Vector2(0.35, 0.4)], c, s, col)
		"hand":
			_poly(ci, [Vector2(-0.45, 0.8), Vector2(0.45, 0.8), Vector2(0.5, -0.05), Vector2(-0.5, -0.05)], c, s, col)
			for i in 4:
				var x := -0.38 + i * 0.25
				_poly(ci, [Vector2(x - 0.09, 0.0), Vector2(x + 0.09, 0.0), Vector2(x + 0.08, -0.7 + absf(i - 1.5) * 0.12), Vector2(x - 0.08, -0.7 + absf(i - 1.5) * 0.12)], c, s, col)
		"swap":
			ci.draw_arc(c, s * 0.6, PI * 0.15, PI * 1.05, 14, col, w)
			ci.draw_arc(c, s * 0.6, PI * 1.15, PI * 2.05, 14, col, w)
			_poly(ci, [Vector2(-0.75, -0.25), Vector2(-0.35, -0.25), Vector2(-0.55, 0.1)], c, s, col)
			_poly(ci, [Vector2(0.75, 0.25), Vector2(0.35, 0.25), Vector2(0.55, -0.1)], c, s, col)
		"potion":
			_poly(ci, [Vector2(-0.15, -0.8), Vector2(0.15, -0.8), Vector2(0.15, -0.35), Vector2(0.55, 0.15), Vector2(0.45, 0.75), Vector2(-0.45, 0.75), Vector2(-0.55, 0.15), Vector2(-0.15, -0.35)], c, s, col)
			_poly(ci, [Vector2(-0.48, 0.2), Vector2(0.48, 0.2), Vector2(0.42, 0.7), Vector2(-0.42, 0.7)], c, s, Color(0.95, 0.2, 0.25))
		"paw":
			ci.draw_circle(c + Vector2(0, 0.25) * s, s * 0.35, col)
			for v in [Vector2(-0.45, -0.25), Vector2(-0.15, -0.55), Vector2(0.15, -0.55), Vector2(0.45, -0.25)]:
				ci.draw_circle(c + v * s, s * 0.15, col)
		"menu":
			for i in 3:
				_line(ci, [Vector2(-0.6, -0.45 + i * 0.45), Vector2(0.6, -0.45 + i * 0.45)], c, s, col, w)
		"bag":
			_poly(ci, [Vector2(-0.6, -0.2), Vector2(0.6, -0.2), Vector2(0.7, 0.75), Vector2(-0.7, 0.75)], c, s, col)
			ci.draw_arc(c + Vector2(0, -0.25) * s, s * 0.35, PI, TAU, 12, col, w)
		"skills", "star":
			var pts: Array = []
			for i in 10:
				var r := 0.85 if i % 2 == 0 else 0.38
				var a := -PI * 0.5 + i * PI / 5.0
				pts.append(Vector2(cos(a), sin(a)) * r)
			_poly(ci, pts, c, s, col)
		"map":
			_poly(ci, [Vector2(-0.8, -0.6), Vector2(-0.3, -0.75), Vector2(0.3, -0.55), Vector2(0.8, -0.7), Vector2(0.8, 0.6), Vector2(0.3, 0.75), Vector2(-0.3, 0.55), Vector2(-0.8, 0.7)], c, s, col)
			_line(ci, [Vector2(-0.3, -0.7), Vector2(-0.3, 0.55)], c, s, Color(0, 0, 0, 0.35), maxf(1.0, w * 0.5))
			_line(ci, [Vector2(0.3, -0.55), Vector2(0.3, 0.7)], c, s, Color(0, 0, 0, 0.35), maxf(1.0, w * 0.5))
		"fire", "meteor":
			_poly(ci, [Vector2(0, -0.9), Vector2(0.45, -0.2), Vector2(0.5, 0.35), Vector2(0.2, 0.8), Vector2(-0.2, 0.8), Vector2(-0.5, 0.35), Vector2(-0.35, -0.15), Vector2(-0.1, 0.1)], c, s, Color(1.0, 0.45, 0.1))
			_poly(ci, [Vector2(0, -0.2), Vector2(0.25, 0.3), Vector2(0.1, 0.7), Vector2(-0.1, 0.7), Vector2(-0.25, 0.3)], c, s, Color(1.0, 0.85, 0.3))
			if kind == "meteor":
				_line(ci, [Vector2(-0.9, -0.9), Vector2(-0.35, -0.35)], c, s, Color(1.0, 0.6, 0.2, 0.8), w)
		"ice", "icewall", "snow":
			var ic := Color(0.6, 0.9, 1.0)
			for i in 3:
				var a := i * PI / 3.0
				_line(ci, [Vector2(cos(a), sin(a)) * -0.8, Vector2(cos(a), sin(a)) * 0.8], c, s, ic, w)
			if kind == "icewall":
				_poly(ci, [Vector2(-0.7, 0.8), Vector2(-0.4, -0.2), Vector2(0.0, 0.8)], c, s, Color(0.7, 0.95, 1.0, 0.8))
		"lightning":
			_poly(ci, [Vector2(0.15, -0.9), Vector2(-0.45, 0.1), Vector2(-0.05, 0.1), Vector2(-0.2, 0.9), Vector2(0.45, -0.15), Vector2(0.05, -0.15)], c, s, Color(0.85, 0.9, 1.0))
		"skull", "dark":
			var dc := Color(0.75, 0.45, 1.0)
			ci.draw_circle(c + Vector2(0, -0.1) * s, s * 0.6, dc)
			_poly(ci, [Vector2(-0.35, 0.3), Vector2(0.35, 0.3), Vector2(0.3, 0.75), Vector2(-0.3, 0.75)], c, s, dc)
			ci.draw_circle(c + Vector2(-0.22, -0.12) * s, s * 0.14, Color(0.1, 0.0, 0.15))
			ci.draw_circle(c + Vector2(0.22, -0.12) * s, s * 0.14, Color(0.1, 0.0, 0.15))
		"drain":
			ci.draw_circle(c + Vector2(0.4, 0.3) * s, s * 0.28, Color(0.95, 0.2, 0.3))
			_line(ci, [Vector2(-0.8, -0.6), Vector2(-0.2, -0.1), Vector2(0.3, 0.2)], c, s, Color(0.75, 0.45, 1.0), w)
		"time", "shadowstep":
			var tc := Color(0.45, 1.0, 0.85) if kind == "time" else Color(0.65, 0.5, 1.0)
			_poly(ci, [Vector2(-0.5, -0.8), Vector2(0.5, -0.8), Vector2(0.05, 0), Vector2(0.5, 0.8), Vector2(-0.5, 0.8), Vector2(-0.05, 0)], c, s, tc)
			if kind == "shadowstep":
				_line(ci, [Vector2(-0.9, 0.0), Vector2(-0.6, 0.0)], c, s, tc, w)
		"whirl", "sweep":
			ci.draw_arc(c, s * 0.7, 0.0, PI * (1.7 if kind == "whirl" else 1.1), 18, col, w * 1.2)
			ci.draw_arc(c, s * 0.38, PI, PI * 2.4, 12, col, w)
		"slam", "quake":
			_poly(ci, [Vector2(-0.3, -0.8), Vector2(0.3, -0.8), Vector2(0.3, -0.2), Vector2(-0.3, -0.2)], c, s, col)
			_line(ci, [Vector2(0, -0.2), Vector2(0, 0.3)], c, s, col, w)
			_line(ci, [Vector2(-0.8, 0.7), Vector2(-0.4, 0.45), Vector2(0, 0.7), Vector2(0.4, 0.45), Vector2(0.8, 0.7)], c, s, col, w)
		"rage":
			_poly(ci, [Vector2(0, -0.9), Vector2(0.25, -0.25), Vector2(0.9, -0.2), Vector2(0.35, 0.2), Vector2(0.55, 0.85), Vector2(0, 0.45), Vector2(-0.55, 0.85), Vector2(-0.35, 0.2), Vector2(-0.9, -0.2), Vector2(-0.25, -0.25)], c, s, Color(1.0, 0.55, 0.25))
		"aim":
			ci.draw_arc(c, s * 0.65, 0, TAU, 20, col, w)
			ci.draw_circle(c, s * 0.12, col)
			for v in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
				_line(ci, [v * 0.45, v * 0.9], c, s, col, w)
		"arrows":
			for i in 3:
				var off := Vector2(-0.25 + i * 0.25, 0.2 - i * 0.2)
				_line(ci, [Vector2(-0.7, 0.4) + off, Vector2(0.5, -0.4) + off], c, s, col, w * 0.8)
				_poly(ci, [Vector2(0.5, -0.4) + off + Vector2(-0.18, -0.02), Vector2(0.5, -0.4) + off + Vector2(0.12, -0.12), Vector2(0.5, -0.4) + off + Vector2(0.02, 0.16)], c, s, col)
		"burst", "bomb":
			for i in 8:
				var a := i * TAU / 8.0
				_line(ci, [Vector2(cos(a), sin(a)) * 0.3, Vector2(cos(a), sin(a)) * 0.85], c, s, Color(1.0, 0.75, 0.35), w)
			ci.draw_circle(c, s * 0.25, Color(1.0, 0.9, 0.5))
		"bubble":
			ci.draw_arc(c, s * 0.75, 0, TAU, 24, Color(0.55, 0.75, 1.0), w * 1.2)
			ci.draw_circle(c, s * 0.55, Color(0.55, 0.75, 1.0, 0.35))
		"stealth":
			ci.draw_arc(c + Vector2(0, 0.25) * s, s * 0.7, PI * 1.15, PI * 1.85, 14, col, w)
			_line(ci, [Vector2(-0.7, -0.6), Vector2(0.7, 0.6)], c, s, col, w)
		"kick":
			_poly(ci, [Vector2(-0.6, -0.8), Vector2(-0.25, -0.8), Vector2(-0.1, 0.2), Vector2(0.7, 0.25), Vector2(0.75, 0.6), Vector2(-0.35, 0.6)], c, s, col)
		_:
			ci.draw_circle(c, s * 0.4, col)
