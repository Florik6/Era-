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
var _hit_t := {}        # actor_id -> msec (spear guard: one blow per second per enemy)
var _trapped := {}      # actor_id -> true (time trap: each victim once)

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
		"ev_steam", "ev_smog": return Color(0.85, 0.88, 0.92)
		"ev_gas": return Color(0.55, 0.85, 0.35)
		"ev_flood": return Color(0.3, 0.5, 0.8)
		"ev_electric": return Color(0.55, 0.75, 1.0)
		"ev_nano": return Color(0.75, 0.75, 0.85)
		"ev_gravity", "ev_time": return Color(0.45, 1.0, 0.85)
		"ice_path": return Color(0.75, 0.93, 1.0)
		"mud": return Color(0.4, 0.32, 0.22)
		"dark_veil": return Color(0.22, 0.08, 0.32)
		"silence": return Color(0.45, 0.15, 0.7)
		"liturgy": return Color(0.4, 0.8, 0.5)
		"whirl", "wind_throne": return Color(0.85, 1.0, 1.0)
		"hallowed": return Color(1.0, 0.95, 0.7)
		"spear_guard": return Color(1.0, 0.9, 0.55)
	return Color(1, 1, 1)

func _build() -> void:
	var c := color()
	_vis = Node3D.new()
	add_child(_vis)
	if params.get("orb", false):
		var orb := MeshInstance3D.new()
		orb.mesh = MeshLib.sphere(0.45, 12, 8)
		orb.material_override = MagicFX.orb_mat("lightning")
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb.position.y = 1.3
		_vis.add_child(orb)
		if VFX.mgr() != null:
			VFX.mgr().attach_light(self, c, 1.5, 6.0, Vector3(0, 1.3, 0))
	var rs: String = DBAbilities.get_ab(str(params.get("ab", ""))).get("vis", {}).get("rune", "")
	if rs != "" and kind in ["mud", "silence", "liturgy", "hallowed", "spear_guard", "dark_veil", "whirl", "wind_throne", "ice_path", "timetrap", "timeslow", "heal"]:
		var rm := MagicFX.ground_rune(Vector3.ZERO, rs, c, radius, -1.0, 0.5 if kind != "whirl" else 2.5, 0.85, self)
		if rm != null:
			rm.position.y = 0.08
	if ResonanceFX.build_zone(self) or MagicFX.build_zone(self):
		return
	var disc := MeshInstance3D.new()
	disc.mesh = MeshLib.cyl(1.0, 1.0, 0.03, 24)
	disc.material_override = MeshLib.mat(Color(c.r, c.g, c.b, 0.28 if kind != "mine" else 0.5), 0.0, 1.0, 1.5, true)
	disc.scale = Vector3(radius, 1, radius)
	disc.position.y = 0.06
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vis.add_child(disc)
	if kind in ["fire", "blizzard", "electric", "rift", "dark", "whirl", "wind_throne", "liturgy", "dark_veil", "hallowed"] and Settings.profile().particles > 0.3:
		var p := CPUParticles3D.new()
		p.amount = int(clampf(radius * 10.0, 8, 40) * Settings.profile().particles)
		p.lifetime = 0.9
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = radius
		p.direction = Vector3.UP
		p.spread = 15.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 3.0
		p.gravity = Vector3(0, 1.5 if kind in ["fire", "liturgy", "hallowed"] else -2.0, 0)
		if kind in ["whirl", "wind_throne"]:
			p.tangential_accel_min = 12.0
			p.tangential_accel_max = 16.0
			p.gravity = Vector3(0, 2.5, 0)
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
		_vis.rotation.y += delta * (2.0 if kind in ["timeslow", "rift"] else (3.5 if kind in ["whirl", "wind_throne"] else 0.0))
	var fol = params.get("follow")
	if fol != null:
		if is_instance_valid(fol) and not fol.is_dead:
			global_position = fol.global_position
		else:
			queue_free()
			return
	elif params.has("vel"):
		var np: Vector3 = global_position + params.vel * delta
		global_position = MagicFX.ground_point(np)
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
				if params.has("hps_pct"):
					a.heal(a.max_hp * float(params.hps_pct) * tick)
				else:
					a.heal(params.get("hps", 8.0) * tick)
			continue
		if kind in ["liturgy", "dark_veil", "hallowed", "wind_throne", "timeslow"] and src != null and is_instance_valid(src) and AbilityExec.is_ally(src, a):
			_ally_tick(a)
			if kind != "hallowed" and kind != "wind_throne" and kind != "timeslow":
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
				a.apply_status("timeslow", 0.7, {"f": float(params.get("f", 0.35))})
		"ice_path", "mud":
			var sf: float = float(info.get("status", {}).get("slow", 0.5))
			for a in victims:
				a.apply_status("slow", 1.0, {"f": sf})
				if kind == "ice_path" and randf() < 0.12 and a.kind != "boss":
					a.apply_status("stun", 0.35)
					VFX.text(a.chest(), "Поскользнулся", Color(0.8, 0.95, 1.0), 0.8)
		"silence":
			for a in victims:
				if a.kind == "boss":
					a.apply_status("slow", 0.8, {"f": 0.7})
				else:
					a.apply_status("silenced", 0.8)
				if float(info.get("amount", 0.0)) > 0.0:
					var infs := info.duplicate()
					infs.proc = true
					Combat.deal(s, a, infs)
		"whirl":
			var pull2: float = params.get("pull", 2.5)
			for a in victims:
				var to_w: Vector3 = global_position - a.global_position
				to_w.y = 0
				if to_w.length() > 0.8 and a.kind != "boss":
					a.knockback = to_w.normalized() * pull2 + to_w.normalized().cross(Vector3.UP) * pull2 * 0.6
				var infw := info.duplicate()
				infw.proc = true
				Combat.deal(s, a, infw)
		"wind_throne":
			for a in victims:
				var away2: Vector3 = a.global_position - global_position
				away2.y = 0
				if a.kind != "boss":
					a.knockback = (away2.normalized() if away2.length() > 0.2 else Vector3(1, 0, 0)) * float(params.get("push", 4.0))
				var inft := info.duplicate()
				inft.proc = true
				Combat.deal(s, a, inft)
		"hallowed":
			for a in victims:
				if DBActors.eget(a.def_id, {}).get("skeleton", false) or a.kind == "undead" or str(a.def_id).contains("wraith") or str(a.def_id).contains("skeleton"):
					var infh := info.duplicate()
					infh.proc = true
					infh.amount = float(info.get("amount", 5.0)) * 2.0
					Combat.deal(s, a, infh)
		"spear_guard":
			var now := Time.get_ticks_msec()
			for a in victims:
				if now - int(_hit_t.get(a.actor_id, 0)) < 1000:
					continue
				_hit_t[a.actor_id] = now
				var away3: Vector3 = a.global_position - global_position
				away3.y = 0
				var infg := info.duplicate()
				infg.melee = true
				Combat.deal(s, a, infg)
				if a.kind != "boss":
					a.knockback = (away3.normalized() if away3.length() > 0.2 else Vector3(1, 0, 0)) * float(params.get("push", 6.0))
				if VFX.mgr() != null:
					VFX.slash(global_position + Vector3(0, 1.0, 0), away3.normalized(), radius, 40.0, "thrust", color())
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
		"ev_steam", "ev_gas", "ev_nano", "ev_electric":
			for a in victims:
				var infe := info.duplicate()
				infe.proc = true
				Combat.deal(null, a, infe)
				if kind == "ev_steam" or kind == "ev_gas":
					a.apply_status("slow", 1.2, {"f": 0.7})
		"ev_flood":
			for a in victims:
				a.apply_status("slow", 1.2, {"f": 0.55})
		"ev_gravity", "ev_time":
			for a in victims:
				a.apply_status("timeslow", 1.0)
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
					var uses: int = int(params.get("uses", 1))
					for v in victims:
						if _trapped.has(v.actor_id) or uses <= 0:
							continue
						_trapped[v.actor_id] = true
						uses -= 1
						v.apply_status("stasis", params.get("stasis", 4.0))
						MagicFX.time_snap(v.global_position, radius * 1.2)
						Audio.play_sfx("time_slow", global_position)
						Combat.deal(s, v, info.duplicate())
					params.uses = uses
					if uses > 0:
						return
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

## Ally effects of support zones.
func _ally_tick(a) -> void:
	match kind:
		"liturgy":
			if a.get("owner_actor") == src and a.team == "summon":
				a.apply_status("liturgy_buff", 0.8, {"mods": {"dmg_pct": 0.4}})
				a.heal(a.max_hp * 0.02)
			elif a == src:
				a.apply_status("liturgy", 0.8)
		"dark_veil":
			a.apply_status("veiled", 0.8)
		"hallowed":
			a.apply_status("hallowed", 0.8, {"mods": {"res_dark": 0.5}})
			for k in ["curse", "decay", "wither", "fear", "weakness"]:
				if a.statuses.has(k):
					a.statuses.erase(k)
		"wind_throne":
			a.apply_status("deflect", 0.8, {"weak": 400.0})
		"timeslow":
			if params.get("haste_allies", false):
				a.apply_status("haste", 0.8)
