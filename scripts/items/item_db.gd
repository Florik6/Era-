class_name ItemDB
## Item base definitions, unique items, modifiers, loot tables and the item factory.
## Item instances are plain Dictionaries so they serialize directly into saves.

const RARITY_NAMES := ["Обычный", "Необычный", "Редкий", "Эпический", "Легендарный", "Мифический"]
const RARITY_COLORS := [Color(0.72, 0.72, 0.72), Color(0.35, 0.85, 0.35), Color(0.3, 0.55, 1.0),
	Color(0.7, 0.35, 0.95), Color(1.0, 0.78, 0.2), Color(0.95, 0.12, 0.22)]
const RARITY_MULT := [1.0, 1.15, 1.35, 1.6, 2.0, 2.6]
# Weight tables (percent). "normal" follows the design table: 58/25/12/4/0.9/0.1
const TABLES := {
	"normal": [58.0, 25.0, 12.0, 4.0, 0.9, 0.1],
	"chest": [40.0, 32.0, 18.0, 7.5, 2.2, 0.3],
	"elite": [20.0, 35.0, 28.0, 12.0, 4.5, 0.5],
	"boss": [0.0, 0.0, 30.0, 45.0, 21.0, 4.0],
	"event": [10.0, 30.0, 33.0, 19.0, 7.0, 1.0],
	"rift": [5.0, 25.0, 35.0, 24.0, 9.5, 1.5],
}

const SLOTS := ["main", "off", "head", "body", "hands", "feet", "ring", "amulet", "module"]
const SLOT_NAMES := {"main": "Оружие", "off": "Доп. рука", "head": "Шлем", "body": "Броня", "hands": "Перчатки",
	"feet": "Обувь", "ring": "Кольцо", "amulet": "Амулет", "module": "Модуль/Имплант", "use": "Расходник", "mat": "Материал"}
const CAT_NAMES := {"sword": "Мечи", "dagger": "Кинжалы", "spear": "Древковое", "heavy": "Тяжёлое оружие", "bow": "Луки и арбалеты",
	"firearm": "Огнестрельное", "staff": "Посохи и фокусы", "unarmed": "Кулаки"}
const DTYPE_NAMES := {"slash": "рубящий", "pierce": "колющий", "blunt": "дробящий", "fire": "огонь", "ice": "лёд",
	"lightning": "молния", "dark": "тьма", "energy": "энергия", "time": "время"}

