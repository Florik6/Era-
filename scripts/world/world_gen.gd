class_name WorldGen
extends RefCounted
## Deterministic, seed-based world layout and terrain functions.
## Hybrid approach: hand-shaped key places (capital, fortress, boss lairs,
## Chronos trial) placed by rules + procedural villages, camps, points of
## interest, roads, rivers and biomes.

const FLAT_CELL := 128.0

var seed_v := 0
var era := 0
var half := 1280.0
var water_level := -1.2
var settlements: Array = []
var pois: Array = []
var roads: Array = []            # Array of [Vector2, Vector2]
var rng := RandomNumberGenerator.new()

var n_height := FastNoiseLite.new()
var n_detail := FastNoiseLite.new()
var n_mount := FastNoiseLite.new()
var n_ridge := FastNoiseLite.new()
var n_moist := FastNoiseLite.new()
var n_temp := FastNoiseLite.new()
var n_river := FastNoiseLite.new()

var _flats := {}                 # Vector2i -> Array[{pos, r, h}]
var _road_boxes: Array = []      # [minx, minz, maxx, maxz] per road
var _spawn := Vector2.ZERO
var _uid := 0

func setup(seed_value: int, era_i: int, half_size: float = 1280.0) -> void:
	seed_v = seed_value
	era = clampi(era_i, 0, DBEras.ERA_COUNT - 1)
	half = half_size
	rng.seed = hash(seed_v * 7919 + era * 104729 + 17)
	var base_seed := seed_v + era * 1013
	_cfg(n_height, base_seed + 1, 0.0022, 4)
	_cfg(n_detail, base_seed + 2, 0.03, 2)
	_cfg(n_mount, base_seed + 3, 0.0016, 3)
	_cfg(n_ridge, base_seed + 4, 0.006, 2)
	_cfg(n_moist, base_seed + 5, 0.0019, 3)
	_cfg(n_temp, base_seed + 6, 0.0011, 2)
	_cfg(n_river, base_seed + 7, 0.0013, 1)
	settlements.clear()
	pois.clear()
	roads.clear()
	_flats.clear()
	_road_boxes.clear()
	_uid = 0
	_generate_layout()

func _cfg(n: FastNoiseLite, s: int, f: float, oct: int) -> void:
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = f
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if oct > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = oct

# ---------------------------------------------------------------- terrain functions
func mountain_mask(x: float, z: float) -> float:
	var m := smoothstep(0.18, 0.55, n_mount.get_noise_2d(x, z))
	var d := maxf(absf(x), absf(z))
	if d > half - 160.0:
		m = maxf(m, smoothstep(half - 160.0, half - 20.0, d))
	return m

func river_factor(x: float, z: float) -> float:
	var rv := absf(n_river.get_noise_2d(x, z))
	return smoothstep(0.056, 0.016, rv)

## Height before settlement flattening and roads.
func raw_height(x: float, z: float) -> float:
	var base := 2.8 + n_height.get_noise_2d(x, z) * 6.0
	var h := base + n_detail.get_noise_2d(x, z) * 1.2
	var m := mountain_mask(x, z)
	if m > 0.0:
		h += m * (10.0 + 15.0 * (1.0 - absf(n_ridge.get_noise_2d(x, z))))
	var moist := n_moist.get_noise_2d(x, z)
	if moist > 0.3 and m < 0.15:
		h = lerpf(h, water_level + 0.35, smoothstep(0.3, 0.6, moist) * 0.75)
	var rf := river_factor(x, z) * (1.0 - m)
	if rf > 0.0:
		h = minf(h, lerpf(h, water_level - 1.6, rf))
	return h

