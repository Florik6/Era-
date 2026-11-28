class_name Stations
## Crafting & tech stations: forge (upgrades), alchemy lab (Renaissance),
## workshop (Industrial devices), terminals (Modern/Future hacking).

static func open(world, type: String, poi) -> void:
	match type:
		"forge": _forge(world)
		"lab": _lab(world)
		"workshop": _workshop(world)
		"terminal": _terminal(world, poi)

static func _has(world, cost: Dictionary, gold: int) -> bool:
	var pd: CharData = world.player.data
	if pd.gold < gold:
		return false
	for b in cost:
		if pd.inv.count(b) < cost[b]:
			return false
	return true

static func _pay(world, cost: Dictionary, gold: int) -> bool:
	if not _has(world, cost, gold):
		Events.notify.emit("Не хватает материалов или золота", Color(1, 0.45, 0.4))
		Audio.play_sfx("error")
		return false
	var pd: CharData = world.player.data
	pd.gold -= gold
	for b in cost:
		pd.inv.consume(b, cost[b])
	return true

static func _forge(world) -> void:
	var pd: CharData = world.player.data
	var recipes: Array = []
	var ore = ["iron_ore", "iron_ore", "gears", "circuits", "circuits"][Profile.current_era]
	for slot in ["main", "body", "off", "head"]:
		var it: Dictionary = pd.inv.equipped(slot)
		if it.is_empty() or it.get("upg", 0) >= 10:
			continue
		var u: int = it.get("upg", 0)
		var cost := {ore: 2 + u}
		var gold := (30 + u * 25) * (Profile.current_era + 1)
		var item: Dictionary = it
		recipes.append({"name": "Улучшить: %s → +%d" % [ItemDB.display_name(item), u + 1], "desc": "+8% урона/брони за уровень.", "cost": cost, "gold": gold,
			"cb": func():
				if _pay(world, cost, gold):
					item.upg = item.get("upg", 0) + 1
					world.player.refresh_gear()
					Audio.play_sfx("hit_metal")
					if CivicLegends.inst != null:
						CivicLegends.inst.on_craft(item)
					return true
				return false})
	recipes.append({"name": "Переплавить руду в шестерни", "desc": "3 руды → 1 шестерня", "cost": {"iron_ore": 3}, "gold": 5, "cb": func():
		if _pay(world, {"iron_ore": 3}, 5):
			pd.inv.add(ItemDB.create("gears", 0, 1))
			return true
		return false})
	recipes.append_array(Recipes.for_station(world, "forge"))
	recipes.append_array(Ammo.recipes_for(world, "forge"))
	recipes.append_array(TechKnow.maintenance_recipes(world))
	world.ui.open("craft", {"title": "Кузница", "recipes": recipes})

static func _lab(world) -> void:
	var pd: CharData = world.player.data
	var defs := [["potion_hp", {"herbs": 2}, 5], ["potion_mana_small", {"herbs": 1}, 3], ["potion_mana", {"herbs": 2}, 6], ["potion_mana_big", {"herbs": 4}, 25], ["potion_mana_elixir", {"herbs": 6, "spirit_essence": 1}, 90], ["elixir_mutation", {"herbs": 3}, 40], ["bomb_flask", {"herbs": 1, "iron_ore": 1}, 10],
		["potion_big", {"herbs": 5}, 60], ["scroll_identify", {"herbs": 1}, 25], ["purify_salt", {"herbs": 2}, 15]]
	var recipes: Array = []
	for d in defs:
		var bid: String = d[0]
		var cost: Dictionary = d[1]
		var gold: int = d[2]
		recipes.append({"name": ItemDB.base(bid).name, "desc": "Алхимический рецепт.", "cost": cost, "gold": gold, "cb": func():
			if _pay(world, cost, gold):
				pd.inv.add(ItemDB.create(bid, 0, 1))
				Profile.milestone("alchemy")
				Audio.play_sfx("heal")
				return true
			return false})
	recipes.append_array(Recipes.for_station(world, "lab"))
	recipes.append_array(Ammo.recipes_for(world, "lab"))
	world.ui.open("craft", {"title": "Алхимическая лаборатория", "recipes": recipes})

