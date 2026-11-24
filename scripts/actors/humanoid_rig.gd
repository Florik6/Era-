class_name HumanoidRig
extends Node3D
## Procedural articulated humanoid (characters, bandits, knights, robots,
## skeletons, golems, trolls, mech colossi) with code-driven animation:
## locomotion, melee combos, bows, guns, casting, blocking, dodge rolls,
## hit reactions, deaths, stealth crouch and surrender.

const SKINS := [Color(0.98, 0.85, 0.72), Color(0.92, 0.74, 0.58), Color(0.78, 0.58, 0.42), Color(0.55, 0.38, 0.26), Color(0.36, 0.24, 0.17)]
const HAIR_COLORS := [Color(0.15, 0.1, 0.07), Color(0.42, 0.26, 0.12), Color(0.8, 0.62, 0.3), Color(0.6, 0.2, 0.1), Color(0.85, 0.85, 0.85), Color(0.08, 0.08, 0.1)]
const CLOTH_COLORS := [Color(0.55, 0.18, 0.15), Color(0.18, 0.32, 0.55), Color(0.25, 0.45, 0.22), Color(0.45, 0.38, 0.28), Color(0.35, 0.2, 0.45), Color(0.2, 0.2, 0.22), Color(0.75, 0.68, 0.5)]

var build_type := "normal"
var j := {}                 # joints
var parts := {}             # named mesh parts
var extras: Array = []      # gear-specific meshes (rebuilt on gear change)
var weapon_node: Node3D = null
var offhand_node: Node3D = null
var weapon_model := ""
var weapon_cat := "unarmed"
var two_handed := false
var look := {}

# animation state set by the owning actor
var move_speed := 0.0       # 0..~1.6 normalized
var action := ""            # current action animation
var action_p := 0.0         # 0..1
var blocking := false
var aiming := false
var dodging := false
var dodge_p := 0.0
var dead := false
var crouch := false
var yielding := false
var casting := false
var hit_t := 0.0
var _phase := 0.0
var _dead_t := 0.0
var _lod_acc := 0.0
var _breath := 0.0
var skin_mat: Material
var cloth_mat: Material
var pants_mat: Material
var boot_mat: Material
var glow_color := Color(0, 0, 0, 0)
var broken_parts := {}

func setup(l: Dictionary) -> void:
	look = l
	build_type = l.get("build", "normal")
	var skin: Color = l.get("skin_color", SKINS[clampi(l.get("skin", 1), 0, SKINS.size() - 1)])
	var cloth: Color = l.get("cloth_color", CLOTH_COLORS[clampi(l.get("cloth", 0), 0, CLOTH_COLORS.size() - 1)])
	glow_color = l.get("glow", Color(0, 0, 0, 0))
	if build_type == "skeleton":
		skin = Color(0.88, 0.85, 0.75)
	elif build_type in ["robot", "golem", "colossus"]:
		skin = l.get("body", Color(0.55, 0.57, 0.6))
	elif build_type == "bulky":
		skin = l.get("body", Color(0.45, 0.55, 0.4))
	var metal = build_type in ["robot", "colossus"] or l.get("metal", false)
	skin_mat = MeshLib.mat(skin, 0.7 if metal else 0.0, 0.4 if metal else 0.8)
	cloth_mat = MeshLib.mat(cloth)
	pants_mat = MeshLib.mat(l.get("pants_color", Color(0.22, 0.2, 0.2)))
	boot_mat = MeshLib.mat(Color(0.2, 0.14, 0.1))
	_build_skeleton()
	scale = Vector3.ONE * l.get("scale", 1.0)

