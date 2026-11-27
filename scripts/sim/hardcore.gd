class_name Hardcore
extends Node
## Hardcore Mode: anatomical injuries. Chosen at New game → «Режим сложности»
## (Profile.difficulty == "hardcore"); in the normal mode every hook returns
## at once and nothing changes.
##
##  * 7 body zones. The zone of a hit comes from the combat data — the real
##    hit point of projectiles (closest point of the flight path) and the strike
##    point of melee swings (attacker height, swing kind, side). Without a hit
##    point (boss slams, spells, environment) it is estimated from the attack
##    direction, relative height and the attacker's size — never a blind roll.
##  * 8 injury types with severity 1–3 (лёгкая / средняя / тяжёлая), bleeding,
##    infection risk, worsening and recovery time. Small hits (< ~6 % of HP)
##    are scratches and leave nothing — not every scratch matters.
##  * Bleeding drains HP every second (acute); infection, worsening and
##    recovery advance by GAME time (Game.game_time, 12 real minutes per day).
##  * Injuries change real stats: weapon-arm wounds cut damage and attack speed,
##    off-arm wounds weaken the block, leg wounds slow you, head wounds cost
##    crit and spell power, chest/abdomen wounds cost stamina and max HP;
##    bleeding and infection stop natural regeneration.
##  * Treatment: medicine items (bandages stop bleeding, antiseptics clean and
##    cure infection, splints/medkits stabilise fractures, lunar salt heals
##    magic wounds, biogel regenerates), healers and doctors in towns, home
##    medical stations and future capsules, rest. A plain HP potion heals HP
##    only — it does not touch injuries.
## Injuries live in Profile.char.injuries (saved with the character).

const ZONES := ["head", "chest", "abdomen", "arm_l", "arm_r", "leg_l", "leg_r"]
const ZONE_NAMES := {"head": "Голова", "chest": "Грудная клетка", "abdomen": "Живот", "arm_l": "Левая рука",
	"arm_r": "Правая рука", "leg_l": "Левая нога", "leg_r": "Правая нога"}
const TYPE_NAMES := {"cut": "Порез", "stab": "Колотая рана", "bruise": "Ушиб", "burn": "Ожог", "frost": "Обморожение",
	"shock": "Электрическая травма", "fracture": "Перелом", "magic": "Магическое повреждение"}
const SEV_NAMES := ["нет", "лёгкая", "средняя", "тяжёлая"]
const ZONE_VULN := {"head": 1.35, "chest": 1.1, "abdomen": 1.2, "arm_l": 0.8, "arm_r": 0.8, "leg_l": 0.9, "leg_r": 0.9}
const ZONE_SLOT := {"head": "head", "chest": "body", "abdomen": "body", "arm_l": "hands", "arm_r": "hands", "leg_l": "legs", "leg_r": "legs"}
const HEAL_DAYS := [0.0, 0.3, 1.2, 3.0]        # natural recovery of one severity step, game days
const INFECT_DAYS := [0.0, 0.0, 0.6, 0.35]     # untreated open wound → infection
const WORSEN_DAYS := 0.5                       # an infected wound worsens one step
const BLEED_RATE := [0.0, 0.0012, 0.0035, 0.008]   # share of max HP lost per second
const BLEED_FLOOR := [0.0, 0.4, 0.12, 0.0]     # light/medium bleeding never takes HP below this share
const CLOT_DAYS := 0.04                        # light bleeding stops by itself (~30 s)
const SCRATCH := 0.3                           # severity score below this leaves no injury
const MAX_INJURIES := 14
const MAGIC_TYPES := ["dark", "time", "holy", "arcane", "void", "magic", "poison", "light", "blood"]

static var inst: Hardcore = null

var world
var _acc := 0.0
var _bleed_acc := 0.0
var _drip_t := 0.0
var _last_gt := -1.0
var _rest_mult := 1.0
var _next_id := 1
var stats := {"hits": 0, "scratches": 0, "injuries": 0, "by_zone": {}, "by_how": {}, "treated": 0, "infections": 0,
	"worsened": 0, "healed": 0, "bled": 0.0}
var last_hit := {}                             # last zone decision (for tests / feedback)

func setup(w) -> void:
	world = w
	inst = self
	for inj in list():
		_next_id = maxi(_next_id, int(inj.get("id", 0)) + 1)
	Events.player_died.connect(_on_player_died)

func _exit_tree() -> void:
	if inst == self:
		inst = null

func enabled() -> bool:
	return Profile.difficulty == "hardcore"

static func active() -> bool:
	return inst != null and inst.enabled()

func list() -> Array:
	if Profile.char.get("injuries") == null:
		return []
	return Profile.char.injuries

func _player():
	return world.player if world else null

