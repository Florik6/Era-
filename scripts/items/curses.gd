class_name Curses
extends RefCounted
## One restriction model for every era: magical curses, spirit bonds and
## technological locks (an exosuit whose AI refuses to let go). Altars,
## alchemists, occult workshops, anomaly labs and deactivation stations all
## run the same rituals with era-specific names.
##
## Curse dict on an item: {id, bound, hidden, release, active, boss_id?}
##  bound+active  → the item can't be removed or replaced
##  hidden        → negative properties not yet identified
## Every curse has at least one reachable release: the universal rituals
## below accept any curse (cost scales with the item), plus the item's own
## native method (night ritual, scroll, boss, quest, terminal).

const KIND_NAMES := {"magic": "Магическое проклятие", "spirit": "Духовная связь", "tech": "Технологическая блокировка", "time": "Временной паразит"}
const SEVERITY_NAMES := ["Слабое", "Сильное", "Мифическое"]

## Era flavour: station name, ritual names (identify, simple, great, bond, mythic).
const ERA_FLAVOUR := [
	{"title": "Древний алтарь очищения", "identify": "Определить проклятие", "simple": "Простое очищение", "great": "Великое очищение", "bond": "Разрыв духовной связи", "mythic": "Очищение мифического предмета"},
	{"title": "Алхимический алтарь очищения", "identify": "Алхимический анализ", "simple": "Очищение солями", "great": "Великая трансмутация", "bond": "Растворение связи", "mythic": "Магнум опус очищения"},
	{"title": "Оккультная мастерская", "identify": "Спектральный анализ", "simple": "Гальваническое очищение", "great": "Экзорцизм на эфирной машине", "bond": "Разрыв эфирной цепи", "mythic": "Великий оккультный протокол"},
	{"title": "Лаборатория аномалий", "identify": "Сканирование аномалии", "simple": "Нейтрализация", "great": "Полная деконтаминация", "bond": "Отключение связи", "mythic": "Протокол «Феникс»"},
	{"title": "Станция деактивации", "identify": "Диагностика системы", "simple": "Перезапуск модуля", "great": "Глубокая очистка прошивки", "bond": "Взлом блокировки снятия", "mythic": "Уничтожение временного паразита"},
]

static func flavour(era: int) -> Dictionary:
	return ERA_FLAVOUR[clampi(era, 0, ERA_FLAVOUR.size() - 1)]

static func is_cursed(item: Dictionary) -> bool:
	return item.get("curse", {}).size() > 0

static func severity(item: Dictionary) -> int:
	var r: int = item.get("rarity", 0)
	return 2 if r >= 5 else (1 if r >= 3 else 0)

static func kind(item: Dictionary) -> String:
	var c: Dictionary = item.get("curse", {})
	if c.get("release", "") == "tech" or (ItemDB.base(item.get("base", "")).get("era", 0) >= 4 and c.get("release", "") != "boss"):
		return "tech"
	if c.get("release", "") in ["boss", "quest"]:
		return "spirit"
	if item.get("mythic", "") == "chrono_rewind" or item.get("mythic", "") == "time_echo":
		return "time"
	return "magic"

static func curse_name(item: Dictionary) -> String:
	var c: Dictionary = item.get("curse", {})
	if c.get("hidden", true):
		return "Неизвестное проклятие"
	return ItemDB.CURSES.get(c.get("id", ""), {}).get("name", "Проклятие")

static func curse_desc(item: Dictionary) -> String:
	var c: Dictionary = item.get("curse", {})
	if c.get("hidden", true):
		return "Отрицательные свойства скрыты. Проведите определение, чтобы узнать их и способы освобождения."
	return ItemDB.CURSES.get(c.get("id", ""), {}).get("desc", "")

static func is_bound(item: Dictionary) -> bool:
	return item.get("curse", {}).get("bound", false)

## Cursed items of a character: equipped first, then the bag.
static func cursed_items(data) -> Array:
	var out: Array = []
	for s in ItemDB.SLOTS:
		var it: Dictionary = data.inv.equip.get(s, {})
		if not it.is_empty() and is_cursed(it):
			out.append({"item": it, "slot": s, "equipped": true})
	for it in data.inv.items:
		if is_cursed(it):
			out.append({"item": it, "slot": ItemDB.base(it.get("base", "")).get("slot", ""), "equipped": false})
	return out

static func _boss_defeated_any() -> bool:
	for k in Game.world_state.get("bosses", {}):
		if Game.world_state.bosses[k].get("defeated", false):
			return true
	return false

