class_name BotBrain
extends RefCounted
## Utility AI for humanoid NPCs. Perception (sight, night, stealth, LOS),
## scored options (fight, flee, heal, orbs, loot, chests, explore, events,
## faction duty, schedules, patrol, assist, hunt, yield), personality weights
## and memory of other actors (fear, grudge, gratitude, respect, defeats by
## weapon type) that change tactics over time.

var n                      # NPC
var p: Dictionary          # personality weights
var think_t := 0.0
var goal := "idle"
var target = null
var obj = null             # chest / drop target
var dest := Vector3.ZERO
var path: Array = []
var threat = null
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var side_t := 0.0
var side_dir := Vector3.ZERO
var strafe := 1.0
var strafe_t := 0.0
var block_t := 0.0
var cover_pos = null
var cover_t := 0.0
var swap_cd := 0.0
var idle_t := 0.0
var rel := {}              # actor_id -> {fear, grudge, gratitude, respect, lost_vs:{cat:n}, wins:int}
var lost_to_ranged := 0
var _orb_cache := Vector3.INF

func _init(npc) -> void:
	n = npc
	p = DBActors.ARCHETYPES.get(npc.archetype, DBActors.ARCHETYPES.explorer)
	think_t = randf() * 0.4
	Events.actor_damaged.connect(_on_damaged)
	Events.actor_killed.connect(_on_killed)

func shutdown() -> void:
	if Events.actor_damaged.is_connected(_on_damaged):
		Events.actor_damaged.disconnect(_on_damaged)
	if Events.actor_killed.is_connected(_on_killed):
		Events.actor_killed.disconnect(_on_killed)

func r_of(id: String) -> Dictionary:
	if not rel.has(id):
		rel[id] = {"fear": 0.0, "grudge": 0.0, "gratitude": 0.0, "respect": 0.0, "lost_vs": {}, "wins": 0}
	return rel[id]

# ---------------------------------------------------------------- memory hooks
func _on_damaged(t, amount: float, src, _dtype: String) -> void:
	if not is_instance_valid(n) or src == null or not is_instance_valid(src):
		return
	if t == n:
		var r := r_of(src.actor_id)
		r.fear += amount / maxf(1.0, n.max_hp) * 0.5
		r.grudge += amount / maxf(1.0, n.max_hp) * 0.4
		if goal != "fight" and goal != "flee" and not n.yielding:
			think_t = 0.0
	elif src == n and t is Actor and t.is_player == false and n.role in ["guard", "soldier"]:
		pass

func _on_killed(victim, killer) -> void:
	if not is_instance_valid(n) or n.is_dead:
		return
	if victim == null or not is_instance_valid(victim):
		return
	if killer != null and not is_instance_valid(killer):
		killer = null
	if killer == n and victim is Actor:
		r_of(victim.actor_id).wins += 1
	# someone helped us by killing our attacker
	if killer != null and victim is Actor and killer is Actor and killer != n:
		if n.last_attacker == victim and n.global_position.distance_to(victim.global_position) < 25.0:
			var r := r_of(killer.actor_id)
			r.gratitude += 0.6
			if killer.is_player and n.record.size() > 0 and Game.world and Game.world.get("legends"):
				Game.world.legends.on_helped(n, killer)

func on_spared(by) -> void:
	var r := r_of(by.actor_id)
	r.gratitude += 1.0
	r.respect += 0.8
	r.fear += 0.5
	goal = "flee"
	threat = by
	think_t = 4.0

func on_lost_to(winner) -> void:
	if winner == null or not is_instance_valid(winner):
		return
	var r := r_of(winner.actor_id)
	var cat: String = winner.weapon_cat() if winner.data else "unarmed"
	r.lost_vs[cat] = r.lost_vs.get(cat, 0) + 1
	r.respect += 0.3
	if cat in ["bow", "firearm", "staff"]:
		lost_to_ranged += 1

# ---------------------------------------------------------------- main loop
func tick(delta: float) -> void:
	if n.yielding:
		n.move_input = Vector3.ZERO
		n.yield_t -= delta
		if n.yield_t <= 0.0:
			n.end_yield()
			goal = "flee"
			think_t = 3.0
		return
	swap_cd = maxf(0.0, swap_cd - delta)
	think_t -= delta
	if think_t <= 0.0:
		var far = Game.player != null and is_instance_valid(Game.player) and n.global_position.distance_squared_to(Game.player.global_position) > 3600.0
		think_t = (0.9 if far else 0.32) + randf() * 0.12
		_think()
	_act(delta)

