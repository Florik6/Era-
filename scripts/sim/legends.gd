class_name LegendSystem
extends Node
## Living Legends: notable NPC records gain renown from real chronicle events,
## become legends (title, aura, cape, better behaviour), remember the player,
## write first-person memories derived only from events that happened, react
## on re-encounters (thanks, duel, revenge, retreat), die into the archive of
## Fallen Legends, leave heirs. Biographies are assembled from Chronicle ids.

const LEGEND_RENOWN := 55.0

var world
var recs := {}          # id -> record (shared with Game.world_state.records)

func _init(w) -> void:
	world = w

func setup() -> void:
	recs = Game.world_state.get("records", {})
	Game.world_state.records = recs
	Events.chronicle.connect(_on_chronicle)
	Events.actor_killed.connect(_on_killed)

func save_state() -> void:
	Game.world_state.records = recs

func record(id: String) -> Dictionary:
	return recs.get(id, {})

func new_record(nm: String, extra: Dictionary = {}) -> Dictionary:
	var rng := Game.rng
	var female: bool = extra.get("female", rng.randf() < 0.35)
	var id: String = extra.get("id", Game.new_uid("npc"))
	var rec := {"id": id, "name": nm, "title": "", "archetype": extra.get("archetype", DBActors.rand_archetype(rng)),
		"class_id": extra.get("class_id", ["warrior", "archer", "rogue", "mage"][rng.randi() % 4]), "faction": extra.get("faction", ""),
		"level": extra.get("level", 1), "renown": 0.0, "kills": 0, "boss_kills": 0, "rare_items": 0, "survivals": 0, "captures": 0,
		"alive": true, "legend": false, "commander": false, "leader": false, "backstory": DBActors.backstory(rng, female),
		"memories": [], "rel": {"respect": 0.0, "fear": 0.0, "rivalry": 0.0, "gratitude": 0.0, "grudge": 0.0, "met": 0},
		"holdings": [], "era_history": [], "data": {}, "pos": extra.get("pos", [0.0, 0.0]), "female": female, "look": {},
		"followers": [], "heir_of": extra.get("heir_of", ""), "cause_of_death": "", "events": [], "hp_frac": 1.0,
		"relic_hunter": extra.get("relic_hunter", false), "hunter": extra.get("hunter", false), "role": extra.get("role", "bot"),
		"era": Profile.current_era, "goal_pos": [0.0, 0.0], "boss_id": extra.get("boss_id", "")}
	recs[id] = rec
	return rec

func records() -> Array:
	var out: Array = []
	for k in recs:
		if recs[k].alive:
			out.append(recs[k])
	out.sort_custom(func(a, b): return (1000.0 if a.legend else 0.0) + a.renown > (1000.0 if b.legend else 0.0) + b.renown)
	return out

func legends() -> Array:
	return records().filter(func(r): return r.legend)

func faction_legend_bonus(fid: String) -> float:
	var b := 0.0
	for k in recs:
		var r: Dictionary = recs[k]
		if r.alive and r.faction == fid:
			if r.legend:
				b += 25.0
			if r.commander:
				b += 10.0
	return b

# ---------------------------------------------------------------- chronicle intake
func _on_chronicle(ev: Dictionary) -> void:
	for i in ev.actors.size():
		var id: String = ev.actors[i]
		if not recs.has(id):
			continue
		var r: Dictionary = recs[id]
		r.events.append(ev.id)
		if r.events.size() > 80:
			r.events.pop_front()
		match ev.type:
			"kill":
				if i == 0:
					r.kills += 1
					r.renown += 4.0 + (10.0 if recs.has(ev.actors[1]) and recs[ev.actors[1]].legend else 0.0)
			"boss_kill":
				if i == 0:
					r.boss_kills += 1
					r.renown += 40.0
			"item_found":
				r.renown += 3.0 * float(ev.extra.get("rarity", 3))
			"capture":
				r.captures += 1
				r.renown += 12.0
				r.holdings.append(ev.extra.get("point", ""))
			"mercy":
				if i == 1:
					r.survivals += 1
					r.renown += 3.0
			"help":
				r.renown += 2.0
			"commander":
				r.renown += 15.0
			"duel":
				r.renown += 8.0
		# memories about the player
		if "player" in ev.actors and id != "player":
			var mem := _memory_text(r, ev, i)
			if mem != "":
				r.memories.append({"t": ev.t, "text": mem, "ev": ev.id})
				if r.memories.size() > 25:
					r.memories.pop_front()
		_check_promotion(r)

