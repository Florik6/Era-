extends Node
## Persistent meta-progression: the main character, unlocked eras, achievements,
## legacy between eras, archive of legends, Last Witness relationship.

const ACHIEVEMENTS := {
	"first_blood": ["Первая кровь", "Победите первого противника."],
	"level_10": ["Закалённый", "Достигните 10 уровня."],
	"level_25": ["Ветеран эпох", "Достигните 25 уровня."],
	"boss_slayer": ["Убийца боссов", "Победите босса."],
	"era_bosses": ["Покоритель эпохи", "Победите всех боссов одной эпохи."],
	"legendary": ["Золотой блеск", "Найдите легендарный предмет."],
	"mythic": ["Багровое чудо", "Найдите мифический предмет."],
	"curse_broken": ["Свободный", "Освободитесь от несъёмного проклятия."],
	"living_evolved": ["Душа клинка", "Пробудите живое оружие."],
	"faction_rank": ["Карьерист", "Получите звание Ветерана в организации."],
	"faction_leader": ["Лидер", "Станьте лидером организации."],
	"era_1": ["Эпоха Возрождения", "Откройте Возрождение."],
	"era_2": ["Век пара", "Откройте Индустриальную эпоху."],
	"era_3": ["Наше время", "Откройте Современность."],
	"era_4": ["За горизонтом", "Откройте Будущее."],
	"legend_slain": ["Конец легенды", "Победите живую легенду."],
	"mercy": ["Милосердие", "Пощадите поверженного противника."],
	"rift_master": ["Покоритель разломов", "Пройдите 5 разломов."],
	"fortress": ["Владелец крепости", "Получите собственную крепость."],
	"chrono_double": ["Победа над собой", "Победите хронодвойника."],
	"mimic": ["Не всё то золото", "Победите мимика."],
	"capture": ["Захватчик", "Захватите контрольную точку."],
	"arena_10": ["Гладиатор", "Выживите 10 волн на Арене."],
	"multi_master": ["Мастер на все руки", "Мастерство 5 в трёх категориях оружия."],
	"spell_100": ["Чародей", "Произнесите 100 заклинаний."],
	"witness": ["Свидетель", "Встретьте Последнего Свидетеля в трёх эпохах."],
	"ascension": ["Восхождение", "Победите Хронопожирателя."],
}

var char := CharData.new()
var has_character := false
var current_era := 0
var unlocked_eras: Array = [0]
var era_progress := {}        # "0" -> {milestones: {}, trial_done: bool, bosses: []}
var achievements := {}        # id -> unix time
var stats := {}               # kills, deaths, bosses, spells, rifts, legendary...
var legacy := {"flags": {}, "relics": [], "faction_power": {}, "faction_rep": {}, "destroyed": []}
var fallen_legends: Array = [] # archive of dead legends (all eras)
var hall_of_legends: Array = [] # notable living legends carried to history
var artifacts: Array = []     # items that survive era transitions (stored when left behind)
var witness := {"relation": 0.0, "met": [], "variant": -1, "hostile": false, "trades": 0}
var world_seed := 0
var arena_best := 0
var arena_tokens := 0
var play_time := 0.0
var tutorial_done := false

func _process(delta: float) -> void:
	if has_character:
		play_time += delta

func new_character(nm: String, cid: String, female: bool, appearance: Dictionary) -> void:
	char = CharData.new()
	char.name = nm if nm.strip_edges() != "" else "Странник"
	char.female = female
	char.appearance = appearance
	char.setup_class(cid)
	for b in ItemDB.CLASS_KITS.get(cid, []):
		var it := ItemDB.create(b, 0, 1, null, false)
		char.inv.add(it)
		if ItemDB.base(b).slot in ItemDB.SLOTS and char.inv.equipped(ItemDB.base(b).slot).is_empty():
			char.inv.equip_item(it)
	char.auto_slots(_main_cat())
	has_character = true
	current_era = 0
	unlocked_eras = [0]
	era_progress = {}
	achievements = {}
	stats = {}
	legacy = {"flags": {}, "relics": [], "faction_power": {}, "faction_rep": {}, "destroyed": []}
	fallen_legends = []
	hall_of_legends = []
	artifacts = []
	world_seed = randi() % 900000 + 1000
	witness = {"relation": 0.0, "met": [], "variant": randi() % 4, "hostile": false, "trades": 0}
	play_time = 0.0
	tutorial_done = false

func _main_cat() -> String:
	var w := char.inv.equipped("main")
	if w.is_empty():
		return "unarmed"
	return ItemDB.base(w.base).get("cat", "unarmed")

func progress(era_i: int) -> Dictionary:
	var k := str(era_i)
	if not era_progress.has(k):
		era_progress[k] = {"milestones": {}, "trial_done": false, "bosses": [], "shards_used": false}
	return era_progress[k]

func milestone(key: String, era_i: int = -1) -> void:
	if era_i < 0:
		era_i = current_era
	var p := progress(era_i)
	if p.milestones.has(key):
		return
	var era_def: Dictionary = DBEras.era(era_i)
	if not era_def.milestones.has(key):
		return
	p.milestones[key] = true
	Events.notify.emit("Веха эпохи: " + era_def.milestones[key], Color(1.0, 0.85, 0.4))

