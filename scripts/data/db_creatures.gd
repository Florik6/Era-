class_name DBCreatures
## «Beasts of the Ages»: exactly 100 new species, 20 per era. Every species
## has a unique id, a body plan with its own proportions and features (see
## BeastRig), behaviour type, health, damage, armour, resistances and
## weaknesses, habitats, loot and a bestiary text. Intelligent humanoids use
## the humanoid rig with their own weapons and gear.
##
## cat: common | dangerous | elite | miniboss
## beh: predator | territorial | herd | ambush | magic | intelligent | construct | swarm
## hab: open-world biomes (forest, plains, mountain, swamp, sand, snow) and
##      places (cave, ruins, coast, industrial, lab, anomaly, dungeon themes)

const CAT_NAMES := {"common": "обычное", "dangerous": "опасное", "elite": "элитное", "miniboss": "мини-босс"}
const BEH_NAMES := {"predator": "хищник", "territorial": "территориальное", "herd": "стадное", "ambush": "засадный хищник",
	"magic": "магическое", "intelligent": "разумное", "construct": "механизм", "swarm": "рой"}
const CAT_HP := {"common": 1.0, "dangerous": 1.6, "elite": 2.6, "miniboss": 6.0}

static var _all := {}

static func K(id: String, era: int, nm: String, cat: String, plan: String, beh: String, hp: float, dmg: float, hab: Array, desc: String, o: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "era": era, "name": nm, "cat": cat, "plan": plan, "beh": beh, "hp": hp, "dmg": dmg, "hab": hab, "desc": desc,
		"speed": 1.0, "dtype": "slash", "res": {}, "loot": [], "abil": [], "f": {}, "scale": 1.0, "armor": 0.0, "lvl": era * 2}
	for k in o:
		d[k] = o[k]
	return d

static func all() -> Dictionary:
	if _all.is_empty():
		for e in _build():
			_all[e.id] = e
	return _all

static func get_def(id: String) -> Dictionary:
	return all().get(id, {})

static func has(id: String) -> bool:
	return all().has(id)

static func of_era(era: int) -> Array:
	return all().values().filter(func(e): return int(e.era) == era)

static func for_habitat(era: int, tag: String) -> Array:
	return of_era(era).filter(func(e): return tag in e.hab and e.cat != "miniboss")

## The actor definition the spawner understands (DBActors.ENEMIES format).
static func enemy_def(id: String) -> Dictionary:
	var e: Dictionary = get_def(id)
	if e.is_empty():
		return {}
	var d := {"name": e.name, "hp": e.hp * float(CAT_HP.get(e.cat, 1.0)), "dmg": e.dmg, "lvl": e.lvl, "xp": int(e.hp * 0.25 * float(CAT_HP.get(e.cat, 1.0))),
		"team": e.get("team", "wildlife" if e.get("beh_peaceful", false) else "monster"), "speed": e.speed, "dtype": e.dtype, "res": e.res, "scale": e.scale, "beast": true, "species": id,
		"elite": e.cat in ["elite", "miniboss"]}
	if e.plan == "humanoid":
		d.rig = "humanoid"
		d.weapons = e.get("weapons", ["sword_iron"])
		d.armor = e.get("armor_kind", "leather")
		d.ai = e.get("ai", "melee")
		d.cloth = e.get("body", Color(0.3, 0.3, 0.3))
		for k in ["hat", "glow", "skeleton", "robot", "new_spells", "spells", "offhand"]:
			if e.has(k):
				d[k] = e[k]
	else:
		d.rig = "beast"
		d.plan = e.plan
		d.f = e.f
		d.body = e.get("body", Color(0.45, 0.42, 0.38))
		d.accent = e.get("accent", Color(0.3, 0.28, 0.25))
		d.glow = e.get("glow", Color(1.0, 0.6, 0.2))
		d.metal = e.get("metal", false)
		d.ai = "caster" if e.has("spells") else "beast"
		if e.has("spells"):
			d.spells = e.spells
		if e.has("proj"):
			d.proj = e.proj
	return d

# ======================================================================= data
static func _build() -> Array:
	var L: Array = []
	_medieval(L)
	_renaissance(L)
	_industrial(L)
	_modern(L)
	_future(L)
	return L

const GREY := Color(0.45, 0.43, 0.4)

