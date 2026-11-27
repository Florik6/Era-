class_name SpellVFX
## Visuals of the «Ascension of Power» abilities. AbilityExec / Cataclysm
## call fx(kind, entry, params); the look comes from the ability's "vis"
## block (colour, shape, rune) and its school palette, so every spell has its
## own silhouette: earth throws real rock, necromancy bone and green
## soul-fire, healing golden lotus light, air white streaks, light rays.
## Pure presentation: nothing here changes the rules. Distant effects are
## trimmed by MagicFX.lod_far and the dynamic quality level.

const SCHOOL_FX := {"fire": "fire", "ice": "ice", "lightning": "lightning", "dark": "dark", "spacetime": "time",
	"earth": "earth", "necro": "necro", "heal": "heal", "air": "air", "light": "light"}
const RUNE_OF := {"earth": "stone", "necro": "bone", "heal": "lotus", "air": "wind", "light": "sun",
	"fire": "fire", "ice": "frost", "lightning": "storm", "dark": "sigil", "spacetime": "clock"}

## Era styling: the same spell is drawn as parchment runes in the Middle
## Ages, alchemical violet sigils in the Renaissance, brass-and-steam circles
## in the industrial age, electric schematics today and holograms in the
## future (a tint of the circles + a hologram ring in era V).
const ERA_ACCENT := [Color(1.0, 0.85, 0.6), Color(0.88, 0.78, 1.0), Color(1.0, 0.62, 0.32), Color(0.6, 0.9, 1.0), Color(0.3, 1.0, 0.95)]

static var _cache := {}
static var counts := {}       # kind -> number of calls (tests: every spell really produces visuals)

static func sch(e: Dictionary) -> String:
	return SCHOOL_FX.get(str(e.get("school", "")), "phys")

static func col(e: Dictionary) -> Color:
	var v: Dictionary = e.get("vis", {})
	if v.has("col"):
		return v.col
	return MagicFX.pal(sch(e), 1)

static func era() -> int:
	if Game.world and Game.world.get("era") != null:
		return clampi(int(Game.world.era), 0, 4)
	return clampi(Profile.current_era, 0, 4)

static func era_tint(c: Color) -> Color:
	var t: Color = c.lerp(ERA_ACCENT[era()], 0.28)
	t.a = c.a
	return t

static func rune(e: Dictionary) -> String:
	var v: Dictionary = e.get("vis", {})
	if v.has("rune"):
		return str(v.rune)
	return RUNE_OF.get(str(e.get("school", "")), "sigil")

static func shape(e: Dictionary) -> String:
	return str(e.get("vis", {}).get("shape", ""))

static func _mg():
	return VFX.mgr()

static func _old(s: String) -> bool:
	return s in ["fire", "ice", "lightning", "dark", "time", "earth"]

static func _near_player(p: Vector3, r: float = 30.0) -> bool:
	return Game.player != null and is_instance_valid(Game.player) and Game.player.global_position.distance_to(p) < r

## Impact for any school (old schools use the existing MagicFX layers).
static func impact(pos: Vector3, s: String, r: float, c: Color) -> void:
	var mg = _mg()
	if mg == null:
		return
	if _old(s):
		MagicFX.impact(pos, s, r)
		return
	var k := clampf(r, 0.5, 6.0)
	mg.glow(pos, MagicFX.pal(s, 0), 1.0 + k * 0.8, 0.22)
	match s:
		"necro":
			mg.emit(pos, {"n": int(10 + k * 5), "life": 0.8, "mat": "mix", "col": Color(0.25, 0.55, 0.3, 0.8), "ramp": "smoke", "size": 0.6 + k * 0.2, "v0": 1.0, "v1": 2.5 + k, "grav": Vector3(0, 1.2, 0), "damp": 3.0, "curve": "puff"})
			mg.emit(pos, {"n": int(6 + k * 3), "life": 0.6, "mat": "shard", "col": Color(0.92, 0.9, 0.82), "size": 0.12, "v0": 3.0, "v1": 6.0, "grav": Vector3(0, -9, 0), "ang": 300.0})
		"heal", "light":
			mg.emit(pos, {"n": int(12 + k * 5), "life": 0.7, "mat": "star", "col": MagicFX.pal(s, 3), "size": 0.25, "v0": 1.5, "v1": 3.5 + k, "grav": Vector3(0, 1.5, 0), "damp": 3.0})
			mg.shock(MagicFX.ground_point(pos), k, c, 0.35)
		"air":
			mg.emit(pos, {"n": int(10 + k * 5), "life": 0.4, "mat": "streak", "col": Color(0.95, 1.0, 1.0, 0.8), "size": 0.35, "v0": 4.0, "v1": 8.0 + k, "spread": 180.0, "flat": 0.8, "grav": Vector3.ZERO, "damp": 4.0})
			mg.shock_v(pos, k, c, 0.3)
		_:
			mg.emit(pos, {"n": int(10 + k * 4), "life": 0.5, "mat": "add", "col": c, "size": 0.4, "v0": 2.0, "v1": 5.0, "grav": Vector3.ZERO, "damp": 4.0})
	if r >= 3.0 and _near_player(pos):
		VFX.shake(minf(0.45, r * 0.06))