# ------------------------------------------------------------------ hits
## Called by Actor.take_damage for the player after the damage is applied.
func on_hit(a, dealt: float, info: Dictionary, src, from_dir: Vector3) -> void:
	if not enabled() or a == null or not a.is_player or dealt <= 0.0 or a.is_dead:
		return
	stats.hits += 1
	var dtype: String = str(info.get("dtype", "slash"))
	var z := zone_of(a, info, src, from_dir)
	last_hit = z
	stats.by_how[z.how] = int(stats.by_how.get(z.how, 0)) + 1
	var zone: String = z.zone
	var score := dealt / maxf(1.0, a.max_hp) * float(ZONE_VULN[zone]) * 5.0
	if not a.data.inv.equipped(ZONE_SLOT[zone]).is_empty():
		score *= 0.8 if dtype in Combat.PHYSICAL else 0.9
	if info.get("crit", false):
		score *= 1.25
	if info.get("finisher", false) or float(info.get("knock", 0.0)) >= 6.0:
		score *= 1.3
	if score < SCRATCH:
		stats.scratches += 1
		return
	var sev := 1 if score < 0.8 else (2 if score < 1.6 else 3)
	var type := _type_for(dtype, info, src, zone, score)
	add_injury(zone, type, sev, _src_name(src))

## Decide the body zone. Returns {zone, how: "collision"|"direction"|"environment"}.
func zone_of(a, info: Dictionary, src, from_dir: Vector3) -> Dictionary:
	var right: Vector3 = a.facing.cross(Vector3.UP).normalized() if a.facing.length() > 0.1 else Vector3.RIGHT
	var sc: float = a._scale() if a.has_method("_scale") else 1.0
	if info.get("hit_pos") is Vector3:
		var hp: Vector3 = info.hit_pos
		var rel: Vector3 = hp - a.global_position
		var h := rel.y / sc
		var lat := Vector3(rel.x, 0, rel.z).dot(right) / sc
		return {"zone": _zone_from_point(h, lat), "how": "collision", "h": h, "lat": lat}
	var has_src: bool = src != null and is_instance_valid(src)
	var dtype: String = str(info.get("dtype", "slash"))
	if not has_src or (not info.get("melee", false) and from_dir.length() < 0.1):
		# environment: burning or frozen ground hurts the legs, lightning strikes from above
		var side := "l" if (Engine.get_physics_frames() + stats.hits) % 2 == 0 else "r"
		if dtype in ["fire", "ice", "poison"]:
			return {"zone": "leg_" + side, "how": "environment"}
		if dtype in ["lightning", "energy"]:
			return {"zone": ["head", "chest", "arm_r"][stats.hits % 3], "how": "environment"}
		return {"zone": ["chest", "abdomen", "leg_" + side][stats.hits % 3], "how": "environment"}
	# estimate from the attack direction
	var lat2 := from_dir.dot(right)
	var src_sc: float = src._scale() if src.has_method("_scale") else 1.0
	var src_h: float = src.global_position.y + 1.2 * src_sc
	var dh: float = (src_h - (a.global_position.y + 1.2 * sc)) / sc
	var w := {"head": 0.6, "chest": 1.6, "abdomen": 1.3, "arm_l": 0.9, "arm_r": 0.9, "leg_l": 0.8, "leg_r": 0.8}
	if dh > 0.5:          # from above (big bosses, slams, high ground)
		w.head *= 2.5
		w.chest *= 1.4
		w.leg_l *= 0.3
		w.leg_r *= 0.3
	elif dh < -0.35:      # low attackers (wolves, crawlers) bite legs
		w.leg_l *= 3.0
		w.leg_r *= 3.0
		w.abdomen *= 1.3
		w.head *= 0.15
	if lat2 > 0.35:
		w.arm_r *= 2.5
		w.leg_r *= 2.0
		w.arm_l *= 0.4
		w.leg_l *= 0.4
	elif lat2 < -0.35:
		w.arm_l *= 2.5
		w.leg_l *= 2.0
		w.arm_r *= 0.4
		w.leg_r *= 0.4
	if a.blocking:
		w.arm_l *= 2.0       # the guard arm takes what slips past the block
	# deterministic pick from the weights (seeded by the hit, not a blind roll)
	var total := 0.0
	for k in w:
		total += float(w[k])
	var seed_v: int = hash(str(src.get_instance_id()) + ":" + str(stats.hits))
	var roll := float(absi(seed_v) % 10000) / 10000.0 * total
	var acc := 0.0
	for k in ZONES:
		acc += float(w[k])
		if roll <= acc:
			return {"zone": k, "how": "direction", "dh": dh, "lat": lat2}
	return {"zone": "chest", "how": "direction"}

static func _zone_from_point(h: float, lat: float) -> String:
	var side := "r" if lat >= 0.0 else "l"
	if h >= 1.45:
		return "head"
	if h >= 1.1:
		return "arm_" + side if absf(lat) > 0.24 else "chest"
	if h >= 0.82:
		return "arm_" + side if absf(lat) > 0.27 else "abdomen"
	return "leg_" + side

func _type_for(dtype: String, info: Dictionary, src, zone: String, score: float) -> String:
	var limb := zone.begins_with("arm") or zone.begins_with("leg")
	match dtype:
		"slash":
			var cat := ""
			if src != null and is_instance_valid(src) and src.has_method("weapon_cat"):
				cat = src.weapon_cat()
			if cat in ["heavy", "hammer", "mace", "club"]:
				return "fracture" if limb and score >= 1.4 else "bruise"
			return "cut"
		"pierce":
			return "stab"
		"blunt":
			if limb and (score >= 1.2 or (float(info.get("knock", 0.0)) >= 6.0 and score >= 0.9)):
				return "fracture"
			return "bruise"
		"fire":
			return "burn"
		"ice":
			return "frost"
		"lightning", "energy":
			return "shock"
		"poison":
			return "stab" if src != null and is_instance_valid(src) and src.has_meta("species") else "magic"
		"earth":
			return "fracture" if limb and score >= 1.3 else "bruise"
	if dtype in MAGIC_TYPES or str(info.get("school", "")) != "":
		return "magic"
	return "bruise"