func power_of(a) -> float:
	if a == null or not is_instance_valid(a):
		return 1.0
	var dps := 10.0
	if a.data:
		var w: Dictionary = a.weapon()
		dps = (ItemDB.stat(w, "dmg") if not w.is_empty() else 6.0 + a.level) * ItemDB.base(w.get("base", "")).get("spd", 1.2)
		dps *= 1.0 + 0.035 * a.mastery_lvl()
	else:
		dps = a.base_dmg * (1.0 + 0.09 * (a.level - 1))
	var ehp: float = a.hp * (1.0 + a.stat("armor") / 60.0)
	return maxf(1.0, sqrt(ehp * dps))

func _think() -> void:
	if not n.can_act():
		return
	var sight := 21.0 if not Game.is_night() else 14.0
	if n.role in ["guard", "soldier"]:
		sight += 4.0
	var enemies: Array = []
	var contenders: Array = []
	for a in Game.actors_near(n.global_position, sight):
		if a == n or a.is_dead:
			continue
		var d: float = a.global_position.distance_to(n.global_position)
		if a.statuses.has("stealth") and d > 3.5:
			continue
		if Game.is_enemy(n, a):
			enemies.append(a)
		elif a.team == "bot" and n.team == "bot" and a.faction_id != n.faction_id:
			contenders.append(a)
	var hp_f: float = n.hp / maxf(1.0, n.max_hp)
	var my_pow := power_of(n)
	var best_goal := "idle"
	var best_s := 0.15
	var best_t = null
	# --- fight
	for e in enemies:
		var s := _fight_score(e, my_pow, true)
		if s > best_s:
			best_s = s
			best_goal = "fight"
			best_t = e
	if n.role == "bot" or n.role == "hunter":
		for c in contenders:
			var s2 := _fight_score(c, my_pow, false)
			if s2 > best_s:
				best_s = s2
				best_goal = "fight"
				best_t = c
	# --- villagers never fight
	if n.role in ["villager", "trader"] and enemies.size() > 0:
		best_goal = "flee"
		best_s = 2.0
		threat = enemies[0]
	# --- flee / yield
	if enemies.size() > 0 and n.role not in ["villager", "trader"]:
		var thr = n.last_attacker if (n.last_attacker != null and is_instance_valid(n.last_attacker) and not n.last_attacker.is_dead) else enemies[0]
		var ratio := my_pow / power_of(thr)
		var flee_line = 0.18 + 0.32 * p.caution
		if hp_f < flee_line and ratio < 1.6:
			var fs = 1.3 + (1.0 - hp_f) + p.caution * 0.5
			if hp_f < 0.15 and p.caution >= 0.4 and n.role in ["bot", "enemy"] and thr is Actor and thr.kind == "humanoid" and n.spared_by == "" and not n.def_id in ["skeleton", "automaton", "combat_robot", "android", "skeleton_minion"]:
				n.start_yield()
				return
			if fs > best_s:
				best_s = fs
				best_goal = "flee"
				threat = thr
	# --- cautious characters avoid much stronger enemies nearby
	if enemies.size() > 0 and n.role == "bot" and best_goal != "flee":
		for e in enemies:
			var avoid_r := 22.0 if (goal == "flee" and threat == e) else 12.0
			if e.global_position.distance_to(n.global_position) < avoid_r:
				var r2: float = my_pow / power_of(e)
				if r2 < 0.55 and p.caution >= 0.45:
					var av: float = 1.0 + p.caution * 0.6 + (0.55 - r2)
					if av > best_s:
						best_s = av
						best_goal = "flee"
						threat = e
	# --- heal
	if hp_f < 0.45 and n.data and n.data.inv.count("potion_hp") > 0 and n.act.is_empty():
		_drink()
	# --- hunters chase the player
	if n.hunting_player and Game.player and not Game.player.is_dead:
		var dp: float = n.global_position.distance_to(Game.player.global_position)
		if dp < 120.0 and best_goal != "flee":
			if dp < sight:
				best_goal = "fight"
				best_t = Game.player
				best_s = 3.0
			else:
				best_goal = "travel"
				dest = Game.player.global_position
				best_s = 1.5
	# --- assist a benefactor (the player) in combat
	if Game.player and is_instance_valid(Game.player) and not Game.player.is_dead and best_goal != "flee":
		var gr: float = r_of("player").gratitude
		if gr > 0.5 and Game.player.combat_t < 2.0 and Game.player.global_position.distance_to(n.global_position) < 26.0:
			var pt = Game.player.last_attacker
			if pt != null and is_instance_valid(pt) and not pt.is_dead and pt != n:
				var sa := 0.9 + gr * 0.5
				if sa > best_s:
					best_s = sa
					best_goal = "fight"
					best_t = pt
					n.add_aggro(pt, 20.0)
	if best_goal == "idle" or best_s < 0.8:
		var alt := _peaceful_goal(hp_f)
		if alt.s > best_s:
			best_s = alt.s
			best_goal = alt.g
	_set_goal(best_goal, best_t)

