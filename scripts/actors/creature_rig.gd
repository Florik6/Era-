class_name CreatureRig
extends Node3D
## Procedural non-humanoid creatures: wolves, drones, spiders, wraiths,
## alchemical blobs and mimics. Same animation interface as HumanoidRig.

var kind := "wolf"
var j := {}
var move_speed := 0.0
var action := ""
var action_p := 0.0
var dead := false
var hit_t := 0.0
var blocking := false
var aiming := false
var dodging := false
var dodge_p := 0.0
var crouch := false
var yielding := false
var casting := false
var weapon_node: Node3D = null
var weapon_cat := "unarmed"
var weapon_model := ""
var two_handed := false
var dormant := false        # mimic disguised as a chest
var _phase := 0.0
var _t := 0.0
var _dead_t := 0.0
var body_mat: Material
var look := {}

func setup(l: Dictionary) -> void:
	look = l
	kind = l.get("rig", "wolf")
	var col: Color = l.get("body", Color(0.5, 0.45, 0.4))
	body_mat = MeshLib.mat(col, 0.7 if l.get("metal", false) else 0.0, 0.4 if l.get("metal", false) else 0.8, 0.8 if kind == "wraith" else 0.0)
	var b := MeshLib.pivot(self, Vector3.ZERO, "body")
	j.body = b
	match kind:
		"wolf": _build_wolf(b, col)
		"drone": _build_drone(b, col)
		"spider": _build_spider(b, col)
		"wraith": _build_wraith(b, col)
		"blob": _build_blob(b, col)
		"mimic": _build_mimic(b, col)
	scale = Vector3.ONE * l.get("scale", 1.0)

func _build_wolf(b: Node3D, col: Color) -> void:
	var torso := MeshLib.pivot(b, Vector3(0, 0.62, 0), "torso")
	j.torso = torso
	MeshLib.part(torso, MeshLib.capsule(0.2, 0.95), body_mat, Vector3.ZERO, Vector3(90, 0, 0))
	var head := MeshLib.pivot(torso, Vector3(0, 0.12, -0.52), "head")
	j.head = head
	MeshLib.part(head, MeshLib.box(Vector3(0.24, 0.22, 0.26)), body_mat)
	MeshLib.part(head, MeshLib.box(Vector3(0.13, 0.1, 0.2)), body_mat, Vector3(0, -0.04, -0.2))
	MeshLib.part(head, MeshLib.box(Vector3(0.05, 0.03, 0.03)), MeshLib.mat(Color(0.05, 0.05, 0.05)), Vector3(0, -0.01, -0.31))
	for sx in [-0.07, 0.07]:
		MeshLib.part(head, MeshLib.prism(Vector3(0.07, 0.12, 0.04)), body_mat, Vector3(sx, 0.15, 0.02))
		MeshLib.part(head, MeshLib.box(Vector3(0.03, 0.03, 0.01)), MeshLib.glow(Color(1.0, 0.8, 0.2), 1.2), Vector3(sx, 0.04, -0.13), Vector3.ZERO, Vector3.ONE, false)
	var tail := MeshLib.pivot(torso, Vector3(0, 0.08, 0.5), "tail")
	j.tail = tail
	MeshLib.part(tail, MeshLib.capsule(0.05, 0.4), body_mat, Vector3(0, 0, 0.18), Vector3(70, 0, 0))
	var i := 0
	for pos in [Vector3(-0.12, -0.05, -0.32), Vector3(0.12, -0.05, -0.32), Vector3(-0.12, -0.05, 0.32), Vector3(0.12, -0.05, 0.32)]:
		var leg := MeshLib.pivot(torso, pos, "leg%d" % i)
		j["leg%d" % i] = leg
		MeshLib.part(leg, MeshLib.capsule(0.045, 0.55), body_mat, Vector3(0, -0.27, 0))
		i += 1

