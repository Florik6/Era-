class_name DBActors
## Enemies, bosses, personalities and name generators.

# rig: humanoid | wolf | golem | drone | spider | wraith | blob | mimic | troll | colossus
# ai: melee | ranged | caster | beast | swarm
const ENEMIES := {
	# ---- Era 0
	"bandit": {"name": "Разбойник", "rig": "humanoid", "weapons": ["axe_hand", "dagger_iron", "bow_short", "sword_iron"], "armor": "leather", "hp": 70, "lvl": 0, "xp": 14, "team": "bandit", "ai": "melee", "cloth": Color(0.4, 0.3, 0.22), "hat": "hood"},
	"deserter": {"name": "Дезертир", "rig": "humanoid", "weapons": ["sword_iron", "spear_iron"], "armor": "chain", "hp": 90, "lvl": 1, "xp": 18, "team": "bandit", "ai": "melee", "cloth": Color(0.45, 0.42, 0.35), "hat": "kettle"},
	"mercenary": {"name": "Наёмник", "rig": "humanoid", "weapons": ["sword_steel", "crossbow_light", "axe_battle"], "armor": "chain", "hp": 110, "lvl": 2, "xp": 24, "team": "bandit", "ai": "melee", "cloth": Color(0.55, 0.2, 0.18), "hat": "kettle"},
	"knight_renegade": {"name": "Рыцарь-отступник", "rig": "humanoid", "weapons": ["sword_steel", "hammer_war"], "offhand": "shield_kite", "armor": "plate", "hp": 170, "lvl": 4, "xp": 45, "team": "bandit", "ai": "melee", "cloth": Color(0.2, 0.2, 0.25), "hat": "greathelm", "elite": true},
	"dark_mage": {"name": "Враждебный маг", "rig": "humanoid", "weapons": ["staff_oak"], "armor": "robe", "hp": 75, "lvl": 2, "xp": 28, "team": "bandit", "ai": "caster", "spells": ["fireball", "frostbolt"], "cloth": Color(0.25, 0.12, 0.3), "hat": "hood"},
	"necro_acolyte": {"name": "Некромант", "rig": "humanoid", "weapons": ["staff_oak"], "armor": "robe", "hp": 90, "lvl": 3, "xp": 34, "team": "monster", "ai": "caster", "spells": ["drain", "curse", "summon"], "cloth": Color(0.1, 0.1, 0.12), "hat": "hood"},
	"wolf": {"name": "Волк", "rig": "wolf", "hp": 55, "dmg": 9.0, "lvl": 0, "xp": 10, "team": "monster", "ai": "beast", "speed": 1.35, "body": Color(0.45, 0.42, 0.4), "dtype": "slash"},
	"troll": {"name": "Пещерный тролль", "rig": "troll", "hp": 320, "dmg": 26.0, "lvl": 5, "xp": 80, "team": "monster", "ai": "beast", "speed": 0.8, "body": Color(0.4, 0.5, 0.35), "dtype": "blunt", "scale": 1.6, "elite": true},
	"skeleton": {"name": "Скелет", "rig": "humanoid", "weapons": ["sword_iron", "bow_short"], "armor": "bones", "hp": 50, "lvl": 1, "xp": 12, "team": "monster", "ai": "melee", "skeleton": true, "res": {"pierce": 0.4, "blunt": -0.4, "dark": 0.8}},
	"cursed_warrior": {"name": "Проклятый воин", "rig": "humanoid", "weapons": ["sword_steel", "axe_battle"], "armor": "cursed", "hp": 140, "lvl": 3, "xp": 36, "team": "monster", "ai": "melee", "cloth": Color(0.15, 0.25, 0.2), "hat": "greathelm", "glow": Color(0.3, 1.0, 0.5), "res": {"dark": 0.6, "fire": -0.3}},
	"wraith": {"name": "Призрак", "rig": "wraith", "hp": 80, "dmg": 13.0, "lvl": 3, "xp": 30, "team": "monster", "ai": "caster", "spells": ["drain"], "body": Color(0.6, 0.75, 0.95, 0.6), "dtype": "dark", "res": {"slash": 0.5, "pierce": 0.5, "fire": -0.5}},
	# ---- Era 1
	"pirate": {"name": "Пират", "rig": "humanoid", "weapons": ["saber", "pistol_wheellock", "axe_boarding"], "armor": "leather", "hp": 140, "lvl": 0, "xp": 30, "team": "bandit", "ai": "melee", "cloth": Color(0.6, 0.15, 0.15), "hat": "bandana"},
	"smuggler": {"name": "Контрабандист", "rig": "humanoid", "weapons": ["saber", "dagger_curved", "pistol_wheellock"], "armor": "leather", "hp": 130, "lvl": 1, "xp": 32, "team": "bandit", "ai": "melee", "cloth": Color(0.3, 0.25, 0.2), "hat": "hat"},
	"musketeer_rogue": {"name": "Мушкетёр-отступник", "rig": "humanoid", "weapons": ["musket", "rapier"], "armor": "cuirass", "hp": 160, "lvl": 2, "xp": 40, "team": "bandit", "ai": "ranged", "cloth": Color(0.25, 0.25, 0.5), "hat": "hat"},
	"assassin": {"name": "Наёмный убийца", "rig": "humanoid", "weapons": ["dagger_curved", "rapier"], "armor": "leather", "hp": 120, "lvl": 3, "xp": 48, "team": "bandit", "ai": "melee", "cloth": Color(0.08, 0.08, 0.1), "hat": "hood", "stealth": true, "speed": 1.2},
	"homunculus": {"name": "Гомункул", "rig": "blob", "hp": 150, "dmg": 18.0, "lvl": 2, "xp": 40, "team": "monster", "ai": "beast", "body": Color(0.6, 0.85, 0.3), "dtype": "dark", "res": {"fire": -0.3}},
	"alchemical_slime": {"name": "Алхимическая слизь", "rig": "blob", "hp": 120, "dmg": 16.0, "lvl": 1, "xp": 30, "team": "monster", "ai": "swarm", "body": Color(0.3, 0.9, 0.7), "dtype": "fire", "scale": 0.8},
	"clockwork_golem": {"name": "Механический голем", "rig": "golem", "hp": 380, "dmg": 34.0, "lvl": 4, "xp": 90, "team": "monster", "ai": "beast", "speed": 0.75, "body": Color(0.7, 0.55, 0.3), "dtype": "blunt", "scale": 1.4, "metal": true, "res": {"slash": 0.4, "pierce": 0.3, "lightning": -0.5}, "elite": true},
	# ---- Era 2
	"gang_thug": {"name": "Бандит банды", "rig": "humanoid", "weapons": ["knife_trench", "revolver", "axe_fire"], "armor": "coat", "hp": 220, "lvl": 0, "xp": 50, "team": "bandit", "ai": "melee", "cloth": Color(0.25, 0.22, 0.2), "hat": "cap"},
	"industrial_guard": {"name": "Заводской охранник", "rig": "humanoid", "weapons": ["rifle_lever", "saber_cavalry"], "armor": "coat", "hp": 260, "lvl": 1, "xp": 56, "team": "bandit", "ai": "ranged", "cloth": Color(0.2, 0.25, 0.35), "hat": "pith"},
	"mercenary_rifle": {"name": "Наёмный стрелок", "rig": "humanoid", "weapons": ["rifle_lever", "shotgun_double"], "armor": "coat", "hp": 240, "lvl": 2, "xp": 60, "team": "bandit", "ai": "ranged", "cloth": Color(0.4, 0.35, 0.25), "hat": "cap"},
	"automaton": {"name": "Боевой автомат", "rig": "humanoid", "weapons": ["steam_hammer", "tesla_gun"], "armor": "robot", "hp": 380, "lvl": 3, "xp": 80, "team": "monster", "ai": "melee", "robot": true, "metal": true, "res": {"slash": 0.35, "pierce": 0.3, "lightning": -0.5}},
	"steam_spider": {"name": "Паровой паук", "rig": "spider", "hp": 300, "dmg": 30.0, "lvl": 2, "xp": 70, "team": "monster", "ai": "beast", "speed": 1.2, "body": Color(0.45, 0.35, 0.25), "dtype": "pierce", "metal": true, "res": {"lightning": -0.4}},
	"tesla_wraith": {"name": "Тесла-призрак", "rig": "wraith", "hp": 260, "dmg": 30.0, "lvl": 3, "xp": 75, "team": "monster", "ai": "caster", "spells": ["spark", "chain"], "body": Color(0.5, 0.7, 1.0, 0.6), "dtype": "lightning"},
	# ---- Era 3
	"merc_soldier": {"name": "Наёмник ЧВК", "rig": "humanoid", "weapons": ["carbine", "pistol_modern"], "armor": "vest", "hp": 420, "lvl": 0, "xp": 90, "team": "bandit", "ai": "ranged", "cloth": Color(0.35, 0.38, 0.28), "hat": "tac_helm", "cover": true},
	"gang_shooter": {"name": "Боевик банды", "rig": "humanoid", "weapons": ["smg", "shotgun", "blade_tactical"], "armor": "jacket", "hp": 380, "lvl": 0, "xp": 85, "team": "bandit", "ai": "ranged", "cloth": Color(0.15, 0.15, 0.18), "hat": "cap", "cover": true},
	"elite_operative": {"name": "Элитный боец", "rig": "humanoid", "weapons": ["katana_ceramic", "carbine"], "armor": "vest", "hp": 600, "lvl": 3, "xp": 140, "team": "bandit", "ai": "melee", "cloth": Color(0.1, 0.1, 0.12), "hat": "tac_helm", "elite": true, "cover": true},
	"combat_drone": {"name": "Автономный дрон", "rig": "drone", "hp": 300, "dmg": 34.0, "lvl": 1, "xp": 80, "team": "monster", "ai": "ranged", "body": Color(0.3, 0.3, 0.32), "dtype": "pierce", "metal": true, "proj": "bullet", "res": {"lightning": -0.6}},
	"experiment": {"name": "Экспериментальное существо", "rig": "troll", "hp": 700, "dmg": 60.0, "lvl": 3, "xp": 150, "team": "monster", "ai": "beast", "body": Color(0.65, 0.5, 0.55), "dtype": "slash", "scale": 1.3, "speed": 1.15, "elite": true},
	# ---- Era 4
	"combat_robot": {"name": "Боевой робот", "rig": "humanoid", "weapons": ["pulse_rifle", "blade_energy"], "armor": "robot", "hp": 800, "lvl": 0, "xp": 160, "team": "monster", "ai": "ranged", "robot": true, "metal": true, "res": {"pierce": 0.3, "lightning": -0.4}},
	"android": {"name": "Андроид", "rig": "humanoid", "weapons": ["blade_energy", "smart_gun"], "armor": "android", "hp": 700, "lvl": 1, "xp": 170, "team": "monster", "ai": "melee", "robot": true, "speed": 1.15, "cloth": Color(0.9, 0.9, 0.95)},
	"cyber_hunter": {"name": "Киберохотник", "rig": "humanoid", "weapons": ["pulse_rifle", "blade_energy"], "armor": "exo", "hp": 900, "lvl": 2, "xp": 200, "team": "bandit", "ai": "ranged", "cloth": Color(0.15, 0.1, 0.2), "hat": "visor", "elite": true, "cover": true},
	"synthetic": {"name": "Синтетическое существо", "rig": "spider", "hp": 850, "dmg": 70.0, "lvl": 2, "xp": 190, "team": "monster", "ai": "beast", "speed": 1.3, "body": Color(0.85, 0.85, 0.9), "dtype": "energy", "metal": true},
	"chrono_anomaly": {"name": "Хроноаномалия", "rig": "wraith", "hp": 750, "dmg": 60.0, "lvl": 3, "xp": 210, "team": "monster", "ai": "caster", "spells": ["timeslow", "riftdash", "spark"], "body": Color(0.4, 1.0, 0.85, 0.55), "dtype": "time"},
	# ---- Special
	"mimic": {"name": "Мимик", "rig": "mimic", "hp": 200, "dmg": 22.0, "lvl": 2, "xp": 60, "team": "monster", "ai": "beast", "body": Color(0.5, 0.35, 0.2), "dtype": "pierce", "speed": 1.1, "elite": true},
	"skeleton_minion": {"name": "Призванный скелет", "rig": "humanoid", "weapons": ["sword_iron"], "armor": "bones", "hp": 60, "lvl": 0, "xp": 0, "team": "summon", "ai": "melee", "skeleton": true},
	"spirit": {"name": "Дух жатвы", "rig": "wraith", "hp": 60, "dmg": 14.0, "lvl": 0, "xp": 0, "team": "summon", "ai": "beast", "body": Color(1.0, 0.3, 0.3, 0.6), "dtype": "dark"},
	"chrono_soldier": {"name": "Хроностраж", "rig": "humanoid", "weapons": ["blade_energy", "pulse_rifle"], "armor": "android", "hp": 260, "lvl": 1, "xp": 70, "team": "monster", "ai": "melee", "robot": true, "glow": Color(0.4, 1.0, 0.9)},
}

