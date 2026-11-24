class_name Spells
## All 20 spells of the five schools, plus shared magical effects used by
## items, bosses and hybrids (chain lightning, summons, micro-rifts).

static func cast(c: Actor, id: String, aim: Vector3) -> bool:
	var sp := DBSkills.spell(id)
	if sp.is_empty() or c.data == null or not c.data.knows_school(sp.school):
		return false
	if c.data.school_level(sp.school) < sp.lvl:
		return false
	var cost: float = sp.mana
	if c.data.school_level(sp.school) >= 6:
		cost *= 0.85
	if c.mana < cost:
		if c.is_player:
			Events.notify.emit("Недостаточно маны", Color(0.5, 0.6, 1.0))
			Audio.play_sfx("error")
		return false
	c.mana -= cost
	c.skill_cd[id] = sp.cd
	if aim.length() < 0.01:
		aim = c.facing
	aim.y = 0
	aim = aim.normalized()
	c.face_dir(aim)
	var power: float = sp.dmg * (1.0 + 0.12 * (c.level - 1))
	var info := {"amount": power, "dtype": DBSkills.SCHOOLS[sp.school].dtype, "school": sp.school, "melee": false, "knock": 1.0, "status": {}}
	var cb := func(): _effect(c, id, sp, aim, info)
	c.start_action("spell", 0.45, 0.55, {"anim": "cast", "cb": cb})
	c.data.add_school_xp(sp.school, 4.0)
	if c.is_player:
		var n := Profile.add_stat("spells")
		if n >= 100:
			Profile.unlock("spell_100")
	if c.data and "battlemage" in c.data.hybrids():
		c.stamina = minf(c.max_stamina, c.stamina + 4.0)
	return true

## Monster/boss casting: no mana or school requirements.
static func cast_free(c: Actor, id: String, aim: Vector3, power: float) -> bool:
	var sp := DBSkills.spell(id)
	if sp.is_empty() or c.skill_cd.has(id) or c.busy():
		return false
	c.skill_cd[id] = sp.cd * 1.6 + 0.5
	if aim.length() < 0.01:
		aim = c.facing
	aim.y = 0
	aim = aim.normalized()
	c.face_dir(aim)
	var info := {"amount": power, "dtype": DBSkills.SCHOOLS[sp.school].dtype, "school": "", "melee": false, "knock": 1.0, "status": {}}
	c.start_action("spell", 0.6, 0.6, {"anim": "cast", "cb": func(): _effect(c, id, sp, aim, info)})
	return true

static func _target(c: Actor, aim: Vector3, rng: float, cone: float = 50.0) -> Actor:
	var best: Actor = null
	var bd := INF
	for a in Game.actors_near(c.global_position, rng):
		if a == c or a.is_dead or not Game.can_damage(c, a):
			continue
		var to: Vector3 = a.global_position - c.global_position
		to.y = 0
		if to.length() > 0.5 and aim.angle_to(to.normalized()) > deg_to_rad(cone):
			continue
		var d := to.length()
		if d < bd and Combat.line_of_sight(c.chest(), a.chest()):
			bd = d
			best = a
	return best

static func _aim_point(c: Actor, aim: Vector3, rng: float) -> Vector3:
	var t := _target(c, aim, rng, 40.0)
	if t:
		return t.global_position
	return c.global_position + aim * rng * 0.6

