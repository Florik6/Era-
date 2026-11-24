class_name QuestSystem
extends Node
## Real quests with objectives tied to world objects and events: bounties on
## actual NPCs, camp clearing, ruins exploration, artifact search, boss hunts,
## caravan escort (with a thief that can steal and flee → follow-up chase),
## settlement defence, rift expeditions, rituals, faction trials, territory
## capture, curse release. Journal API for the UI.

var world
var quests: Array = []
var done: Array = []
var offers := {}          # settlement id -> Array of quest dicts (not accepted)
var _tick := 0.0

func _init(w) -> void:
	world = w

func setup() -> void:
	var s: Dictionary = Game.world_state.get("quests", {})
	quests = s.get("active", [])
	done = s.get("done", [])
	offers = s.get("offers", {})
	Events.actor_killed.connect(_on_killed)
	Events.chest_opened.connect(_on_chest)
	Events.item_picked.connect(_on_item)
	Events.point_captured.connect(_on_captured)

func save_state() -> void:
	Game.world_state.quests = {"active": quests, "done": done.slice(-40), "offers": offers}

# ---------------------------------------------------------------- UI API
func active() -> Array:
	return quests

func completed() -> Array:
	return done

func track(id: String) -> void:
	for q in quests:
		q.tracked = q.id == id

func abandon(id: String) -> void:
	for q in quests:
		if q.id == id and q.get("abandonable", true):
			quests.erase(q)
			Events.notify.emit("Задание отменено: " + q.title, Color(0.8, 0.8, 0.8))
			return

func tracked_quest() -> Dictionary:
	for q in quests:
		if q.get("tracked", false):
			return q
	return quests[0] if not quests.is_empty() else {}

func tracked_text() -> String:
	var q := tracked_quest()
	if q.is_empty():
		var ts: Dictionary = Profile.trial_status(Profile.current_era)
		return "[color=#ffd36b]Цель эпохи:[/color] подготовиться к Суду Хроноса" if not ts.ready else "[color=#ffd36b]Суд Хроноса ждёт![/color] Найдите врата на карте"
	for o in q.objectives:
		if not o.done:
			var prog := (" (%d/%d)" % [o.cur, o.need]) if o.need > 1 else ""
			return "[color=#ffd36b]%s:[/color] %s%s" % [q.title, o.text, prog]
	return q.title

func tracked_target():
	var q := tracked_quest()
	for o in q.get("objectives", []):
		if o.done:
			continue
		if o.has("pos"):
			return Vector3(o.pos[0], 0, o.pos[1])
		if o.has("target_id"):
			for a in Game.actors:
				if is_instance_valid(a) and a.actor_id == o.target_id:
					return a.global_position
			var r: Dictionary = world.legends.record(o.target_id)
			if not r.is_empty():
				return Vector3(r.pos[0], 0, r.pos[1])
	return null

