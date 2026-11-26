class_name ResonanceFX
## Visuals of Magical Resonance: reaction bursts, reaction zones, the
## catastrophe sphere and the anomaly it leaves behind. Visual only — the
## rules live in Resonance and Zone. Everything goes through the VFX manager
## budgets (pooled particles, light cap, decal cap) and scales with the
## particle quality; distant reactions keep only their core layer.

const COL := {
	"steam": Color(0.92, 0.95, 1.0),
	"node": Color(0.55, 0.75, 1.0),
	"vortex": Color(0.75, 0.25, 0.95),
	"instability": Color(0.35, 1.0, 0.85),
	"anomaly": Color(0.85, 0.4, 1.0),
}

static func mgr():
	return MagicFX.mgr()

static func color(kind: String) -> Color:
	return COL.get(kind, Color(1, 1, 1))

## One-shot burst when two magics meet.
static func reaction_burst(kind: String, pos: Vector3, r: float) -> void:
	var mg = mgr()
	if mg == null:
		return
	var far := MagicFX.lod_far(pos)
	var fx: int = 0 if far else mg.fx
	var gp := MagicFX.ground_point(pos)
	var c := color(kind)
	mg.glow(pos + Vector3(0, 0.8, 0), c, 2.0 + r, 0.3)
	mg.shock(gp, r * 1.2, c, 0.5)
	match kind:
		"steam":
			mg.emit(pos + Vector3(0, 0.5, 0), {"n": int(18 + r * 6), "life": 1.6, "mat": "mix", "col": Color(0.95, 0.97, 1.0, 0.7), "ramp": "smoke", "size": 1.4 + r * 0.4, "v0": 3.0, "v1": 6.0 + r, "grav": Vector3(0, 1.6, 0), "damp": 2.5, "curve": "puff", "shape": "sphere", "rad": 0.6, "critical": true})
			mg.emit(pos + Vector3(0, 0.4, 0), {"n": int(14 + r * 4), "life": 0.6, "mat": "streak", "col": Color(0.85, 0.95, 1.0), "size": 0.3, "v0": 6.0, "v1": 11.0, "dir": Vector3.UP, "spread": 85.0, "grav": Vector3(0, -6.0, 0), "curve": "shrink"})
			if fx >= 1:
				mg.emit(pos + Vector3(0, 0.3, 0), {"n": 10, "life": 0.9, "mat": "add", "col": Color(1.0, 0.6, 0.3), "size": 0.5, "v0": 2.0, "v1": 4.0, "grav": Vector3(0, 1.0, 0), "damp": 3.0, "curve": "shrink"})
				mg.emit(pos + Vector3(0, 0.3, 0), {"n": 10, "life": 0.9, "mat": "add", "col": Color(0.5, 0.85, 1.0), "size": 0.5, "v0": 2.0, "v1": 4.0, "grav": Vector3(0, 1.0, 0), "damp": 3.0, "curve": "shrink"})
			mg.light(pos + Vector3(0, 1.2, 0), Color(1.0, 0.95, 0.9), 3.0, 6.0 + r, 0.35)
			mg.decal(gp, "wet", r * 2.2, 25.0, randf() * TAU)
			VFX.shake(minf(0.45, 0.12 + r * 0.05))
		"node":
			for i in (3 if fx == 0 else 6):
				var an := randf() * TAU
				VFX.lightning(pos + Vector3(0, 1.6, 0), gp + Vector3(cos(an) * r, 0.1, sin(an) * r), c, 0.25, 0.07, 2)
			mg.light(pos + Vector3(0, 1.6, 0), c, 4.0, 7.0 + r, 0.3)
			mg.decal(gp, "crack", r * 1.6, 20.0, randf() * TAU)
		"vortex":
			mg.emit(pos + Vector3(0, 0.6, 0), {"n": int(16 + r * 5), "life": 0.9, "mat": "add", "ramp": "fire", "size": 0.5, "shape": "ring", "rad": r, "radial": -6.0, "tan": 8.0, "v0": 0.5, "v1": 1.5, "grav": Vector3(0, 2.0, 0), "curve": "shrink", "critical": true})
			mg.emit(pos + Vector3(0, 0.6, 0), {"n": int(10 + r * 3), "life": 1.2, "mat": "mix", "col": Color(0.22, 0.04, 0.3, 0.8), "ramp": "smoke", "size": 1.2, "shape": "ring", "rad": r * 0.9, "radial": -4.0, "tan": 6.0, "v0": 0.3, "v1": 1.0, "grav": Vector3(0, 1.2, 0), "curve": "puff"})
			mg.light(pos + Vector3(0, 1.0, 0), Color(0.9, 0.35, 0.8), 3.0, 6.0 + r, 0.4)
			mg.decal(gp, "scorch", r * 2.0, 22.0, randf() * TAU)
		"instability":
			mg.shock_v(pos + Vector3(0, 1.2, 0), r * 1.3, c, 0.45)
			if fx >= 1:
				mg.shock_v(pos + Vector3(0, 1.2, 0), r * 0.8, Color(0.9, 1.0, 0.95, 0.8), 0.6)
			mg.emit(pos + Vector3(0, 1.0, 0), {"n": int(12 + r * 3), "life": 1.4, "mat": "star", "col": c, "size": 0.25, "shape": "sphere", "rad": r * 0.8, "v0": 0.1, "v1": 0.6, "grav": Vector3.ZERO, "ramp": "pop"})
			mg.light(pos + Vector3(0, 1.2, 0), c, 3.0, 6.0 + r, 0.4)

