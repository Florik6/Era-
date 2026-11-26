class_name Housing
extends Node
## Player Housing System.
##  * One house per town is for sale (a real building of the settlement,
##    chosen deterministically, only in towns with at least two houses so the
##    residents keep theirs). Five kinds, one per era: деревянный дом, каменный
##    городской дом, промышленный особняк, современная квартира, футуристическое
##    жилище — each with a price, a base chest capacity and furniture slots.
##  * Buying records real ownership in Profile.homes (saved with the profile,
##    never deleted on era changes). The house is reserved for the player even
##    before it is sold: CityLife gives it no residents or spots, NPCs never
##    pick it for routines, exploring, shelter or events, its door opens only
##    for the owner (and for nobody while it is for sale) and cannot be broken.
##    Any NPC that still ends up inside is put outside the door at once.
##  * Safe zone: nobody can hurt the owner inside, and no fighting from inside.
##  * Personal chest (Profile.home_chest): one shared storage reachable from
##    any owned house in any era; capacity = house kind + storage upgrades +
##    placed chests/lockers/safes. The storage screen moves, sorts, filters,
##    searches, merges and splits stacks.
##  * Furniture: catalog «home» items are placed in a live placement mode
##    (ghost follows the hero, rotate, confirm), saved per house, picked up
##    again. Beds rest (sleep until morning, autosave; Hardcore recovery),
##    hearths add comfort, workbenches/alchemy tables open crafting, med
##    stations / capsules treat wounds, racks and displays show weapons, the
##    wall map opens the map, wardrobes open the equipment screen.
##  * Upgrades: storage (+20 chest places), comfort (better rest), extension
##    (+4 furniture places).

const TYPES := [
	{"id": "wood", "era": 0, "name": "Деревянный дом", "price": 600, "cap": 30, "slots": 6, "desc": "Бревенчатый дом с печью и кроватью. Тепло, тихо, свой замок на двери."},
	{"id": "stone", "era": 1, "name": "Каменный городской дом", "price": 1500, "cap": 40, "slots": 8, "desc": "Каменный дом в черте города: крепкие стены, кабинет, место для мастерской."},
	{"id": "mansion", "era": 2, "name": "Промышленный особняк", "price": 3500, "cap": 50, "slots": 10, "desc": "Особняк с паровым отоплением, газовым светом и мастерской."},
	{"id": "apartment", "era": 3, "name": "Современная квартира", "price": 7000, "cap": 60, "slots": 10, "desc": "Квартира с электронным замком, кухней и местом для медстанции."},
	{"id": "future", "era": 4, "name": "Футуристическое жилище", "price": 14000, "cap": 80, "slots": 12, "desc": "Жилой модуль с климат-контролем, голографическим светом и энергощитом двери."},
]
const UPGRADES := {
	"storage": {"name": "Расширение хранилища", "max": 3, "price": [300, 700, 1500], "desc": "+20 мест в личном сундуке"},
	"comfort": {"name": "Уют", "max": 2, "price": [400, 1000], "desc": "Отдых восстанавливает и лечит быстрее"},
	"space": {"name": "Пристройка", "max": 2, "price": [500, 1200], "desc": "+4 места для мебели"},
}
const CHEST_LIKE := ["chest", "wardrobe"]

static var inst: Housing = null
static var private_ids := {}       # bid -> sid: houses reserved for the player (for sale or owned)

var world
var sale := {}                     # sid -> {sid, bid, name}
var nodes := {}                    # bid -> WeakRef(Building)
var _dressed := {}                 # bid -> "sale" | "owned" (what is attached to the node now)
var _props := {}                   # bid -> Array of Nodes attached by Housing
var player_home = null             # the owned Building the player stands in (safe zone)
var placing := {}                  # placement mode: {entry, item, ghost, bar, rot, bid}
var stats := {"evictions": 0, "blocked_hits": 0, "bought": 0, "rests": 0, "placed": 0, "removed": 0, "moved_in": 0, "moved_out": 0}
var _t := 0.0
var _scan_t := 0.0

