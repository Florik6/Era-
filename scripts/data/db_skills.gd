class_name DBSkills
## Classes, weapon skill trees, magic schools and hybrid abilities.

const CLASSES := {
	"warrior": {"name": "Воин", "desc": "Высокая выносливость, ближний бой, блок и парирование.", "hp": 140, "mana": 40, "stamina": 120,
		"mastery": {"sword": 3, "heavy": 1}, "schools": [], "color": Color(0.75, 0.25, 0.2), "armor": 4.0},
	"archer": {"name": "Лучник", "desc": "Дальние атаки, точность, мобильность и особые стрелы.", "hp": 105, "mana": 50, "stamina": 110,
		"mastery": {"bow": 3, "dagger": 1}, "schools": [], "color": Color(0.3, 0.6, 0.25), "speed": 0.08},
	"rogue": {"name": "Разбойник", "desc": "Кинжалы, скрытность, быстрые удары и уклонения.", "hp": 100, "mana": 50, "stamina": 130,
		"mastery": {"dagger": 3, "bow": 1}, "schools": [], "color": Color(0.3, 0.28, 0.35), "crit": 0.08},
	"mage": {"name": "Маг", "desc": "Мана, заклинания, магические школы, щиты и призыв.", "hp": 90, "mana": 130, "stamina": 90,
		"mastery": {"staff": 3}, "schools": ["fire", "ice"], "color": Color(0.3, 0.35, 0.8), "spell": 0.15},
}

