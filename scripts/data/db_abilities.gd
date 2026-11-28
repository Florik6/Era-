class_name DBAbilities
## «Ascension of Power»: the 200 new abilities in one data registry.
##   60 class skills (15 per class)   — learned with class points (character level)
##   40 weapon skills (5 per category) — learned with weapon mastery points (real use)
##  100 spells (10 per school, 10 schools) — learned with school points (school level)
## Every entry: id, name, desc, kind (class|weapon|spell), requirements, cost,
## resource, cast time, cool-down, components ("fx": executed by AbilityExec),
## passive modifiers ("mods" — stat changes, "hooks" — behaviour read by the
## combat code), visuals ("vis"), sound ("sfx"), AI hints ("ai").
## Spells: tier I–VI by position in the school (1-2 I, 3-4 II, 5-6 III,
## 7-8 IV, 9 V, 10 VI). Tier V needs real knowledge (mentor or tome) and rank,
## tier VI (cataclysm) a trial, the «Путь архимага» skill, a reagent and rank.

const CLASS_LVL := [1, 2, 3, 5, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 35]
const CLASS_COST := [1, 1, 1, 2, 1, 2, 2, 2, 2, 2, 2, 2, 3, 3, 5]
const WEAPON_LVL := [2, 5, 8, 12, 16]
const SPELL_TIER := [1, 1, 2, 2, 3, 3, 4, 4, 5, 6]
const SPELL_COST := [1, 1, 1, 2, 2, 2, 3, 3, 4, 6]
const TIER_SCHOOL_LVL := [0, 1, 4, 8, 12, 18, 24]
const TIER_RANK := [0, 1, 1, 2, 3, 5, 7]          # minimum magic rank per tier
## Mana price of a spell as a part of the standard mana pool of a mage at
## the stage where the tier opens: weak 5–10 %, medium 12–20 %, strong
## 25–40 %, master 40–55 %, archmage 60–75 %, catastrophic 80–100 %.
const TIER_BANDS := [[0.0, 0.0], [0.05, 0.10], [0.12, 0.20], [0.25, 0.40], [0.40, 0.55], [0.60, 0.75], [0.80, 1.00]]
const TIER_NAMES := ["", "Послушник", "Ученик", "Адепт", "Мастер", "Архимаг", "Катаклизм"]
const RANK_NAMES := ["Не владеет магией", "Послушник", "Ученик", "Адепт", "Опытный маг", "Мастер школы", "Верховный мастер", "Архимаг", "Легендарный архимаг"]
const WEAPON_CATS := ["sword", "heavy", "spear", "dagger", "bow", "firearm", "staff", "energy"]
const NEW_SCHOOLS := {
	"earth": {"name": "Земля", "color": Color(0.72, 0.58, 0.38), "dtype": "earth", "rune": "stone"},
	"necro": {"name": "Некромантия", "color": Color(0.45, 0.85, 0.55), "dtype": "dark", "rune": "bone"},
	"heal": {"name": "Исцеление", "color": Color(1.0, 0.86, 0.45), "dtype": "light", "rune": "lotus"},
	"air": {"name": "Воздух", "color": Color(0.78, 0.95, 0.95), "dtype": "air", "rune": "wind"},
	"light": {"name": "Свет", "color": Color(1.0, 0.95, 0.7), "dtype": "light", "rune": "sun"},
}
const SCHOOL_ORDER := ["fire", "ice", "lightning", "dark", "spacetime", "earth", "necro", "heal", "air", "light"]
## Reagent consumed by each cataclysm cast (a rare era material).
const CATACLYSM_REAGENT := ["ash_crystal", "silver_powder", "ether_condensate", "battery_pack", "chrono_cell"]

static var _all := {}

# ----------------------------------------------------------------- builders
static func C(id: String, cls: String, n: int, nm: String, type: String, desc: String, o: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "kind": "class", "cls": cls, "n": n, "name": nm, "type": type, "desc": desc,
		"lvl": CLASS_LVL[n - 1], "cost": CLASS_COST[n - 1], "req": "", "cd": 0.0, "stamina": 0.0, "mana": 0.0, "cast": 0.0, "fx": []}
	for k in o:
		d[k] = o[k]
	return d

static func W(id: String, cat: String, n: int, nm: String, type: String, desc: String, o: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "kind": "weapon", "cat": cat, "n": n, "name": nm, "type": type, "desc": desc,
		"lvl": WEAPON_LVL[n - 1], "cost": 1, "req": "", "cd": 0.0, "stamina": 0.0, "mana": 0.0, "cast": 0.0, "fx": []}
	for k in o:
		d[k] = o[k]
	return d

static func S(id: String, school: String, n: int, nm: String, desc: String, o: Dictionary = {}) -> Dictionary:
	var tier: int = SPELL_TIER[n - 1]
	var d := {"id": id, "kind": "spell", "school": school, "n": n, "tier": tier, "name": nm, "type": "active", "desc": desc,
		"slvl": TIER_SCHOOL_LVL[tier], "cost": SPELL_COST[n - 1], "mana": 10.0, "cd": 2.0, "cast": 0.35, "dmg": 0.0, "fx": [],
		"lvl": TIER_SCHOOL_LVL[tier]}
	for k in o:
		d[k] = o[k]
	return d

# ----------------------------------------------------------------- queries
static func all() -> Dictionary:
	if _all.is_empty():
		var list: Array = _build()
		_normalize_costs(list)
		for e in list:
			_all[e.id] = e
	return _all

## Mana of a mage (class base 130 + 4 per level) when the school level
## `slvl` is reached — the reference for spell prices.
static func standard_pool(slvl: int) -> float:
	return 130.0 + 4.0 * float(maxi(slvl, 1) - 1)

## Spell prices are set by tier bands: the authored price only orders the
## spells inside their tier (kept as "mana_authored").
static func _normalize_costs(list: Array) -> void:
	var lo := {}
	var hi := {}
	for e in list:
		if e.kind != "spell":
			continue
		var t: int = int(e.tier)
		var m := float(e.mana)
		lo[t] = minf(float(lo.get(t, m)), m)
		hi[t] = maxf(float(hi.get(t, m)), m)
	for e in list:
		if e.kind != "spell":
			continue
		var t: int = int(e.tier)
		var m := float(e.mana)
		var k := 0.5
		if float(hi[t]) > float(lo[t]):
			k = (m - float(lo[t])) / (float(hi[t]) - float(lo[t]))
		var band: Array = TIER_BANDS[t]
		var pool := standard_pool(TIER_SCHOOL_LVL[t])
		e["mana_authored"] = m
		e["mana"] = maxf(1.0, ceilf(pool * lerpf(float(band[0]), float(band[1]), k)))

static func get_ab(id: String) -> Dictionary:
	return all().get(id, {})

static func has(id: String) -> bool:
	return all().has(id)

static func of_kind(k: String) -> Array:
	return all().values().filter(func(e): return e.kind == k)

static func class_skills(cls: String) -> Array:
	var out: Array = all().values().filter(func(e): return e.kind == "class" and e.cls == cls)
	out.sort_custom(func(a, b): return a.n < b.n)
	return out

static func weapon_skills(cat: String) -> Array:
	var out: Array = all().values().filter(func(e): return e.kind == "weapon" and e.cat == cat)
	out.sort_custom(func(a, b): return a.n < b.n)
	return out

static func school_spells(school: String) -> Array:
	var out: Array = all().values().filter(func(e): return e.kind == "spell" and e.school == school)
	out.sort_custom(func(a, b): return a.n < b.n)
	return out

static func is_new_spell(id: String) -> bool:
	return all().get(id, {}).get("kind", "") == "spell"

static func school_info(s: String) -> Dictionary:
	if NEW_SCHOOLS.has(s):
		return NEW_SCHOOLS[s]
	return DBSkills.SCHOOLS.get(s, {})

# ----------------------------------------------------------------- data
static func _build() -> Array:
	var L: Array = []
	_warrior(L)
	_archer(L)
	_rogue(L)
	_mage(L)
	_weapons(L)
	_fire(L)
	_ice(L)
	_lightning(L)
	_dark(L)
	_time(L)
	_earth(L)
	_necro(L)
	_heal(L)
	_air(L)
	_light(L)
	return L

# ================================================================= CLASSES
static func _warrior(L: Array) -> void:
	var cl := "warrior"
	L.append(C("cw_unbreakable", cl, 1, "Несокрушимая стойка", "active", "Защитная позиция на 6 с: броня +10, отбрасывание не действует.",
		{"cd": 16.0, "stamina": 20.0, "anim": "block", "fx": [{"c": "buff", "to": "self", "status": "steadfast", "dur": 6.0, "prm": {"mods": {"armor": 10.0}, "no_knock": true}}],
		"vis": {"col": Color(0.85, 0.75, 0.55), "shape": "stance"}, "sfx": "block", "ai": {"use": "defend"}}))
	L.append(C("cw_iron_rush", cl, 2, "Железный натиск", "active", "Короткий рывок вперёд и удар ×1,8 с отбрасыванием.",
		{"cd": 8.0, "stamina": 22.0, "anim": "thrust", "fx": [{"c": "move", "kind": "dash", "dist": 5.0}, {"c": "melee", "mult": 1.8, "arc": 100.0, "knock": 4.0, "anim": "slash"}],
		"vis": {"col": Color(1.0, 0.85, 0.6), "shape": "dash"}, "sfx": "swing_heavy", "ai": {"use": "gap", "rng": 6.0}}))
	L.append(C("cw_counter_split", cl, 3, "Ответный раскол", "passive", "После успешного блока 2,5 с следующий удар ×2,2.", {"hooks": {"block_counter": 1.2}}))
	L.append(C("cw_guard_breaker", cl, 4, "Разрушитель защиты", "passive", "Удары по блокирующему противнику выбивают ещё 15 выносливости; пустая выносливость — оглушение.", {"hooks": {"guard_break": 15.0}}))
	L.append(C("cw_defender", cl, 5, "Щит защитника", "active", "Прикрывает ближайшего союзника (или себя): −35% входящего урона на 8 с.",
		{"cd": 20.0, "stamina": 15.0, "anim": "cast", "fx": [{"c": "buff", "to": "ally", "r": 9.0, "status": "guarded", "dur": 8.0, "prm": {"mods": {"taken_pct": -0.35}}}],
		"vis": {"col": Color(0.7, 0.85, 1.0), "shape": "shield_link"}, "sfx": "block", "ai": {"use": "support"}}))
	L.append(C("cw_fighter_blood", cl, 6, "Кровь бойца", "passive", "При здоровье ниже 35% блок тратит вдвое меньше выносливости.", {"hooks": {"low_hp_block": 0.5}}))
	L.append(C("cw_heavy_step", cl, 7, "Тяжёлый шаг", "active", "Силовой удар по земле: ударная волна 4 м, ×1,3 урона, оглушение 0,4 с.",
		{"cd": 9.0, "stamina": 25.0, "anim": "slam", "fx": [{"c": "nova", "r": 4.0, "mult": 1.3, "wpn": true, "status": {"stun": 0.4}, "knock": 3.0}],
		"vis": {"col": Color(0.8, 0.7, 0.55), "shape": "quake"}, "sfx": "explosion", "ai": {"use": "aoe", "rng": 3.5}}))
	L.append(C("cw_relentless", cl, 8, "Непрерывный натиск", "passive", "Каждый удар подряд (в пределах 2 с) даёт +4% урона, до 5 раз.", {"hooks": {"relentless": 0.04}}))
	L.append(C("cw_banner", cl, 9, "Боевое знамя", "active", "Знамя на 10 с: союзники в 7 м получают броню +8 и устойчивость к отбрасыванию.",
		{"cd": 30.0, "stamina": 20.0, "anim": "cast", "fx": [{"c": "buff", "to": "allies", "r": 7.0, "status": "banner", "dur": 10.0, "prm": {"mods": {"armor": 8.0}, "no_knock": true}}, {"c": "prop", "kind": "banner", "life": 10.0}],
		"vis": {"col": Color(0.85, 0.2, 0.2), "shape": "banner"}, "sfx": "mastery_up", "ai": {"use": "support"}}))
	L.append(C("cw_rank_breaker", cl, 10, "Крушитель рядов", "active", "Рывок на 7 м сквозь строй: ×1,2 урона и отбрасывание всем на пути.",
		{"cd": 12.0, "stamina": 30.0, "anim": "thrust", "fx": [{"c": "move", "kind": "dash", "dist": 7.0, "mult": 1.2, "wpn": true, "knock": 6.0}],
		"vis": {"col": Color(1.0, 0.8, 0.5), "shape": "dash"}, "sfx": "swing_heavy", "ai": {"use": "gap", "rng": 8.0}}))
	L.append(C("cw_steel_breath", cl, 11, "Стальное дыхание", "passive", "Выдержанный блоком удар возвращает 15 выносливости.", {"hooks": {"block_stamina": 15.0}}))
	L.append(C("cw_parry_master", cl, 12, "Мастер парирования", "passive", "Окно идеального парирования шире на 0,08 с.", {"hooks": {"parry_window": 0.08}}))
	L.append(C("cw_last_fortress", cl, 13, "Последняя крепость", "passive", "Если рядом 3+ врага: броня +15 и −10% входящего урона.", {"hooks": {"surrounded": 1.0}}))
	L.append(C("cw_titan_wrath", cl, 14, "Гнев титана", "active", "Подготовка 1 с, затем удар по кругу 5,5 м ×3,2 с сильным отбрасыванием.",
		{"cd": 20.0, "stamina": 45.0, "cast": 1.0, "anim": "slam", "fx": [{"c": "nova", "r": 5.5, "mult": 3.2, "wpn": true, "knock": 9.0, "status": {"stun": 0.6}}],
		"vis": {"col": Color(1.0, 0.65, 0.3), "shape": "titan", "rune": "fire"}, "sfx": "explosion", "ai": {"use": "aoe", "rng": 4.5}}))
	L.append(C("cw_battle_legend", cl, 15, "Легенда поля боя", "active", "Высшая техника: четыре мощных удара подряд (×1,4 / ×1,4 / ×1,8 / ×2,6).",
		{"cd": 40.0, "stamina": 55.0, "anim": "spin", "fx": [{"c": "melee_seq", "seq": [["slash", 1.4, 120.0], ["spin", 1.4, 360.0], ["overhead", 1.8, 100.0], ["slam", 2.6, 360.0]], "interval": 0.32}],
		"vis": {"col": Color(1.0, 0.85, 0.4), "shape": "legend"}, "sfx": "swing_heavy", "ai": {"use": "burst", "rng": 3.0}}))