func _fight_score(e, my_pow: float, hostile: bool) -> float:
	var d: float = e.global_position.distance_to(n.global_position)
	var ratio: float = my_pow / power_of(e)
	var s: float
	if hostile:
		s = 0.6 + p.aggr * 0.6
		s *= clampf(ratio, 0.35, 2.2)
		if ratio < 0.8:
			s -= p.caution * 0.6
	else:
		# contenders: only attack when clearly stronger or target weakened
		var weak: float = 1.0 - e.hp / maxf(1.0, e.max_hp)
		s = (ratio - 1.15) * p.aggr * 0.9 + weak * p.ambition * 0.6 * (1.0 if e.combat_t < 4.0 else 0.4)
		if p.caution > 0.7 and ratio < 1.6:
			s -= 0.4
	if e == n.last_attacker:
		s += 0.6
	var r := r_of(e.actor_id)
	s += r.grudge * p.venge * 0.8
	s -= r.gratitude * 1.5
	s -= r.fear * p.caution * 0.6
	if e.is_player and n.record.size() > 0:
		var pr: Dictionary = n.record.get("rel", {})
		s += float(pr.get("grudge", 0.0)) * p.venge * 0.5 + float(pr.get("rivalry", 0.0)) * 0.3
		s -= float(pr.get("gratitude", 0.0)) * 1.2
	if n.role in ["guard", "soldier"] and n.home != Vector3.ZERO and e.global_position.distance_to(n.home) > 45.0:
		s -= 0.6
	s -= d / 45.0
	if e.get("yielding") == true:
		s -= 2.0
	return s