static func _medieval(L: Array) -> void:
	L.append(K("cave_scavenger", 0, "Пещерный падальщик", "common", "quad", "herd", 45, 8, ["cave", "mountain"], "Низкий длинный падальщик пещер. Держится стаей, разбегается при сильном отпоре.",
		{"f": {"len": 1.2, "height": 0.42, "girth": 0.18, "head": 0.8, "tail": 0.6, "eyes": 2}, "body": Color(0.42, 0.38, 0.33), "loot": [["beast_hide", 0.5]], "speed": 1.2}))
	L.append(K("deep_spider", 0, "Глубинный паук", "common", "arach", "ambush", 55, 10, ["cave", "forest"], "Подстерегает в темноте на потолке, оплетает добычу паутиной.",
		{"f": {"legs": 8, "abdomen": 1.0, "eyes": 6}, "body": Color(0.18, 0.16, 0.15), "glow": Color(0.9, 0.2, 0.15), "dtype": "pierce", "abil": ["web", "poison"], "loot": [["spider_silk", 0.6], ["venom_gland", 0.25]]}))
	L.append(K("crystal_spider", 0, "Кристальный паук", "dangerous", "arach", "ambush", 70, 12, ["cave"], "Хитин зарос кристаллами — режущий удар и отражённый свет.",
		{"f": {"legs": 8, "abdomen": 1.1, "eyes": 8, "crystals": 5}, "body": Color(0.35, 0.4, 0.5), "glow": Color(0.6, 0.85, 1.0), "dtype": "pierce", "res": {"slash": 0.3, "blunt": -0.4}, "abil": ["poison"], "loot": [["crystal_shard", 0.5]]}))
	L.append(K("swamp_wolf", 0, "Болотный волк", "common", "quad", "predator", 50, 9, ["swamp", "forest"], "Охотится стаей в тумане болот; воет, созывая своих.",
		{"f": {"len": 1.0, "height": 0.6, "girth": 0.2, "mane": true, "eyes": 2}, "body": Color(0.32, 0.36, 0.28), "abil": ["howl", "pounce"], "loot": [["beast_hide", 0.6], ["beast_fang", 0.3]], "speed": 1.3}))
	L.append(K("stone_slime", 0, "Каменный слизень", "common", "blob", "territorial", 60, 7, ["cave", "mountain"], "Медленный ком слизи с каменными наростами. Дробящее оружие разбивает его корку.",
		{"f": {"rocky": true, "squash": 0.7}, "body": Color(0.5, 0.48, 0.42), "glow": Color(0.9, 0.7, 0.3), "dtype": "blunt", "res": {"slash": 0.4, "pierce": 0.4, "blunt": -0.5}, "speed": 0.6, "loot": [["iron_ore", 0.6], ["stone_heart", 0.08]]}))
	L.append(K("bone_hunter", 0, "Костяной охотник", "dangerous", "humanoid", "predator", 80, 13, ["ruins", "cave"], "Скелет-лучник, выслеживающий живых по теплу.",
		{"weapons": ["bow_short", "dagger_iron"], "ai": "ranged", "skeleton": true, "armor_kind": "bones", "res": {"pierce": 0.4, "dark": 0.8, "light": -0.5}, "loot": [["bone_dust", 0.5]]}))
	L.append(K("forest_spirit", 0, "Лесной дух", "dangerous", "orb", "magic", 60, 11, ["forest"], "Светящийся сгусток лесной магии; безобиден, пока не трогают деревья.",
		{"f": {"core_r": 0.22, "shards": 5, "hover": 1.4}, "body": Color(0.5, 0.9, 0.5), "glow": Color(0.6, 1.0, 0.5), "dtype": "light", "spells": ["h_warm_touch", "a_light_gust"], "res": {"dark": -0.5}, "beh_peaceful": true, "loot": [["spirit_essence", 0.4]]}))
	L.append(K("shadow_deer", 0, "Теневой олень", "common", "quad", "herd", 40, 6, ["forest", "plains"], "Пугливый олень с рогами из сумрака. Убегает, но загнанный — бодается.",
		{"f": {"len": 1.0, "height": 0.85, "girth": 0.19, "neck": 0.35, "horns": 4, "tail": 0.15, "leg": 0.03}, "body": Color(0.22, 0.18, 0.28), "glow": Color(0.7, 0.4, 1.0), "dtype": "pierce", "speed": 1.5, "beh_peaceful": true, "loot": [["beast_hide", 0.6], ["shadow_antler", 0.2]]}))
	L.append(K("cursed_knight", 0, "Проклятый рыцарь", "elite", "humanoid", "territorial", 140, 20, ["ruins"], "Рыцарь в латах, проклятый вечно охранять павший орден.",
		{"weapons": ["sword_steel"], "offhand": "shield_kite", "armor_kind": "plate", "hat": "greathelm", "glow": Color(0.5, 1.0, 0.6), "res": {"slash": 0.3, "light": -0.4}, "loot": [["cursed_steel", 0.4]]}))
	L.append(K("cave_goblin", 0, "Пещерный гоблин", "common", "humanoid", "intelligent", 35, 7, ["cave", "mountain"], "Мелкий, хитрый и жадный. Отступает к своим и бросает камни.",
		{"weapons": ["dagger_iron"], "ai": "melee", "armor_kind": "leather", "scale": 0.75, "body": Color(0.3, 0.45, 0.25), "loot": [["iron_ore", 0.4], ["coin_pouch", 0.3]], "team": "monster"}))
	L.append(K("blind_troll", 0, "Слепой тролль", "elite", "giant", "territorial", 220, 24, ["cave", "mountain"], "Огромный пещерный тролль, ориентируется по звуку. Скрытность против него особенно хороша.",
		{"f": {"width": 0.85, "hunch": 0.45, "arm": 1.2, "eyes": 0}, "body": Color(0.4, 0.42, 0.36), "dtype": "blunt", "scale": 1.5, "speed": 0.8, "abil": ["slam", "regen"], "loot": [["troll_blood", 0.5]]}))
	L.append(K("venom_crawler", 0, "Ядовитый ползун", "common", "worm", "ambush", 50, 9, ["swamp", "cave"], "Сегментный ползун, выплёвывает яд и зарывается в ил.",
		{"f": {"segments": 7, "girth": 0.2, "eyes": 4}, "body": Color(0.35, 0.45, 0.2), "accent": Color(0.6, 0.65, 0.15), "dtype": "pierce", "abil": ["poison", "burrow"], "proj": "magic", "loot": [["venom_gland", 0.4]]}))
	L.append(K("rune_guardian", 0, "Рунический страж", "elite", "giant", "construct", 180, 18, ["ruins", "dungeon"], "Каменный страж, оживлённый рунами. Стоит неподвижно, пока не войдёшь в его круг.",
		{"f": {"width": 0.7, "hunch": 0.05, "rocky": true, "runes": true, "eyes": 1}, "body": Color(0.5, 0.48, 0.44), "glow": Color(0.4, 0.7, 1.0), "dtype": "blunt", "res": {"slash": 0.4, "pierce": 0.5, "lightning": -0.3}, "scale": 1.3, "speed": 0.6, "abil": ["slam"], "loot": [["rune_stone", 0.5]]}))
	L.append(K("stone_hound", 0, "Каменный гончий", "dangerous", "quad", "predator", 80, 13, ["mountain", "cave"], "Пёс из живого камня: тяжёлый укус, почти не чувствует стрел.",
		{"f": {"len": 0.95, "height": 0.58, "girth": 0.24, "spikes": 4, "head": 1.15}, "body": Color(0.48, 0.46, 0.42), "glow": Color(1.0, 0.6, 0.2), "dtype": "blunt", "res": {"pierce": 0.5}, "abil": ["pounce"], "loot": [["stone_heart", 0.12]]}))
	L.append(K("ash_harpy", 0, "Пепельная гарпия", "dangerous", "flyer", "predator", 55, 11, ["mountain", "sand"], "Пикирует с высоты, оставляя за собой пепел.",
		{"f": {"span": 1.0, "feathers": true, "hover": 2.2}, "body": Color(0.4, 0.35, 0.33), "accent": Color(0.25, 0.22, 0.22), "glow": Color(1.0, 0.45, 0.15), "dtype": "fire", "abil": ["dive"], "speed": 1.3, "loot": [["ash_feather", 0.5]]}))
	L.append(K("deep_worm", 0, "Глубинный червь", "elite", "worm", "ambush", 200, 22, ["cave", "sand"], "Огромный червь, выныривающий из-под земли под ногами.",
		{"f": {"segments": 10, "girth": 0.45, "spikes": 1, "eyes": 0}, "body": Color(0.55, 0.45, 0.4), "accent": Color(0.4, 0.3, 0.28), "scale": 1.4, "dtype": "pierce", "abil": ["burrow"], "loot": [["worm_tooth", 0.5]]}))
	L.append(K("grave_knight", 0, "Могильный рыцарь", "elite", "humanoid", "territorial", 160, 22, ["ruins", "dungeon"], "Мёртвый рыцарь в ржавых латах с двуручным мечом. Медленный, но страшный.",
		{"weapons": ["greatsword"], "armor_kind": "plate", "skeleton": true, "glow": Color(0.4, 0.9, 0.5), "res": {"dark": 0.7, "light": -0.5}, "loot": [["cursed_steel", 0.5]]}))
	L.append(K("forest_ent", 0, "Лесной энт", "elite", "tree", "territorial", 240, 20, ["forest"], "Ожившее дерево. Защищает рощу; огонь — его страх.",
		{"f": {"antlers": 4}, "body": Color(0.35, 0.27, 0.18), "accent": Color(0.3, 0.5, 0.22), "glow": Color(0.7, 1.0, 0.4), "dtype": "blunt", "res": {"pierce": 0.4, "fire": -0.6}, "speed": 0.6, "scale": 1.3, "beh_peaceful": true, "abil": ["root"], "loot": [["living_wood", 0.6]]}))
	L.append(K("fire_salamander", 0, "Огненный саламандр", "dangerous", "quad", "territorial", 70, 12, ["mountain", "cave"], "Ящер из лавовых пещер: огненное дыхание и раскалённая шкура.",
		{"f": {"len": 1.1, "height": 0.35, "girth": 0.17, "tail": 0.8, "spikes": 5, "legs": 4}, "body": Color(0.6, 0.25, 0.12), "glow": Color(1.0, 0.5, 0.1), "dtype": "fire", "res": {"fire": 0.8, "ice": -0.5}, "abil": ["breath"], "loot": [["fire_gland", 0.4]]}))
	L.append(K("young_rock_drake", 0, "Молодой скальный дракон", "miniboss", "drake", "territorial", 160, 26, ["mountain"], "Молодой дракон, ещё не покинувший скал. Уже дышит огнём.",
		{"f": {"len": 1.4, "height": 0.75, "girth": 0.3, "neck": 0.6, "tail": 1.0, "horns": 2, "spikes": 5}, "body": Color(0.42, 0.36, 0.3), "glow": Color(1.0, 0.5, 0.15), "dtype": "fire", "scale": 1.5, "res": {"fire": 0.6, "ice": -0.3}, "abil": ["breath", "dive"], "loot": [["drake_scale", 0.8]]}))