static func _archer(L: Array) -> void:
	var cl := "archer"
	L.append(C("ca_eagle_eye", cl, 1, "Зоркий глаз", "passive", "+6% шанса крита, видит слабые места: +20% к обнаружению.", {"mods": {"crit": 0.06, "detect": 0.2}}))
	L.append(C("ca_move_shot", cl, 2, "Стрельба на ходу", "passive", "Стрельба в движении без штрафа к разбросу.", {"hooks": {"move_shot": 1.0}}))
	L.append(C("ca_hunter_mark", cl, 3, "Метка охотника", "active", "Метка на цели 10 с: она получает +20% урона.",
		{"cd": 12.0, "stamina": 10.0, "anim": "cast", "fx": [{"c": "debuff", "to": "target", "rng": 25.0, "status": "marked", "dur": 10.0, "prm": {"mods": {"taken_pct": 0.2}}}],
		"vis": {"col": Color(1.0, 0.3, 0.25), "shape": "mark"}, "sfx": "pickup", "ai": {"use": "open", "rng": 25.0}}))
	L.append(C("ca_silent_string", cl, 4, "Тихая тетива", "passive", "Выстрел из лука не снимает скрытность (+50% урона из тени).", {"hooks": {"silent_shot": 1.0}}))
	L.append(C("ca_quick_aim", cl, 5, "Быстрый прицел", "passive", "После перебежки (1,2 с бега) первый выстрел на 50% быстрее.", {"hooks": {"quick_aim": 0.5}}))
	L.append(C("ca_falcon_step", cl, 6, "Соколиный шаг", "passive", "После уклонения 2 с скорость атаки +35%.", {"hooks": {"falcon": 0.35}}))
	L.append(C("ca_monster_hunter", cl, 7, "Охотник на чудовищ", "passive", "+25% урона по крупным существам и боссам.", {"hooks": {"big_game": 0.25}}))
	L.append(C("ca_pierce_calc", cl, 8, "Пробивающий расчёт", "passive", "Выстрелы игнорируют 30% брони.", {"hooks": {"armor_pen": 0.3}}))
	L.append(C("ca_air_volley", cl, 9, "Воздушный залп", "active", "Четыре стрелы подряд по цели (×0,9 каждая).",
		{"cd": 10.0, "stamina": 28.0, "anim": "shoot", "fx": [{"c": "shots", "n": 4, "interval": 0.12, "mult": 0.9}],
		"vis": {"col": Color(0.9, 0.95, 1.0), "shape": "volley"}, "sfx": "bow_release", "ai": {"use": "burst", "rng": 22.0}}))
	L.append(C("ca_forest_ghost", cl, 10, "Лесной призрак", "passive", "В лесу и среди деревьев: +10% крита, +5% скорости, враги замечают вас только вблизи.", {"hooks": {"forest": 1.0}}))
	L.append(C("ca_height_scout", cl, 11, "Разведчик высоты", "passive", "+20% урона, если вы выше цели на 1,5 м.", {"hooks": {"high_ground": 0.2}}))
	L.append(C("ca_hunting_instinct", cl, 12, "Охотничий инстинкт", "passive", "Раненые враги (<40% здоровья) в 30 м отмечаются; +10% урона по ним.", {"hooks": {"instinct": 0.1}}))
	L.append(C("ca_steady_hand", cl, 13, "Неподвижная рука", "passive", "Стоя на месте 0,6 с: +15% урона выстрелов, разброс вдвое меньше.", {"hooks": {"steady": 0.15}}))
	L.append(C("ca_retribution", cl, 14, "Стрела возмездия", "passive", "После уклонения от удара следующий выстрел ×2.", {"hooks": {"retribution": 1.0}}))
	L.append(C("ca_sky_hunter", cl, 15, "Небесный охотник", "active", "Залп с неба по всем отмеченным целям (до 6) ×2, без меток — по трём ближайшим.",
		{"cd": 35.0, "stamina": 45.0, "anim": "shoot", "cast": 0.6, "fx": [{"c": "sky_volley", "max": 6, "rng": 30.0, "mult": 2.0}],
		"vis": {"col": Color(1.0, 0.9, 0.5), "shape": "sky_volley", "rune": "stars"}, "sfx": "bow_release", "ai": {"use": "burst", "rng": 28.0}}))

static func _rogue(L: Array) -> void:
	var cl := "rogue"
	L.append(C("cr_quiet_step", cl, 1, "Тихий шаг", "passive", "Враги замечают вас на 40% ближе при осторожном движении.", {"hooks": {"quiet": 0.4}}))
	L.append(C("cr_shadow_turn", cl, 2, "Теневой разворот", "active", "Мгновенно оказаться за спиной ближайшего врага (8 м) и ударить ×1,2.",
		{"cd": 9.0, "stamina": 20.0, "anim": "stab", "fx": [{"c": "behind", "rng": 8.0}, {"c": "melee", "mult": 1.2, "arc": 120.0}],
		"vis": {"col": Color(0.5, 0.35, 0.8), "shape": "shadow"}, "sfx": "teleport", "ai": {"use": "gap", "rng": 8.0}}))
	L.append(C("cr_nimble_hands", cl, 3, "Проворные руки", "passive", "Взаимодействие с замками, механизмами и ловушками на 40% быстрее.", {"hooks": {"nimble": 0.4}}))
	L.append(C("cr_feint", cl, 4, "Ложный выпад", "active", "Ложная атака: цель открывается (уязвимость +40%) на 2,5 с.",
		{"cd": 8.0, "stamina": 12.0, "anim": "thrust", "fx": [{"c": "debuff", "to": "target", "rng": 4.5, "status": "vulnerable", "dur": 2.5}],
		"vis": {"col": Color(0.9, 0.9, 1.0), "shape": "feint"}, "sfx": "swing", "ai": {"use": "open", "rng": 4.0}}))
	L.append(C("cr_hidden_mark", cl, 5, "Скрытая метка", "active", "Метка 12 с: ваш следующий удар по цели ×1,6 и кровотечение.",
		{"cd": 10.0, "stamina": 10.0, "anim": "cast", "fx": [{"c": "debuff", "to": "target", "rng": 12.0, "status": "hidden_mark", "dur": 12.0, "prm": {"by_me": true}}],
		"vis": {"col": Color(0.85, 0.15, 0.2), "shape": "mark"}, "sfx": "pickup", "ai": {"use": "open", "rng": 10.0}}))
	L.append(C("cr_dodge_master", cl, 6, "Мастер уклонения", "passive", "Перезарядка рывка −30%, неуязвимость при рывке дольше.", {"hooks": {"dodge_master": 0.3}}))
	L.append(C("cr_silent_hunter", cl, 7, "Бесшумный охотник", "passive", "Убийство из скрытности возвращает скрытность на 2 с.", {"hooks": {"silent_kill": 2.0}}))
	L.append(C("cr_sand_maneuver", cl, 8, "Песчаный манёвр", "active", "Песок в глаза: враги в конусе 4 м ослеплены на 3 с (их удары часто промахиваются).",
		{"cd": 14.0, "stamina": 15.0, "anim": "cast", "fx": [{"c": "cone", "r": 4.0, "ang": 60.0, "mult": 0.0, "status": {"blind": 3.0}}],
		"vis": {"col": Color(0.85, 0.75, 0.5), "shape": "sand"}, "sfx": "swing", "ai": {"use": "defend", "rng": 4.0}}))
	L.append(C("cr_precise_cut", cl, 9, "Точный разрез", "passive", "+40% урона по уязвимым, отмеченным и оглушённым целям.", {"hooks": {"precise": 0.4}}))
	L.append(C("cr_shadow_chain", cl, 10, "Цепочка теней", "passive", "До двух дополнительных рывков подряд (по 15 выносливости).", {"hooks": {"dodge_chain": 2.0}}))
	L.append(C("cr_deception", cl, 11, "Обман зрения", "active", "Иллюзия на вашем месте отвлекает врагов 4 с, вы уходите в тень на 2 с.",
		{"cd": 18.0, "stamina": 20.0, "anim": "cast", "fx": [{"c": "decoy", "life": 4.0}, {"c": "buff", "to": "self", "status": "stealth", "dur": 2.0}],
		"vis": {"col": Color(0.6, 0.5, 0.9), "shape": "decoy"}, "sfx": "teleport", "ai": {"use": "escape"}}))
	L.append(C("cr_last_blade", cl, 12, "Последний клинок", "passive", "После уклонения от удара следующая атака ×2,5.", {"hooks": {"last_blade": 1.5}}))
	L.append(C("cr_burglar", cl, 13, "Профессиональный взломщик", "passive", "Открывает запертые сундуки и решётки эпохи без ключа (кроме чужих домов).", {"hooks": {"burglar": 1.0}}))
	L.append(C("cr_ambush_master", cl, 14, "Мастер засад", "passive", "Удар из скрытности ×3,5 вместо ×2,5 и оглушение на 1 с.", {"hooks": {"ambush": 1.0}}))
	L.append(C("cr_thousand_shadows", cl, 15, "Танец тысячи теней", "active", "Шесть стремительных ударов по 4 ближайшим врагам с остаточными силуэтами.",
		{"cd": 40.0, "stamina": 50.0, "anim": "stab", "fx": [{"c": "shadow_dance", "hits": 6, "targets": 4, "mult": 1.1, "rng": 7.0}],
		"vis": {"col": Color(0.45, 0.3, 0.85), "shape": "shadow_dance"}, "sfx": "swing", "ai": {"use": "burst", "rng": 6.0}}))

static func _mage(L: Array) -> void:
	var cl := "mage"
	L.append(C("cm_mana_conductor", cl, 1, "Проводник маны", "passive", "Слабые заклинания (ступени I–II) дешевле на 25%.", {"hooks": {"mana_weak": 0.25}}))
	L.append(C("cm_steady_focus", cl, 2, "Устойчивая концентрация", "passive", "Удары и оглушения реже прерывают заклинание (−50%).", {"hooks": {"cast_steady": 0.5}}))
	L.append(C("cm_quick_formula", cl, 3, "Быстрая формула", "passive", "Простые заклинания (I–II) готовятся на 30% быстрее.", {"hooks": {"quick_cast": 0.3}}))
	L.append(C("cm_magic_hearing", cl, 4, "Магический слух", "active", "8 с: отмечает магов, разломы и магические источники в 40 м.",
		{"cd": 20.0, "mana": 10.0, "anim": "cast", "fx": [{"c": "reveal", "r": 40.0, "dur": 8.0, "what": "magic"}],
		"vis": {"col": Color(0.7, 0.6, 1.0), "shape": "pulse"}, "sfx": "portal_open", "ai": {"use": "never"}}))
	L.append(C("cm_rune_memory", cl, 5, "Рунная память", "passive", "Четвёртая ячейка подготовленных умений.", {"hooks": {"extra_slot": 1.0}}))
	L.append(C("cm_energy_balance", cl, 6, "Энергетическое равновесие", "passive", "Через 3 с без заклинаний мана восстанавливается на 60% быстрее.", {"hooks": {"mana_idle": 0.6}}))
	L.append(C("cm_elemental_master", cl, 7, "Мастер стихий", "passive", "Резонансы от ваших заклинаний сильнее на 20%.", {"hooks": {"resonance_bonus": 0.2}}))
	L.append(C("cm_seal_hold", cl, 8, "Удержание печати", "passive", "Ваши магические области держатся на 40% дольше (+15% маны).", {"hooks": {"zone_dur": 0.4}}))
	L.append(C("cm_fine_tuning", cl, 9, "Тонкая настройка", "passive", "Снаряды заклинаний на 25% быстрее, автонаведение точнее.", {"hooks": {"fine_tune": 0.25}}))
	L.append(C("cm_magic_recoil", cl, 10, "Магическая отдача", "passive", "Истощение после архимагии и катаклизмов вдвое короче.", {"hooks": {"recoil": 0.5}}))
	L.append(C("cm_arcane_ward", cl, 11, "Арканная защита", "passive", "+8% сопротивления огню, льду, молнии, тьме и времени.", {"mods": {"res_fire": 0.08, "res_ice": 0.08, "res_lightning": 0.08, "res_dark": 0.08, "res_time": 0.08}}))
	L.append(C("cm_second_contour", cl, 12, "Второй контур", "passive", "Можно поддерживать два длительных заклинания вместо одного.", {"hooks": {"sustain_cap": 1.0}}))
	L.append(C("cm_weaving", cl, 13, "Мастер переплетения", "passive", "Комбинированные реакции ваших заклинаний +25% урона.", {"hooks": {"weave": 0.25}}))
	L.append(C("cm_high_focus", cl, 14, "Высшая концентрация", "passive", "Заклинания ступеней V–VI не прерываются и дешевле на 10%.", {"hooks": {"high_focus": 0.1}}))
	L.append(C("cm_archmage_path", cl, 15, "Путь архимага", "passive", "Высшая специализация: открывает ранг архимага и доступ к катаклизмам; +5% силы магии.", {"mods": {"spell": 0.05}, "hooks": {"archmage": 1.0}}))

