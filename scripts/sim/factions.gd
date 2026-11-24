class_name FactionSystem
extends Node
## Organizations of the current era: reputation, ranks, entry trials,
## membership changes with consequences, perks, vendors, relations (war /
## peace / alliance), territory (settlements and control points), strategic
## attacks resolved either physically near the player or abstractly.

var world
var st := {}            # fid -> state
var points := {}        # cp id -> {owner, type, name}
var settlements := {}   # sid -> {owner, population, guards, security, resources, name}
var _strat_t := 0.0
var _income_t := 0.0

func _init(w) -> void:
	world = w

func setup() -> void:
	var ws: Dictionary = Game.world_state
	st = ws.get("factions", {})
	points = ws.get("points", {})
	settlements = ws.get("settlements", {})
	ws.factions = st
	ws.points = points
	ws.settlements = settlements
	var era: int = Profile.current_era
	var fl: Array = DBEras.factions_of(era)
	var fresh := st.is_empty()
	for fid in fl:
		if not st.has(fid):
			var f: Dictionary = DBEras.faction(fid)
			var pred := DBEras.predecessor(fid)
			var base_power := 100.0
			var rep := 0.0
			if pred != "":
				base_power += float(Profile.legacy.faction_power.get(pred, 0.0)) * 0.5
				rep = float(Profile.legacy.faction_rep.get(pred, 0.0)) * 0.5
			st[fid] = {"rep": rep, "strength": base_power, "resources": 50.0, "relations": {}, "leader": "", "commanders": [],
				"rank": DBEras.rank_for_rep(rep), "trial_done": false, "member": false}
			for other in fl:
				if other != fid:
					st[fid].relations[other] = "war" if other in f.enemies else "peace"
	if not st.has("_player"):
		st["_player"] = {"member": "", "left": []}
	if fresh and world.gen:
		var i := 0
		for s in world.gen.settlements:
			var owner_f: String = fl[i % fl.size()] if s.type != "village" or randf() < 0.6 else ""
			if s.type in ["city", "castle", "fort"]:
				owner_f = _strongest_guard_faction(fl)
			settlements[s.id] = {"owner": owner_f, "population": 6 if s.type == "village" else 9, "guards": 2 if s.type == "village" else 4,
				"security": 0.7, "resources": 50.0, "name": s.name}
			i += 1
		for p in world.gen.pois:
			if p.type == "cp":
				points[p.id] = {"owner": fl[randi() % fl.size()] if randf() < 0.55 else "", "type": p.data.get("cp_type", "watchtower"), "name": p.get("name", "Точка")}
	Events.point_captured.connect(_on_point_captured)

func _strongest_guard_faction(fl: Array) -> String:
	for fid in fl:
		if DBEras.faction(fid).style == "guard":
			return fid
	return fl[0]

func save_state() -> void:
	Game.world_state.factions = st
	Game.world_state.points = points
	Game.world_state.settlements = settlements

# ---------------------------------------------------------------- queries (UI API)
func list() -> Array:
	return DBEras.factions_of(Profile.current_era)

func rep(fid: String) -> float:
	return float(st.get(fid, {}).get("rep", 0.0))

func rank(fid: String) -> int:
	return DBEras.rank_for_rep(rep(fid))

func rank_name(fid: String) -> String:
	var f: Dictionary = DBEras.faction(fid)
	var ranks: Array = f.get("ranks", DBEras.FACTION_RANKS)
	if member_of() != fid:
		return "Не состоите" if rep(fid) > -30 else "Враг"
	return ranks[clampi(rank(fid), 0, ranks.size() - 1)]

func member_of() -> String:
	return st.get("_player", {}).get("member", "")

func at_war(a: String, b: String) -> bool:
	return st.get(a, {}).get("relations", {}).get(b, "") == "war"

func relation(a: String, b: String) -> String:
	return st.get(a, {}).get("relations", {}).get(b, "peace")

func relation_text(fid: String) -> String:
	var parts: Array = []
	var names := {"war": "война", "peace": "мир", "alliance": "союз"}
	for other in st.get(fid, {}).get("relations", {}):
		parts.append("%s: %s" % [DBEras.faction(other).get("name", other), names.get(relation(fid, other), "мир")])
	return "; ".join(parts)

func strength(fid: String) -> float:
	return float(st.get(fid, {}).get("strength", 100.0))

func territory(fid: String) -> int:
	var n := 0
	for k in points:
		if points[k].get("owner", "") == fid:
			n += 1
	for k in settlements:
		if settlements[k].owner == fid:
			n += 2
	return n

