class_name DBBeasts
## «Beasts of the Ages»: 40 unique bosses (8 per era: dungeon bosses, a world
## boss and a titan) and 25 large dungeons (5 per era). Boss entries use the
## same format as DBActors.BOSSES (abilities + phases), so BossBrain runs
## them, plus: body plan for BeastRig, breakable parts (weak points), phase
## behaviour changes (speed, armour loss, arena events), resistances,
## weaknesses, loot table and a bestiary text. Shields use BossShield.

static var _bosses := {}
static var _dungeons := {}

## ability shorthand
static func A(t: String, o: Dictionary = {}) -> Dictionary:
	var d := {"type": t}
	for k in o:
		d[k] = o[k]
	return d

static func B(id: String, era: int, nm: String, cat: String, kind: String, hp: float, dmg: float, abil: Dictionary, phases: Array, desc: String, o: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "name": nm, "era": era, "cat": cat, "kind": kind, "hp": hp, "dmg": dmg, "lvl": 4 + era * 3 + (3 if cat == "titan" else (2 if cat == "world" else 0)),
		"abilities": abil, "phases": phases, "desc": desc, "rig": "beast", "plan": "giant", "f": {}, "scale": 2.0, "speed": 0.95,
		"dtype": "blunt", "res": {}, "loot": [], "beast": true}
	for k in o:
		d[k] = o[k]
	return d

static func bosses() -> Dictionary:
	if _bosses.is_empty():
		for e in _build_bosses():
			_bosses[e.id] = e
	return _bosses

static func boss(id: String) -> Dictionary:
	return bosses().get(id, {})

static func has_boss(id: String) -> bool:
	return bosses().has(id)

static func bosses_of_era(era: int) -> Array:
	return bosses().values().filter(func(e): return int(e.era) == era)

static func dungeons() -> Dictionary:
	if _dungeons.is_empty():
		for e in _build_dungeons():
			_dungeons[e.id] = e
	return _dungeons

static func dungeon(id: String) -> Dictionary:
	return dungeons().get(id, {})

static func dungeons_of_era(era: int) -> Array:
	var out: Array = dungeons().values().filter(func(e): return int(e.era) == era)
	out.sort_custom(func(a, b): return int(a.n) < int(b.n))
	return out

