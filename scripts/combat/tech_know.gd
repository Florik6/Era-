class_name TechKnow
## Technological Knowledge System.
##
## A hero does not know how to use a technology just by picking it up. The
## knowledge belongs to the character (CharData.tech, saved with the hero),
## not to the current era: what was learnt in the Future is kept back in the
## Middle Ages, and a future weapon can be studied early through books,
## teachers, rift ruins or the hero's own careful experiments.
##
## Three layers:
##   · 8 knowledge indices (categories) — general understanding;
##   · technology FAMILIES (bows, revolvers, pulse weapons…) — the stage
##     I–V of mastery lives here, so a second pulse rifle is not new;
##   · the concrete MODEL — a short familiarisation, and individual study of
##     a rare item's special part (legendary / mythic / anomalous).
##
## Stages: I unknown item · II primary research · III basic understanding
## (can fire, with penalties) · IV confident (special modes, weapon skills)
## · V master. Research (inspection, trials, books, teachers) takes a family
## to III at most; IV and V come only from practice and training.

const CATS := {
	"medieval": "Средневековое оружие",
	"renaissance": "Оружие Возрождения",
	"industrial": "Индустриальные технологии",
	"modern": "Современное огнестрельное оружие",
	"future": "Технологии будущего",
	"energy": "Энергетические системы",
	"mechanisms": "Сложные механизмы",
	"anomalous": "Аномальные устройства",
}
const CAT_ORDER := ["medieval", "renaissance", "industrial", "modern", "future", "energy", "mechanisms", "anomalous"]
## Categories every era's people grow up with.
const ERA_CATS := [["medieval"], ["renaissance"], ["industrial", "mechanisms"], ["modern"], ["future", "energy"]]
const STAGE_NAMES := ["", "Неизвестный предмет", "Первичное исследование", "Базовое понимание", "Уверенное владение", "Мастер технологии"]
const STAGE_SHORT := ["", "I", "II", "III", "IV", "V"]
const XP_STAGE := [0.0, 0.0, 15.0, 40.0, 150.0, 450.0]
const RESEARCH_CAP := 40.0        # inspection / books / basic courses: up to III
const TEACH_CAP := 150.0          # training with a teacher: up to IV
const FAMILIARIZE_SHOTS := 8

## id: [name, category, era, related families, purpose, parts set]
const FAMILIES := {
	"bows": ["Луки", "medieval", 0, ["crossbows"], "дистанционное метательное оружие", "bow"],
	"crossbows": ["Арбалеты", "medieval", 0, ["bows"], "механическое метательное оружие", "crossbow"],
	"matchlocks": ["Замковые ружья и пистоли", "renaissance", 1, ["revolvers"], "пороховое дистанционное оружие", "lock"],
	"revolvers": ["Револьверы", "industrial", 2, ["matchlocks", "autos"], "пороховое оружие с барабаном", "revolver"],
	"rifles": ["Винтовки", "industrial", 2, ["autos", "matchlocks"], "дальнобойное пороховое оружие", "rifle"],
	"shotguns": ["Дробовики", "industrial", 2, ["rifles"], "оружие с дробовым зарядом", "shotgun"],
	"steam": ["Паровые механизмы", "mechanisms", 2, [], "механическое ударное устройство", "steam"],
	"tesla": ["Тесла-излучатели", "energy", 2, ["shock"], "электрическое разрядное оружие", "tesla"],
	"autos": ["Автоматическое оружие", "modern", 3, ["rifles", "revolvers"], "скорострельное огнестрельное оружие", "auto"],
	"shock": ["Шоковые устройства", "energy", 3, ["tesla"], "электрическое контактное оружие", "shock"],
	"smart": ["Умное оружие", "future", 4, ["pulse"], "оружие с самонаведением", "energy"],
	"pulse": ["Импульсное оружие", "future", 4, ["smart", "ion"], "дистанционное энергетическое оружие", "energy"],
	"plasma": ["Плазменное оружие", "future", 4, [], "тяжёлое энергетическое оружие", "energy"],
	"ion": ["Ионные устройства", "future", 4, ["pulse"], "энергетическое метательное оружие", "energy"],
	"energy_blades": ["Энергоклинки", "energy", 4, ["shock"], "энергетическое холодное оружие", "blade"],
}
const SIMPLE_MECH := ["crossbows", "matchlocks", "revolvers", "steam"]
const ENERGY_FAMS := ["tesla", "shock", "smart", "pulse", "plasma", "ion", "energy_blades"]

