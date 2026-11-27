class_name Dialogs
extends Node
## NPC conversations: villagers (quests, rumours from the real chronicle),
## traders, guards, faction members (joining, vendor), living legends
## (memories, duels, help), the Last Witness.

var world

func _init(w) -> void:
	world = w

func open_npc(n) -> void:
	# special characters (wounded hunter, hunters' guild…) bring their own talk
	if n.has_meta("talk_cb"):
		var cb: Callable = n.get_meta("talk_cb")
		if cb.is_valid():
			cb.call(n)
			return
	if EventDirector2.inst != null and EventDirector2.inst.talk_to(n):
		return
	var opts: Array = []
	var text := ""
	var col := Color(0.6, 0.6, 0.6)
	if n.record.size() > 0:
		_legend_dialog(n)
		return
	match n.role:
		"witness":
			Witness.dialog(world, n)
			return
		"trader":
			if CityLife.inst != null and n.has_meta("prof") and not CityLife.inst.is_open(n):
				text = "«Лавка закрыта. Приходите с утра — с восьми до семи вечера»."
			else:
				text = "«Добро пожаловать! Лучшие товары эпохи «%s»»." % DBEras.era(Profile.current_era).name
				opts.append({"text": "Торговать", "cb": func(): open_trade(n)})
		"healer":
			_healer_dialog(n)
			return
		"mentor":
			if MagicLore.inst != null:
				MagicLore.inst.mentor_dialog(n)
				return
		"guard":
			var st: Dictionary = world.factions.settlement_state(n.settlement_id)
			var owner_f: String = st.get("owner", "")
			text = "«%s под защитой %s. Безопасность: %d%%. Население: %d»." % [st.get("name", "Поселение"), DBEras.faction(owner_f).get("name", "вольных жителей"), int(st.get("security", 0.5) * 100), st.get("population", 0)]
		"soldier":
			var f: Dictionary = DBEras.faction(n.faction_id)
			col = f.get("color", col)
			text = "«Я служу «%s». %s»" % [f.get("name", ""), f.get("desc", "")]
			if world.factions.member_of() != n.faction_id:
				opts.append({"text": "Вступить в «%s»" % f.name, "cb": func(): world.factions.join(n.faction_id)})
			opts.append({"text": "Торговец организации", "cb": func(): world.factions.open_vendor(n.faction_id)})
		_:
			text = _villager_line(n)
	if n.has_meta("civic_id"):
		opts.append({"text": "Расспросить о жизни", "cb": func(): _civic_story(n), "close": true})
	var qs: Array = world.quests.offers_for(n)
	if not qs.is_empty() and n.role in ["villager", "trader", "guard"]:
		opts.push_front({"text": "Задания (%d)" % qs.size(), "cb": func(): _quest_list(n)})
	opts.append({"text": "Слухи", "cb": func(): _rumours(n)})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": n.display_name, "text": text, "portrait_color": col, "options": opts})

## Town healer / doctor: treats Hardcore injuries for gold (era-appropriate
## care; a medical capsule in the future), sells medicine, and in the normal
## mode simply restores health.
func _healer_dialog(n) -> void:
	var pl = world.player
	var opts: Array = []
	var text := "«Покажите, что болит»."
	var hc = world.sys("hardcore")
	var era := Profile.current_era
	if hc != null and hc.enabled():
		var inj: Array = hc.list()
		if inj.is_empty():
			text = "«Вы целы. Берегите себя — и возьмите бинты в дорогу»."
		else:
			var lines: Array = []
			for i in inj:
				lines.append("· %s — %s (%s)%s%s" % [Hardcore.ZONE_NAMES[i.zone], Hardcore.TYPE_NAMES[i.type].to_lower(), Hardcore.SEV_NAMES[int(i.sev)],
					", кровотечение" if int(i.bleed) > 0 and not i.bandaged else "", ", заражение" if i.infected else ""])
			text = "«Давайте посмотрим…»\n" + "\n".join(lines)
			var price: int = hc.care_price()
			var src := "healer" if era <= 1 else "doctor"
			opts.append({"text": "Лечение (%d %s)" % [price, DBEras.era(era).currency], "cb": func():
				if pl.data.gold < price:
					Events.notify.emit("Не хватает денег на лечение", Color(1.0, 0.5, 0.4))
					return
				pl.data.gold -= price
				hc.treat_all(src)
				pl.heal(pl.max_hp * 0.3)
				if CivicLegends.inst != null:
					CivicLegends.inst.on_heal(n)})
			if era == 4:
				var cp := price * 3
				opts.append({"text": "Медицинская капсула — полное восстановление (%d)" % cp, "cb": func():
					if pl.data.gold < cp:
						Events.notify.emit("Не хватает денег на капсулу", Color(1.0, 0.5, 0.4))
						return
					pl.data.gold -= cp
					hc.treat_all("capsule")
					pl.heal(pl.max_hp)})
	else:
		var hp_price := 5 * (era + 1)
		if pl.hp < pl.max_hp:
			opts.append({"text": "Подлечиться (%d %s)" % [hp_price, DBEras.era(era).currency], "cb": func():
				if pl.data.gold >= hp_price:
					pl.data.gold -= hp_price
					pl.heal(pl.max_hp)
					Audio.play_sfx("heal", pl.global_position)})
	opts.append({"text": "Купить лекарства", "cb": func(): open_trade(n)})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": n.display_name, "text": text, "portrait_color": Color(0.6, 0.9, 0.7), "options": opts})