func _build_skeleton() -> void:
	var thick := 1.0
	var width := 1.0
	match build_type:
		"bulky":
			thick = 1.7
			width = 1.55
		"golem", "colossus":
			thick = 1.8
			width = 1.6
		"skeleton":
			thick = 0.5
	if look.get("female", false):
		width *= 0.9
	var body := MeshLib.pivot(self, Vector3.ZERO, "body")
	j.body = body
	var hips := MeshLib.pivot(body, Vector3(0, 0.95, 0), "hips")
	j.hips = hips
	var blocky := build_type in ["golem", "colossus"]
	# pelvis
	parts.pelvis = MeshLib.part(hips, MeshLib.box(Vector3(0.34 * width, 0.2, 0.22 * width)), pants_mat, Vector3(0, -0.02, 0))
	# legs
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var leg := MeshLib.pivot(hips, Vector3(0.1 * sx * width, -0.08, 0), "leg_" + side)
		j["leg_" + side] = leg
		var thigh_m: Mesh = MeshLib.box(Vector3(0.15, 0.46, 0.15) * Vector3(thick, 1, thick)) if blocky else MeshLib.capsule(0.07 * thick, 0.46)
		parts["thigh_" + side] = MeshLib.part(leg, thigh_m, pants_mat, Vector3(0, -0.22, 0))
		var knee := MeshLib.pivot(leg, Vector3(0, -0.44, 0), "knee_" + side)
		j["knee_" + side] = knee
		var shin_m: Mesh = MeshLib.box(Vector3(0.14, 0.44, 0.14) * Vector3(thick, 1, thick)) if blocky else MeshLib.capsule(0.06 * thick, 0.44)
		parts["shin_" + side] = MeshLib.part(knee, shin_m, pants_mat, Vector3(0, -0.21, 0))
		parts["foot_" + side] = MeshLib.part(knee, MeshLib.box(Vector3(0.11 * thick, 0.08, 0.24 * thick)), boot_mat, Vector3(0, -0.43, -0.05))
	# torso
	var spine := MeshLib.pivot(hips, Vector3(0, 0.06, 0), "spine")
	j.spine = spine
	var chest := MeshLib.pivot(spine, Vector3(0, 0.18, 0), "chest")
	j.chest = chest
	if build_type == "skeleton":
		parts.torso = MeshLib.part(chest, MeshLib.cyl(0.03, 0.03, 0.5, 5), skin_mat, Vector3(0, 0.1, 0))
		for i in 4:
			MeshLib.part(chest, MeshLib.torus(0.1, 0.13 - i * 0.008), skin_mat, Vector3(0, 0.25 - i * 0.08, 0), Vector3(0, 0, 0), Vector3(1.3, 1, 0.8))
	else:
		var tm: Mesh = MeshLib.box(Vector3(0.42 * width, 0.5, 0.25 * width)) if build_type != "normal" else MeshLib.capsule(0.21 * width, 0.56)
		parts.torso = MeshLib.part(chest, tm, cloth_mat, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.62) if build_type == "normal" else Vector3.ONE)
	# head
	var neck := MeshLib.pivot(chest, Vector3(0, 0.38, 0), "neck")
	j.neck = neck
	var head := MeshLib.pivot(neck, Vector3(0, 0.13, 0), "head")
	j.head = head
	_build_head(head)
	# arms
	for side in ["l", "r"]:
		var sx2 := -1.0 if side == "l" else 1.0
		var arm := MeshLib.pivot(chest, Vector3(0.25 * sx2 * width, 0.3, 0), "arm_" + side)
		j["arm_" + side] = arm
		var up_m: Mesh = MeshLib.box(Vector3(0.13, 0.3, 0.13) * Vector3(thick, 1, thick)) if blocky else MeshLib.capsule(0.055 * thick, 0.3)
		parts["upper_" + side] = MeshLib.part(arm, up_m, cloth_mat, Vector3(0, -0.14, 0))
		var elbow := MeshLib.pivot(arm, Vector3(0, -0.29, 0), "elbow_" + side)
		j["elbow_" + side] = elbow
		var fo_m: Mesh = MeshLib.box(Vector3(0.12, 0.28, 0.12) * Vector3(thick, 1, thick)) if blocky else MeshLib.capsule(0.048 * thick, 0.28)
		parts["fore_" + side] = MeshLib.part(elbow, fo_m, skin_mat if build_type != "normal" else cloth_mat, Vector3(0, -0.13, 0))
		var hand := MeshLib.pivot(elbow, Vector3(0, -0.28, 0), "hand_" + side)
		j["hand_" + side] = hand
		parts["fist_" + side] = MeshLib.part(hand, MeshLib.box(Vector3(0.08, 0.09, 0.09) * (thick if build_type != "skeleton" else 1.0)), skin_mat, Vector3(0, -0.02, 0))
	if build_type == "colossus":
		_build_colossus_extras()
	if glow_color.a > 0.0:
		var eye_l := OmniLight3D.new()
		eye_l.light_color = glow_color
		eye_l.light_energy = 0.6
		eye_l.omni_range = 3.0
		eye_l.position = Vector3(0, 0.05, -0.2)
		eye_l.shadow_enabled = false
		head.add_child(eye_l)

