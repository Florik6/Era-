extends Node
## Unified event journal. Every significant happening in the world is recorded
## once here; biographies, reputation, quests, legacy and the history screen all
## consume these records instead of duplicating logic.
##
## Event fields: id, type, t (game day), era, pos [x,z], place, actors [ids],
## names {id: name}, result, conseq {}, text.

const MAX_EVENTS := 900

var events: Array = []
var next_id := 1

func record(type: String, actors: Array, data: Dictionary = {}) -> Dictionary:
	var ev := {
		"id": next_id, "type": type,
		"t": snappedf(_game_time(), 0.01),
		"era": Profile.current_era,
		"pos": data.get("pos", [0, 0]),
		"place": data.get("place", ""),
		"actors": [], "names": {},
		"result": data.get("result", ""),
		"conseq": data.get("conseq", {}),
		"text": "",
		"extra": data.get("extra", {}),
	}
	next_id += 1
	for a in actors:
		var id := ""
		var nm := ""
		if a is String:
			id = a
			nm = data.get("names", {}).get(a, a)
		elif a is Dictionary:
			id = a.get("id", "")
			nm = a.get("name", id)
		elif a is Object and is_instance_valid(a):
			id = a.get("actor_id") if a.get("actor_id") else ""
			nm = a.get("display_name") if a.get("display_name") else id
		if id != "":
			ev.actors.append(id)
			ev.names[id] = nm
	if data.has("pos_v3"):
		var p: Vector3 = data.pos_v3
		ev.pos = [snappedf(p.x, 0.1), snappedf(p.z, 0.1)]
		if ev.place == "" and Game.world and Game.world.has_method("place_name"):
			ev.place = Game.world.place_name(p)
	ev.text = data.get("text", "")
	if ev.text == "":
		ev.text = describe(ev)
	events.append(ev)
	if events.size() > MAX_EVENTS:
		events.pop_front()
	Events.chronicle.emit(ev)
	return ev

func _game_time() -> float:
	if has_node("/root/Game"):
		return Game.game_time
	return 0.0

func nm(ev: Dictionary, i: int) -> String:
	if i >= ev.actors.size():
		return "кто-то"
	return ev.names.get(ev.actors[i], ev.actors[i])