func height(x: float, z: float) -> float:
	var h := raw_height(x, z)
	var cell := Vector2i(floori(x / FLAT_CELL), floori(z / FLAT_CELL))
	var arr = _flats.get(cell)
	if arr != null:
		for f in arr:
			var fp: Vector2 = f.pos
			var d := Vector2(x - fp.x, z - fp.y).length()
			var r: float = f.r
			if d < r * 1.7:
				h = lerpf(h, f.h, smoothstep(r * 1.7, r, d))
	var rd := road_distance(x, z)
	if rd < 6.0:
		var t := smoothstep(6.0, 1.5, rd)
		var smooth := 2.8 + n_height.get_noise_2d(x, z) * 6.0 + mountain_mask(x, z) * 12.0
		h = lerpf(h, maxf(minf(h, smooth + 0.5), water_level + 0.3), t * 0.75)
		if t > 0.2:
			h = maxf(h, water_level + 0.3)
	return h

func is_water(x: float, z: float) -> bool:
	return height(x, z) < water_level - 0.05

func road_distance(x: float, z: float) -> float:
	var best := 999.0
	var p := Vector2(x, z)
	for i in roads.size():
		var bx: Array = _road_boxes[i]
		if x < bx[0] - 8.0 or x > bx[2] + 8.0 or z < bx[1] - 8.0 or z > bx[3] + 8.0:
			continue
		var seg: Array = roads[i]
		var cp := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
		best = minf(best, cp.distance_to(p))
	return best

func settlement_at(x: float, z: float, scale_r: float = 1.0):
	for s in settlements:
		var sp: Vector2 = s.pos
		if Vector2(x - sp.x, z - sp.y).length() < float(s.radius) * scale_r:
			return s
	return null

func biome(x: float, z: float) -> String:
	return biome_at(x, z, height(x, z))

func biome_at(x: float, z: float, h: float) -> String:
	if settlement_at(x, z, 0.8) != null:
		return "urban"
	var m := mountain_mask(x, z)
	var temp := n_temp.get_noise_2d(x, z)
	if h > 17.0 and m > 0.4:
		return "snow" if temp < 0.12 else "mountain"
	if m > 0.45:
		return "mountain"
	var moist := n_moist.get_noise_2d(x, z)
	if moist > 0.3:
		return "swamp"
	if temp > 0.33 and moist < -0.22:
		return "sand"
	if moist > -0.05:
		return "forest"
	return "plains"

# ---------------------------------------------------------------- layout
func _id(prefix: String) -> String:
	_uid += 1
	return "%s%d_%d" % [prefix, era, _uid]

func _add_flat(p: Vector2, r: float, h: float) -> void:
	var f := {"pos": p, "r": r, "h": h}
	var ext := r * 1.7
	for cx in range(floori((p.x - ext) / FLAT_CELL), floori((p.x + ext) / FLAT_CELL) + 1):
		for cz in range(floori((p.y - ext) / FLAT_CELL), floori((p.y + ext) / FLAT_CELL) + 1):
			var k := Vector2i(cx, cz)
			if not _flats.has(k):
				_flats[k] = []
			_flats[k].append(f)

func _site_ok(p: Vector2, r: float, allow_mountain: bool = false) -> bool:
	if absf(p.x) > half - 90.0 - r or absf(p.y) > half - 90.0 - r:
		return false
	if not allow_mountain and mountain_mask(p.x, p.y) > 0.5:
		return false
	for a in [0.0, 1.57, 3.14, 4.71]:
		var q := p + Vector2(cos(a), sin(a)) * r * 0.8
		if river_factor(q.x, q.y) > 0.05:
			return false
	if river_factor(p.x, p.y) > 0.0:
		return false
	return raw_height(p.x, p.y) > water_level + 0.5

func _far_from_all(p: Vector2, r: float, spacing: float) -> bool:
	for s in settlements:
		if p.distance_to(s.pos) < float(s.radius) + r + 40.0:
			return false
	for q in pois:
		if p.distance_to(q.pos) < spacing + float(q.get("r", 10.0)):
			return false
	return true

func _flat_height(p: Vector2) -> float:
	return maxf(raw_height(p.x, p.y), water_level + 0.9)

