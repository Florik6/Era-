class_name ItemCatalog
## Expansion catalog: exactly 150 new items (45 weapons incl. 10 legendary and
## 5 mythic, 30 armour/clothing pieces, 25 accessories, 30 resources /
## materials / medicine, 20 home furnishings), 30 per era. Each entry has an
## id, era, name, description, stats, rarity, model, purpose, value and the
## ways to obtain it ("src": shop, craft, drop, event, boss, quest).
## ItemDB.base() falls back to this table, so the rest of the game (drops,
## trade, crafting, equipment, saves) treats these like any other base.

const ERA_ARMOR := [1.0, 1.3, 1.7, 2.2, 2.8]
static var _exp: Dictionary = {}

static func W(id: String, era: int, name: String, cat: String, model: String, dmg: float, spd: float, rng: float, dtype: String, value: int, o: Dictionary = {}) -> Array:
	var d := {"name": name, "era": era, "slot": "main", "cat": cat, "dmg": dmg, "spd": spd, "range": rng, "dtype": dtype, "model": model, "value": value,
		"group": "weapon", "src": o.get("src", ["shop", "drop", "craft"])}
	for k in o:
		d[k] = o[k]
	return [id, d]

static func A(id: String, era: int, name: String, slot: String, model: String, armor: float, value: int, o: Dictionary = {}) -> Array:
	var d := {"name": name, "era": era, "slot": slot, "armor": snappedf(armor * ERA_ARMOR[era], 0.1), "model": model, "value": value,
		"group": "armor", "src": o.get("src", ["shop", "drop", "craft"])}
	for k in o:
		if k != "src":
			d[k] = o[k]
	return [id, d]

static func X(id: String, era: int, name: String, slot: String, stats: Dictionary, value: int, o: Dictionary = {}) -> Array:
	var d := {"name": name, "era": era, "slot": slot, "model": "ring" if slot == "ring" else ("amulet" if slot == "amulet" else "module"), "value": value,
		"group": "accessory", "src": o.get("src", ["shop", "drop", "event", "craft"])}
	for k in stats:
		d[k] = stats[k]
	for k in o:
		if k != "src":
			d[k] = o[k]
	return [id, d]

static func R(id: String, era: int, name: String, kind: String, value: int, o: Dictionary = {}) -> Array:
	var d := {"name": name, "era": era, "slot": "use" if kind == "med" else "mat", "stack": true, "value": value, "group": "resource" if kind != "med" else "medicine",
		"src": o.get("src", ["shop", "craft", "event"])}
	if kind == "med":
		d["effect"] = "med"
	for k in o:
		if k != "src":
			d[k] = o[k]
	return [id, d]

static func H(id: String, era: int, name: String, furn: String, value: int, o: Dictionary = {}) -> Array:
	var d := {"name": name, "era": era, "slot": "home", "furniture": furn, "value": value, "group": "home", "stack": false,
		"src": o.get("src", ["shop", "craft"])}
	for k in o:
		if k != "src":
			d[k] = o[k]
	return [id, d]

static func all() -> Dictionary:
	if _exp.is_empty():
		for pair in _build():
			_exp[pair[0]] = pair[1]
	return _exp

static func base(id: String) -> Dictionary:
	return all().get(id, {})

static func has(id: String) -> bool:
	return all().has(id)

static func ids_by(group: String, era := -1) -> Array:
	var out: Array = []
	var a := all()
	for k in a:
		if a[k].group == group and (era < 0 or int(a[k].era) == era):
			out.append(k)
	return out

## Base ids event merchants bring for a stock category.
static func special_stock(era: int, cat: String) -> Array:
	var out: Array = []
	var a := all()
	for k in a:
		var b: Dictionary = a[k]
		if int(b.era) != era or not "event" in b.src:
			continue
		match cat:
			"food", "medicine":
				if b.group == "medicine":
					out.append(k)
			"goods":
				if b.group in ["resource", "home"]:
					out.append(k)
			"luxury", "iron":
				if b.group in ["accessory", "resource"]:
					out.append(k)
	return out

## Named legendary / mythic weapon with its fixed weapon art.
static func create_named(id: String, lvl: int = 1) -> Dictionary:
	var b := base(id)
	if b.is_empty() or not b.has("art"):
		return {}
	var it := ItemDB.create(id, int(b.rarity), lvl, null, false)
	it.ability = ""
	it.mythic = ""
	it.art = b.art
	it.name = b.name
	it.curse = {}
	return it