# ======================================================================= bosses
static func _build_bosses() -> Array:
	var L: Array = []
	# ------------------------------------------------------------- Middle Ages
	L.append(B("garmon", 0, "Гармон, Каменный Пожиратель", "dungeon", "cave", 2600, 30,
		{"smash": A("slam", {"dmg": 1.6, "radius": 5.0, "cd": 6.0}), "rock": A("rock_throw", {"dmg": 1.2, "count": 2, "cd": 5.0}),
		"ceiling": A("ceiling", {"dmg": 1.4, "count": 6, "cd": 14.0}), "armor": A("armor_up", {"cd": 22.0, "dur": 6.0}),
		"rush": A("charge", {"dmg": 1.3, "cd": 7.0}), "quake": A("quake", {"dmg": 1.2, "cd": 10.0})},
		[{"hp": 1.0, "use": ["smash", "rock", "armor"]}, {"hp": 0.5, "use": ["smash", "rock", "ceiling", "rush", "quake"], "msg": "Каменный панцирь трескается — Гармон в ярости!", "speed": 1.35, "drop_parts": true, "arena": "collapse"}],
		"Огромное существо из скал с тяжёлыми передними лапами и светящимися прожилками руды. Сбейте защитные пластины.",
		{"f": {"width": 1.1, "hunch": 0.5, "rocky": true, "veins": true, "arm": 1.25, "plates": 3, "plate_names": ["plate_l", "plate_r", "plate_back"]},
		"parts": {"plate_l": 320, "plate_r": 320, "plate_back": 360}, "body": Color(0.42, 0.38, 0.33), "accent": Color(0.3, 0.27, 0.24), "glow": Color(1.0, 0.65, 0.25),
		"scale": 2.3, "res": {"slash": 0.3, "pierce": 0.4, "blunt": -0.2}, "dungeon": "black_stone", "loot": [["stone_heart", 1.0], ["x_ore_mantle", 0.35]], "trophy": true}))
	L.append(B("spider_queen", 0, "Королева Глубинных Паучих", "dungeon", "nest", 2400, 26,
		{"web": A("web", {"cd": 8.0, "radius": 4.0}), "brood": A("summon", {"enemy": "deep_spider", "count": 3, "cd": 16.0}), "leap": A("leap", {"dmg": 1.4, "cd": 7.0}),
		"venom": A("poison_zone", {"dmg": 0.35, "count": 3, "cd": 10.0}), "bite": A("cleave", {"dmg": 1.3, "radius": 3.5, "arc": 90.0, "cd": 4.0})},
		[{"hp": 1.0, "use": ["bite", "web", "brood"]}, {"hp": 0.5, "use": ["bite", "leap", "venom", "brood", "web"], "msg": "Гнездо рушится — Королева в ярости!", "speed": 1.2, "arena": "nest_break"}],
		"Массивный паук с длинными конечностями и множеством глаз.",
		{"plan": "arach", "f": {"legs": 8, "abdomen": 1.6, "eyes": 8, "markings": true}, "body": Color(0.16, 0.14, 0.15), "glow": Color(0.9, 0.2, 0.2), "scale": 2.6, "dtype": "pierce", "dungeon": "thousand_eyes",
		"res": {"poison": 0.8, "fire": -0.4}, "loot": [["spider_silk", 1.0], ["venom_gland", 1.0]], "trophy": true}))
	L.append(B("arktor", 0, "Вечный Паладин Арктор", "dungeon", "knight", 2500, 30,
		{"combo": A("combo", {"dmg": 1.1, "hits": 3, "cd": 5.0}), "wave": A("beam", {"dmg": 1.2, "dtype": "light", "cd": 8.0}),
		"stance": A("parry_stance", {"cd": 12.0, "dur": 3.0}), "cleave": A("cleave", {"dmg": 1.5, "radius": 4.5, "arc": 140.0, "cd": 4.0})},
		[{"hp": 1.0, "use": ["cleave", "combo", "stance"]}, {"hp": 0.5, "use": ["combo", "wave", "stance", "cleave"], "msg": "Проклятая стойка Арктора!", "speed": 1.2}],
		"Огромный рыцарь в древних потемневших латах. Умеет парировать — бейте, когда он не в стойке.",
		{"rig": "humanoid", "weapon": "greatsword", "armor": "plate", "hat": "greathelm", "cloth": Color(0.15, 0.15, 0.18), "glow": Color(0.9, 0.85, 0.5), "scale": 1.9, "dtype": "slash",
		"dungeon": "forgotten_order", "res": {"slash": 0.3, "dark": 0.5, "light": -0.3}, "loot": [["cursed_steel", 1.0], ["x_oath_blade", 0.3]], "trophy": true}))
	L.append(B("bone_devourer", 0, "Пожиратель Костей", "dungeon", "necro", 2300, 26,
		{"spears": A("strikes", {"dmg": 1.1, "count": 6, "dtype": "dark", "cd": 7.0}), "servants": A("summon", {"enemy": "skeleton", "count": 3, "cd": 16.0}),
		"walls": A("bone_wall", {"cd": 14.0}), "sweep": A("spin", {"dmg": 1.2, "radius": 5.0, "cd": 8.0}), "nova": A("nova", {"dmg": 1.2, "radius": 6.0, "dtype": "dark", "cd": 10.0})},
		[{"hp": 1.0, "use": ["spears", "servants", "sweep"]}, {"hp": 0.5, "use": ["spears", "walls", "nova", "sweep", "servants"], "msg": "Пожиратель перестраивает конечности!", "form": 1.15}],
		"Неправильная костяная конструкция с несколькими подвижными конечностями.",
		{"plan": "arach", "f": {"legs": 6, "abdomen": 1.4, "eyes": 3, "spikes": 4}, "body": Color(0.85, 0.82, 0.72), "glow": Color(0.4, 1.0, 0.5), "scale": 2.4, "dtype": "dark",
		"dungeon": "forgotten_order", "res": {"dark": 0.8, "pierce": 0.4, "light": -0.5, "blunt": -0.3}, "loot": [["bone_dust", 1.0]], "trophy": true}))
	L.append(B("blight_god", 0, "Лесной Бог Скверны", "dungeon", "forest", 2700, 28,
		{"roots": A("roots", {"dmg": 1.0, "count": 4, "cd": 7.0}), "grab": A("slowzone", {"cd": 12.0}), "kin": A("summon", {"enemy": "forest_spirit", "count": 2, "cd": 18.0}),
		"wave": A("nova", {"dmg": 1.3, "radius": 7.0, "dtype": "poison", "cd": 10.0}), "smash": A("slam", {"dmg": 1.4, "radius": 4.5, "cd": 6.0})},
		[{"hp": 1.0, "use": ["roots", "smash", "kin"]}, {"hp": 0.5, "use": ["roots", "grab", "wave", "smash", "kin"], "msg": "Скверна разливается по лесу!", "speed": 1.15}],
		"Гигантский древесный страж с рогами из ветвей. Уничтожьте светящиеся наросты.",
		{"plan": "tree", "f": {"antlers": 6, "growths": 3}, "parts": {"growth0": 260, "growth1": 260, "growth2": 260}, "body": Color(0.3, 0.24, 0.16), "accent": Color(0.4, 0.2, 0.45), "glow": Color(0.8, 0.3, 1.0),
		"scale": 2.4, "dtype": "poison", "dungeon": "root_crypt", "res": {"pierce": 0.4, "fire": -0.5}, "loot": [["living_wood", 1.0]], "trophy": true}))
	L.append(B("rune_archmage", 0, "Архимаг Забытых Рун", "dungeon", "mage", 2200, 26,
		{"seals": A("strikes", {"dmg": 1.1, "count": 5, "dtype": "fire", "cd": 7.0}), "walls": A("bone_wall", {"cd": 14.0, "stone": true}), "blink": A("blink", {"cd": 6.0}),
		"doubles": A("decoys", {"count": 2, "cd": 16.0}), "fan": A("fan", {"dmg": 0.9, "count": 5, "dtype": "fire", "cd": 3.5}),
		"ward": A("shield", {"charge": 1.5, "dur": 6.0, "cd_after": 20.0, "pool": 0.12, "counter": ["ice", "earth"], "cd": 4.0})},
		[{"hp": 1.0, "use": ["fan", "blink", "seals", "ward"]}, {"hp": 0.5, "use": ["fan", "seals", "walls", "doubles", "blink", "ward"], "msg": "Архимаг изучает ваши приёмы!", "adapt": true}],
		"Древний маг с парящими руническими кольцами. Подстраивается под ваши любимые заклинания — но не знает всего.",
		{"rig": "humanoid", "weapon": "staff_oak", "armor": "robe", "hat": "hood", "cloth": Color(0.2, 0.15, 0.35), "glow": Color(0.5, 0.7, 1.0), "scale": 1.6, "dtype": "fire", "caster": true,
		"dungeon": "first_keeper", "loot": [["rune_stone", 1.0], ["arcane_dust", 1.0]], "trophy": true}))
	L.append(B("crimson_dragon", 0, "Дракон Багровой Бездны", "world", "dragon", 4200, 36,
		{"breath": A("breath", {"dmg": 0.45, "cd": 8.0}), "tail": A("tail", {"dmg": 1.4, "cd": 6.0}), "dive": A("dive", {"dmg": 1.6, "cd": 12.0}),
		"rocks": A("ceiling", {"dmg": 1.3, "count": 8, "cd": 14.0, "sky": true}), "inferno": A("nova", {"dmg": 1.8, "radius": 9.0, "dtype": "fire", "cd": 20.0})},
		[{"hp": 1.0, "use": ["breath", "tail", "dive"]}, {"hp": 0.6, "use": ["breath", "tail", "dive", "rocks"], "msg": "Дракон взмывает в небо!", "speed": 1.15},
		{"hp": 0.3, "use": ["breath", "inferno", "dive", "rocks", "tail"], "msg": "Бездна пылает — ультимативное пламя!", "enrage": true}],
		"Гигантский дракон с чёрной чешуёй, раскалёнными трещинами и повреждёнными крыльями. Меняет логово.",
		{"plan": "drake", "f": {"len": 1.6, "height": 0.8, "girth": 0.35, "neck": 0.8, "tail": 1.3, "horns": 4, "spikes": 7, "eyes": 2}, "body": Color(0.12, 0.1, 0.1), "accent": Color(0.3, 0.08, 0.06), "glow": Color(1.0, 0.35, 0.1),
		"scale": 3.2, "dtype": "fire", "res": {"fire": 0.8, "ice": -0.3}, "loot": [["drake_scale", 1.0], ["x_dragon_heart", 0.25]], "trophy": true}))
	L.append(B("mountain_keeper", 0, "Первый Хранитель Гор", "titan", "titan", 6000, 40,
		{"plates": A("platforms", {"count": 6, "cd": 16.0}), "wave": A("quake", {"dmg": 1.4, "cd": 9.0}), "smash": A("slam", {"dmg": 1.8, "radius": 6.0, "cd": 6.0}),
		"guards": A("summon", {"enemy": "rune_guardian", "count": 2, "cd": 25.0}), "great_quake": A("cataclysm_quake", {"dmg": 2.0, "cd": 30.0})},
		[{"hp": 1.0, "use": ["smash", "wave", "plates"]}, {"hp": 0.66, "use": ["smash", "wave", "guards", "plates"], "msg": "Хранитель пробуждает стражей!", "drop_parts": true},
		{"hp": 0.33, "use": ["great_quake", "smash", "wave", "guards", "plates"], "msg": "ВЕЛИКОЕ ЗЕМЛЕТРЯСЕНИЕ!", "enrage": true, "speed": 1.2}],
		"Колоссальный каменный исполин с рунами по всему телу. Три фазы; уничтожайте руны-сердца.",
		{"f": {"width": 1.3, "hunch": 0.2, "rocky": true, "runes": true, "crystals": 4, "plates": 3, "plate_names": ["rune_l", "rune_r", "rune_back"], "arm": 1.3},
		"parts": {"rune_l": 500, "rune_r": 500, "rune_back": 600}, "body": Color(0.5, 0.48, 0.44), "glow": Color(0.4, 0.7, 1.0), "scale": 3.4, "dungeon": "first_keeper", "speed": 0.8,
		"res": {"slash": 0.4, "pierce": 0.5}, "loot": [["rune_stone", 1.0], ["x_mountain_crown", 0.3]], "trophy": true}))
	# ------------------------------------------------------------- Renaissance
	L.append(B("alch_colossus", 1, "Алхимический Колосс", "dungeon", "construct", 2800, 30,
		{"orbs": A("missiles", {"dmg": 1.0, "count": 4, "dtype": "poison", "cd": 7.0}), "vapor": A("poison_zone", {"dmg": 0.3, "count": 3, "cd": 11.0}),
		"arms": A("slam", {"dmg": 1.5, "radius": 4.5, "cd": 6.0}), "regen": A("regen", {"cd": 20.0, "dur": 5.0})},
		[{"hp": 1.0, "use": ["arms", "orbs", "vapor"]}, {"hp": 0.5, "use": ["arms", "orbs", "vapor", "regen"], "msg": "Колосс впрыскивает себе эликсир!", "speed": 1.15}],
		"Искусственное существо из металла, стекла и жидкостей. Прервите регенерацию.",
		{"f": {"width": 1.0, "hunch": 0.1, "gears": 2, "crystals": 5, "plates": 2, "plate_names": ["flask_l", "flask_r"]}, "parts": {"flask_l": 350, "flask_r": 350}, "body": Color(0.55, 0.5, 0.42), "glow": Color(0.5, 1.0, 0.4),
		"metal": true, "scale": 2.4, "dungeon": "alch_catacombs", "res": {"poison": 0.8, "lightning": -0.3}, "loot": [["mutagen", 1.0]], "trophy": true}))
	L.append(B("black_admiral", 1, "Адмирал Чёрных Парусов", "dungeon", "duelist", 2300, 28,
		{"combo": A("combo", {"dmg": 1.0, "hits": 4, "cd": 5.0}), "pistol": A("fan", {"dmg": 0.8, "count": 3, "dtype": "pierce", "cd": 4.0}),
		"crew": A("summon", {"enemy": "ghost_sailor", "count": 2, "cd": 18.0}), "blink": A("blink", {"cd": 7.0})},
		[{"hp": 1.0, "use": ["combo", "pistol", "blink"]}, {"hp": 0.5, "use": ["combo", "pistol", "crew", "blink"], "msg": "«Все наверх!» — Адмирал зовёт команду!", "speed": 1.2}],
		"Легендарный пиратский командир: рапира, пистоли и команда призраков.",
		{"rig": "humanoid", "weapon": "rapier", "armor": "leather", "hat": "hood", "cloth": Color(0.1, 0.1, 0.12), "scale": 1.5, "dtype": "slash", "dungeon": "sunken_fortress", "loot": [["sea_pearl", 1.0]], "trophy": true}))
	L.append(B("glass_archon", 1, "Стеклянный Архонт", "dungeon", "mage", 2300, 28,
		{"shards": A("fan", {"dmg": 0.9, "count": 7, "dtype": "pierce", "cd": 3.5}), "mirror": A("shield", {"charge": 1.2, "dur": 5.5, "cd_after": 18.0, "pool": 0.1, "counter": ["blunt", "earth"], "cd": 4.0}),
		"copies": A("decoys", {"count": 3, "cd": 15.0}), "cut": A("beam", {"dmg": 1.3, "dtype": "light", "cd": 7.0})},
		[{"hp": 1.0, "use": ["shards", "mirror", "cut"]}, {"hp": 0.5, "use": ["shards", "copies", "cut", "mirror"], "msg": "Архонт раскалывается на отражения!"}],
		"Существо из прозрачных кристаллов. Дробящее оружие и земля раскалывают его щит.",
		{"plan": "orb", "f": {"core_r": 0.5, "shards": 10, "ring": true, "hover": 2.0}, "body": Color(0.8, 0.9, 1.0), "glow": Color(0.7, 0.9, 1.0), "scale": 2.0, "dtype": "pierce", "caster": true,
		"dungeon": "astral_observatory", "res": {"pierce": 0.5, "blunt": -0.4}, "loot": [["crystal_shard", 1.0]], "trophy": true}))
	L.append(B("clock_executioner", 1, "Часовой Палач", "dungeon", "construct", 2600, 30,
		{"swing": A("cleave", {"dmg": 1.5, "radius": 5.0, "arc": 160.0, "cd": 4.5}), "spin": A("spin", {"dmg": 1.1, "radius": 5.0, "cd": 8.0}),
		"overclock": A("haste", {"cd": 16.0, "dur": 5.0}), "charge": A("charge", {"dmg": 1.3, "cd": 7.0})},
		[{"hp": 1.0, "use": ["swing", "charge"]}, {"hp": 0.5, "use": ["swing", "spin", "overclock", "charge"], "msg": "Шестерни разгоняются!", "speed": 1.3}],
		"Механический палач с вращающимися шестернями.",
		{"f": {"width": 0.9, "hunch": 0.0, "gears": 4, "plates": 2, "plate_names": ["gear_l", "gear_r"]}, "parts": {"gear_l": 380, "gear_r": 380}, "body": Color(0.55, 0.45, 0.25), "metal": true, "glow": Color(1.0, 0.8, 0.3),
		"scale": 2.2, "dtype": "slash", "dungeon": "clock_tower", "res": {"lightning": -0.4}, "loot": [["gears", 1.0]], "trophy": true}))
	L.append(B("carnival_witch", 1, "Ведьма Чёрного Карнавала", "dungeon", "mage", 2100, 26,
		{"illusions": A("decoys", {"count": 3, "cd": 12.0}), "traps": A("mines", {"dmg": 1.2, "count": 5, "dtype": "dark", "cd": 12.0}), "masks": A("summon", {"enemy": "mask_parasite", "count": 3, "cd": 16.0}),
		"feint": A("blink", {"cd": 5.0}), "curse": A("strikes", {"dmg": 1.0, "count": 4, "dtype": "dark", "cd": 7.0})},
		[{"hp": 1.0, "use": ["curse", "feint", "illusions"]}, {"hp": 0.5, "use": ["curse", "traps", "masks", "illusions", "feint"], "msg": "Маски падают — представление продолжается!"}],
		"Театральная ведьма: отличите настоящую от иллюзий.",
		{"rig": "humanoid", "weapon": "staff_oak", "armor": "robe", "hat": "hood", "cloth": Color(0.4, 0.05, 0.25), "glow": Color(1.0, 0.4, 0.8), "scale": 1.4, "dtype": "dark", "caster": true,
		"dungeon": "carnival_depths", "loot": [["arcane_dust", 1.0]], "trophy": true}))
	L.append(B("ghost_captain", 1, "Призрачный Капитан", "dungeon", "undead", 2400, 28,
		{"blades": A("fan", {"dmg": 1.0, "count": 4, "dtype": "dark", "cd": 4.0}), "fog": A("nova", {"dmg": 1.0, "radius": 7.0, "dtype": "ice", "cd": 9.0}),
		"ethereal": A("ethereal", {"cd": 15.0, "dur": 3.0}), "spirits": A("summon", {"enemy": "ghost_sailor", "count": 3, "cd": 18.0})},
		[{"hp": 1.0, "use": ["blades", "fog", "ethereal"]}, {"hp": 0.5, "use": ["blades", "fog", "spirits", "ethereal"], "msg": "Море отдаёт мёртвых!", "speed": 1.15}],
		"Проклятый мореплаватель в разорванной форме. Пока бесплотен — бейте магией света.",
		{"rig": "humanoid", "weapon": "sword_steel", "armor": "leather", "hat": "hood", "cloth": Color(0.15, 0.3, 0.35), "glow": Color(0.5, 0.9, 1.0), "scale": 1.6, "dtype": "dark",
		"dungeon": "sunken_fortress", "res": {"slash": 0.3, "light": -0.5}, "loot": [["ectoplasm", 1.0]], "trophy": true}))
	L.append(B("flame_inquisitor", 1, "Великий Инквизитор Пламени", "dungeon", "knight", 2500, 30,
		{"sword": A("combo", {"dmg": 1.1, "hits": 3, "dtype": "fire", "cd": 5.0}), "seals": A("shield", {"charge": 1.6, "dur": 6.0, "cd_after": 22.0, "pool": 0.12, "counter": ["ice", "dark"], "cd": 4.0}),
		"parry": A("parry_stance", {"cd": 12.0, "dur": 2.5}), "judgment": A("strikes", {"dmg": 1.3, "count": 6, "dtype": "fire", "cd": 9.0})},
		[{"hp": 1.0, "use": ["sword", "parry", "seals"]}, {"hp": 0.5, "use": ["sword", "judgment", "parry", "seals"], "msg": "Огненная кара!", "speed": 1.1}],
		"Человек в церемониальных доспехах с огненным мечом. Говорит с теми, кого уважает.",
		{"rig": "humanoid", "weapon": "greatsword", "armor": "plate", "hat": "greathelm", "cloth": Color(0.5, 0.1, 0.05), "glow": Color(1.0, 0.5, 0.15), "scale": 1.6, "dtype": "fire",
		"res": {"fire": 0.6}, "loot": [["fire_gland", 1.0]], "trophy": true, "talks": true}))
	L.append(B("astral_mechanism", 1, "Астральный Механизм", "titan", "titan", 6200, 40,
		{"beam": A("beam", {"dmg": 1.4, "dtype": "lightning", "cd": 6.0}), "rings": A("spin", {"dmg": 1.2, "radius": 7.0, "cd": 9.0}), "pulse": A("nova", {"dmg": 1.4, "radius": 8.0, "dtype": "time", "cd": 11.0}),
		"turrets": A("summon", {"enemy": "clock_spider", "count": 2, "cd": 22.0}), "core": A("shield", {"charge": 1.8, "dur": 7.0, "cd_after": 24.0, "pool": 0.1, "counter": ["lightning"], "cd": 4.0})},
		[{"hp": 1.0, "use": ["beam", "rings", "core"]}, {"hp": 0.66, "use": ["beam", "rings", "turrets", "core"], "msg": "Внешний корпус разрушен!", "drop_parts": true},
		{"hp": 0.33, "use": ["beam", "pulse", "rings", "turrets"], "msg": "Энергетическое ядро пробуждается!", "enrage": true}],
		"Колоссальная алхимическая машина, соединившая магию и механику.",
		{"plan": "orb", "f": {"core_r": 0.7, "shards": 12, "gears": true, "ring": true, "hover": 2.5}, "body": Color(0.6, 0.5, 0.3), "metal": true, "glow": Color(0.6, 0.8, 1.0), "scale": 2.8, "dtype": "lightning",
		"dungeon": "astral_observatory", "loot": [["arcane_dust", 1.0], ["x_astral_lens", 0.3]], "trophy": true}))
	# ------------------------------------------------------------- Industrial
	L.append(B("rust_king", 2, "Король Ржавчины", "dungeon", "construct", 3000, 32,
		{"smash": A("slam", {"dmg": 1.5, "radius": 5.0, "cd": 6.0}), "debris": A("rock_throw", {"dmg": 1.0, "count": 3, "cd": 5.0}), "gears": A("spin", {"dmg": 1.1, "radius": 5.0, "cd": 8.0}),
		"repair": A("regen", {"cd": 18.0, "dur": 4.0})},
		[{"hp": 1.0, "use": ["smash", "debris", "repair"]}, {"hp": 0.5, "use": ["smash", "debris", "gears", "repair"], "msg": "Король чинит себя на ходу!", "speed": 1.2}],
		"Механический монстр из промышленных обломков. Прерывайте ремонт.",
		{"f": {"width": 1.2, "hunch": 0.35, "gears": 4, "plates": 3, "plate_names": ["plate_l", "plate_r", "plate_back"]}, "parts": {"plate_l": 380, "plate_r": 380, "plate_back": 420}, "body": Color(0.45, 0.3, 0.2),
		"metal": true, "glow": Color(1.0, 0.5, 0.2), "scale": 2.4, "dungeon": "rust_mine", "res": {"lightning": -0.4}, "loot": [["scrap_alloy", 1.0]], "trophy": true}))
	L.append(B("electric_phantom", 2, "Электрический Призрак", "dungeon", "energy", 2400, 28,
		{"chain": A("chain", {"dmg": 1.0, "cd": 5.0}), "port": A("blink", {"cd": 5.0}), "traps": A("mines", {"dmg": 1.1, "count": 5, "dtype": "lightning", "cd": 12.0}),
		"overload": A("nova", {"dmg": 1.4, "radius": 7.0, "dtype": "lightning", "cd": 10.0})},
		[{"hp": 1.0, "use": ["chain", "port", "traps"]}, {"hp": 0.5, "use": ["chain", "port", "traps", "overload"], "msg": "Перегрузка сети!", "speed": 1.2}],
		"Аномальное энергетическое существо.",
		{"plan": "orb", "f": {"core_r": 0.5, "shards": 0, "ring": true, "hover": 1.8}, "body": Color(0.5, 0.7, 1.0), "glow": Color(0.6, 0.85, 1.0), "scale": 2.0, "dtype": "lightning", "caster": true,
		"dungeon": "electric_catacombs", "res": {"lightning": 0.9, "slash": 0.4}, "loot": [["power_cell", 1.0]], "trophy": true}))
	L.append(B("iron_miner", 2, "Железный Шахтёр", "dungeon", "construct", 2900, 30,
		{"drill": A("charge", {"dmg": 1.5, "cd": 7.0}), "burrow": A("burrow", {"dmg": 1.4, "cd": 12.0}), "cave_in": A("ceiling", {"dmg": 1.3, "count": 6, "cd": 14.0}),
		"helpers": A("summon", {"enemy": "drill_beetle", "count": 2, "cd": 18.0})},
		[{"hp": 1.0, "use": ["drill", "cave_in"]}, {"hp": 0.5, "use": ["drill", "burrow", "cave_in", "helpers"], "msg": "Шахтёр уходит под землю!"}],
		"Гигантский подземный буровой автоматон.",
		{"plan": "construct", "f": {"legs": 6, "len": 1.4, "drill": true, "gears": 2, "chimney": true}, "body": Color(0.4, 0.38, 0.35), "metal": true, "glow": Color(1.0, 0.6, 0.2), "scale": 2.4,
		"dtype": "pierce", "dungeon": "drill_complex", "loot": [["scrap_alloy", 1.0], ["power_cell", 0.6]], "trophy": true}))
	L.append(B("steel_general", 2, "Генерал Стального Корпуса", "dungeon", "commander", 2500, 30,
		{"rifle": A("volley", {"dmg": 1.0, "count": 5, "dtype": "pierce", "cd": 6.0}), "squad": A("summon", {"enemy": "rust_automaton", "count": 3, "cd": 18.0}),
		"formation": A("armor_up", {"cd": 16.0, "dur": 5.0}), "mortar": A("strikes", {"dmg": 1.2, "count": 5, "dtype": "fire", "cd": 9.0})},
		[{"hp": 1.0, "use": ["rifle", "squad", "formation"]}, {"hp": 0.5, "use": ["rifle", "mortar", "squad", "formation"], "msg": "Генерал вызывает артиллерию!"}],
		"Командир механизированного отряда.",
		{"rig": "humanoid", "weapon": "rifle_lever", "armor": "plate", "hat": "greathelm", "cloth": Color(0.25, 0.28, 0.3), "scale": 1.5, "dtype": "pierce", "loot": [["power_cell", 1.0]], "trophy": true}))
	L.append(B("steam_leviathan", 2, "Паровой Левиафан", "dungeon", "construct", 3200, 32,
		{"steam": A("poison_zone", {"dmg": 0.35, "count": 4, "dtype": "fire", "cd": 10.0}), "limbs": A("slam", {"dmg": 1.6, "radius": 5.0, "cd": 6.0}),
		"overheat": A("nova", {"dmg": 1.5, "radius": 7.0, "dtype": "fire", "cd": 12.0}), "plates": A("armor_up", {"cd": 18.0, "dur": 5.0})},
		[{"hp": 1.0, "use": ["limbs", "steam", "plates"]}, {"hp": 0.5, "use": ["limbs", "steam", "overheat", "plates"], "msg": "Левиафан перегревается!", "speed": 1.2}],
		"Многосекционная машина-зверь.",
		{"plan": "worm", "f": {"segments": 12, "girth": 0.5, "spikes": 1, "eyes": 2}, "body": Color(0.4, 0.36, 0.32), "accent": Color(0.6, 0.45, 0.25), "metal": true, "glow": Color(1.0, 0.5, 0.2), "scale": 2.2,
		"dtype": "fire", "res": {"fire": 0.6, "lightning": -0.3}, "loot": [["coal_core", 1.0]], "trophy": true}))
	L.append(B("machine_architect", 2, "Архитектор Машин", "dungeon", "engineer", 2400, 28,
		{"traps": A("mines", {"dmg": 1.2, "count": 6, "dtype": "fire", "cd": 12.0}), "turrets": A("summon", {"enemy": "scout_automaton", "count": 2, "cd": 16.0}),
		"barrier": A("shield", {"charge": 1.6, "dur": 6.0, "cd_after": 20.0, "pool": 0.12, "counter": ["lightning"], "cd": 4.0}), "zap": A("chain", {"dmg": 1.0, "cd": 6.0})},
		[{"hp": 1.0, "use": ["zap", "traps", "barrier"]}, {"hp": 0.5, "use": ["zap", "traps", "turrets", "barrier"], "msg": "Арена перенастроена!"}],
		"Инженер в боевом экзокостюме.",
		{"rig": "humanoid", "weapon": "tesla_gun", "armor": "robot", "cloth": Color(0.35, 0.3, 0.2), "glow": Color(1.0, 0.7, 0.3), "scale": 1.5, "dtype": "lightning", "caster": true, "loot": [["gears", 1.0]], "trophy": true}))
	L.append(B("ash_titan", 2, "Пепельный Титан Завода", "dungeon", "construct", 3300, 34,
		{"strike": A("slam", {"dmg": 1.6, "radius": 5.0, "dtype": "fire", "cd": 6.0}), "slag": A("poison_zone", {"dmg": 0.4, "count": 4, "dtype": "fire", "cd": 10.0}),
		"breath": A("breath", {"dmg": 0.4, "cd": 9.0}), "armor": A("armor_up", {"cd": 18.0, "dur": 6.0})},
		[{"hp": 1.0, "use": ["strike", "slag", "armor"]}, {"hp": 0.5, "use": ["strike", "slag", "breath", "armor"], "msg": "Титан раскаляется добела!", "speed": 1.15}],
		"Создание, пробудившееся в металлургическом комплексе.",
		{"f": {"width": 1.2, "hunch": 0.2, "rocky": true, "veins": true}, "body": Color(0.25, 0.22, 0.2), "glow": Color(1.0, 0.45, 0.1), "scale": 2.6, "dtype": "fire", "dungeon": "thousand_pipes",
		"res": {"fire": 0.8, "ice": -0.4}, "loot": [["coal_core", 1.0]], "trophy": true}))
	L.append(B("megafactory_heart", 2, "Сердце Мегазавода", "titan", "titan", 6500, 42,
		{"pistons": A("strikes", {"dmg": 1.3, "count": 7, "dtype": "blunt", "cd": 7.0}), "conveyor": A("platforms", {"count": 5, "cd": 15.0}), "sparks": A("chain", {"dmg": 1.1, "cd": 6.0}),
		"drones": A("summon", {"enemy": "rotor_hunter", "count": 2, "cd": 20.0}), "core": A("nova", {"dmg": 1.6, "radius": 9.0, "dtype": "fire", "cd": 12.0})},
		[{"hp": 1.0, "use": ["pistons", "sparks", "conveyor"]}, {"hp": 0.66, "use": ["pistons", "sparks", "drones", "conveyor"], "msg": "Энергетические узлы разрушены!", "drop_parts": true},
		{"hp": 0.33, "use": ["pistons", "core", "sparks", "drones"], "msg": "Центральное ядро открыто!", "enrage": true}],
		"Колоссальный живой промышленный механизм.",
		{"plan": "construct", "f": {"legs": 8, "len": 2.0, "gears": 4, "chimney": true}, "body": Color(0.35, 0.32, 0.3), "metal": true, "glow": Color(1.0, 0.5, 0.2), "scale": 2.8, "dtype": "fire",
		"dungeon": "megafactory", "loot": [["power_cell", 1.0], ["x_factory_core", 0.3]], "trophy": true}))
	# ------------------------------------------------------------- Modern
	L.append(B("project_chimera", 3, "Проект «Химера»", "dungeon", "beast", 3000, 32,
		{"leap": A("leap", {"dmg": 1.4, "cd": 6.0}), "stance": A("haste", {"cd": 14.0, "dur": 4.0}), "regen": A("regen", {"cd": 18.0, "dur": 4.0}),
		"spores": A("poison_zone", {"dmg": 0.35, "count": 3, "cd": 10.0}), "claws": A("cleave", {"dmg": 1.4, "radius": 4.0, "arc": 120.0, "cd": 4.0})},
		[{"hp": 1.0, "use": ["claws", "leap", "spores"]}, {"hp": 0.5, "use": ["claws", "leap", "spores", "regen", "stance"], "msg": "Химера меняет стойку!", "speed": 1.2}],
		"Экспериментальный мутировавший организм.",
		{"plan": "drake", "f": {"len": 1.4, "height": 0.75, "girth": 0.3, "neck": 0.3, "tail": 1.0, "spikes": 5, "horns": 2}, "body": Color(0.55, 0.45, 0.42), "glow": Color(0.6, 1.0, 0.4), "scale": 2.4,
		"dungeon": "chimera_lab", "loot": [["mutagen", 1.0]], "trophy": true}))
	L.append(B("commander_phantom", 3, "Командир «Фантом»", "dungeon", "commander", 2400, 30,
		{"burst": A("volley", {"dmg": 1.0, "count": 6, "dtype": "pierce", "cd": 5.0}), "cloak": A("ethereal", {"cd": 14.0, "dur": 3.0}), "pulse": A("nova", {"dmg": 1.2, "radius": 6.0, "dtype": "energy", "cd": 9.0}),
		"squad": A("summon", {"enemy": "artificial_soldier", "count": 2, "cd": 18.0}), "dodge": A("blink", {"cd": 5.0})},
		[{"hp": 1.0, "use": ["burst", "dodge", "cloak"]}, {"hp": 0.5, "use": ["burst", "pulse", "squad", "cloak", "dodge"], "msg": "Фантом вызывает группу!"}],
		"Опытный боец в высокотехнологичном снаряжении.",
		{"rig": "humanoid", "weapon": "carbine", "armor": "vest", "hat": "visor", "cloth": Color(0.1, 0.1, 0.12), "scale": 1.4, "dtype": "pierce", "dungeon": "phantom_complex", "loot": [["circuits", 1.0]], "trophy": true}))
	L.append(B("tunnel_giant", 3, "Подземный Исполин", "dungeon", "beast", 3300, 34,
		{"smash": A("slam", {"dmg": 1.6, "radius": 5.0, "cd": 6.0}), "ram": A("charge", {"dmg": 1.5, "cd": 7.0}), "wave": A("quake", {"dmg": 1.2, "cd": 9.0}), "hide": A("burrow", {"dmg": 1.3, "cd": 14.0})},
		[{"hp": 1.0, "use": ["smash", "ram"]}, {"hp": 0.5, "use": ["smash", "ram", "wave", "hide"], "msg": "Исполин уходит в тоннели!", "speed": 1.15}],
		"Мутировавшее существо заброшенной инфраструктуры.",
		{"f": {"width": 1.2, "hunch": 0.55, "veins": true, "arm": 1.3, "plates": 2, "plate_names": ["plate_l", "plate_r"]}, "parts": {"plate_l": 380, "plate_r": 380}, "body": Color(0.55, 0.48, 0.42), "glow": Color(0.6, 1.0, 0.4), "scale": 2.6, "loot": [["mutagen", 1.0]], "trophy": true}))
	L.append(B("argus", 3, "ИИ «АРГУС»", "dungeon", "ai", 2800, 30,
		{"laser": A("beam", {"dmg": 1.3, "dtype": "energy", "cd": 6.0}), "drones": A("summon", {"enemy": "battle_drone", "count": 3, "cd": 16.0}),
		"shield": A("shield", {"charge": 1.5, "dur": 6.5, "cd_after": 22.0, "pool": 0.12, "counter": ["lightning", "time"], "cd": 4.0}), "missiles": A("missiles", {"dmg": 1.0, "count": 6, "dtype": "fire", "cd": 8.0})},
		[{"hp": 1.0, "use": ["laser", "drones", "shield"]}, {"hp": 0.5, "use": ["laser", "missiles", "drones", "shield"], "msg": "АРГУС переключает режим атаки!", "adapt": true}],
		"Самостоятельный машинный разум с боевыми модулями.",
		{"plan": "orb", "f": {"core_r": 0.6, "shards": 6, "gears": true, "ring": true, "hover": 2.4}, "body": Color(0.3, 0.32, 0.36), "metal": true, "glow": Color(1.0, 0.2, 0.2), "scale": 2.2, "dtype": "energy",
		"dungeon": "argus_bunker", "res": {"lightning": -0.3}, "loot": [["circuits", 1.0], ["power_cell", 1.0]], "trophy": true}))
	L.append(B("zero_parasite", 3, "Паразит Нулевой Зоны", "dungeon", "anomaly", 2500, 30,
		{"shift": A("blink", {"cd": 4.0}), "false": A("decoys", {"count": 3, "cd": 14.0}), "strike": A("strikes", {"dmg": 1.2, "count": 5, "dtype": "energy", "cd": 7.0}), "rift": A("slowzone", {"cd": 12.0})},
		[{"hp": 1.0, "use": ["shift", "strike"]}, {"hp": 0.5, "use": ["shift", "false", "strike", "rift"], "msg": "Пространство дрожит!"}],
		"Нестабильное аномальное существо.",
		{"plan": "worm", "f": {"segments": 10, "girth": 0.4, "eyes": 6}, "body": Color(0.3, 0.25, 0.45), "glow": Color(0.6, 0.4, 1.0), "scale": 2.0, "dtype": "energy", "dungeon": "zero_zone", "loot": [["arcane_dust", 1.0]], "trophy": true}))
	L.append(B("steel_executioner", 3, "Стальной Палач", "dungeon", "construct", 3100, 34,
		{"crush": A("slam", {"dmg": 1.7, "radius": 5.0, "cd": 6.0}), "wave": A("quake", {"dmg": 1.2, "cd": 9.0}), "modules": A("armor_up", {"cd": 15.0, "dur": 6.0}), "fury": A("combo", {"dmg": 1.2, "hits": 4, "cd": 6.0})},
		[{"hp": 1.0, "use": ["crush", "wave", "modules"]}, {"hp": 0.5, "use": ["fury", "crush", "wave"], "msg": "Броня сорвана — Палач идёт врукопашную!", "speed": 1.35, "drop_parts": true}],
		"Массивная бронированная машина-гуманоид.",
		{"f": {"width": 1.0, "hunch": 0.0, "plates": 3, "gears": 2, "plate_names": ["module_l", "module_r", "module_back"]}, "parts": {"module_l": 400, "module_r": 400, "module_back": 450}, "body": Color(0.5, 0.52, 0.55), "metal": true,
		"glow": Color(1.0, 0.3, 0.2), "scale": 2.4, "loot": [["circuits", 1.0]], "trophy": true}))
	L.append(B("doctor_distortion", 3, "Доктор Искажений", "dungeon", "mage", 2300, 28,
		{"gravity": A("pull", {"cd": 10.0, "radius": 8.0}), "boost": A("haste", {"cd": 15.0, "dur": 5.0}), "subjects": A("summon", {"enemy": "lab_mutant", "count": 2, "cd": 18.0}),
		"rift": A("strikes", {"dmg": 1.2, "count": 5, "dtype": "time", "cd": 8.0}), "blink": A("blink", {"cd": 6.0})},
		[{"hp": 1.0, "use": ["rift", "gravity", "blink"]}, {"hp": 0.5, "use": ["rift", "gravity", "subjects", "boost", "blink"], "msg": "Доктор вводит себе сыворотку!"}],
		"Учёный, изменённый неудачным экспериментом.",
		{"rig": "humanoid", "weapon": "staff_oak", "armor": "robe", "cloth": Color(0.85, 0.85, 0.82), "glow": Color(0.5, 1.0, 0.9), "scale": 1.4, "dtype": "time", "caster": true, "loot": [["arcane_dust", 1.0]], "trophy": true}))
	L.append(B("object_omega", 3, "Объект ОМЕГА", "titan", "titan", 6800, 42,
		{"slam": A("slam", {"dmg": 1.8, "radius": 6.0, "cd": 6.0}), "bio": A("poison_zone", {"dmg": 0.45, "count": 5, "cd": 10.0}), "beam": A("beam", {"dmg": 1.5, "dtype": "energy", "cd": 7.0}),
		"chase": A("charge", {"dmg": 1.6, "cd": 6.0}), "spawn": A("summon", {"enemy": "unstable_clone", "count": 3, "cd": 20.0})},
		[{"hp": 1.0, "use": ["slam", "chase"]}, {"hp": 0.66, "use": ["slam", "chase", "bio", "spawn"], "msg": "ОМЕГА прорывает защитный сектор!", "speed": 1.2},
		{"hp": 0.33, "use": ["slam", "beam", "bio", "chase", "spawn"], "msg": "Финальная форма ОМЕГИ!", "enrage": true, "form": 1.15}],
		"Огромное экспериментальное существо подземного комплекса.",
		{"f": {"width": 1.3, "hunch": 0.4, "veins": true, "arm": 1.4, "crystals": 4}, "body": Color(0.6, 0.45, 0.45), "glow": Color(0.6, 1.0, 0.5), "scale": 3.2, "dungeon": "object_omega",
		"loot": [["mutagen", 1.0], ["x_omega_cell", 0.3]], "trophy": true}))
	# ------------------------------------------------------------- Future
	L.append(B("phase_predator", 4, "Фазовый Хищник", "dungeon", "beast", 3000, 32,
		{"dash": A("charge", {"dmg": 1.4, "cd": 5.0}), "claws": A("cleave", {"dmg": 1.4, "radius": 4.0, "arc": 120.0, "dtype": "energy", "cd": 4.0}),
		"echo": A("decoys", {"count": 2, "cd": 14.0}), "shift": A("blink", {"cd": 4.0})},
		[{"hp": 1.0, "use": ["claws", "dash", "shift"]}, {"hp": 0.5, "use": ["claws", "dash", "echo", "shift"], "msg": "Хищник распадается на фазы!", "speed": 1.25}],
		"Чудовище, переходящее в иное пространственное состояние.",
		{"plan": "quad", "f": {"len": 1.4, "height": 0.8, "girth": 0.28, "crystals": 5, "tail": 1.1, "horns": 2, "spikes": 4}, "body": Color(0.2, 0.25, 0.35), "glow": Color(0.4, 1.0, 0.9), "scale": 2.4,
		"dtype": "energy", "dungeon": "phase_catacombs", "loot": [["phase_crystal", 1.0]], "trophy": true}))
	L.append(B("nanoswarm_queen", 4, "Королева Нанороя", "dungeon", "swarm", 2900, 30,
		{"swarm": A("summon", {"enemy": "nano_swarm", "count": 3, "cd": 14.0}), "rebuild": A("regen", {"cd": 16.0, "dur": 4.0}), "cloud": A("poison_zone", {"dmg": 0.35, "count": 4, "dtype": "slash", "cd": 10.0}),
		"reconfig": A("armor_up", {"cd": 16.0, "dur": 5.0}), "lash": A("fan", {"dmg": 0.9, "count": 6, "dtype": "energy", "cd": 4.0})},
		[{"hp": 1.0, "use": ["lash", "swarm", "cloud"]}, {"hp": 0.5, "use": ["lash", "swarm", "cloud", "rebuild", "reconfig"], "msg": "Королева перестраивает тело!", "form": 1.1}],
		"Синтетическая форма жизни, управляющая роем машин.",
		{"plan": "arach", "f": {"legs": 8, "abdomen": 1.7, "eyes": 6, "crystals": 6}, "body": Color(0.6, 0.62, 0.66), "metal": true, "glow": Color(0.5, 0.9, 1.0), "scale": 2.6, "dtype": "energy",
		"dungeon": "nanite_hive", "res": {"slash": 0.4, "lightning": -0.5}, "loot": [["nanite_dust", 1.0]], "trophy": true}))
	L.append(B("chrono_guardian", 4, "Хронологический Страж", "dungeon", "construct", 3000, 32,
		{"slow": A("slowzone", {"cd": 10.0}), "traps": A("mines", {"dmg": 1.2, "count": 5, "dtype": "time", "cd": 12.0}), "blades": A("fan", {"dmg": 1.0, "count": 5, "dtype": "time", "cd": 4.0}),
		"repeat": A("echo_strike", {"dmg": 1.4, "cd": 9.0}), "smash": A("slam", {"dmg": 1.5, "radius": 5.0, "cd": 6.0})},
		[{"hp": 1.0, "use": ["blades", "slow", "smash"]}, {"hp": 0.5, "use": ["blades", "traps", "repeat", "smash", "slow"], "msg": "Страж повторяет своё прошлое!"}],
		"Древний автоматон, охраняющий временные разломы. Не поддаётся замедлению.",
		{"f": {"width": 0.9, "hunch": 0.0, "gears": 4, "runes": true, "crystals": 3}, "body": Color(0.55, 0.5, 0.35), "metal": true, "glow": Color(0.4, 1.0, 0.85), "scale": 2.3, "dtype": "time",
		"dungeon": "chrono_prison", "time_immune": true, "loot": [["chrono_shard", 1.0]], "trophy": true}))
	L.append(B("reality_parasite", 4, "Паразит Реальности", "dungeon", "anomaly", 2800, 30,
		{"warp": A("pull", {"cd": 9.0, "radius": 8.0}), "false": A("decoys", {"count": 3, "cd": 13.0}), "portals": A("strikes", {"dmg": 1.2, "count": 6, "dtype": "dark", "cd": 8.0}), "gravity": A("slowzone", {"cd": 12.0})},
		[{"hp": 1.0, "use": ["portals", "warp"]}, {"hp": 0.5, "use": ["portals", "warp", "false", "gravity"], "msg": "Геометрия рушится!"}],
		"Аномалия с постоянно меняющейся геометрией.",
		{"plan": "orb", "f": {"core_r": 0.6, "shards": 14, "hover": 2.0}, "body": Color(0.3, 0.2, 0.4), "glow": Color(0.8, 0.4, 1.0), "scale": 2.4, "dtype": "dark", "caster": true,
		"dungeon": "reality_maze", "loot": [["arcane_dust", 1.0]], "trophy": true}))
	L.append(B("fallen_synthetic", 4, "Падший Синтетик", "dungeon", "duelist", 2600, 32,
		{"blades": A("combo", {"dmg": 1.1, "hits": 4, "dtype": "energy", "cd": 5.0}), "counter": A("parry_stance", {"cd": 11.0, "dur": 2.5}), "phase": A("blink", {"cd": 5.0}),
		"mode": A("haste", {"cd": 15.0, "dur": 5.0})},
		[{"hp": 1.0, "use": ["blades", "counter", "phase"]}, {"hp": 0.5, "use": ["blades", "counter", "phase", "mode"], "msg": "Синтетик переключает боевой режим!", "speed": 1.2}],
		"Бывший командир искусственной армии.",
		{"rig": "humanoid", "weapon": "blade_energy", "armor": "android", "cloth": Color(0.85, 0.85, 0.9), "glow": Color(1.0, 0.3, 0.3), "scale": 1.5, "dtype": "energy", "loot": [["nanite_dust", 1.0]], "trophy": true}))
	L.append(B("gravity_colossus", 4, "Гравитационный Исполин", "dungeon", "construct", 3300, 34,
		{"pull": A("pull", {"cd": 8.0, "radius": 10.0}), "push": A("nova", {"dmg": 1.3, "radius": 7.0, "dtype": "energy", "cd": 9.0}), "lift": A("rock_throw", {"dmg": 1.2, "count": 3, "cd": 6.0}),
		"wave": A("quake", {"dmg": 1.3, "cd": 10.0})},
		[{"hp": 1.0, "use": ["pull", "lift", "push"]}, {"hp": 0.5, "use": ["pull", "lift", "push", "wave"], "msg": "Ядро исполина набирает массу!", "speed": 1.1}],
		"Искусственная форма жизни с тяжёлым энергетическим ядром.",
		{"f": {"width": 1.2, "hunch": 0.1, "crystals": 6, "runes": true, "plates": 2, "plate_names": ["plate_l", "plate_r"]}, "parts": {"plate_l": 420, "plate_r": 420}, "body": Color(0.3, 0.32, 0.4), "metal": true, "glow": Color(0.7, 0.5, 1.0), "scale": 2.7, "dtype": "energy", "loot": [["power_cell", 1.0]], "trophy": true}))
	L.append(B("last_time_archmage", 4, "Последний Архимаг Времени", "dungeon", "mage", 2700, 32,
		{"doubles": A("decoys", {"count": 3, "cd": 14.0}), "jump": A("blink", {"cd": 5.0}), "seals": A("strikes", {"dmg": 1.3, "count": 6, "dtype": "time", "cd": 8.0}),
		"tempo": A("haste", {"cd": 14.0, "dur": 5.0}), "anomaly": A("slowzone", {"cd": 12.0}),
		"ward": A("shield", {"charge": 1.4, "dur": 6.0, "cd_after": 20.0, "pool": 0.12, "counter": ["light", "earth"], "cd": 4.0})},
		[{"hp": 1.0, "use": ["seals", "jump", "ward"]}, {"hp": 0.5, "use": ["seals", "doubles", "tempo", "anomaly", "jump", "ward"], "msg": "Архимаг ломает темп времени!"}],
		"Редчайший разумный босс; его жизнь тянется через все эпохи.",
		{"rig": "humanoid", "weapon": "staff_oak", "armor": "robe", "hat": "hood", "cloth": Color(0.15, 0.3, 0.32), "glow": Color(0.4, 1.0, 0.85), "scale": 1.6, "dtype": "time", "caster": true, "time_immune": true,
		"loot": [["chrono_shard", 1.0], ["x_time_hourglass", 0.3]], "trophy": true, "talks": true}))
	L.append(B("age_devourer", 4, "Пожиратель Эпох", "titan", "titan", 7500, 46,
		{"rifts": A("strikes", {"dmg": 1.3, "count": 7, "dtype": "time", "cd": 7.0}), "space": A("pull", {"cd": 10.0, "radius": 10.0}), "spawn": A("summon", {"enemy": "chrono_parasite", "count": 3, "cd": 18.0}),
		"arena": A("platforms", {"count": 6, "cd": 16.0}), "ages": A("ages_wrath", {"dmg": 1.5, "cd": 14.0}), "tail": A("tail", {"dmg": 1.5, "cd": 6.0})},
		[{"hp": 1.0, "use": ["rifts", "space", "tail"]}, {"hp": 0.66, "use": ["rifts", "space", "spawn", "arena", "tail"], "msg": "Пожиратель меняет арену!", "form": 1.1},
		{"hp": 0.33, "use": ["ages", "rifts", "space", "spawn", "tail"], "msg": "Гнев всех эпох!", "enrage": true}],
		"Огромное существо, связанное с разрушением временной структуры мира.",
		{"plan": "drake", "f": {"len": 1.8, "height": 0.85, "girth": 0.4, "neck": 0.9, "tail": 1.5, "horns": 6, "crystals": 8, "spikes": 8, "eyes": 6}, "body": Color(0.15, 0.2, 0.25), "accent": Color(0.25, 0.4, 0.4),
		"glow": Color(0.4, 1.0, 0.85), "scale": 3.6, "dtype": "time", "time_immune": true, "dungeon": "devourer_hall", "loot": [["chrono_shard", 1.0], ["x_epoch_fang", 0.3]], "trophy": true}))
	return L