func _generate_layout() -> void:
	var e: Dictionary = DBEras.era(era)
	# capital near the centre
	var cap_pos := Vector2.ZERO
	for i in 80:
		var c := Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90))
		if _site_ok(c, 80.0):
			cap_pos = c
			break
	_add_settlement(e.capital, "city", cap_pos, 78.0)
	# villages and towns
	var names: Array = e.settlement_names.duplicate()
	var n_v := rng.randi_range(6, 8)
	var made := 0
	var tries := 0
	while made < n_v and tries < 900:
		tries += 1
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(260.0, half - 220.0)
		var p := Vector2(cos(ang), sin(ang)) * dist
		var typ := "village" if rng.randf() < 0.6 else "town"
		var r := 46.0 if typ == "village" else 58.0
		if not _site_ok(p, r):
			continue
		var ok := true
		for s in settlements:
			if p.distance_to(s.pos) < float(s.radius) + r + 190.0:
				ok = false
				break
		if not ok:
			continue
		if era == 1 and made == 1:
			typ = "port"
			r = 58.0
		_add_settlement(names[made % names.size()], typ, p, r)
		made += 1
	# fortress-type settlement
	var fort_names := ["Замок Серый Утёс", "Цитадель Сан-Марко", "Форт Железный", "База «Бастион»", "Цитадель «Эгида»"]
	for i in 400:
		var ang2 := rng.randf() * TAU
		var p2 := Vector2(cos(ang2), sin(ang2)) * rng.randf_range(350.0, 800.0)
		if not _site_ok(p2, 55.0):
			continue
		var ok2 := true
		for s in settlements:
			if p2.distance_to(s.pos) < float(s.radius) + 240.0:
				ok2 = false
				break
		if ok2:
			_add_settlement(fort_names[era], "castle" if era <= 1 else "fort", p2, 55.0)
			break
	_build_roads()
	# service POIs inside settlements
	for s in settlements:
		var sq: float = float(s.radius) * 0.28
		var a0 := rng.randf() * TAU
		_add_poi("forge", "Кузница" if era <= 1 else ("Мастерская кузнеца" if era == 2 else "Оружейная"), s.pos + Vector2(cos(a0), sin(a0)) * sq * 0.75, 0.0, {"settlement": s.id})
		var svc := ""
		var svc_name := ""
		match era:
			1:
				svc = "lab"
				svc_name = "Алхимическая лаборатория"
			2:
				svc = "workshop"
				svc_name = "Мастерская изобретателя"
			3, 4:
				svc = "terminal"
				svc_name = "Терминал управления"
		if svc != "":
			_add_poi(svc, svc_name, s.pos + Vector2(cos(a0 + PI), sin(a0 + PI)) * sq * 0.75, 0.0, {"settlement": s.id})
	# boss lairs
	for bid in e.bosses:
		var bdef: Dictionary = DBActors.BOSSES.get(bid, {})
		_place_poi("lair", bdef.get("lair", "Логово"), 350.0, 900.0, 220.0, 30.0, {"boss_id": bid, "name": bdef.get("name", "")}, true)
	_place_poi("trial", "Суд Хроноса", 180.0, 520.0, 200.0, 28.0, {})
	for i in rng.randi_range(4, 6):
		_place_poi("rift", "Разлом времени", 200.0, half - 150.0, 160.0, 10.0, {})
	var cp_types: Array = e.cp_types
	var cp_names := {"watchtower": "Сторожевая башня", "altar": "Алтарь силы", "warehouse": "Склад", "resource_camp": "Ресурсный лагерь",
		"outpost": "Военный пост", "alchemy_lab": "Алхимический пост", "harbor": "Гавань", "factory": "Фабрика", "coal_mine": "Угольная шахта",
		"power_station": "Электростанция", "comm_tower": "Вышка связи", "lab": "Полевая лаборатория", "checkpoint": "Блокпост",
		"energy_station": "Энергостанция", "data_node": "Узел данных", "defense_turret": "Оборонная турель", "rift_anchor": "Якорь разлома"}
	var n_cp := rng.randi_range(10, 14)
	for i in n_cp:
		var ct: String = cp_types[i % cp_types.size()]
		_place_poi("cp", cp_names.get(ct, "Контрольная точка"), 140.0, half - 140.0, 120.0, 12.0, {"cp_type": ct})
	var camp_names := ["Лагерь разбойников", "Пиратская стоянка", "Логово банды", "Лагерь наёмников", "Укрытие киберохотников"]
	for i in rng.randi_range(10, 16):
		_place_poi("camp", camp_names[era], 160.0, half - 120.0, 110.0, 15.0, {})
	var dn := ["Катакомбы", "Затопленный погреб", "Заброшенная шахта", "Старый бункер", "Подземный комплекс"]
	for i in 4:
		_place_poi("dungeon", dn[era], 200.0, half - 140.0, 160.0, 8.0, {})
	for i in 3:
		_place_poi("altar", "Древний алтарь", 150.0, half - 150.0, 160.0, 8.0, {})
	_place_poi("mirror", "Зеркало Времени", 250.0, half - 200.0, 200.0, 6.0, {})
	for i in 2:
		_place_poi("ruins", ["Древние руины", "Руины виллы", "Заброшенный завод", "Разрушенный квартал", "Руины станции"][era], 200.0, half - 150.0, 180.0, 16.0, {})
	_place_poi("fortress", ["Заброшенная крепость", "Покинутый форт", "Ржавая цитадель", "Брошенная база", "Мёртвая аркология"][era], 300.0, 850.0, 220.0, 30.0, {})
	_place_poi("witness", "Приют Свидетеля", 120.0, 600.0, 150.0, 6.0, {})
	if era == 0:
		_place_poi("tourney", "Турнирное поле", 120.0, 500.0, 150.0, 26.0, {})
	for i in 2:
		_place_poi("shrine", ["Часовня", "Капелла", "Пункт помощи", "Медпункт", "Станция восстановления"][era], 150.0, half - 250.0, 300.0, 6.0, {})
	# spawn: the village nearest to the centre (not the capital)
	var best := 1e9
	var start = settlements[0]
	for s in settlements:
		if s.type == "village" or s.type == "town":
			var d: float = s.pos.length()
			if d < best:
				best = d
				start = s
	var to_c: Vector2 = (cap_pos - start.pos).normalized() if start.pos.distance_to(cap_pos) > 1.0 else Vector2(0, 1)
	_spawn = start.pos + to_c * 5.0