func _peaceful_goal(hp_f: float) -> Dictionary:
	var out := {"g": "wander", "s": 0.2}
	var w = Game.world
	if w == null:
		return out
	# schedules
	if n.role in ["villager", "trader"]:
		var bm_on: bool = w.get("director") != null and w.director != null and w.director.has_method("blood_moon_active") and w.director.blood_moon_active()
		if (Game.is_night() and n.role == "villager") or bm_on:
			return {"g": "home", "s": 1.2}
		return {"g": "wander_home", "s": 0.6}
	if n.role == "guard":
		return {"g": "patrol", "s": 0.7}
	if n.role == "soldier" and n.squad.size() > 0:
		return {"g": "duty", "s": 0.9 + p.loyal * 0.5}
	if n.role == "witness":
		return {"g": "wander_home", "s": 0.6}
	if n.role == "companion" or n.role == "double":
		return {"g": "idle", "s": 0.1}
	# contenders / bandits: slither-style growth
	if n.can_loot and w.get("loot") and n.data:
		var drop = w.loot.wanted_drop_near(n, 22.0)
		if drop:
			var s = 0.8 + p.greed * 0.7
			if s > out.s:
				out = {"g": "loot", "s": s}
				obj = drop
	if w.get("orbs") and n.data:
		var cnt: int = w.orbs.count_near(n.global_position, 16.0)
		var so: float = minf(1.0, cnt / 6.0) * (0.45 + p.greed * 0.6) * (1.2 if hp_f > 0.6 else 0.8)
		if so > out.s:
			out = {"g": "orbs", "s": so}
	if n.can_loot and n.role in ["bot", "enemy"]:
		var ch = Game.grid.nearest(n.global_position, 30.0, "interact", func(o): return o is Chest and not o.get("opened"))
		if ch:
			var sc = 0.55 + p.greed * 0.4 + p.curious * 0.3 + (0.5 if n.relic_hunter else 0.0)
			if sc > out.s:
				out = {"g": "chest", "s": sc}
				obj = ch
	# blood moon: cautious contenders seek the safety of a settlement, the bold go hunting
	if n.role == "bot" and w.get("director") and w.director != null and w.director.has_method("blood_moon_active") and w.director.blood_moon_active():
		if p.caution > 0.55 and w.gen:
			var best_s = null
			var bd := 400.0
			for s in w.gen.settlements:
				var d: float = Vector2(n.global_position.x, n.global_position.z).distance_to(s.pos)
				if d < bd:
					bd = d
					best_s = s
			if best_s != null and bd > 18.0:
				dest = Vector3(best_s.pos.x, 0, best_s.pos.y)
				return {"g": "travel", "s": 1.4}
		elif p.aggr > 0.6:
			out.s = minf(out.s, 0.3)   # roam and fight rather than gather
	if n.role == "bot" and w.get("director") and w.director.has_method("event_near"):
		var ev = w.director.event_near(n.global_position, 220.0)
		if ev != null:
			var se = 0.5 + p.ambition * 0.4 + p.curious * 0.25
			if se > out.s:
				out = {"g": "travel", "s": se}
				dest = ev.pos
	var sx = 0.3 + p.curious * 0.45
	if sx > out.s:
		out = {"g": "explore", "s": sx}
	return out

func _set_goal(g: String, t) -> void:
	if g != goal:
		path.clear()
		idle_t = 0.0
	goal = g
	target = t
	match g:
		"fight":
			if t:
				n.add_aggro(t, 15.0)
		"explore":
			if path.is_empty():
				_plan_explore()
		"home":
			if path.is_empty():
				var b = _home_building()
				if b:
					path = [b.door_out, b.door_in, b.interior_points[0] if b.interior_points.size() > 0 else b.door_in]
				else:
					path = [n.home]
		"wander_home":
			if path.is_empty():
				path = [n.home + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))]
		"patrol":
			if path.is_empty():
				var a := randf() * TAU
				path = [n.home + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 18.0)]
		"duty":
			var sp: Vector3 = n.squad.get("pos", n.home)
			if path.is_empty() or path[-1].distance_to(sp) > 3.0:
				path = [sp + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))]
		"travel":
			path = [dest]
		"wander":
			if path.is_empty():
				path = [n.global_position + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))]

func _home_building():
	if Game.world == null or not Game.world.get("terrain") or Game.world.terrain == null:
		return null
	if not Game.world.terrain.has_method("building_at"):
		return null
	var best = null
	var bd := 40.0
	for b in n.get_tree().get_nodes_in_group("buildings"):
		var d: float = b.global_position.distance_to(n.home)
		if d < bd:
			bd = d
			best = b
	return best

func _plan_explore() -> void:
	var tries := 0
	var tree = n.get_tree()
	# visit a nearby building interior sometimes
	if randf() < 0.35 + p.curious * 0.3:
		var bs = tree.get_nodes_in_group("buildings")
		bs.shuffle()
		for b in bs:
			tries += 1
			if tries > 12:
				break
			if b.global_position.distance_to(n.global_position) < 70.0 and b.get("door_out") != null:
				path = [b.door_out, b.door_in]
				if b.interior_points.size() > 0:
					path.append(b.interior_points[randi() % b.interior_points.size()])
				return
	var a := randf() * TAU
	path = [n.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(20.0, 55.0)]

func _drink() -> void:
	for it in n.data.inv.items:
		if it.base == "potion_hp":
			n.heal(n.max_hp * 0.4)
			n.data.inv.consume("potion_hp", 1)
			VFX.burst(n.chest(), Color(0.4, 1.0, 0.4), 8, 0.3)
			return