func _src_name(src) -> String:
	if src != null and is_instance_valid(src):
		return str(src.get("display_name")) if src.get("display_name") != null else ""
	return ""

## Create or worsen an injury. Returns the injury dictionary.
func add_injury(zone: String, type: String, sev: int, src_name := "") -> Dictionary:
	var l := list()
	sev = clampi(sev, 1, 3)
	for inj in l:
		if inj.zone == zone and inj.type == type:
			# hurt again in the same place: it gets worse and reopens
			inj.sev = mini(3, maxi(int(inj.sev), sev) + (1 if sev >= int(inj.sev) and sev >= 2 else 0))
			inj.bleed = maxi(int(inj.bleed), _bleed_for(type, int(inj.sev), zone))
			inj.bandaged = false
			inj.treated = false if _is_open(inj) else inj.treated
			inj.heal = 0.0
			_notify(inj, true)
			_changed()
			return inj
	if l.size() >= MAX_INJURIES:
		# the body is already a patchwork: worsen the worst wound of that zone instead
		for inj2 in l:
			if inj2.zone == zone:
				inj2.sev = mini(3, int(inj2.sev) + 1)
				_changed()
				return inj2
	var inj3 := {"id": _next_id, "zone": zone, "type": type, "sev": sev, "bleed": _bleed_for(type, sev, zone),
		"bandaged": false, "treated": false, "splinted": false, "infect": 0.0, "infected": false, "worsen": 0.0,
		"heal": 0.0, "clot": 0.0, "t": Game.game_time, "src": src_name}
	_next_id += 1
	l.append(inj3)
	stats.injuries += 1
	stats.by_zone[zone] = int(stats.by_zone.get(zone, 0)) + 1
	_notify(inj3, false)
	_changed()
	return inj3

static func _bleed_for(type: String, sev: int, zone: String) -> int:
	match type:
		"cut":
			return sev
		"stab":
			return mini(3, sev + (1 if zone in ["chest", "abdomen"] and sev >= 2 else 0))
		"fracture":
			return 1 if sev >= 3 else 0
	return 0

static func _is_open(inj: Dictionary) -> bool:
	match String(inj.type):
		"cut", "stab":
			return true
		"burn":
			return int(inj.sev) >= 2
		"frost":
			return int(inj.sev) >= 3
		"fracture":
			return int(inj.bleed) > 0 or int(inj.sev) >= 3
	return false

func _notify(inj: Dictionary, again: bool) -> void:
	var t := "%s%s: %s (%s)" % ["Снова ранение — " if again else "Ранение — ", ZONE_NAMES[inj.zone], TYPE_NAMES[inj.type], SEV_NAMES[int(inj.sev)]]
	if int(inj.bleed) > 0:
		t += ", кровотечение"
	Events.notify.emit(t, color_of(inj))

func _changed() -> void:
	var p = _player()
	if p != null and is_instance_valid(p):
		p.recalc_stats()

# ------------------------------------------------------------------ queries
static func color_of(inj: Dictionary) -> Color:
	if String(inj.type) == "magic":
		return Color(0.7, 0.35, 1.0)
	return [Color(0.4, 0.9, 1.0), Color(1.0, 0.9, 0.25), Color(1.0, 0.55, 0.15), Color(1.0, 0.18, 0.15)][clampi(int(inj.sev), 0, 3)]

## Worst injury of a zone ({} when the zone is healthy).
func worst(zone: String) -> Dictionary:
	var best := {}
	for inj in list():
		if inj.zone != zone:
			continue
		var k := int(inj.sev) * 10 + (5 if inj.type == "magic" else 0) + (3 if inj.infected else 0)
		if best.is_empty() or k > int(best.get("_k", 0)):
			best = inj
			best["_k"] = k
	if not best.is_empty():
		best.erase("_k")
	return best

func of_zone(zone: String) -> Array:
	return list().filter(func(i): return i.zone == zone)

func bleeding() -> int:
	var b := 0
	for inj in list():
		if int(inj.bleed) > 0 and not inj.bandaged:
			b = maxi(b, int(inj.bleed))
	return b

func unstable() -> bool:
	for inj in list():
		if (int(inj.bleed) >= 3 and not inj.bandaged) or (int(inj.sev) >= 3 and inj.zone in ["head", "chest", "abdomen"] and not inj.treated and not inj.splinted):
			return true
	return false

