extends Node
## City combat benchmark (same scenario before and after optimisation).
## Run under xvfb so rendering statistics exist:
##   BENCH_OUT=/path/out.json xvfb-run -a godot --path . --resolution 1280x720 tests/city_bench.tscn
## Phases in the capital: empty city → walking → 24 NPCs appear → mass
## battle → magic exchange → large magical explosions.
## Per phase: CPU process/physics time per frame (avg/p95/max), subsystem
## CPU time (AI, rigs, actor physics), draw calls, objects and primitives
## in frame, node/actor counts, live particle emitters and lights,
## active physics bodies. Software rendering in the container means real
## FPS/GPU time are NOT meaningful here — compare CPU times and counts.

func _ready() -> void:
	seed(424242)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Замер", "mage", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = 0
	Settings.cinematics = 0
	Settings.combat_fx = 2
	Settings.quality = Settings.Quality.MEDIUM
	match OS.get_environment("BENCH_Q"):
		"low":
			Settings.quality = Settings.Quality.LOW
		"high":
			Settings.quality = Settings.Quality.HIGH
		"max":
			Settings.quality = Settings.Quality.MAX
	Settings.effective_quality = Settings.quality
	if "dynamic_quality" in Settings:
		Settings.set("dynamic_quality", OS.get_environment("BENCH_DCQ") == "1")
	var h := Harness.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Harness:
	extends Node
	var results := {}
	var order: Array = []
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout

	func _count(n: Node, out: Dictionary) -> void:
		if n is CPUParticles3D:
			if (n as CPUParticles3D).emitting and n.is_visible_in_tree():
				out.particles += 1
				out.particle_amount += (n as CPUParticles3D).amount
		elif n is GPUParticles3D:
			if (n as GPUParticles3D).emitting and n.is_visible_in_tree():
				out.particles += 1
				out.particle_amount += (n as GPUParticles3D).amount
		elif n is OmniLight3D or n is SpotLight3D:
			if n.is_visible_in_tree() and (n as Light3D).light_energy > 0.01:
				out.lights += 1
				if (n as Light3D).shadow_enabled:
					out.shadow_lights += 1
		for c in n.get_children():
			_count(c, out)

	func measure(nm: String, secs: float, driver: Callable = Callable()) -> void:
		var proc: Array = []
		var phys: Array = []
		var frame: Array = []
		var draws: Array = []
		var objs: Array = []
		var prims: Array = []
		var sub := {}
		var snaps: Array = []
		Perf.take()
		var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
		var next_snap := Time.get_ticks_msec() + 1000
		var last := Time.get_ticks_usec()
		var skip := false
		while Time.get_ticks_msec() < t_end:
			if driver.is_valid():
				driver.call()
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1000.0
			last = now
			var pk := Perf.take()
			if skip:
				skip = false
				continue
			proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			frame.append(dt)
			draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			objs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			for k in pk:
				if not sub.has(k):
					sub[k] = []
				sub[k].append(pk[k] / 1000.0)
			if Time.get_ticks_msec() >= next_snap:
				next_snap += 1500
				var c := {"particles": 0, "particle_amount": 0, "lights": 0, "shadow_lights": 0}
				_count(get_tree().root, c)
				c["nodes"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
				c["actors"] = Game.actors.size()
				c["phys_active"] = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
				snaps.append(c)
				skip = true   # the tree walk itself must not pollute the next sample
		var r := {"frames": proc.size(), "process_ms": _stats(proc), "physics_ms": _stats(phys), "frame_ms": _stats(frame),
			"draw_calls": _stats(draws), "objects": _stats(objs), "primitives": _stats(prims), "sub_ms": {}}
		for k in sub:
			r.sub_ms[k] = _stats(sub[k])
		var mx := {}
		for c in snaps:
			for k in c:
				mx[k] = maxf(float(mx.get(k, 0)), float(c[k]))
		r["peak"] = mx
		results[nm] = r
		order.append(nm)
		print("BENCH %-10s proc %.2f/%.2f  phys %.2f/%.2f  ai %.2f rig %.2f aphys %.2f  draws %.0f  objs %.0f  parts %s lights %s actors %s nodes %s" % [nm,
			r.process_ms.avg, r.process_ms.p95, r.physics_ms.avg, r.physics_ms.p95,
			r.sub_ms.get("ai", {}).get("avg", 0.0), r.sub_ms.get("rig", {}).get("avg", 0.0), r.sub_ms.get("actor_phys", {}).get("avg", 0.0),
			r.draw_calls.avg, r.objects.avg, mx.get("particles", 0), mx.get("lights", 0), mx.get("actors", 0), mx.get("nodes", 0)])

	func _stats(a: Array) -> Dictionary:
		if a.is_empty():
			return {"avg": 0.0, "p95": 0.0, "max": 0.0}
		var b := a.duplicate()
		b.sort()
		var s := 0.0
		for v in b:
			s += float(v)
		return {"avg": snappedf(s / b.size(), 0.01), "p95": snappedf(float(b[int(b.size() * 0.95) - 1 if b.size() > 1 else 0]), 0.01), "max": snappedf(float(b[-1]), 0.01)}

	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		w.director.set_process(false)
		if w.sys("road_encounters"):
			w.sys("road_encounters").set_process(false)
		Game.game_time = floor(Game.game_time) + 0.5
		w.weather.set_weather("clear", 9999.0)
		Perf.enabled = true
		# capital
		var cap: Dictionary = w.gen.settlements[0]
		for s in w.gen.settlements:
			if s.get("kind", "") == "city" or float(s.get("radius", 0)) > float(cap.get("radius", 0)):
				cap = s
		var c3 := Vector3(cap.pos.x, 0, cap.pos.y)
		w.terrain.force_load_around(c3)
		c3.y = w.ground_height(c3) + 0.3
		w._teleport(pl, c3)
		await wait(4.0)
		print("BENCH city=", cap.name, " radius=", cap.get("radius", 0))
		# 1 empty city (villagers only)
		await measure("empty", 6.0)
		# 2 walking around the square
		var t0 := Time.get_ticks_msec()
		await measure("walk", 6.0, func():
			var a := (Time.get_ticks_msec() - t0) / 1000.0 * 0.6
			pl.scripted_move = Vector3(cos(a), 0, sin(a)))
		pl.scripted_move = Vector3.ZERO
		# 3 NPCs appear (bots of two factions, wandering)
		var facs: Array = DBEras.factions_of(0)
		var bots: Array = []
		for i in 24:
			var rec: Dictionary = w.legends.new_record("Боец %d" % i, {"level": 4, "faction": facs[i % 2]})
			var a2 := TAU * i / 24.0
			var b = w.spawner.spawn_bot(rec, c3 + Vector3(cos(a2), 0, sin(a2)) * randf_range(8.0, 22.0))
			if b:
				b.faction_id = facs[i % 2]
				bots.append(b)
		await measure("npcs", 6.0)
		# 4 mass battle: bandits storm the square, factions fight each other
		var ed: Dictionary = DBEras.era(0)
		var raiders: Array = []
		for i in 14:
			var a3 := TAU * i / 14.0
			var e = w.spawner.spawn_enemy(["bandit", "deserter", "mercenary", "knight_renegade"][i % 4], c3 + Vector3(cos(a3), 0, sin(a3)) * 16.0, 3)
			if e:
				raiders.append(e)
		for i in bots.size():
			var b2 = bots[i]
			if is_instance_valid(b2):
				var tgt = raiders[i % raiders.size()] if not raiders.is_empty() else null
				if tgt and is_instance_valid(tgt):
					b2.add_aggro(tgt, 60.0)
					tgt.add_aggro(b2, 60.0)
		await measure("battle", 10.0)
		# 5 magic exchange: hostile mages + the hero casting
		for i in 6:
			var a4 := TAU * i / 6.0
			var m = w.spawner.spawn_enemy("dark_mage", c3 + Vector3(cos(a4), 0, sin(a4)) * 12.0, 3)
			if m:
				m.add_aggro(bots[i % bots.size()] if not bots.is_empty() and is_instance_valid(bots[i % bots.size()]) else pl, 60.0)
		for sc in ["fire", "ice", "lightning", "dark", "spacetime"]:
			pl.data.learn_school(sc)
			pl.data.schools[sc].lvl = 10
		pl.max_mana = 99999.0
		var spells := ["fireball", "frostbolt", "chain", "spark", "drain", "firewall", "thunderclap"]
		var si := [0]
		var next_cast := [0]
		await measure("magic", 8.0, func():
			if Time.get_ticks_msec() >= next_cast[0]:
				next_cast[0] = Time.get_ticks_msec() + 450
				pl.mana = pl.max_mana
				pl.skill_cd.clear()
				pl.act = {}
				Spells.cast(pl, spells[si[0] % spells.size()], Vector3(cos(si[0] * 0.9), 0, sin(si[0] * 0.9)))
				si[0] += 1)
		# 6 large magical explosions (ultimates)
		var ults := ["meteor", "nova", "storm", "blizzard", "meteor", "nova"]
		var ui := [0]
		var next_u := [0]
		await measure("explosion", 8.0, func():
			if Time.get_ticks_msec() >= next_u[0] and ui[0] < ults.size():
				next_u[0] = Time.get_ticks_msec() + 1300
				pl.mana = pl.max_mana
				pl.skill_cd.clear()
				pl.act = {}
				Spells.cast(pl, ults[ui[0]], Vector3(cos(ui[0] * 1.3), 0, sin(ui[0] * 1.3)))
				ui[0] += 1)
		# 7 magical resonance: the storm covens duel on the square while
		#   reactions chain around it (resonance zones, catastrophe, rift)
		if OS.get_environment("BENCH_EXTRA") != "0":
			var res = w.sys("resonance")
			if res:
				res.cata_ready_at = 0.0
			w.director.set_process(true)
			w.director._t = -100000.0
			w.director.start_black_storm(c3 + Vector3(0, 0, 10), {"arena": true, "dur": 60.0})
			var rk := [0]
			var next_r := [0]
			var rpairs := [["fire", "ice"], ["dark", "fire"], ["lightning", "space"], ["time", "time"]]
			await measure("resonance", 10.0, func():
				if Time.get_ticks_msec() >= next_r[0]:
					next_r[0] = Time.get_ticks_msec() + 700
					var pr: Array = rpairs[rk[0] % 4]
					var pp: Vector3 = c3 + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
					Resonance.imprint(pr[0], pp, 40.0, "empowered", null)
					Resonance.imprint(pr[1], pp, 40.0, "empowered", null)
					rk[0] += 1)
			if res:
				results["resonance"]["resonance_stats"] = {"reactions": res.stats.reactions, "catastrophes": res.stats.catastrophes, "blocked_limit": res.stats.blocked_limit, "blocked_cd": res.stats.blocked_cd}
			# 8 a boss fights in the city and goes through its phases
			var bosses: Array = DBEras.era(0).bosses
			var boss = w.spawner.spawn_boss(bosses[0], c3 + Vector3(6, 0, 6), 5)
			if boss:
				for b3 in bots:
					if is_instance_valid(b3) and not b3.is_dead:
						b3.add_aggro(boss, 60.0)
						boss.add_aggro(b3, 60.0)
			await measure("boss", 10.0, func():
				if is_instance_valid(boss) and not boss.is_dead:
					boss.hp = maxf(boss.max_hp * 0.08, boss.hp - boss.max_hp * 0.004)
					if boss.get("brain") != null and boss.brain.has_method("_check_phase"):
						boss.brain._check_phase())
		var out := OS.get_environment("BENCH_OUT")
		if out != "":
			var f := FileAccess.open(out, FileAccess.WRITE)
			f.store_string(JSON.stringify({"order": order, "results": results, "dcq": Settings.get("dynamic_quality")}, "  "))
			f.close()
		print("CITY_BENCH_DONE")
		get_tree().quit()
