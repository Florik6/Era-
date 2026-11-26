class_name CharData
extends RefCounted
## Progression data shared by the player and every humanoid NPC:
## level, independent weapon mastery trees, magic schools, inventory.

var name := "Странник"
var class_id := "warrior"
var female := false
var appearance := {"skin": 1, "hair": 0, "hair_color": 0, "beard": 0, "cloth": 0, "cape": 0}
var level := 1
var xp := 0
var gold := 30
var mastery := {}          # cat -> {lvl, xp, pts, nodes: Array}
var schools := {}          # school -> {lvl, xp}
var slots := {}            # cat -> [id, id, id] chosen actives/spells
var inv := Inventory.new()
var kills := 0
var fame := 0.0
var companion := {}        # {kind, name, lvl, xp}
var injuries: Array = []   # Hardcore Mode wounds (see Hardcore)
var pain_until := 0.0      # game time until which pain relief halves injury penalties

func setup_class(cid: String) -> void:
	class_id = cid
	var c: Dictionary = DBSkills.CLASSES.get(cid, DBSkills.CLASSES.warrior)
	for cat in c.mastery:
		var m := mastery_of(cat)
		m.lvl = c.mastery[cat]
		m.pts = c.mastery[cat]
	for s in c.schools:
		learn_school(s)
	if cid == "mage":
		schools.fire.lvl = 2

func mastery_of(cat: String) -> Dictionary:
	if not mastery.has(cat):
		mastery[cat] = {"lvl": 0, "xp": 0, "pts": 0, "nodes": []}
	return mastery[cat]

func mastery_level(cat: String) -> int:
	return int(mastery.get(cat, {}).get("lvl", 0))

## Returns number of mastery levels gained.
func add_mastery_xp(cat: String, amount: float) -> int:
	var m := mastery_of(cat)
	m.xp = int(m.xp + amount)
	var gained := 0
	while m.xp >= DBSkills.mastery_xp_needed(m.lvl) and m.lvl < 30:
		m.xp -= DBSkills.mastery_xp_needed(m.lvl)
		m.lvl += 1
		m.pts += 1
		gained += 1
	return gained

func has_node(id: String) -> bool:
	for cat in mastery:
		if id in mastery[cat].nodes:
			return true
	return false

func can_learn(cat: String, id: String) -> bool:
	var n := DBSkills.node(cat, id)
	if n.is_empty():
		return false
	var m := mastery_of(cat)
	if id in m.nodes or m.pts <= 0 or m.lvl < n.lvl:
		return false
	return n.req == "" or n.req in m.nodes

func learn_node(cat: String, id: String) -> bool:
	if not can_learn(cat, id):
		return false
	var m := mastery_of(cat)
	m.nodes.append(id)
	m.pts -= 1
	var n := DBSkills.node(cat, id)
	if n.type == "active":
		var s: Array = slots_for(cat)
		for i in s.size():
			if s[i] == "":
				s[i] = id
				break
	return true

## Bots and new characters: spend all points greedily.
func auto_learn() -> void:
	for cat in mastery:
		var guard := 0
		while mastery[cat].pts > 0 and guard < 20:
			guard += 1
			var learned := false
			for n in DBSkills.TREES.get(cat, []):
				if learn_node(cat, n.id):
					learned = true
					break
			if not learned:
				break

func slots_for(cat: String) -> Array:
	if not slots.has(cat):
		slots[cat] = ["", "", ""]
	return slots[cat]

func knows_school(s: String) -> bool:
	return schools.has(s)

func learn_school(s: String) -> bool:
	if schools.has(s):
		return false
	schools[s] = {"lvl": 1, "xp": 0}
	return true

func school_level(s: String) -> int:
	return int(schools.get(s, {}).get("lvl", 0))

func add_school_xp(s: String, amount: float) -> int:
	if not schools.has(s):
		return 0
	var d: Dictionary = schools[s]
	d.xp = int(d.xp + amount)
	var g := 0
	while d.xp >= DBSkills.mastery_xp_needed(d.lvl) and d.lvl < 30:
		d.xp -= DBSkills.mastery_xp_needed(d.lvl)
		d.lvl += 1
		g += 1
	return g