static func fx(kind: String, e: Dictionary, p: Dictionary) -> void:
	counts[kind] = int(counts.get(kind, 0)) + 1
	var mg = _mg()
	if mg == null:
		return
	var s := sch(e)
	var c := col(e)
	match kind:
		"charge": _charge(e, p, s, c)
		"release":
			var a = p.a
			var hp := MagicFX.hand_pos(a)
			if _old(s):
				MagicFX.release(hp, p.aim, s)
			else:
				mg.glow(hp, MagicFX.pal(s, 0), 0.9, 0.15)
				mg.emit(hp, {"n": 10, "life": 0.35, "mat": "star" if s in ["heal", "light"] else "add", "col": c, "size": 0.25, "v0": 1.5, "v1": 4.0, "dir": p.aim, "spread": 45.0, "grav": Vector3.ZERO, "damp": 5.0})
		"slash":
			var a2 = p.a
			VFX.slash(a2.global_position + Vector3(0, 1.0, 0), a2.facing, float(p.rng), float(p.arc), str(p.anim), c)
			if e.get("vis", {}).has("rune") and float(p.arc) >= 300.0:
				MagicFX.ground_rune(a2.global_position, rune(e), c, float(p.rng), 0.6, 1.5, 0.9)
		"dash":
			var a3 = p.a
			MagicFX.ghost(a3, Color(c.r, c.g, c.b, 0.5), 0.4, p.from)
			MagicFX.ghost(a3, Color(c.r, c.g, c.b, 0.35), 0.35, (p.from + p.to) * 0.5)
			mg.beam(p.from + Vector3(0, 0.9, 0), p.to + Vector3(0, 0.9, 0), c, 0.3, 0.35, false)
			if a3.is_player:
				CombatFeel.speed_lines(0.25, 0.6)
		"blink_out":
			MagicFX.blink_out(p.a, s if _old(s) else "time")
		"blink_in":
			MagicFX.blink_in(p.a, p.from, s if _old(s) else "time")
			if s == "lightning":
				mg.bolt(p.from + Vector3(0, 1.0, 0), p.a.chest(), c, 0.25, 0.08, 2)
		"afterimage":
			MagicFX.ghost(p.a, Color(c.r, c.g, c.b, 0.55), 0.45)
		"shot":
			var pr = p.get("p")
			if pr != null and is_instance_valid(pr) and shape(e) in ["royal", "decisive", "sky_volley"]:
				mg.attach_light(pr, c, 1.4, 4.0, Vector3.ZERO)
				_trail(pr, c)
		"proj": _dress(e, p, s, c)
		"bolt": _bolt(e, p, s, c)
		"beam":
			mg.beam(p.from, p.to, c, 0.35, 0.28, false)
			mg.beam(p.from, p.to, Color(1, 1, 1, 0.9), 0.25, 0.08, false)
			mg.glow(p.to, MagicFX.pal(s, 0), 1.2, 0.25)
			mg.light(p.to, c, 3.0, 6.0, 0.25)
		"cone": _cone(e, p, s, c)
		"nova":
			var gp := MagicFX.ground_point(p.pos)
			mg.shock(gp, float(p.r), c, 0.4)
			match s:
				"ice": MagicFX.freeze_nova(gp, float(p.r))
				"lightning": MagicFX.thunderclap(gp, float(p.r))
				"phys", "earth":
					mg.ground_impact(gp, float(p.r) * 0.6)
					VFX.decal(gp, "crack", float(p.r) * 0.9, 12.0, randf() * TAU)
				_: impact(gp + Vector3(0, 0.5, 0), s, float(p.r) * 0.6, c)
			if e.get("vis", {}).has("rune"):
				MagicFX.ground_rune(gp, rune(e), c, float(p.r), 0.7, 1.2, 1.0)
			if _near_player(gp, 20.0) and float(p.r) >= 4.0:
				VFX.shake(0.25)
		"telegraph":
			var f: Dictionary = p.get("f", {})
			VFX.telegraph(p.pos, float(p.r), float(p.dur), Color(c.r, c.g, c.b, 0.9))
			if e.get("kind", "") == "spell" and not f.get("small", false):
				MagicFX.ground_rune(p.pos, rune(e), era_tint(c), float(p.r), float(p.dur) + 0.3, 1.6, 1.1)
		"blast": _blast(e, p, s, c)
		"wave":
			var gp2 := MagicFX.ground_point(p.pos)
			impact(gp2 + Vector3(0, 0.4, 0), s, float(p.w) * 0.8, c)
			if s == "fire":
				VFX.decal(gp2, "scorch", float(p.w) * 1.2, 10.0, randf() * TAU)
		"ray":
			var big: bool = p.get("big", false)
			mg.beam(p.from, p.to, c, 0.4 if big else 0.28, 0.3 if big else 0.14, false)
			mg.beam(p.from, p.to, Color(1, 1, 1, 0.9), 0.25, 0.06, false)
			impact(p.to, s, 1.4 if big else 0.8, c)
		"buff":
			var t = p.t
			mg.ring(t.global_position + Vector3(0, 0.1, 0), 1.2, c, 0.5)
			mg.emit(t.chest(), {"n": 10, "life": 0.7, "mat": "star" if e.get("kind", "") == "spell" else "add", "col": c, "size": 0.2, "shape": "sphere", "rad": 0.6, "v0": 0.5, "v1": 1.5, "dir": Vector3.UP, "spread": 25.0, "grav": Vector3(0, 1.5, 0)})
			if shape(e) == "stone_skin":
				mg.emit(t.chest(), {"n": 14, "life": 0.5, "mat": "chunk", "col": Color(0.55, 0.47, 0.38), "size": 0.18, "shape": "sphere", "rad": 1.4, "radial": -9.0, "v0": 0.0, "v1": 0.3, "grav": Vector3.ZERO})
		"debuff":
			var t2 = p.t
			if s in ["dark", "necro"]:
				MagicFX.curse_seal(MagicFX.hand_pos(p.a), t2)
			else:
				mg.beam(MagicFX.hand_pos(p.a), t2.chest(), c, 0.25, 0.06, false)
			mg.ring(t2.global_position + Vector3(0, 2.3, 0), 0.5, c, 0.8)
		"heal":
			var t3 = p.t
			mg.emit(t3.global_position + Vector3(0, 0.2, 0), {"n": 16, "life": 1.0, "mat": "star", "col": MagicFX.pal("heal", 3), "size": 0.2, "shape": "ring", "rad": 0.8, "v0": 0.5, "v1": 1.4, "dir": Vector3.UP, "spread": 10.0, "grav": Vector3(0, 1.8, 0)})
			mg.glow(t3.chest(), MagicFX.pal("heal", 0), 1.4, 0.4)
			MagicFX.ground_rune(t3.global_position, "lotus", c, 1.1, 0.9, 0.6, 0.9)
			if p.a != t3:
				mg.beam(MagicFX.hand_pos(p.a), t3.chest(), c, 0.3, 0.1, false)
		"shield":
			var t4 = p.t
			mg.shock_v(t4.chest(), 1.2, c, 0.35)
			if str(e.get("vis", {}).get("shape", "")) == "bone_orbit":
				_orbit(t4, Color(0.92, 0.9, 0.82), float(p.get("dur", 10.0)))
		"summon":
			MagicFX.summon_circle(p.pos, 1.9, c)
			MagicFX.ground_rune(p.pos, rune(e), era_tint(c), 2.2, 1.4, 1.0, 1.2)
			impact(p.pos + Vector3(0, 0.6, 0), s, 1.2, c)
		"decoy":
			MagicFX.ghost(p.a, Color(c.r, c.g, c.b, 0.6), 0.6)
		"banner": _banner(p.pos, float(p.life), c)
		"push":
			mg.shock(p.a.global_position + Vector3(0, 0.3, 0), float(p.r), c, 0.3)
		"mirror":
			MagicFX.time_snap(p.a.global_position, 2.0)
		"pulse":
			mg.shock(p.a.global_position + Vector3(0, 0.5, 0), minf(14.0, float(p.r)), c, 0.8)
			mg.light(p.a.chest(), c, 2.0, 10.0, 0.4)
		"mark":
			_marker(p.pos, c, float(p.get("dur", 6.0)))
		# ----------------------------------------------------- cataclysms
		"cataclysm_start":
			MagicFX.ground_rune(p.pos, rune(e), era_tint(c), float(p.r), 6.0, 0.6, 1.3)
			mg.light(p.pos + Vector3(0, 3, 0), c, 4.0, float(p.r) + 8.0, 1.5)
			if _near_player(p.pos, 45.0):
				VFX.shake(0.3)
				CombatFeel.punch(0.08, 0.4)
		"sun_core":
			_core(p.pos, float(p.dur), "fire", float(p.r) * 0.25)
		"cataclysm_blast":
			VFX.explosion(p.pos + Vector3(0, 1, 0), minf(8.0, float(p.r) * 0.6), c)
			mg.shock(p.pos, float(p.r), c, 0.7)
			mg.flash(p.pos + Vector3(0, 3, 0), c, 0.25, 8.0)
			VFX.decal(p.pos, "scorch", float(p.r) * 0.8, 30.0, randf() * TAU)
			if _near_player(p.pos, 50.0):
				VFX.shake(0.7)
				CombatFeel.ultimate_release(p.pos, c)
		"frost_wave":
			MagicFX.freeze_nova(p.pos, float(p.r))
			VFX.decal(p.pos, "frost", float(p.r), 20.0, 0.0)
		"storm_cloud":
			_cloud(p.pos, float(p.r), float(p.dur), c)
		"sky_bolt":
			MagicFX.sky_strike(p.pos, c, float(p.r))
			if p.get("big", false):
				mg.flash(p.pos + Vector3(0, 4, 0), Color(1, 1, 1), 0.2, 9.0)
				VFX.decal(p.pos, "scorch", 4.0, 20.0, randf() * TAU)
				if _near_player(p.pos, 40.0):
					VFX.shake(0.5)
		"void_crown":
			_crown(p.a, c, float(p.dur))
		"time_pulse":
			MagicFX.time_snap(p.pos, float(p.r))
		"quake_runes":
			for i in 5:
				var an := TAU * i / 5.0
				MagicFX.ground_rune(p.pos + Vector3(cos(an), 0, sin(an)) * float(p.r) * 0.55, "stone", c, 2.2, float(p.dur), 0.8, 1.2)
			mg.emit(p.pos, {"n": 30, "life": 1.6, "mat": "chunk", "col": Color(0.5, 0.43, 0.35), "size": 0.22, "shape": "ring", "rad": float(p.r) * 0.8, "v0": 1.0, "v1": 3.0, "dir": Vector3.UP, "spread": 20.0, "grav": Vector3(0, -6, 0), "expl": 0.2})
		"shockwave":
			var gp3 := MagicFX.ground_point(p.pos)
			mg.shock(gp3 + Vector3(0, 0.2, 0), float(p.r), c, 0.55)
			mg.shock(gp3 + Vector3(0, 0.4, 0), float(p.r) * 0.7, MagicFX.pal(s, 0), 0.45)
			mg.ground_impact(gp3, float(p.r) * 0.5)
			mg.emit(gp3, {"n": 26, "life": 0.9, "mat": "mix", "col": Color(0.55, 0.47, 0.38, 0.8), "ramp": "smoke", "size": 1.2, "shape": "ring", "rad": float(p.r) * 0.9, "v0": 1.0, "v1": 3.0, "dir": Vector3.UP, "spread": 30.0, "grav": Vector3(0, -1, 0), "curve": "puff"})
			VFX.decal(gp3, "crack", float(p.r) * 0.7, 25.0, randf() * TAU)
			if _near_player(gp3, 45.0):
				VFX.shake(0.55 - 0.1 * int(p.get("i", 0)))
		"heaven_seal":
			var m := MagicFX.ground_rune(p.pos, "sun", c, float(p.r) * 0.5, float(p.dur), 0.5, 1.4)
			if m != null:
				m.global_position = p.pos
		"dawn_light":
			mg.shock(p.pos + Vector3(0, 0.3, 0), float(p.r), c, 1.0)
			mg.light(p.pos + Vector3(0, 4, 0), c, 5.0, float(p.r) + 6.0, 1.2)
			MagicFX.ground_rune(p.pos, "lotus", c, float(p.r), 2.5, 0.4, 1.3)