static func _effect(c: Actor, id: String, sp: Dictionary, aim: Vector3, info: Dictionary) -> void:
	if not is_instance_valid(c) or c.is_dead:
		return
	var col := Combat.element_color(info.dtype)
	var muzzle := c.chest() + aim * 0.8
	match id:
		# ---------------- fire
		"fireball":
			info.status = {"burn": info.amount * 0.2}
			Projectile.spawn(c, muzzle, aim * 22.0, info, "fireball", {"splash": 2.8, "range": 24.0, "color": col})
			Audio.play_sfx("fire_cast", c.global_position)
		"ignite":
			var t := _target(c, aim, 16.0)
			if t:
				info.status = {"burn": info.amount * 0.8}
				Combat.deal(c, t, info)
				VFX.burst(t.chest(), col, 16, 0.4)
			else:
				var p := c.global_position + aim * 4.0
				for d in Game.grid.query(p, 4.0, "destructible"):
					if d.has_method("ignite"):
						d.ignite()
				VFX.burst(p + Vector3(0, 0.5, 0), col, 14, 0.4)
			Audio.play_sfx("fire_cast", c.global_position)
		"firewall":
			var center := c.global_position + aim * 4.0
			var side := aim.cross(Vector3.UP).normalized()
			info.status = {"burn": info.amount * 0.4}
			for i in range(-2, 3):
				Zone.create("fire", c, center + side * i * 1.6, 1.0, 6.0, info)
			Audio.play_sfx("fire_cast", center)
		"meteor":
			var p2 := _aim_point(c, aim, 18.0)
			VFX.telegraph(p2, 4.0, 1.0, col)
			info.status = {"burn": 12.0, "stun": 0.6}
			c.get_tree().create_timer(1.0, false).timeout.connect(func():
				VFX.explosion(p2, 4.5, col)
				Audio.play_sfx("explosion", p2)
				Combat.aoe(c if is_instance_valid(c) else null, p2, 4.5, info))
		# ---------------- ice
		"frostbolt":
			info.status = {"slow": 0.5}
			Projectile.spawn(c, muzzle, aim * 26.0, info, "magic", {"range": 24.0, "color": col})
			Audio.play_sfx("ice_cast", c.global_position)
		"freeze":
			info.status = {"freeze": 2.0}
			VFX.ring(c.global_position, 6.0, col, 0.4)
			VFX.burst(c.chest(), col, 24, 0.4)
			Combat.aoe(c, c.global_position, 6.0, info)
			if Game.world and Game.world.has_method("freeze_water"):
				Game.world.freeze_water(c.global_position, 7.0)
			Audio.play_sfx("ice_shatter", c.global_position)
		"icewall":
			if Game.world and Game.world.has_method("spawn_ice_wall"):
				Game.world.spawn_ice_wall(c.global_position + aim * 3.5, aim, 9.0)
			Audio.play_sfx("ice_cast", c.global_position)
		"blizzard":
			var p3 := _aim_point(c, aim, 18.0)
			info.status = {"slow": 0.3}
			Zone.create("blizzard", c, p3, 4.5, 6.0, info)
			Audio.play_sfx("ice_cast", p3)
		# ---------------- lightning
		"spark":
			var t2 := _target(c, aim, 18.0, 60.0)
			if t2:
				VFX.beam(muzzle, t2.chest(), col, 0.15, 0.07, true)
				info.status = {"stun": 0.2}
				Combat.deal(c, t2, info)
			else:
				VFX.beam(muzzle, muzzle + aim * 12.0, col, 0.12, 0.06, true)
			Audio.play_sfx("lightning", c.global_position, -2.0)
		"chain":
			var t3 := _target(c, aim, 18.0, 60.0)
			if t3:
				chain_lightning(c, t3, info.amount, 5, false, muzzle)
			Audio.play_sfx("lightning", c.global_position)
		"thunderclap":
			info.status = {"stun": 1.5}
			VFX.ring(c.global_position, 5.5, col, 0.35)
			VFX.flash(c.chest(), col, 0.15, 6.0)
			Combat.aoe(c, c.global_position, 5.5, info)
			Audio.play_sfx("thunder", c.global_position)
			VFX.shake(0.3)
		"storm":
			for i in 8:
				c.get_tree().create_timer(0.25 * i, false).timeout.connect(func():
					if not is_instance_valid(c):
						return
					var tt := _target(c, Vector3.FORWARD, 14.0, 180.0)
					var p4: Vector3 = tt.global_position if tt else c.global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
					VFX.beam(p4 + Vector3(0, 14, 0), p4, col, 0.15, 0.12, true)
					VFX.flash(p4 + Vector3(0, 2, 0), col, 0.1, 5.0)
					Combat.aoe(c, p4, 2.0, info)
					Audio.play_sfx("thunder", p4, -4.0))
		# ---------------- dark
		"curse":
			var t4 := _target(c, aim, 16.0)
			if t4:
				t4.apply_status("curse", 8.0)
				Combat.deal(c, t4, info)
				VFX.burst(t4.chest() + Vector3(0, 0.6, 0), col, 16, 0.3)
			Audio.play_sfx("dark_cast", c.global_position)
		"drain":
			var t5 := _target(c, aim, 14.0)
			if t5:
				var dealt := Combat.deal(c, t5, info)
				c.heal(dealt * 0.8)
				VFX.beam(t5.chest(), c.chest(), Color(0.85, 0.1, 0.3), 0.3, 0.1, false)
			Audio.play_sfx("dark_cast", c.global_position)
		"summon":
			summon(c, "skeleton_minion", 2, c.global_position + aim * 2.0, 25.0)
			Audio.play_sfx("dark_cast", c.global_position)
		"nova":
			info.status = {"fear": 2.0}
			VFX.ring(c.global_position, 7.0, col, 0.45)
			Combat.aoe(c, c.global_position, 7.0, info)
			Audio.play_sfx("dark_cast", c.global_position)
		# ---------------- space & time
		"blink":
			var dest := c.global_position + aim * 9.0
			dest = _safe_dest(c, dest)
			VFX.burst(c.chest(), col, 16, 0.3)
			c.global_position = dest
			if c.has_method("reset_physics_interpolation"):
				c.reset_physics_interpolation()
			VFX.burst(c.chest(), col, 16, 0.3)
			Audio.play_sfx("teleport", dest)
		"timeslow":
			var p5 := _aim_point(c, aim, 12.0)
			Zone.create("timeslow", c, p5, 5.0, 6.0, info)
			Audio.play_sfx("time_slow", p5)
		"timetrap":
			var p6 := c.global_position + aim * 4.0
			Zone.create("timetrap", c, p6, 1.6, 20.0, info, {"stasis": 4.0})
			Audio.play_sfx("time_slow", p6, -4.0)
		"riftdash":
			var start := c.global_position
			var end := _safe_dest(c, start + aim * 10.0)
			VFX.beam(start + Vector3(0, 1, 0), end + Vector3(0, 1, 0), col, 0.3, 0.25, false)
			for a in Game.actors_near((start + end) * 0.5, 7.0):
				if a == c or a.is_dead or not Game.can_damage(c, a):
					continue
				var cp := Geometry3D.get_closest_point_to_segment(a.global_position, start, end)
				if cp.distance_to(a.global_position) < 1.8:
					Combat.deal(c, a, info.duplicate())
			c.global_position = end
			if c.has_method("reset_physics_interpolation"):
				c.reset_physics_interpolation()
			Audio.play_sfx("teleport", end)