# ---------------------------------------------------------------- acting
func _act(delta: float) -> void:
	if not n.can_act():
		n.move_input = Vector3.ZERO
		return
	if n.blocking:
		block_t -= delta
		if block_t <= 0.0:
			n.set_block(false)
	match goal:
		"fight":
			_combat(delta)
		"flee":
			if threat == null or not is_instance_valid(threat) or threat.is_dead:
				goal = "idle"
				return
			var away: Vector3 = n.global_position - threat.global_position
			away.y = 0
			if away.length() > 30.0:
				goal = "idle"
				n.move_input = Vector3.ZERO
				return
			_steer(away.normalized(), delta, 1.0)
			if away.length() < 4.0 and randf() < 0.02:
				n.dodge(away.normalized().rotated(Vector3.UP, randf_range(-0.8, 0.8)))
		"orbs":
			if Game.world and Game.world.get("orbs"):
				var op: Vector3 = Game.world.orbs.nearest_orb(n.global_position, 18.0)
				if op == Vector3.INF:
					goal = "idle"
					think_t = 0.0
				else:
					_move_to(op, delta)
		"loot":
			if obj == null or not is_instance_valid(obj):
				goal = "idle"
				think_t = 0.0
			elif n.global_position.distance_to(obj.global_position) < 1.6:
				Game.world.loot.pickup(n, obj)
				obj = null
				goal = "idle"
			else:
				_move_to(obj.global_position, delta)
		"chest":
			if obj == null or not is_instance_valid(obj) or obj.get("opened"):
				goal = "idle"
				think_t = 0.0
			elif n.global_position.distance_to(obj.global_position) < 2.2:
				n.start_action("interact", 0.4, 0.5, {"anim": "interact"})
				obj.interact(n)
				obj = null
				goal = "idle"
			else:
				_move_to(obj.global_position, delta)
		"idle":
			n.move_input = Vector3.ZERO
			idle_t += delta
			if idle_t > 2.0:
				think_t = 0.0
		_:
			_follow_path(delta)

func _follow_path(delta: float) -> void:
	if path.is_empty():
		n.move_input = Vector3.ZERO
		idle_t += delta
		if idle_t > 1.5 + randf() * 2.0:
			idle_t = 0.0
			if goal in ["explore", "wander", "wander_home", "patrol", "travel"]:
				goal = "idle"
				think_t = 0.0
		return
	var wp: Vector3 = path[0]
	var to = wp - n.global_position
	to.y = 0
	if to.length() < 1.1:
		path.pop_front()
		return
	_move_to(wp, delta, 0.75 if goal in ["wander_home", "patrol", "home"] else 1.0)

func _move_to(pos: Vector3, delta: float, spd: float = 1.0) -> void:
	var to = pos - n.global_position
	to.y = 0
	if to.length() < 0.3:
		n.move_input = Vector3.ZERO
		return
	_steer(to.normalized(), delta, spd)

func _steer(dir: Vector3, delta: float, spd: float) -> void:
	# stuck / wall handling: side-step perpendicular for a moment
	if side_t > 0.0:
		side_t -= delta
		dir = (dir * 0.3 + side_dir).normalized()
	elif n.is_on_wall():
		side_dir = dir.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
		side_t = 0.6
	stuck_t += delta
	if stuck_t > 1.5:
		if n.global_position.distance_to(last_pos) < 0.8 and n.move_input.length() > 0.1:
			side_dir = dir.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
			side_t = 1.0
			if goal in ["explore", "wander", "travel"] and path.size() > 0 and randf() < 0.5:
				path.pop_front()
		last_pos = n.global_position
		stuck_t = 0.0
	# separation from nearby actors
	var sep := Vector3.ZERO
	for a in Game.actors_near(n.global_position, 1.4):
		if a != n and not a.is_dead:
			var off: Vector3 = n.global_position - a.global_position
			off.y = 0
			if off.length() > 0.01:
				sep += off.normalized() * (1.4 - off.length())
	n.move_input = (dir + sep * 0.6).normalized() * spd

