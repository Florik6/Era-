class_name DBEvents
## World Event Director 2.0 — 160 event templates, exactly 32 per era.
## Data only: nothing is loaded or spawned until a template is activated.
##
## Fields: id, era, name, desc, cat (social | economic | explore | atmos | danger),
## arch (scenario archetype run by EventDirector2), where (square, inn, smithy,
## shop, hall, warehouse, outskirts), hours [from, to) (game hours, may wrap),
## needs (building kinds that must exist), dur (game hours), and optional:
## npc (main participant title), crowd, props, stock (special goods
## category), econ {cat: delta}, cut [cat, days, loss], zone, foe, reward,
## weather, world (world condition), renown.

const CATS := ["social", "economic", "explore", "atmos", "danger"]
## Target weights among eligible events in towns / in the wild.
const W_TOWN := {"social": 0.35, "economic": 0.25, "explore": 0.25, "atmos": 0.10, "danger": 0.05}
const W_WILD := {"social": 0.10, "economic": 0.10, "explore": 0.35, "atmos": 0.15, "danger": 0.30}

static func E(id: String, era: int, name: String, desc: String, cat: String, arch: String, o: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "era": era, "name": name, "desc": desc, "cat": cat, "arch": arch,
		"where": o.get("where", "square"), "hours": o.get("hours", [8, 20]), "needs": o.get("needs", []), "dur": float(o.get("dur", 3.0))}
	for k in o:
		if not d.has(k):
			d[k] = o[k]
	return d

static var _all: Array = []
static var _by_id: Dictionary = {}

static func all() -> Array:
	if _all.is_empty():
		_all = _build()
		for e in _all:
			_by_id[e.id] = e
	return _all

static func get_event(id: String) -> Dictionary:
	all()
	return _by_id.get(id, {})

static func of_era(era: int) -> Array:
	return all().filter(func(e): return int(e.era) == era)