func _build_head(head: Node3D) -> void:
	var dark := MeshLib.mat(Color(0.06, 0.05, 0.05))
	match build_type:
		"skeleton":
			parts.head = MeshLib.part(head, MeshLib.sphere(0.12, 8, 5), skin_mat, Vector3(0, 0.02, 0))
			for sx in [-0.045, 0.045]:
				MeshLib.part(head, MeshLib.sphere(0.03, 5, 3), dark, Vector3(sx, 0.03, -0.1), Vector3.ZERO, Vector3.ONE, false)
			MeshLib.part(head, MeshLib.box(Vector3(0.12, 0.05, 0.1)), skin_mat, Vector3(0, -0.09, -0.03))
		"robot", "colossus":
			parts.head = MeshLib.part(head, MeshLib.box(Vector3(0.22, 0.22, 0.24)), skin_mat, Vector3(0, 0.02, 0))
			var vc: Color = glow_color if glow_color.a > 0 else Color(1.0, 0.25, 0.2)
			MeshLib.part(head, MeshLib.box(Vector3(0.18, 0.05, 0.02)), MeshLib.glow(vc, 3.0), Vector3(0, 0.04, -0.125), Vector3.ZERO, Vector3.ONE, false)
			MeshLib.part(head, MeshLib.cyl(0.008, 0.008, 0.15, 4), skin_mat, Vector3(0.08, 0.18, 0))
		"golem":
			parts.head = MeshLib.part(head, MeshLib.box(Vector3(0.26, 0.22, 0.24)), skin_mat, Vector3(0, 0.02, 0))
			var gc: Color = glow_color if glow_color.a > 0 else Color(1.0, 0.7, 0.2)
			for sx in [-0.06, 0.06]:
				MeshLib.part(head, MeshLib.box(Vector3(0.05, 0.04, 0.02)), MeshLib.glow(gc, 3.0), Vector3(sx, 0.04, -0.125), Vector3.ZERO, Vector3.ONE, false)
		"bulky":
			parts.head = MeshLib.part(head, MeshLib.sphere(0.15, 8, 6), skin_mat, Vector3(0, 0.0, -0.04), Vector3.ZERO, Vector3(1.1, 0.9, 1.1))
			for sx in [-0.06, 0.06]:
				MeshLib.part(head, MeshLib.box(Vector3(0.03, 0.03, 0.02)), MeshLib.glow(Color(1, 0.9, 0.3), 1.5), Vector3(sx, 0.03, -0.18), Vector3.ZERO, Vector3.ONE, false)
				MeshLib.part(head, MeshLib.prism(Vector3(0.03, 0.08, 0.03)), MeshLib.mat(Color(0.95, 0.92, 0.8)), Vector3(sx, -0.1, -0.15), Vector3(180, 0, 0), Vector3.ONE, false)
		_:
			parts.head = MeshLib.part(head, MeshLib.sphere(0.13, 10, 7), skin_mat, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(0.95, 1.05, 1.0))
			for sx in [-0.045, 0.045]:
				var e := MeshLib.part(head, MeshLib.box(Vector3(0.03, 0.025, 0.01)), dark, Vector3(sx, 0.04, -0.122), Vector3.ZERO, Vector3.ONE, false)
				e.visibility_range_end = 30.0
			var nose := MeshLib.part(head, MeshLib.box(Vector3(0.03, 0.05, 0.04)), skin_mat, Vector3(0, 0.0, -0.13), Vector3.ZERO, Vector3.ONE, false)
			nose.visibility_range_end = 30.0
			_build_hair(head)