# ------------------------------------------------------------------ pieces
static func _charge(e: Dictionary, p: Dictionary, s: String, c: Color) -> void:
	var a = p.a
	var dur := float(p.dur)
	var tier := int(e.get("tier", 0))
	var big: bool = tier >= 5 or e.get("vis", {}).get("big", false)
	if e.get("kind", "") == "spell":
		if _old(s):
			MagicFX.charge(a, s, dur, big)
		else:
			var mg = _mg()
			if not MagicFX.lod_far(a.global_position, a):
				mg.emit(MagicFX.hand_pos(a), {"n": 14, "life": maxf(0.3, dur), "mat": "star" if s in ["heal", "light"] else "add", "col": c, "size": 0.18, "shape": "sphere", "rad": 0.7, "radial": -6.0, "v0": 0.0, "v1": 0.2, "grav": Vector3.ZERO, "expl": 0.0})
				mg.glow(MagicFX.hand_pos(a), MagicFX.pal(s, 0), 0.7, maxf(0.2, dur))
		if tier >= 3 or big:
			MagicFX.ground_rune(a.global_position, rune(e), era_tint(c), 1.0 + 0.35 * tier, dur + 0.4, 1.1, 0.9 + 0.05 * tier)
		if era() == 4 and not MagicFX.lod_far(a.global_position, a):
			_mg().ring(a.global_position + Vector3(0, 0.15, 0), 1.2 + 0.2 * tier, ERA_ACCENT[4], maxf(0.3, dur))
		if tier == 6 and a.is_player:
			CombatFeel.punch(0.1, 0.8)
	else:
		if e.get("vis", {}).has("rune"):
			MagicFX.ground_rune(a.global_position, rune(e), c, 1.6, dur + 0.3, 1.4, 1.0)
		_mg().glow(a.chest(), c, 1.0, maxf(0.2, dur))