func setup(w) -> void:
	world = w
	inst = self
	private_ids.clear()
	sale.clear()
	if w.gen == null:
		return
	for s in w.gen.settlements:
		var b := pick_house(s)
		if b.is_empty():
			continue
		private_ids[str(b.id)] = str(s.id)
		sale[str(s.id)] = {"sid": str(s.id), "bid": str(b.id), "name": str(s.get("name", ""))}
		if CityLife.inst != null and CityLife.inst.has_method("forget_building"):
			CityLife.inst.forget_building(str(s.id), str(b.id))
	_chest().capacity = chest_capacity()

func _exit_tree() -> void:
	if inst == self:
		inst = null

## The house of a settlement that is for sale: the "house" building farthest
## from the centre (a quiet street), only where at least two houses exist.
static func pick_house(s: Dictionary) -> Dictionary:
	var houses: Array = []
	for b in s.get("buildings", []):
		if str(b.get("kind", "")) == "house":
			houses.append(b)
	if houses.size() < 2:
		return {}
	var best := {}
	var bd := -1.0
	for b in houses:
		var d: float = (b.pos as Vector2).distance_to(s.pos) if b.pos is Vector2 else 0.0
		if d > bd:
			bd = d
			best = b
	return best

static func is_private(bid: String) -> bool:
	return private_ids.has(bid)

static func is_private_building(b) -> bool:
	return b != null and is_instance_valid(b) and private_ids.has(str(b.get("id")))

static func type_for_era(era: int) -> Dictionary:
	return TYPES[clampi(era, 0, TYPES.size() - 1)]

static func key(era: int, bid: String) -> String:
	return "%d:%s" % [era, bid]

func home(bid: String, era := -1) -> Dictionary:
	return Profile.homes.get(key(Profile.current_era if era < 0 else era, bid), {})

func owns(bid: String) -> bool:
	return not home(bid).is_empty()

func owned_here() -> Array:
	var out: Array = []
	for k in Profile.homes:
		if int(Profile.homes[k].era) == Profile.current_era:
			out.append(Profile.homes[k])
	return out

func _chest() -> Inventory:
	return Profile.home_chest

## Shared chest capacity: the best owned house + storage upgrades + every
## placed chest / locker / safe / wardrobe in any owned house (any era).
func chest_capacity() -> int:
	var base := 0
	var extra := 0
	for k in Profile.homes:
		var h: Dictionary = Profile.homes[k]
		var t: Dictionary = _type_by_id(str(h.type))
		base = maxi(base, int(t.get("cap", 30)) + 20 * int(h.get("upgrades", {}).get("storage", 0)))
		for f in h.get("furniture", []):
			var fb := ItemDB.base(str(f.base))
			if str(fb.get("furniture", "")) in CHEST_LIKE:
				extra += int(fb.get("capacity", 0))
	return base + extra

func _type_by_id(id: String) -> Dictionary:
	for t in TYPES:
		if t.id == id:
			return t
	return TYPES[0]

func slots_of(h: Dictionary) -> int:
	return int(_type_by_id(str(h.type)).slots) + 4 * int(h.get("upgrades", {}).get("space", 0))

# ------------------------------------------------------------------ buying
func buy(sid: String) -> bool:
	var s: Dictionary = sale.get(sid, {})
	if s.is_empty():
		return false
	if owns(s.bid):
		return true
	var t := type_for_era(Profile.current_era)
	var pl = world.player
	if pl.data.gold < int(t.price):
		Events.notify.emit("Не хватает денег: нужно %d" % int(t.price), Color(1.0, 0.5, 0.4))
		return false
	pl.data.gold -= int(t.price)
	Profile.homes[key(Profile.current_era, s.bid)] = {"era": Profile.current_era, "sid": sid, "bid": s.bid, "type": t.id, "town": s.name,
		"bought": Game.game_time, "upgrades": {"storage": 0, "comfort": 0, "space": 0}, "furniture": []}
	stats.bought += 1
	_chest().capacity = chest_capacity()
	_dressed.erase(s.bid)          # re-dress the building as owned
	Chronicle.record("home_bought", [pl], {"pos_v3": pl.global_position, "place": s.name,
		"text": "%s купил(а) дом — «%s» в поселении «%s»." % [Profile.char.name, t.name, s.name]})
	Events.banner.emit("Свой дом", "%s · %s" % [t.name, s.name], Color(1.0, 0.85, 0.45))
	Audio.play_sfx("mastery_up")
	SaveSys.save_game()
	return true