# ================================================================= WEAPONS
static func _weapons(L: Array) -> void:
	# swords
	L.append(W("ws_glide_cut", "sword", 1, "Скользящий разрез", "active", "Шаг в сторону и быстрый разрез ×1,5.",
		{"cd": 6.0, "stamina": 16.0, "fx": [{"c": "move", "kind": "side", "dist": 1.4}, {"c": "melee", "mult": 1.5, "arc": 140.0, "rng_add": 0.9, "anim": "slash"}], "vis": {"col": Color(0.85, 0.92, 1.0), "shape": "slash"}, "sfx": "swing", "ai": {"use": "melee", "rng": 3.0}}))
	L.append(W("ws_blade_catch", "sword", 2, "Перехват клинка", "passive", "Успешное парирование сразу даёт контрудар ×2.", {"hooks": {"parry_counter": 2.0}}))
	L.append(W("ws_triple_arc", "sword", 3, "Тройная дуга", "active", "Три удара по разным траекториям: ×1 / ×1,1 / ×1,4.",
		{"cd": 8.0, "stamina": 24.0, "fx": [{"c": "melee_seq", "seq": [["slash", 1.0, 120.0], ["slash2", 1.1, 120.0], ["thrust", 1.4, 60.0]], "interval": 0.24}], "vis": {"col": Color(0.85, 0.92, 1.0), "shape": "slash"}, "sfx": "swing", "ai": {"use": "melee", "rng": 3.0}}))
	L.append(W("ws_knight_charge", "sword", 4, "Рыцарский натиск", "active", "Выпад на 4 м и укол ×2,2 с отбрасыванием.",
		{"cd": 10.0, "stamina": 26.0, "fx": [{"c": "move", "kind": "dash", "dist": 4.0}, {"c": "melee", "mult": 2.2, "arc": 60.0, "rng_add": 0.8, "knock": 6.0, "anim": "thrust"}], "vis": {"col": Color(1.0, 0.9, 0.6), "shape": "dash"}, "sfx": "swing_heavy", "ai": {"use": "gap", "rng": 6.0}}))
	L.append(W("ws_blade_crown", "sword", 5, "Венец клинка", "active", "Вращение, затем венец из призрачных клинков сходится: ×2,8 по кругу 4 м и кровотечение.",
		{"cd": 24.0, "stamina": 45.0, "fx": [{"c": "melee", "mult": 1.2, "arc": 360.0, "anim": "spin"}, {"c": "nova", "t": 0.35, "r": 4.0, "mult": 2.8, "wpn": true, "status": {"bleed": 6.0}}], "vis": {"col": Color(0.8, 0.9, 1.0), "shape": "blade_crown", "rune": "stars"}, "sfx": "swing_heavy", "ai": {"use": "aoe", "rng": 3.5}}))
	# axes & hammers
	L.append(W("wh_bonebreaker", "heavy", 1, "Костоломный замах", "active", "Удар ×1,6: оглушение 0,8 с и пробитая броня на 5 с.",
		{"cd": 8.0, "stamina": 22.0, "fx": [{"c": "melee", "mult": 1.6, "arc": 100.0, "anim": "overhead", "status": {"stun": 0.8, "armor_break": 5.0}}], "vis": {"col": Color(0.9, 0.8, 0.6), "shape": "smash"}, "sfx": "swing_heavy", "ai": {"use": "melee", "rng": 3.0}}))
	L.append(W("wh_dull_split", "heavy", 2, "Глухой раскол", "passive", "Тяжёлое оружие игнорирует 40% брони и бьёт блок вдвое сильнее.", {"hooks": {"anti_armor": 0.4}}))
	L.append(W("wh_thunder_turn", "heavy", 3, "Разворот грома", "active", "Круговой удар ×1,4 по всем вокруг с отбрасыванием.",
		{"cd": 9.0, "stamina": 28.0, "fx": [{"c": "melee", "mult": 1.4, "arc": 360.0, "rng_add": 1.0, "knock": 5.0, "anim": "spin"}], "vis": {"col": Color(1.0, 0.85, 0.5), "shape": "spin"}, "sfx": "swing_heavy", "ai": {"use": "aoe", "rng": 3.5}}))
	L.append(W("wh_iron_fall", "heavy", 4, "Железное падение", "active", "Вертикальный удар: ударная волна 3 м ×2, оглушение.",
		{"cd": 11.0, "stamina": 30.0, "fx": [{"c": "melee", "mult": 1.0, "arc": 80.0, "anim": "slam"}, {"c": "blast", "at": "front", "dist": 1.6, "r": 3.0, "mult": 2.0, "wpn": true, "status": {"stun": 0.6}, "knock": 4.0}], "vis": {"col": Color(0.9, 0.75, 0.5), "shape": "quake"}, "sfx": "explosion", "ai": {"use": "aoe", "rng": 3.0}}))
	L.append(W("wh_giant_verdict", "heavy", 5, "Приговор исполина", "active", "Замах 1,2 с и сокрушительный удар ×4 с ударной волной.",
		{"cd": 22.0, "stamina": 50.0, "cast": 1.2, "fx": [{"c": "blast", "at": "front", "dist": 1.8, "r": 2.8, "mult": 4.0, "wpn": true, "status": {"stun": 1.0}, "knock": 8.0}], "vis": {"col": Color(1.0, 0.7, 0.35), "shape": "titan", "rune": "fire"}, "sfx": "explosion", "ai": {"use": "burst", "rng": 3.0}}))
	# spears
	L.append(W("wp_far_lunge", "spear", 1, "Дальний выпад", "active", "Выпад с дальностью +2 м ×1,7, пробивает двоих.",
		{"cd": 6.0, "stamina": 18.0, "fx": [{"c": "melee", "mult": 1.7, "arc": 40.0, "rng_add": 2.0, "anim": "thrust", "pierce": 2}], "vis": {"col": Color(0.9, 0.95, 1.0), "shape": "thrust"}, "sfx": "swing", "ai": {"use": "melee", "rng": 5.0}}))
	L.append(W("wp_defense_circle", "spear", 2, "Круг обороны", "active", "Вращение древка: два круговых удара ×1,1 и защита −30% урона на 2 с.",
		{"cd": 12.0, "stamina": 26.0, "fx": [{"c": "melee_seq", "seq": [["spin", 1.1, 360.0], ["spin", 1.1, 360.0]], "interval": 0.3, "knock": 4.0}, {"c": "buff", "to": "self", "status": "guarded", "dur": 2.0, "prm": {"mods": {"taken_pct": -0.3}}}], "vis": {"col": Color(0.9, 0.85, 0.7), "shape": "spin"}, "sfx": "swing", "ai": {"use": "defend", "rng": 3.0}}))
	L.append(W("wp_halt_charge", "spear", 3, "Остановка натиска", "passive", "Враг, бросившийся на вас, получает удар ×1,5 и оглушение (раз в 4 с).", {"hooks": {"anti_charge": 1.5}}))
	L.append(W("wp_serpent_spear", "spear", 4, "Змеиное копьё", "active", "Четыре переменных выпада по цели ×0,9 с замедлением.",
		{"cd": 10.0, "stamina": 28.0, "fx": [{"c": "melee_seq", "seq": [["thrust", 0.9, 50.0], ["thrust", 0.9, 50.0], ["thrust", 0.9, 50.0], ["thrust", 0.9, 50.0]], "interval": 0.16, "status": {"slow": 0.6}}], "vis": {"col": Color(0.6, 1.0, 0.7), "shape": "thrust"}, "sfx": "swing", "ai": {"use": "melee", "rng": 4.0}}))
	L.append(W("wp_horizon_guard", "spear", 5, "Страж горизонта", "active", "6 с перед вами зона копья: вошедшие враги получают ×1,5 и отбрасываются.",
		{"cd": 25.0, "stamina": 40.0, "fx": [{"c": "zone", "kind": "spear_guard", "at": "front", "dist": 2.5, "r": 3.2, "dur": 6.0, "mult": 1.5, "wpn": true, "prm": {"push": 6.0}}], "vis": {"col": Color(1.0, 0.9, 0.55), "shape": "guard", "rune": "sigil"}, "sfx": "mastery_up", "ai": {"use": "defend", "rng": 5.0}}))
	# daggers
	L.append(W("wd_instant_stab", "dagger", 1, "Мгновенный укол", "active", "Очень быстрый укол ×1,3.",
		{"cd": 2.5, "stamina": 8.0, "fx": [{"c": "melee", "mult": 1.3, "arc": 70.0, "anim": "stab"}], "vis": {"col": Color(0.95, 0.95, 1.0), "shape": "stab"}, "sfx": "swing", "ai": {"use": "melee", "rng": 2.5}}))
	L.append(W("wd_twin_shadow", "dagger", 2, "Двойная тень", "active", "Два удара ×1,4 (с кинжалом во второй руке), иначе один.",
		{"cd": 7.0, "stamina": 18.0, "fx": [{"c": "melee_seq", "seq": [["stab", 1.4, 80.0], ["slash", 1.4, 80.0]], "interval": 0.14, "need_off": "dagger"}], "vis": {"col": Color(0.6, 0.45, 0.9), "shape": "stab"}, "sfx": "swing", "ai": {"use": "melee", "rng": 2.5}}))
	L.append(W("wd_evasion_blade", "dagger", 3, "Лезвие уклонения", "passive", "После рывка в сторону следующий удар (1,2 с) ×1,8.", {"hooks": {"dodge_strike": 0.8}}))
	L.append(W("wd_rhythm_break", "dagger", 4, "Разрыв ритма", "active", "Короткий удар, срывающий подготовку приёма или заклинания и оглушающий на 0,6 с.",
		{"cd": 9.0, "stamina": 14.0, "fx": [{"c": "melee", "mult": 1.0, "arc": 80.0, "anim": "stab", "interrupt": true, "status": {"stun": 0.6}}], "vis": {"col": Color(1.0, 0.95, 0.6), "shape": "stab"}, "sfx": "parry", "ai": {"use": "interrupt", "rng": 2.5}}))
	L.append(W("wd_dagger_storm", "dagger", 5, "Смерч кинжалов", "active", "Восемь стремительных ударов ×0,7 по трём целям перед вами.",
		{"cd": 22.0, "stamina": 40.0, "fx": [{"c": "melee_seq", "seq": [["stab", 0.7, 100.0], ["slash", 0.7, 100.0], ["stab", 0.7, 100.0], ["slash2", 0.7, 100.0], ["stab", 0.7, 100.0], ["slash", 0.7, 100.0], ["stab", 0.7, 100.0], ["spin", 0.7, 360.0]], "interval": 0.13, "max": 3}], "vis": {"col": Color(0.85, 0.85, 1.0), "shape": "storm_blades"}, "sfx": "swing", "ai": {"use": "burst", "rng": 2.5}}))
	# bows & crossbows
	L.append(W("wb_masters_draw", "bow", 1, "Натяжение мастера", "passive", "Полностью подготовленные выстрелы (прицельный, особые) +25% урона.", {"hooks": {"full_draw": 0.25}}))
	L.append(W("wb_piercing_arrow", "bow", 2, "Пробивная стрела", "active", "Стрела ×1,8 пробивает до трёх целей.",
		{"cd": 8.0, "stamina": 18.0, "fx": [{"c": "shots", "n": 1, "mult": 1.8, "pierce": 3, "spd": 55.0}], "vis": {"col": Color(0.9, 0.95, 1.0), "shape": "arrow"}, "sfx": "bow_release", "ai": {"use": "ranged", "rng": 24.0}}))
	L.append(W("wb_true_string", "bow", 3, "Точная тетива", "passive", "После короткой остановки разброс −60%.", {"hooks": {"true_string": 0.6}}))
	L.append(W("wb_cleaving_volley", "bow", 4, "Рассекающий залп", "active", "Пять стрел веером 40° ×0,8.",
		{"cd": 9.0, "stamina": 22.0, "fx": [{"c": "shots", "n": 5, "spread": 40.0, "mult": 0.8}], "vis": {"col": Color(0.95, 0.95, 1.0), "shape": "volley"}, "sfx": "bow_release", "ai": {"use": "ranged", "rng": 18.0}}))
	L.append(W("wb_royal_shot", "bow", 5, "Королевский выстрел", "active", "Прицеливание 0,9 с и выстрел ×5 с золотым следом, пробивает двоих.",
		{"cd": 20.0, "stamina": 40.0, "cast": 0.9, "fx": [{"c": "shots", "n": 1, "mult": 5.0, "pierce": 2, "spd": 70.0, "knock": 6.0}], "vis": {"col": Color(1.0, 0.85, 0.35), "shape": "royal"}, "sfx": "bow_release", "ai": {"use": "burst", "rng": 28.0}}))
	# firearms
	L.append(W("wf_recoil_control", "firearm", 1, "Контроль отдачи", "passive", "Повторные выстрелы стабильнее: разброс −40%, скорострельность +10%.", {"hooks": {"recoil_ctrl": 0.4}, "mods": {"aspd": 0.1}, "only_cat": "firearm"}))
	L.append(W("wf_target_switch", "firearm", 2, "Быстрая смена цели", "passive", "После попадания по одной цели выстрел по другой +20% урона.", {"hooks": {"switch": 0.2}}))
	L.append(W("wf_decisive_shot", "firearm", 3, "Один решающий выстрел", "active", "Прицеливание 0,8 с: выстрел ×4 с гарантированным критом.",
		{"cd": 14.0, "stamina": 25.0, "cast": 0.8, "fx": [{"c": "shots", "n": 1, "mult": 4.0, "crit": true, "spd": 90.0}], "vis": {"col": Color(1.0, 0.9, 0.6), "shape": "decisive"}, "sfx": "gun_rifle", "ai": {"use": "burst", "rng": 26.0}}))
	L.append(W("wf_suppressive_fire", "firearm", 4, "Подавляющий огонь", "active", "Восемь быстрых выстрелов веером: задетые подавлены (замедление и −20% урона) 3 с.",
		{"cd": 16.0, "stamina": 30.0, "fx": [{"c": "shots", "n": 8, "interval": 0.1, "spread": 30.0, "mult": 0.6, "status": {"suppressed": 3.0}}], "vis": {"col": Color(1.0, 0.85, 0.5), "shape": "volley"}, "sfx": "gun_rifle", "ai": {"use": "ranged", "rng": 18.0}}))
	L.append(W("wf_marksman", "firearm", 5, "Мастер стрелкового дела", "passive", "+10% крита, +20% урона крита, разброс −30%.", {"mods": {"crit": 0.1}, "hooks": {"crit_dmg": 0.2, "recoil_ctrl": 0.3}}))
	# staffs & foci
	L.append(W("wt_rune_strike", "staff", 1, "Рунный удар", "active", "Удар посохом ×1,2 и магический импульс 1,8 м стихией лучшей школы.",
		{"cd": 5.0, "stamina": 10.0, "mana": 8.0, "fx": [{"c": "melee", "mult": 1.2, "arc": 100.0, "anim": "slash"}, {"c": "nova", "r": 1.8, "mult": 0.8, "wpn": true, "school": "best", "knock": 4.0}], "vis": {"col": Color(0.7, 0.6, 1.0), "shape": "rune_strike", "rune": "sigil"}, "sfx": "dark_cast", "ai": {"use": "melee", "rng": 2.5}}))
	L.append(W("wt_energy_conduit", "staff", 2, "Энергетический проводник", "passive", "С посохом: сила заклинаний +10%, расход маны −5%.", {"hooks": {"conduit": 0.1}}))
	L.append(W("wt_guard_turn", "staff", 3, "Защитный оборот", "active", "Вращение посоха 1,2 с отражает снаряды и отталкивает врагов вокруг.",
		{"cd": 12.0, "stamina": 15.0, "fx": [{"c": "buff", "to": "self", "status": "deflect", "dur": 1.2, "prm": {"all": true}}, {"c": "push", "r": 2.5, "force": 6.0}], "vis": {"col": Color(0.75, 0.8, 1.0), "shape": "spin"}, "sfx": "block", "ai": {"use": "defend", "rng": 8.0}}))
	L.append(W("wt_weapon_seal", "staff", 4, "Печать на оружии", "active", "Печать на посохе: три следующих заклинания +30% силы.",
		{"cd": 18.0, "mana": 20.0, "fx": [{"c": "buff", "to": "self", "status": "seal_charge", "dur": 20.0, "prm": {"charges": 3}}], "vis": {"col": Color(0.85, 0.75, 1.0), "shape": "seal", "rune": "summon"}, "sfx": "portal_open", "ai": {"use": "buff"}}))
	L.append(W("wt_perfect_catalyst", "staff", 5, "Совершенный катализатор", "passive", "Сила магии +15%, подготовка −10%, перезарядка заклинаний I–IV −15%.", {"hooks": {"catalyst": 1.0}, "mods": {"spell": 0.15}}))
	# energy & tech
	L.append(W("we_pulse_boost", "energy", 1, "Импульсный разгон", "active", "6 с: энергетические выстрелы на 50% быстрее и +20% урона.",
		{"cd": 14.0, "stamina": 15.0, "fx": [{"c": "buff", "to": "self", "status": "pulse", "dur": 6.0, "prm": {"mods": {"aspd": 0.5, "dmg_pct": 0.2}}}], "vis": {"col": Color(0.4, 0.9, 1.0), "shape": "pulse"}, "sfx": "elec_crackle", "ai": {"use": "buff"}}))
	L.append(W("we_phase_tune", "energy", 2, "Фазовая настройка", "passive", "Энергетические выстрелы проходят 50% щитов и сопротивления энергии.", {"hooks": {"phase_tune": 0.5}}))
	L.append(W("we_heat_control", "energy", 3, "Тепловой контроль", "passive", "Перегрев энергетического оружия копится вдвое медленнее.", {"hooks": {"heat_ctrl": 0.5}}))
	L.append(W("we_resonant_shot", "energy", 4, "Резонансный выстрел", "passive", "Каждый пятый энергетический выстрел даёт энергетический взрыв 2 м.", {"hooks": {"resonant": 1.0}}))
	L.append(W("we_absolute_sync", "energy", 5, "Абсолютная синхронизация", "active", "6 с: скорострельность +60%, урон +30%, нет перегрева; затем 6 с рассинхрона (−30%).",
		{"cd": 40.0, "stamina": 30.0, "fx": [{"c": "buff", "to": "self", "status": "sync", "dur": 6.0, "prm": {"mods": {"aspd": 0.6, "dmg_pct": 0.3}, "no_heat": true, "after": "desync"}}], "vis": {"col": Color(0.3, 1.0, 0.9), "shape": "pulse", "rune": "rift"}, "sfx": "portal_open", "ai": {"use": "burst", "rng": 20.0}}))

