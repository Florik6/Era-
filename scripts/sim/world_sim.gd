class_name WorldSim
extends Node
## Active/background simulation. Records near the player become real 3D NPCs;
## distant records are simulated cheaply: travel, fights between records,
## treasure finds, levelling, joining factions, capturing points, rising to
## command. Settlements grow or decline. Every outcome is logged to the
## Chronicle so the player sees the consequences on return.

const ACTIVE_R := 85.0
const DESPAWN_R := 125.0

var world
var active := {}         # record id -> NPC
var _act_t := 0.0
var _bg_t := 0.0
var _camp_t := 0.0
var camp_spawns := {}    # poi id -> Array of actors

func _init(w) -> void:
	world = w

func setup() -> void:
	if world.legends.recs.is_empty():
		_generate_population()

func _generate_population() -> void:
	var rng := Game.rng
	var era: int = Profile.current_era
	var lr: Vector2i = world.spawner.era_level_range()
	var half: float = world.world_half * 0.85
	for i in 30:
		var female := rng.randf() < 0.35
		var nm := DBActors.rand_name(era, female, rng)
		if rng.randf() < 0.5:
			nm += " " + DBActors.NICKNAMES[rng.randi() % DBActors.NICKNAMES.size()]
		var lvl := rng.randi_range(lr.x, lr.x + (lr.y - lr.x) / 2)
		var rec: Dictionary = world.legends.new_record(nm, {"female": female, "level": lvl, "pos": [rng.randf_range(-half, half), rng.randf_range(-half, half)],
			"relic_hunter": i < 3, "archetype": "treasure" if i < 3 else DBActors.rand_archetype(rng)})
		if i < 3:
			rec.backstory += " Охотник(ца) за реликвиями: ищет артефакты в руинах и разломах."
	var fl: Array = DBEras.factions_of(era)
	for fid in fl:
		var leader: Dictionary = world.legends.new_record(DBActors.rand_name(era, rng.randf() < 0.3, rng), {"faction": fid, "level": lr.y - 2, "role": "soldier", "archetype": "ambitious"})
		leader.leader = true
		leader.commander = true
		leader.legend = true
		leader.renown = 80.0
		leader.title = ["Железная Воля", "Голос Ордена", "Тень Престола", "Первый Клинок"][rng.randi() % 4]
		world.factions.st[fid].leader = leader.id
		for c in 2:
			var cm: Dictionary = world.legends.new_record(DBActors.rand_name(era, rng.randf() < 0.3, rng), {"faction": fid, "level": lr.x + 4 + c * 2, "role": "soldier", "archetype": "defender"})
			cm.commander = true
			cm.renown = 30.0
		var home := _faction_home(fid)
		for k in world.legends.recs:
			var r: Dictionary = world.legends.recs[k]
			if r.faction == fid:
				r.pos = [home.x + rng.randf_range(-20, 20), home.y + rng.randf_range(-20, 20)]
	# descendants of past legends (historical legacy)
	for h in Profile.hall_of_legends:
		if int(h.get("era", -1)) == era - 1 and rng.randf() < 0.7:
			var d: Dictionary = world.legends.new_record(DBActors.rand_name(era, rng.randf() < 0.4, rng), {"heir_of": h.id, "level": lr.x + 2, "pos": [rng.randf_range(-half, half), rng.randf_range(-half, half)]})
			d.backstory = "Потомок легенды «%s» (%s) из эпохи «%s». %s" % [h.name, h.get("title", ""), DBEras.era(era - 1).name, d.backstory]
			d.era_history.append("Род ведёт начало от %s, эпоха «%s»" % [h.name, DBEras.era(era - 1).name])
			d.renown = 20.0

func _faction_home(fid: String) -> Vector2:
	for sid in world.factions.settlements:
		if world.factions.settlements[sid].owner == fid:
			var s = world._settlement(sid)
			if s != null:
				return s.pos
	return Vector2(randf_range(-300, 300), randf_range(-300, 300))

func save_state() -> void:
	for id in active:
		var n = active[id]
		if is_instance_valid(n) and not n.is_dead:
			_sync_back(n)

func _sync_back(n) -> void:
	var r: Dictionary = n.record
	r.data = n.data.to_dict()
	r.level = n.data.level
	r.pos = [n.global_position.x, n.global_position.z]
	r.hp_frac = n.hp / maxf(1.0, n.max_hp)

func _process(delta: float) -> void:
	if Game.mode != "world" or world.player == null or not is_instance_valid(world.player):
		return
	if world.dimension != "":
		return
	_act_t += delta
	_bg_t += delta
	_camp_t += delta
	if _act_t >= 1.0:
		_act_t = 0.0
		_update_active()
	if _bg_t >= 4.0:
		_background_step(_bg_t)
		_bg_t = 0.0

