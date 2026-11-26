class_name Resonance
extends Node
## Magical Resonance: when two magics of a reactive pair land on the same
## spot within a short window, they react.
##
##   fire + ice          → Паровой взрыв (steam burst + scalding cloud)
##   lightning + space   → Электрический узел (node arcing to nearby foes)
##   dark + fire         → Вихрь тёмного пламени (pulling, burning vortex)
##   time + time         → Временная нестабильность (flickering time field)
##
## Every spell impact, magic projectile, spell zone and projectile collision
## leaves an "imprint" (element, position, power, tier, caster). It works for
## anyone — hero, NPC mages, monsters, bosses — so NPC-vs-NPC battles react
## too. Rules, not visuals:
##  - each side must reach MIN_EACH power and the pair MIN_SUM (tier-weighted:
##    normal ×1, empowered ×1.5, ultimate ×2.5); during a magic storm the
##    threshold drops by a quarter;
##  - an area cool-down (no second reaction within 6 m for 3 s), at most
##    MAX_ACTIVE reaction zones at once, imprints expire after WINDOW s;
##  - two static fields of the same caster never react with each other;
##  - a catastrophe needs CATA_SUM weighted power or a cascade of
##    CASCADE_N reactions within CASCADE_R m / CASCADE_T s, the world map
##    (not a rift) and a long global cool-down. It is run by the World
##    Director (sphere, runes, panic, guards, chronicle, anomaly, rift).

const PAIRS := {
	"fire+ice": "steam", "ice+fire": "steam",
	"lightning+space": "node", "space+lightning": "node",
	"dark+fire": "vortex", "fire+dark": "vortex",
	"time+time": "instability",
}
const NAMES := {"steam": "Паровой взрыв", "node": "Электрический узел", "vortex": "Вихрь тёмного пламени",
	"instability": "Временная нестабильность"}
const TIER_K := {"normal": 1.0, "empowered": 1.5, "ultimate": 2.5}
const WINDOW := 2.6
const RADIUS := 4.0
const MIN_EACH := 8.0
const MIN_SUM := 30.0
const CATA_SUM := 170.0
const AREA_R := 6.0
const AREA_CD := 3.0
const MAX_ACTIVE := 3
const MAX_IMPRINTS := 48
const CASCADE_N := 3
const CASCADE_R := 22.0
const CASCADE_T := 20.0
const CATA_CD := 300.0
## space-school spells (the rest of "spacetime" is time)
const SPACE_SPELLS := ["blink", "riftdash"]
const ZONE_EL := {"fire": "fire", "blizzard": "ice", "electric": "lightning", "dark": "dark",
	"timeslow": "time", "timetrap": "time", "rift": "space"}

static var inst: Resonance = null

var world
var enabled := true
var imprints: Array = []
var recent: Array = []
var active: Array = []
var clock := 0.0
var cata_ready_at := 0.0
var _uid := 0
var stats := {"imprints": 0, "reactions": 0, "catastrophes": 0, "blocked_power": 0, "blocked_cd": 0,
	"blocked_limit": 0, "clashes": 0, "by_kind": {}}
## last reaction (for tests and the debug overlay)
var last := {}

func setup(w) -> void:
	world = w
	inst = self
	cata_ready_at = 45.0

func _exit_tree() -> void:
	if inst == self:
		inst = null

func _process(delta: float) -> void:
	clock += delta
	if Engine.get_process_frames() % 30 == 0:
		_prune()

# ---------------------------------------------------------------- elements
static func element_for_spell(id: String, dtype: String) -> String:
	if id in SPACE_SPELLS:
		return "space"
	return element_for_dtype(dtype)

static func element_for_dtype(dtype: String) -> String:
	match dtype:
		"fire", "ice", "lightning", "dark", "time":
			return dtype
		"space", "rift":
			return "space"
	return ""

static func tier_of(info: Dictionary) -> String:
	var t: String = info.get("tier", "normal")
	return t if TIER_K.has(t) else "normal"

# ---------------------------------------------------------------- hooks
## A spell or magic projectile landed.
static func imprint(el: String, pos: Vector3, power: float, tier: String, owner, radius := 0.0) -> void:
	if inst == null or not inst.enabled or el == "":
		return
	inst._add({"el": el, "pos": pos, "power": maxf(power, 0.0), "tier": tier, "owner": owner, "r": radius, "zone": null})

## A spell zone was created (fire wall, blizzard, time field, rift...).
static func zone_created(z) -> void:
	if inst == null or not inst.enabled or z == null:
		return
	if z.params.get("no_res", false):
		return
	var el: String = ZONE_EL.get(z.kind, "")
	if el == "":
		return
	var p: float = maxf(float(z.info.get("amount", 0.0)) * 2.0, 15.0)
	inst._add({"el": el, "pos": z.global_position, "power": p, "tier": tier_of(z.info), "owner": z.src, "r": z.radius, "zone": z})