## Visual dressing of the reaction zones (returns false for other kinds).
static func build_zone(z) -> bool:
	var mg = mgr()
	if mg == null:
		return false
	var kind: String = z.kind
	if not kind in ["steam", "node", "vortex", "instability", "anomaly"]:
		return false
	var r: float = z.radius
	var vis: Node3D = z._vis
	var c := color(kind)
	var ems: Array = []
	match kind:
		"steam":
			ems.append({"n": int(r * 5.0), "life": 2.4, "mat": "mix", "col": Color(0.93, 0.95, 1.0, 0.45), "ramp": "smoke", "size": 2.2, "shape": "ring", "rad": r * 0.7, "tan": 1.5, "v0": 0.2, "v1": 0.6, "dir": Vector3.UP, "spread": 30.0, "grav": Vector3(0, 0.5, 0), "curve": "puff", "pos": Vector3(0, 0.6, 0)})
		"node":
			MagicFX.ground_rune(Vector3(0, 0.08, 0), "storm", c, r, 0.0, 1.6, 1.0, vis)
			var orb := MeshInstance3D.new()
			orb.mesh = MeshLib.sphere(0.45, 12, 8)
			orb.material_override = MagicFX.orb_mat("lightning")
			orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			orb.position.y = 1.6
			vis.add_child(orb)
			orb.create_tween().set_loops().tween_property(orb, "position:y", 1.9, 0.6).set_trans(Tween.TRANS_SINE)
			ems.append({"n": 12, "life": 0.18, "mat": "streak", "col": MagicFX.pal("lightning", 0), "size": 0.35, "shape": "sphere", "rad": 0.5, "v0": 3.0, "v1": 7.0, "spread": 180.0, "grav": Vector3.ZERO, "pos": Vector3(0, 1.7, 0)})
			mg.attach_light(vis, c, 1.6, r + 3.0, Vector3(0, 1.7, 0))
		"vortex":
			MagicFX.ground_rune(Vector3(0, 0.08, 0), "sigil", c, r, 0.0, 2.4, 1.0, vis)
			ems.append({"n": int(r * 8.0), "life": 1.0, "mat": "add", "ramp": "fire", "size": 0.45, "shape": "ring", "rad": r * 0.95, "radial": -3.5, "tan": 7.0, "v0": 0.2, "v1": 0.6, "grav": Vector3(0, 2.2, 0), "curve": "shrink", "pos": Vector3(0, 0.3, 0)})
			ems.append({"n": int(r * 4.0), "life": 1.6, "mat": "mix", "col": Color(0.2, 0.03, 0.28, 0.7), "ramp": "smoke", "size": 1.3, "shape": "ring", "rad": r * 0.8, "radial": -2.5, "tan": 5.0, "v0": 0.1, "v1": 0.4, "grav": Vector3(0, 1.4, 0), "curve": "puff", "pos": Vector3(0, 0.4, 0)})
			mg.attach_light(vis, Color(0.9, 0.35, 0.8), 1.4, r + 3.0, Vector3(0, 1.0, 0))
		"instability":
			MagicFX.ground_rune(Vector3(0, 0.08, 0), "clock", c, r, 0.0, -1.4, 1.1, vis)
			var dome := MeshInstance3D.new()
			dome.mesh = MagicFX.pmesh("hemi")
			dome.material_override = MagicFX.smat("fresnel", {"col": Color(0.35, 1.0, 0.85, 0.14), "power": 1.8, "bands": 6.0}, "dome|instability")
			dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dome.scale = Vector3(r, r * 0.8, r)
			vis.add_child(dome)
			var tw := dome.create_tween().set_loops()
			tw.tween_property(dome, "scale", Vector3(r * 1.06, r * 0.85, r * 1.06), 0.23)
			tw.tween_property(dome, "scale", Vector3(r * 0.94, r * 0.75, r * 0.94), 0.31)
			ems.append({"n": int(r * 6.0), "life": 1.8, "mat": "star", "col": c, "size": 0.2, "shape": "sphere", "rad": r * 0.8, "v0": 0.05, "v1": 0.3, "grav": Vector3.ZERO, "ramp": "pop", "pos": Vector3(0, 1.2, 0)})
		"anomaly":
			MagicFX.ground_rune(Vector3(0, 0.08, 0), "rift", c, r, 0.0, 0.5, 0.9, vis)
			MagicFX.ground_rune(Vector3(0, 0.1, 0), "clock", Color(0.5, 1.0, 0.9), r * 0.6, 0.0, -0.8, 0.7, vis)
			ems.append({"n": int(r * 4.0), "life": 2.6, "mat": "add", "col": c, "size": 0.18, "shape": "sphere", "rad": r * 0.8, "v0": 0.1, "v1": 0.5, "dir": Vector3.UP, "spread": 60.0, "grav": Vector3(0, 0.6, 0), "ramp": "pop", "pos": Vector3(0, 0.8, 0)})
			mg.attach_light(vis, c, 1.2, r + 2.0, Vector3(0, 1.5, 0))
			mg.distort(z.global_position + Vector3(0, 1.5, 0), r * 1.2, z.life, Color(0.6, 0.3, 1.0, 0.12), true)
	for o in ems:
		var od: Dictionary = o
		od["local"] = true
		od["expl"] = 0.0
		var e: CPUParticles3D = mg.make_emitter(od)
		if e:
			vis.add_child(e)
			e.position = od.get("pos", Vector3.ZERO)
			e.emitting = true
	vis.set_meta("fx", true)
	return true

