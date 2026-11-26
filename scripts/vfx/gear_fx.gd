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
