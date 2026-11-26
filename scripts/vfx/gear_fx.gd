class_name GearFX
## Animated look of special equipment, layered on top of the weapon model:
##  - cursed (an active curse): dark violet wisps rising from the weapon and
##    a cold violet rim on the blade;
##  - legendary: slow golden motes and a warm rim;
##  - mythic: crimson-gold sparks and a pulsing crimson rim;
##  - living: veins that pulse with the weapon's growth stage and path
##    (dawn gold / dusk violet / neutral cyan-green).
## Cheap by design: one unique rim material per weapon, a small emitter
## culled beyond VIS_RANGE, nothing at the lowest particle setting.

const VIS_RANGE := 26.0
## Each named legendary / mythic weapon has its own colour and ornament.
const ART_LOOK := {
	"ashen_verdict": [Color(1.0, 0.45, 0.12), "embers"], "lightning_rain": [Color(0.55, 0.75, 1.0), "arcs"],
	"comet_dance": [Color(1.0, 0.25, 0.3), "tail"], "deferred_shot": [Color(0.95, 0.8, 0.4), "gear"],
	"ninth_thunder": [Color(0.45, 0.7, 1.0), "coil"], "mechanist_ricochet": [Color(0.9, 0.2, 0.15), "gear"],
	"polar_volley": [Color(0.5, 0.95, 1.0), "coil"], "silent_city": [Color(0.8, 0.85, 0.95), "tail"],
	"silent_cut": [Color(0.8, 0.85, 0.95), "tail"], "phase_echo": [Color(1.0, 0.85, 0.45), "rings"],
	"dual_trajectory": [Color(0.7, 0.5, 1.0), "rings"], "lesser_eclipse": [Color(0.45, 0.1, 0.65), "orb"],
	"threads_of_fate": [Color(1.0, 0.85, 0.5), "rings"], "steam_storm": [Color(0.75, 0.85, 1.0), "coil"],
	"null_protocol": [Color(0.4, 1.0, 0.55), "orb"], "first_era_rift": [Color(0.55, 0.35, 1.0), "orb"],
}