static func _renaissance(L: Array) -> void:
	L.append(K("alch_slime", 1, "Алхимический слизень", "common", "blob", "territorial", 55, 8, ["lab", "urban", "swamp"], "Слизь из разлитых зелий. Каждый раз другого цвета и с другим ядом.",
		{"f": {"squash": 0.8, "crystals": 2}, "body": Color(0.4, 0.8, 0.5), "glow": Color(0.6, 1.0, 0.3), "dtype": "poison", "abil": ["poison", "explode"], "loot": [["mutagen", 0.3]]}))
	L.append(K("glass_golem", 1, "Стеклянный голем", "elite", "giant", "construct", 170, 18, ["lab", "ruins"], "Голем из алхимического стекла: дробящее оружие разбивает его, стрелы отскакивают.",
		{"f": {"width": 0.65, "hunch": 0.0, "crystals": 6, "eyes": 1}, "body": Color(0.7, 0.85, 0.9), "glow": Color(0.6, 0.9, 1.0), "dtype": "slash", "res": {"pierce": 0.6, "blunt": -0.5}, "scale": 1.3, "loot": [["crystal_shard", 0.6]]}))
	L.append(K("mech_jester", 1, "Механический шут", "dangerous", "humanoid", "intelligent", 70, 12, ["urban", "dungeon"], "Заводная кукла в колпаке. Кувыркается и колет внезапно.",
		{"weapons": ["rapier"], "robot": true, "armor_kind": "robot", "hat": "hood", "body": Color(0.6, 0.15, 0.2), "loot": [["gears", 0.6]]}))
	L.append(K("ghost_sailor", 1, "Призрачный матрос", "common", "humanoid", "territorial", 55, 10, ["coast", "dungeon"], "Утонувший моряк; холодный туман вокруг, удары проходят наполовину.",
		{"weapons": ["sword_iron"], "skeleton": true, "armor_kind": "leather", "glow": Color(0.5, 0.9, 1.0), "res": {"slash": 0.4, "pierce": 0.4, "light": -0.5}, "loot": [["ectoplasm", 0.5]]}))
	L.append(K("plague_rat", 1, "Чумная крыса", "common", "quad", "swarm", 25, 5, ["urban", "swamp", "dungeon"], "Крысы приходят стаями; укус заражает раны.",
		{"f": {"len": 0.55, "height": 0.25, "girth": 0.12, "tail": 0.5, "head": 0.6}, "body": Color(0.3, 0.27, 0.24), "glow": Color(0.8, 0.9, 0.3), "dtype": "pierce", "abil": ["poison"], "speed": 1.3, "loot": [["mutagen", 0.1]]}))
	L.append(K("alch_chimera", 1, "Алхимическая химера", "elite", "quad", "predator", 180, 20, ["lab", "mountain"], "Сшитое из трёх зверей создание с горбом и рогами.",
		{"f": {"len": 1.3, "height": 0.75, "girth": 0.28, "hump": 1.0, "horns": 2, "mane": true, "tail": 0.9, "tail_club": true}, "body": Color(0.5, 0.42, 0.32), "glow": Color(0.6, 1.0, 0.4), "abil": ["pounce", "breath"], "scale": 1.3, "loot": [["mutagen", 0.6]]}))
	L.append(K("mask_parasite", 1, "Маска-паразит", "dangerous", "flyer", "ambush", 40, 9, ["urban", "dungeon"], "Летающая маска, цепляющаяся к лицу. Ослепляет.",
		{"f": {"span": 0.5, "len": 0.25, "hover": 1.7}, "body": Color(0.92, 0.88, 0.82), "accent": Color(0.6, 0.1, 0.15), "dtype": "dark", "abil": ["blind"], "loot": [["arcane_dust", 0.4]]}))
	L.append(K("blood_duelist", 1, "Кровавый дуэлянт", "dangerous", "humanoid", "intelligent", 90, 15, ["urban"], "Фехтовальщик, пьющий кровь. Парирует и отвечает уколом.",
		{"weapons": ["rapier"], "armor_kind": "leather", "body": Color(0.45, 0.05, 0.08), "hat": "hood", "loot": [["coin_pouch", 0.5]]}))
	L.append(K("crystal_scorpion", 1, "Кристальный скорпион", "dangerous", "insect", "ambush", 80, 13, ["sand", "cave"], "Скорпион с кристаллическим жалом; яд замедляет.",
		{"f": {"legs": 6, "abdomen": 0.8, "crystals": 3, "eyes": 2}, "body": Color(0.6, 0.5, 0.35), "glow": Color(0.7, 0.9, 1.0), "dtype": "pierce", "abil": ["poison"], "loot": [["venom_gland", 0.4], ["crystal_shard", 0.3]]}))
	L.append(K("sea_crawler", 1, "Морской ползун", "common", "insect", "territorial", 60, 10, ["coast"], "Панцирный краб-ползун приливных пещер.",
		{"f": {"legs": 6, "abdomen": 0.6, "stinger": false}, "body": Color(0.6, 0.3, 0.2), "dtype": "blunt", "res": {"slash": 0.3, "lightning": -0.5}, "loot": [["chitin", 0.5]]}))
	L.append(K("living_statue", 1, "Ожившая статуя", "elite", "giant", "territorial", 200, 19, ["ruins", "urban"], "Статуя площади, оживлённая неудачным опытом. Двигается, когда на неё не смотрят.",
		{"f": {"width": 0.6, "hunch": 0.0, "head": 1.0}, "body": Color(0.75, 0.73, 0.68), "dtype": "blunt", "res": {"slash": 0.5, "pierce": 0.5, "blunt": -0.3}, "speed": 0.7, "scale": 1.2, "loot": [["marble_chunk", 0.6]]}))
	L.append(K("clock_spider", 1, "Часовой паук", "dangerous", "construct", "construct", 70, 12, ["urban", "dungeon"], "Паук из шестерёнок и пружин.",
		{"f": {"legs": 6, "len": 0.6, "gears": 2}, "body": Color(0.6, 0.48, 0.25), "accent": Color(0.4, 0.35, 0.25), "metal": true, "dtype": "pierce", "res": {"lightning": -0.5}, "loot": [["gears", 0.6]]}))
	L.append(K("sand_hunter", 1, "Песчаный охотник", "dangerous", "quad", "ambush", 75, 13, ["sand"], "Ящер, зарывающийся в песок и бросающийся на тех, кто проходит рядом.",
		{"f": {"len": 1.2, "height": 0.4, "girth": 0.2, "tail": 0.9, "spikes": 6}, "body": Color(0.75, 0.62, 0.4), "abil": ["burrow", "pounce"], "loot": [["beast_hide", 0.5]]}))
	L.append(K("mist_spirit", 1, "Туманный дух", "dangerous", "orb", "magic", 55, 11, ["coast", "swamp"], "Сгусток холодного тумана; замедляет и выпивает тепло.",
		{"f": {"core_r": 0.25, "shards": 0, "ring": true, "hover": 1.2}, "body": Color(0.8, 0.85, 0.9), "glow": Color(0.7, 0.9, 1.0), "dtype": "ice", "spells": ["i_frost_needle"], "res": {"ice": 0.8, "fire": -0.5, "slash": 0.5}, "loot": [["ectoplasm", 0.5]]}))
	L.append(K("infected_alchemist", 1, "Заражённый алхимик", "dangerous", "humanoid", "intelligent", 75, 12, ["lab", "urban"], "Алхимик, отравленный своим зельем. Бросает колбы.",
		{"weapons": ["staff_alchemical"], "ai": "caster", "armor_kind": "robe", "body": Color(0.3, 0.45, 0.25), "new_spells": ["f_ember", "n_wither_curse"], "loot": [["mutagen", 0.5]]}))
	L.append(K("mech_raven", 1, "Механический ворон", "common", "flyer", "swarm", 30, 6, ["urban", "mountain"], "Заводной разведчик алхимиков; летает стаями.",
		{"f": {"span": 0.6, "len": 0.35, "hover": 2.5}, "body": Color(0.2, 0.2, 0.22), "metal": true, "glow": Color(1.0, 0.3, 0.2), "dtype": "pierce", "res": {"lightning": -0.6}, "abil": ["dive"], "loot": [["gears", 0.3]]}))
	L.append(K("port_warden", 1, "Проклятый страж порта", "elite", "humanoid", "territorial", 150, 20, ["coast"], "Стражник затонувшей таможни: алебарда и тяжёлые латы.",
		{"weapons": ["halberd"], "armor_kind": "plate", "skeleton": true, "glow": Color(0.4, 0.8, 1.0), "loot": [["cursed_steel", 0.4]]}))
	L.append(K("astral_jelly", 1, "Астральная медуза", "dangerous", "orb", "magic", 60, 12, ["anomaly", "coast"], "Парящая медуза из звёздного света; щупальца жалят молнией.",
		{"f": {"core_r": 0.35, "shards": 8, "hover": 2.0}, "body": Color(0.5, 0.4, 0.9), "glow": Color(0.8, 0.6, 1.0), "dtype": "lightning", "spells": ["l_electric_spark"], "loot": [["arcane_dust", 0.5]]}))
	L.append(K("rune_dummy", 1, "Рунный манекен", "common", "humanoid", "construct", 60, 9, ["dungeon", "lab"], "Тренировочный манекен, исписанный рунами. Учится на ваших ударах.",
		{"weapons": ["staff_oak"], "robot": true, "armor_kind": "robot", "body": Color(0.6, 0.5, 0.35), "res": {"blunt": -0.3}, "loot": [["rune_stone", 0.3]]}))
	L.append(K("deep_sea_beast", 1, "Глубинный морской зверь", "miniboss", "worm", "territorial", 260, 26, ["coast"], "Морское чудовище с зубастой пастью; выныривает у берега.",
		{"f": {"segments": 12, "girth": 0.5, "spikes": 1, "eyes": 2}, "body": Color(0.25, 0.35, 0.4), "accent": Color(0.4, 0.55, 0.5), "scale": 1.6, "res": {"ice": 0.4, "lightning": -0.4}, "abil": ["burrow"], "loot": [["sea_pearl", 0.7]]}))

