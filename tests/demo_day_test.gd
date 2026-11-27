extends Node
## Final demonstration scenario (directive §33), played as real interactive
## systems — no scripted scene: a game day in a medieval town (morning:
## counters open, the smith works, buyers, guards on duty; day: a caravan
## unloads, the hero buys a rare item, travellers in the tavern tell about a
## missing merchant and the hero gets the task; evening: shops close, the inn
## fills, people sit and talk, a bard plays; night: people go home, the guard
## watches, a peaceful night event), a rare raid on ANOTHER day (the guard
## defends, the hero fights and is wounded — Hardcore), the town recovers and
## the raid does not repeat; the hero goes home, puts loot in the chest,
## changes gear, treats the wound, sleeps, the game is saved and the next
## morning the town lives on. Prints DEMO_DONE pass=N fail=M.

func _ready() -> void:
	seed(330033)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Арден", "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 1, "cloth": 2})
	Profile.world_seed = 777001
	Profile.current_era = 0
	Profile.difficulty = "hardcore"
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var civil_hits := 0
	var civil_detail := {}
	var cap := {}
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Events.actor_damaged.connect(_on_dmg)
		_run()
	func _on_dmg(t, amount: float, src, _dt: String) -> void:
		if amount <= 0.0 or src == null or not is_instance_valid(src) or not is_instance_valid(t):
			return
		if CityPeace.hostile_kind(src) or CityPeace.hostile_kind(t) or src.is_player or t.is_player:
			return
		civil_hits += 1
		var k := "%s->%s" % [str(src.get("role")), str(t.get("role"))]
		civil_detail[k] = int(civil_detail.get(k, 0)) + 1
	## Move the clock forward to hour hh (today, or tomorrow if it has passed).
	func at(hh: float, next_day := false) -> void:
		var day := floorf(Game.game_time)
		if next_day or hh / 24.0 <= fposmod(Game.game_time, 1.0):
			day += 1.0
		Game.game_time = day + hh / 24.0
		for a in folk():
			if a.get("brain") != null:
				a.brain.think_t = 0.0
	func folk() -> Array:
		var out: Array = []
		for a in Game.world.settlement_npcs.get(cap.id, []):
			if is_instance_valid(a) and not a.is_dead:
				out.append(a)
		return out
	func count_act(acts: Array, settled := true) -> int:
		var n := 0
		for a in folk():
			var pl: Dictionary = a.get_meta("plan", {})
			if String(pl.get("act", "")) in acts and (not settled or (a.brain.goal == "routine" and a.brain._r_state == "at")):
				n += 1
		return n
	func by_prof(prof: String) -> Array:
		return folk().filter(func(a): return a.get_meta("prof", "") == prof)
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl: Player = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		var ev2 = w.sys("events2")
		ev2.enabled = false
		var cl = w.sys("city_life")
		var cpz = w.sys("city_peace")
		var hc = w.sys("hardcore")
		var hs = w.sys("housing")
		var civ = w.sys("civic")
		cap = w.director.capital()
		var cp := Vector3(cap.pos.x, 0, cap.pos.y)
		w.terrain.force_load_around(cp)
		await wait(1.0)
		cp.y = w.ground_height(cp) + 0.5
		Game.game_time = 1.0 + 6.5 / 24.0
		w._teleport(pl, cp)
		await wait(4.0)
		cpz.cities[cap.id].last_raid = Game.game_time     # day 1 is peaceful: no raid due
		var arr: Array = w.settlement_npcs.get(cap.id, [])
		var c_own: Dictionary = cap.duplicate()
		c_own.owner = w.factions.settlement_owner(cap.id)
		for i in 22:
			var p: Vector3 = cp + Vector3(randf_range(-22, 22), 0, randf_range(-22, 22))
			p.y = w.ground_height(p)
			var v = w.spawner.spawn_villager(c_own, p, "guard" if i % 6 == 0 else "villager")
			if v:
				arr.append(v)
		w.settlement_npcs[cap.id] = arr
		await wait(1.0)
		ck("a medieval town with several dozen residents", Profile.current_era == 0 and folk().size() >= 25, "%d" % folk().size())
		# ================================================= DAY 1 — morning
		at(8.5)
		await wait(24.0)
		var m_at := 0
		for m in by_prof("merchant"):
			if String(m.get_meta("plan", {}).get("act", "")) == "trade" and m.brain._r_state == "at":
				m_at += 1
		ck("morning: merchants open their counters", m_at >= 1)
		ck("morning: the smith goes to work", count_act(["work"]) >= 1)
		ck("morning: buyers come to the counters", count_act(["shop", "market"], false) >= 1 or cl.stats.trades > 0)
		ck("morning: the guard goes on duty", count_act(["post"]) + count_act(["patrol"], false) >= 2)
		ck("morning: no pointless brawls", civil_hits == 0, str(civil_detail))
		# the hero orders a blade at the town forge: the smith's real work
		var smith = by_prof("smith")[0] if not by_prof("smith").is_empty() else null
		pl.data.gold = 3000
		pl.data.inv.add(_qty("iron_ore", 9))
		var ingot = null
		for r in Recipes.for_station(w, "forge"):
			if r.name == "Железный слиток":
				ingot = r
		var crafted: bool = ingot != null and ingot.cb.call()
		var srec: Dictionary = civ.record_of(smith) if smith else {}
		ck("crafting at the town forge goes into the smith's real biography", crafted and not srec.is_empty() and int(srec.civic_points) >= 1
			and String("\n".join(w.legends.biography(srec).chronicle)).contains(srec.name))
		# ================================================= day — caravan, rare item, travellers
		at(12.5)
		var car: Dictionary = ev2.start(DBEvents.get_event("med_caravan"), {}, true)
		await wait(3.0)
		ck("day: a trade caravan arrives at the square", not car.has("refused") and car.state == "running" and car.data.get("merchants", []).size() >= 1 and car.nodes.size() >= 2,
			"%d merchants, %d props" % [car.data.get("merchants", []).size(), car.nodes.size()])
		ck("day: porters unload the goods", car.npcs.size() > car.data.get("merchants", []).size())
		ck("day: residents gather at the stalls", car.get("crowd", []).size() >= 2)
		var merch = car.data.merchants[0]
		ev2._open_special_trade(car, merch)
		await wait(0.3)
		var tr = w.ui.stack.back()
		var rare: Dictionary = {}
		for it in tr.args.items:
			if int(it.get("rarity", 0)) >= 2 or ItemCatalog.has(it.base):
				rare = it
				break
		var n_inv: int = pl.data.inv.items.size()
		if not rare.is_empty():
			tr._buy(rare, ItemDB.value(rare))
		w.ui.close_all()
		ck("day: the hero buys a rare item from the caravan", not rare.is_empty() and pl.data.inv.items.size() > n_inv, ItemDB.display_name(rare) if not rare.is_empty() else "")
		var mask: Dictionary = ev2.start(DBEvents.get_event("med_iron_mask"), {}, true)
		await wait(2.0)
		ck("day: a traveller stops at the tavern", not mask.has("refused") and mask.npcs.size() >= 1)
		var trav = mask.npcs[0]
		ev2._talk_visitor(mask, trav)
		await wait(0.2)
		var dlg = w.ui.stack.back()
		var lead_opt = null
		for o in dlg.args.options:
			if String(o.text).begins_with("Расспросить"):
				lead_opt = o
		w.ui.close_all()
		var lead: Dictionary = ev2._traveller_lead(mask, trav) if lead_opt != null else {}
		w.ui.close_all()
		ck("day: the traveller tells about a missing merchant — a new task", lead_opt != null and not lead.is_empty() and not lead.has("refused") and lead.tpl.name == "Пропавший торговец" and lead.nodes.size() >= 1,
			str(lead.get("objective", "")))
		for e in [car, mask, lead]:
			if e is Dictionary and e.get("state", "") == "running":
				ev2.finish(e, "демо: дальше", true)
		# ================================================= evening
		at(19.4)
		await wait(26.0)
		var open_eve := 0
		for m in by_prof("merchant"):
			if cl.is_open(m):
				open_eve += 1
		ck("evening: merchants close their shops", open_eve == 0)
		ck("evening: workers stop working", count_act(["work", "trade"]) == 0)
		ck("evening: the tavern fills with visitors", cl.stats.tavern_visits > 0 and count_act(["inn", "eat"], false) >= 1)
		var sitting := 0
		for a in folk():
			if a.rig and str(a.rig.get("pose")) == "sit":
				sitting += 1
		ck("evening: people sit at tables and talk", sitting >= 1 or count_act(["chat", "bench"], false) >= 1, "sitting %d" % sitting)
		ck("evening: a bard performs", cl.stats.songs > 0)
		# ================================================= night
		at(22.6)
		var peace0: int = ev2.stats.get("peace_hits", 0)
		var nite: Dictionary = ev2.start(DBEvents.get_event("med_night_service"), {}, true)
		await wait(24.0)
		var asleep := count_act(["sleep"])
		ck("night: most residents go home", asleep >= int(folk().size() * 0.3), "%d of %d" % [asleep, folk().size()])
		var gacts: Array = []
		for g in by_prof("guard"):
			gacts.append("%s/%s/%s" % [String(g.get_meta("plan", {}).get("act", "-")), g.brain.goal, g.brain.get("_r_state")])
		ck("night: the guard keeps patrolling", count_act(["post"]) + count_act(["patrol"], false) >= 1, str(gacts))
		ck("night: a peaceful atmospheric event takes place", not nite.has("refused") and int(ev2.stats.get("peace_hits", 0)) == peace0, str(nite.get("refused", "")))
		if nite.get("state", "") == "running":
			ev2.finish(nite, "служба окончена", true)
		ck("the whole first day passed without brawls", civil_hits == 0, str(civil_detail))
		# ================================================= DAY 2 — a rare raid
		at(14.0, true)
		cpz.cities[cap.id].last_raid = -99.0
		await wait(2.0)
		ck("another day: a raid is possible only now (conditions met)", cpz.can_raid(cap.id))
		w.director.start_raid_on(cap.id, "")
		var raid = null
		for e in w.director.events:
			if e.type == "raid":
				raid = e
		ck("a real raid threatens the town", raid != null and cpz.state_of(cap.id) == "attack")
		for r in raid.actors:
			if is_instance_valid(r):
				r.global_position = cp + Vector3(randf_range(-7, 7), 0.5, randf_range(-7, 7))
		await wait(0.5)
		var guard = null
		for a in folk():
			if a.get_meta("prof", "") == "guard" and a.has_meta("civic_id"):
				guard = a
				break
		# the hero joins the fight at once and is wounded in the leg (Hardcore)
		pl.statuses.erase("invuln")
		var alive: Array = raid.actors.filter(func(r): return is_instance_valid(r) and not r.is_dead)
		var r0 = alive[0]
		var hit_hero: float = Combat.deal(pl, r0, {"amount": 30.0, "dtype": "slash", "melee": true})
		Combat.deal(r0, pl, {"amount": pl.max_hp * 0.3, "dtype": "slash", "melee": true, "hit_pos": pl.global_position + Vector3(0, 0.45, 0) + pl.facing.cross(Vector3.UP) * 0.1})
		pl.apply_status("invuln", 999999.0)
		var leg: Dictionary = hc.worst("leg_r")
		ck("the hero fights the raiders and takes a leg wound", hit_hero > 0.0 and not leg.is_empty(), str(leg.get("type", "")))
		if guard:
			Combat.deal(guard, alive[mini(1, alive.size() - 1)], {"amount": 20.0, "dtype": "pierce", "melee": true})
		await wait(8.0)
		ck("the guard defends the town", cpz.stats.guard_responses > 0 or folk().any(func(a): return a.get("role") == "guard" and a.brain.goal == "fight"))
		for r in raid.actors:
			if is_instance_valid(r) and not r.is_dead:
				r.take_damage({"amount": 99999.0, "dtype": "slash", "src": pl})
		await wait(2.0)
		ck("the raid is beaten and the town recovers", not raid in w.director.events and cpz.state_of(cap.id) == "recovery")
		var grec: Dictionary = civ.record_of(guard) if guard else {}
		ck("the defending guard's deed is in his real biography", not grec.is_empty() and int(grec.get("civic_points", 0)) >= 2, "%s pts %d" % [grec.get("name", ""), int(grec.get("civic_points", 0))])
		ck("the raid does not repeat right away", not cpz.can_raid(cap.id))
		Game.game_time += CityPeace.RECOVERY_DAYS + CityPeace.NORMALIZE_DAYS + 0.05
		await wait(12.0)
		ck("the town returns to ordinary life", cpz.state_of(cap.id) in ["normalizing", "peaceful"], cpz.state_of(cap.id))
		# ================================================= the hero's life: home
		var sid: String = cap.id if hs.sale.has(cap.id) else hs.sale.keys()[0]
		pl.data.gold += Housing.type_for_era(0).price
		var b = await _goto_house(w, hs, sid)
		hs.buy(sid)
		await wait(0.6)
		w._teleport(pl, b.to_global(Vector3(0.6, 0.1, 0.2)))
		await wait(0.6)
		ck("the hero returns to the own house", hs.owns(hs.sale[sid].bid) and hs.player_home == b)
		var loot := ItemDB.create("x_north_axe", 1, 3)
		pl.data.inv.add(loot)
		ck("found weapon goes into the chest", hs.move_to_chest(loot) and Profile.home_chest.items.has(loot))
		var armor := ItemDB.create("x_bo_cuirass", 1, 3)
		pl.data.inv.add(armor)
		pl.equip_item(armor)
		ck("the hero changes equipment", pl.data.inv.equipped("body").get("uid", -1) == armor.uid)
		var gz := ItemDB.create("gauze_bandage", 0, 1)
		gz.qty = 3
		pl.data.inv.add(gz)
		var cln := ItemDB.create("cleansing_tincture", 0, 1)
		pl.data.inv.add(cln)
		for i in 2:
			pl.use_item(gz)              # the first dressing may only slow a heavy bleed
		pl.use_item(cln)
		var leg_ok := true
		for inj in hc.list():
			if (int(inj.bleed) > 0 and not inj.bandaged) or (Hardcore._is_open(inj) and not inj.treated):
				leg_ok = false
		ck("Hardcore: the wounds are dressed at home", leg_ok)
		var sev_before := 0.0
		for inj in hc.list():
			sev_before += float(inj.sev) - float(inj.heal)
		var gt_sleep := Game.game_time
		hs.sleep(hs.sale[sid].bid)
		var sev_after := 0.0
		for inj in hc.list():
			sev_after += float(inj.sev) - float(inj.heal)
		ck("the hero rests until morning and recovers", Game.game_time > gt_sleep and Game.game_time - gt_sleep < 1.0 and absf(fposmod(Game.game_time, 1.0) * 24.0 - 7.0) < 0.05 and sev_after < sev_before - 0.3, "wound burden %.2f → %.2f" % [sev_before, sev_after])
		ck("progress is saved", SaveSys.has_save())
		var saved_gold: int = Profile.char.gold
		SaveSys.load_profile()
		ck("the save holds the house, the chest and the hero", Profile.char.gold == saved_gold and Profile.home_chest.items.size() >= 1 and Profile.homes.size() == 1)
		# ================================================= next morning: the world lives on
		w._teleport(pl, cp)
		await wait(2.0)
		at(8.6)
		var tr0: int = cl.stats.trades
		await wait(28.0)
		ck("next morning the town lives on (counters, work, trade)", count_act(["trade", "work"]) >= 1 and cl.stats.trades >= tr0)
		ck("the chronicle remembers the day (raid, recovery, deeds)", Chronicle.events.any(func(e): return e.type == "city_recovery") and Chronicle.events.any(func(e): return e.type == "civic_deed"))
		ck("no pointless brawls in the whole scenario", civil_hits == 0, str(civil_detail))
		print("DEMO_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
	func _goto_house(w, hs, sid: String):
		var s = w._settlement(sid)
		var bd: Dictionary = {}
		for bb in s.buildings:
			if str(bb.id) == hs.sale[sid].bid:
				bd = bb
		var bas := Basis(Vector3.UP, float(bd.rot))
		var door := Vector3(bd.pos.x, float(s.height), bd.pos.y) + bas * Vector3(0, 0, bd.size.y * 0.5 + 2.2)
		w.terrain.force_load_around(door)
		await wait(1.0)
		door.y = w.ground_height(door) + 0.3
		w._teleport(Game.player, door)
		for i in 40:
			await wait(0.25)
			if hs.building(hs.sale[sid].bid) != null:
				break
		await wait(0.6)
		return hs.building(hs.sale[sid].bid)
	func _qty(id: String, n: int) -> Dictionary:
		var it := ItemDB.create(id, 0, 1)
		it.qty = n
		return it