func _check_promotion(r: Dictionary) -> void:
	if r.legend or not r.alive:
		return
	var deeds: int = r.kills / 5 + r.boss_kills * 2 + r.captures + r.rare_items + r.survivals
	if r.renown >= LEGEND_RENOWN and deeds >= 2:
		r.legend = true
		r.title = _title_for(r)
		var ev := Chronicle.record("legend_born", [{"id": r.id, "name": r.name}], {"extra": {"title": r.title}})
		r.events.append(ev.id)
		Events.legend_born.emit(r)
		Events.banner.emit("Родилась легенда", "%s «%s»" % [r.name, r.title], Color(1.0, 0.75, 0.3))
		var n = _active_npc(r.id)
		if n:
			n.title = r.title
			n.refresh_gear()
			world.spawner._legend_aura(n)
			world.spawner.name_tag(n, Color(1.0, 0.75, 0.25))
			n.base_speed *= 1.05

func _title_for(r: Dictionary) -> String:
	if r.boss_kills > 0:
		return "Победитель Чудовищ"
	if r.captures >= 2:
		return "Владыка %s" % (r.holdings[-1] if not r.holdings.is_empty() else "Земель")
	if r.survivals >= 2:
		return "Несломленный"
	if r.rare_items >= 3:
		return "Искатель Сокровищ"
	if r.kills >= 15:
		return "Гроза Дорог"
	var t := ["Бесстрашный", "Неуловимый", "Странник Эпох", "Хранитель Клятвы", "Пепельный Клинок"]
	return t[hash(r.id) % t.size()]

func _active_npc(id: String):
	for a in Game.actors:
		if is_instance_valid(a) and a.actor_id == id and not a.is_dead:
			return a
	return null

# ---------------------------------------------------------------- relationships & memory
func _memory_text(r: Dictionary, ev: Dictionary, my_index: int) -> String:
	var place: String = ev.place if ev.place != "" else "на безымянной дороге"
	var arch: String = r.archetype
	var rel: Dictionary = r.rel
	var who := "этого воина" if not Profile.char.female else "эту воительницу"
	var weapon_word := "мечника"
	if Game.player and is_instance_valid(Game.player):
		match Game.player.weapon_cat():
			"bow": weapon_word = "лучника"
			"dagger": weapon_word = "убийцу с кинжалами"
			"staff": weapon_word = "мага"
			"firearm": weapon_word = "стрелка"
			"heavy": weapon_word = "бойца с тяжёлым оружием"
			"spear": weapon_word = "копейщика"
	match ev.type:
		"mercy":
			if my_index == 1:
				rel.gratitude += 1.0
				rel.respect += 0.6
				rel.met += 1
				var ends := {"vengeful": "Но в следующий раз всё будет иначе.", "defender": "Я верну этот долг.", "cautious": "Больше я не встану у него на пути.",
					"ambitious": "Однажды я превзойду его.", "opportunist": "Странный поступок. Может, это пригодится мне."}
				return "Я встретил %s у места «%s». Он победил меня, но почему-то не добил. Тогда я запомнил его лицо. %s" % [weapon_word, place, ends.get(arch, "Я этого не забуду.")]
		"help":
			if my_index == 1:
				rel.gratitude += 0.6
				rel.met += 1
				return "У места «%s» меня почти одолели, но %s пришёл на помощь. Теперь я в долгу." % [place, Profile.char.name]
		"kill":
			if my_index == 0 and ev.actors[1] == "player":
				rel.respect -= 0.2
				rel.rivalry += 0.3
				return "Я одолел %s у места «%s». Говорят, он ещё вернётся. Пусть приходит." % [Profile.char.name, place]
		"duel":
			rel.rivalry += 0.5
			rel.respect += 0.5
			var won: bool = ev.extra.get("winner", "") == r.name
			return ("Наша дуэль у места «%s» закончилась моей победой. Но он сражался достойно." if won else "Я проиграл дуэль у места «%s». Это не конец — это начало соперничества.") % place
		"betrayal":
			rel.grudge += 1.5
			return "%s предал меня. Такое не прощают." % Profile.char.name
		"faction_join":
			if r.faction != "" and ev.extra.get("faction", "") == DBEras.faction(r.faction).get("name", "?"):
				rel.respect += 0.3
				return "%s вступил в наши ряды. Посмотрим, чего он стоит." % Profile.char.name
		"boss_kill":
			if ev.actors[0] == "player":
				rel.respect += 0.4
				rel.fear += 0.2
				return "Слышал, %s одолел %s. Опасный человек." % [Profile.char.name, ev.extra.get("boss", "чудовище")]
	return ""

