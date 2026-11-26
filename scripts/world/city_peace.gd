class_name CityPeace
extends Node
## City Peace System: every settlement has a safety state, and by default it
## is peaceful. The state only changes for a real reason:
##   peaceful → tense      a crime, a brawl broken up by the guard, a rumour
##   tense/peaceful → alarm  a hostile creature or raider inside the town
##   → attack              a real raid / siege event (rare, see can_raid)
##   attack → recovery     the attackers are gone or the event ended
##   recovery → normalizing → peaceful   by game time
## Inside a town in a peaceful-ish state a truce holds between everyone who
## is not a monster, raider or boss: faction wars and "contender" rivalries
## are not fought on the market square (they belong to roads, forts and
## contested land). Real attacks still matter: whoever attacks a townsperson
## becomes an offender and the guard deals with him; the player gets one
## warning first.
## Raids: at most one at a time per town, at least RAID_MIN_DAYS game days
## apart, never during recovery.

const STATES := ["peaceful", "tense", "alarm", "attack", "recovery", "normalizing"]
const STATE_NAMES := {"peaceful": "Мирно", "tense": "Напряжённо", "alarm": "Тревога", "attack": "Нападение",
	"recovery": "Восстановление", "normalizing": "Нормализация"}
const MARGIN := 22.0             # m beyond the settlement radius that still counts as town
const RAID_MIN_DAYS := 3.0       # game days between large attacks on one town
const RECOVERY_DAYS := 0.25      # 6 game hours
const NORMALIZE_DAYS := 0.12
const TENSE_DAYS := 0.08
const OFFENDER_S := 60.0         # real seconds an offender stays wanted
const HOSTILE_TEAMS := ["monster", "bandit", "boss"]

static var inst: CityPeace = null

var world
var cities := {}                 # sid -> {id, name, pos, r, type, state, since, last_raid, reason}
var offenders := {}              # actor_id -> expiry (msec)
var warned := {}                 # actor_id -> msec of last warning (player)
var stats := {"crimes": 0, "warnings": 0, "guard_responses": 0, "squabbles": 0, "squabbles_resolved": 0,
	"raids_started": 0, "raids_refused": 0, "transitions": 0, "spawns_blocked": 0, "truce_blocks": 0}
var log: Array = []              # recent transitions (for tests / journal)
var _t := 0.0
var _sq_t := 40.0
var _squabble := {}

func setup(w) -> void:
	world = w
	inst = self
	var saved: Dictionary = Game.world_state.get("city_peace", {})
	for s in w.gen.settlements:
		var sv: Dictionary = saved.get(s.id, {})
		cities[s.id] = {"id": s.id, "name": s.get("name", ""), "pos": Vector3(s.pos.x, 0, s.pos.y), "r": float(s.get("radius", 40.0)),
			"type": s.get("type", "village"), "state": sv.get("state", "peaceful"), "since": float(sv.get("since", Game.game_time)),
			"last_raid": float(sv.get("last_raid", -99.0)), "reason": sv.get("reason", "")}
		if cities[s.id].state in ["attack", "alarm"]:
			cities[s.id].state = "recovery"       # a save never resumes mid-fight
	Events.actor_damaged.connect(_on_damaged)
	Events.world_event_ended.connect(_on_event_ended)

func _exit_tree() -> void:
	if inst == self:
		inst = null

func save_state() -> void:
	var out := {}
	for sid in cities:
		var c: Dictionary = cities[sid]
		out[sid] = {"state": c.state, "since": c.since, "last_raid": c.last_raid, "reason": c.reason}
	Game.world_state.city_peace = out

# ---------------------------------------------------------------- queries
func city_at(p: Vector3, margin: float = MARGIN):
	var best = null
	var bd := INF
	for sid in cities:
		var c: Dictionary = cities[sid]
		var d := Vector2(c.pos.x - p.x, c.pos.z - p.z).length()
		if d < c.r + margin and d < bd:
			bd = d
			best = c
	return best

func state_of(sid: String) -> String:
	return cities.get(sid, {}).get("state", "peaceful")

func is_peaceful_state(st: String) -> bool:
	return st in ["peaceful", "tense", "recovery", "normalizing"]

## True inside a town whose state keeps the truce (not alarm/attack).
func in_peace_zone(p: Vector3, margin: float = MARGIN) -> bool:
	var c = city_at(p, margin)
	return c != null and is_peaceful_state(c.state)

static func hostile_kind(a) -> bool:
	if a == null or not is_instance_valid(a):
		return false
	return a.team in HOSTILE_TEAMS or a.get("hunting_player") == true

func is_offender(a) -> bool:
	return a != null and is_instance_valid(a) and int(offenders.get(a.actor_id, 0)) > Time.get_ticks_msec()