func _update_active() -> void:
	var pp: Vector3 = world.player.global_position
	var maxn: int = Settings.profile().max_npcs
	# despawn far
	for id in active.keys():
		var n = active[id]
		if not is_instance_valid(n) or n.is_dead:
			active.erase(id)
			continue
		if n.global_position.distance_to(pp) > DESPAWN_R:
			_sync_back(n)
			if n.has_method("get") and n.data.level > 0:
				pass
			if n.brain and n.brain.goal == "flee" and n.last_attacker == world.player:
				world.legends.on_player_beat(n.record, true)
			n.queue_free()
			active.erase(id)
	var count := 0
	for a in Game.actors:
		if is_instance_valid(a) and not a.is_dead and a != world.player:
			count += 1
	if count >= maxn:
		return
	for id in world.legends.recs:
		var r: Dictionary = world.legends.recs[id]
		if not r.alive or active.has(id) or r.role == "boss":
			continue
		var rp := Vector3(r.pos[0], 0, r.pos[1])
		if rp.distance_to(pp) < ACTIVE_R:
			var n
			if r.role == "soldier" and r.faction != "":
				n = world.spawner.spawn_soldier(r.faction, "commander" if r.commander else "infantry", rp, int(r.level), r)
				if r.data.size() > 0:
					n.data.from_dict(r.data)
					n.refresh_gear()
				n.home = rp
			else:
				n = world.spawner.spawn_bot(r, rp)
			if r.has("inherit_weapon") and n.data:
				var w: Dictionary = r.inherit_weapon
				r.erase("inherit_weapon")
				n.data.inv.add(w)
				n.data.inv.equip_item(w)
				n.refresh_gear()
			if r.legend:
				n.title = r.title
				n.refresh_gear()
			active[id] = n
			world.legends.on_encounter(n)
			count += 1
			if count >= maxn:
				return

## Cheap simulation for distant records.
func _background_step(dt: float) -> void:
	var rng := Game.rng
	var recs: Dictionary = world.legends.recs
	var ids := recs.keys()
	var pp: Vector3 = world.player.global_position
	for id in ids:
		var r: Dictionary = recs[id]
		if not r.alive or active.has(id) or r.role == "boss":
			continue
		var p := Vector2(r.pos[0], r.pos[1])
		var gp := Vector2(r.goal_pos[0], r.goal_pos[1])
		if gp == Vector2.ZERO or p.distance_to(gp) < 10.0:
			gp = _pick_goal(r)
			r.goal_pos = [gp.x, gp.y]
			# travel along the road network when there is one
			r.erase("route")
			if world.gen and world.gen.has_method("road_path") and p.distance_to(gp) > 60.0:
				var rp: Array = world.gen.road_path(p, gp)
				if rp.size() > 2:
					var flat: Array = []
					for v in rp:
						flat.append([v.x, v.y])
					r["route"] = flat
		var step_to := gp
		var route: Array = r.get("route", [])
		while not route.is_empty() and p.distance_to(Vector2(route[0][0], route[0][1])) < 6.0:
			route.pop_front()
		if not route.is_empty():
			step_to = Vector2(route[0][0], route[0][1])
		var np := p.move_toward(step_to, 1.3 * dt * (1.25 if not route.is_empty() else 1.0))
		# keep simulated movement out of the player's active bubble edge popping
		r.pos = [np.x, np.y]
		var cd: CharData = null
		# random life events
		var roll := rng.randf()
		if roll < 0.012 * dt:
			_find_treasure(r)
		elif roll < 0.02 * dt:
			_gain(r, 30 + rng.randi() % 60)
		if r.faction == "" and r.archetype in ["defender", "ambitious", "hunter"] and rng.randf() < 0.002 * dt:
			var fl: Array = DBEras.factions_of(Profile.current_era)
			r.faction = fl[rng.randi() % fl.size()]
			Chronicle.record("faction_join", [{"id": r.id, "name": r.name}], {"extra": {"faction": DBEras.faction(r.faction).name}})
		if r.faction != "" and not r.commander and r.renown >= 45.0 and rng.randf() < 0.01 * dt:
			r.commander = true
			Chronicle.record("commander", [{"id": r.id, "name": r.name}], {"extra": {"faction": DBEras.faction(r.faction).name}})
		if r.faction != "" and rng.randf() < 0.004 * dt:
			_try_capture(r)
	# fights between nearby inactive records
	for i in 3:
		var a_id = ids[rng.randi() % ids.size()]
		var a: Dictionary = recs[a_id]
		if not a.alive or active.has(a_id) or a.role == "boss":
			continue
		var ap := Vector2(a.pos[0], a.pos[1])
		for b_id in ids:
			if b_id == a_id or active.has(b_id):
				continue
			var b: Dictionary = recs[b_id]
			if not b.alive or b.role == "boss":
				continue
			if ap.distance_to(Vector2(b.pos[0], b.pos[1])) < 60.0:
				var hostile: bool = (a.faction != "" and b.faction != "" and world.factions.at_war(a.faction, b.faction)) or (a.faction == "" and b.faction == "" and rng.randf() < 0.35 * DBActors.ARCHETYPES.get(a.archetype, {}).get("aggr", 0.5))
				if hostile and rng.randf() < 0.25:
					_abstract_fight(a, b)
				break
	# settlements evolve
	for sid in world.factions.settlements:
		var s: Dictionary = world.factions.settlements[sid]
		s.resources = clampf(s.resources + rng.randf_range(-1.0, 2.0), 0.0, 200.0)
		if s.resources > 80.0 and rng.randf() < 0.02:
			s.population = mini(12, s.population + 1)
			s.resources -= 30.0
		s.security = clampf(s.security + 0.01, 0.1, 1.0)