func _build_hair(head: Node3D) -> void:
	var hc: Color = look.get("hair_color_value", HAIR_COLORS[clampi(look.get("hair_color", 0), 0, HAIR_COLORS.size() - 1)])
	var hm := MeshLib.mat(hc)
	var style: int = look.get("hair", 1)
	if style >= 1:
		parts.hair = MeshLib.part(head, MeshLib.sphere(0.138, 10, 6), hm, Vector3(0, 0.05, 0.01), Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
	if style == 2:
		MeshLib.part(head, MeshLib.box(Vector3(0.26, 0.3, 0.08)), hm, Vector3(0, -0.06, 0.1))
	elif style == 3:
		MeshLib.part(head, MeshLib.cyl(0.03, 0.04, 0.25, 6), hm, Vector3(0, -0.04, 0.15), Vector3(25, 0, 0))
	elif style == 4:
		MeshLib.part(head, MeshLib.box(Vector3(0.04, 0.08, 0.26)), hm, Vector3(0, 0.15, 0.0))
	var beard: int = look.get("beard", 0)
	if beard == 1:
		MeshLib.part(head, MeshLib.box(Vector3(0.18, 0.06, 0.08)), hm, Vector3(0, -0.08, -0.08))
	elif beard == 2:
		MeshLib.part(head, MeshLib.prism(Vector3(0.2, 0.16, 0.1)), hm, Vector3(0, -0.13, -0.07), Vector3(180, 0, 0))

func _build_colossus_extras() -> void:
	var brass := MeshLib.mat(Color(0.75, 0.55, 0.3), 0.8, 0.35)
	var boiler := MeshLib.pivot(j.chest, Vector3(0, 0.15, 0.25), "boiler")
	j.boiler = boiler
	MeshLib.part(boiler, MeshLib.cyl(0.2, 0.2, 0.55, 10), brass)
	MeshLib.part(boiler, MeshLib.sphere(0.08, 8, 4), MeshLib.glow(Color(1.0, 0.45, 0.1), 2.5), Vector3(0, 0, 0.2))
	for sx in [-0.12, 0.12]:
		MeshLib.part(boiler, MeshLib.cyl(0.04, 0.04, 0.4, 6), MeshLib.mat(Color(0.2, 0.2, 0.2), 0.6, 0.5), Vector3(sx, 0.4, 0))
	for side in ["l", "r"]:
		MeshLib.part(j["hand_" + side], MeshLib.box(Vector3(0.22, 0.22, 0.22)), brass, Vector3(0, -0.06, 0))
		MeshLib.part(j["arm_" + side], MeshLib.sphere(0.13, 8, 5), brass, Vector3(0, 0.02, 0))

## Visual damage for damageable boss parts.
func break_part(part_name: String) -> void:
	if broken_parts.has(part_name):
		return
	broken_parts[part_name] = true
	var node: Node3D = null
	match part_name:
		"left_arm": node = j.get("elbow_l")
		"right_arm": node = j.get("elbow_r")
		"boiler": node = j.get("boiler")
	if node:
		node.visible = false

# ---------------------------------------------------------------- gear
func set_gear(equip: Dictionary, faction_color: Color = Color(0, 0, 0, 0), cape: bool = false) -> void:
	for e in extras:
		if is_instance_valid(e):
			e.queue_free()
	extras.clear()
	if weapon_node:
		weapon_node.queue_free()
		weapon_node = null
	if offhand_node:
		offhand_node.queue_free()
		offhand_node = null
	var body_it: Dictionary = equip.get("body", {})
	var head_it: Dictionary = equip.get("head", {})
	var main_it: Dictionary = equip.get("main", {})
	var off_it: Dictionary = equip.get("off", {})
	var armor_model: String = ItemDB.base(body_it.get("base", "")).get("model", look.get("armor", "")) if not body_it.is_empty() else look.get("armor", "")
	_apply_armor(armor_model, body_it, faction_color)
	var hm: String = ItemDB.base(head_it.get("base", "")).get("model", "") if not head_it.is_empty() else look.get("hat", "")
	if hm != "" and build_type in ["normal", "bulky"]:
		_apply_helmet(hm, head_it)
	if parts.has("hair"):
		parts.hair.visible = hm == "" or hm in ["hat", "bandana", "cap", "goggles", "tophat"]
	weapon_model = ""
	weapon_cat = "unarmed"
	two_handed = false
	if not main_it.is_empty():
		var b := ItemDB.base(main_it.base)
		weapon_model = b.get("model", "sword")
		weapon_cat = b.get("cat", "sword")
		two_handed = b.get("two_h", false)
		weapon_node = WeaponModels.build(weapon_model, main_it)
		if weapon_cat == "bow":
			j.hand_l.add_child(weapon_node)
		else:
			j.hand_r.add_child(weapon_node)
		weapon_node.position = Vector3(0, -0.05, 0)
	if not off_it.is_empty():
		var ob := ItemDB.base(off_it.base)
		offhand_node = WeaponModels.build(ob.get("model", "shield_round"), off_it)
		j.hand_l.add_child(offhand_node)
		offhand_node.position = Vector3(-0.08, -0.05, 0)
	if cape or faction_color.a > 0.5:
		var cc: Color = faction_color if faction_color.a > 0 else Color(0.5, 0.1, 0.1)
		var cp := MeshLib.pivot(j.chest, Vector3(0, 0.36, 0.14), "cape")
		var cm := MeshLib.part(cp, MeshLib.box(Vector3(0.44, 0.9 if cape else 0.55, 0.03)), MeshLib.mat(cc), Vector3(0, -0.45 if cape else -0.27, 0.02))
		cm.rotation_degrees.x = 8
		j.cape = cp
		extras.append(cp)

func _apply_armor(model: String, it: Dictionary, faction_color: Color) -> void:
	var torso_c: Color = (cloth_mat as StandardMaterial3D).albedo_color
	var metal := 0.0
	var rough := 0.85
	var sleeves: Material = cloth_mat
	var legs: Material = pants_mat
	var rar: int = it.get("rarity", 0)
	match model:
		"leather", "jacket":
			torso_c = Color(0.42, 0.28, 0.16) if model == "leather" else Color(0.2, 0.22, 0.2)
		"chain":
			torso_c = Color(0.55, 0.56, 0.58)
			metal = 0.7
			rough = 0.5
			_extra(j.hips, MeshLib.cyl(0.2, 0.24, 0.3, 8), MeshLib.mat(torso_c, 0.7, 0.5), Vector3(0, -0.15, 0))
		"plate", "cuirass", "cursed":
			torso_c = Color(0.72, 0.74, 0.78) if model != "cursed" else Color(0.18, 0.22, 0.2)
			metal = 0.85
			rough = 0.35
			for sx in [-0.27, 0.27]:
				_extra(j.chest, MeshLib.sphere(0.11, 8, 5), MeshLib.mat(torso_c, 0.85, 0.35), Vector3(sx, 0.32, 0), Vector3.ZERO, Vector3(1.2, 0.7, 1.2))
			if model == "plate" or model == "cursed":
				legs = MeshLib.mat(torso_c.darkened(0.1), 0.8, 0.4)
				sleeves = MeshLib.mat(torso_c, 0.85, 0.35)
			if model == "cursed":
				_extra(j.chest, MeshLib.box(Vector3(0.05, 0.3, 0.02)), MeshLib.glow(Color(0.3, 1.0, 0.5), 2.0), Vector3(0, 0.12, -0.16))
		"robe":
			_extra(j.hips, MeshLib.cyl(0.2, 0.32, 0.8, 10), cloth_mat, Vector3(0, -0.38, 0))
			_extra(j.chest, MeshLib.box(Vector3(0.08, 0.5, 0.02)), MeshLib.mat(Color(0.9, 0.8, 0.4), 0.5, 0.5), Vector3(0, 0.1, -0.15))
		"coat":
			torso_c = Color(0.3, 0.22, 0.16)
			_extra(j.hips, MeshLib.cyl(0.21, 0.27, 0.6, 8), MeshLib.mat(torso_c), Vector3(0, -0.28, 0))
			sleeves = MeshLib.mat(torso_c)
		"steam_suit":
			torso_c = Color(0.7, 0.52, 0.3)
			metal = 0.8
			rough = 0.4
			sleeves = MeshLib.mat(torso_c, 0.8, 0.4)
			legs = MeshLib.mat(Color(0.35, 0.3, 0.25), 0.5, 0.6)
			_extra(j.chest, MeshLib.cyl(0.11, 0.11, 0.4, 8), MeshLib.mat(Color(0.6, 0.45, 0.25), 0.8, 0.35), Vector3(0, 0.12, 0.2))
			for sx in [-0.28, 0.28]:
				_extra(j.chest, MeshLib.sphere(0.12, 8, 5), MeshLib.mat(torso_c, 0.8, 0.4), Vector3(sx, 0.32, 0))
		"vest":
			torso_c = Color(0.3, 0.33, 0.25)
			_extra(j.chest, MeshLib.box(Vector3(0.4, 0.38, 0.28)), MeshLib.mat(torso_c), Vector3(0, 0.1, 0))
			for sx in [-0.1, 0.1]:
				_extra(j.chest, MeshLib.box(Vector3(0.08, 0.1, 0.05)), MeshLib.mat(torso_c.darkened(0.2)), Vector3(sx, 0.02, -0.15))
		"energy_armor", "exo":
			torso_c = Color(0.22, 0.24, 0.3) if model == "energy_armor" else Color(0.4, 0.42, 0.45)
			metal = 0.7
			rough = 0.35
			sleeves = MeshLib.mat(torso_c, 0.7, 0.35)
			legs = MeshLib.mat(torso_c.darkened(0.2), 0.6, 0.4)
			var ec: Color = Color(0.3, 0.9, 1.0) if rar < 2 else ItemDB.RARITY_COLORS[rar]
			_extra(j.chest, MeshLib.box(Vector3(0.03, 0.4, 0.02)), MeshLib.glow(ec, 2.5), Vector3(0, 0.1, -0.15))
			for sx in [-0.27, 0.27]:
				_extra(j.chest, MeshLib.box(Vector3(0.16, 0.1, 0.2)), MeshLib.mat(torso_c, 0.7, 0.35), Vector3(sx, 0.33, 0))
			if model == "exo":
				for side in ["l", "r"]:
					_extra(j["knee_" + side], MeshLib.box(Vector3(0.04, 0.4, 0.04)), MeshLib.mat(Color(0.6, 0.6, 0.62), 0.9, 0.3), Vector3(0.09, -0.2, 0))
		"robot", "android":
			torso_c = (skin_mat as StandardMaterial3D).albedo_color if model == "robot" else Color(0.92, 0.92, 0.95)
			metal = 0.6
			rough = 0.35
			sleeves = MeshLib.mat(torso_c, 0.6, 0.35)
			legs = sleeves
		"bones":
			return
		"doublet":
			torso_c = Color(0.5, 0.15, 0.2)
	if faction_color.a > 0.5 and model in ["", "cloth", "leather", "robe", "coat", "jacket"]:
		torso_c = torso_c.lerp(faction_color, 0.55)
	var tmat := MeshLib.mat(torso_c, metal, rough)
	if parts.has("torso"):
		parts.torso.material_override = tmat
	for side in ["l", "r"]:
		if parts.has("upper_" + side):
			parts["upper_" + side].material_override = sleeves if model != "" else cloth_mat
		if build_type == "normal" and parts.has("fore_" + side):
			parts["fore_" + side].material_override = sleeves if model in ["plate", "steam_suit", "energy_armor", "exo", "robot", "android", "cursed", "coat"] else skin_mat
		if parts.has("thigh_" + side):
			parts["thigh_" + side].material_override = legs
			parts["shin_" + side].material_override = legs
	_extra(j.hips, MeshLib.box(Vector3(0.36, 0.05, 0.24)), MeshLib.mat(Color(0.25, 0.16, 0.08)), Vector3(0, 0.07, 0))

func _apply_helmet(model: String, it: Dictionary) -> void:
	var h: Node3D = j.head
	var steel := MeshLib.mat(Color(0.7, 0.72, 0.76), 0.85, 0.35)
	match model:
		"hood":
			_extra(h, MeshLib.sphere(0.155, 10, 6), MeshLib.mat((cloth_mat as StandardMaterial3D).albedo_color.darkened(0.25)), Vector3(0, 0.04, 0.02), Vector3.ZERO, Vector3(1.0, 1.0, 1.05))
		"kettle":
			_extra(h, MeshLib.sphere(0.145, 10, 6), steel, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
			_extra(h, MeshLib.cyl(0.24, 0.24, 0.02, 12), steel, Vector3(0, 0.04, 0))
		"greathelm":
			_extra(h, MeshLib.cyl(0.15, 0.15, 0.3, 10), steel, Vector3(0, 0.03, 0))
			_extra(h, MeshLib.box(Vector3(0.22, 0.02, 0.02)), MeshLib.mat(Color(0.05, 0.05, 0.05)), Vector3(0, 0.05, -0.15))
		"morion":
			_extra(h, MeshLib.sphere(0.15, 10, 6), steel, Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(0.9, 0.9, 1.3))
			_extra(h, MeshLib.box(Vector3(0.02, 0.1, 0.3)), steel, Vector3(0, 0.18, 0))
		"hat", "tophat":
			var hc := Color(0.15, 0.12, 0.12) if model == "tophat" else Color(0.25, 0.15, 0.2)
			_extra(h, MeshLib.cyl(0.25 if model == "hat" else 0.2, 0.25 if model == "hat" else 0.2, 0.02, 12), MeshLib.mat(hc), Vector3(0, 0.1, 0))
			_extra(h, MeshLib.cyl(0.12, 0.13, 0.12 if model == "hat" else 0.26, 10), MeshLib.mat(hc), Vector3(0, 0.17 if model == "hat" else 0.23, 0))
			if model == "hat":
				_extra(h, MeshLib.box(Vector3(0.02, 0.04, 0.3)), MeshLib.mat(Color(0.95, 0.95, 0.9)), Vector3(0.1, 0.22, 0.05), Vector3(30, 0, 0))
		"bandana":
			_extra(h, MeshLib.sphere(0.14, 8, 5), MeshLib.mat(Color(0.7, 0.1, 0.1)), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1, 0.7, 1))
		"cap":
			_extra(h, MeshLib.sphere(0.14, 8, 5), MeshLib.mat(Color(0.25, 0.25, 0.28)), Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
			_extra(h, MeshLib.box(Vector3(0.16, 0.015, 0.1)), MeshLib.mat(Color(0.2, 0.2, 0.22)), Vector3(0, 0.08, -0.15))
		"pith":
			_extra(h, MeshLib.sphere(0.16, 10, 6), MeshLib.mat(Color(0.85, 0.8, 0.65)), Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1.15, 0.75, 1.25))
		"goggles":
			for sx in [-0.05, 0.05]:
				_extra(h, MeshLib.cyl(0.035, 0.035, 0.03, 8), MeshLib.mat(Color(0.6, 0.4, 0.2), 0.8, 0.3), Vector3(sx, 0.08, -0.12), Vector3(90, 0, 0))
		"tac_helm":
			_extra(h, MeshLib.sphere(0.155, 10, 6), MeshLib.mat(Color(0.3, 0.32, 0.26)), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1, 0.85, 1.05))
		"visor":
			_extra(h, MeshLib.sphere(0.158, 10, 6), MeshLib.mat(Color(0.2, 0.22, 0.28), 0.7, 0.3), Vector3(0, 0.03, 0))
			var vc: Color = Color(0.3, 0.9, 1.0) if it.get("rarity", 0) < 2 else ItemDB.RARITY_COLORS[it.rarity]
			_extra(h, MeshLib.box(Vector3(0.24, 0.06, 0.03)), MeshLib.glow(vc, 2.5), Vector3(0, 0.04, -0.14))