## The town truce: two non-hostile actors inside a peaceful town are not
## enemies unless one of them is a wanted offender or the other has a fresh
## personal grudge from a real attack (handled by the caller via aggro).
func truce(a, b) -> bool:
	if a == null or b == null:
		return false
	if hostile_kind(a) or hostile_kind(b):
		return false
	if a.is_player or b.is_player:
		return false
	if is_offender(a) or is_offender(b):
		return false
	# the truce holds during alarms (a stray beast) too; only a real attack on
	# the town (raid / siege) lifts it
	var ca = city_at(a.global_position)
	var cb = city_at(b.global_position)
	if ca == null or cb == null or ca.state == "attack" or cb.state == "attack":
		return false
	# an organised battle event (faction war) is allowed where it was started
	if a.get("squad") is Dictionary and not a.squad.is_empty() and b.get("squad") is Dictionary and not b.squad.is_empty():
		return false
	stats.truce_blocks += 1
	return true

## Large attacks: one at a time per town, far apart, never during recovery.
func can_raid(sid: String, allow_reason := "") -> bool:
	var c: Dictionary = cities.get(sid, {})
	if c.is_empty():
		return true
	var ok: bool = c.state in ["peaceful", "tense", "normalizing"] and Game.game_time - float(c.last_raid) >= RAID_MIN_DAYS
	if not ok:
		stats.raids_refused += 1
	return ok

func begin_attack(sid: String, reason: String) -> void:
	var c: Dictionary = cities.get(sid, {})
	if c.is_empty():
		return
	c.last_raid = Game.game_time
	stats.raids_started += 1
	_set_state(c, "attack", reason)
	# townsfolk take cover, guards gather
	for a in Game.actors_near(c.pos, c.r + MARGIN):
		if a.is_dead or a.get("brain") == null:
			continue
		var role := str(a.get("role"))
		if role in ["villager", "trader"] and a.brain.has_method("flee_from"):
			a.brain.flee_from(c.pos + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), 12.0)
			a.set_meta("sheltering", true)
		elif role == "guard" and a.brain.has_method("investigate"):
			a.brain.investigate(c.pos)

func end_attack(sid: String, outcome: String) -> void:
	var c: Dictionary = cities.get(sid, {})
	if c.is_empty() or c.state != "attack":
		return
	_set_state(c, "recovery", outcome)
	Chronicle.record("city_recovery", [], {"pos_v3": c.pos, "place": c.name, "extra": {"outcome": outcome}})

func _set_state(c: Dictionary, st: String, reason: String) -> void:
	if c.state == st:
		return
	log.append({"sid": c.id, "from": c.state, "to": st, "t": Game.game_time, "reason": reason})
	if log.size() > 60:
		log.pop_front()
	c.state = st
	c.since = Game.game_time
	c.reason = reason
	stats.transitions += 1

# ---------------------------------------------------------------- crimes & threats
func _on_damaged(t, amount: float, src, _dt: String) -> void:
	if src == null or t == null or not is_instance_valid(src) or not is_instance_valid(t) or amount <= 0.0:
		return
	var c = city_at(t.global_position)
	if c == null:
		return
	if src.has_meta("spar") and t.has_meta("spar"):
		return      # a sanctioned bout (tournament, training): not a crime
	if hostile_kind(src):
		# a monster or raider is hurting people in town
		if c.state in ["peaceful", "tense", "normalizing", "recovery"]:
			_set_state(c, "alarm", "угроза: %s" % src.display_name)
		_guards_on(src, c)
		return
	var victim_civil: bool = str(t.get("role")) in ["villager", "trader", "guard"] or (t.get("settlement_id") != null and str(t.settlement_id) != "")
	if not victim_civil or hostile_kind(t):
		return
	if src.is_player:
		var now := Time.get_ticks_msec()
		if now - int(warned.get("player", -999999)) > 20000:
			warned["player"] = now
			stats.warnings += 1
			_shout(t, "Стража! Опусти оружие!")
			Events.notify.emit("Стража предупреждает: нападение на жителей карается.", Color(1.0, 0.7, 0.4))
			return
	stats.crimes += 1
	offenders[src.actor_id] = Time.get_ticks_msec() + int(OFFENDER_S * 1000.0)
	if c.state == "peaceful" or c.state == "normalizing":
		_set_state(c, "tense", "нападение на жителя")
	_guards_on(src, c)

func _guards_on(culprit, c: Dictionary) -> void:
	var n := 0
	for g in Game.actors_near(culprit.global_position, 38.0):
		if g.is_dead or str(g.get("role")) != "guard" or g == culprit:
			continue
		g.add_aggro(culprit, 30.0)
		n += 1
	if n > 0:
		stats.guard_responses += 1

func _shout(a, txt: String) -> void:
	VFX.text(a.global_position + Vector3(0, 2.4, 0), txt, Color(1.0, 0.8, 0.5), 0.9)

func _on_event_ended(e: Dictionary) -> void:
	if e.get("type", "") in ["raid", "battle", "town_attack"]:
		var sid: String = e.get("data", {}).get("sid", e.get("data", {}).get("target", ""))
		if cities.has(sid):
			end_attack(sid, "угроза устранена")