# ------------------------------------------------------------------ tick
func _process(delta: float) -> void:
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	_t += delta
	if _t < 0.25:
		return
	_t = 0.0
	_scan_t -= 0.25
	if _scan_t <= 0.0:
		_scan_t = 2.0
		_find_nodes()
	var pl = world.player
	player_home = null
	for bid in nodes:
		var b = nodes[bid].get_ref()
		if b == null or not is_instance_valid(b):
			continue
		var owned := owns(bid)
		var want := "owned" if owned else "sale"
		if _dressed.get(bid, "") != want:
			_dress(b, want)
		if b.global_position.distance_to(pl.global_position) > 60.0:
			continue
		# privacy: nobody but the owner stays inside
		for a in Game.actors_near(b.global_position, (b.w + b.d) * 0.6):
			if a == pl or a.is_dead or a.get("owner_actor") == pl:
				continue
			if b.contains(a.global_position):
				_evict(a, b)
		if owned and b.contains(pl.global_position):
			player_home = b

func _find_nodes() -> void:
	var pl = world.player
	for bid in nodes.keys():
		var r = nodes[bid].get_ref()
		if r == null or not is_instance_valid(r):
			nodes.erase(bid)
			_dressed.erase(bid)
			_props.erase(bid)
	for b in get_tree().get_nodes_in_group("buildings"):
		var bid := str(b.get("id"))
		if private_ids.has(bid) and not nodes.has(bid) and b.global_position.distance_to(pl.global_position) < 200.0:
			nodes[bid] = weakref(b)

func building(bid: String):
	if not nodes.has(bid):
		_find_nodes()
	var r = nodes.get(bid)
	return r.get_ref() if r != null else null

func _evict(a, b) -> void:
	var out: Vector3 = b.door_out + (b.door_out - b.door_in).normalized() * 1.5
	out.y = world.ground_height(out) + 0.1
	a.global_position = out
	a.velocity = Vector3.ZERO
	if a.get("brain") != null and a.brain.get("path") != null:
		a.brain.path = []
	if world.player:
		a.aggro.erase(world.player.actor_id)
	stats.evictions += 1

## Attach the sale sign or the owner's nameplate, the door lock and (owned)
## the built-in bed / chest and the placed furniture.
func _dress(b, mode: String) -> void:
	for n in _props.get(str(b.id), []):
		if is_instance_valid(n):
			n.queue_free()
	_props[str(b.id)] = []
	_dressed[str(b.id)] = mode
	if b.door_node != null and is_instance_valid(b.door_node):
		b.door_node.lock = "owner" if mode == "owned" else "closed"
	var sid: String = private_ids[str(b.id)]
	var sign := HomeProp.new()
	sign.housing = self
	sign.kind = "sign" if mode == "sale" else "plate"
	sign.bid = str(b.id)
	sign.sid = sid
	b.add_child(sign)
	sign.position = Vector3(b.door_x + 1.6, 0.0, b.d * 0.5 + 0.9)
	_props[str(b.id)].append(sign)
	if mode != "owned":
		return
	var hw: float = b.w * 0.5
	var hd: float = b.d * 0.5
	# built-ins: the house's own bed and a personal chest
	var bed := HomeProp.new()
	bed.housing = self
	bed.kind = "bed_builtin"
	bed.bid = str(b.id)
	b.add_child(bed)
	bed.position = Vector3(-hw + 1.6, 0.0, -hd + 1.4)
	_props[str(b.id)].append(bed)
	var ch := HomeProp.new()
	ch.housing = self
	ch.kind = "chest_builtin"
	ch.bid = str(b.id)
	b.add_child(ch)
	ch.position = Vector3(-hw + 0.55, 0.0, -hd + 2.75)
	ch.rotation.y = -PI * 0.5
	_props[str(b.id)].append(ch)
	var h := home(str(b.id))
	for f in h.get("furniture", []):
		_spawn_furniture(b, f)

