class_name LivingPOIs
extends Node
## Living points of interest: story places with a chain of real events.
## Example: a looted wagon on the road (hook) → tracks → an abandoned mill
## where the gang hides → their journal tells who they are → the beaten
## leader yields: spare him (he joins a faction, remembers the mercy and
## later rises as a living legend), hand him to the guards, or finish him.
## Each era has its own places: mills, chapels, old towers, caves, mines,
## alchemists' workshops, secret labs, abandoned outposts, future sites.
## State per site lives in world_state.living_pois; everything is spawned
## only near the hero and survives save/load.

const SITES := [
	[["mill", "Заброшенная мельница", "bandit", "wagon", "Разбойники ограбили обоз и укрылись на старой мельнице."],
	 ["chapel", "Старая часовня", "cult", "pilgrim", "Пропавшие паломники шли к часовне, где теперь служат тёмную мессу."],
	 ["tower", "Древняя башня", "caster", "lights", "По ночам в окнах древней башни горят огни — там прячется отступник-маг."],
	 ["cave", "Пещера у ручья", "beast", "prints", "Скот пропадает, а следы ведут к пещере у ручья."]],
	[["alch_workshop", "Алхимическая мастерская", "cult", "flask", "Еретики-алхимики отравляют колодцы ради опытов."],
	 ["mine", "Старая шахта", "bandit", "wagon", "Контрабандисты прячут награбленное в старой шахте."],
	 ["tower", "Башня астронома", "caster", "lights", "Безумный астроном призывает существ со звёзд."]],
	[["mine", "Заброшенная шахта", "machine", "tracks", "Из заброшенной шахты выходят взбесившиеся механизмы."],
	 ["secret_lab", "Тайная лаборатория", "bandit", "wagon", "Изобретатель-отступник ворует детали с поездов."],
	 ["chapel", "Сгоревшая часовня", "cult", "pilgrim", "Оккультисты собираются в сгоревшей часовне."]],
	[["secret_lab", "Секретная лаборатория", "machine", "tracks", "Сбежавшие боевые дроны охраняют брошенную лабораторию."],
	 ["outpost", "Брошенный блокпост", "bandit", "wagon", "Наёмники грабят грузовики и прячутся на брошенном блокпосту."]],
	[["future_site", "Сооружение «Кенотаф»", "machine", "tracks", "Сооружение будущего охраняют синтетики, сошедшие с ума."],
	 ["secret_lab", "Лаборатория хронистов", "cult", "pilgrim", "Хроно-культисты пытаются переписать прошлое."]],
]

var world
var sites: Array = []        # {id, kind, name, team, hook, story, pos: Vector2, hook_pos: Vector2}
var _nodes := {}             # id -> {site: Node3D, hook: Node3D}
var _actors := {}            # id -> Array
var _t := 0.0

func setup(w) -> void:
	world = w
	if w.gen == null:
		return
	if not Game.world_state.has("living_pois"):
		Game.world_state["living_pois"] = {}
	_place_sites()

func _st(id: String) -> Dictionary:
	var all: Dictionary = Game.world_state.living_pois
	if not all.has(id):
		all[id] = {"stage": 0}
	return all[id]

func _place_sites() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Profile.world_seed * 31 + world.era * 977
	var defs: Array = SITES[clampi(world.era, 0, SITES.size() - 1)]
	var setts: Array = world.gen.settlements
	if setts.is_empty():
		return
	for i in defs.size():
		var d: Array = defs[i]
		var s: Dictionary = setts[(i * 3 + rng.randi() % maxi(1, setts.size())) % setts.size()]
		var pos := Vector2.ZERO
		var ok := false
		for tries in 30:
			var a := rng.randf() * TAU
			pos = s.pos + Vector2(cos(a), sin(a)) * rng.randf_range(110.0, 210.0)
			if absf(pos.x) > world.world_half - 60.0 or absf(pos.y) > world.world_half - 60.0:
				continue
			if world.gen.has_method("is_water") and world.gen.is_water(pos.x, pos.y):
				continue
			var clear := true
			for p in world.gen.pois:
				if p.pos.distance_to(pos) < 45.0:
					clear = false
					break
			for s2 in setts:
				if s2.pos.distance_to(pos) < 70.0:
					clear = false
					break
			if clear:
				ok = true
				break
		if not ok:
			continue
		var hook: Vector2 = s.pos.lerp(pos, 0.45)
		sites.append({"id": "lp_%d_%d" % [world.era, i], "kind": d[0], "name": d[1], "team": d[2], "hook": d[3], "story": d[4], "pos": pos, "hook_pos": hook, "settlement": s.name})

