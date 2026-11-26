class_name Destructible
extends StaticBody3D
## Breakable world objects with a cheap state machine (intact -> burning ->
## destroyed). Doors swing open for nearby actors; destroyed objects stop
## blocking movement and line of sight. State persists per chunk.

signal destroyed(d)

const HP := {"door": 60.0, "crate": 20.0, "barrel": 25.0, "fence": 30.0, "table": 25.0, "shelf": 30.0,
	"cracked_wall": 70.0, "palisade": 110.0, "pillar": 220.0}

var kind := "crate"
var uid := ""
var hp := 20.0
var max_hp := 20.0
var hit_radius := 0.6
var flammable := true
var explosive := false
var is_destroyed := false
var burning := false
var burn_t := 0.0
var era := 0
var state: Dictionary = {}       # chunk state dict {destroyed:[], opened:[]}
var size := Vector3.ONE
var _visual: Node3D
var _door_pivot: Node3D
var _door_open := 0.0
var _check_t := 0.0
var _burn_acc := 0.0
var _fx: Node3D
var _col: CollisionShape3D
var _registered := false

## Configure before adding to the tree. `sz` overrides the default size.
func configure(k: String, id: String, st: Dictionary, era_i: int = 0, sz: Vector3 = Vector3.ZERO, rot_y: float = 0.0) -> void:
	kind = k
	uid = id
	state = st
	era = era_i
	max_hp = HP.get(k, 30.0)
	hp = max_hp
	flammable = k in ["door", "crate", "barrel", "fence", "table", "shelf", "palisade"] and era_i <= 2
	if k in ["door", "crate", "table", "shelf"] and era_i >= 3:
		flammable = k in ["crate", "table", "shelf"]
	match k:
		"door": size = Vector3(1.6, 2.4, 0.15)
		"crate": size = Vector3(0.9, 0.9, 0.9)
		"barrel": size = Vector3(0.8, 1.0, 0.8)
		"fence": size = Vector3(2.4, 1.0, 0.12)
		"table": size = Vector3(1.6, 0.8, 0.9)
		"shelf": size = Vector3(1.4, 1.8, 0.45)
		"cracked_wall": size = Vector3(1.8, 3.0, 0.32)
		"palisade": size = Vector3(2.6, 2.4, 0.4)
		"pillar": size = Vector3(1.2, 4.5, 1.2)
	if sz != Vector3.ZERO:
		size = sz
	hit_radius = maxf(size.x, size.z) * 0.5 + 0.2
	rotation.y = rot_y

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group("destructibles")
	if uid != "" and state.has("destroyed") and uid in state.destroyed:
		is_destroyed = true
	_build()
	if is_destroyed:
		_apply_destroyed(false)
	else:
		Game.grid.insert_deferred(self, "destructible")
		_registered = true
	set_process(kind == "door" and not is_destroyed)
	set_physics_process(false)

func _exit_tree() -> void:
	if _registered:
		Game.grid.remove(self, "destructible")
		_registered = false

func _mat_wood() -> Material:
	return MeshLib.mat(Color(0.5, 0.34, 0.19))

