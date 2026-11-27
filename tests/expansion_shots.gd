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
			w.sys("hardcore").list().clear()
			var sid: String = hs.sale.keys()[0]
			var cap: Dictionary = w.director.capital()
			if hs.sale.has(cap.id):
				sid = cap.id
			var s = w._settlement(sid)
			var bd: Dictionary = {}
			for bb in s.buildings:
				if str(bb.id) == hs.sale[sid].bid:
					bd = bb
			var bas := Basis(Vector3.UP, float(bd.rot))
			var door := Vector3(bd.pos.x, float(s.height), bd.pos.y) + bas * Vector3(1.0, 0, bd.size.y * 0.5 + 3.2)
			w.terrain.force_load_around(door)
			await wait(1.5)
			door.y = w.ground_height(door) + 0.3
			w._teleport(pl, door)
			pl.facing = -(bas * Vector3(0, 0, 1))
			for i in 30:
				await wait(0.25)
				if hs.building(hs.sale[sid].bid) != null:
					break
			await wait(1.5)
			await shot("exp_home_for_sale")
			pl.data.gold = 99999
			hs.buy(sid)
			await wait(1.0)
			var b = hs.building(hs.sale[sid].bid)
			for pair in [["x_traveler_bed", Vector3(b.w * 0.5 - 1.0, 0, -0.4), 0.0], ["x_sword_mount", Vector3(-b.w * 0.5 + 1.2, 0, 0.9), PI * 0.5],
					["x_mason_hearth", Vector3(0.4, 0, -b.d * 0.5 + 1.0), 0.0], ["x_alchemy_table", Vector3(b.w * 0.5 - 1.0, 0, b.d * 0.5 - 1.7), PI]]:
				var it := ItemDB.create(pair[0], 0, 1)
				pl.data.inv.add(it)
				hs.place(hs.sale[sid].bid, it, pair[1], pair[2])
			var rack: Dictionary = hs.home(hs.sale[sid].bid).furniture[1]
			rack.items = [ItemDB.create("x_north_axe", 1, 3), ItemCatalog.create_named("x_ash_king_blade", 5)]
			hs._dressed.erase(hs.sale[sid].bid)
			await wait(0.6)
			w._teleport(pl, b.to_global(Vector3(0.2, 0.1, b.d * 0.5 - 1.6)))
			pl.facing = -(b.global_transform.basis * Vector3(0, 0, 1)).normalized()
			await wait(2.0)
			await shot("exp_home_interior")
			for id in ["x_border_sword", "linen_bandage", "iron_ingot", "x_herbalist_ring"]:
				var it2 := ItemDB.create(id, 1, 3)
				pl.data.inv.add(it2)
				hs.move_to_chest(it2)
			w.ui.open("storage", {"bid": hs.sale[sid].bid})
			await wait(0.6)
			await shot("exp_home_chest")
			w.ui.close_all()
		print("SHOTS_DONE")
		get_tree().quit()
