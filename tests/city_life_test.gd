extends Node
## Peaceful city and a rare raid (mandatory tests of the expansion).
## Part 1 — a day in the capital with several dozen townsfolk: merchants open
## their counters, the smith works, people shop, the inn fills in the
## evening with a bard, the guard patrols, nobody fights without reason,
## people go home at night, shops close, and the town wakes in the morning.
## Part 2 — one prepared raid: guard response, townsfolk take cover, a finite
## band with a target, the hero can intervene, the fight ends, recovery, the
## routine resumes, and no second raid starts right after.
## Prints CITY_DONE pass=N fail=M.

func _ready() -> void:
	seed(808)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Горожанин", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var civil_hits := 0
	var civil_detail := {}
	var cap := {}
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func _ready() -> void:
		Events.actor_damaged.connect(_on_dmg)
		_run()
	func _on_dmg(t, amount: float, src, _dt: String) -> void:
		if amount <= 0.0 or src == null or not is_instance_valid(src) or not is_instance_valid(t):
			return
		if CityPeace.hostile_kind(src) or CityPeace.hostile_kind(t):
			return
		civil_hits += 1
		var k := "%s->%s" % [str(src.get("role")), str(t.get("role"))]
		civil_detail[k] = int(civil_detail.get(k, 0)) + 1
	func set_hour(hh: float) -> void:
		Game.game_time = floor(Game.game_time) + 1.0 + hh / 24.0
	func folk() -> Array:
		var out: Array = []
		for a in Game.world.settlement_npcs.get(cap.id, []):
			if is_instance_valid(a) and not a.is_dead:
				out.append(a)
		return out
	func count_act(acts: Array, settled := true) -> int:
		var n := 0
		for a in folk():
			var pl: Dictionary = a.get_meta("plan", {})
			if String(pl.get("act", "")) in acts and (not settled or (a.brain.goal == "routine" and a.brain._r_state == "at")):
				n += 1
		return n
	func by_prof(prof: String) -> Array:
		var out: Array = []
		for a in folk():
			if a.get_meta("prof", "") == prof:
				out.append(a)
		return out
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0          # no unrelated world events in this test
		var cl = w.sys("city_life")
		var cpz = w.sys("city_peace")
		ck("city peace, city life and economy are attached", cl != null and cpz != null and w.sys("city_economy") != null)
		cap = w.director.capital()
		var cp := Vector3(cap.pos.x, 0, cap.pos.y)
		w.terrain.force_load_around(cp)
		await wait(1.0)
		cp.y = w.ground_height(cp) + 0.5
		set_hour(7.5)
		w._teleport(pl, cp)
		await wait(4.0)
		cpz.cities[cap.id].last_raid = Game.game_time      # a peaceful stretch: no raid due
		# several dozen townsfolk
		var arr: Array = w.settlement_npcs.get(cap.id, [])
		var c_own: Dictionary = cap.duplicate()
		c_own.owner = w.factions.settlement_owner(cap.id)
		for i in 26:
			var p: Vector3 = cp + Vector3(randf_range(-22, 22), 0, randf_range(-22, 22))
			p.y = w.ground_height(p)
			var v = w.spawner.spawn_villager(c_own, p, "guard" if i % 7 == 0 else "villager")
			if v:
				arr.append(v)
		w.settlement_npcs[cap.id] = arr
		await wait(1.0)
		var total := folk().size()
		ck("test town has several dozen townsfolk", total >= 30, "%d" % total)
		ck("the town starts peaceful", cpz.state_of(cap.id) == "peaceful")
		# ---- morning: shops open, smith works, guards on duty
		set_hour(8.6)
		for a in folk():
			a.brain.think_t = 0.0
		await wait(24.0)
		var merchants := by_prof("merchant")
		var m_at := 0
		for m in merchants:
			if String(m.get_meta("plan", {}).get("act", "")) == "trade" and m.brain._r_state == "at":
				m_at += 1
		ck("merchants stand at their counters in working hours", merchants.size() > 0 and m_at >= 1, "%d of %d" % [m_at, merchants.size()])
		var smiths := by_prof("smith")
		ck("the smith works at the anvil", smiths.size() > 0 and count_act(["work"]) >= 1, "work sessions %d" % cl.stats.work_sessions)
		ck("guards are on posts or patrolling", count_act(["post"]) + count_act(["patrol"], false) >= 2, "post %d, patrol %d" % [count_act(["post"]), count_act(["patrol"], false)])
		await wait(14.0)
		ck("townsfolk buy goods (real trades at counters)", cl.stats.trades > 0, "trades %d" % cl.stats.trades)
		ck("residents visit the market", count_act(["shop", "market"], false) > 0)
		# ---- evening: the inn fills up, a bard plays
		set_hour(19.2)
		for a in folk():
			a.brain.think_t = 0.0
		await wait(26.0)
		ck("evening: people sit in the inn", cl.stats.tavern_visits > 0 and count_act(["inn", "eat"]) >= 1, "visits %d, now %d" % [cl.stats.tavern_visits, count_act(["inn", "eat"])])
		var bards := by_prof("bard")
		ck("a bard performs in the evening", bards.size() > 0 and cl.stats.songs > 0, "bards %d songs %d" % [bards.size(), cl.stats.songs])
		var shops_open_eve := 0
		for m in merchants:
			if cl.is_open(m):
				shops_open_eve += 1
		ck("merchants have closed their counters in the evening", shops_open_eve == 0, "%d open" % shops_open_eve)
		# ---- night: home, sleep
		set_hour(23.0)
		for a in folk():
			a.brain.think_t = 0.0
		await wait(24.0)
		var sleeping := count_act(["sleep"])
		ck("at night townsfolk go home to sleep", sleeping >= int(total * 0.3), "%d of %d" % [sleeping, total])
		ck("the guard keeps watch at night", count_act(["post"]) + count_act(["patrol"], false) >= 1)
		# ---- no double booking
		var seen := {}
		var dup := 0
		for a in folk():
			var sid: String = a.get_meta("spot_id", "")
			if sid != "":
				if seen.has(sid):
					dup += 1
				seen[sid] = true
		ck("no two people hold the same place", dup == 0, "%d duplicates, %d conflicts avoided" % [dup, cl.stats.reservation_conflicts])
		# ---- morning again
		set_hour(8.7)
		for a in folk():
			a.brain.think_t = 0.0
		var tr0: int = cl.stats.trades
		await wait(30.0)
		ck("next morning the town comes alive again", count_act(["trade", "work"]) >= 1 and cl.stats.trades >= tr0, "trades +%d" % (cl.stats.trades - tr0))
		ck("nobody fought without reason all day", civil_hits == 0, str(civil_detail))
		ck("the town stayed peaceful", cpz.state_of(cap.id) in ["peaceful", "tense"], cpz.state_of(cap.id))
		# ================================================= rare raid
		cpz.cities[cap.id].last_raid = -99.0
		set_hour(14.0)
		civil_hits = 0
		ck("a raid is allowed when the town is due", cpz.can_raid(cap.id))
		var ev_n0: int = w.director.events.size()
		w.director.start_raid_on(cap.id, "")
		var raid = null
		for e in w.director.events:
			if e.type == "raid":
				raid = e
		ck("the raid starts as a real event with a finite band", raid != null and raid.actors.size() >= 3 and raid.actors.size() <= 8, "%d raiders" % (raid.actors.size() if raid else 0))
		ck("the town goes into the attack state", cpz.state_of(cap.id) == "attack")
		var targeted := 0
		for r in raid.actors:
			if is_instance_valid(r) and r.brain.dest.distance_to(cp) < 15.0:
				targeted += 1
		ck("raiders have a concrete target (the town centre)", targeted == raid.actors.size())
		await wait(1.0)
		var shelter := 0
		for a in folk():
			if a.has_meta("sheltering") or a.brain.goal == "flee":
				shelter += 1
		ck("townsfolk take cover", shelter >= 5, "%d" % shelter)
		ck("the hero can fight the raiders", Game.can_damage(pl, raid.actors[0]))
		# let the guard engage, then finish the raid
		for r in raid.actors:
			if is_instance_valid(r):
				r.global_position = cp + Vector3(randf_range(-8, 8), 0.5, randf_range(-8, 8))
		await wait(10.0)
		var guard_fight := 0
		for a in folk():
			if a.get("role") == "guard" and a.brain.goal == "fight":
				guard_fight += 1
		ck("the guard responds to the raid", guard_fight >= 1 or cpz.stats.guard_responses > 0, "fighting %d, responses %d" % [guard_fight, cpz.stats.guard_responses])
		for r in raid.actors:
			if is_instance_valid(r) and not r.is_dead:
				r.take_damage({"amount": 99999.0, "dtype": "slash", "src": pl})
		await wait(2.0)
		ck("the raid ends when the band is beaten", not raid in w.director.events)
		ck("the town moves to recovery", cpz.state_of(cap.id) == "recovery", cpz.state_of(cap.id))
		ck("no new raid right after the last one", not cpz.can_raid(cap.id))
		var refused0: int = cpz.stats.raids_refused
		w.director._start("bandit_raid", pl.global_position)
		var raids := 0
		for e in w.director.events:
			if e.type == "raid":
				raids += 1
		ck("the director's raid roll is refused during recovery", raids == 0 and cpz.stats.raids_refused > refused0)
		for a in folk():
			a.brain.think_t = 0.0
		var back := 0
		for i in 30:                     # poll: under load the AI ticks less often in real time
			await wait(1.0)
			back = 0
			for a in folk():
				if a.brain.goal == "routine":
					back += 1
			if i >= 11 and back >= int(folk().size() * 0.4):
				break
		var goals := {}
		for a in folk():
			var gk := "%s/%s%s" % [str(a.get_meta("prof", "?")), a.brain.goal, "/sh" if a.has_meta("sheltering") else ""]
			goals[gk] = int(goals.get(gk, 0)) + 1
		ck("townsfolk return to their routine after the raid", back >= int(folk().size() * 0.4), "%d of %d %s %s" % [back, folk().size(), cpz.state_of(cap.id), str(goals)])
		ck("no townsperson attacked another during the raid", civil_hits == 0, str(civil_detail))
		print("CITY_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