# ================================================================= SPELLS
static func _fire(L: Array) -> void:
	var s := "fire"
	L.append(S("f_ember", s, 1, "Искра", "Маленький огненный снаряд по одной цели, лёгкое горение.", {"mana": 8.0, "cd": 0.9, "cast": 0.25, "dmg": 14.0,
		"fx": [{"c": "proj", "spd": 30.0, "rng": 20.0, "kind": "magic", "status": {"burn": 2.0}}], "vis": {"shape": "ember", "col": Color(1.0, 0.6, 0.2)}, "sfx": "fire_cast", "ai": {"use": "ranged", "rng": 18.0}}))
	L.append(S("f_flame_palm", s, 2, "Огненная ладонь", "Вспышка пламени перед магом: конус 3,5 м.", {"mana": 12.0, "cd": 3.0, "cast": 0.2, "dmg": 22.0,
		"fx": [{"c": "cone", "r": 3.5, "ang": 70.0, "status": {"burn": 4.0}}], "vis": {"shape": "palm", "col": Color(1.0, 0.5, 0.15)}, "sfx": "fire_cast", "ai": {"use": "melee", "rng": 3.0}}))
	L.append(S("f_blazing_arrow", s, 3, "Пылающая стрела", "Быстрый огненный снаряд-стрела с остаточным горением.", {"mana": 16.0, "cd": 2.0, "cast": 0.3, "dmg": 30.0,
		"fx": [{"c": "proj", "spd": 36.0, "rng": 24.0, "kind": "magic", "status": {"burn": 6.0}}], "vis": {"shape": "fire_arrow", "col": Color(1.0, 0.45, 0.1)}, "sfx": "fire_cast", "ai": {"use": "ranged", "rng": 22.0}}))
	L.append(S("f_ember_ring", s, 4, "Кольцо углей", "Огненное кольцо вокруг мага на 4 с, отталкивает подошедших.", {"mana": 24.0, "cd": 9.0, "cast": 0.3, "dmg": 12.0,
		"fx": [{"c": "push", "r": 3.5, "force": 5.0}, {"c": "zone", "kind": "fire", "at": "self", "r": 3.5, "dur": 4.0, "status": {"burn": 3.0}, "prm": {"ring": true}}], "vis": {"shape": "ring", "col": Color(1.0, 0.55, 0.15), "rune": "fire"}, "sfx": "fire_cast", "ai": {"use": "defend", "rng": 3.5}}))
	L.append(S("f_flame_whip", s, 5, "Пламенный хлыст", "Управляемая дуга огня 7 м по сектору 90°.", {"mana": 28.0, "cd": 5.0, "cast": 0.3, "dmg": 40.0,
		"fx": [{"c": "cone", "r": 7.0, "ang": 90.0, "status": {"burn": 5.0}}], "vis": {"shape": "whip", "col": Color(1.0, 0.4, 0.1)}, "sfx": "fire_cast", "ai": {"use": "aoe", "rng": 6.0}}))
	L.append(S("f_volcanic_mark", s, 6, "Вулканическая метка", "Руна на земле, через 1,2 с — взрыв 3,5 м и горящая земля.", {"mana": 32.0, "cd": 8.0, "cast": 0.4, "dmg": 70.0,
		"fx": [{"c": "blast", "at": "aim", "rng": 16.0, "r": 3.5, "delay": 1.2, "status": {"burn": 8.0}, "telegraph": true}, {"c": "zone", "kind": "fire", "at": "aim", "rng": 16.0, "r": 2.5, "dur": 3.0, "t": 1.2, "mult": 0.15}], "vis": {"shape": "volcano", "col": Color(1.0, 0.35, 0.05), "rune": "fire"}, "sfx": "explosion", "ai": {"use": "aoe", "rng": 15.0}}))
	L.append(S("f_fire_serpent", s, 7, "Огненный змей", "Огненная волна ползёт на 14 м и бьёт всех на пути.", {"mana": 45.0, "cd": 12.0, "cast": 0.5, "dmg": 55.0,
		"fx": [{"c": "wave", "len": 14.0, "w": 1.8, "spd": 12.0, "status": {"burn": 8.0}}], "vis": {"shape": "serpent", "col": Color(1.0, 0.45, 0.1)}, "sfx": "fire_cast", "ai": {"use": "line", "rng": 13.0}}))
	L.append(S("f_phoenix_seal", s, 8, "Печать Феникса", "15 с: огненные заклинания +35% силы, крылья пламени за спиной.", {"mana": 40.0, "cd": 30.0, "cast": 0.6, "dmg": 0.0, "sustain": true,
		"fx": [{"c": "buff", "to": "self", "status": "phoenix", "dur": 15.0, "prm": {"school_pow": {"fire": 0.35}}}], "vis": {"shape": "wings", "col": Color(1.0, 0.6, 0.15), "rune": "fire"}, "sfx": "portal_open", "ai": {"use": "buff"}}))
	L.append(S("f_flame_sky", s, 9, "Суд Пламенного Неба", "Символы над областью 5 м, затем шесть огненных ударов.", {"mana": 75.0, "cd": 26.0, "cast": 1.4, "dmg": 60.0,
		"fx": [{"c": "blast", "at": "aim", "rng": 18.0, "r": 2.2, "n": 6, "interval": 0.3, "scatter": 4.0, "status": {"burn": 8.0}, "telegraph": true, "sky": true}], "vis": {"shape": "sky_fire", "col": Color(1.0, 0.5, 0.15), "rune": "fire", "big": true}, "sfx": "explosion", "ai": {"use": "aoe", "rng": 16.0}}))
	L.append(S("f_sun_worshipper", s, 10, "Солнцепоклонник", "КАТАКЛИЗМ. Над ареной рождается огненное ядро; через 3 с — вспышка и ударная волна 12 м.", {"mana": 160.0, "cd": 120.0, "cast": 3.0, "dmg": 420.0,
		"fx": [{"c": "cataclysm", "kind": "sun", "at": "aim", "rng": 22.0, "r": 12.0, "delay": 0.4, "status": {"burn": 20.0}, "after_zone": "fire"}], "vis": {"shape": "sun_core", "col": Color(1.0, 0.55, 0.15), "rune": "fire", "big": true}, "sfx": "explosion", "ai": {"use": "cataclysm", "rng": 20.0}}))