## A townsperson's real life story: rank and the Chronicle entries of their deeds.
func _civic_story(n) -> void:
	var cl = CivicLegends.inst
	var rec: Dictionary = cl.record_of(n) if cl else {}
	if rec.is_empty():
		return
	var bio: Dictionary = world.legends.biography(rec)
	var lines: Array = bio.get("chronicle", [])
	var t := "[b]%s[/b] — %s%s\n\n%s" % [rec.name, cl.rank_name(rec), " · живая легенда" if rec.legend else "",
		"\n".join(lines.slice(-6)) if not lines.is_empty() else "«Пока рассказать нечего — обычная жизнь, обычная работа»."]
	world.ui.open("dialog", {"title": rec.name, "text": t, "options": [{"text": "Назад", "cb": func(): open_npc(n)}]})

func _villager_line(n) -> String:
	var lines := ["«Времена неспокойные. На дорогах опять шалят»", "«Говорят, в руинах видели странный свет»", "«Хорошо, что стража рядом»",
		"«Мой дед рассказывал о разломах времени. Я думал — сказки»", "«Если ищешь работу — спроси у людей, у всех свои беды»"]
	if Game.is_night():
		lines.append("«Ночью лучше не выходить за ворота…»")
	return lines[hash(n.actor_id) % lines.size()]

func _quest_list(n) -> void:
	var opts: Array = []
	for q in world.quests.offers_for(n):
		var qq: Dictionary = q
		opts.append({"text": "%s — %s" % [qq.title, qq.reward_text], "cb": func(): _quest_detail(n, qq), "close": true})
	opts.append({"text": "Назад", "cb": func(): open_npc(n)})
	world.ui.open("dialog", {"title": "Задания: " + n.display_name, "text": "Чем можете помочь?", "options": opts})

func _quest_detail(n, q: Dictionary) -> void:
	var t := "[b]%s[/b]\n%s\n\n[color=#ffd36b]Награда:[/color] %s" % [q.title, q.desc, q.reward_text]
	world.ui.open("dialog", {"title": q.title, "text": t, "options": [
		{"text": "Принять", "cb": func(): world.quests.accept(q)},
		{"text": "Назад", "cb": func(): _quest_list(n)}]})

func _rumours(n) -> void:
	var lines: Array = []
	for ev in Chronicle.recent(40):
		if ev.type in ["legend_born", "legend_died", "boss_kill", "settlement_captured", "battle", "capture", "item_found", "invasion", "boss_escaped", "loot_stolen", "beast_slain", "lair_cleared"]:
			lines.append("· " + ev.text)
		if lines.size() >= 5:
			break
	var lg: Array = world.legends.legends()
	if not lg.is_empty():
		var l: Dictionary = lg[0]
		lines.append("· Все говорят о %s «%s». Говорят, его видели возле «%s»." % [l.name, l.title, world.gen.nearest_place(Vector2(l.pos[0], l.pos[1])) if world.gen else "?"])
	if BeastWorld.inst != null:
		var rl: String = BeastWorld.inst.rumour_line()
		if rl != "":
			lines.append("· " + rl)
	if world.gen:
		for p in world.gen.pois:
			if p.type == "lair" and not Game.world_state.bosses.get(p.data.get("boss_id", ""), {}).get("defeated", false):
				lines.append("· В месте «%s» обитает %s." % [p.get("name", "логово"), DBActors.BOSSES[p.data.boss_id].name])
				break
	if lines.is_empty():
		lines.append("«Ничего интересного не слышно»")
	world.ui.open("dialog", {"title": "Слухи", "text": "\n".join(lines), "options": [{"text": "Спасибо", "cb": func(): pass}]})