# ======================================================================= dungeons
static func D(id: String, era: int, n: int, nm: String, theme: String, boss_id: String, pool: Array, o: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "era": era, "n": n, "name": nm, "theme": theme, "boss": boss_id, "pool": pool, "rooms": 9, "traps": ["spikes"], "miniboss": "",
		"floor": Color(0.3, 0.28, 0.26), "wall": Color(0.25, 0.23, 0.21), "light": Color(1.0, 0.8, 0.6), "sky": Color(0.04, 0.04, 0.05), "ambient": "drip"}
	for k in o:
		d[k] = o[k]
	return d

static func _build_dungeons() -> Array:
	var L: Array = []
	var cave := {"floor": Color(0.3, 0.28, 0.26), "wall": Color(0.27, 0.25, 0.22), "light": Color(1.0, 0.75, 0.5)}
	L.append(D("black_stone", 0, 1, "Пещеры Чёрного Камня", "cave", "garmon", ["stone_slime", "cave_scavenger", "deep_spider", "stone_hound", "cave_goblin"], cave.merged({"miniboss": "blind_troll", "traps": ["rocks", "spikes"], "rooms": 9})))
	L.append(D("thousand_eyes", 0, 2, "Гнездо Тысячи Глаз", "nest", "spider_queen", ["deep_spider", "crystal_spider", "venom_crawler"], {"floor": Color(0.22, 0.2, 0.2), "wall": Color(0.2, 0.18, 0.18), "light": Color(0.8, 0.9, 0.7), "miniboss": "crystal_spider", "traps": ["web", "poison"], "rooms": 10}))
	L.append(D("forgotten_order", 0, 3, "Катакомбы Забытого Ордена", "crypt", "arktor", ["cursed_knight", "grave_knight", "bone_hunter"], {"floor": Color(0.35, 0.33, 0.3), "wall": Color(0.4, 0.38, 0.35), "light": Color(0.7, 0.9, 1.0), "miniboss": "grave_knight", "traps": ["spikes", "fire"], "rooms": 10}))
	L.append(D("root_crypt", 0, 4, "Лесной Склеп Корней", "roots", "blight_god", ["forest_spirit", "venom_crawler", "swamp_wolf", "forest_ent"], {"floor": Color(0.25, 0.22, 0.16), "wall": Color(0.22, 0.28, 0.16), "light": Color(0.7, 1.0, 0.6), "miniboss": "forest_ent", "traps": ["poison", "roots"], "rooms": 9}))
	L.append(D("first_keeper", 0, 5, "Чертог Первого Хранителя", "hall", "mountain_keeper", ["rune_guardian", "stone_hound", "cursed_knight", "stone_slime"], {"floor": Color(0.42, 0.4, 0.38), "wall": Color(0.45, 0.43, 0.4), "light": Color(0.6, 0.8, 1.0), "miniboss": "rune_guardian", "traps": ["rocks", "spikes"], "rooms": 12}))
	L.append(D("alch_catacombs", 1, 1, "Алхимические Катакомбы", "lab_old", "alch_colossus", ["alch_slime", "infected_alchemist", "plague_rat", "alch_chimera"], {"floor": Color(0.3, 0.32, 0.28), "wall": Color(0.32, 0.3, 0.26), "light": Color(0.6, 1.0, 0.5), "miniboss": "alch_chimera", "traps": ["poison", "fire"]}))
	L.append(D("sunken_fortress", 1, 2, "Затонувшая Крепость", "flooded", "ghost_captain", ["ghost_sailor", "sea_crawler", "port_warden", "mist_spirit"], {"floor": Color(0.2, 0.28, 0.3), "wall": Color(0.25, 0.3, 0.32), "light": Color(0.5, 0.8, 1.0), "miniboss": "port_warden", "traps": ["water", "spikes"]}))
	L.append(D("clock_tower", 1, 3, "Часовая Башня Подземелий", "gears", "clock_executioner", ["clock_spider", "mech_jester", "rune_dummy", "mech_raven"], {"floor": Color(0.4, 0.32, 0.22), "wall": Color(0.35, 0.28, 0.2), "light": Color(1.0, 0.85, 0.5), "miniboss": "living_statue", "traps": ["blades", "spikes"]}))
	L.append(D("carnival_depths", 1, 4, "Карнавальные Подземелья", "carnival", "carnival_witch", ["mask_parasite", "mech_jester", "blood_duelist", "plague_rat"], {"floor": Color(0.3, 0.15, 0.2), "wall": Color(0.35, 0.1, 0.25), "light": Color(1.0, 0.5, 0.8), "miniboss": "blood_duelist", "traps": ["illusion", "spikes"]}))
	L.append(D("astral_observatory", 1, 5, "Астральная Обсерватория", "astral", "astral_mechanism", ["astral_jelly", "glass_golem", "rune_dummy", "clock_spider"], {"floor": Color(0.2, 0.2, 0.3), "wall": Color(0.25, 0.25, 0.4), "light": Color(0.7, 0.7, 1.0), "miniboss": "glass_golem", "traps": ["lightning", "spikes"], "rooms": 12}))
	L.append(D("rust_mine", 2, 1, "Заброшенная Шахта Ржавчины", "mine", "rust_king", ["rust_automaton", "metal_scavenger", "mine_mutant", "boiler_parasite"], {"floor": Color(0.3, 0.25, 0.2), "wall": Color(0.35, 0.27, 0.2), "light": Color(1.0, 0.7, 0.4), "miniboss": "mine_mutant", "traps": ["rocks", "steam"]}))
	L.append(D("electric_catacombs", 2, 2, "Электрические Катакомбы", "electric", "electric_phantom", ["electric_worm", "electric_ghost", "energy_clot", "scout_automaton"], {"floor": Color(0.2, 0.22, 0.28), "wall": Color(0.22, 0.25, 0.32), "light": Color(0.5, 0.8, 1.0), "miniboss": "electric_ghost", "traps": ["lightning", "spikes"]}))
	L.append(D("drill_complex", 2, 3, "Подземный Буровой Комплекс", "mine", "iron_miner", ["drill_beetle", "steam_hunter", "rust_automaton", "mech_hound"], {"floor": Color(0.32, 0.28, 0.24), "wall": Color(0.3, 0.3, 0.32), "light": Color(1.0, 0.75, 0.45), "miniboss": "steam_golem", "traps": ["rocks", "steam"]}))
	L.append(D("thousand_pipes", 2, 4, "Печь Тысячи Труб", "furnace", "ash_titan", ["overheated_automaton", "coal_elemental", "boiler_parasite", "steam_golem"], {"floor": Color(0.25, 0.18, 0.15), "wall": Color(0.3, 0.2, 0.15), "light": Color(1.0, 0.5, 0.2), "miniboss": "slag_giant", "traps": ["fire", "steam"]}))
	L.append(D("megafactory", 2, 5, "Сердце Мегазавода", "factory", "megafactory_heart", ["factory_warden", "mech_hound", "rotor_hunter", "steam_hunter", "mech_scorpion"], {"floor": Color(0.3, 0.3, 0.32), "wall": Color(0.28, 0.28, 0.3), "light": Color(1.0, 0.7, 0.4), "miniboss": "steam_golem", "traps": ["blades", "fire", "lightning"], "rooms": 12}))
	L.append(D("chimera_lab", 3, 1, "Лаборатория «Химера»", "lab", "project_chimera", ["lab_mutant", "escaped_experiment", "unstable_clone", "anomaly_slime"], {"floor": Color(0.55, 0.57, 0.58), "wall": Color(0.7, 0.72, 0.74), "light": Color(0.9, 1.0, 1.0), "miniboss": "lab_giant", "traps": ["gas", "lightning"]}))
	L.append(D("phantom_complex", 3, 2, "Подземный Комплекс Фантом", "bunker", "commander_phantom", ["shadow_operative", "artificial_soldier", "recon_robot", "battle_drone"], {"floor": Color(0.3, 0.32, 0.3), "wall": Color(0.35, 0.37, 0.35), "light": Color(1.0, 0.95, 0.85), "miniboss": "electromech_guard", "traps": ["lasers", "spikes"]}))
	L.append(D("zero_zone", 3, 3, "Зона Нулевого Эксперимента", "anomaly", "zero_parasite", ["anomaly_slime", "energy_parasite", "space_stalker", "underground_parasite"], {"floor": Color(0.2, 0.18, 0.28), "wall": Color(0.25, 0.2, 0.35), "light": Color(0.7, 0.5, 1.0), "miniboss": "space_stalker", "traps": ["timeslow", "lightning"]}))
	L.append(D("argus_bunker", 3, 4, "Бункер «АРГУС»", "bunker", "argus", ["battle_drone", "recon_robot", "electromech_guard", "urban_mech_beast"], {"floor": Color(0.25, 0.27, 0.3), "wall": Color(0.3, 0.32, 0.36), "light": Color(1.0, 0.4, 0.35), "miniboss": "urban_mech_beast", "traps": ["lasers", "lightning"]}))
	L.append(D("object_omega", 3, 5, "Объект ОМЕГА", "lab", "object_omega", ["lab_mutant", "bio_golem", "armored_mutant", "exp_predator", "toxic_hunter"], {"floor": Color(0.5, 0.52, 0.55), "wall": Color(0.6, 0.62, 0.65), "light": Color(0.8, 1.0, 0.9), "miniboss": "bio_golem", "traps": ["gas", "lasers"], "rooms": 12}))
	L.append(D("phase_catacombs", 4, 1, "Фазовые Катакомбы", "phase", "phase_predator", ["phase_spider", "quantum_predator", "space_slime", "chrono_parasite"], {"floor": Color(0.15, 0.18, 0.25), "wall": Color(0.2, 0.25, 0.35), "light": Color(0.4, 1.0, 0.9), "miniboss": "quantum_predator", "traps": ["timeslow", "lasers"]}))
	L.append(D("nanite_hive", 4, 2, "Нанитовый Улей", "hive", "nanoswarm_queen", ["nano_swarm", "nanite_scorpion", "synth_warrior", "cyber_beast"], {"floor": Color(0.35, 0.37, 0.4), "wall": Color(0.45, 0.47, 0.5), "light": Color(0.5, 0.9, 1.0), "miniboss": "nanite_scorpion", "traps": ["blades", "lightning"]}))
	L.append(D("chrono_prison", 4, 3, "Хронологическая Тюрьма", "chrono", "chrono_guardian", ["chrono_parasite", "chrono_double", "quantum_golem", "plasma_guard"], {"floor": Color(0.3, 0.35, 0.33), "wall": Color(0.35, 0.45, 0.42), "light": Color(0.4, 1.0, 0.85), "miniboss": "quantum_golem", "traps": ["timeslow", "spikes"]}))
	L.append(D("reality_maze", 4, 4, "Лабиринт Реальности", "maze", "reality_parasite", ["dimension_parasite", "space_slime", "neural_parasite", "astral_stalker"], {"floor": Color(0.22, 0.15, 0.3), "wall": Color(0.3, 0.2, 0.4), "light": Color(0.8, 0.5, 1.0), "miniboss": "astral_stalker", "traps": ["timeslow", "illusion"]}))
	L.append(D("devourer_hall", 4, 5, "Чертог Пожирателя Эпох", "epochs", "age_devourer", ["phase_giant", "lesser_time_eater", "chrono_double", "synth_harpy", "artificial_chimera"], {"floor": Color(0.2, 0.25, 0.28), "wall": Color(0.3, 0.32, 0.35), "light": Color(0.5, 1.0, 0.9), "miniboss": "phase_giant", "traps": ["timeslow", "fire", "lightning"], "rooms": 13}))
	return L
