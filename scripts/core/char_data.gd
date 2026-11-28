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
# «Ascension of Power» progression
var class_pts := 1         # class points: one per character level
var class_skills: Array = []   # learned class skills (DBAbilities)
var spells: Array = []     # learned new spells (DBAbilities)
var knowledge := {}        # "know_<spell>" (mentor), "tome_<spell>" (book), "trial_<school>", "mentor_<school>"
var ab_page := 0           # prepared page shown on the HUD (0 / 1)
var saved_sets := {}       # name -> {cat: {"0": [...], "1": [...]}}
var favorites: Array = []
var pain_until := 0.0      # game time until which pain relief halves injury penalties
var vitals := {}           # saved mana state: {mana, max_mana, delay, potion_cd, surge_t, surge_k}
# Technological Knowledge System (TechKnow) — belongs to the hero, kept across eras
var tech := {}             # family -> {xp, research}
var tech_cats := {}        # category -> general knowledge (books, teachers)
var tech_models := {}      # weapon base id -> {fam, parts, streak, special, shots, examined, identified, compared}
var tech_skills: Array = []  # Tech Cognition branch
var tech_pts := 0          # points of cognition
var tech_mem := {"eras": [0], "schemas": [], "training": [], "maint": []}   # Historical Knowledge Memory

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
			for n in DBSkills.tree(cat):
				if learn_node(cat, n.id):
					learned = true
					break
			if not learned:
				break

func slots_for(cat: String) -> Array:
	return page_slots(cat, 0)

## Prepared abilities of a weapon category on a page (0 / 1), 4 entries
## (the 4th is usable with «Рунная память»).
func page_slots(cat: String, page: int) -> Array:
	var key := cat if page == 0 else cat + "#1"
	if not slots.has(key):
		slots[key] = ["", "", "", ""]
	var s: Array = slots[key]
	while s.size() < 4:
		s.append("")
	return s

func slot_count() -> int:
	return 4 if "cm_rune_memory" in class_skills else 3

## Slots shown on the HUD right now (page 0 is auto-filled with defaults).
func active_slots(cat: String) -> Array:
	if ab_page == 1:
		var p1: Array = page_slots(cat, 1)
		for i in p1.size():
			if p1[i] != "" and not knows_slot_id(p1[i], cat):
				p1[i] = ""
		return p1
	return auto_slots(cat)

func knows_slot_id(id: String, cat: String) -> bool:
	if id.begins_with("art_"):
		return str(inv.equipped("main").get("art", "")) == id.trim_prefix("art_")
	return id in known_actives(cat) or id in known_spells()

## Put an ability into a slot. Returns "" or the reason it is refused.
func set_slot(cat: String, page: int, i: int, id: String) -> String:
	var s := page_slots(cat, page)
	if i < 0 or i >= slot_count():
		return "ячейка недоступна"
	if id != "":
		if not knows_slot_id(id, cat):
			return "умение не изучено"
		if int(DBAbilities.get_ab(id).get("tier", 0)) == 6:
			var others := prepared_cataclysms()
			others.erase(id)
			if s[i] != "" and int(DBAbilities.get_ab(s[i]).get("tier", 0)) == 6:
				others.erase(s[i])
			if others.size() >= cataclysm_cap():
				return "можно подготовить только %d катаклизм(а)" % cataclysm_cap()
	s[i] = id
	return ""

func prepared_cataclysms() -> Array:
	var out: Array = []
	for k in slots:
		for id in slots[k]:
			if id != "" and int(DBAbilities.get_ab(id).get("tier", 0)) == 6 and not id in out:
				out.append(id)
	return out

## One cataclysm prepared at a time; a rare artifact allows a second.
func cataclysm_cap() -> int:
	for k in inv.equip:
		if inv.equip[k].get("extra_cataclysm", false) or ItemDB.base(inv.equip[k].base).get("extra_cataclysm", false):
			return 2
	return 1

func save_set(nm: String) -> void:
	var d := {}
	for k in slots:
		d[k] = (slots[k] as Array).duplicate()
	saved_sets[nm] = d

func load_set(nm: String) -> bool:
	if not saved_sets.has(nm):
		return false
	for k in saved_sets[nm]:
		slots[k] = (saved_sets[nm][k] as Array).duplicate()
	return true

# ------------------------------------------------------------ abilities
## Passive skills currently learned (class skills + weapon tree nodes).
func passive_ids() -> Array:
	var out: Array = []
	for id in class_skills:
		out.append(id)
	for cat in mastery:
		for id in mastery[cat].nodes:
			if DBAbilities.has(id):
				out.append(id)
	return out