func open_trade(n) -> void:
	var era := Profile.current_era
	var lvl: int = world.player.level
	var items: Array = []
	for b in ["potion_hp", "potion_mana", "scroll_identify", "scroll_purify", "purify_salt", "spirit_essence"]:
		var it := ItemDB.create(b, 0, 1)
		it.qty = 5 if b.begins_with("potion") else (3 if b == "purify_salt" else (1 if b == "spirit_essence" else 2))
		items.append(it)
	var tomes := ["tome_fire", "tome_ice", "tome_lightning", "tome_dark", "tome_spacetime"]
	items.append(ItemDB.create(tomes[hash(n.actor_id) % tomes.size()], 0, 1))
	if era >= 1:
		items.append(ItemDB.create("bomb_flask" if era < 3 else "grenade", 0, 1))
	items.append(ItemDB.create("companion_whistle", 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(n.actor_id) + Game.day()
	for i in 5:
		items.append(ItemDB.random_for_era(era, lvl, "chest", 0.0, rng))
	var owner_f: String = world.factions.settlement_owner(n.settlement_id)
	var mult := 1.0
	if owner_f != "" and world.factions.member_of() == owner_f:
		mult = 0.85
	if CityEconomy.inst != null and str(n.settlement_id) != "":
		mult *= CityEconomy.inst.price_mult(n.settlement_id, "goods")      # town supply and shortages
	# expansion goods sold in shops of this era (rotating daily)
	var shop_ids: Array = []
	for k in ItemCatalog.all():
		var xb: Dictionary = ItemCatalog.base(k)
		if int(xb.era) == era and "shop" in xb.src and not xb.has("art"):
			shop_ids.append(k)
	shop_ids.sort()
	var srng := RandomNumberGenerator.new()
	srng.seed = hash(str(n.actor_id)) + Game.day() * 7
	for i in mini(8, shop_ids.size()):
		var sid: String = shop_ids[srng.randi() % shop_ids.size()]
		var sit := ItemDB.create(sid, 0, lvl)
		if ItemDB.base(sid).get("stack", false):
			sit.qty = 3
		items.append(sit)
	for med in ItemCatalog.ids_by("medicine", era):
		var mi := ItemDB.create(med, 0, 1)
		mi.qty = 4
		items.append(mi)
	world.ui.open("trade", {"title": "Торговец: " + n.display_name, "items": items, "price_mult": mult, "sell": true, "sell_mult": 0.35,
		"npc": n, "buy_cb": func(it): return world.factions.buy(it, mult)})

func _legend_dialog(n) -> void:
	var r: Dictionary = n.record
	var rel: Dictionary = r.rel
	var text := "[b]%s%s[/b]\n" % [r.name, (" «%s»" % r.title) if r.title != "" else ""]
	if rel.gratitude > 0.5:
		text += "«Я не забыл, что ты для меня сделал. Чем могу помочь?»"
	elif rel.rivalry > 0.4:
		text += "«Снова ты. Сразимся? Только честно — один на один»."
	elif rel.grudge > 0.5:
		text += "«Ты ещё смеешь со мной говорить?»"
	else:
		text += "«Чего тебе, странник?»"
	if not r.memories.is_empty():
		text += "\n\n[i][color=#bbaa88]%s[/color][/i]" % r.memories[-1].text
	var opts: Array = []
	opts.append({"text": "Кто ты?", "cb": func():
		var bio: Dictionary = world.legends.biography(r)
		world.ui.open("dialog", {"title": r.name, "text": "%s\n\n%s\n%s" % [bio.backstory, bio.relations, "\n".join(bio.chronicle.slice(-5))], "options": [{"text": "Назад", "cb": func(): _legend_dialog(n)}]})})
	if rel.gratitude > 0.5:
		opts.append({"text": "Пойдём со мной (помощь в бою)", "cb": func():
			n.brain.r_of("player").gratitude = maxf(1.0, rel.gratitude)
			Events.notify.emit("%s будет помогать вам в бою." % r.name, Color(0.7, 1.0, 0.7))})
	if rel.rivalry > 0.4 or n.dialog_kind == "legend":
		opts.append({"text": "Принять вызов на дуэль", "cb": func(): world.legends.start_duel(n)})
	if n.faction_id != "" and world.factions.member_of() != n.faction_id:
		opts.append({"text": "Вступить в «%s»" % DBEras.faction(n.faction_id).name, "cb": func(): world.factions.join(n.faction_id)})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": r.name, "text": text, "portrait_color": Color(1.0, 0.8, 0.35) if r.legend else Color(0.6, 0.6, 0.6), "options": opts})