## Called when the player defeats (but doesn't kill) or fights a record.
func on_player_beat(rec: Dictionary, fled: bool) -> void:
	rec.rel.fear += 0.4
	rec.rel.grudge += 0.3 if rec.archetype in ["vengeful", "ambitious", "aggressive"] else 0.1
	rec.rel.met += 1
	if fled:
		rec.survivals += 1
		rec.renown += 4.0
		var place = world.place_name(Game.player.global_position) if Game.player else ""
		rec.memories.append({"t": Game.game_time, "text": "Мне пришлось бежать от %s у места «%s». %s" % [Profile.char.name, place,
			"Я ещё отомщу." if rec.archetype == "vengeful" else "Нужно стать сильнее."]})

func on_helped(npc, helper) -> void:
	if helper.is_player:
		Chronicle.record("help", [helper, npc], {"pos_v3": npc.global_position})

## Re-encounter reactions when a known record meets the player again.
func on_encounter(npc) -> void:
	var r: Dictionary = npc.record
	if r.is_empty() or Game.player == null:
		return
	var rel: Dictionary = r.rel
	if rel.met <= 0 and rel.gratitude <= 0 and rel.grudge <= 0:
		return
	if rel.gratitude > 0.6:
		npc.brain.r_of("player").gratitude = rel.gratitude
		VFX.text(npc.chest() + Vector3(0, 1, 0), "Я помню твою доброту!", Color(0.7, 1.0, 0.7))
		Events.notify.emit("%s узнаёт вас и благодарит. Готов(а) помочь в бою." % r.name, Color(0.7, 1.0, 0.7))
	elif rel.grudge > 0.7 and r.archetype in ["vengeful", "ambitious", "aggressive", "hunter"]:
		npc.add_aggro(Game.player, 60.0)
		npc.brain.r_of("player").grudge = rel.grudge
		VFX.text(npc.chest() + Vector3(0, 1, 0), "Наконец-то! Месть!", Color(1.0, 0.5, 0.4))
		Events.notify.emit("%s узнаёт вас и жаждет мести!" % r.name, Color(1.0, 0.5, 0.4))
	elif rel.fear > 0.8:
		npc.brain.goal = "flee"
		npc.brain.threat = Game.player
		VFX.text(npc.chest() + Vector3(0, 1, 0), "Только не ты...", Color(0.8, 0.8, 1.0))
	elif rel.rivalry > 0.5 and rel.respect > 0.3:
		Events.notify.emit("%s вызывает вас на дуэль! Поговорите с ним." % r.name, Color(1.0, 0.85, 0.4))
		npc.dialog_kind = "legend"

func start_duel(npc) -> void:
	npc.dialog_kind = ""
	npc.add_aggro(Game.player, 120.0)
	npc.set_meta("duel", true)
	Events.banner.emit("Дуэль!", "%s против %s" % [Profile.char.name, npc.display_name], Color(1.0, 0.8, 0.4))
	npc.died.connect(func(_a, _k):
		Chronicle.record("duel", [Game.player, npc], {"pos_v3": npc.global_position, "extra": {"winner": Profile.char.name}})
		Profile.milestone("duel"), CONNECT_ONE_SHOT)