# ---------------------------------------------------------------- bases
# Weapons: cat, dmg, spd (attacks/s), range (m), dtype, model, two_h, proj, mag, reload, spread
const BASES := {
	# ===== Era 0 — Medieval
	"sword_iron": {"name": "Железный меч", "era": 0, "slot": "main", "cat": "sword", "dmg": 11.0, "spd": 1.5, "range": 2.3, "dtype": "slash", "model": "sword", "value": 20},
	"sword_steel": {"name": "Стальной меч", "era": 0, "slot": "main", "cat": "sword", "dmg": 15.0, "spd": 1.5, "range": 2.4, "dtype": "slash", "model": "sword", "value": 60},
	"dagger_iron": {"name": "Нож разбойника", "era": 0, "slot": "main", "cat": "dagger", "dmg": 7.0, "spd": 2.6, "range": 1.7, "dtype": "pierce", "model": "dagger", "value": 15},
	"dagger_curved": {"name": "Кривой кинжал", "era": 0, "slot": "main", "cat": "dagger", "dmg": 10.0, "spd": 2.6, "range": 1.8, "dtype": "slash", "model": "dagger", "value": 50},
	"spear_iron": {"name": "Копьё", "era": 0, "slot": "main", "cat": "spear", "dmg": 13.0, "spd": 1.2, "range": 3.4, "dtype": "pierce", "model": "spear", "two_h": true, "value": 30},
	"axe_hand": {"name": "Топор лесоруба", "era": 0, "slot": "main", "cat": "heavy", "dmg": 14.0, "spd": 1.1, "range": 2.2, "dtype": "slash", "model": "axe", "value": 18},
	"axe_battle": {"name": "Боевая секира", "era": 0, "slot": "main", "cat": "heavy", "dmg": 22.0, "spd": 0.8, "range": 2.6, "dtype": "slash", "model": "greataxe", "two_h": true, "value": 70},
	"hammer_war": {"name": "Боевой молот", "era": 0, "slot": "main", "cat": "heavy", "dmg": 24.0, "spd": 0.75, "range": 2.5, "dtype": "blunt", "model": "hammer", "two_h": true, "value": 75},
	"greatsword": {"name": "Двуручный меч", "era": 0, "slot": "main", "cat": "heavy", "dmg": 26.0, "spd": 0.8, "range": 2.9, "dtype": "slash", "model": "greatsword", "two_h": true, "value": 90},
	"bow_short": {"name": "Короткий лук", "era": 0, "slot": "main", "cat": "bow", "dmg": 10.0, "spd": 1.3, "range": 22.0, "dtype": "pierce", "model": "bow", "two_h": true, "proj": "arrow", "value": 25},
	"bow_long": {"name": "Длинный лук", "era": 0, "slot": "main", "cat": "bow", "dmg": 15.0, "spd": 0.95, "range": 30.0, "dtype": "pierce", "model": "longbow", "two_h": true, "proj": "arrow", "value": 65},
	"crossbow_light": {"name": "Лёгкий арбалет", "era": 0, "slot": "main", "cat": "bow", "dmg": 19.0, "spd": 0.7, "range": 26.0, "dtype": "pierce", "model": "crossbow", "two_h": true, "proj": "bolt", "value": 60},
	"staff_oak": {"name": "Дубовый посох", "era": 0, "slot": "main", "cat": "staff", "dmg": 9.0, "spd": 1.2, "range": 20.0, "dtype": "fire", "model": "staff", "two_h": true, "proj": "magic", "mana": 20, "value": 30},
	"shield_wood": {"name": "Деревянный щит", "era": 0, "slot": "off", "armor": 4.0, "block": 0.6, "model": "shield_round", "value": 12},
	"shield_kite": {"name": "Каплевидный щит", "era": 0, "slot": "off", "armor": 8.0, "block": 0.75, "model": "shield_kite", "value": 55},
	"grimoire": {"name": "Гримуар", "era": 0, "slot": "off", "spell": 0.12, "mana": 25, "model": "book", "value": 40},
	"armor_cloth": {"name": "Стёганка", "era": 0, "slot": "body", "armor": 3.0, "hp": 10, "model": "cloth", "value": 10},
	"armor_leather": {"name": "Кожаная куртка", "era": 0, "slot": "body", "armor": 6.0, "hp": 15, "model": "leather", "value": 30},
	"armor_chain": {"name": "Кольчуга", "era": 0, "slot": "body", "armor": 11.0, "hp": 25, "model": "chain", "value": 60},
	"armor_plate": {"name": "Латный доспех", "era": 0, "slot": "body", "armor": 17.0, "hp": 40, "model": "plate", "speed": -0.06, "value": 120},
	"robe_mage": {"name": "Мантия мага", "era": 0, "slot": "body", "armor": 3.0, "mana": 40, "spell": 0.1, "model": "robe", "value": 50},
	"helm_hood": {"name": "Капюшон", "era": 0, "slot": "head", "armor": 1.5, "model": "hood", "value": 8},
	"helm_kettle": {"name": "Шапель", "era": 0, "slot": "head", "armor": 4.0, "model": "kettle", "value": 30},
	"helm_great": {"name": "Топфхельм", "era": 0, "slot": "head", "armor": 7.0, "hp": 10, "model": "greathelm", "value": 70},
	"gloves_leather": {"name": "Кожаные перчатки", "era": 0, "slot": "hands", "armor": 1.5, "crit": 0.02, "model": "gloves", "value": 10},
	"gauntlets_steel": {"name": "Латные рукавицы", "era": 0, "slot": "hands", "armor": 4.0, "model": "gauntlets", "value": 40},
	"boots_leather": {"name": "Кожаные сапоги", "era": 0, "slot": "feet", "armor": 1.5, "speed": 0.03, "model": "boots", "value": 10},
	"boots_steel": {"name": "Латные сапоги", "era": 0, "slot": "feet", "armor": 4.0, "model": "sabatons", "value": 40},
	"ring_copper": {"name": "Медное кольцо", "era": 0, "slot": "ring", "crit": 0.03, "model": "ring", "value": 25},
	"amulet_bone": {"name": "Костяной амулет", "era": 0, "slot": "amulet", "mana": 15, "hp": 10, "model": "amulet", "value": 30},
	# ===== Era 1 — Renaissance
	"rapier": {"name": "Рапира", "era": 1, "slot": "main", "cat": "sword", "dmg": 19.0, "spd": 1.9, "range": 2.6, "dtype": "pierce", "model": "rapier", "value": 90},
	"saber": {"name": "Абордажная сабля", "era": 1, "slot": "main", "cat": "sword", "dmg": 21.0, "spd": 1.6, "range": 2.4, "dtype": "slash", "model": "saber", "value": 80},
	"halberd": {"name": "Алебарда", "era": 1, "slot": "main", "cat": "spear", "dmg": 28.0, "spd": 0.9, "range": 3.6, "dtype": "slash", "model": "halberd", "two_h": true, "value": 110},
	"axe_boarding": {"name": "Абордажный топор", "era": 1, "slot": "main", "cat": "heavy", "dmg": 27.0, "spd": 1.0, "range": 2.3, "dtype": "slash", "model": "axe", "value": 85},
	"musket": {"name": "Мушкет", "era": 1, "slot": "main", "cat": "firearm", "dmg": 48.0, "spd": 0.6, "range": 30.0, "dtype": "pierce", "model": "musket", "two_h": true, "proj": "bullet", "mag": 1, "reload": 2.2, "spread": 3.0, "value": 140},
	"pistol_wheellock": {"name": "Колесцовый пистоль", "era": 1, "slot": "main", "cat": "firearm", "dmg": 30.0, "spd": 0.9, "range": 18.0, "dtype": "pierce", "model": "pistol_old", "proj": "bullet", "mag": 2, "reload": 1.6, "spread": 5.0, "value": 100},
	"crossbow_heavy": {"name": "Тяжёлый арбалет", "era": 1, "slot": "main", "cat": "bow", "dmg": 32.0, "spd": 0.6, "range": 30.0, "dtype": "pierce", "model": "crossbow", "two_h": true, "proj": "bolt", "value": 110},
	"staff_alchemical": {"name": "Алхимический жезл", "era": 1, "slot": "main", "cat": "staff", "dmg": 17.0, "spd": 1.25, "range": 22.0, "dtype": "fire", "model": "staff_alch", "two_h": true, "proj": "magic", "mana": 35, "value": 100},
	"armor_doublet": {"name": "Дублет фехтовальщика", "era": 1, "slot": "body", "armor": 10.0, "hp": 30, "speed": 0.03, "model": "leather", "value": 70},
	"armor_cuirass": {"name": "Кираса", "era": 1, "slot": "body", "armor": 22.0, "hp": 45, "model": "plate", "value": 140},
	"helm_morion": {"name": "Морион", "era": 1, "slot": "head", "armor": 8.0, "model": "morion", "value": 60},
	"hat_feather": {"name": "Шляпа с пером", "era": 1, "slot": "head", "armor": 3.0, "crit": 0.04, "model": "hat", "value": 55},
	"gloves_duelist": {"name": "Перчатки дуэлянта", "era": 1, "slot": "hands", "armor": 3.0, "aspd": 0.06, "model": "gloves", "value": 50},
	"boots_riding": {"name": "Ботфорты", "era": 1, "slot": "feet", "armor": 3.0, "speed": 0.05, "model": "boots", "value": 50},
	"ring_gold": {"name": "Золотой перстень", "era": 1, "slot": "ring", "crit": 0.05, "mana": 15, "model": "ring", "value": 80},
	"amulet_alch": {"name": "Алхимический медальон", "era": 1, "slot": "amulet", "res_fire": 0.15, "res_ice": 0.15, "hp": 20, "model": "amulet", "value": 80},
	# ===== Era 2 — Industrial
	"revolver": {"name": "Револьвер", "era": 2, "slot": "main", "cat": "firearm", "dmg": 34.0, "spd": 2.0, "range": 22.0, "dtype": "pierce", "model": "revolver", "proj": "bullet", "mag": 6, "reload": 1.8, "spread": 3.5, "value": 150},
	"rifle_lever": {"name": "Рычажная винтовка", "era": 2, "slot": "main", "cat": "firearm", "dmg": 52.0, "spd": 1.2, "range": 34.0, "dtype": "pierce", "model": "rifle", "two_h": true, "proj": "bullet", "mag": 8, "reload": 2.4, "spread": 1.5, "value": 190},
	"shotgun_double": {"name": "Двустволка", "era": 2, "slot": "main", "cat": "firearm", "dmg": 16.0, "spd": 1.3, "range": 12.0, "dtype": "pierce", "model": "shotgun", "two_h": true, "proj": "pellet", "pellets": 7, "mag": 2, "reload": 2.0, "spread": 14.0, "value": 160},
	"saber_cavalry": {"name": "Кавалерийская сабля", "era": 2, "slot": "main", "cat": "sword", "dmg": 32.0, "spd": 1.6, "range": 2.5, "dtype": "slash", "model": "saber", "value": 130},
	"knife_trench": {"name": "Окопный нож", "era": 2, "slot": "main", "cat": "dagger", "dmg": 24.0, "spd": 2.7, "range": 1.8, "dtype": "pierce", "model": "dagger", "value": 110},
	"steam_hammer": {"name": "Паровой молот", "era": 2, "slot": "main", "cat": "heavy", "dmg": 55.0, "spd": 0.7, "range": 2.8, "dtype": "blunt", "model": "steam_hammer", "two_h": true, "value": 220},
	"axe_fire": {"name": "Пожарный топор", "era": 2, "slot": "main", "cat": "heavy", "dmg": 40.0, "spd": 1.0, "range": 2.4, "dtype": "slash", "model": "axe", "value": 140},
	"tesla_gun": {"name": "Тесла-излучатель", "era": 2, "slot": "main", "cat": "firearm", "dmg": 26.0, "spd": 2.2, "range": 16.0, "dtype": "lightning", "model": "tesla_gun", "two_h": true, "proj": "spark", "mag": 12, "reload": 2.2, "spread": 4.0, "value": 230},
	"tesla_staff": {"name": "Электрический жезл", "era": 2, "slot": "main", "cat": "staff", "dmg": 28.0, "spd": 1.3, "range": 22.0, "dtype": "lightning", "model": "staff_tech", "two_h": true, "proj": "magic", "mana": 45, "value": 200},
	"armor_coat": {"name": "Кожаный плащ", "era": 2, "slot": "body", "armor": 16.0, "hp": 45, "speed": 0.03, "model": "coat", "value": 120},
	"armor_steam": {"name": "Паровой бронекостюм", "era": 2, "slot": "body", "armor": 34.0, "hp": 80, "speed": -0.05, "model": "steam_suit", "value": 300},
	"helm_pith": {"name": "Пробковый шлем", "era": 2, "slot": "head", "armor": 9.0, "model": "pith", "value": 80},
	"goggles": {"name": "Лётные очки", "era": 2, "slot": "head", "armor": 5.0, "crit": 0.05, "model": "goggles", "value": 90},
	"gloves_work": {"name": "Рабочие рукавицы", "era": 2, "slot": "hands", "armor": 6.0, "model": "gauntlets", "value": 60},
	"boots_hob": {"name": "Подкованные ботинки", "era": 2, "slot": "feet", "armor": 6.0, "speed": 0.03, "model": "boots", "value": 60},
	"module_steam": {"name": "Паровой усилитель", "era": 2, "slot": "module", "dmg_pct": 0.08, "armor": 5.0, "model": "module", "value": 160},
	# ===== Era 3 — Modern
	"pistol_modern": {"name": "Пистолет", "era": 3, "slot": "main", "cat": "firearm", "dmg": 38.0, "spd": 3.0, "range": 24.0, "dtype": "pierce", "model": "pistol", "proj": "bullet", "mag": 15, "reload": 1.4, "spread": 2.5, "value": 200},
	"carbine": {"name": "Карабин", "era": 3, "slot": "main", "cat": "firearm", "dmg": 40.0, "spd": 5.5, "range": 32.0, "dtype": "pierce", "model": "carbine", "two_h": true, "proj": "bullet", "mag": 30, "reload": 2.2, "spread": 3.0, "value": 320},
	"shotgun": {"name": "Помповый дробовик", "era": 3, "slot": "main", "cat": "firearm", "dmg": 24.0, "spd": 1.4, "range": 13.0, "dtype": "pierce", "model": "shotgun", "two_h": true, "proj": "pellet", "pellets": 8, "mag": 6, "reload": 2.6, "spread": 13.0, "value": 280},
	"smg": {"name": "Пистолет-пулемёт", "era": 3, "slot": "main", "cat": "firearm", "dmg": 26.0, "spd": 8.0, "range": 20.0, "dtype": "pierce", "model": "smg", "proj": "bullet", "mag": 32, "reload": 1.8, "spread": 6.0, "value": 280},
	"blade_tactical": {"name": "Тактический клинок", "era": 3, "slot": "main", "cat": "dagger", "dmg": 40.0, "spd": 2.8, "range": 1.9, "dtype": "slash", "model": "dagger", "value": 220},
	"katana_ceramic": {"name": "Керамическая катана", "era": 3, "slot": "main", "cat": "sword", "dmg": 52.0, "spd": 1.8, "range": 2.6, "dtype": "slash", "model": "katana", "value": 300},
	"baton_shock": {"name": "Шоковая дубинка", "era": 3, "slot": "main", "cat": "heavy", "dmg": 50.0, "spd": 1.4, "range": 2.2, "dtype": "lightning", "model": "baton", "value": 220},
	"focus_arcane": {"name": "Арканный фокус", "era": 3, "slot": "main", "cat": "staff", "dmg": 42.0, "spd": 1.5, "range": 24.0, "dtype": "lightning", "model": "focus", "proj": "magic", "mana": 60, "value": 300},
	"vest_kevlar": {"name": "Бронежилет", "era": 3, "slot": "body", "armor": 40.0, "hp": 90, "model": "vest", "value": 300},
	"armor_jacket": {"name": "Тактическая куртка", "era": 3, "slot": "body", "armor": 26.0, "hp": 70, "speed": 0.05, "model": "jacket", "value": 220},
	"helm_tactical": {"name": "Тактический шлем", "era": 3, "slot": "head", "armor": 14.0, "hp": 20, "model": "tac_helm", "value": 180},
	"gloves_tactical": {"name": "Тактические перчатки", "era": 3, "slot": "hands", "armor": 7.0, "aspd": 0.06, "model": "gloves", "value": 120},
	"boots_combat": {"name": "Берцы", "era": 3, "slot": "feet", "armor": 8.0, "speed": 0.04, "model": "boots", "value": 120},
	"module_scanner": {"name": "Сканер аномалий", "era": 3, "slot": "module", "detect": 1.0, "crit": 0.04, "model": "module", "value": 250},
	# ===== Era 4 — Future
	"blade_energy": {"name": "Энергоклинок", "era": 4, "slot": "main", "cat": "sword", "dmg": 75.0, "spd": 1.9, "range": 2.7, "dtype": "energy", "model": "energy_blade", "value": 450},
	"pulse_rifle": {"name": "Импульсная винтовка", "era": 4, "slot": "main", "cat": "firearm", "dmg": 55.0, "spd": 5.0, "range": 34.0, "dtype": "energy", "model": "pulse_rifle", "two_h": true, "proj": "pulse", "mag": 40, "reload": 1.8, "spread": 2.0, "value": 500},
	"plasma_cannon": {"name": "Плазменная пушка", "era": 4, "slot": "main", "cat": "firearm", "dmg": 140.0, "spd": 0.7, "range": 28.0, "dtype": "fire", "model": "plasma_cannon", "two_h": true, "proj": "plasma", "mag": 4, "reload": 2.6, "spread": 1.0, "splash": 3.0, "value": 600},
	"smart_gun": {"name": "Разумный пистолет", "era": 4, "slot": "main", "cat": "firearm", "dmg": 50.0, "spd": 3.5, "range": 28.0, "dtype": "energy", "model": "smart_gun", "proj": "pulse", "mag": 20, "reload": 1.5, "spread": 1.0, "homing": 1.0, "value": 520},
	"staff_chrono": {"name": "Хроноскипетр", "era": 4, "slot": "main", "cat": "staff", "dmg": 66.0, "spd": 1.6, "range": 26.0, "dtype": "time", "model": "staff_chrono", "two_h": true, "proj": "magic", "mana": 90, "value": 520},
	"shield_energy": {"name": "Энергощит", "era": 4, "slot": "off", "armor": 30.0, "block": 0.85, "model": "shield_energy", "value": 400},
	"armor_energy": {"name": "Энергоброня", "era": 4, "slot": "body", "armor": 60.0, "hp": 160, "model": "energy_armor", "value": 520},
	"exo_frame": {"name": "Экзоскелет", "era": 4, "slot": "body", "armor": 70.0, "hp": 200, "dmg_pct": 0.1, "speed": 0.04, "model": "exo", "value": 650},
	"helm_visor": {"name": "Шлем с визором", "era": 4, "slot": "head", "armor": 22.0, "hp": 40, "model": "visor", "value": 350},
	"implant_reflex": {"name": "Имплант рефлексов", "era": 4, "slot": "module", "aspd": 0.12, "speed": 0.06, "model": "implant", "value": 500},
	"implant_neural": {"name": "Нейроимплант", "era": 4, "slot": "module", "spell": 0.2, "mana": 60, "model": "implant", "value": 500},
	"gloves_power": {"name": "Силовые перчатки", "era": 4, "slot": "hands", "armor": 12.0, "dmg_pct": 0.08, "model": "gauntlets", "value": 300},
	"boots_grav": {"name": "Гравиботинки", "era": 4, "slot": "feet", "armor": 12.0, "speed": 0.08, "model": "boots", "value": 300},
	# ===== Consumables / materials (all eras)
	"potion_hp": {"name": "Зелье здоровья", "era": -1, "slot": "use", "effect": "heal", "power": 0.4, "stack": true, "value": 15},
	"potion_mana": {"name": "Зелье маны", "era": -1, "slot": "use", "effect": "mana", "power": 0.5, "stack": true, "value": 15},
	"potion_big": {"name": "Великое зелье", "era": -1, "slot": "use", "effect": "heal_full", "power": 1.0, "stack": true, "value": 60},
	"elixir_mutation": {"name": "Эликсир мутации", "era": 1, "slot": "use", "effect": "mutation", "stack": true, "value": 50},
	"scroll_identify": {"name": "Свиток распознавания", "era": -1, "slot": "use", "effect": "identify", "stack": true, "value": 20},
	"scroll_purify": {"name": "Свиток очищения", "era": -1, "slot": "use", "effect": "purify", "stack": true, "value": 80},
	"relic_purifier": {"name": "Реликвия Освобождения", "era": -1, "slot": "use", "effect": "release_any", "stack": true, "value": 300},
	"bomb_flask": {"name": "Алхимическая бомба", "era": 1, "slot": "use", "effect": "bomb", "stack": true, "value": 25},
	"grenade": {"name": "Граната", "era": 3, "slot": "use", "effect": "bomb", "stack": true, "value": 30},
	"tome_fire": {"name": "Фолиант Огня", "era": -1, "slot": "use", "effect": "learn_school", "school": "fire", "stack": true, "value": 120},
	"tome_ice": {"name": "Фолиант Льда", "era": -1, "slot": "use", "effect": "learn_school", "school": "ice", "stack": true, "value": 120},
	"tome_lightning": {"name": "Фолиант Молний", "era": -1, "slot": "use", "effect": "learn_school", "school": "lightning", "stack": true, "value": 120},
	"tome_dark": {"name": "Фолиант Тьмы", "era": -1, "slot": "use", "effect": "learn_school", "school": "dark", "stack": true, "value": 150},
	"tome_spacetime": {"name": "Фолиант Пространства", "era": -1, "slot": "use", "effect": "learn_school", "school": "spacetime", "stack": true, "value": 180},
	"companion_whistle": {"name": "Свисток зверолова", "era": -1, "slot": "use", "effect": "companion", "stack": true, "value": 150},
	"mirror_shard": {"name": "Осколок Зеркала Времени", "era": -1, "slot": "use", "effect": "chrono_double", "stack": true, "value": 200},
	"chrono_shard": {"name": "Осколок Хроноса", "era": -1, "slot": "mat", "stack": true, "value": 50},
	"iron_ore": {"name": "Руда", "era": -1, "slot": "mat", "stack": true, "value": 4},
	"herbs": {"name": "Травы", "era": -1, "slot": "mat", "stack": true, "value": 3},
	"gears": {"name": "Шестерни", "era": -1, "slot": "mat", "stack": true, "value": 8},
	"circuits": {"name": "Микросхемы", "era": -1, "slot": "mat", "stack": true, "value": 12},
	"relic_iron_crown": {"name": "Железная Корона Эпохи", "era": 0, "slot": "mat", "stack": true, "value": 500, "relic": true},
	"relic_astrolabe": {"name": "Астролябия Возрождения", "era": 1, "slot": "mat", "stack": true, "value": 600, "relic": true},
	"relic_steam_heart": {"name": "Паровое Сердце", "era": 2, "slot": "mat", "stack": true, "value": 700, "relic": true},
	"relic_quantum_core": {"name": "Квантовое Ядро", "era": 3, "slot": "mat", "stack": true, "value": 800, "relic": true},
}

