class_name Loot
extends Node
## Loot tables, drops on death, chests, containers, picking up by the player
## and by NPCs (an NPC that takes an item really owns it afterwards).

var world

func _init(w) -> void:
	world = w

func spawn_drop(item: Dictionary, pos: Vector3, by_player: bool = false, gold: int = 0) -> ItemDrop:
	if gold <= 0 and (item.is_empty() or not item.has("base")):
		return null
	var d := ItemDrop.new()
	d.setup(item, gold, by_player)
	world.fx_root.add_child(d)
	if world.has_method("ground_height"):
		pos.y = world.ground_height(pos) + 0.05
	d.global_position = pos
	if not by_player:
		d.announce()
	return d

func _scatter(center: Vector3) -> Vector3:
	var a := randf() * TAU
	return center + Vector3(cos(a), 0, sin(a)) * randf_range(0.6, 1.8)

func drop_for(victim: Actor, killer) -> void:
	var era := Profile.current_era
	var lvl: int = victim.level
	var luck := 0.0
	if killer and is_instance_valid(killer) and killer.data:
		luck = killer.stat("luck")
	if world.director != null:
		luck += float(world.director.mods.get("loot", 0.0))
	if victim.has_meta("blood_variant") and randf() < 0.35:
		spawn_drop(ItemDB.create("chrono_shard", 0, 1), _scatter(victim.global_position))
	var p: Vector3 = victim.global_position
	# NPC inventories drop what they carried
	if victim.data and victim.kind == "humanoid" and victim.get("role") in ["bot", "enemy", "hunter", "soldier"]:
		var carried: Array = []
		for it in victim.data.inv.items:
			if ItemDB.is_equipment(it) and randf() < 0.35:
				carried.append(it)
		var w: Dictionary = victim.weapon()
		if not w.is_empty() and randf() < (0.6 if victim.record.size() > 0 else 0.22):
			carried.append(w)
		for it in carried.slice(0, 3):
			spawn_drop(it.duplicate(true), _scatter(p))
		var g: int = int(victim.data.gold * 0.5) if victim.record.size() > 0 else randi_range(2, 6) * (era + 1)
		if g > 0:
			spawn_drop({}, _scatter(p), false, g)
	if victim.kind == "boss":
		return   # bosses handled by world.on_boss_defeated
	var table := "elite" if victim.elite else "normal"
	var chance := 1.0 if victim.elite else 0.28
	if victim.def_id == "mimic":
		chance = 1.0
		table = "chest"
	if randf() < chance:
		spawn_drop(ItemDB.random_for_era(era, lvl, table, luck), _scatter(p))
	if randf() < 0.22:
		spawn_drop(ItemDB.random_consumable(era), _scatter(p))
	if victim.elite and randf() < 0.35:
		spawn_drop(ItemDB.create("chrono_shard", 0, 1), _scatter(p))
	# spirit essence (curse rituals): restless dead, dark casters and rift-born
	var dark: bool = DBActors.eget(victim.def_id, {}).get("dtype", "") == "dark" or victim.def_id in ["skeleton", "wraith", "cursed_warrior", "necro_acolyte", "dark_mage", "chrono_anomaly", "spirit"]
	if randf() < (0.3 if dark else 0.06) + (0.15 if world.dimension != "" else 0.0):
		spawn_drop(ItemDB.create("spirit_essence", 0, 1), _scatter(p))
	if victim.kind == "creature" and randf() < 0.3:
		spawn_drop({}, _scatter(p), false, randi_range(2, 8) * (era + 1))

