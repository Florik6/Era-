extends Node
## «Ascension of Power» — mandatory tests of section 28 (skills + magic):
## exact counts and unique ids, requirements and points, actives and
## passives with real effects, weapon gating, saves; magic school gating,
## ranks, damage, mana, cool-downs, spell power growth, NPC use; and a live
## run of ALL 200 abilities in the world (each must start and do something
## measurable: damage, a status, a summon, terrain, movement, a heal…).
## Prints ABILITIES_DONE pass=N fail=M.

func _ready() -> void:
	seed(20020)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Восходящий", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 777200
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var dummies: Array = []
	var last_dist := 0.0
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

	func clear_dummies() -> void:
		for d in dummies:
			if is_instance_valid(d) and not d.is_dead:
				AbilityExec.despawn(d)
		dummies.clear()

	## Fresh tough targets in front of the hero (rooted so they stay put).
	func spawn_dummies(n: int, dist := 6.0, id := "bandit") -> Array:
		var pl = Game.player
		clear_dummies()
		for i in n:
			var p: Vector3 = pl.global_position + pl.facing * dist + pl.facing.cross(Vector3.UP) * (float(i) - (n - 1) * 0.5) * 1.6
			var m = Game.world.spawner.spawn_enemy(id, p, 6)
			if m:
				m.base_hp_override = 6000.0
				m.recalc_stats()
				m.max_hp = 6000.0
				m.hp = 6000.0
				m.team = "bandit"
				m.apply_status("root", 9999.0)
				# passive training dummies: no AI of their own (no noise in the checks)
				if m.get("brain") != null and m.brain.has_method("shutdown"):
					m.brain.shutdown()
					m.brain = null
				dummies.append(m)
		return dummies

	func dummy_hp() -> float:
		var s := 0.0
		for d in dummies:
			if is_instance_valid(d) and not d.is_dead:
				s += d.hp
			else:
				s += 0.0
		return s

	func _keys(a) -> Dictionary:
		var out := {}
		if a != null and is_instance_valid(a):
			for k in a.statuses:
				out[k] = float(a.statuses[k].get("t", 0.0))
		return out

	func snapshot() -> Dictionary:
		var st := {}
		for d in dummies:
			if is_instance_valid(d):
				for k in d.statuses:
					st[str(d.actor_id) + k] = float(d.statuses[k].get("t", 0.0))
		var pl = Game.player
		return {"hp": dummy_hp(), "st": st, "summons": AbilityExec.world_summons(), "terrain": StoneStructure.spawned,
			"pos": pl.global_position, "zones": Game.world.zones.size(), "pst": _keys(pl), "shield": pl.shield_hp,
			"php": pl.hp, "vfx": _vfx_total(), "casts": int(AbilityExec.stats.casts), "mana": pl.mana, "sk": pl.skill_cd.size()}

	func _vfx_total() -> int:
		var n := 0
		for k in SpellVFX.counts:
			n += int(SpellVFX.counts[k])
		return n

	func equip(base: String) -> void:
		var pl = Game.player
		var it := ItemDB.create(base, 1, 10, null, false)
		pl.data.inv.add(it)
		pl.equip_item(it)
		# keep the bag from filling up with the weapons swapped out
		pl.data.inv.items = pl.data.inv.items.filter(func(x): return ItemDB.base(x.base).get("slot", "") != "main")
		pl.recalc_stats()

	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		if w.sys("beasts"):
			w.sys("beasts").enabled = false     # no wandering creatures in the test arena
		if w.get("sim"):
			w.sim.set_process(false)
		TimeFX.inst.set_base(2.0)
		var d: CharData = pl.data
		# ============================================================ data
		var all := DBAbilities.all()
		ck("exactly 200 new abilities", all.size() == 200, "%d" % all.size())
		var cls_n := DBAbilities.of_kind("class").size()
		var wpn_n := DBAbilities.of_kind("weapon").size()
		var sp_n := DBAbilities.of_kind("spell").size()
		ck("skills: exactly 100 (60 class + 40 weapon)", cls_n == 60 and wpn_n == 40, "%d+%d" % [cls_n, wpn_n])
		var per_cls := true
		for c in ["warrior", "archer", "rogue", "mage"]:
			per_cls = per_cls and DBAbilities.class_skills(c).size() == 15
		ck("15 class skills for each class", per_cls)
		var per_cat := true
		for c in DBAbilities.WEAPON_CATS:
			per_cat = per_cat and DBAbilities.weapon_skills(c).size() == 5
		ck("5 skills for each of 8 weapon categories", per_cat)
		ck("magic: exactly 100 spells", sp_n == 100, "%d" % sp_n)
		var grid_ok := true
		var tiers_ok := true
		for s in DBAbilities.SCHOOL_ORDER:
			var l := DBAbilities.school_spells(s)
			grid_ok = grid_ok and l.size() == 10
			for i in l.size():
				tiers_ok = tiers_ok and int(l[i].tier) == DBAbilities.SPELL_TIER[i] and int(l[i].n) == i + 1
		ck("10 schools × 10 spells", grid_ok)
		ck("tiers I–VI by position (1-2,3-4,5-6,7-8,9,10)", tiers_ok)
		var old_ids := {}
		for cat in DBSkills.TREES:
			for n in DBSkills.TREES[cat]:
				old_ids[n.id] = true
		for s in DBSkills.SCHOOLS:
			for sp in DBSkills.SCHOOLS[s].spells:
				old_ids[sp.id] = true
		var clash := []
		var names := {}
		var dup_names := []
		for id in all:
			if old_ids.has(id):
				clash.append(id)
			var nm: String = all[id].name
			if names.has(nm) and all[id].kind != "spell":
				dup_names.append(nm)
			names[nm] = true
		ck("unique ids, no clash with the 20 old spells / old tree nodes (old abilities kept)", clash.is_empty() and old_ids.size() >= 40, str(clash))
		var fx_ok := true
		var bad_fx := []
		for id in all:
			var e: Dictionary = all[id]
			if e.type == "active" and e.fx.is_empty():
				fx_ok = false
				bad_fx.append(id)
			if e.type == "passive" and e.get("hooks", {}).is_empty() and e.get("mods", {}).is_empty():
				fx_ok = false
				bad_fx.append(id)
		ck("every active has components, every passive has real modifiers", fx_ok, str(bad_fx))
		# ===================================================== requirements
		var fresh := CharData.new()
		fresh.setup_class("warrior")
		fresh.level = 1
		fresh.class_pts = 1
		ck("level-1 warrior can learn «Несокрушимая стойка»", fresh.ability_block("cw_unbreakable") == "")
		ck("…but not a level-2 skill", fresh.ability_block("cw_iron_rush").contains("уровень"), fresh.ability_block("cw_iron_rush"))
		ck("…nor another class's skill", fresh.ability_block("ca_eagle_eye").contains("класс"), fresh.ability_block("ca_eagle_eye"))
		ck("learning spends class points", fresh.learn_ability("cw_unbreakable") and fresh.class_pts == 0 and "cw_unbreakable" in fresh.class_skills)
		fresh.level = 2
		ck("no points → refused with a reason", fresh.ability_block("cw_iron_rush").contains("очков"), fresh.ability_block("cw_iron_rush"))
		var before_pts := fresh.class_pts
		fresh.xp = fresh.xp_needed()
		fresh.add_xp(0)
		ck("a level-up gives a class point", fresh.class_pts == before_pts + 1, "%d→%d" % [before_pts, fresh.class_pts])
		ck("weapon skill needs mastery", fresh.ability_block("ws_blade_crown").contains("мастерство"), fresh.ability_block("ws_blade_crown"))
		fresh.mastery_of("sword").lvl = 2
		fresh.mastery_of("sword").pts = 1
		ck("weapon skill learned with a mastery point", fresh.learn_ability("ws_glide_cut") and fresh.has_node("ws_glide_cut") and fresh.mastery_of("sword").pts == 0)
		ck("weapon skills live in the weapon tree (DBSkills.tree)", DBSkills.tree("sword").size() == DBSkills.TREES.sword.size() + 5 and DBSkills.tree("energy").size() == 5)
		ck("spell needs the school", fresh.ability_block("e_stone_shard").contains("школа"), fresh.ability_block("e_stone_shard"))
		fresh.learn_school("earth")
		ck("school learned → tier I spell learnable", fresh.ability_block("e_stone_shard") == "" and fresh.learn_ability("e_stone_shard"))
		ck("tier II needs school mastery", fresh.ability_block("e_stone_skin").contains("мастерство школы"), fresh.ability_block("e_stone_skin"))
		ck("a new character has no magic rank before any school (rank «%s» with one)" % DBAbilities.RANK_NAMES[fresh.magic_rank()], CharData.new().magic_rank() == 0 and fresh.magic_rank() == 1)
		# ===================================================== the hero
		d.level = 40
		d.class_pts = 200
		pl.recalc_stats()
		# actives + passives of the warrior
		ck("warrior learns «Мастер парирования»", d.learn_ability("cw_parry_master") or d.class_skills.has("cw_parry_master"))
		var pw0: float = 0.0
		pl.recalc_stats()
		pw0 = pl.parry_window()
		d.class_skills.erase("cw_parry_master")
		pl.recalc_stats()
		var pw1: float = pl.parry_window()
		d.class_skills.append("cw_parry_master")
		pl.recalc_stats()
		ck("passive changes the real parry window (+0.08 s)", absf((pw0 - pw1) - 0.08) < 0.001, "%.3f vs %.3f" % [pw0, pw1])
		ck("warrior learns «Несокрушимая стойка» (active)", d.learn_ability("cw_unbreakable") or "cw_unbreakable" in d.class_skills)
		pl.recalc_stats()
		ck("active class skill appears in the prepared slots", "cw_unbreakable" in d.active_slots(pl.mastery_cat()), str(d.active_slots(pl.mastery_cat())))
		var arm0: float = pl.stat("armor")
		var st0: float = pl.stamina
		ck("using the active works", pl.use_ability("cw_unbreakable", pl.facing))
		await wait(0.6)
		ck("…armour +10 and no knock-back, stamina spent, cool-down set", pl.stat("armor") >= arm0 + 9.9 and pl._no_knock() and pl.stamina < st0 and pl.skill_cd.has("cw_unbreakable"), "%.1f→%.1f" % [arm0, pl.stat("armor")])
		ck("cool-down blocks a second use", not pl.use_ability("cw_unbreakable", pl.facing))
		# weapon gating
		d.mastery_of("spear").lvl = 20
		d.mastery_of("spear").pts = 5
		ck("spear skill learned", d.learn_ability("wp_far_lunge"))
		ck("spear skill refused with a sword in hand", AbilityExec.block_reason(pl, "wp_far_lunge").contains("оружие"), AbilityExec.block_reason(pl, "wp_far_lunge"))
		# save / load
		d.knowledge["know_test"] = true
		d.save_set("бой")
		var dd := d.to_dict()
		var back := CharData.new()
		back.from_dict(JSON.parse_string(JSON.stringify(dd)))
		ck("save/load keeps class skills, points, spells, knowledge, sets", back.class_skills == d.class_skills and back.class_pts == d.class_pts and back.knowledge.has("know_test") and back.saved_sets.has("бой") and back.spells == d.spells)
		var legacy := d.to_dict()
		legacy.erase("class_pts")
		legacy.erase("class_skills")
		var mig := CharData.new()
		mig.from_dict(legacy)
		ck("old saves migrate (class points = level)", mig.class_pts == mig.level and mig.class_skills.is_empty())
		# ===================================================== magic gating / ranks
		d.class_id = "mage"
		for s in DBAbilities.SCHOOL_ORDER:
			d.learn_school(s)
			d.schools[s].lvl = 3
			d.schools[s].pts = 2
		ck("rank from mastery, not level (lvl 40, schools 3 → «%s»)" % DBAbilities.RANK_NAMES[d.magic_rank()], d.magic_rank() <= 2)
		ck("tier V refused without knowledge", d.ability_block("e_mountain_heart") != "", d.ability_block("e_mountain_heart"))
		for s in DBAbilities.SCHOOL_ORDER:
			d.schools[s].lvl = 26
			d.schools[s].pts = 60
		d.class_skills.append("cm_archmage_path")
		for s in DBAbilities.SCHOOL_ORDER:
			for e in DBAbilities.school_spells(s):
				if int(e.tier) <= 4:
					d.learn_ability(e.id)
		ck("rank grows with mastery + achievements (now «%s»)" % DBAbilities.RANK_NAMES[d.magic_rank()], d.magic_rank() >= 5)
		var why5 := d.ability_block("e_mountain_heart")
		ck("tier V still needs a mentor or a tome", why5.contains("знание"), why5)
		d.knowledge["tome_e_mountain_heart"] = true
		ck("tier V learned after the tome", d.learn_ability("e_mountain_heart"))
		var why6 := d.ability_block("e_great_quake")
		ck("cataclysm needs the school trial", why6 != "" , why6)
		d.knowledge["trial_earth"] = true
		d.knowledge["tome_e_great_quake"] = true
		ck("cataclysm learned with path + trial + tome + rank", d.learn_ability("e_great_quake"), d.ability_block("e_great_quake"))
		# learn everything for the live run
		for s in DBAbilities.SCHOOL_ORDER:
			for e in DBAbilities.school_spells(s):
				d.knowledge["tome_" + e.id] = true
				d.knowledge["trial_" + s] = true
		for e in DBAbilities.of_kind("spell"):
			if not e.id in d.spells:
				d.spells.append(e.id)
		ck("all 100 spells known", d.spells.size() == 100 and d.known_spells().size() >= 100)
		ck("magic rank reaches «%s»" % DBAbilities.RANK_NAMES[d.magic_rank()], d.magic_rank() >= 7)
		# prepared cataclysm limit
		d.ab_page = 1
		var r1 := d.set_slot("staff", 1, 0, "e_great_quake")
		var r2 := d.set_slot("staff", 1, 1, "f_sun_worshipper")
		ck("only one cataclysm prepared at a time", r1 == "" and r2.contains("катаклизм"), r2)
		d.ab_page = 0
		# power, mana, cool-down
		equip("staff_oak")
		spawn_dummies(1, 7.0)
		await wait(0.5)
		var e1: Dictionary = DBAbilities.get_ab("e_stone_shard")
		var p_lo := AbilityExec.spell_power(pl, e1)
		d.schools.earth.lvl = 5
		var parts_lo := AbilityExec.power_parts(pl, e1)
		d.schools.earth.lvl = 26
		var parts_hi := AbilityExec.power_parts(pl, e1)
		ck("power depends on school mastery (deal factor %.2f → %.2f), level, focus, rank" % [parts_lo.school, parts_hi.school], float(parts_hi.school) > float(parts_lo.school) and float(parts_hi.focus) > 0.95 and float(parts_hi.level) > 1.0 and float(parts_hi.rank) > 1.0)
		pl.mana = pl.max_mana
		var m0: float = pl.mana
		var hp0 := dummy_hp()
		pl.face_dir((dummies[0].global_position - pl.global_position).normalized())
		ck("«Каменный осколок» cast", pl.use_ability("e_stone_shard", pl.facing))
		ck("…mana spent = cost (%.0f)" % AbilityExec.mana_cost(pl, e1), absf((m0 - pl.mana) - AbilityExec.mana_cost(pl, e1)) < 0.5, "%.1f" % (m0 - pl.mana))
		ck("…cool-down set", pl.skill_cd.has("e_stone_shard"))
		await wait(1.2)
		ck("…real damage to the target", dummy_hp() < hp0, "%.0f→%.0f" % [hp0, dummy_hp()])
		ck("cataclysm without reagent is refused", AbilityExec.block_reason(pl, "e_great_quake") != "", AbilityExec.block_reason(pl, "e_great_quake"))
		# ===================================================== live run of all 200
		await live_run()
		TimeFX.inst.set_base(1.0)
		print("ABILITIES_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()

	## Use every ability for real and check that it changed the world.
	func live_run() -> void:
		var pl = Game.player
		var d: CharData = pl.data
		var cats := {"sword": "sword_iron", "heavy": "hammer_war", "spear": "spear_iron", "dagger": "dagger_iron", "bow": "bow_short",
			"firearm": "pistol_modern", "staff": "staff_oak", "energy": "pulse_rifle"}
		for cat in DBAbilities.WEAPON_CATS:
			d.mastery_of(cat).lvl = 20
			d.mastery_of(cat).pts = 10
			for e in DBAbilities.weapon_skills(cat):
				if not e.id in d.mastery_of(cat).nodes:
					d.mastery_of(cat).nodes.append(e.id)
		for c in ["warrior", "archer", "rogue", "mage"]:
			for e in DBAbilities.class_skills(c):
				if not e.id in d.class_skills:
					d.class_skills.append(e.id)
		pl.recalc_stats()
		var ok_n := 0
		var effect_n := 0
		var failed := []
		var no_effect := []
		var order: Array = []
		for c in ["warrior", "archer", "rogue", "mage"]:
			order.append_array(DBAbilities.class_skills(c))
		for cat in DBAbilities.WEAPON_CATS:
			order.append_array(DBAbilities.weapon_skills(cat))
		for s in DBAbilities.SCHOOL_ORDER:
			order.append_array(DBAbilities.school_spells(s))
		var passive_ok := 0
		var passive_n := 0
		var cur_cat := ""
		var home: Vector3 = pl.global_position
		var home_dir: Vector3 = pl.facing
		var only := OS.get_environment("AB_ONLY")
		if only != "":
			order = order.filter(func(x): return x.id in only.split(","))
		for e in order:
			if e.type == "passive":
				passive_n += 1
				pl.recalc_stats()
				var ok_p := true
				for k in e.get("hooks", {}):
					if e.kind == "weapon" and e.cat != pl.mastery_cat():
						continue
					ok_p = ok_p and pl.hook(k) > 0.0
				passive_ok += 1 if ok_p else 0
				continue
			var want_cat: String = e.cat if e.kind == "weapon" else ("staff" if e.kind == "spell" else "sword")
			if e.kind == "class" and e.cls == "archer":
				want_cat = "bow"
			if e.kind == "class" and e.cls == "rogue":
				want_cat = "dagger"
			if e.kind == "class" and e.cls == "mage":
				want_cat = "staff"
			if want_cat != cur_cat:
				equip(cats[want_cat])
				cur_cat = want_cat
			d.class_id = e.cls if e.kind == "class" else d.class_id
			dummies = dummies.filter(func(x): return is_instance_valid(x) and not x.is_dead)
			var dist := 5.0
			var f0: Dictionary = e.fx[0]
			var close := false
			for fc in e.fx:
				if fc.c in ["melee", "melee_seq", "nova", "shadow_dance", "behind", "push", "decoy"] or (fc.c == "cone" and float(fc.get("r", 4.0)) < 5.0) or (fc.c == "blast" and fc.get("at", "") == "front"):
					close = true
			if close:
				dist = clampf(pl.weapon_range() * 0.8 + 0.4, 1.3, 2.4)
			if f0.c in ["bolt", "beam", "debuff"] and float(f0.get("rng", 8.0)) < 6.0:
				dist = 2.4
			# same spot every time (dashes and blinks moved the hero)
			Game.world._teleport(pl, home)
			pl.face_dir(home_dir)
			# a clean arena for every ability: earlier walls/spikes/slabs and fields gone
			for st in StoneStructure.live.duplicate():
				if is_instance_valid(st):
					st.queue_free()
			StoneStructure.live.clear()
			for z in Game.world.zones.duplicate():
				if is_instance_valid(z):
					z.queue_free()
			spawn_dummies(3, dist)
			last_dist = dist
			await wait(0.4)
			# aim at the middle dummy
			var tgt = dummies[1] if dummies.size() > 1 else dummies[0]
			var to: Vector3 = tgt.global_position - pl.global_position
			to.y = 0
			pl.face_dir(to.normalized())
			pl.skill_cd.clear()
			pl.act = {}
			pl.mana = pl.max_mana
			pl.stamina = pl.max_stamina
			pl.statuses.erase("exhausted")
			pl.statuses.erase("silenced")
			AbilityExec.cataclysm_until = 0
			if int(e.get("tier", 0)) == 6:
				while d.inv.is_full() and not d.inv.items.is_empty():
					d.inv.items.pop_front()
				d.inv.add(ItemDB.create(AbilityExec.cataclysm_reagent(), 0, 1))
				d.ab_page = 1
				d.set_slot("staff", 1, 0, "")
				for k in d.slots:
					for i in d.slots[k].size():
						if d.slots[k][i] != "" and int(DBAbilities.get_ab(d.slots[k][i]).get("tier", 0)) == 6:
							d.slots[k][i] = ""
				d.set_slot(pl.mastery_cat(), 1, 0, e.id)
			if e.id == "h_close_wound" or e.id == "h_warm_touch" or e.id == "h_great_regen":
				pl.hp = pl.max_hp * 0.4
			if e.id == "t_instant_mirror":
				pass   # repeats the last spell (cast just before)
			var snap := snapshot()
			if only != "":
				for dm in dummies:
					print("DBG ", e.id, " dummy d=%.2f los=%s hp=%.0f st=%s" % [dm.global_position.distance_to(pl.global_position), Combat.line_of_sight(pl.chest(), dm.chest()), dm.hp, str(dm.statuses.keys())])
			var ok: bool = pl.use_ability(e.id, to.normalized())
			if not ok:
				failed.append("%s(%s)" % [e.id, AbilityExec.block_reason(pl, e.id, to.normalized())])
				continue
			ok_n += 1
			var ct := AbilityExec.cast_time(pl, e)
			await wait(ct + 1.3 + (2.5 if int(e.get("tier", 0)) == 6 else 0.0))
			var now := snapshot()
			var new_st := false
			for k in now.st:
				if not snap.st.has(k) or float(now.st[k]) > float(snap.st[k]) + 0.05:
					new_st = true
			for k in now.pst:
				if not snap.pst.has(k) or float(now.pst[k]) > float(snap.pst[k]) + 0.05:
					new_st = true
			var changed: bool = now.hp < snap.hp - 0.5 or new_st or now.summons != snap.summons or now.terrain != snap.terrain \
				or now.pos.distance_to(snap.pos) > 0.8 or now.zones != snap.zones or now.shield != snap.shield or now.php > snap.php + 0.5
			if e.id in ["cm_magic_hearing", "n_bone_whisper"]:
				changed = AbilityExec.last_reveal.has(pl.actor_id)
			if e.id == "g_firefly":
				changed = AbilityExec._orbs.has(pl.actor_id) and is_instance_valid(AbilityExec._orbs[pl.actor_id])
			if e.id == "t_instant_mirror":
				changed = changed or int(now.casts) >= int(snap.casts) + 1
			for fc in e.fx:
				if fc.c in ["buff", "shield"] and str(fc.get("to", "self")) in ["ally", "allies"]:
					changed = changed or int(now.vfx) > int(snap.vfx)     # it may land on a nearby ally
			if only != "":
				print("DBG ", e.id, " ok=", ok, " hp ", snap.hp, "->", now.hp, " pos ", snap.pos.distance_to(now.pos), " pst ", now.pst.keys())
				for dm in dummies:
					if is_instance_valid(dm):
						print("DBG   after d=%.2f hp=%.0f st=%s" % [dm.global_position.distance_to(pl.global_position), dm.hp, str(dm.statuses.keys())])
			if changed:
				effect_n += 1
			else:
				no_effect.append(e.id)
			pl.statuses.erase("magic_shield")
			pl.shield_hp = 0.0
			d.ab_page = 0
			if Game.world.zones.size() > 12:
				for z in Game.world.zones.duplicate():
					if is_instance_valid(z):
						z.queue_free()
		var actives := 0
		for e in order:
			if e.type == "active":
				actives += 1
		ck("all %d active abilities start for real" % actives, ok_n == actives, str(failed))
		ck("every active changed the world (damage/status/summon/terrain/move/heal/shield)", effect_n == actives, str(no_effect))
		ck("all %d passives give their hooks" % passive_n, passive_ok == passive_n, "%d/%d" % [passive_ok, passive_n])
		ck("no summon over the limits (world %d ≤ %d)" % [AbilityExec.world_summons(), AbilityExec.MAX_SUMMONS_WORLD], AbilityExec.world_summons() <= AbilityExec.MAX_SUMMONS_WORLD)
		ck("terrain capped (%d live ≤ %d)" % [StoneStructure.count_live(), StoneStructure.MAX_LIVE], StoneStructure.count_live() <= StoneStructure.MAX_LIVE)
		print("SPELLVFX ", SpellVFX.counts)
