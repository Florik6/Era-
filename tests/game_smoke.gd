extends Node
## End-to-end smoke test: new character → living world → scripted gameplay,
## UI screens, combat, spells, loot, dimension entry, save/load. Saves
## screenshots and prints a summary. Run under xvfb with a GPU driver.

var shots_dir := ""
var mode := "world"

func _ready() -> void:
	shots_dir = OS.get_environment("SHOTS_DIR")
	if shots_dir == "":
		shots_dir = "user://shots"
	DirAccess.make_dir_recursive_absolute(shots_dir)
	mode = OS.get_environment("SMOKE_MODE") if OS.get_environment("SMOKE_MODE") != "" else "world"
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Тестер", OS.get_environment("SMOKE_CLASS") if OS.get_environment("SMOKE_CLASS") != "" else "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.current_era = int(OS.get_environment("SMOKE_ERA")) if OS.get_environment("SMOKE_ERA") != "" else 0
	var h := Harness.new()
	h.shots_dir = shots_dir
	h.mode = mode
	get_tree().root.add_child.call_deferred(h)
	Game.start(mode)

class Harness:
	extends Node
	var shots_dir := ""
	var mode := ""
	var log: Array = []
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	func shot(nm: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shots_dir + "/" + nm + ".png")
		print("SHOT ", nm)
	func _run() -> void:
		await wait(4.0)
		var w = Game.world
		var p = Game.player
		print("WORLD READY mode=", Game.mode, " player=", p != null, " pos=", p.global_position if p else Vector3.ZERO, " actors=", Game.actors.size(), " fps=", Engine.get_frames_per_second())
		await shot("01_spawn")
		# walk around
		var t := 0.0
		while t < 3.0:
			p.scripted_move = Vector3(1, 0, -0.3).normalized()
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		p.scripted_move = Vector3.ZERO
		await shot("02_walk")
		# combat: spawn enemies near and fight
		var era_d: Dictionary = DBEras.era(Profile.current_era)
		var foes: Array = []
		for i in 3:
			var e = w.spawner.spawn_enemy(era_d.enemies[i % era_d.enemies.size()], p.global_position + Vector3(4 + i * 1.5, 0, -3), 1)
			if e:
				foes.append(e)
		print("SPAWNED foes=", foes.size())
		for k in 90:
			var tgt = null
			for f in foes:
				if is_instance_valid(f) and not f.is_dead:
					tgt = f
					break
			if tgt == null:
				break
			var dir: Vector3 = tgt.global_position - p.global_position
			dir.y = 0
			p.scripted_move = dir.normalized() if dir.length() > 1.8 else Vector3.ZERO
			p.attack(dir.normalized())
			if k % 20 == 5:
				p.use_slot(0, dir.normalized())
			if k == 10:
				await shot("03_combat")
			p.hp = p.max_hp
			await wait(0.1)
		p.scripted_move = Vector3.ZERO
		var dead := 0
		for f in foes:
			if not is_instance_valid(f) or f.is_dead:
				dead += 1
		print("COMBAT foes_dead=", dead, "/", foes.size(), " player_lvl=", p.data.level, " kills=", p.data.kills, " mastery_sword=", p.data.mastery_level(p.weapon_cat()))
		await wait(1.0)
		await shot("04_after_combat")
		# magic
		p.data.learn_school("fire")
		p.data.learn_school("lightning")
		p.data.schools.fire.lvl = 8
		p.mana = p.max_mana
		var ok1: bool = Spells.cast(p, "fireball", p.facing)
		await wait(0.6)
		var ok2: bool = Spells.cast(p, "firewall", p.facing)
		await wait(0.3)
		await shot("05_magic")
		print("MAGIC fireball=", ok1, " firewall=", ok2, " mana=", p.mana)
		# loot visuals
		for r in [3, 4, 5]:
			w.loot.spawn_drop(ItemDB.random_for_era(Profile.current_era, 5, ["normal", "elite", "boss"][r - 3]) if r < 5 else ItemDB.create_unique("u_archon_blade", 5), p.global_position + Vector3(r - 4, 0, 3))
		var leg := ItemDB.create("sword_steel", 4, 3)
		w.loot.spawn_drop(leg, p.global_position + Vector3(2, 0, 2))
		var my := ItemDB.create("staff_oak", 5, 3)
		w.loot.spawn_drop(my, p.global_position + Vector3(-2, 0, 2))
		await wait(0.8)
		await shot("06_loot")
		# UI screens
		for nm in ["inventory", "skills", "factions", "journal", "map", "legends", "chronicle", "pause"]:
			w.ui.open(nm)
			await wait(0.4)
			await shot("ui_" + nm)
			w.ui.close_all()
			await wait(0.1)
		print("UI paused_after_close=", get_tree().paused)
		# night + weather
		Game.game_time = float(int(Game.game_time)) + 0.95
		if w.weather and w.weather.has_method("set_weather"):
			w.weather.set_weather("rain", 30.0)
		await wait(2.5)
		await shot("07_night_rain")
		Game.game_time = float(int(Game.game_time)) + 1.5
		if w.weather and w.weather.has_method("set_weather"):
			w.weather.set_weather("fog", 30.0)
		await wait(2.5)
		await shot("08_day_fog")
		# boss
		var bid: String = era_d.bosses[0]
		var b = w.spawner.spawn_boss(bid, p.global_position + Vector3(0, 0, -9), 3)
		await wait(2.0)
		await shot("09_boss")
		for k in 30:
			if not is_instance_valid(b) or b.is_dead:
				break
			p.hp = p.max_hp
			p.attack((b.global_position - p.global_position).normalized())
			await wait(0.1)
		if is_instance_valid(b):
			b.hp = b.max_hp * 0.5
			await wait(1.5)
			await shot("10_boss_phase")
			b.queue_free()
		# rift
		w.enter_dimension("mechanical", {"expedition": true})
		await wait(2.5)
		await shot("11_rift")
		print("DIMENSION ", w.dimension, " objective=", w.objective_text())
		w.leave_dimension(false)
		await wait(1.0)
		# bots / legends
		print("RECORDS ", w.legends.recs.size(), " active_npcs=", w.sim.active.size(), " chronicle=", Chronicle.events.size(), " settlements=", w.gen.settlements.size() if w.gen else 0, " pois=", w.gen.pois.size() if w.gen else 0)
		# save/load
		var sok: bool = SaveSys.save_game()
		var d := SaveSys.read_json(SaveSys.PROFILE)
		print("SAVE ok=", sok, " profile_keys=", d.size(), " world_file=", FileAccess.file_exists(SaveSys.WORLD_FMT % Profile.current_era))
		await wait(1.0)
		await shot("12_end")
		print("FPS ", Engine.get_frames_per_second(), " actors=", Game.actors.size())
		print("SMOKE_DONE")
		get_tree().quit()