func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	_col = CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	_col.shape = sh
	_col.position.y = size.y * 0.5
	add_child(_col)
	var wood := _mat_wood()
	var iron := MeshLib.mat(Color(0.32, 0.32, 0.34), 0.7, 0.4)
	match kind:
		"door":
			_door_pivot = MeshLib.pivot(_visual, Vector3(-size.x * 0.5, 0, 0))
			var dc := Color(0.42, 0.27, 0.15) if era <= 1 else (Color(0.3, 0.22, 0.18) if era == 2 else (Color(0.55, 0.57, 0.6) if era == 3 else Color(0.2, 0.22, 0.28)))
			MeshLib.part(_door_pivot, MeshLib.box(Vector3(size.x - 0.05, size.y - 0.05, size.z)), MeshLib.mat(dc, 0.5 if era >= 3 else 0.0, 0.6), Vector3(size.x * 0.5, size.y * 0.5, 0))
			MeshLib.part(_door_pivot, MeshLib.box(Vector3(0.08, 0.08, 0.2)), iron, Vector3(size.x - 0.25, size.y * 0.48, 0))
			if era == 4:
				MeshLib.part(_door_pivot, MeshLib.box(Vector3(0.06, size.y - 0.3, size.z + 0.02)), MeshLib.mat(Color(0.3, 0.9, 1.0), 0.0, 0.4, 2.0), Vector3(size.x * 0.5, size.y * 0.5, 0))
		"crate":
			MeshLib.part(_visual, MeshLib.box(size), MeshLib.mat(Color(0.56, 0.4, 0.22)), Vector3(0, size.y * 0.5, 0))
			MeshLib.part(_visual, MeshLib.box(Vector3(size.x + 0.04, 0.08, size.z + 0.04)), MeshLib.mat(Color(0.4, 0.27, 0.14)), Vector3(0, size.y * 0.85, 0))
			MeshLib.part(_visual, MeshLib.box(Vector3(size.x + 0.04, 0.08, size.z + 0.04)), MeshLib.mat(Color(0.4, 0.27, 0.14)), Vector3(0, size.y * 0.15, 0))
		"barrel":
			var bc := Color(0.75, 0.15, 0.12) if explosive else Color(0.5, 0.33, 0.18)
			MeshLib.part(_visual, MeshLib.cyl(0.37, 0.4, size.y, 9), MeshLib.mat(bc), Vector3(0, size.y * 0.5, 0))
			MeshLib.part(_visual, MeshLib.torus(0.37, 0.43), iron, Vector3(0, size.y * 0.22, 0))
			MeshLib.part(_visual, MeshLib.torus(0.37, 0.43), iron, Vector3(0, size.y * 0.78, 0))
			if explosive:
				MeshLib.part(_visual, MeshLib.box(Vector3(0.3, 0.3, 0.02)), MeshLib.mat(Color(1.0, 0.85, 0.2), 0.0, 0.5, 1.0), Vector3(0, size.y * 0.5, 0.41))
		"fence":
			var fm: Material = wood if era <= 2 else MeshLib.mat(Color(0.5, 0.52, 0.55), 0.7, 0.4)
			for sx in [-size.x * 0.45, size.x * 0.45]:
				MeshLib.part(_visual, MeshLib.box(Vector3(0.12, size.y, 0.12)), fm, Vector3(sx, size.y * 0.5, 0))
			MeshLib.part(_visual, MeshLib.box(Vector3(size.x, 0.1, 0.06)), fm, Vector3(0, size.y * 0.75, 0))
			MeshLib.part(_visual, MeshLib.box(Vector3(size.x, 0.1, 0.06)), fm, Vector3(0, size.y * 0.35, 0))
		"table":
			MeshLib.part(_visual, MeshLib.box(Vector3(size.x, 0.08, size.z)), wood, Vector3(0, size.y, 0))
			for p in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
				MeshLib.part(_visual, MeshLib.box(Vector3(0.08, size.y, 0.08)), wood, Vector3(p.x * (size.x * 0.45), size.y * 0.5, p.z * (size.z * 0.4)))
		"shelf":
			MeshLib.part(_visual, MeshLib.box(size), MeshLib.mat(Color(0.42, 0.28, 0.16)), Vector3(0, size.y * 0.5, 0))
			var bookc := [Color(0.6, 0.15, 0.15), Color(0.15, 0.3, 0.55), Color(0.2, 0.45, 0.2), Color(0.7, 0.6, 0.3)]
			for i in 3:
				MeshLib.part(_visual, MeshLib.box(Vector3(size.x - 0.15, 0.32, 0.1)), MeshLib.mat(bookc[i % 4]), Vector3(0, 0.35 + i * 0.5, size.z * 0.5 + 0.01))
		"cracked_wall":
			var wc := _wall_color()
			MeshLib.part(_visual, MeshLib.box(size), MeshLib.mat(wc), Vector3(0, size.y * 0.5, 0))
			for i in 4:
				MeshLib.part(_visual, MeshLib.box(Vector3(0.05, 0.6, size.z + 0.02)), MeshLib.mat(wc.darkened(0.5)), Vector3(-0.4 + i * 0.27, 0.8 + (i % 2) * 0.7, 0), Vector3(0, 0, 25 - i * 15))
		"palisade":
			for i in 5:
				var x := -size.x * 0.5 + 0.26 + i * (size.x - 0.5) / 4.0
				MeshLib.part(_visual, MeshLib.cyl(0.15, 0.17, size.y, 6), wood, Vector3(x, size.y * 0.5, 0))
				MeshLib.part(_visual, MeshLib.cyl(0.0, 0.15, 0.4, 6), wood, Vector3(x, size.y + 0.2, 0))
		"pillar":
			MeshLib.part(_visual, MeshLib.cyl(0.5, 0.6, size.y, 10), MeshLib.mat(Color(0.5, 0.48, 0.46)), Vector3(0, size.y * 0.5, 0))
			MeshLib.part(_visual, MeshLib.box(Vector3(1.4, 0.35, 1.4)), MeshLib.mat(Color(0.45, 0.43, 0.42)), Vector3(0, size.y, 0))

func _wall_color() -> Color:
	return [Color(0.82, 0.76, 0.62), Color(0.9, 0.78, 0.6), Color(0.58, 0.3, 0.22), Color(0.72, 0.72, 0.72), Color(0.3, 0.32, 0.38)][clampi(era, 0, 4)]

func _process(delta: float) -> void:
	if kind != "door" or is_destroyed:
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.2
		var near := false
		for a in Game.actors_near(global_position, 2.2):
			if not a.is_dead and a.global_position.distance_to(global_position) < 1.9:
				near = true
				break
		var want := 1.0 if near else 0.0
		if want != _door_open:
			_door_open = want
			_col.disabled = want > 0.5
	if _door_pivot:
		var target := -1.75 * _door_open
		_door_pivot.rotation.y = lerpf(_door_pivot.rotation.y, target, minf(1.0, delta * 8.0))

