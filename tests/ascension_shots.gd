extends Node
## Screenshots of the Visual Ascension systems (run under xvfb; SHOTS_DIR =
## output): resonance reactions, catastrophe, the storm over the capital,
## wet roads and snow, era grading, a historical echo, special weapons and
## the graphics settings screen.

func _ready() -> void:
	seed(9090)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Арден", "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 1, "cloth": 2})
	Profile.world_seed = 777001
	Profile.current_era = int(OS.get_environment("SHOT_ERA")) if OS.get_environment("SHOT_ERA") != "" else 0
	Settings.quality = Settings.Quality.HIGH
	Settings.effective_quality = Settings.Quality.HIGH
	Settings.cinematics = 0
	var h := Harness.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Harness:
	extends Node
	var dir := ""
	var part := ""
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		dir = OS.get_environment("SHOTS_DIR")
		part = OS.get_environment("SHOT_PART")
		if dir == "":
			dir = "user://shots"
		DirAccess.make_dir_recursive_absolute(dir)
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	func frames(n: int) -> void:
		for i in n:
			await get_tree().physics_frame
	func shot(nm: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/" + nm + ".png")
		print("SHOT ", nm)
	func open_spot() -> void:
		var w = Game.world
		var pl = Game.player
		var space = pl.get_world_3d().direct_space_state
		for tries in 80:
			var a := randf() * TAU
			var p: Vector3 = pl.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(30.0, 160.0)
			w.terrain.force_load_around(p)
			p.y = w.ground_height(p) + 0.3
			if w.is_water(p):
				continue
			var clear := true
			for k in 8:
				var d := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + d * 12.0, 1)
				q.exclude = [pl.get_rid()]
				if not space.intersect_ray(q).is_empty():
					clear = false
					break
			if clear:
				w._teleport(pl, p)
				await frames(4)
				return
	func _run() -> void:
		await wait(3.5)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		w.director._t = -100000.0
		w.day_night.time_override = 15.0
		w.weather.auto_cycle = false
		w.weather.set_weather("clear", 9999.0)
		var res = w.sys("resonance")
		if part == "" or part == "grade":
			await open_spot()
			await wait(2.0)
			await shot("va_era%d_grade" % Profile.current_era)
			if part == "grade":
				get_tree().quit()
				return
		# --- resonance reactions, one per pair
		await open_spot()
		var c: Vector3 = pl.global_position + pl.facing * 7.0
		c.y = w.ground_height(c)
		for pr in [["fire", "ice", "steam"], ["dark", "fire", "vortex"], ["lightning", "space", "node"], ["time", "time", "instability"]]:
			res.reset()
			res.clock += 10.0
			Resonance.imprint(pr[0], c, 45.0, "empowered", pl)
			Resonance.imprint(pr[1], c, 45.0, "empowered", null)
			await wait(0.35)
			await shot("va_res_%s" % pr[2])
			await wait(1.2)
			for z in res.active:
				if is_instance_valid(z):
					z.queue_free()
		# --- catastrophe
		res.reset()
		w.director.resonance_rift_chance = 1.0
		Resonance.imprint("fire", c, 90.0, "ultimate", pl)
		Resonance.imprint("ice", c, 40.0, "empowered", null)
		await wait(0.7)
		await shot("va_catastrophe")
		await wait(8.5)
		await shot("va_catastrophe_rift")
		for ev in w.director.events.duplicate():
			if ev.type == "resonance":
				ev.t = ev.dur
				w.director._tick_event(ev, 0.1)
		# --- clash
		var a = w.spawner.spawn_bot(w.legends.new_record("Рыцарь", {"level": 6, "class_id": "warrior"}), c + Vector3(-1.0, 0, 0))
		var b = w.spawner.spawn_bot(w.legends.new_record("Наёмник", {"level": 6, "class_id": "warrior"}), c + Vector3(1.0, 0, 0))
		for x in [a, b]:
			var it := ItemDB.create("hammer_war", 0, 6, null, false)
			x.data.inv.add(it)
			x.data.inv.equip_item(it)
			x.refresh_gear()
			x.brain = null
		await frames(3)
		a.global_position = c + Vector3(-1.0, 0, 0)
		b.global_position = c + Vector3(1.0, 0, 0)
		a.face_dir(Vector3.RIGHT)
		b.face_dir(Vector3.LEFT)
		a.add_aggro(b, 600.0)
		b.add_aggro(a, 600.0)
		a.start_action("melee", 0.6, 0.5, {"anim": "overhead", "finisher": true})
		b.start_action("melee", 0.6, 0.5, {"anim": "overhead", "finisher": true})
		await wait(0.33)
		await shot("va_clash")
		a.queue_free()
		b.queue_free()
		# --- special weapons on the hero
		for kind in ["legendary", "mythic", "cursed", "living"]:
			var bases := {"legendary": "sword_steel", "mythic": "sword_steel", "cursed": "sword_steel", "living": "sword_steel"}
			var it2 := ItemDB.create(bases[kind], 4 if kind == "legendary" else (5 if kind == "mythic" else 2), 8, null, false)
			if kind == "cursed":
				it2.curse = {"id": "bloodthirst", "bound": true}
			if kind == "living":
				it2.living = {"stage": 2, "xp": 0, "path": "dusk"}
			if kind == "mythic":
				it2.mythic = "chrono_rewind"
			pl.data.inv.add(it2)
			pl.data.inv.equip_item(it2)
			pl.refresh_gear()
			await wait(0.6)
			w.cam.base_dist = 4.0
			await wait(0.5)
			await shot("va_weapon_%s" % kind)
			w.cam.base_dist = 10.5
		# --- weather surfaces: wet roads and snow (near a road)
		var road_p: Vector3 = pl.global_position
		if w.gen.has_method("road_path") or w.gen.get("roads") != null:
			for st in w.gen.settlements:
				road_p = Vector3(st.pos.x, 0, st.pos.y)
				break
		w.terrain.force_load_around(road_p)
		await wait(1.0)
		road_p.y = w.ground_height(road_p)
		w._teleport(pl, road_p + Vector3(0, 0.5, 0))
		await wait(2.5)
		w.weather.set_weather("rain", 9999.0)
		w.weather.wetness = 1.0
		await wait(2.0)
		await shot("va_wet_roads")
		w.weather.set_weather("snow", 9999.0)
		w.weather.wetness = 0.0
		w.weather.snow_cover = 1.0
		await wait(2.0)
		await shot("va_snow_cover")
		w.weather.set_weather("clear", 9999.0)
		w.weather.snow_cover = 0.0
		await wait(1.5)
		# --- black storm over the capital
		var cap: Dictionary = w.director.capital()
		var cp := Vector3(cap.pos.x, 0, cap.pos.y)
		w.terrain.force_load_around(cp)
		await wait(1.0)
		cp.y = w.ground_height(cp)
		w._teleport(pl, cp + Vector3(0, 0.5, -14))
		await wait(3.0)
		w.director.start_black_storm()
		await wait(9.0)
		await shot("va_black_storm")
		await wait(6.0)
		await shot("va_black_storm_2")
		# --- historical echo
		var ec = w.sys("echoes")
		var ev := Chronicle.record("boss_kill", [pl], {"pos_v3": pl.global_position + Vector3(2.5, 0, -5), "extra": {"boss": "Палач Чёрной Башни"}})
		Game.game_time += 0.1
		ec._cd = 0.0
		ec.play({"ev": ev})
		await wait(2.4)
		await shot("va_echo")
		# --- settings screen
		w.ui.open("settings")
		await wait(0.8)
		await shot("va_settings")
		print("ASCENSION_SHOTS_DONE")
		get_tree().quit()