# Weapon models that get created by default class kits.
const CLASS_KITS := {
	"warrior": ["sword_iron", "shield_wood", "armor_leather", "potion_hp", "potion_hp"],
	"archer": ["bow_short", "armor_leather", "helm_hood", "potion_hp", "potion_hp"],
	"rogue": ["dagger_iron", "armor_leather", "helm_hood", "potion_hp", "scroll_identify"],
	"mage": ["staff_oak", "robe_mage", "potion_mana", "potion_mana", "potion_hp"],
}

# ---------------------------------------------------------------- modifiers
const MODS := {
	"sharp": {"stat": "dmg_pct", "min": 0.05, "max": 0.2, "prefix": "Острый"},
	"swift": {"stat": "aspd", "min": 0.04, "max": 0.14, "prefix": "Быстрый"},
	"vamp": {"stat": "lifesteal", "min": 0.02, "max": 0.06, "prefix": "Вампирский"},
	"burning": {"stat": "fire_dmg", "min": 3.0, "max": 10.0, "prefix": "Пылающий"},
	"frost": {"stat": "ice_dmg", "min": 3.0, "max": 9.0, "prefix": "Морозный"},
	"shock": {"stat": "lightning_dmg", "min": 3.0, "max": 10.0, "prefix": "Грозовой"},
	"cruel": {"stat": "crit", "min": 0.03, "max": 0.1, "prefix": "Жестокий"},
	"vital": {"stat": "hp", "min": 15.0, "max": 60.0, "suffix": "жизни"},
	"arcane": {"stat": "mana", "min": 15.0, "max": 50.0, "suffix": "магии"},
	"guard": {"stat": "armor", "min": 3.0, "max": 12.0, "suffix": "стража"},
	"regen": {"stat": "regen", "min": 0.5, "max": 2.5, "suffix": "восстановления"},
	"lucky": {"stat": "luck", "min": 0.05, "max": 0.2, "suffix": "удачи"},
	"wind": {"stat": "speed", "min": 0.03, "max": 0.08, "suffix": "ветра"},
	"fireward": {"stat": "res_fire", "min": 0.08, "max": 0.25, "suffix": "огнеупорности"},
	"iceward": {"stat": "res_ice", "min": 0.08, "max": 0.25, "suffix": "тепла"},
	"stormward": {"stat": "res_lightning", "min": 0.08, "max": 0.25, "suffix": "заземления"},
	"spell": {"stat": "spell", "min": 0.05, "max": 0.18, "suffix": "чародейства"},
}