## Damage from weapons, projectiles, spells and explosions.
func take_hit(amount: float, dtype: String = "blunt", src = null) -> void:
	if is_destroyed:
		return
	if flammable and dtype == "fire":
		ignite()
	var mult := 1.0
	if kind in ["cracked_wall", "pillar"] and dtype in ["slash", "pierce"]:
		mult = 0.5
	if dtype in ["blunt", "fire"] and kind != "pillar":
		mult *= 1.3
	hp -= amount * mult
	if _visual:
		var tw := _visual.create_tween()
		_visual.scale = Vector3(1.06, 0.94, 1.06)
		tw.tween_property(_visual, "scale", Vector3.ONE, 0.12)
	if hp <= 0.0:
		destroy(src)

func ignite() -> void:
	if not flammable or is_destroyed or burning:
		return
	burning = true
	var raining := false
	if Game.world and Game.world.get("weather") and Game.world.weather and Game.world.weather.has_method("is_raining"):
		raining = Game.world.weather.is_raining()
	burn_t = 4.0 if raining else 8.0
	_fx = Node3D.new()
	add_child(_fx)
	var p := CPUParticles3D.new()
	p.amount = int(14 * Settings.profile().particles) + 4
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = size * 0.4
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = MeshLib.box(Vector3(0.18, 0.18, 0.18))
	p.material_override = MeshLib.mat(Color(1.0, 0.5, 0.12), 0.0, 1.0, 3.0, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position.y = size.y * 0.6
	_fx.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 1.3
	l.omni_range = 5.0
	l.position.y = size.y + 0.3
	l.shadow_enabled = false
	_fx.add_child(l)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not burning or is_destroyed:
		return
	burn_t -= delta
	_burn_acc += delta
	if _burn_acc >= 0.5:
		_burn_acc = 0.0
		hp -= max_hp * 0.09
		for d in Game.grid.query(global_position, 3.0, "destructible"):
			if d != self and is_instance_valid(d) and d.flammable and not d.burning and randf() < 0.25:
				d.ignite()
		for a in Game.actors_near(global_position, hit_radius + 1.5):
			if not a.is_dead and a.global_position.distance_to(global_position) < hit_radius + 1.2:
				Combat.deal(null, a, {"amount": 4.0, "dtype": "fire", "proc": true})
		if hp <= 0.0:
			destroy(null)
			return
	if burn_t <= 0.0:
		burning = false
		if _fx:
			_fx.queue_free()
			_fx = null

func destroy(src = null) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	burning = false
	if uid != "" and state.has("destroyed") and not uid in state.destroyed:
		state.destroyed.append(uid)
	var snd := "door_break" if kind == "door" else "wood_break"
	if kind in ["cracked_wall", "pillar"]:
		snd = "explosion"
	Audio.play_sfx(snd, global_position, -2.0)
	VFX.burst(global_position + Vector3(0, size.y * 0.5, 0), Color(0.55, 0.42, 0.28) if flammable else Color(0.6, 0.6, 0.6), 14, 0.35)
	if explosive:
		VFX.explosion(global_position + Vector3(0, 0.5, 0), 3.5, Color(1.0, 0.5, 0.15))
		Audio.play_sfx("explosion", global_position)
		var att = src if (src != null and is_instance_valid(src)) else null
		Combat.aoe(att, global_position, 3.5, {"amount": 35.0 + era * 25.0, "dtype": "fire", "status": {"burn": 6.0}, "proc": true})
	if Game.world and Game.world.get("loot") and Game.world.loot and Game.world.loot.has_method("drop_from_container") and kind in ["crate", "barrel", "shelf", "table"]:
		if randf() < 0.35:
			Game.world.loot.drop_from_container(global_position + Vector3(0, 0.4, 0), kind)
	_apply_destroyed(true)
	destroyed.emit(self)

func _apply_destroyed(animate: bool) -> void:
	if _registered:
		Game.grid.remove(self, "destructible")
		_registered = false
	collision_layer = 0
	if _col:
		_col.disabled = true
	set_process(false)
	if _fx:
		_fx.queue_free()
		_fx = null
	if _visual:
		_visual.queue_free()
		_visual = null
	if kind == "door":
		return
	# debris
	var deb := Node3D.new()
	add_child(deb)
	var m: Material = _mat_wood() if flammable else MeshLib.mat(Color(0.5, 0.48, 0.46))
	var n := 4 if kind in ["crate", "barrel", "table", "fence"] else 6
	for i in n:
		var a := i * 2.1
		var r := 0.2 + float((i * 37) % 10) / 15.0
		var piece := MeshLib.part(deb, MeshLib.box(Vector3(0.5, 0.08, 0.16) * (1.6 if kind in ["pillar", "cracked_wall", "palisade"] else 1.0)), m,
			Vector3(cos(a) * r, 0.05, sin(a) * r), Vector3(0, a * 40.0, (i % 3) * 8.0))
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if animate:
		deb.scale = Vector3(1.0, 0.1, 1.0)
		var tw := deb.create_tween()
		tw.tween_property(deb, "scale", Vector3.ONE, 0.2)
