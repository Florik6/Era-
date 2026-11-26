extends Node
## «Буря над Чёрным городом», end to end, on real systems only.
##  Stage A — limited test arena (open field, LOW settings): two covens of NPC
##  mages fight each other with ordinary spells; their magics react
##  (resonance, NPC vs NPC); limits hold; the storm ends with a chronicle
##  entry and restores the weather and modifiers.
##  Stage B — the era capital with a crowd (HIGH settings, +20 townsfolk):
##  the same scenario in the city; when a catastrophe happens townsfolk flee
##  and guards converge. If the duel produces no catastrophe within the time
##  limit, one is provoked with a real ultimate-strength pair on the square
##  (reported as such) to check the city integration.
## Prints STORM_DONE pass=N fail=M and a STORM_STATS line.

func _ready() -> void:
	seed(20261126)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Profile.new_character("Наблюдатель", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = 0
	Settings.quality = Settings.Quality.LOW
	Settings.effective_quality = Settings.Quality.LOW
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var cross_hits := 0
	var mage_ids := {}
	var max_active := 0
	var max_imprints := 0
	var max_lights := 0
	var stats_out := {}
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func frames(n: int) -> void:
		for i in n:
			await get_tree().physics_frame
	func _ready() -> void:
		Events.actor_damaged.connect(_on_dmg)
		_run()
	func _on_dmg(t, amount: float, src, _dt: String) -> void:
		if OS.has_environment("STORM_DEBUG") and t != null and is_instance_valid(t) and mage_ids.has(t.actor_id):
			print("DBG dmg %s(%s) <- %s %.0f %s hp=%.0f" % [t.display_name, mage_ids[t.actor_id], (src.display_name if src != null and is_instance_valid(src) else "null"), amount, _dt, t.hp])
		if src == null or t == null or not is_instance_valid(src) or not is_instance_valid(t):
			return
		if mage_ids.has(src.actor_id) and mage_ids.has(t.actor_id) and mage_ids[src.actor_id] != mage_ids[t.actor_id] and amount > 0.0:
			cross_hits += 1
	func far_open_spot() -> void:
		var w = Game.world
		var pl = Game.player
		var space = pl.get_world_3d().direct_space_state
		for tries in 120:
			var a := randf() * TAU
			var p: Vector3 = pl.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(60.0, 260.0)
			var near_town := false
			for st in w.gen.settlements:
				if Vector2(st.pos.x - p.x, st.pos.y - p.z).length() < st.get("r", 60.0) + 70.0:
					near_town = true
			if near_town:
				continue
			w.terrain.force_load_around(p)
			p.y = w.ground_height(p) + 0.3
			if w.is_water(p):
				continue
			var clear := true
			for k in 12:
				var d := Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0))
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + d * 16.0, 1)
				q.exclude = [pl.get_rid()]
				if not space.intersect_ray(q).is_empty():
					clear = false
					break
			if clear:
				w._teleport(pl, p + Vector3(0, 0, -16))
				await frames(4)
				return
	func storm_ev():
		for e in Game.world.director.events:
			if e.type == "black_storm":
				return e
		return null
	func watch(e, secs: float) -> void:
		var res = Game.world.sys("resonance")
		var t := 0.0
		while t < secs and e in Game.world.director.events:
			await wait(0.5)
			t += 0.5
			var live := 0
			for z in res.active:
				if is_instance_valid(z):
					live += 1
			max_active = maxi(max_active, live)
			max_imprints = maxi(max_imprints, res.imprints.size())
			var mg = VFX.mgr()
			if mg != null:
				max_lights = maxi(max_lights, int(mg.get("_lights_live")))
			if int(e.data.get("catastrophes", 0)) > 0 and t > 12.0 and secs < 999.0:
				break
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		pl.team = "player"
		w.director.resonance_rift_chance = 1.0
		w.director._t = -100000.0     # no unrelated random world events during the test
		var res = w.sys("resonance")
		res.cata_ready_at = 0.0
		# ================================================= Stage A: arena
		print("STAGE A: test arena, LOW settings")
		Settings.apply()
		await far_open_spot()
		var center: Vector3 = pl.global_position + Vector3(0, 0, 16)
		var r0: int = res.stats.reactions
		var e = w.director.start_black_storm(center, {"arena": true, "dur": 150.0})
		ck("storm started on the arena", e != null and not e.is_empty() and storm_ev() == e)
		var nm: int = e.data.mages.ember.size() + e.data.mages.frost.size()
		ck("two covens arrived (3 + 4 mages)", e.data.mages.ember.size() == 3 and e.data.mages.frost.size() == 4, "%d + %d" % [e.data.mages.ember.size(), e.data.mages.frost.size()])
		for side in ["ember", "frost"]:
			for m in e.data.mages[side]:
				mage_ids[m.actor_id] = side
		ck("the weather turned into a storm", w.weather.current == "storm")
		ck("magic storm empowers spells", float(w.director.mods.spell) > 1.0)
		await watch(e, 75.0)
		var ra: int = res.stats.reactions - r0
		var owners_npc: bool = res.last.is_empty() or res.last.owner != pl
		ck("covens fight each other (NPC vs NPC hits)", cross_hits > 0, "%d hits" % cross_hits)
		ck("their spells react (resonance from NPC magic)", ra > 0, "%d reactions, kinds %s" % [ra, str(res.stats.by_kind)])
		ck("reactions came from NPC casters, not the hero", owners_npc)
		ck("reaction zones never exceeded the limit", max_active <= Resonance.MAX_ACTIVE, "max %d" % max_active)
		ck("imprints stayed bounded", max_imprints <= Resonance.MAX_IMPRINTS, "max %d" % max_imprints)
		stats_out["arena"] = {"reactions": ra, "kinds": res.stats.by_kind.duplicate(), "catastrophes": int(e.data.get("catastrophes", 0)), "strikes": e.data.strikes, "hits": cross_hits, "max_active": max_active, "max_lights": max_lights}
		var arena_won: bool = storm_ev() == null
		print("STORM_INFO arena duel lasted %.0f s (%s)" % [e.t, "a coven won" if arena_won else "still going"])
		stats_out["arena_duration_s"] = snappedf(e.t, 1.0)
		# end the arena storm (timeout path)
		e.t = e.dur
		await wait(1.0)
		ck("arena storm ended cleanly", storm_ev() == null)
		ck("modifiers restored after the storm", float(w.director.mods.spell) == 1.0)
		ck("weather left the storm", w.weather.current != "storm")
		var chron := false
		for ev in Chronicle.events:
			if ev.type == "black_storm":
				chron = true
		ck("chronicle records the storm", chron)
		if str(e.data.get("result", "")) == "ковены рассеялись" or true:
			var left := 0
			for side in ["ember", "frost"]:
				for m in e.data.mages[side]:
					if is_instance_valid(m) and not m.is_dead:
						left += 1
			ck("on timeout the surviving covens leave (winners of a finished duel may stay)", left == 0 or arena_won, "%d left" % left)
		# clear leftover resonance events from stage A
		for ev in w.director.events.duplicate():
			if ev.type == "resonance":
				ev.t = ev.dur
				w.director._tick_event(ev, 0.1)
		# ================================================= Stage B: capital
		print("STAGE B: capital with a crowd, HIGH settings")
		Settings.quality = Settings.Quality.HIGH
		Settings.effective_quality = Settings.Quality.HIGH
		Settings.apply()
		var cap: Dictionary = w.director.capital()
		ck("the era has a capital", not cap.is_empty())
		var cpos := Vector3(cap.pos.x, 0, cap.pos.y)
		w.terrain.force_load_around(cpos)
		await wait(1.0)
		cpos.y = w.ground_height(cpos)
		w._teleport(pl, cpos + Vector3(0, 0.5, -14))
		await wait(3.0)
		var crowd: Array = []
		for k in 20:
			var a := randf() * TAU
			var pp: Vector3 = cpos + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 30.0)
			pp.y = w.ground_height(pp)
			var v = w.spawner.spawn_villager(cap, pp, "villager" if k % 5 != 0 else "guard")
			if v:
				crowd.append(v)
		await wait(1.0)
		var townsfolk := 0
		for a2 in Game.actors_near(cpos, 70.0):
			if a2.get("role") in ["villager", "trader", "guard", "soldier"]:
				townsfolk += 1
		ck("the city square is crowded", townsfolk >= 20, "%d townsfolk" % townsfolk)
		cross_hits = 0
		max_active = 0
		mage_ids.clear()
		res.cata_ready_at = 0.0
		var r1: int = res.stats.reactions
		var c1: int = res.stats.catastrophes
		var e2 = w.director.start_black_storm(Vector3.INF, {"dur": 200.0})
		ck("storm over the capital started", e2 != null and not e2.is_empty() and e2.data.city == cap.get("name", ""), str(e2.data.get("city", "")) if e2 else "")
		for side in ["ember", "frost"]:
			for m in e2.data.mages[side]:
				mage_ids[m.actor_id] = side
		await watch(e2, 80.0)
		var rb: int = res.stats.reactions - r1
		var natural: bool = res.stats.catastrophes > c1
		ck("city duel: covens fight and their magic reacts", cross_hits > 0 and rb > 0, "%d hits, %d reactions" % [cross_hits, rb])
		ck("limits hold in the city too", max_active <= Resonance.MAX_ACTIVE, "max %d" % max_active)
		var provoked := false
		if not natural:
			provoked = true
			res.cata_ready_at = 0.0
			res.recent.clear()
			Resonance.imprint("fire", cpos, 90.0, "ultimate", e2.data.mages.ember[0] if is_instance_valid(e2.data.mages.ember[0]) else null)
			Resonance.imprint("ice", cpos, 40.0, "empowered", null)
			await frames(3)
		print("STORM_INFO catastrophe in the city: ", "natural (from the duel)" if natural else "provoked by the test on the square")
		var rev = null
		for ev in w.director.events:
			if ev.type == "resonance":
				rev = ev
		ck("catastrophe in the city runs through the director", rev != null)
		if rev != null:
			ck("townsfolk flee from it", int(rev.data.get("fled", 0)) >= 3, "%d fled" % int(rev.data.get("fled", 0)))
			ck("guards converge on it", int(rev.data.get("guards", 0)) >= 1, "%d guards" % int(rev.data.get("guards", 0)))
			await wait(8.7)
			ck("the city anomaly opens a rift", rev.data.get("portal") != null and is_instance_valid(rev.data.portal))
		stats_out["city"] = {"reactions": rb, "catastrophe": "natural" if natural else "provoked", "fled": rev.data.get("fled", 0) if rev else 0,
			"guards": rev.data.get("guards", 0) if rev else 0, "hits": cross_hits, "max_active": max_active, "max_lights": max_lights,
			"townsfolk": townsfolk, "kinds": res.stats.by_kind.duplicate()}
		e2.t = e2.dur
		await wait(1.0)
		ck("city storm ended cleanly", storm_ev() == null)
		print("STORM_STATS ", JSON.stringify(stats_out))
		print("STORM_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