func markers() -> Array:
	var out: Array = []
	var disc = world.sys("discovery")
	for s in sites:
		var st := _st(s.id)
		if st.stage >= 1 or (disc and disc.is_discovered(s.id)):
			out.append({"pos": s.pos, "kind": "story", "name": s.name + (" ✓" if st.stage >= 3 else ""), "color": Color(0.95, 0.75, 0.45) if st.stage < 3 else Color(0.6, 0.6, 0.6)})
	return out

func _process(delta: float) -> void:
	if world == null or world.dimension != "" or world.player == null or not is_instance_valid(world.player):
		return
	for id in _nodes:
		if _has(id, "site"):
			var bl = _nodes[id].site.get_node_or_null("Blades")
			if bl:
				bl.rotation.z += delta * 0.4
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	var pp: Vector3 = world.player.global_position
	var p2 := Vector2(pp.x, pp.z)
	for s in sites:
		var st := _st(s.id)
		var dh: float = p2.distance_to(s.hook_pos)
		var ds: float = p2.distance_to(s.pos)
		# hook scene on the road
		if st.stage == 0 and dh < 120.0 and not _has(s.id, "hook"):
			_spawn_hook(s)
		elif _has(s.id, "hook") and (dh > 200.0 or st.stage >= 2):
			_free(s.id, "hook")
		# the place itself
		if ds < 110.0 and not _has(s.id, "site"):
			_spawn_site(s)
		elif _has(s.id, "site") and ds > 200.0:
			_free(s.id, "site")
			_despawn_actors(s.id)
		if ds < 28.0 and st.stage <= 1:
			_arrive(s)
		if st.stage == 2:
			_tick_fight(s)
		# consequence: a spared leader rises as a legend a day later
		if st.get("choice", "") == "spared" and not st.get("legend_done", false) and Game.day() >= int(st.get("day", 0)) + 1:
			st.legend_done = true
			var r: Dictionary = world.legends.record(st.get("leader_id", ""))
			if not r.is_empty() and r.alive:
				r.renown = maxf(float(r.renown), world.legends.LEGEND_RENOWN)
				r.survivals = int(r.survivals) + 2
				world.legends._check_promotion(r)

func _has(id: String, part: String) -> bool:
	return _nodes.has(id) and _nodes[id].has(part) and is_instance_valid(_nodes[id][part])

func _free(id: String, part: String) -> void:
	if _has(id, part):
		_nodes[id][part].queue_free()
	if _nodes.has(id):
		_nodes[id].erase(part)

func _put(id: String, part: String, n: Node3D, pos2: Vector2) -> void:
	world.fx_root.add_child(n)
	var p := Vector3(pos2.x, 0, pos2.y)
	p.y = world.ground_height(p)
	n.global_position = p
	if not _nodes.has(id):
		_nodes[id] = {}
	_nodes[id][part] = n

# ------------------------------------------------------------------ hook
func _spawn_hook(s: Dictionary) -> void:
	var root := Node3D.new()
	var kind = {"wagon": "wrecked_cart", "pilgrim": "corpse", "lights": "campfire", "prints": "huge_print", "flask": "loot", "tracks": "wrecked_cart"}.get(s.hook, "wrecked_cart")
	var pr := RoadEncounters.make_prop(kind, world.era, randf() * TAU)
	root.add_child(pr)
	if s.hook in ["wagon", "pilgrim"]:
		var pr2 := RoadEncounters.make_prop("loot", world.era, 0.5)
		root.add_child(pr2)
		pr2.position = Vector3(1.6, 0, 0.8)
	var spot := StorySpot.new()
	spot.label = "Осмотреть: " + {"wagon": "разграбленную повозку", "pilgrim": "тело паломника", "lights": "брошенный костёр", "prints": "следы", "flask": "разбитые склянки", "tracks": "обломки"}.get(s.hook, "место")
	var sid: String = s.id
	spot.on_interact = func(_a): _hook_used(sid)
	root.add_child(spot)
	spot.position = Vector3(0, 0, 1.6)
	_put(s.id, "hook", root, s.hook_pos)

func _site_by_id(id: String) -> Dictionary:
	for s in sites:
		if s.id == id:
			return s
	return {}

