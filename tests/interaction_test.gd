extends Node
## Scripted end-to-end checks of the interactions that used to be broken:
##  A) rift portals: interaction button, entry, stages (guards → anchors →
##     echo boss), exit, safe return, no re-entry loop, walk-through entry,
##     retreat, death inside a rift, save while inside.
##  B) the ancient altar and curse cleansing (sword + armour, save/reload).
## Prints CHECK lines and INTERACTION_DONE pass=N fail=M.

var pass_n := 0
var fail_n := 0

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Тестер", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.current_era = 0
	Settings.cinematics = 1
	var h := Harness.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

func check(nm: String, ok: bool, extra := "") -> void:
	if ok:
		pass_n += 1
	else:
		fail_n += 1
	print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")

class Harness:
	extends Node
	var pass_n := 0
	var fail_n := 0
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	func frames(n: int) -> void:
		for i in n:
			await get_tree().physics_frame
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")

	func _close_ui() -> void:
		if Game.world and Game.world.ui:
			Game.world.ui.close_all()

	func _go_near(p: Vector3, off: Vector3) -> void:
		var w = Game.world
		var pl = Game.player
		var t := p + off
		w.terrain.force_load_around(t)
		t.y = w.ground_height(t) + 0.3
		w._teleport(pl, t)
		await frames(4)
		await wait(0.6)

	func _poi_node(id: String):
		var w = Game.world
		var n = w.poi_nodes.get(id)
		return n if n != null and is_instance_valid(n) else null

	func _kill_stage(dim) -> void:
		for a in dim.stage_enemies.duplicate():
			if is_instance_valid(a) and not a.is_dead:
				a.die(Game.player)
		await wait(0.8)

	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 9999.0)
		# keep ambient monsters from interfering with the scripted checks
		w.director.set_process(false)
		var rifts: Array = w.gen.pois.filter(func(p): return p.type == "rift")
		ck("world has rift portals", rifts.size() >= 2, "rifts=%d" % rifts.size())
		if rifts.size() < 2:
			_finish()
			return
		# ---------------------------------------------------------- A1: button + entry
		var r0: Dictionary = rifts[0]
		var rp := Vector3(r0.pos.x, 0, r0.pos.y)
		await wait(1.5)   # portals ignore the hero for a few seconds after loading
		await _go_near(rp, Vector3(3.0, 0, 0))
		var rn = _poi_node(r0.id)
		ck("rift POI node streamed in", rn != null)
		for a in Game.actors_near(pl.global_position, 30.0):
			if a != pl and a.kind != "boss":
				a.queue_free()
		await wait(0.5)
		ck("rift is the interaction target (button shown)", pl.interact_target == rn, "target=%s" % str(pl.interact_target))
		ck("rift label offers entry", pl.interact_label().begins_with("Войти"), pl.interact_label())
		ck("rift label shows danger + state", rn != null and rn._label.text.find("Опасность") >= 0, rn._label.text if rn else "")
		pl.do_interact()
		await wait(1.5)
		ck("entered a rift dimension", w.dimension != "" and w.dim_node != null, "dimension=" + w.dimension)
		var dim = w.dim_node
		if dim == null:
			_finish()
			return
		ck("player is inside the rift arena", dim != null and Vector2(pl.global_position.x - dim.center.x, pl.global_position.z - dim.center.z).length() < dim.radius)
		ck("camera follows player inside", w.cam.target == pl and w.cam.global_position.distance_to(pl.global_position) < 40.0)
		ck("rift has enemies, chests, traps", dim.stage_enemies.size() >= 5 and dim._trap_nodes.size() > 0)
		ck("retreat portal exists from the start", dim._retreat != null and is_instance_valid(dim._retreat))
		await _go_near(dim._retreat.global_position, Vector3(1.0, 0, 0))
		ck("retreat portal is interactable", pl.interact_target == dim._retreat, str(pl.interact_target))
		# ---------------------------------------------------------- A2: stages
		await _kill_stage(dim)
		await wait(0.7)
		ck("stage 2: three anchors spawned", dim.stage == 2 and dim.anchors.size() == 3, "stage=%d anchors=%d" % [dim.stage, dim.anchors.size()])
		var guard := 0
		while not dim.anchors.is_empty() and guard < 6:
			guard += 1
			var an = dim.anchors[0]
			await _go_near(an.global_position, Vector3(0.5, 0, 0.5))
			var t0 := Time.get_ticks_msec()
			while is_instance_valid(an) and an in dim.anchors and Time.get_ticks_msec() - t0 < 9000:
				await wait(0.25)
			if dim.stage == 2:
				for a in dim.stage_enemies.duplicate():
					if is_instance_valid(a) and not a.is_dead and not (a is Boss):
						a.die(pl)
		ck("anchors closed by standing in the circle", dim.anchors.is_empty())
		await wait(0.5)
		var boss = null
		for a in dim.stage_enemies:
			if is_instance_valid(a) and a is Boss:
				boss = a
		ck("stage 3: echo boss spawned", dim.stage == 3 and boss != null, "stage=%d" % dim.stage)
		var bosses_before: Dictionary = Game.world_state.bosses.duplicate(true)
		if boss:
			boss.die(pl)
		await wait(1.2)
		ck("rift completed, exit opened", dim.done)
		ck("echo boss did not mark the real boss defeated", Game.world_state.bosses.hash() == bosses_before.hash())
		var ex = null
		for c in dim.get_children():
			if c is Dimension.DimensionExit and not c.retreat:
				ex = c
		ck("exit portal spawned", ex != null)
		var inv_before: int = pl.data.inv.items.size()
		var xp_before: int = pl.data.xp
		var lvl_before: int = pl.data.level
		await _go_near(ex.global_position, Vector3(1.0, 0, 0))
		ck("exit portal is interactable", pl.interact_target == ex, str(pl.interact_target))
		pl.do_interact()
		await wait(1.0)
		ck("left the dimension", w.dimension == "" and w.dim_node == null)
		var back_d: float = Vector2(pl.global_position.x - rp.x, pl.global_position.z - rp.z).length()
		ck("returned next to the rift, outside its trigger", back_d > 3.0 and back_d < 9.0, "dist=%.1f" % back_d)
		ck("inventory, xp and level kept", pl.data.inv.items.size() >= inv_before and (pl.data.level > lvl_before or pl.data.xp >= xp_before))
		ck("camera snapped back to the player", w.cam.target == pl and w.cam.global_position.distance_to(pl.global_position) < 40.0)
		ck("rift reports closed after clearing", rn != null and rn.rift_block_reason() != "", rn.rift_block_reason() if rn else "")
		# stand right next to it for a while: no re-teleport loop
		await _go_near(rp, Vector3(1.0, 0, 0))
		pl.scripted_move = Vector3(-1, 0, 0)
		await wait(1.0)
		pl.scripted_move = Vector3.ZERO
		await wait(1.0)
		ck("no re-entry into a cleared rift", w.dimension == "")
		# ---------------------------------------------------------- A3: walk-through + death inside
		var r1: Dictionary = rifts[1]
		var rp1 := Vector3(r1.pos.x, 0, r1.pos.y)
		w.portal_block_until = 0
		await _go_near(rp1, Vector3(4.0, 0, 0))
		for a in Game.actors_near(pl.global_position, 30.0):
			if a != pl and a.kind != "boss":
				a.queue_free()
		await wait(0.4)
		var t1 := Time.get_ticks_msec()
		while w.dimension == "" and Time.get_ticks_msec() - t1 < 5000:
			var to: Vector3 = rp1 - pl.global_position
			to.y = 0
			pl.scripted_move = to.normalized()
			await get_tree().physics_frame
		pl.scripted_move = Vector3.ZERO
		await wait(1.0)
		ck("walking through the ring enters the rift", w.dimension != "")
		# save while inside → saved position is the outside return point
		SaveSys.save_game()
		var sp = Game.world_state.get("player_pos")
		ck("saving inside a rift stores the outside return point", sp is Array and Vector2(sp[0] - rp1.x, sp[2] - rp1.z).length() < 9.0)
		# death inside
		pl.statuses.erase("invuln")
		pl.hp = 1.0
		pl.take_damage({"amount": 99999.0, "dtype": "true", "src": null})
		await wait(2.4)
		ck("player died inside the rift", pl.is_dead)
		ck("death screen opened", w.ui.top_name() == "death", w.ui.top_name())
		w._respawn()
		_close_ui()
		await wait(1.0)
		ck("respawned in the world after rift death", not pl.is_dead and w.dimension == "" and w.dim_node == null)
		ck("controls released after respawn", not Game.ui_is_open())
		pl.apply_status("invuln", 9999.0)
		# ---------------------------------------------------------- B: altar
		await _altar_tests()
		_finish()

	# ============================================================== altar
	func _altar_tests() -> void:
		var w = Game.world
		var pl = Game.player
		var altars: Array = w.gen.pois.filter(func(p): return p.type == "altar")
		ck("world has altars", altars.size() > 0)
		if altars.is_empty():
			return
		var a0: Dictionary = altars[0]
		var ap := Vector3(a0.pos.x, 0, a0.pos.y)
		# 1-3: cursed sword found and equipped → bound
		var sword := ItemDB.create("sword_steel", 3, pl.level, null, false)
		sword.curse = {"id": "drain", "bound": true, "hidden": true, "release": "ritual"}
		sword["curse_boost"] = 1.3
		sword.stats.dmg = snappedf(sword.stats.dmg * 1.3, 0.01)
		var sword_dmg: float = sword.stats.dmg
		pl.data.inv.add(sword)
		var res: Dictionary = pl.equip_item(sword)
		ck("cursed sword equipped and bound", res.ok and res.get("bound", false) and pl.data.inv.is_bound("main"))
		# 4-5: trying to unequip is blocked with a reason
		var un: Dictionary = pl.unequip_slot("main") if pl.has_method("unequip_slot") else pl.data.inv.unequip("main")
		ck("unequipping the bound sword is blocked", not un.ok and String(un.msg).length() > 5, String(un.msg))
		var other := ItemDB.create("sword_iron", 0, 1, null, false)
		pl.data.inv.add(other)
		var sw: Dictionary = pl.equip_item(other)
		ck("replacing the bound sword is blocked", not sw.ok)
		# 6-7: walk to the altar → interaction button
		await _go_near(ap, Vector3(2.0, 0, 0))
		for a in Game.actors_near(pl.global_position, 30.0):
			if a != pl:
				a.queue_free()
		await wait(0.5)
		var an = _poi_node(a0.id)
		ck("altar is the interaction target", an != null and pl.interact_target == an, str(pl.interact_target))
		ck("altar button text", pl.interact_label() == "Использовать алтарь", pl.interact_label())
		# 8: the altar screen opens
		pl.do_interact()
		await wait(0.4)
		var scr = w.ui.get_screen("altar")
		ck("altar screen opened", scr != null)
		if scr == null:
			return
		# 9-10: the sword is listed; curse type + requirements visible
		var listed: Array = scr.cursed.map(func(e): return e.item.uid)
		ck("cursed sword listed at the altar", sword.uid in listed)
		scr.select_uid(sword.uid)
		await wait(0.1)
		ck("details panel shows the curse section", scr.details_text().find("Проклятие") >= 0)
		# identification of a hidden curse on an item in the bag
		var ring := ItemDB.create("ring_copper" if ItemDB.BASES.has("ring_copper") else "sword_iron", 2, 1, null, false)
		ring.curse = {"id": "hunted", "bound": false, "hidden": true, "release": "purify"}
		pl.data.inv.add(ring)
		scr.refresh()
		var rit: Array = Curses.rituals_for(ring, pl, "altar")
		var ids: Array = rit.map(func(r): return r.id)
		ck("unknown curse offers identification", "identify" in ids, str(ids))
		pl.data.gold = 0
		var idr: Dictionary = Curses.rituals_for(ring, pl, "altar").filter(func(r): return r.id == "identify")[0]
		ck("identification unavailable without gold", not idr.available)
		pl.data.gold = 5000
		idr = Curses.rituals_for(ring, pl, "altar").filter(func(r): return r.id == "identify")[0]
		ck("identification available with gold", idr.available, idr.reason)
		var gold0: int = pl.data.gold
		scr.start_ritual(ring.uid, "identify")
		await _wait_ritual()
		ck("curse identified", not ring.curse.get("hidden", true))
		ck("identification charged once", pl.data.gold == gold0 - int(idr.costs.gold), "%d → %d" % [gold0, pl.data.gold])
		# 11: requirements — break the bond first without resources
		_close_ui()
		pl.do_interact()
		await wait(0.3)
		scr = w.ui.get_screen("altar")
		rit = Curses.rituals_for(sword, pl, "altar")
		ids = rit.map(func(r): return r.id)
		ck("known strong curse offers great cleansing + bond break", "cleanse_great" in ids and "break_bond" in ids, str(ids))
		var br: Dictionary = rit.filter(func(r): return r.id == "break_bond")[0]
		ck("bond break blocked without ingredients", not br.available and br.reason != "", br.reason)
		var gold1: int = pl.data.gold
		var started: bool = scr.start_ritual(sword.uid, "break_bond")
		ck("ritual refuses to start without ingredients", not started and pl.data.gold == gold1)
		# give the ingredients
		for k in br.costs.items:
			var st := ItemDB.create(k, 0, 1)
			st.qty = int(br.costs.items[k])
			pl.data.inv.add(st)
		rit = Curses.rituals_for(sword, pl, "altar")
		br = rit.filter(func(r): return r.id == "break_bond")[0]
		ck("bond break available with ingredients", br.available, br.reason)
		# 12-13: ritual with animation; try to unequip mid-ritual
		started = scr.start_ritual(sword.uid, "break_bond")
		ck("bond-break ritual started", started)
		await wait(0.6)
		var ritual = w.get("active_ritual")
		ck("ritual animation node is running", ritual != null and is_instance_valid(ritual) and ritual.stage_reached >= 1)
		var mid: Dictionary = pl.unequip_slot("main")
		ck("gear locked during the ritual", not mid.ok)
		await _wait_ritual()
		ck("ritual played all visual stages", w.get("last_ritual_stages") != null and int(w.last_ritual_stages) >= 6, str(w.get("last_ritual_stages")))
		# 14-16: bond broken → can unequip & swap; negative effect still present
		ck("bond broken: no longer bound", not pl.data.inv.is_bound("main") and not sword.curse.get("bound", true))
		ck("bond break keeps the curse and the power", sword.curse.get("id", "") == "drain" and absf(sword.stats.dmg - sword_dmg) < 0.01)
		for k in br.costs.items:
			ck("ingredient %s consumed" % k, pl.data.inv.count(k) == 0)
		var sw2: Dictionary = pl.equip_item(other)
		ck("can now swap the sword for another weapon", sw2.ok and pl.data.inv.equipped("main").get("uid", -1) == other.uid)
		ck("old sword is back in the bag, not destroyed", pl.data.inv.find(sword.uid).size() > 0)
		# full cleanse of the same sword from the bag (great cleansing)
		_close_ui()
		var gr: Dictionary = Curses.rituals_for(sword, pl, "altar").filter(func(r): return r.id == "cleanse_great")[0]
		for k in gr.costs.items:
			var st2 := ItemDB.create(k, 0, 1)
			st2.qty = int(gr.costs.items[k])
			pl.data.inv.add(st2)
		pl.do_interact()
		await wait(0.3)
		scr = w.ui.get_screen("altar")
		ck("bag items are listed too", scr != null and sword.uid in scr.cursed.map(func(e): return e.item.uid))
		scr.start_ritual(sword.uid, "cleanse_great")
		await _wait_ritual()
		ck("great cleansing removed the curse", sword.curse.is_empty())
		ck("curse's share of power removed (balance)", sword.stats.dmg < sword_dmg - 0.01, "%.2f → %.2f" % [sword_dmg, sword.stats.dmg])
		# ---------------------------------------------------------- armour (simple cleansing + direct unequip)
		var armor := ItemDB.create("armor_leather" if ItemDB.BASES.has("armor_leather") else _any_armor(), 1, 1, null, false)
		armor.curse = {"id": "frail", "bound": true, "hidden": false, "release": "purify"}
		pl.data.inv.add(armor)
		var slot: String = ItemDB.base(armor.base).slot
		var ra: Dictionary = pl.equip_item(armor)
		ck("cursed armour equipped and bound", ra.ok and pl.data.inv.is_bound(slot), slot)
		ck("bound armour can't be removed", not pl.unequip_slot(slot).ok)
		var sr: Dictionary = Curses.rituals_for(armor, pl, "altar").filter(func(r): return r.id == "cleanse_simple")[0]
		for k in sr.costs.items:
			var st3 := ItemDB.create(k, 0, 1)
			st3.qty = int(sr.costs.items[k])
			pl.data.inv.add(st3)
		_close_ui()
		pl.do_interact()
		await wait(0.3)
		scr = w.ui.get_screen("altar")
		scr.start_ritual(armor.uid, "cleanse_simple")
		await _wait_ritual()
		ck("armour cleansed", armor.curse.is_empty())
		var ru: Dictionary = pl.unequip_slot(slot)
		ck("cleansed armour can be taken off", ru.ok, String(ru.get("msg", "")))
		ck("armour kept in the bag", pl.data.inv.find(armor.uid).size() > 0)
		# interruption: moving away cancels without charging
		var cursed2 := ItemDB.create("sword_iron", 2, 1, null, false)
		cursed2.curse = {"id": "clumsy", "bound": true, "hidden": false, "release": "purify"}
		pl.data.inv.add(cursed2)
		pl.equip_item(cursed2)
		var sr2: Dictionary = Curses.rituals_for(cursed2, pl, "altar").filter(func(r): return r.id == "cleanse_simple")[0]
		for k in sr2.costs.items:
			var st4 := ItemDB.create(k, 0, 1)
			st4.qty = int(sr2.costs.items[k])
			pl.data.inv.add(st4)
		var g2: int = pl.data.gold
		_close_ui()
		pl.do_interact()
		await wait(0.3)
		scr = w.ui.get_screen("altar")
		scr.start_ritual(cursed2.uid, "cleanse_simple")
		await wait(0.5)
		await _go_near(ap, Vector3(14.0, 0, 0))
		await _wait_ritual()
		ck("walking away interrupts the ritual", not cursed2.curse.is_empty())
		ck("interrupted ritual charged nothing", pl.data.gold == g2 and pl.data.inv.count("purify_salt") >= int(sr2.costs.items.get("purify_salt", 0)))
		# 17: save → reload profile → results persist
		SaveSys.save_game()
		var sword_uid: int = sword.uid
		var armor_uid: int = armor.uid
		ck("profile reload", SaveSys.load_profile())
		var inv2 = Profile.char.inv
		var s2: Dictionary = inv2.find(sword_uid)
		if s2.is_empty():
			for v in inv2.equip.values():
				if int(v.uid) == sword_uid:
					s2 = v
		var a2: Dictionary = inv2.find(armor_uid)
		ck("after reload: sword still cleansed", not s2.is_empty() and s2.get("curse", {}).is_empty())
		ck("after reload: armour still cleansed and unequipped", not a2.is_empty() and a2.get("curse", {}).is_empty())

	func _any_armor() -> String:
		for k in ItemDB.BASES:
			if ItemDB.BASES[k].get("slot", "") == "body":
				return k
		return "robe"

	func _wait_ritual() -> void:
		var t0 := Time.get_ticks_msec()
		await wait(0.2)
		while Game.world.get("active_ritual") != null and is_instance_valid(Game.world.active_ritual) and Time.get_ticks_msec() - t0 < 12000:
			await wait(0.2)
		await wait(0.3)

	func _finish() -> void:
		print("INTERACTION_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
