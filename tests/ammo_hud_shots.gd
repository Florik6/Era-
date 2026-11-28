extends Node
## Screenshots of the ammo / mana HUD (run under xvfb with a renderer;
## headless runs only check that the HUD state is right).
## Prints AMMO_HUD_SHOTS_DONE pass=N fail=M.

func _ready() -> void:
	seed(6161)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Стрелок", "mage", false, {"skin": 1, "hair": 3, "hair_color": 2, "beard": 0, "cloth": 1})
	Profile.world_seed = 616161
	Profile.current_era = 0
	Settings.cinematics = 0
	Settings.auto_reload = false
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
			dir = "user://ammo_hud_shots"
		DirAccess.make_dir_recursive_absolute(dir)
		_run()

	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		pl.apply_status("test_cool", 999999.0, {"no_heat": true})
		w.director._t = -100000.0
		for sn in ["events2", "beasts"]:
			if w.sys(sn):
				w.sys(sn).enabled = false
		var tc = w.touch
		if tc:
			tc.visible = true
		# pulse rifle 24 / 120
		var it := ItemDB.create("pulse_rifle", 0, 5, null, false)
		pl.data.inv.add(it)
		pl.equip_item(it)
		Ammo.set_loaded(pl, 24)
		var res := ItemDB.create("ammo_pulse", 0, 1, null, false)
		res.qty = 120
		pl.data.inv.add(res)
		var mp := ItemDB.create("potion_mana", 0, 1, null, false)
		mp.qty = 3
		pl.data.inv.add(mp)
		await wait(0.8)
		ck("HUD text 24 / 120", Ammo.hud_text(pl) == "24 / 120", Ammo.hud_text(pl))
		ck("label «Заряд» for an energy weapon", Ammo.hud_label(pl) == "Заряд")
		ck("reload and mana-potion buttons shown", tc == null or (tc.buttons.reload.visible and tc.buttons.mana_potion.visible))
		await shot("01_pulse_24_120")
		pl.toggle_boost()
		await wait(0.3)
		ck("boosted mode shows ×5", Ammo.hud_text(pl).ends_with("×5"), Ammo.hud_text(pl))
		await shot("02_boosted")
		pl.toggle_boost()
		# a spell: the mana bar drops and pauses
		var d: CharData = pl.data
		var e: Dictionary = DBAbilities.school_spells("fire")[2]
		d.learn_school("fire")
		d.schools["fire"].lvl = 10
		d.spells.append(e.id)
		pl.mana = pl.max_mana
		var st := ItemDB.create("staff_oak", 0, 5, null, false)
		d.inv.add(st)
		pl.equip_item(st)
		pl.mana = pl.max_mana
		var ok: bool = pl.use_ability(e.id, pl.facing)
		await wait(0.9)
		ck("cast spends mana (bar drops)", ok and pl.mana < pl.max_mana - 10.0, "%.0f / %.0f" % [pl.mana, pl.max_mana])
		await shot("03_mana_after_cast")
		pl.mana = 2.0
		pl.skill_cd.clear()
		pl.act = {}
		pl.use_ability(e.id, pl.facing)
		await wait(0.15)
		await shot("04_no_mana")
		# empty magazine warning
		pl.equip_item(it)
		Ammo.set_loaded(pl, 0)
		pl.data.inv.consume("ammo_pulse", pl.data.inv.count("ammo_pulse"))
		pl.attack_cd = 0.0
		pl.act = {}
		pl.attack(pl.facing)
		await wait(0.2)
		await shot("05_out_of_ammo")
		print("AMMO_HUD_SHOTS_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