const LEGENDARY_ABILITIES := {
	"chain_proc": "При ударе (20%): цепная молния по 3 целям.",
	"nova_kill": "При убийстве: огненная волна вокруг владельца.",
	"execute": "Тройной урон по врагам с запасом здоровья ниже 25%.",
	"phantom": "Каждый 3-й удар порождает призрачный удар.",
	"frost_aura": "Враги рядом замедляются на 30%.",
	"thorns": "Возвращает 25% полученного урона ближнего боя.",
	"explosive": "Снаряды взрываются при попадании.",
	"leech_mana": "Удары восстанавливают ману.",
}
const MYTHIC_MECHANICS := {
	"time_echo": "Эхо времени: каждая атака повторяется через 0,6 с призрачной копией.",
	"rift_strike": "Удар разлома: попадания открывают микроразлом, затягивающий и ранящий врагов.",
	"soul_harvest": "Жатва душ: убитые враги восстают духами-союзниками на 15 с.",
	"chrono_rewind": "Откат: смертельный урон отматывает здоровье назад (раз в 60 с).",
	"auto_parry": "Предвидение: 30% шанс автоматически парировать любую атаку.",
}

const CURSES := {
	"drain": {"name": "Ненасытность", "desc": "Вне боя постепенно отнимает здоровье."},
	"frail": {"name": "Хрупкость", "desc": "-20% максимального здоровья."},
	"clumsy": {"name": "Неуклюжесть", "desc": "-15% скорости атаки."},
	"bloodlust": {"name": "Жажда крови", "desc": "Здоровье не восстанавливается само по себе."},
	"mana_burn": {"name": "Пустота", "desc": "Мана не восстанавливается вне боя."},
	"hunted": {"name": "Метка охотника", "desc": "Привлекает охотников за головами."},
}
const RELEASE_METHODS := {
	"purify": "Очищение: алтарь, жрец или свиток очищения.",
	"ritual": "Ритуал: проведите ритуал у древнего алтаря ночью.",
	"quest": "Задание: выполните задание «Освобождение».",
	"boss": "Победа над связанным боссом.",
	"artifact": "Реликвия Освобождения снимает любую связь.",
	"tech": "Отключите управляющую технологию на терминале.",
}

