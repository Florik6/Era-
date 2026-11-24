class_name Spawner
extends Node
## Creates every kind of actor from data: era enemies, contenders (bots),
## villagers/traders/guards, faction soldiers, bosses, companions.

var world
var root: Node3D

func _init(w, r: Node3D) -> void:
	world = w
	root = r

func era_level_range() -> Vector2i:
	var ranges := [Vector2i(1, 12), Vector2i(8, 20), Vector2i(15, 28), Vector2i(22, 36), Vector2i(30, 48)]
	return ranges[clampi(Profile.current_era, 0, 4)]

func level_near_player(offset: int = 0) -> int:
	var pl := 1
	if Game.player and is_instance_valid(Game.player) and Game.player.data:
		pl = Game.player.data.level
	var r := era_level_range()
	return clampi(pl + offset + randi_range(-1, 1), r.x, r.y)

func _place(a: Node3D, pos: Vector3) -> void:
	if world.has_method("ground_height"):
		pos.y = world.ground_height(pos) + 0.2
	root.add_child(a)
	a.global_position = pos
	if a.has_method("reset_physics_interpolation"):
		a.reset_physics_interpolation()

func _rand_look(rng: RandomNumberGenerator, female: bool) -> Dictionary:
	return {"build": "normal", "skin": rng.randi() % 5, "hair": rng.randi() % 5, "hair_color": rng.randi() % 6,
		"beard": 0 if female else rng.randi() % 3, "cloth": rng.randi() % 7, "female": female}

## Era enemy from DBActors.ENEMIES (humanoids → NPC with BotBrain, creatures → Monster).
func spawn_enemy(id: String, pos: Vector3, lvl: int = -1) -> Actor:
	var d: Dictionary = DBActors.ENEMIES.get(id, {})
	if d.is_empty():
		return null
	if lvl < 0:
		lvl = level_near_player(d.get("lvl", 0))
	var scale_f := 1.0 + 0.11 * (lvl - 1)
	var a: Actor
	if d.rig == "humanoid":
		var n := NPC.new()
		n.role = "enemy"
		n.archetype = ["aggressive", "hunter", "opportunist", "cautious"][randi() % 4]
		n.can_loot = d.team == "bandit"
		var cd := CharData.new()
		cd.level = lvl
		cd.class_id = "mage" if d.ai == "caster" else ("archer" if d.ai == "ranged" else "warrior")
		var weapons: Array = d.get("weapons", [])
		if not weapons.is_empty():
			var wid: String = weapons[randi() % weapons.size()]
			if d.ai == "ranged":
				for w in weapons:
					if ItemDB.base(w).get("cat", "") in ["bow", "firearm"]:
						wid = w
						break
			var w_it := ItemDB.create(wid, 0 if not d.get("elite", false) else 2, lvl, null, false)
			cd.inv.add(w_it)
			cd.inv.equip_item(w_it)
			var cat: String = ItemDB.base(wid).get("cat", "sword")
			cd.mastery_of(cat).lvl = mini(12, lvl / 2 + 1)
			cd.mastery_of(cat).pts = cd.mastery_of(cat).lvl
			for w2 in weapons:
				if w2 != wid and randf() < 0.5:
					cd.inv.add(ItemDB.create(w2, 0, lvl, null, false))
		if d.has("offhand"):
			var o := ItemDB.create(d.offhand, 1, lvl, null, false)
			cd.inv.add(o)
			cd.inv.equip_item(o)
		for s in d.get("spells", []):
			var sp := DBSkills.spell(s)
			if not sp.is_empty():
				cd.learn_school(sp.school)
				cd.schools[sp.school].lvl = maxi(cd.schools[sp.school].lvl, sp.lvl + 1)
		cd.auto_learn()
		if randf() < 0.5:
			cd.inv.add(ItemDB.create("potion_hp", 0, 1))
		n.data = cd
		var look := _rand_look(Game.rng, randf() < 0.25)
		if d.get("skeleton", false):
			look.build = "skeleton"
		elif d.get("robot", false):
			look.build = "robot"
			look.body = d.get("cloth", Color(0.55, 0.57, 0.6))
		look.cloth_color = d.get("cloth", Color(0.4, 0.35, 0.3))
		look.armor = d.get("armor", "")
		look.hat = d.get("hat", "")
		look.glow = d.get("glow", Color(0, 0, 0, 0))
		look.metal = d.get("metal", false)
		var r := HumanoidRig.new()
		r.setup(look)
		n.set_rig(r)
		a = n
	else:
		var m := Monster.new()
		var cr: Node3D
		if d.rig in ["troll", "golem", "colossus"]:
			var hr := HumanoidRig.new()
			hr.setup({"build": "bulky" if d.rig == "troll" else d.rig, "body": d.get("body", Color(0.5, 0.5, 0.5)), "scale": d.get("scale", 1.4),
				"metal": d.get("metal", false), "hair": 0, "glow": d.get("glow", Color(0, 0, 0, 0))})
			cr = hr
		else:
			var c := CreatureRig.new()
			c.setup({"rig": d.rig, "body": d.get("body", Color(0.5, 0.5, 0.5)), "scale": d.get("scale", 1.0), "metal": d.get("metal", false), "glow": d.get("glow", Color(0.8, 1.0, 1.0))})
			cr = c
		m.set_rig(cr)
		m.spells = d.get("spells", [])
		m.proj_kind = d.get("proj", "")
		m.base_dmg = d.get("dmg", 10.0)
		m.natural_dtype = d.get("dtype", "slash")
		m.natural_range = 1.8 * d.get("scale", 1.0) + (0.6 if d.rig in ["troll", "golem"] else 0.0)
		m.stats = {"armor": 3.0 + lvl * 1.5 + (10.0 if d.get("metal", false) else 0.0)}
		a = m
	a.def_id = id
	a.display_name = d.name
	a.team = d.get("team", "monster")
	a.level = lvl
	a.elite = d.get("elite", false)
	a.resist = d.get("res", {})
	a.base_speed = 4.8 * d.get("speed", 1.0)
	a.max_hp = d.hp * scale_f
	if a is Monster:
		a.stats["base_hp"] = a.max_hp
	_place(a, pos)
	if a is NPC:
		a.base_hp_override = d.hp * scale_f
		a.refresh_gear()
	a.hp = a.max_hp
	if id == "mimic" and a.rig is CreatureRig:
		a.rig.set_dormant(false)
		Audio.play_sfx("mimic", pos)
		a.knockback = Vector3.ZERO
	return a

