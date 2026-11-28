extends Node
## «Ascension of Power» — section 28 school tests:
## EARTH: structures rise and block, walls stop projectiles and break, the
##   golem follows and fights, the quake hits only its area, everything sinks
##   back (paths restored);
## NECROMANCY: summons, per-spell and per-owner limits, despawn without
##   corpses or kill credit, no copies of named NPCs, the chronicle intact;
## HEALING + HARDCORE: HP, the chosen body part, injury types, bleeding
##   stopped, wounds healed by their state, infection not cured by the wrong
##   spell, no endless healing, saves;
## plus resonance pairs, NPC casters (earth mage, necromancer, healer), town
## rules, mentors / trials / treatises, and a performance probe.
## Prints SCHOOLS_DONE pass=N fail=M.

func _ready() -> void:
	seed(31337)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Геомант", "mage", false, {"skin": 2, "hair": 2, "hair_color": 2, "beard": 0, "cloth": 1})
	Profile.world_seed = 919191
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, false, false, false).timeout
	func _ready() -> void:
		_run()

	func foe(id: String, pos: Vector3, hp := 4000.0, rooted := true):
		var m = Game.world.spawner.spawn_enemy(id, pos, 6)
		if m:
			m.max_hp = hp
			m.hp = hp
			if rooted:
				m.apply_status("root", 9999.0)
				# a rooted test target has no AI of its own (no stray fights)
				if m.get("brain") != null and m.brain.has_method("shutdown"):
					m.brain.shutdown()
					m.brain = null
		return m

	func ready_caster() -> void:
		var pl = Game.player
		pl.skill_cd.clear()
		pl.act = {}
		pl.mana = pl.max_mana
		pl.stamina = pl.max_stamina
		pl.statuses.erase("exhausted")
		AbilityExec.cataclysm_until = 0
		AbilityExec._high_until.clear()      # one high spell at a time (0.15.0)
		pl.mana_delay_t = 0.0

	func clean() -> void:
		for st in StoneStructure.live.duplicate():
			if is_instance_valid(st):
				st.queue_free()
		StoneStructure.live.clear()
		for z in Game.world.zones.duplicate():
			if is_instance_valid(z):
				z.queue_free()

	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		TimeFX.inst.set_base(2.0)
		var d: CharData = pl.data
		d.level = 30
		pl.recalc_stats()
		for s in DBAbilities.SCHOOL_ORDER:
			d.learn_school(s)
			d.schools[s].lvl = 26
		d.class_skills.append("cm_archmage_path")
		for e in DBAbilities.of_kind("spell"):
			d.knowledge["tome_" + e.id] = true
			if not e.id in d.spells:
				d.spells.append(e.id)
		var st := ItemDB.create("staff_oak", 2, 20, null, false)
		d.inv.add(st)
		pl.equip_item(st)
		pl.recalc_stats()
		var fwd: Vector3 = pl.facing
		var side: Vector3 = fwd.cross(Vector3.UP)
		# ======================================================== EARTH
		clean()
		var target = foe("bandit", pl.global_position + fwd * 8.0)
		await wait(0.5)
		ready_caster()
		var n0 := StoneStructure.spawned
		ck("«Каменные копья» cast", pl.use_ability("e_stone_spears", fwd))
		await wait(1.2)
		ck("…six stone spikes rose", StoneStructure.spawned - n0 == 6, "%d" % (StoneStructure.spawned - n0))
		ck("…and hurt the foe on the line", target.hp < target.max_hp)
		var solid_spikes := StoneStructure.live.filter(func(x): return x.kind == "stone_spike" and x.solid).size()
		ck("…spikes are solid obstacles", solid_spikes >= 5, "%d" % solid_spikes)
		await wait(4.5)
		ck("…and sink back after their time (paths restored)", StoneStructure.live.filter(func(x): return is_instance_valid(x) and x.kind == "stone_spike").is_empty())
		# wall blocks a projectile
		clean()
		ready_caster()
		ck("«Стена бастиона» cast", pl.use_ability("e_bastion_wall", fwd))
		await wait(1.0)
		var walls := StoneStructure.live.filter(func(x): return x.kind == "stone_wall")
		ck("…five wall segments", walls.size() == 5, "%d" % walls.size())
		var archer = foe("bandit", pl.global_position + fwd * 9.0)
		await wait(0.3)
		var hp_before: float = pl.hp
		pl.statuses.erase("invuln")
		var arrow_info := {"amount": 40.0, "dtype": "pierce", "src": archer, "melee": false}
		var from: Vector3 = archer.chest()
		var p := Projectile.spawn(archer, from, (pl.chest() - from).normalized() * 40.0, arrow_info, "arrow", {"range": 20.0})
		await wait(0.8)
		ck("…an arrow from behind the wall does not reach the mage", pl.hp >= hp_before - 0.1, "%.0f→%.0f" % [hp_before, pl.hp])
		pl.apply_status("invuln", 999999.0)
		var wall0 = walls[2]
		wall0.take_hit(500.0, "blunt", archer)
		await wait(0.6)
		ck("…a wall segment can be broken", not is_instance_valid(wall0) or wall0._sinking)
		var ray_after := Combat.line_of_sight(pl.chest(), archer.chest())
		clean()
		await wait(0.5)
		ck("…after the wall is gone the line of fire is open again", Combat.line_of_sight(pl.chest(), archer.chest()))
		AbilityExec.despawn(archer)
		AbilityExec.despawn(target)
		# golem AI
		ready_caster()
		var enemy = foe("bandit", pl.global_position + fwd * 7.0 + side * 2.0, 3000.0, false)
		ck("«Голем хранителя» cast", pl.use_ability("e_guardian_golem", fwd))
		await wait(1.6)
		var golems := AbilityExec.live_summons(pl).filter(func(m): return m.def_id == "stone_golem")
		ck("…one stone golem", golems.size() == 1)
		var gl = golems[0] if not golems.is_empty() else null
		if gl:
			ck("…the golem is the mage's ally (team summon, owner)", gl.team == "summon" and gl.owner_actor == pl and not Game.can_damage(pl, gl))
			var ehp: float = enemy.hp
			enemy.add_aggro(pl, 60.0)
			pl.last_attacker = enemy
			pl.combat_t = 0.0
			await wait(8.0)
			var e_gone: bool = not is_instance_valid(enemy) or enemy.is_dead
			ck("…the golem goes for the foe and hits it", e_gone or enemy.hp < ehp, "%.0f→%.0f" % [ehp, -1.0 if e_gone else enemy.hp])
			ready_caster()
			pl.use_ability("e_guardian_golem", fwd)
			await wait(1.6)
			ck("…a second cast replaces the first golem (limit 1)", AbilityExec.live_summons(pl).filter(func(m): return m.def_id == "stone_golem").size() == 1)
		if is_instance_valid(enemy):
			AbilityExec.despawn(enemy)
		for m in AbilityExec.live_summons(pl):
			AbilityExec.despawn(m)
		# great quake
		clean()
		await wait(0.4)
		ready_caster()
		d.inv.add(ItemDB.create(AbilityExec.cataclysm_reagent(), 0, 1))
		d.ab_page = 1
		ck("quake prepared in the set", d.set_slot("staff", 1, 0, "e_great_quake") == "")
		var center: Vector3 = pl.global_position + fwd * 12.0
		var inside: Array = []
		var outside = foe("bandit", center + side * 22.0)
		for i in 3:
			inside.append(foe("bandit", center + Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * 4.0))
		var ally = Game.world.spawner.spawn_villager({"id": "", "owner": ""}, center + side * 3.0, "villager")
		await wait(0.5)
		var ally_hp: float = ally.hp
		var out_hp: float = outside.hp
		var in_hp := 0.0
		for f in inside:
			in_hp += f.hp
		var rg := d.inv.count(AbilityExec.cataclysm_reagent())
		ck("«Великое Землетрясение» cast", pl.use_ability("e_great_quake", fwd))
		ck("…the reagent is consumed", d.inv.count(AbilityExec.cataclysm_reagent()) == rg - 1)
		ck("…a second cataclysm cannot start meanwhile", AbilityExec.block_reason(pl, "f_sun_worshipper") != "")
		await wait(4.4)
		var cq: Dictionary = Cataclysm.last.get("quake", {})
		ck("…preparation: runes then rising slabs (%d)" % int(cq.get("slabs", 0)), int(cq.get("slabs", 0)) >= 5)
		await wait(2.6)
		var in_hp2 := 0.0
		for f in inside:
			in_hp2 += f.hp if is_instance_valid(f) and not f.is_dead else 0.0
		ck("…three readable shockwaves (%d)" % int(cq.get("waves", 0)), int(cq.get("waves", 0)) == 3)
		ck("…real damage inside the area", in_hp2 < in_hp * 0.85, "%.0f→%.0f" % [in_hp, in_hp2])
		ck("…nothing outside the area", outside.hp >= out_hp - 0.1)
		ck("…allies and townsfolk are not hurt", ally.hp >= ally_hp - 0.1)
		ck("…the caster is exhausted afterwards", pl.statuses.has("exhausted"))
		var slabs_now := StoneStructure.live.filter(func(x): return is_instance_valid(x) and x.kind == "slab").size()
		ck("…the arena is changed for a while (%d slabs)" % slabs_now, slabs_now >= 5)
		await wait(8.0)
		var slabs_left := StoneStructure.live.filter(func(x): return is_instance_valid(x) and x.kind == "slab" and not x._sinking).size()
		ck("…after ~10 s everything sinks back (navigation restored)", slabs_left == 0, "%d" % slabs_left)
		for f in inside + [outside]:
			if is_instance_valid(f):
				AbilityExec.despawn(f)
		if is_instance_valid(ally):
			ally.queue_free()
		d.ab_page = 0
		# ======================================================== NECROMANCY
		clean()
		ready_caster()
		var chron0 := Chronicle.events.size() if Chronicle.get("events") != null else -1
		var named = foe("bandit", pl.global_position + fwd * 5.0, 50.0)
		named.display_name = "Борис Именной"
		await wait(0.3)
		named.statuses.erase("root")
		Combat.deal(pl, named, {"amount": 9999.0, "dtype": "slash"})
		await wait(0.5)
		ck("a death nearby is remembered (cheaper raise)", AbilityExec.near_recent_death(pl.global_position, 10.0))
		var cost_near := AbilityExec.mana_cost(pl, DBAbilities.get_ab("n_raise_servant"))
		ck("…raise costs less near a fresh death", cost_near < float(DBAbilities.get_ab("n_raise_servant").mana))
		ck("«Поднятие слуги» cast", pl.use_ability("n_raise_servant", fwd))
		await wait(1.4)
		ready_caster()
		pl.use_ability("n_raise_servant", fwd)
		await wait(1.4)
		ready_caster()
		pl.use_ability("n_raise_servant", fwd)
		await wait(1.4)
		var servants := AbilityExec.live_summons(pl).filter(func(m): return m.def_id == "skeleton_minion")
		ck("…at most two servants (limit)", servants.size() == 2, "%d" % servants.size())
		var dup := false
		for m in AbilityExec.live_summons(pl):
			if m.display_name == named.display_name or (m.get("record") is Dictionary and not m.record.is_empty()):
				dup = true
		ck("…no copy of the dead named NPC is raised", not dup)
		ready_caster()
		pl.use_ability("n_burial_knight", fwd)
		await wait(1.6)
		ck("«Рыцарь Погребения» raised", AbilityExec.live_summons(pl).filter(func(m): return m.def_id == "bone_knight").size() == 1)
		ck("…owner limit holds (≤ %d)" % AbilityExec.MAX_SUMMONS_PER_OWNER, AbilityExec.live_summons(pl).size() <= AbilityExec.MAX_SUMMONS_PER_OWNER)
		var kills0: int = d.kills
		var corpses0 := 0
		for a in Game.actors_near(pl.global_position, 30.0):
			if a.is_dead:
				corpses0 += 1
		for m in AbilityExec.live_summons(pl):
			m.summon_time = 0.05
		await wait(0.6)
		var corpses1 := 0
		for a in Game.actors_near(pl.global_position, 30.0):
			if a.is_dead:
				corpses1 += 1
		ck("…summons despawn when their time ends", AbilityExec.live_summons(pl).is_empty())
		ck("…without corpses or kill credit", corpses1 <= corpses0 and d.kills == kills0, "corpses %d→%d kills %d→%d" % [corpses0, corpses1, kills0, d.kills])
		var chron1 := Chronicle.events.size() if Chronicle.get("events") != null else -1
		ck("…the chronicle is intact (no bogus deaths from despawns)", chron1 >= chron0 and Chronicle.count_type("kill", pl.actor_id) <= 1)
		# ======================================================== HEALING + HARDCORE
		clean()
		Profile.difficulty = "hardcore"
		var hc = w.sys("hardcore")
		ck("hardcore on", Hardcore.active())
		Profile.char.injuries = []
		ready_caster()
		pl.hp = pl.max_hp * 0.5
		var hp0: float = pl.hp
		var why_wt := AbilityExec.block_reason(pl, "h_warm_touch", fwd)
		var ok_wt: bool = pl.use_ability("h_warm_touch", fwd)
		await wait(1.0)
		ck("«Тёплое прикосновение» restores HP", pl.hp > hp0 + pl.max_hp * 0.08, "%.0f→%.0f ok=%s why=%s busy=%s" % [hp0, pl.hp, str(ok_wt), why_wt, str(pl.busy())])
		var arm: Dictionary = hc.add_injury("arm_r", "cut", 2)
		var leg: Dictionary = hc.add_injury("leg_l", "cut", 2)
		ck("two cuts, both bleeding", int(arm.bleed) > 0 and int(leg.bleed) > 0)
		ready_caster()
		pl.set_meta("heal_pick", int(arm.id))
		pl.use_ability("h_hemostasis", fwd)
		await wait(1.0)
		ck("«Печать кровостаза» on the CHOSEN arm stops its bleeding", arm.bandaged and not leg.bandaged)
		ready_caster()
		pl.set_meta("heal_pick", int(arm.id))
		pl.use_ability("h_close_wound", fwd)
		await wait(1.2)
		ck("«Закрытие раны» closes the chosen cut (treated, healing)", arm.treated and float(arm.heal) > 0.5 or int(arm.sev) < 2, "sev %d heal %.2f" % [int(arm.sev), float(arm.heal)])
		var heal_before := float(leg.heal)
		var leg_sev := int(leg.sev)
		ready_caster()
		pl.set_meta("heal_pick", int(leg.id))
		pl.use_ability("h_close_wound", fwd)
		await wait(1.2)
		var heal1 := float(leg.heal) + int(leg_sev - int(leg.sev))
		ready_caster()
		pl.set_meta("heal_pick", int(leg.id))
		var r_again: Dictionary = hc.spell_op(pl, "close_wound", 26, int(leg.id))
		ck("no endless healing: the same wound refuses a second closing soon after", not r_again.ok and str(r_again.reason).contains("уже"), str(r_again))
		var frac: Dictionary = hc.add_injury("leg_r", "fracture", 3)
		ck("a heavy fracture", frac.type == "fracture" and int(frac.sev) == 3)
		var rt: Dictionary = hc.spell_op(pl, "tissue", 26, int(frac.id))
		ck("«Восстановление тканей» refuses a fracture", not rt.ok and str(rt.reason).contains("Костяное"), str(rt))
		if int(frac.bleed) > 0:
			var rb0: Dictionary = hc.spell_op(pl, "bone_unity", 26, int(frac.id))
			ck("«Костяное единство» refuses while it bleeds", not rb0.ok, str(rb0))
			hc.spell_op(pl, "hemostasis", 26, int(frac.id))
		var rb: Dictionary = hc.spell_op(pl, "bone_unity", 26, int(frac.id))
		ck("«Костяное единство» sets the bone", rb.ok and frac.splinted, str(rb))
		var inf: Dictionary = hc.add_injury("abdomen", "stab", 2)
		inf.infected = true
		var rw: Dictionary = hc.spell_op(pl, "close_wound", 26, int(inf.id))
		ck("infection is NOT cured by the wrong spell (closing)", not rw.ok and inf.infected, str(rw))
		var rw2: Dictionary = hc.spell_op(pl, "tissue", 26, int(inf.id))
		ck("…nor by tissue restoration", not rw2.ok and inf.infected)
		var rc: Dictionary = hc.spell_op(pl, "cleanse", 26, int(inf.id))
		ck("«Очищающий поток» cures the infection of a medium wound (mastery 26)", rc.ok and not inf.infected, str(rc))
		var heavy: Dictionary = hc.add_injury("chest", "stab", 3)
		heavy.infected = true
		var rc3: Dictionary = hc.spell_op(pl, "cleanse", 26, int(heavy.id))
		ck("…but heavy infection needs a healer", not rc3.ok and heavy.infected, str(rc3))
		# save / load
		pl.data.injuries = Profile.char.injuries
		var dd := Profile.char.to_dict()
		var back := CharData.new()
		back.from_dict(JSON.parse_string(JSON.stringify(dd)))
		var keep_ok := false
		for i2 in back.injuries:
			if i2.zone == "arm_r" and i2.get("bandaged", false) and i2.get("treated", false):
				keep_ok = true
		ck("healing state survives save/load", keep_ok and back.injuries.size() == Profile.char.injuries.size())
		Profile.difficulty = "normal"
		Profile.char.injuries = []
		# ======================================================== RESONANCE
		clean()
		var res = w.sys("resonance")
		if res:
			res.reset()
			res.cata_ready_at = 99999.0
			var pairs := [["fire", "air", "firestorm"], ["ice", "lightning", "conduct"], ["earth", "fire", "magma"], ["earth", "lightning", "crystal_node"],
				["necro", "dark", "harvest"], ["light", "dark", "eclipse"], ["heal", "light", "sanctuary"], ["time", "earth", "echo"]]
			var got: Array = []
			var k := 0
			for pr in pairs:
				res.reset()
				for zz in res.active:
					if is_instance_valid(zz):
						zz.queue_free()
				res.active.clear()
				res.cata_ready_at = 99999.0
				var pos: Vector3 = pl.global_position + fwd * 6.0 + side * (k * 7.0 - 24.0)
				k += 1
				Resonance.imprint(pr[0], pos, 40.0, "normal", pl)
				Resonance.imprint(pr[1], pos, 40.0, "normal", pl)
				got.append(res.last.get("kind", "") == pr[2])
				await wait(0.2)
			ck("resonance pairs: fire+air, ice+lightning, earth+fire, earth+lightning, necro+dark, light+dark, heal+light, time+any", not false in got, str(got))
			res.reset()
			res.cata_ready_at = 99999.0
			var pos2: Vector3 = pl.global_position + fwd * 6.0
			Resonance.imprint("fire", pos2, 40.0, "normal", pl)
			Resonance.imprint("air", pos2, 40.0, "normal", pl)
			var n1: int = int(res.stats.reactions)
			Resonance.imprint("fire", pos2, 40.0, "normal", pl)
			Resonance.imprint("air", pos2, 40.0, "normal", pl)
			ck("no endless stacking: area cool-down blocks a second reaction on the spot", int(res.stats.reactions) == n1)
			clean()
		# ======================================================== NPC CASTERS
		# NPC casters are tested out in the wild (towns forbid destructive magic)
		var spot: Vector3 = pl.global_position + fwd * 30.0
		for k3 in 24:
			var cand: Vector3 = pl.global_position + Vector3(cos(k3 * 0.8), 0, sin(k3 * 0.8)) * (40.0 + 12.0 * k3)
			if CityPeace.inst == null or CityPeace.inst.city_at(cand, 30.0) == null:
				spot = cand
				break
		if w.has_method("ground_height"):
			spot.y = w.ground_height(spot)
		w._teleport(pl, spot - fwd * 16.0)
		await wait(2.0)
		if w.has_method("ground_height"):
			spot.y = w.ground_height(spot)
		var geo = foe("geomancer", spot, 600.0, false)
		var shooter = Game.world.spawner.spawn_enemy("bandit", spot - fwd * 12.0, 6)
		await wait(0.4)
		ck("an NPC earth mage knows earth spells (low tiers only)", geo.data.spells.has("e_bastion_wall") and geo.data.max_spell_tier() <= 3, str(geo.data.spells))
		# a ranged foe shooting at the earth mage
		var bw := ItemDB.create("bow_short", 0, 6, null, false)
		shooter.data.inv.add(bw)
		shooter.data.inv.equip_item(bw)
		shooter.team = "player"
		shooter.faction_id = ""
		geo.add_aggro(shooter, 60.0)
		shooter.add_aggro(geo, 60.0)
		geo.brain.target = shooter
		geo.brain.goal = "fight"
		var used0: int = int(AbilityAI.stats.used)
		var walls0 := StoneStructure.spawned
		var t_end := Time.get_ticks_msec() + 30000
		while Time.get_ticks_msec() < t_end and StoneStructure.spawned == walls0:
			await wait(0.5)
		ck("the earth mage reacts to an archer by raising stone (wall/spikes)", StoneStructure.spawned > walls0, "AI used %d" % (int(AbilityAI.stats.used) - used0))
		AbilityExec.despawn(geo)
		AbilityExec.despawn(shooter)
		clean()
		# necromancer: raises the dead near a corpse
		var nec = foe("necro_acolyte", spot + side * 6.0, 600.0, false)
		var victim = Game.world.spawner.spawn_enemy("wolf", spot + side * 8.0, 2)
		await wait(0.3)
		victim.team = "player"
		Combat.deal(null, victim, {"amount": 9999.0, "dtype": "slash"})
		var bait = Game.world.spawner.spawn_enemy("bandit", spot + side * 14.0, 6)
		bait.team = "player"
		bait.faction_id = ""
		bait.max_hp = 5000.0
		bait.hp = 5000.0
		nec.add_aggro(bait, 60.0)
		bait.add_aggro(nec, 60.0)
		nec.brain.target = bait
		nec.brain.goal = "fight"
		t_end = Time.get_ticks_msec() + 30000
		while Time.get_ticks_msec() < t_end and AbilityExec.live_summons(nec).is_empty():
			await wait(0.5)
		ck("an NPC necromancer raises servants near the fresh death", not AbilityExec.live_summons(nec).is_empty())
		t_end = Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < t_end and is_instance_valid(nec) and is_instance_valid(bait) and not nec.statuses.has("magic_shield") and not bait.statuses.has("wither"):
			await wait(0.5)
		var both: bool = is_instance_valid(nec) and is_instance_valid(bait)
		ck("…and uses its shield or curse", both and (nec.statuses.has("magic_shield") or bait.statuses.has("wither") or bait.statuses.has("root")), "alive=%s" % str(both))
		ck("…keeping its distance (%.1f m)" % (nec.global_position.distance_to(bait.global_position) if both else -1.0), both and nec.global_position.distance_to(bait.global_position) > 4.0)
		if is_instance_valid(nec):
			for m in AbilityExec.live_summons(nec):
				AbilityExec.despawn(m)
			AbilityExec.despawn(nec)
		if is_instance_valid(bait):
			AbilityExec.despawn(bait)
		# healer heals a wounded ally
		var heal_npc = foe("field_healer", spot - side * 6.0, 300.0, false)
		var buddy = foe("bandit", spot - side * 9.0, 1000.0, true)
		await wait(0.3)
		buddy.hp = 300.0
		buddy.apply_status("invuln", 999.0)
		var bhp: float = buddy.hp
		var enemy2 = Game.world.spawner.spawn_enemy("bandit", spot - side * 18.0, 6)
		enemy2.team = "player"
		enemy2.faction_id = ""
		enemy2.max_hp = 5000.0
		enemy2.hp = 5000.0
		enemy2.apply_status("root", 999.0)
		heal_npc.add_aggro(enemy2, 60.0)
		heal_npc.brain.target = enemy2
		heal_npc.brain.goal = "fight"
		t_end = Time.get_ticks_msec() + 25000
		while Time.get_ticks_msec() < t_end and is_instance_valid(buddy) and buddy.hp <= bhp + 1.0:
			await wait(0.5)
		ck("an NPC healer heals the wounded ally", is_instance_valid(buddy) and buddy.hp > bhp + 1.0, "%.0f→%.0f" % [bhp, buddy.hp if is_instance_valid(buddy) else -1.0])
		for a in [heal_npc, buddy, enemy2]:
			if is_instance_valid(a):
				AbilityExec.despawn(a)
		# ======================================================== TOWN RULES
		var cp = CityPeace.inst
		var town = null
		if cp:
			for sid in cp.cities:
				town = cp.cities[sid]
				break
		if town != null:
			pl.global_position = town.pos + Vector3(0, 1, 0)
			if w.has_method("ground_height"):
				pl.global_position.y = w.ground_height(town.pos) + 0.2
			await wait(1.0)
			var mage_npc = foe("geomancer", town.pos + Vector3(4, 0, 0), 300.0, true)
			mage_npc.team = "bandit"
			ck("an NPC refuses destructive magic on a peaceful square", not CityMagic.allowed(mage_npc, DBAbilities.get_ab("f_volcanic_mark"), town.pos))
			ck("…but harmless magic is fine", CityMagic.allowed(mage_npc, DBAbilities.get_ab("h_warm_touch"), town.pos))
			AbilityExec.despawn(mage_npc)
			CityMagic.reset()
			ready_caster()
			pl.use_ability("f_volcanic_mark", fwd)
			await wait(1.0)
			ck("the hero is warned first", int(CityMagic.stats.warnings) == 1 and int(CityMagic.stats.guard_calls) == 0)
			ready_caster()
			pl.use_ability("f_volcanic_mark", fwd)
			await wait(1.0)
			ck("…a repeat calls the guard (bounded: offender for %d s)" % int(CityPeace.OFFENDER_S), int(CityMagic.stats.guard_calls) == 1 and cp.is_offender(pl))
			cp.offenders.erase(pl.actor_id)
			for g in Game.actors_near(pl.global_position, 60.0):
				g.aggro.erase(pl.actor_id)
			clean()
		else:
			ck("a town exists for the town-rule checks", false)
		# ======================================================== LORE
		var lore = w.sys("magic_lore")
		ck("magic lore active: one named archmage per school", lore != null and lore.archmages.size() == 10)
		if lore:
			var names := {}
			for s in lore.archmages:
				names[lore.archmages[s].name] = true
			ck("…each with a unique name", names.size() == 10)
			var men = lore.spawn_mentor("earth", pl.global_position + fwd * 3.0)
			ck("…a mentor appears (role mentor)", men != null and men.role == "mentor")
			var d2 := CharData.new()
			d2.setup_class("mage")
			d2.learn_school("earth")
			d2.schools.earth.lvl = 20
			lore.teach(d2, "earth", "e_mountain_heart")
			ck("…a mentor's teaching is real knowledge for tier V", d2.knowledge.has("know_e_mountain_heart"))
			var tr: Dictionary = MagicLore.treatise("e_great_quake")
			ck("…a treatise carries the cataclysm knowledge", str(tr.get("knowledge", "")) == "tome_e_great_quake")
			d.knowledge.erase("trial_earth")
			var keeper = lore.start_trial("earth", pl)
			ck("…the trial summons the keeper of the school", keeper != null and keeper.get_meta("trial", "") == "earth")
			if keeper:
				Combat.deal(pl, keeper, {"amount": 999999.0, "dtype": "earth"})
				await wait(0.5)
				ck("…defeating it grants the trial mark, the treatise and reagents", d.knowledge.has("trial_earth") and lore.archmages.earth.trial_done)
			if men:
				men.queue_free()
		# ======================================================== PERFORMANCE
		clean()
		TimeFX.inst.set_base(1.0)
		var foes: Array = []
		for i in 12:
			foes.append(foe("bandit", pl.global_position + fwd * 10.0 + Vector3(cos(i * 0.52), 0, sin(i * 0.52)) * 5.0))
		await wait(0.5)
		var t0 := Time.get_ticks_usec()
		var frames := 0
		var worst := 0.0
		var last := Time.get_ticks_usec()
		var ids := ["e_stone_spears", "f_flame_sky", "l_nine_strikes", "i_white_silence", "a_cutting_cyclone", "e_mountain_fist"]
		for id in ids:
			ready_caster()
			pl.use_ability(id, fwd)
			for k2 in 40:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				worst = maxf(worst, float(now - last) / 1000.0)
				last = now
				frames += 1
		var avg := float(Time.get_ticks_usec() - t0) / 1000.0 / maxf(1.0, frames)
		print("PERF magic burst: frames=%d avg=%.1f ms worst=%.1f ms terrain=%d zones=%d" % [frames, avg, worst, StoneStructure.count_live(), w.zones.size()])
		ck("performance probe ran (headless, not a device measurement): terrain ≤ %d, zones bounded" % StoneStructure.MAX_LIVE, StoneStructure.count_live() <= StoneStructure.MAX_LIVE and w.zones.size() < 30)
		print("SCHOOLS_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