## Stat changes of one injury (positive "hc_*" keys are penalties as shares).
func inj_mods(inj: Dictionary) -> Dictionary:
	var m := {}
	var s := int(inj.sev)
	var t: String = inj.type
	match String(inj.zone):
		"arm_r":
			if t == "fracture":
				m.dmg_pct = -0.3
				m.aspd = -0.25
			elif t == "bruise":
				m.aspd = -0.04 * s
			else:
				m.dmg_pct = -0.05 * s
				m.aspd = -0.03 * s
		"arm_l":
			m.block = -0.4 if t == "fracture" else -0.08 * s
			m.hc_twohand = 0.12 if t == "fracture" else 0.03 * s
		"leg_l", "leg_r":
			if t == "fracture":
				m.speed = -0.15 if inj.splinted else -0.3
			else:
				m.speed = -0.05 * s
		"head":
			m.crit = -0.02 * s
			m.spell = -0.06 * s
			if s >= 3:
				m.hc_st_regen = 0.2
		"chest":
			m.hc_st = 0.07 * s
			m.hc_st_regen = 0.1 * s
		"abdomen":
			m.hc_hp = 0.04 * s
			m.hc_st = 0.05 * s
	match t:
		"magic":
			m.spell = float(m.get("spell", 0.0)) - 0.05 * s
			m.hc_mana = 0.06 * s
		"frost":
			m.aspd = float(m.get("aspd", 0.0)) - 0.03 * s
		"shock":
			m.aspd = float(m.get("aspd", 0.0)) - 0.02 * s
			m.crit = float(m.get("crit", 0.0)) - 0.01 * s
		"burn":
			m.hc_st_regen = float(m.get("hc_st_regen", 0.0)) + 0.05 * s
	if s >= 3:
		m.hc_hp = float(m.get("hc_hp", 0.0)) + 0.05
	if inj.infected:
		m.hc_regen = 0.5
		m.hc_st_regen = float(m.get("hc_st_regen", 0.0)) + 0.15
	if int(inj.bleed) > 0 and not inj.bandaged:
		m.hc_regen = 1.0
	return m

## Folded into Actor.recalc_stats for the player.
func mods_into(s: Dictionary) -> void:
	var p = _player()
	var two_h := false
	if p != null and is_instance_valid(p):
		two_h = bool(ItemDB.base(p.weapon().get("base", "")).get("two_h", false)) if not p.weapon().is_empty() else false
	var pain: bool = float(Profile.char.get("pain_until") if Profile.char.get("pain_until") != null else 0.0) > Game.game_time
	var k := 0.5 if pain else 1.0
	for inj in list():
		var m := inj_mods(inj)
		for key in m:
			var v: float = float(m[key])
			if key == "hc_twohand":
				if two_h:
					s.dmg_pct = float(s.get("dmg_pct", 0.0)) - v * k
				continue
			if key in ["hc_regen"]:
				s[key] = maxf(float(s.get(key, 0.0)), v)       # bleeding blocks regen whatever the pain relief
				continue
			s[key] = float(s.get(key, 0.0)) + v * (k if not key.begins_with("hc_") or key != "hc_regen" else 1.0)
	if unstable():
		s.hc_regen = 1.0
	for key in ["hc_hp", "hc_st", "hc_mana"]:
		if s.has(key):
			s[key] = clampf(float(s[key]), 0.0, 0.5)

static func mods_text(m: Dictionary) -> Array:
	var names := {"dmg_pct": "Урон", "aspd": "Скорость атак", "block": "Блок", "speed": "Скорость передвижения", "crit": "Шанс крита",
		"spell": "Сила заклинаний", "hc_st": "Макс. выносливость", "hc_st_regen": "Восстановление выносливости", "hc_hp": "Макс. здоровье",
		"hc_mana": "Макс. мана", "hc_regen": "Естественное восстановление HP", "hc_twohand": "Урон двуручным оружием"}
	var out: Array = []
	for k in m:
		var v: float = float(m[k])
		if absf(v) < 0.001:
			continue
		var pct := roundi(absf(v) * 100.0)
		out.append("%s −%d%%" % [names.get(k, k), pct])
	return out

# ------------------------------------------------------------------ treatment
## What can be done for one injury: [{proc, need, items: [base ids that work]}].
func treatments_for(inj: Dictionary) -> Array:
	var out: Array = []
	if int(inj.bleed) > 0 and not inj.bandaged:
		out.append({"proc": "Остановить кровотечение", "key": "bleed", "need": int(inj.bleed)})
	if _is_open(inj) and not inj.treated and not inj.infected:
		out.append({"proc": "Обработать рану", "key": "infection", "need": 1})
	if inj.infected:
		out.append({"proc": "Лечить заражение", "key": "infection", "need": 2 if int(inj.sev) < 3 else 3})
	if inj.type == "fracture" and not inj.splinted:
		out.append({"proc": "Стабилизировать перелом", "key": "fracture", "need": 1})
	if inj.type in ["burn", "frost"]:
		out.append({"proc": "Регенерация тканей", "key": "burn", "need": 1})
	if inj.type == "magic":
		out.append({"proc": "Магическое исцеление", "key": "magic", "need": 1})
	if inj.type in ["bruise", "shock"] or (out.is_empty() and int(inj.sev) >= 1):
		out.append({"proc": "Обезболить и дать покой", "key": "pain", "need": 1})
	out.append({"proc": "Технологическая регенерация", "key": "regen", "need": 1})
	for t in out:
		t.items = _items_for(String(t.key), int(t.need))
	return out

