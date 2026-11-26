class_name Zone
extends Node3D
## Persistent area effects: fire walls, blizzards, time-slow fields, time traps,
## mines, micro-rifts, electric traps, healing circles, boss hazards.

var kind := "fire"
var src = null
var radius := 3.0
var life := 5.0
var tick := 0.5
var info := {}
var params := {}
var _acc := 0.0
var _vis: Node3D

static func create(k: String, source, pos: Vector3, r: float, duration: float, inf: Dictionary = {}, prm: Dictionary = {}) -> Zone:
	if Game.world == null:
		return null
	var z := Zone.new()
	z.kind = k
	z.src = source
	z.radius = r
	z.life = duration
	z.info = inf
	z.params = prm
	Game.world.fx_root.add_child(z)
	z.global_position = pos
	z._build()
	Game.world.zones.append(z)
	Resonance.zone_created(z)
	return z

func _exit_tree() -> void:
	if Game.world:
		Game.world.zones.erase(self)

func color() -> Color:
	match kind:
		"fire": return Color(1.0, 0.45, 0.1)
		"blizzard": return Color(0.6, 0.9, 1.0)
		"timeslow", "timetrap", "rift": return Color(0.4, 1.0, 0.85)
		"mine": return Color(1.0, 0.2, 0.1)
		"electric": return Color(0.6, 0.75, 1.0)
		"heal": return Color(0.4, 1.0, 0.5)
		"dark": return Color(0.6, 0.2, 0.85)
		"steam", "node", "vortex", "instability", "anomaly": return ResonanceFX.color(kind)
	return Color(1, 1, 1)

