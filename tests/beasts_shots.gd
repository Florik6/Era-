extends Node
## Screenshots for «Beasts of the Ages» (run under xvfb with a renderer):
## the Black Stone caves, the hidden wall, Гармон awakening and in phase 2,
## creature line-ups for every era and a boss gallery.
## Prints BEASTS_SHOTS_DONE shots=N.

func _ready() -> void:
	seed(5151)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Ратибор", "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 1, "cloth": 1})
	Profile.world_seed = 20261127
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var dir := ""
	var n := 0
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func shot(nm: String) -> void:
		if DisplayServer.get_name() == "headless":
			return
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/" + nm + ".png")
		n += 1
		print("SHOT ", nm)
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		dir = OS.get_environment("SHOTS_DIR")
		if dir == "":
			dir = "user://beasts_shots"
		DirAccess.make_dir_recursive_absolute(dir)
		_run()
	func tp(p: Vector3) -> void:
		Game.world._teleport(Game.player, p)
	func face(a: Vector3) -> void:
		var pl = Game.player
		var to: Vector3 = a - pl.global_position
		to.y = 0
		if to.length() > 0.1:
			pl.face_dir(to.normalized())
	func _run() -> void:
		await wait(3.5)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		# --- the caves
		var d: BeastDungeon = w.enter_dungeon("black_stone")
		await wait(1.5)
		var hall: Dictionary = d.rooms[d.order[1]]
		tp(hall.pos + Vector3(0, 0.4, hall.size * 0.4))
		await wait(1.5)
		face(hall.pos)
		await wait(0.6)
		await shot("bs_01_cave_hall")
		if d.secret_wall != null and is_instance_valid(d.secret_wall):
			tp(d.secret_wall.global_position + Vector3(0, 0.4, 3.0))
			face(d.secret_wall.global_position)
			await wait(0.8)
			await shot("bs_02_hidden_wall")
		var br: Dictionary = d.rooms[d.order[d.order.size() - 1]]
		tp(br.pos + Vector3(0, 0.4, br.size * 0.35))
		await wait(0.9)
		var b = d.boss
		if b:
			face(b.global_position)
			await wait(0.3)
			await shot("bs_03_garmon_awakens")
			await wait(4.0)
			await shot("bs_04_garmon_phase1")
			b.statuses.erase("invuln")
			b.hp = b.max_hp * 0.45
			await wait(3.0)
			face(b.global_position)
			await shot("bs_05_garmon_phase2_cracks")
			await wait(3.0)
			await shot("bs_06_cave_collapse")
			b.statuses.erase("invuln")
			Combat.deal(pl, b, {"amount": b.hp + 99999.0, "dtype": "blunt", "src": pl})
			await wait(2.0)
			await shot("bs_07_victory")
		d.finish_and_leave()
		await wait(7.0)
		# --- the bestiary (journal): bosses tab with Гармон, creatures tab
		var js = w.ui.open("journal")
		await wait(0.5)
		if js != null:
			js.set("_best_sel", "garmon")
			js.refresh()
			js._tabs.current_tab = 4
			await wait(0.6)
			await shot("bestiary_boss_garmon")
			var known_sp := "stone_slime"
			for cd2 in DBCreatures.of_era(0):
				if BeastWorld.knowledge(cd2.id) > 0:
					known_sp = cd2.id
					break
			js.set("_best_sel", known_sp)
			js.refresh()
			js._tabs.current_tab = 3
			await wait(0.6)
			await shot("bestiary_creature")
		w.ui.close_all()
		get_tree().paused = false
		await wait(0.5)
		# --- creature line-ups (one picture per era), out in the wild
		var wild := Vector3.ZERO
		for i in 400:
			var c := Vector3(randf_range(-700, 700), 0, randf_range(-700, 700))
			if w.gen.settlement_at(c.x, c.z, 2.5) == null and not w.gen.is_water(c.x, c.z) and w.gen.biome(c.x, c.z) in ["plains", "forest"]:
				wild = c
				break
		w.terrain.force_load_around(wild)
		wild.y = w.ground_height(wild) + 0.4
		tp(wild)
		await wait(2.0)
		var base: Vector3 = pl.global_position + Vector3(0, 0, -3)
		for e in 5:
			var mobs: Array = []
			var i := 0
			for cd in DBCreatures.of_era(e):
				if i >= 10:
					break
				var an := PI + float(i) / 10.0 * TAU
				var p: Vector3 = base + Vector3(0, 0, 3.5) + Vector3(sin(an), 0, cos(an)) * (4.2 if i % 2 == 0 else 5.6)
				p.y = w.ground_height(p) + 0.3
				var m = w.spawner.spawn_enemy(cd.id, p, 3)
				if m:
					m.apply_status("stun", 999.0)
					m.apply_status("invuln", 999.0)
					m.face_dir(Vector3(0, 0, 1))
					mobs.append(m)
				i += 1
			tp(base + Vector3(0, 0.4, 3.5))
			face(base + Vector3(0, 0, -2))
			await wait(1.4)
			await shot("creatures_era%d" % e)
			for m in mobs:
				if is_instance_valid(m):
					m.queue_free()
			await wait(0.3)
		# --- boss gallery (two per era)
		for e in 5:
			var bl: Array = DBBeasts.bosses_of_era(e)
			for j in [0, bl.size() - 1]:
				var bp: Vector3 = base + Vector3(0, 0.5, -4)
				bp.y = w.ground_height(bp) + 0.5
				var bb = w.spawner.spawn_boss(bl[j].id, bp, 10)
				if bb == null:
					continue
				bb.brain.dormant = 999.0
				bb.apply_status("invuln", 999.0)
				Settings.camera_zoom = 0.6
				tp(bp + Vector3(0, -0.1, 4.0 + float(bl[j].get("scale", 2.0)) * 1.8))
				w.cam.cine_focus = bp + Vector3(0, 1.0, 0)
				face(bp)
				await wait(1.2)
				await shot("boss_%s" % bl[j].id)
				w.cam.cine_focus = null
				bb.queue_free()
				await wait(0.3)
		# --- a boss shield dome (fixed shield state machine): full, then damaged
		var sb = null
		for bid4 in DBBeasts.bosses():
			var bd4: Dictionary = DBBeasts.boss(bid4)
			for ab4 in bd4.abilities:
				if bd4.abilities[ab4].type == "shield" and sb == null:
					var bp4: Vector3 = base + Vector3(0, 0.5, -4)
					bp4.y = w.ground_height(bp4) + 0.5
					sb = w.spawner.spawn_boss(bid4, bp4, 10)
					sb.brain.dormant = 999.0
					sb.shield.start(bd4.abilities[ab4])
		if sb != null:
			Settings.camera_zoom = 0.8
			tp(sb.global_position + Vector3(0, -0.1, 9.0))
			w.cam.cine_focus = sb.global_position + Vector3(0, 1.0, 0)
			face(sb.global_position)
			await wait(2.6)
			await shot("shield_dome_full")
			sb.shield.hit_pool(sb.shield.pool_max * 0.7)
			await wait(0.4)
			await shot("shield_dome_critical")
			w.cam.cine_focus = null
			sb.queue_free()
		print("BEASTS_SHOTS_DONE shots=%d" % n)
		get_tree().quit()