func leader_name(fid: String) -> String:
	var lid: String = st.get(fid, {}).get("leader", "")
	if lid == "player":
		return Profile.char.name + " (вы)"
	var rec: Dictionary = world.legends.record(lid) if world.legends else {}
	if rec.is_empty():
		return "—"
	return rec.name + ((" «%s»" % rec.title) if rec.get("title", "") != "" else "")

func perks(fid: String) -> Array:
	var out: Array = []
	var r := rank(fid) if member_of() == fid else -1
	var lines := ["Доступ к торговцу организации", "+5% к урону и броне", "Скидка 15%, союзники помогают в бою", "Право призвать отряд соратников", "Доход с территорий и управление организацией"]
	for i in lines.size():
		out.append(("✔ " if r >= i else "· ") + lines[i])
	return out

func settlement_owner(sid: String) -> String:
	return settlements.get(sid, {}).get("owner", "")

func settlement_state(sid: String) -> Dictionary:
	return settlements.get(sid, {})

func point_owner(pid: String) -> String:
	return points.get(pid, {}).get("owner", "")

## Player combat bonuses from rank and owned control points.
func player_bonus() -> Dictionary:
	var b := {"dmg": 0.0, "armor": 0.0, "xp": 0.0}
	var m := member_of()
	if m != "" and rank(m) >= 1:
		b.dmg += 0.05
		b.armor += 0.05
	for k in points:
		var o: String = points[k].get("owner", "")
		if o == "player" or (m != "" and o == m):
			match points[k].get("type", ""):
				"watchtower", "comm_tower", "data_node":
					b.xp += 0.05
				"outpost", "checkpoint", "defense_turret", "power_station", "energy_station":
					b.dmg += 0.03
				_:
					b.armor += 0.02
	return b

# ---------------------------------------------------------------- membership
func can_join(fid: String) -> Dictionary:
	if member_of() == fid:
		return {"ok": false, "reason": "Вы уже состоите в этой организации."}
	if rep(fid) <= -30.0:
		return {"ok": false, "reason": "Организация считает вас врагом."}
	if member_of() != "":
		return {"ok": true, "reason": "Придётся покинуть «%s». Это вызовет недовольство." % DBEras.faction(member_of()).name}
	return {"ok": true, "reason": ""}

func join(fid: String) -> void:
	var c := can_join(fid)
	if not c.ok:
		Events.notify.emit(c.reason, Color(1, 0.5, 0.4))
		return
	if not st[fid].trial_done:
		world.quests.start_faction_trial(fid)
		return
	_do_join(fid)

func complete_trial(fid: String) -> void:
	st[fid].trial_done = true
	_do_join(fid)

func _do_join(fid: String) -> void:
	var prev := member_of()
	if prev != "":
		leave()
	for other in list():
		if other != fid and at_war(fid, other) and rep(other) > -20.0:
			add_rep(other, -40.0, "вступление во враждебную организацию")
	st._player.member = fid
	st[fid].member = true
	add_rep(fid, 25.0, "вступление")
	if world.player:
		world.player.faction_id = fid
		world.player.refresh_gear()
	Chronicle.record("faction_join", [world.player], {"pos_v3": world.player.global_position, "extra": {"faction": DBEras.faction(fid).name}})
	Events.banner.emit("Вы вступили в организацию", DBEras.faction(fid).name, DBEras.faction(fid).color)
	Profile.milestone("join_faction")

func leave() -> void:
	var m := member_of()
	if m == "":
		return
	st._player.member = ""
	st[m].member = false
	st._player.left.append(m)
	add_rep(m, -50.0, "уход из организации")
	if world.player:
		world.player.faction_id = ""
		world.player.refresh_gear()
	Chronicle.record("faction_leave", [world.player], {"extra": {"faction": DBEras.faction(m).name}})
	if st[m].get("leader", "") == "player":
		st[m].leader = ""
	if rep(m) < -20.0 and world.director:
		world.director.queue_hunters("Мстители «%s»" % DBEras.faction(m).name, m)

