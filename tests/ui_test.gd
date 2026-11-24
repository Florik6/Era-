extends Node
## UI smoke test: builds the main menu and every UI screen with sample data
## and saves screenshots. Run with a display (xvfb) — see report.

const OUT := "/tmp/claude-0/-home-user-Era-/4dd8d359-84a1-5cb8-8e5d-83e3c1e26fc1/scratchpad/"

class StubFactions:
	extends RefCounted
	var member := "steel_lion"
	func list() -> Array: return DBEras.factions_of(0)
	func rep(fid: String) -> float: return {"steel_lion": 420.0, "black_raven": -40.0, "ash_circle": 95.0}.get(fid, 0.0)
	func rank_name(fid: String) -> String: return DBEras.faction(fid).ranks[DBEras.rank_for_rep(rep(fid))]
	func relation_text(fid: String) -> String: return "война с Братством Чёрного Ворона" if fid == "steel_lion" else "нейтралитет"
	func strength(_fid: String) -> float: return 640.0
	func territory(_fid: String) -> int: return 4
	func leader_name(fid: String) -> String: return "Сэр Готфрид Несломленный" if fid == "steel_lion" else ""
	func perks(fid: String) -> Array: return ["+5% брони", "Скидка у торговцев 10%"] if fid == member else []
	func member_of() -> String: return member
	func can_join(fid: String) -> Dictionary: return {"ok": fid == "ash_circle", "reason": "" if fid == "ash_circle" else "Враждебна вашей организации"}
	func join(_fid: String) -> Dictionary: return {"ok": true, "msg": "Испытание выдано"}
	func leave() -> void: member = ""
	func open_vendor(_fid: String) -> void: pass

class StubQuests:
	extends RefCounted
	func active() -> Array:
		return [
			{"id": "q1", "title": "Голова Однорукого Брана", "desc": "Разбойник Бран грабит караваны у Каменного Брода.", "type": "bounty", "giver": "Староста Ольховки",
				"objectives": [{"text": "Найти лагерь Брана", "cur": 1, "need": 1, "done": true}, {"text": "Победить Брана", "cur": 0, "need": 1, "done": false}],
				"reward_text": "120 золота, репутация Ордена +40", "tracked": true, "state": "active"},
			{"id": "q2", "title": "Сопровождение каравана", "desc": "Доведите караван до Тихой Заводи.", "type": "escort", "giver": "Купец Лоренц",
				"objectives": [{"text": "Караван доставлен", "cur": 0, "need": 1, "done": false}, {"text": "Отбить нападения", "cur": 2, "need": 3, "done": false}],
				"reward_text": "Редкий предмет", "tracked": false, "state": "active"},
		]
	func completed() -> Array:
		return [{"id": "q0", "title": "Вступление в Орден", "desc": "Испытание пройдено.", "type": "faction", "objectives": [{"text": "Победить 5 разбойников", "cur": 5, "need": 5, "done": true}], "state": "done"}]
	func track(_id) -> void: pass
	func abandon(_id) -> void: pass

class StubLegends:
	extends RefCounted
	var recs: Array = [
		{"id": "n1", "name": "Эдгар", "title": "Гроза Дорог", "archetype": "vengeful", "faction": "black_raven", "level": 14, "renown": 320, "legend": true, "alive": true},
		{"id": "n2", "name": "Изольда", "title": "", "archetype": "explorer", "faction": "", "level": 7, "renown": 80, "legend": false, "alive": true},
	]
	func records() -> Array: return recs
	func biography(r: Dictionary) -> Dictionary:
		return {"backstory": "Вырос в нищей деревне у реки, пока однажды не нашёл в руинах странный клинок. Теперь он хочет стать легендой.",
			"chronicle": ["День 1: Эдгар проиграл бой страннику Тест у старой мельницы, но был пощажён.", "День 3: Эдгар нашёл «Кривой кинжал Бури».", "День 5: Эдгар вступил в Братство Чёрного Ворона.", "День 8: Эдгар захватил сторожевую башню у Волчьей Балки."],
			"memories": ["Я встретил этого мечника возле старой мельницы. Он победил меня, но почему-то не добил. Тогда я запомнил его лицо."],
			"victories": 23, "defeats": 2, "relations": "К вам: уважение 40%, соперничество 60%", "equipment": ["Кривой кинжал Бури", "Кожаная куртка"],
			"achievements": ["Захват территории", "Редкая находка"], "holdings": ["Сторожевая башня у Волчьей Балки"], "era_history": [],
			"title": r.get("title", ""), "alive": true, "cause": ""}

class StubWorld:
	extends Node
	var world_half := 1280.0
	var factions = StubFactions.new()
	var quests = StubQuests.new()
	var legends = StubLegends.new()
	var _tex: ImageTexture
	func map_texture() -> ImageTexture:
		if _tex == null:
			var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
			var n := FastNoiseLite.new()
			for y in 128:
				for x in 128:
					var v := n.get_noise_2d(x * 2.0, y * 2.0)
					var c := Color(0.3, 0.5, 0.22).lerp(Color(0.5, 0.48, 0.45), clampf(v * 2.0, 0, 1))
					if v < -0.3:
						c = Color(0.18, 0.38, 0.55)
					img.set_pixel(x, y, c)
			_tex = ImageTexture.create_from_image(img)
		return _tex
	func map_markers() -> Array:
		return [{"pos": Vector2(0, 0), "kind": "capital", "name": "Крепость Дальнегорье", "color": Color(1, 0.85, 0.4)},
			{"pos": Vector2(-400, 300), "kind": "settlement", "name": "Ольховка", "color": Color(0.9, 0.9, 0.8)},
			{"pos": Vector2(500, -200), "kind": "lair", "name": "Чёрная Башня", "color": Color(0.9, 0.2, 0.2)},
			{"pos": Vector2(200, 600), "kind": "rift", "name": "Разлом", "color": Color(0.4, 1, 0.9)},
			{"pos": Vector2(-700, -650), "kind": "trial", "name": "Суд Хроноса", "color": Color(1, 0.8, 0.2)}]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_data()
	await _run()
	print("UI_TEST_DONE")
	get_tree().quit()

