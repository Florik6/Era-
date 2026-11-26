class_name Projectile
extends Node3D
## Swept projectile: ray-tests world geometry each step (stops at walls and
## damages destructibles), sphere-tests actors along the segment, supports
## piercing, splash, homing, gravity and time-slow zones.

static var _meshes := {}

var src = null
var vel := Vector3.ZERO
var info := {}
var kind := "arrow"
var pierce := 0
var splash := 0.0
var homing := 0.0
var grav := 0.0
var max_dist := 30.0
var traveled := 0.0
var hit_ids := {}
var radius := 0.3
var color := Color.WHITE
var on_end: Callable = Callable()
var dead := false

static func spawn(source, pos: Vector3, velocity: Vector3, inf: Dictionary, k: String, opts: Dictionary = {}) -> Projectile:
	if Game.world == null:
		return null
	var p := Projectile.new()
	p.src = source
	p.vel = velocity
	p.info = inf
	p.kind = k
	p.pierce = opts.get("pierce", 0)
	p.splash = opts.get("splash", 0.0)
	p.homing = opts.get("homing", 0.0)
	p.max_dist = opts.get("range", 30.0)
	p.color = opts.get("color", Combat.element_color(inf.get("dtype", "pierce")))
	p.on_end = opts.get("on_end", Callable())
	p.radius = opts.get("radius", 0.35 if k in ["magic", "plasma", "fireball"] else 0.25)
	if k == "arrow":
		p.grav = 3.0
	Game.world.fx_root.add_child(p)
	p.global_position = pos
	p._build()
	return p

func _build() -> void:
	var sch := MagicFX.proj_school(kind, info)
	if sch != "" and MagicFX.dress_projectile(self, sch, kind, color):
		set_meta("school", sch)
		if vel.length() > 0.01:
			look_at(global_position + vel, Vector3.UP)
		return
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		"arrow", "bolt":
			mi.mesh = MeshLib.box(Vector3(0.03, 0.03, 0.7 if kind == "arrow" else 0.45))
			mi.material_override = MeshLib.mat(Color(0.55, 0.4, 0.25)) if info.get("status", {}).is_empty() else MeshLib.glow(color, 2.0)
		"bullet", "pellet":
			mi.mesh = MeshLib.box(Vector3(0.05, 0.05, 0.6))
			mi.material_override = MeshLib.mat(Color(1.0, 0.85, 0.5), 0.0, 1.0, 3.0, true)
		"pulse", "spark":
			mi.mesh = MeshLib.box(Vector3(0.08, 0.08, 0.9))
			mi.material_override = MeshLib.mat(color, 0.0, 1.0, 4.0, true)
		"plasma":
			mi.mesh = MeshLib.sphere(0.32, 8, 6)
			mi.material_override = MeshLib.mat(Color(1.0, 0.5, 0.2), 0.0, 1.0, 4.0, true)
		_:
			mi.mesh = MeshLib.sphere(0.22 if kind != "fireball" else 0.35, 8, 6)
			mi.material_override = MeshLib.mat(color, 0.0, 1.0, 3.5, true)
	add_child(mi)
	if kind == "plasma" and VFX.mgr() != null:
		VFX.mgr().attach_light(self, color, 1.2, 4.0, Vector3.ZERO)
	MagicFX.dress_basic(self, kind, color, info)
	if vel.length() > 0.01:
		look_at(global_position + vel, Vector3.UP)

func _physics_process(delta: float) -> void:
	if dead:
		return
	var dt := delta
	if Game.world and Game.world.has_method("timeslow_at") and Game.world.timeslow_at(global_position, src):
		dt *= 0.25
	if homing > 0.0 and src and is_instance_valid(src):
		var best = null
		var bd := 14.0
		for a in Game.actors_near(global_position, 14.0):
			if a == src or a.is_dead or not Game.can_damage(src, a):
				continue
			var d = a.global_position.distance_to(global_position)
			if d < bd:
				bd = d
				best = a
		if best:
			var want: Vector3 = (best.chest() - global_position).normalized() * vel.length()
			vel = vel.lerp(want, minf(1.0, dt * 4.0 * homing))
	vel.y -= grav * dt
	var from := global_position
	var to := from + vel * dt
	var seg := to - from
	var seg_len := seg.length()
	var hit_world := false
	var hit_collider: Object = null
	var sp := Combat.space()
	if sp:
		var q := PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD | Actor.LAYER_DESTRUCT)
		var r := sp.intersect_ray(q)
		if not r.is_empty():
			to = r.position
			hit_world = true
			hit_collider = r.collider
			seg = to - from
			seg_len = seg.length()
	# actor sweep
	var mid := from + seg * 0.5
	for a in Game.actors_near(mid, seg_len * 0.5 + 2.5):
		if a.is_dead or hit_ids.has(a.actor_id) or a == src:
			continue
		if src != null and is_instance_valid(src) and not Game.can_damage(src, a):
			continue
		var c: Vector3 = a.global_position + Vector3(0, 0.9 * a._scale(), 0)
		var closest := Geometry3D.get_closest_point_to_segment(c, from, to)
		var dv := c - closest
		if absf(dv.y) < 1.0 * a._scale() and Vector2(dv.x, dv.z).length() < a.radius() + radius:
			hit_ids[a.actor_id] = true
			var inf := info.duplicate()
			Combat.deal(src if (src != null and is_instance_valid(src)) else null, a, inf)
			if kind in ["arrow", "bolt"] and VFX.mgr() != null and randf() < 0.6:
				VFX.mgr().stuck_arrow(closest, vel, 0.7 if kind == "arrow" else 0.45, a)
			if pierce <= 0:
				_end(closest)
				return
			pierce -= 1
	if hit_world:
		if VFX.mgr() != null and not has_meta("school") and splash <= 0.0:
			VFX.mgr().world_impact(to, -vel.normalized(), kind, vel)
		if hit_collider and hit_collider.has_method("take_hit"):
			hit_collider.take_hit(info.get("amount", 5.0), info.get("dtype", "pierce"), src)
		elif hit_collider and hit_collider.get_parent() and hit_collider.get_parent().has_method("take_hit"):
			hit_collider.get_parent().take_hit(info.get("amount", 5.0), info.get("dtype", "pierce"), src)
		_end(to)
		return
	global_position = to
	traveled += seg_len
	if vel.length() > 0.01:
		look_at(global_position + vel, Vector3.UP)
	if traveled >= max_dist or global_position.y < -50.0:
		_end(global_position, kind in ["fireball", "plasma"])

func _end(pos: Vector3, explode: bool = true) -> void:
	if dead:
		return
	dead = true
	var sch: String = get_meta("school", "")
	MagicFX.detach_trails(self)
	if splash > 0.0 and explode:
		var inf := info.duplicate()
		inf.amount *= 0.75
		inf.proc = true
		if sch != "":
			MagicFX.impact(pos, sch, splash)
			if splash >= 3.0:
				VFX.shake(minf(0.5, splash * 0.08))
		else:
			VFX.explosion(pos, splash, color)
		Combat.aoe(src if (src != null and is_instance_valid(src)) else null, pos, splash, inf)
		Audio.play_sfx("explosion", pos, -2.0)
	elif sch != "":
		MagicFX.impact(pos, sch, 0.7, false)
	elif kind in ["magic", "spark", "pulse"]:
		VFX.burst(pos, color, 8, 0.3)
	if on_end.is_valid():
		on_end.call(pos)
	queue_free()