static func _safe_dest(c: Actor, dest: Vector3) -> Vector3:
	var from := c.chest()
	var to := dest + Vector3(0, 1.2, 0)
	var sp := Combat.space()
	if sp:
		var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD | Actor.LAYER_DESTRUCT))
		if not r.is_empty():
			to = r.position - (to - from).normalized() * 0.7
	var p := Vector3(to.x, c.global_position.y, to.z)
	if Game.world and Game.world.has_method("ground_height"):
		p.y = Game.world.ground_height(p) + 0.1
	return p

static func chain_lightning(c, first: Actor, dmg: float, jumps: int, proc: bool, from_pos: Vector3 = Vector3.INF) -> void:
	var hit := {}
	var cur: Actor = first
	var prev = from_pos if from_pos != Vector3.INF else (c.chest() if c and is_instance_valid(c) else first.chest())
	var col := Color(0.75, 0.8, 1.0)
	for i in jumps:
		if cur == null:
			break
		hit[cur.actor_id] = true
		VFX.beam(prev, cur.chest(), col, 0.18, 0.07, true)
		var info := {"amount": dmg * (1.0 - 0.12 * i), "dtype": "lightning", "status": {"stun": 0.15}, "proc": proc, "school": "lightning" if not proc else ""}
		Combat.deal(c if (c and is_instance_valid(c)) else null, cur, info)
		prev = cur.chest()
		var nxt: Actor = null
		var bd := 8.0
		for a in Game.actors_near(cur.global_position, 8.0):
			if a.is_dead or hit.has(a.actor_id) or a == c:
				continue
			if c and is_instance_valid(c) and not Game.can_damage(c, a):
				continue
			var d: float = a.global_position.distance_to(cur.global_position)
			if d < bd:
				bd = d
				nxt = a
		cur = nxt

static func micro_rift(c: Actor, pos: Vector3, dmg: float) -> void:
	Zone.create("rift", c, pos, 2.5, 1.8, {"amount": dmg * 0.25, "dtype": "time", "proc": true})
	Audio.play_sfx("portal_open", pos, -8.0)

## Spawn temporary allied summons for an owner.
static func summon(owner_a: Actor, enemy_id: String, count: int, pos: Vector3, life: float) -> Array:
	var out: Array = []
	if Game.world == null:
		return out
	for i in count:
		var p := pos + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		var m = Game.world.spawner.spawn_enemy(enemy_id, p, maxi(1, owner_a.level))
		if m:
			m.team = "summon"
			m.owner_actor = owner_a
			m.summon_time = life
			m.faction_id = owner_a.faction_id
			out.append(m)
			VFX.burst(p + Vector3(0, 1, 0), Color(0.6, 0.3, 0.9), 14, 0.35)
	return out

static func shadow_clone_burst(c: Actor, pos: Vector3) -> void:
	c.get_tree().create_timer(0.5, false).timeout.connect(func():
		if not is_instance_valid(c):
			return
		VFX.explosion(pos, 2.5, Color(0.5, 0.2, 0.8))
		Combat.aoe(c, pos, 2.5, {"amount": 12.0 + c.level * 3.0, "dtype": "dark", "proc": true, "status": {"slow": 0.5}}))