# ---------------------------------------------------------------- uniques
const UNIQUES := {
	"u_insatiable": {"base": "sword_steel", "name": "Клинок Ненасытного", "rarity": 4, "dmg_mult": 2.2,
		"ability": "nova_kill", "mods": {"lifesteal": 0.04}, "on_kill_heal": 0.12,
		"curse": {"id": "drain", "bound": true, "hidden": true, "release": "ritual"},
		"lore": "Клинок, выкованный некромантом. Дарит силу, но всегда голоден."},
	"u_living_blade": {"base": "sword_iron", "name": "Спящий Клинок Аэрин", "rarity": 3, "dmg_mult": 1.2,
		"living": {"stage": 0, "xp": 0, "path": ""},
		"lore": "Древний меч с душой. Он просыпается вместе с владельцем."},
	"u_headsman_axe": {"base": "axe_battle", "name": "Секира Палача", "rarity": 4, "dmg_mult": 1.8, "ability": "execute",
		"lore": "Оружие Палача Чёрной Башни. Не знает пощады."},
	"u_distortion_staff": {"base": "staff_oak", "name": "Посох Искажения", "rarity": 5, "dmg_mult": 2.4, "mythic": "time_echo",
		"lore": "Посох Проклятого Архимага, трещащий от разорванного времени."},
	"u_crown_thorns": {"base": "helm_kettle", "name": "Венец Терний", "rarity": 3, "mods": {"spell": 0.25, "mana": 60},
		"curse": {"id": "frail", "bound": true, "hidden": true, "release": "purify"},
		"lore": "Корона безумного короля. Шепчет заклинания."},
	"u_thirst_ring": {"base": "ring_copper", "name": "Кольцо Вечной Жажды", "rarity": 4, "mods": {"crit": 0.15, "lifesteal": 0.03},
		"curse": {"id": "bloodlust", "bound": true, "hidden": true, "release": "quest"},
		"lore": "Кольцо, которое не отпускает тех, кто однажды вкусил крови."},
	"u_necro_grimoire": {"base": "grimoire", "name": "Книга Забытых Имён", "rarity": 4, "mods": {"spell": 0.3}, "ability": "leech_mana",
		"curse": {"id": "mana_burn", "bound": true, "hidden": false, "release": "boss", "boss_id": "necro_lord"},
		"lore": "Гримуар Некроманта. Связан с его душой: освободиться можно, только победив его."},
	"u_baron_pistol": {"base": "pistol_wheellock", "name": "Пистоль Порохового Барона", "rarity": 4, "dmg_mult": 1.9, "ability": "explosive",
		"lore": "Каждый выстрел — маленькая буря пороха."},
	"u_titan_heart": {"base": "amulet_alch", "name": "Сердце Титана", "rarity": 4, "mods": {"hp": 150, "regen": 3.0}, "ability": "thorns",
		"lore": "Пульсирующее алхимическое сердце."},
	"u_duelist_rapier": {"base": "rapier", "name": "Рапира Заводного Дуэлянта", "rarity": 5, "dmg_mult": 2.2, "mythic": "auto_parry",
		"lore": "Механизм рапиры предугадывает каждый выпад."},
	"u_magnate_revolver": {"base": "revolver", "name": "Золотой Револьвер Магната", "rarity": 4, "dmg_mult": 1.9, "ability": "chain_proc",
		"lore": "Револьвер, купленный ценой целого города."},
	"u_colossus_hammer": {"base": "steam_hammer", "name": "Молот Колосса", "rarity": 4, "dmg_mult": 1.9, "ability": "nova_kill",
		"lore": "Поршень парового колосса, превращённый в оружие."},
	"u_mech_gauntlet": {"base": "gloves_work", "name": "Длань Повелителя Механизмов", "rarity": 4, "mods": {"dmg_pct": 0.25, "aspd": 0.15},
		"curse": {"id": "clumsy", "bound": true, "hidden": true, "release": "tech"},
		"lore": "Механическая перчатка с собственной волей. Отключить её можно только через управляющий терминал."},
	"u_phantom_blade": {"base": "blade_tactical", "name": "Клинок Фантома", "rarity": 4, "dmg_mult": 1.9, "ability": "phantom",
		"lore": "Оружие Призрачного Командира."},
	"u_guardian_core": {"base": "module_scanner", "name": "Ядро Стража", "rarity": 4, "mods": {"armor": 40, "hp": 120}, "ability": "frost_aura",
		"lore": "Энергетическое ядро экспериментального стража."},
	"u_autonomous_rifle": {"base": "carbine", "name": "Автономная Винтовка «Рой»", "rarity": 5, "dmg_mult": 2.1, "mythic": "soul_harvest",
		"lore": "Разумное оружие с собственной боевой логикой."},
	"u_archon_blade": {"base": "blade_energy", "name": "Клинок Архонта", "rarity": 5, "dmg_mult": 2.4, "mythic": "rift_strike",
		"lore": "Клинок, рассекающий ткань пространства."},
	"u_emperor_crown": {"base": "helm_visor", "name": "Корона Синтетического Императора", "rarity": 4, "mods": {"spell": 0.3, "crit": 0.1}, "ability": "chain_proc",
		"lore": "Нейрокорона машинного владыки."},
	"u_chrono_reaver": {"base": "staff_chrono", "name": "Пожиратель Мгновений", "rarity": 5, "dmg_mult": 2.5, "mythic": "chrono_rewind",
		"lore": "Скипетр, сотканный из украденных секунд."},
}