func _build_drone(b: Node3D, col: Color) -> void:
	var core := MeshLib.pivot(b, Vector3(0, 1.9, 0), "core")
	j.core = core
	MeshLib.part(core, MeshLib.box(Vector3(0.5, 0.18, 0.5)), body_mat)
	MeshLib.part(core, MeshLib.sphere(0.12, 8, 5), MeshLib.glow(Color(1.0, 0.25, 0.2), 3.0), Vector3(0, -0.1, -0.2))
	MeshLib.part(core, MeshLib.cyl(0.03, 0.03, 0.4, 6), MeshLib.mat(Color(0.15, 0.15, 0.15), 0.6, 0.4), Vector3(0, -0.12, -0.35), Vector3(90, 0, 0))
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		var arm_pos := Vector3(cos(a) * 0.42, 0.04, sin(a) * 0.42)
		MeshLib.part(core, MeshLib.box(Vector3(0.4, 0.04, 0.05)), body_mat, arm_pos * 0.5, Vector3(0, -rad_to_deg(a), 0))
		var rot := MeshLib.pivot(core, arm_pos + Vector3(0, 0.06, 0), "rotor%d" % k)
		j["rotor%d" % k] = rot
		MeshLib.part(rot, MeshLib.box(Vector3(0.34, 0.01, 0.05)), MeshLib.mat(Color(0.1, 0.1, 0.1)), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)

func _build_spider(b: Node3D, col: Color) -> void:
	var torso := MeshLib.pivot(b, Vector3(0, 0.55, 0), "torso")
	j.torso = torso
	MeshLib.part(torso, MeshLib.sphere(0.3, 10, 6), body_mat, Vector3(0, 0, 0), Vector3.ZERO, Vector3(1.0, 0.6, 1.2))
	MeshLib.part(torso, MeshLib.sphere(0.4, 10, 6), body_mat, Vector3(0, 0.08, 0.5), Vector3.ZERO, Vector3(1.0, 0.75, 1.1))
	MeshLib.part(torso, MeshLib.sphere(0.12, 8, 5), MeshLib.glow(Color(1.0, 0.5, 0.15), 2.5), Vector3(0, 0.05, -0.3))
	for k in 6:
		var side := -1.0 if k < 3 else 1.0
		var zi := (k % 3 - 1) * 0.28
		var leg := MeshLib.pivot(torso, Vector3(0.22 * side, 0, zi), "leg%d" % k)
		j["leg%d" % k] = leg
		var up := MeshLib.pivot(leg, Vector3.ZERO, "up%d" % k)
		up.rotation.z = -0.7 * side
		MeshLib.part(up, MeshLib.cyl(0.035, 0.035, 0.5, 5), body_mat, Vector3(0.25 * side, 0, 0), Vector3(0, 0, 90))
		var low := MeshLib.pivot(up, Vector3(0.5 * side, 0, 0), "low%d" % k)
		low.rotation.z = 1.7 * side
		MeshLib.part(low, MeshLib.cyl(0.03, 0.015, 0.65, 5), body_mat, Vector3(0.32 * side, 0, 0), Vector3(0, 0, 90))

