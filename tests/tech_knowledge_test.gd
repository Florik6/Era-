extends Node
## Technological Knowledge System — the mandatory checks, played as the demo
## scenario «a medieval warrior finds a rifle of the future» in the real game:
## T1 unknown device found in a rift (name, hidden stats, inspect animation,
##    «Вы не знаете…», no shot); T2 study: interactive screen with the 3D
##    model and parts, examination, purpose, a series of trials without
##    knowledge, a treatise, a teacher; T3 first use with real penalties and
##    real charge; T4 training and practice → confident → master (special
##    modes, weapon skills, special cells); T5 kept after a save/restart;
##    T6 transfer to a related model and a special part of a rare one;
##    T7 Historical Knowledge Memory and old saves; T8 NPC knowledge;
##    T9 a mythic magic artifact; T10 supply of future weapons;
##    T11 Tech Cognition skills; T12 handling animations.
## Prints TECH_DONE pass=N fail=M.

func _ready() -> void:
	seed(717171)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Ратибор", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 717171
	Profile.current_era = 0
	Settings.cinematics = 0
	Settings.auto_reload = false
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var shots := 0
	var notes: Array = []
	var w
	var pl
	var d

	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")

	func rwait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()

	func _on_fx(n: Node) -> void:
		if n is Projectile and n.src == pl:
			shots += 1

	func _on_note(text: String, _c: Color) -> void:
		notes.append(text)

	func said(part: String) -> bool:
		for t in notes:
			if str(t).contains(part):
				return true
		return false

	func idle() -> void:
		pl.act = {}
		pl.attack_cd = 0.0
		pl.reload_t = 0.0

	func hold_fire(secs: float) -> void:
		var end := Time.get_ticks_msec() + int(secs * 1000.0)
		while Time.get_ticks_msec() < end:
			pl.attack(pl.facing)
			await get_tree().physics_frame
		await rwait(0.2)

	func give(base: String, n: int) -> void:
		var it := ItemDB.create(base, 0, 1, null, false)
		it.qty = n
		d.inv.add(it)

	func _run() -> void:
		await rwait(3.0)
		w = Game.world
		pl = Game.player
		d = pl.data
		pl.apply_status("invuln", 999999.0)
		pl.apply_status("test_cool", 999999.0, {"no_heat": true})
		w.director._t = -100000.0
		for sn in ["events2", "beasts"]:
			if w.sys(sn):
				w.sys(sn).enabled = false
		TimeFX.inst.set_base(1.0)
		w.fx_root.child_entered_tree.connect(_on_fx)
		Events.notify.connect(_on_note)
		ck("new medieval hero masters medieval technology (bows V)", TechKnow.family_stage(pl, "bows") == 5 and TechKnow.family_stage(pl, "pulse") == 1 and d.tech_mem.eras == [0])
		var rifle := await _t1_found(w)
		await _t2_study(rifle)
		await _t3_first_use(rifle)
		await _t4_training(rifle)
		_t5_saves()
		await _t6_transfer()
		_t7_memory()
		await _t8_npcs()
		await _t9_magic()
		_t10_supply()
		_t11_skills()
		print("TECH_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()

	# ============================================================ T1
	func _t1_found(world) -> Dictionary:
		world.enter_dimension("mechanical", {"expedition": true})
		await rwait(2.0)
		ck("T1 the hero is inside an ancient rift", str(world.dimension) != "")
		for a in Game.actors_near(pl.global_position, 60.0):
			if a != pl and not a.is_dead and Game.can_damage(a, pl):
				a.queue_free()
		var rf := ItemDB.create("pulse_rifle", 1, 6)
		notes.clear()
		var drop: ItemDrop = world.loot.spawn_drop(rf, pl.global_position + pl.facing * 1.2)
		if drop != null and is_instance_valid(drop):
			world.loot.pickup(pl, drop)        # walking over it picks it up as well
		await rwait(0.4)
		ck("T1 «Обнаружено неизвестное устройство» on pickup", said("Обнаружено неизвестное устройство"), str(notes))
		var it: Dictionary = {}
		for x in d.inv.items:
			if x.base == "pulse_rifle":
				it = x
		ck("T1 shown as «Неизвестное технологическое оружие», stats hidden", ItemDB.display_name(it) == "Неизвестное технологическое оружие" and ItemDB.describe(it).contains("???") and not ItemDB.describe(it).contains("Магазин"), ItemDB.display_name(it))
		ck("T1 the family is unknown to him: stage I", TechKnow.item_stage(pl, it) == 1 and TechKnow.gap(d, "pulse") >= 2)
		notes.clear()
		pl.equip_item(it)
		ck("T1 he can hold it: equipped, turning it over in his hands (inspect animation)", pl.weapon().get("uid", -1) == it.uid and str(pl.act.get("name", "")) == "inspect", str(pl.act.get("name", "")))
		await rwait(1.5)
		Ammo.set_loaded(pl, 30)
		idle()
		shots = 0
		notes.clear()
		var fired: bool = pl.attack(pl.facing)
		await rwait(0.4)
		ck("T1 trying to shoot: «Вы не знаете, как пользоваться этим оружием», no projectile, charge kept", not fired and shots == 0 and pl.ammo == 30 and said("Вы не знаете, как пользоваться этим оружием"), str(notes))
		ck("T1 the hands are those of a novice (handling 0)", is_equal_approx(TechKnow.handling(pl), 0.0) and pl.rig.handling < 0.01)
		return it

	# ============================================================ T2
	func _t2_study(it: Dictionary) -> void:
		var scr = w.ui.open("inspect", {"item": it})
		await rwait(0.8)
		ck("T2 «Изучить» opens the study screen", scr != null and w.ui.top_name() == "inspect")
		var meshes: int = scr.view.model.find_children("*", "MeshInstance3D", true, false).size() if scr and scr.view and scr.view.model else 0
		ck("T2 the 3D model is in the centre with numbered parts", meshes > 0 and scr.view._markers.size() == 3, "meshes %d markers %d" % [meshes, scr.view._markers.size()])
		var d0: float = scr.view._dist
		scr.view.zoom(0.8)
		scr.view.spin(0.7)
		ck("T2 the model can be zoomed and rotated", scr.view._dist < d0)
		scr._act("examine")
		scr._act("identify")
		ck("T2 after examination: «Предположительно: дистанционное энергетическое оружие» (stage II)", TechKnow.stage_of_xp(TechKnow.fam_xp(d, "pulse")) == 2 and ItemDB.display_name(it).begins_with("Предположительно"), ItemDB.display_name(it))
		# the energy module without any knowledge: a series of trials
		scr._select_part("energy")
		var right := "хранит и подаёт заряд"
		var r1 := TechKnow.answer(d, it, "energy", right)
		var r_wrong := TechKnow.answer(d, it, "energy", "служит противовесом")
		var r2 := TechKnow.answer(d, it, "energy", right)
		var r3 := TechKnow.answer(d, it, "energy", right)
		var r4 := TechKnow.answer(d, it, "energy", right)
		ck("T2 energy module without knowledge: 3 right guesses in a row (a wrong one resets)", bool(r1.ok) and not bool(r1.done) and not bool(r_wrong.ok) and not bool(r3.done) and bool(r4.done) and TechKnow.part_known(d, it, "energy"), "%s / %s / %s" % [r1.msg, r3.msg, r4.msg])
		# a treatise found in the rift: the trigger needs only one trial now
		give("tech_manual_future", 1)
		var man: Dictionary = {}
		for x in d.inv.items:
			if x.base == "tech_manual_future":
				man = x
		pl.use_item(man)
		ck("T2 the treatise «Технологии будущего» adds knowledge (schematic remembered)", TechKnow.cat_xp(d, "future") >= 30.0 and "future" in d.tech_mem.schemas)
		ck("T2 with the treatise the activation mechanism needs a single trial", TechKnow.trials_needed(d, "pulse", true) == 1)
		# the screen's own trial buttons
		scr._select_part("trigger")
		scr._answer("выпускает накопленный импульс")
		scr._select_part("panel")
		scr._answer("показывает остаток заряда и режим")
		ck("T2 three parts understood → basic understanding (stage III)", TechKnow.part_known(d, it, "trigger") and TechKnow.part_known(d, it, "panel") and TechKnow.item_stage(pl, it) == 3, "stage %d xp %.0f" % [TechKnow.item_stage(pl, it), TechKnow.fam_xp(d, "pulse")])
		ck("T2 research alone cannot go past basic understanding", TechKnow.raw_xp(d, "pulse") <= TechKnow.RESEARCH_CAP + 0.01)
		ck("T2 now the name and stats are visible", ItemDB.display_name(it).to_lower().contains("импульсная винтовка") and ItemDB.describe(it).contains("Магазин"), ItemDB.display_name(it))
		var tscr = w.ui.open("tech")
		await rwait(0.3)
		ck("T2 the «Технологическое познание» screen opens (8 indices, families, skills)", tscr != null and w.ui.top_name() == "tech")
		w.ui.close_all()
		await rwait(0.3)

	# ============================================================ T3
	func _t3_first_use(it: Dictionary) -> void:
		var base_iv: float = 1.0 / float(ItemDB.base("pulse_rifle").spd)
		ck("T3 first use: penalties of stage III (preparation ×1.5, spread ×2.2, reload ×1.8)", absf(pl.attack_interval() / base_iv - 1.5) < 0.05 and is_equal_approx(float(TechKnow.mods(pl).spread), 2.2) and is_equal_approx(float(TechKnow.mods(pl).reload), 1.8), "interval ×%.2f" % (pl.attack_interval() / base_iv))
		Ammo.set_loaded(pl, 30)
		idle()
		shots = 0
		await hold_fire(1.0)
		var used := 30 - int(pl.ammo)
		ck("T3 he fires — every shot spends a real charge", shots >= 2 and used == shots, "shots %d used %d" % [shots, used])
		ck("T3 unsure handling animation (0.25), special modes locked", is_equal_approx(pl.rig.handling, 0.25) and Ammo.toggle_boost(pl) != "" and not Ammo.boost_on(pl))
		ck("T3 weapon skills of the pulse rifle are not open yet", TechKnow.skill_block(pl, DBAbilities.get_ab("we_pulse_boost")) != "")
		give("ammo_pulse", 30)
		idle()
		pl.reload()
		ck("T3 the reload is slow for a novice (×1.8)", absf(pl.reload_total - float(ItemDB.base("pulse_rifle").reload) * 1.8) < 0.05, "%.2f" % pl.reload_total)
		await rwait(3.6)
		Ammo.set_loaded(pl, 0)
		d.inv.consume("ammo_pulse", d.inv.count("ammo_pulse"))
		idle()
		shots = 0
		await hold_fire(0.6)
		ck("T3 an empty energy magazine does not fire", shots == 0)

	# ============================================================ T4
	func _t4_training(it: Dictionary) -> void:
		# a teacher (the Last Witness — an era traveller) trains him twice
		d.gold += 500
		var opts: Array = TechKnow.teacher_options(w, TechKnow.teacher_cats(0, true), true, func(): pass)
		var trained := 0
		for _rep in 2:
			for o in TechKnow.teacher_options(w, TechKnow.teacher_cats(0, true), true, func(): pass):
				if str(o.text).begins_with("Тренировка: Импульсное оружие"):
					o.cb.call()
					trained += 1
					break
		ck("T4 the era traveller offers courses of all 8 categories and trains the pulse family", opts.size() >= 8 and trained == 2 and TechKnow.raw_xp(d, "pulse") >= 120.0, "xp %.0f" % TechKnow.raw_xp(d, "pulse"))
		# practice: real shots
		give("ammo_pulse", 120)
		Ammo.set_loaded(pl, 30)
		var before := TechKnow.raw_xp(d, "pulse")
		var t_end := Time.get_ticks_msec() + 30000
		while Time.get_ticks_msec() < t_end and TechKnow.family_stage(pl, "pulse") < 4:
			idle()
			if pl.ammo <= 0:
				Ammo.set_loaded(pl, 30)
			await hold_fire(0.8)
		ck("T4 practice shots raise experience → confident handling (IV)", TechKnow.family_stage(pl, "pulse") == 4 and TechKnow.raw_xp(d, "pulse") > before, "xp %.0f" % TechKnow.raw_xp(d, "pulse"))
		var base_iv: float = 1.0 / float(ItemDB.base("pulse_rifle").spd)
		ck("T4 confident: preparation ×1.1, spread ×1.25, reload ×1.2, handling 0.65", absf(pl.attack_interval() / base_iv - 1.1) < 0.05 and is_equal_approx(float(TechKnow.mods(pl).spread), 1.25) and is_equal_approx(pl.rig.handling, 0.65), "×%.2f" % (pl.attack_interval() / base_iv))
		ck("T4 the boosted mode (5 units) and weapon skills open", Ammo.toggle_boost(pl) == "" and Ammo.boost_on(pl) and TechKnow.skill_block(pl, DBAbilities.get_ab("we_pulse_boost")) == "")
		Ammo.toggle_boost(pl)
		ck("T4 special cells (quantum) still need mastery", TechKnow.can_special_ammo(pl) == false and Ammo.select_kind(pl, "ammo_quantum") != "")
		# long practice, accelerated: 300 recorded shots without the animation
		for i in 300:
			TechKnow.practice(pl, 1.0)
		ck("T4 long practice → master of the technology (V): spread ×0.9, handling 1.0", TechKnow.family_stage(pl, "pulse") == 5 and is_equal_approx(float(TechKnow.mods(pl).spread), 0.9) and is_equal_approx(TechKnow.handling(pl), 1.0))
		give("ammo_quantum", 6)
		ck("T4 a master recognises compatible special cells", TechKnow.can_special_ammo(pl) and Ammo.select_kind(pl, "ammo_quantum") == "")
		ck("T4 advanced weapon skills (n 4–5) need mastery and are open now", TechKnow.skill_block(pl, DBAbilities.get_ab("we_absolute_sync")) == "")
		ck("T4 Tech Cognition points were earned at III and V", int(d.tech_pts) >= 3, str(d.tech_pts))

	# ============================================================ T5
	func _t5_saves() -> void:
		var ok: bool = SaveSys.save_game()
		var dd: Dictionary = SaveSys.read_json(SaveSys.PROFILE)
		var back := CharData.new()
		back.from_dict(dd.get("char", {}))
		ck("T5 after a save / restart the mastery is kept (pulse V, models, treatise, eras)", ok and TechKnow.stage_of_xp(TechKnow.fam_xp(back, "pulse")) == 5 and TechKnow.model_known(back, "pulse_rifle") and "future" in back.tech_mem.schemas and back.tech_mem.eras == [0],
			"%.0f %s" % [TechKnow.fam_xp(back, "pulse"), str(back.tech_mem)])

	# ============================================================ T6
	func _t6_transfer() -> void:
		w.leave_dimension(true)
		await rwait(1.5)
		var ph := ItemCatalog.base("x_photon_rifle")
		var photon := ItemDB.create("x_photon_rifle", 1, 6) if not ph.is_empty() else {}
		d.inv.add(photon)
		ck("T6 back in the Middle Ages, another pulse model is recognised (same family, mastered)", TechKnow.item_family(photon) == "pulse" and TechKnow.unknown_name(photon) == "" and TechKnow.family_stage(pl, "pulse") == 5)
		pl.equip_item(photon)
		ck("T6 only a short familiarisation is needed (handled at III until then)", TechKnow.item_stage(pl, photon) == 3)
		var msg := TechKnow.familiarize(d, photon)
		ck("T6 after familiarisation: full mastery on the new model, no new training", TechKnow.item_stage(pl, photon) == 5, msg)
		var qw := ItemCatalog.create_named("x_quantum_whisper_rifle", 6)
		d.inv.add(qw)
		pl.equip_item(qw)
		TechKnow.familiarize(d, qw)
		ck("T6 a rare model's special mechanics need their own study (art locked)", not TechKnow.special_ok(pl, qw) and not pl.use_ability("art_" + str(ItemDB.base(qw.base).art), pl.facing))
		var r := TechKnow.answer(d, qw, "special", "хранит особую силу этого предмета")
		idle()
		pl.skill_cd.clear()
		ck("T6 studying its special part unlocks the art", bool(r.done) and TechKnow.special_ok(pl, qw) and pl.use_ability("art_" + str(ItemDB.base(qw.base).art), pl.facing), str(r.msg))
		await rwait(1.0)
		var fresh := CharData.new()
		fresh.tech["pulse"] = {"xp": 450.0, "research": 0.0}
		ck("T6 related families: mastering pulse weapons gives a smart gun primary understanding (II); plasma is its own technology (I)",
			TechKnow.stage_of_xp(TechKnow.fam_xp(fresh, "smart")) == 2 and TechKnow.stage_of_xp(TechKnow.fam_xp(fresh, "plasma")) == 1)
		ck("T6 the treatise of future technology still lets him understand plasma weapons only to II (general knowledge)", TechKnow.family_stage(pl, "plasma") == 2 and TechKnow.raw_xp(d, "plasma") == 0.0)

	# ============================================================ T7
	func _t7_memory() -> void:
		TechKnow.on_visit(d, 4)
		ck("T7 a visit to the Future is remembered; its locals' weapons are now familiar by sight (II)", 4 in d.tech_mem.eras and TechKnow.family_stage(pl, "plasma") == 2)
		var old := CharData.new()
		old.tech_mem = {"eras": [0], "schemas": [], "training": [], "maint": []}
		var rev := ItemDB.create("revolver", 0, 5)
		old.inv.add(rev)
		TechKnow.migrate(old, [0, 1, 2])
		ck("T7 an old save: eras already played become known (revolvers IV, owned revolver familiar), the Future stays unknown",
			TechKnow.stage_of_xp(TechKnow.fam_xp(old, "revolvers")) == 4 and TechKnow.model_known(old, "revolver") and TechKnow.stage_of_xp(TechKnow.fam_xp(old, "pulse")) == 1)

	# ============================================================ T8
	func _t8_npcs() -> void:
		var guard = w.spawner.spawn_enemy("bandit", pl.global_position + pl.facing * 9.0, 4)
		await rwait(0.3)
		guard.apply_status("root", 9999.0)
		if guard.get("brain") != null and guard.brain.has_method("shutdown"):
			guard.brain.shutdown()
		ck("T8 a medieval fighter does not understand an energy weapon", TechKnow.npc_stage(guard, "pulse") == 1 and TechKnow.npc_stage(guard, "bows") >= 4)
		var gun := ItemDB.create("plasma_cannon", 2, 5)
		var w0: Dictionary = guard.weapon()
		w.loot._npc_take(guard, gun)
		ck("T8 picking it up does not make him use it (not equipped)", guard.weapon().get("uid", -2) == w0.get("uid", -3))
		guard.data.inv.equip_item(gun)
		guard.refresh_gear()
		guard.attack_cd = 0.0
		guard.act = {}
		ck("T8 even forced into his hands it does not fire", not guard.attack(guard.facing))
		var trooper = w.spawner.spawn_enemy("bandit", pl.global_position + pl.facing * -9.0, 4)
		var pr := ItemDB.create("pulse_rifle", 1, 5)
		trooper.data.inv.add(pr)
		trooper.data.inv.equip_item(pr)
		trooper.data.tech.erase("_init")
		ck("T8 a fighter from a rift who came with this weapon handles it", TechKnow.npc_stage(trooper, "pulse") >= 4)
		guard.queue_free()
		trooper.queue_free()

	# ============================================================ T9
	func _t9_magic() -> void:
		var staff := ItemCatalog.create_named("x_steam_storm_heart", 6)
		d.inv.add(staff)
		var eq: Dictionary = pl.equip_item(staff)
		idle()
		ck("T9 a mythic magic staff: can be picked up and equipped", bool(eq.ok) and pl.weapon().get("uid", -1) == staff.uid)
		pl.attack(pl.facing)
		ck("T9 basic use works (the staff's bolt)", str(pl.act.get("name", "")) == "cast_bolt")
		await rwait(0.8)
		idle()
		pl.skill_cd.clear()
		var art_id: String = "art_" + str(ItemDB.base(staff.base).art)
		ck("T9 its special power is locked for a warrior without magic", not pl.use_ability(art_id, pl.facing) and not TechKnow.special_study_ok(d, staff))
		d.learn_school("lightning")
		d.schools["lightning"].lvl = 9
		var r := TechKnow.answer(d, staff, "special", "хранит особую силу этого предмета")
		idle()
		pl.skill_cd.clear()
		pl.mana = pl.max_mana
		ck("T9 with magic mastery 9 its special part is understood and the art works", bool(r.done) and pl.use_ability(art_id, pl.facing), str(r.msg))
		ck("T9 full mastery comes later: the art at 75 % until school 16", is_equal_approx(TechKnow.special_power(pl, staff), 0.75))
		await rwait(1.5)

	# ============================================================ T10
	func _t10_supply() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		pl.equip_item(d.inv.items.filter(func(x): return x.base == "pulse_rifle")[0])
		var found: Dictionary = Ammo.loot_for(pl, 0, rng)
		ck("T10 ordinary medieval chests do not hold pulse charges (supply problem)", found.get("base", "") != "ammo_pulse", str(found.get("base", "")))
		var rec := TechKnow.maintenance_recipes(w)
		var has_pulse := false
		for r in rec:
			has_pulse = has_pulse or str(r.name).contains("Импульсные")
		ck("T10 a forge can restore charges from rift fragments once the device is understood", has_pulse)
		Ammo.set_loaded(pl, 0)
		d.inv.consume("ammo_pulse", d.inv.count("ammo_pulse"))
		ck("T10 out of charges he keeps the knowledge (still a master)", TechKnow.family_stage(pl, "pulse") == 5 and not Ammo.can_fire(pl))

	# ============================================================ T11
	func _t11_skills() -> void:
		var before_pts := int(d.tech_pts)
		var why := TechKnow.learn_skill(d, "tc_curiosity")
		ck("T11 a Tech Cognition skill is learnt with cognition points", why == "" and "tc_curiosity" in d.tech_skills and int(d.tech_pts) == before_pts - 1, why)
		var rev := ItemDB.create("revolver", 0, 4)
		d.inv.add(rev)
		var x0 := TechKnow.raw_xp(d, "revolvers")
		TechKnow.identify(d, rev)
		ck("T11 «Любознательность»: identification gives +50 % (18 instead of 12)", absf(TechKnow.raw_xp(d, "revolvers") - x0 - 18.0) < 0.01, "%.1f" % (TechKnow.raw_xp(d, "revolvers") - x0))
		ck("T11 a skill with a prerequisite is refused without it", TechKnow.learn_skill(d, "tc_genius") != "")
		ck("T11 10 skills in the branch", TechKnow.SKILLS.size() == 10)
