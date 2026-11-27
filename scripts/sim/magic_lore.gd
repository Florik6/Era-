class_name MagicLore
extends Node
## Where high magic comes from. Most people have no magic at all; every
## school has exactly one named archmage in the world, living in a town as
## a mentor. A mentor teaches the school, passes on the knowledge of the
## school's tier-V spell and, to a proven master, opens the school trial: a
## keeper of the school is summoned to an arena and must be defeated. The
## trial gives the trial mark, the treatise of the school's cataclysm and
## the era's reagent. Ancient treatises (tier V/VI knowledge) can also be
## found on bosses. All of this is saved with the world.

static var inst: MagicLore = null
const FIRST := ["Аэрин", "Морвен", "Талис", "Ирмар", "Селена", "Корвин", "Илдар", "Вейра", "Осрик", "Лиора", "Драмир", "Эльвен"]
const EPITHET := {"fire": "Пламенный", "ice": "Хладный", "lightning": "Громовержец", "dark": "Сумрачный", "spacetime": "Вне Времени",
	"earth": "Каменная Длань", "necro": "Хранитель Костей", "heal": "Милосердная", "air": "Вольный Ветер", "light": "Рассветный"}

var world
var archmages := {}        # school -> {name, sid, met, trial_done, taught: []}
var mentors := {}          # school -> NPC
var keepers := {}          # school -> trial keeper NPC
var stats := {"taught": 0, "trials_started": 0, "trials_won": 0, "treatises": 0}
var _t := 0.0

func setup(w) -> void:
	world = w
	inst = self
	archmages = Game.world_state.get("archmages", {})
	if w.get("gen") == null or w.gen == null:
		return
	if archmages.is_empty():
		var towns: Array = []
		for s in w.gen.settlements:
			if s.get("type", "village") in ["city", "castle", "town", "fort"]:
				towns.append(s)
		if towns.is_empty():
			towns = w.gen.settlements.duplicate()
		var r := RandomNumberGenerator.new()
		r.seed = hash(Profile.world_seed) ^ 0x5eed
		var i := 0
		for sch in DBAbilities.SCHOOL_ORDER:
			var nm: String = FIRST[r.randi() % FIRST.size()]
			if nm == "Селена":
				nm = "Селена"
			var sid: String = towns[i % towns.size()].id if not towns.is_empty() else ""
			archmages[sch] = {"name": "%s %s" % [nm, EPITHET[sch]], "sid": sid, "met": false, "trial_done": false, "taught": []}
			i += 1
	Game.world_state["archmages"] = archmages

func archmage_title(sch: String) -> String:
	return "Архимаг %s" % archmages.get(sch, {}).get("name", "?")

func _process(delta: float) -> void:
	_t += delta
	if _t < 2.0:
		return
	_t = 0.0
	if world == null or world.get("gen") == null or world.gen == null or world.player == null or not is_instance_valid(world.player):
		return
	var pp: Vector3 = world.player.global_position
	for sch in archmages:
		var m = mentors.get(sch)
		if m != null and is_instance_valid(m) and not m.is_dead:
			if m.global_position.distance_to(pp) > 160.0:
				m.queue_free()
				mentors.erase(sch)
			continue
		var s := _settlement(str(archmages[sch].sid))
		if s.is_empty():
			continue
		var c := Vector3(s.pos.x, 0, s.pos.y)
		if c.distance_to(Vector3(pp.x, 0, pp.z)) < 90.0:
			spawn_mentor(sch)

func _settlement(sid: String) -> Dictionary:
	if world.get("gen") == null or world.gen == null:
		return {}
	for s in world.gen.settlements:
		if s.id == sid:
			return s
	return {}