## Parts examined on the inspection screen: [id, name, real purpose, position
## along the model 0..1, needs knowledge when the technology is far ahead].
const PARTS := {
	"bow": [["string", "Тетива", "натягивается и толкает стрелу", 0.5, false], ["limbs", "Плечи лука", "копят силу натяжения", 0.85, false], ["grip", "Рукоять", "держит лук и направляет стрелу", 0.45, false]],
	"crossbow": [["windlass", "Взводный механизм", "натягивает тугую дугу", 0.15, false], ["trigger", "Спусковой рычаг", "отпускает тетиву", 0.4, false], ["rail", "Ложе с желобом", "направляет болт", 0.75, false]],
	"lock": [["lock", "Замок", "высекает искру и поджигает порох", 0.35, false], ["barrel", "Ствол", "направляет пулю", 0.8, false], ["ramrod", "Шомпол", "забивает заряд в ствол", 0.65, false]],
	"revolver": [["drum", "Барабан", "хранит патроны и подаёт их по очереди", 0.45, false], ["hammer", "Курок", "бьёт по капсюлю патрона", 0.3, false], ["barrel", "Ствол", "направляет пулю", 0.8, false]],
	"rifle": [["action", "Затвор", "подаёт патрон и запирает ствол", 0.4, false], ["magazine", "Магазин", "хранит патроны", 0.45, false], ["sights", "Прицел", "помогает целиться вдаль", 0.6, false]],
	"shotgun": [["action", "Перезарядный механизм", "выбрасывает гильзу и подаёт новую", 0.5, false], ["chamber", "Патронник", "держит дробовой заряд", 0.4, false], ["barrel", "Ствол", "направляет сноп дроби", 0.8, false]],
	"steam": [["boiler", "Котёл", "копит давление пара", 0.3, true], ["piston", "Поршень", "превращает давление в удар", 0.7, false], ["valve", "Клапан", "сбрасывает давление разом", 0.5, false]],
	"tesla": [["coil", "Катушка", "копит электрический разряд", 0.55, true], ["capacitor", "Накопитель", "отдаёт ток катушке", 0.3, true], ["emitter", "Излучатель", "выпускает разряд в цель", 0.85, false]],
	"auto": [["magazine", "Магазин", "подаёт патроны", 0.4, false], ["selector", "Переводчик огня", "меняет одиночный огонь на очередь", 0.35, false], ["action", "Затвор", "сам перезаряжает оружие после выстрела", 0.5, true]],
	"shock": [["cell", "Ячейка заряда", "хранит энергию удара", 0.25, true], ["contacts", "Контакты", "передают разряд при касании", 0.85, false], ["switch", "Включатель", "подаёт ток на контакты", 0.4, false]],
	"energy": [["energy", "Энергетический модуль", "хранит и подаёт заряд", 0.25, true], ["panel", "Панель состояния", "показывает остаток заряда и режим", 0.55, false], ["trigger", "Механизм активации", "выпускает накопленный импульс", 0.4, true]],
	"blade": [["emitter", "Излучатель клинка", "формирует лезвие из энергии", 0.7, true], ["cell", "Энергоячейка", "питает клинок", 0.2, true], ["grip", "Рукоять с переключателем", "включает и гасит лезвие", 0.3, false]],
}
const SPECIAL_PART := ["special", "Особый узел", "хранит особую силу этого предмета", 0.6, true]
const DECOYS := ["служит противовесом", "украшение мастера", "охлаждает руки стрелка", "хранит запасные клинки", "показывает направление ветра",
	"заводит часовой механизм", "отпугивает зверей звоном", "служит компасом", "подставка для отдыха", "держит фитиль сухим"]

## Tech Cognition branch: [id, name, description, cost, requirement]
const SKILLS := [
	["tc_curiosity", "Любознательность", "Первичное исследование неизвестных предметов даёт на 50% больше знаний.", 1, ""],
	["tc_mech_sense", "Механическое чутьё", "Простые механизмы (арбалеты, замки, револьверы, паровые машины) изучаются вдвое быстрее.", 1, ""],
	["tc_practical", "Практический ученик", "+50% опыта владения на тренировках и в бою.", 1, ""],
	["tc_era_explorer", "Исследователь эпох", "Чужая эпоха кажется на одну эпоху ближе: меньше деталей требуют особых знаний.", 1, "tc_curiosity"],
	["tc_translation", "Технологический перевод", "Схемы и трактаты дают вдвое больше знаний.", 1, "tc_curiosity"],
	["tc_energy", "Понимание энергетических систем", "Энергетические устройства осваиваются в 1,5 раза быстрее; нагрев −20%.", 2, "tc_mech_sense"],
	["tc_engineer", "Инженерное мышление", "Распознаёт совместимые детали: особые боеприпасы и ячейки доступны со стадии IV.", 2, "tc_mech_sense"],
	["tc_adaptation", "Мастер адаптации", "Родственные модели не требуют ознакомления; штрафы стадии III меньше на 30%.", 2, "tc_practical"],
	["tc_archeotech", "Археотехнолог", "Древние и аномальные устройства и особые узлы артефактов изучаются вдвое быстрее.", 2, "tc_era_explorer"],
	["tc_genius", "Гений эпох", "Технологии намного выше уровня эпохи: детали понимаются с одного испытания, опыт ×1,25.", 3, "tc_era_explorer"],
]

## Penalties / bonuses of the stage for the weapon in hand.
const STAGE_MODS := {
	3: {"spread": 2.2, "interval": 1.5, "reload": 1.8, "heat": 1.5, "hand": 0.25},
	4: {"spread": 1.25, "interval": 1.1, "reload": 1.2, "heat": 1.1, "hand": 0.65},
	5: {"spread": 0.9, "interval": 0.95, "reload": 0.9, "heat": 1.0, "hand": 1.0},
}

static var stats := {"refused": 0, "studied_parts": 0, "practice": 0.0, "taught": 0, "manuals": 0, "stage_ups": 0}

# ================================================================== data
static func family_of(b: Dictionary) -> String:
	if b.has("tech"):
		return str(b.tech)
	var model := str(b.get("model", ""))
	match model:
		"bow", "longbow":
			return "bows"
		"crossbow":
			return "ion" if int(b.get("era", 0)) >= 4 else "crossbows"
		"musket", "pistol_old":
			return "matchlocks"
		"revolver":
			return "revolvers"
		"rifle":
			return "rifles"
		"shotgun":
			return "shotguns"
		"carbine", "pistol", "smg":
			return "autos"
		"tesla_gun":
			return "tesla"
		"pulse_rifle":
			return "pulse"
		"plasma_cannon":
			return "plasma"
		"smart_gun":
			return "smart"
		"energy_blade":
			return "energy_blades"
		"baton":
			return "shock"
		"steam_hammer":
			return "steam"
	return ""        # simple blades and magic foci: nothing technological to learn