static func _ice(L: Array) -> void:
	var s := "ice"
	L.append(S("i_cold_touch", s, 1, "Холодное касание", "Ледяное прикосновение (4 м): урон и замедление.", {"mana": 8.0, "cd": 1.0, "cast": 0.2, "dmg": 15.0,
		"fx": [{"c": "bolt", "rng": 4.0, "cone": 60.0, "status": {"slow": 0.6}}], "vis": {"shape": "frost_touch", "col": Color(0.6, 0.9, 1.0)}, "sfx": "ice_cast", "ai": {"use": "melee", "rng": 3.5}}))
	L.append(S("i_frost_needle", s, 2, "Морозная игла", "Быстрый кристаллический снаряд.", {"mana": 10.0, "cd": 1.0, "cast": 0.25, "dmg": 18.0,
		"fx": [{"c": "proj", "spd": 38.0, "rng": 24.0, "kind": "magic", "status": {"slow": 0.8}}], "vis": {"shape": "needle", "col": Color(0.75, 0.95, 1.0)}, "sfx": "ice_cast", "ai": {"use": "ranged", "rng": 22.0}}))
	L.append(S("i_ice_path", s, 3, "Ледяная дорожка", "Скользкая полоса 8 м на 6 с: враги замедляются и поскальзываются.", {"mana": 18.0, "cd": 8.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "zone", "kind": "ice_path", "at": "line", "len": 8.0, "r": 1.4, "dur": 6.0, "status": {"slow": 0.5}}], "vis": {"shape": "ice_path", "col": Color(0.7, 0.92, 1.0), "rune": "frost"}, "sfx": "ice_crack", "ai": {"use": "defend", "rng": 8.0}}))
	L.append(S("i_shard_fan", s, 4, "Осколочный веер", "Пять ледяных осколков веером 50°.", {"mana": 20.0, "cd": 4.0, "cast": 0.3, "dmg": 16.0,
		"fx": [{"c": "proj", "n": 5, "spread": 50.0, "spd": 30.0, "rng": 16.0, "kind": "magic", "status": {"slow": 0.7}}], "vis": {"shape": "shards", "col": Color(0.7, 0.92, 1.0)}, "sfx": "ice_cast", "ai": {"use": "aoe", "rng": 12.0}}))
	L.append(S("i_crystal_shield", s, 5, "Хрустальный щит", "Хрустальная оболочка 10 с поглощает урон (60 + 4 × мастерство).", {"mana": 30.0, "cd": 18.0, "cast": 0.4, "dmg": 0.0, "sustain": true,
		"fx": [{"c": "shield", "to": "self", "amt": 60.0, "per_lvl": 4.0, "dur": 10.0}], "vis": {"shape": "crystal_shell", "col": Color(0.75, 0.95, 1.0)}, "sfx": "ice_shatter", "ai": {"use": "defend"}}))
	L.append(S("i_freezing_ring", s, 6, "Замораживающее кольцо", "Кольцо холода 5 м: замедление, мокрые цели замерзают.", {"mana": 30.0, "cd": 10.0, "cast": 0.35, "dmg": 20.0,
		"fx": [{"c": "nova", "r": 5.0, "status": {"slow": 0.4}, "wet_freeze": 2.0}], "vis": {"shape": "frost_ring", "col": Color(0.6, 0.9, 1.0), "rune": "frost"}, "sfx": "ice_shatter", "ai": {"use": "aoe", "rng": 4.5}}))
	L.append(S("i_ice_lances", s, 7, "Ледяные копья", "Из земли бьют пять высоких ледяных шипов к цели (временные преграды).", {"mana": 45.0, "cd": 12.0, "cast": 0.5, "dmg": 50.0,
		"fx": [{"c": "terrain", "kind": "ice_spike", "at": "line", "n": 5, "len": 9.0, "r": 1.3, "life": 5.0, "knock_up": 6.0, "status": {"slow": 0.5}}], "vis": {"shape": "ice_spikes", "col": Color(0.7, 0.95, 1.0), "rune": "frost"}, "sfx": "ice_shatter", "ai": {"use": "line", "rng": 9.0}}))
	L.append(S("i_winter_guard", s, 8, "Зимний страж", "Призывает ледяного стража на 15 с: он стоит и бьёт морозными иглами.", {"mana": 50.0, "cd": 35.0, "cast": 0.8, "dmg": 0.0,
		"fx": [{"c": "summon", "id": "ice_guardian", "n": 1, "life": 15.0, "limit": 1, "at": "front"}], "vis": {"shape": "construct", "col": Color(0.7, 0.95, 1.0), "rune": "frost"}, "sfx": "ice_crack", "ai": {"use": "summon"}}))
	L.append(S("i_white_silence", s, 9, "Белое Безмолвие", "Сильная метель 7 м на 8 с: сильное замедление и ледяные преграды.", {"mana": 80.0, "cd": 30.0, "cast": 1.3, "dmg": 18.0,
		"fx": [{"c": "zone", "kind": "blizzard", "at": "aim", "rng": 16.0, "r": 7.0, "dur": 8.0, "status": {"slow": 0.25}}, {"c": "terrain", "kind": "ice_wall", "at": "aim", "rng": 16.0, "n": 3, "r": 5.0, "life": 8.0}], "vis": {"shape": "blizzard", "col": Color(0.85, 0.97, 1.0), "rune": "frost", "big": true}, "sfx": "ice_cast", "ai": {"use": "aoe", "rng": 15.0}}))
	L.append(S("i_eternal_winter", s, 10, "Вечная Зима", "КАТАКЛИЗМ. Зона 12 м покрывается ледяными структурами, три морозные волны замораживают врагов.", {"mana": 160.0, "cd": 120.0, "cast": 3.0, "dmg": 300.0,
		"fx": [{"c": "cataclysm", "kind": "winter", "at": "aim", "rng": 20.0, "r": 12.0, "waves": 3, "status": {"freeze": 2.0}, "after_zone": "blizzard"}], "vis": {"shape": "winter", "col": Color(0.75, 0.95, 1.0), "rune": "frost", "big": true}, "sfx": "ice_shatter", "ai": {"use": "cataclysm", "rng": 18.0}}))

static func _lightning(L: Array) -> void:
	var s := "lightning"
	L.append(S("l_electric_spark", s, 1, "Электрическая искра", "Короткий направленный разряд в ближайшую цель.", {"mana": 8.0, "cd": 0.9, "cast": 0.15, "dmg": 16.0,
		"fx": [{"c": "bolt", "rng": 14.0, "cone": 50.0, "status": {"stun": 0.1}}], "vis": {"shape": "zap", "col": Color(0.75, 0.85, 1.0)}, "sfx": "lightning", "ai": {"use": "ranged", "rng": 13.0}}))
	L.append(S("l_charged_touch", s, 2, "Заряженное касание", "Электрический удар вблизи (2,5 м) с оглушением.", {"mana": 10.0, "cd": 2.0, "cast": 0.15, "dmg": 26.0,
		"fx": [{"c": "cone", "r": 2.5, "ang": 80.0, "status": {"stun": 0.35}}], "vis": {"shape": "shock_palm", "col": Color(0.7, 0.8, 1.0)}, "sfx": "elec_crackle", "ai": {"use": "melee", "rng": 2.3}}))
	L.append(S("l_chain_flash", s, 3, "Цепная вспышка", "Разряд перескакивает между четырьмя целями.", {"mana": 20.0, "cd": 4.0, "cast": 0.3, "dmg": 22.0,
		"fx": [{"c": "chain", "jumps": 4, "rng": 16.0}], "vis": {"shape": "chain", "col": Color(0.7, 0.8, 1.0)}, "sfx": "lightning", "ai": {"use": "ranged", "rng": 15.0}}))
	L.append(S("l_storm_mark", s, 4, "Грозовая метка", "Метка 10 с: цель получает на 40% больше урона от молний.", {"mana": 14.0, "cd": 8.0, "cast": 0.2, "dmg": 0.0,
		"fx": [{"c": "debuff", "to": "target", "rng": 18.0, "status": "storm_mark", "dur": 10.0, "prm": {"vuln": {"lightning": 0.4}}}], "vis": {"shape": "mark", "col": Color(0.6, 0.75, 1.0)}, "sfx": "elec_crackle", "ai": {"use": "open", "rng": 16.0}}))
	L.append(S("l_ground_discharge", s, 5, "Разряд по земле", "Электрическая волна по земле: конус 7 м и заряженная земля 2 с.", {"mana": 30.0, "cd": 7.0, "cast": 0.35, "dmg": 35.0,
		"fx": [{"c": "cone", "r": 7.0, "ang": 60.0, "status": {"stun": 0.3}}, {"c": "zone", "kind": "electric", "at": "front", "dist": 3.5, "r": 2.5, "dur": 2.0, "mult": 0.2}], "vis": {"shape": "ground_arc", "col": Color(0.65, 0.78, 1.0)}, "sfx": "thunder", "ai": {"use": "aoe", "rng": 6.0}}))
	L.append(S("l_lightning_dash", s, 6, "Молниеносный рывок", "Рывок на 8 м с электрическим следом, ранящим всех на пути.", {"mana": 26.0, "cd": 6.0, "cast": 0.1, "dmg": 30.0,
		"fx": [{"c": "move", "kind": "blink_path", "dist": 8.0, "mult": 1.0, "status": {"stun": 0.2}}], "vis": {"shape": "bolt_dash", "col": Color(0.75, 0.85, 1.0)}, "sfx": "teleport", "ai": {"use": "escape"}}))
	L.append(S("l_ball_lightning", s, 7, "Шаровая молния", "Медленная шаровая молния 6 с бьёт разрядами всех рядом.", {"mana": 45.0, "cd": 14.0, "cast": 0.5, "dmg": 18.0,
		"fx": [{"c": "zone", "kind": "electric", "at": "front", "dist": 2.0, "r": 3.0, "dur": 6.0, "move": 4.0, "prm": {"orb": true}}], "vis": {"shape": "ball", "col": Color(0.75, 0.85, 1.0)}, "sfx": "elec_crackle", "ai": {"use": "aoe", "rng": 12.0}}))
	L.append(S("l_thunder_guard", s, 8, "Громовой страж", "Электрический столп на 15 с бьёт врагов поблизости.", {"mana": 50.0, "cd": 35.0, "cast": 0.8, "dmg": 0.0,
		"fx": [{"c": "summon", "id": "thunder_guardian", "n": 1, "life": 15.0, "limit": 1, "at": "front"}], "vis": {"shape": "construct", "col": Color(0.6, 0.75, 1.0), "rune": "storm"}, "sfx": "thunder", "ai": {"use": "summon"}}))
	L.append(S("l_nine_strikes", s, 9, "Девять Небесных Разрядов", "Девять мощных молний по отмеченной зоне 6 м.", {"mana": 80.0, "cd": 28.0, "cast": 1.2, "dmg": 70.0,
		"fx": [{"c": "blast", "at": "aim", "rng": 18.0, "r": 2.0, "n": 9, "interval": 0.22, "scatter": 5.0, "prefer_targets": true, "status": {"stun": 0.3}, "telegraph": true, "sky": true}], "vis": {"shape": "sky_bolt", "col": Color(0.8, 0.88, 1.0), "rune": "storm", "big": true}, "sfx": "thunder", "ai": {"use": "aoe", "rng": 16.0}}))
	L.append(S("l_storm_heart", s, 10, "Сердце Грозы", "КАТАКЛИЗМ. Над ареной грозовое облако: восемь ударов с ясным предупреждением, финальный — вдвое сильнее.", {"mana": 160.0, "cd": 120.0, "cast": 3.0, "dmg": 110.0,
		"fx": [{"c": "cataclysm", "kind": "storm", "at": "aim", "rng": 20.0, "r": 12.0, "strikes": 8, "status": {"stun": 0.6}}], "vis": {"shape": "storm_cloud", "col": Color(0.75, 0.85, 1.0), "rune": "storm", "big": true}, "sfx": "thunder", "ai": {"use": "cataclysm", "rng": 18.0}}))

