class_name Witness
## The Last Witness: a cross-era character who changes clothes and place but
## keeps memory of the player. His story differs between playthroughs
## (variant chosen at character creation) and is revealed era by era.

const VARIANTS := [
	["Страж Времени", "Я был стражем у врат Хроноса, когда эпохи ещё не имели имён.", "Мой долг — следить, чтобы история не порвалась. Ты тянешь её нити сильнее всех.", "Когда придёт Хронопожиратель, я встану рядом с тобой. Или против тебя — если ты станешь им."],
	["Проклятый Странник", "Я бессмертен, но это проклятие, а не дар.", "Меня связал клинок, похожий на те, что ты находишь. Освобождения нет уже тысячу лет.", "Если ты победишь Хронопожирателя, может быть, я наконец смогу умереть."],
	["Бывший Аватар", "Когда-то я сам судил героев от имени Хроноса.", "Я отказался от силы, когда понял, что время нельзя судить.", "Последний суд будет не над тобой. Он будет над самим временем."],
	["Ты из будущего", "У тебя знакомое лицо. Слишком знакомое.", "Я видел, чем закончится твой путь. Я не могу сказать — это изменит всё.", "Я — то, кем ты станешь, если проиграешь. Не проиграй."],
]

static func spawn_at(world, pos: Vector3) -> void:
	if Profile.witness.get("hostile", false):
		return
	var s := {"id": "witness", "owner": ""}
	var n = world.spawner.spawn_villager(s, pos + Vector3(2, 0, 0), "villager")
	n.role = "witness"
	n.dialog_kind = "witness"
	n.actor_id = "witness"
	n.display_name = "Последний Свидетель"
	var outfits := [Color(0.35, 0.3, 0.45), Color(0.5, 0.2, 0.3), Color(0.25, 0.25, 0.25), Color(0.2, 0.25, 0.3), Color(0.8, 0.8, 0.9)]
	n.rig.queue_free()
	var r := HumanoidRig.new()
	r.setup({"build": "normal", "skin": 1, "hair": 4, "hair_color": 4, "beard": 2, "cloth_color": outfits[Profile.current_era], "glow": Color(0.6, 0.9, 1.0)})
	n.set_rig(r)
	n.refresh_gear()

static func dialog(world, n) -> void:
	var w: Dictionary = Profile.witness
	var era := Profile.current_era
	var first = not era in w.met
	if first:
		w.met.append(era)
		Chronicle.record("witness", [world.player], {"pos_v3": n.global_position})
		if w.met.size() >= 3:
			Profile.unlock("witness")
	var v: Array = VARIANTS[clampi(int(w.get("variant", 0)), 0, 3)]
	var rel: float = w.relation
	var text := ""
	if w.met.size() == 1 and first:
		text = "«Ещё один путник эпох... Меня называют Последним Свидетелем. %s»" % v[1]
	elif first:
		text = "«Мы снова встретились, %s. Я помню тебя по эпохе «%s». %s»" % [Profile.char.name, DBEras.era(int(w.met[0])).name, v[mini(w.met.size() - 1, 3)]]
	else:
		text = "«%s»" % (v[mini(w.met.size(), 3)] if rel >= 0.5 else "Время не ждёт. Чем я могу помочь?")
	if rel < -0.5:
		text = "«Ты разочаровываешь меня, %s. Ещё один шаг — и мы станем врагами»." % Profile.char.name
	var opts: Array = []
	opts.append({"text": "Торговать артефактами", "cb": func():
		var items: Array = [ItemDB.create("relic_purifier", 0, 1), ItemDB.create("mirror_shard", 0, 1), ItemDB.create("tome_spacetime", 0, 1)]
		var sh := ItemDB.create("chrono_shard", 0, 1)
		sh.qty = 3
		items.append(sh)
		if rel >= 1.0:
			items.append(ItemDB.random_for_era(era, world.player.level, "boss"))
		w.trades = int(w.get("trades", 0)) + 1
		w.relation = rel + 0.15
		world.ui.open("trade", {"title": "Последний Свидетель", "items": items, "price_mult": 1.2 - minf(0.4, rel * 0.1), "sell": false, "buy_cb": func(it): return world.factions.buy(it, 1.2 - minf(0.4, rel * 0.1))})})
	opts.append({"text": "Расскажи о разломах", "cb": func():
		var lines: Array = []
		if world.gen:
			for p in world.gen.pois:
				if p.type in ["rift", "trial", "mirror"]:
					lines.append("· %s: %s" % [{"rift": "Разлом", "trial": "Врата Хроноса", "mirror": "Зеркало времени"}[p.type], world.gen.nearest_place(p.pos)])
		w.relation = rel + 0.1
		world.ui.open("dialog", {"title": "Сведения о разломах", "text": "«Слушай внимательно:»\n" + "\n".join(lines.slice(0, 8)), "options": [{"text": "Спасибо", "cb": func(): pass}]})})
	opts.append({"text": "Попросить помощи", "cb": func():
		if rel >= 0.0:
			world.player.heal(world.player.max_hp)
			world.player.mana = world.player.max_mana
			world.player.apply_status("haste", 60.0)
			world.player.apply_status("regen_buff", 60.0, {"hps": 6.0 + era * 6.0})
			Events.notify.emit("Свидетель благословляет вас: исцеление, ускорение и регенерация.", Color(0.6, 0.9, 1.0))
		else:
			Events.notify.emit("«Не сейчас»", Color(0.7, 0.7, 0.8))})
	opts.append({"text": "Напасть на Свидетеля", "cb": func():
		w.relation = -3.0
		w.hostile = true
		n.team = "boss"
		n.dialog_kind = ""
		n.display_name = "Последний Свидетель (враг)"
		n.base_hp_override = 600.0 * (era + 1)
		n.refresh_gear()
		n.hp = n.max_hp
		n.add_aggro(world.player, 999.0)
		Events.banner.emit("Последний Свидетель стал врагом", "Он запомнит это во всех эпохах.", Color(1.0, 0.4, 0.4))})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": "Последний Свидетель — " + v[0] if w.met.size() >= 3 else "Последний Свидетель", "text": text, "portrait_color": Color(0.6, 0.9, 1.0), "options": opts})