func _on_killed(victim, killer) -> void:
	if not (victim is Actor) or victim.record.is_empty():
		return
	var r: Dictionary = victim.record
	if not recs.has(r.id):
		return
	var k = killer
	if k != null and is_instance_valid(k) and k.owner_actor != null and is_instance_valid(k.owner_actor):
		k = k.owner_actor
	var kname: String = k.display_name if (k != null and is_instance_valid(k)) else "неизвестный"
	r.data = victim.data.to_dict() if victim.data else r.data
	on_death(r, kname, k.actor_id if (k != null and is_instance_valid(k)) else "", victim.global_position)

func on_death(r: Dictionary, killer_name: String, killer_id: String, pos: Vector3) -> void:
	if not r.alive:
		return
	r.alive = false
	var place = world.place_name(pos)
	r.cause_of_death = "Погиб(ла) от руки %s у места «%s», день %d." % [killer_name, place, Game.day() + 1]
	if r.legend or r.renown >= 25.0:
		var ev := Chronicle.record("legend_died", [{"id": r.id, "name": r.name}, {"id": killer_id if killer_id != "" else "unknown", "name": killer_name}],
			{"place": place, "extra": {"cause": r.cause_of_death}})
		r.events.append(ev.id)
		var snap := r.duplicate(true)
		snap.chronicle_text = biography(r).chronicle
		snap.era = Profile.current_era
		Profile.fallen_legends.append(snap)
		if Profile.fallen_legends.size() > 60:
			Profile.fallen_legends.pop_front()
		Events.legend_died.emit(r)
		if r.legend:
			Events.banner.emit("Пала легенда", "%s «%s»" % [r.name, r.title], Color(0.8, 0.8, 0.9))
		_react_to_death(r, killer_id)

func _react_to_death(r: Dictionary, killer_id: String) -> void:
	# comrades swear revenge, faction loses a leader, an heir rises
	for k in recs:
		var o: Dictionary = recs[k]
		if not o.alive or o.id == r.id:
			continue
		if o.faction != "" and o.faction == r.faction and killer_id == "player":
			o.rel.grudge += 0.5
			o.memories.append({"t": Game.game_time, "text": "%s убил нашего товарища %s. Мы этого не забудем." % [Profile.char.name, r.name]})
	if r.leader and r.faction != "":
		world.factions.st[r.faction].leader = ""
		_pick_leader(r.faction)
	if r.legend:
		var heir := new_record(DBActors.rand_name(Profile.current_era, randf() < 0.4, Game.rng), {"faction": r.faction, "level": maxi(1, int(r.level) - 2),
			"heir_of": r.id, "archetype": "vengeful" if killer_id == "player" else r.archetype, "pos": r.pos})
		heir.backstory = "Наследник(ца) легенды %s «%s». %s" % [r.name, r.title, heir.backstory]
		if killer_id == "player":
			heir.rel.grudge = 1.0
		if r.data.size() > 0:
			var cd := CharData.new()
			cd.from_dict(r.data)
			var w := cd.inv.equipped("main")
			if not w.is_empty():
				w.history.append("Унаследовано от %s «%s»" % [r.name, r.title])
				heir["inherit_weapon"] = w
		Chronicle.record("heir", [{"id": heir.id, "name": heir.name}, {"id": r.id, "name": r.name}])

func _pick_leader(fid: String) -> void:
	var best: Dictionary = {}
	for k in recs:
		var o: Dictionary = recs[k]
		if o.alive and o.faction == fid and (best.is_empty() or o.renown > best.renown):
			best = o
	if not best.is_empty():
		best.leader = true
		best.commander = true
		world.factions.st[fid].leader = best.id
		Chronicle.record("leader", [{"id": best.id, "name": best.name}], {"extra": {"faction": DBEras.faction(fid).name}})

