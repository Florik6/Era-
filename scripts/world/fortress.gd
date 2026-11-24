class_name Fortress
## The player's stronghold: claim it, upgrade walls/barracks/workshop, hire a
## garrison, appoint a commander (a grateful living legend), store relics,
## defend against raids. Transforms in each era (castle → manor → factory
## compound → bunker → arcology hub).

const ERA_NAMES := ["Замок", "Палаццо", "Фабричная усадьба", "Бункер", "Аркология"]

static func state() -> Dictionary:
	var f: Dictionary = Game.world_state.get("fortress", {})
	Game.world_state.fortress = f
	var carried: Dictionary = Profile.legacy.flags.get("fortress", {})
	if f.is_empty() and carried.get("owned", false):
		# the stronghold transforms into this era's base
		f.owned = true
		f.walls = carried.get("walls", 1)
		f.barracks = carried.get("barracks", 1)
		f.workshop = carried.get("workshop", 0)
		f.commander = ""
		f.garrison = carried.get("barracks", 1) * 2
	return f

static func open(world, poi) -> void:
	var f := state()
	var era := Profile.current_era
	var nm: String = ERA_NAMES[era] + " «%s»" % poi.data.get("name", "Твердыня")
	if not f.get("owned", false):
		var cost := 400 * (era + 1)
		world.ui.open("dialog", {"title": nm, "text": "Заброшенная твердыня. Её можно выкупить у местных старейшин или отбить у засевших мародёров.", "options": [
			{"text": "Выкупить (%d)" % cost, "cb": func():
				if world.player.data.gold >= cost:
					world.player.data.gold -= cost
					_claim(world, poi, nm)
				else:
					Events.notify.emit("Недостаточно золота", Color(1, 0.4, 0.4))},
			{"text": "Отбить силой", "cb": func(): _assault(world, poi, nm)},
			{"text": "Уйти", "cb": func(): pass}]})
		return
	var gold_up := func(lvl: int) -> int: return 250 * (lvl + 1) * (era + 1)
	var opts: Array = []
	for part in [["walls", "Стены"], ["barracks", "Казармы"], ["workshop", "Мастерская"]]:
		var key: String = part[0]
		var lv: int = int(f.get(key, 0))
		if lv < 3:
			var c: int = gold_up.call(lv)
			opts.append({"text": "Улучшить: %s → %d (%d)" % [part[1], lv + 1, c], "cb": func():
				if world.player.data.gold >= c:
					world.player.data.gold -= c
					f[key] = lv + 1
					Events.notify.emit("%s улучшены до уровня %d" % [part[1], lv + 1], Color(0.9, 0.8, 0.5))
					Audio.play_sfx("hit_metal")
				else:
					Events.notify.emit("Недостаточно золота", Color(1, 0.4, 0.4))})
	opts.append({"text": "Нанять защитника (%d)" % (80 * (era + 1)), "cb": func():
		var c2 := 80 * (era + 1)
		if int(f.get("garrison", 0)) >= 2 + int(f.get("barracks", 0)) * 2:
			Events.notify.emit("Казармы переполнены — улучшите их.", Color(1, 0.6, 0.4))
		elif world.player.data.gold >= c2:
			world.player.data.gold -= c2
			f.garrison = int(f.get("garrison", 0)) + 1
			_spawn_garrison(world, poi, 1)
		else:
			Events.notify.emit("Недостаточно золота", Color(1, 0.4, 0.4))})
	var grateful: Array = []
	for r in world.legends.records():
		if r.rel.gratitude > 0.5 or r.rel.respect > 0.8:
			grateful.append(r)
	if not grateful.is_empty():
		var g: Dictionary = grateful[0]
		opts.append({"text": "Назначить командиром: %s" % g.name, "cb": func():
			f.commander = g.id
			g.commander = true
			g.era_history.append("Назначен(а) командиром крепости игрока")
			Chronicle.record("commander", [{"id": g.id, "name": g.name}], {"extra": {"faction": nm}})
			Events.notify.emit("%s теперь командует вашей крепостью." % g.name, Color(0.8, 1.0, 0.7))})
	if int(f.get("workshop", 0)) > 0:
		opts.append({"text": "Мастерская крепости", "cb": func(): Stations.open(world, "forge" if era < 2 else "workshop", poi)})
	opts.append({"text": "Склад реликвий", "cb": func(): Legacy.relic_dialog(world)})
	opts.append({"text": "Уйти", "cb": func(): pass})
	var cmd: Dictionary = world.legends.record(f.get("commander", ""))
	var text := "Стены: %d · Казармы: %d · Мастерская: %d\nГарнизон: %d · Командир: %s" % [f.get("walls", 1), f.get("barracks", 1), f.get("workshop", 0), f.get("garrison", 0), cmd.get("name", "не назначен")]
	world.ui.open("dialog", {"title": nm, "text": text, "portrait_color": Color(0.95, 0.8, 0.5), "options": opts})
	_spawn_garrison(world, poi, 0)

static func _claim(world, poi, nm: String) -> void:
	var f := state()
	f.owned = true
	f.walls = 1
	f.barracks = 1
	f.workshop = 0
	f.garrison = 2
	f.commander = ""
	Profile.unlock("fortress")
	Chronicle.record("fortress", [world.player], {"pos_v3": poi.global_position, "extra": {"name": nm}})
	Events.banner.emit("Крепость ваша!", nm, Color(0.95, 0.8, 0.5))
	_spawn_garrison(world, poi, 0)

static func _assault(world, poi, nm: String) -> void:
	var defs: Array = []
	var ids: Array = DBEras.era(Profile.current_era).enemies.filter(func(x): return DBActors.ENEMIES[x].team == "bandit")
	for i in 5:
		var m = world.spawner.spawn_enemy(ids[i % ids.size()], poi.global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), world.spawner.level_near_player(1))
		if m:
			m.add_aggro(world.player, 120.0)
			defs.append(m)
	Events.banner.emit("Штурм крепости", "Перебейте мародёров!", Color(1.0, 0.6, 0.3))
	_watch(world, poi, defs, nm)

static func _watch(world, poi, defs: Array, nm: String) -> void:
	world.get_tree().create_timer(1.0, false).timeout.connect(func():
		for d in defs:
			if is_instance_valid(d) and not d.is_dead:
				_watch(world, poi, defs, nm)
				return
		_claim(world, poi, nm))

static func _spawn_garrison(world, poi, n: int) -> void:
	var f := state()
	var have: int = poi.get_meta("garrison_spawned", 0)
	var want: int = n if n > 0 else int(f.get("garrison", 0)) - have
	for i in want:
		var s := {"id": "fortress", "owner": world.factions.member_of()}
		var g = world.spawner.spawn_villager(s, poi.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), "guard")
		g.team = "player"
		g.display_name = "Защитник крепости"
		g.dialog_kind = ""
		poi.set_meta("garrison_spawned", have + i + 1)

## Snapshot for era transitions.
static func carry_over() -> void:
	var f: Dictionary = Game.world_state.get("fortress", {})
	if f.get("owned", false):
		Profile.legacy.flags["fortress"] = {"owned": true, "walls": f.get("walls", 1), "barracks": f.get("barracks", 1), "workshop": f.get("workshop", 0)}