static func kind_of(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	if it.get("curse", {}) is Dictionary and it.get("curse", {}).size() > 0:
		return "cursed"
	if it.get("living", {}) is Dictionary and it.get("living", {}).size() > 0:
		return "living"
	if str(it.get("mythic", "")) != "" or int(it.get("rarity", 0)) >= 5:
		return "mythic"
	if int(it.get("rarity", 0)) >= 4:
		return "legendary"
	return ""

static func color_for(it: Dictionary, kind: String) -> Color:
	if it.has("art") and ART_LOOK.has(str(it.art)):
		return ART_LOOK[str(it.art)][0]
	match kind:
		"cursed":
			return Color(0.42, 0.08, 0.7)
		"legendary":
			return Color(1.0, 0.78, 0.3)
		"mythic":
			return Color(1.0, 0.25, 0.25)
		"living":
			var path: String = it.get("living", {}).get("path", "")
			return Color(1.0, 0.82, 0.35) if path == "dawn" else (Color(0.65, 0.25, 1.0) if path == "dusk" else Color(0.3, 1.0, 0.8))
	return Color(1, 1, 1)

static func _ornament(weapon: Node3D, kind: String, c: Color) -> void:
	var gm := MeshLib.glow(c, 2.2)
	match kind:
		"gear":
			MeshLib.part(weapon, MeshLib.torus(0.06, 0.09), gm, Vector3(0, 0.0, -0.12), Vector3(0, 90, 0), Vector3.ONE, false)
		"coil":
			for i in 3:
				MeshLib.part(weapon, MeshLib.torus(0.04, 0.055), gm, Vector3(0, 0, -0.25 - i * 0.12), Vector3(90, 0, 0), Vector3.ONE, false)
		"rings":
			var rn := Node3D.new()
			weapon.add_child(rn)
			rn.position = Vector3(0, 0, -0.35)
			MeshLib.part(rn, MeshLib.torus(0.14, 0.16), gm, Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
			MeshLib.part(rn, MeshLib.torus(0.1, 0.115), gm, Vector3.ZERO, Vector3(0, 0, 90), Vector3.ONE, false)
			rn.create_tween().set_loops().tween_property(rn, "rotation:z", TAU, 3.0).as_relative()
		"orb":
			var o := MeshInstance3D.new()
			o.mesh = MeshLib.sphere(0.07, 10, 6)
			o.material_override = gm
			o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			weapon.add_child(o)
			o.position = Vector3(0, 0.05, -0.1)
		"embers", "arcs", "tail":
			MeshLib.part(weapon, MeshLib.box(Vector3(0.012, 0.012, 0.7)), gm, Vector3(0, 0.03, -0.45), Vector3.ZERO, Vector3.ONE, false)

## Dress a freshly built weapon node. Returns the kind applied ("" = none).
static func attach(weapon: Node3D, it: Dictionary) -> String:
	var kind := kind_of(it)
	if kind == "" or weapon == null:
		return ""
	var c := color_for(it, kind)
	var stage: int = int(it.get("living", {}).get("stage", 0)) if kind == "living" else 0
	var rim := MagicFX.smat("fresnel", {"col": Color(c.r, c.g, c.b, 0.35 if kind != "legendary" else 0.25), "power": 2.2, "bands": 1.0}) as ShaderMaterial
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = rim
	weapon.set_meta("gear_fx", kind)
	weapon.set_meta("gear_rim", rim)
	if it.has("art") and ART_LOOK.has(str(it.art)):
		_ornament(weapon, String(ART_LOOK[str(it.art)][1]), c)
		weapon.set_meta("art_look", str(it.art))
	# pulsing rim for mythic and living weapons (living pulses faster as it grows)
	if kind in ["mythic", "living", "cursed"]:
		var period := 1.6 if kind == "mythic" else (2.4 - 0.4 * stage if kind == "living" else 3.0)
		var hi := 0.55 if kind != "cursed" else 0.7
		var lo := 0.15
		var tw := weapon.create_tween().set_loops()
		tw.tween_method(func(v: float): rim.set_shader_parameter("col", Color(c.r, c.g, c.b, v)), lo, hi, period * 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_method(func(v: float): rim.set_shader_parameter("col", Color(c.r, c.g, c.b, v)), hi, lo, period * 0.5).set_trans(Tween.TRANS_SINE)
	var pk: float = float(Settings.profile().get("particles", 0.7))
	var mg = MagicFX.mgr()
	if mg == null or pk < 0.5:
		return kind
	var o := {}
	match kind:
		"cursed":
			o = {"n": 7, "life": 1.6, "mat": "mix", "col": Color(0.2, 0.05, 0.3, 0.6), "ramp": "smoke", "size": 0.32, "shape": "box", "box": Vector3(0.03, 0.03, 0.4), "v0": 0.2, "v1": 0.5, "dir": Vector3.UP, "spread": 25.0, "grav": Vector3(0, 0.5, 0), "curve": "puff"}
		"legendary":
			o = {"n": 5, "life": 1.4, "mat": "add", "col": Color(1.0, 0.85, 0.4, 0.9), "size": 0.05, "shape": "box", "box": Vector3(0.02, 0.02, 0.4), "v0": 0.05, "v1": 0.2, "dir": Vector3.UP, "spread": 40.0, "grav": Vector3(0, 0.3, 0), "ramp": "pop"}
		"mythic":
			o = {"n": 8, "life": 0.7, "mat": "streak", "col": Color(1.0, 0.45, 0.25), "size": 0.08, "shape": "box", "box": Vector3(0.02, 0.02, 0.45), "v0": 0.4, "v1": 1.2, "spread": 180.0, "grav": Vector3(0, -1.0, 0), "curve": "shrink"}
		"living":
			o = {"n": 3 + stage * 2, "life": 1.2, "mat": "add", "col": Color(c.r, c.g, c.b, 0.85), "size": 0.06, "shape": "box", "box": Vector3(0.02, 0.02, 0.4), "v0": 0.05, "v1": 0.25, "dir": Vector3.UP, "spread": 50.0, "grav": Vector3(0, 0.2, 0), "ramp": "pop"}
	o["local"] = false
	o["expl"] = 0.0
	var e: CPUParticles3D = mg.make_emitter(o)
	if e:
		e.name = "GearFX"
		weapon.add_child(e)
		e.position = Vector3(0, 0, -0.45)
		e.visibility_range_end = VIS_RANGE
		e.emitting = true
	return kind
