extends Node
## Screenshots of combat spectacle moments (run under xvfb). SHOTS_DIR = output.

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Арден", "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 1, "cloth": 2})
	Profile.current_era = 0
	Settings.combat_fx = 3
	Settings.cinematics = 1
	var h := Harness.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Harness:
	extends Node
	var dir := ""
	var home := Vector3.ZERO
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		dir = OS.get_environment("SHOTS_DIR")
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
		var base: Vector3 = pl.global_position
		for tries in 50:
			var a := randf() * TAU
			var p: Vector3 = base + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 140.0)
			w.terrain.force_load_around(p)
			p.y = w.ground_height(p) + 0.3
			if w.is_water(p):
				continue
			var clear := true
			for k in 8:
				var d := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + d * 10.0, 1)
				q.exclude = [pl.get_rid()]
				if not space.intersect_ray(q).is_empty():
					clear = false
					break
			if clear:
				w._teleport(pl, p)
				home = p
				await frames(4)
				return
	func foes(n: int, dist: float = 3.0) -> Array:
		var out: Array = []
		var pl = Game.player
		var ed: Dictionary = DBEras.era(0)
		for i in n:
			var a := -0.6 + 1.2 * float(i) / maxf(1, n - 1)
			var e = Game.world.spawner.spawn_enemy(ed.enemies[i % ed.enemies.size()], pl.global_position + Vector3(sin(a), 0, -cos(a)) * dist, 1)
			if e:
				e.base_speed = 0.0
				e.max_hp = 9999.0
				e.hp = 9999.0
				out.append(e)
		return out
	func clear_foes() -> void:
		for a in Game.actors_near(Game.player.global_position, 50.0):
			if a != Game.player:
				a.queue_free()
	func reset_hero(cls: String) -> void:
		var pl = Game.player
		pl.data.class_id = cls
		pl._mstyle = {}
		pl.rig.gait = ""
		Game.world._teleport(pl, home)
		pl.facing = Vector3(0, 0, -1)
		pl.act = {}
		pl.attack_cd = 0.0
		pl.dodge_cd = 0.0
		pl.stamina = pl.max_stamina
		pl.mana = pl.max_mana
		pl.skill_cd.clear()

	func _run() -> void:
		await wait(3.5)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		w.director.set_process(false)
		if w.sys("road_encounters"):
			w.sys("road_encounters").set_process(false)
		Game.game_time = floor(Game.game_time) + 0.55
		w.weather.set_weather("clear", 9999.0)
		await open_spot()
		clear_foes()
		await wait(1.5)
		# 1 heavy finisher: shockwave, cracks, slash arc
		reset_hero("warrior")
		var axe := ItemDB.create("axe_battle", 2, 1, null, false)
		pl.data.inv.add(axe)
		pl.equip_item(axe)
		var f1 := foes(3, 2.2)
		await frames(3)
		pl.combo = pl._combo_chain("heavy").size() - 1
		pl.combo_t = 5.0
		pl.attack(pl.facing)
		await wait(0.42)
		await shot("c01_heavy_finisher")
		await wait(0.8)
		# 2 ground split (hv_slam)
		reset_hero("warrior")
		pl.data.mastery_of("heavy").lvl = 10
		Skills.use(pl, "hv_slam", pl.facing)
		await wait(0.55)
		await shot("c02_ground_split")
		for e in f1:
			if is_instance_valid(e):
				e.queue_free()
		await wait(0.6)
		# 3 parry spark + slow-mo
		reset_hero("warrior")
		var sw := ItemDB.create("sword_steel", 3, 1, null, false)
		pl.data.inv.add(sw)
		pl.equip_item(sw)
		var f2 := foes(1, 1.6)
		await frames(3)
		pl.statuses.erase("invuln")
		pl.set_block(true)
		pl.block_t = 0.05
		pl.take_damage({"amount": 10.0, "dtype": "slash", "src": f2[0], "melee": true})
		await get_tree().process_frame
		await shot("c03_parry")
		pl.set_block(false)
		pl.apply_status("invuln", 99999.0)
		await wait(0.6)
		pl.attack(pl.facing)
		await wait(0.3)
		await shot("c04_counter")
		for e in f2:
			if is_instance_valid(e):
				e.queue_free()
		await wait(0.6)
		# 5 rogue shadow dash
		reset_hero("rogue")
		pl.dodge(Vector3(1, 0, 0))
		await wait(0.17)
		await shot("c05_shadow_dash")
		await wait(0.6)
		# 6 mage blink
		reset_hero("mage")
		pl.dodge(Vector3(-1, 0, 0))
		await wait(0.12)
		await shot("c06_blink")
		await wait(0.6)
		# 7-11 ultimates
		var schools := {"meteor": "fire", "blizzard": "ice", "storm": "lightning", "nova": "dark", "riftdash": "spacetime"}
		var delays := {"meteor": 1.75, "blizzard": 1.1, "storm": 1.15, "nova": 0.95, "riftdash": 0.9}
		var n := 7
		for sp in ["meteor", "blizzard", "storm", "nova", "riftdash"]:
			reset_hero("mage")
			pl.data.learn_school(schools[sp])
			pl.data.schools[schools[sp]].lvl = 10
			pl.max_mana = 9999.0
			pl.mana = 9999.0
			var f3 := foes(3, 7.0)
			await frames(3)
			Spells.cast(pl, sp, pl.facing)
			await wait(float(delays[sp]))
			await shot("c%02d_ultimate_%s" % [n, sp])
			n += 1
			await wait(1.0)
			for e in f3:
				if is_instance_valid(e):
					e.queue_free()
			await wait(0.6)
		# 12 boss phase event
		reset_hero("warrior")
		var b = w.spawner.spawn_boss("executioner", pl.global_position + Vector3(0, 0, -8))
		await wait(1.0)
		b.hp = b.max_hp * 0.05
		b.brain._check_phase()
		await wait(0.5)
		await shot("c12_boss_phase")
		await wait(2.5)
		await shot("c13_boss_rage")
		print("COMBAT_SHOTS_DONE")
		get_tree().quit()