func _hook_used(id: String) -> void:
	var s := _site_by_id(id)
	var st := _st(id)
	if s.is_empty() or st.stage > 0:
		return
	st.stage = 1
	var disc = world.sys("discovery")
	if disc:
		disc.reveal(id)
	world.ui.open("dialog", {"title": s.name, "text": s.story + "\n\nСледы ведут прочь от дороги — к месту «%s»." % s.name, "options": [{"text": "Идти по следу", "cb": func(): pass}]})
	var tr = world.sys("tracking")
	if tr:
		var from: Vector3 = Vector3(s.hook_pos.x, 0, s.hook_pos.y)
		var kind = {"prints": "huge", "lights": "magic", "tracks": "tire"}.get(s.hook, "footprints")
		tr.start_trail(from, Vector3(s.pos.x, 0, s.pos.y), kind, {"label": "След к месту «%s»" % s.name})
	Chronicle.record("discovery", [world.player], {"pos_v3": world.player.global_position, "extra": {"place": s.name, "category": "story"}})

# ------------------------------------------------------------------ site
func _spawn_site(s: Dictionary) -> void:
	_put(s.id, "site", _build_site(s.kind), s.pos)

func _build_site(kind: String) -> Node3D:
	var n := Node3D.new()
	var wood := MeshLib.mat(Color(0.42, 0.3, 0.18))
	var stone := MeshLib.mat(Color(0.5, 0.48, 0.45))
	var dark := MeshLib.mat(Color(0.14, 0.12, 0.12))
	var metal := MeshLib.mat(Color(0.42, 0.44, 0.48), 0.7, 0.4)
	match kind:
		"mill":
			MeshLib.part(n, MeshLib.box(Vector3(5, 5, 5)), stone, Vector3(0, 2.5, 0))
			MeshLib.part(n, MeshLib.prism(Vector3(5.6, 2.5, 5.6)), wood, Vector3(0, 6.2, 0))
			var blades := Node3D.new()
			blades.name = "Blades"
			n.add_child(blades)
			blades.position = Vector3(0, 5.0, 2.8)
			for i in 4:
				MeshLib.part(blades, MeshLib.box(Vector3(0.6, 4.2, 0.1)), wood, Vector3(0, 2.1, 0).rotated(Vector3(0, 0, 1), i * PI / 2), Vector3(0, 0, i * 90))
			MeshLib.part(n, MeshLib.box(Vector3(1.4, 2.2, 0.2)), dark, Vector3(0, 1.1, 2.55))
		"chapel":
			MeshLib.part(n, MeshLib.box(Vector3(5, 4, 8)), stone, Vector3(0, 2, 0))
			MeshLib.part(n, MeshLib.prism(Vector3(5.4, 2.4, 8.4)), dark, Vector3(0, 5.2, 0))
			MeshLib.part(n, MeshLib.box(Vector3(1.6, 7, 1.6)), stone, Vector3(0, 3.5, -4.6))
			MeshLib.part(n, MeshLib.box(Vector3(0.2, 1.4, 0.2)), metal, Vector3(0, 7.8, -4.6))
			MeshLib.part(n, MeshLib.box(Vector3(0.8, 0.2, 0.2)), metal, Vector3(0, 8.0, -4.6))
		"tower":
			MeshLib.part(n, MeshLib.cyl(2.4, 2.8, 12.0, 12), stone, Vector3(0, 6, 0))
			MeshLib.part(n, MeshLib.cyl(0.1, 3.0, 2.5, 12), dark, Vector3(0, 13.2, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.5, 0.8, 0.1)), MeshLib.glow(Color(1.0, 0.8, 0.4), 2.5), Vector3(0, 9, 2.45))
		"cave":
			MeshLib.part(n, MeshLib.sphere(6.0, 10, 6), stone, Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(1.2, 0.6, 1.0))
			MeshLib.part(n, MeshLib.box(Vector3(2.6, 2.4, 1.0)), dark, Vector3(0, 1.2, 6.0))
		"mine":
			MeshLib.part(n, MeshLib.box(Vector3(4, 3.4, 0.6)), wood, Vector3(0, 1.7, 0))
			MeshLib.part(n, MeshLib.box(Vector3(2.6, 2.6, 0.7)), dark, Vector3(0, 1.3, 0.05))
			for x in [-1.0, 1.0]:
				MeshLib.part(n, MeshLib.box(Vector3(0.12, 0.08, 8.0)), metal, Vector3(x * 0.6, 0.05, 4.0))
			MeshLib.part(n, MeshLib.box(Vector3(1.2, 0.8, 1.6)), metal, Vector3(0, 0.5, 4.0))
		"alch_workshop":
			MeshLib.part(n, MeshLib.box(Vector3(6, 3.6, 5)), wood, Vector3(0, 1.8, 0))
			MeshLib.part(n, MeshLib.prism(Vector3(6.4, 2, 5.4)), dark, Vector3(0, 4.6, 0))
			MeshLib.part(n, MeshLib.cyl(0.4, 0.5, 2.5, 8), stone, Vector3(2.2, 5.5, -1.5))
			MeshLib.part(n, MeshLib.cyl(0.8, 0.8, 1.0, 10), MeshLib.glow(Color(0.4, 1.0, 0.5), 1.6), Vector3(-2.0, 0.5, 3.2))
		"secret_lab":
			MeshLib.part(n, MeshLib.box(Vector3(8, 3.2, 6)), metal, Vector3(0, 1.6, 0))
			MeshLib.part(n, MeshLib.box(Vector3(8.2, 0.2, 6.2)), MeshLib.glow(Color(0.3, 0.9, 1.0), 1.5), Vector3(0, 3.3, 0))
			MeshLib.part(n, MeshLib.cyl(0.1, 0.1, 5.0, 6), metal, Vector3(3, 5.6, 2))
		"outpost":
			MeshLib.part(n, MeshLib.box(Vector3(6, 2.6, 4)), MeshLib.mat(Color(0.4, 0.42, 0.35)), Vector3(0, 1.3, 0))
			for i in 6:
				MeshLib.part(n, MeshLib.box(Vector3(1.2, 1.0, 0.7)), MeshLib.mat(Color(0.6, 0.55, 0.4)), Vector3(-4 + i * 1.6, 0.5, 4.0))
			MeshLib.part(n, MeshLib.box(Vector3(0.3, 4, 0.3)), metal, Vector3(3.5, 2, -2))
		_:
			MeshLib.part(n, MeshLib.sphere(5.0, 14, 8), MeshLib.mat(Color(0.2, 0.22, 0.3), 0.6, 0.3), Vector3(0, 0, 0), Vector3.ZERO, Vector3(1.4, 0.8, 1.4))
			MeshLib.part(n, MeshLib.torus(6.2, 6.5), MeshLib.glow(Color(0.8, 0.3, 1.0), 2.4), Vector3(0, 0.1, 0), Vector3.ZERO, Vector3.ONE, false)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.4)
	l.light_energy = 1.0
	l.omni_range = 9.0
	l.position = Vector3(2.5, 1.6, 3.5)
	l.shadow_enabled = false
	n.add_child(l)
	return n