func add_rep(fid: String, v: float, reason: String = "") -> void:
	if not st.has(fid):
		return
	var before := rank(fid)
	st[fid].rep = clampf(rep(fid) + v, -100.0, 3000.0)
	Events.faction_rep_changed.emit(fid, rep(fid))
	if absf(v) >= 5.0:
		Events.notify.emit("%s: репутация %+d%s" % [DBEras.faction(fid).name, int(v), (" (%s)" % reason) if reason != "" else ""], DBEras.faction(fid).color)
	var after := rank(fid)
	if member_of() == fid and after > before:
		var rn := rank_name(fid)
		Chronicle.record("rank_up", [world.player], {"extra": {"rank": rn, "faction": DBEras.faction(fid).name}})
		Events.banner.emit("Новое звание: " + rn, DBEras.faction(fid).name, DBEras.faction(fid).color)
		if after >= 2:
			Profile.unlock("faction_rank")
		if after >= 4:
			Profile.unlock("faction_leader")
			st[fid].leader = "player"
			Chronicle.record("leader", [world.player], {"extra": {"faction": DBEras.faction(fid).name}})
		if world.player:
			world.player.recalc_stats()

func open_vendor(fid: String) -> void:
	if member_of() != fid and rep(fid) < 30.0:
		Events.notify.emit("Торговец обслуживает только членов организации или друзей (репутация 30+).", Color(1, 0.6, 0.4))
		return
	var items: Array = []
	var lvl: int = world.player.level
	var r := rank(fid) if member_of() == fid else 0
	for b in DBEras.faction(fid).get("vendor", []):
		var bd := ItemDB.base(b)
		var rar := clampi(r / 2 + (1 if bd.slot in ItemDB.SLOTS else 0), 0, 3)
		var it := ItemDB.create(b, rar if bd.slot in ItemDB.SLOTS else 0, lvl, null, false)
		if not bd.slot in ItemDB.SLOTS:
			it.qty = 3
		items.append(it)
	var mult := 1.0 - (0.15 if r >= 2 else 0.0)
	world.ui.open("trade", {"title": "Торговец: " + DBEras.faction(fid).name, "items": items, "price_mult": mult, "sell": true, "sell_mult": 0.35,
		"buy_cb": func(it): return buy(it, mult)})

func buy(it: Dictionary, mult: float) -> bool:
	var price := int(ItemDB.value(it) * mult)
	var pd: CharData = world.player.data
	if pd.gold < price:
		Events.notify.emit("Недостаточно золота", Color(1, 0.4, 0.4))
		return false
	if not pd.inv.add(it.duplicate(true)):
		Events.notify.emit("Инвентарь полон", Color(1, 0.4, 0.4))
		return false
	pd.gold -= price
	Audio.play_sfx("coin")
	return true

# ---------------------------------------------------------------- territory
func capture_point(pid: String, new_owner: String, by_actor = null) -> void:
	if not points.has(pid) or not points[pid].has("type"):
		return
	var prev: String = points[pid].get("owner", "")
	if prev == new_owner:
		return
	points[pid].owner = new_owner
	var fname = "себя" if new_owner == "player" else DBEras.faction(new_owner).get("name", "свободных")
	var actors: Array = []
	if by_actor != null:
		actors.append(by_actor)
	Chronicle.record("capture", actors if not actors.is_empty() else [{"id": "faction_" + new_owner, "name": fname}], {"extra": {"point": points[pid].name, "faction": fname}})
	if prev != "" and prev != "player":
		st[prev].strength = maxf(20.0, strength(prev) - 6.0)
	if new_owner != "" and new_owner != "player":
		st[new_owner].strength = strength(new_owner) + 6.0
	Events.point_captured.emit(pid, new_owner)

func _on_point_captured(pid, owner_f) -> void:
	var m := member_of()
	if owner_f == "player" or (m != "" and owner_f == m):
		if world.player and world.player.global_position.distance_to(_poi_pos(pid)) < 30.0:
			Profile.milestone("capture_point")
			Profile.unlock("capture")
			if m != "":
				add_rep(m, 30.0, "захват точки")

func _poi_pos(pid: String) -> Vector3:
	if world.gen:
		for p in world.gen.pois:
			if p.id == pid:
				return Vector3(p.pos.x, 0, p.pos.y)
	return Vector3(99999, 0, 99999)