static func _items_for(key: String, need: int) -> Array:
	var out: Array = []
	var a := ItemCatalog.all()
	for id in a:
		var med: Dictionary = a[id].get("med", {})
		if int(med.get(key, 0)) >= need or (key == "regen" and float(med.get("regen", 0.0)) > 0.0):
			out.append(id)
	return out

## Use a medicine item. Returns true when it did something (the item is used up).
## target_id focuses the item on one injury (from the anatomy screen).
func apply_medicine(a, base: String, med: Dictionary, target_id := -1) -> bool:
	var done: Array = []
	var l := list()
	var order: Array = l.duplicate()
	order.sort_custom(func(x, y): return int(x.sev) * 10 + int(x.bleed) > int(y.sev) * 10 + int(y.bleed))
	if target_id >= 0:
		for inj in l:
			if int(inj.id) == target_id:
				order.erase(inj)
				order.push_front(inj)
	# each procedure treats ONE wound per item (the targeted / worst one)
	if int(med.get("bleed", 0)) > 0:
		for inj in order:
			if int(inj.bleed) <= 0 or inj.bandaged:
				continue
			if int(inj.bleed) <= int(med.bleed):
				inj.bandaged = true
				done.append("кровотечение остановлено (%s)" % ZONE_NAMES[inj.zone])
			else:
				# too weak to stop it: a tight dressing still slows the bleeding
				inj.bleed = maxi(1, int(inj.bleed) - int(med.bleed))
				inj.clot = 0.0
				done.append("кровотечение ослаблено (%s) — нужна повязка сильнее или лекарь" % ZONE_NAMES[inj.zone])
			break
	if int(med.get("infection", 0)) > 0:
		var lvl: int = int(med.infection)
		for inj in order:
			if inj.infected and lvl >= (2 if int(inj.sev) < 3 else 3):
				inj.infected = false
				inj.infect = 0.0
				inj.treated = true
				inj.worsen = 0.0
				done.append("заражение вылечено (%s)" % ZONE_NAMES[inj.zone])
				break
			if _is_open(inj) and not inj.treated and not inj.infected:
				inj.treated = true
				inj.infect = 0.0
				done.append("рана обработана (%s)" % ZONE_NAMES[inj.zone])
				break
	if int(med.get("fracture", 0)) > 0:
		for inj in order:
			if inj.type == "fracture" and not inj.splinted:
				inj.splinted = true
				done.append("перелом стабилизирован (%s)" % ZONE_NAMES[inj.zone])
				break
	if int(med.get("burn", 0)) > 0:
		for inj in order:
			if inj.type in ["burn", "frost"] and int(inj.sev) <= int(med.burn) + 1:
				inj.treated = true
				inj.heal = float(inj.heal) + 0.6
				done.append("%s заживает (%s)" % [TYPE_NAMES[inj.type].to_lower(), ZONE_NAMES[inj.zone]])
				break
	if int(med.get("magic", 0)) > 0:
		for inj in order:
			if inj.type == "magic":
				inj.sev = int(inj.sev) - int(med.magic)
				done.append("магическое повреждение ослаблено (%s)" % ZONE_NAMES[inj.zone])
				break
	if float(med.get("regen", 0.0)) > 0.0:
		for inj in l:
			if int(inj.bleed) == 0 or inj.bandaged:
				inj.heal = float(inj.heal) + float(med.regen)
		done.append("ткани регенерируют")
	if int(med.get("pain", 0)) > 0:
		Profile.char.pain_until = Game.game_time + 0.25
		for inj in l:
			if inj.type in ["bruise", "shock"]:
				inj.heal = float(inj.heal) + 0.25
		done.append("боль утихла — штрафы ослаблены на 6 ч")
	_resolve_heal()
	var healed_hp := false
	if float(med.get("heal", 0.0)) > 0.0 and a.hp < a.max_hp:
		a.heal(a.max_hp * float(med.heal))
		healed_hp = true
	if done.is_empty() and not healed_hp:
		Events.notify.emit("%s сейчас не поможет" % ItemDB.base(base).get("name", "Средство"), Color(0.8, 0.8, 0.8))
		return false
	stats.treated += done.size()
	VFX.burst(a.chest(), Color(0.6, 1.0, 0.7), 8, 0.25)
	Audio.play_sfx("heal", a.global_position, -4.0)
	if not done.is_empty():
		Events.notify.emit("%s: %s" % [ItemDB.base(base).get("name", "Лечение"), ", ".join(PackedStringArray(done))], Color(0.6, 1.0, 0.7))
	_changed()
	return true

## A venomous bite: the newest open wound becomes poisoned (infection is
## close — treat it). Never creates a wound by itself.
func poison_last() -> void:
	var l := list()
	if l.is_empty():
		return
	var inj: Dictionary = l[l.size() - 1]
	if not inj.infected and not inj.treated:
		inj.infect = minf(0.95, float(inj.infect) + 0.5)
		inj["poisoned"] = true
		_changed()