## Helper for spells: element from the spell id and its info.
static func from_spell(c, id: String, pos: Vector3, info: Dictionary, radius := 0.0, min_power := 0.0) -> void:
	if inst == null:
		return
	var el := element_for_spell(id, str(info.get("dtype", "")))
	imprint(el, pos, maxf(float(info.get("amount", 0.0)), min_power), tier_of(info), c, radius)

# ---------------------------------------------------------------- core
func _weighted(im: Dictionary) -> float:
	return float(im.power) * float(TIER_K.get(im.tier, 1.0))

func _alive(im: Dictionary) -> bool:
	if im.zone != null:
		return is_instance_valid(im.zone) and not im.zone.is_queued_for_deletion() and clock >= float(im.get("cool", 0.0))
	return clock - float(im.t) <= WINDOW

func _prune() -> void:
	var keep: Array = []
	for im in imprints:
		if im.zone != null:
			if is_instance_valid(im.zone):
				keep.append(im)
		elif clock - float(im.t) <= WINDOW:
			keep.append(im)
	imprints = keep
	var act: Array = []
	for z in active:
		if is_instance_valid(z):
			act.append(z)
	active = act
	var rec: Array = []
	for r in recent:
		if clock - float(r.t) <= CASCADE_T:
			rec.append(r)
	recent = rec

func _add(im: Dictionary) -> void:
	_uid += 1
	im["id"] = _uid
	im["t"] = clock
	stats.imprints += 1
	var best = null
	var best_sum := 0.0
	for o in imprints:
		if not _alive(o):
			continue
		var key: String = o.el + "+" + im.el
		if not PAIRS.has(key):
			continue
		# two static fields of the same caster (e.g. a boss's arena hazards)
		# don't feed on each other; a caster's own field + own spell still can
		if o.zone != null and im.zone != null and o.owner != null and o.owner == im.owner:
			continue
		var reach: float = RADIUS + float(o.r) + float(im.r) * 0.5
		var d := Vector2(o.pos.x - im.pos.x, o.pos.z - im.pos.z).length()
		if d > reach:
			continue
		var sm := _weighted(o) + _weighted(im)
		if sm > best_sum:
			best_sum = sm
			best = o
	if best == null:
		_store(im)
		return
	var kind: String = PAIRS[best.el + "+" + im.el]
	var a_w := _weighted(best)
	var b_w := _weighted(im)
	var k_storm := 0.75 if _magic_storm() else 1.0
	if minf(a_w, b_w) < MIN_EACH * k_storm or best_sum < MIN_SUM * k_storm:
		stats.blocked_power += 1
		_store(im)
		return
	var mid: Vector3 = (best.pos + im.pos) * 0.5
	if best.zone != null and is_instance_valid(best.zone):
		mid = im.pos if im.zone == null else (best.pos + im.pos) * 0.5
	for r in recent:
		if clock - float(r.t) < AREA_CD and Vector2(r.pos.x - mid.x, r.pos.z - mid.z).length() < AREA_R:
			stats.blocked_cd += 1
			_store(im)
			return
	_prune()
	if active.size() >= MAX_ACTIVE:
		stats.blocked_limit += 1
		_store(im)
		return
	# the older imprint is spent; a zone partner stays but rests for a while
	if best.zone != null:
		best["cool"] = clock + AREA_CD + 1.0
		if kind == "steam" and is_instance_valid(best.zone):
			best.zone.life = minf(best.zone.life, 0.6)      # fire and ice cancel out
	else:
		imprints.erase(best)
	if im.zone != null:
		im["cool"] = clock + AREA_CD + 1.0
		_store(im)
	var owner = im.owner if (im.owner != null and is_instance_valid(im.owner)) else (best.owner if (best.owner != null and is_instance_valid(best.owner)) else null)
	_react(kind, mid, best_sum, [best, im], owner)

func _store(im: Dictionary) -> void:
	imprints.append(im)
	if imprints.size() > MAX_IMPRINTS:
		imprints.pop_front()

func _magic_storm() -> bool:
	if world == null or world.get("director") == null:
		return false
	return float(world.director.mods.get("spell", 1.0)) > 1.0