func _extra(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> void:
	extras.append(MeshLib.part(parent, mesh, m, pos, rot, scl))

# ---------------------------------------------------------------- animation
func trigger(act: String) -> void:
	action = act
	action_p = 0.0

func on_hit(_dir: Vector3 = Vector3.ZERO, _heavy: bool = false) -> void:
	hit_t = 0.25

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam and not dead:
		var d2 := cam.global_position.distance_squared_to(global_position)
		if d2 > 1600.0:
			_lod_acc += delta
			if _lod_acc < 0.066:
				return
			delta = _lod_acc
			_lod_acc = 0.0
	animate(delta)

func animate(delta: float) -> void:
	var t := {}  # joint -> Vector3 target rotation
	var rate := 12.0
	hit_t = maxf(0.0, hit_t - delta)
	_breath += delta * 2.0
	# --- base / locomotion
	var sp := clampf(move_speed, 0.0, 1.8)
	if sp > 0.05:
		_phase += delta * (5.5 + 4.5 * sp)
	var s := sin(_phase)
	var c := cos(_phase)
	var amp := 0.55 * minf(sp, 1.3)
	t.leg_l = Vector3(s * amp, 0, 0)
	t.leg_r = Vector3(-s * amp, 0, 0)
	t.knee_l = Vector3(-maxf(0.0, -c) * amp * 1.3 - 0.05, 0, 0)
	t.knee_r = Vector3(-maxf(0.0, c) * amp * 1.3 - 0.05, 0, 0)
	t.arm_l = Vector3(-s * amp * 0.7, 0, -0.12)
	t.arm_r = Vector3(s * amp * 0.7, 0, 0.12)
	t.elbow_l = Vector3(0.25 + sp * 0.3, 0, 0)
	t.elbow_r = Vector3(0.25 + sp * 0.3, 0, 0)
	t.spine = Vector3(0.08 * sp + sin(_breath) * 0.015, 0, 0)
	t.neck = Vector3(-0.05 * sp, 0, 0)
	t.hand_r = Vector3(0, 0, 0)
	t.hand_l = Vector3(0, 0, 0)
	var hips_y := 0.95 + absf(s) * 0.04 * sp
	# weapon carry poses
	match weapon_cat:
		"staff", "spear":
			t.arm_r = Vector3(0.3, 0, 0.15)
			t.elbow_r = Vector3(0.9, 0, 0)
			t.hand_r = Vector3(0.6, 0, 0)
		"bow":
			t.arm_l = Vector3(0.25 - s * amp * 0.3, 0, -0.15)
			t.elbow_l = Vector3(0.6, 0, 0)
		"firearm":
			if two_handed:
				t.arm_r = Vector3(0.7, 0, 0.1)
				t.elbow_r = Vector3(0.9, 0, 0)
				t.hand_r = Vector3(-0.9, 0, 0)
				t.arm_l = Vector3(0.9, 0, 0.5)
				t.elbow_l = Vector3(1.0, 0, 0)
			else:
				t.elbow_r = Vector3(0.5, 0, 0)
				t.hand_r = Vector3(-0.3, 0, 0)
		"heavy":
			if two_handed:
				t.arm_r = Vector3(0.5, 0, 0.1)
				t.elbow_r = Vector3(1.0, 0, 0)
				t.hand_r = Vector3(0.9, 0, 0)
				t.arm_l = Vector3(0.6, 0, 0.45)
				t.elbow_l = Vector3(1.1, 0, 0)
		"sword", "dagger":
			t.elbow_r = Vector3(0.6, 0, 0)
			t.hand_r = Vector3(0.35, 0, 0)
	if aiming:
		_pose_aim(t)
	if blocking:
		t.arm_l = Vector3(1.25, 0.0, 0.55)
		t.elbow_l = Vector3(1.2, 0, 0)
		t.hand_l = Vector3(0, -0.4, 0)
		if offhand_node == null:
			t.arm_r = Vector3(1.3, 0, -0.4)
			t.elbow_r = Vector3(1.0, 0, 0)
			t.hand_r = Vector3(-1.2, 0, 0.9)
		rate = 18.0
	if crouch:
		hips_y -= 0.25
		t.spine.x += 0.35
		t.leg_l.x += 0.5
		t.leg_r.x += 0.5
		t.knee_l.x -= 0.8
		t.knee_r.x -= 0.8
	if casting:
		t.arm_l = Vector3(1.4, 0, 0.3)
		t.elbow_l = Vector3(0.3, 0, 0)
		t.arm_r = Vector3(1.4, 0, -0.3) if weapon_cat != "staff" else Vector3(1.2, 0, 0)
	# --- one-shot actions
	if action != "":
		rate = 22.0
		_pose_action(t, action, action_p)
	if yielding:
		hips_y = 0.55
		t.leg_l = Vector3(1.4, 0, 0)
		t.knee_l = Vector3(-1.5, 0, 0)
		t.leg_r = Vector3(-0.2, 0, 0)
		t.knee_r = Vector3(-1.6, 0, 0)
		t.arm_l = Vector3(2.6, 0, -0.3)
		t.arm_r = Vector3(2.6, 0, 0.3)
		t.neck = Vector3(0.4, 0, 0)
	if hit_t > 0.0:
		t.spine.x -= hit_t * 1.2
		t.neck.x -= hit_t * 0.8
	var k := minf(1.0, delta * rate)
	for jn in t:
		if j.has(jn):
			j[jn].rotation = j[jn].rotation.lerp(t[jn], k)
	j.hips.position.y = lerpf(j.hips.position.y, hips_y, minf(1.0, delta * 10.0))
	if j.has("cape"):
		j.cape.rotation.x = lerpf(j.cape.rotation.x, 0.15 + sp * 0.45 + sin(_breath * 1.7) * 0.04, k)
	# --- whole-body: dodge roll & death
	var body: Node3D = j.body
	if dead:
		_dead_t = minf(_dead_t + delta * 2.2, 1.0)
		var e := 1.0 - pow(1.0 - _dead_t, 3.0)
		body.rotation.x = lerpf(0.0, 1.45, e)
		body.position.y = lerpf(0.0, 0.12, e)
		body.position.z = lerpf(0.0, 0.2, e)
	elif dodging:
		body.rotation.x = -TAU * dodge_p
		body.position.y = -0.45 * sin(PI * dodge_p)
	else:
		_dead_t = 0.0
		body.rotation.x = lerpf(body.rotation.x, 0.0, minf(1.0, delta * 15.0))
		if absf(body.rotation.x) < 0.01:
			body.rotation.x = 0.0
		body.position.y = lerpf(body.position.y, 0.0, minf(1.0, delta * 15.0))
		body.position.z = 0.0

func _pose_aim(t: Dictionary) -> void:
	match weapon_cat:
		"bow":
			t.arm_l = Vector3(1.55, 0.0, -0.05)
			t.elbow_l = Vector3(0.0, 0, 0)
			t.hand_l = Vector3(-1.55, 0, 0)
			t.arm_r = Vector3(1.5, 0.0, -0.6)
			t.elbow_r = Vector3(1.9, 0, 0)
			t.spine.y = 0.3
		"firearm":
			t.arm_r = Vector3(1.55, 0, 0.0)
			t.elbow_r = Vector3(0.05, 0, 0)
			t.hand_r = Vector3(-1.55, 0, 0)
			if two_handed:
				t.arm_l = Vector3(1.45, 0, 0.55)
				t.elbow_l = Vector3(0.5, 0, 0)
		"staff":
			t.arm_r = Vector3(1.45, 0, 0.0)
			t.elbow_r = Vector3(0.1, 0, 0)
			t.hand_r = Vector3(-1.3, 0, 0)

func _pose_action(t: Dictionary, act: String, p: float) -> void:
	# windup -> strike -> recover curves
	var w := clampf(p / 0.35, 0.0, 1.0)
	var st := clampf((p - 0.35) / 0.25, 0.0, 1.0)
	var rc := clampf((p - 0.6) / 0.4, 0.0, 1.0)
	var e := w * (1.0 - rc)
	match act:
		"slash", "slash2":
			var dirs := 1.0 if act == "slash" else -1.0
			t.spine.y = lerpf(-0.7 * dirs * w, 0.8 * dirs, st) * (1.0 - rc)
			t.arm_r = Vector3(1.35 * e + 0.2, 0.0, lerpf(1.1 * dirs, -0.5 * dirs, st) * (1.0 - rc))
			t.elbow_r = Vector3(lerpf(0.8, 0.15, st), 0, 0)
			t.hand_r = Vector3(-1.4 * e, 0, 0)
		"thrust", "stab":
			t.arm_r = Vector3(lerpf(0.9, 1.6, st) * (1.0 - rc) + 0.2, 0, 0.1)
			t.elbow_r = Vector3(lerpf(1.6, 0.0, st) * (1.0 - rc) + 0.3 * rc, 0, 0)
			t.hand_r = Vector3(-1.5 * e, 0, 0)
			t.spine.x = 0.25 * st * (1.0 - rc)
			t.spine.y = -0.3 * w * (1.0 - st)
		"overhead", "slam":
			var up := lerpf(2.9, 0.7, st)
			t.arm_r = Vector3(up * (1.0 - rc) + 0.2 * rc, 0, 0.1)
			t.elbow_r = Vector3(lerpf(0.6, 0.1, st), 0, 0)
			t.hand_r = Vector3(-1.5 * e, 0, 0)
			if two_handed or act == "slam":
				t.arm_l = Vector3(up * (1.0 - rc), 0, 0.45)
				t.elbow_l = Vector3(lerpf(0.6, 0.1, st), 0, 0)
			t.spine.x = lerpf(-0.25, 0.45, st) * (1.0 - rc)
			if act == "slam":
				t.leg_l.x += 0.5 * st * (1.0 - rc)
				t.knee_l.x -= 0.6 * st * (1.0 - rc)
		"spin":
			t.spine.y = TAU * p
			t.arm_r = Vector3(1.5, 0, 0.9)
			t.hand_r = Vector3(-1.5, 0, 0)
			t.arm_l = Vector3(0.4, 0, -1.2)
		"shoot":
			_pose_aim(t)
			if weapon_cat == "firearm":
				t.arm_r.x += 0.35 * (1.0 - p)
				t.spine.x -= 0.1 * (1.0 - p)
			elif weapon_cat == "bow":
				t.elbow_r = Vector3(lerpf(0.4, 1.9, p), 0, 0)
		"cast":
			t.arm_l = Vector3(lerpf(0.5, 1.6, st) * (1.0 - rc), 0, 0.2)
			t.arm_r = Vector3(lerpf(0.5, 1.6, st) * (1.0 - rc), 0, -0.2)
			t.elbow_l = Vector3(lerpf(1.4, 0.1, st), 0, 0)
			t.elbow_r = Vector3(lerpf(1.4, 0.1, st), 0, 0)
			t.hand_r = Vector3(-1.2 * e, 0, 0)
			t.spine.x = -0.15 * w + 0.15 * st
		"kick":
			t.leg_r = Vector3(lerpf(-0.3, 1.5, st) * (1.0 - rc), 0, 0)
			t.knee_r = Vector3(lerpf(-1.2, 0.0, st) * (1.0 - rc), 0, 0)
			t.spine.x = -0.2 * st * (1.0 - rc)
		"throw":
			t.arm_r = Vector3(lerpf(-0.6, 2.4, st) * (1.0 - rc), 0, 0.2)
			t.elbow_r = Vector3(lerpf(1.5, 0.2, st), 0, 0)
		"interact":
			t.arm_r = Vector3(1.0 * e, 0, 0)
			t.arm_l = Vector3(1.0 * e, 0, 0)
			t.spine.x = 0.4 * e
		"cheer":
			t.arm_r = Vector3(2.8 * e, 0, 0.2)
			t.arm_l = Vector3(2.8 * e, 0, -0.2)
		"roar":
			t.arm_r = Vector3(1.0 * e, 0, 1.2 * e)
			t.arm_l = Vector3(1.0 * e, 0, -1.2 * e)
			t.spine.x = -0.4 * e
			t.neck.x = -0.5 * e