const LIVING_STAGES := ["Спящий", "Пробуждённый", "Вознесённый"]
const LIVING_PATHS := {"dawn": "Клинок Зари", "dusk": "Клинок Сумрака"}

static var _uid_counter: int = 1

# ---------------------------------------------------------------- factory
static func next_uid() -> int:
	_uid_counter += 1
	return int(Time.get_unix_time_from_system()) % 100000 * 10000 + _uid_counter

static func base(id: String) -> Dictionary:
	return BASES.get(id, {})

static func roll_rarity(table: String = "normal", luck: float = 0.0, rng: RandomNumberGenerator = null) -> int:
	var w: Array = TABLES.get(table, TABLES.normal).duplicate()
	# luck shifts weight from common into higher tiers
	if luck > 0.0:
		var moved: float = w[0] * clampf(luck, 0.0, 0.6)
		w[0] -= moved
		w[1] += moved * 0.5
		w[2] += moved * 0.3
		w[3] += moved * 0.15
		w[4] += moved * 0.045
		w[5] += moved * 0.005
	var total := 0.0
	for x in w:
		total += x
	var r := (rng.randf() if rng else randf()) * total
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return i
	return 0

static func is_equipment(item: Dictionary) -> bool:
	var b := base(item.get("base", ""))
	return b.get("slot", "") in SLOTS