static func _dark(L: Array) -> void:
	var s := "dark"
	L.append(S("d_shadow_needle", s, 1, "Теневая игла", "Быстрый тёмный снаряд.", {"mana": 8.0, "cd": 0.9, "cast": 0.25, "dmg": 16.0,
		"fx": [{"c": "proj", "spd": 32.0, "rng": 22.0, "kind": "magic"}], "vis": {"shape": "needle", "col": Color(0.6, 0.25, 0.85)}, "sfx": "dark_cast", "ai": {"use": "ranged", "rng": 20.0}}))
	L.append(S("d_weakness_seal", s, 2, "Печать слабости", "Цель 8 с наносит на 25% меньше урона.", {"mana": 12.0, "cd": 8.0, "cast": 0.25, "dmg": 0.0,
		"fx": [{"c": "debuff", "to": "target", "rng": 16.0, "status": "weakness", "dur": 8.0, "prm": {"mods": {"dmg_pct": -0.25}}}], "vis": {"shape": "seal", "col": Color(0.55, 0.2, 0.8), "rune": "sigil"}, "sfx": "dark_cast", "ai": {"use": "open", "rng": 15.0}}))
	L.append(S("d_dark_veil", s, 3, "Тёмная завеса", "Область 4 м на 6 с: союзников внутри замечают только вплотную.", {"mana": 22.0, "cd": 18.0, "cast": 0.4, "dmg": 0.0,
		"fx": [{"c": "zone", "kind": "dark_veil", "at": "self", "r": 4.0, "dur": 6.0, "prm": {"veil": true}}], "vis": {"shape": "veil", "col": Color(0.3, 0.1, 0.4), "rune": "sigil"}, "sfx": "dark_hum", "ai": {"use": "escape"}}))
	L.append(S("d_fear_whisper", s, 4, "Шёпот страха", "Слабые враги в конусе 6 м (не сильнее мага, не боссы) бегут 3 с.", {"mana": 18.0, "cd": 12.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "cone", "r": 6.0, "ang": 70.0, "mult": 0.0, "status": {"fear": 3.0}, "weak_only": true}], "vis": {"shape": "whisper", "col": Color(0.55, 0.2, 0.8)}, "sfx": "dark_hum", "ai": {"use": "defend", "rng": 5.0}}))
	L.append(S("d_cursed_chains", s, 5, "Проклятые цепи", "Цепи сковывают цель на 2,5 с и жгут тьмой.", {"mana": 30.0, "cd": 10.0, "cast": 0.35, "dmg": 20.0,
		"fx": [{"c": "bolt", "rng": 16.0, "cone": 45.0, "status": {"root": 2.5, "decay": 6.0}}], "vis": {"shape": "chains", "col": Color(0.6, 0.25, 0.85)}, "sfx": "dark_cast", "ai": {"use": "open", "rng": 15.0}}))
	L.append(S("d_energy_drain", s, 6, "Поглощение энергии", "Выпивает силы цели: возвращает мане половину урона (без маны у цели — здоровье).", {"mana": 24.0, "cd": 6.0, "cast": 0.3, "dmg": 30.0,
		"fx": [{"c": "bolt", "rng": 14.0, "cone": 45.0, "drain": 0.5}], "vis": {"shape": "drain", "col": Color(0.6, 0.25, 0.85)}, "sfx": "dark_cast", "ai": {"use": "ranged", "rng": 13.0}}))
	L.append(S("d_shadow_copy", s, 7, "Теневая копия", "Иллюзорная копия мага 6 с отвлекает врагов и взрывается тьмой.", {"mana": 40.0, "cd": 22.0, "cast": 0.4, "dmg": 40.0,
		"fx": [{"c": "decoy", "life": 6.0, "burst": 3.0}], "vis": {"shape": "decoy", "col": Color(0.5, 0.2, 0.8)}, "sfx": "teleport", "ai": {"use": "escape"}}))
	L.append(S("d_abyss_seal", s, 8, "Печать бездны", "Опасная руническая область 4 м на 6 с: тьма и замедление.", {"mana": 50.0, "cd": 14.0, "cast": 0.5, "dmg": 22.0,
		"fx": [{"c": "zone", "kind": "dark", "at": "aim", "rng": 16.0, "r": 4.0, "dur": 6.0, "status": {"slow": 0.6}}], "vis": {"shape": "abyss", "col": Color(0.45, 0.1, 0.7), "rune": "sigil"}, "sfx": "dark_hum", "ai": {"use": "aoe", "rng": 15.0}}))
	L.append(S("d_silence_gates", s, 9, "Врата Безмолвия", "Область 7 м на 8 с: враги внутри не могут применять умения (боссы лишь замедляются).", {"mana": 80.0, "cd": 35.0, "cast": 1.3, "dmg": 10.0,
		"fx": [{"c": "zone", "kind": "silence", "at": "aim", "rng": 16.0, "r": 7.0, "dur": 8.0, "prm": {"silence": true}}], "vis": {"shape": "gates", "col": Color(0.45, 0.15, 0.7), "rune": "sigil", "big": true}, "sfx": "dark_hum", "ai": {"use": "aoe", "rng": 15.0}}))
	L.append(S("d_void_crown", s, 10, "Корона Пустоты", "КАТАКЛИЗМ. Тёмная корона над магом и шесть печатей по арене: последовательные взрывы и слабость.", {"mana": 160.0, "cd": 120.0, "cast": 3.0, "dmg": 360.0,
		"fx": [{"c": "cataclysm", "kind": "void", "at": "aim", "rng": 20.0, "r": 12.0, "seals": 6, "status": {"weakness": 6.0}}], "vis": {"shape": "void_crown", "col": Color(0.5, 0.15, 0.8), "rune": "sigil", "big": true}, "sfx": "dark_hum", "ai": {"use": "cataclysm", "rng": 18.0}}))

static func _time(L: Array) -> void:
	var s := "spacetime"
	L.append(S("t_minor_shift", s, 1, "Малый сдвиг", "Короткое перемещение на 5 м.", {"mana": 8.0, "cd": 3.0, "cast": 0.05, "dmg": 0.0,
		"fx": [{"c": "move", "kind": "blink", "dist": 5.0}], "vis": {"shape": "shift", "col": Color(0.45, 1.0, 0.85)}, "sfx": "teleport", "ai": {"use": "escape"}}))
	L.append(S("t_time_trace", s, 2, "Временной след", "Остаточный силуэт мага 3 с отвлекает врагов.", {"mana": 10.0, "cd": 10.0, "cast": 0.1, "dmg": 0.0,
		"fx": [{"c": "decoy", "life": 3.0}], "vis": {"shape": "afterimage", "col": Color(0.45, 1.0, 0.85)}, "sfx": "time_warp", "ai": {"use": "escape"}}))
	L.append(S("t_space_push", s, 3, "Пространственный толчок", "Отбрасывает цели в секторе 5 м.", {"mana": 18.0, "cd": 7.0, "cast": 0.25, "dmg": 18.0,
		"fx": [{"c": "cone", "r": 5.0, "ang": 70.0, "knock": 8.0}], "vis": {"shape": "space_wave", "col": Color(0.45, 1.0, 0.85)}, "sfx": "time_warp", "ai": {"use": "defend", "rng": 4.5}}))
	L.append(S("t_delay_rune", s, 4, "Руна задержки", "Руна 3 м на 6 с замедляет врагов и снаряды.", {"mana": 20.0, "cd": 10.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "zone", "kind": "timeslow", "at": "aim", "rng": 12.0, "r": 3.0, "dur": 6.0}], "vis": {"shape": "clock_rune", "col": Color(0.45, 1.0, 0.85), "rune": "clock"}, "sfx": "time_slow", "ai": {"use": "defend", "rng": 10.0}}))
	L.append(S("t_phase_step", s, 5, "Фазовый шаг", "Сквозь врагов на 8 м, 0,5 с неуязвимости, урон по пути.", {"mana": 24.0, "cd": 6.0, "cast": 0.05, "dmg": 25.0,
		"fx": [{"c": "move", "kind": "blink_path", "dist": 8.0, "mult": 1.0, "invuln": 0.5}], "vis": {"shape": "phase", "col": Color(0.5, 1.0, 0.9)}, "sfx": "teleport", "ai": {"use": "escape"}}))
	L.append(S("t_instant_mirror", s, 6, "Зеркало мгновения", "Повторяет ваше последнее заклинание (до IV ступени) на 70% силы бесплатно.", {"mana": 30.0, "cd": 15.0, "cast": 0.2, "dmg": 0.0,
		"fx": [{"c": "mirror", "pow": 0.7}], "vis": {"shape": "mirror", "col": Color(0.6, 1.0, 0.95)}, "sfx": "time_warp", "ai": {"use": "never"}}))
	L.append(S("t_time_trap", s, 7, "Временная ловушка", "Область 3 м на 10 с: первые три вошедших врага застывают на 3 с.", {"mana": 40.0, "cd": 12.0, "cast": 0.4, "dmg": 20.0,
		"fx": [{"c": "zone", "kind": "timetrap", "at": "aim", "rng": 12.0, "r": 3.0, "dur": 10.0, "prm": {"stasis": 3.0, "uses": 3}}], "vis": {"shape": "trap", "col": Color(0.45, 1.0, 0.85), "rune": "clock"}, "sfx": "time_slow", "ai": {"use": "defend", "rng": 10.0}}))
	L.append(S("t_coord_rupture", s, 8, "Разрыв координат", "Четыре пространственных импульса вокруг цели.", {"mana": 45.0, "cd": 10.0, "cast": 0.45, "dmg": 40.0,
		"fx": [{"c": "blast", "at": "aim", "rng": 16.0, "r": 2.2, "n": 4, "interval": 0.18, "scatter": 3.0, "prefer_targets": true}], "vis": {"shape": "rupture", "col": Color(0.5, 1.0, 0.9), "rune": "rift"}, "sfx": "portal_open", "ai": {"use": "aoe", "rng": 15.0}}))
	L.append(S("t_frozen_moment", s, 9, "Застывший миг", "Зона 6 м на 5 с: враги и снаряды почти останавливаются.", {"mana": 80.0, "cd": 35.0, "cast": 1.0, "dmg": 0.0,
		"fx": [{"c": "zone", "kind": "timeslow", "at": "aim", "rng": 14.0, "r": 6.0, "dur": 5.0, "prm": {"f": 0.1}}], "vis": {"shape": "frozen_moment", "col": Color(0.5, 1.0, 0.9), "rune": "clock", "big": true}, "sfx": "time_slow", "ai": {"use": "aoe", "rng": 13.0}}))
	L.append(S("t_rift_seconds", s, 10, "Разлом Секунд", "КАТАКЛИЗМ. Локальное искажение времени 12 м на 10 с: враги на 80% медленнее и получают импульсы, союзники ускорены.", {"mana": 160.0, "cd": 120.0, "cast": 3.0, "dmg": 60.0,
		"fx": [{"c": "cataclysm", "kind": "rift_seconds", "at": "aim", "rng": 18.0, "r": 12.0, "dur": 10.0, "pulses": 5}], "vis": {"shape": "time_rift", "col": Color(0.45, 1.0, 0.85), "rune": "clock", "big": true}, "sfx": "time_warp", "ai": {"use": "cataclysm", "rng": 16.0}}))

