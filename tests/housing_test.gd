extends Node
## Player housing: a house for sale in town, buying sets real ownership, the
## door opens only for the owner, no NPC gets in or uses it in routines, the
## house is a safe zone, the personal chest (move / split / merge / sort /
## filter / capacity upgrades), furniture placement and pick-up, weapon racks,
## the med station, sleeping until morning with autosave and Hardcore
## recovery, and ownership + chest + furniture surviving save/load and an era
## change there and back. Prints HOUSING_DONE pass=N fail=M.

func _ready() -> void:
	seed(606060)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Домовладелец", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
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
	func frames(n: int) -> void:
		for i in n:
			await get_tree().physics_frame
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func _goto_house(w, hs, sid: String):
		var s = w._settlement(sid)
		var bd: Dictionary = {}
		for b in s.buildings:
			if str(b.id) == hs.sale[sid].bid:
				bd = b
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
	func _inside_point(b) -> Vector3:
		var p: Vector3 = b.to_global(Vector3(0.6, 0.1, 0.2))
		return p
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl: Player = Game.player
		var hs: Housing = w.sys("housing")
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		ck("housing subsystem attached", hs != null and Housing.inst == hs)
		ck("towns have a house for sale", hs.sale.size() >= 1 and Housing.private_ids.size() == hs.sale.size(), "%d" % hs.sale.size())
		var cap: Dictionary = w.director.capital()
		var sid: String = str(cap.id)
		if not hs.sale.has(sid):
			sid = hs.sale.keys()[0]
		var bid: String = hs.sale[sid].bid
		# NPC routines never use the house
		var t: Dictionary = CityLife.inst.town(sid) if CityLife.inst else {}
		var spot_in := 0
		for k in t.get("spots", {}):
			for sp in t.spots[k]:
				if sp.bid == bid:
					spot_in += 1
		ck("CityLife gives the house no residents or spots", spot_in == 0 and not t.get("homes", []).has(bid))
		var b = await _goto_house(w, hs, sid)
		ck("the house exists in the world with a sale sign and a closed door", b != null and b.door_node != null and b.door_node.lock == "closed" and hs._dressed.get(bid, "") == "sale")
		var bot_home := false
		for n in w.settlement_npcs.get(sid, []):
			if is_instance_valid(n) and n.get("brain") != null and n.brain._home_building() == b:
				bot_home = true
		ck("no NPC treats the house as its home", not bot_home)
		# buying
		pl.data.gold = 10
		ck("buying without money is refused", not hs.buy(sid) and not hs.owns(bid))
		pl.data.gold = 5000
		var bought: bool = hs.buy(sid)
		await wait(0.6)
		var t0: Dictionary = Housing.type_for_era(0)
		ck("buying sets real ownership", bought and hs.owns(bid) and Profile.homes.has(Housing.key(0, bid)) and pl.data.gold == 5000 - int(t0.price))
		ck("the door now opens only for the owner, the house is furnished", b.door_node.lock == "owner" and hs._dressed.get(bid, "") == "owned" and hs._props[bid].size() >= 3)
		# a villager placed inside is put out at once; the door stays shut for NPCs
		var intr = w.spawner.spawn_villager(w._settlement(sid), _inside_point(b), "villager")
		await wait(0.8)
		ck("an NPC inside the house is put out at once", is_instance_valid(intr) and not b.contains(intr.global_position) and hs.stats.evictions >= 1)
		intr.global_position = b.door_out
		await wait(0.5)
		ck("the door does not open for an NPC standing at it", b.door_node._door_open < 0.5)
		intr.queue_free()
		# go inside: safe zone
		w._teleport(pl, _inside_point(b))
		await wait(0.6)
		ck("inside the house is a safe zone", hs.player_home == b)
		var foe = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], b.door_out + Vector3(0, 0, 0.5), 3)
		foe.base_speed = 0.0
		await frames(3)
		var hp0: float = pl.hp
		var dealt: float = Combat.deal(foe, pl, {"amount": 40.0, "dtype": "slash", "melee": true})
		ck("nobody can hurt the owner inside", dealt == 0.0 and pl.hp == hp0)
		foe.queue_free()
		# the chest
		var sword := ItemDB.create("x_border_sword", 1, 3)
		pl.data.inv.add(sword)
		var med := ItemDB.create("linen_bandage", 0, 1)
		med.qty = 8
		pl.data.inv.add(med)
		ck("chest capacity comes from the house", hs.chest_capacity() == int(t0.cap))
		var mv1: bool = hs.move_to_chest(sword)
		var mv2: bool = hs.move_to_chest(med, 3)
		ck("items move into the chest (whole and split stacks)", mv1 and mv2 and Profile.home_chest.items.has(sword) and Profile.home_chest.count("linen_bandage") == 3 and pl.data.inv.count("linen_bandage") == 5)
		hs.move_to_chest(pl.data.inv.items.filter(func(x): return x.base == "linen_bandage")[0])
		Profile.home_chest.merge_stacks()
		ck("stacks merge in the chest", Profile.home_chest.count("linen_bandage") == 8 and Profile.home_chest.items.filter(func(x): return x.base == "linen_bandage").size() == 1)
		Profile.home_chest.sort_items("type")
		ck("chest sorts and filters", ItemFilter.group_of(Profile.home_chest.items[0]) == "weapon" and ItemFilter.apply(Profile.home_chest.items, "medicine", "бинт").size() == 1)
		var st = w.ui.open("storage", {"bid": bid})
		await frames(3)
		ck("the storage screen shows bag and chest", st._chest_box.get_child_count() >= 2 and String(st._chest_lbl.text).contains("Сундук"))
		w.ui.close_all()
		hs.upgrade(bid, "storage")
		ck("storage upgrade adds 20 places", hs.chest_capacity() == int(t0.cap) + 20)
		ck("taking back from the chest works", hs.move_to_bag(sword) and pl.data.inv.items.has(sword))
		# furniture
		for id in ["x_traveler_bed", "x_oak_chest", "x_sword_mount", "x_mason_hearth"]:
			pl.data.inv.add(ItemDB.create(id, 0, 1))
		var chest_it: Dictionary = pl.data.inv.items.filter(func(x): return x.base == "x_oak_chest")[0]
		var why_door: String = hs.place(bid, chest_it, Vector3(b.door_x, 0, b.d * 0.5 - 1.0), 0.0)
		ck("furniture cannot block the door", why_door != "" and pl.data.inv.items.has(chest_it), why_door)
		var why_ok: String = hs.place(bid, chest_it, Vector3(b.w * 0.5 - 1.0, 0, 0.2), 0.0)
		ck("a chest is placed and saved", why_ok == "" and hs.home(bid).furniture.size() == 1 and not pl.data.inv.items.has(chest_it), why_ok)
		ck("a placed chest adds capacity", hs.chest_capacity() == int(t0.cap) + 20 + 20)
		# live placement mode with the ghost
		var rack_it: Dictionary = pl.data.inv.items.filter(func(x): return x.base == "x_sword_mount")[0]
		w._teleport(pl, b.to_global(Vector3(-0.4, 0.1, 0.6)))
		pl.facing = (b.to_global(Vector3(-0.4, 0, -0.9)) - pl.global_position).normalized()
		pl.facing.y = 0
		pl.facing = pl.facing.normalized()
		await frames(2)
		hs.start_placing(bid, rack_it)
		await frames(4)
		hs.rotate_placing()
		await frames(2)
		ck("placement mode shows a ghost and a status bar", hs.placing.has("ghost") and is_instance_valid(hs.placing.ghost) and is_instance_valid(hs.placing.bar))
		var conf: String = hs.confirm_placing()
		ck("confirming places the rack where the ghost was", conf == "" and hs.home(bid).furniture.size() == 2, conf)
		var rack: Dictionary = hs.home(bid).furniture[1]
		var rack_node = null
		for p in hs._props[bid]:
			if is_instance_valid(p) and p.kind == "furniture" and p.entry == rack:
				rack_node = p
		var wpn := ItemDB.create("x_north_axe", 1, 3)
		rack.items.append(wpn)
		if rack_node:
			rack_node.rebuild()
		await frames(2)
		ck("a weapon rack shows the mounted weapon", rack_node != null and rack_node.find_children("Weapon", "Node3D", true, false).size() >= 1)
		var hearth_it: Dictionary = pl.data.inv.items.filter(func(x): return x.base == "x_mason_hearth")[0]
		hs.place(bid, hearth_it, Vector3(-0.6, 0, -0.2), 0.0)
		var n_f: int = hs.home(bid).furniture.size()
		var picked: bool = hs.pick_up(bid, int(rack.uid))
		ck("furniture can be picked up (with what is on it)", picked and hs.home(bid).furniture.size() == n_f - 1 and pl.data.inv.items.has(wpn) and pl.data.inv.items.filter(func(x): return x.base == "x_sword_mount").size() == 1)
		# sleeping until morning, with Hardcore recovery and autosave
		Profile.difficulty = "hardcore"
		var hc = w.sys("hardcore")
		hc.list().clear()
		var inj: Dictionary = hc.add_injury("leg_l", "bruise", 2)
		inj.heal = 0.0
		Game.game_time = floor(Game.game_time) + 22.0 / 24.0
		pl.hp = pl.max_hp * 0.3
		var gt0 := Game.game_time
		var hours: float = hs.sleep(bid)
		var h_now := fposmod(Game.game_time, 1.0) * 24.0
		ck("sleeping in the own bed lasts until 7:00 and restores health", absf(h_now - 7.0) < 0.05 and hours > 8.5 and pl.hp >= pl.max_hp - 0.5, "%.1f h, now %.2f" % [hours, h_now])
		ck("rest at home heals injuries (Hardcore)", not hc.list().has(inj) or int(inj.sev) < 2)
		ck("sleeping saved the game", SaveSys.has_save())
		# med station in the house treats wounds
		var ms := ItemDB.create("x_home_med_station", 0, 1)
		pl.data.inv.add(ms)
		var why_ms: String = hs.place(bid, ms, Vector3(b.w * 0.5 - 1.0, 0, b.d * 0.5 - 1.6), 0.0)
		var cut: Dictionary = hc.add_injury("arm_r", "cut", 2)
		var ms_node = null
		for p in hs._props[bid]:
			if is_instance_valid(p) and p.kind == "furniture" and str(p.entry.get("base", "")) == "x_home_med_station":
				ms_node = p
		if ms_node:
			hs.use_prop(ms_node)
		ck("the home med station treats wounds", why_ms == "" and ms_node != null and cut.bandaged and cut.treated, why_ms)
		Profile.difficulty = "normal"
		hc.list().clear()
		# NPCs living their day near the house never get in
		var ev0: int = hs.stats.evictions
		w._teleport(pl, b.door_out + (b.door_out - b.door_in).normalized() * 6.0)
		for n in w.settlement_npcs.get(sid, []):
			if is_instance_valid(n) and n.get("brain") != null:
				n.brain.think_t = 0.0
		var inside_seen := 0
		for i in 40:
			await wait(0.5)
			for a in Game.actors_near(b.global_position, 12.0):
				if a != pl and not a.is_dead and b.contains(a.global_position):
					inside_seen += 1
		ck("during 20 s of town life no NPC is inside the house", inside_seen == 0 and hs.stats.evictions - ev0 <= 1, "seen %d, evictions %d" % [inside_seen, hs.stats.evictions - ev0])
		# save / load
		SaveSys.save_game()
		var n_chest: int = Profile.home_chest.items.size()
		var n_furn: int = hs.home(bid).furniture.size()
		Profile.homes = {}
		Profile.home_chest = Inventory.new()
		SaveSys.load_profile()
		ck("ownership, furniture and chest survive save and load", hs.owns(bid) and hs.home(bid).furniture.size() == n_furn and Profile.home_chest.items.size() == n_chest, "%d furn %d chest" % [hs.home(bid).furniture.size(), Profile.home_chest.items.size()])
		# era change there and back: nothing is lost
		Profile.unlock_era(1)
		w.change_era(1)
		await wait(4.0)
		w = Game.world
		hs = w.sys("housing")
		ck("after moving to another era the house and the chest are still owned", Profile.homes.has(Housing.key(0, bid)) and Profile.home_chest.items.size() == n_chest and hs.owned_here().is_empty())
		ck("the new era offers its own house kind", Housing.type_for_era(1).name == "Каменный городской дом")
		w.change_era(0)
		await wait(4.0)
		w = Game.world
		hs = w.sys("housing")
		var sid2 := ""
		for k in hs.sale:
			if hs.sale[k].bid == bid:
				sid2 = k
		ck("back in the first era the same house is there and owned", sid2 != "" and hs.owns(bid) and hs.home(bid).furniture.size() == n_furn)
		if sid2 != "":
			var b2 = await _goto_house(w, hs, sid2)
			ck("…with its lock, props and furniture rebuilt", b2 != null and b2.door_node.lock == "owner" and hs._dressed.get(bid, "") == "owned" and hs._props[bid].size() >= 3 + n_furn)
		print("HOUSING_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