func _build_wraith(b: Node3D, col: Color) -> void:
	var torso := MeshLib.pivot(b, Vector3(0, 1.2, 0), "torso")
	j.torso = torso
	MeshLib.part(torso, MeshLib.cyl(0.18, 0.4, 1.1, 10), body_mat, Vector3(0, -0.35, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshLib.part(torso, MeshLib.sphere(0.2, 8, 6), body_mat, Vector3(0, 0.38, 0))
	for sx in [-0.06, 0.06]:
		MeshLib.part(torso, MeshLib.sphere(0.035, 6, 4), MeshLib.glow(look.get("glow", Color(0.8, 1.0, 1.0)), 4.0), Vector3(sx, 0.4, -0.17), Vector3.ZERO, Vector3.ONE, false)
	for side in [-1.0, 1.0]:
		var arm := MeshLib.pivot(torso, Vector3(0.22 * side, 0.2, 0), "arm%d" % (0 if side < 0 else 1))
		j["arm%d" % (0 if side < 0 else 1)] = arm
		MeshLib.part(arm, MeshLib.cyl(0.04, 0.08, 0.6, 6), body_mat, Vector3(0, -0.3, 0), Vector3.ZERO, Vector3.ONE, false)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.7
	light.omni_range = 4.0
	light.shadow_enabled = false
	torso.add_child(light)

func _build_blob(b: Node3D, col: Color) -> void:
	var torso := MeshLib.pivot(b, Vector3(0, 0.45, 0), "torso")
	j.torso = torso
	var m := MeshLib.mat(Color(col.r, col.g, col.b, 0.85), 0.0, 0.2, 0.4)
	MeshLib.part(torso, MeshLib.sphere(0.5, 12, 8), m, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.85, 1.0))
	MeshLib.part(torso, MeshLib.sphere(0.2, 8, 6), MeshLib.mat(col.darkened(0.4)), Vector3(0, 0, 0))
	for sx in [-0.14, 0.14]:
		MeshLib.part(torso, MeshLib.sphere(0.07, 6, 4), MeshLib.mat(Color(1, 1, 1)), Vector3(sx, 0.18, -0.38))
		MeshLib.part(torso, MeshLib.sphere(0.035, 6, 4), MeshLib.mat(Color(0, 0, 0)), Vector3(sx, 0.18, -0.44))

func _build_mimic(b: Node3D, col: Color) -> void:
	var wood := MeshLib.mat(Color(0.48, 0.32, 0.16))
	var iron := MeshLib.mat(Color(0.35, 0.33, 0.3), 0.7, 0.4)
	var base := MeshLib.pivot(b, Vector3(0, 0.0, 0), "base")
	j.base = base
	MeshLib.part(base, MeshLib.box(Vector3(0.9, 0.5, 0.6)), wood, Vector3(0, 0.25, 0))
	MeshLib.part(base, MeshLib.box(Vector3(0.92, 0.06, 0.62)), iron, Vector3(0, 0.45, 0))
	var tongue := MeshLib.part(base, MeshLib.box(Vector3(0.18, 0.04, 0.6)), MeshLib.mat(Color(0.8, 0.2, 0.3)), Vector3(0, 0.5, -0.2))
	j.tongue = tongue
	tongue.visible = false
	var lid := MeshLib.pivot(base, Vector3(0, 0.5, 0.3), "lid")
	j.lid = lid
	MeshLib.part(lid, MeshLib.box(Vector3(0.9, 0.22, 0.6)), wood, Vector3(0, 0.11, -0.3))
	MeshLib.part(lid, MeshLib.box(Vector3(0.12, 0.12, 0.05)), MeshLib.mat(Color(0.9, 0.75, 0.3), 0.8, 0.3), Vector3(0, 0.0, -0.61))
	for k in 6:
		var x := -0.36 + k * 0.144
		MeshLib.part(lid, MeshLib.prism(Vector3(0.07, 0.1, 0.04)), MeshLib.mat(Color(0.95, 0.93, 0.85)), Vector3(x, -0.04, -0.56), Vector3(180, 0, 0), Vector3.ONE, false)
		MeshLib.part(base, MeshLib.prism(Vector3(0.07, 0.1, 0.04)), MeshLib.mat(Color(0.95, 0.93, 0.85)), Vector3(x, 0.53, -0.26), Vector3.ZERO, Vector3.ONE, false)
	for k in 4:
		var leg := MeshLib.pivot(base, Vector3(-0.35 + (k % 2) * 0.7, 0.1, -0.2 + (k / 2) * 0.4), "leg%d" % k)
		j["leg%d" % k] = leg
		var lm := MeshLib.part(leg, MeshLib.cyl(0.035, 0.03, 0.4, 5), MeshLib.mat(Color(0.35, 0.2, 0.18)), Vector3(0, -0.2, 0))
		lm.visible = false
		j["legm%d" % k] = lm

func set_gear(_e: Dictionary, _fc: Color = Color(0, 0, 0, 0), _cape: bool = false) -> void:
	pass

func break_part(_p: String) -> void:
	pass

func trigger(act: String) -> void:
	action = act
	action_p = 0.0

func on_hit(_dir: Vector3 = Vector3.ZERO, _heavy: bool = false) -> void:
	hit_t = 0.25

func set_dormant(v: bool) -> void:
	dormant = v
	if kind == "mimic":
		for k in 4:
			j["legm%d" % k].visible = not v
		j.tongue.visible = not v

var _lod_acc := 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	# distant creatures animate at a lower rate (same scheme as humanoids)
	if not dead:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d2 := cam.global_position.distance_squared_to(global_position)
			if d2 > 1600.0:
				_lod_acc += delta
				if _lod_acc < (0.066 if d2 < 4900.0 else 0.15):
					return
				delta = _lod_acc
				_lod_acc = 0.0
	_t += delta
	hit_t = maxf(0.0, hit_t - delta)
	var sp := clampf(move_speed, 0.0, 2.0)
	_phase += delta * (4.0 + 6.0 * sp)
	var s := sin(_phase)
	var body: Node3D = j.body
	if dead:
		_dead_t = minf(1.0, _dead_t + delta * 2.0)
		body.rotation.z = lerpf(0.0, 1.5, _dead_t) if kind in ["wolf", "spider", "mimic", "blob"] else 0.0
		if kind == "drone":
			body.position.y = lerpf(0.0, -1.7, _dead_t)
			body.rotation.x = _dead_t * 0.8
		elif kind == "wraith":
			body.scale = Vector3.ONE * maxf(0.05, 1.0 - _dead_t)
		elif kind == "blob":
			body.scale = Vector3(1.0 + _dead_t, maxf(0.1, 1.0 - _dead_t), 1.0 + _dead_t)
		return
	var atk := 0.0
	if action != "":
		atk = sin(clampf(action_p, 0.0, 1.0) * PI)
	match kind:
		"wolf":
			for i in 4:
				var ph := s if i in [0, 3] else -s
				j["leg%d" % i].rotation.x = ph * 0.6 * minf(sp, 1.3)
			j.tail.rotation.x = 0.3 + sin(_t * 6.0) * 0.15
			j.tail.rotation.y = sin(_t * 4.0) * 0.3
			j.torso.position.y = 0.62 + absf(s) * 0.03 * sp
			j.head.rotation.x = -atk * 0.6 + hit_t
			j.torso.position.z = -atk * 0.45
		"drone":
			for i in 4:
				j["rotor%d" % i].rotation.y += delta * 40.0
			j.core.position.y = 1.9 + sin(_t * 2.5) * 0.12
			j.core.rotation.x = -0.25 * minf(sp, 1.0) + hit_t
		"spider":
			for i in 6:
				var ph2 := s if i % 2 == 0 else -s
				j["leg%d" % i].rotation.y = ph2 * 0.35 * minf(sp, 1.4)
				j["leg%d" % i].rotation.x = maxf(0.0, ph2) * 0.25 * sp
			j.torso.rotation.x = -atk * 0.4 + hit_t
		"wraith":
			j.torso.position.y = 1.2 + sin(_t * 2.0) * 0.12
			j.arm0.rotation.x = 0.3 + atk * 1.5 + sin(_t * 3.0) * 0.1
			j.arm1.rotation.x = 0.3 + atk * 1.5 + sin(_t * 3.0 + 1.0) * 0.1
			j.torso.rotation.x = 0.15 * minf(sp, 1.0)
		"blob":
			var sq := sin(_t * 6.0) * 0.08 * (0.5 + sp)
			j.torso.scale = Vector3(1.0 + sq + atk * 0.3, 1.0 - sq - atk * 0.2, 1.0 + sq + atk * 0.3)
			j.torso.position.y = 0.45 + absf(sin(_t * 6.0)) * 0.15 * sp
		"mimic":
			if dormant:
				j.lid.rotation.x = sin(_t * 1.3) * 0.015
				j.base.position.y = 0.0
			else:
				j.lid.rotation.x = -0.5 - atk * 0.7 - absf(s) * 0.2
				j.base.position.y = 0.38 + absf(s) * 0.06 * sp
				for i in 4:
					j["leg%d" % i].rotation.x = (s if i % 2 == 0 else -s) * 0.6
