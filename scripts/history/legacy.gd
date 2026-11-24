class_name Legacy
## Historical inheritance between eras: faction successors keep a share of
## strength and the player's reputation; slain bosses leave monuments and
## ruins; relics deposited in one era reappear as museum artifacts with
## their history; living legends enter the Hall of Legends and their
## descendants appear later; the fortress transforms into the next base.

static func on_leave_era(world, era_i: int, _new_era: int) -> void:
	for fid in world.factions.list():
		var terr: int = world.factions.territory(fid)
		Profile.legacy.faction_power[fid] = world.factions.strength(fid) + terr * 10.0
		Profile.legacy.faction_rep[fid] = world.factions.rep(fid)
	for bid in Game.world_state.bosses:
		if Game.world_state.bosses[bid].get("defeated", false):
			Profile.legacy.flags["boss_slain_" + bid] = {"era": era_i, "day": Game.day()}
	var lg: Array = world.legends.legends()
	for r in lg.slice(0, 5):
		var snap: Dictionary = r.duplicate(true)
		snap.era = era_i
		snap.chronicle_text = world.legends.biography(r).chronicle
		Profile.hall_of_legends.append(snap)
	var strongest := ""
	var sp := -1.0
	for fid in world.factions.list():
		if world.factions.strength(fid) > sp:
			sp = world.factions.strength(fid)
			strongest = fid
	if strongest != "":
		Profile.legacy.flags["dominant_" + str(era_i)] = strongest
	Fortress.carry_over()

static func apply_to_world(world) -> void:
	var era := Profile.current_era
	if era == 0:
		return
	var prev_dom = Profile.legacy.flags.get("dominant_" + str(era - 1))
	if prev_dom != null:
		var succ: String = DBEras.faction(prev_dom).get("successor", "")
		if succ != "" and world.factions.st.has(succ) and not world.factions.st[succ].get("legacy_applied", false):
			world.factions.st[succ].strength += 40.0
			world.factions.st[succ].legacy_applied = true
			Events.notify.emit("Наследие: «%s» усилилась благодаря успехам предков из «%s»." % [DBEras.faction(succ).name, DBEras.faction(prev_dom).name], Color(1.0, 0.85, 0.5))

static func relic_dialog(world) -> void:
	var era := Profile.current_era
	var lines: Array = []
	var opts: Array = []
	for i in Profile.legacy.relics.size():
		var rel: Dictionary = Profile.legacy.relics[i]
		var it: Dictionary = rel.item
		if int(rel.era) < era:
			lines.append("[color=#ffd36b]%s[/color] — оставлен(а) в эпохе «%s» у места «%s». Спустя века стал музейным экспонатом." % [ItemDB.display_name(it), DBEras.era(int(rel.era)).name, rel.get("place", "?")])
			if not rel.get("claimed", false):
				var idx = i
				opts.append({"text": "Забрать экспонат: %s" % ItemDB.display_name(it), "cb": func():
					var r2: Dictionary = Profile.legacy.relics[idx]
					var item: Dictionary = r2.item.duplicate(true)
					LivingWeapon.tech_upgrade(item, era)
					item.history.append("Найден в музее эпохи «%s» как исторический артефакт" % DBEras.era(era).name)
					if world.player.data.inv.add(item):
						r2.claimed = true
						Events.banner.emit("Реликвия вернулась", ItemDB.display_name(item), Color(1.0, 0.85, 0.3))})
		elif int(rel.era) == era:
			lines.append("%s — оставлен(а) вами в этой эпохе." % ItemDB.display_name(it))
	for it in world.player.data.inv.items:
		if it.get("rarity", 0) >= 4 and ItemDB.is_equipment(it):
			var item2: Dictionary = it
			opts.append({"text": "Оставить в истории: %s" % ItemDB.display_name(item2), "cb": func():
				world.player.data.inv.remove(item2.uid)
				item2.history.append("Оставлен в эпохе «%s», день %d" % [DBEras.era(era).name, Game.day() + 1])
				Profile.legacy.relics.append({"item": item2, "era": era, "place": world.place_name(world.player.global_position), "claimed": false})
				Chronicle.record("relic_left", [world.player], {"pos_v3": world.player.global_position, "extra": {"item": ItemDB.display_name(item2)}})
				Events.notify.emit("Реликвия сохранена в истории. В будущих эпохах её найдут в музее.", Color(1.0, 0.85, 0.5))})
			if opts.size() > 6:
				break
	opts.append({"text": "Уйти", "cb": func(): pass})
	var text := "Здесь хранятся реликвии, пережившие века.\n\n" + ("\n".join(lines) if not lines.is_empty() else "Экспонатов пока нет. Оставьте легендарный предмет, чтобы он вошёл в историю.")
	world.ui.open("dialog", {"title": "Реликвии истории", "text": text, "portrait_color": Color(1.0, 0.85, 0.5), "options": opts})

static func monument_dialog(world, data: Dictionary) -> void:
	var era := Profile.current_era
	var lines: Array = []
	for k in Profile.legacy.flags:
		if k.begins_with("boss_slain_"):
			var bid: String = k.substr(11)
			var f: Dictionary = Profile.legacy.flags[k]
			if int(f.get("era", 99)) < era:
				lines.append("«Здесь, в эпоху «%s», %s сокрушил(а) %s. Ныне на месте его логова — руины и этот памятник»." % [DBEras.era(int(f.era)).name, Profile.char.name, DBActors.BOSSES.get(bid, {}).get("name", bid)])
	for h in Profile.hall_of_legends:
		if int(h.get("era", 99)) < era:
			lines.append("Табличка: «%s %s — легенда эпохи «%s»»." % [h.name, ("«%s»" % h.title) if h.get("title", "") != "" else "", DBEras.era(int(h.era)).name])
	if lines.is_empty():
		lines.append("Надпись стёрлась от времени. История этого места ещё не написана.")
	world.ui.open("dialog", {"title": "Памятник прошлому", "text": "\n\n".join(lines.slice(0, 6)), "options": [{"text": "Уйти", "cb": func(): pass}]})