# Boss ability library types: cleave, slam, charge, fan, volley, summon, beam, nova, blink, slowzone, portal, hook, spin, quake, strikes, missiles, mines, shield
const BOSSES := {
	"executioner": {"name": "Палач Чёрной Башни", "era": 0, "rig": "humanoid", "scale": 1.8, "weapon": "axe_battle", "armor": "plate", "hat": "hood",
		"cloth": Color(0.18, 0.05, 0.05), "hp": 1500, "dmg": 26.0, "lvl": 6, "speed": 0.95, "dtype": "slash",
		"abilities": {"cleave": {"type": "cleave", "dmg": 1.5, "radius": 4.6, "arc": 120.0, "cd": 3.0}, "charge": {"type": "charge", "dmg": 1.3, "cd": 7.0},
			"hook": {"type": "hook", "dmg": 0.6, "cd": 9.0}, "spin": {"type": "spin", "dmg": 0.9, "radius": 4.5, "cd": 10.0},
			"summon": {"type": "summon", "enemy": "deserter", "count": 2, "cd": 22.0}},
		"phases": [{"hp": 1.0, "use": ["cleave", "charge"]},
			{"hp": 0.6, "use": ["cleave", "charge", "hook", "summon"], "msg": "Палач срывает цепи с крюков!"},
			{"hp": 0.3, "use": ["cleave", "spin", "hook", "charge"], "msg": "Палач впадает в ярость! Башня рушится!", "enrage": true, "arena": "break"}],
		"reward": "u_headsman_axe", "lair": "Чёрная Башня", "lore": "Бывший королевский палач, проклятый за казнь невинного."},
	"archmage": {"name": "Проклятый Архимаг", "era": 0, "rig": "humanoid", "scale": 1.5, "weapon": "staff_oak", "armor": "robe", "hat": "hood",
		"cloth": Color(0.3, 0.1, 0.45), "glow": Color(0.8, 0.3, 1.0), "hp": 1300, "dmg": 24.0, "lvl": 7, "speed": 0.9, "dtype": "fire",
		"abilities": {"fan": {"type": "fan", "dmg": 0.9, "count": 5, "dtype": "fire", "cd": 3.5}, "blink": {"type": "blink", "cd": 6.0},
			"nova": {"type": "nova", "dmg": 1.1, "radius": 7.0, "dtype": "ice", "cd": 9.0}, "portal": {"type": "portal", "dimension": "distorted", "cd": 999.0},
			"strikes": {"type": "strikes", "dmg": 1.2, "count": 6, "dtype": "lightning", "cd": 8.0}, "slowzone": {"type": "slowzone", "cd": 14.0},
			"volley": {"type": "volley", "dmg": 1.4, "count": 5, "dtype": "fire", "cd": 10.0}, "summon": {"type": "summon", "enemy": "wraith", "count": 2, "cd": 20.0}},
		"phases": [{"hp": 1.0, "use": ["fan", "blink", "nova"]},
			{"hp": 0.6, "use": ["portal", "fan", "strikes", "slowzone", "blink"], "msg": "Архимаг разрывает реальность! Вы в Искажённом измерении!"},
			{"hp": 0.3, "use": ["volley", "strikes", "summon", "blink", "nova"], "msg": "Архимаг призывает души павших учеников!", "enrage": true}],
		"reward": "u_distortion_staff", "lair": "Шпиль Искажения", "lore": "Глава Круга, посмевший остановить время и потерявший душу."},
	"necro_lord": {"name": "Некромант Забытой Крепости", "era": 0, "rig": "humanoid", "scale": 1.6, "weapon": "staff_oak", "armor": "robe", "hat": "hood",
		"cloth": Color(0.08, 0.1, 0.08), "glow": Color(0.3, 1.0, 0.4), "hp": 1400, "dmg": 22.0, "lvl": 7, "speed": 0.85, "dtype": "dark",
		"abilities": {"summon": {"type": "summon", "enemy": "skeleton", "count": 3, "cd": 12.0}, "beam": {"type": "beam", "dmg": 1.3, "dtype": "dark", "cd": 6.0},
			"nova": {"type": "nova", "dmg": 1.2, "radius": 6.5, "dtype": "dark", "cd": 9.0}, "shield": {"type": "shield", "enemy": "cursed_warrior", "count": 2, "cd": 30.0},
			"mines": {"type": "mines", "dmg": 1.3, "count": 6, "dtype": "dark", "cd": 11.0}},
		"phases": [{"hp": 1.0, "use": ["summon", "beam"]},
			{"hp": 0.6, "use": ["summon", "beam", "nova", "shield"], "msg": "Некромант укрывается за щитом из душ!"},
			{"hp": 0.3, "use": ["beam", "nova", "mines", "summon"], "msg": "Мёртвые восстают по всей крепости!", "enrage": true}],
		"reward": "u_insatiable", "lair": "Забытая Крепость", "lore": "Создатель Клинка Ненасытного."},
	"powder_baron": {"name": "Пороховой Барон", "era": 1, "rig": "humanoid", "scale": 1.7, "weapon": "musket", "armor": "cuirass", "hat": "hat",
		"cloth": Color(0.5, 0.1, 0.1), "hp": 2600, "dmg": 40.0, "lvl": 6, "speed": 0.9, "dtype": "fire",
		"abilities": {"fan": {"type": "fan", "dmg": 0.8, "count": 7, "dtype": "pierce", "cd": 3.0}, "mines": {"type": "mines", "dmg": 1.6, "count": 7, "dtype": "fire", "cd": 9.0},
			"volley": {"type": "volley", "dmg": 1.5, "count": 7, "dtype": "fire", "cd": 8.0}, "summon": {"type": "summon", "enemy": "pirate", "count": 3, "cd": 20.0},
			"charge": {"type": "charge", "dmg": 1.2, "cd": 8.0}},
		"phases": [{"hp": 1.0, "use": ["fan", "mines"]}, {"hp": 0.6, "use": ["fan", "volley", "summon"], "msg": "Барон вызывает свою пиратскую команду!"},
			{"hp": 0.3, "use": ["volley", "mines", "charge", "fan"], "msg": "Пороховые склады взрываются!", "enrage": true, "arena": "break"}],
		"reward": "u_baron_pistol", "lair": "Пороховой Форт", "lore": "Пират, купивший титул и половину флота."},
	"alch_titan": {"name": "Алхимический Титан", "era": 1, "rig": "golem", "scale": 2.6, "body": Color(0.4, 0.7, 0.35), "hp": 3200, "dmg": 46.0, "lvl": 7, "speed": 0.7, "dtype": "blunt",
		"abilities": {"slam": {"type": "slam", "dmg": 1.6, "radius": 5.5, "cd": 5.0}, "quake": {"type": "quake", "dmg": 1.2, "cd": 9.0},
			"nova": {"type": "nova", "dmg": 1.0, "radius": 8.0, "dtype": "fire", "cd": 12.0}, "summon": {"type": "summon", "enemy": "alchemical_slime", "count": 4, "cd": 16.0}},
		"phases": [{"hp": 1.0, "use": ["slam", "quake"]}, {"hp": 0.6, "use": ["slam", "quake", "summon"], "msg": "Титан истекает живой алхимией!"},
			{"hp": 0.3, "use": ["slam", "nova", "quake", "summon"], "msg": "Титан мутирует!", "enrage": true, "form": 1.25}],
		"reward": "u_titan_heart", "lair": "Лаборатория Великого Делания", "lore": "Попытка алхимиков создать бессмертного стража."},
	"mech_duelist": {"name": "Механический Дуэлянт", "era": 1, "rig": "humanoid", "scale": 1.5, "weapon": "rapier", "armor": "robot", "robot": true, "metal": true,
		"hp": 2400, "dmg": 44.0, "lvl": 7, "speed": 1.25, "dtype": "pierce",
		"abilities": {"cleave": {"type": "cleave", "dmg": 1.2, "radius": 3.8, "arc": 70.0, "cd": 1.8}, "charge": {"type": "charge", "dmg": 1.3, "cd": 5.0},
			"blink": {"type": "blink", "cd": 5.0}, "spin": {"type": "spin", "dmg": 0.9, "radius": 4.0, "cd": 8.0}},
		"phases": [{"hp": 1.0, "use": ["cleave", "charge"]}, {"hp": 0.6, "use": ["cleave", "charge", "blink"], "msg": "Дуэлянт переключается во вторую стойку."},
			{"hp": 0.3, "use": ["cleave", "spin", "blink", "charge"], "msg": "Пружины на пределе! Дуэлянт ускоряется!", "enrage": true}],
		"reward": "u_duelist_rapier", "lair": "Дуэльная Арена", "lore": "Заводной автомат, не проигравший ни одной дуэли."},
	"iron_magnate": {"name": "Железный Магнат", "era": 2, "rig": "humanoid", "scale": 1.7, "weapon": "revolver", "armor": "steam_suit", "metal": true,
		"cloth": Color(0.2, 0.18, 0.15), "hat": "tophat", "hp": 4600, "dmg": 60.0, "lvl": 6, "speed": 0.9, "dtype": "pierce",
		"abilities": {"fan": {"type": "fan", "dmg": 0.7, "count": 6, "dtype": "pierce", "cd": 2.5}, "summon": {"type": "summon", "enemy": "industrial_guard", "count": 3, "cd": 18.0},
			"missiles": {"type": "missiles", "dmg": 1.0, "count": 4, "dtype": "fire", "cd": 8.0}, "shield": {"type": "shield", "enemy": "automaton", "count": 2, "cd": 35.0}},
		"phases": [{"hp": 1.0, "use": ["fan", "summon"]}, {"hp": 0.6, "use": ["fan", "missiles", "shield"], "msg": "Магнат прячется за своими автоматами!"},
			{"hp": 0.3, "use": ["fan", "missiles", "summon"], "msg": "Магнат включает форсаж бронекостюма!", "enrage": true}],
		"reward": "u_magnate_revolver", "lair": "Особняк Магната", "lore": "Владелец всех фабрик Ферроград."},
	"steam_colossus": {"name": "Паровой Колосс", "era": 2, "rig": "colossus", "scale": 2.4, "body": Color(0.45, 0.35, 0.28), "metal": true, "hp": 5400, "dmg": 70.0, "lvl": 7, "speed": 0.6, "dtype": "blunt",
		"parts": {"left_arm": 900, "right_arm": 900, "boiler": 1200},
		"abilities": {"slam": {"type": "slam", "dmg": 1.6, "radius": 6.0, "cd": 5.0, "part": "right_arm"}, "beam": {"type": "beam", "dmg": 1.2, "dtype": "fire", "cd": 7.0, "part": "left_arm"},
			"quake": {"type": "quake", "dmg": 1.2, "cd": 9.0}, "nova": {"type": "nova", "dmg": 1.1, "radius": 9.0, "dtype": "fire", "cd": 12.0, "part": "boiler"}},
		"phases": [{"hp": 1.0, "use": ["slam", "beam"]}, {"hp": 0.6, "use": ["slam", "beam", "quake"], "msg": "Колосс стравливает перегретый пар!"},
			{"hp": 0.3, "use": ["slam", "beam", "quake", "nova"], "msg": "Котёл Колосса на грани взрыва!", "enrage": true}],
		"reward": "u_colossus_hammer", "lair": "Сборочный Цех №1", "lore": "Шагающая машина, построенная для войны, которая так и не началась. Его части можно разрушить."},
	"mech_lord": {"name": "Повелитель Механизмов", "era": 2, "rig": "humanoid", "scale": 1.6, "weapon": "tesla_staff", "armor": "steam_suit", "metal": true, "glow": Color(0.4, 0.7, 1.0),
		"cloth": Color(0.3, 0.25, 0.2), "hat": "goggles", "hp": 4200, "dmg": 55.0, "lvl": 7, "speed": 0.9, "dtype": "lightning",
		"abilities": {"strikes": {"type": "strikes", "dmg": 1.1, "count": 7, "dtype": "lightning", "cd": 6.0}, "summon": {"type": "summon", "enemy": "steam_spider", "count": 2, "cd": 16.0},
			"beam": {"type": "beam", "dmg": 1.2, "dtype": "lightning", "cd": 6.0}, "mines": {"type": "mines", "dmg": 1.3, "count": 8, "dtype": "lightning", "cd": 10.0}},
		"phases": [{"hp": 1.0, "use": ["beam", "summon"]}, {"hp": 0.6, "use": ["beam", "strikes", "mines"], "msg": "Электрические ловушки активированы!"},
			{"hp": 0.3, "use": ["strikes", "mines", "summon", "beam"], "msg": "Повелитель подключается к сети завода!", "enrage": true}],
		"reward": "u_mech_gauntlet", "lair": "Электростанция Тесла", "lore": "Инженер, сросшийся со своими машинами."},
	"phantom_commander": {"name": "Призрачный Командир", "era": 3, "rig": "humanoid", "scale": 1.5, "weapon": "carbine", "armor": "vest", "cloth": Color(0.1, 0.1, 0.12), "hat": "tac_helm",
		"hp": 7000, "dmg": 80.0, "lvl": 6, "speed": 1.1, "dtype": "pierce",
		"abilities": {"fan": {"type": "fan", "dmg": 0.6, "count": 6, "dtype": "pierce", "cd": 2.2}, "blink": {"type": "blink", "cd": 5.0}, "summon": {"type": "summon", "enemy": "merc_soldier", "count": 3, "cd": 18.0},
			"volley": {"type": "volley", "dmg": 1.4, "count": 6, "dtype": "fire", "cd": 9.0}},
		"phases": [{"hp": 1.0, "use": ["fan", "blink"]}, {"hp": 0.6, "use": ["fan", "blink", "summon"], "msg": "Командир вызывает подкрепление!"},
			{"hp": 0.3, "use": ["fan", "volley", "blink", "summon"], "msg": "Авиаудар по координатам!", "enrage": true}],
		"reward": "u_phantom_blade", "lair": "База «Тень»", "lore": "Командир, которого официально не существует."},
	"exp_guardian": {"name": "Экспериментальный Страж", "era": 3, "rig": "troll", "scale": 2.2, "body": Color(0.5, 0.6, 0.7), "glow": Color(0.3, 0.8, 1.0), "hp": 8000, "dmg": 90.0, "lvl": 7, "speed": 0.9, "dtype": "energy",
		"abilities": {"slam": {"type": "slam", "dmg": 1.5, "radius": 5.5, "cd": 5.0}, "charge": {"type": "charge", "dmg": 1.3, "cd": 7.0}, "beam": {"type": "beam", "dmg": 1.3, "dtype": "energy", "cd": 7.0},
			"nova": {"type": "nova", "dmg": 1.1, "radius": 8.0, "dtype": "lightning", "cd": 11.0}},
		"phases": [{"hp": 1.0, "use": ["slam", "charge"]}, {"hp": 0.6, "use": ["slam", "charge", "beam"], "msg": "Страж выходит из-под контроля!"},
			{"hp": 0.3, "use": ["slam", "beam", "nova", "charge"], "msg": "Сдерживающее поле разрушено!", "enrage": true, "form": 1.2}],
		"reward": "u_guardian_core", "lair": "Лаборатория 9", "lore": "Результат слияния магии и генной инженерии."},
	"combat_complex": {"name": "Автономный Боевой Комплекс", "era": 3, "rig": "colossus", "scale": 2.2, "body": Color(0.3, 0.32, 0.3), "metal": true, "hp": 8500, "dmg": 85.0, "lvl": 7, "speed": 0.7, "dtype": "pierce",
		"parts": {"left_arm": 1500, "right_arm": 1500, "boiler": 2000},
		"abilities": {"fan": {"type": "fan", "dmg": 0.6, "count": 8, "dtype": "pierce", "cd": 2.5, "part": "right_arm"}, "missiles": {"type": "missiles", "dmg": 1.0, "count": 6, "dtype": "fire", "cd": 8.0, "part": "left_arm"},
			"summon": {"type": "summon", "enemy": "combat_drone", "count": 3, "cd": 18.0}, "nova": {"type": "nova", "dmg": 1.0, "radius": 8.0, "dtype": "lightning", "cd": 12.0, "part": "boiler"}},
		"phases": [{"hp": 1.0, "use": ["fan", "missiles"]}, {"hp": 0.6, "use": ["fan", "missiles", "summon"], "msg": "Комплекс выпускает рой дронов!"},
			{"hp": 0.3, "use": ["fan", "missiles", "nova", "summon"], "msg": "Протокол уничтожения активирован!", "enrage": true}],
		"reward": "u_autonomous_rifle", "lair": "Военная база «Цитадель»", "lore": "Боевая машина, решившая, что люди — угроза."},
	"rift_archon": {"name": "Архонт Разлома", "era": 4, "rig": "humanoid", "scale": 1.9, "weapon": "blade_energy", "armor": "energy_armor", "glow": Color(0.4, 1.0, 0.9), "cloth": Color(0.1, 0.3, 0.35),
		"hp": 12000, "dmg": 120.0, "lvl": 6, "speed": 1.0, "dtype": "time",
		"abilities": {"cleave": {"type": "cleave", "dmg": 1.4, "radius": 4.5, "arc": 140.0, "cd": 2.5}, "blink": {"type": "blink", "cd": 5.0}, "portal": {"type": "portal", "dimension": "future_rift", "cd": 999.0},
			"slowzone": {"type": "slowzone", "cd": 12.0}, "strikes": {"type": "strikes", "dmg": 1.2, "count": 8, "dtype": "time", "cd": 7.0}, "summon": {"type": "summon", "enemy": "chrono_anomaly", "count": 2, "cd": 20.0}},
		"phases": [{"hp": 1.0, "use": ["cleave", "blink", "slowzone"]}, {"hp": 0.6, "use": ["portal", "cleave", "strikes", "blink"], "msg": "Архонт затягивает вас в Разлом будущего!"},
			{"hp": 0.3, "use": ["cleave", "strikes", "summon", "slowzone"], "msg": "Время распадается!", "enrage": true}],
		"reward": "u_archon_blade", "lair": "Якорь Разлома", "lore": "Страж между временами."},
	"synth_emperor": {"name": "Синтетический Император", "era": 4, "rig": "humanoid", "scale": 1.8, "weapon": "plasma_cannon", "armor": "android", "robot": true, "metal": true, "glow": Color(1.0, 0.2, 0.25),
		"hp": 13000, "dmg": 130.0, "lvl": 7, "speed": 0.9, "dtype": "energy",
		"abilities": {"beam": {"type": "beam", "dmg": 1.4, "dtype": "energy", "cd": 5.0}, "missiles": {"type": "missiles", "dmg": 1.1, "count": 6, "dtype": "energy", "cd": 7.0},
			"summon": {"type": "summon", "enemy": "android", "count": 3, "cd": 18.0}, "shield": {"type": "shield", "enemy": "combat_robot", "count": 2, "cd": 30.0}, "nova": {"type": "nova", "dmg": 1.2, "radius": 8.0, "dtype": "energy", "cd": 10.0}},
		"phases": [{"hp": 1.0, "use": ["beam", "missiles"]}, {"hp": 0.6, "use": ["beam", "missiles", "shield", "summon"], "msg": "Император вызывает Легион!"},
			{"hp": 0.3, "use": ["beam", "nova", "missiles", "summon"], "msg": "Император загружает боевое ядро!", "enrage": true}],
		"reward": "u_emperor_crown", "lair": "Тронный Узел", "lore": "Первый ИИ, объявивший себя правителем."},
	"chrono_devourer": {"name": "Хронопожиратель", "era": 4, "rig": "wraith", "scale": 3.0, "body": Color(0.3, 0.9, 0.8, 0.7), "glow": Color(0.5, 1.0, 0.9), "hp": 16000, "dmg": 140.0, "lvl": 8, "speed": 0.9, "dtype": "time",
		"abilities": {"strikes": {"type": "strikes", "dmg": 1.2, "count": 9, "dtype": "time", "cd": 5.0}, "slowzone": {"type": "slowzone", "cd": 10.0}, "nova": {"type": "nova", "dmg": 1.3, "radius": 9.0, "dtype": "time", "cd": 9.0},
			"summon": {"type": "summon", "enemy": "chrono_soldier", "count": 3, "cd": 16.0}, "blink": {"type": "blink", "cd": 6.0}, "volley": {"type": "volley", "dmg": 1.5, "count": 8, "dtype": "time", "cd": 9.0}},
		"phases": [{"hp": 1.0, "use": ["strikes", "slowzone", "blink"]}, {"hp": 0.6, "use": ["strikes", "nova", "summon"], "msg": "Хронопожиратель поглощает эпохи!"},
			{"hp": 0.3, "use": ["volley", "nova", "summon", "slowzone", "blink"], "msg": "Конец времени близок!", "enrage": true, "form": 1.3}],
		"reward": "u_chrono_reaver", "lair": "Сердце Хроноса", "lore": "Существо, питающееся самой историей."},
	# Trial guardian (Chronos Trial final stage), era-scaled at runtime
	"chronos_avatar": {"name": "Аватар Хроноса", "era": -1, "rig": "humanoid", "scale": 2.0, "weapon": "staff_chrono", "armor": "energy_armor", "glow": Color(1.0, 0.85, 0.3), "cloth": Color(0.6, 0.5, 0.2),
		"hp": 1600, "dmg": 26.0, "lvl": 8, "speed": 1.0, "dtype": "time",
		"abilities": {"strikes": {"type": "strikes", "dmg": 1.0, "count": 6, "dtype": "time", "cd": 6.0}, "blink": {"type": "blink", "cd": 5.0}, "nova": {"type": "nova", "dmg": 1.0, "radius": 7.0, "dtype": "time", "cd": 9.0},
			"fan": {"type": "fan", "dmg": 0.8, "count": 5, "dtype": "time", "cd": 3.0}, "slowzone": {"type": "slowzone", "cd": 12.0}},
		"phases": [{"hp": 1.0, "use": ["fan", "blink"]}, {"hp": 0.6, "use": ["fan", "strikes", "slowzone"], "msg": "Хронос испытывает вашу силу!"},
			{"hp": 0.3, "use": ["fan", "strikes", "nova", "blink"], "msg": "Последнее испытание!", "enrage": true}],
		"reward": "", "lair": "Суд Хроноса", "lore": "Воплощение самого времени."},
}

