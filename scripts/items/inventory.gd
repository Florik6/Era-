class_name Inventory
extends RefCounted
## Bag + equipment slots. Handles stacking, two-handed rules and bound curses.

const CAPACITY := 40

var items: Array = []
var equip: Dictionary = {}

func is_full() -> bool:
	return items.size() >= CAPACITY

func add(item: Dictionary) -> bool:
	if item.is_empty():
		return false
	var b := ItemDB.base(item.base)
	if b.get("stack", false):
		for it in items:
			if it.base == item.base:
				it.qty = it.get("qty", 1) + item.get("qty", 1)
				return true
	if is_full():
		return false
	items.append(item)
	return true

func find(uid: int) -> Dictionary:
	for it in items:
		if it.uid == uid:
			return it
	for s in equip:
		if equip[s].uid == uid:
			return equip[s]
	return {}

func remove(uid: int) -> Dictionary:
	for i in items.size():
		if items[i].uid == uid:
			var it: Dictionary = items[i]
			items.remove_at(i)
			return it
	return {}

func count(base_id: String) -> int:
	var n := 0
	for it in items:
		if it.base == base_id:
			n += it.get("qty", 1)
	return n

func consume(base_id: String, n: int = 1) -> bool:
	if count(base_id) < n:
		return false
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if it.base != base_id:
			continue
		var take: int = mini(n, it.get("qty", 1))
		it.qty = it.get("qty", 1) - take
		n -= take
		if it.qty <= 0:
			items.remove_at(i)
		if n <= 0:
			return true
	return true

func equipped(slot: String) -> Dictionary:
	return equip.get(slot, {})

func is_bound(slot: String) -> bool:
	var it: Dictionary = equip.get(slot, {})
	return it.get("curse", {}).get("bound", false) and it.get("curse", {}).get("active", false)

## Returns {ok: bool, msg: String, bound: bool}
func equip_item(item: Dictionary) -> Dictionary:
	var b := ItemDB.base(item.base)
	var slot: String = b.get("slot", "")
	if not slot in ItemDB.SLOTS:
		return {"ok": false, "msg": "Этот предмет нельзя надеть."}
	if is_bound(slot):
		return {"ok": false, "msg": "Проклятый предмет не даёт себя снять!"}
	if slot == "main" and b.get("two_h", false) and equip.has("off"):
		if is_bound("off"):
			return {"ok": false, "msg": "Проклятый предмет во второй руке мешает взять двуручное оружие."}
		var off: Dictionary = equip["off"]
		equip.erase("off")
		items.append(off)
	if slot == "off" and equip.has("main") and ItemDB.base(equip.main.base).get("two_h", false):
		if is_bound("main"):
			return {"ok": false, "msg": "Двуручное проклятое оружие нельзя убрать."}
		var mainw: Dictionary = equip["main"]
		equip.erase("main")
		items.append(mainw)
	remove(item.uid)
	if equip.has(slot):
		items.append(equip[slot])
	equip[slot] = item
	var res := {"ok": true, "msg": "", "bound": false}
	var c: Dictionary = item.get("curse", {})
	if c.size() > 0:
		c.hidden = false
		if c.get("bound", false):
			c.active = true
			res.bound = true
			res.msg = "Предмет связан с вами проклятием «%s»!" % ItemDB.CURSES.get(c.id, {}).get("name", "")
	return res

func unequip(slot: String) -> Dictionary:
	if not equip.has(slot):
		return {"ok": false, "msg": ""}
	if is_bound(slot):
		var c: Dictionary = equip[slot].curse
		return {"ok": false, "msg": "Нельзя снять! " + ItemDB.RELEASE_METHODS.get(c.get("release", "purify"), "")}
	if is_full():
		return {"ok": false, "msg": "Инвентарь полон."}
	items.append(equip[slot])
	equip.erase(slot)
	return {"ok": true, "msg": ""}

## Release a bound curse via a specific method. Returns true if something was freed.
func release_curse(method: String, boss_id: String = "") -> Array:
	var freed: Array = []
	for s in equip:
		var c: Dictionary = equip[s].get("curse", {})
		if c.is_empty() or not c.get("bound", false):
			continue
		var ok := false
		if method == "artifact":
			ok = true
		elif method == c.get("release", ""):
			ok = (method != "boss") or c.get("boss_id", "") == boss_id or c.get("boss_id", "") == ""
		if ok:
			equip[s].curse = {}
			equip[s].history.append("Освобождён от проклятия (%s)" % method)
			freed.append(equip[s])
	return freed

func all_equipped() -> Array:
	return equip.values()

func to_dict() -> Dictionary:
	return {"items": items, "equip": equip}

func from_dict(d: Dictionary) -> void:
	items = d.get("items", [])
	equip = d.get("equip", {})
	for it in items:
		_fix(it)
	for s in equip:
		_fix(equip[s])

static func _fix(it: Dictionary) -> void:
	# JSON turns ints into floats; normalise common keys
	for k in ["uid", "rarity", "lvl", "upg", "qty"]:
		if it.has(k):
			it[k] = int(it[k])
	if it.has("living") and it.living.size() > 0:
		it.living.stage = int(it.living.get("stage", 0))
		it.living.xp = int(it.living.get("xp", 0))