## The school's archmage appears near the town square (rare: one per school).
func spawn_mentor(sch: String, at = null) -> NPC:
	var m = mentors.get(sch)
	if m != null and is_instance_valid(m) and not m.is_dead:
		return m
	var s := _settlement(str(archmages.get(sch, {}).get("sid", "")))
	var pos: Vector3
	if at is Vector3:
		pos = at
	elif not s.is_empty():
		var an := float(hash(sch) % 628) / 100.0
		pos = Vector3(s.pos.x, 0, s.pos.y) + Vector3(cos(an), 0, sin(an)) * 9.0
	else:
		return null
	var n: NPC = world.spawner.spawn_villager(s if not s.is_empty() else {"id": "", "owner": ""}, pos, "mentor")
	n.display_name = archmage_title(sch)
	n.set_meta("school", sch)
	n.data.class_id = "mage"
	n.data.level = 30
	n.data.learn_school(sch)
	n.data.schools[sch].lvl = 28
	for e in DBAbilities.school_spells(sch):
		if int(e.tier) <= 5 and not e.id in n.data.spells:
			n.data.spells.append(e.id)
	var st := ItemDB.create("staff_oak", 3, 30, null, false)
	n.data.inv.add(st)
	n.data.inv.equip_item(st)
	n.refresh_gear()
	n.hp = n.max_hp
	world.spawner.name_tag(n, DBSkills.SCHOOLS[sch].color)
	mentors[sch] = n
	return n

func mentor_dialog(n) -> void:
	var sch: String = n.get_meta("school", "fire")
	var pl = world.player
	var d: CharData = pl.data
	var am: Dictionary = archmages[sch]
	am.met = true
	var sd: Dictionary = DBSkills.SCHOOLS[sch]
	var era := Profile.current_era
	var cur: String = DBEras.era(era).currency
	var opts: Array = []
	var text := "«Я — %s, архимаг школы «%s». Таких, как я, в мире немного: магия высших ступеней не даётся даром»." % [am.name, sd.name]
	if not d.knows_school(sch):
		var price := 250 * (era + 1)
		opts.append({"text": "Начать обучение школе (%d %s)" % [price, cur], "cb": func():
			if d.gold < price:
				Events.notify.emit("Не хватает денег", Color(1.0, 0.5, 0.4))
				return
			d.gold -= price
			d.learn_school(sch)
			stats.taught += 1
			Events.banner.emit("Новая школа магии", sd.name, sd.color)})
	else:
		var t5: Dictionary = DBAbilities.school_spells(sch)[8]
		var t6: Dictionary = DBAbilities.school_spells(sch)[9]
		if not d.knowledge.has("know_" + t5.id):
			var price5 := 600 * (era + 1)
			if d.school_level(sch) >= 16:
				opts.append({"text": "Учение: «%s» (%d %s)" % [t5.name, price5, cur], "cb": func():
					if d.gold < price5:
						Events.notify.emit("Не хватает денег", Color(1.0, 0.5, 0.4))
						return
					d.gold -= price5
					teach(d, sch, t5.id)})
			else:
				text += "\n«Приходи, когда мастерство школы достигнет 16 — тогда я открою тебе «%s»»." % t5.name
		for e in DBAbilities.school_spells(sch):
			if e.get("need_know", false) and not d.knowledge.has("know_" + e.id) and not d.knowledge.has("tome_" + e.id) and d.school_level(sch) >= int(e.slvl):
				var pk := 300 * (era + 1)
				var eid: String = e.id
				opts.append({"text": "Учение: «%s» (%d %s)" % [e.name, pk, cur], "cb": func():
					if d.gold < pk:
						Events.notify.emit("Не хватает денег", Color(1.0, 0.5, 0.4))
						return
					d.gold -= pk
					teach(d, sch, eid)})
		if not d.knowledge.has("trial_" + sch):
			if d.school_level(sch) >= 20 and t5.id in d.spells:
				opts.append({"text": "Пройти испытание школы", "cb": func(): start_trial(sch, pl)})
			else:
				text += "\n«Испытание школы — для мастера: мастерство 20 и «%s»»." % t5.name
		else:
			var rg := AbilityExec.cataclysm_reagent()
			var pr := 400 * (era + 1)
			opts.append({"text": "Купить реагент «%s» (%d %s)" % [ItemDB.base(rg).get("name", rg), pr, cur], "cb": func():
				if d.gold < pr:
					Events.notify.emit("Не хватает денег", Color(1.0, 0.5, 0.4))
					return
				d.gold -= pr
				d.inv.add(ItemDB.create(rg, 0, 1))})
			if not d.knowledge.has("tome_" + t6.id):
				opts.append({"text": "Получить трактат «%s»" % t6.name, "cb": func(): give_treatise(d, t6.id)})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": n.display_name, "text": text, "portrait_color": sd.color, "options": opts})