static func _earth(L: Array) -> void:
	var s := "earth"
	L.append(S("e_stone_shard", s, 1, "Каменный осколок", "Камень поднимается с земли и летит в противника.", {"mana": 9.0, "cd": 1.0, "cast": 0.3, "dmg": 18.0,
		"fx": [{"c": "proj", "spd": 26.0, "rng": 20.0, "kind": "rock", "knock": 2.0}], "vis": {"shape": "rock", "col": Color(0.6, 0.5, 0.38)}, "sfx": "ground_crack", "ai": {"use": "ranged", "rng": 18.0}}))
	L.append(S("e_earth_jolt", s, 2, "Земляной толчок", "Ударная волна по земле: конус 4 м и пошатывание.", {"mana": 12.0, "cd": 4.0, "cast": 0.25, "dmg": 20.0,
		"fx": [{"c": "cone", "r": 4.0, "ang": 80.0, "status": {"stun": 0.25}, "knock": 3.0}], "vis": {"shape": "jolt", "col": Color(0.6, 0.5, 0.38)}, "sfx": "ground_crack", "ai": {"use": "melee", "rng": 3.5}}))
	L.append(S("e_stone_skin", s, 3, "Каменная кожа", "15 с: броня +12 (+0,8 за уровень школы), скорость −5%.", {"mana": 20.0, "cd": 20.0, "cast": 0.4, "dmg": 0.0, "sustain": true,
		"fx": [{"c": "buff", "to": "self", "status": "stone_skin", "dur": 15.0, "prm": {"mods": {"armor": 12.0, "speed": -0.05}, "per_lvl": {"armor": 0.8}}}], "vis": {"shape": "stone_skin", "col": Color(0.6, 0.52, 0.42)}, "sfx": "ground_crack", "ai": {"use": "buff"}}))
	L.append(S("e_mud_trap", s, 4, "Грязевая ловушка", "Вязкая грязь 3,5 м на 7 с замедляет врагов.", {"mana": 20.0, "cd": 10.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "zone", "kind": "mud", "at": "aim", "rng": 12.0, "r": 3.5, "dur": 7.0, "status": {"slow": 0.4}}], "vis": {"shape": "mud", "col": Color(0.4, 0.32, 0.22), "rune": "stone"}, "sfx": "ground_crack", "ai": {"use": "defend", "rng": 10.0}}))
	L.append(S("e_stone_spears", s, 5, "Каменные копья", "Шесть острых каменных копий вырастают к цели (держатся 4 с, мешают пройти).", {"mana": 32.0, "cd": 8.0, "cast": 0.45, "dmg": 45.0,
		"fx": [{"c": "terrain", "kind": "stone_spike", "at": "line", "n": 6, "len": 9.0, "r": 1.2, "life": 4.0, "knock_up": 6.0, "solid": true}], "vis": {"shape": "stone_spears", "col": Color(0.6, 0.5, 0.38), "rune": "stone"}, "sfx": "ground_crack", "ai": {"use": "line", "rng": 9.0}}))
	L.append(S("e_bastion_wall", s, 6, "Стена бастиона", "Каменная стена 6 м поперёк на 10 с: преграждает путь и снаряды.", {"mana": 30.0, "cd": 16.0, "cast": 0.5, "dmg": 0.0,
		"fx": [{"c": "terrain", "kind": "stone_wall", "at": "front", "dist": 3.5, "n": 5, "r": 6.0, "life": 10.0, "solid": true, "hp": 120.0}], "vis": {"shape": "wall", "col": Color(0.55, 0.47, 0.38), "rune": "stone"}, "sfx": "ground_crack", "ai": {"use": "wall", "rng": 9.0}}))
	L.append(S("e_mountain_fist", s, 7, "Кулак горы", "Огромный каменный кулак обрушивается на область 3 м и оглушает.", {"mana": 48.0, "cd": 13.0, "cast": 0.6, "dmg": 90.0,
		"fx": [{"c": "blast", "at": "aim", "rng": 16.0, "r": 3.0, "delay": 0.8, "status": {"stun": 1.0}, "knock": 5.0, "telegraph": true, "fist": true}], "vis": {"shape": "fist", "col": Color(0.55, 0.47, 0.38), "rune": "stone"}, "sfx": "explosion", "ai": {"use": "aoe", "rng": 15.0}}))
	L.append(S("e_guardian_golem", s, 8, "Голем хранителя", "Призывает каменного голема на 25 с: он защищает мага и бьёт врагов. Знание голема хранится в древних подземельях (или у наставника).", {"mana": 60.0, "cd": 45.0, "cast": 1.0, "dmg": 0.0, "need_know": true,
		"fx": [{"c": "summon", "id": "stone_golem", "n": 1, "life": 25.0, "limit": 1, "at": "front"}], "vis": {"shape": "construct", "col": Color(0.6, 0.5, 0.38), "rune": "stone"}, "sfx": "ground_crack", "ai": {"use": "summon"}}))
	L.append(S("e_mountain_heart", s, 9, "Гнев Горного Сердца", "Пять разломов расходятся от точки: каменные волны и шипы.", {"mana": 85.0, "cd": 30.0, "cast": 1.4, "dmg": 70.0,
		"fx": [{"c": "fissures", "at": "aim", "rng": 16.0, "n": 5, "len": 8.0, "status": {"stun": 0.5}}], "vis": {"shape": "fissures", "col": Color(0.6, 0.48, 0.35), "rune": "stone", "big": true}, "sfx": "explosion", "ai": {"use": "aoe", "rng": 15.0}}))
	L.append(S("e_great_quake", s, 10, "Великое Землетрясение", "КАТАКЛИЗМ. В области 13 м земля трясётся, поднимаются каменные плиты, три ударные волны; через 10 с всё возвращается.", {"mana": 170.0, "cd": 120.0, "cast": 3.0, "dmg": 380.0,
		"fx": [{"c": "cataclysm", "kind": "quake", "at": "aim", "rng": 20.0, "r": 13.0, "waves": 3, "platforms": 7, "status": {"stun": 1.2}}], "vis": {"shape": "quake", "col": Color(0.62, 0.5, 0.36), "rune": "stone", "big": true}, "sfx": "explosion", "ai": {"use": "cataclysm", "rng": 18.0}}))

static func _necro(L: Array) -> void:
	var s := "necro"
	L.append(S("n_bone_whisper", s, 1, "Шёпот костей", "10 с: видны следы смерти и некромантическая энергия в 35 м.", {"mana": 6.0, "cd": 15.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "reveal", "r": 35.0, "dur": 10.0, "what": "death"}], "vis": {"shape": "pulse", "col": Color(0.45, 0.85, 0.55), "rune": "bone"}, "sfx": "dark_hum", "ai": {"use": "never"}}))
	L.append(S("n_bone_spike", s, 2, "Костяной шип", "Магический костяной снаряд.", {"mana": 9.0, "cd": 1.0, "cast": 0.25, "dmg": 18.0,
		"fx": [{"c": "proj", "spd": 30.0, "rng": 22.0, "kind": "bone"}], "vis": {"shape": "bone", "col": Color(0.9, 0.9, 0.8)}, "sfx": "dark_cast", "ai": {"use": "ranged", "rng": 20.0}}))
	L.append(S("n_wither_curse", s, 3, "Проклятие увядания", "8 с: цель увядает (урон тьмой каждую секунду) и теряет 20% брони.", {"mana": 16.0, "cd": 8.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "debuff", "to": "target", "rng": 16.0, "status": "wither", "dur": 8.0, "prm": {"dot": 6.0, "dtype": "dark", "mods": {"armor_pct": -0.2}}}], "vis": {"shape": "seal", "col": Color(0.4, 0.75, 0.45), "rune": "bone"}, "sfx": "dark_cast", "ai": {"use": "open", "rng": 15.0}}))
	L.append(S("n_grave_hand", s, 4, "Рука могилы", "Костяная рука из земли держит цель 2,5 с.", {"mana": 20.0, "cd": 10.0, "cast": 0.3, "dmg": 14.0,
		"fx": [{"c": "blast", "at": "target", "rng": 14.0, "r": 1.2, "delay": 0.4, "status": {"root": 2.5}, "hand": true}], "vis": {"shape": "grave_hand", "col": Color(0.85, 0.85, 0.75), "rune": "bone"}, "sfx": "dark_cast", "ai": {"use": "open", "rng": 13.0}}))
	L.append(S("n_raise_servant", s, 5, "Поднятие слуги", "Временный неживой помощник на 30 с (до двух). Рядом с недавней смертью — дешевле.", {"mana": 35.0, "cd": 20.0, "cast": 0.8, "dmg": 0.0,
		"fx": [{"c": "summon", "id": "skeleton_minion", "n": 1, "life": 30.0, "limit": 2, "at": "front", "corpse": true}], "vis": {"shape": "raise", "col": Color(0.45, 0.85, 0.55), "rune": "bone"}, "sfx": "dark_cast", "ai": {"use": "summon"}}))
	L.append(S("n_bone_shield", s, 6, "Костяной щит", "12 с вокруг вращаются кости: поглощают урон (50 + 3 × мастерство).", {"mana": 28.0, "cd": 18.0, "cast": 0.4, "dmg": 0.0, "sustain": true,
		"fx": [{"c": "shield", "to": "self", "amt": 50.0, "per_lvl": 3.0, "dur": 12.0, "orbit": "bone"}], "vis": {"shape": "bone_orbit", "col": Color(0.9, 0.9, 0.8)}, "sfx": "dark_cast", "ai": {"use": "defend"}}))
	L.append(S("n_soul_seal", s, 7, "Печать души", "Метка 15 с: некромантия по цели +30%; её смерть вернёт 25% маны.", {"mana": 30.0, "cd": 10.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "debuff", "to": "target", "rng": 16.0, "status": "soul_seal", "dur": 15.0, "prm": {"vuln_school": {"necro": 0.3}, "by_me": true}}], "vis": {"shape": "soul", "col": Color(0.45, 0.9, 0.6), "rune": "bone"}, "sfx": "dark_hum", "ai": {"use": "open", "rng": 15.0}}))
	L.append(S("n_burial_knight", s, 8, "Рыцарь Погребения", "Мощный неживой защитник на 30 с (один).", {"mana": 60.0, "cd": 50.0, "cast": 1.0, "dmg": 0.0,
		"fx": [{"c": "summon", "id": "bone_knight", "n": 1, "life": 30.0, "limit": 1, "at": "front"}], "vis": {"shape": "raise", "col": Color(0.45, 0.85, 0.55), "rune": "bone"}, "sfx": "dark_cast", "ai": {"use": "summon"}}))
	L.append(S("n_black_liturgy", s, 9, "Чёрная Литургия", "Ритуальная область 6 м на 10 с: призванные внутри +40% урона и лечатся, некромантия дешевле на 30%.", {"mana": 80.0, "cd": 40.0, "cast": 1.5, "dmg": 0.0,
		"fx": [{"c": "zone", "kind": "liturgy", "at": "self", "r": 6.0, "dur": 10.0, "prm": {"liturgy": true}}], "vis": {"shape": "liturgy", "col": Color(0.4, 0.8, 0.5), "rune": "bone", "big": true}, "sfx": "dark_hum", "ai": {"use": "buff"}}))
	L.append(S("n_march_of_dead", s, 10, "Марш Мёртвых", "КАТАКЛИЗМ. Огромная печать 12 м и наступление четырёх призрачных и костяных воинов на 20 с.", {"mana": 170.0, "cd": 150.0, "cast": 3.0, "dmg": 0.0,
		"fx": [{"c": "cataclysm", "kind": "march", "at": "aim", "rng": 18.0, "r": 12.0, "life": 20.0}], "vis": {"shape": "march", "col": Color(0.45, 0.9, 0.55), "rune": "bone", "big": true}, "sfx": "dark_hum", "ai": {"use": "cataclysm", "rng": 16.0}}))

static func _heal(L: Array) -> void:
	var s := "heal"
	L.append(S("h_warm_touch", s, 1, "Тёплое прикосновение", "Восстанавливает 12% здоровья (себе или раненому союзнику рядом).", {"mana": 10.0, "cd": 2.0, "cast": 0.4, "dmg": 0.0,
		"fx": [{"c": "heal", "to": "ally_or_self", "r": 8.0, "amt": 0.12}], "vis": {"shape": "heal_touch", "col": Color(1.0, 0.88, 0.5), "rune": "lotus"}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_soothing_light", s, 2, "Успокаивающий свет", "Снимает лёгкие отрицательные эффекты, боль от лёгких травм утихает на 3 ч.", {"mana": 12.0, "cd": 8.0, "cast": 0.4, "dmg": 0.0,
		"fx": [{"c": "heal", "to": "self", "amt": 0.05, "hc": "soothe", "cleanse": ["slow", "stun", "blind", "weakness"]}], "vis": {"shape": "soothe", "col": Color(1.0, 0.92, 0.65), "rune": "lotus"}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_close_wound", s, 3, "Закрытие раны", "Заживляет выбранную лёгкую или среднюю рану (порез, колотая) без заражения; без Hardcore — 18% здоровья.", {"mana": 20.0, "cd": 10.0, "cast": 0.6, "dmg": 0.0,
		"fx": [{"c": "heal", "to": "self", "amt": 0.18, "hc": "close_wound"}], "vis": {"shape": "close_wound", "col": Color(1.0, 0.85, 0.45), "rune": "lotus"}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_hemostasis", s, 4, "Печать кровостаза", "Останавливает кровотечение в выбранной зоне (сильное — с мастерства 10, иначе ослабляет).", {"mana": 18.0, "cd": 8.0, "cast": 0.4, "dmg": 0.0,
		"fx": [{"c": "heal", "to": "self", "amt": 0.05, "hc": "hemostasis"}], "vis": {"shape": "hemostasis", "col": Color(1.0, 0.75, 0.4), "rune": "lotus"}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_cleansing_flow", s, 5, "Очищающий поток", "Снимает яды и проклятия заклинаний, ранние стадии заражения (заражение средней раны — с мастерства 12).", {"mana": 28.0, "cd": 14.0, "cast": 0.6, "dmg": 0.0,
		"fx": [{"c": "heal", "to": "self", "amt": 0.06, "hc": "cleanse", "cleanse": ["curse", "decay", "wither", "weakness", "bleed"]}], "vis": {"shape": "flow", "col": Color(0.75, 1.0, 0.7), "rune": "lotus"}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_tissue_restore", s, 6, "Восстановление тканей", "Ускоряет заживление выбранной травмы (не перелома) и снимает часть штрафов; без Hardcore — 25% за 5 с.", {"mana": 32.0, "cd": 16.0, "cast": 0.8, "dmg": 0.0,
		"fx": [{"c": "heal", "to": "self", "amt": 0.0, "hot": 0.05, "hot_dur": 5.0, "hc": "tissue"}], "vis": {"shape": "tissue", "col": Color(0.8, 1.0, 0.6), "rune": "lotus"}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_bone_unity", s, 7, "Костяное единство", "Сращивает тяжёлый перелом (шина + заживление). Дорого и долго; кровотечение должно быть остановлено.", {"mana": 50.0, "cd": 30.0, "cast": 2.0, "dmg": 0.0,
		"fx": [{"c": "heal", "to": "self", "amt": 0.08, "hc": "bone_unity"}], "vis": {"shape": "bone_unity", "col": Color(1.0, 0.95, 0.75), "rune": "lotus"}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_healers_circle", s, 8, "Круг целителей", "Круг 5 м на 8 с постепенно лечит всех союзников (3%/с), травмы не снимает.", {"mana": 55.0, "cd": 30.0, "cast": 0.8, "dmg": 0.0,
		"fx": [{"c": "zone", "kind": "heal", "at": "self", "r": 5.0, "dur": 8.0, "prm": {"hps_pct": 0.03}}], "vis": {"shape": "heal_circle", "col": Color(0.9, 1.0, 0.6), "rune": "lotus", "big": true}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_great_regen", s, 9, "Великая регенерация", "Сильно улучшает одну тяжёлую травму (−1 ступень, обработка, кровь остановлена) и 40% здоровья. Тяжёлое заражение не лечит.", {"mana": 85.0, "cd": 45.0, "cast": 1.8, "dmg": 0.0,
		"fx": [{"c": "heal", "to": "self", "amt": 0.4, "hc": "great_regen"}], "vis": {"shape": "great_regen", "col": Color(1.0, 0.9, 0.5), "rune": "lotus", "big": true}, "sfx": "heal", "ai": {"use": "heal"}}))
	L.append(S("h_first_dawn", s, 10, "Свет Первого Рассвета", "ВЫСШЕЕ ИСЦЕЛЕНИЕ. Круг 10 м: стабилизирует тяжелораненых союзников, 60% здоровья. Не воскрешает и не снимает проклятий.", {"mana": 180.0, "cd": 180.0, "cast": 3.0, "dmg": 0.0,
		"fx": [{"c": "cataclysm", "kind": "dawn", "at": "self", "r": 10.0}], "vis": {"shape": "dawn", "col": Color(1.0, 0.92, 0.6), "rune": "lotus", "big": true}, "sfx": "heal", "ai": {"use": "heal"}}))

