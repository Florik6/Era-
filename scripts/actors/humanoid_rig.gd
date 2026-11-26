class_name HumanoidRig
extends Node3D
## Procedural articulated humanoid (heroes, bandits, knights, robots,
## skeletons, golems, trolls, mech colossi) with code-driven animation.
##
## Models: tapered torso (chest + waist), boots, layered gear rebuilt by
## set_gear(): belts/pouches, bracers, pauldrons, tabards, robes, coats,
## era-specific armour (medieval plate .. future energy armour), helmets,
## class-readable kit (warrior pauldrons+cape, archer hood+quiver, rogue
## scarf+crossed sheaths, mage robe+pointed hat+glowing staff) and
## legendary/mythic flourishes. Tiny parts cull beyond SMALL_RANGE.
##
## Animation: idle breathing/weight shift/look-around, walk/run blend with
## counter-rotation, weapon carry stances, melee sets (horizontal slashes,
## backhand, thrust/stab lunges, overhead/slam, spin), bow draw driving the
## real string, firearm aim with recoil, staff/hand casting, kick, throw,
## block (shield turned to face the threat), parry flash, directional hit
## flinch / heavy stagger with knockback, 5 death variants, dodge roll,
## stealth crouch, surrender.
##
## VFX hooks: weapon_tip() -> Node3D (blade tip / muzzle / staff gem marker),
## weapon_tip_pos() -> Vector3, hand_pos(side) -> Vector3 (global).

const SKINS := [Color(0.98, 0.85, 0.72), Color(0.92, 0.74, 0.58), Color(0.78, 0.58, 0.42), Color(0.55, 0.38, 0.26), Color(0.36, 0.24, 0.17)]
const HAIR_COLORS := [Color(0.15, 0.1, 0.07), Color(0.42, 0.26, 0.12), Color(0.8, 0.62, 0.3), Color(0.6, 0.2, 0.1), Color(0.85, 0.85, 0.85), Color(0.08, 0.08, 0.1)]
const CLOTH_COLORS := [Color(0.55, 0.18, 0.15), Color(0.18, 0.32, 0.55), Color(0.25, 0.45, 0.22), Color(0.45, 0.38, 0.28), Color(0.35, 0.2, 0.45), Color(0.2, 0.2, 0.22), Color(0.75, 0.68, 0.5)]
const SMALL_RANGE := 24.0
const STEEL := Color(0.74, 0.76, 0.8)
const GOLD := Color(0.95, 0.75, 0.25)
const BRASS := Color(0.8, 0.6, 0.3)
const IRON := Color(0.45, 0.45, 0.47)
const BELT_COLORS := [Color(0.36, 0.22, 0.12), Color(0.28, 0.16, 0.1), Color(0.12, 0.1, 0.09), Color(0.16, 0.17, 0.14), Color(0.2, 0.21, 0.24)]
const BOOT_COLORS := [Color(0.3, 0.2, 0.12), Color(0.24, 0.15, 0.1), Color(0.1, 0.09, 0.08), Color(0.22, 0.2, 0.16), Color(0.28, 0.3, 0.34)]
const MELEE_ACTS := ["slash", "slash2", "thrust", "stab", "overhead", "slam", "spin"]
const HALF_PI := PI * 0.5
const SIDES := ["l", "r"]
const AIM_KEYS := ["hips", "spine", "neck", "arm_l", "elbow_l", "hand_l", "arm_r", "elbow_r", "hand_r"]

var build_type := "normal"
var j := {}                 # joints
var parts := {}             # named mesh parts
var extras: Array = []      # gear-specific nodes (rebuilt on gear change)
var weapon_node: Node3D = null
var offhand_node: Node3D = null
var weapon_model := ""
var weapon_cat := "unarmed"
var two_handed := false
var look := {}
var era := 0
var class_hint := ""
var _cat := "unarmed"        # animation category (crossbows animate like long guns)

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
var pose := ""                 # "" | "sit" | "sleep" (city life: tavern seats, beds)
var yielding := false
var casting := false
var gait := ""              # class gait: heavy (warrior), light (rogue/archer), soft (mage)
var hit_t := 0.0
var parry_t := 0.0
var _hit_max := 0.3
var _hit_local := Vector3(0, 0, 1)
var _hit_heavy := false
var _death_kind := -1
var _phase := 0.0
# secondary motion (cape / hair inertia)
var _last_yaw := 0.0
var _yaw_rate := 0.0
var _last_sp := 0.0
var _sp_accel := 0.0
var _cape_z := 0.0
var _cape_kick := 0.0
var _dead_t := 0.0
var _lod_acc := 0.0
var _breath := 0.0
var _clock := 0.0
var _look_yaw := 0.0
var _look_next := 2.5
var _block_k := 0.0
var _aim_k := 0.0
var _draw := 0.0
var _staff_drop := 0.0
var _shield_mount: Node3D = null
var _bow_top: Node3D = null
var _bow_bot: Node3D = null
var _bow_arrow: Node3D = null
var _bow_half := 0.5
var _t := {}                # reused target dictionary (no per-frame allocation)
var _tmp := {}
var skin_mat: Material
var cloth_mat: Material
var pants_mat: Material
var boot_mat: Material
var glow_color := Color(0, 0, 0, 0)
var broken_parts := {}
var _width := 1.0
var _thick := 1.0

const _JOINTS := ["hips", "spine", "neck", "leg_l", "leg_r", "knee_l", "knee_r", "arm_l", "arm_r", "elbow_l", "elbow_r", "hand_l", "hand_r"]
const _SHIELD_IDLE := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))      # face to the outside of the arm
const _SHIELD_BLOCK := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))     # face forward, upright (rig space)

func setup(l: Dictionary) -> void:
	look = l
	era = _current_era()
	build_type = l.get("build", "normal")
	class_hint = str(l.get("class", ""))
	var skin: Color = l.get("skin_color", SKINS[clampi(l.get("skin", 1), 0, SKINS.size() - 1)])
	var cloth: Color = l.get("cloth_color", CLOTH_COLORS[clampi(l.get("cloth", 0), 0, CLOTH_COLORS.size() - 1)])
	glow_color = l.get("glow", Color(0, 0, 0, 0))
	if build_type == "skeleton":
		skin = Color(0.88, 0.85, 0.75)
	elif build_type in ["robot", "golem", "colossus"]:
		skin = l.get("body", Color(0.55, 0.57, 0.6))
	elif build_type == "bulky":
		skin = l.get("body", Color(0.45, 0.55, 0.4))
	var metal: bool = build_type in ["robot", "colossus"] or l.get("metal", false)
	skin_mat = MeshLib.mat(skin, 0.7 if metal else 0.0, 0.4 if metal else 0.75)
	cloth_mat = MeshLib.mat(cloth)
	pants_mat = MeshLib.mat(l.get("pants_color", Color(0.24, 0.21, 0.2)))
	boot_mat = MeshLib.mat(BOOT_COLORS[clampi(era, 0, 4)], 0.0, 0.6)
	if build_type != "normal":
		boot_mat = skin_mat if build_type != "skeleton" else MeshLib.mat(Color(0.25, 0.2, 0.16))
	_build_skeleton()
	for k in _JOINTS:
		_t[k] = Vector3.ZERO
	scale = Vector3.ONE * l.get("scale", 1.0)

static func _current_era() -> int:
	return clampi(Profile.current_era, 0, 4)

# ---------------------------------------------------------------- skeleton
func _build_skeleton() -> void:
	match build_type:
		"bulky":
			_thick = 1.7
			_width = 1.55
		"golem", "colossus":
			_thick = 1.8
			_width = 1.6
		"skeleton":
			_thick = 0.5
	if look.get("female", false):
		_width *= 0.9
	var th := _thick
	var wd := _width
	var body := MeshLib.pivot(self, Vector3.ZERO, "body")
	j.body = body
	var hips := MeshLib.pivot(body, Vector3(0, 0.95, 0), "hips")
	j.hips = hips
	var blocky := build_type in ["golem", "colossus", "robot"]
	parts.pelvis = MeshLib.part(hips, MeshLib.box(Vector3(0.31 * wd, 0.18, 0.2 * wd)), pants_mat, Vector3(0, -0.02, 0))
	for side in ["l", "r"]:
		var sx := -1.0 if side == "l" else 1.0
		var leg := MeshLib.pivot(hips, Vector3(0.093 * sx * wd, -0.07, 0), "leg_" + side)
		j["leg_" + side] = leg
		var thigh_m: Mesh = MeshLib.box(Vector3(0.15, 0.46, 0.15) * Vector3(th, 1, th)) if blocky else MeshLib.capsule(0.075 * th, 0.46)
		parts["thigh_" + side] = MeshLib.part(leg, thigh_m, pants_mat, Vector3(0, -0.21, 0))
		var knee := MeshLib.pivot(leg, Vector3(0, -0.44, 0), "knee_" + side)
		j["knee_" + side] = knee
		var shin_m: Mesh = MeshLib.box(Vector3(0.14, 0.44, 0.14) * Vector3(th, 1, th)) if blocky else MeshLib.capsule(0.063 * th, 0.44)
		parts["shin_" + side] = MeshLib.part(knee, shin_m, boot_mat, Vector3(0, -0.2, 0))
		parts["foot_" + side] = MeshLib.part(knee, MeshLib.box(Vector3(0.115 * th, 0.085, 0.25 * th)), boot_mat, Vector3(0, -0.425, -0.05))
	var spine := MeshLib.pivot(hips, Vector3(0, 0.06, 0), "spine")
	j.spine = spine
	var chest := MeshLib.pivot(spine, Vector3(0, 0.18, 0), "chest")
	j.chest = chest
	match build_type:
		"skeleton":
			parts.waist = MeshLib.part(spine, MeshLib.cyl(0.03, 0.03, 0.3, 5), skin_mat, Vector3(0, 0.06, 0))
			parts.torso = MeshLib.part(chest, MeshLib.torus(0.1, 0.15), skin_mat, Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1.25, 2.4, 0.85))
			MeshLib.part(chest, MeshLib.torus(0.08, 0.12), skin_mat, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.2, 1.6, 0.8))
		"normal":
			parts.waist = MeshLib.part(spine, MeshLib.cyl(0.155 * wd, 0.15 * wd, 0.26, 10), cloth_mat, Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(1, 1, 0.7))
			parts.torso = MeshLib.part(chest, MeshLib.capsule(0.205 * wd, 0.47), cloth_mat, Vector3(0, 0.15, 0), Vector3.ZERO, Vector3(1.12, 1.0, 0.64))
		_:
			parts.torso = MeshLib.part(chest, MeshLib.box(Vector3(0.44 * wd, 0.52, 0.27 * wd)), cloth_mat if build_type == "robot" else skin_mat, Vector3(0, 0.1, 0))
			parts.waist = MeshLib.part(spine, MeshLib.box(Vector3(0.32 * wd, 0.2, 0.22 * wd)), skin_mat, Vector3(0, 0.05, 0))
	var neck := MeshLib.pivot(chest, Vector3(0, 0.38, 0), "neck")
	j.neck = neck
	if build_type == "normal":
		parts.neck = MeshLib.part(neck, MeshLib.cyl(0.048, 0.056, 0.13, 6), skin_mat, Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	if build_type == "bulky":
		neck.position = Vector3(0, 0.3, -0.1)
	var head := MeshLib.pivot(neck, Vector3(0, 0.13, 0), "head")
	j.head = head
	_build_head(head)
	for side in ["l", "r"]:
		var sx2 := -1.0 if side == "l" else 1.0
		var arm := MeshLib.pivot(chest, Vector3(0.255 * sx2 * wd, 0.3, 0), "arm_" + side)
		j["arm_" + side] = arm
		var up_m: Mesh = MeshLib.box(Vector3(0.13, 0.3, 0.13) * Vector3(th, 1, th)) if blocky else MeshLib.capsule(0.058 * th, 0.31)
		parts["upper_" + side] = MeshLib.part(arm, up_m, cloth_mat if build_type in ["normal", "robot"] else skin_mat, Vector3(0, -0.14, 0))
		var elbow := MeshLib.pivot(arm, Vector3(0, -0.29, 0), "elbow_" + side)
		j["elbow_" + side] = elbow
		var fo_m: Mesh = MeshLib.box(Vector3(0.12, 0.28, 0.12) * Vector3(th, 1, th)) if blocky else MeshLib.capsule(0.05 * th, 0.28)
		parts["fore_" + side] = MeshLib.part(elbow, fo_m, skin_mat, Vector3(0, -0.13, 0))
		var hand := MeshLib.pivot(elbow, Vector3(0, -0.27, 0), "hand_" + side)
		j["hand_" + side] = hand
		var fist_k := th if build_type != "skeleton" else 0.8
		parts["fist_" + side] = MeshLib.part(hand, MeshLib.box(Vector3(0.085, 0.1, 0.095) * fist_k), skin_mat, Vector3(0, -0.035, 0))
	if build_type == "colossus":
		_build_colossus_extras()
	if build_type == "bulky":
		for side in ["l", "r"]:
			MeshLib.part(j["arm_" + side], MeshLib.sphere(0.12, 8, 5), MeshLib.mat((skin_mat as StandardMaterial3D).albedo_color.darkened(0.15)), Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.2, 0.9, 1.2))
	if glow_color.a > 0.0 and Settings.vq("lights", 8) >= 8:
		var eye_l := OmniLight3D.new()
		eye_l.light_color = glow_color
		eye_l.light_energy = 0.6
		eye_l.omni_range = 3.0
		eye_l.position = Vector3(0, 0.05, -0.2)
		eye_l.shadow_enabled = false
		head.add_child(eye_l)