## A contender: autonomous slither-style competitor with full progression.
func spawn_bot(rec: Dictionary, pos: Vector3) -> NPC:
	var n := NPC.new()
	n.role = "bot"
	n.team = "bot"
	n.actor_id = rec.id
	n.record = rec
	n.archetype = rec.get("archetype", "explorer")
	n.relic_hunter = rec.get("relic_hunter", false)
	n.dialog_kind = "bot"
	n.hunting_player = rec.get("hunter", false)
	n.faction_id = rec.get("faction", "")
	var cd := CharData.new()
	if rec.has("data") and rec.data.size() > 0:
		cd.from_dict(rec.data)
	else:
		cd.name = rec.name
		cd.setup_class(rec.get("class_id", "warrior"))
		cd.level = rec.get("level", 1)
		for b in ItemDB.CLASS_KITS.get(cd.class_id, []):
			var it := ItemDB.create(b, 0, cd.level, null, false)
			cd.inv.add(it)
			if ItemDB.base(b).slot in ItemDB.SLOTS:
				cd.inv.equip_item(it)
		cd.auto_learn()
	n.data = cd
	n.display_name = rec.name
	n.title = rec.get("title", "")
	var look: Dictionary = rec.get("look", {})
	if look.is_empty():
		look = _rand_look(Game.rng, rec.get("female", false))
		rec.look = look
	var r := HumanoidRig.new()
	r.setup(look)
	n.set_rig(r)
	_place(n, pos)
	n.refresh_gear()
	n.hp = n.max_hp * clampf(rec.get("hp_frac", 1.0), 0.3, 1.0)
	n.mana = n.max_mana
	if rec.get("legend", false):
		_legend_aura(n)
	return n

