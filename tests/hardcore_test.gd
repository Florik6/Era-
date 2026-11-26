extends Node
## Hardcore Mode: the normal mode is untouched; in Hardcore hits wound body
## zones taken from combat data (projectile impact point, melee strike point)
## or estimated from the attack direction; injury types, severity, bleeding,
## infection and worsening by game time, stat penalties, treatment with the
## right items / healer / capsule / rest, HP potions not curing wounds, the
## X-ray anatomy screen (markers, tap, rotate, zoom, apply), save / load.
## Prints HARDCORE_DONE pass=N fail=M.

func _ready() -> void:
	seed(424242)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Ранимый", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 515151
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
		await get_tree().create_timer(s, true, false, true).timeout
	func frames(n: int) -> void:
		for i in n:
			await get_tree().physics_frame
	func _ready() -> void:
		_run()
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl: Player = Game.player
		var hc: Hardcore = w.sys("hardcore")
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		ck("hardcore subsystem attached", hc != null and Hardcore.inst == hc)
		# ---------------- normal mode is untouched
		ck("a new character starts in the normal mode", Profile.difficulty == "normal" and not hc.enabled())
		var foe = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], pl.global_position + Vector3(0, 0, -2.0), 1)
		foe.base_speed = 0.0
		await frames(3)
		var mhp0: float = pl.max_hp
		var sp0: float = pl.speed()
		Combat.deal(foe, pl, {"amount": pl.max_hp * 0.4, "dtype": "slash", "melee": true, "hit_pos": pl.global_position + Vector3(0.3, 1.2, 0)})
		await frames(2)
		ck("normal mode: hits leave no injuries and no penalties", hc.list().is_empty() and is_equal_approx(pl.max_hp, mhp0) and is_equal_approx(pl.speed(), sp0))
		var scr0 = w.ui.open("anatomy")
		await frames(2)
		ck("normal mode: anatomy screen says Hardcore only", scr0.xray == null)
		w.ui.close_all()
		pl.hp = pl.max_hp * 0.5
		var hpa: float = pl.hp
		var bnd := ItemDB.create("linen_bandage", 0, 1)
		pl.data.inv.add(bnd)
		pl.use_item(bnd)
		ck("normal mode: medicine simply heals", pl.hp > hpa)
		# ---------------- Hardcore
		Profile.difficulty = "hardcore"
		pl.hp = pl.max_hp
		pl.recalc_stats()
		var base_max: float = pl.max_hp
		var base_speed: float = pl.speed()
		var base_dmg: float = pl.stat("dmg_pct")
		var base_st: float = pl.max_stamina
		ck("hardcore enabled", hc.enabled() and Hardcore.active())
		# zone from the impact point (collision data)
		var zones := {}
		for pair in [[Vector3(0, 1.62, 0), "head"], [Vector3(0, 1.25, 0), "chest"], [Vector3(0, 0.95, 0), "abdomen"], [Vector3(0, 0.4, 0), "leg"],
				[Vector3(0, 1.25, 0) + pl.facing.cross(Vector3.UP) * 0.32, "arm_r"], [Vector3(0, 1.25, 0) - pl.facing.cross(Vector3.UP) * 0.32, "arm_l"]]:
			var z: Dictionary = hc.zone_of(pl, {"hit_pos": pl.global_position + pair[0], "melee": true}, foe, Vector3.ZERO)
			zones[pair[1]] = z
		ck("impact point decides the zone (head/chest/abdomen/legs/arms)", zones.head.zone == "head" and zones.chest.zone == "chest" and zones.abdomen.zone == "abdomen"
			and String(zones.leg.zone).begins_with("leg") and zones.arm_r.zone == "arm_r" and zones.arm_l.zone == "arm_l" and zones.head.how == "collision", str(zones))
		# a real arrow at head height hits the head
		var archer = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], pl.global_position + pl.facing * 9.0, 1)
		archer.base_speed = 0.0
		await frames(3)
		var from: Vector3 = pl.global_position + pl.facing * 6.0 + Vector3(0, 1.66, 0)
		var target: Vector3 = pl.global_position + Vector3(0, 1.66, 0)
		Projectile.spawn(archer, from, (target - from).normalized() * 40.0, {"amount": pl.max_hp * 0.2, "dtype": "pierce"}, "arrow", {"range": 12.0})
		await wait(0.6)
		ck("a real arrow at head height wounds the head (projectile impact point)", hc.last_hit.get("how", "") == "collision" and hc.last_hit.get("zone", "") == "head" and not hc.worst("head").is_empty(), str(hc.last_hit))
		ck("the arrow made a stab wound", hc.worst("head").get("type", "") == "stab")
		# melee from a low creature bites the legs (strike point from the swing)
		var wolf = null
		for id in DBEras.era(0).enemies:
			if DBActors.ENEMIES.get(id, {}).get("kind", "") == "creature" or str(id).contains("wolf"):
				wolf = w.spawner.spawn_enemy(id, pl.global_position - pl.facing * 1.4, 1)
				break
		if wolf:
			wolf.base_speed = 0.0
			await frames(3)
			wolf.facing = (pl.global_position - wolf.global_position).normalized()
			pl.statuses.erase("invuln")
			var sp := Combat.strike_point(wolf, pl, "")
			var zw: Dictionary = hc.zone_of(pl, {"hit_pos": sp, "melee": true}, wolf, Vector3.ZERO)
			ck("a wolf's bite lands on the legs (creature strike height)", String(zw.zone).begins_with("leg"), "%s h=%.2f" % [zw.zone, float(zw.get("h", 0))])
			wolf.queue_free()
		# an overhead swing from a humanoid lands on the head
		var brute = w.spawner.spawn_villager(w.gen.settlements[0], pl.global_position + pl.facing * 1.3, "villager")
		await frames(3)
		var spo := Combat.strike_point(brute, pl, "overhead")
		var zo: Dictionary = hc.zone_of(pl, {"hit_pos": spo, "melee": true}, brute, Vector3.ZERO)
		ck("an overhead swing lands on the head", zo.zone == "head", "%s h=%.2f" % [zo.zone, float(zo.get("h", 0))])
		brute.queue_free()
		# no hit point: estimated from the attack direction, not a blind roll
		var right: Vector3 = pl.facing.cross(Vector3.UP).normalized()
		var side_src = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], pl.global_position + right * 2.0, 1)
		side_src.base_speed = 0.0
		await frames(3)
		var right_hits := 0
		var left_limb := 0
		for i in 60:
			var zd: Dictionary = hc.zone_of(pl, {"melee": false}, side_src, right)
			if String(zd.zone).ends_with("_r") or zd.zone in ["chest", "abdomen"]:
				right_hits += 1
			if String(zd.zone).ends_with("_l"):
				left_limb += 1
			hc.stats.hits += 1
		var zd2: Dictionary = hc.zone_of(pl, {"melee": false}, side_src, right)
		ck("without a hit point the zone is estimated from the direction (right side → right limbs)", zd2.how == "direction" and right_hits >= 42 and left_limb <= 12, "%d/60 right, %d left limbs" % [right_hits, left_limb])
		side_src.queue_free()
		# scratches leave nothing
		var n0: int = hc.list().size()
		Combat.deal(foe, pl, {"amount": pl.max_hp * 0.03, "dtype": "slash", "melee": true, "hit_pos": pl.global_position + Vector3(0, 1.25, 0)})
		ck("a scratch (3% HP) leaves no injury", hc.list().size() == n0 and hc.stats.scratches >= 1)
		# types and severity
		hc.list().clear()
		pl.hp = pl.max_hp
		pl.recalc_stats()
		var ra := pl.global_position + Vector3(0, 1.25, 0) + right * 0.32
		Combat.deal(foe, pl, {"amount": pl.max_hp * 0.25, "dtype": "slash", "melee": true, "hit_pos": ra})
		var cut: Dictionary = hc.worst("arm_r")
		ck("a sword blow on the right arm makes a bleeding cut", cut.get("type", "") == "cut" and int(cut.get("bleed", 0)) >= 1, str(cut))
		pl.hp = pl.max_hp
		Combat.deal(foe, pl, {"amount": pl.max_hp * 0.35, "dtype": "blunt", "melee": true, "knock": 8.0, "hit_pos": pl.global_position + Vector3(0, 0.45, 0) + right * 0.1})
		var fr: Dictionary = hc.worst("leg_r")
		ck("a heavy blunt blow on the leg breaks it", fr.get("type", "") == "fracture", str(fr))
		pl.hp = pl.max_hp
		Combat.deal(null, pl, {"amount": pl.max_hp * 0.2, "dtype": "fire"})
		var burn_found := false
		for inj in hc.list():
			burn_found = burn_found or inj.type == "burn"
		ck("burning ground burns (environment → legs)", burn_found and hc.last_hit.how == "environment" and String(hc.last_hit.zone).begins_with("leg"))
		pl.hp = pl.max_hp
		Combat.deal(foe, pl, {"amount": pl.max_hp * 0.3, "dtype": "dark", "hit_pos": pl.global_position + Vector3(0, 1.25, 0)})
		ck("dark magic leaves a magic injury (purple)", hc.worst("chest").get("type", "") == "magic" and Hardcore.color_of(hc.worst("chest")).b > 0.9)
		# stat penalties
		pl.recalc_stats()
		ck("right-arm cut lowers damage, leg fracture slows, injuries cut max stamina/HP",
			pl.stat("dmg_pct") < base_dmg - 0.04 and pl.speed() < base_speed * 0.8 and pl.max_hp <= base_max, "dmg %.2f→%.2f speed %.1f→%.1f" % [base_dmg, pl.stat("dmg_pct"), base_speed, pl.speed()])
		# bleeding drains HP; an HP potion heals HP but not the wounds
		var heavy: Dictionary = hc.add_injury("abdomen", "stab", 3, "тест")
		pl.hp = pl.max_hp
		var hp_b: float = pl.hp
		await wait(3.0)
		ck("heavy bleeding drains health every second", pl.hp < hp_b - pl.max_hp * 0.01 and hc.bleeding() == 3 and hc.unstable(), "%.0f → %.0f" % [hp_b, pl.hp])
		var n_before: int = hc.list().size()
		var pot := ItemDB.create("potion_hp", 0, 1)
		pl.data.inv.add(pot)
		pl.use_item(pot)
		ck("an HP potion does not cure injuries", hc.list().size() == n_before and hc.bleeding() == 3)
		# the wrong bandage does not stop heavy bleeding; the right one does
		var lin := ItemDB.create("linen_bandage", 0, 1)
		pl.data.inv.add(lin)
		var did_lin: bool = hc.apply_medicine(pl, "linen_bandage", ItemDB.base("linen_bandage").med, int(heavy.id))
		ck("a linen bandage cannot stop heavy bleeding", not heavy.bandaged)
		var hem: bool = hc.apply_medicine(pl, "hemostatic_dressing", ItemDB.base("hemostatic_dressing").med, int(heavy.id))
		ck("a hemostatic dressing stops it", hem and heavy.bandaged and hc.bleeding() < 3)
		var spl: bool = hc.apply_medicine(pl, "miner_medkit", ItemDB.base("miner_medkit").med, int(fr.id))
		ck("a medkit splints the fracture (speed penalty halves)", spl and fr.splinted)
		var mg: Dictionary = hc.worst("chest")
		var mg_sev := int(mg.sev)
		hc.apply_medicine(pl, "moon_salt_extract", ItemDB.base("moon_salt_extract").med, int(mg.id))
		ck("lunar salt heals the magic injury", int(mg.sev) < mg_sev)
		# light bleeding clots by itself (game time)
		hc.list().clear()
		var light: Dictionary = hc.add_injury("arm_l", "cut", 1)
		Game.game_time += Hardcore.CLOT_DAYS + 0.01
		await wait(2.5)
		ck("light bleeding stops by itself after a while (game time)", int(light.bleed) == 0)
		# infection develops by game time, worsens, and is cured by antiseptic
		var wound: Dictionary = hc.add_injury("leg_l", "cut", 2)
		wound.bandaged = true
		Game.game_time += 1.3
		await wait(2.5)
		ck("an untreated wound gets infected over game time", wound.infected, "infect %.2f" % float(wound.infect))
		var s_inf := int(wound.sev)
		Game.game_time += Hardcore.WORSEN_DAYS + 0.05
		await wait(2.5)
		ck("an infected wound worsens", s_inf == 2 and int(wound.sev) == 3, "%d → %d" % [s_inf, int(wound.sev)])
		var tin: bool = hc.apply_medicine(pl, "cleansing_tincture", ItemDB.base("cleansing_tincture").med, int(wound.id))
		var cured_by_tincture: bool = not wound.infected
		hc.apply_medicine(pl, "anti_infection_kit", ItemDB.base("anti_infection_kit").med, int(wound.id))
		ck("a weak tincture cannot cure infection, the anti-infection kit can", not cured_by_tincture and not wound.infected and wound.treated, "tincture %s" % str(tin))
		# rest speeds recovery; light wounds heal
		var bruise: Dictionary = hc.add_injury("head", "bruise", 1)
		hc.rest(8.0, 2)
		ck("rest heals a light bruise", not hc.list().has(bruise))
		# healer / doctor / capsule
		hc.add_injury("chest", "cut", 2)
		hc.add_injury("arm_r", "fracture", 2)
		var res: Dictionary = hc.treat_all("doctor")
		var all_ok := true
		for inj in hc.list():
			if (int(inj.bleed) > 0 and not inj.bandaged) or (inj.type == "fracture" and not inj.splinted) or (Hardcore._is_open(inj) and not inj.treated):
				all_ok = false
		ck("a doctor stops bleeding, cleans wounds and sets bones", all_ok and not res.done.is_empty(), str(res.done))
		hc.treat_all("capsule")
		ck("a medical capsule restores the body completely", hc.list().is_empty())
		# the town has a healer and the dialog treats for gold
		var healer = null
		for sid in w.settlement_npcs:
			for n in w.settlement_npcs[sid]:
				if is_instance_valid(n) and n.role == "healer":
					healer = n
		ck("towns have a healer / doctor", healer != null and String(healer.display_name).contains("знахарь"))
		if healer:
			hc.add_injury("leg_l", "cut", 2)
			pl.data.gold = 500
			w.dialogs.open_npc(healer)
			await frames(2)
			var dlg = w.ui.stack.back()
			var opt = null
			for o in dlg.args.options:
				if String(o.text).begins_with("Лечение"):
					opt = o
			if opt:
				opt.cb.call()
			w.ui.close_all()
			ck("the healer's treatment works and costs gold", opt != null and pl.data.gold < 500 and hc.bleeding() == 0)
		# ---------------- X-ray screen
		hc.list().clear()
		var ia: Dictionary = hc.add_injury("arm_r", "cut", 2)
		hc.add_injury("leg_l", "fracture", 3)
		hc.add_injury("head", "magic", 1)
		hc.add_injury("chest", "bruise", 1)
		var ch = w.ui.open("character", {"tab": "health"})
		await frames(3)
		var has_btn := false
		for b in ch.find_children("*", "Button", true, false):
			if (b as Button).text == "Анатомия" and not (b as Button).disabled:
				has_btn = true
		ck("Персонаж → Здоровье has the Анатомия button", has_btn)
		w.ui.close_all()
		var an = w.ui.open("anatomy")
		await frames(6)
		var xr: XrayView = an.xray
		ck("anatomy shows the translucent 3D body with 7 zone markers", xr != null and xr.rig != null and xr.markers.size() == 7)
		var lab_count := 0
		for z in xr.markers:
			lab_count += xr.markers[z].find_children("*", "Label3D", true, false).size()
		ck("injured zones carry text markers (not only colour)", lab_count == 4)
		var cols_ok: bool = Hardcore.color_of(hc.worst("chest")).is_equal_approx(Color(1.0, 0.9, 0.25)) and Hardcore.color_of(hc.worst("arm_r")).is_equal_approx(Color(1.0, 0.55, 0.15)) and Hardcore.color_of(hc.worst("leg_l")).is_equal_approx(Color(1.0, 0.18, 0.15)) and Hardcore.color_of(hc.worst("head")).b > 0.9
		ck("colours: yellow light, orange medium, red severe, purple magic", cols_ok)
		await frames(2)
		var p_leg: Vector2 = xr.zone_screen_pos("leg_l")
		var tap := InputEventScreenTouch.new()
		tap.index = 0
		tap.position = p_leg
		tap.pressed = true
		xr._gui_input(tap)
		tap = tap.duplicate()
		tap.pressed = false
		xr._gui_input(tap)
		await frames(2)
		ck("tapping a zone selects it and shows the injury", an._zone == "leg_l" and String(an._info.text).contains("Перелом") and String(an._info.text).contains("Шина"), "pos %s zone %s" % [str(p_leg), an._zone])
		var yaw0: float = xr._yaw
		var dist0: float = xr._dist
		xr._touches = {0: Vector2(100, 100)}
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.relative = Vector2(50, 0)
		drag.position = Vector2(150, 100)
		xr._gui_input(drag)
		xr._touches = {0: Vector2(100, 100), 1: Vector2(200, 100)}
		xr._pinch0 = 100.0
		var drag2 := InputEventScreenDrag.new()
		drag2.index = 1
		drag2.position = Vector2(260, 100)
		xr._gui_input(drag2)
		xr._touches = {}
		ck("drag rotates and pinch zooms the model", absf(xr._yaw - yaw0) > 0.3 and xr._dist < dist0, "yaw %.2f→%.2f dist %.2f→%.2f" % [yaw0, xr._yaw, dist0, xr._dist])
		# apply medicine from the screen
		pl.data.inv.add(_qty("gauze_bandage", 2))
		an._select("arm_r")
		await frames(2)
		var apply_btn: Button = null
		for b in an._treat.get_children():
			if b is Button and String(b.text).contains("Марлевый бинт"):
				apply_btn = b
		var cnt0: int = pl.data.inv.count("gauze_bandage")
		var found_btn: bool = apply_btn != null
		if apply_btn:
			apply_btn.pressed.emit()
		await frames(2)
		var texts: Array = []
		for b in an._treat.get_children():
			if b is Button:
				texts.append(b.text)
		ck("«Применить» uses the item on that wound", found_btn and ia.bandaged and pl.data.inv.count("gauze_bandage") == cnt0 - 1, "btn %s bandaged %s cnt %d→%d %s zone %s" % [str(found_btn), str(ia.bandaged), cnt0, pl.data.inv.count("gauze_bandage"), str(texts), an._zone])
		w.ui.close_all()
		# HUD chips
		ck("HUD shows injury chips", hc.hud_chips().size() >= 2)
		# ---------------- save / load
		SaveSys.save_game()
		var n_inj: int = hc.list().size()
		Profile.difficulty = "normal"
		Profile.char.injuries = []
		SaveSys.load_profile()
		ck("difficulty and injuries survive save and load", Profile.difficulty == "hardcore" and Profile.char.injuries.size() == n_inj and n_inj >= 3, "%d" % Profile.char.injuries.size())
		print("HARDCORE_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
	func _qty(id: String, n: int) -> Dictionary:
		var it := ItemDB.create(id, 0, 1)
		it.qty = n
		return it
