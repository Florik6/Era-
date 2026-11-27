class_name Recipes
## Crafting recipes for the 150 expansion items, generated from the catalog
## with era materials. Every ingredient is obtainable (shops, drops, events
## or another recipe) — tests/items_test checks that. Stations:
##   forge     — weapons, armour, metal materials, legendary development
##   lab       — medicine and alchemical materials
##   workshop  — accessories, tech materials, furniture, home upgrades
## Recipes are plain dictionaries for the crafting screen (name, desc, cost,
## gold, group, cb).

const MATS := {
	0: {"metal": "iron_ingot", "soft": "enchanted_leather", "rare": "ash_crystal"},
	1: {"metal": "brass_blank", "soft": "alch_glassware", "rare": "silver_powder"},
	2: {"metal": "steel_plate", "soft": "copper_winding", "rare": "ether_condensate"},
	3: {"metal": "polymer_sheet", "soft": "electronic_board", "rare": "battery_pack"},
	4: {"metal": "quantum_alloy", "soft": "phase_fabric", "rare": "chrono_cell"},
}

## Recipe definition for one catalog item: {item, station, cost, gold, group}.
static func def_for(id: String) -> Dictionary:
	var b := ItemCatalog.base(id)
	if b.is_empty() or not "craft" in b.src:
		return {}
	var era: int = int(b.era)
	var m: Dictionary = MATS[era]
	var g := 20 + 15 * era
	var cost := {}
	var station := "forge"
	match String(b.group):
		"weapon":
			if b.has("art"):
				cost = {m.metal: 8, m.rare: 5, m.soft: 3}
				g = 900 + 400 * era
			else:
				cost = {m.metal: 3, m.soft: 1}
				g = 40 + 30 * era
		"armor":
			cost = {m.metal: 2, m.soft: 2}
			g = 35 + 25 * era
		"accessory":
			cost = {m.rare: 1, m.soft: 2}
			g = 50 + 30 * era
			station = "workshop"
		"medicine":
			station = "lab"
			cost = {"herbs": 2} if era < 2 else {m.soft: 1}
			if b.get("med", {}).has("fracture"):
				cost[m.metal] = 1
			g = 8 + 6 * era
		"resource":
			if id == m.metal:
				cost = {"iron_ore": 3} if era == 0 else {MATS[era - 1].metal: 2}
				g = 8 + 6 * era
			elif id == m.rare:
				cost = {m.metal: 2, m.soft: 2}
				g = 40 + 20 * era
			else:
				cost = {m.metal: 1} if era > 0 or id != "enchanted_leather" else {"iron_ore": 2}
				g = 12 + 6 * era
			station = "lab" if id in ["alch_glassware", "silver_powder"] else ("workshop" if era >= 2 else "forge")
		"home":
			cost = {m.metal: 2, m.soft: 1}
			g = int(b.value * 0.6)
			station = "workshop"
	return {"item": id, "station": station, "cost": cost, "gold": g, "group": String(b.group)}

static func all_defs() -> Array:
	var out: Array = []
	for k in ItemCatalog.all():
		var d := def_for(k)
		if not d.is_empty():
			out.append(d)
	return out

## Recipes usable at a station in an era (current era and earlier ones).
static func for_station(world, station: String) -> Array:
	var pd: CharData = world.player.data
	var era := Profile.current_era
	var out: Array = []
	for d in all_defs():
		var b := ItemCatalog.base(d.item)
		if int(b.era) > era or (d.station != station and not (station == "home" and d.station in ["forge", "lab", "workshop"] and d.group in ["medicine", "home", "resource"])):
			continue
		var did: Dictionary = d
		out.append({"name": b.name, "desc": str(b.get("desc", "")), "cost": did.cost, "gold": did.gold, "group": did.group,
			"cb": func():
				if not Stations._pay(world, did.cost, did.gold):
					return false
				var it: Dictionary = ItemCatalog.create_named(did.item, world.player.level) if b.has("art") else ItemDB.create(did.item, 1 if did.group in ["weapon", "armor", "accessory"] else 0, world.player.level)
				if not pd.inv.add(it):
					world.loot.spawn_drop(it, world.player.global_position + Vector3(1, 0, 0))
				Profile.add_stat("crafted")
				if CivicLegends.inst != null and station in ["forge", "workshop"]:
					CivicLegends.inst.on_craft(it)        # the town smith's real work → biography
				Audio.play_sfx("hit_metal" if station == "forge" else "pickup")
				return true})
	if station == "forge":
		out.append_array(_legend_development(world))
	return out

## Developing a legendary/mythic weapon: up to 5 awakenings, each makes the
## weapon stronger and shortens its art's cool-down.
static func _legend_development(world) -> Array:
	var pd: CharData = world.player.data
	var out: Array = []
	var it: Dictionary = pd.inv.equipped("main")
	if it.is_empty() or str(it.get("art", "")) == "":
		return out
	var lvl := int(it.get("awaken", 0))
	if lvl >= 5:
		return out
	var era := int(ItemDB.base(it.base).get("era", 0))
	var m: Dictionary = MATS[era]
	var cost := {m.rare: 2 + lvl, m.metal: 3 + lvl}
	var gold := 300 * (lvl + 1) * (era + 1)
	var item: Dictionary = it
	out.append({"name": "Пробуждение: %s → %d/5" % [ItemDB.display_name(item), lvl + 1], "desc": "+12% урона и −8% к перезарядке способности за ступень.",
		"cost": cost, "gold": gold, "group": "upgrade",
		"cb": func():
			if not Stations._pay(world, cost, gold):
				return false
			item.awaken = int(item.get("awaken", 0)) + 1
			if item.stats.has("dmg"):
				item.stats.dmg = snappedf(float(item.stats.dmg) * 1.12, 0.01)
			world.player.refresh_gear()
			Audio.play_sfx("mastery_up")
			Chronicle.record("item_found", [world.player], {"pos_v3": world.player.global_position, "text": "%s пробудил(а) %s до ступени %d." % [Profile.char.name, ItemDB.display_name(item), item.awaken]})
			return true})
	return out