func _small(mi: MeshInstance3D) -> MeshInstance3D:
	mi.visibility_range_end = SMALL_RANGE
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _build_head(head: Node3D) -> void:
	var dark := MeshLib.mat(Color(0.06, 0.05, 0.05))
	match build_type:
		"skeleton":
			parts.head = MeshLib.part(head, MeshLib.sphere(0.12, 8, 5), skin_mat, Vector3(0, 0.02, 0))
			for sx in [-0.045, 0.045]:
				MeshLib.part(head, MeshLib.sphere(0.03, 5, 3), MeshLib.glow(glow_color, 2.5) if glow_color.a > 0 else dark, Vector3(sx, 0.03, -0.1), Vector3.ZERO, Vector3.ONE, false)
			MeshLib.part(head, MeshLib.box(Vector3(0.12, 0.05, 0.1)), skin_mat, Vector3(0, -0.09, -0.03))
		"robot", "colossus":
			parts.head = MeshLib.part(head, MeshLib.box(Vector3(0.22, 0.22, 0.24)), skin_mat, Vector3(0, 0.02, 0))
			var vc: Color = glow_color if glow_color.a > 0 else Color(1.0, 0.25, 0.2)
			MeshLib.part(head, MeshLib.box(Vector3(0.18, 0.05, 0.02)), MeshLib.glow(vc, 3.0), Vector3(0, 0.04, -0.125), Vector3.ZERO, Vector3.ONE, false)
			_small(MeshLib.part(head, MeshLib.cyl(0.008, 0.008, 0.15, 4), skin_mat, Vector3(0.08, 0.18, 0)))
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
			parts.head = MeshLib.part(head, MeshLib.sphere(0.13, 10, 7), skin_mat, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(0.92, 1.05, 1.0))
			for sx in [-0.045, 0.045]:
				_small(MeshLib.part(head, MeshLib.box(Vector3(0.032, 0.026, 0.01)), dark, Vector3(sx, 0.04, -0.121)))
			_small(MeshLib.part(head, MeshLib.box(Vector3(0.03, 0.05, 0.04)), skin_mat, Vector3(0, 0.0, -0.128)))
			_build_hair(head)

func _build_hair(head: Node3D) -> void:
	var hc: Color = look.get("hair_color_value", HAIR_COLORS[clampi(look.get("hair_color", 0), 0, HAIR_COLORS.size() - 1)])
	var hm := MeshLib.mat(hc, 0.0, 0.6)
	var style: int = look.get("hair", 1)
	if style >= 1:
		parts.hair = MeshLib.part(head, MeshLib.sphere(0.14, 10, 6), hm, Vector3(0, 0.05, 0.012), Vector3.ZERO, Vector3(0.98, 0.78, 1.02))
	var hx: Node3D = null
	if style == 2:
		hx = MeshLib.part(head, MeshLib.box(Vector3(0.25, 0.3, 0.07)), hm, Vector3(0, -0.07, 0.1), Vector3(-6, 0, 0))
	elif style == 3:
		hx = MeshLib.part(head, MeshLib.capsule(0.035, 0.28), hm, Vector3(0, -0.06, 0.16), Vector3(28, 0, 0))
	elif style == 4:
		hx = MeshLib.part(head, MeshLib.box(Vector3(0.045, 0.08, 0.26)), hm, Vector3(0, 0.15, 0.0))
	if hx:
		parts.hair2 = hx
	var beard: int = look.get("beard", 0)
	if beard == 1:
		parts.beard = MeshLib.part(head, MeshLib.box(Vector3(0.17, 0.06, 0.07)), hm, Vector3(0, -0.085, -0.09))
	elif beard == 2:
		parts.beard = MeshLib.part(head, MeshLib.prism(Vector3(0.19, 0.17, 0.09)), hm, Vector3(0, -0.13, -0.075), Vector3(180, 0, 0))

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

## Number of mesh instances in this rig (gear and weapons included).
func mesh_count(include_small: bool = true) -> int:
	return _count_meshes(self, include_small)

func _count_meshes(n: Node, include_small: bool) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			if mi.is_visible_in_tree() and (include_small or mi.visibility_range_end <= 0.0 or mi.visibility_range_end > 40.0):
				c += 1
		c += _count_meshes(ch, include_small)
	return c

# ---------------------------------------------------------------- VFX hooks
## Marker at the blade tip / muzzle / staff gem (falls back to the right hand).
func weapon_tip() -> Node3D:
	if weapon_node != null and is_instance_valid(weapon_node) and weapon_node.has_meta("tip"):
		var tp = weapon_node.get_meta("tip")
		if tp is Node3D and is_instance_valid(tp):
			return tp
	return j.get("hand_r")

func weapon_tip_pos() -> Vector3:
	var n := weapon_tip()
	if n != null and n.is_inside_tree():
		return n.global_position
	return global_position + Vector3(0, 1.2, 0)

## Palm position of a hand in world space: side "l"/"left" or "r"/"right".
func hand_pos(side: String) -> Vector3:
	var h: Node3D = j.get("hand_l" if side.begins_with("l") else "hand_r")
	if h == null or not h.is_inside_tree():
		return global_position + Vector3(0, 1.0, 0)
	return h.global_transform * Vector3(0, -0.05, 0)

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
	_shield_mount = null
	_bow_top = null
	_bow_bot = null
	_bow_arrow = null
	j.erase("cape")
	j.erase("cape2")
	era = _current_era()
	var body_it: Dictionary = equip.get("body", {})
	var head_it: Dictionary = equip.get("head", {})
	var main_it: Dictionary = equip.get("main", {})
	var off_it: Dictionary = equip.get("off", {})
	weapon_model = ""
	weapon_cat = "unarmed"
	two_handed = false
	if not main_it.is_empty():
		var b := ItemDB.base(main_it.base)
		weapon_model = b.get("model", "sword")
		weapon_cat = b.get("cat", "sword")
		two_handed = b.get("two_h", false)
	_cat = weapon_cat
	if weapon_model == "crossbow":
		_cat = "firearm"
		two_handed = true
	var off_model := ""
	if not off_it.is_empty():
		off_model = ItemDB.base(off_it.base).get("model", "shield_round")
	var cls := _class_of()
	var top_rar := 0
	var mythic := false
	for it in [body_it, head_it, main_it, off_it]:
		top_rar = maxi(top_rar, int(it.get("rarity", 0)))
		if str(it.get("mythic", "")) != "":
			mythic = true
	var armor_model: String = ItemDB.base(body_it.get("base", "")).get("model", look.get("armor", "")) if not body_it.is_empty() else look.get("armor", "")
	var hm: String = ItemDB.base(head_it.get("base", "")).get("model", "") if not head_it.is_empty() else look.get("hat", "")
	# the player may hide the helmet (appearance option, stats still count)
	if _is_player() and bool(look.get("hide_helm", false)):
		hm = ""
	var humanish := build_type in ["normal", "skeleton"]
	_apply_armor(armor_model, body_it, faction_color, top_rar, mythic)
	if humanish or build_type == "bulky":
		_apply_limbs(equip)
	if build_type in ["normal", "bulky"]:
		if hm != "":
			_apply_helmet(hm, head_it, cls)
		elif armor_model == "robe" and build_type == "normal":
			_apply_helmet("wizard_hat" if era <= 2 else "hood", body_it, cls)
	if parts.has("hair"):
		var hair_vis: bool = hm == "" or hm in ["hat", "bandana", "cap", "goggles", "tophat", "pith"]
		if armor_model == "robe" and hm == "" and era > 2:
			hair_vis = false
		parts.hair.visible = hair_vis
		if parts.has("hair2"):
			parts.hair2.visible = hair_vis or hm in ["kettle", "morion"]
	# ---- weapons
	if weapon_model != "":
		weapon_node = WeaponModels.build(weapon_model, main_it)
		if weapon_cat == "bow" and weapon_model != "crossbow":
			j.hand_l.add_child(weapon_node)
			_bow_top = weapon_node.get_meta("string_top", null)
			_bow_bot = weapon_node.get_meta("string_bot", null)
			_bow_arrow = weapon_node.get_meta("arrow", null)
			_bow_half = float(weapon_node.get_meta("string_len", 0.5))
		else:
			j.hand_r.add_child(weapon_node)
		weapon_node.position = Vector3(0, -0.05, 0)
		GearFX.attach(weapon_node, main_it)
	if off_model != "":
		var fc: Color = faction_color if faction_color.a > 0.5 else Color(0, 0, 0, 0)
		offhand_node = WeaponModels.build(off_model, off_it, fc)
		if off_model.begins_with("shield"):
			_shield_mount = MeshLib.pivot(j.elbow_l, Vector3(0, -0.15, 0), "shield_mount")
			_shield_mount.basis = _SHIELD_IDLE
			_shield_mount.add_child(offhand_node)
			offhand_node.position = Vector3(0.075, 0, 0)
			extras.append(_shield_mount)
		else:
			j.hand_l.add_child(offhand_node)
			offhand_node.position = Vector3(0, -0.06, -0.02)
	if humanish:
		_class_gear(cls, armor_model, hm)
	# ---- an equipped cloak replaces the default cape
	var cloak_it: Dictionary = equip.get("cloak", {})
	if not cloak_it.is_empty() and build_type in ["normal", "bulky", "skeleton"]:
		var cb := ItemDB.base(cloak_it.base)
		var ccol: Color = cb.get("color", Color(0.4, 0.15, 0.12))
		if _is_player() and look.has("dye"):
			ccol = ccol.lerp(look.dye, 0.65)
		_build_cape(ccol, String(cb.get("model", "")) in ["cloak_wool", "cloak_void", "cloak_soot"], int(cloak_it.get("rarity", 0)), String(cb.get("model", "")))
		_set_visuals(equip)
		return
	_set_visuals(equip)
	# ---- capes: legends/commanders long, faction soldiers short, warrior heroes long
	var hero := _is_player()
	var want_cape := cape or (hero and cls == "warrior" and build_type == "normal")
	if (want_cape or faction_color.a > 0.5) and build_type in ["normal", "bulky", "skeleton"] and armor_model != "robe":
		var cc: Color = faction_color if faction_color.a > 0.5 else Color(0.55, 0.1, 0.1)
		if hero and faction_color.a <= 0.5:
			cc = Color(0.42, 0.1, 0.11) if top_rar < 4 else Color(0.12, 0.14, 0.3)
		if mythic:
			cc = Color(0.3, 0.03, 0.06)
		# muted cloth so the cape never dominates the silhouette from the
		# high camera; long capes only for legends/commanders
		cc = cc.lerp(Color(0.25, 0.22, 0.2), 0.18)
		_build_cape(cc, cape, top_rar)