func change_settlement_owner(sid: String, fid: String, reason: String) -> void:
	if not settlements.has(sid):
		return
	var prev: String = settlements[sid].owner
	settlements[sid].owner = fid
	settlements[sid].security = 0.4
	settlements[sid].guards = maxi(1, settlements[sid].guards - 1)
	var fname: String = DBEras.faction(fid).get("name", "мятежников") if fid != "" else "вольных жителей"
	Chronicle.record("settlement_captured", [{"id": "faction_" + fid, "name": fname}], {"extra": {"settlement": settlements[sid].name, "faction": fname, "reason": reason}})
	Events.settlement_changed.emit(settlements[sid])
	if world.settlement_npcs.has(sid):
		for n in world.settlement_npcs[sid]:
			if is_instance_valid(n):
				n.queue_free()
		world.settlement_npcs.erase(sid)
		var s = world._settlement(sid)
		if s != null and world.player and Vector2(world.player.global_position.x, world.player.global_position.z).distance_to(s.pos) < 150.0:
			world._populate_settlement(s)
	if prev != "" and st.has(prev):
		st[prev].strength = maxf(20.0, strength(prev) - 12.0)
	if fid != "" and st.has(fid):
		st[fid].strength = strength(fid) + 12.0

## Strategic layer: factions attack enemies; physical battles near the player.
func _process(delta: float) -> void:
	if Game.mode != "world" or world.gen == null:
		return
	_strat_t += delta
	_income_t += delta
	if _income_t > 120.0:
		_income_t = 0.0
		_income()
	if _strat_t < 50.0:
		return
	_strat_t = 0.0
	var fl := list()
	var att: String = fl[randi() % fl.size()]
	var enemies: Array = []
	for o in fl:
		if at_war(att, o):
			enemies.append(o)
	# occasional diplomacy shifts
	if randf() < 0.12 and fl.size() > 2:
		var a: String = fl[randi() % fl.size()]
		var b: String = fl[randi() % fl.size()]
		if a != b and not b in DBEras.faction(a).enemies:
			var nr := "alliance" if relation(a, b) == "peace" and randf() < 0.5 else ("war" if relation(a, b) == "peace" else "peace")
			st[a].relations[b] = nr
			st[b].relations[a] = nr
			Events.notify.emit("Дипломатия: %s и %s — %s" % [DBEras.faction(a).name, DBEras.faction(b).name, {"war": "война", "peace": "мир", "alliance": "союз"}[nr]], Color(0.9, 0.85, 0.6))
	if enemies.is_empty():
		return
	var target_f: String = enemies[randi() % enemies.size()]
	var targets: Array = []
	for pid in points:
		if not points[pid].has("type"):
			continue
		if points[pid].get("owner", "") == target_f or points[pid].get("owner", "") == "":
			targets.append(["cp", pid])
	for sid in settlements:
		if settlements[sid].owner == target_f and randf() < 0.3:
			targets.append(["settlement", sid])
	if targets.is_empty():
		return
	var tgt: Array = targets[randi() % targets.size()]
	var tpos := _poi_pos(tgt[1]) if tgt[0] == "cp" else _settlement_pos(tgt[1])
	if world.player and world.player.global_position.distance_to(tpos) < 220.0 and world.director:
		world.director.start_battle(att, target_f, tgt[0], tgt[1], tpos)
	else:
		_abstract_battle(att, target_f, tgt)

func _settlement_pos(sid: String) -> Vector3:
	var s = world._settlement(sid)
	if s == null:
		return Vector3(99999, 0, 99999)
	return Vector3(s.pos.x, 0, s.pos.y)

func _abstract_battle(att: String, def_f: String, tgt: Array) -> void:
	var a_pow = strength(att) * randf_range(0.7, 1.3) + world.legends.faction_legend_bonus(att)
	var d_pow = (strength(def_f) if def_f != "" else 60.0) * randf_range(0.7, 1.3) + world.legends.faction_legend_bonus(def_f)
	if tgt[0] == "settlement":
		d_pow *= 1.0 + float(settlements[tgt[1]].get("security", 0.5))
	var winner := att if a_pow > d_pow else def_f
	var place: String = points[tgt[1]].name if tgt[0] == "cp" else settlements[tgt[1]].name
	Chronicle.record("battle", [], {"place": place, "extra": {"a": DBEras.faction(att).name, "b": DBEras.faction(def_f).get("name", "защитники"), "winner": DBEras.faction(winner).get("name", "защитники")}})
	world.legends.battle_outcome(att, def_f, winner, place)
	if winner == att:
		if tgt[0] == "cp":
			capture_point(tgt[1], att)
		else:
			change_settlement_owner(tgt[1], att, "осада")
	else:
		st[att].strength = maxf(20.0, strength(att) - 5.0)

func _income() -> void:
	var m := member_of()
	if m == "" or rank(m) < 4:
		return
	var g := territory(m) * 6 * (Profile.current_era + 1)
	if g > 0 and world.player:
		world.player.data.gold += g
		Events.notify.emit("Доход с территорий: +%d" % g, Color(1.0, 0.85, 0.3))