func _spawn_furniture(b, f: Dictionary) -> Node3D:
	var fp := HomeProp.new()
	fp.housing = self
	fp.kind = "furniture"
	fp.entry = f
	fp.bid = str(b.id)
	b.add_child(fp)
	fp.position = Vector3(float(f.x), 0.0, float(f.z))
	fp.rotation.y = float(f.rot)
	_props[str(b.id)].append(fp)
	return fp

## Safe zone: no damage to or from the owner inside the house.
static func blocks(att, tgt) -> bool:
	if inst == null or inst.player_home == null or not is_instance_valid(inst.player_home):
		return false
	if (tgt != null and is_instance_valid(tgt) and tgt.get("is_player") == true) or (att != null and is_instance_valid(att) and att.get("is_player") == true):
		inst.stats.blocked_hits += 1
		return true
	return false

# ------------------------------------------------------------------ chest
func move_to_chest(it: Dictionary, n := -1) -> bool:
	var inv: Inventory = world.player.data.inv
	return _move(inv, _chest(), it, n)

func move_to_bag(it: Dictionary, n := -1) -> bool:
	return _move(_chest(), world.player.data.inv, it, n)

func _move(from: Inventory, to: Inventory, it: Dictionary, n: int) -> bool:
	_chest().capacity = chest_capacity()
	var q: int = int(it.get("qty", 1))
	if n > 0 and n < q:
		var part: Dictionary = it.duplicate(true)
		part.qty = n
		part.uid = ItemDB.next_uid()
		if not to.add(part):
			return false
		it.qty = q - n
		return true
	var taken := from.remove(int(it.uid))
	if taken.is_empty():
		return false
	if not to.add(taken):
		from.items.append(taken)
		return false
	return true

func upgrade(bid: String, kind: String) -> bool:
	var h := home(bid)
	var u: Dictionary = UPGRADES.get(kind, {})
	if h.is_empty() or u.is_empty():
		return false
	var lvl := int(h.upgrades.get(kind, 0))
	if lvl >= int(u.max):
		return false
	var price: int = int(u.price[lvl]) * (Profile.current_era + 1)
	if world.player.data.gold < price:
		Events.notify.emit("Не хватает денег: нужно %d" % price, Color(1.0, 0.5, 0.4))
		return false
	world.player.data.gold -= price
	h.upgrades[kind] = lvl + 1
	_chest().capacity = chest_capacity()
	Events.notify.emit("%s: уровень %d" % [u.name, lvl + 1], Color(1.0, 0.85, 0.45))
	Audio.play_sfx("mastery_up")
	return true

# ------------------------------------------------------------------ furniture
## Check a placement (local coordinates of the building).
func can_place(b, local: Vector3, ignore_uid := -1) -> String:
	var h := home(str(b.id))
	if h.is_empty():
		return "это не ваш дом"
	var hw: float = b.w * 0.5 - 0.55
	var hd: float = b.d * 0.5 - 0.55
	if absf(local.x) > hw or absf(local.z) > hd:
		return "нужно ставить внутри дома"
	var door_l := Vector3(b.door_x, 0, b.d * 0.5 - 1.0)
	if Vector2(local.x - door_l.x, local.z - door_l.z).length() < 1.3:
		return "не загораживайте дверь"
	for p in [Vector3(-b.w * 0.5 + 0.75, 0, -b.d * 0.5 + 1.2), Vector3(-b.w * 0.5 + 0.55, 0, -b.d * 0.5 + 2.75), Vector3(b.w * 0.5 - 1.0, 0, -b.d * 0.5 + 0.45)]:
		if Vector2(local.x - p.x, local.z - p.z).length() < 1.0:
			return "место занято"
	for f in h.furniture:
		if int(f.uid) != ignore_uid and Vector2(local.x - float(f.x), local.z - float(f.z)).length() < 0.95:
			return "слишком близко к другой мебели"
	if h.furniture.size() >= slots_of(h) and ignore_uid < 0:
		return "нет места для мебели (улучшение «Пристройка»)"
	return ""