static func create(base_id: String, rarity: int = 0, lvl: int = 1, rng: RandomNumberGenerator = null, allow_curse: bool = true) -> Dictionary:
	var b := base(base_id)
	if b.is_empty():
		return {}
	var r := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var item := {"uid": next_uid(), "base": base_id, "rarity": rarity, "lvl": max(1, lvl), "upg": 0, "qty": 1,
		"stats": {}, "mods": {}, "ability": "", "mythic": "", "curse": {}, "living": {}, "history": [], "name": ""}
	if b.get("slot", "") in ["use", "mat"]:
		item.rarity = 4 if b.get("relic", false) else (2 if b.get("effect", "") in ["learn_school", "release_any", "chrono_double", "companion"] else 0)
		item.name = b.name
		return item
	var mult: float = RARITY_MULT[rarity] * (1.0 + 0.1 * (lvl - 1))
	for k in ["dmg", "armor", "hp", "mana", "spell", "block", "crit", "speed", "aspd", "dmg_pct", "res_fire", "res_ice", "detect"]:
		if b.has(k):
			var v: float = float(b[k])
			if k in ["dmg", "armor", "hp", "mana"]:
				v *= mult
			elif k in ["spell", "crit", "dmg_pct"]:
				v *= RARITY_MULT[rarity]
			item.stats[k] = snappedf(v, 0.01)
	# modifiers
	var mod_keys := MODS.keys()
	var n_mods := rarity
	for i in n_mods:
		var mk: String = mod_keys[r.randi() % mod_keys.size()]
		var m: Dictionary = MODS[mk]
		var v2: float = lerpf(m.min, m.max, r.randf()) * (1.0 + 0.05 * lvl)
		item.mods[m.stat] = snappedf(item.mods.get(m.stat, 0.0) + v2, 0.01)
	if rarity == 4:
		var ak := LEGENDARY_ABILITIES.keys()
		item.ability = ak[r.randi() % ak.size()]
	elif rarity == 5:
		var mk2 := MYTHIC_MECHANICS.keys()
		item.mythic = mk2[r.randi() % mk2.size()]
		var ak2 := LEGENDARY_ABILITIES.keys()
		item.ability = ak2[r.randi() % ak2.size()]
	# hidden curses: tempting items are sometimes cursed
	if allow_curse and rarity >= 1 and r.randf() < 0.07:
		var ck := CURSES.keys()
		var cid: String = ck[r.randi() % ck.size()]
		var bound := r.randf() < 0.6
		var methods := ["purify", "ritual", "quest", "artifact"]
		if b.get("era", 0) >= 2:
			methods.append("tech")
		item.curse = {"id": cid, "bound": bound, "hidden": true, "release": methods[r.randi() % methods.size()]}
		if item.stats.has("dmg"):
			item.stats.dmg = snappedf(item.stats.dmg * 1.3, 0.01)
		if item.stats.has("armor"):
			item.stats.armor = snappedf(item.stats.armor * 1.3, 0.01)
	item.name = _gen_name(item, b, r)
	return item

static func create_unique(uid_key: String, lvl: int = 1) -> Dictionary:
	var u: Dictionary = UNIQUES.get(uid_key, {})
	if u.is_empty():
		return {}
	var item := create(u.base, u.rarity, lvl, null, false)
	item.name = u.name
	item.unique = uid_key
	item.mods = {}
	if u.has("dmg_mult") and item.stats.has("dmg"):
		item.stats.dmg = snappedf(BASES[u.base].dmg * u.dmg_mult * (1.0 + 0.1 * (lvl - 1)), 0.01)
	for k in u.get("mods", {}):
		item.mods[k] = u.mods[k]
	item.ability = u.get("ability", "")
	item.mythic = u.get("mythic", "")
	item.curse = u.get("curse", {}).duplicate()
	item.living = u.get("living", {}).duplicate()
	item.lore = u.get("lore", "")
	return item

static func random_for_era(era_i: int, lvl: int, table: String = "normal", luck: float = 0.0, rng: RandomNumberGenerator = null) -> Dictionary:
	var r := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var rarity := roll_rarity(table, luck, r)
	# a small chance for a themed unique on legendary/mythic rolls
	if rarity >= 4 and r.randf() < 0.25:
		var pool: Array = []
		for k in UNIQUES:
			var ub: Dictionary = BASES[UNIQUES[k].base]
			if ub.era == era_i and UNIQUES[k].rarity == rarity and not k in ["u_living_blade"]:
				pool.append(k)
		if not pool.is_empty():
			return create_unique(pool[r.randi() % pool.size()], lvl)
	var candidates: Array = []
	for k in BASES:
		var b: Dictionary = BASES[k]
		if b.slot in SLOTS and (b.era == era_i or (b.era == era_i - 1 and r.randf() < 0.25)):
			candidates.append(k)
	var id: String = candidates[r.randi() % candidates.size()]
	return create(id, rarity, lvl, r)

static func random_consumable(era_i: int, rng: RandomNumberGenerator = null) -> Dictionary:
	var r := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var pool := ["potion_hp", "potion_hp", "potion_hp", "potion_mana", "potion_mana", "scroll_identify", "herbs", "iron_ore"]
	if era_i >= 1:
		pool.append_array(["bomb_flask", "elixir_mutation", "gears"])
	if era_i >= 2:
		pool.append("gears")
	if era_i >= 3:
		pool.append_array(["grenade", "circuits"])
	if r.randf() < 0.08:
		pool.append_array(["scroll_purify", "potion_big"])
	if r.randf() < 0.04:
		pool.append_array(["tome_fire", "tome_ice", "tome_lightning", "tome_dark", "tome_spacetime"][r.randi() % 5])
	if r.randf() < 0.02:
		pool.append("mirror_shard")
	return create(pool[r.randi() % pool.size()], 0, 1, r)

static func _gen_name(item: Dictionary, b: Dictionary, r: RandomNumberGenerator) -> String:
	if item.rarity == 0:
		return b.name
	var prefix := ""
	var suffix := ""
	for k in MODS:
		var m: Dictionary = MODS[k]
		if item.mods.has(m.stat):
			if m.has("prefix") and prefix == "":
				prefix = m.prefix
			elif m.has("suffix") and suffix == "":
				suffix = m.suffix
	var nm: String = b.name
	if prefix != "" and r.randf() < 0.8:
		nm = prefix + " " + nm.substr(0, 1).to_lower() + nm.substr(1)
	if suffix != "" and item.rarity >= 2:
		nm += " " + suffix
	if item.rarity >= 4:
		var epics := ["Рассвета", "Бури", "Пепла", "Вечности", "Тысячи Лет", "Хроноса", "Падших Королей", "Разлома"]
		nm = b.name + " " + epics[r.randi() % epics.size()]
	return nm

static func display_name(item: Dictionary) -> String:
	var nm: String = item.get("name", base(item.get("base", "")).get("name", "?"))
	if item.get("upg", 0) > 0:
		nm += " +%d" % item.upg
	if item.get("living", {}).size() > 0:
		var st: int = item.living.get("stage", 0)
		if st >= 2 and item.living.get("path", "") != "":
			nm = LIVING_PATHS.get(item.living.path, nm)
		elif st > 0:
			nm = LIVING_STAGES[st] + " " + nm.substr(nm.find(" ") + 1)
	return nm

