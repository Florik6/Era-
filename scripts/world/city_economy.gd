class_name CityEconomy
extends Node
## Aggregated town economy (no per-coin simulation): every settlement keeps
## stock levels per category; townsfolk purchases draw them down, daily
## supply and deliveries refill them, events can cut a supply line. Prices
## follow the stock (shortage → dearer, glut → cheaper) and the trade screen
## reads price_mult(). Saved with the world.

const CATS := ["iron", "food", "medicine", "goods", "luxury"]
const BASE := {"iron": 60.0, "food": 100.0, "medicine": 40.0, "goods": 80.0, "luxury": 20.0}
const DAILY := {"iron": 25.0, "food": 60.0, "medicine": 12.0, "goods": 30.0, "luxury": 5.0}

static var inst: CityEconomy = null

var world
var towns := {}            # sid -> {stock: {cat: float}, blocked: {cat: until_day}, sales: int, last_day: float}
var log: Array = []

func setup(w) -> void:
	world = w
	inst = self
	var saved: Dictionary = Game.world_state.get("economy", {})
	for s in w.gen.settlements:
		var sv: Dictionary = saved.get(s.id, {})
		var stock := {}
		for c in CATS:
			stock[c] = float(sv.get("stock", {}).get(c, BASE[c]))
		towns[s.id] = {"stock": stock, "blocked": sv.get("blocked", {}), "sales": int(sv.get("sales", 0)), "last_day": float(sv.get("last_day", Game.game_time))}

func _exit_tree() -> void:
	if inst == self:
		inst = null

func save_state() -> void:
	Game.world_state.economy = towns.duplicate(true)

func stock(sid: String, cat: String) -> float:
	return float(towns.get(sid, {}).get("stock", {}).get(cat, BASE.get(cat, 50.0)))

func price_mult(sid: String, cat: String) -> float:
	var b: float = BASE.get(cat, 50.0)
	var s := stock(sid, cat)
	return clampf(1.0 + (b - s) / b * 0.6, 0.75, 2.2)

func is_short(sid: String, cat: String) -> bool:
	return stock(sid, cat) < float(BASE.get(cat, 50.0)) * 0.35

func sale(sid: String, cat: String, n := 1.0) -> void:
	var t: Dictionary = towns.get(sid, {})
	if t.is_empty():
		return
	t.stock[cat] = maxf(0.0, float(t.stock[cat]) - n)
	t.sales += 1

func deliver(sid: String, cat: String, amount: float, why := "") -> void:
	var t: Dictionary = towns.get(sid, {})
	if t.is_empty():
		return
	t.stock[cat] = minf(float(BASE[cat]) * 2.0, float(t.stock[cat]) + amount)
	t.blocked.erase(cat)
	log.append({"sid": sid, "cat": cat, "amount": amount, "why": why, "t": Game.game_time})

## A supply line is cut (robbed caravan, flood…): stock drops and daily
## supply stops for `days` game days unless someone delivers.
func cut_supply(sid: String, cat: String, days: float, loss: float, why := "") -> void:
	var t: Dictionary = towns.get(sid, {})
	if t.is_empty():
		return
	t.stock[cat] = maxf(0.0, float(t.stock[cat]) - loss)
	t.blocked[cat] = Game.game_time + days
	log.append({"sid": sid, "cat": cat, "amount": -loss, "why": why, "t": Game.game_time})

var _t := 0.0
func _process(delta: float) -> void:
	_t += delta
	if _t < 5.0:
		return
	_t = 0.0
	for sid in towns:
		var t: Dictionary = towns[sid]
		var dt: float = Game.game_time - float(t.last_day)
		if dt <= 0.0:
			t.last_day = Game.game_time
			continue
		t.last_day = Game.game_time
		for c in CATS:
			if float(t.blocked.get(c, -1.0)) > Game.game_time:
				continue
			t.blocked.erase(c)
			# supply drifts the stock back toward its normal level
			var b: float = BASE[c]
			var s: float = t.stock[c]
			if s < b:
				t.stock[c] = minf(b, s + DAILY[c] * dt)
			elif s > b * 1.2:
				t.stock[c] = maxf(b * 1.2, s - DAILY[c] * 0.5 * dt)