## Place a furniture item from the bag. Returns "" or the reason.
func place(bid: String, it: Dictionary, local: Vector3, rot: float) -> String:
	var b = building(bid)
	if b == null:
		return "дом далеко"
	var why := can_place(b, local)
	if why != "":
		return why
	var inv: Inventory = world.player.data.inv
	var taken := inv.remove(int(it.uid))
	if taken.is_empty():
		return "предмета нет в сумке"
	var h := home(bid)
	var f := {"uid": int(taken.uid), "base": str(taken.base), "x": snappedf(local.x, 0.05), "z": snappedf(local.z, 0.05), "rot": snappedf(rot, 0.01), "item": taken, "items": []}
	h.furniture.append(f)
	_spawn_furniture(b, f)
	_chest().capacity = chest_capacity()
	stats.placed += 1
	Audio.play_sfx("pickup")
	return ""

func pick_up(bid: String, uid: int) -> bool:
	var h := home(bid)
	for f in h.get("furniture", []):
		if int(f.uid) == uid:
			# whatever is on a rack / in a display goes back to the bag first
			for it in f.get("items", []):
				if not world.player.data.inv.add(it):
					_chest().add(it)
			var item: Dictionary = f.get("item", {})
			if item.is_empty():
				item = ItemDB.create(str(f.base), 0, 1)
			if not world.player.data.inv.add(item):
				Events.notify.emit("Сумка полна", Color(1.0, 0.5, 0.4))
				return false
			h.furniture.erase(f)
			stats.removed += 1
			_chest().capacity = chest_capacity()
			_dressed.erase(bid)           # rebuild the props
			return true
	return false

# ------------------------------------------------------------------ rest
## Sleep in your own bed until 07:00: full health, Hardcore recovery, autosave.
func sleep(bid: String) -> float:
	var pl = world.player
	var h := home(bid)
	var now := Game.game_time
	var hour := fposmod(now, 1.0) * 24.0
	var hours := (31.0 - hour) if hour >= 7.0 else (7.0 - hour)
	hours = clampf(hours, 1.0, 16.0)
	Game.game_time = now + hours / 24.0
	var quality := 2 + int(h.get("upgrades", {}).get("comfort", 0))
	var bonus := 0.0
	var has_med := false
	for f in h.get("furniture", []):
		var fb := ItemDB.base(str(f.base))
		bonus += float(fb.get("rest", 0.0))
		if str(fb.get("furniture", "")) == "med_station":
			has_med = true
	if has_med:
		quality += 1
	if bonus >= 0.2:
		quality += 1
	pl.hp = pl.max_hp
	pl.mana = pl.max_mana
	pl.stamina = pl.max_stamina
	var hc = world.sys("hardcore")
	if hc != null and hc.enabled():
		hc.rest(hours, quality)
		pl.recalc_stats()
		pl.hp = pl.max_hp
	stats.rests += 1
	Events.notify.emit("Вы выспались дома (%d ч). Прогресс сохранён." % roundi(hours), Color(0.7, 0.9, 1.0))
	Audio.play_sfx("heal")
	SaveSys.save_game()
	return hours

# ------------------------------------------------------------------ interactions
func use_prop(p) -> void:
	match String(p.kind):
		"sign":
			_sale_dialog(p.sid)
		"plate":
			_manage_dialog(p.bid)
		"bed_builtin":
			sleep(p.bid)
		"chest_builtin":
			open_chest(p.bid)
		"furniture":
			_use_furniture(p)

func open_chest(bid: String) -> void:
	_chest().capacity = chest_capacity()
	world.ui.open("storage", {"bid": bid})

func _use_furniture(p) -> void:
	var f: Dictionary = p.entry
	var fb := ItemDB.base(str(f.base))
	var hc = world.sys("hardcore")
	match str(fb.get("furniture", "")):
		"bed":
			sleep(p.bid)
		"chest":
			open_chest(p.bid)
		"wardrobe":
			world.ui.open("inventory")
		"hearth":
			world.player.heal(world.player.max_hp * 0.25)
			world.player.stamina = world.player.max_stamina
			Events.notify.emit("Вы погрелись у огня", Color(1.0, 0.75, 0.4))
		"alchemy":
			_craft("lab", "Домашняя алхимия")
		"workbench":
			_craft("workshop", "Домашняя мастерская")
		"map":
			world.ui.open("map")
		"med_station":
			var tier := int(fb.get("heal_tier", 1))
			if hc != null and hc.enabled():
				hc.treat_all("capsule" if tier >= 3 else "station", tier)
			world.player.heal(world.player.max_hp * (1.0 if tier >= 3 else 0.5))
		"weapon_rack", "display":
			_display_dialog(p)