static func _industrial(L: Array) -> void:
	L.append(K("rust_automaton", 2, "Ржавый автоматон", "common", "humanoid", "construct", 70, 11, ["industrial", "urban"], "Брошенный рабочий автомат. Ржав, медлителен, но силён.",
		{"weapons": ["hammer_war"], "robot": true, "armor_kind": "robot", "body": Color(0.5, 0.35, 0.22), "res": {"lightning": -0.5}, "loot": [["scrap_alloy", 0.6]]}))
	L.append(K("steam_hunter", 2, "Паровой охотник", "dangerous", "construct", "predator", 90, 14, ["industrial", "plains"], "Четвероногая паровая машина-охотник.",
		{"f": {"legs": 4, "len": 1.0, "chimney": true}, "body": Color(0.35, 0.32, 0.3), "metal": true, "glow": Color(1.0, 0.6, 0.2), "abil": ["pounce"], "res": {"lightning": -0.4}, "loot": [["scrap_alloy", 0.5]]}))
	L.append(K("electric_worm", 2, "Электрический червь", "dangerous", "worm", "ambush", 85, 13, ["industrial", "swamp"], "Червь, живущий в кабелях; бьёт током.",
		{"f": {"segments": 8, "girth": 0.22, "eyes": 2}, "body": Color(0.25, 0.3, 0.45), "glow": Color(0.5, 0.8, 1.0), "dtype": "lightning", "res": {"lightning": 0.8}, "abil": ["shock", "burrow"], "loot": [["power_cell", 0.3]]}))
	L.append(K("mech_hound", 2, "Механическая гончая", "common", "construct", "predator", 60, 10, ["industrial", "urban"], "Сторожевой механический пёс заводов.",
		{"f": {"legs": 4, "len": 0.8}, "body": Color(0.4, 0.4, 0.42), "metal": true, "glow": Color(1.0, 0.2, 0.15), "res": {"lightning": -0.5}, "speed": 1.3, "loot": [["gears", 0.5]]}))
	L.append(K("mine_mutant", 2, "Шахтный мутант", "dangerous", "giant", "predator", 110, 15, ["industrial", "cave"], "Шахтёр, изменённый рудничным газом. Сильный и злой.",
		{"f": {"width": 0.65, "hunch": 0.5, "arm": 1.15, "veins": true}, "body": Color(0.45, 0.42, 0.35), "glow": Color(0.6, 1.0, 0.3), "dtype": "blunt", "loot": [["mutagen", 0.4]]}))
	L.append(K("steel_spider", 2, "Стальной паук", "dangerous", "arach", "ambush", 85, 13, ["industrial"], "Паук из стальных балок; паутина из проволоки.",
		{"f": {"legs": 8, "abdomen": 0.9, "eyes": 4}, "body": Color(0.4, 0.42, 0.45), "metal": true, "glow": Color(1.0, 0.5, 0.1), "dtype": "pierce", "res": {"slash": 0.3, "lightning": -0.4}, "abil": ["web"], "loot": [["scrap_alloy", 0.5]]}))
	L.append(K("scout_automaton", 2, "Разведывательный автоматон", "common", "orb", "construct", 45, 8, ["industrial", "plains"], "Летающий шар-разведчик; поднимает тревогу.",
		{"f": {"core_r": 0.2, "shards": 4, "gears": true, "hover": 2.2}, "body": Color(0.5, 0.45, 0.35), "glow": Color(1.0, 0.8, 0.3), "dtype": "lightning", "proj": "spark", "res": {"lightning": -0.5}, "abil": ["howl"], "loot": [["gears", 0.4]]}))
	L.append(K("steam_golem", 2, "Паровой голем", "elite", "giant", "construct", 220, 22, ["industrial"], "Котёл на ногах. Выпускает пар, если подойти близко.",
		{"f": {"width": 0.9, "hunch": 0.1, "gears": 2, "plates": 2}, "body": Color(0.35, 0.33, 0.3), "metal": true, "glow": Color(1.0, 0.55, 0.2), "dtype": "blunt", "res": {"fire": 0.5, "lightning": -0.3}, "scale": 1.4, "abil": ["steam"], "loot": [["power_cell", 0.4]]}))
	L.append(K("electric_ghost", 2, "Электрический призрак", "dangerous", "orb", "magic", 65, 13, ["industrial", "anomaly"], "Сгусток тока с лицом. Проходит сквозь провода.",
		{"f": {"core_r": 0.28, "shards": 0, "ring": true}, "body": Color(0.5, 0.7, 1.0), "glow": Color(0.6, 0.85, 1.0), "dtype": "lightning", "spells": ["l_electric_spark", "l_chain_flash"], "res": {"lightning": 0.9, "slash": 0.5}, "loot": [["power_cell", 0.4]]}))
	L.append(K("toxic_slime", 2, "Токсичный слизень", "common", "blob", "territorial", 55, 9, ["industrial", "swamp"], "Слизь из промышленных отходов; оставляет ядовитый след.",
		{"f": {"squash": 0.75}, "body": Color(0.5, 0.75, 0.2), "glow": Color(0.7, 1.0, 0.2), "dtype": "poison", "abil": ["poison", "explode"], "loot": [["mutagen", 0.3]]}))
	L.append(K("drill_beetle", 2, "Буровой жук", "dangerous", "insect", "territorial", 90, 14, ["industrial", "cave"], "Жук с роговым буром; пробивает доски и щиты.",
		{"f": {"legs": 6, "abdomen": 1.0, "stinger": false, "eyes": 2}, "body": Color(0.3, 0.25, 0.2), "accent": Color(0.6, 0.5, 0.3), "dtype": "pierce", "res": {"slash": 0.3}, "abil": ["charge"], "loot": [["chitin", 0.5]]}))
	L.append(K("metal_scavenger", 2, "Металлический падальщик", "common", "quad", "herd", 50, 8, ["industrial", "plains"], "Звери, научившиеся грызть металл. Держатся стаями у свалок.",
		{"f": {"len": 1.0, "height": 0.45, "girth": 0.18, "spikes": 3, "plates": 2}, "body": Color(0.45, 0.4, 0.35), "accent": Color(0.55, 0.5, 0.48), "loot": [["scrap_alloy", 0.4]]}))
	L.append(K("factory_warden", 2, "Промышленный страж", "elite", "humanoid", "construct", 160, 20, ["industrial"], "Охранный автомат завода с пневматическим ружьём.",
		{"weapons": ["rifle_lever"], "ai": "ranged", "robot": true, "armor_kind": "robot", "body": Color(0.3, 0.32, 0.35), "res": {"lightning": -0.5, "pierce": 0.3}, "loot": [["power_cell", 0.4]]}))
	L.append(K("mech_scorpion", 2, "Механический скорпион", "dangerous", "insect", "ambush", 95, 15, ["industrial", "sand"], "Стальной скорпион с электрическим жалом.",
		{"f": {"legs": 6, "abdomen": 0.8, "eyes": 2}, "body": Color(0.45, 0.42, 0.38), "metal": true, "glow": Color(0.5, 0.8, 1.0), "dtype": "lightning", "abil": ["shock"], "res": {"lightning": 0.3}, "loot": [["scrap_alloy", 0.5]]}))
	L.append(K("coal_elemental", 2, "Угольный элементаль", "dangerous", "orb", "magic", 80, 14, ["industrial", "mountain"], "Тлеющий ком угля с вихрем искр.",
		{"f": {"core_r": 0.35, "shards": 7, "hover": 1.0}, "body": Color(0.15, 0.13, 0.12), "glow": Color(1.0, 0.4, 0.1), "dtype": "fire", "spells": ["f_ember"], "res": {"fire": 0.8, "ice": -0.5}, "loot": [["coal_core", 0.4]]}))
	L.append(K("overheated_automaton", 2, "Перегретый автоматон", "dangerous", "humanoid", "construct", 80, 14, ["industrial"], "Раскалённый автомат: взрывается при гибели.",
		{"weapons": ["hammer_war"], "robot": true, "armor_kind": "robot", "body": Color(0.6, 0.25, 0.12), "glow": Color(1.0, 0.5, 0.1), "dtype": "fire", "abil": ["explode"], "loot": [["power_cell", 0.3]]}))
	L.append(K("boiler_parasite", 2, "Котельный паразит", "common", "worm", "swarm", 35, 7, ["industrial"], "Мелкие черви, живущие в котлах и трубах.",
		{"f": {"segments": 5, "girth": 0.12}, "body": Color(0.6, 0.4, 0.3), "dtype": "fire", "abil": ["burrow"], "loot": [["coal_core", 0.1]]}))
	L.append(K("rotor_hunter", 2, "Роторный охотник", "dangerous", "orb", "predator", 70, 13, ["industrial", "plains"], "Летающая машина с режущими роторами.",
		{"f": {"core_r": 0.25, "shards": 4, "gears": true, "hover": 1.4}, "body": Color(0.4, 0.4, 0.42), "metal": true, "glow": Color(1.0, 0.3, 0.2), "res": {"lightning": -0.5}, "speed": 1.3, "loot": [["gears", 0.5]]}))
	L.append(K("slag_giant", 2, "Шлаковый исполин", "miniboss", "giant", "territorial", 260, 28, ["industrial"], "Исполин из застывшего шлака; раскалённые трещины по телу.",
		{"f": {"width": 1.0, "hunch": 0.3, "rocky": true, "veins": true}, "body": Color(0.25, 0.22, 0.2), "glow": Color(1.0, 0.45, 0.1), "dtype": "fire", "res": {"fire": 0.7, "ice": -0.4}, "scale": 1.6, "abil": ["slam"], "loot": [["coal_core", 0.8]]}))
	L.append(K("energy_clot", 2, "Аномальный энергетический сгусток", "dangerous", "orb", "magic", 60, 13, ["anomaly", "industrial"], "Сгусток неустойчивой энергии; взрывается, если его перегрузить.",
		{"f": {"core_r": 0.3, "shards": 0, "ring": true, "hover": 1.5}, "body": Color(0.6, 0.9, 1.0), "glow": Color(0.5, 0.9, 1.0), "dtype": "energy", "abil": ["explode"], "res": {"energy": 0.8}, "loot": [["power_cell", 0.5]]}))