const ARCHETYPES := {
	"aggressive": {"name": "Агрессивный", "aggr": 1.0, "caution": 0.15, "greed": 0.4, "curious": 0.3, "loyal": 0.4, "venge": 0.6, "ambition": 0.6},
	"cautious": {"name": "Осторожный", "aggr": 0.25, "caution": 0.95, "greed": 0.5, "curious": 0.4, "loyal": 0.6, "venge": 0.3, "ambition": 0.4},
	"hunter": {"name": "Охотник", "aggr": 0.8, "caution": 0.4, "greed": 0.3, "curious": 0.4, "loyal": 0.4, "venge": 0.5, "ambition": 0.7},
	"gatherer": {"name": "Собиратель", "aggr": 0.3, "caution": 0.6, "greed": 0.9, "curious": 0.5, "loyal": 0.5, "venge": 0.2, "ambition": 0.5},
	"opportunist": {"name": "Приспособленец", "aggr": 0.55, "caution": 0.6, "greed": 0.8, "curious": 0.4, "loyal": 0.15, "venge": 0.4, "ambition": 0.7},
	"defender": {"name": "Защитник", "aggr": 0.5, "caution": 0.5, "greed": 0.3, "curious": 0.2, "loyal": 1.0, "venge": 0.5, "ambition": 0.3},
	"treasure": {"name": "Искатель сокровищ", "aggr": 0.35, "caution": 0.55, "greed": 1.0, "curious": 0.9, "loyal": 0.3, "venge": 0.3, "ambition": 0.6},
	"ambitious": {"name": "Честолюбивый", "aggr": 0.7, "caution": 0.4, "greed": 0.6, "curious": 0.5, "loyal": 0.5, "venge": 0.5, "ambition": 1.0},
	"vengeful": {"name": "Мстительный", "aggr": 0.65, "caution": 0.4, "greed": 0.4, "curious": 0.3, "loyal": 0.5, "venge": 1.0, "ambition": 0.5},
	"explorer": {"name": "Исследователь", "aggr": 0.35, "caution": 0.5, "greed": 0.5, "curious": 1.0, "loyal": 0.4, "venge": 0.3, "ambition": 0.5},
}