func _craft(station: String, title: String) -> void:
	var recipes: Array = Recipes.for_station(world, station)
	recipes.append_array(Recipes.for_station(world, "home"))
	world.ui.open("craft", {"title": title, "recipes": recipes})

func _sale_dialog(sid: String) -> void:
	var t := type_for_era(Profile.current_era)
	var s: Dictionary = sale.get(sid, {})
	var cur: String = DBEras.era(Profile.current_era).currency
	var text := "[b]%s[/b] — %s\n%s\n\nЦена: [color=#ffd36b]%d %s[/color] · сундук на %d мест · мебель: %d мест.\nДом станет вашим навсегда: посторонние не входят, внутри безопасно, сундук общий для всех ваших домов." % [t.name, s.get("name", ""), t.desc, int(t.price), cur, int(t.cap), int(t.slots)]
	var opts: Array = []
	opts.append({"text": "Купить за %d" % int(t.price), "cb": func(): buy(sid), "disabled": world.player.data.gold < int(t.price)})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": "Дом продаётся", "text": text, "portrait_color": Color(1.0, 0.85, 0.45), "options": opts})

func _manage_dialog(bid: String) -> void:
	var h := home(bid)
	var t := _type_by_id(str(h.type))
	var text := "[b]%s[/b] · %s\nСундук: %d / %d · мебель: %d / %d\nУют: %d · хранилище: %d · пристройка: %d" % [t.name, h.town, _chest().items.size(), chest_capacity(),
		h.furniture.size(), slots_of(h), int(h.upgrades.comfort), int(h.upgrades.storage), int(h.upgrades.space)]
	var opts: Array = []
	opts.append({"text": "Личный сундук", "cb": func(): open_chest(bid)})
	opts.append({"text": "Спать до утра", "cb": func(): sleep(bid)})
	var furn: Array = world.player.data.inv.items.filter(func(it): return str(ItemDB.base(it.base).get("slot", "")) == "home")
	if not furn.is_empty():
		opts.append({"text": "Расставить мебель (%d в сумке)" % furn.size(), "cb": func(): _choose_furniture(bid), "close": true})
	if not h.furniture.is_empty():
		opts.append({"text": "Убрать мебель", "cb": func(): _remove_dialog(bid), "close": true})
	opts.append({"text": "Улучшения", "cb": func(): _upgrade_dialog(bid), "close": true})
	opts.append({"text": "Выйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": "Мой дом", "text": text, "portrait_color": Color(1.0, 0.85, 0.45), "options": opts})

func _choose_furniture(bid: String) -> void:
	var opts: Array = []
	for it in world.player.data.inv.items:
		if str(ItemDB.base(it.base).get("slot", "")) == "home":
			var item: Dictionary = it
			opts.append({"text": ItemDB.display_name(item), "cb": func(): start_placing(bid, item)})
	opts.append({"text": "Назад", "cb": func(): _manage_dialog(bid)})
	world.ui.open("dialog", {"title": "Что поставить?", "text": "Выберите предмет — затем подойдите к нужному месту, поверните и нажмите «Поставить».", "options": opts})

func _remove_dialog(bid: String) -> void:
	var opts: Array = []
	for f in home(bid).furniture:
		var uid: int = int(f.uid)
		opts.append({"text": "Убрать: %s" % ItemDB.base(str(f.base)).get("name", f.base), "cb": func(): pick_up(bid, uid)})
	opts.append({"text": "Назад", "cb": func(): _manage_dialog(bid)})
	world.ui.open("dialog", {"title": "Убрать мебель", "text": "Мебель вернётся в сумку.", "options": opts})