func knows_ability(id: String) -> bool:
	var e: Dictionary = DBAbilities.get_ab(id)
	match str(e.get("kind", "")):
		"class":
			return id in class_skills
		"weapon":
			return has_node(id)
		"spell":
			return id in spells
	return false

## Why an ability cannot be learned now ("" = it can).
func ability_block(id: String) -> String:
	var e: Dictionary = DBAbilities.get_ab(id)
	if e.is_empty():
		return "нет такого умения"
	if knows_ability(id):
		return "уже изучено"
	match str(e.kind):
		"class":
			if e.cls != class_id:
				return "только для класса «%s»" % DBSkills.CLASSES.get(e.cls, {}).get("name", e.cls)
			if level < int(e.lvl):
				return "нужен уровень %d" % int(e.lvl)
			if str(e.req) != "" and not e.req in class_skills:
				return "нужно умение «%s»" % DBAbilities.get_ab(e.req).get("name", e.req)
			if class_pts < int(e.cost):
				return "нужно очков класса: %d" % int(e.cost)
		"weapon":
			var m := mastery_of(e.cat)
			if m.lvl < int(e.lvl):
				return "нужно мастерство %d" % int(e.lvl)
			if m.pts < 1:
				return "нет очков мастерства"
		"spell":
			var sch: String = e.school
			if not knows_school(sch):
				return "школа «%s» не изучена" % DBAbilities.school_info(sch).get("name", sch)
			if school_level(sch) < int(e.slvl):
				return "нужно мастерство школы %d" % int(e.slvl)
			if int(schools[sch].get("pts", 0)) < int(e.cost):
				return "нужно очков школы: %d" % int(e.cost)
			var tier: int = int(e.tier)
			if magic_rank() < DBAbilities.TIER_RANK[tier]:
				return "нужен ранг «%s»" % DBAbilities.RANK_NAMES[DBAbilities.TIER_RANK[tier]]
			if tier == 5 and not (knowledge.has("know_" + id) or knowledge.has("tome_" + id)):
				return "нужно знание: наставник или древний трактат"
			if e.get("need_know", false) and not (knowledge.has("know_" + id) or knowledge.has("tome_" + id)):
				return "нужно знание: трактат из подземелья или наставник"
			if tier == 6:
				if not "cm_archmage_path" in class_skills:
					return "нужна специализация «Путь архимага»"
				if not knowledge.has("trial_" + sch):
					return "нужно пройти испытание школы"
				if not knowledge.has("tome_" + id):
					return "нужен древний трактат катаклизма"
	return ""

func learn_ability(id: String) -> bool:
	if ability_block(id) != "":
		return false
	var e: Dictionary = DBAbilities.get_ab(id)
	match str(e.kind):
		"class":
			class_pts -= int(e.cost)
			class_skills.append(id)
		"weapon":
			return learn_node(e.cat, id)
		"spell":
			schools[e.school].pts = int(schools[e.school].get("pts", 0)) - int(e.cost)
			spells.append(id)
	return true

## Highest tier among known spells (old spells count by their level).
func max_spell_tier(sch := "") -> int:
	var t := 0
	for s in schools:
		if sch != "" and s != sch:
			continue
		for sp in DBSkills.SCHOOLS.get(s, {}).get("spells", []):
			if sp.lvl <= schools[s].lvl:
				t = maxi(t, 1 if sp.lvl <= 1 else (2 if sp.lvl <= 3 else (3 if sp.lvl <= 5 else 4)))
	for id in spells:
		var e: Dictionary = DBAbilities.get_ab(id)
		if sch == "" or e.get("school", "") == sch:
			t = maxi(t, int(e.get("tier", 0)))
	return t

func tier_count(sch: String, tier: int) -> int:
	var n := 0
	for id in spells:
		var e: Dictionary = DBAbilities.get_ab(id)
		if e.get("school", "") == sch and int(e.get("tier", 0)) >= tier:
			n += 1
	return n

## Magic rank 0..8 from mastery and achievements — not from character level:
## Послушник → Ученик → Адепт → Опытный маг → Мастер школы → Верховный мастер
## → Архимаг → Легендарный архимаг.
func magic_rank() -> int:
	if schools.is_empty():
		return 0
	var best := 0
	var total := 0
	var bs := ""
	for s in schools:
		total += int(schools[s].lvl)
		if int(schools[s].lvl) > best:
			best = int(schools[s].lvl)
			bs = s
	var mt := max_spell_tier()
	var r := 1
	if best >= 4:
		r = 2
	if best >= 8 and mt >= 3:
		r = 3
	if best >= 12 and mt >= 4 and total >= 20:
		r = 4
	if r >= 4 and best >= 16 and tier_count(bs, 4) >= 2:
		r = 5
	if r >= 5 and best >= 20 and mt >= 5:
		r = 6
	var trials := 0
	for k in knowledge:
		if str(k).begins_with("trial_"):
			trials += 1
	if r >= 6 and best >= 24 and "cm_archmage_path" in class_skills and trials >= 1:
		r = 7
	if r >= 7 and mt >= 6:
		var second := 0
		for s in schools:
			if s != bs:
				second = maxi(second, int(schools[s].lvl))
		if second >= 20:
			r = 8
	return r