func battle_outcome(att: String, def_f: String, winner: String, place: String) -> void:
	for k in recs:
		var o: Dictionary = recs[k]
		if not o.alive or not (o.faction == att or o.faction == def_f):
			continue
		if not o.commander:
			continue
		if o.faction == winner:
			o.renown += 10.0
			o.era_history.append("Победа в битве у места «%s»" % place)
			_check_promotion(o)
		elif randf() < 0.15:
			on_death(o, "войск противника", "", Vector3(o.pos[0], 0, o.pos[1]))

## Bosses that escape become nemeses with their own record.
func boss_nemesis(b, times: int) -> void:
	var id: String = "boss_" + b.boss_id
	var r: Dictionary = recs.get(id, {})
	if r.is_empty():
		r = new_record(b.display_name, {"id": id, "role": "boss", "boss_id": b.boss_id, "archetype": "vengeful"})
		r.backstory = b.def.get("lore", "")
	r.renown += 30.0
	r.survivals += 1
	r.rel.grudge += 1.0
	r.memories.append({"t": Game.game_time, "text": "%s едва не уничтожил меня у места «%s». Я вернусь сильнее." % [Profile.char.name, world.place_name(b.global_position)]})
	_check_promotion(r)

# ---------------------------------------------------------------- biography
func biography(r: Dictionary) -> Dictionary:
	var chron: Array = []
	var victories := 0
	var defeats := 0
	var by_id := {}
	for ev in Chronicle.events:
		by_id[int(ev.id)] = ev
	for eid in r.get("events", []):
		var ev = by_id.get(int(eid))
		if ev == null:
			continue
		chron.append("День %d: %s" % [int(ev.t) + 1, ev.text])
		if ev.type in ["kill", "boss_kill", "duel"] and ev.actors.size() > 0 and ev.actors[0] == r.id:
			victories += 1
		if ev.type in ["mercy"] and ev.actors.size() > 1 and ev.actors[1] == r.id:
			defeats += 1
	var rel: Dictionary = r.rel
	var rel_parts: Array = []
	if rel.respect > 0.3:
		rel_parts.append("уважение")
	if rel.fear > 0.3:
		rel_parts.append("страх")
	if rel.rivalry > 0.3:
		rel_parts.append("соперничество")
	if rel.gratitude > 0.3:
		rel_parts.append("благодарность")
	if rel.grudge > 0.3:
		rel_parts.append("жажда мести")
	var eq: Array = []
	if r.data.size() > 0:
		var cd := CharData.new()
		cd.from_dict(r.data)
		for s in cd.inv.equip:
			eq.append(ItemDB.display_name(cd.inv.equip[s]))
		r.level = cd.level
	var ach: Array = []
	if r.kills > 0:
		ach.append("Побед в бою: %d" % r.kills)
	if r.boss_kills > 0:
		ach.append("Повержено боссов: %d" % r.boss_kills)
	if r.rare_items > 0:
		ach.append("Найдено редких предметов: %d" % r.rare_items)
	if r.captures > 0:
		ach.append("Захвачено точек: %d" % r.captures)
	if r.survivals > 0:
		ach.append("Пережил(а) смертельную опасность: %d" % r.survivals)
	if r.commander:
		ach.append("Командир «%s»" % DBEras.faction(r.faction).get("name", ""))
	if r.leader:
		ach.append("Лидер «%s»" % DBEras.faction(r.faction).get("name", ""))
	var mems: Array = []
	for m in r.memories:
		mems.append("«%s»" % m.text)
	var eh: Array = r.era_history.duplicate()
	if r.heir_of != "":
		eh.push_front("Наследник легенды прошлого")
	return {"backstory": r.backstory, "chronicle": chron, "memories": mems, "victories": victories + r.kills, "defeats": defeats,
		"relations": ("Отношение к вам: " + ", ".join(rel_parts)) if not rel_parts.is_empty() else "Отношение к вам: безразличие",
		"equipment": eq, "achievements": ach, "holdings": r.holdings, "era_history": eh, "title": r.title, "alive": r.alive,
		"cause": r.cause_of_death, "level": r.level, "faction": DBEras.faction(r.faction).get("name", "Без организации"),
		"archetype": DBActors.ARCHETYPES.get(r.archetype, {}).get("name", "")}
