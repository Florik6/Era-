class_name CityMagic
## Rules for magic among people:
## • destructive magic is not cast on a peaceful square — NPC casters refuse,
##   the hero is warned once, then the town guard answers (only guards nearby,
##   with expiring aggro: no endless chains of fights);
## • necromancy alarms factions that hold it forbidden (knightly orders,
##   royal guards, the military): reputation drops, a repeat brings the guard;
## • while a town is under real attack (alarm / attack state) the defenders'
##   magic is allowed against the attackers.

const FORBID_STYLES := ["knight", "guard", "military", "order", "police"]
const WARN_MS := 25000
const NECRO_MS := 60000
static var stats := {"warnings": 0, "guard_calls": 0, "necro_alarms": 0, "necro_guard_calls": 0, "npc_refused": 0}
static var _warned := {}       # actor_id -> msec of the last warning
static var _necro := {}        # actor_id -> msec of the last necromancy seen by a forbidding faction

## Spell that would wreck a market: damaging areas, terrain and cataclysms.
static func destructive(e: Dictionary) -> bool:
	if e.get("kind", "") != "spell":
		return false
	if int(e.get("tier", 0)) >= 6 and e.get("school", "") != "heal":
		return true
	if float(e.get("dmg", 0.0)) <= 0.0:
		for f in e.fx:
			if f.c == "terrain":
				return true
		return false
	for f in e.fx:
		if f.c in ["blast", "zone", "nova", "wave", "fissures", "terrain", "cataclysm"]:
			return true
	return false

static func _town(p: Vector3):
	if CityPeace.inst == null:
		return null
	return CityPeace.inst.city_at(p, 6.0)

static func _peaceful(c) -> bool:
	return c != null and CityPeace.inst.is_peaceful_state(str(c.state))

static func town_owner_style(c) -> String:
	if c == null or Game.world == null or Game.world.get("factions") == null or Game.world.factions == null:
		return ""
	var fid: String = Game.world.factions.settlement_owner(str(c.get("id", "")))
	if fid == "":
		return ""
	return str(DBEras.faction(fid).get("style", ""))

## NPC casters ask before casting.
static func allowed(a: Actor, e: Dictionary, pos: Vector3) -> bool:
	if a == null or a.is_player:
		return true
	var c = _town(pos)
	if c == null:
		c = _town(a.global_position)
	if c == null:
		return true
	if destructive(e) and _peaceful(c):
		stats.npc_refused += 1
		return false
	if e.get("school", "") == "necro" and town_owner_style(c) in FORBID_STYLES and not CityPeace.hostile_kind(a):
		stats.npc_refused += 1
		return false
	return true

static func on_cast(a: Actor, e: Dictionary, pos: Vector3) -> void:
	if a == null or not a.is_player or not destructive(e):
		return
	var c = _town(pos)
	if c == null:
		c = _town(a.global_position)
	if not _peaceful(c):
		return
	var now := Time.get_ticks_msec()
	var last := int(_warned.get(a.actor_id, -999999))
	if now - last > WARN_MS and int(e.get("tier", 0)) < 6:
		_warned[a.actor_id] = now
		stats.warnings += 1
		Events.notify.emit("Стража: разрушительная магия в городе запрещена!", Color(1.0, 0.7, 0.4))
		return
	_warned[a.actor_id] = now
	stats.guard_calls += 1
	CityPeace.inst.offenders[a.actor_id] = now + int(CityPeace.OFFENDER_S * 1000.0)
	CityPeace.inst._guards_on(a, c)
	Events.notify.emit("Стража идёт за вами: магия разрушения на мирной улице.", Color(1.0, 0.5, 0.35))

static func on_area(a: Actor, e: Dictionary, pos: Vector3, _r: float) -> void:
	pass   # areas are judged at cast time (on_cast); kept for future per-zone rules

static func on_necromancy(a: Actor, pos: Vector3) -> void:
	if a == null:
		return
	var c = _town(pos)
	var style := town_owner_style(c)
	var witnesses: Array = []
	for t in Game.actors_near(pos, 26.0):
		if t == a or t.is_dead or t.data == null:
			continue
		if str(t.get("role")) == "guard" or t.team == "soldier":
			witnesses.append(t)
	if style not in FORBID_STYLES and witnesses.is_empty():
		return
	if style not in FORBID_STYLES:
		# only soldiers of forbidding factions care
		witnesses = witnesses.filter(func(w): return str(DBEras.faction(str(w.faction_id)).get("style", "")) in FORBID_STYLES)
		if witnesses.is_empty():
			return
	stats.necro_alarms += 1
	var now := Time.get_ticks_msec()
	var repeat := now - int(_necro.get(a.actor_id, -999999)) < NECRO_MS
	_necro[a.actor_id] = now
	if a.is_player and Game.world and Game.world.get("factions") != null and Game.world.factions != null and c != null:
		var fid: String = Game.world.factions.settlement_owner(str(c.get("id", "")))
		if fid != "":
			Game.world.factions.add_rep(fid, -8.0, "некромантия")
	# raised dead are attacked by the witnesses (they are abominations here)
	for s in AbilityExec.live_summons(a):
		for w in witnesses:
			w.add_aggro(s, 20.0)
	if repeat and c != null and CityPeace.inst != null:
		stats.necro_guard_calls += 1
		CityPeace.inst.offenders[a.actor_id] = now + int(CityPeace.OFFENDER_S * 1000.0)
		CityPeace.inst._guards_on(a, c)
		if a.is_player:
			Events.notify.emit("Некромантия здесь запрещена — стража атакует!", Color(1.0, 0.45, 0.4))
	elif a.is_player:
		Events.notify.emit("Здесь некромантию считают преступлением. Повторите — и стража вмешается.", Color(1.0, 0.7, 0.45))

static func reset() -> void:
	_warned.clear()
	_necro.clear()
	for k in stats:
		stats[k] = 0
