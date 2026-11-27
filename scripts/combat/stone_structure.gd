class_name StoneStructure
extends StaticBody3D
## Temporary terrain raised by magic: stone and ice spikes, bastion walls,
## ice walls and quake slabs. Solid pieces block movement and projectiles
## (layer DESTRUCT, which actors and projectile rays collide with) and can be
## broken; every piece sinks back into the ground when its time is up, so the
## arena and all paths return to normal. Meshes and shapes are prepared once
## and shared (no per-cast mesh building), and the number of live pieces is
## capped (the oldest crumble first).

const MAX_LIVE := 48
static var live: Array = []
static var _mesh := {}
static var _shape := {}
static var _mats := {}
static var spawned := 0

var kind := "stone_spike"
var life := 5.0
var hp := 0.0
var max_hp := 0.0
var solid := false
var src = null
var height := 2.0
var _body: Node3D
var _box: BoxShape3D
var _sinking := false

static func spawn(k: String, pos: Vector3, dir: Vector3, opts: Dictionary = {}) -> StoneStructure:
	if Game.world == null or not is_instance_valid(Game.world):
		return null
	_prune()
	while live.size() >= MAX_LIVE:
		var old = live.pop_front()
		if is_instance_valid(old):
			old.crumble()
	var s := StoneStructure.new()
	s.kind = k
	s.life = float(opts.get("life", 5.0))
	s.solid = bool(opts.get("solid", false))
	s.src = opts.get("src")
	s.max_hp = float(opts.get("hp", 0.0))
	if s.max_hp <= 0.0:
		s.max_hp = 160.0 if k in ["stone_wall", "slab"] else (90.0 if k == "ice_wall" else 60.0)
	s.hp = s.max_hp
	s.collision_layer = Actor.LAYER_DESTRUCT if s.solid else 0
	s.collision_mask = 0
	Game.world.fx_root.add_child(s)
	s.global_position = pos
	if dir.length() > 0.01:
		var d := Vector3(dir.x, 0, dir.z).normalized()
		s.look_at(pos + d, Vector3.UP)
	s._build(float(opts.get("width", 2.6)), float(opts.get("scale", 1.0)), float(opts.get("height", 0.0)))
	live.append(s)
	spawned += 1
	return s

static func _prune() -> void:
	live = live.filter(func(x): return is_instance_valid(x) and not x._sinking)

static func count_live() -> int:
	_prune()
	return live.size()

static func _m(k: String) -> Material:
	if not _mats.has(k):
		match k:
			"stone":
				_mats[k] = MeshLib.mat(Color(0.5, 0.43, 0.35), 0.0, 0.95)
			"stone_dark":
				_mats[k] = MeshLib.mat(Color(0.36, 0.31, 0.26), 0.0, 0.95)
			"rune":
				_mats[k] = MeshLib.mat(Color(1.0, 0.75, 0.35), 0.0, 1.0, 2.2, true)
			"ice":
				_mats[k] = MagicFX.ice_mat()
	return _mats[k]

static func _shared_mesh(k: String) -> Mesh:
	if not _mesh.has(k):
		match k:
			"spike":
				_mesh[k] = MeshLib.cyl(0.0, 0.42, 2.2, 5)
			"spike_small":
				_mesh[k] = MeshLib.cyl(0.0, 0.25, 1.2, 5)
			"crystal":
				_mesh[k] = MeshLib.cyl(0.0, 0.32, 2.4, 6)
			"block":
				_mesh[k] = MeshLib.box(Vector3(1, 1, 1))
			"slab":
				_mesh[k] = MeshLib.cyl(1.25, 1.45, 1.0, 7)
	return _mesh[k]

