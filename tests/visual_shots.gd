extends Node
## Control screenshots for the visual overhaul (run under xvfb + lavapipe):
## day forest, road between settlements, village, night, blood moon, fog,
## sword fight, magic fight, boss, legendary loot, rift, story place,
## altar screen, ritual, layout editor. SHOTS_DIR selects the output folder.

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Арден", OS.get_environment("SHOT_CLASS") if OS.get_environment("SHOT_CLASS") != "" else "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 1, "cloth": 2})
	Profile.current_era = int(OS.get_environment("SHOT_ERA")) if OS.get_environment("SHOT_ERA") != "" else 0
	Settings.cinematics = 1
	Settings.show_fps = true
	var h := Harness.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Harness:
	extends Node
	var dir := ""
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		dir = OS.get_environment("SHOTS_DIR")
		if dir == "":
			dir = "user://shots"
		DirAccess.make_dir_recursive_absolute(dir)
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	func shot(nm: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir + "/" + nm + ".png")
		print("SHOT ", nm, " fps=", Engine.get_frames_per_second(), " draws=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	func go(p: Vector3, settle := 2.0) -> void:
		var w = Game.world
		w.terrain.force_load_around(p)
		p.y = w.ground_height(p) + 0.3
		w._teleport(Game.player, p)
		await wait(settle)
	func set_hour(h: float) -> void:
		Game.game_time = floor(Game.game_time) + h / 24.0
	func clear_ui() -> void:
		Game.world.ui.close_all()
	func foes_away(r := 40.0) -> void:
		for a in Game.actors_near(Game.player.global_position, r):
			if a != Game.player and Game.is_enemy(Game.player, a):
				a.queue_free()

	func _run() -> void:
		await wait(3.5)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		w.director.set_process(false)
		w.weather.set_weather("clear", 9999.0)
		set_hour(10.0)
		# 1 day forest
		var forest: Vector3 = pl.global_position
		for i in 60:
			var a := TAU * i / 60.0
			var p: Vector3 = pl.global_position + Vector3(cos(a), 0, sin(a)) * (80.0 + i * 6.0)
			var h: float = w.gen.height(p.x, p.z) if w.gen.has_method("height") else 0.0
			if w.gen.biome_at(p.x, p.z, h) in ["forest", "taiga", "jungle", "woods"]:
				forest = p
				break
		await go(forest, 3.0)
		foes_away()
		print("DBG forest player_y=%.2f ground=%.2f cam_y=%.2f" % [pl.global_position.y, w.ground_height(pl.global_position), w.cam.global_position.y])
		await shot("v01_day_forest")
		# 2 road between settlements
		var s0: Dictionary = w.gen.settlements[0]
		var s1: Dictionary = w.gen.settlements[1] if w.gen.settlements.size() > 1 else s0
		var mid: Vector2 = s0.pos.lerp(s1.pos, 0.5)
		if w.gen.has_method("nearest_road_point"):
			mid = w.gen.nearest_road_point(mid)
		await go(Vector3(mid.x, 0, mid.y), 3.0)
		foes_away()
		await shot("v02_road")
		# 3 village (workers at forge/stall)
		await go(Vector3(s0.pos.x + 4, 0, s0.pos.y + 7), 6.0)
		foes_away()
		await shot("v03_village")
		# 4 night
		set_hour(23.0)
		await wait(1.5)
		await shot("v04_night")
		# 5 blood moon
		w.director._start("blood_moon", pl.global_position)
		await wait(4.0)
		await shot("v05_blood_moon")
		for e in w.director.active_events().duplicate():
			w.director._end(e, "test")
		w.day_night.set_override("blood_moon", false)
		# 6 fog (standard setting, daytime)
		set_hour(8.0)
		w.weather.set_weather("fog", 9999.0)
		await wait(4.0)
		await shot("v06_fog")
		w.weather.set_weather("clear", 9999.0)
		set_hour(15.0)
		await wait(2.0)
		# 7 sword fight
		await go(forest + Vector3(20, 0, 10), 2.0)
		var ed: Dictionary = DBEras.era(Profile.current_era)
		var foes: Array = []
		for i in 3:
			var e = w.spawner.spawn_enemy(ed.enemies[i % ed.enemies.size()], pl.global_position + Vector3(2.5 + i, 0, -1.5 + i), 1)
			if e:
				e.add_aggro(pl, 50.0)
				foes.append(e)
		for k in 6:
			if not foes.is_empty() and is_instance_valid(foes[0]):
				pl.facing = (foes[0].global_position - pl.global_position).normalized()
			pl.attack(pl.facing)
			await wait(0.3)
		await shot("v07_sword_fight")
		# 8 magic fight
		for sc in ["fire", "ice", "lightning"]:
			pl.data.learn_school(sc)
		for sp in ["fireball", "frostbolt", "chain"]:
			if DBSkills.spell(sp).is_empty():
				continue
			pl.mana = pl.max_mana
			var aim: Vector3 = (foes[0].global_position - pl.global_position).normalized() if not foes.is_empty() and is_instance_valid(foes[0]) else pl.facing
			Spells.cast_free(pl, sp, aim, 1.0)
			await wait(0.35)
		await wait(0.2)
		await shot("v08_magic_fight")
		for e in foes:
			if is_instance_valid(e):
				e.queue_free()
		# 9 boss
		var bid: String = DBEras.era(Profile.current_era).bosses[0]
		var b = w.spawner.spawn_boss(bid, pl.global_position + Vector3(0, 0, -9))
		if b:
			b.add_aggro(pl, 80.0)
			Events.boss_engaged.emit(b)
		await wait(3.0)
		await shot("v09_boss")
		if b and is_instance_valid(b):
			b.queue_free()
		await wait(0.5)
		# 10 legendary loot
		for r in [3, 4, 5]:
			var it := ItemDB.random_for_era(Profile.current_era, pl.level, "boss", 0.5)
			it.rarity = r
			w.loot.spawn_drop(it, pl.global_position + Vector3(-2.5 + r - 3, 0, -2.5))
		await wait(2.0)
		await shot("v10_legendary_loot")
		# 11 rift
		w.portal_block_until = 0
		w.enter_dimension(["warped_medieval", "mechanical", "chronos", "future_rift", "future_rift"][clampi(Profile.current_era, 0, 4)], {"expedition": true})
		await wait(3.0)
		await shot("v11_rift")
		w.leave_dimension(false)
		await wait(2.0)
		# 12 story place
		var lp = w.sys("living_pois")
		if lp and lp.sites.size() > 0:
			var st: Dictionary = lp.sites[0]
			await go(Vector3(st.pos.x + 9, 0, st.pos.y + 9), 3.0)
			await shot("v12_story_place")
		# 13-14 altar screen + ritual
		var altars: Array = w.gen.pois.filter(func(p): return p.type == "altar")
		if not altars.is_empty():
			await go(Vector3(altars[0].pos.x + 2.2, 0, altars[0].pos.y), 2.5)
			foes_away(60.0)
			var sw := ItemDB.create("sword_steel", 4, pl.level, null, false)
			sw.curse = {"id": "drain", "bound": true, "hidden": false, "release": "ritual"}
			pl.data.inv.add(sw)
			pl.equip_item(sw)
			for k in ["purify_salt", "spirit_essence", "chrono_shard"]:
				var m := ItemDB.create(k, 0, 1)
				m.qty = 5
				pl.data.inv.add(m)
			pl.data.gold = 2000
			await wait(0.5)
			if pl.interact_target:
				pl.do_interact()
			await wait(0.6)
			await shot("v13_altar_ui")
			var scr = w.ui.get_screen("altar")
			if scr:
				scr.start_ritual(sw.uid, "break_bond")
			await wait(2.1)
			await shot("v14_ritual")
			await wait(3.0)
		clear_ui()
		# 15 layout editor
		w.ui.open("layout_editor")
		await wait(0.6)
		await shot("v15_layout_editor")
		clear_ui()
		print("VISUAL_SHOTS_DONE")
		get_tree().quit()