# Skill trees: each node {id, name, desc, type: active|passive, lvl: mastery level req, req: prerequisite id, cd, cost(stamina/mana)}
const TREES := {
	"sword": [
		{"id": "sw_quick", "name": "Быстрая атака", "desc": "Два стремительных удара подряд.", "type": "active", "lvl": 1, "req": "", "cd": 4.0, "stamina": 15},
		{"id": "sw_heavy", "name": "Сильная атака", "desc": "Мощный удар сверху: 260% урона, отбрасывание.", "type": "active", "lvl": 3, "req": "", "cd": 7.0, "stamina": 25},
		{"id": "sw_parry", "name": "Парирование", "desc": "Окно парирования увеличено, парирование оглушает.", "type": "passive", "lvl": 4, "req": ""},
		{"id": "sw_riposte", "name": "Контратака", "desc": "После парирования следующий удар наносит 300% урона.", "type": "passive", "lvl": 6, "req": "sw_parry"},
		{"id": "sw_combo", "name": "Комбинация клинка", "desc": "Четвёртый удар серии — вращающийся удар по площади.", "type": "passive", "lvl": 8, "req": "sw_quick"},
		{"id": "sw_whirl", "name": "Вихрь стали", "desc": "Уникальная техника: вращение, ранящее всех вокруг 3 раза.", "type": "active", "lvl": 12, "req": "sw_combo", "cd": 12.0, "stamina": 40},
	],
	"dagger": [
		{"id": "dg_flurry", "name": "Шквал ударов", "desc": "Пять быстрых уколов.", "type": "active", "lvl": 1, "req": "", "cd": 5.0, "stamina": 18},
		{"id": "dg_stealth", "name": "Скрытность", "desc": "Становитесь незаметны на 6 с, первая атака из тени ×2.5.", "type": "active", "lvl": 2, "req": "", "cd": 14.0, "stamina": 20},
		{"id": "dg_backstab", "name": "Удар в спину", "desc": "Атаки со спины наносят +80% урона.", "type": "passive", "lvl": 4, "req": ""},
		{"id": "dg_evasion", "name": "Уклонение", "desc": "Рывок восстанавливается на 40% быстрее и дольше неуязвим.", "type": "passive", "lvl": 6, "req": ""},
		{"id": "dg_combo", "name": "Кровавая серия", "desc": "Каждый удар серии усиливает следующий на 15%.", "type": "passive", "lvl": 8, "req": "dg_flurry"},
		{"id": "dg_shadowstep", "name": "Теневой шаг", "desc": "Мгновенно оказаться за спиной цели и ударить.", "type": "active", "lvl": 11, "req": "dg_backstab", "cd": 10.0, "stamina": 30},
	],
	"spear": [
		{"id": "sp_lunge", "name": "Выпад", "desc": "Рывок вперёд с пронзающим ударом.", "type": "active", "lvl": 1, "req": "", "cd": 5.0, "stamina": 18},
		{"id": "sp_sweep", "name": "Размах", "desc": "Удар древком по дуге 220°, сбивает с ног.", "type": "active", "lvl": 3, "req": "", "cd": 7.0, "stamina": 25},
		{"id": "sp_reach", "name": "Длинная рука", "desc": "+25% дальности атак.", "type": "passive", "lvl": 4, "req": ""},
		{"id": "sp_impale", "name": "Пронзание", "desc": "Удары пробивают до 2 целей.", "type": "passive", "lvl": 7, "req": "sp_lunge"},
		{"id": "sp_wall", "name": "Стена копий", "desc": "Серия из трёх выпадов с замедлением целей.", "type": "active", "lvl": 11, "req": "sp_impale", "cd": 11.0, "stamina": 35},
	],
	"heavy": [
		{"id": "hv_slam", "name": "Удар по земле", "desc": "Сокрушительный удар по площади 4 м.", "type": "active", "lvl": 1, "req": "", "cd": 6.0, "stamina": 25},
		{"id": "hv_break", "name": "Разрушение защиты", "desc": "Удары снижают броню цели на 30% (5 с).", "type": "passive", "lvl": 3, "req": ""},
		{"id": "hv_combo", "name": "Силовая серия", "desc": "Третий удар серии оглушает.", "type": "passive", "lvl": 5, "req": ""},
		{"id": "hv_unstoppable", "name": "Неудержимость", "desc": "8 с: иммунитет к оглушению и -40% входящего урона.", "type": "active", "lvl": 7, "req": "hv_break", "cd": 18.0, "stamina": 30},
		{"id": "hv_quake", "name": "Землетрясение", "desc": "Три волны ударов, расходящиеся вперёд.", "type": "active", "lvl": 12, "req": "hv_slam", "cd": 14.0, "stamina": 45},
	],
	"bow": [
		{"id": "bw_aimed", "name": "Прицельный выстрел", "desc": "Заряженный выстрел: 300% урона, высокая скорость стрелы.", "type": "active", "lvl": 1, "req": "", "cd": 5.0, "stamina": 15},
		{"id": "bw_rapid", "name": "Быстрая стрельба", "desc": "Три стрелы подряд.", "type": "active", "lvl": 3, "req": "", "cd": 6.0, "stamina": 20},
		{"id": "bw_pierce", "name": "Пробивающая стрела", "desc": "Стрелы пробивают 1 врага насквозь.", "type": "passive", "lvl": 4, "req": ""},
		{"id": "bw_eagle", "name": "Орлиный глаз", "desc": "+15% к криту и +20% дальности.", "type": "passive", "lvl": 6, "req": "bw_aimed"},
		{"id": "bw_special", "name": "Особые стрелы", "desc": "Залп из 5 стрел стихии вашей лучшей школы (или огненных).", "type": "active", "lvl": 9, "req": "bw_rapid", "cd": 10.0, "stamina": 30},
	],
	"firearm": [
		{"id": "fa_steady", "name": "Твёрдая рука", "desc": "-50% разброса.", "type": "passive", "lvl": 2, "req": ""},
		{"id": "fa_recoil", "name": "Контроль отдачи", "desc": "+20% скорострельности.", "type": "passive", "lvl": 4, "req": "fa_steady"},
		{"id": "fa_reload", "name": "Быстрая перезарядка", "desc": "-40% времени перезарядки.", "type": "passive", "lvl": 3, "req": ""},
		{"id": "fa_burst", "name": "Шквальный огонь", "desc": "Мгновенно выпустить 5 пуль веером.", "type": "active", "lvl": 1, "req": "", "cd": 7.0, "stamina": 15},
		{"id": "fa_special", "name": "Особый приём", "desc": "Разрывной заряд: взрыв по площади в точке попадания.", "type": "active", "lvl": 8, "req": "fa_burst", "cd": 12.0, "stamina": 25},
	],
	"staff": [
		{"id": "st_focus", "name": "Концентрация", "desc": "+20% силы магии.", "type": "passive", "lvl": 2, "req": ""},
		{"id": "st_shield", "name": "Магический щит", "desc": "Щит, поглощающий урон (40 + 2×мастерство).", "type": "active", "lvl": 1, "req": "", "cd": 14.0, "mana": 30},
		{"id": "st_flow", "name": "Поток маны", "desc": "+60% восстановления маны.", "type": "passive", "lvl": 4, "req": "st_focus"},
		{"id": "st_overload", "name": "Перегрузка", "desc": "Посох выпускает 6 зарядов веером.", "type": "active", "lvl": 7, "req": "", "cd": 9.0, "mana": 40},
	],
	"unarmed": [
		{"id": "ua_kick", "name": "Пинок", "desc": "Отталкивающий удар ногой.", "type": "active", "lvl": 1, "req": "", "cd": 4.0, "stamina": 10},
	],
}