static func _trail(n: Node3D, c: Color) -> void:
	var mg = _mg()
	var em: CPUParticles3D = mg.make_emitter({"n": 14, "life": 0.35, "mat": "add", "col": c, "size": 0.25, "v0": 0.0, "v1": 0.3, "grav": Vector3.ZERO, "curve": "shrink", "local": false, "expl": 0.0})
	if em:
		n.add_child(em)
		em.emitting = true

static func _m(k: String, c: Color, glow := 0.0) -> Material:
	var key := "%s|%s|%.1f" % [k, c.to_html(), glow]
	if not _cache.has(key):
		_cache[key] = MeshLib.mat(c, 0.0, 0.9, glow, glow > 0.0)
	return _cache[key]

## Give a spell projectile its own silhouette.
static func _dress(e: Dictionary, p: Dictionary, s: String, c: Color) -> void:
	var pr = p.get("p")
	if pr == null or not is_instance_valid(pr):
		return
	var sh := shape(e)
	var k := str(p.get("kind", "magic"))
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match k:
		"rock":
			mi.mesh = MeshLib.box(Vector3(0.38, 0.32, 0.42))
			mi.material_override = _m("rock", Color(0.48, 0.41, 0.33))
			mi.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
			var tw := mi.create_tween().set_loops(8)
			tw.tween_property(mi, "rotation:x", mi.rotation.x + TAU, 0.6)
			_trail(pr, Color(0.6, 0.52, 0.42, 0.7))
		"bone":
			mi.mesh = MeshLib.cyl(0.0, 0.09, 0.8, 5)
			mi.material_override = _m("bone", Color(0.92, 0.9, 0.82), 0.4)
			mi.rotation_degrees = Vector3(-90, 0, 0)
			_trail(pr, Color(0.45, 0.85, 0.55, 0.8))
		_:
			match sh:
				"needle", "fire_arrow", "light_spear", "ember":
					var length := 1.4 if sh == "light_spear" else (0.9 if sh == "fire_arrow" else 0.55)
					mi.mesh = MeshLib.cyl(0.0, 0.07 if sh != "light_spear" else 0.12, length, 6)
					mi.material_override = _m("glow", c, 3.0)
					mi.rotation_degrees = Vector3(-90, 0, 0)
					if sh == "light_spear":
						_mg().attach_light(pr, c, 1.6, 5.0, Vector3.ZERO)
				"crescent":
					mi.mesh = MeshLib.torus(0.35, 0.42)
					mi.material_override = _m("glow", Color(0.92, 1.0, 1.0, 0.8), 2.0)
					mi.scale = Vector3(1.2, 0.25, 0.7)
				"shards":
					mi.mesh = MeshLib.cyl(0.0, 0.08, 0.5, 4)
					mi.material_override = MagicFX.ice_mat()
					mi.rotation_degrees = Vector3(-90, 0, 0)
				_:
					mi.free()
					return
	pr.add_child(mi)

