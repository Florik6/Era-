class_name LivingWeapon
## Weapons with a soul: gain experience from kills, evolve through three
## stages (model, stats, abilities change) and branch on the final stage.
## Keeps a history of important moments.

static func add_xp(owner_a: Actor, item: Dictionary, amount: int, victim = null) -> void:
	var lv: Dictionary = item.living
	if lv.stage >= 2:
		return
	lv.xp += amount
	if victim and victim.kind == "boss":
		item.history.append("Вкусил силу босса «%s»" % victim.display_name)
	var need := ItemDB.living_xp_needed(lv.stage)
	if lv.xp < need:
		return
	lv.xp = 0
	lv.stage += 1
	if lv.stage == 2:
		var school := owner_a.data.best_school() if owner_a.data else ""
		lv.path = "dusk" if school in ["dark", "spacetime"] else "dawn"
		item.ability = "nova_kill" if lv.path == "dawn" else "phantom"
		item.mods["lifesteal"] = item.mods.get("lifesteal", 0.0) + (0.0 if lv.path == "dawn" else 0.05)
		item.mods["fire_dmg"] = item.mods.get("fire_dmg", 0.0) + (12.0 if lv.path == "dawn" else 0.0)
		item.rarity = 4
	else:
		item.mods["dmg_pct"] = item.mods.get("dmg_pct", 0.0) + 0.1
		item.ability = "chain_proc"
		item.rarity = maxi(item.rarity, 3)
	var where := ""
	if Game.world and Game.world.has_method("place_name"):
		where = Game.world.place_name(owner_a.global_position)
	var line := "Стадия %d: %s у места «%s», день %d" % [lv.stage + 1, ItemDB.display_name(item), where, Game.day() + 1]
	item.history.append(line)
	owner_a.refresh_gear()
	VFX.ring(owner_a.global_position, 3.0, Color(0.3, 1.0, 0.8), 0.8)
	Audio.play_sfx("mastery_up", owner_a.global_position)
	if owner_a.is_player:
		Events.banner.emit("Живое оружие эволюционировало!", ItemDB.display_name(item), Color(0.4, 1.0, 0.8))
		Profile.unlock("living_evolved")
	Chronicle.record("living_evolved", [owner_a], {"pos_v3": owner_a.global_position, "extra": {"item": ItemDB.display_name(item)}})

## Era transition: artifacts that survive into later eras gain tech upgrades.
static func tech_upgrade(item: Dictionary, new_era: int) -> void:
	if item.get("living", {}).is_empty() and item.get("rarity", 0) < 4:
		return
	item.lvl = item.get("lvl", 1) + 4
	var key := "dmg" if item.stats.has("dmg") else "armor"
	if item.stats.has(key):
		item.stats[key] = snappedf(item.stats[key] * 1.9, 0.01)
	var names := ["", "алхимическая гравировка", "паровой усилитель", "углеродное покрытие", "квантовое ядро"]
	item.history.append("Пережил переход в эпоху «%s»: %s" % [DBEras.era(new_era).name, names[clampi(new_era, 0, 4)]])