## Healing magic (school «Исцеление») on real injuries. Each spell treats
## one state of one wound — the chosen one (anatomy screen) or the most
## fitting one — and refuses what it cannot do: a closing spell does not cure
## infection, tissue restoration does not set bones, a broken bone is not set
## while it bleeds, heavy infection needs a healer. One spell effect per
## wound per 6 game hours (no endless healing). Returns {ok, done, reason}.
const SPELL_GAP_DAYS := 0.25

func spell_op(a, op: String, slvl: int, target_id := -1) -> Dictionary:
	var l := list()
	var res := {"ok": false, "done": [], "reason": ""}
	var order: Array = l.duplicate()
	order.sort_custom(func(x, y): return int(x.sev) * 10 + int(x.bleed) > int(y.sev) * 10 + int(y.bleed))
	if target_id >= 0:
		for inj in l:
			if int(inj.id) == target_id:
				order = [inj]
				break
	var fresh := func(inj: Dictionary) -> bool:
		var st: Dictionary = inj.get("spell_t", {})
		return Game.game_time - float(st.get(op, -99.0)) >= SPELL_GAP_DAYS
	var mark := func(inj: Dictionary) -> void:
		var st: Dictionary = inj.get("spell_t", {})
		st[op] = Game.game_time
		inj["spell_t"] = st
	var zn := func(inj: Dictionary) -> String: return ZONE_NAMES.get(inj.zone, inj.zone)
	match op:
		"soothe":
			Profile.char.pain_until = maxf(Profile.char.pain_until, Game.game_time + 0.125)
			for inj in order:
				if int(inj.sev) == 1 and inj.type in ["bruise", "shock", "cut"] and fresh.call(inj):
					inj.heal = float(inj.heal) + 0.3
					mark.call(inj)
			res.done.append("боль от лёгких травм утихла на 3 ч")
		"close_wound":
			for inj in order:
				if not inj.type in ["cut", "stab"] or int(inj.sev) > 2:
					if target_id >= 0:
						res.reason = "«Закрытие раны» лечит только лёгкие и средние порезы и колотые раны"
					continue
				if inj.infected:
					res.reason = "рана заражена — сначала «Очищающий поток»"
					continue
				if not fresh.call(inj):
					res.reason = "рана уже под действием заклинания"
					continue
				inj.bandaged = true
				inj.bleed = 0
				inj.treated = true
				inj.infect = 0.0
				inj.heal = float(inj.heal) + 0.75
				mark.call(inj)
				res.done.append("рана закрыта (%s)" % zn.call(inj))
				break
		"hemostasis":
			var cap := 3 if slvl >= 10 else 2
			for inj in order:
				if int(inj.bleed) <= 0 or inj.bandaged:
					continue
				if not fresh.call(inj):
					res.reason = "кровотечение уже под печатью"
					continue
				mark.call(inj)
				if int(inj.bleed) <= cap:
					inj.bandaged = true
					res.done.append("кровотечение остановлено (%s)" % zn.call(inj))
				else:
					inj.bleed = maxi(1, int(inj.bleed) - 1)
					inj.clot = 0.0
					res.done.append("кровотечение ослаблено (%s) — сильное останавливается с мастерства 10" % zn.call(inj))
				break
			if res.done.is_empty() and res.reason == "":
				res.reason = "нет кровотечения"
		"cleanse":
			for inj in order:
				if inj.infected:
					if int(inj.sev) >= 3:
						res.reason = "тяжёлое заражение не снимается заклинанием — нужен лекарь"
						continue
					if int(inj.sev) == 2 and slvl < 12:
						res.reason = "заражение средней раны — с мастерства 12"
						continue
					inj.infected = false
					inj.infect = 0.0
					inj.worsen = 0.0
					inj.treated = true
					res.done.append("заражение снято (%s)" % zn.call(inj))
					break
				if inj.type == "magic" and fresh.call(inj):
					inj.sev = int(inj.sev) - 1
					mark.call(inj)
					res.done.append("магическое повреждение ослаблено (%s)" % zn.call(inj))
					break
				if _is_open(inj) and not inj.treated and float(inj.infect) > 0.0:
					inj.infect = 0.0
					inj.treated = true
					res.done.append("рана очищена (%s)" % zn.call(inj))
					break
			if res.done.is_empty() and res.reason == "":
				res.reason = "нет заражения или проклятия"
		"tissue":
			for inj in order:
				if inj.type == "fracture":
					res.reason = "перелом сращивает «Костяное единство»"
					continue
				if inj.infected:
					res.reason = "заражённая рана не заживёт — сначала «Очищающий поток»"
					continue
				if int(inj.bleed) > 0 and not inj.bandaged:
					res.reason = "сначала остановите кровотечение"
					continue
				if not fresh.call(inj):
					res.reason = "ткани уже восстанавливаются"
					continue
				inj.heal = float(inj.heal) + 0.85
				if inj.type in ["burn", "frost"]:
					inj.treated = true
				mark.call(inj)
				res.done.append("%s заживает быстрее (%s)" % [TYPE_NAMES.get(inj.type, "травма").to_lower(), zn.call(inj)])
				break
		"bone_unity":
			for inj in order:
				if inj.type != "fracture":
					continue
				if int(inj.bleed) > 0 and not inj.bandaged:
					res.reason = "перелом кровоточит — сначала «Печать кровостаза»"
					continue
				if not fresh.call(inj):
					res.reason = "кость уже срастается"
					continue
				inj.splinted = true
				inj.treated = true
				inj.heal = float(inj.heal) + 1.0
				mark.call(inj)
				res.done.append("кость срастается (%s)" % zn.call(inj))
				break
			if res.done.is_empty() and res.reason == "":
				res.reason = "нет перелома"
		"great_regen":
			for inj in order:
				if int(inj.sev) < 2:
					continue
				if inj.infected and int(inj.sev) >= 3:
					res.reason = "тяжёлое заражение великая регенерация не лечит"
					continue
				if not fresh.call(inj):
					res.reason = "травма уже под действием регенерации"
					continue
				inj.sev = int(inj.sev) - 1
				inj.bandaged = true
				inj.treated = true
				inj.bleed = mini(int(inj.bleed), 0)
				if inj.type == "fracture":
					inj.splinted = true
				mark.call(inj)
				res.done.append("тяжёлая травма отступает (%s)" % zn.call(inj))
				break
		"dawn":
			for inj in l:
				if int(inj.bleed) > 0:
					inj.bandaged = true
				if int(inj.sev) >= 3 and inj.type == "fracture":
					inj.splinted = true
			res.done.append("тяжелораненые стабилизированы")
	res.ok = not res.done.is_empty()
	if res.ok:
		stats.treated += res.done.size()
		_resolve_heal()
		_changed()
		Events.notify.emit("Исцеление: %s" % ", ".join(PackedStringArray(res.done)), Color(1.0, 0.9, 0.5))
	elif res.reason != "":
		Events.notify.emit("Исцеление: %s" % res.reason, Color(0.9, 0.8, 0.6))
	return res