func _legend_aura(n: Actor) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.35)
	l.light_energy = 0.8
	l.omni_range = 3.5
	l.position = Vector3(0, 1.0, 0)
	l.shadow_enabled = false
	n.add_child(l)

func spawn_villager(settlement: Dictionary, pos: Vector3, role: String = "villager") -> NPC:
	var n := NPC.new()
	n.role = role
	n.team = "neutral"
	n.faction_id = settlement.get("owner", "")
	n.settlement_id = settlement.get("id", "")
	n.home = pos
	n.can_loot = false
	n.dialog_kind = "trader" if role == "trader" else ("guard" if role == "guard" else "villager")
	var rng := Game.rng
	var female := rng.randf() < 0.45
	var cd := CharData.new()
	cd.name = DBActors.rand_name(Profile.current_era, female, rng)
	cd.level = level_near_player(0)
	cd.class_id = "warrior"
	if role == "guard":
		var fdef: Dictionary = DBEras.faction(n.faction_id)
		var wid: String = fdef.get("units", {}).get("infantry", "spear_iron") if not fdef.is_empty() else ["spear_iron", "halberd", "rifle_lever", "carbine", "pulse_rifle"][Profile.current_era]
		if wid == "":
			wid = "sword_iron"
		var w := ItemDB.create(wid, 1, cd.level, null, false)
		cd.inv.add(w)
		cd.inv.equip_item(w)
		var armor_ids := ["armor_chain", "armor_cuirass", "armor_coat", "vest_kevlar", "armor_energy"]
		var ar := ItemDB.create(armor_ids[clampi(Profile.current_era, 0, 4)], 1, cd.level, null, false)
		cd.inv.add(ar)
		cd.inv.equip_item(ar)
		cd.mastery_of(ItemDB.base(wid).get("cat", "spear")).lvl = 6
		n.archetype = "defender"
	else:
		n.archetype = "cautious"
	n.data = cd
	n.display_name = cd.name + (" (стражник)" if role == "guard" else (" (торговец)" if role == "trader" else ""))
	var look := _rand_look(rng, female)
	if role == "trader":
		look.cloth = 6
	var r := HumanoidRig.new()
	r.setup(look)
	n.set_rig(r)
	_place(n, pos)
	n.refresh_gear()
	n.hp = n.max_hp
	return n

## Faction soldier with a war role.
func spawn_soldier(fid: String, unit: String, pos: Vector3, lvl: int, rec: Dictionary = {}) -> NPC:
	var f: Dictionary = DBEras.faction(fid)
	var n := NPC.new()
	n.role = "soldier"
	n.team = "f_" + fid
	n.faction_id = fid
	n.unit_role = unit
	n.archetype = "defender" if unit != "scout" else "hunter"
	n.dialog_kind = "faction"
	var cd := CharData.new()
	var female := randf() < 0.3
	cd.name = rec.get("name", DBActors.rand_name(Profile.current_era, female, Game.rng))
	cd.level = lvl
	var wid: String = f.get("units", {}).get(unit, "sword_iron")
	if wid == "":
		wid = f.units.infantry
	var w := ItemDB.create(wid, 1 if unit != "commander" else 3, lvl, null, false)
	cd.inv.add(w)
	cd.inv.equip_item(w)
	var cat: String = ItemDB.base(wid).get("cat", "sword")
	cd.mastery_of(cat).lvl = clampi(lvl / 2 + 2, 2, 15)
	cd.mastery_of(cat).pts = cd.mastery_of(cat).lvl
	if unit == "mage" or cat == "staff":
		var schools := ["fire", "ice", "lightning", "dark", "spacetime"]
		var s: String = schools[randi() % 3]
		cd.learn_school(s)
		cd.schools[s].lvl = clampi(lvl / 3 + 1, 1, 8)
	var armor_ids := [["armor_leather", "armor_chain", "armor_plate"], ["armor_doublet", "armor_cuirass", "armor_cuirass"], ["armor_coat", "armor_coat", "armor_steam"], ["armor_jacket", "vest_kevlar", "vest_kevlar"], ["armor_energy", "armor_energy", "exo_frame"]]
	var tier := 2 if unit in ["heavy", "commander"] else (0 if unit in ["scout", "archer", "mage"] else 1)
	var ar := ItemDB.create(armor_ids[clampi(Profile.current_era, 0, 4)][tier], 1, lvl, null, false)
	cd.inv.add(ar)
	cd.inv.equip_item(ar)
	cd.auto_learn()
	cd.inv.add(ItemDB.create("potion_hp", 0, 1))
	n.data = cd
	n.display_name = cd.name
	if unit == "commander":
		n.title = "Командир"
	var look := _rand_look(Game.rng, female)
	look.cloth_color = f.get("color", Color(0.5, 0.5, 0.5)).darkened(0.2)
	var r := HumanoidRig.new()
	r.setup(look)
	n.set_rig(r)
	if rec.size() > 0:
		n.record = rec
		n.actor_id = rec.id
	_place(n, pos)
	n.refresh_gear()
	n.hp = n.max_hp
	return n