func describe(ev: Dictionary) -> String:
	var at := (" у места «%s»" % ev.place) if ev.place != "" else ""
	var x: Dictionary = ev.get("extra", {})
	match ev.type:
		"kill":
			return "%s сразил(а) %s%s." % [nm(ev, 0), nm(ev, 1), at]
		"boss_kill":
			return "%s одолел(а) босса «%s»%s." % [nm(ev, 0), x.get("boss", nm(ev, 1)), at]
		"boss_escaped":
			return "Босс «%s» бежал от %s, затаив злобу." % [nm(ev, 1), nm(ev, 0)]
		"boss_returned":
			return "Босс «%s» вернулся, став сильнее." % nm(ev, 0)
		"legend_born":
			return "%s стал(а) живой легендой: «%s»." % [nm(ev, 0), x.get("title", "")]
		"legend_died":
			return "Пала легенда — %s. %s" % [nm(ev, 0), x.get("cause", "")]
		"item_found":
			return "%s нашёл(ла) «%s»%s." % [nm(ev, 0), x.get("item", "?"), at]
		"faction_join":
			return "%s вступил(а) в «%s»." % [nm(ev, 0), x.get("faction", "")]
		"faction_leave":
			return "%s покинул(а) «%s»." % [nm(ev, 0), x.get("faction", "")]
		"rank_up":
			return "%s получил(а) звание «%s» в «%s»." % [nm(ev, 0), x.get("rank", ""), x.get("faction", "")]
		"capture":
			return "%s захватил(а) %s для «%s»." % [nm(ev, 0), x.get("point", "точку"), x.get("faction", "себя")]
		"settlement_captured":
			return "%s перешло под контроль «%s»." % [x.get("settlement", "Поселение"), x.get("faction", "")]
		"battle":
			return "Битва%s: «%s» против «%s». Победитель — «%s»." % [at, x.get("a", ""), x.get("b", ""), x.get("winner", "")]
		"quest_done":
			return "%s выполнил(а) задание «%s»." % [nm(ev, 0), x.get("quest", "")]
		"quest_failed":
			return "%s провалил(а) задание «%s»." % [nm(ev, 0), x.get("quest", "")]
		"mercy":
			return "%s пощадил(а) поверженного %s%s." % [nm(ev, 0), nm(ev, 1), at]
		"betrayal":
			return "%s предал(а) %s." % [nm(ev, 0), nm(ev, 1)]
		"help":
			return "%s помог(ла) %s в бою%s." % [nm(ev, 0), nm(ev, 1), at]
		"rift_cleared":
			return "%s прошёл(ла) разлом «%s»." % [nm(ev, 0), x.get("rift", "")]
		"discovery":
			return "%s открыл(а) место «%s»." % [nm(ev, 0), x.get("place", "")]
		"era_unlocked":
			return "%s прошёл(ла) Суд Хроноса и открыл(а) эпоху «%s»." % [nm(ev, 0), x.get("era", "")]
		"world_event":
			return "Событие: %s%s." % [x.get("name", ""), at]
		"event2":
			return "%s%s: %s." % [x.get("name", "Событие"), at, x.get("result", "")]
		"legend_visit":
			return ev.get("text", "%s прибыл(а)%s." % [nm(ev, 0), at])
		"city_recovery":
			return "%s приходит в себя после нападения: %s." % [ev.get("place", "Город"), x.get("outcome", "")]
		"resonance_catastrophe":
			var who := nm(ev, 0) if ev.actors.size() > 0 else "Столкновение чар"
			return "%s вызвал(а) резонансную катастрофу «%s»%s." % [who, x.get("kind", ""), at]
		"resonance_rift":
			return "На месте катастрофы «%s» открылся разлом%s." % [x.get("kind", ""), at]
		"black_storm":
			return "Над Чёрным городом разразилась магическая буря%s: %s." % [at, x.get("result", "город выстоял")]
		"world_event_end":
			return "Завершилось: %s. %s" % [x.get("name", ""), x.get("outcome", "")]
		"invasion":
			return "Разлом выпустил захватчиков из эпохи «%s»%s." % [x.get("from", "?"), at]
		"duel":
			return "Дуэль: %s против %s. Победил(а) %s." % [nm(ev, 0), nm(ev, 1), x.get("winner", "")]
		"curse_bound":
			return "%s оказался(ась) связан(а) проклятым предметом «%s»." % [nm(ev, 0), x.get("item", "")]
		"curse_broken":
			return "%s освободился(ась) от проклятия «%s»." % [nm(ev, 0), x.get("item", "")]
		"living_evolved":
			return "Живое оружие «%s» эволюционировало." % x.get("item", "")
		"commander":
			return "%s назначен(а) командиром «%s»." % [nm(ev, 0), x.get("faction", "")]
		"leader":
			return "%s возглавил(а) «%s»." % [nm(ev, 0), x.get("faction", "")]
		"heir":
			return "%s стал(а) наследником легенды %s." % [nm(ev, 0), nm(ev, 1)]
		"fortress":
			return "%s получил(а) во владение крепость «%s»." % [nm(ev, 0), x.get("name", "")]
		"fortress_raid":
			return "Крепость «%s» атакована. %s" % [x.get("name", ""), x.get("outcome", "")]
		"destroyed":
			return "%s разрушил(а) %s." % [nm(ev, 0), x.get("what", "строение")]
		"relic_left":
			return "%s оставил(а) реликвию «%s»%s." % [nm(ev, 0), x.get("item", ""), at]
		"witness":
			return "%s встретил(а) Последнего Свидетеля." % nm(ev, 0)
		"hunted":
			return "За голову %s назначена награда. Охотники вышли на след." % nm(ev, 0)
		"level_up":
			return "%s достиг(ла) %d уровня." % [nm(ev, 0), x.get("lvl", 0)]
		"chrono_double":
			return "%s сразился(ась) со своим хронодвойником. %s" % [nm(ev, 0), x.get("outcome", "")]
		"loot_stolen":
			return "%s похитил(а) «%s» и скрылся(ась)." % [nm(ev, 0), x.get("item", "")]
	return ev.type

func for_actor(id: String, limit: int = 60) -> Array:
	var out: Array = []
	for i in range(events.size() - 1, -1, -1):
		if id in events[i].actors:
			out.append(events[i])
			if out.size() >= limit:
				break
	out.reverse()
	return out

func recent(n: int = 50, era_i: int = -1) -> Array:
	var out: Array = []
	for i in range(events.size() - 1, -1, -1):
		if era_i < 0 or events[i].era == era_i:
			out.append(events[i])
			if out.size() >= n:
				break
	return out

func count_type(type: String, actor_id: String = "") -> int:
	var n := 0
	for e in events:
		if e.type == type and (actor_id == "" or actor_id in e.actors):
			n += 1
	return n

func to_dict() -> Dictionary:
	return {"events": events, "next_id": next_id}

func from_dict(d: Dictionary) -> void:
	events = d.get("events", [])
	next_id = int(d.get("next_id", events.size() + 1))
	for e in events:
		e.id = int(e.id)
		e.era = int(e.era)

func clear() -> void:
	events.clear()
	next_id = 1