## Full care. source: "healer" (знахарь / целитель), "doctor" (врач),
## "station" (медицинская станция, heal_tier 1–2), "capsule" (футуристическая
## капсула). Returns {done: [...]}.
func treat_all(source: String, tier := 1) -> Dictionary:
	var done: Array = []
	var l := list()
	if source == "capsule":
		var n := l.size()
		l.clear()
		Profile.char.pain_until = 0.0
		if n > 0:
			done.append("капсула полностью восстановила тело (%d повреждений)" % n)
	else:
		for inj in l:
			if int(inj.bleed) > 0 and not inj.bandaged:
				inj.bandaged = true
				done.append("остановлено кровотечение")
			if inj.infected and (source != "station" or tier >= 2):
				inj.infected = false
				inj.infect = 0.0
				inj.worsen = 0.0
				done.append("вылечено заражение")
			if _is_open(inj) and not inj.treated:
				inj.treated = true
				done.append("обработана рана")
			if inj.type == "fracture" and not inj.splinted:
				inj.splinted = true
				done.append("наложена шина")
			if inj.type == "magic":
				inj.sev = int(inj.sev) - (2 if source == "healer" else 1)
				done.append("снято магическое повреждение" if int(inj.sev) <= 0 else "ослаблено магическое повреждение")
			inj.heal = float(inj.heal) + (0.35 if source in ["healer", "doctor"] else 0.15 * tier)
		_resolve_heal()
	stats.treated += done.size()
	var p = _player()
	if p != null and is_instance_valid(p):
		VFX.burst(p.chest(), Color(0.6, 1.0, 0.75), 14, 0.35)
		Audio.play_sfx("heal", p.global_position)
	var uniq: Array = []
	for d in done:
		if not d in uniq:
			uniq.append(d)
	Events.notify.emit(("Лечение: " + ", ".join(PackedStringArray(uniq))) if not uniq.is_empty() else "Лечение не требуется", Color(0.6, 1.0, 0.75))
	_changed()
	return {"done": uniq}

## Price of a healer's/doctor's full care.
func care_price() -> int:
	var s := 0
	for inj in list():
		s += int(inj.sev) * (2 if inj.infected else 1)
	return s * 12 * (Profile.current_era + 1)

## Rest (sleeping in a bed, at the inn, at home): advances recovery faster.
## quality 1 = inn/simple bed, 2 = own bed, 3 = bed + medical station.
func rest(hours: float, quality := 1) -> void:
	var dt := hours / 24.0
	_rest_mult = 1.0 + 1.5 * quality
	_progress(dt)
	_rest_mult = 1.0

# ------------------------------------------------------------------ time
func _process(delta: float) -> void:
	if world == null or not enabled():
		_last_gt = Game.game_time
		return
	var p = _player()
	if p == null or not is_instance_valid(p) or p.is_dead:
		_last_gt = Game.game_time
		return
	if get_tree().paused:
		return
	_bleed_acc += delta
	if _bleed_acc >= 0.5:
		_bleed(p, _bleed_acc)
		_bleed_acc = 0.0
	_acc += delta
	if _acc >= 2.0:
		_acc = 0.0
		if _last_gt < 0.0:
			_last_gt = Game.game_time
		var dt := Game.game_time - _last_gt
		_last_gt = Game.game_time
		if dt > 0.0:
			_progress(dt)