## Gloves, leg armour, boots: each slot changes its own part of the body.
func _apply_limbs(equip: Dictionary) -> void:
	var hands: Dictionary = equip.get("hands", {})
	var legs: Dictionary = equip.get("legs", {})
	var feet: Dictionary = equip.get("feet", {})
	var dye: Color = look.get("dye", Color(0, 0, 0, 0)) if _is_player() else Color(0, 0, 0, 0)
	if not hands.is_empty():
		var hb := ItemDB.base(hands.base)
		var metal: bool = String(hb.get("model", "")) == "gauntlets"
		var hc := Color(0.55, 0.56, 0.6) if metal else Color(0.33, 0.22, 0.13)
		if int(hb.get("era", 0)) >= 3 and not metal:
			hc = Color(0.15, 0.16, 0.17)
		var hm2 := MeshLib.mat(hc, 0.8 if metal else 0.0, 0.35 if metal else 0.7)
		for side in ["l", "r"]:
			if parts.has("fist_" + side):
				parts["fist_" + side].material_override = hm2
			if metal and j.has("elbow_" + side):
				_extra(j["elbow_" + side], MeshLib.cyl(0.055, 0.06, 0.16, 8), hm2, Vector3(0, -0.15, 0), Vector3.ZERO, Vector3.ONE, true)
	if not legs.is_empty():
		var lb := ItemDB.base(legs.base)
		var lm: String = String(lb.get("model", ""))
		var plate: bool = lm.begins_with("greaves")
		var lc := Color(0.5, 0.5, 0.54) if plate else Color(0.27, 0.24, 0.22)
		match lm:
			"trousers":
				lc = Color(0.35, 0.12, 0.14)
			"pants_armored":
				lc = Color(0.2, 0.22, 0.2)
			"greaves_phase":
				lc = Color(0.25, 0.28, 0.38)
		if dye.a > 0.5 and not plate:
			lc = lc.lerp(dye, 0.6)
		var lmat := MeshLib.mat(lc, 0.75 if plate else 0.0, 0.4 if plate else 0.8)
		for side in ["l", "r"]:
			if parts.has("thigh_" + side):
				parts["thigh_" + side].material_override = lmat
			if plate and j.has("knee_" + side):
				_extra(j["knee_" + side], MeshLib.box(Vector3(0.12, 0.1, 0.07)), lmat, Vector3(0, -0.02, -0.06), Vector3.ZERO, Vector3.ONE, true)
			if lm == "greaves_phase" and j.has("knee_" + side):
				_extra(j["knee_" + side], MeshLib.box(Vector3(0.02, 0.3, 0.02)), MeshLib.glow(Color(0.4, 0.8, 1.0), 1.6), Vector3(0.06, -0.18, -0.05), Vector3.ZERO, Vector3.ONE, true)
			if lm == "pants_armored" and j.has("knee_" + side):
				_extra(j["knee_" + side], MeshLib.box(Vector3(0.11, 0.1, 0.06)), MeshLib.mat(Color(0.12, 0.12, 0.12)), Vector3(0, -0.03, -0.06), Vector3.ZERO, Vector3.ONE, true)
	if not feet.is_empty():
		var fb := ItemDB.base(feet.base)
		var sab: bool = String(fb.get("model", "")) == "sabatons"
		var fc2 := Color(0.5, 0.5, 0.54) if sab else Color(0.25, 0.17, 0.1)
		if int(fb.get("era", 0)) >= 3 and not sab:
			fc2 = Color(0.12, 0.12, 0.13)
		var fmat := MeshLib.mat(fc2, 0.8 if sab else 0.0, 0.35 if sab else 0.65)
		for side in ["l", "r"]:
			if parts.has("foot_" + side):
				parts["foot_" + side].material_override = fmat
			if parts.has("shin_" + side) and (sab or "jet" in String(feet.base) or "steam" in String(feet.base)):
				parts["shin_" + side].material_override = fmat
		if "jet" in String(feet.base) or "steam" in String(feet.base):
			for side in ["l", "r"]:
				if j.has("knee_" + side):
					_extra(j["knee_" + side], MeshLib.cyl(0.03, 0.04, 0.08, 8), MeshLib.glow(Color(0.4, 0.75, 1.0) if "jet" in String(feet.base) else Color(1.0, 0.6, 0.3), 1.6), Vector3(0, -0.44, 0.08), Vector3(90, 0, 0), Vector3.ONE, true)

## Visible accessories (amulet pendant, ring glint) and the set emblem when
## four or more pieces of one set are worn.
func _set_visuals(equip: Dictionary) -> void:
	var am: Dictionary = equip.get("amulet", {})
	if not am.is_empty() and j.has("chest"):
		var col: Color = ItemDB.RARITY_COLORS[clampi(int(am.get("rarity", 0)), 0, 5)]
		_extra(j.chest, MeshLib.sphere(0.035, 8, 5), MeshLib.glow(col.lerp(Color(1, 0.85, 0.4), 0.4), 1.4), Vector3(0, 0.2, -0.13), Vector3.ZERO, Vector3.ONE, true)
	var rg: Dictionary = equip.get("ring", {})
	if not rg.is_empty() and j.has("hand_r"):
		_extra(j.hand_r, MeshLib.torus(0.035, 0.045), MeshLib.mat(Color(0.95, 0.8, 0.35), 0.9, 0.25), Vector3(0, -0.06, 0), Vector3(0, 0, 90), Vector3.ONE, true)
	var sets := {}
	for sl in equip:
		var sid: String = str(ItemDB.base(equip[sl].get("base", "")).get("set", ""))
		if sid != "":
			sets[sid] = int(sets.get(sid, 0)) + 1
	for sid in sets:
		if int(sets[sid]) >= 4 and j.has("chest"):
			var ec: Color = {"black_outpost": Color(0.75, 0.75, 0.8), "duelist": Color(0.9, 0.2, 0.25), "steelworker": Color(1.0, 0.55, 0.2), "operative": Color(0.4, 0.9, 0.5), "chronologist": Color(0.3, 0.9, 1.0)}.get(sid, Color(1, 1, 1))
			_extra(j.chest, MeshLib.box(Vector3(0.09, 0.09, 0.02)), MeshLib.glow(ec, 1.8), Vector3(0.09, 0.14, -0.14), Vector3(0, 0, 45), Vector3.ONE, true)
			set_meta("set_full", sid)

func _class_of() -> String:
	var p := get_parent()
	if p != null:
		var d = p.get("data")
		if d != null and d is Object:
			var c = d.get("class_id")
			if c != null and str(c) != "":
				return str(c)
	if class_hint != "":
		return class_hint
	match weapon_cat:
		"bow": return "archer"
		"dagger": return "rogue"
		"staff": return "mage"
	return "warrior"

func _is_player() -> bool:
	var p := get_parent()
	if p != null and p.get("is_player") == true:
		return true
	return look.get("hero", false)

func _build_cape(cc: Color, long: bool, rar: int, style := "") -> void:
	var cp := MeshLib.pivot(j.chest, Vector3(0, 0.36, 0.13), "cape")
	var cmat := MeshLib.mat(cc, 0.0, 0.92)
	var cmat_d := MeshLib.mat(cc.darkened(0.25), 0.0, 0.92)
	var top_h := 0.44 if long else 0.34
	cp.rotation.x = deg_to_rad(8.0)
	MeshLib.part(cp, MeshLib.box(Vector3(0.36 * _width, top_h, 0.025)), cmat, Vector3(0, -top_h * 0.5, 0.02))
	# darker side panels give the flat cloth some shape
	for sx in [-1.0, 1.0]:
		MeshLib.part(cp, MeshLib.box(Vector3(0.05 * _width, top_h * 0.95, 0.03)), cmat_d, Vector3(sx * 0.185 * _width, -top_h * 0.5, 0.02))
	_small(MeshLib.part(cp, MeshLib.box(Vector3(0.42 * _width, 0.05, 0.07)), MeshLib.mat(cc.darkened(0.4)), Vector3(0, -0.01, 0.0)))
	_small(MeshLib.part(cp, MeshLib.box(Vector3(0.37 * _width, 0.025, 0.03)), MeshLib.mat(Color(0.55, 0.45, 0.25), 0.6, 0.4), Vector3(0, -top_h + 0.01, 0.02)))
	j.cape = cp
	extras.append(cp)
	match style:
		"poncho":
			_extra(cp, MeshLib.box(Vector3(0.5 * _width, 0.12, 0.3)), MeshLib.mat(cc.darkened(0.1)), Vector3(0, -0.02, -0.12))
		"cloak_void":
			_small(MeshLib.part(cp, MeshLib.box(Vector3(0.37 * _width, 0.02, 0.03)), MeshLib.glow(Color(0.35, 0.3, 0.9), 1.4), Vector3(0, -top_h + 0.02, 0.025)))
		"cloak_duelist":
			_small(MeshLib.part(cp, MeshLib.box(Vector3(0.38 * _width, 0.03, 0.03)), MeshLib.mat(Color(0.85, 0.7, 0.3), 0.7, 0.3), Vector3(0, -top_h + 0.02, 0.025)))
	if long:
		var c2 := MeshLib.pivot(cp, Vector3(0, -top_h, 0.02), "cape2")
		MeshLib.part(c2, MeshLib.box(Vector3(0.34 * _width, 0.4, 0.022)), cmat, Vector3(0, -0.2, 0))
		if rar >= 4:
			_small(MeshLib.part(c2, MeshLib.box(Vector3(0.35 * _width, 0.035, 0.03)), MeshLib.mat(GOLD, 0.8, 0.3), Vector3(0, -0.39, 0)))
		j.cape2 = c2

