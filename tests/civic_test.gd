extends Node
## Peaceful careers (Living Legends link): townsfolk get a persistent identity
## per town and profession; only real deeds (crafting at the forge, trade,
## healing, raid defence, events) give points, are written to the Chronicle
## and the NPC's biography, raise the rank and finally make a living legend
## (legendary armourer, captain of the guard…). No deeds — no fame.
## Prints CIVIC_DONE pass=N fail=M.

func _ready() -> void:
	seed(808080)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Заказчик", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 777001
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
	func _ready() -> void:
		_run()
	func prof_npc(w, sid: String, prof: String):
		for n in w.settlement_npcs.get(sid, []):
			if is_instance_valid(n) and not n.is_dead and n.get_meta("prof", "") == prof:
				return n
		return null
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		w.sys("events2").enabled = false
		var civ: CivicLegends = w.sys("civic")
		ck("civic careers subsystem attached", civ != null and CivicLegends.inst == civ)
		var cap: Dictionary = w.director.capital()
		var cp := Vector3(cap.pos.x, 0, cap.pos.y)
		w.terrain.force_load_around(cp)
		await wait(1.0)
		cp.y = w.ground_height(cp) + 0.5
		Game.game_time = 1.0 + 10.0 / 24.0
		w._teleport(pl, cp)
		await wait(5.0)
		for n in w.settlement_npcs.get(cap.id, []):
			if is_instance_valid(n) and CityLife.inst:
				CityLife.inst.assign(n)
		var smith = prof_npc(w, cap.id, "smith")
		var merchant = prof_npc(w, cap.id, "merchant")
		var healer = prof_npc(w, cap.id, "healer")
		var guard = prof_npc(w, cap.id, "guard")
		ck("townsfolk with a profession get a persistent record", smith != null and smith.has_meta("civic_id") and merchant != null and merchant.has_meta("civic_id") and guard != null and guard.has_meta("civic_id"))
		var srec: Dictionary = civ.record_of(smith)
		ck("a new smith starts as an apprentice, without fame", int(srec.civic_rank) == 0 and int(srec.civic_points) == 0 and not srec.legend and String(smith.display_name).contains("подмастерье"), smith.display_name)
		# crafting at the town forge = real deeds
		for i in 3:
			civ.on_craft(ItemDB.create("x_border_sword", 1, 3))
		ck("helping the hero three times makes him a smith", int(srec.civic_rank) == 1 and String(smith.display_name).contains("кузнец"), smith.display_name)
		ck("each deed is a Chronicle entry with him as the actor", Chronicle.events.filter(func(e): return e.type == "civic_deed" and e.actors.has(srec.id)).size() == 3)
		for i in 3:
			civ.on_craft(ItemDB.create("x_ash_king_blade", 4, 5))
		ck("rare weapons made in his forge make him a legendary armourer", srec.legend and String(srec.title) == "Легендарный оружейник" and Chronicle.events.any(func(e): return e.type == "legend_born" and e.actors.has(srec.id)), str(srec.title))
		ck("he is listed among the living legends", w.legends.legends().any(func(r): return r.id == srec.id))
		var bio: Dictionary = w.legends.biography(srec)
		ck("his biography is made of his real deeds", bio.chronicle.size() >= 7 and String("\n".join(bio.chronicle)).contains("Клинок Пепельного Короля"), "%d lines" % bio.chronicle.size())
		# merchant: real trade only
		var mrec: Dictionary = civ.record_of(merchant)
		civ.on_trade(merchant, 650)
		ck("a merchant earns a deed per ~300 coins of real trade", int(mrec.civic_points) == 2 and int(mrec.trade_acc) == 50, "pts %d acc %d" % [int(mrec.civic_points), int(mrec.get("trade_acc", 0))])
		if healer:
			civ.on_trade(healer, 900)
		ck("trade does not count for a non-merchant", healer == null or int(civ.record_of(healer).civic_points) == 0)
		if healer:
			civ.on_heal(healer)
			ck("healing the hero is the healer's deed", int(civ.record_of(healer).civic_points) == 1)
		# guards: only those who really fought raiders
		var grec: Dictionary = civ.record_of(guard)
		var raider = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], guard.global_position + Vector3(2, 0, 0), 1)
		await wait(0.3)
		civ.on_attack_end(cap.id, "налёт отбит")
		ck("a guard who did not fight gets nothing", int(grec.civic_points) == 0)
		Combat.deal(guard, raider, {"amount": 5.0, "dtype": "pierce", "melee": true})
		civ.on_attack_end(cap.id, "налёт отбит")
		ck("a guard who defended the town is rewarded (deed + biography)", int(grec.civic_points) == 2 and Chronicle.events.any(func(e): return e.type == "civic_deed" and e.actors.has(grec.id)))
		for i in 4:
			Combat.deal(guard, raider, {"amount": 5.0, "dtype": "pierce", "melee": true})
			civ.on_attack_end(cap.id, "налёт отбит")
		ck("several defences make him captain of the town guard", grec.legend and String(grec.title) == "Капитан городской стражи", str(grec.title))
		raider.queue_free()
		# no deeds, no fame
		var bard = prof_npc(w, cap.id, "bard")
		if bard:
			var brec: Dictionary = civ.record_of(bard)
			ck("without deeds nobody becomes famous", int(brec.civic_rank) == 0 and not brec.legend)
		# identity survives the town being unloaded and repopulated
		var sname: String = srec.name
		for n in w.settlement_npcs.get(cap.id, []):
			if is_instance_valid(n):
				n.queue_free()
		w.settlement_npcs.erase(cap.id)
		await wait(0.5)
		w._populate_settlement(w._settlement(cap.id))
		await wait(0.5)
		for n in w.settlement_npcs.get(cap.id, []):
			if is_instance_valid(n) and CityLife.inst:
				CityLife.inst.assign(n)
		var smith2 = prof_npc(w, cap.id, "smith")
		ck("on the next visit the same smith works there (name and record)", smith2 != null and smith2 != smith and smith2.get_meta("civic_id", "") == srec.id and String(smith2.data.name) == sname and String(smith2.display_name).contains("легендарный оружейник"), str(smith2.display_name if smith2 else ""))
		# event explorers get their own record
		var e := {"tpl": DBEvents.get_event("med_lost_dog"), "data": {"host": smith2}, "sid": cap.id, "pos": cp, "result": "пёс найден"}
		var host = w.spawner.spawn_villager(w._settlement(cap.id), cp + Vector3(3, 0, 0), "villager")
		e.data.host = host
		civ.on_event_done(e, true)
		var hrec: Dictionary = civ.record_of(host)
		ck("a successful search makes the event's person an explorer with a real record", not hrec.is_empty() and String(hrec.civic) == "explorer" and int(hrec.civic_points) == 2)
		print("CIVIC_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