func _bleed(p, dt: float) -> void:
	var drain := 0.0
	var floor_v := 1.0
	for inj in list():
		var b := int(inj.bleed)
		if b <= 0 or inj.bandaged:
			continue
		drain += BLEED_RATE[b] * p.max_hp * dt
		floor_v = minf(floor_v, BLEED_FLOOR[b])
	if drain <= 0.0:
		return
	var floor_hp: float = floor_v * p.max_hp
	if p.hp - drain < floor_hp and floor_v > 0.0:
		drain = maxf(0.0, p.hp - floor_hp)
	p.hp -= drain
	stats.bled += drain
	_drip_t -= dt
	if _drip_t <= 0.0:
		_drip_t = 1.2
		VFX.burst(p.global_position + Vector3(0, 0.6, 0), Color(0.55, 0.02, 0.02), 3, 0.07)
	if p.hp <= 0.0:
		p.hp = 0.0
		p.die(null)

## Advance infection, worsening and recovery by dt game days.
func _progress(dt: float) -> void:
	var l := list()
	var changed := false
	for inj in l:
		var sev := int(inj.sev)
		if int(inj.bleed) > 0 and not inj.bandaged:
			if int(inj.bleed) == 1:
				inj.clot = float(inj.clot) + dt
				if float(inj.clot) >= CLOT_DAYS:
					inj.bleed = 0
					changed = true
			continue          # an open bleeding wound does not heal
		var dt_inf := dt          # part of dt spent already infected
		if _is_open(inj) and not inj.treated and not inj.infected and sev >= 2:
			var rate := 1.0 / float(INFECT_DAYS[sev]) * (0.5 if inj.bandaged else 1.0)
			var before := float(inj.infect)
			inj.infect = before + dt * rate
			dt_inf = 0.0
			if float(inj.infect) >= 1.0:
				inj.infected = true
				dt_inf = maxf(0.0, dt - (1.0 - before) / rate)
				stats.infections += 1
				changed = true
				Events.notify.emit("Рана воспалилась: %s — нужна обработка" % ZONE_NAMES[inj.zone], Color(0.6, 0.9, 0.3))
		if inj.infected:
			inj.worsen = float(inj.worsen) + dt_inf
			if float(inj.worsen) >= WORSEN_DAYS:
				inj.worsen = 0.0
				if sev < 3:
					inj.sev = sev + 1
					stats.worsened += 1
					changed = true
					Events.notify.emit("Заражение усиливается: %s (%s)" % [ZONE_NAMES[inj.zone], SEV_NAMES[int(inj.sev)]], Color(0.9, 0.5, 0.2))
			continue          # infected wounds do not heal
		if inj.type == "fracture" and sev >= 2 and not inj.splinted:
			continue          # a broken bone must be set first
		var mult := _rest_mult * (1.5 if inj.treated else 1.0)
		inj.heal = float(inj.heal) + dt / float(HEAL_DAYS[sev]) * mult
	if _resolve_heal() or changed:
		_changed()

## Apply accumulated recovery: a full bar lowers the severity by one step.
func _resolve_heal() -> bool:
	var l := list()
	var changed := false
	for inj in l.duplicate():
		while float(inj.heal) >= 1.0 and int(inj.sev) > 0:
			inj.heal = float(inj.heal) - 1.0
			inj.sev = int(inj.sev) - 1
			inj.bleed = mini(int(inj.bleed), int(inj.sev) - 1) if int(inj.bleed) > 0 else 0
			changed = true
		if int(inj.sev) <= 0:
			l.erase(inj)
			stats.healed += 1
			changed = true
			Events.notify.emit("Зажило: %s — %s" % [ZONE_NAMES[inj.zone], TYPE_NAMES[inj.type].to_lower()], Color(0.6, 1.0, 0.7))
	return changed

## Dying in Hardcore: whoever found you patched you up — bleeding stopped,
## light wounds gone, the rest stays.
func _on_player_died() -> void:
	if not enabled():
		return
	var l := list()
	for inj in l.duplicate():
		inj.bleed = 0
		inj.bandaged = false
		if int(inj.sev) <= 1:
			l.erase(inj)
	_changed()

# ------------------------------------------------------------------ HUD
func hud_chips() -> Array:
	var out: Array = []
	if not enabled() or list().is_empty():
		return out
	var b := bleeding()
	if b > 0:
		out.append(["Кровотечение" + ("!" if b >= 3 else ""), Color(0.9, 0.12, 0.12)])
	var inf := false
	var fr := false
	var mg := false
	var worst_s := 0
	for inj in list():
		inf = inf or inj.infected
		fr = fr or (inj.type == "fracture")
		mg = mg or (inj.type == "magic")
		worst_s = maxi(worst_s, int(inj.sev))
	if fr:
		out.append(["Перелом", Color(1.0, 0.75, 0.5)])
	if inf:
		out.append(["Заражение", Color(0.6, 0.9, 0.3)])
	if mg:
		out.append(["Магич. травма", Color(0.7, 0.35, 1.0)])
	out.append(["Ранений: %d" % list().size(), [Color(0.6, 0.6, 0.6), Color(1.0, 0.9, 0.25), Color(1.0, 0.55, 0.15), Color(1.0, 0.2, 0.15)][worst_s]])
	return out