func _add_settlement(nm: String, typ: String, p: Vector2, r: float) -> void:
	var h := _flat_height(p)
	var s := {"id": _id("s"), "name": nm, "pos": p, "type": typ, "radius": r, "height": h, "buildings": [],
		"owner": "", "population": 0, "guards": 0, "security": 0.5, "resources": 100}
	match typ:
		"city":
			s.population = 60
			s.guards = 10
			s.security = 0.85
		"town", "port":
			s.population = 35
			s.guards = 6
			s.security = 0.7
		"castle", "fort":
			s.population = 25
			s.guards = 12
			s.security = 0.9
		_:
			s.population = 18
			s.guards = 3
			s.security = 0.5
	var facs: Array = DBEras.factions_of(era)
	if typ in ["castle", "fort"]:
		s.owner = facs[0]
	elif not facs.is_empty() and rng.randf() < 0.75:
		s.owner = facs[rng.randi() % facs.size()]
	settlements.append(s)
	_add_flat(p, r, h)
	_layout_buildings(s)

func _layout_buildings(s: Dictionary) -> void:
	var kinds: Array = []
	var total := 6
	match s.type:
		"village":
			kinds = ["inn", "smithy"]
			total = rng.randi_range(5, 8)
		"town", "port":
			kinds = ["inn", "smithy", "shop", "hall", "warehouse"]
			if s.type == "port":
				kinds.append("warehouse")
			total = rng.randi_range(8, 11)
		"city":
			kinds = ["inn", "smithy", "shop", "shop", "hall", "tower", "warehouse", "warehouse", "inn"]
			total = rng.randi_range(12, 14)
		_:
			kinds = ["hall", "tower", "tower", "warehouse", "smithy"]
			total = rng.randi_range(6, 8)
	while kinds.size() < total:
		kinds.append("house")
	var sizes := {"house": Vector2(7, 6), "inn": Vector2(10, 8), "shop": Vector2(8, 6), "smithy": Vector2(7, 7),
		"hall": Vector2(13, 10), "tower": Vector2(6, 6), "warehouse": Vector2(12, 8)}
	var center: Vector2 = s.pos
	var r: float = s.radius
	var square_r := r * 0.28
	var placed: Array = []
	var bi := 0
	for k in kinds:
		var sz: Vector2 = sizes[k]
		if k == "house":
			sz += Vector2(rng.randi_range(-1, 1), rng.randi_range(-1, 0))
		var ok := false
		for attempt in 40:
			var ring := 0 if attempt < 20 else 1
			var a := rng.randf() * TAU
			var dist := square_r + sz.y * 0.5 + 2.5 + ring * 13.0 + rng.randf_range(0.0, 3.0)
			if dist + maxf(sz.x, sz.y) * 0.6 > r * 0.9:
				continue
			var p := center + Vector2(cos(a), sin(a)) * dist
			var rad := maxf(sz.x, sz.y) * 0.62
			var clash := false
			for q in placed:
				if p.distance_to(q[0]) < rad + float(q[1]) + 1.5:
					clash = true
					break
			if clash:
				continue
			var dir := (center - p).normalized()
			var b := {"id": "%s_b%d" % [s.id, bi], "pos": p, "size": sz, "rot": atan2(dir.x, dir.y), "kind": k, "height": s.height}
			s.buildings.append(b)
			placed.append([p, rad])
			bi += 1
			ok = true
			break
		if not ok:
			continue

