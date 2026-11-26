class_name MonsterBrain
extends RefCounted
## FSM for creatures and summons: wander near home, sense enemies (LOS),
## chase/attack (melee, ranged or spells), pack alerts, leash back home,
## beasts flee at low health. Summons and companions follow their owner.

var m
var target = null
var think_t := 0.0
var wander_to := Vector3.ZERO
var wander_t := 0.0
var strafe := 1.0
var strafe_t := 0.0
var returning := false

func _init(mon) -> void:
	m = mon
	think_t = randf() * 0.4

func tick(delta: float) -> void:
	if not m.can_act():
		m.move_input = Vector3.ZERO
		return
	if m.rig and m.rig.get("dormant") == true:
		m.move_input = Vector3.ZERO
		return
	think_t -= delta
	if think_t <= 0.0:
		think_t = (1.5 if m.lod_tier >= 2 else (0.55 if m.lod_tier == 1 else 0.3)) + randf() * 0.1
		_think()
	_act(delta)

func _owner():
	if m.owner_actor != null and is_instance_valid(m.owner_actor) and not m.owner_actor.is_dead:
		return m.owner_actor
	return null

func _think() -> void:
	var own = _owner()
	var sense := 16.0 + (5.0 if Game.is_night() else 0.0)
	if own:
		sense = 14.0
	if target != null and (not is_instance_valid(target) or target.is_dead or target.global_position.distance_to(m.global_position) > sense * 2.0):
		target = null
	if own and own.is_player and own.get("companion_mode") == "hold":
		target = null
		return
	if target == null:
		var best = null
		var bd := sense
		var center: Vector3 = own.global_position if own else m.global_position
		if own and own.last_attacker and is_instance_valid(own.last_attacker) and not own.last_attacker.is_dead and own.combat_t < 4.0:
			best = own.last_attacker
		else:
			for a in Game.actors_near(center, sense):
				if a == m or a.is_dead or not Game.is_enemy(m, a):
					continue
				if a.statuses.has("stealth") and a.global_position.distance_to(m.global_position) > 3.0:
					continue
				var d: float = a.global_position.distance_to(m.global_position)
				if d < bd and Combat.line_of_sight(m.chest(), a.chest()):
					bd = d
					best = a
		if best:
			target = best
			_alert_pack(best)
	if not own and target == null and m.global_position.distance_to(m.home) > m.leash:
		returning = true
	if target and not own and m.global_position.distance_to(m.home) > m.leash * 1.5:
		target = null
		returning = true
		m.aggro.clear()

func _alert_pack(t) -> void:
	for a in Game.actors_near(m.global_position, 15.0):
		if a != m and a is Monster and a.def_id == m.def_id and not a.is_dead and a.brain and a.brain.target == null:
			a.brain.target = t

func _act(delta: float) -> void:
	var own = _owner()
	if target == null:
		if own:
			var to: Vector3 = own.global_position - m.global_position
			to.y = 0
			if to.length() > 3.5:
				m.move_input = to.normalized() * (1.0 if to.length() > 7.0 else 0.6)
			else:
				m.move_input = Vector3.ZERO
			return
		if returning:
			var th: Vector3 = m.home - m.global_position
			th.y = 0
			if th.length() < 2.0:
				returning = false
				m.hp = minf(m.max_hp, m.hp + m.max_hp * 0.3)
			m.move_input = th.normalized()
			return
		wander_t -= delta
		if wander_t <= 0.0:
			wander_t = randf_range(2.0, 6.0)
			wander_to = m.home + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		var tw: Vector3 = wander_to - m.global_position
		tw.y = 0
		m.move_input = tw.normalized() * 0.45 if tw.length() > 1.0 else Vector3.ZERO
		return
	var t = target
	var to2: Vector3 = t.global_position - m.global_position
	to2.y = 0
	var d := to2.length()
	var dir = to2.normalized() if d > 0.01 else m.facing
	m.face_dir(dir)
	# beasts flee when badly hurt
	if m.rig and m.rig.get("kind") == "wolf" and m.hp < m.max_hp * 0.2 and not own:
		m.move_input = -dir
		return
	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_t = randf_range(1.0, 2.5)
		strafe = -strafe
	if m.proj_kind != "":
		if d > 15.0:
			m.move_input = dir
		elif d < 7.0:
			m.move_input = -dir * 0.8
		else:
			m.move_input = dir.cross(Vector3.UP) * strafe * 0.6
		if d < 18.0 and Combat.line_of_sight(m.chest(), t.chest()):
			m.shoot_at(t)
		return
	if not m.spells.is_empty():
		if d > 13.0:
			m.move_input = dir
		elif d < 5.0:
			m.move_input = -dir * 0.7
		else:
			m.move_input = dir.cross(Vector3.UP) * strafe * 0.5
		if d < 15.0 and randf() < 0.08:
			var sp: String = m.spells[randi() % m.spells.size()]
			Spells.cast_free(m, sp, dir, m.base_dmg * 1.3)
		elif d < m.natural_range + 0.5:
			m.attack(dir)
		return
	if d > m.natural_range * 0.85:
		m.move_input = dir
	else:
		m.move_input = dir.cross(Vector3.UP) * strafe * 0.2
		m.attack(dir)
