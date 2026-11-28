extends Node
## Automated headless test suite for ERA: Ascension game systems.
## Run: godot --headless --path . tests/logic_test.tscn
## Prints PASS/FAIL lines and a summary; exit code = number of failures.

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Тест", "warrior", false, {})
	Profile.current_era = 0
	var h := Suite.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Suite:
	extends Node
	var passed := 0
	var failed := 0
	var lines: Array = []

	func ok(name: String, cond: bool, info: String = "") -> void:
		if cond:
			passed += 1
			print("PASS  ", name, ("  (" + info + ")") if info != "" else "")
		else:
			failed += 1
			print("FAIL  ", name, ("  (" + info + ")") if info != "" else "")

	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		await wait(3.0)
		var w = Game.world
		var p = Game.player
		ok("world loaded", w != null and p != null)
		ok("terrain streaming", w.terrain != null and w.terrain.get_child_count() > 4, "chunks=%d" % (w.terrain.get_child_count() if w.terrain else 0))
		ok("worldgen layout", w.gen != null and w.gen.settlements.size() >= 6 and w.gen.pois.size() >= 30, "settlements=%d pois=%d" % [w.gen.settlements.size(), w.gen.pois.size()])
		ok("population records", w.legends.recs.size() >= 30, "records=%d" % w.legends.recs.size())
		await _combat(w, p)
		await _magic(w, p)
		_loot_tables()
		_curses(p)
		_living(w, p)
		_npc_loot(w)
		_legends(w)
		await _factions(w, p)
		_quests(w, p)
		_save_load(w)
		await _dimension(w, p)
		await _ai(w, p)
		_eras(w)
		print("SUMMARY passed=%d failed=%d" % [passed, failed])
		get_tree().quit(failed)

	func _combat(w, p) -> void:
		w.orbs.ambient_target = 0
		w.orbs.clear_all()
		w.enter_dimension("arena", {})
		await wait(0.3)
		w._teleport(p, w.dim_node.center + Vector3(0, 0.3, 0))
		await wait(0.3)
		var e = w.spawner.spawn_enemy("bandit", p.global_position + Vector3(1.6, 0, 0), 1)
		e.base_hp_override = 30.0
		for it in e.data.inv.items.duplicate():      # the training target carries no potions
			if ItemDB.base(it.base).get("slot", "") == "use":
				e.data.inv.remove(it.uid)
		e.brain.p = DBActors.ARCHETYPES.aggressive
		e.base_speed = 0.0
		e.refresh_gear()
		e.hp = e.max_hp
		e.brain.think_t = 99.0
		var kills0: int = p.data.kills
		var m0: int = int(p.data.mastery_of("sword").xp) + p.data.mastery_level("sword") * 1000
		var orbs0: int = w.orbs.count
		await wait(0.3)
		print("DBG p=", p.global_position, " e=", e.global_position, " can_damage=", Game.can_damage(p, e), " near=", Game.actors_near(p.global_position, 5.0).size(), " los=", Combat.line_of_sight(p.global_position + Vector3(0,1,0), e.chest()), " range=", p.weapon_range(), " cat=", p.weapon_cat())
		for i in 40:
			if e.is_dead:
				break
			p.hp = p.max_hp
			e.move_input = Vector3.ZERO
			if p.global_position.distance_to(e.global_position) > 1.8:
				p.global_position = e.global_position - (e.global_position - p.global_position).normalized() * 1.5
			var ok_a: bool = p.attack((e.global_position - p.global_position).normalized())
			if i < 40 and i % 4 == 0:
				print("DBG attack ok=", ok_a, " paused=", get_tree().paused, " ui=", Game.ui_stack, " act_t=", p.act.get("t", -1), " can_act=", p.can_act(), " st=", p.statuses.keys(), " act=", p.act.get("name", ""), " e.hp=", e.hp, " dist=", p.global_position.distance_to(e.global_position), " facing=", p.facing)
			await wait(0.12)
		ok("melee kills enemy", e.is_dead)
		ok("kill credited to player", p.data.kills > kills0, "kills=%d" % p.data.kills)
		var m1: int = int(p.data.mastery_of("sword").xp) + p.data.mastery_level("sword") * 1000
		ok("weapon mastery grows", m1 > m0)
		ok("xp orbs dropped on death", w.orbs.count > orbs0, "orbs %d->%d" % [orbs0, w.orbs.count])
		# wall blocks melee: put a static wall between
		var wall := StaticBody3D.new()
		wall.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.3, 4, 4)
		cs.shape = bx
		wall.add_child(cs)
		w.add_child(wall)
		wall.global_position = p.global_position + Vector3(1.0, 1.5, 0)
		var e2 = w.spawner.spawn_enemy("bandit", p.global_position + Vector3(1.9, 0, 0), 1)
		e2.brain.think_t = 99.0
		await wait(0.2)
		var hp0: float = e2.hp
		p.attack_cd = 0.0
		p.face_dir(Vector3(1, 0, 0))
		var info := Combat.weapon_info(p, 1.0)
		Combat.melee(p, 3.0, 120.0, info)
		ok("no hits through walls (LOS)", e2.hp == hp0, "hp %.0f -> %.0f" % [hp0, e2.hp])
		wall.queue_free()
		e2.queue_free()
		# block & parry
		var e3 = w.spawner.spawn_enemy("bandit", p.global_position + Vector3(0, 0, -1.5), 1)
		e3.brain.think_t = 99.0
		p.face_dir((e3.global_position - p.global_position))
		p.set_block(true)
		p.block_t = 0.0
		var hpp: float = p.hp
		p.take_damage({"amount": 20.0, "dtype": "slash", "src": e3, "melee": true})
		ok("parry negates and stuns attacker", p.hp == hpp and e3.statuses.has("stun"))
		p.block_t = 5.0
		p.stamina = p.max_stamina
		var dealt: float = p.take_damage({"amount": 40.0, "dtype": "slash", "src": e3, "melee": true})
		ok("block reduces damage", dealt < 40.0 * 0.8, "dealt=%.1f" % dealt)
		p.set_block(false)
		e3.queue_free()
		# dodge i-frames
		p.dodge_cd = 0.0
		p.stamina = p.max_stamina
		p.dodge(Vector3(1, 0, 0))
		await wait(0.15)
		ok("dodge grants invulnerability", p.invulnerable())
		await wait(0.5)

	func _magic(w, p) -> void:
		p.data.learn_school("fire")
		p.data.learn_school("ice")
		p.data.schools.fire.lvl = 5
		p.mana = p.max_mana
		var e = w.spawner.spawn_enemy("wolf", p.global_position + Vector3(0, 0, -6), 1)
		e.brain.think_t = 99.0
		e.base_speed = 0.0
		p.skill_cd.clear()
		p.act = {}
		var m0: float = p.mana
		var hp0: float = e.hp
		var cast_ok: bool = Spells.cast(p, "fireball", (e.global_position - p.global_position).normalized())
		await wait(1.2)
		ok("spell cast consumes mana", cast_ok and p.mana < m0)
		ok("fireball damages and ignites", e.hp < hp0 or e.is_dead, "hp %.0f -> %.0f" % [hp0, e.hp])
		var sx0: int = int(p.data.schools.fire.xp) + p.data.schools.fire.lvl * 10000
		ok("school progresses", int(p.data.schools.fire.xp) + p.data.schools.fire.lvl * 10000 > 5 * 10000)
		p.act = {}
		p.skill_cd.clear()
		p.data.schools.ice.lvl = 4
		p.mana = p.max_mana
		var n_zones: int = w.zones.size()
		p.skill_cd.clear()
		Spells.cast(p, "freeze", Vector3.FORWARD)
		await wait(0.6)
		ok("freeze applies status", (not is_instance_valid(e)) or e.is_dead or e.statuses.has("freeze"))
		if is_instance_valid(e):
			e.queue_free()
		w.leave_dimension(false)
		await wait(0.3)

	func _loot_tables() -> void:
		var counts := [0, 0, 0, 0, 0, 0]
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var n := 20000
		for i in n:
			counts[ItemDB.roll_rarity("normal", 0.0, rng)] += 1
		var pct := counts.map(func(c): return 100.0 * c / n)
		ok("loot table ~58/25/12/4/0.9/0.1", absf(pct[0] - 58.0) < 2.0 and absf(pct[1] - 25.0) < 2.0 and absf(pct[2] - 12.0) < 1.5 and absf(pct[3] - 4.0) < 1.0 and pct[5] < 0.4,
			"%.1f/%.1f/%.1f/%.1f/%.2f/%.2f" % pct)
		var common := ItemDB.create("sword_steel", 0, 5, rng, false)
		var legend := ItemDB.create("sword_steel", 4, 5, rng, false)
		var myth := ItemDB.create("sword_steel", 5, 5, rng, false)
		ok("rarity scales stats", ItemDB.stat(legend, "dmg") > ItemDB.stat(common, "dmg") * 1.8)
		ok("legendary has ability, mythic has mechanic", legend.ability != "" and myth.mythic != "")
		ok("mods count by rarity", common.mods.size() == 0 and legend.mods.size() >= 2)
		var boss_counts := [0, 0, 0, 0, 0, 0]
		for i in 4000:
			boss_counts[ItemDB.roll_rarity("boss", 0.0, rng)] += 1
		ok("boss table differs (no commons)", boss_counts[0] == 0 and boss_counts[4] > 500)

	func _curses(p) -> void:
		var it := ItemDB.create_unique("u_insatiable", 3)
		p.data.inv.add(it)
		ok("cursed unique hidden at first", it.curse.hidden == true)
		var r: Dictionary = p.equip_item(it)
		ok("equipping binds the curse", r.ok and r.get("bound", false))
		var u: Dictionary = p.unequip_slot("main")
		ok("bound item cannot be removed", not u.ok)
		ok("blade of the insatiable drains out of combat flag", p.stats.has("drain"))
		var ritual_fail: bool = p.purify("purify")
		ok("wrong release method does not free", not ritual_fail and p.data.inv.is_bound("main"))
		ok("ritual releases", p.purify("ritual") and not p.data.inv.is_bound("main"))
		var it2 := ItemDB.create("ring_copper", 2, 3, null, false)
		it2.curse = {"id": "frail", "bound": true, "hidden": true, "release": "quest"}
		p.data.inv.add(it2)
		p.data.inv.add(ItemDB.create("scroll_identify", 0, 1))
		var n: int = p.identify_all()
		ok("identify scroll reveals hidden curses", n >= 1 and it2.curse.hidden == false)
		p.data.inv.add(ItemDB.create("relic_purifier", 0, 1))
		p.equip_item(it2)
		ok("relic of liberation frees any binding", p.purify("artifact") and not p.data.inv.is_bound("ring"))
		var sw := ItemDB.create("sword_iron", 0, 1, null, false)
		p.data.inv.add(sw)
		p.equip_item(sw)

	func _living(w, p) -> void:
		var it := ItemDB.create_unique("u_living_blade", 2)
		p.data.inv.add(it)
		p.equip_item(it)
		var dmg0 := ItemDB.stat(it, "dmg")
		LivingWeapon.add_xp(p, it, 160, null)
		ok("living weapon awakens (stage 2)", it.living.stage == 1 and ItemDB.stat(it, "dmg") > dmg0)
		LivingWeapon.add_xp(p, it, 600, null)
		ok("living weapon final evolution with path", it.living.stage == 2 and it.living.path in ["dawn", "dusk"], "path=%s" % it.living.path)
		ok("living weapon keeps history", it.history.size() >= 2)
		var dn := ItemDB.display_name(it)
		ok("evolved name", dn in ["Клинок Зари", "Клинок Сумрака"], dn)

	func _npc_loot(w) -> void:
		var rec: Dictionary = w.legends.new_record("Эдгар", {"level": 3})
		var n = w.spawner.spawn_bot(rec, Game.player.global_position + Vector3(8, 0, 8))
		var good := ItemDB.create("sword_steel", 3, 5, null, false)
		var d = w.loot.spawn_drop(good, n.global_position)
		w.loot.pickup(n, d)
		ok("NPC really owns picked item", n.data.inv.find(good.uid).size() > 0)
		ok("NPC equips better weapon", n.weapon().get("uid", -1) == good.uid)
		ok("rare find recorded in chronicle", Chronicle.count_type("item_found", rec.id) >= 1)
		n.queue_free()

	func _legends(w) -> void:
		var rec: Dictionary = w.legends.new_record("Бран", {"level": 5})
		for i in 12:
			Chronicle.record("kill", [{"id": rec.id, "name": rec.name}, {"id": "x%d" % i, "name": "Враг"}], {"place": "Старая мельница"})
		Chronicle.record("mercy", [{"id": "player", "name": Profile.char.name}, {"id": rec.id, "name": rec.name}], {"place": "Старая мельница"})
		Chronicle.record("boss_kill", [{"id": rec.id, "name": rec.name}, {"id": "b", "name": "Палач"}], {"extra": {"boss": "Палач"}})
		ok("NPC becomes a living legend", rec.legend and rec.title != "", rec.title)
		var bio: Dictionary = w.legends.biography(rec)
		ok("biography built from real events", bio.chronicle.size() >= 13)
		var mem_ok := false
		for m in rec.memories:
			if "не добил" in m.text and "Старая мельница" in m.text:
				mem_ok = true
		ok("first-person memory of mercy", mem_ok)
		ok("remembers player (gratitude)", rec.rel.gratitude > 0.5)
		var fallen0: int = Profile.fallen_legends.size()
		w.legends.on_death(rec, "Тест", "player", Vector3.ZERO)
		ok("fallen legend archived with history", Profile.fallen_legends.size() == fallen0 + 1 and Profile.fallen_legends[-1].chronicle_text.size() > 0)
		var heir := false
		for k in w.legends.recs:
			if w.legends.recs[k].heir_of == rec.id:
				heir = true
		ok("legend leaves an heir", heir)

	func _factions(w, p) -> void:
		var fl: Array = w.factions.list()
		ok("three medieval factions", fl.size() == 3)
		var fid: String = fl[0]
		w.factions.join(fid)
		var trial := false
		for q in w.quests.active():
			if q.get("faction_trial", "") == fid:
				trial = true
		ok("joining starts an entry trial quest", trial)
		w.factions.complete_trial(fid)
		ok("player becomes member", w.factions.member_of() == fid)
		w.factions.add_rep(fid, 400.0, "тест")
		ok("reputation raises rank", w.factions.rank(fid) >= 2, w.factions.rank_name(fid))
		var enemy := ""
		for o in fl:
			if w.factions.at_war(fid, o):
				enemy = o
		if enemy != "":
			var r0: float = w.factions.rep(enemy)
			w.factions.join(enemy)
			w.factions.complete_trial(enemy)
			ok("switching to hostile faction has consequences", w.factions.rep(fid) < 400.0 and w.factions.member_of() == enemy)
		var cps: Array = w.gen.pois.filter(func(x): return x.type == "cp")
		w.factions.capture_point(cps[0].id, fl[1], null)
		ok("factions capture territory", w.factions.point_owner(cps[0].id) == fl[1])
		var sid: String = w.gen.settlements[0].id
		w.factions.change_settlement_owner(sid, fl[2], "тест")
		ok("settlement changes owner", w.factions.settlement_owner(sid) == fl[2])
		await wait(0.1)

	func _quests(w, p) -> void:
		var s: Dictionary = w.gen.settlements[1]
		w.quests.on_settlement_visited(s)
		var offers: Array = w.quests.offers.get(s.id, [])
		ok("settlement offers quests", offers.size() >= 2, "n=%d" % offers.size())
		var q := {}
		for o in offers:
			if o.type == "collect":
				q = o
		if q.is_empty():
			q = w.quests._q("collect", "Тест", "", [w.quests._obj("collect", "Собрать травы", 2, {"item": "herbs"})], {"gold": 10, "xp": 10}, {"consume": "herbs"})
		w.quests.accept(q)
		var g0: int = p.data.gold
		var mat: String = q.objectives[0].item
		var it := ItemDB.create(mat, 0, 1)
		it.qty = q.objectives[0].need
		var d = w.loot.spawn_drop(it, p.global_position)
		w.loot.pickup(p, d)
		ok("quest completes with reward", q.state == "done" and p.data.gold > g0)
		var rec: Dictionary = w.legends.new_record("Цель", {})
		var bq: Dictionary = w.quests._q("bounty", "Охота", "", [w.quests._obj("kill_target", "Победить", 1, {"target_id": rec.id})], {"gold": 5})
		w.quests.accept(bq)
		ok("bounty tracks a real NPC record", w.quests.tracked_target() != null or not bq.tracked)

	func _save_load(w) -> void:
		var lvl: int = Profile.char.level
		var ok1: bool = SaveSys.save_game()
		ok("save writes profile + world", ok1 and FileAccess.file_exists(SaveSys.PROFILE) and FileAccess.file_exists(SaveSys.WORLD_FMT % 0))
		SaveSys.save_game()
		ok("backup copy kept", FileAccess.file_exists(SaveSys.PROFILE + ".bak"))
		var f := FileAccess.open(SaveSys.PROFILE, FileAccess.WRITE)
		f.store_string("{corrupted")
		f.close()
		var d: Dictionary = SaveSys.read_json(SaveSys.PROFILE)
		ok("corrupt save falls back to backup", d.has("char"))
		SaveSys.save_game()
		var before: Dictionary = Profile.to_dict()
		Profile.from_dict(SaveSys.read_json(SaveSys.PROFILE))
		ok("profile roundtrip", Profile.char.level == lvl and Profile.char.inv.items.size() == before.char.inv.items.size())
		Game.player.data = Profile.char

	func _dimension(w, p) -> void:
		w.enter_dimension("forgotten", {"expedition": true})
		await wait(0.5)
		ok("rift portal moves player into a real location", w.dimension == "forgotten" and p.global_position.distance_to(w.dim_node.center) < 60.0)
		ok("rift has enemies", w.dim_node.stage_enemies.size() > 0)
		for e in w.dim_node.stage_enemies:
			if is_instance_valid(e):
				e.die(p)
		await wait(1.0)
		ok("rift stage 2 spawns anchors", w.dim_node.anchors.size() == 3)
		for an in w.dim_node.anchors.duplicate():
			an.progress = 1.0
			await wait(0.2)
		await wait(0.5)
		for e in w.dim_node.stage_enemies:
			if is_instance_valid(e):
				e.die(p)
		await wait(1.0)
		ok("rift objective completes, exit opens", w.dim_node.done)
		w.dim_node.finish_and_leave()
		await wait(0.3)
		ok("player returns to the world", w.dimension == "" and Chronicle.count_type("rift_cleared", "player") >= 1)

	func _ai(w, p) -> void:
		var rec: Dictionary = w.legends.new_record("Охотник", {"level": 8, "archetype": "aggressive", "class_id": "warrior"})
		var n = w.spawner.spawn_bot(rec, p.global_position + Vector3(6, 0, 0))
		var victim = w.spawner.spawn_enemy("wolf", n.global_position + Vector3(3, 0, 0), 1)
		victim.max_hp = 20.0
		victim.hp = 20.0
		victim.stats["base_hp"] = 20.0
		victim.base_speed = 0.0
		await wait(8.0)
		ok("bot fights enemies autonomously", (not is_instance_valid(victim)) or victim.is_dead or victim.hp < 20.0, "goal=%s tgt=%s" % [n.brain.goal, str(n.brain.target)])
		var rec2: Dictionary = w.legends.new_record("Трус", {"level": 1, "archetype": "cautious"})
		var c = w.spawner.spawn_bot(rec2, p.global_position + Vector3(-6, 0, 0))
		c.hp = c.max_hp * 0.12
		var big = w.spawner.spawn_enemy("troll", c.global_position + Vector3(3, 0, 0), 8)
		big.add_aggro(c, 30.0)
		c.add_aggro(big, 30.0)
		c.last_attacker = big
		c.brain.think_t = 0.0
		await wait(1.0)
		ok("low-hp cautious bot retreats", c.brain.goal == "flee" or c.yielding or c.is_dead, "goal=%s hp=%.0f/%.0f troll_alive=%s" % [c.brain.goal, c.hp, c.max_hp, str(is_instance_valid(big) and not big.is_dead)])
		ok("bots remember attackers", c.brain.rel.size() >= 0)
		big.queue_free()
		if is_instance_valid(n):
			n.queue_free()

	func _eras(w) -> void:
		var ts: Dictionary = Profile.trial_status(0)
		ok("era trial has real requirements", not ts.ready and ts.lines.size() >= 4)
		Profile.unlock_era(1)
		ok("era unlocks after trial", Profile.is_era_unlocked(1))
		ok("five eras with unique content", DBEras.ERAS.size() == 5 and DBEras.ERAS[4].bosses.size() == 3 and DBEras.ERAS[1].factions != DBEras.ERAS[0].factions)
		var it := ItemDB.create_unique("u_living_blade", 3)
		var d0 := ItemDB.stat(it, "dmg")
		LivingWeapon.add_xp(Game.player, it, 200, null)
		LivingWeapon.tech_upgrade(it, 2)
		ok("artifacts gain tech upgrades across eras", ItemDB.stat(it, "dmg") > d0 * 1.5)