static func _workshop(world) -> void:
	var pd: CharData = world.player.data
	var recipes: Array = []
	recipes.append({"name": "Паровой усилитель (модуль)", "desc": "Технологический модуль: +урон и броня.", "cost": {"gears": 4}, "gold": 80, "cb": func():
		if _pay(world, {"gears": 4}, 80):
			pd.inv.add(ItemDB.create("module_steam", 2, world.player.level, null, false))
			Profile.milestone("craft_device")
			return true
		return false})
	recipes.append({"name": "Механический помощник", "desc": "Собрать боевого спутника.", "cost": {"gears": 3}, "gold": 60, "cb": func():
		if _pay(world, {"gears": 3}, 60):
			world.summon_companion(world.player)
			Profile.milestone("craft_device")
			return true
		return false})
	recipes.append({"name": "Граната", "desc": "Взрывное устройство.", "cost": {"gears": 1}, "gold": 15, "cb": func():
		if _pay(world, {"gears": 1}, 15):
			pd.inv.add(ItemDB.create("grenade", 0, 1))
			Profile.milestone("craft_device")
			return true
		return false})
	recipes.append({"name": "Экспериментальный бронекостюм", "desc": "Паровой бронекостюм редкого качества.", "cost": {"gears": 8, "iron_ore": 6}, "gold": 200, "cb": func():
		if _pay(world, {"gears": 8, "iron_ore": 6}, 200):
			pd.inv.add(ItemDB.create("armor_steam", 2, world.player.level, null, false))
			Profile.milestone("craft_device")
			return true
		return false})
	recipes.append_array(Recipes.for_station(world, "workshop"))
	recipes.append_array(Ammo.recipes_for(world, "workshop"))
	recipes.append_array(TechKnow.maintenance_recipes(world))
	world.ui.open("craft", {"title": "Мастерская", "recipes": recipes})

static func _terminal(world, poi) -> void:
	var opts: Array = []
	opts.append({"text": "Взломать систему", "cb": func(): _hack(world, poi)})
	opts.append({"text": "Отключить блокировки снаряжения (тех-проклятия)", "cb": func():
		world.ui.open("altar", {"altar": poi, "station": "tech"})})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": "Терминал", "text": "Экран мерцает. Доступ защищён, но защиту можно обойти. Взлом поднимет тревогу.", "portrait_color": Color(0.3, 0.8, 1.0), "options": opts})

static func _hack(world, poi) -> void:
	var st: Dictionary = Game.world_state.get("poi_state", {}).get(poi.data.id, {})
	Game.world_state.poi_state[poi.data.id] = st
	if st.get("hacked", false):
		Events.notify.emit("Терминал уже взломан.", Color(0.6, 0.8, 1.0))
		return
	Events.banner.emit("Тревога!", "Защитные системы пробуждаются. Продержитесь!", Color(0.4, 0.8, 1.0))
	var guards: Array = []
	var ids := ["combat_drone", "merc_soldier"] if Profile.current_era == 3 else ["combat_robot", "android"]
	for i in 3:
		var m = world.spawner.spawn_enemy(ids[i % 2], poi.global_position + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)))
		if m:
			m.add_aggro(world.player, 60.0)
			guards.append(m)
	_watch(world, poi, guards, st)

static func _watch(world, poi, guards: Array, st: Dictionary) -> void:
	world.get_tree().create_timer(1.0, false).timeout.connect(func():
		var alive := 0
		for g in guards:
			if is_instance_valid(g) and not g.is_dead:
				alive += 1
		if alive > 0:
			_watch(world, poi, guards, st)
			return
		st.hacked = true
		Profile.milestone("hack_terminal")
		Profile.milestone("clear_lab")
		world.loot.spawn_drop(ItemDB.random_for_era(Profile.current_era, world.player.level, "elite"), poi.global_position)
		var sh := ItemDB.create("chrono_shard", 0, 1)
		world.loot.spawn_drop(sh, poi.global_position + Vector3(1, 0, 0))
		Events.banner.emit("Система взломана", "Лаборатория зачищена, данные получены.", Color(0.4, 0.9, 1.0)))