static func _build() -> Array:
	var L: Array = []
	# ============================== I. Medieval (30)
	L.append(W("x_border_sword", 0, "Меч пограничника", "sword", "sword", 16.0, 1.5, 2.4, "slash", 70, {"desc": "Надёжный клинок дозорных северной границы."}))
	L.append(W("x_north_axe", 0, "Северный топор", "heavy", "greataxe", 24.0, 0.85, 2.6, "slash", 85, {"two_h": true, "desc": "Тяжёлый топор северян, рубит щиты."}))
	L.append(W("x_watch_spear", 0, "Копьё дозорного", "spear", "spear", 17.0, 1.2, 3.5, "pierce", 65, {"two_h": true, "desc": "Длинное копьё сторожевых башен."}))
	L.append(W("x_chapel_crossbow", 0, "Арбалет часовни", "bow", "crossbow", 22.0, 0.75, 27.0, "pierce", 90, {"two_h": true, "proj": "bolt", "desc": "Освящённый арбалет храмовой стражи."}))
	L.append(W("x_marsh_bow", 0, "Лук болотного следопыта", "bow", "longbow", 16.0, 1.05, 30.0, "pierce", 80, {"two_h": true, "proj": "arrow", "desc": "Гибкий лук из болотного тиса."}))
	L.append(W("x_ash_staff", 0, "Посох пепельника", "staff", "staff", 13.0, 1.2, 21.0, "fire", 85, {"two_h": true, "proj": "magic", "mana": 30, "desc": "Посох Круга Пепельных Магов."}))
	L.append(W("x_ash_king_blade", 0, "Клинок Пепельного Короля", "sword", "sword", 28.0, 1.45, 2.6, "fire", 900, {"rarity": 4, "art": "ashen_verdict", "src": ["boss", "craft"], "desc": "Легендарный меч павшего короля. «Пепельный приговор»: огненный разрез, копящий метки жара."}))
	L.append(W("x_thousand_lightning_bow", 0, "Лук Тысячи Зарниц", "bow", "longbow", 24.0, 1.1, 32.0, "lightning", 900, {"rarity": 4, "art": "lightning_rain", "two_h": true, "proj": "arrow", "src": ["boss", "event"], "desc": "Легендарный лук. «Дождь зарниц»: после идеального уклонения — серия магических стрел."}))
	L.append(W("x_eclipse_heart", 0, "Сердце Затмения", "sword", "greatsword", 34.0, 0.9, 2.9, "dark", 2500, {"rarity": 5, "art": "lesser_eclipse", "two_h": true, "src": ["boss"], "desc": "Мифический клинок. Копит энергию заблокированных атак и высвобождает «Малое Затмение»."}))
	L.append(A("x_bo_helm", 0, "Шлем Чёрной заставы", "head", "greathelm", 6.0, 60, {"hp": 10, "set": "black_outpost", "desc": "Глухой шлем гарнизона Чёрной заставы."}))
	L.append(A("x_bo_cuirass", 0, "Кираса Чёрной заставы", "body", "plate", 16.0, 120, {"hp": 30, "speed": -0.04, "set": "black_outpost", "desc": "Воронёная кираса заставы."}))
	L.append(A("x_bo_bracers", 0, "Наручи Чёрной заставы", "hands", "gauntlets", 3.5, 45, {"set": "black_outpost", "desc": "Стальные наручи с заклёпками."}))
	L.append(A("x_bo_greaves", 0, "Поножи Чёрной заставы", "legs", "greaves_plate", 7.0, 55, {"set": "black_outpost", "desc": "Латные поножи заставы."}))
	L.append(A("x_bo_boots", 0, "Сапоги Чёрной заставы", "feet", "sabatons", 3.5, 40, {"set": "black_outpost", "desc": "Тяжёлые сапоги дозора."}))
	L.append(A("x_bo_cloak", 0, "Плащ Чёрной заставы", "cloak", "cloak_wool", 2.0, 45, {"res_ice": 0.08, "color": Color(0.12, 0.12, 0.14), "set": "black_outpost", "desc": "Шерстяной плащ ночного дозора."}))
	L.append(X("x_herbalist_ring", 0, "Перстень травницы", "ring", {"regen": 0.6, "hp": 10}, 70, {"desc": "Ускоряет заживление."}))
	L.append(X("x_first_knight_medal", 0, "Медальон Первого Рыцаря", "amulet", {"armor": 4.0, "hp": 20}, 120, {"src": ["quest", "drop", "event"], "desc": "Медальон основателя ордена."}))
	L.append(X("x_whisper_bead", 0, "Бусина Шёпота", "amulet", {"mana": 25, "spell": 0.05}, 90, {"desc": "Шепчет подсказки заклинателю."}))
	L.append(X("x_wolf_path_charm", 0, "Оберег Волчьей Тропы", "ring", {"speed": 0.04, "detect": 0.2}, 80, {"desc": "Ведёт тропами волков."}))
	L.append(X("x_stone_guard_seal", 0, "Печать Каменного Стража", "module", {"armor": 6.0, "res_fire": 0.05}, 100, {"desc": "Каменная печать древнего стража."}))
	L.append(R("linen_bandage", 0, "Льняной бинт", "med", 8, {"med": {"bleed": 1, "heal": 0.06}, "desc": "Останавливает лёгкое кровотечение."}))
	L.append(R("cleansing_tincture", 0, "Очищающая настойка", "med", 14, {"med": {"infection": 1, "heal": 0.04}, "desc": "Промывает рану, снижает риск заражения."}))
	L.append(R("healer_thistle", 0, "Чертополох лекаря", "med", 6, {"med": {"pain": 1, "heal": 0.03}, "src": ["shop", "event", "drop"], "desc": "Лечебная трава, растёт за городом."}))
	L.append(R("iron_ingot", 0, "Железный слиток", "mat", 12, {"src": ["shop", "craft", "drop", "event"], "desc": "Основа кузнечного ремесла."}))
	L.append(R("enchanted_leather", 0, "Зачарованная кожа", "mat", 25, {"desc": "Кожа, пропитанная рунами."}))
	L.append(R("ash_crystal", 0, "Пепельный кристалл", "mat", 40, {"src": ["drop", "event", "shop"], "desc": "Кристалл из пепла древних костров. Нужен для легендарного ремесла."}))
	L.append(H("x_oak_chest", 0, "Сундук дубового дома", "chest", 80, {"capacity": 20, "desc": "Личное хранилище на 20 мест."}))
	L.append(H("x_sword_mount", 0, "Настенный держатель мечей", "weapon_rack", 60, {"capacity": 4, "desc": "Выставляет 4 клинка на стене."}))
	L.append(H("x_mason_hearth", 0, "Очаг каменщика", "hearth", 110, {"rest": 0.1, "desc": "Тёплый очаг: отдых восстанавливает больше."}))
	L.append(H("x_traveler_bed", 0, "Кровать путешественника", "bed", 70, {"rest": 0.25, "desc": "Сон восстанавливает силы и раны."}))
	# ============================== II. Renaissance (30)
	L.append(W("x_noble_rapier", 1, "Рапира дворянина", "sword", "rapier", 21.0, 1.95, 2.6, "pierce", 120, {"desc": "Изящная рапира с позолоченной гардой."}))
	L.append(W("x_wheellock_pistol", 1, "Колесцовый пистолет", "firearm", "pistol_old", 32.0, 0.9, 18.0, "pierce", 130, {"proj": "bullet", "mag": 2, "reload": 1.9, "spread": 4.0, "desc": "Пистолет с колесцовым замком."}))
	L.append(W("x_harbor_musket", 1, "Мушкет портового караула", "firearm", "musket", 50.0, 0.6, 31.0, "pierce", 150, {"two_h": true, "proj": "bullet", "mag": 1, "reload": 2.1, "spread": 3.0, "desc": "Тяжёлый мушкет портовой стражи."}))
	L.append(W("x_cartographer_dagger", 1, "Кинжал картографа", "dagger", "dagger", 14.0, 2.6, 1.8, "pierce", 90, {"detect": 0.2, "desc": "Тонкий кинжал с гравированной картой."}))
	L.append(W("x_alch_wand", 1, "Алхимический жезл", "staff", "staff_alch", 18.0, 1.3, 22.0, "fire", 140, {"two_h": true, "proj": "magic", "mana": 40, "desc": "Жезл, наполненный летучими эссенциями."}))
	L.append(W("x_sea_saber", 1, "Морская сабля", "sword", "saber", 22.0, 1.65, 2.4, "slash", 110, {"desc": "Сабля абордажной команды."}))
	L.append(W("x_scarlet_comet_rapier", 1, "Рапира Алой Кометы", "sword", "rapier", 32.0, 2.0, 2.7, "pierce", 1100, {"rarity": 4, "art": "comet_dance", "src": ["boss", "event"], "desc": "Легенда. «Танец кометы»: стремительная контратака после парирования."}))
	L.append(W("x_clockmaker_pistol", 1, "Пистолет Часовщика", "firearm", "pistol_old", 40.0, 1.0, 20.0, "pierce", 1100, {"rarity": 4, "art": "deferred_shot", "proj": "bullet", "mag": 3, "reload": 1.6, "spread": 2.5, "src": ["boss", "craft"], "desc": "Легенда. «Выстрел отсрочки»: дополнительное отложенное попадание."}))
	L.append(W("x_astrolabe_of_fates", 1, "Астролябия Судеб", "staff", "focus", 36.0, 1.4, 24.0, "time", 3000, {"rarity": 5, "art": "threads_of_fate", "proj": "magic", "mana": 70, "src": ["boss"], "desc": "Миф. Плетёт «Нити Судеб» и предвидит опасные атаки."}))
	L.append(A("x_duel_mask", 1, "Маска дуэлянта", "head", "mask", 5.0, 80, {"crit": 0.03, "set": "duelist", "desc": "Бархатная полумаска."}))
	L.append(A("x_duel_doublet", 1, "Камзол дуэлянта", "body", "doublet", 12.0, 140, {"hp": 25, "speed": 0.03, "set": "duelist", "desc": "Стёганый камзол фехтовальщика."}))
	L.append(A("x_duel_gloves", 1, "Кожаные перчатки дуэлянта", "hands", "gloves", 3.0, 60, {"aspd": 0.06, "set": "duelist", "desc": "Тонкие перчатки для рапиры."}))
	L.append(A("x_duel_trousers", 1, "Штаны дуэлянта", "legs", "trousers", 5.0, 60, {"speed": 0.02, "set": "duelist", "desc": "Плотные штаны с кожаными вставками."}))
	L.append(A("x_duel_boots", 1, "Сапоги дуэлянта", "feet", "boots", 3.0, 60, {"speed": 0.04, "set": "duelist", "desc": "Высокие сапоги для выпадов."}))
	L.append(A("x_duel_cloak", 1, "Плащ дуэлянта", "cloak", "cloak_duelist", 2.0, 70, {"crit": 0.02, "color": Color(0.5, 0.08, 0.12), "set": "duelist", "desc": "Короткий бордовый плащ."}))
	L.append(X("x_alch_ring", 1, "Перстень алхимика", "ring", {"res_fire": 0.1, "res_ice": 0.1, "mana": 15}, 110, {"desc": "Защищает от едких паров."}))
	L.append(X("x_navigator_watch", 1, "Часы навигатора", "module", {"speed": 0.04, "aspd": 0.03}, 130, {"desc": "Хронометр мореплавателя."}))
	L.append(X("x_captain_medal", 1, "Медальон капитана", "amulet", {"hp": 25, "crit": 0.03}, 140, {"src": ["quest", "drop", "event"], "desc": "Знак капитана флота."}))
	L.append(X("x_explorer_lens", 1, "Линза первооткрывателя", "module", {"detect": 0.35}, 120, {"desc": "Подсвечивает тайники и следы."}))
	L.append(X("x_secret_guild_brooch", 1, "Брошь тайной гильдии", "amulet", {"crit": 0.05}, 150, {"src": ["event", "quest", "drop"], "desc": "Знак членов тайного общества."}))
	L.append(R("gauze_bandage", 1, "Марлевый бинт", "med", 12, {"med": {"bleed": 2, "heal": 0.08}, "desc": "Останавливает среднее кровотечение."}))
	L.append(R("alch_antiseptic", 1, "Алхимический антисептик", "med", 20, {"med": {"infection": 2, "heal": 0.04}, "desc": "Обеззараживает раны."}))
	L.append(R("moon_salt_extract", 1, "Экстракт лунной соли", "med", 30, {"med": {"magic": 1, "heal": 0.05}, "desc": "Снимает магическое повреждение."}))
	L.append(R("brass_blank", 1, "Латунная заготовка", "mat", 18, {"desc": "Заготовка для механизмов."}))
	L.append(R("alch_glassware", 1, "Набор алхимических стёкол", "mat", 30, {"desc": "Колбы и реторты для зелий."}))
	L.append(R("silver_powder", 1, "Серебряный порошок", "mat", 35, {"src": ["shop", "event", "drop"], "desc": "Против нечисти и для чар."}))
	L.append(H("x_duelist_wardrobe", 1, "Шкаф дуэлянта", "wardrobe", 120, {"capacity": 12, "desc": "Хранит комплекты экипировки."}))
	L.append(H("x_alchemy_table", 1, "Алхимический стол", "alchemy", 180, {"desc": "Домашняя алхимия: лекарства и эликсиры."}))
	L.append(H("x_mariner_chest", 1, "Сундук мореплавателя", "chest", 140, {"capacity": 28, "desc": "Окованный сундук на 28 мест."}))
	L.append(H("x_world_map", 1, "Настенная карта мира", "map", 90, {"desc": "Показывает открытые места и события."}))
	# ============================== III. Industrial (30)
	L.append(W("x_steam_hammer", 2, "Паровой молот", "heavy", "steam_hammer", 46.0, 0.75, 2.6, "blunt", 240, {"two_h": true, "desc": "Молот с паровым поршнем."}))
	L.append(W("x_mechanic_revolver", 2, "Револьвер механика", "firearm", "revolver", 36.0, 2.0, 22.0, "pierce", 220, {"proj": "bullet", "mag": 6, "reload": 1.7, "spread": 3.2, "desc": "Надёжный шестизарядник."}))
	L.append(W("x_iron_guard_carbine", 2, "Карабин Железной Гвардии", "firearm", "rifle", 54.0, 1.2, 34.0, "pierce", 260, {"two_h": true, "proj": "bullet", "mag": 8, "reload": 2.0, "spread": 2.0, "desc": "Табельный карабин гвардии."}))
	L.append(W("x_miner_bayonet", 2, "Штык шахтёра", "dagger", "dagger", 26.0, 2.4, 1.9, "pierce", 150, {"desc": "Короткий штык из рудничной стали."}))
	L.append(W("x_shock_club", 2, "Электрическая дубинка", "heavy", "baton", 34.0, 1.4, 2.2, "lightning", 200, {"desc": "Бьёт током при ударе."}))
	L.append(W("x_automaton_staff", 2, "Автоматонный посох", "staff", "staff_tech", 30.0, 1.3, 22.0, "lightning", 230, {"two_h": true, "proj": "magic", "mana": 50, "desc": "Посох на шестернях и лампах."}))
	L.append(W("x_nine_towers_thunder", 2, "Громобой Девяти Башен", "heavy", "steam_hammer", 60.0, 0.8, 2.8, "lightning", 1400, {"rarity": 4, "art": "ninth_thunder", "two_h": true, "src": ["boss", "craft"], "desc": "Легенда. «Удар девятого грома»: круговая электрическая волна."}))
	L.append(W("x_red_gear_revolver", 2, "Револьвер Красной Шестерни", "firearm", "revolver", 44.0, 2.1, 23.0, "pierce", 1400, {"rarity": 4, "art": "mechanist_ricochet", "proj": "bullet", "mag": 6, "reload": 1.5, "spread": 2.8, "src": ["boss", "event"], "desc": "Легенда. «Рикошет механиста»: ограниченная цепь попаданий."}))
	L.append(W("x_steam_storm_heart", 2, "Сердце Паровой Бури", "staff", "staff_tech", 52.0, 1.3, 24.0, "lightning", 3500, {"rarity": 5, "art": "steam_storm", "two_h": true, "proj": "magic", "mana": 80, "src": ["boss"], "desc": "Миф. Паровой катаклизм и электрический шторм с перегревом."}))
	L.append(A("x_steel_helm", 2, "Шлем сталелитейщика", "head", "pith", 6.0, 110, {"res_fire": 0.08, "set": "steelworker", "desc": "Шлем с защитным стеклом."}))
	L.append(A("x_steel_chest", 2, "Нагрудник сталелитейщика", "body", "steam_suit", 16.0, 220, {"hp": 45, "res_fire": 0.1, "set": "steelworker", "desc": "Клёпаный нагрудник литейщика."}))
	L.append(A("x_mech_bracers", 2, "Механические наручи", "hands", "gauntlets", 3.5, 100, {"aspd": 0.04, "set": "steelworker", "desc": "Наручи с пружинными приводами."}))
	L.append(A("x_reinforced_greaves", 2, "Усиленные поножи", "legs", "greaves_mech", 7.0, 110, {"set": "steelworker", "desc": "Поножи со стальными пластинами."}))
	L.append(A("x_steam_boots", 2, "Паровые сапоги", "feet", "boots", 3.5, 120, {"speed": 0.06, "set": "steelworker", "desc": "Сапоги с паровыми толкателями."}))
	L.append(A("x_chimney_cloak", 2, "Плащ дымоходов", "cloak", "cloak_soot", 2.0, 100, {"res_fire": 0.08, "color": Color(0.22, 0.2, 0.19), "set": "steelworker", "desc": "Плотный прокопчённый плащ."}))
	L.append(X("x_tesla_coil", 2, "Катушка Теслы", "module", {"spell": 0.06, "res_lightning": 0.1}, 180, {"desc": "Подпитывает электрические чары."}))
	L.append(X("x_miner_compass", 2, "Компас шахтёра", "module", {"detect": 0.4}, 120, {"desc": "Указывает на руду и тайники."}))
	L.append(X("x_element_valve", 2, "Вентиль стихий", "amulet", {"res_fire": 0.1, "res_ice": 0.1}, 170, {"desc": "Сбрасывает избыток стихийной энергии."}))
	L.append(X("x_engineer_monocle", 2, "Монокль инженера", "ring", {"crit": 0.05}, 160, {"desc": "Видит слабые места механизмов."}))
	L.append(X("x_iron_guard_token", 2, "Жетон Железной Гвардии", "amulet", {"armor": 8.0, "hp": 20}, 150, {"src": ["quest", "drop", "event"], "desc": "Знак заслуг гвардейца."}))
	L.append(R("sterile_dressing", 2, "Стерильная повязка", "med", 18, {"med": {"bleed": 2, "infection": 1, "heal": 0.08}, "desc": "Перевязка с обеззараживанием."}))
	L.append(R("antiseptic_solution", 2, "Антисептический раствор", "med", 22, {"med": {"infection": 2}, "desc": "Раствор против заражения."}))
	L.append(R("miner_medkit", 2, "Медицинский набор шахтёра", "med", 45, {"med": {"bleed": 2, "fracture": 1, "heal": 0.15}, "desc": "Шины, бинты и спирт: можно зафиксировать перелом."}))
	L.append(R("copper_winding", 2, "Медная обмотка", "mat", 20, {"desc": "Проволока для катушек и приводов."}))
	L.append(R("steel_plate", 2, "Стальная пластина", "mat", 28, {"src": ["shop", "craft", "drop", "event"], "desc": "Листовая сталь."}))
	L.append(R("ether_condensate", 2, "Эфирный конденсат", "mat", 50, {"src": ["drop", "event", "shop"], "desc": "Сгущённый эфир для легендарного ремесла."}))
	L.append(H("x_code_locker", 2, "Шкаф с кодовым замком", "chest", 200, {"capacity": 32, "desc": "Защищённый шкаф на 32 места."}))
	L.append(H("x_mech_workbench", 2, "Верстак механика", "workbench", 220, {"desc": "Домашняя мастерская: оружие и детали."}))
	L.append(H("x_stove_generator", 2, "Печь-генератор", "hearth", 180, {"rest": 0.12, "desc": "Тепло и свет для дома."}))
	L.append(H("x_relic_display", 2, "Витрина редких реликвий", "display", 160, {"capacity": 6, "desc": "Выставляет 6 реликвий."}))
	# ============================== IV. Modern (30)
	L.append(W("x_tactical_carbine", 3, "Тактический карабин", "firearm", "carbine", 42.0, 5.5, 32.0, "pierce", 320, {"two_h": true, "proj": "bullet", "mag": 30, "reload": 2.1, "spread": 2.5, "desc": "Компактный автоматический карабин."}))
	L.append(W("x_compact_pistol", 3, "Компактный пистолет", "firearm", "pistol", 30.0, 3.5, 20.0, "pierce", 220, {"proj": "bullet", "mag": 15, "reload": 1.3, "spread": 3.0, "desc": "Скрытого ношения."}))
	L.append(W("x_folding_knife", 3, "Складной боевой нож", "dagger", "dagger", 34.0, 2.7, 1.8, "slash", 180, {"desc": "Тактический нож с фиксатором."}))
	L.append(W("x_guard_shotgun", 3, "Дробовик охраны", "firearm", "shotgun", 25.0, 1.4, 13.0, "pierce", 280, {"two_h": true, "proj": "pellet", "pellets": 8, "mag": 6, "reload": 2.4, "spread": 7.0, "desc": "Помповый дробовик охраны."}))
	L.append(W("x_sniper_rifle", 3, "Снайперская винтовка", "firearm", "rifle", 120.0, 0.55, 48.0, "pierce", 420, {"two_h": true, "proj": "bullet", "mag": 5, "reload": 2.6, "spread": 0.5, "desc": "Дальнобойная винтовка с оптикой."}))
	L.append(W("x_shock_wand", 3, "Электрический боевой жезл", "staff", "focus", 40.0, 1.5, 22.0, "lightning", 300, {"proj": "magic", "mana": 55, "desc": "Боевой фокус с разрядником."}))
	L.append(W("x_helios_rifle", 3, "Штормовая винтовка «Гелиос»", "firearm", "carbine", 58.0, 4.5, 34.0, "lightning", 1700, {"rarity": 4, "art": "polar_volley", "two_h": true, "proj": "bullet", "mag": 30, "reload": 2.0, "spread": 2.0, "src": ["boss", "event"], "desc": "Легенда. «Полярный залп»: импульс, ослабляющий магическую защиту."}))
	L.append(W("x_silent_city_blade", 3, "Клинок Тихого Города", "sword", "katana", 62.0, 1.9, 2.6, "slash", 1700, {"rarity": 4, "art": "silent_cut", "src": ["boss", "craft"], "desc": "Легенда. «Беззвучный разрез»: особая контратака после уклонения."}))
	L.append(W("x_null_protocol", 3, "Нулевой Протокол", "firearm", "smart_gun", 70.0, 3.0, 30.0, "energy", 4000, {"rarity": 5, "art": "null_protocol", "proj": "bullet", "mag": 20, "reload": 1.8, "spread": 1.5, "src": ["boss"], "desc": "Миф. Пробивает энергетические защиты и создаёт пространственную нестабильность."}))
	L.append(A("x_op_helmet", 3, "Шлем оперативника", "head", "tac_helm", 6.0, 160, {"set": "operative", "desc": "Баллистический шлем."}))
	L.append(A("x_op_vest", 3, "Бронежилет оперативника", "body", "vest", 16.0, 300, {"hp": 55, "set": "operative", "desc": "Бронежилет с плитами."}))
	L.append(A("x_tac_gloves", 3, "Тактические перчатки", "hands", "gloves", 3.5, 120, {"aspd": 0.05, "set": "operative", "desc": "Перчатки с защитой костяшек."}))
	L.append(A("x_armored_pants", 3, "Армированные штаны", "legs", "pants_armored", 7.0, 150, {"set": "operative", "desc": "Штаны с наколенниками."}))
	L.append(A("x_silent_boots", 3, "Бесшумные ботинки", "feet", "boots", 3.5, 140, {"speed": 0.05, "stealth": 0.2, "set": "operative", "desc": "Мягкая подошва — тихий шаг."}))
	L.append(A("x_poncho", 3, "Защитное пончо", "cloak", "poncho", 2.0, 110, {"res_ice": 0.08, "color": Color(0.32, 0.36, 0.26), "set": "operative", "desc": "Непромокаемое пончо."}))
	L.append(X("x_wrist_analyzer", 3, "Наручный анализатор", "module", {"detect": 0.3, "regen": 0.4}, 200, {"desc": "Следит за здоровьем, предупреждает о кровотечении."}))
	L.append(X("x_survivor_medal", 3, "Медальон выжившего", "amulet", {"hp": 40}, 180, {"src": ["quest", "drop", "event"], "desc": "Для тех, кто прошёл через худшее."}))
	L.append(X("x_optic_module", 3, "Оптический модуль", "module", {"crit": 0.06}, 220, {"desc": "Прицельная оптика."}))
	L.append(X("x_guard_bracelet", 3, "Браслет защиты", "ring", {"armor": 10.0}, 200, {"desc": "Энергоплёнка на запястье."}))
	L.append(X("x_anomaly_sensor", 3, "Датчик аномалий", "amulet", {"res_time": 0.15, "detect": 0.2}, 230, {"src": ["event", "drop", "shop"], "desc": "Пищит рядом с разломами."}))
	L.append(R("hemostatic_dressing", 3, "Кровоостанавливающая повязка", "med", 28, {"med": {"bleed": 3, "heal": 0.1}, "desc": "Останавливает даже тяжёлое кровотечение."}))
	L.append(R("antiseptic_spray", 3, "Антисептический спрей", "med", 26, {"med": {"infection": 2, "heal": 0.03}, "desc": "Быстрая обработка ран."}))
	L.append(R("anti_infection_kit", 3, "Антиинфекционный медицинский комплект", "med", 60, {"med": {"infection": 3, "fracture": 1, "heal": 0.15}, "desc": "Полевая хирургия и антибиотики."}))
	L.append(R("polymer_sheet", 3, "Полимерный лист", "mat", 30, {"desc": "Лёгкий прочный материал."}))
	L.append(R("electronic_board", 3, "Электронная плата", "mat", 40, {"src": ["shop", "craft", "drop", "event"], "desc": "Схемы для устройств."}))
	L.append(R("battery_pack", 3, "Аккумуляторный блок", "mat", 45, {"desc": "Питание для техники и дома."}))
	L.append(H("x_bio_safe", 3, "Сейф с биометрическим замком", "chest", 320, {"capacity": 40, "desc": "Открывается только хозяином."}))
	L.append(H("x_gun_rack", 3, "Оружейная стойка", "weapon_rack", 200, {"capacity": 6, "desc": "Стойка на 6 единиц оружия."}))
	L.append(H("x_home_med_station", 3, "Домашняя медицинская станция", "med_station", 420, {"heal_tier": 2, "desc": "Лечит раны и осложнения дома."}))
	L.append(H("x_gear_diag_station", 3, "Станция диагностики экипировки", "workbench", 360, {"desc": "Ремонт и улучшение экипировки."}))
	# ============================== V. Future (30)
	L.append(W("x_plasma_blade", 4, "Плазменный клинок", "sword", "energy_blade", 70.0, 1.9, 2.7, "fire", 450, {"desc": "Клинок из удержанной плазмы."}))
	L.append(W("x_ion_crossbow", 4, "Ионный арбалет", "bow", "crossbow", 64.0, 0.9, 32.0, "lightning", 420, {"two_h": true, "proj": "bolt", "desc": "Стреляет ионизированными болтами."}))
	L.append(W("x_photon_rifle", 4, "Фотонная винтовка", "firearm", "pulse_rifle", 56.0, 5.0, 36.0, "energy", 480, {"two_h": true, "proj": "pulse", "mag": 40, "reload": 1.8, "spread": 1.5, "desc": "Луч сжатого света."}))
	L.append(W("x_grav_hammer", 4, "Гравимолот", "heavy", "hammer", 88.0, 0.8, 2.8, "blunt", 520, {"two_h": true, "desc": "Удар искривляет гравитацию."}))
	L.append(W("x_nano_knife", 4, "Нанонож разведчика", "dagger", "dagger", 46.0, 2.8, 1.9, "slash", 380, {"desc": "Режет на молекулярном уровне."}))
	L.append(W("x_pulse_staff", 4, "Импульсный посох", "staff", "staff_chrono", 60.0, 1.6, 26.0, "energy", 500, {"two_h": true, "proj": "magic", "mana": 80, "desc": "Генератор импульсных волн."}))
	L.append(W("x_phase_dawn_blade", 4, "Клинок Фазового Рассвета", "sword", "energy_blade", 92.0, 1.95, 2.8, "energy", 2200, {"rarity": 4, "art": "phase_echo", "src": ["boss", "craft"], "desc": "Легенда. «Фазовое эхо»: отложенный энергетический удар."}))
	L.append(W("x_quantum_whisper_rifle", 4, "Винтовка «Квантовый Шёпот»", "firearm", "pulse_rifle", 70.0, 4.0, 38.0, "energy", 2200, {"rarity": 4, "art": "dual_trajectory", "two_h": true, "proj": "pulse", "mag": 30, "reload": 1.8, "spread": 1.2, "src": ["boss", "event"], "desc": "Легенда. «Двойственная траектория»: фантомный энергетический снаряд."}))
	L.append(W("x_first_era_singularity", 4, "Сингулярность Первой Эры", "heavy", "hammer", 110.0, 0.85, 3.0, "time", 5000, {"rarity": 5, "art": "first_era_rift", "two_h": true, "src": ["boss"], "desc": "Миф. Гравитационное притяжение и «Разрыв первой эпохи»."}))
	L.append(A("x_chrono_neurohelm", 4, "Нейрошлем хронолога", "head", "visor", 6.0, 220, {"spell": 0.06, "set": "chronologist", "desc": "Шлем с нейроинтерфейсом."}))
	L.append(A("x_chrono_suit", 4, "Бронекостюм хронолога", "body", "energy_armor", 16.0, 420, {"hp": 70, "set": "chronologist", "desc": "Бронекостюм с хронокомпенсаторами."}))
	L.append(A("x_grav_bracers", 4, "Гравинаручи", "hands", "gauntlets", 3.5, 180, {"aspd": 0.06, "set": "chronologist", "desc": "Наручи с гравитационными стабилизаторами."}))
	L.append(A("x_phase_greaves", 4, "Фазовые поножи", "legs", "greaves_phase", 7.0, 200, {"speed": 0.03, "set": "chronologist", "desc": "Поножи, смещающиеся в фазе."}))
	L.append(A("x_jet_boots", 4, "Реактивные ботинки", "feet", "boots", 3.5, 220, {"speed": 0.08, "set": "chronologist", "desc": "Микродвигатели в подошве."}))
	L.append(A("x_light_absorb_cloak", 4, "Плащ-светопоглотитель", "cloak", "cloak_void", 2.0, 240, {"stealth": 0.25, "color": Color(0.05, 0.05, 0.08), "set": "chronologist", "desc": "Поглощает свет."}))
	L.append(X("x_stabilization_core", 4, "Ядро стабилизации", "module", {"res_time": 0.2, "armor": 8.0}, 300, {"desc": "Стабилизирует хронополе вокруг владельца."}))
	L.append(X("x_chrono_token", 4, "Хроно-жетон", "amulet", {"aspd": 0.05, "speed": 0.03}, 280, {"src": ["event", "quest", "drop"], "desc": "Жетон путешественника во времени."}))
	L.append(X("x_nano_medal", 4, "Наномедальон", "amulet", {"regen": 1.0, "hp": 30}, 320, {"desc": "Наноботы чинят ткани."}))
	L.append(X("x_quantum_compass", 4, "Квантовый компас", "module", {"detect": 0.5}, 260, {"desc": "Указывает на скрытое в любой эпохе."}))
	L.append(X("x_interface_seal", 4, "Интерфейсная печать", "ring", {"spell": 0.08, "mana": 40}, 300, {"desc": "Прямой интерфейс к энергосети."}))
	L.append(R("nano_bandage", 4, "Наноповязка", "med", 40, {"med": {"bleed": 3, "infection": 1, "regen": 0.2, "heal": 0.12}, "desc": "Самозатягивающаяся повязка."}))
	L.append(R("regen_biogel", 4, "Биогель регенерации", "med", 70, {"med": {"fracture": 1, "burn": 2, "regen": 0.5, "heal": 0.25}, "desc": "Технологическая регенерация тканей."}))
	L.append(R("anti_infection_module", 4, "Антиинфекционный модуль", "med", 60, {"med": {"infection": 3, "magic": 1}, "desc": "Модуль очистки крови."}))
	L.append(R("phase_fabric", 4, "Фазовая ткань", "mat", 45, {"desc": "Ткань, сдвинутая по фазе."}))
	L.append(R("quantum_alloy", 4, "Квантовый сплав", "mat", 70, {"src": ["shop", "craft", "drop", "event"], "desc": "Сплав для легендарной техники."}))
	L.append(R("chrono_cell", 4, "Ячейка хроноэнергии", "mat", 80, {"src": ["drop", "event", "shop"], "desc": "Источник энергии для мифических артефактов."}))
	L.append(H("x_quantum_safe", 4, "Защищённый квантовый сейф", "chest", 500, {"capacity": 50, "desc": "Хранилище на 50 мест вне времени."}))
	L.append(H("x_antigrav_rack", 4, "Стойка антигравитации", "weapon_rack", 300, {"capacity": 8, "desc": "Оружие парит в поле."}))
	L.append(H("x_med_capsule", 4, "Домашняя медицинская капсула", "med_station", 700, {"heal_tier": 3, "desc": "Полное восстановление после сна в капсуле."}))
	L.append(H("x_holo_gallery", 4, "Голографическая галерея", "display", 280, {"capacity": 8, "desc": "Голограммы ваших трофеев."}))
	return L