static func _build() -> Array:
	var L: Array = []
	# ======================================================= I. Средневековье
	L.append(E("med_harvest_fest", 0, "Праздник урожая", "Жители собираются на площади, торговцы выставляют особые товары.", "social", "gathering", {"crowd": 8, "props": ["stall", "banner", "lanterns"], "stock": "food", "econ": {"food": 30}, "dur": 5, "npc": "Староста"}))
	L.append(E("med_smith_no_iron", 0, "Кузнец остался без железа", "Поставки железа сорвались — кузнец просит доставить слитки.", "economic", "shortage", {"where": "smithy", "needs": ["smithy"], "cut": ["iron", 1.5, 40], "fetch": "iron_ingot", "fetch_n": 3, "npc": "Кузнец", "dur": 24}))
	L.append(E("med_bread_day", 0, "Новый хлебный день", "Пекарь открывает лавку, у прилавка очередь, есть поручение.", "economic", "merchant", {"hours": [6, 12], "props": ["stall", "crates"], "stock": "food", "econ": {"food": 20}, "npc": "Пекарь", "crowd": 5}))
	L.append(E("med_wandering_bard", 0, "Странствующий бард", "В таверне выступает музыкант и поёт о скрытом месте.", "social", "gathering", {"where": "inn", "needs": ["inn"], "hours": [17, 24], "npc": "Странствующий бард", "crowd": 6, "reveal": true}))
	L.append(E("med_great_fair", 0, "Большая ярмарка", "Прибыли торговцы с необычным товаром.", "economic", "merchant", {"props": ["stall", "stall", "banner", "crates"], "stock": "goods", "merchants": 2, "econ": {"goods": 40}, "dur": 6, "npc": "Ярмарочный купец", "crowd": 8}))
	L.append(E("med_wedding", 0, "Свадьба жителей", "Горожане празднуют свадьбу, героя зовут в гости.", "social", "gathering", {"hours": [11, 20], "props": ["banner", "lanterns"], "crowd": 9, "npc": "Молодожёны", "reward": "potion_hp"}))
	L.append(E("med_tourney", 0, "Рыцарские состязания", "Безопасный турнир по правилам: зрители, судья и награда.", "social", "competition", {"props": ["ring", "banner"], "crowd": 8, "npc": "Рыцарь-участник", "renown": 3.0}))
	L.append(E("med_herb_shortage", 0, "Недостаток лечебных трав", "Целительница просит найти редкие травы за городом.", "economic", "shortage", {"cut": ["medicine", 1.0, 20], "fetch": "healer_thistle", "fetch_n": 3, "npc": "Целительница"}))
	L.append(E("med_squire_bout", 0, "Учебный поединок оруженосцев", "Молодые бойцы тренируются на площадке — без настоящих смертей.", "social", "competition", {"props": ["ring"], "crowd": 5, "npc": "Оруженосец"}))
	L.append(E("med_lost_dog", 0, "Потерявшийся пёс", "Ребёнок ищет пса; следы ведут за город.", "explore", "search", {"target": "dog", "npc": "Ребёнок", "reward_gold": 25}))
	L.append(E("med_copyist", 0, "Переписчик древних книг", "Учёный просит проверить сведения о забытой рукописи.", "explore", "investigation", {"where": "hall", "clues": 3, "npc": "Переписчик", "reward": "scroll_identify"}))
	L.append(E("med_pilgrims", 0, "Прибытие паломников", "Путники посещают храм и рассказывают истории.", "social", "visitor", {"visitors": 4, "npc": "Паломник", "hours": [8, 18]}))
	L.append(E("med_land_dispute", 0, "Спор землевладельцев", "Двое делят участок земли и просят рассудить.", "social", "dispute", {"npc": "Землевладелец"}))
	L.append(E("med_odd_prices", 0, "Необычные цены на рынке", "Из-за перебоев поставок меняется ассортимент.", "economic", "price_shift", {"econ": {"goods": -35, "luxury": 15}, "dur": 24}))
	L.append(E("med_missing_bell", 0, "Пропавший городской колокол", "Стража ищет, куда исчез колокол.", "explore", "investigation", {"clues": 3, "npc": "Капитан стражи", "culprit": "Звонарь-должник"}))
	L.append(E("med_caravan", 0, "Прибытие торгового каравана", "Купцы разгружают товары и идут в трактир.", "economic", "merchant", {"props": ["cart", "crates", "crates"], "porters": 2, "stock": "goods", "econ": {"goods": 50, "iron": 20}, "npc": "Караванщик", "crowd": 4}))
	L.append(E("med_explorer", 0, "Странствующий исследователь", "Учёный платит за изучение древнего сооружения.", "explore", "mystery", {"where": "outskirts", "npc": "Исследователь", "reward_gold": 40}))
	L.append(E("med_shrine_wakes", 0, "Пробуждение старого святилища", "В лесу проснулся слабый магический эффект.", "explore", "mystery", {"where": "outskirts", "rift_chance": 0.25}))
	L.append(E("med_rune_riddle", 0, "Загадка каменных рун", "На камнях проступила последовательность древних знаков.", "explore", "investigation", {"where": "outskirts", "clues": 3, "order": true, "reward": "ash_crystal"}))
	L.append(E("med_night_service", 0, "Ночная служба в часовне", "Жители собираются на службу; слышны новые сведения.", "social", "gathering", {"hours": [20, 24], "where": "hall", "crowd": 7, "npc": "Священник", "reveal": true}))
	L.append(E("med_river_flood", 0, "Разлив реки", "Вода залила тропу; нужно помочь укрепить берег.", "atmos", "hazard", {"zone": "flood", "fix": 2, "weather": "rain", "dur": 6}))
	L.append(E("med_wolves_pasture", 0, "Волки возле пастбища", "Пастух просит отогнать волков за поселением.", "danger", "outskirts", {"foe": "wolf", "count": 3, "npc": "Пастух"}))
	L.append(E("med_mill_broken", 0, "Поломка мельницы", "Мельник ищет материалы для ремонта.", "economic", "shortage", {"cut": ["food", 1.0, 25], "fetch": "iron_ingot", "fetch_n": 2, "npc": "Мельник"}))
	L.append(E("med_old_coins", 0, "Находка старинных монет", "Житель нашёл клад и просит оценить монеты.", "explore", "visitor", {"npc": "Счастливый житель", "reward_gold": 30}))
	L.append(E("med_rare_horse", 0, "Редкая породистая лошадь", "В город прибыл торговец редкими животными.", "economic", "merchant", {"props": ["cart", "banner"], "stock": "luxury", "npc": "Торговец лошадьми"}))
	L.append(E("med_tax_collector", 0, "Королевский сборщик налогов", "Чиновник объявляет сбор: цены растут, жители недовольны.", "economic", "visitor", {"npc": "Сборщик налогов", "econ": {"goods": -20}, "where": "hall"}))
	L.append(E("med_iron_mask", 0, "Незнакомец в железной маске", "Загадочный путник остановился в таверне.", "explore", "visitor", {"where": "inn", "needs": ["inn"], "npc": "Незнакомец в маске", "reveal": true}))
	L.append(E("med_apprentice_gone", 0, "Исчезновение ученика кузнеца", "Кузнец потерял ученика — нужна помощь в поисках.", "explore", "search", {"needs": ["smithy"], "target": "person", "npc": "Кузнец", "reward_gold": 35}))
	L.append(E("med_spy_scout", 0, "Подозрительный разведчик", "На окраине кто-то изучает оборону поселения.", "danger", "outskirts", {"foe": "scout", "count": 1, "npc": "Стражник"}))
	L.append(E("med_bandit_raid", 0, "Редкий разбойничий налёт", "Отряд разбойников идёт к складу; стража держит оборону.", "danger", "raid", {"foe": "bandit", "count": 4, "where": "warehouse"}))
	L.append(E("med_blood_vigil", 0, "Бдение Кровавой Луны", "Жители проводят защитный обряд под кровавой луной.", "atmos", "gathering", {"world": "blood_moon", "hours": [20, 6], "crowd": 6, "props": ["lanterns"], "npc": "Хранительница обряда"}))
	L.append(E("med_hero_returns", 0, "Возвращение старого героя", "В город прибыла живая легенда.", "social", "visitor", {"legend": true, "npc": "Старый герой"}))
	# ======================================================= II. Возрождение
	L.append(E("ren_masked_ball", 1, "Большой бал масок", "Торжество, где можно познакомиться с влиятельными людьми.", "social", "gathering", {"where": "hall", "hours": [18, 24], "crowd": 9, "props": ["lanterns", "banner"], "npc": "Хозяин бала"}))
	L.append(E("ren_fencing", 1, "Турнир фехтовальщиков", "Дуэлянты соревнуются на площадке.", "social", "competition", {"props": ["ring"], "crowd": 7, "npc": "Дуэлянт", "renown": 3.0}))
	L.append(E("ren_alchemy_leak", 1, "Алхимическая утечка", "Неудачный эксперимент — нужно перекрыть утечку.", "atmos", "hazard", {"zone": "gas", "fix": 2, "where": "shop"}))
	L.append(E("ren_portrait", 1, "Заказ портрета", "Художник ищет натурщика для необычного поручения.", "social", "visitor", {"npc": "Художник", "reward_gold": 20}))
	L.append(E("ren_forged_painting", 1, "Поддельная картина", "Торговец просит выяснить происхождение полотна.", "explore", "investigation", {"clues": 3, "npc": "Торговец картинами", "culprit": "Фальсификатор"}))
	L.append(E("ren_ship_arrives", 1, "Прибытие корабля", "В порт пришёл новый груз.", "economic", "merchant", {"props": ["crates", "crates", "cart"], "porters": 2, "stock": "goods", "econ": {"goods": 45, "luxury": 10}, "npc": "Капитан"}))
	L.append(E("ren_auction", 1, "Аукцион редкостей", "Продаются необычные предметы и артефакты.", "economic", "merchant", {"where": "hall", "stock": "luxury", "crowd": 6, "npc": "Аукционист"}))
	L.append(E("ren_cartographer", 1, "Экспедиция картографа", "Исследователь ищет сопровождение на неизвестный маршрут.", "explore", "mystery", {"where": "outskirts", "npc": "Картограф", "reward_gold": 40}))
	L.append(E("ren_play_premiere", 1, "Премьера театральной пьесы", "Горожане собираются на представление.", "social", "gathering", {"hours": [17, 23], "props": ["stage", "lanterns"], "crowd": 9, "npc": "Актёр"}))
	L.append(E("ren_wine_fest", 1, "Праздник виноделов", "Сезонная ярмарка вина.", "economic", "merchant", {"props": ["stall", "stall", "banner"], "stock": "food", "econ": {"food": 25, "luxury": 10}, "npc": "Винодел", "crowd": 6}))
	L.append(E("ren_clock_broken", 1, "Неисправные городские часы", "Механизм башни требует ремонта.", "atmos", "hazard", {"zone": "none", "fix": 2, "npc": "Часовщик", "reward_gold": 25}))
	L.append(E("ren_lecture", 1, "Открытая лекция учёного", "Исследователь рассказывает о новой гипотезе магии.", "social", "gathering", {"where": "hall", "crowd": 6, "npc": "Учёный", "reveal": true}))
	L.append(E("ren_invention", 1, "Демонстрация изобретения", "Изобретатель испытывает необычный механизм.", "atmos", "spectacle", {"fx": "sparks", "crowd": 6, "npc": "Изобретатель"}))
	L.append(E("ren_canal_dispute", 1, "Спор за право пользоваться каналом", "Торговцы делят доступ к маршруту.", "economic", "dispute", {"npc": "Купец"}))
	L.append(E("ren_sea_fog", 1, "Необычный морской туман", "Порт ограничил движение кораблей.", "atmos", "price_shift", {"econ": {"goods": -20}, "weather": "fog", "dur": 8}))
	L.append(E("ren_anomal_compass", 1, "Аномальный компас", "Прибор указывает на тайное место.", "explore", "mystery", {"where": "outskirts", "rift_chance": 0.3, "npc": "Навигатор"}))
	L.append(E("ren_forbidden_leaflet", 1, "Запрещённая листовка", "По городу ходят подозрительные объявления.", "explore", "investigation", {"clues": 3, "culprit": "Печатник", "npc": "Стражник"}))
	L.append(E("ren_doctor_warning", 1, "Предупреждение городского лекаря", "Квартал нуждается в санитарной помощи.", "economic", "shortage", {"cut": ["medicine", 1.0, 15], "fetch": "alch_antiseptic", "fetch_n": 2, "npc": "Городской лекарь"}))
	L.append(E("ren_runaway_apprentice", 1, "Сбежавший помощник алхимика", "Ученик скрылся после неудачного опыта.", "explore", "search", {"target": "person", "npc": "Алхимик", "reward_gold": 30}))
	L.append(E("ren_fireworks", 1, "Праздничный фейерверк", "Вечернее небо над площадью расцветает огнями.", "atmos", "spectacle", {"fx": "fireworks", "hours": [19, 24], "crowd": 8}))
	L.append(E("ren_tolls", 1, "Проверка торговых пошлин", "Чиновники объявляют новые правила.", "economic", "visitor", {"npc": "Таможенный чиновник", "econ": {"goods": -15}}))
	L.append(E("ren_smuggler_note", 1, "Записка контрабандиста", "Найдены сведения о тайной сделке.", "explore", "investigation", {"clues": 2, "where": "warehouse", "culprit": "Контрабандист"}))
	L.append(E("ren_lost_boat", 1, "Потерянная лодка рыбака", "Нужно выяснить, куда исчезло судно.", "explore", "search", {"target": "boat", "npc": "Рыбак", "reward_gold": 25}))
	L.append(E("ren_book_theft", 1, "Кража редкой книги", "В библиотеке начинается расследование.", "explore", "investigation", {"where": "hall", "clues": 3, "culprit": "Переплётчик", "npc": "Библиотекарь"}))
	L.append(E("ren_rapier_lost", 1, "Пропавшая дуэльная рапира", "Оружейник просит найти дорогой клинок.", "explore", "search", {"target": "item", "npc": "Оружейник", "reward_gold": 35}))
	L.append(E("ren_bad_potion", 1, "Неудачное алхимическое зелье", "Опыт временно меняет поведение предметов.", "atmos", "hazard", {"zone": "gas", "fix": 1, "dur": 3}))
	L.append(E("ren_art_rivalry", 1, "Соперничество художественных мастерских", "Двое художников борются за заказ.", "social", "dispute", {"npc": "Художник"}))
	L.append(E("ren_secret_society", 1, "Приглашение тайного общества", "Загадочный человек предлагает испытание.", "explore", "investigation", {"clues": 3, "order": true, "npc": "Посланник ложи", "reward": "brass_blank"}))
	L.append(E("ren_bank_caravan", 1, "Караван богатого банка", "Через город везут ценности под охраной.", "economic", "merchant", {"props": ["cart", "crates"], "porters": 2, "guards": 2, "econ": {"luxury": 15}, "npc": "Банкир"}))
	L.append(E("ren_pirate_sail", 1, "Пиратский корабль на горизонте", "Портовая стража усиливает наблюдение.", "danger", "outskirts", {"foe": "pirate", "count": 2, "npc": "Портовый стражник"}))
	L.append(E("ren_pirate_raid", 1, "Редкий налёт контрабандистов", "Отряд идёт к складам порта; стража встречает.", "danger", "raid", {"foe": "pirate", "count": 4, "where": "warehouse"}))
	L.append(E("ren_traveler_returns", 1, "Возвращение известного путешественника", "Знакомый по прежним событиям приносит вести.", "social", "visitor", {"legend": true, "npc": "Путешественник"}))
	# ======================================================= III. Индустриальная эпоха
	L.append(E("ind_morning_shift", 2, "Утренняя заводская смена", "Рабочие идут к предприятиям.", "social", "gathering", {"hours": [5, 9], "where": "warehouse", "crowd": 8, "npc": "Мастер смены"}))
	L.append(E("ind_strike_talks", 2, "Переговоры о забастовке", "Представители рабочих говорят с владельцем.", "social", "dispute", {"where": "hall", "npc": "Профсоюзный вожак"}))
	L.append(E("ind_train_arrives", 2, "Прибытие пассажирского поезда", "На станции появляются путешественники и торговцы.", "economic", "merchant", {"props": ["wagon", "crates"], "porters": 2, "visitors": 3, "stock": "goods", "econ": {"goods": 40}, "npc": "Начальник станции"}))
	L.append(E("ind_steam_leak", 2, "Утечка пара", "На фабрике авария — нужно перекрыть вентили.", "atmos", "hazard", {"zone": "steam", "fix": 3, "where": "warehouse"}))
	L.append(E("ind_mech_contest", 2, "Соревнование механиков", "Изобретатели показывают устройства.", "social", "competition", {"props": ["ring", "crates"], "crowd": 7, "npc": "Механик", "renown": 2.5}))
	L.append(E("ind_blackout", 2, "Перебой электроснабжения", "Часть города осталась без света.", "atmos", "outage", {"fix": 2, "hours": [17, 24], "npc": "Электрик"}))
	L.append(E("ind_expo", 2, "Выставка промышленных технологий", "В город съехались инженеры и торговцы.", "economic", "merchant", {"where": "hall", "props": ["stall", "banner"], "stock": "goods", "npc": "Инженер-экспонент", "crowd": 6}))
	L.append(E("ind_rail_repair", 2, "Ремонт железнодорожного пути", "Рабочие перекрыли участок дороги.", "atmos", "hazard", {"zone": "none", "fix": 2, "where": "outskirts", "npc": "Путеец"}))
	L.append(E("ind_worker_cafe", 2, "Вечер в рабочем кафе", "Рабочие обсуждают новости.", "social", "gathering", {"where": "inn", "needs": ["inn"], "hours": [17, 23], "crowd": 7, "reveal": true}))
	L.append(E("ind_clock_glitch", 2, "Сбой городского часового механизма", "Устройства работают неправильно.", "atmos", "hazard", {"zone": "electric", "fix": 2, "dur": 3}))
	L.append(E("ind_boiler_broken", 2, "Поломка котла", "Мастерской нужны редкие материалы.", "economic", "shortage", {"where": "smithy", "cut": ["iron", 1.0, 25], "fetch": "steel_plate", "fetch_n": 2, "npc": "Котельщик"}))
	L.append(E("ind_blueprints_gone", 2, "Пропажа инженерных чертежей", "Начинается детективная история.", "explore", "investigation", {"clues": 3, "culprit": "Конкурент", "npc": "Инженер"}))
	L.append(E("ind_illegal_shop", 2, "Незаконная мастерская", "На окраине обнаружено подпольное производство.", "explore", "investigation", {"where": "outskirts", "clues": 2, "culprit": "Подпольщик"}))
	L.append(E("ind_school_opening", 2, "Открытие технического училища", "Жители собираются на церемонию.", "social", "gathering", {"where": "hall", "crowd": 8, "props": ["banner"], "npc": "Директор училища"}))
	L.append(E("ind_smog", 2, "Промышленный смог", "Атмосфера квартала временно меняется.", "atmos", "hazard", {"zone": "smog", "fix": 0, "dur": 6}))
	L.append(E("ind_airship", 2, "Первый полёт дирижабля", "Над городом проплывает дирижабль.", "atmos", "spectacle", {"fx": "airship", "crowd": 8}))
	L.append(E("ind_demonstration", 2, "Мирная рабочая демонстрация", "Горожане выдвигают требования на площади.", "social", "gathering", {"crowd": 10, "props": ["banner", "banner"], "npc": "Оратор"}))
	L.append(E("ind_telegram", 2, "Таинственная телеграмма", "Сообщение запускает небольшое расследование.", "explore", "investigation", {"clues": 3, "npc": "Телеграфист", "reward_gold": 30}))
	L.append(E("ind_train_robbery", 2, "Ограбление поезда за городом", "Грабители засели у путей.", "danger", "outskirts", {"foe": "bandit", "count": 3, "npc": "Проводник"}))
	L.append(E("ind_electric_anomaly", 2, "Электрическая аномалия", "Устройства дают опасные разряды.", "atmos", "hazard", {"zone": "electric", "fix": 2}))
	L.append(E("ind_miners_find", 2, "Необычная находка шахтёров", "В шахте нашли редкий материал.", "explore", "mystery", {"where": "outskirts", "reward": "ether_condensate", "npc": "Шахтёр"}))
	L.append(E("ind_inspector", 2, "Прибытие промышленного инспектора", "Заводы проходят проверку.", "economic", "visitor", {"npc": "Инспектор", "econ": {"goods": -15}, "where": "warehouse"}))
	L.append(E("ind_mech_theatre", 2, "Премьера механического театра", "Горожане смотрят представление автоматонов.", "social", "gathering", {"hours": [16, 23], "props": ["stage"], "crowd": 8, "npc": "Механический актёр"}))
	L.append(E("ind_lost_automaton", 2, "Потерянный механический питомец", "Маленький автоматон бродит по городу.", "explore", "search", {"target": "pet", "npc": "Изобретательница", "reward_gold": 25}))
	L.append(E("ind_guild_feud", 2, "Спор инженерных гильдий", "Организации делят контракт.", "economic", "dispute", {"npc": "Мастер гильдии"}))
	L.append(E("ind_gas_leak", 2, "Утечка газа в канализации", "Появилась опасная зона.", "danger", "hazard", {"zone": "gas", "fix": 2}))
	L.append(E("ind_invention_auction", 2, "Аукцион изобретений", "Продаются технологические диковины.", "economic", "merchant", {"where": "hall", "stock": "luxury", "crowd": 6, "npc": "Аукционист"}))
	L.append(E("ind_runaway_automaton", 2, "Сбежавший экспериментальный автоматон", "Машина покинула мастерскую.", "explore", "search", {"target": "machine", "npc": "Конструктор", "reward_gold": 40}))
	L.append(E("ind_night_ghost", 2, "Призрак ночной смены", "На заброшенной фабрике происходят странности.", "explore", "mystery", {"where": "outskirts", "hours": [20, 4], "rift_chance": 0.25}))
	L.append(E("ind_sabotage", 2, "Саботаж электростанции", "Нарушена работа промышленного района.", "danger", "outage", {"fix": 3, "culprit": "Диверсант"}))
	L.append(E("ind_machine_raid", 2, "Редкое нападение механической группы", "Повреждённые автоматоны идут на мастерские.", "danger", "raid", {"foe": "machine", "count": 4, "where": "smithy"}))
	L.append(E("ind_workers_fund", 2, "Фонд помощи рабочим", "Горожане собирают средства для пострадавших.", "social", "gathering", {"crowd": 7, "npc": "Казначей фонда", "donation": true}))
	# ======================================================= IV. Современность
	L.append(E("mod_rush_hour", 3, "Утренний час пик", "Жители спешат на работу, открываются кафе.", "social", "gathering", {"hours": [7, 10], "crowd": 9}))
	L.append(E("mod_big_sale", 3, "Большая распродажа", "Магазин объявил временные скидки.", "economic", "price_shift", {"needs": ["shop"], "econ": {"goods": 40}, "dur": 8}))
	L.append(E("mod_guard_change", 3, "Смена городской охраны", "Патрули передают друг другу посты.", "social", "gathering", {"crowd": 4, "npc": "Командир патруля", "guards_parade": true}))
	L.append(E("mod_street_musician", 3, "Уличный музыкант", "На площади собираются слушатели.", "social", "gathering", {"crowd": 6, "npc": "Уличный музыкант", "music": true}))
	L.append(E("mod_film_premiere", 3, "Премьера фильма", "Горожане идут в кинотеатр.", "social", "gathering", {"where": "hall", "hours": [18, 24], "crowd": 8, "props": ["lanterns"]}))
	L.append(E("mod_sports_match", 3, "Спортивное соревнование", "Команды NPC проводят матч.", "social", "competition", {"props": ["ring"], "crowd": 9, "npc": "Капитан команды"}))
	L.append(E("mod_city_festival", 3, "Городской фестиваль", "Улицы украшены, работают временные точки.", "social", "gathering", {"props": ["stall", "banner", "lanterns"], "crowd": 10, "stock": "food", "dur": 6}))
	L.append(E("mod_power_cut", 3, "Перебой электроэнергии", "Заведениям нужно восстановить питание.", "atmos", "outage", {"fix": 2, "npc": "Техник"}))
	L.append(E("mod_newspaper", 3, "Сенсация местной газеты", "Репортёр ищет сведения о необычном случае.", "explore", "investigation", {"clues": 3, "npc": "Репортёр", "reward_gold": 30}))
	L.append(E("mod_ambulance", 3, "Скорая помощь", "Медики спешат к пострадавшему.", "social", "visitor", {"npc": "Медик", "medic": true}))
	L.append(E("mod_lost_parcel", 3, "Потерянная посылка", "Курьер восстанавливает маршрут доставки.", "explore", "search", {"target": "item", "npc": "Курьер", "reward_gold": 25}))
	L.append(E("mod_museum_expo", 3, "Выставка исторических артефактов", "Музей показывает предметы прошлых эпох.", "explore", "gathering", {"where": "hall", "crowd": 6, "npc": "Куратор музея", "reveal": true}))
	L.append(E("mod_screen_hack", 3, "Взлом рекламного экрана", "На дисплее появилось подозрительное сообщение.", "explore", "investigation", {"clues": 2, "culprit": "Хакер"}))
	L.append(E("mod_tech_launch", 3, "Презентация технологии", "Компания показывает новое устройство.", "atmos", "spectacle", {"fx": "sparks", "crowd": 7, "npc": "Ведущий презентации"}))
	L.append(E("mod_traffic_jam", 3, "Автомобильная пробка", "Участок дороги перегружен.", "atmos", "hazard", {"zone": "none", "fix": 1, "where": "outskirts", "npc": "Регулировщик"}))
	L.append(E("mod_metro_fault", 3, "Нарушение работы метро", "Люди ищут обходные пути.", "atmos", "price_shift", {"econ": {"goods": -10}, "dur": 6}))
	L.append(E("mod_drone_mixup", 3, "Ошибочная доставка дрона", "Посылка попала не по адресу.", "explore", "search", {"target": "item", "npc": "Адресат", "reward_gold": 20}))
	L.append(E("mod_police_alert", 3, "Полицейское предупреждение", "На окраине разыскивают подозреваемого.", "danger", "outskirts", {"foe": "criminal", "count": 1, "npc": "Полицейский"}))
	L.append(E("mod_job_fair", 3, "Ярмарка вакансий корпорации", "Компания набирает сотрудников.", "economic", "gathering", {"props": ["stall", "banner"], "crowd": 7, "npc": "Рекрутёр"}))
	L.append(E("mod_science_leak", 3, "Утечка научной информации", "Исследователь сообщает о подозрительных опытах.", "explore", "investigation", {"clues": 3, "npc": "Исследователь"}))
	L.append(E("mod_city_garden", 3, "Городской сад", "Жители озеленяют пустырь.", "social", "gathering", {"crowd": 7, "props": ["crates"], "npc": "Садовод"}))
	L.append(E("mod_underground_tourney", 3, "Подпольный спортивный турнир", "Состязания с правилами и судьёй.", "social", "competition", {"props": ["ring"], "crowd": 6, "npc": "Боец", "hours": [19, 3]}))
	L.append(E("mod_street_food", 3, "Фестиваль уличной еды", "Появились временные торговцы.", "economic", "merchant", {"props": ["stall", "stall"], "merchants": 2, "stock": "food", "econ": {"food": 35}, "crowd": 7}))
	L.append(E("mod_lost_pet", 3, "Потерянное домашнее животное", "Житель просит помочь с поисками.", "explore", "search", {"target": "dog", "npc": "Хозяйка", "reward_gold": 25}))
	L.append(E("mod_arch_find", 3, "Археологическая находка", "На стройке нашли предмет древней эпохи.", "explore", "mystery", {"where": "outskirts", "reward": "ash_crystal", "npc": "Прораб"}))
	L.append(E("mod_lab_alarm", 3, "Аварийная тревога лаборатории", "Комплекс закрыл опасную зону.", "danger", "hazard", {"zone": "electric", "fix": 2}))
	L.append(E("mod_comm_outage", 3, "Сбой городской связи", "Люди не получают сообщения.", "atmos", "outage", {"fix": 1, "npc": "Связист"}))
	L.append(E("mod_flash_flood", 3, "Ливневое подтопление", "Часть улиц затоплена.", "atmos", "hazard", {"zone": "flood", "fix": 2, "weather": "rain"}))
	L.append(E("mod_black_market", 3, "Предложение чёрного рынка", "Незнакомец предлагает подозрительный товар.", "economic", "merchant", {"stock": "luxury", "npc": "Скупщик", "hours": [20, 4], "shady": true}))
	L.append(E("mod_convoy_attack", 3, "Нападение на транспорт за городом", "Колонна остановлена налётчиками.", "danger", "outskirts", {"foe": "criminal", "count": 3, "npc": "Водитель"}))
	L.append(E("mod_gang_raid", 3, "Редкий налёт преступной группы", "Банда идёт к магазинам; охрана встречает.", "danger", "raid", {"foe": "criminal", "count": 4, "where": "shop"}))
	L.append(E("mod_living_legend", 3, "Появление живой легенды", "Известный человек приехал в город.", "social", "visitor", {"legend": true, "npc": "Знаменитость"}))
	# ======================================================= V. Будущее
	L.append(E("fut_holo_fest", 4, "Голографический фестиваль", "Улицы украшены интерактивными проекциями.", "atmos", "spectacle", {"fx": "holo", "crowd": 9, "hours": [17, 24]}))
	L.append(E("fut_broken_helper", 4, "Неисправный робот-помощник", "Сервисному автоматону нужен ремонт.", "economic", "shortage", {"cut": ["goods", 0.5, 10], "fetch": "electronic_board", "fetch_n": 1, "npc": "Робот-помощник"}))
	L.append(E("fut_implant_service", 4, "Обслуживание нейроимплантов", "Клиника проводит процедуру.", "social", "visitor", {"npc": "Нейротехник", "medic": true}))
	L.append(E("fut_gravity_fault", 4, "Сбой искусственной гравитации", "Сектор перешёл в особый режим.", "atmos", "hazard", {"zone": "gravity", "fix": 2}))
	L.append(E("fut_synth_rights", 4, "Обсуждение прав синтетиков", "Городской совет проводит заседание.", "social", "gathering", {"where": "hall", "crowd": 7, "npc": "Советник", "vote": true}))
	L.append(E("fut_android_musician", 4, "Музыкант-андроид", "На площади выступает искусственный исполнитель.", "social", "gathering", {"crowd": 7, "npc": "Андроид-музыкант", "music": true}))
	L.append(E("fut_chrono_tourism", 4, "Хронологический туризм", "Туристы осматривают реконструкции.", "social", "visitor", {"visitors": 4, "npc": "Хроногид"}))
	L.append(E("fut_drone_error", 4, "Ошибка дрона-курьера", "Доставка привела к необычной ситуации.", "explore", "search", {"target": "item", "npc": "Получатель", "reward_gold": 20}))
	L.append(E("fut_biodome", 4, "Цветение биокупола", "Горожане идут в искусственный сад.", "atmos", "spectacle", {"fx": "bloom", "crowd": 7}))
	L.append(E("fut_quantum_bazaar", 4, "Квантовый базар", "Торговая площадка с необычными ресурсами.", "economic", "merchant", {"props": ["stall", "stall"], "merchants": 2, "stock": "luxury", "econ": {"luxury": 15}, "crowd": 6}))
	L.append(E("fut_synth_pet", 4, "Потерянный синтетический питомец", "Роботизированного зверька надо вернуть.", "explore", "search", {"target": "pet", "npc": "Владелец", "reward_gold": 25}))
	L.append(E("fut_teleport_overload", 4, "Перегрузка телепортационной станции", "Транспорт временно меняет маршруты.", "atmos", "hazard", {"zone": "electric", "fix": 2, "npc": "Оператор станции"}))
	L.append(E("fut_grav_race", 4, "Гонка антигравитационных аппаратов", "Организованное соревнование.", "social", "competition", {"props": ["ring"], "crowd": 8, "npc": "Гонщик", "renown": 2.5}))
	L.append(E("fut_holo_gallery", 4, "Выставка живых голограмм", "Художники показывают интерактивные работы.", "social", "gathering", {"where": "hall", "crowd": 6, "npc": "Голохудожник"}))
	L.append(E("fut_contracts", 4, "Изменение корпоративных контрактов", "Корпорации меняют цены и услуги.", "economic", "price_shift", {"econ": {"goods": -25, "luxury": 20}, "dur": 24}))
	L.append(E("fut_robo_chef", 4, "Экспериментальный робот-повар", "Посетители пробуют необычное меню.", "social", "gathering", {"where": "inn", "needs": ["inn"], "crowd": 6, "npc": "Робот-повар", "stock": "food"}))
	L.append(E("fut_quantum_forecast", 4, "Квантовый прогноз", "Система предупреждает о возможной аномалии.", "explore", "mystery", {"where": "outskirts", "rift_chance": 0.35}))
	L.append(E("fut_relic_scan", 4, "Сканирование древней реликвии", "Учёные изучают предмет из другой эпохи.", "explore", "investigation", {"where": "hall", "clues": 2, "npc": "Исследователь реликвий"}))
	L.append(E("fut_unstable_echo", 4, "Нестабильный исторический отголосок", "На улице мелькают образы прошлого.", "atmos", "echo"))
	L.append(E("fut_clone_dispute", 4, "Спор двух клонов о личности", "Конфликт, который можно решить без драки.", "social", "dispute", {"npc": "Клон"}))
	L.append(E("fut_alien_caravan", 4, "Прибытие внеземного каравана", "Город получает редкие ресурсы.", "economic", "merchant", {"props": ["cart", "crates"], "porters": 2, "stock": "luxury", "econ": {"luxury": 25, "goods": 20}, "npc": "Посланник каравана"}))
	L.append(E("fut_nano_leak", 4, "Нанотехнологическая утечка", "Небольшая область стала опасной.", "danger", "hazard", {"zone": "nano", "fix": 2}))
	L.append(E("fut_reactor", 4, "Стабилизация энергореактора", "Техники предотвращают отключение.", "atmos", "outage", {"fix": 3, "npc": "Техник реактора"}))
	L.append(E("fut_adaptive_arch", 4, "Перестройка адаптивной архитектуры", "Здание меняет конфигурацию.", "atmos", "spectacle", {"fx": "rebuild", "crowd": 5}))
	L.append(E("fut_time_experiment", 4, "Неудачный временной эксперимент", "Возникла локальная аномалия.", "danger", "hazard", {"zone": "time", "fix": 2, "rift_chance": 0.3}))
	L.append(E("fut_ai_debate", 4, "Философский спор ИИ", "Два ИИ спорят об автономии и зовут героя.", "social", "dispute", {"npc": "ИИ-собеседник"}))
	L.append(E("fut_memory_sale", 4, "Продажа запрещённого воспоминания", "Торговец предлагает необычный артефакт.", "economic", "merchant", {"stock": "luxury", "npc": "Торговец воспоминаниями", "hours": [20, 4], "shady": true}))
	L.append(E("fut_shuttle_repair", 4, "Ремонт орбитального шаттла", "Инженерам нужен редкий компонент.", "economic", "shortage", {"cut": ["goods", 1.0, 15], "fetch": "quantum_alloy", "fetch_n": 1, "npc": "Инженер шаттла"}))
	L.append(E("fut_museum_sword", 4, "Древний меч в музее будущего", "Реликвия странно реагирует на ребёнка.", "explore", "mystery", {"where": "hall", "npc": "Ребёнок", "reward": "chrono_cell"}))
	L.append(E("fut_rogue_bot", 4, "Вышедший из-под контроля сервисный бот", "Повреждённый робот устроил происшествие.", "danger", "outskirts", {"foe": "machine", "count": 1, "npc": "Оператор", "in_town": true}))
	L.append(E("fut_chrono_invasion", 4, "Редкое вторжение хронологических существ", "Из небольшого разлома выходят чужаки; защита города реагирует.", "danger", "raid", {"foe": "chrono", "count": 4, "where": "square"}))
	L.append(E("fut_council_vote", 4, "Голосование автоматизированного совета", "Решение совета меняет правила торговли.", "economic", "gathering", {"where": "hall", "crowd": 6, "npc": "Голос совета", "vote": true, "econ": {"goods": 15}}))
	return L