# Magic schools — each spell {id, name, desc, lvl (school level req), mana, cd, kind}
const SCHOOLS := {
	"fire": {"name": "Огонь", "color": Color(1.0, 0.45, 0.1), "dtype": "fire", "spells": [
		{"id": "fireball", "name": "Огненный шар", "desc": "Шар взрывается по площади и поджигает.", "lvl": 1, "mana": 18, "cd": 1.6, "dmg": 26.0},
		{"id": "ignite", "name": "Поджигание", "desc": "Поджигает цель и деревянные объекты.", "lvl": 2, "mana": 14, "cd": 4.0, "dmg": 10.0},
		{"id": "firewall", "name": "Огненная стена", "desc": "Стена пламени перед магом на 6 с.", "lvl": 4, "mana": 35, "cd": 10.0, "dmg": 12.0},
		{"id": "meteor", "name": "Взрыв", "desc": "Через 1 с в точке прицела гремит взрыв огромной силы.", "lvl": 7, "mana": 55, "cd": 14.0, "dmg": 90.0},
	]},
	"ice": {"name": "Лёд", "color": Color(0.5, 0.85, 1.0), "dtype": "ice", "spells": [
		{"id": "frostbolt", "name": "Ледяная стрела", "desc": "Замедляет цель на 50%.", "lvl": 1, "mana": 15, "cd": 1.3, "dmg": 20.0},
		{"id": "freeze", "name": "Заморозка", "desc": "Замораживает врагов вокруг на 2 с. Замораживает воду.", "lvl": 3, "mana": 30, "cd": 9.0, "dmg": 14.0},
		{"id": "icewall", "name": "Ледяная преграда", "desc": "Стена льда, блокирующая путь и снаряды.", "lvl": 4, "mana": 30, "cd": 12.0, "dmg": 0.0},
		{"id": "blizzard", "name": "Ледяная буря", "desc": "Буря в точке прицела: урон и сильное замедление.", "lvl": 7, "mana": 50, "cd": 15.0, "dmg": 12.0},
	]},
	"lightning": {"name": "Молния", "color": Color(0.75, 0.8, 1.0), "dtype": "lightning", "spells": [
		{"id": "spark", "name": "Разряд", "desc": "Мгновенный разряд в ближайшего врага. ×2 по мокрым.", "lvl": 1, "mana": 14, "cd": 1.1, "dmg": 22.0},
		{"id": "chain", "name": "Цепная молния", "desc": "Перескакивает между 5 врагами.", "lvl": 3, "mana": 28, "cd": 5.0, "dmg": 24.0},
		{"id": "thunderclap", "name": "Громовой удар", "desc": "Оглушает всех врагов вокруг на 1,5 с.", "lvl": 5, "mana": 35, "cd": 10.0, "dmg": 20.0},
		{"id": "storm", "name": "Призыв бури", "desc": "8 ударов молнии по врагам вокруг.", "lvl": 8, "mana": 60, "cd": 18.0, "dmg": 30.0},
	]},
	"dark": {"name": "Тьма", "color": Color(0.6, 0.2, 0.8), "dtype": "dark", "spells": [
		{"id": "curse", "name": "Проклятие", "desc": "Цель наносит -30% урона и получает +25% урона 8 с.", "lvl": 1, "mana": 16, "cd": 5.0, "dmg": 6.0},
		{"id": "drain", "name": "Похищение жизни", "desc": "Выпивает здоровье цели и лечит мага.", "lvl": 2, "mana": 20, "cd": 3.0, "dmg": 24.0},
		{"id": "summon", "name": "Призыв нежити", "desc": "Призывает 2 скелетов-воинов на 25 с.", "lvl": 4, "mana": 45, "cd": 25.0, "dmg": 0.0},
		{"id": "nova", "name": "Теневая волна", "desc": "Волна тьмы ранит и пугает врагов.", "lvl": 7, "mana": 50, "cd": 13.0, "dmg": 45.0},
	]},
	"spacetime": {"name": "Пространство и время", "color": Color(0.4, 1.0, 0.85), "dtype": "time", "spells": [
		{"id": "blink", "name": "Телепортация", "desc": "Мгновенное перемещение на 9 м.", "lvl": 1, "mana": 16, "cd": 4.0, "dmg": 0.0},
		{"id": "timeslow", "name": "Замедление времени", "desc": "Зона, где враги и снаряды движутся на 70% медленнее.", "lvl": 3, "mana": 35, "cd": 14.0, "dmg": 0.0},
		{"id": "timetrap", "name": "Временная ловушка", "desc": "Ловушка: первый вошедший враг застывает на 4 с.", "lvl": 5, "mana": 25, "cd": 10.0, "dmg": 20.0},
		{"id": "riftdash", "name": "Пространственный рывок", "desc": "Рывок сквозь врагов, ранящий всех на пути.", "lvl": 7, "mana": 40, "cd": 8.0, "dmg": 50.0},
	]},
}