static func item_family(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	return family_of(ItemDB.base(str(it.get("base", ""))))

static func fam_name(fam: String) -> String:
	return str(FAMILIES[fam][0]) if FAMILIES.has(fam) else ""

static func fam_cat(fam: String) -> String:
	return str(FAMILIES[fam][1]) if FAMILIES.has(fam) else ""

static func fam_era(fam: String) -> int:
	return int(FAMILIES[fam][2]) if FAMILIES.has(fam) else 0

## A rare item has its own special part to study (legendary art, mythic).
static func has_special(it: Dictionary) -> bool:
	if it.is_empty():
		return false
	var b := ItemDB.base(str(it.get("base", "")))
	return b.has("art") or int(it.get("rarity", 0)) >= 5 or str(it.get("mythic", "")) != "" or b.get("anomalous", false)

static func stage_of_xp(x: float) -> int:
	if x >= XP_STAGE[5]:
		return 5
	if x >= XP_STAGE[4]:
		return 4
	if x >= XP_STAGE[3]:
		return 3
	if x >= XP_STAGE[2]:
		return 2
	return 1

# ================================================================== character state
static func _fam_rec(d, fam: String) -> Dictionary:
	if not d.tech.has(fam):
		d.tech[fam] = {"xp": 0.0, "research": 0.0}
	return d.tech[fam]

static func raw_xp(d, fam: String) -> float:
	return float(d.tech.get(fam, {}).get("xp", 0.0))

static func cat_xp(d, cat: String) -> float:
	return float(d.tech_cats.get(cat, 0.0))

static func has_skill(d, id: String) -> bool:
	return d != null and id in d.tech_skills

static func model_rec(d, base_id: String) -> Dictionary:
	if not d.tech_models.has(base_id):
		d.tech_models[base_id] = {"fam": false, "parts": [], "streak": {}, "special": false, "shots": 0, "examined": false, "identified": false, "compared": false}
	return d.tech_models[base_id]

static func model_known(d, base_id: String) -> bool:
	return d.has_meta("tech_all") or bool(d.tech_models.get(base_id, {}).get("fam", false))

## Effective experience: own practice + general category knowledge (up to
## basic understanding) + a related family (primary understanding).
static func fam_xp(d, fam: String) -> float:
	if not FAMILIES.has(fam):
		return XP_STAGE[5]
	var x := raw_xp(d, fam)
	x = maxf(x, minf(cat_xp(d, fam_cat(fam)), RESEARCH_CAP))
	for r in FAMILIES[fam][3]:
		if stage_of_xp(raw_xp(d, str(r))) >= 4:
			x = maxf(x, XP_STAGE[2])
	return x

static func max_known_era(d) -> int:
	var m := 0
	for e in d.tech_mem.get("eras", [0]):
		m = maxi(m, int(e))
	return m

# ================================================================== stages
static func family_stage(a, fam: String) -> int:
	if fam == "" or not FAMILIES.has(fam):
		return 5
	if a == null or a.data == null:
		return 5        # monsters: natural weapons
	if not a.is_player:
		return npc_stage(a, fam)
	return stage_of_xp(fam_xp(a.data, fam))

## Stage for a concrete item: a new model of a known family needs a short
## familiarisation first (until then it is handled at stage III at most).
static func item_stage(a, it: Dictionary) -> int:
	var fam := item_family(it)
	if fam == "":
		return 5
	var s := family_stage(a, fam)
	if a != null and a.is_player and s >= 4 and not model_known(a.data, str(it.base)) and not has_skill(a.data, "tc_adaptation"):
		s = 3
	return s

static func weapon_stage(a) -> int:
	return item_stage(a, a.weapon()) if a != null and a.data != null else 5

static func can_fire(a) -> bool:
	return weapon_stage(a) >= 3

static func can_special(a) -> bool:
	return weapon_stage(a) >= 4

static func can_special_ammo(a) -> bool:
	var s := weapon_stage(a)
	return s >= 5 or (s >= 4 and a.is_player and has_skill(a.data, "tc_engineer"))

static func mods(a) -> Dictionary:
	var s := clampi(weapon_stage(a), 3, 5)
	var m: Dictionary = STAGE_MODS[s].duplicate()
	if s == 3 and a != null and a.is_player and has_skill(a.data, "tc_adaptation"):
		for k in ["spread", "interval", "reload", "heat"]:
			m[k] = 1.0 + (float(m[k]) - 1.0) * 0.7
	if a != null and a.is_player and has_skill(a.data, "tc_energy") and ENERGY_FAMS.has(item_family(a.weapon())):
		m.heat = float(m.heat) * 0.8
	return m

## How sure the hands are (rig animation): 0 novice … 1 master.
static func handling(a) -> float:
	var s := weapon_stage(a)
	if s <= 2:
		return 0.0
	return float(STAGE_MODS[s].hand)

## Weapon skills of a technological weapon: the first three need confident
## handling (IV), the advanced ones mastery (V).
static func skill_block(a, e: Dictionary) -> String:
	if e.get("kind", "") != "weapon" or a == null or a.data == null:
		return ""
	var fam := item_family(a.weapon())
	if fam == "":
		return ""
	var need := 5 if int(e.get("n", 1)) >= 4 else 4
	var s := weapon_stage(a)
	if s < need:
		return "нужно владение технологией «%s»: %s (сейчас %s)" % [fam_name(fam), STAGE_SHORT[need], STAGE_SHORT[s]]
	return ""

## Special abilities of a rare item (legendary art, mythic power).
static func special_ok(a, it: Dictionary) -> bool:
	if a == null or not a.is_player or it.is_empty():
		return true
	var d = a.data
	var b := ItemDB.base(str(it.base))
	var out_of_era: bool = int(b.get("era", 0)) > max_known_era(d)
	if d.has_meta("tech_all"):
		return true
	if int(it.get("rarity", 0)) >= 5 or out_of_era or b.get("anomalous", false):
		return bool(d.tech_models.get(str(it.base), {}).get("special", false))
	return item_stage(a, it) >= 4

## Full mastery of a rare item: specials at 75 % power until the family (or,
## for magic foci, the best school) is mastered.
static func special_power(a, it: Dictionary) -> float:
	if a == null or not a.is_player or it.is_empty():
		return 1.0
	var fam := item_family(it)
	if fam != "":
		return 1.0 if item_stage(a, it) >= 5 else 0.75
	var best := 0
	for s in a.data.schools:
		best = maxi(best, int(a.data.schools[s].lvl))
	return 1.0 if best >= 16 or str(ItemDB.base(str(it.base)).get("cat", "")) != "staff" else 0.75

# ================================================================== NPCs
## NPCs know the weapons they were given and their own era's technology; a
## medieval guard does not understand an energy cannon he found.
static func npc_stage(a, fam: String) -> int:
	var d = a.data
	if not d.tech.has("_init"):
		d.tech["_init"] = {"xp": 0.0}
		var soldier: bool = str(a.get("role")) in ["soldier", "hunter", "guard", "enemy", "bot"]
		for it in d.inv.all_equipped() + d.inv.items:
			var f := item_family(it)
			if f != "":
				_fam_rec(d, f).xp = maxf(raw_xp(d, f), XP_STAGE[5] if soldier else XP_STAGE[4])
	if d.tech.has(fam):
		return stage_of_xp(raw_xp(d, fam))
	if str(a.get("role")) == "witness" or a.has_meta("era_traveler"):
		return 4
	var home := int(a.get_meta("home_era", Profile.current_era))
	return 4 if fam_era(fam) <= home else 1

static func npc_can_use(a, it: Dictionary) -> bool:
	return item_stage(a, it) >= 3

# ================================================================== progress
static func add_xp(d, fam: String, amount: float, cap := -1.0, why := "") -> float:
	if d == null or not FAMILIES.has(fam) or amount <= 0.0:
		return 0.0
	var r := _fam_rec(d, fam)
	var before_stage := stage_of_xp(fam_xp(d, fam))
	var x := float(r.xp)
	var target := x + amount
	if cap >= 0.0:
		target = minf(target, maxf(x, cap))
	r.xp = target
	var after_stage := stage_of_xp(fam_xp(d, fam))
	if after_stage > before_stage:
		_on_stage_up(d, fam, after_stage)
	return target - x

static func _on_stage_up(d, fam: String, st: int) -> void:
	stats.stage_ups += 1
	if st == 3 or st == 5:
		d.tech_pts += 1         # Tech Cognition points: basic understanding and mastery
	if d == Profile.char:
		Events.notify.emit("Технология «%s»: %s (%s)" % [fam_name(fam), STAGE_NAMES[st], STAGE_SHORT[st]], Color(0.55, 0.9, 1.0))
		Audio.play_sfx("mastery_up", null, -6.0)

static func _research_mult(d, fam: String) -> float:
	var m := 1.0
	if has_skill(d, "tc_curiosity"):
		m *= 1.5
	if has_skill(d, "tc_mech_sense") and SIMPLE_MECH.has(fam):
		m *= 2.0
	if has_skill(d, "tc_energy") and ENERGY_FAMS.has(fam):
		m *= 1.5
	if has_skill(d, "tc_genius") and gap(d, fam) >= 2:
		m *= 1.25
	return m

## Research points (inspection, trials, comparison): never past basic understanding.
static func research(d, fam: String, amount: float) -> float:
	var got := add_xp(d, fam, amount * _research_mult(d, fam), RESEARCH_CAP)
	_fam_rec(d, fam).research = float(_fam_rec(d, fam).get("research", 0.0)) + got
	return got

## Practice with a weapon the hero can use: every real shot / swing teaches.
static func practice(a, amount := 1.0) -> void:
	if a == null or not a.is_player or a.data == null:
		return
	var it: Dictionary = a.weapon()
	var fam := item_family(it)
	if fam == "" or item_stage(a, it) < 3:
		return
	var d = a.data
	var m := amount
	if has_skill(d, "tc_practical"):
		m *= 1.5
	if has_skill(d, "tc_energy") and ENERGY_FAMS.has(fam):
		m *= 1.5
	if has_skill(d, "tc_genius") and gap(d, fam) >= 2:
		m *= 1.25
	stats.practice += m
	var mr := model_rec(d, str(it.base))
	mr.shots = int(mr.get("shots", 0)) + 1
	if not bool(mr.fam) and int(mr.shots) >= FAMILIARIZE_SHOTS:
		mr.fam = true          # a few real shots are a familiarisation too
		if d == Profile.char and stage_of_xp(fam_xp(d, fam)) >= 4:
			Events.notify.emit("Вы привыкли к модели «%s»" % ItemDB.base(str(it.base)).get("name", ""), Color(0.6, 0.9, 1.0))
	add_xp(d, fam, m)

## How far ahead of everything the hero has seen a technology is.
static func gap(d, fam: String) -> int:
	var g := fam_era(fam) - max_known_era(d)
	if has_skill(d, "tc_era_explorer"):
		g -= 1
	return maxi(0, g)

## A part that needs real knowledge can be understood directly when the
## technology is close enough, or the hero has general knowledge of the
## category (book, teacher, earlier study); otherwise only a series of trials.
static func part_direct(d, fam: String, needs: bool) -> bool:
	if not needs or gap(d, fam) < 2:
		return true
	var cat := fam_cat(fam)
	return cat_xp(d, cat) >= XP_STAGE[2] or cat in d.tech_mem.get("schemas", []) or cat in d.tech_mem.get("training", [])

static func trials_needed(d, fam: String, needs: bool) -> int:
	if part_direct(d, fam, needs):
		return 1
	return 1 if has_skill(d, "tc_genius") else 3

static func parts_of(it: Dictionary) -> Array:
	var fam := item_family(it)
	var out: Array = []
	if fam != "":
		out.append_array(PARTS.get(str(FAMILIES[fam][5]), []))
	if has_special(it):
		out.append(SPECIAL_PART)
	return out

static func part_def(it: Dictionary, part_id: String) -> Array:
	for p in parts_of(it):
		if str(p[0]) == part_id:
			return p
	return []

static func part_known(d, it: Dictionary, part_id: String) -> bool:
	var mr: Dictionary = d.tech_models.get(str(it.base), {})
	if part_id == "special":
		return bool(mr.get("special", false))
	if part_id in mr.get("parts", []):
		return true
	# a family understood at III+ explains its common parts on any model
	var fam := item_family(it)
	return fam != "" and stage_of_xp(fam_xp(d, fam)) >= 3

# ------------------------------------------------------------ inspection actions
## Look the device over (once per model).
static func examine(d, it: Dictionary) -> String:
	var fam := item_family(it)
	var mr := model_rec(d, str(it.base))
	if bool(mr.examined):
		return "Вы уже осмотрели этот предмет."
	mr.examined = true
	if fam != "":
		research(d, fam, 4.0)
	return "Вы внимательно осматриваете предмет: %s." % _looks(it)

static func _looks(it: Dictionary) -> String:
	var fam := item_family(it)
	match str(FAMILIES.get(fam, ["", "", 0, [], "", ""])[5]):
		"energy":
			return "гладкий корпус без фитиля и пороховой полки, внутри что-то тихо гудит"
		"blade":
			return "рукоять без клинка, на торце — светящаяся линза"
		"tesla", "shock":
			return "медные витки и контакты, от них пахнет грозой"
		"auto", "rifle", "revolver", "shotgun":
			return "стальной ствол и много подвижных деталей"
		"lock":
			return "ствол, кремень и полка для пороха"
		"steam":
			return "котёл, трубки и тяжёлый поршень"
	return "знакомая работа мастеров"

## Try to work out what the thing is for.
static func identify(d, it: Dictionary) -> String:
	var fam := item_family(it)
	if fam == "":
		return "Назначение очевидно."
	var mr := model_rec(d, str(it.base))
	if not bool(mr.identified):
		mr.identified = true
		research(d, fam, 12.0)
	return "Предположительно: %s." % str(FAMILIES[fam][4])

## Compare with something the hero already knows.
static func compare(d, it: Dictionary) -> String:
	var fam := item_family(it)
	if fam == "":
		return "Сравнивать не с чем."
	var best := ""
	for r in FAMILIES[fam][3]:
		if stage_of_xp(raw_xp(d, str(r))) >= 3:
			best = str(r)
	if best == "":
		for f2 in FAMILIES:
			if f2 != fam and fam_cat(str(f2)) == fam_cat(fam) and stage_of_xp(raw_xp(d, str(f2))) >= 3:
				best = str(f2)
	var mr := model_rec(d, str(it.base))
	if best == "":
		return "Ничего похожего вы раньше не держали в руках."
	if not bool(mr.compared):
		mr.compared = true
		research(d, fam, 10.0)
	return "Похоже на «%s»: часть деталей вам понятна." % fam_name(best)

## Trial answers for a part: the real purpose and two wrong guesses.
static func trial_options(it: Dictionary, part_id: String, seed_v := 0) -> Array:
	var p := part_def(it, part_id)
	if p.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(it.base) + part_id) + seed_v
	var pool: Array = DECOYS.duplicate()
	var opts: Array = [str(p[2])]
	while opts.size() < 3 and not pool.is_empty():
		opts.append(pool.pop_at(rng.randi() % pool.size()))
	for i in range(opts.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = opts[i]
		opts[i] = opts[j]
		opts[j] = tmp
	return opts

## The player picked an answer in a trial. {ok, done, msg, left}
static func answer(d, it: Dictionary, part_id: String, choice: String) -> Dictionary:
	var p := part_def(it, part_id)
	var fam := item_family(it)
	if p.is_empty():
		return {"ok": false, "done": false, "msg": "Нечего изучать.", "left": 0}
	if part_known(d, it, part_id):
		return {"ok": true, "done": true, "msg": "Эта деталь вам уже понятна.", "left": 0}
	var mr := model_rec(d, str(it.base))
	var streaks: Dictionary = mr.streak
	if part_id == "special" and not special_study_ok(d, it):
		return {"ok": false, "done": false, "msg": special_need_text(d, it), "left": 0}
	if choice != str(p[2]):
		streaks[part_id] = 0
		return {"ok": false, "done": false, "msg": "Не похоже. %s подсказывает другое — попробуйте ещё раз." % str(p[1]), "left": trials_needed(d, fam, bool(p[4]))}
	var need := trials_needed(d, fam, bool(p[4]))
	if part_id == "special" and has_skill(d, "tc_archeotech"):
		need = 1
	streaks[part_id] = int(streaks.get(part_id, 0)) + 1
	if int(streaks[part_id]) < need:
		return {"ok": true, "done": false, "msg": "Верно. Без знаний эпохи нужно подтвердить догадку: ещё %d испытания подряд." % (need - int(streaks[part_id])), "left": need - int(streaks[part_id])}
	stats.studied_parts += 1
	if part_id == "special":
		mr.special = true
		var g := 2.0 if has_skill(d, "tc_archeotech") else 1.0
		d.tech_cats["anomalous"] = cat_xp(d, "anomalous") + 8.0 * g
		return {"ok": true, "done": true, "msg": "Вы поняли особый узел: особые способности предмета доступны.", "left": 0}
	var parts: Array = mr.parts
	if not part_id in parts:
		parts.append(part_id)
	if fam != "":
		research(d, fam, 14.0)
	return {"ok": true, "done": true, "msg": "Понятно: %s — %s." % [str(p[1]), str(p[2])], "left": 0}

## Rare item's special part: a technological item needs confident handling,
## a magic focus needs real magic mastery.
static func special_study_ok(d, it: Dictionary) -> bool:
	var fam := item_family(it)
	if fam != "":
		return stage_of_xp(fam_xp(d, fam)) >= 4 or has_skill(d, "tc_archeotech")
	var best := 0
	for s in d.schools:
		best = maxi(best, int(d.schools[s].lvl))
	return best >= 8 or has_skill(d, "tc_archeotech") or cat_xp(d, "anomalous") >= 40.0

static func special_need_text(d, it: Dictionary) -> String:
	var fam := item_family(it)
	if fam != "":
		return "Особый узел станет понятен при уверенном владении (IV) технологией «%s»." % fam_name(fam)
	return "Чтобы понять особую силу предмета, нужно мастерство магии 8 или навык «Археотехнолог»."

## A new model of a family the hero already handles: a short introduction.
static func familiarize(d, it: Dictionary) -> String:
	var fam := item_family(it)
	if fam == "":
		return ""
	if stage_of_xp(fam_xp(d, fam)) < 3:
		return "Сначала нужно понять саму технологию."
	var mr := model_rec(d, str(it.base))
	mr.fam = true
	return "Вы ознакомились с моделью «%s»: принципы те же, что у «%s»." % [ItemDB.base(str(it.base)).get("name", ""), fam_name(fam)]

## What the inventory may show about the item (hidden until understood).
static func unknown_name(it: Dictionary) -> String:
	if it.is_empty() or Profile.char == null:
		return ""
	var fam := item_family(it)
	if fam == "":
		return ""
	var st := stage_of_xp(fam_xp(Profile.char, fam))
	if st <= 1 and not bool(Profile.char.tech_models.get(str(it.base), {}).get("identified", false)):
		return "Неизвестное технологическое оружие"
	if st <= 2:
		return "Предположительно: %s" % str(FAMILIES[fam][4])
	return ""

# ------------------------------------------------------------ other sources
## Teacher: basic course of a category (all its families to III).
static func teach_basic(d, cat: String) -> String:
	d.tech_cats[cat] = maxf(cat_xp(d, cat), RESEARCH_CAP)
	var tr: Array = d.tech_mem.training
	if not cat in tr:
		tr.append(cat)
	stats.taught += 1
	for fam in FAMILIES:
		if fam_cat(str(fam)) == cat and stage_of_xp(fam_xp(d, str(fam))) >= 3 and raw_xp(d, str(fam)) < RESEARCH_CAP:
			add_xp(d, str(fam), RESEARCH_CAP - raw_xp(d, str(fam)), RESEARCH_CAP)
	return "Вы прошли курс «%s»: основы всех её устройств понятны." % CATS.get(cat, cat)

## Teacher: a training session for one family (towards IV, never V).
static func train(d, fam: String) -> String:
	if stage_of_xp(fam_xp(d, fam)) < 3:
		return "Сначала нужен базовый курс."
	if raw_xp(d, fam) >= TEACH_CAP:
		return "Дальше учит только практика."
	var got := add_xp(d, fam, 45.0, TEACH_CAP)
	stats.taught += 1
	var tr: Array = d.tech_mem.training
	if not fam in tr:
		tr.append(fam)
	return "Тренировка с «%s»: +%d опыта владения." % [fam_name(fam), int(got)]

## A treatise / schematic of a category.
static func read_manual(d, cat: String) -> String:
	var g := 30.0 * (2.0 if has_skill(d, "tc_translation") else 1.0)
	d.tech_cats[cat] = minf(cat_xp(d, cat) + g, RESEARCH_CAP)
	var sc: Array = d.tech_mem.schemas
	if not cat in sc:
		sc.append(cat)
	stats.manuals += 1
	return "Трактат «%s» прочитан: знания категории %d / %d." % [CATS.get(cat, cat), int(cat_xp(d, cat)), int(RESEARCH_CAP)]

## A fragment of technology from rift ruins: research for the most advanced
## unknown device the hero carries (or general future knowledge).
static func use_fragment(d) -> String:
	var best := ""
	var be := -1
	for it in d.inv.all_equipped() + d.inv.items:
		var f := item_family(it)
		if f != "" and stage_of_xp(fam_xp(d, f)) < 3 and fam_era(f) > be:
			be = fam_era(f)
			best = f
	if best != "":
		var got := research(d, best, 12.0)
		return "Фрагмент изучен: «%s» +%d знаний." % [fam_name(best), int(got)]
	d.tech_cats["future"] = minf(cat_xp(d, "future") + 8.0, RESEARCH_CAP)
	return "Фрагмент изучен: знания о технологиях будущего растут."

## Learn a Tech Cognition skill. "" or why not.
static func learn_skill(d, id: String) -> String:
	for s in SKILLS:
		if str(s[0]) != id:
			continue
		if id in d.tech_skills:
			return "уже изучено"
		if str(s[4]) != "" and not str(s[4]) in d.tech_skills:
			return "сначала «%s»" % skill_name(str(s[4]))
		if d.tech_pts < int(s[3]):
			return "нужно очков познания: %d" % int(s[3])
		d.tech_pts -= int(s[3])
		d.tech_skills.append(id)
		return ""
	return "нет такого навыка"

static func skill_name(id: String) -> String:
	for s in SKILLS:
		if str(s[0]) == id:
			return str(s[1])
	return id

## Historical Knowledge Memory: an era visited for the first time; the
## people there use their technology all around — primary understanding.
static func on_visit(d, era: int) -> void:
	if d == null:
		return
	var eras: Array = d.tech_mem.eras
	if era in eras:
		return
	eras.append(era)
	if eras.size() > 1:
		d.tech_pts += 1
	for fam in FAMILIES:
		if fam_era(str(fam)) == era and raw_xp(d, str(fam)) < XP_STAGE[2]:
			_fam_rec(d, str(fam)).xp = XP_STAGE[2]

## New hero: the technology of his own era is mastered.
static func setup_new(d, era := 0) -> void:
	d.tech_mem = {"eras": [era], "schemas": [], "training": [], "maint": []}
	for fam in FAMILIES:
		if fam_era(str(fam)) == era:
			_fam_rec(d, str(fam)).xp = XP_STAGE[5]
	d.tech_pts = 1
	for it in d.inv.all_equipped() + d.inv.items:
		if item_family(it) != "" and stage_of_xp(fam_xp(d, item_family(it))) >= 4:
			model_rec(d, str(it.base)).fam = true

## Saves made before the system: every era already played is confident
## knowledge, weapons the hero owns from those eras are familiar.
static func migrate(d, unlocked: Array) -> void:
	var eras: Array = d.tech_mem.eras
	for e in unlocked:
		if not int(e) in eras:
			eras.append(int(e))
	for fam in FAMILIES:
		var fe := fam_era(str(fam))
		if fe in eras:
			_fam_rec(d, str(fam)).xp = maxf(raw_xp(d, str(fam)), XP_STAGE[5] if fe == 0 else XP_STAGE[4])
	for it in d.inv.all_equipped() + d.inv.items:
		var f := item_family(it)
		if f != "" and stage_of_xp(fam_xp(d, f)) >= 4:
			model_rec(d, str(it.base)).fam = true
	d.tech_pts = maxi(int(d.tech_pts), eras.size())

## Tests / debug: everything mastered.
static func debug_master_all(d) -> void:
	for fam in FAMILIES:
		_fam_rec(d, str(fam)).xp = XP_STAGE[5]
	for it in d.inv.all_equipped() + d.inv.items:
		var mr := model_rec(d, str(it.base))
		mr.fam = true
		mr.special = true
	d.set_meta("tech_all", true)

static func is_master_all(d) -> bool:
	return d != null and d.has_meta("tech_all")

# ================================================================== items
## Treatises of the 8 categories and fragments of technology from rifts.
static var _items := {}

static func item_base(id: String) -> Dictionary:
	if _items.is_empty():
		for c in CAT_ORDER:
			_items["tech_manual_" + c] = {"name": "Трактат: %s" % CATS[c], "era": -1, "slot": "use", "effect": "tech_manual", "tcat": c, "stack": false, "value": 90, "group": "book",
				"desc": "Схемы и записи об устройствах категории «%s»: основы всех её технологий (до базового понимания)." % CATS[c]}
		_items["tech_fragment"] = {"name": "Фрагмент технологий", "era": -1, "slot": "use", "effect": "tech_fragment", "stack": true, "value": 35, "group": "mat",
			"desc": "Обломок устройства из разлома: изучение продвигает исследование самого сложного неизвестного предмета в сумке. Нужен и для обслуживания оружия будущего."}
	return _items.get(id, {})

static func has_item(id: String) -> bool:
	return id == "tech_fragment" or id.begins_with("tech_manual_")

## Maintenance of future weapons far from their era: a forge / workshop can
## restore charge cells from rift fragments once the device is understood.
## [ammo id, qty, cost, gold, family]
const MAINTENANCE := [
	["ammo_pulse", 12, {"tech_fragment": 1, "chrono_shard": 1}, 30, "pulse"],
	["ammo_cell", 10, {"tech_fragment": 1, "chrono_shard": 1}, 30, "smart"],
	["ammo_plasma", 3, {"tech_fragment": 2, "chrono_shard": 1}, 45, "plasma"],
	["ammo_tesla", 10, {"tech_fragment": 1, "iron_ore": 1}, 20, "tesla"],
]

static func maintenance_recipes(world) -> Array:
	var out: Array = []
	var pd = world.player.data
	for r in MAINTENANCE:
		var fam: String = r[4]
		if fam_era(fam) <= Profile.current_era or stage_of_xp(fam_xp(pd, fam)) < 3:
			continue      # in its own era the regular workshops do it; unknown devices cannot be serviced
		var bid: String = r[0]
		var qty: int = r[1]
		var cost: Dictionary = r[2]
		var gold: int = r[3]
		out.append({"name": "Обслуживание: %s ×%d" % [Ammo.base(bid).name, qty], "desc": "Восстановление зарядов для «%s» из фрагментов разлома." % fam_name(fam), "cost": cost, "gold": gold, "group": "ammo",
			"cb": func():
				if not Stations._pay(world, cost, gold):
					return false
				var it := ItemDB.create(bid, 0, 1)
				it.qty = qty
				if not pd.inv.add(it):
					world.loot.spawn_drop(it, world.player.global_position + Vector3(1, 0, 0))
				var mt: Array = pd.tech_mem.maint
				if not fam in mt:
					mt.append(fam)
				return true})
	return out

# ================================================================== teachers
## Who teaches what: an era's smith / gunsmith / engineer / specialist /
## scientist teaches that era's categories; the era traveler (the Last
## Witness) knows all of them and can explain anomalous devices.
const TEACHER_TITLES := ["Кузнец", "Оружейник Возрождения", "Инженер", "Оружейный специалист", "Учёный будущего"]

static func teacher_cats(era: int, traveler := false) -> Array:
	if traveler:
		return CAT_ORDER.duplicate()
	return ERA_CATS[clampi(era, 0, ERA_CATS.size() - 1)]

static func course_price(cat: String, traveler := false) -> int:
	var e := 0
	for i in ERA_CATS.size():
		if cat in ERA_CATS[i]:
			e = i
	if cat == "anomalous":
		e = 4
	return int((40 + 30 * e) * (2.0 if traveler else 1.0))

static func train_price(fam: String, traveler := false) -> int:
	return int((25 + 15 * fam_era(fam)) * (2.0 if traveler else 1.0))

## Dialog options a teacher offers. world: the World; done_cb reopens the menu.
static func teacher_options(world, cats: Array, traveler: bool, done_cb: Callable) -> Array:
	var d = world.player.data
	var opts: Array = []
	var cur: String = DBEras.era(Profile.current_era).currency
	for c in cats:
		var cat: String = c
		if cat_xp(d, cat) < RESEARCH_CAP:
			var pr := course_price(cat, traveler)
			opts.append({"text": "Курс: %s (%d %s)" % [CATS[cat], pr, cur], "cb": func():
				if d.gold < pr:
					Events.notify.emit("Не хватает денег на обучение", Color(1, 0.5, 0.4))
				else:
					d.gold -= pr
					Events.notify.emit(teach_basic(d, cat), Color(0.6, 0.9, 1.0))
				done_cb.call()})
		for f in FAMILIES:
			var fam: String = f
			if fam_cat(fam) != cat or stage_of_xp(fam_xp(d, fam)) < 3 or raw_xp(d, fam) >= TEACH_CAP:
				continue
			var tp := train_price(fam, traveler)
			opts.append({"text": "Тренировка: %s (%d %s)" % [fam_name(fam), tp, cur], "cb": func():
				if d.gold < tp:
					Events.notify.emit("Не хватает денег на тренировку", Color(1, 0.5, 0.4))
				else:
					d.gold -= tp
					Events.notify.emit(train(d, fam), Color(0.6, 0.9, 1.0))
				done_cb.call()})
	# ask about an unknown device the hero carries: the teacher names it
	for it in d.inv.items + d.inv.all_equipped():
		var fam2 := item_family(it)
		if fam2 != "" and fam_cat(fam2) in cats and unknown_name(it) != "":
			var it2: Dictionary = it
			opts.append({"text": "Спросить об устройстве: «%s»" % unknown_name(it2), "cb": func():
				Events.notify.emit(identify(d, it2) + " Это «%s»." % fam_name(item_family(it2)), Color(0.6, 0.9, 1.0))
				done_cb.call()})
			break
	if traveler:
		for it3 in d.inv.items + d.inv.all_equipped():
			if has_special(it3) and not bool(d.tech_models.get(str(it3.base), {}).get("special", false)) and (item_family(it3) == "" or stage_of_xp(fam_xp(d, item_family(it3))) >= 3):
				var it4: Dictionary = it3
				var sp := 150 + 50 * int(it4.get("rarity", 3))
				opts.append({"text": "Объяснить особый узел «%s» (%d %s)" % [ItemDB.display_name(it4), sp, cur], "cb": func():
					if d.gold < sp:
						Events.notify.emit("Не хватает денег", Color(1, 0.5, 0.4))
					else:
						d.gold -= sp
						model_rec(d, str(it4.base)).special = true
						d.tech_cats["anomalous"] = cat_xp(d, "anomalous") + 10.0
						Events.notify.emit("Свидетель объяснил особый узел: особые способности предмета доступны", Color(0.6, 0.9, 1.0))
					done_cb.call()})
				break
	return opts

static func open_teacher(world, n, traveler := false) -> void:
	var era := Profile.current_era
	var cats := teacher_cats(era, traveler)
	var title: String = "Последний Свидетель — знания эпох" if traveler else "%s — обучение" % TEACHER_TITLES[clampi(era, 0, 4)]
	var d = world.player.data
	var lines: Array = []
	for c in cats:
		lines.append("%s: %d / %d" % [CATS[c], int(cat_xp(d, c)), int(RESEARCH_CAP)])
	var text := "«Чему тебя научить?»\n\n" + "\n".join(lines)
	var opts := teacher_options(world, cats, traveler, func(): open_teacher(world, n, traveler))
	opts.append({"text": "Назад", "cb": func(): pass})
	world.ui.open("dialog", {"title": title, "text": text, "options": opts})

static func stage_text(a, it: Dictionary) -> String:
	var fam := item_family(it)
	if fam == "":
		return ""
	var s := item_stage(a, it)
	return "Технология «%s»: %s — %s" % [fam_name(fam), STAGE_SHORT[s], STAGE_NAMES[s]]
