extends Node
## Screenshots of the Technological Knowledge System (xvfb + renderer):
## the study screen of an unknown future rifle, a part trial, the knowledge
## screen and the hero turning the unknown device over in his hands.
## Prints TECH_SHOTS_DONE pass=N fail=M.

func _ready() -> void:
	seed(8181)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Ратибор", "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 818181
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var dir := ""
	var render := false
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func shot(nm: String) -> void:
		if not render:
			return
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/" + nm + ".png")
		print("SHOT ", nm)
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		render = DisplayServer.get_name() != "headless"
		dir = OS.get_environment("SHOTS_DIR")
		if dir == "":
			dir = "user://tech_shots"
		DirAccess.make_dir_recursive_absolute(dir)
		_run()
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		var d = pl.data
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		for sn in ["events2", "beasts"]:
			if w.sys(sn):
				w.sys(sn).enabled = false
		var it := ItemDB.create("pulse_rifle", 1, 6)
		d.inv.add(it)
		pl.equip_item(it)
		await wait(0.5)
		w.cam.yaw = pl.rotation.y + PI
		await shot("01_unknown_device_in_hands")
		ck("the hero turns the unknown device over (inspect)", str(pl.act.get("name", "")) == "inspect")
		await wait(1.0)
		var scr = w.ui.open("inspect", {"item": it})
		await wait(1.0)
		await shot("02_study_screen_unknown")
		ck("study screen with the 3D model", scr != null and scr.view.model != null)
		scr._act("examine")
		scr._act("identify")
		scr._select_part("energy")
		await wait(0.6)
		await shot("03_part_trial")
		scr._answer("хранит и подаёт заряд")
		await wait(0.4)
		await shot("04_series_of_trials")
		w.ui.close_all()
		await wait(0.3)
		var t = w.ui.open("tech")
		await wait(0.6)
		await shot("05_knowledge_screen")
		ck("knowledge screen", t != null)
		w.ui.close_all()
		print("TECH_SHOTS_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