func boss_rewards(boss: Boss) -> void:
	var p := boss.global_position
	MagicLore.boss_treatise_drop(p)
	var era := Profile.current_era
	# «Beasts of the Ages»: own table (materials, trophy, relic, era legendary)
	if boss.def.get("beast", false):
		BeastWorld.boss_loot(boss)
		spawn_drop(ItemDB.random_for_era(era, boss.level, "boss"), _scatter(p))
		spawn_drop({}, _scatter(p), false, 120 * (era + 1))
		for i in 2:
			spawn_drop(ItemDB.random_consumable(era), _scatter(p))
		return
	var reward: String = boss.def.get("reward", "")
	if reward != "":
		spawn_drop(ItemDB.create_unique(reward, boss.level), _scatter(p))
	# expansion: the era's named legendary weapons drop from its bosses (one the
	# hero doesn't own yet), the mythic one from the era's last boss
	var named := named_drop(boss, era)
	if not named.is_empty():
		spawn_drop(named, _scatter(p))
	for i in 2:
		spawn_drop(ItemDB.random_for_era(era, boss.level, "boss"), _scatter(p))
	var shards := ItemDB.create("chrono_shard", 0, 1)
	shards.qty = 2 + era
	spawn_drop(shards, _scatter(p))
	var relic: String = DBEras.era(era).trial.get("relic", "")
	if relic != "" and Profile.char.inv.count(relic) == 0:
		spawn_drop(ItemDB.create(relic, 4, 1), _scatter(p))
	spawn_drop({}, _scatter(p), false, 150 * (era + 1))
	for i in 3:
		spawn_drop(ItemDB.random_consumable(era), _scatter(p))

func named_drop(boss, era: int) -> Dictionary:
	var owned := {}
	if Game.player and Game.player.data:
		for it in Game.player.data.inv.items:
			owned[it.base] = true
		for sl in Game.player.data.inv.equip:
			owned[Game.player.data.inv.equip[sl].get("base", "")] = true
	var bosses: Array = DBEras.era(era).bosses
	var last: bool = not bosses.is_empty() and str(boss.get("boss_id")) == str(bosses[bosses.size() - 1])
	var want := 5 if last else 4
	for k in ItemCatalog.ids_by("weapon", era):
		var b := ItemCatalog.base(k)
		if b.has("art") and int(b.rarity) == want and not owned.has(k):
			return ItemCatalog.create_named(k, boss.level)
	if last:
		for k in ItemCatalog.ids_by("weapon", era):
			var b2 := ItemCatalog.base(k)
			if b2.has("art") and int(b2.rarity) == 4 and not owned.has(k):
				return ItemCatalog.create_named(k, boss.level)
	return {}

func roll_chest(chest, actor) -> void:
	var era := Profile.current_era
	var lvl: int = chest.get("lvl") if chest.get("lvl") else (Game.player.level if Game.player else 1)
	var rich: bool = chest.get("tier") == "rich"
	var items: Array = []
	var n := (2 if rich else 1) + (1 if randf() < 0.4 else 0)
	var luck: float = actor.stat("luck") if actor and actor.data else 0.0
	for i in n:
		items.append(ItemDB.random_for_era(era, lvl, "chest" if not rich else "elite", luck))
	if randf() < 0.7:
		items.append(ItemDB.random_consumable(era))
	if randf() < (0.35 if rich else 0.12):
		items.append(ItemDB.create("chrono_shard", 0, 1))
	# ancient dungeons keep lost magical knowledge: a geomancer who can read
	# it (earth mastery 12) always finds the golem's treatise in the first chest
	var pd: CharData = actor.data if actor != null and actor.get("is_player") == true else null
	if world.get("dimension") == "dungeon" and pd != null and pd.school_level("earth") >= 12 and not pd.knowledge.has("tome_e_guardian_golem") and not pd.knowledge.has("know_e_guardian_golem") and not pd.inv.items.any(func(x): return str(x.get("knowledge", "")) == "tome_e_guardian_golem"):
		items.append(MagicLore.treatise("e_guardian_golem"))
	elif world.get("dimension") == "dungeon" and randf() < (0.6 if rich else 0.25):
		var lore_ids := ["e_guardian_golem"]
		for sch in DBAbilities.SCHOOL_ORDER:
			lore_ids.append(DBAbilities.school_spells(sch)[8].id)
		items.append(MagicLore.treatise(lore_ids[0] if randf() < 0.4 else lore_ids[randi() % lore_ids.size()]))
	var gold := randi_range(5, 25) * (era + 1) * (2 if rich else 1)
	Audio.play_sfx("chest_open", chest.global_position)
	if actor and actor is NPC:
		# NPC claims the contents for itself
		for it in items:
			_npc_take(actor, it)
		actor.data.gold += gold
		return
	for it in items:
		spawn_drop(it, _scatter(chest.global_position))
	spawn_drop({}, _scatter(chest.global_position), false, gold)
	Events.chest_opened.emit(actor, chest)