# ---------------------------------------------------------------- tick
func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	var now := Time.get_ticks_msec()
	for id in offenders.keys():
		if int(offenders[id]) < now:
			offenders.erase(id)
	var pp: Vector3 = world.player.global_position
	for sid in cities:
		var c: Dictionary = cities[sid]
		var age: float = Game.game_time - float(c.since)
		match c.state:
			"alarm":
				if Vector2(c.pos.x - pp.x, c.pos.z - pp.z).length() < 260.0:
					if _hostiles_in(c) == 0:
						_set_state(c, "tense", "угроза устранена")
				elif age > 0.05:
					_set_state(c, "tense", "угроза ушла")
			"attack":
				if age > 0.3 and _hostiles_in(c) == 0:
					end_attack(sid, "нападающих не осталось")
			"recovery":
				_recovery_tick(c)
				if age >= RECOVERY_DAYS:
					_set_state(c, "normalizing", "город приходит в себя")
			"normalizing":
				if age >= NORMALIZE_DAYS:
					_set_state(c, "peaceful", "обычная жизнь")
			"tense":
				if age >= TENSE_DAYS:
					_set_state(c, "peaceful", "всё спокойно")
	_squabble_tick(delta)

func _hostiles_in(c: Dictionary) -> int:
	var n := 0
	for a in Game.actors_near(c.pos, c.r + MARGIN):
		if not a.is_dead and hostile_kind(a):
			n += 1
	return n

## Recovery: wounded townsfolk are tended, people come out of cover, guards
## sweep the streets (only for towns near the hero; the rest is abstract).
func _recovery_tick(c: Dictionary) -> void:
	if world.player.global_position.distance_to(c.pos) > 200.0:
		return
	for a in Game.actors_near(c.pos, c.r + MARGIN):
		if a.is_dead or a.get("brain") == null:
			continue
		var role := str(a.get("role"))
		if role in ["villager", "trader", "guard"] and a.hp < a.max_hp:
			a.heal(a.max_hp * 0.02)
		if a.has_meta("sheltering"):
			a.remove_meta("sheltering")
			a.brain.flee_pos = Vector3.INF
			if a.brain.goal == "flee":
				a.brain.goal = "idle"
		# offenders and leftover grudges between townsfolk are dropped
		if role in ["villager", "trader", "guard"]:
			for k in a.aggro.keys():
				var o = _actor_by_id(k)
				if o == null or not hostile_kind(o):
					a.aggro.erase(k)

func _actor_by_id(id: String):
	for a in Game.actors:
		if is_instance_valid(a) and a.actor_id == id:
			return a
	return null

# ---------------------------------------------------------------- squabbles
## Small peaceful incident: two townsfolk argue, the guard comes over and
## they go their ways. Never turns into a fight on its own.
func _squabble_tick(delta: float) -> void:
	if not _squabble.is_empty():
		_squabble.t += 1.0
		var a = _squabble.a
		var b = _squabble.b
		var g = _squabble.get("g")
		if not is_instance_valid(a) or not is_instance_valid(b) or a.is_dead or b.is_dead:
			_squabble = {}
			return
		for x in [a, b]:
			var o = b if x == a else a
			x.move_input = Vector3.ZERO
			x.face_dir((o.global_position - x.global_position).normalized())
			x.brain.think_t = 2.0
		if int(_squabble.t) % 2 == 0:
			_shout(a if int(_squabble.t) % 4 == 0 else b, ["Это моё место!", "Ты обсчитал меня!", "Не смей!", "Сам такой!"][randi() % 4])
		if g != null and is_instance_valid(g) and g.global_position.distance_to(a.global_position) < 11.0 and not _squabble.get("told", false):
			_squabble.told = true
			_shout(g, "Разойдитесь! Без драк в городе.")
		if _squabble.t >= 9.0:
			stats.squabbles_resolved += 1
			for x in [a, b]:
				x.brain.think_t = 0.0
				x.brain.goal = "idle"
			_squabble = {}
		return
	_sq_t -= delta * 1.0
	if _sq_t > 0.0:
		return
	_sq_t = randf_range(90.0, 180.0)
	var c = city_at(world.player.global_position, 0.0)
	if c == null or c.state != "peaceful":
		return
	var folk: Array = []
	var guard = null
	for a in Game.actors_near(world.player.global_position, 30.0):
		if a.is_dead or a.get("brain") == null:
			continue
		var role := str(a.get("role"))
		if role == "villager" and a.brain.goal != "flee":
			folk.append(a)
		elif role == "guard" and guard == null:
			guard = a
	if folk.size() < 2:
		return
	var a2 = folk[0]
	var b2 = folk[1]
	stats.squabbles += 1
	_squabble = {"a": a2, "b": b2, "g": guard, "t": 0.0}
	var mid: Vector3 = (a2.global_position + b2.global_position) * 0.5
	if guard and guard.brain.has_method("investigate"):
		guard.brain.investigate(mid, 8.0)