func _apply_armor(model: String, it: Dictionary, faction_color: Color, top_rar: int, mythic: bool) -> void:
	var rar: int = it.get("rarity", 0)
	var cloth_c: Color = (cloth_mat as StandardMaterial3D).albedo_color
	var torso_c := cloth_c
	var metal := 0.0
	var rough := 0.85
	var sleeves: Material = cloth_mat
	var fore: Material = skin_mat if build_type == "normal" else (parts["fore_l"] as MeshInstance3D).material_override
	var legs: Material = pants_mat
	var shins: Material = boot_mat
	var fists: Material = skin_mat
	var heraldry: Color = faction_color if faction_color.a > 0.5 else cloth_c
	var gold_trim := top_rar >= 4
	var trim := MeshLib.mat(GOLD if gold_trim else IRON, 0.85, 0.32)
	var leather := MeshLib.mat(Color(0.33, 0.21, 0.12), 0.0, 0.7)
	var ch: Node3D = j.chest
	var hp: Node3D = j.hips
	var wd := _width
	var belt_c: Color = BELT_COLORS[era]
	var pouches := true
	var e := era
	match model:
		"leather", "doublet":
			if e == 1 or model == "doublet":
				torso_c = Color(0.5, 0.15, 0.2).lerp(cloth_c, 0.3)
				sleeves = MeshLib.mat(torso_c.lightened(0.15))
				fore = sleeves
				for sx in [-1.0, 1.0]:
					_extra(j["arm_l" if sx < 0 else "arm_r"], MeshLib.sphere(0.085, 8, 5), MeshLib.mat(torso_c.lightened(0.25)), Vector3(0, -0.04, 0), Vector3.ZERO, Vector3(1.15, 1.0, 1.15))
				_extra(j.neck, MeshLib.torus(0.06, 0.11), MeshLib.mat(Color(0.95, 0.94, 0.9)), Vector3(0, -0.02, 0), Vector3.ZERO, Vector3(1, 1.6, 1))
			else:
				torso_c = Color(0.42, 0.28, 0.16) if e != 3 else Color(0.25, 0.24, 0.2)
				for sx in [-1.0, 1.0]:
					var arm: Node3D = j["arm_l" if sx < 0 else "arm_r"]
					_extra(arm, MeshLib.sphere(0.09, 8, 5), MeshLib.mat(torso_c.darkened(0.25), 0.0, 0.7), Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.25, 0.75, 1.2))
				# diagonal strap across the chest
				_extra(ch, MeshLib.box(Vector3(0.05, 0.56, 0.02)), MeshLib.mat(torso_c.darkened(0.45)), Vector3(0, 0.14, -0.137), Vector3(0, 0, 38))
			for side in ["l", "r"]:
				_extra(j["elbow_" + side], MeshLib.cyl(0.058, 0.064, 0.15, 8), leather, Vector3(0, -0.18, 0))
		"jacket":
			torso_c = Color(0.2, 0.22, 0.2) if cloth_c.v > 0.3 else Color(0.32, 0.3, 0.26)
			sleeves = MeshLib.mat(torso_c)
			fore = sleeves
			_extra(j.neck, MeshLib.cyl(0.08, 0.1, 0.08, 10), MeshLib.mat(torso_c.darkened(0.2)), Vector3(0, -0.01, 0))
			_extra(ch, MeshLib.box(Vector3(0.012, 0.42, 0.02)), MeshLib.mat(Color(0.6, 0.6, 0.62), 0.8, 0.3), Vector3(0, 0.12, -0.135), Vector3.ZERO, Vector3.ONE, true)
		"chain":
			torso_c = Color(0.55, 0.56, 0.58)
			metal = 0.7
			rough = 0.5
			sleeves = MeshLib.mat(torso_c, 0.7, 0.5)
			fore = leather
			fists = leather
			_extra(hp, MeshLib.cyl(0.19 * wd, 0.235 * wd, 0.28, 10), MeshLib.mat(torso_c.darkened(0.1), 0.7, 0.5), Vector3(0, -0.13, 0), Vector3.ZERO, Vector3(1, 1, 0.8))
			_tabard(heraldry, trim)
			for sx in [-1.0, 1.0]:
				_extra(j["arm_l" if sx < 0 else "arm_r"], MeshLib.sphere(0.09, 8, 5), leather, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.25, 0.75, 1.2))
		"plate", "cuirass", "cursed":
			var cursed := model == "cursed"
			torso_c = STEEL if not cursed else Color(0.17, 0.2, 0.19)
			if gold_trim and not cursed:
				torso_c = STEEL.lerp(GOLD, 0.12)
			metal = 0.85
			rough = 0.32
			var pm := MeshLib.mat(torso_c, 0.85, 0.32)
			var renaissance := e == 1 or model == "cuirass"
			sleeves = pm if not renaissance else MeshLib.mat(cloth_c.lightened(0.1))
			fore = pm if not renaissance else leather
			fists = pm if not renaissance else leather
			if not renaissance:
				legs = MeshLib.mat(torso_c.darkened(0.08), 0.8, 0.38)
				shins = pm
				for side in ["l", "r"]:
					_extra(j["knee_" + side], MeshLib.sphere(0.07, 8, 5), trim, Vector3(0, 0.0, -0.03), Vector3.ZERO, Vector3(1, 0.8, 1), true)
			# pauldrons ride the shoulder joints: big dome + lower lame
			var pk := 0.85 if renaissance else 1.0
			for side in ["l", "r"]:
				var sxv := -1.0 if side == "l" else 1.0
				_extra(j["arm_" + side], MeshLib.sphere(0.125 * pk, 10, 6), pm, Vector3(0.02 * sxv, 0.03, 0), Vector3.ZERO, Vector3(1.3, 0.85, 1.25))
				if not renaissance:
					_extra(j["arm_" + side], MeshLib.box(Vector3(0.17, 0.045, 0.2)), trim, Vector3(0.03 * sxv, -0.07, 0), Vector3(0, 0, 18 * sxv))
			# breastplate ridge + tassets
			_extra(ch, MeshLib.prism(Vector3(0.1, 0.4, 0.04)), pm, Vector3(0, 0.12, -0.13), Vector3(0, 0, 180), Vector3.ONE, true)
			_extra(hp, MeshLib.box(Vector3(0.34 * wd, 0.17, 0.235 * wd)), MeshLib.mat(torso_c.darkened(0.12), 0.8, 0.35), Vector3(0, -0.11, 0))
			if renaissance:
				# sash in house colours
				_extra(ch, MeshLib.box(Vector3(0.07, 0.6, 0.02)), MeshLib.mat(heraldry), Vector3(0, 0.08, -0.145), Vector3(0, 0, -36))
			elif not cursed:
				_tabard(heraldry, trim)
			if cursed:
				_extra(ch, MeshLib.box(Vector3(0.03, 0.3, 0.02)), MeshLib.glow(Color(0.3, 1.0, 0.5), 2.0), Vector3(0.04, 0.12, -0.155), Vector3(0, 0, 12), Vector3.ONE, true)
		"robe":
			var rc := cloth_c if cloth_c.v > 0.18 else Color(0.25, 0.2, 0.45)
			torso_c = rc
			sleeves = MeshLib.mat(rc)
			fore = sleeves
			var accent: Color = ItemDB.RARITY_COLORS[clampi(rar, 0, 5)] if rar >= 2 else Color(0.9, 0.78, 0.4)
			_extra(hp, MeshLib.cyl(0.19 * wd, 0.34 * wd, 0.86, 12), MeshLib.mat(rc.darkened(0.08)), Vector3(0, -0.4, 0), Vector3.ZERO, Vector3(1, 1, 0.92))
			_extra(ch, MeshLib.box(Vector3(0.075, 0.5, 0.02)), MeshLib.mat(accent, 0.5, 0.45), Vector3(0, 0.1, -0.138))
			_extra(hp, MeshLib.box(Vector3(0.075, 0.82, 0.02)), MeshLib.mat(accent, 0.5, 0.45), Vector3(0, -0.36, -0.215), Vector3(-9, 0, 0))
			# shoulder mantle reads well from the high camera
			_extra(ch, MeshLib.cyl(0.13 * wd, 0.3 * wd, 0.2, 12), MeshLib.mat(rc.darkened(0.3)), Vector3(0, 0.3, 0.0), Vector3.ZERO, Vector3(1, 1, 0.75))
			for side in ["l", "r"]:
				_extra(j["elbow_" + side], MeshLib.cyl(0.055, 0.1, 0.16, 8), MeshLib.mat(rc.darkened(0.08)), Vector3(0, -0.2, 0))
			belt_c = Color(0.85, 0.75, 0.5)
			pouches = false
		"coat":
			torso_c = Color(0.3, 0.22, 0.16) if cloth_c.v > 0.25 else Color(0.18, 0.2, 0.3)
			sleeves = MeshLib.mat(torso_c)
			fore = sleeves
			_extra(hp, MeshLib.cyl(0.2 * wd, 0.29 * wd, 0.62, 10), MeshLib.mat(torso_c.darkened(0.05)), Vector3(0, -0.27, 0.01), Vector3.ZERO, Vector3(1, 1, 0.85))
			_extra(j.neck, MeshLib.cyl(0.085, 0.12, 0.1, 10), MeshLib.mat(torso_c.darkened(0.2)), Vector3(0, -0.02, 0))
			_extra(ch, MeshLib.box(Vector3(0.02, 0.36, 0.02)), MeshLib.mat(BRASS, 0.8, 0.35), Vector3(0.04, 0.1, -0.138), Vector3.ZERO, Vector3.ONE, true)
		"steam_suit":
			torso_c = Color(0.7, 0.52, 0.3)
			metal = 0.8
			rough = 0.4
			var bm := MeshLib.mat(torso_c, 0.8, 0.4)
			sleeves = bm
			fore = MeshLib.mat(Color(0.35, 0.3, 0.25), 0.4, 0.6)
			legs = MeshLib.mat(Color(0.35, 0.3, 0.25), 0.5, 0.6)
			_extra(ch, MeshLib.cyl(0.11, 0.11, 0.42, 10), MeshLib.mat(Color(0.6, 0.45, 0.25), 0.8, 0.35), Vector3(0, 0.12, 0.2))
			_extra(ch, MeshLib.cyl(0.025, 0.025, 0.36, 6), MeshLib.mat(Color(0.25, 0.25, 0.25), 0.6, 0.5), Vector3(0.1, 0.42, 0.18), Vector3(20, 0, 0), Vector3.ONE, true)
			_extra(ch, MeshLib.sphere(0.035, 6, 4), MeshLib.glow(Color(1.0, 0.6, 0.25), 2.0), Vector3(-0.09, 0.2, -0.14), Vector3.ZERO, Vector3.ONE, true)
			for side in ["l", "r"]:
				_extra(j["arm_" + side], MeshLib.sphere(0.115, 8, 5), bm, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.2, 0.85, 1.2))
		"vest":
			torso_c = cloth_c.darkened(0.15)
			_extra(ch, MeshLib.box(Vector3(0.42 * wd, 0.38, 0.29 * wd)), MeshLib.mat(Color(0.3, 0.33, 0.25)), Vector3(0, 0.12, 0))
			_extra(ch, MeshLib.box(Vector3(0.26, 0.09, 0.05)), MeshLib.mat(Color(0.22, 0.25, 0.18)), Vector3(0, 0.0, -0.16))
			for side in ["l", "r"]:
				_extra(j["knee_" + side], MeshLib.box(Vector3(0.11, 0.1, 0.06)), MeshLib.mat(Color(0.15, 0.15, 0.15)), Vector3(0, -0.03, -0.06), Vector3.ZERO, Vector3.ONE, true)
		"energy_armor", "exo":
			torso_c = Color(0.22, 0.24, 0.3) if model == "energy_armor" else Color(0.4, 0.42, 0.45)
			metal = 0.7
			rough = 0.35
			var em := MeshLib.mat(torso_c, 0.7, 0.35)
			sleeves = em
			fore = em
			fists = MeshLib.mat(torso_c.darkened(0.3), 0.6, 0.4)
			legs = MeshLib.mat(torso_c.darkened(0.2), 0.6, 0.4)
			shins = em
			var ec: Color = Color(0.3, 0.9, 1.0) if rar < 2 else ItemDB.RARITY_COLORS[rar]
			var glow := MeshLib.glow(ec, 2.5)
			_extra(ch, MeshLib.box(Vector3(0.03, 0.4, 0.02)), glow, Vector3(0, 0.1, -0.142))
			_extra(ch, MeshLib.box(Vector3(0.24, 0.3, 0.1)), MeshLib.mat(torso_c.darkened(0.25), 0.7, 0.35), Vector3(0, 0.14, 0.17))
			_extra(ch, MeshLib.box(Vector3(0.16, 0.03, 0.02)), glow, Vector3(0, 0.2, 0.225), Vector3.ZERO, Vector3.ONE, true)
			for side in ["l", "r"]:
				var sxv2 := -1.0 if side == "l" else 1.0
				_extra(j["arm_" + side], MeshLib.box(Vector3(0.17, 0.09, 0.21)), em, Vector3(0.02 * sxv2, 0.02, 0), Vector3(0, 0, 14 * sxv2))
			if model == "exo":
				for side in ["l", "r"]:
					_extra(j["knee_" + side], MeshLib.box(Vector3(0.04, 0.4, 0.04)), MeshLib.mat(Color(0.6, 0.6, 0.62), 0.9, 0.3), Vector3(0.09 * (-1.0 if side == "l" else 1.0), -0.2, 0))
			belt_c = Color(0.15, 0.16, 0.2)
			pouches = false
		"robot", "android":
			torso_c = (skin_mat as StandardMaterial3D).albedo_color if model == "robot" else Color(0.92, 0.92, 0.95)
			metal = 0.6
			rough = 0.35
			sleeves = MeshLib.mat(torso_c, 0.6, 0.35)
			legs = sleeves
			fore = sleeves
			pouches = false
			belt_c = Color(0, 0, 0, 0)
		"bones":
			return
		_:
			# plain clothes, era flavoured
			if build_type == "normal":
				if e <= 1:
					_extra(hp, MeshLib.cyl(0.18 * wd, 0.22 * wd, 0.24, 10), MeshLib.mat(cloth_c.darkened(0.1)), Vector3(0, -0.12, 0), Vector3.ZERO, Vector3(1, 1, 0.8))
				elif e == 2:
					_extra(ch, MeshLib.box(Vector3(0.38 * wd, 0.32, 0.27 * wd)), MeshLib.mat(Color(0.2, 0.17, 0.15)), Vector3(0, 0.1, 0))
				elif e == 4:
					_extra(ch, MeshLib.box(Vector3(0.02, 0.4, 0.02)), MeshLib.glow(Color(0.3, 0.85, 1.0), 2.0), Vector3(0.06, 0.1, -0.138), Vector3.ZERO, Vector3.ONE, true)
				sleeves = MeshLib.mat(cloth_c.lightened(0.08))
	if faction_color.a > 0.5 and model in ["", "cloth", "leather", "coat", "jacket"]:
		torso_c = torso_c.lerp(faction_color, 0.45)
	var tmat := MeshLib.mat(torso_c, metal, rough)
	if parts.has("torso") and build_type in ["normal", "robot", "skeleton"]:
		parts.torso.material_override = tmat if build_type != "skeleton" else skin_mat
	if parts.has("waist") and build_type == "normal":
		parts.waist.material_override = MeshLib.mat(torso_c.darkened(0.12), metal, rough)
	for side in ["l", "r"]:
		if build_type == "normal":
			parts["upper_" + side].material_override = sleeves
			parts["fore_" + side].material_override = fore
			parts["fist_" + side].material_override = fists
			parts["thigh_" + side].material_override = legs
			parts["shin_" + side].material_override = shins
			parts["foot_" + side].material_override = shins if shins != boot_mat else boot_mat
	# belt + buckle + pouch
	if belt_c.a > 0.0 and build_type in ["normal", "bulky", "skeleton"]:
		_extra(hp, MeshLib.box(Vector3(0.33 * wd, 0.055, 0.225 * wd)), MeshLib.mat(belt_c, 0.0, 0.6), Vector3(0, 0.075, 0))
		var buckle_m: Material = MeshLib.mat(GOLD if gold_trim else (BRASS if era in [1, 2] else IRON), 0.85, 0.3)
		if era == 4:
			buckle_m = MeshLib.glow(Color(0.35, 0.85, 1.0), 2.0)
		_extra(hp, MeshLib.box(Vector3(0.065, 0.05, 0.02)), buckle_m, Vector3(0, 0.075, -0.118 * wd), Vector3.ZERO, Vector3.ONE, true)
		if pouches:
			_extra(hp, MeshLib.box(Vector3(0.085, 0.09, 0.05)), MeshLib.mat(belt_c.lightened(0.12)), Vector3(0.14 * wd, 0.03, 0.06), Vector3(0, -30, 0), Vector3.ONE, true)
	# legendary / mythic flourish: rune gem on the chest
	if top_rar >= 4 and build_type == "normal":
		var gc: Color = Color(1.0, 0.25, 0.3) if mythic else ItemDB.RARITY_COLORS[clampi(top_rar, 0, 5)]
		_extra(ch, MeshLib.sphere(0.03, 6, 4), MeshLib.glow(gc, 3.0), Vector3(0, 0.27, -0.15), Vector3.ZERO, Vector3.ONE, true)

func _tabard(c: Color, trim: Material) -> void:
	_extra(j.chest, MeshLib.box(Vector3(0.26 * _width, 0.62, 0.02)), MeshLib.mat(c, 0.0, 0.9), Vector3(0, -0.02, -0.15))
	_extra(j.chest, MeshLib.box(Vector3(0.1, 0.1, 0.022)), trim, Vector3(0, 0.12, -0.152), Vector3(0, 0, 45), Vector3.ONE, true)