const NAMES_M := [
	["Эдгар", "Бран", "Ульрих", "Готфрид", "Ранульф", "Освальд", "Тибальд", "Конрад", "Роланд", "Гарет", "Седрик", "Альрик", "Бертран", "Хаген", "Вильгельм"],
	["Лоренцо", "Джакомо", "Марко", "Витторио", "Рафаэль", "Бенедетто", "Андреа", "Фабио", "Сальваторе", "Томмазо", "Дарио", "Чезаре"],
	["Артур", "Виктор", "Эдмунд", "Генри", "Чарльз", "Томас", "Фредерик", "Гарольд", "Освин", "Бенджамин", "Сэмюэл", "Грегори"],
	["Макс", "Алекс", "Дэн", "Игорь", "Марк", "Кирилл", "Рэй", "Стас", "Тим", "Глеб", "Роман", "Артём"],
	["Кай", "Зейн", "Орион", "Векс", "Рен", "Сайфер", "Аксиом", "Талос", "Ион", "Квазар", "Дрейк", "Сол"],
]
const NAMES_F := [
	["Изольда", "Агнесса", "Матильда", "Элеонора", "Гвен", "Ирма", "Хильда", "Бланка", "Ровена"],
	["Изабелла", "Лукреция", "Беатриче", "Франческа", "Катарина", "Джулия", "Симонетта", "Лаура"],
	["Ада", "Виктория", "Флоренс", "Эмили", "Маргарет", "Шарлотта", "Эвелин", "Грейс"],
	["Ника", "Ева", "Лана", "Кира", "Мира", "Яна", "Вера", "Алиса"],
	["Нова", "Лира", "Астра", "Сола", "Вега", "Ксения-9", "Аура", "Селена"],
]
const NICKNAMES := ["Однорукий", "Рыжий", "Тихий", "Беспощадный", "Счастливчик", "Хромой", "Седой", "Волк", "Ворон", "Молчун",
	"Кровавый", "Меткий", "Железный", "Хитрый", "Бешеный", "Пепельный", "Старый", "Быстрый", "Шрам", "Гроза"]
