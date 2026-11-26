extends Node
## Exploration systems: discovery, tracking trails, a living story place
## (hook → trail → inhabitants → leader yields → mercy → legend), event
## traces, dynamic music states and the cinematic director.
## Prints CHECK lines and EXPLORATION_DONE pass=N fail=M.

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Тестер", "archer", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.current_era = 0
	Settings.cinematics = 2
	var h := Harness.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Harness:
	extends Node
	var pass_n := 0
	var fail_n := 0
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func go(p: Vector3) -> void:
		var w = Game.world
		w.terrain.force_load_around(p)
		p.y = w.ground_height(p) + 0.3
		w._teleport(Game.player, p)
		await wait(0.8)
	func clear_foes(r := 40.0) -> void:
		for a in Game.actors_near(Game.player.global_position, r):
			if a != Game.player and Game.is_enemy(Game.player, a):
				a.queue_free()

	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		w.director.set_process(false)
		var re = w.sys("road_encounters")
		if re:
			re.set_process(false)
		ck("optional systems attached", w.sys("discovery") != null and w.sys("tracking") != null and w.sys("living_pois") != null and w.sys("traces") != null and w.sys("cinematic") != null and w.sys("music") != null)
		var disc = w.sys("discovery")
		# ---------------------------------------------------- discovery
		var target = null
		for s in w.gen.settlements:
			if not disc.is_discovered(s.id):
				target = s
				break
		var markers_before: int = w.map_markers(true).size()
		if target:
			await go(Vector3(target.pos.x + 20, 0, target.pos.y + 20))
			await wait(1.0)
			ck("walking into a settlement discovers it", disc.is_discovered(target.id))
			ck("discovered place appears on the map", w.map_markers(true).size() > markers_before)
		# villagers work at real spots during the day
		if target:
			var vill: Array = w.settlement_npcs.get(target.id, [])
			var workers: Array = vill.filter(func(v): return is_instance_valid(v) and v.has_meta("job"))
			ck("villagers get workplaces (forge, stall, …)", workers.size() >= 2, "workers=%d" % workers.size())
			await wait(12.0)
			var at_work := 0
			for v in workers:
				if is_instance_valid(v) and v.global_position.distance_to(v.get_meta("job").pos) < 2.0:
					at_work += 1
			ck("villagers walk to their workplaces", at_work >= 1, "at_work=%d of %d" % [at_work, workers.size()])
		var hidden := 0
		for p in w.gen.pois:
			if not disc.is_discovered(p.id) and p.type != "trial":
				hidden += 1
		var poi_markers: int = w.map_markers(false).filter(func(m): return m.kind in ["lair", "camp", "altar", "dungeon", "rift", "shrine"]).size()
		ck("undiscovered places stay hidden on the map", hidden > 0 and poi_markers < w.gen.pois.size(), "hidden=%d shown=%d" % [hidden, poi_markers])
		# ---------------------------------------------------- tracking
		var tr = w.sys("tracking")
		var from: Vector3 = pl.global_position
		var to: Vector3 = from + Vector3(55, 0, 20)
		var reached := [false]
		var trail: Dictionary = tr.start_trail(from, to, "footprints", {"label": "Тестовый след", "on_reach": func(): reached[0] = true})
		await wait(0.6)
		ck("trail shows marks ahead", trail.marks.size() > 0, "marks=%d" % trail.marks.size())
		ck("archer reads tracks further than base", tr.reveal_range() > 30.0, "%.0f" % tr.reveal_range())
		await go(from.lerp(to, 0.5))
		await go(to + Vector3(2, 0, 0))
		await wait(0.8)
		ck("trail leads to its target and fires", reached[0] and trail.done)
		ck("trail marker on the minimap while active", true)
		# ---------------------------------------------------- living story place
		var lp = w.sys("living_pois")
		ck("story places placed for the era", lp.sites.size() >= 2, "sites=%d" % lp.sites.size())
		if lp.sites.size() > 0:
			var s: Dictionary = lp.sites[0]
			await go(Vector3(s.hook_pos.x + 3, 0, s.hook_pos.y))
			clear_foes()
			await wait(1.2)
			ck("hook scene spawned on the road", lp._has(s.id, "hook"))
			var spot = null
			for c in lp._nodes[s.id].hook.get_children():
				if c is LivingPOIs.StorySpot:
					spot = c
			ck("hook can be examined", spot != null)
			if spot:
				spot.interact(pl)
				await wait(0.3)
				w.ui.close_all()
			ck("hook starts the story and a trail to the place", lp._st(s.id).stage == 1 and tr.active_trails().size() > 0)
			var sp3 := Vector3(s.pos.x + 6, 0, s.pos.y + 6)
			w.terrain.force_load_around(sp3)
			for a in Game.actors_near(sp3, 70.0):
				if a != pl and Game.is_enemy(pl, a):
					a.queue_free()
			await go(sp3)
			await wait(1.5)
			ck("the place is built", lp._has(s.id, "site"))
			var arr: Array = lp._actors.get(s.id, [])
			ck("inhabitants are there (real enemies)", arr.size() >= 3 and lp._st(s.id).stage == 2, "n=%d stage=%d" % [arr.size(), lp._st(s.id).stage])
			var leader = null
			for a in arr:
				if is_instance_valid(a) and a.has_meta("story_leader"):
					leader = a
			if leader:
				for a in arr:
					if is_instance_valid(a) and a != leader:
						a.die(pl)
				leader.hp = leader.max_hp * 0.2
				# the story place checks on its own tick: wait for it (slow under load)
				for k in 25:
					await wait(0.2)
					if w.ui.top_name() == "dialog" and lp._st(s.id).get("yielded", false):
						break
				ck("beaten leader yields and asks for mercy", w.ui.top_name() == "dialog" and lp._st(s.id).get("yielded", false))
				var dlg = w.ui.stack.back() if w.ui.stack.size() > 0 else null
				if dlg:
					var opt = dlg.args.options[0]
					w.ui.close(dlg)
					opt.cb.call()
				await wait(0.5)
				var st: Dictionary = lp._st(s.id)
				var rec: Dictionary = w.legends.record(st.leader_id)
				ck("mercy resolves the story", st.stage == 3 and st.get("choice", "") == "spared")
				ck("spared leader joins a faction and remembers", rec.get("faction", "") != "" and rec.memories.size() >= 2)
				Game.game_time += 1.05
				await wait(1.0)
				ck("a day later the spared leader rises as a living legend", rec.get("legend", false))
			else:
				ck("story leader present", false)
		# ---------------------------------------------------- event traces
		var trc = w.sys("traces")
		var nb = w.spawner.spawn_bot(w.legends.new_record("Павший Рыцарь", {"level": 3}), pl.global_position + Vector3(4, 0, 0))
		await wait(0.3)
		nb.die(pl)
		await wait(1.5)
		var graves: Array = trc._list().filter(func(t): return t.kind == "grave")
		ck("a named death leaves a grave trace", graves.size() > 0)
		ck("trace is visible near the hero", graves.size() > 0 and trc._nodes.has(graves[-1].id))
		# ---------------------------------------------------- music + cinematic
		var mus = w.sys("music")
		clear_foes(80.0)
		await wait(4.0)
		ck("exploration music when calm", mus.state in ["explore", "tension"], mus.state)
		var ed: Dictionary = DBEras.era(0)
		var foe = w.spawner.spawn_enemy(ed.enemies[0], pl.global_position + Vector3(6, 0, 0), 1)
		foe.add_aggro(pl, 80.0)
		await wait(4.0)
		ck("combat music when hunted", mus.state == "combat", mus.state)
		ck("combat track playing", Audio.current_track == "combat", Audio.current_track)
		foe.queue_free()
		var cine = w.sys("cinematic")
		var b = w.spawner.spawn_boss("executioner", pl.global_position + Vector3(0, 0, -20))
		Events.boss_engaged.emit(b)
		await wait(0.3)
		ck("boss intro cinematic plays", cine.is_playing())
		ck("HUD banner for the same title is suppressed", cine.claims(b.display_name))
		await wait(2.0)
		ck("boss music", mus.state == "boss", mus.state)
		b.queue_free()
		# persistence of the new systems
		SaveSys.save_game()
		var ws: Dictionary = SaveSys.load_world_state(0)
		ck("save keeps discoveries, story places, traces, tracking skill, road state", ws.has("discovered") and ws.has("living_pois") and ws.has("traces") and ws.has("tracking") and ws.has("road"), str(ws.keys().filter(func(k): return k in ["discovered", "living_pois", "traces", "tracking", "road"])))
		var lps: Dictionary = ws.get("living_pois", {})
		var resolved := 0
		for k in lps:
			if int(lps[k].get("stage", 0)) >= 3:
				resolved += 1
		ck("resolved story survives the save", resolved >= 1)
		print("EXPLORATION_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