func _build_roads() -> void:
	var n := settlements.size()
	if n < 2:
		return
	var in_tree := [0]
	var edges: Array = []
	while in_tree.size() < n:
		var best := 1e12
		var bi := -1
		var bj := -1
		for i in in_tree:
			for j in n:
				if j in in_tree:
					continue
				var d: float = settlements[i].pos.distance_to(settlements[j].pos)
				if d < best:
					best = d
					bi = i
					bj = j
		edges.append([bi, bj])
		in_tree.append(bj)
	# a couple of extra links to the capital for loops
	for j in range(1, n):
		var linked := false
		for e in edges:
			if (e[0] == 0 and e[1] == j) or (e[1] == 0 and e[0] == j):
				linked = true
		if not linked and settlements[j].pos.distance_to(settlements[0].pos) < 600.0 and rng.randf() < 0.5:
			edges.append([0, j])
	for e in edges:
		var a: Vector2 = settlements[e[0]].pos
		var b: Vector2 = settlements[e[1]].pos
		var mid := (a + b) * 0.5
		var perp := (b - a).orthogonal().normalized()
		mid += perp * rng.randf_range(-0.12, 0.12) * a.distance_to(b)
		_add_road(a, mid)
		_add_road(mid, b)

func _add_road(a: Vector2, b: Vector2) -> void:
	roads.append([a, b])
	_road_boxes.append([minf(a.x, b.x), minf(a.y, b.y), maxf(a.x, b.x), maxf(a.y, b.y)])

func _add_poi(typ: String, nm: String, p: Vector2, r: float, data: Dictionary) -> Dictionary:
	var poi := {"id": _id("p"), "type": typ, "pos": p, "name": nm, "data": data, "r": r}
	pois.append(poi)
	if r > 0.0:
		_add_flat(p, r, _flat_height(p))
	return poi

func _place_poi(typ: String, nm: String, dmin: float, dmax: float, spacing: float, r: float, data: Dictionary, allow_mountain: bool = false) -> void:
	for i in 260:
		var ang := rng.randf() * TAU
		var p := Vector2(cos(ang), sin(ang)) * rng.randf_range(dmin, dmax)
		if not _site_ok(p, r, allow_mountain):
			continue
		if not _far_from_all(p, r, spacing):
			continue
		if road_distance(p.x, p.y) < r + 4.0:
			continue
		_add_poi(typ, nm, p, r, data.duplicate())
		return
	# relaxed fallback so required POIs always exist
	for i in 400:
		var p2 := Vector2(rng.randf_range(-half + 150, half - 150), rng.randf_range(-half + 150, half - 150))
		if raw_height(p2.x, p2.y) > water_level + 0.5 and _far_from_all(p2, r, spacing * 0.4):
			_add_poi(typ, nm, p2, r, data.duplicate())
			return