static func rarity_color(item: Dictionary) -> Color:
	return RARITY_COLORS[clampi(item.get("rarity", 0), 0, 5)]

## Total value of one stat on an item including upgrades and mods.
static func stat(item: Dictionary, key: String) -> float:
	var v: float = float(item.get("stats", {}).get(key, 0.0)) + float(item.get("mods", {}).get(key, 0.0))
	if key in ["dmg", "armor"]:
		v *= 1.0 + 0.08 * item.get("upg", 0)
		if item.get("living", {}).size() > 0:
			v *= 1.0 + 0.45 * item.living.get("stage", 0)
	return v

## Heuristic power used by AI to compare items.
static func power(item: Dictionary) -> float:
	if item.is_empty():
		return 0.0
	var p = stat(item, "dmg") * base(item.base).get("spd", 1.0) + stat(item, "armor") * 1.5 + stat(item, "hp") * 0.3 + stat(item, "mana") * 0.2
	p += stat(item, "crit") * 80.0 + stat(item, "dmg_pct") * 60.0 + stat(item, "spell") * 60.0
	p *= 1.0 + 0.15 * item.get("rarity", 0)
	if item.get("curse", {}).size() > 0 and not item.curse.get("hidden", true):
		p *= 0.7
	return p

static func value(item: Dictionary) -> int:
	var b := base(item.get("base", ""))
	return int(b.get("value", 1) * (1.0 + item.get("rarity", 0) * item.get("rarity", 0) * 0.8) * (1.0 + 0.1 * item.get("lvl", 1)))

## BBCode description used by item cards.
static func describe(item: Dictionary) -> String:
	var b := base(item.get("base", ""))
	var col := rarity_color(item).to_html(false)
	var t := "[b][color=#%s]%s[/color][/b]\n" % [col, display_name(item)]
	if b.slot in ["use", "mat"]:
		t += "[color=#aaaaaa]%s%s[/color]\n" % [SLOT_NAMES.get(b.slot, ""), (" ×%d" % item.get("qty", 1)) if item.get("qty", 1) > 1 else ""]
	else:
		t += "[color=#aaaaaa]%s · %s · ур. %d[/color]\n" % [RARITY_NAMES[item.rarity], SLOT_NAMES.get(b.slot, ""), item.get("lvl", 1)]
	if b.has("cat"):
		t += "%s · урон [b]%.0f[/b] (%s) · %.1f уд/с · дальность %.0f м\n" % [CAT_NAMES.get(b.cat, ""), stat(item, "dmg"), DTYPE_NAMES.get(b.get("dtype", ""), ""), b.get("spd", 1.0), b.get("range", 2.0)]
		if b.has("mag"):
			t += "Магазин: %d · перезарядка %.1f с\n" % [b.mag, b.reload]
	var labels := {"armor": "Броня", "hp": "Здоровье", "mana": "Мана", "spell": "Сила магии", "block": "Блок", "crit": "Крит. шанс",
		"speed": "Скорость", "aspd": "Скорость атаки", "dmg_pct": "Урон", "lifesteal": "Вампиризм", "fire_dmg": "Урон огнём",
		"ice_dmg": "Урон льдом", "lightning_dmg": "Урон молнией", "regen": "Регенерация", "luck": "Удача", "res_fire": "Сопр. огню",
		"res_ice": "Сопр. льду", "res_lightning": "Сопр. молнии", "detect": "Распознаёт проклятия"}
	for k in item.get("stats", {}):
		if k == "dmg":
			continue
		t += "%s: %s\n" % [labels.get(k, k), _fmt(k, stat(item, k) if k != "armor" else stat(item, "armor"))]
	for k in item.get("mods", {}):
		if item.stats.has(k):
			continue
		t += "[color=#88ccff]%s: +%s[/color]\n" % [labels.get(k, k), _fmt(k, item.mods[k])]
	if item.get("ability", "") != "":
		t += "[color=#ffcc33]★ %s[/color]\n" % LEGENDARY_ABILITIES.get(item.ability, "")
	if item.get("mythic", "") != "":
		t += "[color=#ff3344]✦ %s[/color]\n" % MYTHIC_MECHANICS.get(item.mythic, "")
	if item.get("living", {}).size() > 0:
		var lv: Dictionary = item.living
		t += "[color=#66ffcc]Живое оружие · стадия %d/3 · опыт %d/%d[/color]\n" % [lv.stage + 1, lv.xp, living_xp_needed(lv.stage)]
	var c: Dictionary = item.get("curse", {})
	if c.size() > 0:
		if c.get("hidden", true):
			t += "[color=#777777]??? Неизвестная аура[/color]\n"
		else:
			var cd: Dictionary = CURSES.get(c.id, {})
			t += "[color=#cc3333]Проклятие: %s — %s[/color]\n" % [cd.get("name", ""), cd.get("desc", "")]
			if c.get("bound", false):
				t += "[color=#cc3333]Несъёмный. %s[/color]\n" % RELEASE_METHODS.get(c.release, "")
	if b.has("effect"):
		var eff := {"heal": "Восстанавливает 40% здоровья.", "mana": "Восстанавливает 50% маны.", "heal_full": "Полностью восстанавливает здоровье и ману.",
			"identify": "Раскрывает скрытые свойства предмета.", "purify": "Снимает проклятие очищением.", "release_any": "Разрывает любую связь проклятого предмета.",
			"bomb": "Бросок: взрыв по площади.", "learn_school": "Открывает школу магии.", "mutation": "Мощное, но нестабильное усиление.",
			"chrono_double": "Призывает вашего хронодвойника для поединка.", "companion": "Призывает боевого спутника эпохи."}
		t += "[color=#cccccc]%s[/color]\n" % eff.get(b.effect, "")
	if item.get("lore", "") != "":
		t += "[i][color=#bbaa88]%s[/color][/i]\n" % item.lore
	for h in item.get("history", []):
		t += "[color=#998866]· %s[/color]\n" % h
	t += "[color=#888888]Цена: %d[/color]" % value(item)
	return t

static func _fmt(k: String, v: float) -> String:
	if k in ["crit", "speed", "aspd", "dmg_pct", "lifesteal", "spell", "block", "luck", "res_fire", "res_ice", "res_lightning"]:
		return "%d%%" % roundi(v * 100.0)
	return "%.0f" % v

static func living_xp_needed(stage: int) -> int:
	return [150, 500, 999999][clampi(stage, 0, 2)]