# ---------------------------------------------------------------- creation
func _q(type: String, title: String, desc: String, objectives: Array, reward: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var q := {"id": Game.new_uid("q"), "type": type, "title": title, "desc": desc, "objectives": objectives, "reward": reward,
		"reward_text": _reward_text(reward), "state": "active", "tracked": false, "giver": extra.get("giver", ""), "faction": extra.get("faction", "")}
	q.merge(extra)
	return q

func _obj(kind: String, text: String, need: int = 1, extra: Dictionary = {}) -> Dictionary:
	var o := {"kind": kind, "text": text, "need": need, "cur": 0, "done": false}
	o.merge(extra)
	return o

func _reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if r.get("gold", 0) > 0:
		parts.append("%d %s" % [r.gold, DBEras.era(Profile.current_era).currency])
	if r.get("xp", 0) > 0:
		parts.append("%d опыта" % r.xp)
	if r.get("item", "") != "":
		parts.append("предмет (%s)" % {"normal": "обычная добыча", "chest": "сундук", "elite": "ценная", "boss": "легендарная", "event": "особая", "rift": "из разлома"}.get(r.item, r.item))
	for f in r.get("rep", {}):
		parts.append("репутация «%s» %+d" % [DBEras.faction(f).name, r.rep[f]])
	if r.get("shards", 0) > 0:
		parts.append("осколки Хроноса ×%d" % r.shards)
	return ", ".join(parts)

func accept(q: Dictionary) -> void:
	if quests.size() >= 8:
		Events.notify.emit("Слишком много активных заданий", Color(1, 0.5, 0.4))
		return
	q.state = "active"
	for s in offers:
		offers[s].erase(q)
	quests.append(q)
	if quests.size() == 1:
		q.tracked = true
	Events.quest_updated.emit(q)
	Events.notify.emit("Новое задание: " + q.title, Color(1.0, 0.85, 0.4))
	_on_accept(q)

func on_settlement_visited(s: Dictionary) -> void:
	if not offers.has(s.id) or offers[s.id].is_empty():
		offers[s.id] = _generate_for(s)

func offers_for(npc) -> Array:
	return offers.get(npc.settlement_id, [])

func _generate_for(s: Dictionary) -> Array:
	var out: Array = []
	var era := Profile.current_era
	var lvl: int = world.player.level if world.player else 1
	var gmul := (era + 1) * 30
	var sp := Vector2(s.pos.x, s.pos.y)
	var camps: Array = []
	var ruins: Array = []
	var lairs: Array = []
	var rifts: Array = []
	var cps: Array = []
	var dungeons: Array = []
	if world.gen:
		for p in world.gen.pois:
			var d: float = sp.distance_to(p.pos)
			if p.type == "camp" and d < 500:
				camps.append(p)
			elif p.type in ["ruins", "altar"]:
				ruins.append(p)
			elif p.type == "lair":
				lairs.append(p)
			elif p.type == "rift" and d < 700:
				rifts.append(p)
			elif p.type == "cp" and d < 500:
				cps.append(p)
			elif p.type == "dungeon":
				dungeons.append(p)
	# bounty on a real NPC record (bandit-minded contenders)
	var cands: Array = []
	for r in world.legends.records():
		if r.role == "bot" and r.archetype in ["aggressive", "opportunist", "vengeful", "hunter"] and r.faction == "":
			cands.append(r)
	if not cands.is_empty():
		var tr: Dictionary = cands[randi() % cands.size()]
		out.append(_q("bounty", "Охота за головой: %s" % tr.name, "Жители %s жалуются на %s. Найдите и победите.%s" % [s.name, tr.name, " Это живая легенда!" if tr.legend else ""],
			[_obj("kill_target", "Победить %s" % tr.name, 1, {"target_id": tr.id})], {"gold": gmul * (3 if tr.legend else 2), "xp": 120 + lvl * 20, "item": "elite" if tr.legend else "normal"}, {"giver": s.name}))
	if not camps.is_empty():
		var c: Dictionary = camps[randi() % camps.size()]
		out.append(_q("clear", "Зачистка: %s" % c.get("name", "лагерь"), "Разбойничий лагерь угрожает дорогам у %s. Уничтожьте всех." % s.name,
			[_obj("clear_camp", "Зачистить лагерь «%s»" % c.get("name", "лагерь"), 1, {"poi": c.id, "pos": [c.pos.x, c.pos.y]})], {"gold": gmul * 2, "xp": 150 + lvl * 15, "item": "chest"}, {"giver": s.name}))
	if not ruins.is_empty():
		var r2: Dictionary = ruins[randi() % ruins.size()]
		out.append(_q("explore", "Тайна руин", "Старики говорят, что в месте «%s» спрятан артефакт." % r2.get("name", "руины"),
			[_obj("reach", "Исследовать «%s»" % r2.get("name", "руины"), 1, {"pos": [r2.pos.x, r2.pos.y], "radius": 14.0}), _obj("loot_chest", "Найти и открыть тайник", 1, {"pos": [r2.pos.x, r2.pos.y]})],
			{"gold": gmul, "xp": 120 + lvl * 15, "item": "elite"}, {"giver": s.name}))
	if not lairs.is_empty():
		var l: Dictionary = lairs[randi() % lairs.size()]
		var bid: String = l.data.get("boss_id", "")
		if not Game.world_state.bosses.get(bid, {}).get("defeated", false):
			out.append(_q("boss", "Охота на босса: %s" % DBActors.BOSSES[bid].name, DBActors.BOSSES[bid].lore,
				[_obj("boss", "Победить: %s" % DBActors.BOSSES[bid].name, 1, {"boss_id": bid, "pos": [l.pos.x, l.pos.y]})], {"gold": gmul * 6, "xp": 500 + lvl * 40, "shards": 2}, {"giver": s.name}))
	if not rifts.is_empty():
		var rf: Dictionary = rifts[randi() % rifts.size()]
		out.append(_q("expedition", "Экспедиция в разлом", "Разлом «%s» нестабилен. Пройдите его и вернитесь." % rf.get("name", "разлом"),
			[_obj("rift", "Пройти разлом", 1, {"pos": [rf.pos.x, rf.pos.y]})], {"gold": gmul * 3, "xp": 300 + lvl * 25, "item": "rift", "shards": 1}, {"giver": s.name}))
	# escort caravan (dynamic chain with a thief)
	if world.gen and world.gen.settlements.size() > 1:
		var dest: Dictionary = world.gen.settlements[randi() % world.gen.settlements.size()]
		if dest.id != s.id and sp.distance_to(dest.pos) < 450.0:
			out.append(_q("escort", "Караван в %s" % dest.name, "Торговый караван отправляется в %s. Защитите его в пути." % dest.name,
				[_obj("escort", "Сопроводить караван до %s" % dest.name, 1, {"pos": [dest.pos.x, dest.pos.y], "from": [s.pos.x, s.pos.y]})],
				{"gold": gmul * 3, "xp": 200 + lvl * 20, "item": "chest"}, {"giver": s.name}))
	out.append(_q("defend", "Оборона: %s" % s.name, "Разведчики видели отряд, идущий на %s. Помогите отбить нападение." % s.name,
		[_obj("defend", "Отбить нападение на %s" % s.name, 1, {"pos": [s.pos.x, s.pos.y], "settlement": s.id})], {"gold": gmul * 2, "xp": 180 + lvl * 20, "item": "normal"}, {"giver": s.name}))
	var mat = ["herbs", "iron_ore", "gears", "circuits", "circuits"][era]
	out.append(_q("collect", "Поставка: %s" % ItemDB.base(mat).name, "Мастерам %s нужны материалы." % s.name,
		[_obj("collect", "Собрать: %s" % ItemDB.base(mat).name, 4, {"item": mat})], {"gold": gmul, "xp": 90 + lvl * 10}, {"giver": s.name, "consume": mat}))
	if not cps.is_empty():
		var cp: Dictionary = cps[randi() % cps.size()]
		out.append(_q("capture", "Захват: %s" % cp.get("name", "точка"), "Захватите контрольную точку, чтобы обезопасить округу.",
			[_obj("capture", "Захватить «%s»" % cp.get("name", "точку"), 1, {"poi": cp.id, "pos": [cp.pos.x, cp.pos.y]})], {"gold": gmul * 2, "xp": 160 + lvl * 15}, {"giver": s.name}))
	out.shuffle()
	return out.slice(0, 4)

func _on_accept(q: Dictionary) -> void:
	match q.type:
		"escort":
			world.director.start_caravan(q)
		"defend":
			world.director.start_raid_on(q.objectives[0].settlement, q.id)

func start_faction_trial(fid: String) -> void:
	for q in quests:
		if q.get("faction_trial", "") == fid:
			Events.notify.emit("Испытание уже начато: " + q.title, Color(1, 0.85, 0.4))
			return
	var f: Dictionary = DBEras.faction(fid)
	var enemy_team := "bandit"
	var n := 5 + Profile.current_era
	var q := _q("trial", "Испытание: %s" % f.name, "Чтобы вступить в «%s», докажите силу: одолейте врагов дорог." % f.name,
		[_obj("kill_team", "Победить разбойников или чудовищ", n, {"team": [enemy_team, "monster"]})],
		{"gold": 50 * (Profile.current_era + 1), "xp": 150, "rep": {fid: 20}}, {"faction": fid, "faction_trial": fid, "abandonable": true})
	accept(q)

func start_release_quest(item: Dictionary) -> void:
	var q := _q("ritual", "Освобождение", "Проклятый предмет «%s» не отпускает вас. Очистите душу в бою и принесите дар алтарю." % ItemDB.display_name(item),
		[_obj("kill_team", "Одолеть проклятых и чудовищ", 6, {"team": ["monster"]}), _obj("collect", "Собрать травы для ритуала", 3, {"item": "herbs"})],
		{"xp": 200, "gold": 40}, {"release_uid": item.uid, "consume": "herbs", "abandonable": false})
	accept(q)

## Dynamic chain: a thief stole an item during an escort.
func start_thief_chase(thief, stolen: Dictionary) -> void:
	var q := _q("retrieve", "Погоня за вором", "%s похитил «%s» из каравана! Догоните и верните." % [thief.display_name, ItemDB.display_name(stolen)],
		[_obj("kill_target", "Догнать вора: %s" % thief.display_name, 1, {"target_id": thief.actor_id})], {"gold": 120 * (Profile.current_era + 1), "xp": 160, "item": "elite"},
		{"abandonable": true})
	q.tracked = true
	for o in quests:
		o.tracked = false
	accept(q)
	q.tracked = true

# ---------------------------------------------------------------- progress
func _progress(pred: Callable, amount: int = 1) -> void:
	for q in quests.duplicate():
		var changed := false
		for o in q.objectives:
			if o.done:
				continue
			if pred.call(o, q):
				o.cur = mini(o.need, o.cur + amount)
				if o.cur >= o.need:
					o.done = true
				changed = true
			break   # objectives are sequential
		if changed:
			Events.quest_updated.emit(q)
			_check_complete(q)

func _on_killed(victim, killer) -> void:
	var k = killer
	if k != null and is_instance_valid(k) and k.owner_actor != null and is_instance_valid(k.owner_actor):
		k = k.owner_actor
	var by_player: bool = k != null and is_instance_valid(k) and k.is_player
	_progress(func(o, _q):
		if o.kind == "kill_target" and o.get("target_id", "") == victim.actor_id:
			return true
		if o.kind == "kill_team" and by_player and victim.team in o.get("team", []):
			return true
		if o.kind == "boss" and victim is Boss and victim.boss_id == o.get("boss_id", ""):
			return true
		return false)

func _on_chest(a, chest) -> void:
	if a == null or not a.is_player:
		return
	_progress(func(o, _q):
		return o.kind == "loot_chest" and Vector2(chest.global_position.x, chest.global_position.z).distance_to(Vector2(o.pos[0], o.pos[1])) < 60.0)

func _on_item(a, _it) -> void:
	if a == null or not a.is_player:
		return
	for q in quests:
		for o in q.objectives:
			if o.kind == "collect" and not o.done:
				o.cur = mini(o.need, a.data.inv.count(o.item))
				if o.cur >= o.need:
					o.done = true
					Events.quest_updated.emit(q)
					_check_complete(q)

func _on_captured(pid, owner_f) -> void:
	var m: String = world.factions.member_of()
	if owner_f == "player" or (m != "" and owner_f == m):
		_progress(func(o, _q): return o.kind == "capture" and o.get("poi", "") == pid)

func on_chronicle(ev: Dictionary) -> void:
	if ev.type == "rift_cleared" and "player" in ev.actors:
		_progress(func(o, _q): return o.kind == "rift")

func on_camp_cleared(poi_id: String) -> void:
	_progress(func(o, _q): return o.kind == "clear_camp" and o.get("poi", "") == poi_id)

func on_defend_result(qid: String, success: bool) -> void:
	for q in quests:
		if q.id == qid:
			if success:
				q.objectives[0].cur = 1
				q.objectives[0].done = true
				_check_complete(q)
			else:
				_fail(q, "Поселение не удалось защитить.")
			return

func on_escort_result(qid: String, success: bool, msg: String = "") -> void:
	for q in quests:
		if q.id == qid:
			if success:
				q.objectives[0].cur = 1
				q.objectives[0].done = true
				_check_complete(q)
			else:
				_fail(q, msg)
			return

func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5 or world.player == null or not is_instance_valid(world.player):
		return
	_tick = 0.0
	var pp: Vector3 = world.player.global_position
	_progress(func(o, _q):
		return o.kind == "reach" and Vector2(pp.x, pp.z).distance_to(Vector2(o.pos[0], o.pos[1])) < o.get("radius", 10.0))

func _check_complete(q: Dictionary) -> void:
	for o in q.objectives:
		if not o.done:
			return
	quests.erase(q)
	q.state = "done"
	done.append(q)
	var r: Dictionary = q.reward
	var pd: CharData = world.player.data
	if q.has("consume"):
		pd.inv.consume(q.consume, q.objectives[-1].need if q.objectives[-1].kind == "collect" else 0)
	pd.gold += int(r.get("gold", 0))
	world.player.gain_xp(int(r.get("xp", 0)))
	if r.get("item", "") != "":
		var it := ItemDB.random_for_era(Profile.current_era, world.player.level, r.item, 0.1)
		if not pd.inv.add(it):
			world.loot.spawn_drop(it, pp_safe())
		Events.notify.emit("Награда: " + ItemDB.display_name(it), ItemDB.rarity_color(it))
	if r.get("shards", 0) > 0:
		var sh := ItemDB.create("chrono_shard", 0, 1)
		sh.qty = r.shards
		pd.inv.add(sh)
	for f in r.get("rep", {}):
		world.factions.add_rep(f, r.rep[f], "задание")
	if q.get("faction", "") != "" and not q.has("faction_trial"):
		world.factions.add_rep(q.faction, 25.0, "задание")
	elif q.get("giver", "") != "":
		var m: String = world.factions.member_of()
		if m != "":
			world.factions.add_rep(m, 10.0, "помощь жителям")
	if q.has("faction_trial"):
		world.factions.complete_trial(q.faction_trial)
	if q.has("release_uid"):
		world.player.purify("quest")
	Chronicle.record("quest_done", [world.player], {"pos_v3": world.player.global_position, "extra": {"quest": q.title}})
	Events.quest_completed.emit(q)
	Events.banner.emit("Задание выполнено", q.title + " — " + q.reward_text, Color(0.6, 1.0, 0.6))
	Audio.play_sfx("quest_done")
	if not quests.is_empty() and tracked_quest().is_empty():
		quests[0].tracked = true

func pp_safe() -> Vector3:
	return world.player.global_position if world.player else Vector3.ZERO

func _fail(q: Dictionary, msg: String) -> void:
	quests.erase(q)
	q.state = "failed"
	done.append(q)
	Chronicle.record("quest_failed", [world.player], {"extra": {"quest": q.title}})
	Events.banner.emit("Задание провалено", msg, Color(1.0, 0.5, 0.4))