func _arrive(s: Dictionary) -> void:
	var st := _st(s.id)
	if st.stage == 0:
		st.stage = 1
	var disc = world.sys("discovery")
	if disc and not disc.is_discovered(s.id):
		disc._discover(s.id, s.name, "secret", Vector3(s.pos.x, 0, s.pos.y))
	if st.stage == 1 and not _actors.has(s.id):
		_spawn_inhabitants(s)
		st.stage = 2

func _pool(team: String) -> Array:
	var ed: Dictionary = DBEras.era(world.era)
	var all: Array = ed.enemies + ed.night_enemies
	var want = {"bandit": ["bandit"], "cult": ["monster", "bandit"], "caster": ["monster"], "beast": ["beast", "monster"], "machine": ["monster", "machine", "bandit"]}.get(team, ["bandit"])
	var out: Array = all.filter(func(x): return DBActors.ENEMIES.has(x) and DBActors.ENEMIES[x].team in want)
	if team in ["caster", "cult"]:
		var c2: Array = out.filter(func(x): return DBActors.ENEMIES[x].ai in ["caster", "ranged"])
		if not c2.is_empty():
			out = c2 + out
	if out.is_empty():
		out = ed.enemies.duplicate()
	return world.spawner.suitable(out)

func _spawn_inhabitants(s: Dictionary) -> void:
	var st := _st(s.id)
	var pool := _pool(s.team)
	var arr: Array = []
	var center := Vector3(s.pos.x, 0, s.pos.y)
	for i in 3 + mini(2, world.era):
		var a := TAU * i / 5.0
		var m = world.spawner.spawn_enemy(pool[i % pool.size()], center + Vector3(cos(a), 0, sin(a)) * 6.0)
		if m:
			m.home = m.global_position
			arr.append(m)
	# the leader: a named person with a record (can survive, remember and rise)
	if s.team in ["bandit", "cult", "caster"]:
		var nm := DBActors.rand_name(world.era, randf() < 0.3, Game.rng)
		var rec: Dictionary = {}
		if st.get("leader_id", "") != "":
			rec = world.legends.record(st.leader_id)
		if rec.is_empty():
			rec = world.legends.new_record(nm, {"level": world.spawner.level_near_player(2), "archetype": "ambitious", "class_id": "mage" if s.team != "bandit" else "warrior"})
			rec.memories.append({"t": Game.game_time, "text": "Я собрал(а) людей у места «%s». %s" % [s.name, s.story]})
			st.leader_id = rec.id
		if rec.alive:
			var ld = world.spawner.spawn_bot(rec, center + Vector3(0, 0, -3))
			if ld:
				ld.team = "bandit"
				ld.display_name = "%s, главарь" % rec.name
				ld.add_aggro(world.player, 40.0)
				world.spawner.name_tag(ld, Color(1.0, 0.6, 0.4))
				ld.set_meta("story_leader", s.id)
				arr.append(ld)
	_actors[s.id] = arr
	# their journal tells the story
	if _has(s.id, "site"):
		var j := StorySpot.new()
		j.label = "Прочитать записи"
		var sid: String = s.id
		j.on_interact = func(_a): _read_journal(sid)
		_nodes[s.id].site.add_child(j)
		j.position = Vector3(3.0, 0, 3.0)
	Events.notify.emit("%s: здесь кто-то есть!" % s.name, Color(1.0, 0.6, 0.4))