static func _power_loss(item: Dictionary) -> float:
	if item.has("curse_boost"):
		return 1.0 - 1.0 / float(item.curse_boost)
	if item.get("unique", "") != "" and ItemDB.UNIQUES.get(item.unique, {}).has("curse"):
		return 0.15
	return 0.0

## Ritual list for one item at a station ("altar" or "tech").
## Each: {id, name, desc, effect, consequence, costs{gold, items{base:qty}},
##        available, reason, native}
static func rituals_for(item: Dictionary, pl, station: String = "altar") -> Array:
	var out: Array = []
	if not is_cursed(item):
		return out
	var era := Profile.current_era
	var fl := flavour(era)
	var c: Dictionary = item.curse
	var sev := severity(item)
	var k := kind(item)
	var m := era + 1
	var loss := _power_loss(item)
	var loss_txt := ("Сила, заключённая в проклятии, уйдёт: урон/броня −%d%%." % roundi(loss * 100.0)) if loss > 0.0 else "Характеристики предмета не изменятся."
	var keep_txt := "Уникальные способности, история и улучшения сохранятся."
	if c.get("hidden", true):
		out.append(_r("identify", fl.identify, "Раскрыть скрытые свойства до принятия решения.", "reveal",
			"Станут известны тип проклятия, отрицательные свойства и способы освобождения. Предмет не изменится.",
			{"gold": 25 * m, "items": {}}, pl))
		if pl.data.inv.count("scroll_identify") > 0:
			out.append(_r("identify_scroll", fl.identify + " (свиток)", "Использовать свиток распознавания.", "reveal",
				"Станут известны свойства проклятия. Свиток будет израсходован.", {"gold": 0, "items": {"scroll_identify": 1}}, pl))
		return out
	var tech_mult := 1.0 if station == "tech" or k != "tech" else 1.5
	if sev == 0:
		out.append(_r("cleanse_simple", fl.simple, "Снимает слабое проклятие полностью.", "cleanse",
			"Отрицательное свойство «%s» исчезнет, снятие станет свободным. %s %s" % [curse_name(item), loss_txt, keep_txt],
			{"gold": int(50 * m * tech_mult), "items": {"herbs": 2, "purify_salt": 1}}, pl))
	if sev <= 1:
		out.append(_r("cleanse_great", fl.great, "Для эпических и легендарных проклятий (и любых слабых).", "cleanse",
			"Проклятие «%s» будет полностью уничтожено. %s %s" % [curse_name(item), loss_txt, keep_txt],
			{"gold": int(140 * m * tech_mult), "items": {"purify_salt": 2, "spirit_essence": 2, "chrono_shard": 1}}, pl))
		if is_bound(item):
			out.append(_r("break_bond", fl.bond, "Разрешает снять предмет, сохраняя его силу и риски.", "unbind",
				"Предмет можно будет снять, заменить и выбросить. Отрицательное свойство «%s» останется, пока предмет надет. Сила сохранится." % curse_name(item),
				{"gold": int(80 * m * tech_mult), "items": {"spirit_essence": 1, "chrono_shard": 1}}, pl))
	else:
		var rr := _r("cleanse_mythic_relic", fl.mythic + " (реликвия)", "Реликвия Освобождения разрывает мифическое проклятие.", "cleanse",
			"Проклятие исчезнет. %s %s" % [loss_txt, keep_txt], {"gold": 0, "items": {"relic_purifier": 1}}, pl)
		out.append(rr)
		var rite := _r("cleanse_mythic", fl.mythic, "Требует редких ингредиентов и победы над боссом этой эпохи.", "cleanse",
			"Проклятие исчезнет. %s %s" % [loss_txt, keep_txt], {"gold": 400 * m, "items": {"chrono_shard": 5, "spirit_essence": 3}}, pl)
		if rite.available and not _boss_defeated_any():
			rite.available = false
			rite.reason = "нужна победа над боссом эпохи"
		out.append(rite)
		if is_bound(item):
			out.append(_r("break_bond_mythic", fl.bond, "Разрывает связь мифического предмета, оставляя проклятие.", "unbind",
				"Предмет можно будет снять. Отрицательные свойства останутся, пока он надет.",
				{"gold": 200 * m, "items": {"chrono_shard": 3, "spirit_essence": 2}}, pl))
	# native methods of this particular curse
	match c.get("release", ""):
		"ritual":
			if station == "altar":
				var nr := _r("night_ritual", "Ночной ритуал", "Родной способ этого проклятия: бесплатно, но пробуждает стражей тьмы.", "cleanse",
					"Проклятие исчезнет, но рядом появятся враги. %s" % loss_txt, {"gold": 0, "items": {}}, pl)
				nr.native = true
				if not Game.is_night():
					nr.available = false
					nr.reason = "только ночью"
				out.append(nr)
		"purify":
			var sr := _r("scroll_purify", "Свиток очищения", "Родной способ: свиток снимает это проклятие.", "cleanse",
				"Проклятие исчезнет. %s" % loss_txt, {"gold": 0, "items": {"scroll_purify": 1}}, pl)
			sr.native = true
			out.append(sr)
		"tech":
			var tr := _r("tech_override", "Отключение управляющей системы", "Родной способ: взлом встроенного ИИ на терминале или в мастерской.", "cleanse",
				"Блокировка и паразитный модуль будут удалены. %s" % loss_txt, {"gold": 60 * m, "items": {"circuits": 2}}, pl)
			tr.native = true
			if station != "tech":
				tr.available = false
				tr.reason = "нужен терминал или мастерская"
			out.append(tr)
	return out