func _setup_data() -> void:
	Profile.new_character("Эдгар", "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 2, "cloth": 1, "cape": 0})
	var c := Profile.char
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 10:
		c.inv.add(ItemDB.random_for_era(i % 3, 3, "boss" if i % 3 == 0 else "chest", 0.0, rng))
	c.inv.add(ItemDB.create_unique("u_insatiable", 4))
	c.inv.add(ItemDB.create_unique("u_living_blade", 2))
	c.inv.add(ItemDB.create("tome_fire"))
	c.inv.add(ItemDB.create("chrono_shard"))
	c.learn_school("fire")
	c.schools.fire.lvl = 4
	c.add_mastery_xp("sword", 900)
	c.add_mastery_xp("bow", 300)
	c.auto_learn()
	c.gold = 640
	c.level = 6
	Chronicle.clear()
	Chronicle.record("kill", [{"id": "player", "name": "Эдгар"}, {"id": "b1", "name": "Однорукий Бран"}], {"place": "Ольховка"})
	Chronicle.record("faction_join", [{"id": "player", "name": "Эдгар"}], {"extra": {"faction": "Орден Стального Льва"}})
	Chronicle.record("legend_born", [{"id": "n1", "name": "Рыжий Освальд"}], {"extra": {"title": "Гроза Дорог"}})
	Chronicle.record("world_event", [], {"place": "Тихая Заводь", "extra": {"name": "Кровавая луна"}})
	Profile.fallen_legends = [{"id": "x1", "name": "Конрад Железный", "title": "Хранитель Башни", "level": 12, "era": 0, "archetype": "defender",
		"backstory": "Был сыном кузнеца, но мечтал о славе.", "memories": [{"t": 2.0, "text": "Башня — мой дом. Никто её не возьмёт."}],
		"chronicle_text": ["Захватил сторожевую башню.", "Пал в бою с Палачом Чёрной Башни."], "kills": 31, "cause_of_death": "Сражён Палачом Чёрной Башни у Чёрной Башни."}]
	Profile.unlock("first_blood")
	Profile.milestone("mastery_5")

func shot(nm: String, wait: float = 0.6) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "ui_%s.png" % nm)
	print("shot ", nm)

func _run() -> void:
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await shot("menu", 1.6)
	menu._open_panel("play")
	await shot("menu_play")
	menu._start_create("world")
	await shot("menu_create")
	menu._open_panel("eras")
	await shot("menu_eras")
	menu._open_panel("achievements")
	await shot("menu_achievements")
	menu._open_panel("character")
	await shot("menu_character")
	menu._close_panel()
	menu.ui.open("settings")
	await shot("menu_settings")
	menu.ui.close_all()
	menu.queue_free()
	await get_tree().process_frame
	# in-game screens over a plain 3D backdrop
	var w := StubWorld.new()
	add_child(w)
	Game.world = w
	var mb := MenuBackground.new()
	add_child(mb)
	mb.set_era(1)
	mb.set_character({"build": "normal"}, {})
	var ui := UIManager.new()
	add_child(ui)
	var c := Profile.char
	var s = ui.open("inventory")
	await shot("inventory")
	s._card(c.inv.items[0], "")
	await shot("inventory_card")
	ui.close_all()
	for nm in ["skills", "factions", "journal", "map", "legends", "chronicle", "pause", "eras"]:
		var scr = ui.open(nm, {"select_cb": func(_i): pass})
		await shot(nm)
		if nm == "skills":
			scr._tabs.current_tab = 1
			await shot("skills_tree")
			scr._tabs.current_tab = 9
			await shot("skills_magic")
		if nm == "journal":
			scr._tabs.current_tab = 2
			await shot("journal_trial")
		if nm == "legends":
			scr._set_mode("fallen")
			await shot("legends_fallen")
		ui.close_all()
	ui.open("dialog", {"title": "Староста Ольховки", "portrait_color": Color(0.6, 0.4, 0.3), "text": "Разбойники совсем распоясались, путник. [b]Однорукий Бран[/b] грабит караваны у Каменного Брода. Поможешь?",
		"options": [{"text": "Взять задание: «Голова Однорукого Брана»", "cb": func(): pass}, {"text": "Торговать"}, {"text": "Расскажи о Свидетеле", "disabled": true}, {"text": "Уйти"}]})
	await shot("dialog")
	ui.close_all()
	var shop: Array = []
	for i in 6:
		shop.append(ItemDB.random_for_era(0, 2, "chest"))
	ui.open("trade", {"title": "Торговец Ордена", "items": shop, "price_mult": 1.1, "sell": true})
	await shot("trade")
	ui.close_all()
	ui.open("craft", {"title": "Кузница", "recipes": [{"name": "Улучшить оружие +1", "desc": "Повышает урон на 8%.", "cost": {"iron_ore": 3}, "gold": 50, "cb": func(): return true},
		{"name": "Зелье здоровья", "desc": "Алхимия: травы и вода.", "cost": {"herbs": 2}, "gold": 0, "cb": func(): return "Сварено зелье"}]})
	await shot("craft")
	ui.close_all()
	ui.open("death", {"text": "Вас сразил [b]Палач Чёрной Башни[/b].\nПотеряно 30 золота. Возрождение у святилища Ольховки.", "respawn_cb": func(): pass})
	await shot("death", 1.0)
	ui.close_all()
	Game.world = null