func _pick_goal(r: Dictionary) -> Vector2:
	var rng := Game.rng
	if world.gen == null:
		return Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
	var pois: Array = world.gen.pois
	if r.relic_hunter or r.archetype == "treasure":
		var cands := pois.filter(func(p): return p.type in ["ruins", "rift", "dungeon", "altar"])
		if not cands.is_empty():
			return cands[rng.randi() % cands.size()].pos
	if r.faction != "":
		var cps := pois.filter(func(p): return p.type == "cp")
		if not cps.is_empty() and rng.randf() < 0.6:
			return cps[rng.randi() % cps.size()].pos
	if rng.randf() < 0.5 and not world.gen.settlements.is_empty():
		return world.gen.settlements[rng.randi() % world.gen.settlements.size()].pos
	return pois[rng.randi() % pois.size()].pos if not pois.is_empty() else Vector2.ZERO

func _gain(r: Dictionary, xp: int) -> void:
	if r.data.is_empty():
		r.level = int(r.level) + (1 if Game.rng.randf() < 0.3 else 0)
		return
	var cd := CharData.new()
	cd.from_dict(r.data)
	var lv := cd.add_xp(xp)
	var w := cd.inv.equipped("main")
	var cat: String = ItemDB.base(w.get("base", "")).get("cat", "unarmed") if not w.is_empty() else "unarmed"
	cd.add_mastery_xp(cat, xp * 0.5)
	cd.auto_learn()
	r.data = cd.to_dict()
	r.level = cd.level
	if lv > 0 and r.legend:
		r.era_history.append("Достиг(ла) %d уровня" % cd.level)

func _find_treasure(r: Dictionary) -> void:
	var luck := 0.3 if r.relic_hunter else 0.0
	var it := ItemDB.random_for_era(Profile.current_era, int(r.level), "chest", luck)
	if r.data.size() > 0:
		var cd := CharData.new()
		cd.from_dict(r.data)
		if cd.inv.add(it):
			var slot: String = ItemDB.base(it.base).get("slot", "")
			if slot in ItemDB.SLOTS and ItemDB.power(it) > ItemDB.power(cd.inv.equipped(slot)):
				cd.inv.equip_item(it)
			r.data = cd.to_dict()
	if it.get("rarity", 0) >= 3:
		r.rare_items += 1
		var place = world.gen.nearest_place(Vector2(r.pos[0], r.pos[1])) if world.gen else ""
		Chronicle.record("item_found", [{"id": r.id, "name": r.name}], {"place": place, "extra": {"item": ItemDB.display_name(it), "rarity": it.rarity}})

func _try_capture(r: Dictionary) -> void:
	if world.gen == null:
		return
	var p := Vector2(r.pos[0], r.pos[1])
	for poi in world.gen.pois:
		if poi.type != "cp" or p.distance_to(poi.pos) > 70.0:
			continue
		var owner_f: String = world.factions.point_owner(poi.id)
		if owner_f != r.faction and owner_f != "player" and (owner_f == "" or world.factions.at_war(r.faction, owner_f)):
			world.factions.capture_point(poi.id, r.faction, {"id": r.id, "name": r.name})
		return

func _power(r: Dictionary) -> float:
	var p = 10.0 + float(r.level) * 6.0 + r.renown * 0.3
	if r.data.size() > 0:
		var cd := CharData.new()
		cd.from_dict(r.data)
		for s in cd.inv.equip:
			p += ItemDB.power(cd.inv.equip[s]) * 0.15
	return p

func _abstract_fight(a: Dictionary, b: Dictionary) -> void:
	var pa := _power(a) * Game.rng.randf_range(0.7, 1.3)
	var pb := _power(b) * Game.rng.randf_range(0.7, 1.3)
	var w := a if pa >= pb else b
	var l := b if pa >= pb else a
	w.kills += 1
	w.renown += 6.0
	_gain(w, 60)
	var place = world.gen.nearest_place(Vector2(l.pos[0], l.pos[1])) if world.gen else ""
	var lethal = Game.rng.randf() < 0.45 and not (l.leader and Game.rng.randf() < 0.5)
	Chronicle.record("kill" if lethal else "duel", [{"id": w.id, "name": w.name}, {"id": l.id, "name": l.name}], {"place": place, "extra": {"winner": w.name}})
	if lethal:
		world.legends.on_death(l, w.name, w.id, Vector3(l.pos[0], 0, l.pos[1]))
	else:
		l.survivals += 1
		l.renown += 2.0
	world.legends._check_promotion(w)