func _combat(delta: float) -> void:
	var t = target
	if t == null or not is_instance_valid(t) or t.is_dead or (t.get("yielding") == true):
		goal = "idle"
		think_t = 0.0
		n.move_input = Vector3.ZERO
		return
	var to: Vector3 = t.global_position - n.global_position
	to.y = 0
	var d := to.length()
	var dir = to.normalized() if d > 0.01 else n.facing
	var r: float = n.weapon_range()
	var ranged: bool = n.is_ranged()
	if d > 40.0:
		goal = "idle"
		return
	# weapon swap by distance
	if swap_cd <= 0.0 and n.data:
		swap_cd = 5.0
		if not ranged and d > 10.0:
			_swap_to(["bow", "firearm", "staff"])
		elif ranged and d < 3.0 and n.weapon_cat() != "staff":
			_swap_to(["sword", "dagger", "spear", "heavy"])
	n.face_dir(dir)
	strafe_t -= delta
	if strafe_t <= 0.0:
		strafe_t = randf_range(0.8, 2.0)
		strafe = -strafe
	var t_ranged: bool = t.is_ranged() if t.has_method("is_ranged") else false
	if ranged:
		var want_cover: bool = (p.caution > 0.55 or DBActors.ENEMIES.get(n.def_id, {}).get("cover", false) or lost_to_ranged >= 2) and t_ranged
		if want_cover:
			cover_t -= delta
			if cover_t <= 0.0:
				cover_t = 2.5
				cover_pos = _find_cover(t)
		if want_cover and cover_pos != null and n.global_position.distance_to(cover_pos) > 1.0 and d < r:
			_move_to(cover_pos, delta)
		elif d > r * 0.85:
			_steer(dir, delta, 1.0)
		elif d < r * 0.35:
			_steer(-dir, delta, 0.9)
		else:
			_steer(dir.cross(Vector3.UP) * strafe, delta, 0.6)
		if d <= r and Combat.line_of_sight(n.chest(), t.chest()):
			n.attack(dir)
	else:
		if d > r * 0.8:
			var appr = dir
			if t_ranged and lost_to_ranged >= 2:
				appr = (dir + dir.cross(Vector3.UP) * strafe * 0.6).normalized()
				if randf() < 0.01:
					n.dodge(appr)
			_steer(appr, delta, 1.0)
		else:
			n.move_input = dir.cross(Vector3.UP) * strafe * 0.25
			if not n.blocking:
				n.attack(dir)
		# defend against incoming melee
		if not n.blocking and d < 3.6 and t.act.get("name", "") == "melee" and randf() < p.caution * 0.08:
			n.set_block(true)
			block_t = 0.45
	# dodge incoming heavy actions
	if d < 6.0 and t.act.get("name", "") in ["skill", "spell"] and randf() < 0.03 + p.caution * 0.04:
		n.dodge(dir.cross(Vector3.UP) * strafe)
	# skills & spells
	if randf() < 0.12 and n.data and n.act.is_empty():
		var slots: Array = n.data.auto_slots(n.weapon_cat())
		for i in 3:
			var id: String = slots[i]
			if id == "" or n.skill_cd.has(id):
				continue
			var sp := DBSkills.spell(id)
			var useful := false
			if not sp.is_empty():
				useful = n.mana >= sp.mana and (d < 16.0 or id in ["st_shield"])
				if id in ["blink", "riftdash"] and d < 4.0:
					useful = false
			else:
				useful = d < r + 2.5 or id in ["dg_stealth", "hv_unstoppable", "st_shield"]
			if useful:
				n.use_slot(i, dir)
				break
	if n.hp < n.max_hp * 0.35 and randf() < 0.05 and n.data and n.data.inv.count("potion_hp") > 0:
		_drink()

func _swap_to(cats: Array) -> void:
	var best := {}
	for it in n.data.inv.items:
		var b := ItemDB.base(it.base)
		if b.get("slot", "") == "main" and b.get("cat", "") in cats:
			if best.is_empty() or ItemDB.power(it) > ItemDB.power(best):
				best = it
	if not best.is_empty():
		var res: Dictionary = n.data.inv.equip_item(best)
		if res.ok:
			n.refresh_gear()

func _find_cover(t) -> Variant:
	var best = null
	var bd := INF
	for i in 8:
		var a := TAU * i / 8.0
		var p2: Vector3 = n.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 6.0)
		if Game.world and Game.world.has_method("ground_height"):
			p2.y = Game.world.ground_height(p2)
		if not Combat.line_of_sight(t.chest(), p2 + Vector3(0, 1.0, 0)):
			var d: float = p2.distance_to(n.global_position)
			if d < bd:
				bd = d
				best = p2
	return best