func teach(d: CharData, sch: String, spell_id: String) -> void:
	d.knowledge["know_" + spell_id] = true
	d.knowledge["mentor_" + sch] = true
	archmages[sch].taught.append(spell_id)
	stats.taught += 1
	Chronicle.record("knowledge", [Game.player] if Game.player else [], {"text": "%s получил(а) знание «%s» от архимага %s." % [Profile.char.name, DBAbilities.get_ab(spell_id).name, archmages[sch].name], "extra": {"school": sch}})
	Events.notify.emit("Знание получено: «%s»" % DBAbilities.get_ab(spell_id).name, DBSkills.SCHOOLS[sch].color)

func give_treatise(d: CharData, spell_id: String) -> void:
	d.inv.add(treatise(spell_id))
	stats.treatises += 1
	Events.notify.emit("Получен трактат «%s»" % DBAbilities.get_ab(spell_id).name, Color(1.0, 0.85, 0.5))

## An ancient treatise item: reading it gives the knowledge of one spell.
static func treatise(spell_id: String) -> Dictionary:
	var it := ItemDB.create("arcane_treatise", 2, 1, null, false)
	it.knowledge = "tome_" + spell_id
	it.name = "Трактат «%s»" % DBAbilities.get_ab(spell_id).get("name", spell_id)
	return it

## The school trial: the keeper of the school appears in an arena ring.
func start_trial(sch: String, pl) -> NPC:
	var old = keepers.get(sch)
	if old != null and is_instance_valid(old) and not old.is_dead:
		return old
	var pos: Vector3 = pl.global_position + pl.facing * 12.0
	var k = world.spawner.spawn_enemy("trial_keeper", pos, maxi(8, pl.level))
	if k == null:
		return null
	k.display_name = "Хранитель школы «%s»" % DBSkills.SCHOOLS[sch].name
	k.set_meta("trial", sch)
	k.data.learn_school(sch)
	k.data.schools[sch].lvl = 22
	for e in DBAbilities.school_spells(sch):
		if int(e.tier) <= 4 and not e.id in k.data.spells:
			k.data.spells.append(e.id)
	k.max_hp = 900.0 + 60.0 * pl.level
	k.hp = k.max_hp
	k.add_aggro(pl, 120.0)
	world.spawner.name_tag(k, DBSkills.SCHOOLS[sch].color)
	MagicFX.ground_rune(pos, MagicFX.rune_style_for(sch), DBSkills.SCHOOLS[sch].color, 9.0, 8.0, 0.4, 1.2)
	keepers[sch] = k
	stats.trials_started += 1
	k.died.connect(func(_a, killer): _trial_won(sch, killer))
	Events.banner.emit("Испытание школы «%s»" % DBSkills.SCHOOLS[sch].name, "Одолейте Хранителя", DBSkills.SCHOOLS[sch].color)
	return k

func _trial_won(sch: String, _killer) -> void:
	var pl = world.player if world else null
	if pl == null or not is_instance_valid(pl):
		return
	var d: CharData = pl.data
	d.knowledge["trial_" + sch] = true
	archmages[sch].trial_done = true
	if d.knows_school(sch):
		d.schools[sch].pts = int(d.schools[sch].get("pts", 0)) + 3      # a proven master: three school points
	stats.trials_won += 1
	var t6: Dictionary = DBAbilities.school_spells(sch)[9]
	give_treatise(d, t6.id)
	d.inv.add(ItemDB.create(AbilityExec.cataclysm_reagent(), 0, 1))
	d.inv.add(ItemDB.create(AbilityExec.cataclysm_reagent(), 0, 1))
	Chronicle.record("trial", [pl], {"text": "%s прошёл(а) испытание школы «%s» и одолел(а) её Хранителя." % [Profile.char.name, DBSkills.SCHOOLS[sch].name], "extra": {"school": sch}})
	Events.banner.emit("Испытание пройдено", "Школа «%s»: путь к катаклизму открыт" % DBSkills.SCHOOLS[sch].name, DBSkills.SCHOOLS[sch].color)

## A boss may carry an ancient treatise of a tier V spell.
static func boss_treatise_drop(pos: Vector3) -> void:
	if Game.world == null or randf() > 0.35:
		return
	var sch: String = DBAbilities.SCHOOL_ORDER[randi() % DBAbilities.SCHOOL_ORDER.size()]
	var id: String = DBAbilities.school_spells(sch)[8].id
	if Game.world.get("loot") != null:
		Game.world.loot.spawn_drop(treatise(id), pos + Vector3(1.0, 0, 0.5))

func save_state() -> void:
	Game.world_state["archmages"] = archmages