static func _modern(L: Array) -> void:
	L.append(K("lab_mutant", 3, "Лабораторный мутант", "common", "giant", "predator", 80, 12, ["lab", "urban"], "Подопытный, сбежавший из лаборатории. Сильный, не чувствует боли.",
		{"f": {"width": 0.55, "hunch": 0.35, "veins": true, "arm": 1.1}, "body": Color(0.6, 0.5, 0.48), "glow": Color(0.6, 1.0, 0.4), "dtype": "blunt", "loot": [["mutagen", 0.5]]}))
	L.append(K("infected_hunter", 3, "Заражённый охотник", "dangerous", "humanoid", "predator", 85, 14, ["urban", "forest"], "Охотник, заражённый вирусом; бегает быстро и кусает.",
		{"weapons": ["dagger_iron"], "armor_kind": "leather", "body": Color(0.35, 0.4, 0.3), "speed": 1.25, "abil": ["poison"], "loot": [["mutagen", 0.3]]}))
	L.append(K("underground_parasite", 3, "Подземный паразит", "common", "worm", "ambush", 55, 9, ["urban", "cave", "lab"], "Паразит коммуникаций, вылезает из люков.",
		{"f": {"segments": 7, "girth": 0.2, "eyes": 0, "spikes": 1}, "body": Color(0.6, 0.55, 0.5), "abil": ["burrow", "poison"], "loot": [["mutagen", 0.2]]}))
	L.append(K("exp_predator", 3, "Экспериментальный хищник", "elite", "quad", "predator", 170, 20, ["lab", "forest"], "Выведенный в лаборатории хищник с бронепластинами.",
		{"f": {"len": 1.2, "height": 0.7, "girth": 0.26, "plates": 3, "spikes": 4, "horns": 2, "tail": 0.8}, "body": Color(0.3, 0.32, 0.35), "glow": Color(1.0, 0.3, 0.2), "abil": ["pounce"], "speed": 1.3, "scale": 1.2, "loot": [["mutagen", 0.6]]}))
	L.append(K("recon_robot", 3, "Разведывательный робот", "common", "construct", "construct", 55, 9, ["urban", "lab"], "Шагающий робот наблюдения; передаёт координаты.",
		{"f": {"legs": 2, "len": 0.5}, "body": Color(0.55, 0.58, 0.6), "metal": true, "glow": Color(0.3, 0.8, 1.0), "proj": "bullet", "res": {"lightning": -0.5}, "abil": ["howl"], "loot": [["circuits", 0.4]]}))
	L.append(K("battle_drone", 3, "Боевой дрон", "dangerous", "orb", "construct", 60, 12, ["urban", "lab", "plains"], "Квадрокоптер с пулемётом.",
		{"f": {"core_r": 0.2, "shards": 4, "gears": true, "hover": 2.4}, "body": Color(0.25, 0.27, 0.3), "metal": true, "glow": Color(1.0, 0.25, 0.2), "dtype": "pierce", "proj": "bullet", "res": {"lightning": -0.6}, "loot": [["circuits", 0.5]]}))
	L.append(K("shadow_operative", 3, "Теневой оперативник", "elite", "humanoid", "intelligent", 120, 18, ["urban", "lab"], "Боец спецподразделения: маскировка и короткие очереди.",
		{"weapons": ["smg"], "ai": "ranged", "armor_kind": "vest", "body": Color(0.1, 0.1, 0.12), "hat": "visor", "loot": [["circuits", 0.4], ["coin_pouch", 0.4]]}))
	L.append(K("electromech_guard", 3, "Электромеханический страж", "elite", "giant", "construct", 190, 20, ["lab"], "Охранный экзоскелет с электрошоком.",
		{"f": {"width": 0.7, "hunch": 0.0, "gears": 2, "plates": 2}, "body": Color(0.5, 0.52, 0.55), "metal": true, "glow": Color(0.4, 0.8, 1.0), "dtype": "lightning", "abil": ["shock"], "scale": 1.25, "loot": [["power_cell", 0.5]]}))
	L.append(K("bio_golem", 3, "Биологический голем", "elite", "giant", "territorial", 230, 22, ["lab"], "Масса выращенной плоти; регенерирует.",
		{"f": {"width": 0.95, "hunch": 0.4, "veins": true}, "body": Color(0.65, 0.4, 0.4), "glow": Color(1.0, 0.3, 0.3), "dtype": "blunt", "res": {"fire": -0.4}, "abil": ["regen", "slam"], "scale": 1.4, "loot": [["mutagen", 0.7]]}))
	L.append(K("anomaly_slime", 3, "Аномальный слизень", "common", "blob", "territorial", 55, 9, ["anomaly", "lab"], "Слизь, мерцающая между измерениями.",
		{"f": {"squash": 0.9, "crystals": 3}, "body": Color(0.5, 0.4, 0.9), "glow": Color(0.7, 0.5, 1.0), "dtype": "time", "abil": ["blink"], "loot": [["arcane_dust", 0.3]]}))
	L.append(K("armored_mutant", 3, "Бронированный мутант", "dangerous", "giant", "predator", 130, 16, ["lab", "urban"], "Мутант, обросший костяными пластинами.",
		{"f": {"width": 0.7, "hunch": 0.3, "plates": 3, "spikes": 3}, "body": Color(0.5, 0.45, 0.4), "accent": Color(0.85, 0.82, 0.75), "res": {"slash": 0.4, "pierce": 0.3}, "abil": ["charge"], "loot": [["chitin", 0.5]]}))
	L.append(K("escaped_experiment", 3, "Сбежавший эксперимент", "dangerous", "arach", "ambush", 90, 14, ["lab", "urban"], "Многоногое существо из пробирки.",
		{"f": {"legs": 6, "abdomen": 1.2, "markings": true, "eyes": 3}, "body": Color(0.7, 0.65, 0.6), "glow": Color(0.6, 1.0, 0.4), "dtype": "poison", "abil": ["poison", "web"], "loot": [["mutagen", 0.5]]}))
	L.append(K("underground_chimera", 3, "Подземная химера", "elite", "drake", "predator", 200, 22, ["cave", "urban"], "Слепая химера коллекторов с костяными крыльями.",
		{"f": {"len": 1.3, "height": 0.6, "girth": 0.27, "neck": 0.35, "tail": 0.8, "eyes": 0, "spikes": 3}, "body": Color(0.55, 0.5, 0.45), "abil": ["pounce", "poison"], "scale": 1.2, "loot": [["mutagen", 0.6]]}))
	L.append(K("energy_parasite", 3, "Энергетический паразит", "common", "orb", "swarm", 35, 7, ["lab", "anomaly"], "Мелкие сгустки, пьющие электричество.",
		{"f": {"core_r": 0.12, "shards": 3, "hover": 1.1}, "body": Color(0.5, 0.9, 1.0), "glow": Color(0.5, 0.9, 1.0), "dtype": "energy", "abil": ["drain"], "loot": [["power_cell", 0.1]]}))
	L.append(K("toxic_hunter", 3, "Токсичный охотник", "dangerous", "quad", "predator", 85, 14, ["swamp", "urban"], "Хищник ядовитых болот у химзаводов.",
		{"f": {"len": 1.1, "height": 0.55, "girth": 0.2, "spikes": 5, "tail": 0.7}, "body": Color(0.4, 0.5, 0.2), "glow": Color(0.8, 1.0, 0.2), "dtype": "poison", "abil": ["poison", "pounce"], "loot": [["venom_gland", 0.5]]}))
	L.append(K("urban_mech_beast", 3, "Городской механический зверь", "dangerous", "construct", "territorial", 110, 16, ["urban"], "Сбежавший военный робот-зверь.",
		{"f": {"legs": 4, "len": 1.1, "gears": 2}, "body": Color(0.35, 0.38, 0.32), "metal": true, "glow": Color(1.0, 0.6, 0.2), "res": {"pierce": 0.3, "lightning": -0.4}, "abil": ["charge"], "loot": [["circuits", 0.5]]}))
	L.append(K("artificial_soldier", 3, "Искусственный солдат", "dangerous", "humanoid", "intelligent", 100, 15, ["lab", "urban"], "Выращенный солдат с карабином.",
		{"weapons": ["carbine"], "ai": "ranged", "armor_kind": "vest", "body": Color(0.3, 0.35, 0.3), "hat": "visor", "loot": [["circuits", 0.3]]}))
	L.append(K("unstable_clone", 3, "Нестабильный клон", "common", "humanoid", "predator", 60, 11, ["lab"], "Клон, распадающийся на глазах. Взрывается при смерти.",
		{"weapons": ["dagger_iron"], "armor_kind": "leather", "body": Color(0.8, 0.8, 0.85), "glow": Color(0.6, 1.0, 0.9), "abil": ["explode"], "loot": [["mutagen", 0.3]]}))
	L.append(K("lab_giant", 3, "Лабораторный исполин", "miniboss", "giant", "territorial", 280, 26, ["lab"], "Огромный подопытный в лохмотьях смирительной брони.",
		{"f": {"width": 1.0, "hunch": 0.45, "veins": true, "plates": 2, "arm": 1.3}, "body": Color(0.6, 0.48, 0.45), "glow": Color(0.6, 1.0, 0.4), "dtype": "blunt", "scale": 1.7, "abil": ["slam", "charge"], "loot": [["mutagen", 0.9]]}))
	L.append(K("space_stalker", 3, "Пространственный преследователь", "elite", "humanoid", "predator", 130, 18, ["anomaly", "lab"], "Существо, шагающее через короткие разломы.",
		{"weapons": ["blade_energy"], "armor_kind": "android", "body": Color(0.2, 0.25, 0.3), "glow": Color(0.4, 1.0, 0.9), "abil": ["blink"], "loot": [["arcane_dust", 0.5]]}))