# ---------------------------------------------------------------- reactions
func _react(kind: String, pos: Vector3, power: float, src: Array, owner) -> void:
	pos.y = world.ground_height(pos) if world and world.has_method("ground_height") else pos.y
	stats.reactions += 1
	stats.by_kind[kind] = int(stats.by_kind.get(kind, 0)) + 1
	var r := clampf(3.0 + power / 45.0, 3.0, 7.0)
	var amount := clampf(power * 0.42, 10.0, 220.0)
	var tiers: Array = [src[0].tier, src[1].tier]
	last = {"kind": kind, "pos": pos, "power": power, "radius": r, "tiers": tiers, "t": clock,
		"els": [src[0].el, src[1].el], "owner": owner}
	recent.append({"pos": pos, "t": clock, "kind": kind})
	ResonanceFX.reaction_burst(kind, pos, r)
	Audio.play_sfx("resonance_hum", pos, -6.0)
	var z: Zone = null
	match kind:
		"steam":
			Audio.play_sfx("steam_burst", pos)
			Combat.aoe(owner, pos + Vector3(0, 0.5, 0), r, {"amount": amount, "dtype": "fire", "knock": 2.4, "status": {"slow": 0.4}, "melee": false, "proc": true}, false)
			for a in Game.actors_near(pos, r + 0.5):
				if is_instance_valid(a) and not a.is_dead:
					a.statuses.erase("burn")
					a.statuses.erase("freeze")
			z = Zone.create("steam", owner, pos, r * 0.9, 5.0, {"amount": 0.0, "dtype": "fire"}, {"no_res": true})
		"node":
			Audio.play_sfx("thunder", pos, -4.0)
			Audio.play_sfx("elec_crackle", pos)
			z = Zone.create("node", owner, pos, 4.0 + r * 0.3, 6.0, {"amount": amount * 0.16, "dtype": "lightning", "status": {"stun": 0.25}}, {"no_res": true, "arcs": 2 if power < 120.0 else 3, "reach": 7.0 + r * 0.4})
			if z:
				z.tick = 0.5
		"vortex":
			Audio.play_sfx("dark_hum", pos)
			Audio.play_sfx("fire_cast", pos, -3.0)
			z = Zone.create("vortex", owner, pos, r, 5.0, {"amount": amount * 0.08, "dtype": "dark", "status": {"burn": amount * 0.05}}, {"no_res": true, "pull": 3.5 + power / 80.0})
			if z:
				z.tick = 0.35
		"instability":
			Audio.play_sfx("time_warp", pos)
			z = Zone.create("instability", owner, pos, r, 6.0, {"amount": amount * 0.05, "dtype": "time"}, {"no_res": true})
			if z:
				z.tick = 0.5
	if z:
		active.append(z)
	Events.notify.emit("Резонанс: " + NAMES.get(kind, kind), ResonanceFX.color(kind))
	if Events.has_signal("resonance"):
		Events.emit_signal("resonance", last)
	_check_catastrophe(kind, pos, power, src, owner)

func _check_catastrophe(kind: String, pos: Vector3, power: float, src: Array, owner) -> void:
	var near := 0
	for rr in recent:
		if Vector2(rr.pos.x - pos.x, rr.pos.z - pos.z).length() < CASCADE_R:
			near += 1
	var trigger := ""
	var k_time := 0.8 if kind == "instability" else 1.0     # time folding on itself tears easier
	if power >= CATA_SUM * k_time:
		trigger = "power"
	elif near >= CASCADE_N:
		trigger = "cascade"
	if trigger == "":
		return
	if clock < cata_ready_at:
		return
	if world == null or world.get("dimension") != "" or Game.mode != "world":
		return
	if world.get("director") == null or not world.director.has_method("resonance_catastrophe"):
		return
	cata_ready_at = clock + CATA_CD
	stats.catastrophes += 1
	var owners: Array = []
	for s in src:
		if s.owner != null and is_instance_valid(s.owner) and not s.owner in owners:
			owners.append(s.owner)
	world.director.resonance_catastrophe(pos, kind, power, owners, trigger)

## Two magic projectiles met in the air (called by Projectile).
func projectile_meet(a, b) -> void:
	var ea := element_for_dtype(str(a.info.get("dtype", "")))
	var eb := element_for_dtype(str(b.info.get("dtype", "")))
	var pos: Vector3 = (a.global_position + b.global_position) * 0.5
	stats.clashes += 1
	ResonanceFX.projectile_clash(pos, a.color, b.color)
	Audio.play_sfx("impact_heavy", pos, -4.0)
	var pa := float(a.info.get("amount", 10.0))
	var pb := float(b.info.get("amount", 10.0))
	a.dead_by_clash = true
	b.dead_by_clash = true
	a._end(pos, false)
	b._end(pos, false)
	if PAIRS.has(ea + "+" + eb):
		imprint(ea, pos, pa, tier_of(a.info), a.src)
		imprint(eb, pos, pb, tier_of(b.info), b.src)

## Test / scenario helper: forget cool-downs and imprints.
func reset() -> void:
	imprints.clear()
	recent.clear()
	cata_ready_at = 0.0
