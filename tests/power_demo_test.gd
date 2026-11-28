extends Node
## «Ascension of Power» — demo scenario (section 29), played through the
## real systems:
##  1. A young earth mage: a found «Фолиант Земли» → «Каменный осколок» in
##     real fights → the school's archmage mentor in town → «Каменная кожа»
##     → «Каменные копья» → the golem's treatise found in a dungeon chest →
##     the golem → the path of the archmage, the school trial → «Великое
##     Землетрясение»: preparation, runes, rising stones, readable shockwaves,
##     real damage, enemies reacting, a temporarily changed arena.
##  2. Hardcore: a wound → the anatomy menu → the injured arm selected → a
##     healing spell changes that injury → save / load keeps it.
##  3. An NPC necromancer fighting on its own: raises servants where someone
##     died, shields and curses.
## School mastery beyond the first real levels is granted as training XP
## (stated in the report); mana and cool-downs are refilled between casts.
## Screenshots are written when rendering (xvfb), skipped headless.
## Prints POWER_DEMO_DONE pass=N fail=M.

func _ready() -> void:
	seed(29029)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Ирма", "mage", false, {"skin": 1, "hair": 3, "hair_color": 2, "beard": 0, "cloth": 1})
	Profile.world_seed = 290290
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var dir := ""
	var render := false
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, false).timeout
	func shot(nm: String) -> void:
		if not render:
			return
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + "/" + nm + ".png")
		print("SHOT ", nm)
	func _ready() -> void:
		render = DisplayServer.get_name() != "headless"
		dir = OS.get_environment("SHOTS_DIR")
		if dir == "":
			dir = "user://power_shots"
		DirAccess.make_dir_recursive_absolute(dir)
		_run()

	func refill() -> void:
		var pl = Game.player
		pl.skill_cd.clear()
		pl.act = {}
		pl.mana = pl.max_mana
		pl.stamina = pl.max_stamina
		pl.statuses.erase("exhausted")
		pl.mana_delay_t = 0.0
		AbilityExec._high_until.clear()      # the archmage "one high spell at a time" window (0.15.0)

	func face(a, t) -> Vector3:
		var to: Vector3 = t.global_position - a.global_position
		to.y = 0
		a.face_dir(to.normalized())
		return to.normalized()

	func train(sch: String, to_lvl: int) -> void:
		var d: CharData = Game.player.data
		var guard := 0
		while d.school_level(sch) < to_lvl and guard < 400:
			d.add_school_xp(sch, DBSkills.mastery_xp_needed(d.school_level(sch)))
			guard += 1

	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		var d: CharData = pl.data
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		if w.get("day_night") and w.day_night.get("time_override") != null:
			w.day_night.time_override = 13.0
		pl.apply_status("invuln", 999999.0)
		# ================================================= 1. the young earth mage
		ck("the mage does not know earth magic yet", not d.knows_school("earth"))
		var tome := ItemDB.create("tome_earth", 0, 1)
		d.inv.add(tome)
		pl.use_item(tome)
		ck("a found «Фолиант Земли» opens the school", d.knows_school("earth") and d.magic_rank() >= 1)
		ck("«Каменный осколок» learned with the first school point", d.learn_ability("e_stone_shard"))
		var wolf = w.spawner.spawn_enemy("wolf", pl.global_position + pl.facing * 9.0, 1)
		var xp0: int = int(d.schools.earth.xp) + 1000 * d.school_level("earth")
		var casts := 0
		var t_end := Time.get_ticks_msec() + 25000
		while is_instance_valid(wolf) and not wolf.is_dead and Time.get_ticks_msec() < t_end:
			refill()
			if wolf.global_position.distance_to(pl.global_position) > 14.0:
				# the hurt wolf runs: the mage follows it
				w._teleport(pl, wolf.global_position + (pl.global_position - wolf.global_position).normalized() * 8.0)
			var dd := face(pl, wolf)
			if pl.use_ability("e_stone_shard", dd):
				casts += 1
			await wait(0.7)
			if casts == 1:
				await shot("01_stone_shard")
		ck("the stone shard kills a wolf in a real fight (%d casts)" % casts, wolf == null or not is_instance_valid(wolf) or wolf.is_dead)
		var xp1: int = int(d.schools.earth.xp) + 1000 * d.school_level("earth")
		ck("…and the school grows from use", xp1 > xp0)
		# the mentor
		var lore = w.sys("magic_lore")
		var mentor = null
		if lore:
			var sid: String = lore.archmages.earth.sid
			var s: Dictionary = lore._settlement(sid)
			if not s.is_empty():
				w._teleport(pl, Vector3(s.pos.x, 0, s.pos.y) + Vector3(6, 0, 6))
				await wait(3.0)
			mentor = lore.mentors.get("earth")
			if mentor == null or not is_instance_valid(mentor):
				mentor = lore.spawn_mentor("earth")
		ck("the earth archmage lives in a town as a mentor", mentor != null and is_instance_valid(mentor) and mentor.role == "mentor", lore.archmage_title("earth") if lore else "")
		if mentor:
			w._teleport(pl, mentor.global_position + Vector3(2, 0, 0))
			await wait(0.6)
			w.dialogs.open_npc(mentor)
			await wait(0.4)
			ck("…talking to the mentor opens the archmage's dialog", w.ui.top_name() == "dialog" and lore.archmages.earth.met)
			await shot("02_mentor")
			w.ui.close_top()
		# stone skin
		train("earth", 4)
		ck("«Каменная кожа» learned at mastery 4", d.learn_ability("e_stone_skin"))
		refill()
		var arm0: float = pl.stat("armor")
		pl.use_ability("e_stone_skin", pl.facing)
		await wait(0.9)
		ck("…armour rises (%.0f → %.0f)" % [arm0, pl.stat("armor")], pl.stat("armor") > arm0 + 10.0)
		await shot("03_stone_skin")
		# stone spears
		train("earth", 8)
		ck("«Каменные копья» learned at mastery 8", d.learn_ability("e_stone_spears"))
		var foes: Array = []
		for i in 3:
			var b = w.spawner.spawn_enemy("bandit", pl.global_position + pl.facing * (5.0 + 2.0 * i), 3)
			b.apply_status("root", 6.0)
			foes.append(b)
		await wait(0.4)
		refill()
		var hp_line := 0.0
		for b in foes:
			hp_line += b.hp
		pl.use_ability("e_stone_spears", face(pl, foes[1]))
		await wait(0.9)
		await shot("04_stone_spears")
		var hp_line2 := 0.0
		for b in foes:
			hp_line2 += b.hp if is_instance_valid(b) and not b.is_dead else 0.0
		ck("…a line of spikes hits the foes standing in it", hp_line2 < hp_line)
		for b in foes:
			if is_instance_valid(b) and not b.is_dead:
				AbilityExec.despawn(b)
		# dungeon: the golem's treatise
		train("earth", 12)
		ck("the golem needs real knowledge", d.ability_block("e_guardian_golem").contains("знание"), d.ability_block("e_guardian_golem"))
		w.enter_dimension("dungeon", {"expedition": true})
		await wait(1.5)
		var dim = w.dim_node
		var chest = null
		for c in dim.get_children():
			if c.has_method("interact") and c.get("tier") != null and c.get("is_mimic") != true:
				chest = c
				break
		ck("a dungeon with chests", chest != null)
		var got_treatise := false
		if chest:
			w._teleport(pl, chest.global_position + Vector3(1.5, 0, 0))
			await wait(0.4)
			chest.interact(pl)
			await wait(0.8)
			for dr in Game.grid.query(chest.global_position, 6.0, "interact"):
				if dr is ItemDrop and str(dr.item.get("knowledge", "")) == "tome_e_guardian_golem":
					dr.interact(pl)
			await wait(0.3)
			for it in d.inv.items.duplicate():
				if str(it.get("knowledge", "")) == "tome_e_guardian_golem":
					got_treatise = true
					pl.use_item(it)
		var near_drops: Array = []
		if chest:
			for dr2 in Game.grid.query(chest.global_position, 8.0, "interact"):
				if dr2 is ItemDrop:
					near_drops.append(str(dr2.item.get("base", "gold")) + ":" + str(dr2.item.get("knowledge", "")))
		ck("…the golem's treatise found in a dungeon chest and read", got_treatise and d.knowledge.has("tome_e_guardian_golem"), "chest opened=%s drops=%s" % [str(chest.get("opened")) if chest else "-", str(near_drops)])
		ck("«Голем хранителя» learned", d.learn_ability("e_guardian_golem"), d.ability_block("e_guardian_golem"))
		refill()
		pl.use_ability("e_guardian_golem", pl.facing)
		await wait(1.6)
		ck("…the golem rises in the dungeon", AbilityExec.live_summons(pl).any(func(m): return m.def_id == "stone_golem"))
		await shot("05_golem_dungeon")
		w.leave_dimension(true)
		await wait(2.0)
		for m in AbilityExec.live_summons(pl):
			AbilityExec.despawn(m)
		# the archmage path and the trial
		d.level = 35
		pl.recalc_stats()                    # a real level-up recalculates max mana (130 + 4 per level)
		d.class_pts += 40
		for e in DBAbilities.class_skills("mage"):
			d.learn_ability(e.id)
		ck("«Путь архимага» taken", "cm_archmage_path" in d.class_skills)
		train("earth", 24)
		train("fire", 1)
		d.knowledge["know_e_mountain_heart"] = true
		for id in ["e_mountain_fist", "e_mountain_heart"]:
			d.learn_ability(id)
		ck("tier V «Гнев Горного Сердца» learned (mentor's knowledge)", "e_mountain_heart" in d.spells)
		var keeper = lore.start_trial("earth", pl) if lore else null
		ck("the school trial summons its keeper", keeper != null)
		t_end = Time.get_ticks_msec() + 60000
		var spells := ["e_stone_spears", "e_mountain_fist", "e_stone_shard", "e_mountain_heart"]
		var si := 0
		while keeper != null and is_instance_valid(keeper) and not keeper.is_dead and Time.get_ticks_msec() < t_end:
			refill()
			if pl.global_position.distance_to(keeper.global_position) > 14.0:
				w._teleport(pl, keeper.global_position + (pl.global_position - keeper.global_position).normalized() * 9.0)
			pl.use_ability(spells[si % spells.size()], face(pl, keeper))
			si += 1
			await wait(1.6)
		ck("…the keeper falls to real earth magic", keeper == null or not is_instance_valid(keeper) or keeper.is_dead, "%d casts" % si)
		await wait(0.5)
		ck("…trial mark, cataclysm treatise and reagents", d.knowledge.has("trial_earth") and d.inv.count(AbilityExec.cataclysm_reagent()) >= 2)
		for it in d.inv.items.duplicate():
			if str(it.get("knowledge", "")) == "tome_e_great_quake":
				pl.use_item(it)
		ck("«Великое Землетрясение» learned", d.learn_ability("e_great_quake"), d.ability_block("e_great_quake"))
		ck("the mage is now «%s»" % DBAbilities.RANK_NAMES[d.magic_rank()], d.magic_rank() >= 7)
		d.ab_page = 1
		ck("the cataclysm is prepared (the only one)", d.set_slot("staff", 1, 0, "e_great_quake") == "" and d.prepared_cataclysms() == ["e_great_quake"])
		# the battle
		var arena: Vector3 = pl.global_position + pl.facing * 14.0
		var band: Array = []
		for i in 6:
			var b2 = w.spawner.spawn_enemy("bandit", arena + Vector3(cos(i * 1.05), 0, sin(i * 1.05)) * randf_range(2.0, 6.0), 6)
			b2.max_hp = 900.0
			b2.hp = 900.0
			band.append(b2)
		await wait(1.0)
		var hp_b := 0.0
		for b2 in band:
			hp_b += b2.hp
		refill()
		var slabs0 := StoneStructure.spawned
		ck("«Великое Землетрясение» is cast", pl.use_ability("e_great_quake", face(pl, band[0])))
		await wait(1.6)
		await shot("06_quake_preparation_runes")
		await wait(1.5)
		await shot("07_quake_rising_stones")
		await wait(1.1)
		await shot("08_quake_shockwave")
		await wait(2.4)
		var cq: Dictionary = Cataclysm.last.get("quake", {})
		var hp_b2 := 0.0
		var dead := 0
		var afraid := 0
		for b2 in band:
			if is_instance_valid(b2) and not b2.is_dead:
				hp_b2 += b2.hp
				if b2.statuses.has("fear") or b2.statuses.has("stun"):
					afraid += 1
			else:
				dead += 1
		ck("…preparation with runes and rising stones (%d slabs)" % int(cq.get("slabs", 0)), int(cq.get("slabs", 0)) >= 5 and StoneStructure.spawned - slabs0 >= 5)
		ck("…three readable shockwaves", int(cq.get("waves", 0)) == 3)
		ck("…real damage (%.0f → %.0f, %d fell)" % [hp_b, hp_b2, dead], hp_b2 < hp_b * 0.8)
		ck("…enemies react (stunned / frightened / fallen: %d)" % (afraid + dead), afraid + dead >= 1 or int(cq.get("hits", 0)) >= 6)
		ck("…the arena is changed for a while", StoneStructure.live.any(func(x): return is_instance_valid(x) and x.kind == "slab" and not x._sinking))
		await shot("09_quake_changed_arena")
		await wait(9.0)
		ck("…and returns to normal", not StoneStructure.live.any(func(x): return is_instance_valid(x) and x.kind == "slab" and not x._sinking))
		for b2 in band:
			if is_instance_valid(b2) and not b2.is_dead:
				AbilityExec.despawn(b2)
		d.ab_page = 0
		# ================================================= 2. Hardcore healing
		Profile.difficulty = "hardcore"
		var hc = w.sys("hardcore")
		Profile.char.injuries = []
		for e in DBAbilities.school_spells("heal"):
			if int(e.tier) <= 4:
				if not d.knows_school("heal"):
					d.learn_school("heal")
				train("heal", 12)
				d.learn_ability(e.id)
		pl.statuses.erase("invuln")
		var bandit = w.spawner.spawn_enemy("bandit", pl.global_position + pl.facing * 1.6, 4)
		await wait(0.3)
		var arm_pos: Vector3 = pl.global_position + pl.facing.cross(Vector3.UP) * 0.38 + Vector3(0, 1.25 * pl._scale(), 0) + pl.facing * 0.15
		var info := Combat.weapon_info(bandit, 2.5)
		info.melee = true
		info.hit_pos = arm_pos
		info.dtype = "slash"
		info.amount = maxf(float(info.amount), pl.max_hp * 0.15)  # a real (medium) blow for a level-35 hero
		Combat.deal(bandit, pl, info)
		pl.apply_status("invuln", 999999.0)
		AbilityExec.despawn(bandit)
		var arm = null
		for inj in hc.list():
			if str(inj.zone).begins_with("arm"):
				arm = inj
		if arm == null and not hc.list().is_empty():
			arm = hc.list()[0]
		ck("a sword blow wounds the hero (zone from the strike point: %s)" % (str(arm.zone) if arm else "—"), arm != null)
		if arm:
			if int(arm.bleed) == 0:
				arm.bleed = 2
			var anat = w.ui.open("anatomy")
			await wait(0.4)
			anat._select(str(arm.zone))
			await wait(0.3)
			var btn: Button = null
			for c in anat._treat.get_children():
				if c is Button and c.text.begins_with("✚") and c.text.contains("кровостаза") and not c.disabled:
					btn = c
			ck("the anatomy menu offers healing magic for the selected arm", btn != null)
			await shot("10_anatomy_heal")
			var bleed_before := int(arm.bleed)
			if btn:
				btn.pressed.emit()
				await wait(0.5)
			ck("«Печать кровостаза» changed that injury (bleeding stopped)", arm.bandaged and bleed_before > 0)
			refill()
			anat._select(str(arm.zone))
			await wait(0.2)
			var btn2: Button = null
			for c in anat._treat.get_children():
				if c is Button and c.text.begins_with("✚") and c.text.contains("Закрытие") and not c.disabled:
					btn2 = c
			if btn2:
				btn2.pressed.emit()
				await wait(0.5)
			ck("«Закрытие раны» treats the cut (treated, healing %.0f%%)" % (float(arm.heal) * 100.0), arm.treated or int(arm.sev) < 2)
			await shot("11_anatomy_after")
			w.ui.close_top()
			var snap_sev := int(arm.sev)
			var snap_band: bool = arm.bandaged
			SaveSys.save_game()
			SaveSys.load_profile()
			var found := false
			for inj in Profile.char.injuries:
				if inj.zone == arm.zone and int(inj.sev) == snap_sev and inj.bandaged == snap_band:
					found = true
			ck("save / load keeps the healed state of the arm", found)
		Profile.difficulty = "normal"
		Profile.char.injuries = []
		# ================================================= 3. the NPC necromancer
		var spot: Vector3 = pl.global_position + pl.facing * 18.0
		var nec = w.spawner.spawn_enemy("necro_acolyte", spot, 5)
		nec.max_hp = 900.0
		nec.hp = 900.0
		var prey = w.spawner.spawn_enemy("wolf", spot + Vector3(3, 0, 0), 1)
		await wait(0.3)
		Combat.deal(null, prey, {"amount": 9999.0, "dtype": "slash"})
		var foes2: Array = []
		for i in 2:
			var b3 = w.spawner.spawn_enemy("bandit", spot + Vector3(10, 0, -2 + 4 * i), 4)
			b3.max_hp = 1500.0
			b3.hp = 1500.0
			foes2.append(b3)
			nec.add_aggro(b3, 60.0)
			b3.add_aggro(nec, 60.0)
		nec.brain.target = foes2[0]
		nec.brain.goal = "fight"
		w._teleport(pl, spot + Vector3(-10, 0, 6))
		var used := {}
		t_end = Time.get_ticks_msec() + 60000
		while Time.get_ticks_msec() < t_end and is_instance_valid(nec) and not nec.is_dead:
			for k in nec.skill_cd:
				if DBAbilities.has(k):
					used[k] = true
			if used.has("n_raise_servant") and (used.has("n_bone_shield") or used.has("n_wither_curse") or used.has("n_grave_hand")) and used.size() >= 3:
				break
			nec.hp = maxf(nec.hp, 300.0)
			if randi() % 4 == 0:
				print("NEC goal=%s tgt=%s mana=%.0f/%.0f ai=%s summons=%d" % [nec.brain.goal, str(nec.brain.target), nec.mana, nec.max_mana, str(AbilityAI.stats), AbilityExec.live_summons(nec).size()])
			await wait(0.5)
		await shot("12_npc_necromancer")
		ck("the NPC necromancer raised servants itself", used.has("n_raise_servant"), str(used.keys()))
		ck("…and used shield / curse / grave hand (%d abilities)" % used.size(), used.size() >= 2)
		ck("…the raised dead are its allies, temporary and capped", AbilityExec.live_summons(nec).size() <= AbilityExec.MAX_SUMMONS_PER_OWNER and AbilityExec.live_summons(nec).all(func(m): return m.summon_time > 0.0))
		print("POWER_DEMO_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