# Hybrid abilities unlock automatically when two specializations are developed.
const HYBRIDS := {
	"spellblade": {"name": "Клинок Чародея", "desc": "Удары оружием ближнего боя добавляют 35% урона стихией лучшей школы.", "a": "melee", "a_lvl": 5, "b": "school", "b_lvl": 3},
	"arcane_archer": {"name": "Магический Стрелок", "desc": "Стрелы и пули несут стихию лучшей школы (+30%).", "a": "ranged", "a_lvl": 5, "b": "school", "b_lvl": 3},
	"shadow_dancer": {"name": "Танцор Теней", "desc": "Рывок оставляет теневую копию, взрывающуюся тьмой.", "a": "dagger", "a_lvl": 5, "b": "dark|spacetime", "b_lvl": 2},
	"battlemage": {"name": "Боевой Маг", "desc": "Попадания восстанавливают 2 маны, заклинания — 4 выносливости.", "a": "heavy|sword|spear", "a_lvl": 4, "b": "school", "b_lvl": 4},
	"weapon_master": {"name": "Мастер Оружия", "desc": "+10% урона за каждую категорию оружия с мастерством 5+.", "a": "multi", "a_lvl": 5, "b": "", "b_lvl": 0},
}

const MELEE_CATS := ["sword", "dagger", "spear", "heavy", "unarmed"]
const RANGED_CATS := ["bow", "firearm"]

static func node(cat: String, id: String) -> Dictionary:
	for n in TREES.get(cat, []):
		if n.id == id:
			return n
	return {}

static func find_skill(id: String) -> Dictionary:
	for cat in TREES:
		for n in TREES[cat]:
			if n.id == id:
				var d: Dictionary = n.duplicate()
				d.cat = cat
				return d
	return {}

static func spell(id: String) -> Dictionary:
	for s in SCHOOLS:
		for sp in SCHOOLS[s].spells:
			if sp.id == id:
				var d: Dictionary = sp.duplicate()
				d.school = s
				return d
	return {}

static func is_spell(id: String) -> bool:
	return not spell(id).is_empty()

static func mastery_xp_needed(lvl: int) -> int:
	return int(40.0 * pow(lvl + 1, 1.45))

static func level_xp_needed(lvl: int) -> int:
	return int(80.0 * pow(lvl, 1.55))