func _apply_helmet(model: String, it: Dictionary, cls: String) -> void:
	var h: Node3D = j.head
	var steel := MeshLib.mat(Color(0.7, 0.72, 0.76), 0.85, 0.35)
	var cc: Color = (cloth_mat as StandardMaterial3D).albedo_color
	match model:
		"hood":
			var hc: Color = cc.darkened(0.3)
			if cls == "rogue" or weapon_cat == "dagger":
				hc = Color(0.13, 0.13, 0.15)
			elif cls == "archer" or weapon_cat == "bow":
				hc = Color(0.2, 0.36, 0.18)
			var hmat := MeshLib.mat(hc, 0.0, 0.9)
			_extra(h, MeshLib.sphere(0.158, 10, 6), hmat, Vector3(0, 0.035, 0.02), Vector3.ZERO, Vector3(1.0, 1.0, 1.08))
			_extra(h, MeshLib.prism(Vector3(0.14, 0.14, 0.12)), hmat, Vector3(0, 0.07, 0.15), Vector3(-60, 0, 0))
			# cowl over the shoulders
			_extra(j.chest, MeshLib.cyl(0.12, 0.25 * _width, 0.14, 10), hmat, Vector3(0, 0.36, 0.01), Vector3.ZERO, Vector3(1, 1, 0.8))
		"wizard_hat":
			var wc: Color = cc.darkened(0.2) if cc.v > 0.2 else Color(0.22, 0.16, 0.4)
			var wm := MeshLib.mat(wc, 0.0, 0.85)
			_extra(h, MeshLib.cyl(0.27, 0.27, 0.025, 14), wm, Vector3(0, 0.1, 0.0))
			_extra(h, MeshLib.cyl(0.015, 0.14, 0.36, 10), wm, Vector3(0, 0.29, 0.03), Vector3(-12, 0, 0))
			var rar: int = it.get("rarity", 0)
			var band: Color = ItemDB.RARITY_COLORS[rar] if rar >= 2 else Color(0.9, 0.75, 0.35)
			_extra(h, MeshLib.cyl(0.142, 0.142, 0.04, 12), MeshLib.mat(band, 0.6, 0.4), Vector3(0, 0.13, 0.005), Vector3.ZERO, Vector3.ONE, true)
		"kettle":
			_extra(h, MeshLib.sphere(0.145, 10, 6), steel, Vector3(0, 0.06, 0), Vector3.ZERO, Vector3(1, 0.8, 1))
			_extra(h, MeshLib.cyl(0.24, 0.24, 0.02, 12), steel, Vector3(0, 0.04, 0))
		"greathelm":
			_extra(h, MeshLib.cyl(0.152, 0.152, 0.3, 12), steel, Vector3(0, 0.03, 0))
			_extra(h, MeshLib.box(Vector3(0.22, 0.022, 0.02)), MeshLib.mat(Color(0.05, 0.05, 0.05)), Vector3(0, 0.05, -0.152))
			if it.get("rarity", 0) >= 3 or _is_player():
				var pc: Color = (cloth_mat as StandardMaterial3D).albedo_color.lightened(0.2)
				_extra(h, MeshLib.box(Vector3(0.04, 0.12, 0.26)), MeshLib.mat(pc), Vector3(0, 0.23, 0.03))
		"morion":
			_extra(h, MeshLib.sphere(0.15, 10, 6), steel, Vector3(0, 0.07, 0), Vector3.ZERO, Vector3(0.9, 0.9, 1.3))
			_extra(h, MeshLib.box(Vector3(0.02, 0.1, 0.3)), steel, Vector3(0, 0.18, 0))
		"hat", "tophat":
			var hc2 := Color(0.15, 0.12, 0.12) if model == "tophat" else Color(0.25, 0.15, 0.2)
			_extra(h, MeshLib.cyl(0.25 if model == "hat" else 0.2, 0.25 if model == "hat" else 0.2, 0.02, 12), MeshLib.mat(hc2), Vector3(0, 0.1, 0))
			_extra(h, MeshLib.cyl(0.12, 0.13, 0.12 if model == "hat" else 0.26, 10), MeshLib.mat(hc2), Vector3(0, 0.17 if model == "hat" else 0.23, 0))
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
			_extra(h, MeshLib.box(Vector3(0.03, 0.04, 0.06)), MeshLib.mat(Color(0.1, 0.1, 0.1)), Vector3(0.14, 0.05, -0.04), Vector3.ZERO, Vector3.ONE, true)
		"mask":
			_extra(h, MeshLib.box(Vector3(0.24, 0.07, 0.03)), MeshLib.mat(Color(0.08, 0.05, 0.08)), Vector3(0, 0.05, -0.14))
			for sx in [-0.055, 0.055]:
				_extra(h, MeshLib.box(Vector3(0.045, 0.025, 0.01)), MeshLib.mat(Color(0.95, 0.85, 0.5), 0.7, 0.3), Vector3(sx, 0.055, -0.158), Vector3.ZERO, Vector3.ONE, true)
		"visor":
			_extra(h, MeshLib.sphere(0.158, 10, 6), MeshLib.mat(Color(0.2, 0.22, 0.28), 0.7, 0.3), Vector3(0, 0.03, 0))
			var vc: Color = Color(0.3, 0.9, 1.0) if it.get("rarity", 0) < 2 else ItemDB.RARITY_COLORS[it.rarity]
			_extra(h, MeshLib.box(Vector3(0.24, 0.06, 0.03)), MeshLib.glow(vc, 2.5), Vector3(0, 0.04, -0.14))

## Class-readable kit carried on the body.
func _class_gear(cls: String, armor_model: String, hm: String) -> void:
	var ch: Node3D = j.chest
	var hp: Node3D = j.hips
	match weapon_cat:
		"bow":
			if weapon_model == "crossbow":
				var bc := WeaponModels.stowed("holster")
				hp.add_child(bc)
				bc.position = Vector3(0.18 * _width, -0.05, 0.03)
				extras.append(bc)
			else:
				var q := WeaponModels.stowed("quiver")
				ch.add_child(q)
				q.position = Vector3(0.07, 0.14, 0.17)
				q.rotation = Vector3(0.25, 0, -0.45)
				extras.append(q)
				_extra(ch, MeshLib.box(Vector3(0.04, 0.58, 0.02)), MeshLib.mat(Color(0.3, 0.19, 0.1)), Vector3(0, 0.13, -0.137), Vector3(0, 0, -38))
		"sword":
			if not two_handed:
				var sc := WeaponModels.stowed("scabbard")
				hp.add_child(sc)
				sc.position = Vector3(-0.19 * _width, 0.06, -0.02)
				sc.rotation = Vector3(deg_to_rad(-118 if weapon_model != "katana" else -100), deg_to_rad(8), 0)
				extras.append(sc)
		"dagger":
			for sgn in [-1.0, 1.0]:
				var ds := WeaponModels.stowed("dagger_sheath")
				ch.add_child(ds)
				ds.position = Vector3(0.0, -0.06, 0.16)
				ds.rotation = Vector3(deg_to_rad(-90), 0, deg_to_rad(40 * sgn))
				extras.append(ds)
			# face scarf (rogue)
			if build_type == "normal" and (cls == "rogue" or hm in ["", "hood"]):
				_extra(j.head, MeshLib.box(Vector3(0.21, 0.09, 0.15)), MeshLib.mat(Color(0.14, 0.14, 0.16)), Vector3(0, -0.06, -0.06))
				_extra(j.neck, MeshLib.cyl(0.075, 0.09, 0.08, 8), MeshLib.mat(Color(0.14, 0.14, 0.16)), Vector3(0, 0.0, 0))
		"firearm":
			if two_handed:
				var bd := WeaponModels.stowed("bandolier")
				ch.add_child(bd)
				bd.position = Vector3(0, 0.12, -0.14)
				bd.rotation = Vector3(0, 0, deg_to_rad(36))
				extras.append(bd)
			else:
				var hs := WeaponModels.stowed("holster")
				j.leg_r.add_child(hs)
				hs.position = Vector3(0.085, -0.15, 0)
				extras.append(hs)
		"staff":
			if armor_model != "robe" and build_type == "normal":
				# satchel of reagents for non-robed casters
				_extra(hp, MeshLib.box(Vector3(0.1, 0.12, 0.06)), MeshLib.mat(Color(0.4, 0.28, 0.16)), Vector3(-0.15 * _width, -0.02, 0.05), Vector3(0, 30, 0))

func _extra(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, small: bool = false) -> void:
	var mi := MeshLib.part(parent, mesh, m, pos, rot, scl)
	if small:
		_small(mi)
	extras.append(mi)

# ---------------------------------------------------------------- animation API
func trigger(act: String) -> void:
	action = act
	action_p = 0.0
	if act == "parry":
		parry_t = 0.3

## dir: world-space push direction (attacker -> victim). heavy: stagger.
func on_hit(dir: Vector3 = Vector3.ZERO, heavy: bool = false) -> void:
	_hit_heavy = heavy
	_hit_max = 0.5 if heavy else 0.3
	hit_t = _hit_max
	var d := dir
	d.y = 0.0
	if d.length() > 0.01 and is_inside_tree():
		var l := global_transform.basis.inverse() * d
		l.y = 0.0
		_hit_local = l.normalized() if l.length() > 0.001 else Vector3(0, 0, 1)
	else:
		_hit_local = Vector3(0, 0, 1)

## Short parry flash pose (callable by the owner on a successful parry).
func parry() -> void:
	parry_t = 0.3

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam and not dead:
		var d2 := cam.global_position.distance_squared_to(global_position)
		if d2 > 1600.0:
			_lod_acc += delta
			if _lod_acc < (0.066 if d2 < 4900.0 else 0.15):
				return
			delta = _lod_acc
			_lod_acc = 0.0
	if Perf.enabled:
		var t0 := Time.get_ticks_usec()
		animate(delta)
		Perf.add("rig", Time.get_ticks_usec() - t0)
	else:
		animate(delta)

static func _ss(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)

static func _seg(p: float, a: float, b: float) -> float:
	return _ss((p - a) / (b - a))

## Blend a joint target: base -> windup -> strike, then back to base.
func _ap(key: String, wv: Vector3, sv: Vector3, w: float, st: float, rc: float) -> void:
	var base: Vector3 = _t[key]
	_t[key] = base.lerp(wv, w).lerp(sv, st).lerp(base, rc)