const BACKSTORY := {
	"origin": ["вырос в нищей деревне у реки", "был сыном кузнеца", "сбежал из монастыря", "служил в городской страже", "родился в семье торговцев",
		"был подкидышем, воспитанным бродячими артистами", "потерял семью во время набега", "был учеником старого мастера", "долгие годы скитался по дорогам",
		"рос в портовых трущобах"],
	"turn": ["пока однажды не нашёл в руинах странный клинок", "пока не задолжал опасным людям", "но мечтал о славе", "пока не увидел разлом времени своими глазами",
		"пока не поклялся отомстить", "но всегда искал богатства", "пока война не забрала у него всё", "пока не услышал легенды о героях прошлого"],
	"goal": ["Теперь он хочет стать легендой.", "Теперь его ведёт жажда золота.", "Теперь он ищет тех, кто виновен в его бедах.", "Теперь он ищет своё место в мире.",
		"Теперь он верит, что время можно покорить.", "Теперь он защищает слабых, как умеет."],
}

static func rand_name(era_i: int, female: bool, rng: RandomNumberGenerator) -> String:
	var arr: Array = NAMES_F[clampi(era_i, 0, 4)] if female else NAMES_M[clampi(era_i, 0, 4)]
	return arr[rng.randi() % arr.size()]