func _upgrade_dialog(bid: String) -> void:
	var h := home(bid)
	var opts: Array = []
	for k in UPGRADES:
		var u: Dictionary = UPGRADES[k]
		var lvl := int(h.upgrades.get(k, 0))
		var kk: String = k
		if lvl >= int(u.max):
			opts.append({"text": "%s — максимум" % u.name, "cb": func(): pass, "disabled": true})
		else:
			var price: int = int(u.price[lvl]) * (Profile.current_era + 1)
			opts.append({"text": "%s %d→%d (%d): %s" % [u.name, lvl, lvl + 1, price, u.desc], "cb": func(): upgrade(bid, kk)})
	opts.append({"text": "Назад", "cb": func(): _manage_dialog(bid)})
	world.ui.open("dialog", {"title": "Улучшения дома", "text": "Улучшения сохраняются навсегда.", "options": opts})

## Weapon racks and displays: mount weapons / relics from the bag, take them back.
func _display_dialog(p) -> void:
	var f: Dictionary = p.entry
	var fb := ItemDB.base(str(f.base))
	var cap := int(fb.get("capacity", 4))
	var opts: Array = []
	for it in f.items:
		var item: Dictionary = it
		opts.append({"text": "Снять: %s" % ItemDB.display_name(item), "cb": func():
			if world.player.data.inv.add(item):
				f.items.erase(item)
				p.rebuild()})
	if f.items.size() < cap:
		for it in world.player.data.inv.items:
			var b := ItemDB.base(it.base)
			if str(b.get("slot", "")) in ["main", "off"] or (str(fb.furniture) == "display" and int(it.get("rarity", 0)) >= 3):
				var item2: Dictionary = it
				opts.append({"text": "Выставить: %s" % ItemDB.display_name(item2), "cb": func():
					var taken: Dictionary = world.player.data.inv.remove(int(item2.uid))
					if not taken.is_empty():
						f.items.append(taken)
						p.rebuild()})
	opts.append({"text": "Закрыть", "cb": func(): pass})
	world.ui.open("dialog", {"title": fb.get("name", "Стойка"), "text": "Выставлено %d / %d." % [f.items.size(), cap], "options": opts})

# ------------------------------------------------------------------ placement mode
func start_placing(bid: String, it: Dictionary) -> void:
	cancel_placing()
	var b = building(bid)
	if b == null:
		return
	var ghost := Node3D.new()
	ghost.add_child(FurnitureLib.build(str(ItemDB.base(it.base).get("furniture", "chest")), Profile.current_era, []))
	b.add_child(ghost)
	for mi in ghost.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).transparency = 0.45
	var bar := PlacementBar.new()
	bar.housing = self
	bar.title = ItemDB.display_name(it)
	world.hud.add_child(bar)
	placing = {"bid": bid, "item": it, "ghost": ghost, "bar": bar, "rot": 0.0, "why": ""}
	set_physics_process(true)

func _physics_process(_dt: float) -> void:
	if placing.is_empty():
		return
	var b = building(placing.bid)
	var g: Node3D = placing.ghost
	if b == null or not is_instance_valid(g):
		cancel_placing()
		return
	var pl = world.player
	var wp: Vector3 = pl.global_position + pl.facing * 1.4
	var local: Vector3 = b.to_local(wp)
	local.y = 0.0
	local.x = snappedf(local.x, 0.25)
	local.z = snappedf(local.z, 0.25)
	g.position = local
	g.rotation.y = float(placing.rot)
	var why := can_place(b, local)
	placing.why = why
	placing.local = local
	var c := Color(0.4, 1.0, 0.5) if why == "" else Color(1.0, 0.35, 0.3)
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _ghost_mat(c)
	if is_instance_valid(placing.bar):
		placing.bar.set_status(why)

var _gm := {}
func _ghost_mat(c: Color) -> StandardMaterial3D:
	var k := c.to_html()
	if not _gm.has(k):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gm[k] = m
	return _gm[k]

func rotate_placing() -> void:
	if not placing.is_empty():
		placing.rot = fposmod(float(placing.rot) + PI * 0.5, TAU)