func spawn_boss(id: String, pos: Vector3, lvl: int = -1, times_escaped: int = 0) -> Boss:
	var d: Dictionary = DBActors.BOSSES.get(id, {})
	if d.is_empty():
		return null
	if lvl < 0:
		var r := era_level_range()
		lvl = clampi(maxi(level_near_player(1), r.x + d.get("lvl", 6)), r.x, r.y + 4)
	var b := Boss.new()
	b.times_escaped = times_escaped
	b.setup_boss(id, lvl + times_escaped * 3)
	if times_escaped > 0:
		b.display_name = d.name + " (Вернувшийся)"
		var extra := ["volley", "strikes", "nova", "summon", "blink"]
		for e in extra:
			if d.abilities.has(e) and not e in d.phases[0].use:
				b.bonus_abilities.append(e)
				break
	_place(b, pos)
	b.arena_center = b.global_position
	return b

## Era-appropriate companion: wolf / familiar / mechanical helper / drone.
func spawn_companion(owner_a: Actor, pos: Vector3) -> Monster:
	var kinds := [["wolf", "Волк-спутник"], ["wraith", "Фамильяр"], ["spider", "Механический помощник"], ["drone", "Боевой дрон"], ["drone", "Тактический дрон"]]
	var k: Array = kinds[clampi(Profile.current_era, 0, 4)]
	var m := Monster.new()
	var c := CreatureRig.new()
	var col = [Color(0.55, 0.5, 0.45), Color(0.4, 0.8, 1.0, 0.7), Color(0.75, 0.6, 0.35), Color(0.3, 0.35, 0.3), Color(0.8, 0.85, 0.95)][clampi(Profile.current_era, 0, 4)]
	c.setup({"rig": k[0], "body": col, "scale": 0.7 if k[0] == "spider" else (0.8 if k[0] == "wraith" else 1.0), "metal": Profile.current_era >= 2, "glow": Color(0.5, 0.9, 1.0)})
	m.set_rig(c)
	m.is_companion = true
	m.companion_kind = k[0]
	m.owner_actor = owner_a
	m.team = "player"
	m.actor_id = "companion"
	var cd: Dictionary = Profile.char.companion
	if cd.is_empty():
		cd = {"name": k[1], "lvl": 1, "xp": 0}
		Profile.char.companion = cd
	m.display_name = cd.name
	m.level = maxi(1, owner_a.level - 2 + int(cd.lvl))
	m.max_hp = 80.0 * (1.0 + 0.15 * (m.level - 1))
	m.stats = {"armor": 5.0 + m.level, "base_hp": m.max_hp}
	m.base_dmg = 8.0 * (1.0 + 0.1 * (m.level - 1))
	m.base_speed = 6.2
	m.natural_range = 2.0
	if k[0] == "drone":
		m.proj_kind = "pulse" if Profile.current_era >= 4 else "bullet"
	if k[0] == "wraith":
		m.spells = ["frostbolt", "spark"]
		m.natural_dtype = "ice"
	_place(m, pos)
	m.hp = m.max_hp
	return m