func animate(delta: float) -> void:
	_clock += delta
	hit_t = maxf(0.0, hit_t - delta)
	parry_t = maxf(0.0, parry_t - delta)
	var t := _t
	var rate := 11.0
	var sp := clampf(move_speed, 0.0, 1.8)
	var run_k := clampf((sp - 0.6) / 0.5, 0.0, 1.0)
	var heavy_build := build_type in ["golem", "colossus", "bulky"]
	var gait_k := 0.72 if heavy_build else 1.0
	var g_amp := 1.0
	var g_arm := 1.0
	var g_bounce := 1.0
	var g_low := 0.0
	match gait:
		"heavy":   # armoured, planted strides
			gait_k *= 0.88
			g_amp = 1.1
			g_bounce = 1.5
		"light":   # quick, low, springy
			gait_k *= 1.14
			g_arm = 0.85
			g_low = 0.035
		"soft":    # composed, gliding, hands ready to cast
			gait_k *= 0.95
			g_arm = 0.55
			g_bounce = 0.6
	if sp > 0.04:
		# below a slow walk the cadence drops too, so feet don't shuffle in place
		var cadence := clampf(sp / 0.28, 0.4, 1.0)
		_phase += delta * (4.4 + 4.6 * sp) * gait_k * cadence
	_breath += delta * (1.9 if build_type != "robot" else 0.0)
	var s := sin(_phase)
	var c := cos(_phase)
	var g := minf(sp, 1.3)
	var idle_k := clampf(1.0 - sp / 0.15, 0.0, 1.0)
	# ---- locomotion
	var amp := (0.5 * g + 0.12 * run_k) * (0.8 if heavy_build else 1.0) * g_amp
	var kb := (0.55 + 0.75 * run_k) * g
	t.leg_l = Vector3(s * amp, 0, -0.04 * idle_k)
	t.leg_r = Vector3(-s * amp, 0, 0.04 * idle_k)
	t.knee_l = Vector3(-maxf(0.0, c) * kb - 0.05 - 0.15 * run_k * maxf(0.0, -c), 0, 0)
	t.knee_r = Vector3(-maxf(0.0, -c) * kb - 0.05 - 0.15 * run_k * maxf(0.0, c), 0, 0)
	var arm_amp := (0.42 * g + 0.25 * run_k) * (0.5 if build_type == "robot" else 1.0) * g_arm
	t.arm_l = Vector3(-s * arm_amp, 0, -0.1 - 0.04 * idle_k)
	t.arm_r = Vector3(s * arm_amp, 0, 0.1 + 0.04 * idle_k)
	t.elbow_l = Vector3(0.22 + 0.25 * g + 0.65 * run_k, 0, 0)
	t.elbow_r = Vector3(0.22 + 0.25 * g + 0.65 * run_k, 0, 0)
	t.hand_l = Vector3.ZERO
	t.hand_r = Vector3.ZERO
	var breathe := sin(_breath) * 0.02 * (0.4 + idle_k)
	t.spine = Vector3(-0.05 * g - 0.16 * run_k + breathe, -s * 0.16 * g, 0)
	t.hips = Vector3(0, s * 0.12 * g, sin(_clock * 0.7) * 0.03 * idle_k)
	t.neck = Vector3(0.05 * g + 0.12 * run_k - breathe * 0.5, s * 0.1 * g, 0)
	var hips_y := 0.95 + absf(c) * (0.03 + 0.035 * run_k) * g * g_bounce - 0.035 * run_k - g_low * run_k
	# idle look-around
	if idle_k > 0.5 and action == "":
		if _clock > _look_next:
			_look_next = _clock + randf_range(2.5, 6.0)
			_look_yaw = 0.0 if randf() < 0.4 else randf_range(-0.55, 0.55)
	else:
		_look_yaw = 0.0
	t.neck.y += _look_yaw * idle_k
	# build posture
	match build_type:
		"bulky":
			t.spine.x -= 0.32
			t.neck.x += 0.3
			t.arm_l.x += 0.15
			t.arm_r.x += 0.15
			t.knee_l.x -= 0.12
			t.knee_r.x -= 0.12
			hips_y -= 0.04
		"golem", "colossus":
			t.leg_l.z -= 0.07
			t.leg_r.z += 0.07
			t.arm_l.z -= 0.18
			t.arm_r.z += 0.18
			t.hips.z += s * 0.06 * g
		"skeleton":
			t.neck.z = sin(_clock * 13.0) * 0.03
			t.arm_l.z -= 0.05
			t.arm_r.z += 0.05
		"robot":
			t.neck.y += sin(_clock * 0.8) * 0.3 * idle_k
	_carry(t, s, g, run_k, idle_k)
	# ---- stances
	var want_block := blocking and action == ""
	_block_k = move_toward(_block_k, 1.0 if want_block else 0.0, delta * 7.0)
	if want_block:
		_pose_block(t)
		rate = 18.0
	if crouch:
		hips_y -= 0.27
		t.spine.x -= 0.38
		t.neck.x += 0.3
		t.leg_l.x += 0.6
		t.leg_r.x += 0.6
		t.knee_l.x -= 1.0
		t.knee_r.x -= 1.0
		t.arm_l.x += 0.25
	if casting and action == "":
		t.arm_l = Vector3(1.3, 0.2, 0)
		t.elbow_l = Vector3(0.3, 0, 0)
		t.hand_l = Vector3(-1.0, 0, 0)
		if _cat != "staff":
			t.arm_r = Vector3(1.3, -0.2, 0)
			t.elbow_r = Vector3(0.3, 0, 0)
			t.hand_r = Vector3(-1.0, 0, 0)
	# ---- one-shot actions
	var aim_want := aiming and _cat in ["bow", "firearm"]
	var body_yaw := 0.0
	var hips_dy := 0.0
	if action != "":
		rate = 24.0
		var res := _pose_action(t, action, clampf(action_p, 0.0, 1.0))
		hips_dy = res.x
		body_yaw = res.y
		if action == "shoot" and _cat in ["bow", "firearm"]:
			aim_want = true
	elif aiming:
		_pose_aim(t, 0.4)
	if parry_t > 0.0:
		var pk := sin(parry_t / 0.3 * PI)
		t.arm_r = t.arm_r.lerp(Vector3(1.0, 0.0, 1.4), pk)
		t.elbow_r = t.elbow_r.lerp(Vector3(0.6, 0, 0), pk)
		t.hand_r = t.hand_r.lerp(Vector3(-0.4, 0.8, 0), pk)
		t.spine.x += 0.15 * pk
		rate = 26.0
	hips_y += hips_dy
	match pose:
		"sit":
			hips_y -= 0.42
			t.leg_l = Vector3(1.45, 0, 0.06)
			t.leg_r = Vector3(1.45, 0, -0.06)
			t.knee_l = Vector3(-1.5, 0, 0)
			t.knee_r = Vector3(-1.5, 0, 0)
			if action == "":
				t.arm_l = t.arm_l.lerp(Vector3(0.5, 0, -0.1), 0.8)
				t.arm_r = t.arm_r.lerp(Vector3(0.5, 0, 0.1), 0.8)
				t.elbow_l = Vector3(0.9, 0, 0)
				t.elbow_r = Vector3(0.9, 0, 0)
		"sleep":
			t.leg_l = Vector3(0.1, 0, 0)
			t.leg_r = Vector3(0.05, 0, 0)
			t.knee_l = Vector3(-0.2, 0, 0)
			t.knee_r = Vector3(-0.1, 0, 0)
			t.arm_l = Vector3(0.2, 0, -0.3)
			t.arm_r = Vector3(0.2, 0, 0.3)
	rotation.x = lerpf(rotation.x, -1.45 if pose == "sleep" else 0.0, minf(1.0, delta * 4.0))
	if yielding:
		hips_y = 0.55
		t.leg_l = Vector3(1.4, 0, 0)
		t.knee_l = Vector3(-1.5, 0, 0)
		t.leg_r = Vector3(-0.2, 0, 0)
		t.knee_r = Vector3(-1.6, 0, 0)
		t.arm_l = Vector3(2.6, 0, -0.3)
		t.arm_r = Vector3(2.6, 0, 0.3)
		t.elbow_l = Vector3(0.4, 0, 0)
		t.elbow_r = Vector3(0.4, 0, 0)
		t.spine = Vector3(-0.15, 0, 0)
		t.neck = Vector3(-0.35, 0, 0)
	# ---- hit reaction: flinch away from the blow, heavy = stagger
	var hk := 0.0
	if hit_t > 0.0 and not dead:
		var u := 1.0 - hit_t / _hit_max
		hk = sin(minf(1.0, u * 2.2) * PI * 0.5) * (1.0 - u) * 1.6
		var amt := 1.0 if _hit_heavy else 0.6
		t.spine.x += _hit_local.z * 0.6 * hk * amt
		t.spine.z -= _hit_local.x * 0.45 * hk * amt
		t.neck.x += _hit_local.z * 0.45 * hk * amt
		t.arm_l.z -= 0.35 * hk * amt
		t.arm_r.z += 0.35 * hk * amt
		t.arm_l.x += 0.3 * hk * amt
		if _hit_heavy:
			t.knee_l.x -= 0.4 * hk
			t.knee_r.x -= 0.3 * hk
			t.leg_l.x -= 0.3 * hk * _hit_local.z
			hips_y -= 0.06 * hk
		rate = maxf(rate, 20.0)
	# ---- death pose overrides limbs
	if dead:
		hips_y = _death_limbs(t, hips_y)
		rate = 8.0
	var k := minf(1.0, delta * rate)
	for jn in _JOINTS:
		var node: Node3D = j[jn]
		node.rotation = node.rotation.lerp(t[jn], k)
	j.hips.position.y = lerpf(j.hips.position.y, hips_y, minf(1.0, delta * 12.0))
	_update_body(delta, body_yaw, hk)
	_update_gear(delta, sp)

## Weapon carry / idle stances.
func _carry(t: Dictionary, s: float, g: float, run_k: float, idle_k: float) -> void:
	var sw := s * 0.12 * g
	match _cat:
		"staff":
			t.arm_r = Vector3(0.18 + sw, 0, 0.13)
			t.elbow_r = Vector3(0.4, 0, 0)
			t.hand_r = Vector3(HALF_PI - 0.58, 0, 0)
		"spear":
			t.arm_r = Vector3(0.3 + sw, 0, 0.12)
			t.elbow_r = Vector3(0.55, 0, 0)
			t.hand_r = Vector3(-0.3, 0, 0)
			t.arm_l = Vector3(0.75 + sw, 0, 0.32)
			t.elbow_l = Vector3(0.6, 0, 0)
		"bow":
			t.arm_l = Vector3(0.18 - s * 0.25 * g, 0, -0.14)
			t.elbow_l = Vector3(0.35, 0, 0)
			t.hand_l = Vector3(0.0, 0, 0.1)
		"firearm":
			if two_handed:
				t.arm_r = Vector3(0.45, 0, 0.12)
				t.elbow_r = Vector3(1.05, 0, 0)
				t.hand_r = Vector3(-1.2, 0, 0)
				t.arm_l = Vector3(0.85, 0, 0.5)
				t.elbow_l = Vector3(0.95, 0, 0)
			else:
				t.arm_r = Vector3(0.12 + sw, 0, 0.12)
				t.elbow_r = Vector3(0.5, 0, 0)
				t.hand_r = Vector3(-0.45, 0, 0)
		"heavy":
			if two_handed:
				if run_k > 0.3:
					# weapon rests on the shoulder while running
					t.arm_r = Vector3(1.2, 0, 0.25)
					t.elbow_r = Vector3(2.0, 0, 0)
					t.hand_r = Vector3(0.6, 0, 0)
				else:
					t.arm_r = Vector3(0.4, 0, 0.1)
					t.elbow_r = Vector3(0.95, 0, 0)
					t.hand_r = Vector3(0.75, 0.55, 0)
					t.arm_l = Vector3(0.62, 0, 0.45)
					t.elbow_l = Vector3(1.1, 0, 0)
			else:
				t.arm_r = Vector3(0.15 + sw, 0, 0.15)
				t.elbow_r = Vector3(0.55, 0, 0)
				t.hand_r = Vector3(0.15, 0, 0)
		"sword":
			if two_handed:
				t.arm_r = Vector3(0.4, 0, 0.05)
				t.elbow_r = Vector3(0.9, 0, 0)
				t.hand_r = Vector3(0.2, 0.3, 0)
				t.arm_l = Vector3(0.6, 0, 0.42)
				t.elbow_l = Vector3(1.0, 0, 0)
			else:
				t.arm_r = Vector3(0.2 + sw, 0, 0.14)
				t.elbow_r = Vector3(0.6, 0, 0)
				t.hand_r = Vector3(0.05, 0.15, 0)
		"dagger":
			t.arm_r = Vector3(0.3 + sw, 0, 0.14)
			t.elbow_r = Vector3(0.95, 0, 0)
			t.hand_r = Vector3(-0.35, 0, 0)
			if idle_k > 0.0:
				# rogue's low, ready crouch
				t.knee_l.x -= 0.18 * idle_k
				t.knee_r.x -= 0.18 * idle_k
				t.leg_l.x += 0.1 * idle_k
				t.spine.x -= 0.1 * idle_k
	if offhand_node != null and _shield_mount != null:
		t.arm_l = Vector3(0.25 - s * 0.12 * g, 0, -0.16)
		t.elbow_l = Vector3(0.65, 0, 0)

func _pose_block(t: Dictionary) -> void:
	if _shield_mount != null:
		t.arm_l = Vector3(1.05, 0.0, 0.3)
		t.elbow_l = Vector3(1.25, 0, 0)
		t.spine.x -= 0.08
		t.knee_l.x -= 0.2
		t.knee_r.x -= 0.25
		t.leg_l.x += 0.2
	elif _cat in ["bow", "firearm"]:
		t.arm_l = Vector3(1.4, 0.0, 0.5)
		t.elbow_l = Vector3(1.3, 0, 0)
		t.arm_r = Vector3(1.3, 0.0, -0.4)
		t.elbow_r = Vector3(1.3, 0, 0)
	else:
		# weapon guard across the body
		t.arm_r = Vector3(1.0, 0.35, 0)
		t.elbow_r = Vector3(1.15, 0, 0)
		t.hand_r = Vector3(0.1, 1.05, 0)
		t.arm_l = Vector3(0.9, 0.0, 0.35)
		t.elbow_l = Vector3(1.4, 0, 0)
		t.spine.y = -0.2
		t.knee_l.x -= 0.2
		t.knee_r.x -= 0.25