func confirm_placing() -> String:
	if placing.is_empty():
		return "нет"
	var why := place(placing.bid, placing.item, placing.get("local", Vector3.ZERO), float(placing.rot))
	if why != "":
		Events.notify.emit("Нельзя поставить: " + why, Color(1.0, 0.5, 0.4))
		return why
	Events.notify.emit("Поставлено: " + ItemDB.display_name(placing.item), Color(0.6, 1.0, 0.7))
	cancel_placing()
	return ""

func cancel_placing() -> void:
	if placing.is_empty():
		return
	if is_instance_valid(placing.ghost):
		placing.ghost.queue_free()
	if is_instance_valid(placing.bar):
		placing.bar.queue_free()
	placing = {}

# ================================================================== props
## Sign, nameplate, built-in bed/chest and placed furniture: one interactable.
class HomeProp extends Node3D:
	var housing
	var kind := "furniture"
	var bid := ""
	var sid := ""
	var entry := {}
	var interact_radius := 2.0
	var _vis: Node3D

	func _ready() -> void:
		Game.grid.insert_deferred(self, "interact")
		rebuild()

	func _exit_tree() -> void:
		Game.grid.remove(self, "interact")

	func rebuild() -> void:
		if _vis and is_instance_valid(_vis):
			_vis.queue_free()
		var era := Profile.current_era
		match kind:
			"sign", "plate":
				_vis = FurnitureLib.sign(era, kind == "sign")
				interact_radius = 2.4
			"bed_builtin":
				_vis = Node3D.new()          # the house's own bed mesh is part of the building
				interact_radius = 1.8
			"chest_builtin":
				_vis = FurnitureLib.build("chest", era, [])
				interact_radius = 1.6
			_:
				var fb := ItemDB.base(str(entry.get("base", "")))
				_vis = FurnitureLib.build(str(fb.get("furniture", "chest")), era, entry.get("items", []), int(fb.get("heal_tier", 1)))
				interact_radius = 1.8
		add_child(_vis)

	func can_interact(_a) -> bool:
		return true

	func interact_label() -> String:
		match kind:
			"sign":
				return "Дом продаётся"
			"plate":
				return "Мой дом"
			"bed_builtin":
				return "Спать до утра"
			"chest_builtin":
				return "Личный сундук"
		var fb := ItemDB.base(str(entry.get("base", "")))
		match str(fb.get("furniture", "")):
			"bed":
				return "Спать до утра"
			"chest":
				return "Личный сундук"
			"wardrobe":
				return "Гардероб"
			"hearth":
				return "Погреться у огня"
			"alchemy":
				return "Алхимический стол"
			"workbench":
				return "Верстак"
			"map":
				return "Карта мира"
			"med_station":
				return "Медицинская станция" if int(fb.get("heal_tier", 1)) < 3 else "Медицинская капсула"
			"weapon_rack":
				return "Оружейная стойка"
			"display":
				return "Витрина"
		return str(fb.get("name", "Мебель"))

	func interact(_a) -> void:
		if housing:
			housing.use_prop(self)

## On-screen bar of the placement mode (the game keeps running so the hero
## can walk the ghost to its place).
class PlacementBar extends Control:
	var housing
	var title := ""
	var _st: Label

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_CENTER_TOP)
		position = Vector2(-330, 92)
		var p := UITheme.panel(Color(0.05, 0.05, 0.08, 0.85), UITheme.GOLD_DIM, 12, 10)
		add_child(p)
		var vb := VBoxContainer.new()
		p.add_child(vb)
		vb.add_child(UITheme.label("Расстановка: " + title, 18, UITheme.GOLD, "bold"))
		_st = UITheme.label("", 15, UITheme.TEXT_DIM)
		vb.add_child(_st)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		row.add_child(UITheme.button("Повернуть", func(): housing.rotate_placing(), 52, 150))
		row.add_child(UITheme.button("Поставить", func(): housing.confirm_placing(), 52, 160))
		row.add_child(UITheme.button("Отмена", func(): housing.cancel_placing(), 52, 130))

	func set_status(why: String) -> void:
		if _st:
			_st.text = "Можно ставить" if why == "" else "Нельзя: " + why
			_st.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if why == "" else Color(1.0, 0.55, 0.45))