static func _air(L: Array) -> void:
	var s := "air"
	L.append(S("a_light_gust", s, 1, "Лёгкий порыв", "Отталкивает лёгких врагов и предметы в конусе 4 м.", {"mana": 8.0, "cd": 3.0, "cast": 0.2, "dmg": 8.0,
		"fx": [{"c": "cone", "r": 4.0, "ang": 60.0, "knock": 7.0, "light_only": true}], "vis": {"shape": "gust", "col": Color(0.85, 1.0, 1.0)}, "sfx": "slash_air", "ai": {"use": "defend", "rng": 3.5}}))
	L.append(S("a_wind_blade", s, 2, "Ветряной клинок", "Быстрый воздушный полумесяц, пробивает одну цель.", {"mana": 10.0, "cd": 1.2, "cast": 0.2, "dmg": 20.0,
		"fx": [{"c": "proj", "spd": 34.0, "rng": 20.0, "kind": "magic", "pierce": 1}], "vis": {"shape": "crescent", "col": Color(0.8, 1.0, 1.0)}, "sfx": "slash_air", "ai": {"use": "ranged", "rng": 18.0}}))
	L.append(S("a_tailwind", s, 3, "Попутный ветер", "10 с: скорость +25% (маг и союзники в 6 м).", {"mana": 16.0, "cd": 20.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "buff", "to": "allies", "r": 6.0, "status": "tailwind", "dur": 10.0, "prm": {"mods": {"speed": 0.25}}}], "vis": {"shape": "wind_trail", "col": Color(0.85, 1.0, 1.0), "rune": "wind"}, "sfx": "slash_air", "ai": {"use": "buff"}}))
	L.append(S("a_air_shield", s, 4, "Воздушный щит", "6 с отклоняет слабые немагические снаряды.", {"mana": 22.0, "cd": 16.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "buff", "to": "self", "status": "deflect", "dur": 6.0, "prm": {"weak": 40.0}}], "vis": {"shape": "air_dome", "col": Color(0.85, 1.0, 1.0)}, "sfx": "slash_air", "ai": {"use": "defend"}}))
	L.append(S("a_whirl_gust", s, 5, "Порыв вихря", "Вращающийся ветер 3 м на 4 с тянет и ранит.", {"mana": 28.0, "cd": 9.0, "cast": 0.35, "dmg": 12.0,
		"fx": [{"c": "zone", "kind": "whirl", "at": "aim", "rng": 12.0, "r": 3.0, "dur": 4.0, "prm": {"pull": 2.5}}], "vis": {"shape": "whirl", "col": Color(0.85, 1.0, 1.0), "rune": "wind"}, "sfx": "slash_air", "ai": {"use": "aoe", "rng": 11.0}}))
	L.append(S("a_sky_step", s, 6, "Шаг небес", "Воздушный рывок на 7 м с белым следом и краткой неуязвимостью.", {"mana": 20.0, "cd": 5.0, "cast": 0.05, "dmg": 0.0,
		"fx": [{"c": "move", "kind": "dash", "dist": 7.0, "invuln": 0.25}], "vis": {"shape": "sky_step", "col": Color(0.9, 1.0, 1.0)}, "sfx": "slash_air", "ai": {"use": "escape"}}))
	L.append(S("a_cutting_cyclone", s, 7, "Режущий циклон", "Подвижный вихрь 6 с идёт вперёд и режет всех на пути.", {"mana": 45.0, "cd": 14.0, "cast": 0.5, "dmg": 16.0,
		"fx": [{"c": "zone", "kind": "whirl", "at": "front", "dist": 2.0, "r": 2.5, "dur": 6.0, "move": 5.0, "prm": {"pull": 1.0}}], "vis": {"shape": "cyclone", "col": Color(0.85, 1.0, 1.0)}, "sfx": "slash_air", "ai": {"use": "line", "rng": 14.0}}))
	L.append(S("a_storm_wings", s, 8, "Крылья шторма", "12 с: перезарядка рывка −40%, скорость +15%.", {"mana": 40.0, "cd": 30.0, "cast": 0.5, "dmg": 0.0, "sustain": true,
		"fx": [{"c": "buff", "to": "self", "status": "storm_wings", "dur": 12.0, "prm": {"mods": {"speed": 0.15}, "dodge_cd": 0.4}}], "vis": {"shape": "wings", "col": Color(0.85, 1.0, 1.0), "rune": "wind"}, "sfx": "slash_air", "ai": {"use": "buff"}}))
	L.append(S("a_wind_throne", s, 9, "Трон Ветров", "Область 6 м вокруг мага на 8 с: враги выталкиваются, снаряды отклоняются.", {"mana": 80.0, "cd": 35.0, "cast": 1.2, "dmg": 15.0,
		"fx": [{"c": "zone", "kind": "wind_throne", "at": "self", "r": 6.0, "dur": 8.0, "follow": true, "prm": {"push": 4.0, "deflect": true}}], "vis": {"shape": "wind_throne", "col": Color(0.9, 1.0, 1.0), "rune": "wind", "big": true}, "sfx": "slash_air", "ai": {"use": "defend", "rng": 6.0}}))
	L.append(S("a_sky_hurricane", s, 10, "Небесный Ураган", "КАТАКЛИЗМ. Огромный вихрь 11 м на 7 с затягивает врагов и бьёт; в конце — выброс наружу.", {"mana": 165.0, "cd": 120.0, "cast": 3.0, "dmg": 80.0,
		"fx": [{"c": "cataclysm", "kind": "hurricane", "at": "aim", "rng": 18.0, "r": 11.0, "dur": 7.0, "pulses": 6}], "vis": {"shape": "hurricane", "col": Color(0.85, 1.0, 1.0), "rune": "wind", "big": true}, "sfx": "slash_air", "ai": {"use": "cataclysm", "rng": 16.0}}))

static func _light(L: Array) -> void:
	var s := "light"
	L.append(S("g_firefly", s, 1, "Светлячок", "Магический огонёк 60 с освещает путь и выдаёт скрытых врагов в 6 м.", {"mana": 6.0, "cd": 20.0, "cast": 0.3, "dmg": 0.0,
		"fx": [{"c": "light_orb", "life": 60.0, "r": 6.0}], "vis": {"shape": "firefly", "col": Color(1.0, 0.95, 0.65)}, "sfx": "pickup", "ai": {"use": "never"}}))
	L.append(S("g_purify_beam", s, 2, "Луч очищения", "Световой луч по цели (×1,5 по нежити и тьме).", {"mana": 10.0, "cd": 1.5, "cast": 0.25, "dmg": 20.0,
		"fx": [{"c": "beam", "rng": 14.0, "w": 1.0, "single": true}], "vis": {"shape": "beam", "col": Color(1.0, 0.95, 0.7)}, "sfx": "heal", "ai": {"use": "ranged", "rng": 13.0}}))
	L.append(S("g_radiant_sign", s, 3, "Сияющий знак", "12 с: цель светится (+15% урона по ней), не может скрыться.", {"mana": 14.0, "cd": 10.0, "cast": 0.25, "dmg": 0.0,
		"fx": [{"c": "debuff", "to": "target", "rng": 18.0, "status": "radiant", "dur": 12.0, "prm": {"mods": {"taken_pct": 0.15}, "no_stealth": true}}], "vis": {"shape": "mark", "col": Color(1.0, 0.95, 0.6)}, "sfx": "pickup", "ai": {"use": "open", "rng": 16.0}}))
	L.append(S("g_dawn_shield", s, 4, "Щит рассвета", "Союзники в 6 м получают световой щит (30 + 2 × мастерство) на 6 с.", {"mana": 20.0, "cd": 16.0, "cast": 0.35, "dmg": 0.0,
		"fx": [{"c": "shield", "to": "allies", "r": 6.0, "amt": 30.0, "per_lvl": 2.0, "dur": 6.0}], "vis": {"shape": "light_dome", "col": Color(1.0, 0.95, 0.7), "rune": "sun"}, "sfx": "heal", "ai": {"use": "defend"}}))
	L.append(S("g_hallowed_ground", s, 5, "Освящённая область", "Зона 5 м на 10 с: союзники защищены от тьмы, тёмные эффекты снимаются, нежить горит.", {"mana": 32.0, "cd": 20.0, "cast": 0.5, "dmg": 10.0,
		"fx": [{"c": "zone", "kind": "hallowed", "at": "self", "r": 5.0, "dur": 10.0, "prm": {"hallowed": true}}], "vis": {"shape": "hallowed", "col": Color(1.0, 0.95, 0.7), "rune": "sun"}, "sfx": "heal", "ai": {"use": "defend", "rng": 5.0}}))
	L.append(S("g_light_spear", s, 6, "Копьё света", "Тяжёлый световой снаряд, пробивает двоих.", {"mana": 30.0, "cd": 6.0, "cast": 0.45, "dmg": 55.0,
		"fx": [{"c": "proj", "spd": 32.0, "rng": 26.0, "kind": "magic", "pierce": 2, "knock": 3.0}], "vis": {"shape": "light_spear", "col": Color(1.0, 0.95, 0.65)}, "sfx": "heal", "ai": {"use": "ranged", "rng": 24.0}}))
	L.append(S("g_sun_guard", s, 7, "Солнечная стража", "Световой страж на 15 с бьёт лучами и прикрывает мага.", {"mana": 50.0, "cd": 35.0, "cast": 0.8, "dmg": 0.0,
		"fx": [{"c": "summon", "id": "light_sentinel", "n": 1, "life": 15.0, "limit": 1, "at": "front"}], "vis": {"shape": "construct", "col": Color(1.0, 0.92, 0.6), "rune": "sun"}, "sfx": "heal", "ai": {"use": "summon"}}))
	L.append(S("g_seven_rays", s, 8, "Семь лучей", "Семь световых лучей по отмеченным или ближайшим целям в 18 м.", {"mana": 48.0, "cd": 14.0, "cast": 0.5, "dmg": 30.0,
		"fx": [{"c": "rays", "n": 7, "rng": 18.0}], "vis": {"shape": "rays", "col": Color(1.0, 0.95, 0.7), "rune": "sun"}, "sfx": "heal", "ai": {"use": "aoe", "rng": 17.0}}))
	L.append(S("g_dawn_verdict", s, 9, "Приговор рассвета", "Столб света на подготовленную область 3,5 м: огромный урон, ослепление.", {"mana": 80.0, "cd": 28.0, "cast": 1.4, "dmg": 160.0,
		"fx": [{"c": "blast", "at": "aim", "rng": 18.0, "r": 3.5, "delay": 1.0, "status": {"blind": 3.0}, "telegraph": true, "pillar": true}], "vis": {"shape": "pillar", "col": Color(1.0, 0.95, 0.7), "rune": "sun", "big": true}, "sfx": "explosion", "ai": {"use": "aoe", "rng": 16.0}}))
	L.append(S("g_heaven_verdict", s, 10, "Небесный Вердикт", "КАТАКЛИЗМ. Световая печать над ареной: восемь лучей по врагам и финальный центральный луч.", {"mana": 165.0, "cd": 120.0, "cast": 3.0, "dmg": 100.0,
		"fx": [{"c": "cataclysm", "kind": "verdict", "at": "aim", "rng": 20.0, "r": 12.0, "strikes": 8, "status": {"blind": 2.0}}], "vis": {"shape": "heaven_seal", "col": Color(1.0, 0.95, 0.7), "rune": "sun", "big": true}, "sfx": "explosion", "ai": {"use": "cataclysm", "rng": 18.0}}))