## NPCs: learn class skills and spells their mastery allows (never above
## max_tier; tiers V–VI only with the knowledge flags set by the spawner).
func auto_learn_abilities(max_tier := 3) -> void:
	for e in DBAbilities.class_skills(class_id):
		learn_ability(e.id)
	for s in schools:
		for e in DBAbilities.school_spells(s):
			if int(e.tier) <= max_tier:
				learn_ability(e.id)

func knows_school(s: String) -> bool:
	return schools.has(s)

func learn_school(s: String) -> bool:
	if schools.has(s):
		return false
	schools[s] = {"lvl": 1, "xp": 0, "pts": 1}
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
		d.pts = int(d.get("pts", 0)) + 1
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
		for sp in DBSkills.SCHOOLS.get(s, {}).get("spells", []):
			if sp.lvl <= schools[s].lvl:
				out.append(sp.id)
	for id in spells:
		if not id in out:
			out.append(id)
	return out

func known_actives(cat: String) -> Array:
	var out: Array = []
	for id in mastery_of(cat).nodes:
		if DBSkills.node(cat, id).get("type", "") == "active":
			out.append(id)
	for id in class_skills:
		if DBAbilities.get_ab(id).get("type", "") == "active" and not id in out:
			out.append(id)
	return out

## Fill empty slots with sensible defaults (actives first, then spells).
## Cataclysms are never put in automatically (they are prepared by hand).
func auto_slots(cat: String) -> Array:
	var s: Array = slots_for(cat)
	var pool: Array = known_actives(cat)
	var sp := known_spells()
	if cat == "staff":
		pool = sp + pool
	else:
		pool = pool + sp
	pool = pool.filter(func(id): return int(DBAbilities.get_ab(id).get("tier", 0)) < 6)
	var n := slot_count()
	for i in s.size():
		if s[i] != "" and not (s[i] in pool) and not (s[i] in known_spells() and int(DBAbilities.get_ab(s[i]).get("tier", 0)) == 6) and not str(s[i]).begins_with("art_"):
			s[i] = ""
	for id in pool:
		if id in s:
			continue
		for i in n:
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
		class_pts += 1
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
		"fame": fame, "companion": companion, "injuries": injuries, "pain_until": pain_until,
		"class_pts": class_pts, "class_skills": class_skills, "spells": spells, "knowledge": knowledge, "ab_page": ab_page,
		"saved_sets": saved_sets, "favorites": favorites, "vitals": vitals,
		"tech": tech, "tech_cats": tech_cats, "tech_models": tech_models, "tech_skills": tech_skills, "tech_pts": tech_pts, "tech_mem": tech_mem}

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
	class_skills = d.get("class_skills", [])
	class_pts = int(d.get("class_pts", level - class_skills.size()))   # older saves: one point per level
	spells = d.get("spells", [])
	knowledge = d.get("knowledge", {})
	ab_page = int(d.get("ab_page", 0))
	saved_sets = d.get("saved_sets", {})
	favorites = d.get("favorites", [])
	vitals = d.get("vitals", {})
	tech = d.get("tech", {})
	tech_cats = d.get("tech_cats", {})
	tech_models = d.get("tech_models", {})
	for k in tech_models:
		var mr: Dictionary = tech_models[k]
		mr["shots"] = int(mr.get("shots", 0))
	tech_skills = d.get("tech_skills", [])
	tech_pts = int(d.get("tech_pts", 0))
	tech_mem = d.get("tech_mem", {"eras": [0], "schemas": [], "training": [], "maint": []})
	for k2 in ["eras", "schemas", "training", "maint"]:
		if not tech_mem.has(k2):
			tech_mem[k2] = [0] if k2 == "eras" else []
	var eras_i: Array = []
	for e in tech_mem.eras:
		eras_i.append(int(e))
	tech_mem.eras = eras_i
	for sch in schools:
		if not schools[sch].has("pts"):
			schools[sch].pts = int(schools[sch].lvl)
		schools[sch].pts = int(schools[sch].pts)
