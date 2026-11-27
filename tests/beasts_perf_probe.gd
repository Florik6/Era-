extends Node
## Performance probe for «Beasts of the Ages» (headless: CPU times and counts,
## not real phone FPS). Phases: open world baseline → ecology around the
## hero → inside the Black Stone caves (all rooms entered) → boss fight →
## back outside. Per phase: mean / p95 process time per frame (ms), node
## count, live actors, ecology creatures. Prints BEASTS_PERF_DONE.

func _ready() -> void:
	seed(99)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Замер", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 20261127
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var samples: Array = []
	var sampling := false
	func rwait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func _process(_d: float) -> void:
		if sampling:
			samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	func phase(nm: String, secs: float) -> void:
		samples.clear()
		sampling = true
		await rwait(secs)
		sampling = false
		var s := samples.duplicate()
		s.sort()
		var mean := 0.0
		for v in s:
			mean += float(v)
		mean /= maxf(1.0, float(s.size()))
		var p95: float = float(s[int(s.size() * 0.95)]) if not s.is_empty() else 0.0
		var bw: BeastWorld = BeastWorld.inst
		print("PERF %-22s frames=%4d  cpu_mean=%6.2f ms  cpu_p95=%6.2f ms  nodes=%5d  actors=%3d  eco=%2d" % [nm, s.size(), mean, p95,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), Game.actors.size(), bw.live_eco().size() if bw else -1])
	func _run() -> void:
		await rwait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		await phase("world_baseline", 6.0)
		var p := Vector3.ZERO
		for i in 400:
			var c := Vector3(randf_range(-800, 800), 0, randf_range(-800, 800))
			if w.gen.settlement_at(c.x, c.z, 2.5) == null and not w.gen.is_water(c.x, c.z) and w.gen.biome(c.x, c.z) == "forest":
				p = c
				break
		w.terrain.force_load_around(p)
		p.y = w.ground_height(p) + 0.4
		w._teleport(pl, p)
		await rwait(2.0)
		for i in 4:
			BeastWorld.inst.spawn_ecology_near(pl.global_position)
		await phase("world_ecology", 10.0)
		var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var d: BeastDungeon = w.enter_dungeon("black_stone")
		await rwait(1.0)
		await phase("dungeon_start", 5.0)
		for i in range(1, d.order.size() - 1):
			w._teleport(pl, d.rooms[d.order[i]].pos + Vector3(0, 0.4, 0))
			await rwait(0.6)
		await phase("dungeon_rooms_spawned", 8.0)
		var br: Dictionary = d.rooms[d.order[d.order.size() - 1]]
		w._teleport(pl, br.pos + Vector3(0, 0.4, br.size * 0.3))
		await rwait(2.0)
		await phase("boss_fight_phase1", 10.0)
		if d.boss and is_instance_valid(d.boss):
			d.boss.statuses.erase("invuln")
			d.boss.hp = d.boss.max_hp * 0.45
		await rwait(1.5)
		await phase("boss_fight_phase2", 10.0)
		print("PERF dungeon rooms=%d  static_bodies=%d  traps=%d  rubble_live=%d" % [d.rooms.size(), _count_bodies(d), d.stats.traps, StoneStructure.count_live()])
		d.finish_and_leave()
		await rwait(2.0)
		var dungeons_alive := 0
		for c in w.get_children():
			if c is BeastDungeon:
				dungeons_alive += 1
		print("PERF memory: nodes before entering=%d  after leaving=%d  dungeon nodes alive=%d  static_mem=%.1f MB" % [nodes_before,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), dungeons_alive, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
		await phase("world_after", 6.0)
		print("BEASTS_PERF_DONE")
		get_tree().quit()
	func _count_bodies(n: Node) -> int:
		var c := 1 if n is StaticBody3D else 0
		for ch in n.get_children():
			c += _count_bodies(ch)
		return c