func drop_from_container(pos: Vector3, _kind: String) -> void:
	if randf() < 0.25:
		spawn_drop(ItemDB.random_consumable(Profile.current_era), pos)
	elif randf() < 0.2:
		spawn_drop({}, pos, false, randi_range(1, 6) * (Profile.current_era + 1))

func wanted_drop_near(n, r: float):
	var best = null
	var bs := 0.0
	for d in Game.grid.query(n.global_position, r, "pickup"):
		if not is_instance_valid(d):
			continue
		var s := _want(n, d)
		if s > bs:
			bs = s
			best = d
	return best

func _want(n, d: ItemDrop) -> float:
	if d.gold > 0:
		return 0.6
	var it: Dictionary = d.item
	var b := ItemDB.base(it.get("base", ""))
	if b.get("slot", "") in ["use", "mat"]:
		return 0.5
	if n.data.inv.is_full():
		return 0.0
	var slot: String = b.get("slot", "")
	var cur: Dictionary = n.data.inv.equipped(slot)
	var gain := ItemDB.power(it) - ItemDB.power(cur)
	return clampf(0.4 + gain / 30.0, 0.0, 2.0) + it.get("rarity", 0) * 0.15

func pickup(a, d: ItemDrop) -> void:
	if not is_instance_valid(d) or d.is_queued_for_deletion():
		return
	if d.gold > 0:
		a.data.gold += d.gold
		if a.is_player:
			Audio.play_sfx("coin", a.global_position, -4.0)
			Events.notify.emit("+%d %s" % [d.gold, DBEras.era(Profile.current_era).currency], Color(1.0, 0.85, 0.3))
		d.queue_free()
		return
	var it: Dictionary = d.item
	if a.is_player:
		if not a.data.inv.add(it):
			Events.notify.emit("Инвентарь полон!", Color(1.0, 0.4, 0.4))
			Audio.play_sfx("error")
			return
		# detection devices reveal curses on pickup
		if a.stat("detect") > 0.0 and it.get("curse", {}).size() > 0:
			it.curse.hidden = false
			Events.notify.emit("Сканер: предмет проклят!", Color(0.9, 0.3, 0.4))
		Audio.play_sfx("pickup", a.global_position, -3.0)
		Events.notify.emit("Получено: " + ItemDB.display_name(it) + ((" ×%d" % it.qty) if it.get("qty", 1) > 1 else ""), ItemDB.rarity_color(it))
		Events.item_picked.emit(a, it)
		if it.get("rarity", 0) >= 4:
			Profile.unlock("legendary" if it.rarity == 4 else "mythic")
		if it.get("rarity", 0) >= 3 and ItemDB.is_equipment(it):
			Chronicle.record("item_found", [a], {"pos_v3": a.global_position, "extra": {"item": ItemDB.display_name(it), "rarity": it.rarity}})
		Profile.add_stat("items")
		d.queue_free()
		return
	if _npc_take(a, it):
		d.queue_free()

func _npc_take(n, it: Dictionary) -> bool:
	if not n.data.inv.add(it):
		return false
	if ItemDB.is_equipment(it):
		var slot: String = ItemDB.base(it.base).slot
		if ItemDB.power(it) > ItemDB.power(n.data.inv.equipped(slot)) and it.get("curse", {}).get("hidden", false) == false:
			var res: Dictionary = n.data.inv.equip_item(it)
			if res.ok:
				n.refresh_gear()
		elif it.get("curse", {}).get("hidden", true) and ItemDB.power(it) > ItemDB.power(n.data.inv.equipped(slot)):
			# NPCs can fall for hidden curses too
			var res2: Dictionary = n.data.inv.equip_item(it)
			if res2.ok:
				n.refresh_gear()
	if it.get("rarity", 0) >= 3:
		if n.record.size() > 0:
			n.record.rare_items = n.record.get("rare_items", 0) + 1
		Chronicle.record("item_found", [n], {"pos_v3": n.global_position, "extra": {"item": ItemDB.display_name(it), "rarity": it.rarity}})
	return true