func _read_journal(id: String) -> void:
	var s := _site_by_id(id)
	var st := _st(id)
	if st.get("journal", false):
		world.ui.open("dialog", {"title": "Записи", "text": st.get("journal_text", s.story), "options": [{"text": "Закрыть", "cb": func(): pass}]})
		return
	st.journal = true
	var r: Dictionary = world.legends.record(st.get("leader_id", ""))
	var who: String = r.get("name", "главарь")
	var txt := "«День за днём. %s\nЛюди злятся: добычи всё меньше. Если %s не найдёт нового дела, банда разбежится.»\n\nВы узнали, кто стоит за всем этим: %s." % [s.story, who, who]
	st.journal_text = txt
	world.player.gain_xp(30 + 10 * world.era)
	world.ui.open("dialog", {"title": "Записи у места «%s»" % s.name, "text": txt, "options": [{"text": "Закрыть", "cb": func(): pass}]})

func _despawn_actors(id: String) -> void:
	for a in _actors.get(id, []):
		if is_instance_valid(a) and not a.is_dead:
			a.queue_free()
	_actors.erase(id)
	var st := _st(id)
	if st.stage == 2:
		st.stage = 1      # come back later: they're still there

func _tick_fight(s: Dictionary) -> void:
	var st := _st(s.id)
	var arr: Array = _actors.get(s.id, [])
	var leader = null
	var henchmen := 0
	for a in arr:
		if not is_instance_valid(a) or a.is_dead:
			continue
		if a.has_meta("story_leader"):
			leader = a
		else:
			henchmen += 1
	var r: Dictionary = world.legends.record(st.get("leader_id", ""))
	if leader == null:
		if not r.is_empty() and r.get("alive", true):
			# the leader vanished without dying (despawned): they'll be back
			if henchmen == 0:
				_actors.erase(s.id)
				st.stage = 1
			return
		if henchmen == 0 and not arr.is_empty():
			# leader dead (or there was none): the place is cleared
			_resolve(s, "killed" if not r.is_empty() else "cleared")
		return
	if henchmen == 0 and leader.hp < leader.max_hp * 0.35 and not st.get("yielded", false):
		st.yielded = true
		leader.aggro.clear()
		if leader.brain and leader.brain.has_method("shutdown"):
			leader.brain.shutdown()
		leader.brain = null
		leader.move_input = Vector3.ZERO
		leader.team = "neutral"
		if leader.rig:
			leader.rig.yielding = true
		var ld = leader
		world.ui.open("dialog", {"title": ld.display_name, "text": "«Хватит! Я сдаюсь… Мы грабили, потому что иначе нас ждала голодная смерть. Отпусти — и я уйду к тем, кто даст мне честное дело».",
			"options": [
				{"text": "Пощадить (уйдёт во фракцию)", "cb": func(): _spare(s, ld)},
				{"text": "Сдать страже (+репутация, награда)", "cb": func(): _hand_over(s, ld)},
				{"text": "Добить", "cb": func(): ld.die(world.player)}]})