func spawn_point() -> Vector2:
	return _spawn

func pois_of(typ: String) -> Array:
	var out: Array = []
	for p in pois:
		if p.type == typ:
			out.append(p)
	return out

func nearest_place(p: Vector2) -> String:
	for s in settlements:
		if p.distance_to(s.pos) < float(s.radius) * 1.5:
			return s.name
	var best := ""
	var bd := 45.0
	for q in pois:
		var d: float = p.distance_to(q.pos)
		if d < bd + float(q.get("r", 0.0)):
			bd = d
			best = q.name
	if best != "":
		return best
	if is_water(p.x, p.y) or river_factor(p.x, p.y) > 0.3:
		return ["Берег реки", "Речная заводь", "Канал", "Набережная", "Охладительный канал"][era]
	var b := biome(p.x, p.y)
	var names := {
		"forest": ["Тёмный лес", "Кипарисовая роща", "Сухой лес", "Лесопарк", "Синтетическая роща"],
		"plains": ["Широкие луга", "Виноградные холмы", "Угольные поля", "Пригород", "Пустоши колонии"],
		"mountain": ["Скалистые горы", "Мраморные утёсы", "Рудные горы", "Карьеры", "Кристальные пики"],
		"swamp": ["Гиблые топи", "Малярийные болота", "Отстойники", "Затопленная зона", "Токсичные топи"],
		"sand": ["Пустошь", "Выжженная равнина", "Шлаковые пустоши", "Зона отчуждения", "Мёртвые дюны"],
		"snow": ["Снежные вершины", "Ледяной перевал", "Морозные высоты", "Северный хребет", "Криозона"],
		"urban": ["Окраины", "Предместье", "Рабочие кварталы", "Спальный район", "Нижний уровень"],
	}
	return names.get(b, names.plains)[era]

func _ground_color(b: String) -> Color:
	var g: Dictionary = DBEras.era(era).ground
	return g.get(b, g.plains)

## Coloured overview map for the minimap / world map. Recommended size 160-256.
func overview_image(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var water_c: Color = DBEras.era(era).water
	water_c.a = 1.0
	var step := half * 2.0 / size
	for py in size:
		for px in size:
			var x := -half + (px + 0.5) * step
			var z := -half + (py + 0.5) * step
			var h := raw_height(x, z)
			var c: Color
			if h < water_level - 0.05:
				c = water_c
			else:
				c = _ground_color(biome_at(x, z, h)).lightened(clampf(h / 60.0, -0.1, 0.35))
				if mountain_mask(x, z) > 0.45:
					c = c.darkened(0.05)
			img.set_pixel(px, py, c)
	var road_c := _ground_color("road").lightened(0.15)
	for seg in roads:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var n := int(a.distance_to(b) / step) + 1
		for i in n + 1:
			var q := a.lerp(b, float(i) / n)
			var ix := int((q.x + half) / step)
			var iy := int((q.y + half) / step)
			if ix >= 0 and iy >= 0 and ix < size and iy < size:
				img.set_pixel(ix, iy, road_c)
	for s in settlements:
		var sp: Vector2 = s.pos
		var cx := int((sp.x + half) / step)
		var cy := int((sp.y + half) / step)
		var rr := maxi(2, int(float(s.radius) * 0.6 / step))
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				var ix2 := cx + dx
				var iy2 := cy + dy
				if ix2 >= 0 and iy2 >= 0 and ix2 < size and iy2 < size and dx * dx + dy * dy <= rr * rr:
					img.set_pixel(ix2, iy2, Color(0.92, 0.85, 0.65) if s.type != "city" else Color(1.0, 0.92, 0.7))
	return img