static func _future(L: Array) -> void:
	L.append(K("nano_swarm", 4, "Нанорой", "common", "orb", "swarm", 40, 8, ["anomaly", "urban"], "Облако нанитов; режет и разбирает металл.",
		{"f": {"core_r": 0.1, "shards": 12, "hover": 1.2}, "body": Color(0.6, 0.62, 0.65), "metal": true, "glow": Color(0.5, 0.9, 1.0), "res": {"slash": 0.6, "pierce": 0.6, "lightning": -0.6}, "loot": [["nanite_dust", 0.4]]}))
	L.append(K("phase_spider", 4, "Фазовый паук", "dangerous", "arach", "ambush", 90, 14, ["anomaly"], "Паук, мерцающий между фазами пространства.",
		{"f": {"legs": 8, "abdomen": 0.9, "eyes": 8, "markings": true}, "body": Color(0.25, 0.3, 0.45), "glow": Color(0.4, 1.0, 0.9), "dtype": "energy", "abil": ["blink", "web"], "loot": [["phase_crystal", 0.4]]}))
	L.append(K("quantum_predator", 4, "Квантовый хищник", "elite", "quad", "predator", 180, 22, ["anomaly", "plains"], "Хищник, присутствующий в двух местах сразу.",
		{"f": {"len": 1.2, "height": 0.7, "girth": 0.24, "crystals": 4, "tail": 0.9, "horns": 2}, "body": Color(0.2, 0.22, 0.3), "glow": Color(0.5, 0.8, 1.0), "dtype": "energy", "abil": ["blink", "pounce"], "speed": 1.3, "loot": [["phase_crystal", 0.6]]}))
	L.append(K("synth_warrior", 4, "Синтетический воин", "dangerous", "humanoid", "intelligent", 110, 17, ["urban", "anomaly"], "Боевой синтетик с энергоклинком.",
		{"weapons": ["blade_energy"], "robot": true, "armor_kind": "android", "body": Color(0.85, 0.85, 0.9), "glow": Color(0.4, 0.9, 1.0), "loot": [["nanite_dust", 0.4]]}))
	L.append(K("energy_worm", 4, "Энергетический червь", "dangerous", "worm", "ambush", 90, 14, ["anomaly", "sand"], "Червь из чистой энергии; ныряет в землю, оставляя светящийся след.",
		{"f": {"segments": 9, "girth": 0.25, "eyes": 0}, "body": Color(0.4, 0.8, 1.0), "accent": Color(0.6, 0.95, 1.0), "glow": Color(0.5, 0.9, 1.0), "dtype": "energy", "abil": ["burrow", "shock"], "loot": [["power_cell", 0.5]]}))
	L.append(K("chrono_parasite", 4, "Хронологический паразит", "common", "flyer", "swarm", 35, 7, ["anomaly"], "Мелкий летающий паразит, крадущий секунды.",
		{"f": {"span": 0.4, "len": 0.2, "hover": 1.6}, "body": Color(0.4, 1.0, 0.85), "glow": Color(0.4, 1.0, 0.85), "dtype": "time", "abil": ["drain"], "loot": [["chrono_shard", 0.2]]}))
	L.append(K("gravity_hunter", 4, "Гравитационный охотник", "elite", "construct", "predator", 170, 20, ["anomaly", "plains"], "Машина, притягивающая жертву гравитационным лучом.",
		{"f": {"legs": 6, "len": 1.0, "gears": 2}, "body": Color(0.3, 0.3, 0.38), "metal": true, "glow": Color(0.7, 0.5, 1.0), "dtype": "energy", "abil": ["pull"], "loot": [["power_cell", 0.5]]}))
	L.append(K("plasma_guard", 4, "Плазменный страж", "elite", "giant", "construct", 200, 22, ["urban", "anomaly"], "Страж с плазменным ядром в груди.",
		{"f": {"width": 0.75, "hunch": 0.0, "plates": 2, "runes": true}, "body": Color(0.8, 0.82, 0.85), "metal": true, "glow": Color(1.0, 0.5, 0.2), "dtype": "fire", "proj": "plasma", "scale": 1.3, "loot": [["power_cell", 0.6]]}))
	L.append(K("artificial_chimera", 4, "Искусственная химера", "elite", "drake", "predator", 200, 22, ["anomaly"], "Синтезированная химера с энергокрыльями.",
		{"f": {"len": 1.3, "height": 0.7, "girth": 0.25, "neck": 0.4, "tail": 1.0, "crystals": 3}, "body": Color(0.85, 0.85, 0.9), "accent": Color(0.4, 0.8, 1.0), "glow": Color(0.4, 0.9, 1.0), "dtype": "energy", "abil": ["breath", "pounce"], "scale": 1.2, "loot": [["nanite_dust", 0.6]]}))
	L.append(K("space_slime", 4, "Пространственный слизень", "common", "blob", "territorial", 55, 9, ["anomaly"], "Прозрачная слизь, сворачивающая пространство вокруг.",
		{"f": {"squash": 0.95, "crystals": 4}, "body": Color(0.6, 0.8, 1.0), "glow": Color(0.6, 0.85, 1.0), "dtype": "time", "abil": ["pull"], "loot": [["phase_crystal", 0.2]]}))
	L.append(K("cyber_beast", 4, "Кибернетический зверь", "dangerous", "quad", "predator", 100, 15, ["urban", "plains"], "Зверь с имплантами и стальной челюстью.",
		{"f": {"len": 1.1, "height": 0.62, "girth": 0.22, "plates": 2, "eyes": 1}, "body": Color(0.35, 0.33, 0.32), "accent": Color(0.7, 0.72, 0.75), "glow": Color(1.0, 0.2, 0.2), "abil": ["pounce"], "loot": [["nanite_dust", 0.3]]}))
	L.append(K("neural_parasite", 4, "Нейронный паразит", "dangerous", "insect", "ambush", 70, 12, ["anomaly", "urban"], "Паразит, путающий мысли: жертва бьёт мимо.",
		{"f": {"legs": 6, "abdomen": 0.6, "eyes": 2}, "body": Color(0.7, 0.5, 0.8), "glow": Color(1.0, 0.5, 1.0), "dtype": "dark", "abil": ["blind"], "loot": [["arcane_dust", 0.4]]}))
	L.append(K("quantum_golem", 4, "Квантовый голем", "elite", "giant", "construct", 230, 23, ["anomaly"], "Голем из кристаллической решётки, расщепляющий удары.",
		{"f": {"width": 0.8, "hunch": 0.1, "crystals": 8, "runes": true}, "body": Color(0.3, 0.35, 0.5), "glow": Color(0.5, 0.8, 1.0), "dtype": "energy", "res": {"slash": 0.3, "energy": 0.6}, "scale": 1.4, "loot": [["phase_crystal", 0.7]]}))
	L.append(K("chrono_double", 4, "Хронологический двойник", "dangerous", "humanoid", "intelligent", 90, 15, ["anomaly"], "Ваша же тень из соседней секунды.",
		{"weapons": ["blade_energy"], "armor_kind": "android", "body": Color(0.4, 1.0, 0.85), "glow": Color(0.4, 1.0, 0.85), "abil": ["blink"], "loot": [["chrono_shard", 0.4]]}))
	L.append(K("astral_stalker", 4, "Астральный преследователь", "elite", "flyer", "predator", 150, 20, ["anomaly"], "Крылатое существо звёздной пустоты.",
		{"f": {"span": 1.3, "len": 0.7, "hover": 2.4, "feathers": true}, "body": Color(0.2, 0.15, 0.35), "accent": Color(0.6, 0.4, 1.0), "glow": Color(0.8, 0.6, 1.0), "dtype": "dark", "abil": ["dive", "blink"], "loot": [["arcane_dust", 0.6]]}))
	L.append(K("nanite_scorpion", 4, "Нанитовый скорпион", "dangerous", "insect", "ambush", 95, 15, ["urban", "sand"], "Скорпион, собранный роем нанитов.",
		{"f": {"legs": 6, "abdomen": 0.8, "eyes": 2}, "body": Color(0.6, 0.62, 0.65), "metal": true, "glow": Color(0.5, 0.9, 1.0), "dtype": "energy", "abil": ["shock"], "res": {"slash": 0.3}, "loot": [["nanite_dust", 0.5]]}))
	L.append(K("synth_harpy", 4, "Синтетическая гарпия", "dangerous", "flyer", "predator", 70, 13, ["urban", "mountain"], "Летающий синтетик с режущими крыльями.",
		{"f": {"span": 1.0, "len": 0.45, "hover": 2.3}, "body": Color(0.85, 0.85, 0.9), "accent": Color(0.3, 0.35, 0.4), "metal": true, "glow": Color(0.4, 0.9, 1.0), "dtype": "slash", "abil": ["dive"], "loot": [["nanite_dust", 0.4]]}))
	L.append(K("phase_giant", 4, "Фазовый исполин", "miniboss", "giant", "territorial", 280, 28, ["anomaly"], "Великан, полупрозрачный от фазовых сдвигов.",
		{"f": {"width": 1.0, "hunch": 0.2, "crystals": 6}, "body": Color(0.35, 0.45, 0.7), "glow": Color(0.4, 1.0, 0.9), "dtype": "energy", "scale": 1.7, "abil": ["blink", "slam"], "loot": [["phase_crystal", 0.9]]}))
	L.append(K("dimension_parasite", 4, "Паразит измерений", "elite", "worm", "ambush", 170, 20, ["anomaly"], "Червь, прогрызающий дыры между мирами.",
		{"f": {"segments": 11, "girth": 0.32, "eyes": 6, "spikes": 1}, "body": Color(0.3, 0.2, 0.4), "accent": Color(0.6, 0.3, 0.8), "glow": Color(0.8, 0.4, 1.0), "dtype": "dark", "abil": ["burrow", "blink"], "loot": [["arcane_dust", 0.6]]}))
	L.append(K("lesser_time_eater", 4, "Малый пожиратель времени", "miniboss", "drake", "magic", 260, 26, ["anomaly"], "Детёныш Пожирателя Эпох. Ест секунды и роняет их осколки.",
		{"f": {"len": 1.4, "height": 0.7, "girth": 0.3, "neck": 0.5, "tail": 1.1, "crystals": 5, "horns": 4}, "body": Color(0.2, 0.3, 0.32), "glow": Color(0.4, 1.0, 0.85), "dtype": "time", "scale": 1.5, "spells": ["t_delay_rune", "t_coord_rupture"], "abil": ["blink"], "loot": [["chrono_shard", 1.0]]}))