func _spare(s: Dictionary, ld) -> void:
	var st := _st(s.id)
	var r: Dictionary = world.legends.record(st.leader_id)
	var facs: Array = DBEras.factions_of(world.era)
	var fid: String = facs[randi() % facs.size()]
	r.faction = fid
	r.archetype = "defender"
	r.rel.gratitude += 2.0
	r.renown = float(r.renown) + 20.0
	r.memories.append({"t": Game.game_time, "text": "%s пощадил(а) меня у места «%s». Я ушёл(ушла) к «%s» и не забуду этой милости." % [Profile.char.name, s.name, DBEras.faction(fid).name]})
	Chronicle.record("mercy", [world.player, ld], {"pos_v3": ld.global_position})
	if is_instance_valid(ld):
		ld.faction_id = fid
		ld.team = "bot"
		if ld.rig:
			ld.rig.yielding = false
		ld.brain = BotBrain.new(ld)
	world.player.data.fame += 4.0
	_resolve(s, "spared")
	Events.banner.emit("Милосердие", "%s уходит к «%s». Мир запомнит это." % [r.name, DBEras.faction(fid).name], Color(0.7, 1.0, 0.8))

func _hand_over(s: Dictionary, ld) -> void:
	var st := _st(s.id)
	var r: Dictionary = world.legends.record(st.leader_id)
	r.alive = false
	r.cause_of_death = "казнён по приговору"
	var gold: int = 60 * (world.era + 1)
	world.player.data.gold += gold
	var facs: Array = DBEras.factions_of(world.era)
	if world.factions and world.factions.has_method("add_rep") and not facs.is_empty():
		world.factions.add_rep(facs[0], 8.0)
	Chronicle.record("story", [world.player], {"pos_v3": ld.global_position, "text": "%s сдал(а) страже главаря %s у места «%s»." % [Profile.char.name, r.get("name", "?"), s.name]})
	if is_instance_valid(ld):
		ld.queue_free()
	_resolve(s, "handed")
	Events.banner.emit("Правосудие", "Награда: %d %s" % [gold, DBEras.era(world.era).currency], Color(0.9, 0.85, 0.5))

func _resolve(s: Dictionary, choice: String) -> void:
	var st := _st(s.id)
	if st.stage >= 3:
		return
	st.stage = 3
	st.choice = choice
	st.day = Game.day()
	world.player.gain_xp(80 + 30 * world.era)
	if _has(s.id, "site") and ResourceLoader.exists("res://scripts/world/chest.gd"):
		var ch = load("res://scripts/world/chest.gd").new()
		ch.set("tier", "rich")
		ch.set("lvl", world.spawner.level_near_player(2))
		_nodes[s.id].site.add_child(ch)
		ch.position = Vector3(-3.0, 0, 3.0)
	if choice in ["killed", "cleared"]:
		Events.banner.emit("Место очищено", s.name, Color(0.8, 1.0, 0.7))
	Chronicle.record("story", [world.player], {"pos_v3": Vector3(s.pos.x, 0, s.pos.y), "text": "История места «%s» завершилась: %s." % [s.name, {"spared": "главарь пощажён", "handed": "главарь сдан страже", "killed": "главарь убит", "cleared": "логово уничтожено"}.get(choice, choice)]})

## Interactable used by story places (hooks, journals).
class StorySpot:
	extends Node3D
	var label := "Осмотреть"
	var interact_radius := 2.8
	var on_interact: Callable
	func _ready() -> void:
		var lb := Label3D.new()
		lb.text = "!"
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 56
		lb.pixel_size = 0.006
		lb.outline_size = 10
		lb.modulate = Color(1.0, 0.85, 0.4)
		lb.position.y = 1.6
		lb.visibility_range_end = 35.0
		add_child(lb)
		Game.grid.insert_deferred(self, "interact")
	func _exit_tree() -> void:
		Game.grid.remove(self, "interact")
	func interact_label() -> String:
		return label
	func interact(a) -> void:
		if a.is_player and on_interact.is_valid():
			on_interact.call(a)