static func _bolt(e: Dictionary, p: Dictionary, s: String, c: Color) -> void:
	var mg = _mg()
	var from: Vector3 = p.from
	var to: Vector3 = p.to
	match shape(e):
		"drain":
			if p.has("t"):
				MagicFX.drain(p.t, p.a)
			else:
				mg.beam(from, to, c, 0.2, 0.08, true)
		"chains":
			for i in 3:
				mg.beam(from + Vector3(0, 0.1 * i, 0), to + Vector3(0, -0.2 + 0.2 * i, 0), Color(0.55, 0.25, 0.8), 0.6, 0.06, true)
			if p.has("t"):
				MagicFX.ground_rune(p.t.global_position, "sigil", c, 1.2, 2.5, 1.0, 1.0)
		"frost_touch":
			mg.emit(from, {"n": 12, "life": 0.4, "mat": "shard", "col": Color(0.85, 0.96, 1.0, 0.9), "size": 0.12, "v0": 4.0, "v1": 7.0, "dir": (to - from).normalized(), "spread": 25.0, "grav": Vector3.ZERO, "ang": 300.0})
			mg.beam(from, to, c, 0.2, 0.12, false)
		_:
			if s == "lightning":
				VFX.lightning(from, to, c, 0.18, 0.07, 2)
			else:
				mg.beam(from, to, c, 0.25, 0.1, false)
	if not p.get("miss", false):
		impact(to, s, 0.7, c)

