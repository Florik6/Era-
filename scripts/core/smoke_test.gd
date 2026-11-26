class_name SmokeTest
extends Node
## Platform smoke test, started only with the command-line flag --smoke-test
## (the iOS-simulator CI job launches the app with it; on desktop:
## `godot --path . -- --smoke-test`). Never runs in normal play.
##
## Waits for the main menu, creates a fresh character, loads the world,
## measures frame rate, casts spells against a spawned enemy, saves, reloads
## the profile from disk and writes the result to user://smoke_result.json
## (also printed as one "SMOKE_RESULT {...}" line). The game keeps running
## afterwards so a screenshot can be taken.

var res := {}
var _fps: Array = []

static func requested() -> bool:
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a == "--smoke-test":
			return true
	return false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout

func _log(step: String) -> void:
	res["last_step"] = step
	BootGuard.log_line("smoke: " + step)
	print("SMOKE_STEP ", step)

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	res["platform"] = OS.get_name()
	res["model"] = OS.get_model_name()
	res["version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	res["renderer"] = RenderingServer.get_current_rendering_method()
	res["driver"] = RenderingServer.get_current_rendering_driver_name()
	res["adapter"] = RenderingServer.get_video_adapter_name()
	res["screen"] = [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y]
	res["window"] = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	var sa := DisplayServer.get_display_safe_area()
	res["safe_area"] = [sa.position.x, sa.position.y, sa.size.x, sa.size.y]
	res["user_dir"] = OS.get_user_data_dir()
	_log("boot")
	# wait for the real menu (the boot loader changes scene on its own)
	var waited := 0.0
	while waited < 90.0:
		var cs := get_tree().current_scene
		if cs != null and cs.scene_file_path.ends_with("main_menu.tscn"):
			break
		await _wait(0.5)
		waited += 0.5
	res["menu_reached"] = waited < 90.0
	res["menu_s"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
	_log("menu")
	await _wait(2.5)
	SaveSys.delete_all()
	Profile.new_character("Проверка", "mage", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 0, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = 0
	var tw := Time.get_ticks_msec()
	Game.start("world")
	waited = 0.0
	while waited < 120.0 and (Game.world == null or Game.player == null):
		await _wait(0.5)
		waited += 0.5
	res["world_loaded"] = Game.world != null and Game.player != null
	res["world_load_s"] = snappedf((Time.get_ticks_msec() - tw) / 1000.0, 0.1)
	if not res.world_loaded:
		_finish(false)
		return
	_log("world")
	await _wait(6.0)
	Game.player.apply_status("invuln", 9999.0)
	# frame rate while standing in the world
	_fps.clear()
	for i in 20:
		await _wait(0.5)
		_fps.append(Engine.get_frames_per_second())
	res["fps_world_avg"] = _avg(_fps)
	res["fps_world_min"] = _fps.min()
	# combat: spawn an enemy, cast spells at it
	_log("combat")
	var w = Game.world
	var pl = Game.player
	var en = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], pl.global_position + pl.facing * 7.0, 1)
	var hp0: float = en.hp if en else 0.0
	_fps.clear()
	for id in ["fireball", "frostbolt", "spark", "fireball", "nova"]:
		if is_instance_valid(en) and not en.is_dead:
			var aim: Vector3 = en.global_position - pl.global_position
			pl.skill_cd.erase(id)
			Spells.cast_free(pl, id, aim, 25.0)
		for k in 3:
			await _wait(0.4)
			_fps.append(Engine.get_frames_per_second())
	res["fps_combat_avg"] = _avg(_fps)
	res["enemy_damaged"] = (not is_instance_valid(en)) or en.is_dead or en.hp < hp0
	# save → reload from disk
	_log("save")
	res["save_ok"] = SaveSys.save_game()
	res["save_exists"] = SaveSys.has_save()
	Profile.char.name = "—"
	res["load_ok"] = SaveSys.load_profile() and Profile.char.name == "Проверка"
	res["static_mem_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	res["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_finish(bool(res.menu_reached) and bool(res.world_loaded) and bool(res.save_ok) and bool(res.load_ok))

func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return snappedf(s / a.size(), 0.1)

func _finish(ok: bool) -> void:
	res["ok"] = ok
	var f := FileAccess.open("user://smoke_result.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(res, "  "))
		f.close()
	_log("done ok=%s" % ok)
	print("SMOKE_RESULT ", JSON.stringify(res))