static func _r(id: String, nm: String, desc: String, effect: String, consequence: String, costs: Dictionary, pl) -> Dictionary:
	var miss := missing(pl, costs)
	return {"id": id, "name": nm, "desc": desc, "effect": effect, "consequence": consequence, "costs": costs,
		"available": miss.is_empty(), "reason": ("не хватает: " + ", ".join(miss)) if not miss.is_empty() else "", "native": false}

static func missing(pl, costs: Dictionary) -> Array:
	var out: Array = []
	if pl == null or pl.data == null:
		return ["персонаж"]
	if int(costs.get("gold", 0)) > pl.data.gold:
		out.append("%d %s" % [int(costs.gold) - pl.data.gold, DBEras.era(Profile.current_era).currency])
	for b in costs.get("items", {}):
		var need: int = int(costs.items[b])
		var have: int = pl.data.inv.count(b)
		if have < need:
			out.append("%s ×%d" % [ItemDB.base(b).get("name", b), need - have])
	return out

static func cost_lines(pl, costs: Dictionary) -> Array:
	var out: Array = []
	if int(costs.get("gold", 0)) > 0:
		out.append([("%d %s" % [int(costs.gold), DBEras.era(Profile.current_era).currency]), pl.data.gold >= int(costs.gold)])
	for b in costs.get("items", {}):
		var need: int = int(costs.items[b])
		var have: int = pl.data.inv.count(b)
		out.append(["%s ×%d (есть %d)" % [ItemDB.base(b).get("name", b), need, have], have >= need])
	return out

## Charges the costs. Call only after the ritual succeeded.
static func pay(pl, costs: Dictionary) -> bool:
	if not missing(pl, costs).is_empty():
		return false
	pl.data.gold -= int(costs.get("gold", 0))
	for b in costs.get("items", {}):
		pl.data.inv.consume(b, int(costs.items[b]))
	return true

## Applies a ritual's effect to the real item data. Returns a summary line.
static func apply(item: Dictionary, effect: String, ritual_name: String) -> String:
	var c: Dictionary = item.get("curse", {})
	if c.is_empty():
		return ""
	if not item.has("history"):
		item["history"] = []
	var day := Game.day() + 1
	match effect:
		"reveal":
			c.hidden = false
			item.history.append("Проклятие распознано (%s), день %d" % [ritual_name, day])
			return "Распознано: %s — %s" % [curse_name(item), curse_desc(item)]
		"unbind":
			var nm := curse_name(item)
			c.bound = false
			c.hidden = false
			c.erase("active")
			item.history.append("Связь разорвана: %s, день %d" % [ritual_name, day])
			return "Связь разорвана. «%s» остаётся, но предмет можно снять." % nm
		"cleanse":
			var nm2 := curse_name(item)
			var loss := _power_loss(item)
			if loss > 0.0:
				for st in ["dmg", "armor"]:
					if item.get("stats", {}).has(st):
						item.stats[st] = snappedf(float(item.stats[st]) * (1.0 - loss), 0.01)
			item.erase("curse_boost")
			item.curse = {}
			item.history.append("Очищен от проклятия «%s» (%s), день %d" % [nm2, ritual_name, day])
			return "Проклятие «%s» уничтожено." % nm2
	return ""

static func find_item(data, uid: int) -> Dictionary:
	var it: Dictionary = data.inv.find(uid)
	if not it.is_empty():
		return it
	for s in data.inv.equip:
		if int(data.inv.equip[s].get("uid", -1)) == uid:
			return data.inv.equip[s]
	return {}