static func _cone(e: Dictionary, p: Dictionary, s: String, c: Color) -> void:
	var mg = _mg()
	var a = p.a
	var aim: Vector3 = p.aim
	var r := float(p.r)
	var o: Vector3 = a.chest() + aim * 0.5
	var spread := float(p.ang) * 0.5
	match s:
		"fire":
			mg.emit(o, {"n": int(18 + r * 5), "life": 0.5, "mat": "add", "ramp": "fire", "size": 0.7, "v0": r * 1.5, "v1": r * 2.6, "dir": aim, "spread": spread, "grav": Vector3(0, 2, 0), "damp": 2.0, "curve": "shrink"})
		"lightning":
			for i in 4:
				var d := aim.rotated(Vector3.UP, deg_to_rad(randf_range(-spread, spread)))
				mg.bolt(o, o + d * r + Vector3(0, -0.8, 0), c, 0.18, 0.06, 1)
		"earth", "phys":
			mg.emit(o + Vector3(0, -0.8, 0), {"n": int(14 + r * 4), "life": 0.7, "mat": "chunk", "col": Color(0.52, 0.45, 0.36), "size": 0.2, "v0": r * 1.2, "v1": r * 2.2, "dir": aim + Vector3(0, 0.3, 0), "spread": spread, "grav": Vector3(0, -12, 0)})
			mg.emit(o + Vector3(0, -0.8, 0), {"n": 10, "life": 0.8, "mat": "mix", "col": Color(0.6, 0.53, 0.42, 0.7), "ramp": "smoke", "size": 0.9, "v0": r * 0.8, "v1": r * 1.4, "dir": aim, "spread": spread, "grav": Vector3.ZERO, "damp": 3.0, "curve": "puff"})
		"air", "time":
			mg.emit(o, {"n": int(14 + r * 3), "life": 0.4, "mat": "streak", "col": Color(c.r, c.g, c.b, 0.8), "size": 0.4, "v0": r * 2.0, "v1": r * 3.0, "dir": aim, "spread": spread, "grav": Vector3.ZERO})
			mg.shock_v(o, r * 0.5, c, 0.3, aim)
		"dark", "necro":
			mg.emit(o, {"n": int(12 + r * 3), "life": 0.8, "mat": "mix", "col": Color(0.25, 0.08, 0.35, 0.8) if s == "dark" else Color(0.2, 0.45, 0.25, 0.8), "ramp": "smoke", "size": 0.8, "v0": r * 1.0, "v1": r * 1.8, "dir": aim, "spread": spread, "grav": Vector3.ZERO, "damp": 2.0, "curve": "puff"})
		_:
			mg.emit(o, {"n": int(12 + r * 3), "life": 0.5, "mat": "add", "col": c, "size": 0.4, "v0": r * 1.4, "v1": r * 2.4, "dir": aim, "spread": spread, "grav": Vector3.ZERO, "damp": 2.0})

static func _blast(e: Dictionary, p: Dictionary, s: String, c: Color) -> void:
	var mg = _mg()
	var f: Dictionary = p.get("f", {})
	var pos: Vector3 = p.pos
	var r := float(p.r)
	if f.get("sky", false):
		if s == "fire":
			var top := pos + Vector3(randf_range(-3, 3), 14.0, randf_range(-3, 3))
			mg.beam(top, pos, Color(1.0, 0.6, 0.2), 0.25, 0.4, false)
			MagicFX.explode(pos + Vector3(0, 0.5, 0), r, c)
			VFX.decal(pos, "scorch", r * 1.1, 18.0, randf() * TAU)
		else:
			MagicFX.sky_strike(pos, c, r)
	elif f.get("fist", false):
		_fist(pos, r)
	elif f.get("pillar", false):
		mg.beam(pos + Vector3(0, 24.0, 0), pos, c, 0.55, r * 0.6, false)
		mg.beam(pos + Vector3(0, 24.0, 0), pos, Color(1, 1, 1), 0.4, r * 0.2, false)
		mg.flash(pos + Vector3(0, 2, 0), c, 0.25, 7.0)
		impact(pos + Vector3(0, 0.5, 0), "light", r, c)
	elif f.get("hand", false):
		_hand(pos)
	else:
		if s == "phys":
			mg.ground_impact(pos, r * 0.7)
			mg.shock(pos + Vector3(0, 0.2, 0), r, c, 0.35)
			VFX.decal(pos, "crack", r, 12.0, randf() * TAU)
		else:
			impact(pos + Vector3(0, 0.5, 0), s, r, c)
	if f.get("big", false) and _near_player(pos, 35.0):
		VFX.shake(0.35)