func _build() -> void:
	var c := color()
	_vis = Node3D.new()
	add_child(_vis)
	if ResonanceFX.build_zone(self) or MagicFX.build_zone(self):
		return
	var disc := MeshInstance3D.new()
	disc.mesh = MeshLib.cyl(1.0, 1.0, 0.03, 24)
	disc.material_override = MeshLib.mat(Color(c.r, c.g, c.b, 0.28 if kind != "mine" else 0.5), 0.0, 1.0, 1.5, true)
	disc.scale = Vector3(radius, 1, radius)
	disc.position.y = 0.06
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(disc)
	if kind in ["fire", "blizzard", "electric", "rift", "dark"] and Settings.profile().particles > 0.3:
		var p := CPUParticles3D.new()
		p.amount = int(clampf(radius * 10.0, 8, 40) * Settings.profile().particles)
		p.lifetime = 0.9
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = radius
		p.direction = Vector3.UP
		p.spread = 15.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 3.0
		p.gravity = Vector3(0, 1.5 if kind == "fire" else -2.0, 0)
		p.mesh = MeshLib.box(Vector3(0.12, 0.12, 0.12))
		p.material_override = MeshLib.mat(c, 0.0, 1.0, 3.0, true)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position.y = 0.5
		_vis.add_child(p)
	if kind in ["timeslow", "rift"]:
		var ring := MeshInstance3D.new()
		ring.mesh = MeshLib.torus(0.95, 1.0)
		ring.material_override = MeshLib.mat(c, 0.0, 1.0, 2.5, true)
		ring.scale = Vector3(radius, 1.0, radius)
		ring.position.y = 0.3
		_vis.add_child(ring)
	if kind == "fire":
		var l := OmniLight3D.new()
		l.light_color = c
		l.light_energy = 1.0
		l.omni_range = radius + 3.0
		l.position.y = 1.0
		l.shadow_enabled = false
		_vis.add_child(l)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if life < 0.5:
		MagicFX.zone_fade(self)
	if not _vis.has_meta("fx"):
		_vis.rotation.y += delta * (2.0 if kind in ["timeslow", "rift"] else 0.0)
	_acc += delta
	if _acc < tick:
		return
	_acc = 0.0
	var victims: Array = []
	for a in Game.actors_near(global_position, radius + 0.5):
		if a.is_dead or absf(a.global_position.y - global_position.y) > 3.0:
			continue
		if (a.global_position - global_position).length() > radius + a.radius():
			continue
		if kind == "heal":
			if src == null or not Game.is_enemy(src, a):
				a.heal(params.get("hps", 8.0) * tick)
			continue
		if params.get("everyone", false):
			pass
		elif params.get("hostile_all", false):
			if a.team in ["monster", "boss"]:
				continue
		elif src != null and is_instance_valid(src):
			if not Game.can_damage(src, a):
				continue
		elif a.team in ["monster", "boss"]:
			continue
		victims.append(a)
	var s = src if (src != null and is_instance_valid(src)) else null
	match kind:
		"fire", "blizzard", "dark", "electric":
			if kind == "electric" and VFX.mgr() != null:
				var an := randf() * TAU
				VFX.lightning(global_position + Vector3(0, 0.2, 0), global_position + Vector3(cos(an) * radius, 0.15, sin(an) * radius), color(), 0.12, 0.04, 1)
			for a in victims:
				var inf := info.duplicate()
				inf.proc = true
				Combat.deal(s, a, inf)
			if kind == "fire":
				for d in Game.grid.query(global_position, radius, "destructible"):
					if is_instance_valid(d) and d.has_method("ignite"):
						d.ignite()
		"timeslow":
			for a in victims:
				a.apply_status("timeslow", 0.7)
		"steam":
			for a in victims:
				a.apply_status("slow", 0.8, {"f": 0.65})
				a.statuses.erase("burn")
		"node":
			# the node arcs to the nearest foes in reach
			var reach: float = params.get("reach", 7.0)
			var arcs: int = params.get("arcs", 2)
			var top := global_position + Vector3(0, 1.7, 0)
			var cands: Array = []
			for a in Game.actors_near(global_position, reach):
				if a.is_dead or (s != null and not Game.can_damage(s, a)) or (s == null and a.team in ["monster", "boss"]):
					continue
				cands.append([a.global_position.distance_squared_to(global_position), a])
			cands.sort_custom(func(x, y): return x[0] < y[0])
			for i in mini(arcs, cands.size()):
				var t = cands[i][1]
				VFX.lightning(top, t.chest(), color(), 0.16, 0.06, 1)
				var inf3 := info.duplicate()
				inf3.proc = true
				Combat.deal(s, t, inf3)
			if cands.is_empty() and VFX.mgr() != null:
				var an2 := randf() * TAU
				VFX.lightning(top, global_position + Vector3(cos(an2) * radius, 0.1, sin(an2) * radius), color(), 0.12, 0.05, 1)
		"vortex":
			var pull: float = params.get("pull", 3.5)
			for a in victims:
				var to_c: Vector3 = global_position - a.global_position
				to_c.y = 0
				if to_c.length() > 0.6:
					a.knockback = to_c.normalized() * pull
				var inf4 := info.duplicate()
				inf4.proc = true
				Combat.deal(s, a, inf4)
		"instability":
			# time flickers: some are slowed, some hurried, everyone is shaken
			for a in victims:
				if randf() < 0.5:
					a.apply_status("timeslow", 0.6)
				else:
					a.apply_status("haste", 0.6)
				var inf5 := info.duplicate()
				inf5.proc = true
				Combat.deal(s, a, inf5)
			if randf() < 0.35:
				MagicFX.time_snap(global_position, radius * 0.8)
		"anomaly":
			for a in victims:
				if randf() < 0.4:
					a.apply_status("timeslow", 1.0)
				var inf6 := info.duplicate()
				inf6.proc = true
				Combat.deal(null, a, inf6)
			if randf() < 0.3 and VFX.mgr() != null:
				var an3 := randf() * TAU
				var p3 := global_position + Vector3(cos(an3), 0, sin(an3)) * randf() * radius
				VFX.lightning(p3 + Vector3(0, 4.0, 0), p3, color(), 0.15, 0.05, 1)
		"timetrap", "mine":
			if victims.size() > 0:
				if kind == "timetrap":
					victims[0].apply_status("stasis", params.get("stasis", 4.0))
					MagicFX.time_snap(global_position, radius * 1.5)
					Audio.play_sfx("time_slow", global_position)
					Combat.deal(s, victims[0], info.duplicate())
				else:
					VFX.explosion(global_position, radius + 1.0, color())
					Audio.play_sfx("explosion", global_position)
					Combat.aoe(s, global_position, radius + 1.0, info.duplicate())
				queue_free()
		"rift":
			for a in victims:
				a.knockback = (global_position - a.global_position).normalized() * 4.0
				var inf2 := info.duplicate()
				inf2.proc = true
				Combat.deal(s, a, inf2)