func _build(width: float, scl: float, h_over: float) -> void:
	_body = Node3D.new()
	add_child(_body)
	var col := CollisionShape3D.new()
	match kind:
		"stone_spike", "ice_spike":
			height = 2.2 * scl
			var main := MeshLib.part(_body, _shared_mesh("spike" if kind == "stone_spike" else "crystal"), _m("stone" if kind == "stone_spike" else "ice"), Vector3(0, height * 0.5, 0), Vector3(randf_range(-8, 8), randf() * 360.0, randf_range(-8, 8)), Vector3.ONE * scl, false)
			main.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for i in 2:
				var off := Vector3(randf_range(-0.45, 0.45), 0.35, randf_range(-0.45, 0.45))
				MeshLib.part(_body, _shared_mesh("spike_small"), _m("stone_dark" if kind == "stone_spike" else "ice"), off, Vector3(randf_range(-25, 25), 0, randf_range(-25, 25)), Vector3.ONE * scl, false)
			var cs := CylinderShape3D.new()
			cs.radius = 0.34 * scl
			cs.height = height
			col.shape = cs
			col.position.y = height * 0.5
		"stone_wall", "ice_wall":
			height = 2.6 if kind == "stone_wall" else 2.3
			var thick := 0.9 if kind == "stone_wall" else 0.7
			var w := maxf(0.8, width)
			MeshLib.part(_body, _shared_mesh("block"), _m("stone" if kind == "stone_wall" else "ice"), Vector3(0, height * 0.5, 0), Vector3(0, 0, randf_range(-3, 3)), Vector3(w, height, thick), true)
			if kind == "stone_wall":
				MeshLib.part(_body, _shared_mesh("block"), _m("stone_dark"), Vector3(randf_range(-0.2, 0.2) * w, height + 0.15, 0), Vector3(0, 0, randf_range(-8, 8)), Vector3(w * 0.7, 0.35, thick * 0.85), false)
				MeshLib.part(_body, _shared_mesh("block"), _m("rune"), Vector3(0, height * 0.55, -thick * 0.51), Vector3.ZERO, Vector3(0.35, 0.35, 0.02), false)
			var bs := BoxShape3D.new()
			bs.size = Vector3(w, height, thick)
			col.shape = bs
			_box = bs
			col.position.y = height * 0.5
		"slab":
			height = h_over if h_over > 0.0 else randf_range(0.7, 1.5)
			MeshLib.part(_body, _shared_mesh("slab"), _m("stone"), Vector3(0, height * 0.5, 0), Vector3(randf_range(-6, 6), randf() * 360.0, randf_range(-6, 6)), Vector3(1.0, height, 1.0), true)
			var cs2 := CylinderShape3D.new()
			cs2.radius = 1.3
			cs2.height = height
			col.shape = cs2
			col.position.y = height * 0.5
	if solid:
		add_child(col)
		_clear_footprint()
	else:
		col.free()
	# rise from the ground
	_body.position.y = -height
	var tw := create_tween()
	tw.tween_property(_body, "position:y", 0.0, 0.16 if kind != "slab" else 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if VFX.mgr() != null and not MagicFX.lod_far(global_position):
		VFX.mgr().emit(global_position + Vector3(0, 0.2, 0), {"n": 6, "life": 0.5, "mat": "mix", "col": Color(0.55, 0.47, 0.38, 0.8) if kind != "ice_spike" and kind != "ice_wall" else Color(0.85, 0.95, 1.0, 0.8), "ramp": "smoke", "size": 0.5, "v0": 1.0, "v1": 2.5, "spread": 70.0, "dir": Vector3.UP, "grav": Vector3(0, -2, 0), "curve": "puff"})

## Actors caught inside a newly raised solid piece are pushed out of it.
func _clear_footprint() -> void:
	var half := 1.4
	for t in Game.actors_near(global_position, 3.0):
		if t.is_dead:
			continue
		var lp: Vector3 = global_transform.affine_inverse() * t.global_position
		var inside := false
		match kind:
			"stone_wall", "ice_wall":
				var bs: BoxShape3D = _box
				inside = absf(lp.x) < bs.size.x * 0.5 + 0.3 and absf(lp.z) < bs.size.z * 0.5 + t.radius()
				if inside:
					var push: float = (1.0 if lp.z >= 0.0 else -1.0) * (bs.size.z * 0.5 + t.radius() + 0.15 - absf(lp.z))
					t.global_position += global_transform.basis.z.normalized() * push
			_:
				inside = Vector2(lp.x, lp.z).length() < half
				if inside:
					var away: Vector3 = t.global_position - global_position
					away.y = 0
					if away.length() < 0.05:
						away = Vector3(1, 0, 0)
					t.global_position = global_position + away.normalized() * (half + t.radius())

func take_hit(amount: float, dtype: String = "blunt", _src = null) -> void:
	if _sinking:
		return
	var k := 1.0
	if kind in ["ice_spike", "ice_wall"] and dtype == "fire":
		k = 2.5
	if kind in ["stone_wall", "stone_spike", "slab"] and dtype in ["blunt", "earth"]:
		k = 1.5
	hp -= amount * k
	if hp <= 0.0:
		crumble()

func crumble() -> void:
	if _sinking:
		return
	_sinking = true
	collision_layer = 0
	if VFX.mgr() != null and not MagicFX.lod_far(global_position):
		var c := Color(0.5, 0.43, 0.35) if not kind.begins_with("ice") else Color(0.85, 0.95, 1.0)
		VFX.burst(global_position + Vector3(0, height * 0.5, 0), c, 10, 0.3)
	var tw := create_tween()
	tw.tween_property(_body, "position:y", -height, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _physics_process(delta: float) -> void:
	if _sinking:
		return
	life -= delta
	if life <= 0.0:
		crumble()

func _exit_tree() -> void:
	live.erase(self)
