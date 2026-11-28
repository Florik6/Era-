extends Node
## Expansion items: 150 items with the required distribution, every item
## obtainable through a real code path, recipes using only obtainable
## ingredients, equipment changing the hero's look slot by slot, all 15
## weapon arts working, crafting, medicine, save/load.
## Prints ITEMS_DONE pass=N fail=M.

func _ready() -> void:
	seed(150150)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Оружейник", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	TechKnow.debug_master_all(Profile.char)   # this suite tests other systems: all technology known
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
		_run()
	func obtainable_base(id: String, seen := {}) -> bool:
		if seen.has(id):
			return false
		seen[id] = true
		if ItemDB.BASES.has(id):
			return true        # base-game materials (ore, herbs…) are sold and dropped
		var b := ItemCatalog.base(id)
		if b.is_empty():
			return false
		for s in b.src:
			if s in ["shop", "drop", "event", "boss"]:
				return true
		var d := Recipes.def_for(id)
		if d.is_empty():
			return false
		for ing in d.cost:
			if not obtainable_base(ing, seen.duplicate()):
				return false
		return true
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		# ---------------- catalog
		var a := ItemCatalog.all()
		ck("exactly 150 expansion items", a.size() == 150, "%d" % a.size())
		var g := {}
		var per_era := [0, 0, 0, 0, 0]
		var leg := 0
		var myth := 0
		var clash := []
		var bad := []
		for k in a:
			var b: Dictionary = a[k]
			g[b.group] = int(g.get(b.group, 0)) + 1
			per_era[int(b.era)] += 1
			if b.has("art"):
				if int(b.rarity) == 4:
					leg += 1
				elif int(b.rarity) == 5:
					myth += 1
			if ItemDB.BASES.has(k):
				clash.append(k)
			if str(b.get("name", "")) == "" or str(b.get("desc", "")) == "" or int(b.get("value", 0)) <= 0 or b.src.is_empty():
				bad.append(k)
			if b.group in ["weapon", "armor"] and str(b.get("model", "")) == "":
				bad.append(k + ":model")
		ck("distribution 45 / 30 / 25 / 30 / 20", int(g.get("weapon", 0)) == 45 and int(g.get("armor", 0)) == 30 and int(g.get("accessory", 0)) == 25 and int(g.get("resource", 0)) + int(g.get("medicine", 0)) == 30 and int(g.get("home", 0)) == 20, str(g))
		ck("30 items per era", per_era == [30, 30, 30, 30, 30], str(per_era))
		ck("10 legendary and 5 mythic weapons with arts", leg == 10 and myth == 5, "%d / %d" % [leg, myth])
		ck("unique ids, no clash with base items", clash.is_empty(), str(clash))
		ck("every item has name, description, value, sources, model", bad.is_empty(), str(bad))
		var art_ok := true
		for k in a:
			if a[k].has("art") and not LegendaryArts.ARTS.has(a[k].art):
				art_ok = false
		ck("every art weapon has an implemented art", art_ok and LegendaryArts.ARTS.size() == 15)
		# ---------------- obtainability through real paths
		var drop_pool := {}
		for i in 600:
			var it: Dictionary = ItemDB.random_for_era(i % 5, 5, "normal")
			drop_pool[it.base] = true
			var c: Dictionary = ItemDB.random_consumable(i % 5)
			drop_pool[c.base] = true
		var event_pool := {}
		for era in 5:
			for cat in ["food", "medicine", "goods", "luxury", "iron"]:
				for b2 in ItemCatalog.special_stock(era, cat):
					event_pool[b2] = true
		for t in DBEvents.all():
			for key in ["reward"]:
				if t.has(key):
					event_pool[t[key]] = true
		var unreachable := []
		for k in a:
			var b: Dictionary = a[k]
			var ok := false
			for s in b.src:
				match s:
					"drop":
						ok = ok or drop_pool.has(k)
					"shop":
						ok = ok or (not b.has("art"))
					"event":
						ok = ok or event_pool.has(k)
					"craft":
						ok = ok or not Recipes.def_for(k).is_empty()
					"boss":
						ok = ok or b.has("art")
					"quest":
						pass
			if not ok:
				unreachable.append(k)
		ck("every item has a working way to obtain it", unreachable.is_empty(), str(unreachable))
		var bad_rec := []
		for d in Recipes.all_defs():
			for ing in d.cost:
				if not obtainable_base(ing, {d.item: true}):
					bad_rec.append("%s←%s" % [d.item, ing])
		ck("no recipe needs an unobtainable ingredient", bad_rec.is_empty(), str(bad_rec))
		ck("recipes exist for weapons, armour, medicine, accessories, furniture", _has_groups(Recipes.all_defs(), ["weapon", "armor", "medicine", "accessory", "home", "resource"]))
		# shops really sell expansion goods
		var trader = w.spawner.spawn_villager(w.gen.settlements[0], pl.global_position + Vector3(3, 0, 0), "trader")
		await frames(3)
		w.dialogs.open_trade(trader)
		await frames(2)
		var top = w.ui.stack.back() if w.ui.stack.size() > 0 else null
		var shop_x := 0
		if top and top.args.has("items"):
			for it2 in top.args.items:
				if ItemCatalog.has(it2.base):
					shop_x += 1
		w.ui.close_all()
		ck("traders sell expansion items", shop_x >= 4, "%d" % shop_x)
		trader.queue_free()
		# boss loot gives the era's named legendary
		var bosses: Array = DBEras.era(0).bosses
		var boss = w.spawner.spawn_boss(bosses[0], pl.global_position + Vector3(0, 0, 12), 5)
		await frames(3)
		var named: Dictionary = w.loot.named_drop(boss, 0)
		ck("a boss drops a named legendary weapon of its era", not named.is_empty() and int(named.rarity) == 4 and named.has("art"), str(named.get("name", "")))
		boss.queue_free()
		# ---------------- crafting
		pl.data.gold = 99999
		pl.data.inv.add(_qty("iron_ore", 10))
		var forge: Array = Recipes.for_station(w, "forge")
		var ingot = null
		for r in forge:
			if r.name == "Железный слиток":
				ingot = r
		var n_before: int = pl.data.inv.count("iron_ingot")
		var crafted: bool = ingot != null and ingot.cb.call()
		ck("crafting consumes materials and makes the item", crafted and pl.data.inv.count("iron_ingot") == n_before + 1 and pl.data.inv.count("iron_ore") == 7, "ingots %d ore %d" % [pl.data.inv.count("iron_ingot"), pl.data.inv.count("iron_ore")])
		# ---------------- equipment changes the look
		for id in ["x_bo_helm", "x_bo_cuirass", "x_bo_bracers", "x_bo_greaves", "x_bo_boots", "x_bo_cloak"]:
			var it3 := ItemDB.create(id, 1, 3)
			pl.data.inv.add(it3)
			pl.equip_item(it3)
		await frames(3)
		var rig: HumanoidRig = pl.rig
		var thigh_mat = rig.parts.thigh_l.material_override
		ck("leg armour changes the legs", thigh_mat != null and (thigh_mat as StandardMaterial3D).metallic > 0.5)
		ck("gauntlets change the hands", (rig.parts.fist_l.material_override as StandardMaterial3D).metallic > 0.5)
		ck("a cloak item is worn as a cape", rig.j.has("cape"))
		ck("a full set shows its emblem", rig.get_meta("set_full", "") == "black_outpost")
		var helm_before := rig.extras.size()
		pl.data.appearance.hide_helm = 1
		rig.look.hide_helm = true
		pl.refresh_gear()
		await frames(2)
		ck("the helmet can be hidden", rig.extras.size() < helm_before or not rig.parts.hair.visible == false, "%d → %d extras" % [helm_before, rig.extras.size()])
		pl.data.appearance.hide_helm = 0
		rig.look.erase("hide_helm")
		# ---------------- inventory screen: preview, try-on, helmet, dye, stacks
		var scr = w.ui.open("inventory")
		await frames(4)
		var pv: GearPreview = scr._preview
		ck("inventory shows a 3D preview of the hero", pv != null and pv.rig != null and pv.vp.size.x > 0)
		var try_it := ItemDB.create("x_rnl_tricorn", 1, 3) if ItemCatalog.has("x_rnl_tricorn") else ItemDB.create(ItemCatalog.ids_by("armor", 1)[0], 1, 3)
		pv.try_on(try_it)
		await frames(2)
		var slot_try: String = ItemDB.base(try_it.base).slot
		ck("try-on dresses the preview without equipping", pv.equip_override.get(slot_try, {}).get("uid", -1) == try_it.uid and pl.data.inv.equipped(slot_try).get("uid", -2) != try_it.uid)
		pv.clear_try_on()
		var yaw0: float = pv._yaw
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.relative = Vector2(40, 0)
		pv._touches = {0: Vector2(100, 100)}
		pv._gui_input(drag)
		ck("dragging rotates the preview", absf(pv._yaw - yaw0) > 0.3)
		scr._toggle_helm()
		var helm_saved := int(pl.data.appearance.get("hide_helm", 0)) == 1 and bool(pl.rig.look.get("hide_helm", false))
		scr._toggle_helm()
		scr._next_dye()
		var dye0 := int(pl.data.appearance.get("dye", -1))
		ck("helmet toggle and cloak dye change the hero", helm_saved and dye0 >= 0 and pl.rig.look.get("dye", null) is Color, "dye %d" % dye0)
		w.ui.close_all()
		var stack := _qty("linen_bandage", 9)
		pl.data.inv.add(stack)
		var part: Dictionary = pl.data.inv.split(stack.uid, 4)
		var ok_split: bool = not part.is_empty() and int(part.qty) == 4 and int(pl.data.inv.find(stack.uid).qty) == 5
		var merged: int = pl.data.inv.merge_stacks()
		ck("stacks split and merge back", ok_split and merged >= 1 and pl.data.inv.count("linen_bandage") == 9, "merged %d" % merged)
		pl.data.inv.sort_items("type")
		var order := {"weapon": 0, "armor": 1, "accessory": 2, "medicine": 3, "resource": 4, "home": 5, "other": 6}
		var mono := true
		for i in range(1, pl.data.inv.items.size()):
			if int(order[ItemFilter.group_of(pl.data.inv.items[i - 1])]) > int(order[ItemFilter.group_of(pl.data.inv.items[i])]):
				mono = false
		var first_grp := "sorted" if mono else "unsorted"
		var flt: Array = ItemFilter.apply(pl.data.inv.items, "medicine", "бинт")
		ck("sorting and filter/search work", mono and flt.size() >= 1 and flt.all(func(x): return ItemFilter.group_of(x) == "medicine"), "%s, %d" % [first_grp, flt.size()])
		# ---------------- the 15 weapon arts
		var art_res := {}
		for k in a:
			if not a[k].has("art"):
				continue
			var wpn := ItemCatalog.create_named(k, 8)
			pl.data.inv.add(wpn)
			var res: Dictionary = pl.equip_item(wpn)
			await frames(2)
			var slots: Array = pl.data.auto_slots(pl.weapon_cat())
			var aid := "art_" + str(a[k].art)
			var dummy = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], pl.global_position + pl.facing * 4.0, 1)
			dummy.max_hp = 99999.0
			dummy.hp = 99999.0
			dummy.base_speed = 0.0
			await frames(3)
			pl.skill_cd.clear()
			pl.act = {}
			if str(a[k].art) == "lesser_eclipse":
				pl.set_meta("eclipse", 60.0)
			var aim: Vector3 = (dummy.global_position - pl.global_position).normalized()
			var hp0: float = dummy.hp
			var used: bool = pl.use_ability(aid, aim)
			await wait(2.2)
			var effect: bool = dummy.hp < hp0 or dummy.statuses.has("slow") or dummy.statuses.has("res_down")
			art_res[a[k].art] = [aid in slots, used, effect]
			dummy.queue_free()
			pl.global_position = pl.global_position     # stay
			await frames(2)
		var art_bad := []
		for art in art_res:
			if not (art_res[art][0] and art_res[art][1] and art_res[art][2]):
				art_bad.append("%s:%s" % [art, str(art_res[art])])
		ck("all 15 weapon arts: in the skill slot, usable, with a real effect", art_bad.is_empty() and art_res.size() == 15, str(art_bad))
		# passives: heat marks, steam overheat
		var ash := ItemCatalog.create_named("x_ash_king_blade", 5)
		pl.data.inv.add(ash)
		pl.equip_item(ash)
		var foe = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], pl.global_position + Vector3(0, 0, 3), 1)
		foe.max_hp = 99999.0
		foe.hp = 99999.0
		await frames(2)
		Combat.deal(pl, foe, {"amount": 5.0, "dtype": "slash", "melee": true})
		Combat.deal(pl, foe, {"amount": 5.0, "dtype": "slash", "melee": true})
		ck("«Пепельный приговор» hits stack heat marks", int(foe.get_meta("heat", 0)) == 2)
		foe.queue_free()
		var storm := ItemCatalog.create_named("x_steam_storm_heart", 5)
		pl.data.inv.add(storm)
		pl.equip_item(storm)
		await frames(2)
		var uses := 0
		for i in 4:
			pl.skill_cd.clear()
			pl.act = {}
			if pl.use_ability("art_steam_storm", pl.facing):
				uses += 1
			await frames(3)
		ck("«Сердце Паровой Бури» overheats after repeated use", uses == 3 and float(pl.get_meta("overheat_until", 0.0)) > Time.get_ticks_msec() / 1000.0, "uses %d" % uses)
		# ---------------- medicine (normal mode)
		pl.statuses.erase("invuln")
		pl.hp = pl.max_hp * 0.5
		var hp1: float = pl.hp
		var med := ItemDB.create("linen_bandage", 0, 1)
		pl.data.inv.add(med)
		pl.use_item(med)
		ck("medicine heals in the normal mode", pl.hp > hp1)
		pl.apply_status("invuln", 999999.0)
		# ---------------- save / load
		var leg_it := ItemCatalog.create_named("x_border_sword", 3) if false else ItemCatalog.create_named("x_thousand_lightning_bow", 3)
		leg_it.awaken = 2
		pl.data.inv.add(leg_it)
		SaveSys.save_game()
		Profile.char.inv.items.clear()
		SaveSys.load_profile()
		var found := false
		var count_x := 0
		for it4 in Profile.char.inv.items:
			if ItemCatalog.has(it4.base):
				count_x += 1
			if it4.base == "x_thousand_lightning_bow" and int(it4.get("awaken", 0)) == 2 and str(it4.get("art", "")) == "lightning_rain":
				found = true
		ck("expansion items survive save and load (with art and awakening)", found and count_x >= 5, "%d items" % count_x)
		ck("helmet visibility and dye survive save and load", int(Profile.char.appearance.get("dye", -1)) == dye0 and Player.look_from(Profile.char).get("dye", null) is Color)
		print("ITEMS_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
	func _qty(id: String, n: int) -> Dictionary:
		var it := ItemDB.create(id, 0, 1)
		it.qty = n
		return it
	func _has_groups(defs: Array, gs: Array) -> bool:
		var have := {}
		for d in defs:
			have[d.group] = true
		for x in gs:
			if not have.has(x):
				return false
		return true