## «Кулак горы»: a stone fist drops from the sky and smashes the ground.
static func _fist(pos: Vector3, r: float) -> void:
	var mg = _mg()
	var n := Node3D.new()
	mg.add_child(n)
	n.global_position = pos + Vector3(0, 12.0, 0)
	var stone := _m("rock", Color(0.48, 0.41, 0.33))
	MeshLib.part(n, MeshLib.box(Vector3(1.0, 1.0, 1.0)), stone, Vector3.ZERO, Vector3(0, 20, 0), Vector3(r * 0.8, r * 0.7, r * 0.8), false)
	for i in 4:
		MeshLib.part(n, MeshLib.box(Vector3(1, 1, 1)), stone, Vector3(-r * 0.3 + r * 0.2 * i, -r * 0.42, r * 0.28), Vector3(0, 20, 0), Vector3(r * 0.17, r * 0.3, r * 0.22), false)
	var tw := n.create_tween()
	tw.tween_property(n, "global_position", pos + Vector3(0, r * 0.4, 0), 0.22).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		mg.ground_impact(pos, r)
		mg.emit(pos, {"n": 24, "life": 0.9, "mat": "chunk", "col": Color(0.5, 0.43, 0.35), "size": 0.25, "v0": 3.0, "v1": 8.0, "dir": Vector3.UP, "spread": 70.0, "grav": Vector3(0, -14, 0)})
		VFX.decal(pos, "crack", r * 1.3, 20.0, randf() * TAU)
		if _near_player(pos, 30.0):
			VFX.shake(0.45))
	tw.tween_interval(0.5)
	tw.tween_property(n, "global_position", pos + Vector3(0, -r, 0), 0.4)
	tw.tween_callback(n.queue_free)

## «Рука могилы»: a bony hand bursts from the ground and closes.
static func _hand(pos: Vector3) -> void:
	var mg = _mg()
	var n := Node3D.new()
	mg.add_child(n)
	n.global_position = pos + Vector3(0, -1.6, 0)
	var bone := _m("bone", Color(0.9, 0.88, 0.8), 0.3)
	for i in 5:
		var an := TAU * i / 5.0
		var fing := MeshLib.part(n, MeshLib.cyl(0.02, 0.07, 1.3, 5), bone, Vector3(cos(an) * 0.45, 0.65, sin(an) * 0.45), Vector3(rad_to_deg(sin(an)) * 0.4, 0, -rad_to_deg(cos(an)) * 0.4), Vector3.ONE, false)
		fing.rotation = Vector3(sin(an) * 0.35, 0, -cos(an) * 0.35)
	var tw := n.create_tween()
	tw.tween_property(n, "global_position", pos, 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.3)
	tw.tween_property(n, "global_position", pos + Vector3(0, -1.6, 0), 0.4)
	tw.tween_callback(n.queue_free)
	mg.emit(pos, {"n": 12, "life": 0.8, "mat": "mix", "col": Color(0.3, 0.55, 0.32, 0.8), "ramp": "smoke", "size": 0.7, "v0": 0.5, "v1": 1.5, "grav": Vector3(0, 1, 0), "curve": "puff"})

static func _banner(pos: Vector3, life: float, c: Color) -> void:
	var mg = _mg()
	var n := Node3D.new()
	mg.add_child(n)
	n.global_position = MagicFX.ground_point(pos)
	MeshLib.part(n, MeshLib.cyl(0.04, 0.05, 3.0, 6), _m("pole", Color(0.35, 0.25, 0.15)), Vector3(0, 1.5, 0), Vector3.ZERO, Vector3.ONE, true)
	var cloth := MeshLib.part(n, MeshLib.box(Vector3(0.9, 1.2, 0.03)), _m("cloth", c), Vector3(0.47, 2.3, 0), Vector3.ZERO, Vector3.ONE, true)
	var tw := cloth.create_tween().set_loops(int(life / 1.2) + 1)
	tw.tween_property(cloth, "rotation:y", 0.25, 0.6)
	tw.tween_property(cloth, "rotation:y", -0.15, 0.6)
	mg.ring(n.global_position + Vector3(0, 0.1, 0), 7.0, c, 0.8)
	var t2 := n.create_tween()
	t2.tween_interval(life)
	t2.tween_callback(n.queue_free)

static func _marker(pos: Vector3, c: Color, dur: float) -> void:
	var mg = _mg()
	var n := MeshInstance3D.new()
	n.mesh = MeshLib.torus(0.35, 0.45)
	n.material_override = _m("glow", c, 3.0)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mg.add_child(n)
	n.global_position = pos + Vector3(0, 2.6, 0)
	var tw := n.create_tween()
	tw.tween_property(n, "rotation:y", TAU * 3.0, dur)
	tw.tween_callback(n.queue_free)