## The catastrophe: rune circle, a sphere that swells and collapses,
## a sky beam and a ground shockwave. Flash and shake follow the camera
## settings (Settings.flash_strength / camera shake switch).
static func catastrophe(pos: Vector3, r: float, kind: String) -> void:
	var mg = mgr()
	if mg == null:
		return
	var gp := MagicFX.ground_point(pos)
	var c := color(kind)
	MagicFX.ground_rune(gp + Vector3(0, 0.07, 0), "rift", c, r * 1.1, 4.0, 1.8, 1.4)
	MagicFX.ground_rune(gp + Vector3(0, 0.09, 0), "clock", Color(0.7, 1.0, 0.95), r * 0.7, 4.0, -2.4, 1.2)
	var sph := MeshInstance3D.new()
	sph.mesh = MeshLib.sphere(1.0, 24, 16)
	sph.material_override = MagicFX.smat("fresnel", {"col": Color(c.r, c.g, c.b, 0.35), "power": 1.6, "bands": 4.0})
	sph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mg.add_child(sph)
	sph.global_position = gp + Vector3(0, 0.5, 0)
	sph.scale = Vector3.ONE * 0.4
	var tw := sph.create_tween()
	tw.tween_property(sph, "scale", Vector3.ONE * r, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(sph, "scale", Vector3.ONE * r * 1.08, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sph, "scale", Vector3.ONE * 0.2, 0.35).set_ease(Tween.EASE_IN)
	tw.tween_callback(sph.queue_free)
	VFX.beam(gp + Vector3(0, 70, 0), gp, c, 1.6, 0.9, false)
	mg.shock(gp, r * 1.6, c, 1.2)
	mg.glow(gp + Vector3(0, 2.0, 0), c, r * 1.5, 0.6 * Settings.flash_k())
	mg.light(gp + Vector3(0, 3.0, 0), c, 6.0 * Settings.flash_k(), r * 3.0, 1.8)
	mg.emit(gp + Vector3(0, 1.0, 0), {"n": 40, "life": 2.2, "mat": "star", "col": c, "size": 0.35, "shape": "sphere", "rad": r * 0.6, "v0": 2.0, "v1": 6.0, "grav": Vector3(0, 0.5, 0), "damp": 1.0, "ramp": "pop", "critical": true})
	mg.decal(gp, "rune", r * 1.8, 60.0, randf() * TAU)
	VFX.shake(0.7)

## Two opposed projectiles collided in the air.
static func projectile_clash(pos: Vector3, ca: Color, cb: Color) -> void:
	var mg = mgr()
	if mg == null:
		return
	mg.glow(pos, ca.lerp(cb, 0.5), 2.2, 0.2)
	mg.emit(pos, {"n": 14, "life": 0.5, "mat": "streak", "col": ca, "size": 0.3, "v0": 5.0, "v1": 10.0, "grav": Vector3(0, -6.0, 0), "curve": "shrink", "critical": true})
	mg.emit(pos, {"n": 14, "life": 0.5, "mat": "streak", "col": cb, "size": 0.3, "v0": 5.0, "v1": 10.0, "grav": Vector3(0, -6.0, 0), "curve": "shrink", "critical": true})
	mg.shock_v(pos, 1.6, Color(1, 1, 1, 0.8), 0.3)