func boss_defeated(boss_id: String) -> void:
	var b: Dictionary = DBActors.BOSSES.get(boss_id, {})
	var era_i: int = b.get("era", current_era)
	if era_i < 0:
		return
	var p := progress(era_i)
	if not boss_id in p.bosses:
		p.bosses.append(boss_id)
	milestone("boss", era_i)
	add_stat("bosses")
	unlock("boss_slayer")
	if p.bosses.size() >= DBEras.era(era_i).bosses.size():
		milestone("all_bosses", era_i)
		unlock("era_bosses")

## Returns {ready: bool, lines: Array[[text, ok]]}
func trial_status(era_i: int) -> Dictionary:
	var e: Dictionary = DBEras.era(era_i)
	var t: Dictionary = e.trial
	var lines: Array = []
	if t.is_empty():
		return {"ready": false, "lines": [["Это последняя эпоха. Победите Хронопожирателя.", false]]}
	var p := progress(era_i)
	var ok_lvl = char.level >= t.level
	lines.append(["Уровень %d (сейчас %d)" % [t.level, char.level], ok_lvl])
	var shards := char.inv.count("chrono_shard")
	var ok_sh = shards >= t.shards
	lines.append(["Осколки Хроноса: %d/%d" % [shards, t.shards], ok_sh])
	var ok_relic := char.inv.count(t.relic) > 0
	lines.append(["Реликвия: %s" % ItemDB.base(t.relic).name, ok_relic])
	var done: int = p.milestones.size()
	var ok_ms = done >= t.need_milestones
	lines.append(["Освоенные механики эпохи: %d/%d" % [done, t.need_milestones], ok_ms])
	var ok_req := true
	for r in t.get("require", []):
		var has: bool = p.milestones.has(r)
		ok_req = ok_req and has
		lines.append(["Обязательно: " + e.milestones.get(r, r), has])
	return {"ready": ok_lvl and ok_sh and ok_relic and ok_ms and ok_req, "lines": lines}

func unlock_era(i: int) -> void:
	if i >= DBEras.ERA_COUNT:
		return
	progress(i - 1).trial_done = true
	if not i in unlocked_eras:
		unlocked_eras.append(i)
		unlocked_eras.sort()
		unlock("era_%d" % i)

func is_era_unlocked(i: int) -> bool:
	return i in unlocked_eras or Settings.dev_unlock_all

func unlock(id: String) -> void:
	if achievements.has(id) or not ACHIEVEMENTS.has(id):
		return
	achievements[id] = int(Time.get_unix_time_from_system())
	Events.achievement.emit(id)
	Events.banner.emit("Достижение: " + ACHIEVEMENTS[id][0], ACHIEVEMENTS[id][1], Color(1.0, 0.85, 0.3))
	if has_node("/root/Audio"):
		Audio.play_sfx("achievement")

func add_stat(key: String, n: float = 1.0) -> float:
	stats[key] = stats.get(key, 0.0) + n
	return stats[key]

func set_flag(key: String, value = true) -> void:
	legacy.flags[key] = value

func flag(key: String, default = null):
	return legacy.flags.get(key, default)

func to_dict() -> Dictionary:
	return {"char": char.to_dict(), "has_character": has_character, "current_era": current_era, "unlocked_eras": unlocked_eras,
		"era_progress": era_progress, "achievements": achievements, "stats": stats, "legacy": legacy,
		"fallen_legends": fallen_legends, "hall_of_legends": hall_of_legends, "artifacts": artifacts, "witness": witness,
		"world_seed": world_seed, "arena_best": arena_best, "arena_tokens": arena_tokens, "play_time": play_time,
		"tutorial_done": tutorial_done}

func from_dict(d: Dictionary) -> void:
	char = CharData.new()
	char.from_dict(d.get("char", {}))
	has_character = d.get("has_character", false)
	current_era = int(d.get("current_era", 0))
	unlocked_eras = []
	for e in d.get("unlocked_eras", [0]):
		unlocked_eras.append(int(e))
	era_progress = d.get("era_progress", {})
	achievements = d.get("achievements", {})
	stats = d.get("stats", {})
	legacy = d.get("legacy", legacy)
	for k in ["flags", "relics", "faction_power", "faction_rep", "destroyed"]:
		if not legacy.has(k):
			legacy[k] = {} if k in ["flags", "faction_power", "faction_rep"] else []
	fallen_legends = d.get("fallen_legends", [])
	hall_of_legends = d.get("hall_of_legends", [])
	artifacts = d.get("artifacts", [])
	witness = d.get("witness", witness)
	world_seed = int(d.get("world_seed", 1234))
	arena_best = int(d.get("arena_best", 0))
	arena_tokens = int(d.get("arena_tokens", 0))
	play_time = float(d.get("play_time", 0.0))
	tutorial_done = d.get("tutorial_done", false)