static func _core(pos: Vector3, dur: float, s: String, size: float) -> void:
	var mg = _mg()
	var ball := MeshInstance3D.new()
	ball.mesh = MeshLib.sphere(1.0, 16, 10)
	ball.material_override = MagicFX.orb_mat(s)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mg.add_child(ball)
	ball.global_position = pos
	ball.scale = Vector3.ONE * 0.2
	mg.light(pos, MagicFX.pal(s, 1), 6.0, 22.0, dur + 0.3)
	var tw := ball.create_tween()
	tw.tween_property(ball, "scale", Vector3.ONE * size, dur).set_ease(Tween.EASE_IN)
	tw.tween_property(ball, "global_position", pos + Vector3(0, -8.0, 0), 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(ball.queue_free)

static func _cloud(pos: Vector3, r: float, dur: float, c: Color) -> void:
	var mg = _mg()
	var n := Node3D.new()
	mg.add_child(n)
	n.global_position = pos
	var disc := MeshLib.part(n, MeshLib.cyl(r, r * 0.8, 1.6, 16), _m("cloud", Color(0.16, 0.17, 0.22, 0.85)), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var em: CPUParticles3D = mg.make_emitter({"n": 24, "life": 2.0, "mat": "mix", "col": Color(0.2, 0.22, 0.28, 0.8), "ramp": "smoke", "size": 3.0, "shape": "sphere", "rad": r * 0.8, "v0": 0.1, "v1": 0.5, "grav": Vector3.ZERO, "expl": 0.0, "local": true})
	if em:
		n.add_child(em)
		em.emitting = true
	var tw := n.create_tween()
	tw.tween_interval(dur)
	tw.tween_property(disc, "scale", Vector3(0.01, 0.01, 0.01), 0.6)
	tw.tween_callback(n.queue_free)

static func _crown(a, c: Color, dur: float) -> void:
	if a == null or not is_instance_valid(a):
		return
	var mg = _mg()
	var f := MagicFX.Follow.new()
	f.life = dur
	f.target = a
	f.offset = Vector3(0, 2.6 * a._scale(), 0)
	mg.add_child(f)
	f.global_position = a.global_position + f.offset
	for i in 7:
		var an := TAU * i / 7.0
		MeshLib.part(f, MeshLib.cyl(0.0, 0.09, 0.6, 4), _m("glow", c, 2.5), Vector3(cos(an) * 0.45, 0.25, sin(an) * 0.45), Vector3.ZERO, Vector3.ONE, false)
	var ring := MeshLib.part(f, MeshLib.torus(0.42, 0.5), _m("glow", c, 2.5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Bones orbiting the caster while the bone shield holds.
static func _orbit(t, c: Color, dur: float) -> void:
	var mg = _mg()
	var f := MagicFX.Follow.new()
	f.life = dur
	f.target = t
	f.offset = Vector3(0, 1.0, 0)
	mg.add_child(f)
	f.global_position = t.global_position + f.offset
	var spin := Node3D.new()
	f.add_child(spin)
	for i in 5:
		var an := TAU * i / 5.0
		MeshLib.part(spin, MeshLib.cyl(0.03, 0.05, 0.55, 5), _m("bone", c, 0.3), Vector3(cos(an) * 0.9, sin(an * 2.0) * 0.25, sin(an) * 0.9), Vector3(0, 0, 70), Vector3.ONE, false)
	var tw := spin.create_tween().set_loops(int(dur / 1.2) + 1)
	tw.tween_property(spin, "rotation:y", TAU, 1.2).from(0.0)

## «Светлячок»: a light that follows its caster and exposes hidden enemies.
static func light_orb(a, life: float, r: float) -> Node3D:
	var orb := LightOrb.new()
	orb.owner_a = a
	orb.life = life
	orb.reveal_r = r
	var host: Node = Game.world.fx_root if Game.world else (Engine.get_main_loop() as SceneTree).root
	host.add_child(orb)
	orb.global_position = a.global_position + Vector3(0.6, 2.2, 0.0)
	return orb

class LightOrb extends Node3D:
	var owner_a = null
	var life := 60.0
	var reveal_r := 6.0
	var revealed := 0
	var _t := 0.0
	func _ready() -> void:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.sphere(0.14, 8, 6)
		mi.material_override = MeshLib.mat(Color(1.0, 0.95, 0.65), 0.0, 1.0, 4.0, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.92, 0.7)
		l.light_energy = 1.4
		l.omni_range = 9.0
		l.shadow_enabled = false
		add_child(l)
	func _process(dt: float) -> void:
		life -= dt
		if life <= 0.0 or owner_a == null or not is_instance_valid(owner_a) or owner_a.is_dead:
			queue_free()
			return
		var want: Vector3 = owner_a.global_position + Vector3(0.7 * cos(Time.get_ticks_msec() * 0.0015), 2.2 + 0.15 * sin(Time.get_ticks_msec() * 0.003), 0.7 * sin(Time.get_ticks_msec() * 0.0015))
		global_position = global_position.lerp(want, minf(1.0, dt * 4.0))
		_t += dt
		if _t >= 0.5:
			_t = 0.0
			for t in Game.actors_near(owner_a.global_position, reveal_r):
				if t != owner_a and not t.is_dead and t.statuses.has("stealth") and Game.is_enemy(owner_a, t):
					t.statuses.erase("stealth")
					t.apply_status("revealed", 3.0)
					revealed += 1
