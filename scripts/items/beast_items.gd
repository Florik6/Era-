class_name BeastItems
## Items of «Beasts of the Ages», kept apart from the 150-item catalogue:
## creature materials (crafting / selling), one unique relic per boss line
## (ids x_*), and a trophy for the house for each of the 40 bosses
## (trophy_<boss id>, placed with the housing furniture mode).

const MATS := {
	"beast_hide": ["Шкура зверя", 8], "beast_fang": ["Клык хищника", 10], "spider_silk": ["Паучий шёлк", 12], "venom_gland": ["Ядовая железа", 16],
	"crystal_shard": ["Осколок кристалла", 18], "stone_heart": ["Каменное сердце", 60], "bone_dust": ["Костяная пыль", 8], "spirit_essence": ["Эссенция духа", 30],
	"shadow_antler": ["Теневой рог", 25], "cursed_steel": ["Проклятая сталь", 28], "troll_blood": ["Кровь тролля", 35], "rune_stone": ["Рунный камень", 30],
	"ash_feather": ["Пепельное перо", 14], "worm_tooth": ["Зуб червя", 22], "living_wood": ["Живое дерево", 26], "fire_gland": ["Огненная железа", 24],
	"drake_scale": ["Драконья чешуя", 80], "mutagen": ["Мутаген", 20], "ectoplasm": ["Эктоплазма", 18], "arcane_dust": ["Арканная пыль", 22],
	"chitin": ["Хитин", 12], "marble_chunk": ["Обломок мрамора", 15], "sea_pearl": ["Морская жемчужина", 70], "scrap_alloy": ["Лом сплава", 14],
	"power_cell": ["Энергоячейка", 30], "coal_core": ["Угольное ядро", 26], "nanite_dust": ["Нанитовая пыль", 32], "phase_crystal": ["Фазовый кристалл", 40],
	"coin_pouch": ["Кошель гоблина", 35],
}
const RELICS := {
	"x_ore_mantle": ["Рудная мантия Гармона", 0, "+15% брони, удары оглушают чаще"], "x_oath_blade": ["Клятва Арктора", 0, "Реликвия рыцарского ордена"],
	"x_dragon_heart": ["Сердце Багровой Бездны", 0, "Мифическая реликвия: сопротивление огню"], "x_mountain_crown": ["Корона Хранителя Гор", 0, "Мифическая реликвия титана"],
	"x_astral_lens": ["Астральная линза", 1, "Реликвия механизма звёзд"], "x_factory_core": ["Ядро Мегазавода", 2, "Мифическая реликвия эпохи пара"],
	"x_omega_cell": ["Клетка ОМЕГИ", 3, "Мифическая реликвия комплекса"], "x_time_hourglass": ["Песочные часы Архимага", 4, "Реликвия последнего архимага"],
	"x_epoch_fang": ["Клык Пожирателя Эпох", 4, "Мифическая реликвия конца времён"],
}

static var _cache := {}

static func base(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var d := {}
	if MATS.has(id):
		d = {"name": MATS[id][0], "era": -1, "slot": "mat", "stack": true, "value": MATS[id][1], "group": "beast"}
	elif RELICS.has(id):
		d = {"name": RELICS[id][0], "era": RELICS[id][1], "slot": "amulet", "stack": false, "value": 900, "group": "relic", "desc": RELICS[id][2],
			"stats": {"hp": 40.0, "armor": 6.0}, "rarity_min": 4}
	elif id.begins_with("trophy_"):
		var b: Dictionary = DBBeasts.boss(id.trim_prefix("trophy_"))
		if not b.is_empty():
			d = {"name": "Трофей: %s" % b.name, "era": int(b.era), "slot": "home", "furniture": "trophy", "value": 500, "group": "home", "stack": false,
				"trophy_of": b.id, "src": ["boss"]}
	if not d.is_empty():
		_cache[id] = d
	return d

static func has(id: String) -> bool:
	return not base(id).is_empty()

static func count() -> Dictionary:
	return {"mats": MATS.size(), "relics": RELICS.size(), "trophies": DBBeasts.bosses().size()}