func best_school() -> String:
	var best := ""
	var bl := 0
	for s in schools:
		if schools[s].lvl > bl:
			bl = schools[s].lvl
			best = s
	return best

func known_spells() -> Array:
	var out: Array = []
	for s in schools:
		for sp in DBSkills.SCHOOLS[s].spells:
			if sp.lvl <= schools[s].lvl:
				out.append(sp.id)
	return out

func known_actives(cat: String) -> Array:
	var out: Array = []
	for id in mastery_of(cat).nodes:
		if DBSkills.node(cat, id).get("type", "") == "active":
			out.append(id)
	return out

## Fill empty slots with sensible defaults (actives first, then spells).
func auto_slots(cat: String) -> Array:
	var s: Array = slots_for(cat)
	var pool: Array = known_actives(cat)
	var sp := known_spells()
	if cat == "staff":
		pool = sp + pool
	else:
		pool = pool + sp
	for i in 3:
		if s[i] != "" and not (s[i] in pool):
			s[i] = ""
	for id in pool:
		if id in s:
			continue
		for i in 3:
			if s[i] == "":
				s[i] = id
				break
	# a legendary / mythic weapon brings its weapon art into the last slot
	var art := str(inv.equipped("main").get("art", ""))
	if art != "":
		var aid := "art_" + art
		if not aid in s:
			s[2] = aid
	return s

func xp_needed() -> int:
	return DBSkills.level_xp_needed(level)

func add_xp(n: int) -> int:
	xp += n
	var g := 0
	while xp >= xp_needed() and level < 60:
		xp -= xp_needed()
		level += 1
		g += 1
	return g

func weapon_categories_at(lvl: int) -> int:
	var n := 0
	for cat in mastery:
		if cat != "unarmed" and mastery[cat].lvl >= lvl:
			n += 1
	return n

func hybrids() -> Array:
	var out: Array = []
	var best_melee := 0
	for c in DBSkills.MELEE_CATS:
		best_melee = maxi(best_melee, mastery_level(c))
	var best_ranged := maxi(mastery_level("bow"), mastery_level("firearm"))
	var bs := best_school()
	var bsl := school_level(bs)
	if best_melee >= 5 and bsl >= 3:
		out.append("spellblade")
	if best_ranged >= 5 and bsl >= 3:
		out.append("arcane_archer")
	if mastery_level("dagger") >= 5 and (school_level("dark") >= 2 or school_level("spacetime") >= 2):
		out.append("shadow_dancer")
	if maxi(mastery_level("heavy"), maxi(mastery_level("sword"), mastery_level("spear"))) >= 4 and bsl >= 4:
		out.append("battlemage")
	if weapon_categories_at(5) >= 2:
		out.append("weapon_master")
	return out

func to_dict() -> Dictionary:
	return {"name": name, "class_id": class_id, "female": female, "appearance": appearance, "level": level, "xp": xp,
		"gold": gold, "mastery": mastery, "schools": schools, "slots": slots, "inv": inv.to_dict(), "kills": kills,
		"fame": fame, "companion": companion, "injuries": injuries, "pain_until": pain_until}

func from_dict(d: Dictionary) -> void:
	name = d.get("name", name)
	class_id = d.get("class_id", class_id)
	female = d.get("female", false)
	appearance = d.get("appearance", appearance)
	for k in appearance:
		if typeof(appearance[k]) == TYPE_FLOAT:
			appearance[k] = int(appearance[k])
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	gold = int(d.get("gold", 0))
	mastery = d.get("mastery", {})
	for c in mastery:
		for k in ["lvl", "xp", "pts"]:
			mastery[c][k] = int(mastery[c].get(k, 0))
	schools = d.get("schools", {})
	for s in schools:
		schools[s].lvl = int(schools[s].lvl)
		schools[s].xp = int(schools[s].xp)
	slots = d.get("slots", {})
	inv = Inventory.new()
	inv.from_dict(d.get("inv", {}))
	kills = int(d.get("kills", 0))
	fame = float(d.get("fame", 0.0))
	companion = d.get("companion", {})
	injuries = []
	for inj in d.get("injuries", []):
		if inj is Dictionary:
			for k in ["id", "sev", "bleed"]:
				inj[k] = int(inj.get(k, 0))
			injuries.append(inj)
	pain_until = float(d.get("pain_until", 0.0))