static func rand_archetype(rng: RandomNumberGenerator) -> String:
	var k := ARCHETYPES.keys()
	return k[rng.randi() % k.size()]

static func backstory(rng: RandomNumberGenerator, female: bool) -> String:
	var s: String = "%s %s, %s. %s" % [
		BACKSTORY.origin[rng.randi() % BACKSTORY.origin.size()],
		"", BACKSTORY.turn[rng.randi() % BACKSTORY.turn.size()], BACKSTORY.goal[rng.randi() % BACKSTORY.goal.size()]]
	s = s.replace("  ", " ").replace(" ,", ",")
	if female:
		s = s.replace("был ", "была ").replace("вырос", "выросла").replace("сбежал", "сбежала").replace("служил", "служила").replace("родился", "родилась") \
			.replace("потерял", "потеряла").replace("скитался", "скиталась").replace("рос ", "росла ").replace("нашёл", "нашла").replace("задолжал", "задолжала") \
			.replace("мечтал", "мечтала").replace("увидел", "увидела").replace("поклялся", "поклялась").replace("искал", "искала").replace("услышал", "услышала") \
			.replace("он ", "она ").replace("его ", "её ").replace("верит", "верит").replace("защищает", "защищает").replace("сыном", "дочерью").replace("учеником", "ученицей")
	return s.substr(0, 1).to_upper() + s.substr(1)