func _pose_aim(t: Dictionary, draw_p: float) -> void:
	match _cat:
		"bow":
			# sideways archer stance; bow arm horizontal toward the target
			t.hips.y = -0.35
			t.spine = Vector3(-0.05, -0.6, 0)
			t.neck = Vector3(0.0, 0.85, 0)
			t.arm_l = Vector3(0.0, -0.75, -1.5)
			t.elbow_l = Vector3(0.12, 0, 0)
			t.hand_l = Vector3(0, 0, 0)
			var yaw := lerpf(1.9, -0.95, draw_p)
			t.arm_r = Vector3(0.0, yaw, 1.5)
			t.elbow_r = Vector3(lerpf(0.4, 2.55, draw_p), 0, 0)
			t.hand_r = Vector3(0, 0, 0)
		"firearm":
			if two_handed:
				t.arm_r = Vector3(1.05, 0.3, 0)
				t.elbow_r = Vector3(1.35, 0, 0)
				t.arm_l = Vector3(1.4, -0.35, 0.1)
				t.elbow_l = Vector3(0.45, 0, 0)
				t.spine.y = -0.25
				t.neck.y = 0.2
			else:
				t.arm_r = Vector3(1.55, -0.05, 0)
				t.elbow_r = Vector3(0.05, 0, 0)
				t.spine.y = -0.15
		"staff":
			t.arm_r = Vector3(1.45, 0, 0.0)
			t.elbow_r = Vector3(0.1, 0, 0)
			t.hand_r = Vector3(-1.5, 0, 0)

## Returns Vector2(hips_dy, body_yaw).
func _pose_action(t: Dictionary, act: String, p: float) -> Vector2:
	var w := _seg(p, 0.0, 0.3)
	var st := _seg(p, 0.28, 0.46)
	var rc := _seg(p, 0.58, 1.0)
	var hold := st * (1.0 - rc)
	var hips_dy := 0.0
	var yaw := 0.0
	var two := two_handed or _cat in ["spear"]
	match act:
		"talk":
			var g1 := sin(p * TAU * 2.0)
			var e1 := _ss(p / 0.2) * (1.0 - _seg(p, 0.8, 1.0))
			t.arm_r = t.arm_r.lerp(Vector3(1.0 + 0.3 * g1, 0.2, 0.35), e1)
			t.elbow_r = t.elbow_r.lerp(Vector3(1.1, 0, 0), e1)
			t.arm_l = t.arm_l.lerp(Vector3(0.6 - 0.2 * g1, 0, -0.3), e1 * 0.7)
			t.neck.y += 0.15 * g1 * e1
		"drink":
			var e2 := _ss(p / 0.35) * (1.0 - _seg(p, 0.7, 1.0))
			t.arm_r = t.arm_r.lerp(Vector3(1.9, 0, 0.35), e2)
			t.elbow_r = t.elbow_r.lerp(Vector3(2.2, 0, 0), e2)
			t.neck.x -= 0.35 * e2
		"play":
			var str_k := sin(p * TAU * 4.0)
			t.arm_l = t.arm_l.lerp(Vector3(1.1, 0.4, -0.2), 0.9)
			t.elbow_l = t.elbow_l.lerp(Vector3(1.3, 0, 0), 0.9)
			t.arm_r = t.arm_r.lerp(Vector3(0.7 + 0.15 * str_k, -0.3, 0.25), 0.9)
			t.elbow_r = t.elbow_r.lerp(Vector3(1.2, 0, 0), 0.9)
			t.neck.x += 0.1
		"slash":
			# forehand: sweep from back-right around the front to the left
			_ap("spine", Vector3(-0.08, -0.7, 0), Vector3(-0.2, 0.65, 0), w, st, rc)
			_ap("arm_r", Vector3(0.0, -0.6, 1.75), Vector3(0.0, 2.15, 1.3), w, st, rc)
			_ap("elbow_r", Vector3(0.75, 0, 0), Vector3(0.1, 0, 0), w, st, rc)
			_ap("hand_r", Vector3(-2.2, 0, 0), Vector3(-1.65, 0, 0), w, st, rc)
			_ap("leg_l", Vector3(-0.1, 0, 0), Vector3(0.45, 0, 0), w, st, rc)
			_ap("knee_l", Vector3(-0.1, 0, 0), Vector3(-0.35, 0, 0), w, st, rc)
			_ap("leg_r", Vector3(0.1, 0, 0), Vector3(-0.3, 0, 0), w, st, rc)
			_ap("arm_l", Vector3(0.5, 0, -0.5), Vector3(0.2, 0, -0.7), w, st, rc)
			t.neck.y -= t.spine.y * 0.6
			hips_dy = -0.06 * hold
		"slash2":
			# backhand: from across the chest out to the right, rising
			_ap("spine", Vector3(-0.08, 0.6, 0), Vector3(-0.15, -0.7, 0), w, st, rc)
			_ap("arm_r", Vector3(0.5, 2.5, 1.3), Vector3(0.45, -0.5, 1.65), w, st, rc)
			_ap("elbow_r", Vector3(1.5, 0, 0), Vector3(0.12, 0, 0), w, st, rc)
			_ap("hand_r", Vector3(-1.1, 0, 0), Vector3(-1.7, 0, 0), w, st, rc)
			_ap("leg_r", Vector3(0.0, 0, 0), Vector3(0.4, 0, 0), w, st, rc)
			_ap("knee_r", Vector3(-0.1, 0, 0), Vector3(-0.3, 0, 0), w, st, rc)
			_ap("leg_l", Vector3(0.0, 0, 0), Vector3(-0.25, 0, 0), w, st, rc)
			t.neck.y -= t.spine.y * 0.6
			hips_dy = -0.05 * hold
		"thrust", "stab":
			var k := 1.0 if act == "thrust" else 0.7
			_ap("arm_r", Vector3(0.4, 0.2, 0.05), Vector3(1.5, -0.08, 0.0), w, st, rc)
			_ap("elbow_r", Vector3(1.85, 0, 0), Vector3(0.05, 0, 0), w, st, rc)
			_ap("hand_r", Vector3(-2.25, 0, 0), Vector3(-1.55, 0, 0), w, st, rc)
			_ap("spine", Vector3(0.05, -0.45 * k, 0), Vector3(-0.3 * k, 0.35 * k, 0), w, st, rc)
			_ap("leg_l", Vector3(0.0, 0, 0), Vector3(0.6 * k, 0, 0), w, st, rc)
			_ap("knee_l", Vector3(-0.15, 0, 0), Vector3(-0.5 * k, 0, 0), w, st, rc)
			_ap("leg_r", Vector3(0.0, 0, 0), Vector3(-0.45 * k, 0, 0), w, st, rc)
			if two:
				_ap("arm_l", Vector3(0.6, -0.1, 0.4), Vector3(1.35, 0.25, 0.2), w, st, rc)
				_ap("elbow_l", Vector3(1.4, 0, 0), Vector3(0.35, 0, 0), w, st, rc)
			else:
				_ap("arm_l", Vector3(0.6, 0, -0.3), Vector3(-0.3, 0, -0.35), w, st, rc)
			hips_dy = -0.11 * k * hold
		"overhead", "slam":
			var deep := act == "slam" or (two_handed and _cat == "heavy")
			_ap("arm_r", Vector3(2.85, 0, 0.1), Vector3(0.7 if not deep else 0.4, 0, 0.05), w, st, rc)
			_ap("elbow_r", Vector3(0.8, 0, 0), Vector3(0.1, 0, 0), w, st, rc)
			_ap("hand_r", Vector3(0.25, 0, 0), Vector3(-0.85 if not deep else -0.75, 0, 0), w, st, rc)
			if two or act == "slam":
				_ap("arm_l", Vector3(2.85, 0, 0.45), Vector3(0.75 if not deep else 0.45, 0, 0.45), w, st, rc)
				_ap("elbow_l", Vector3(0.8, 0, 0), Vector3(0.15, 0, 0), w, st, rc)
			_ap("spine", Vector3(0.3, -0.15, 0), Vector3(-0.5 if not deep else -0.75, 0.05, 0), w, st, rc)
			_ap("leg_l", Vector3(0.0, 0, 0), Vector3(0.45, 0, 0), w, st, rc)
			_ap("knee_l", Vector3(0.0, 0, 0), Vector3(-0.5 if not deep else -0.8, 0, 0), w, st, rc)
			_ap("knee_r", Vector3(0.0, 0, 0), Vector3(-0.2 if not deep else -0.7, 0, 0), w, st, rc)
			_ap("neck", Vector3(0.25, 0, 0), Vector3(0.3, 0, 0), w, st, rc)
			hips_dy = (-0.08 if not deep else -0.22) * hold
		"spin":
			var sp2 := _seg(p, 0.08, 0.72)
			yaw = TAU * sp2
			var out := _seg(p, 0.0, 0.15) * (1.0 - _seg(p, 0.8, 1.0))
			t.arm_r = t.arm_r.lerp(Vector3(0.0, -0.2, 1.45), out)
			t.elbow_r = t.elbow_r.lerp(Vector3(0.08, 0, 0), out)
			t.hand_r = t.hand_r.lerp(Vector3(-1.65, 0, 0), out)
			t.arm_l = t.arm_l.lerp(Vector3(0.0, 0.3, -1.25), out)
			t.spine.x -= 0.15 * out
			t.knee_l.x -= 0.35 * out
			t.knee_r.x -= 0.35 * out
			hips_dy = -0.1 * out
		"shoot":
			match _cat:
				"bow":
					var draw := _seg(p, 0.05, 0.5) * (1.0 - _seg(p, 0.53, 0.58))
					var settle := _seg(p, 0.0, 0.15) * (1.0 - _seg(p, 0.8, 1.0))
					for key in AIM_KEYS:
						_tmp[key] = t[key]
					_pose_aim(t, draw)
					for key2 in AIM_KEYS:
						var bv: Vector3 = _tmp[key2]
						t[key2] = bv.lerp(t[key2], settle)
				"firearm":
					_pose_aim(t, 1.0)
					var kick := 1.0 - _seg(p, 0.05, 0.6)
					t.arm_r.x += 0.38 * kick
					t.elbow_r.x += 0.2 * kick
					t.spine.x += 0.1 * kick
					t.neck.x += 0.05 * kick
				_:
					_pose_cast(t, p)
		"cast":
			_pose_cast(t, p)
			hips_dy = -0.04 * _seg(p, 0.4, 0.55) * (1.0 - _seg(p, 0.7, 1.0))
		"kick":
			_ap("leg_r", Vector3(-0.35, 0, 0), Vector3(1.5, 0, 0), w, st, rc)
			_ap("knee_r", Vector3(-1.4, 0, 0), Vector3(-0.05, 0, 0), w, st, rc)
			_ap("spine", Vector3(0.0, 0, 0), Vector3(0.25, 0, 0), w, st, rc)
			_ap("arm_l", Vector3(0.4, 0, -0.5), Vector3(0.6, 0, -0.7), w, st, rc)
			_ap("arm_r", Vector3(0.4, 0, 0.5), Vector3(-0.2, 0, 0.6), w, st, rc)
		"throw":
			_ap("arm_r", Vector3(2.6, 0, 0.3), Vector3(1.2, 0, 0.1), w, st, rc)
			_ap("elbow_r", Vector3(1.7, 0, 0), Vector3(0.1, 0, 0), w, st, rc)
			_ap("spine", Vector3(0.2, -0.5, 0), Vector3(-0.3, 0.4, 0), w, st, rc)
			_ap("arm_l", Vector3(1.2, 0, -0.2), Vector3(0.3, 0, -0.4), w, st, rc)
			_ap("leg_l", Vector3(0.0, 0, 0), Vector3(0.45, 0, 0), w, st, rc)
		"interact":
			var e := _ss(p / 0.4) * (1.0 - _seg(p, 0.65, 1.0))
			t.arm_r = t.arm_r.lerp(Vector3(1.0, 0, 0.1), e)
			t.arm_l = t.arm_l.lerp(Vector3(0.9, 0, -0.1), e)
			t.spine.x -= 0.4 * e
			t.knee_l.x -= 0.3 * e
			t.knee_r.x -= 0.3 * e
			hips_dy = -0.08 * e
		"cheer":
			var e2 := _ss(p / 0.3) * (1.0 - _seg(p, 0.75, 1.0))
			var bob := absf(sin(p * TAU * 2.0))
			t.arm_r = t.arm_r.lerp(Vector3(2.8, 0, 0.25), e2)
			t.arm_l = t.arm_l.lerp(Vector3(2.8, 0, -0.25), e2)
			t.spine.x += 0.12 * e2
			hips_dy = 0.06 * bob * e2
		"roar":
			var e3 := _ss(p / 0.3) * (1.0 - _seg(p, 0.75, 1.0))
			t.arm_r = t.arm_r.lerp(Vector3(0.9, 0, 1.3), e3)
			t.arm_l = t.arm_l.lerp(Vector3(0.9, 0, -1.3), e3)
			t.elbow_r.x += 0.8 * e3
			t.elbow_l.x += 0.8 * e3
			t.spine.x += 0.35 * e3
			t.neck.x += 0.45 * e3
		"parry":
			var e4 := sin(clampf(p, 0.0, 1.0) * PI)
			t.arm_r = t.arm_r.lerp(Vector3(1.0, 0.0, 1.4), e4)
			t.hand_r = t.hand_r.lerp(Vector3(-0.4, 0.8, 0), e4)
			t.spine.x += 0.15 * e4
	return Vector2(hips_dy, yaw)

