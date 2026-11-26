extends Node
## Screenshots of the expansion screens (run under xvfb; SHOTS_DIR = output,
## SHOT_PART = inventory | anatomy | home | "" for all): the inventory with the
## 3D try-on preview and set gear, the Hardcore X-ray anatomy screen, the
## character health tab, the player's house with chest and furniture.

func _ready() -> void:
	seed(5151)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Арден", "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 1, "cloth": 2})
	Profile.world_seed = 777001
	Profile.current_era = 0
	Profile.difficulty = "hardcore"
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
			await get_tree().process_frame
	func shot(nm: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/" + nm + ".png")
		print("SHOT ", nm)
	func _run() -> void:
		await wait(3.5)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		w.director._t = -100000.0
		w.day_night.time_override = 14.0
		if part == "" or part == "inventory":
			for id in ["x_bo_helm", "x_bo_cuirass", "x_bo_bracers", "x_bo_greaves", "x_bo_boots", "x_bo_cloak"]:
				var it := ItemDB.create(id, 1, 3)
				pl.data.inv.add(it)
				pl.equip_item(it)
			var blade := ItemCatalog.create_named("x_ash_king_blade", 5)
			pl.data.inv.add(blade)
			pl.equip_item(blade)
			for id in ["linen_bandage", "cleansing_tincture", "iron_ingot", "x_herbalist_ring", "x_north_axe", "x_oak_chest"]:
				pl.data.inv.add(ItemDB.create(id, 1, 3))
			var scr = w.ui.open("inventory")
			await wait(1.0)
			await shot("exp_inventory")
			scr._preview.try_on(ItemDB.create("x_north_axe", 1, 3))
			scr._preview._yaw = 2.4
			scr._preview._place_cam()
			await wait(0.5)
			await shot("exp_inventory_tryon")
			w.ui.close_all()
		if part == "" or part == "anatomy":
			var hc = w.sys("hardcore")
			hc.list().clear()
			hc.add_injury("arm_r", "cut", 2, "Разбойник")
			hc.add_injury("leg_l", "fracture", 3, "Тролль")
			hc.add_injury("head", "magic", 1, "Тёмный маг")
			hc.add_injury("chest", "bruise", 1, "Разбойник")
			hc.list()[0].infect = 0.4
			pl.data.inv.add(ItemDB.create("gauze_bandage", 0, 1))
			pl.data.inv.add(ItemDB.create("cleansing_tincture", 0, 1))
			var ch = w.ui.open("character", {"tab": "health"})
			await wait(0.6)
			await shot("exp_character_health")
			w.ui.close_all()
			var an = w.ui.open("anatomy")
			await wait(1.0)
			an._select("arm_r")
			await wait(0.4)
			await shot("exp_anatomy_front")
			an.xray._yaw = 2.6
			an.xray._place_cam()
			an._select("leg_l")
			await wait(0.4)
			await shot("exp_anatomy_back")
			w.ui.close_all()
			await wait(0.3)
			await shot("exp_hud_injuries")
		if (part == "" or part == "home") and w.sys("housing") != null:
			var hs = w.sys("housing")
			if hs.has_method("demo_shots"):
				await hs.demo_shots(self)
		print("SHOTS_DONE")
		get_tree().quit()
