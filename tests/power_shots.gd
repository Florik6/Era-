extends Node
## Screenshots of the «Ascension of Power» skill screens and a few spells
## (run under xvfb with a renderer; headless runs only check that the
## screens open). Prints POWER_SHOTS_DONE pass=N fail=M.

func _ready() -> void:
	seed(4242)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Ирма", "mage", false, {"skin": 1, "hair": 3, "hair_color": 2, "beard": 0, "cloth": 1})
	Profile.world_seed = 290290
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
		render = DisplayServer.get_name() != "headless"
		dir = OS.get_environment("SHOTS_DIR")
		if dir == "":
			dir = "user://power_shots"
		DirAccess.make_dir_recursive_absolute(dir)
		_run()
	func _run() -> void:
		await wait(3.5)
		var w = Game.world
		var pl = Game.player
		var d: CharData = pl.data
		pl.apply_status("invuln", 99999.0)
		w.director._t = -100000.0
		if w.get("day_night") and w.day_night.get("time_override") != null:
			w.day_night.time_override = 14.0
		d.level = 24
		d.class_pts = 6
		for e in DBAbilities.class_skills("mage").slice(0, 8):
			d.class_skills.append(e.id)
		for s in ["earth", "necro", "heal", "air", "light"]:
			d.learn_school(s)
			d.schools[s].lvl = 14
			d.schools[s].pts = 4
		for s in DBAbilities.SCHOOL_ORDER:
			for e in DBAbilities.school_spells(s):
				if int(e.tier) <= 3 and d.knows_school(s):
					d.learn_ability(e.id)
		pl.recalc_stats()
		var sc = w.ui.open("skills")
		await wait(0.6)
		ck("skills screen opens", sc != null)
		var tabs: TabContainer = sc._tabs
		var names: Array = []
		for c in tabs.get_children():
			names.append(str(c.name))
		ck("tabs: Класс / Оружие / Магия / Специализации / Изученные / Набор", names.slice(0, 6) == ["Класс", "Оружие", "Магия", "Специализации", "Изученные", "Набор"], str(names))
		tabs.current_tab = 0
		await wait(0.4)
		await shot("ui_01_class")
		tabs.current_tab = 2
		var magic: TabContainer = tabs.get_child(2)
		ck("ten school tabs, each with its sign", magic.get_tab_count() == 10)
		for i in [5, 6, 7, 8, 9]:
			magic.current_tab = i
			await wait(0.4)
			await shot("ui_02_school_%s" % DBAbilities.SCHOOL_ORDER[i])
		tabs.current_tab = 1
		await wait(0.4)
		await shot("ui_03_weapons")
		tabs.current_tab = 3
		await wait(0.4)
		await shot("ui_04_specialisations")
		tabs.current_tab = 5
		await wait(0.4)
		await shot("ui_05_prepared_set")
		var big := true
		for b in sc.find_children("*", "Button", true, false):
			if b.is_visible_in_tree() and b.size.y > 0.0 and b.size.y < 40.0:
				big = false
		ck("touch targets are large (buttons ≥ 40 px)", big)
		w.ui.close_top()
		await wait(0.5)
		# a few spells in the world
		var foes: Array = []
		for i in 4:
			var b2 = w.spawner.spawn_enemy("bandit", pl.global_position + pl.facing * 9.0 + pl.facing.cross(Vector3.UP) * (i - 1.5) * 2.0, 4)
			b2.apply_status("root", 30.0)
			foes.append(b2)
		await wait(0.6)
		for id in ["e_stone_spears", "n_raise_servant", "a_cutting_cyclone", "g_seven_rays", "h_healers_circle"]:
			pl.skill_cd.clear()
			pl.mana = pl.max_mana
			pl.act = {}
			pl.use_ability(id, pl.facing)
			await wait(AbilityExec.cast_time(pl, DBAbilities.get_ab(id)) + 0.5)
			await shot("fx_" + id)
		print("POWER_SHOTS_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