## Casting gesture: gather (0..0.42), release (0.42..0.58), recover.
func _pose_cast(t: Dictionary, p: float) -> void:
	var w := _seg(p, 0.0, 0.42)
	var st := _seg(p, 0.42, 0.56)
	var rc := _seg(p, 0.68, 1.0)
	if _cat == "staff":
		_ap("arm_r", Vector3(2.45, 0, 0.12), Vector3(1.4, 0.05, 0), w, st, rc)
		_ap("elbow_r", Vector3(0.35, 0, 0), Vector3(0.1, 0, 0), w, st, rc)
		_ap("hand_r", Vector3(-1.25, 0, 0), Vector3(-1.5, 0, 0), w, st, rc)
		_ap("arm_l", Vector3(0.9, -0.2, -0.2), Vector3(1.35, 0.3, 0), w, st, rc)
		_ap("elbow_l", Vector3(1.2, 0, 0), Vector3(0.15, 0, 0), w, st, rc)
		_ap("hand_l", Vector3(0.0, 0, 0), Vector3(-1.1, 0, 0), w, st, rc)
	else:
		_ap("arm_l", Vector3(0.6, -0.35, 0), Vector3(1.5, 0.12, 0), w, st, rc)
		_ap("arm_r", Vector3(0.6, 0.35, 0), Vector3(1.5, -0.12, 0), w, st, rc)
		_ap("elbow_l", Vector3(1.7, 0, 0), Vector3(0.05, 0, 0), w, st, rc)
		_ap("elbow_r", Vector3(1.7, 0, 0), Vector3(0.05, 0, 0), w, st, rc)
		_ap("hand_l", Vector3(0.0, 0, 0), Vector3(-1.1, 0, 0), w, st, rc)
		_ap("hand_r", Vector3(0.0, 0, 0), Vector3(-1.1, 0, 0), w, st, rc)
	_ap("spine", Vector3(0.14, 0, 0), Vector3(-0.22, 0, 0), w, st, rc)
	_ap("neck", Vector3(-0.1, 0, 0), Vector3(0.12, 0, 0), w, st, rc)
	_ap("leg_l", Vector3(0.0, 0, 0), Vector3(0.3, 0, 0), w, st, rc)

## Limb pose while dead (variant chosen at the moment of death).
func _death_limbs(t: Dictionary, hips_y: float) -> float:
	if _death_kind < 0:
		if build_type in ["skeleton", "golem", "colossus"]:
			_death_kind = 4
		elif _hit_heavy:
			_death_kind = 3
		elif _hit_local.z < -0.35:
			_death_kind = 1
		else:
			_death_kind = 2 if randf() < 0.4 else 0
	var e := _dead_t
	match _death_kind:
		0, 3:
			t.arm_l = Vector3(0.7, 0, -1.0)
			t.arm_r = Vector3(0.9, 0, 1.1)
			t.elbow_l = Vector3(0.5, 0, 0)
			t.elbow_r = Vector3(0.3, 0, 0)
			t.leg_l = Vector3(0.25, 0, -0.1)
			t.leg_r = Vector3(0.05, 0, 0.12)
			t.knee_l = Vector3(-0.4, 0, 0)
			t.knee_r = Vector3(-0.1, 0, 0)
			t.spine = Vector3(0.15, 0.1, 0)
			t.neck = Vector3(0.35, 0.4, 0)
		1:
			t.arm_l = Vector3(2.4, 0, -0.5)
			t.arm_r = Vector3(2.2, 0, 0.6)
			t.elbow_l = Vector3(0.6, 0, 0)
			t.elbow_r = Vector3(0.4, 0, 0)
			t.leg_l = Vector3(-0.1, 0, 0)
			t.leg_r = Vector3(0.1, 0, 0)
			t.knee_l = Vector3(-0.3, 0, 0)
			t.knee_r = Vector3(-0.6, 0, 0)
			t.spine = Vector3(-0.1, 0, 0)
			t.neck = Vector3(0.3, -0.6, 0)
		2:
			# drop to the knees, then pitch forward
			t.leg_l = Vector3(0.1, 0, -0.05)
			t.leg_r = Vector3(0.0, 0, 0.05)
			t.knee_l = Vector3(-1.5, 0, 0)
			t.knee_r = Vector3(-1.55, 0, 0)
			t.arm_l = Vector3(0.3, 0, -0.2)
			t.arm_r = Vector3(0.4, 0, 0.2)
			t.elbow_l = Vector3(0.3, 0, 0)
			t.elbow_r = Vector3(0.3, 0, 0)
			t.spine = Vector3(-0.45, 0, 0)
			t.neck = Vector3(-0.4, 0, 0)
			hips_y = lerpf(0.95, 0.5, clampf(e * 2.0, 0.0, 1.0))
		4:
			t.leg_l = Vector3(1.2, 0, -0.4)
			t.leg_r = Vector3(1.0, 0, 0.45)
			t.knee_l = Vector3(-2.2, 0, 0)
			t.knee_r = Vector3(-2.0, 0, 0)
			t.spine = Vector3(-0.9, 0, 0.2)
			t.neck = Vector3(-0.5, 0, 0.3)
			t.arm_l = Vector3(0.2, 0, -0.5)
			t.arm_r = Vector3(0.3, 0, 0.7)
			hips_y = lerpf(0.95, 0.22, e)
	return hips_y

## Whole-body transforms: death falls, dodge roll, spin, knockback slide.
func _update_body(delta: float, body_yaw: float, hk: float) -> void:
	var body: Node3D = j.body
	if dead:
		var spd := 2.2 if _death_kind != 2 else 1.3
		_dead_t = minf(_dead_t + delta * spd, 1.0)
		var e := 1.0 - pow(1.0 - _dead_t, 3.0)
		match _death_kind:
			0:
				body.rotation = Vector3(1.45 * e, 0, 0)
				body.position = Vector3(0, 0.06 * e, 0.12 * e)
			1:
				body.rotation = Vector3(-1.42 * e, 0, 0)
				body.position = Vector3(0, 0.08 * e, -0.15 * e)
			2:
				var f := _seg(_dead_t, 0.45, 1.0)
				body.rotation = Vector3(-1.3 * f, 0, 0.15 * f)
				body.position = Vector3(0, 0.05 * f, -0.1 * f)
			3:
				body.rotation = Vector3(1.45 * e, 0.7 * e, 0)
				body.position = _hit_local * 0.75 * e + Vector3(0, 0.06 * e, 0)
			_:
				body.rotation = Vector3(0, 0, 0.25 * e)
				body.position = Vector3.ZERO
		return
	_dead_t = 0.0
	_death_kind = -1
	if dodging:
		var dp := _ss(dodge_p)
		var ang := -TAU * dp
		var h := 0.55
		body.rotation = Vector3(ang, 0, 0)
		body.position = Vector3(0, h - h * cos(ang) - 0.25 * sin(PI * dodge_p), -h * sin(ang))
		var tuck := sin(PI * clampf(dodge_p, 0.0, 1.0))
		for side in SIDES:
			(j["leg_" + side] as Node3D).rotation.x = 1.4 * tuck
			(j["knee_" + side] as Node3D).rotation.x = -1.9 * tuck
			(j["arm_" + side] as Node3D).rotation.x = 1.0 * tuck
			(j["elbow_" + side] as Node3D).rotation.x = 1.5 * tuck
		(j.spine as Node3D).rotation.x = -0.9 * tuck
		(j.neck as Node3D).rotation.x = -0.6 * tuck
		return
	var kl := minf(1.0, delta * 15.0)
	var rot := body.rotation
	rot.x = lerpf(rot.x, 0.0, kl)
	rot.z = lerpf(rot.z, 0.0, kl)
	if body_yaw != 0.0:
		rot.y = body_yaw
	else:
		rot.y = lerp_angle(rot.y, 0.0, kl)
	if absf(rot.x) < 0.005:
		rot.x = 0.0
	body.rotation = rot
	# heavy hits shove the body back a little (visual knockback)
	var push := Vector3.ZERO
	if _hit_heavy and hk > 0.0:
		push = _hit_local * 0.12 * hk
	body.position = body.position.lerp(push, kl)

## Shield facing, bow string, aimed weapon orientation, staff grip, cape.
func _update_gear(delta: float, sp: float) -> void:
	if _shield_mount != null and is_instance_valid(_shield_mount):
		if _block_k > 0.001:
			var want := _rig_basis(j.elbow_l).inverse() * _SHIELD_BLOCK
			_shield_mount.basis = Basis(_SHIELD_IDLE.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), _ss(_block_k)))
		else:
			_shield_mount.basis = _SHIELD_IDLE
	var aim_on := (action == "shoot" and weapon_cat in ["bow", "firearm"]) or (aiming and weapon_cat in ["bow", "firearm"])
	_aim_k = move_toward(_aim_k, 1.0 if aim_on else 0.0, delta * 9.0)
	if weapon_node != null and is_instance_valid(weapon_node):
		if weapon_cat in ["bow", "firearm"]:
			if _aim_k > 0.001:
				var parent: Node3D = weapon_node.get_parent()
				var want2 := _rig_basis(parent).inverse()
				weapon_node.basis = Basis(Quaternion.IDENTITY.slerp(want2.get_rotation_quaternion(), _ss(_aim_k)))
			elif weapon_node.basis != Basis.IDENTITY:
				weapon_node.basis = Basis.IDENTITY
		if weapon_cat == "staff":
			var planted := action == "" and not blocking and not dead
			_staff_drop = move_toward(_staff_drop, 0.45 if planted else 0.08, delta * 2.5)
			weapon_node.position = Vector3(0, -0.05, _staff_drop)
			var orbit: Node3D = weapon_node.get_node_or_null("Orbit")
			if orbit:
				orbit.rotation.y += delta * 2.0
	# bow string follows the drawing hand
	if _bow_top != null and is_instance_valid(_bow_top):
		var drawing := action == "shoot" and action_p < 0.54 and not dead
		var want_d := 0.0
		if drawing:
			var lp := weapon_node.to_local(hand_pos("r"))
			want_d = clampf(lp.z + 0.02, 0.0, 0.62)
			_draw = want_d if want_d > _draw else lerpf(_draw, want_d, minf(1.0, delta * 10.0))
		else:
			_draw = move_toward(_draw, 0.0, delta * 9.0)
		var half := _bow_half
		var ln := sqrt(half * half + _draw * _draw)
		var a := atan2(_draw, half)
		_bow_top.rotation.x = -a
		_bow_bot.rotation.x = a
		_bow_top.scale.y = ln
		_bow_bot.scale.y = ln
		if _bow_arrow != null:
			_bow_arrow.visible = drawing and _draw > 0.08
			_bow_arrow.position.z = -0.02 + _draw
	# secondary motion: turning swings cape and hair sideways, a sudden stop
	# throws the cape forward, a sudden start pulls it back
	if delta > 0.0001 and is_inside_tree():
		var yaw := global_rotation.y
		_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _last_yaw, -PI, PI) / delta, minf(1.0, delta * 10.0))
		_last_yaw = yaw
		_sp_accel = lerpf(_sp_accel, (sp - _last_sp) / delta, minf(1.0, delta * 8.0))
		_last_sp = sp
	_cape_z = lerpf(_cape_z, clampf(-_yaw_rate * 0.07, -0.4, 0.4), minf(1.0, delta * 5.0))
	_cape_kick = lerpf(_cape_kick, clampf(-_sp_accel * 0.12, -0.35, 0.45), minf(1.0, delta * 4.0))
	if parts.has("hair") and parts.hair is Node3D and (parts.hair as Node3D).visible:
		var hn: Node3D = parts.hair
		hn.rotation.z = lerpf(hn.rotation.z, clampf(-_yaw_rate * 0.015, -0.06, 0.06), minf(1.0, delta * 7.0))
		hn.rotation.x = lerpf(hn.rotation.x, sin(_phase * 2.0) * 0.01 * minf(sp, 1.2) + _cape_kick * 0.04, minf(1.0, delta * 9.0))
	# cape: hangs from the shoulders, lifts when running, flutters
	if j.has("cape"):
		var cp: Node3D = j.cape
		var lift := 0.08 + sp * 0.42 + sin(_breath * 1.7) * 0.03 - _cape_kick
		var spine_x: float = (j.spine as Node3D).rotation.x + (j.hips as Node3D).rotation.x
		cp.rotation.x = lerpf(cp.rotation.x, -lift - spine_x, minf(1.0, delta * 8.0))
		cp.rotation.z = _cape_z
		if j.has("cape2"):
			var c2: Node3D = j.cape2
			c2.rotation.x = lerpf(c2.rotation.x, -sp * 0.35 - absf(sin(_phase)) * 0.12 * sp - sin(_clock * 2.3) * 0.05, minf(1.0, delta * 6.0))

func _rig_basis(n: Node3D) -> Basis:
	return global_transform.basis.orthonormalized().inverse() * n.global_transform.basis.orthonormalized()
