class_name EventDirector2
extends Node
## World Event Director 2.0. Picks one of the 160 DBEvents templates that
## fits the moment (era, place, time of day, buildings, townsfolk, world
## state, weather, town peace state, cool-downs) using category weights
## (towns: mostly social/economic, a small share of dangers), and runs it as
## a real scenario: participants and objects appear, there is a goal and a
## state, it ends with a concrete result and consequences (economy,
## renown, chronicle, legends), and its temporary objects and people are
## removed (visitors walk away first). Danger events in towns go through
## CityPeace (rare, never during recovery).
## Budget: at most MAX_ACTIVE events at a time, one per town, a gap of
## TOWN_GAP game days between starts in a town, a per-template cool-down.

const TICK := 10.0
const MAX_ACTIVE := 2
const TOWN_GAP := 0.125          # 3 game hours between starts in one town
const TEMPLATE_CD := 2.0         # game days before a template may repeat
const NEAR_TOWN := 140.0

static var inst: EventDirector2 = null

var world
var active: Array = []
var history := {}                # template id -> {"n": int, "last": day, "results": [..]}
var town_last := {}              # sid -> day of the last start
var stats := {"started": 0, "ended": 0, "success": 0, "refused": 0, "by_cat": {}, "peace_hits": 0, "temp_npcs": 0, "temp_nodes": 0}
var enabled := true
var _t := 4.0

func setup(w) -> void:
	world = w
	inst = self
	var sv: Dictionary = Game.world_state.get("events2", {})
	history = sv.get("history", {})
	town_last = sv.get("town_last", {})
	Events.actor_damaged.connect(_on_damaged)

func _exit_tree() -> void:
	if inst == self:
		inst = null

func save_state() -> void:
	Game.world_state.events2 = {"history": history, "town_last": town_last}

# ---------------------------------------------------------------- selection
func _context() -> Dictionary:
	var pp: Vector3 = world.player.global_position
	var town = null
	var bd := INF
	for s in world.gen.settlements:
		var d := Vector2(s.pos.x - pp.x, s.pos.y - pp.z).length()
		if d < float(s.radius) + NEAR_TOWN and d < bd:
			bd = d
			town = s
	return {"pos": pp, "town": town, "in_town": town != null and bd < float(town.radius) + 30.0, "hour": Game.hour(), "era": Profile.current_era}

func _hour_ok(h: float, w: Array) -> bool:
	var a := float(w[0])
	var b := float(w[1])
	if a <= b:
		return h >= a and h < b
	return h >= a or h < b

func _town_has(s: Dictionary, kinds: Array) -> bool:
	if kinds.is_empty():
		return true
	var have := {}
	for b in s.get("buildings", []):
		have[String(b.kind)] = true
	for k in kinds:
		if not have.has(k):
			return false
	return true

## "" when the template may start now, otherwise the reason it cannot.
func why_not(tpl: Dictionary, ctx: Dictionary, force := false) -> String:
	if int(tpl.era) != int(ctx.era):
		return "другая эпоха"
	for e in active:
		if e.tpl.id == tpl.id:
			return "уже идёт"
	if not force and Game.game_time - float(history.get(tpl.id, {}).get("last", -99.0)) < TEMPLATE_CD:
		return "недавно было"
	if not _hour_ok(ctx.hour, tpl.hours):
		return "не то время суток"
	var s = ctx.town
	if s == null:
		return "нет поселения рядом"
	if not _town_has(s, tpl.needs):
		return "нет нужного здания"
	if String(tpl.where) in ["inn", "smithy", "shop", "hall", "warehouse"] and not _town_has(s, [tpl.where]) and tpl.where != "hall":
		return "нет здания для места"
	if world.settlement_npcs.get(s.id, []).is_empty() and String(tpl.arch) in ["gathering", "dispute", "competition"]:
		return "нет жителей"
	for e in active:
		if e.sid == s.id and not force:
			return "в поселении уже идёт событие"
	if not force and Game.game_time - float(town_last.get(s.id, -99.0)) < TOWN_GAP:
		return "слишком часто"
	var wc: String = tpl.get("world", "")
	if wc == "blood_moon" and not (world.director.has_method("blood_moon_active") and world.director.blood_moon_active()):
		return "нет кровавой луны"
	var wt: String = tpl.get("weather", "")
	if wt != "" and not force and world.weather and not world.weather.current in [wt, "storm"]:
		return "не та погода"
	if bool(tpl.get("legend", false)) and _pick_legend() == null:
		return "нет живой легенды"
	if CityPeace.inst:
		var st: String = CityPeace.inst.state_of(s.id)
		if st in ["alarm", "attack"]:
			return "в городе тревога"
		if tpl.arch == "raid" and not CityPeace.inst.can_raid(s.id):
			return "город недавно атаковали"
		if tpl.cat == "danger" and st == "recovery" and tpl.arch != "hazard":
			return "город восстанавливается"
	return ""

func pick(ctx: Dictionary) -> Dictionary:
	var pool := {}
	for tpl in DBEvents.of_era(ctx.era):
		if why_not(tpl, ctx) == "":
			if not pool.has(tpl.cat):
				pool[tpl.cat] = []
			pool[tpl.cat].append(tpl)
	if pool.is_empty():
		return {}
	var weights: Dictionary = DBEvents.W_TOWN if ctx.in_town else DBEvents.W_WILD
	var total := 0.0
	for c in pool:
		total += float(weights.get(c, 0.1))
	var r := randf() * total
	var cat: String = pool.keys()[0]
	for c in pool:
		r -= float(weights.get(c, 0.1))
		if r <= 0.0:
			cat = c
			break
	var lst: Array = pool[cat]
	# prefer templates seen less often
	lst.sort_custom(func(a, b): return int(history.get(a.id, {}).get("n", 0)) < int(history.get(b.id, {}).get("n", 0)))
	return lst[randi() % mini(3, lst.size())]

func _process(delta: float) -> void:
	if not enabled or world == null or world.player == null or not is_instance_valid(world.player) or Game.mode != "world":
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	for e in active.duplicate():
		_tick(e)
	if world.dimension != "" or active.size() >= MAX_ACTIVE:
		return
	if randf() > 0.35:
		return
	var ctx := _context()
	var tpl := pick(ctx)
	if not tpl.is_empty():
		start(tpl, ctx)

# ---------------------------------------------------------------- lifecycle
## Start a template (tests may force it in the current town).
func start(tpl: Dictionary, ctx: Dictionary = {}, force := false) -> Dictionary:
	if ctx.is_empty():
		ctx = _context()
	var why := why_not(tpl, ctx, force)
	if why != "":
		stats.refused += 1
		return {"refused": why}
	var s: Dictionary = ctx.town
	var e := {"uid": Game.new_uid("ev2"), "tpl": tpl, "sid": s.id, "town": s, "t0": Game.game_time, "until": Game.game_time + float(tpl.dur) / 24.0,
		"state": "running", "nodes": [], "npcs": [], "foes": [], "data": {}, "objective": "", "result": "", "ok": false, "progress": 0}
	e.pos = _place(e)
	active.append(e)
	town_last[s.id] = Game.game_time
	var h: Dictionary = history.get(tpl.id, {"n": 0, "last": -99.0, "results": []})
	h.n = int(h.n) + 1
	h.last = Game.game_time
	history[tpl.id] = h
	stats.started += 1
	stats.by_cat[tpl.cat] = int(stats.by_cat.get(tpl.cat, 0)) + 1
	call("_start_" + String(tpl.arch), e)
	Events.notify.emit("%s: %s" % [tpl.name, tpl.desc], _cat_color(tpl.cat))
	if e.objective != "":
		Events.notify.emit("Цель: " + e.objective, Color(1.0, 0.85, 0.5))
	return e

func _cat_color(c: String) -> Color:
	return {"social": Color(0.95, 0.85, 0.55), "economic": Color(0.7, 0.9, 0.6), "explore": Color(0.6, 0.8, 1.0),
		"atmos": Color(0.8, 0.7, 1.0), "danger": Color(1.0, 0.5, 0.4)}.get(c, Color(1, 1, 1))

func _tick(e: Dictionary) -> void:
	if e.state != "running":
		return
	var fn := "_tick_" + String(e.tpl.arch)
	if has_method(fn):
		call(fn, e)
	if e.state == "running" and Game.game_time >= float(e.until):
		call("_timeout_" + String(e.tpl.arch), e) if has_method("_timeout_" + String(e.tpl.arch)) else finish(e, "событие завершилось", true)

## Ends an event with a concrete result and applies its consequences.
func finish(e: Dictionary, result: String, ok: bool) -> void:
	if e.state != "running":
		return
	e.state = "done"
	e.result = result
	e.ok = ok
	var tpl: Dictionary = e.tpl
	if ok:
		stats.success += 1
		for c in tpl.get("econ", {}):
			if CityEconomy.inst:
				var v: float = tpl.econ[c]
				if v >= 0.0:
					CityEconomy.inst.deliver(e.sid, c, v, tpl.name)
				else:
					CityEconomy.inst.cut_supply(e.sid, c, 0.5, -v, tpl.name)
	var h: Dictionary = history.get(tpl.id, {})
	if h.has("results"):
		h.results.append({"t": Game.game_time, "result": result, "ok": ok})
		if h.results.size() > 5:
			h.results.pop_front()
	stats.ended += 1
	Chronicle.record("event2", e.get("actors_rec", []), {"pos_v3": e.pos, "place": e.town.get("name", ""), "extra": {"name": tpl.name, "result": result, "id": tpl.id}})
	Events.notify.emit("%s — %s" % [tpl.name, result], _cat_color(tpl.cat))
	_cleanup(e)
	active.erase(e)

func _cleanup(e: Dictionary) -> void:
	for n in e.nodes:
		if is_instance_valid(n):
			n.queue_free()
	e.nodes.clear()
	for a in e.npcs:
		if is_instance_valid(a):
			if a.has_meta("leaves") and not a.is_dead:
				_send_away(a)
			else:
				a.queue_free()
	e.npcs.clear()
	for a in e.foes:
		if is_instance_valid(a) and not a.is_dead:
			a.queue_free()
	e.foes.clear()
	for a in e.get("crowd", []):
		if is_instance_valid(a):
			a.remove_meta("plan")
			if a.get("brain"):
				a.brain.think_t = 0.0
	if e.data.has("lights"):
		for pair in e.data.lights:
			if is_instance_valid(pair[0]):
				pair[0].light_energy = pair[1]

## Visitors don't vanish in front of the hero: they walk out of town first.
func _send_away(a) -> void:
	var c: Vector3 = Vector3(world.player.global_position)
	var out: Vector3 = a.global_position + (a.global_position - c).normalized() * 45.0
	a.set_meta("walk_to", out)
	var t := get_tree().create_timer(25.0, false)
	t.timeout.connect(func():
		if is_instance_valid(a):
			a.queue_free())

func _on_damaged(t, amount: float, src, _dt: String) -> void:
	if amount <= 0.0 or t == null or not is_instance_valid(t):
		return
	for e in active:
		if e.tpl.cat == "danger" or e.tpl.arch in ["competition", "hazard"]:
			continue
		if t in e.npcs or (src != null and is_instance_valid(src) and src in e.npcs):
			stats.peace_hits += 1

func _physics_process(delta: float) -> void:
	# simple scripted walking for event participants (no brain)
	for e in active:
		for a in e.npcs + e.get("porters", []):
			_walk_step(a)
	for a in get_tree().get_nodes_in_group("ev2_leaving"):
		_walk_step(a)

func _walk_step(a) -> void:
	if not is_instance_valid(a) or a.is_dead or not a.has_meta("walk_to"):
		return
	var to: Vector3 = a.get_meta("walk_to") - a.global_position
	to.y = 0
	if to.length() < 0.8:
		a.move_input = Vector3.ZERO
		a.remove_meta("walk_to")
		if a.has_meta("then_face"):
			a.face_dir(a.get_meta("then_face"))
		return
	a.move_input = to.normalized() * 0.7

# ---------------------------------------------------------------- helpers
func _place(e: Dictionary) -> Vector3:
	var s: Dictionary = e.town
	var c := Vector3(s.pos.x, float(s.height), s.pos.y)
	var where: String = e.tpl.where
	if where == "outskirts":
		for i in 12:
			var a := randf() * TAU
			var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * (float(s.radius) + randf_range(28.0, 60.0))
			p.y = world.ground_height(p)
			if not world.is_water(p):
				return p
		return c + Vector3(float(s.radius) + 35.0, 0, 0)
	if where in ["inn", "smithy", "shop", "hall", "warehouse"]:
		for b in s.get("buildings", []):
			if String(b.kind) == where:
				var bas := Basis(Vector3.UP, float(b.rot))
				var door: Vector3 = Vector3(b.pos.x, float(s.height), b.pos.y) + bas * Vector3(0, 0, b.size.y * 0.5 + 3.0)
				return door
	var p2 := c + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	p2.y = world.ground_height(p2)
	return p2

func _npc(e: Dictionary, title: String, pos: Vector3, role := "villager", leaves := true):
	pos.y = world.ground_height(pos)
	var n = world.spawner.spawn_villager({"id": "", "owner": world.factions.settlement_owner(e.sid)}, pos, role)
	if n == null:
		return null
	n.brain = null
	n.display_name = "%s %s" % [title, n.display_name.get_slice(" ", 0)] if title != "" else n.display_name
	n.set_meta("ev2", e.uid)
	if leaves:
		n.set_meta("leaves", true)
	world.spawner.name_tag(n, Color(1.0, 0.9, 0.6))
	e.npcs.append(n)
	stats.temp_npcs += 1
	return n

func _foe(e: Dictionary, kind: String, pos: Vector3):
	var era := Profile.current_era
	var ids: Array = []
	var ed: Dictionary = DBEras.era(era)
	match kind:
		"wolf":
			ids = ed.enemies.filter(func(x): return DBActors.ENEMIES[x].rig == "wolf")
		"bandit", "pirate", "criminal", "scout":
			ids = ed.enemies.filter(func(x): return DBActors.ENEMIES[x].team == "bandit")
		"machine":
			ids = ed.enemies.filter(func(x): return DBActors.ENEMIES[x].rig in ["robot", "automaton", "humanoid"] and DBActors.ENEMIES[x].team != "bandit")
		"chrono":
			ids = ed.night_enemies
	if ids.is_empty():
		ids = ed.enemies
	ids = world.spawner.suitable(ids)
	pos.y = world.ground_height(pos)
	var m = world.spawner.spawn_enemy(ids[randi() % ids.size()], pos, world.spawner.level_near_player(0))
	if m:
		m.set_meta("ev2", e.uid)
		e.foes.append(m)
	return m

func _prop(e: Dictionary, kind: String, pos: Vector3, face: Vector3 = Vector3.FORWARD) -> Node3D:
	var n := EventProps.build(kind, Profile.current_era)
	world.fx_root.add_child(n)
	pos.y = world.ground_height(pos)
	n.global_position = pos
	if face.length() > 0.01:
		n.look_at(pos + Vector3(face.x, 0, face.z), Vector3.UP)
	e.nodes.append(n)
	stats.temp_nodes += 1
	return n

func _obj(e: Dictionary, label: String, pos: Vector3, cb: Callable, kind := "clue") -> Node3D:
	var o := EventObject.new()
	o.label = label
	o.kind = kind
	o.on_use = cb
	world.fx_root.add_child(o)
	pos.y = world.ground_height(pos)
	o.global_position = pos
	e.nodes.append(o)
	stats.temp_nodes += 1
	return o

func _ring(c: Vector3, r: float, i: int, n: int) -> Vector3:
	var a := TAU * i / maxf(1.0, n)
	return c + Vector3(cos(a), 0, sin(a)) * r

func _folk(e: Dictionary, n: int, exclude_work := true) -> Array:
	var out: Array = []
	for a in world.settlement_npcs.get(e.sid, []):
		if out.size() >= n:
			break
		if not is_instance_valid(a) or a.is_dead or a.get("role") == "guard":
			continue
		if exclude_work and String(a.get_meta("plan", {}).get("act", "")) in ["trade", "work", "serve"]:
			continue
		out.append(a)
	return out

## Townsfolk gather around a point and watch (CityLife plan override).
func _gather(e: Dictionary, center: Vector3, n: int, act := "watch") -> void:
	var crowd := _folk(e, n)
	e.crowd = crowd
	var i := 0
	for a in crowd:
		var p := _ring(center, 4.0 + (i % 2) * 1.2, i, crowd.size())
		p.y = world.ground_height(p)
		var spot := {"id": "%s:crowd:%d" % [e.uid, i], "kind": "crowd", "pos": p, "face": (center - p).normalized(), "bid": "", "door": Vector3.INF, "by": a.actor_id}
		if CityLife.inst:
			CityLife.inst.release(a)
		a.set_meta("spot_id", spot.id)
		a.set_meta("plan", {"act": act, "until": e.until, "spot_id": spot.id, "spot": spot})
		if a.get("brain"):
			a.brain.think_t = 0.0
		i += 1

func _reward(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var pl = world.player
	var g := int(tpl.get("reward_gold", 0))
	if g > 0:
		Profile.char.gold += g
		Events.notify.emit("+%d золота" % g, Color(1.0, 0.85, 0.3))
	var rid: String = tpl.get("reward", "")
	if rid != "" and ItemDB.has_base(rid):
		var it := ItemDB.create(rid, 0, pl.level)
		pl.data.inv.add(it)
		Events.notify.emit("Получено: %s" % ItemDB.base(rid).get("name", rid), Color(0.7, 1.0, 0.7))

func _talk(n, text: String, options: Array = []) -> void:
	world.ui.open("dialog", {"title": n.display_name, "text": text, "options": options if not options.is_empty() else [{"text": "Хорошо", "cb": func(): pass}]})

## Called by Dialogs when the hero talks to an event participant.
func talk_to(n) -> bool:
	for e in active:
		if n in e.npcs or n in e.get("crowd", []):
			var fn := "_talk_" + String(e.tpl.arch)
			if has_method(fn) and n in e.npcs:
				call(fn, e, n)
				return true
	return false

func _say(a, txt: String) -> void:
	if is_instance_valid(a):
		VFX.text(a.global_position + Vector3(0, 2.4, 0), txt, Color(1.0, 0.92, 0.6), 0.9)

# ================================================================ archetypes
# ---- gathering: festival, wedding, service, lecture, premiere, demonstration
func _start_gathering(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var c: Vector3 = e.pos
	var i := 0
	for k in tpl.get("props", []):
		_prop(e, k, _ring(c, 7.0, i, maxi(1, tpl.props.size())), (c - _ring(c, 7.0, i, maxi(1, tpl.props.size()))))
		i += 1
	var host = _npc(e, tpl.get("npc", ""), c, "villager", true) if tpl.has("npc") else null
	if host:
		e.data.host = host
	_gather(e, c, int(tpl.get("crowd", 6)), "watch")
	if tpl.has("stock") and CityEconomy.inst:
		CityEconomy.inst.deliver(e.sid, tpl.stock, 15.0, tpl.name)
	e.objective = "Побывать на событии" + (" и поговорить с «%s»" % tpl.npc if tpl.has("npc") else "")

func _tick_gathering(e: Dictionary) -> void:
	var host = e.data.get("host")
	if host != null and is_instance_valid(host) and host.act.is_empty():
		host.start_action("work", 1.6, 0.5, {"anim": "play" if e.tpl.get("music", false) or "бард" in String(e.tpl.get("npc", "")).to_lower() else "talk"})
	for a in e.get("crowd", []):
		if is_instance_valid(a) and randf() < 0.15 and a.act.is_empty():
			a.start_action("work", 1.0, 0.5, {"anim": "cheer" if randf() < 0.4 else "talk"})
	if world.player.global_position.distance_to(e.pos) < 14.0:
		e.data.visited = true

func _timeout_gathering(e: Dictionary) -> void:
	finish(e, "прошло при %d гостях" % e.get("crowd", []).size() + (", герой был среди гостей" if e.data.get("visited", false) else ""), true)

func _talk_gathering(e: Dictionary, n) -> void:
	var tpl: Dictionary = e.tpl
	var opts: Array = []
	if tpl.get("reveal", false) and not e.data.get("revealed", false):
		opts.append({"text": "Расспросить", "cb": func(): _reveal_place(e)})
	if tpl.get("vote", false) and not e.data.get("voted", false):
		opts.append({"text": "Голосовать «за»", "cb": func(): e.data.voted = true; finish(e, "решение принято голосом героя", true)})
		opts.append({"text": "Голосовать «против»", "cb": func(): e.data.voted = true; finish(e, "решение отклонено", false)})
	if tpl.get("donation", false) and not e.data.get("donated", false):
		opts.append({"text": "Пожертвовать 20 золота", "cb": func(): _donate(e)})
	if tpl.has("reward") and not e.data.get("gift", false):
		opts.append({"text": "Поздравить", "cb": func(): e.data.gift = true; _reward(e)})
	opts.append({"text": "Уйти", "cb": func(): pass})
	_talk(n, "«%s»" % tpl.desc, opts)

func _reveal_place(e: Dictionary) -> void:
	e.data.revealed = true
	var disc = world.sys("discovery")
	var best = null
	var bd := INF
	for p in world.gen.pois:
		if disc and disc.is_discovered(p.id):
			continue
		var d := Vector2(p.pos.x - e.pos.x, p.pos.y - e.pos.z).length()
		if d < bd:
			bd = d
			best = p
	if best != null and disc and disc.has_method("_mark"):
		disc._mark(best.id)
		Events.notify.emit("Рассказ раскрыл место: %s" % best.get("name", best.type), Color(0.6, 0.85, 1.0))
		e.data.revealed_id = best.id

func _donate(e: Dictionary) -> void:
	if Profile.char.gold < 20:
		Events.notify.emit("Не хватает золота", Color(1, 0.5, 0.4))
		return
	Profile.char.gold -= 20
	e.data.donated = true
	var crowd: Array = e.get("crowd", [])
	if not crowd.is_empty() and is_instance_valid(crowd[0]):
		Chronicle.record("help", [world.player, crowd[0]], {"pos_v3": e.pos, "text": "%s пожертвовал(а) фонду помощи — %s получил(а) поддержку." % [Profile.char.name, crowd[0].display_name]})

# ---- merchant: caravan, ship, train, fair, auction, black market
func _start_merchant(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var c: Vector3 = e.pos
	var props: Array = tpl.get("props", ["stall"])
	for i in props.size():
		_prop(e, props[i], c + Vector3(-4.0 + i * 2.8, 0, -3.0), Vector3(0, 0, 1))
	var mlist: Array = []
	for i in int(tpl.get("merchants", 1)):
		var m = _npc(e, tpl.get("npc", "Купец"), c + Vector3(-2.0 + i * 3.0, 0, -1.5), "trader", true)
		if m:
			m.set_meta("ev2_stock", tpl.get("stock", "goods"))
			mlist.append(m)
	e.data.merchants = mlist
	var porters: Array = []
	for i in int(tpl.get("porters", 0)):
		var p = _npc(e, "Носильщик", c + Vector3(6.0, 0, i * 1.5), "villager", true)
		if p:
			porters.append(p)
	e.porters = porters
	for i in int(tpl.get("visitors", 0)):
		var v = _npc(e, "Путешественник", c + Vector3(-6.0, 0, i * 1.2), "villager", true)
		if v:
			v.set_meta("walk_to", c + Vector3(randf_range(-10, 10), 0, randf_range(4, 10)))
	_gather(e, c, int(tpl.get("crowd", 3)), "shop")
	if CityEconomy.inst:
		for k in tpl.get("econ", {}):
			if float(tpl.econ[k]) > 0.0:
				CityEconomy.inst.deliver(e.sid, k, float(tpl.econ[k]) * 0.5, tpl.name)
	e.objective = "Заглянуть к приезжим торговцам"

func _tick_merchant(e: Dictionary) -> void:
	var c: Vector3 = e.pos
	for p in e.get("porters", []):
		if is_instance_valid(p) and not p.has_meta("walk_to"):
			var to_cart: bool = p.get_meta("leg", 0) == 0
			p.set_meta("leg", 1 if to_cart else 0)
			p.set_meta("walk_to", c + (Vector3(6.0, 0, 0) if to_cart else Vector3(-3.0, 0, -2.6)))
			if not to_cart:
				p.start_action("work", 0.6, 0.4, {"anim": "interact"})
	for m in e.data.get("merchants", []):
		if is_instance_valid(m) and m.act.is_empty() and randf() < 0.3:
			m.start_action("work", 0.5, 0.3, {"anim": "interact"})
			if CityLife.inst:
				CityLife.inst.stats.trades += 1

func _timeout_merchant(e: Dictionary) -> void:
	finish(e, "торговцы распродали товар и уехали", true)

func _talk_merchant(e: Dictionary, n) -> void:
	if n in e.data.get("merchants", []):
		_open_special_trade(e, n)
	else:
		_talk(n, "«Тяжёлые ящики! Купцы на площади, загляни к ним»")

func _open_special_trade(e: Dictionary, n) -> void:
	var lvl: int = world.player.level
	var cat: String = n.get_meta("ev2_stock", "goods")
	var items: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(e.uid)
	var extra := 0.25 if cat == "luxury" else 0.08
	for i in 6:
		items.append(ItemDB.random_for_era(Profile.current_era, lvl, "chest", extra, rng))
	for b in ItemCatalog.special_stock(Profile.current_era, cat):
		if ItemDB.has_base(b):
			items.append(ItemDB.create(b, 0, lvl))
	var mult: float = 1.15 if e.tpl.get("shady", false) else 1.0
	world.ui.open("trade", {"title": "%s (событие)" % n.display_name, "items": items, "price_mult": mult, "sell": true, "sell_mult": 0.4,
		"buy_cb": func(it): return world.factions.buy(it, mult)})

# ---- shortage: iron, herbs, mill, boiler, robots
func _start_shortage(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var cut: Array = tpl.get("cut", ["goods", 1.0, 20])
	if CityEconomy.inst:
		CityEconomy.inst.cut_supply(e.sid, cut[0], float(cut[1]), float(cut[2]), tpl.name)
	var giver = _npc(e, tpl.get("npc", "Мастер"), e.pos, "villager", false)
	e.data.giver = giver
	var fid: String = tpl.get("fetch", "")
	if not ItemDB.has_base(fid):
		fid = "potion_hp"
	e.data.fetch = fid
	e.data.fetch_n = int(tpl.get("fetch_n", 2))
	e.objective = "Принести %d × %s (%s)" % [e.data.fetch_n, ItemDB.base(fid).get("name", fid), tpl.get("npc", "")]

func _talk_shortage(e: Dictionary, n) -> void:
	var have: int = world.player.data.inv.count(e.data.fetch)
	var need: int = e.data.fetch_n
	if have >= need:
		_talk(n, "«Ты принёс то, что нужно!»", [{"text": "Отдать %d шт." % need, "cb": func():
			world.player.data.inv.consume(e.data.fetch, need)
			var cut: Array = e.tpl.get("cut", ["goods", 1.0, 20])
			if CityEconomy.inst:
				CityEconomy.inst.deliver(e.sid, cut[0], float(cut[2]) * 1.5, "доставка героя")
			Profile.char.gold += 20 + 10 * need
			e.actors_rec = [world.player]
			finish(e, "поставка доставлена героем — цены вернулись", true)}, {"text": "Позже", "cb": func(): pass}])
	else:
		_talk(n, "«Нужно %d × %s, а у тебя %d. Можно купить, найти или изготовить»." % [need, ItemDB.base(e.data.fetch).get("name", e.data.fetch), have])

func _timeout_shortage(e: Dictionary) -> void:
	finish(e, "дефицит затянулся — цены остались высокими до новой поставки", false)

# ---- search: dog, pet, apprentice, boat, item, automaton
func _start_search(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var giver = _npc(e, tpl.get("npc", "Житель"), e.pos, "villager", false)
	e.data.giver = giver
	var s: Dictionary = e.town
	var c := Vector3(s.pos.x, 0, s.pos.y)
	var a := randf() * TAU
	var tp: Vector3 = c + Vector3(cos(a), 0, sin(a)) * (float(s.radius) + randf_range(25.0, 55.0))
	tp.y = world.ground_height(tp)
	var kind: String = tpl.get("target", "item")
	var lbl: String = {"dog": "Подозвать пса", "pet": "Поймать питомца", "person": "Позвать пропавшего", "boat": "Осмотреть лодку", "item": "Подобрать находку", "machine": "Отключить автоматон"}.get(kind, "Осмотреть")
	_obj(e, lbl, tp, func(_p): _found(e), kind)
	# a trail of marks from town toward the target
	var from: Vector3 = c + (tp - c).normalized() * float(s.radius) * 0.6
	for i in 6:
		var q: Vector3 = from.lerp(tp, float(i) / 6.0)
		VFX.decal(Vector3(q.x, world.ground_height(q), q.z), "footprint", 0.6, float(e.tpl.dur) * 30.0, atan2(tp.x - from.x, tp.z - from.z))
	e.data.target_pos = tp
	e.objective = "Найти пропажу за городом (следы ведут от окраины)"

func _found(e: Dictionary) -> void:
	if e.data.get("found", false):
		return
	e.data.found = true
	e.objective = "Вернуться к «%s»" % e.tpl.get("npc", "")
	Events.notify.emit("Нашлось! Вернитесь к тому, кто просил о помощи.", Color(0.7, 1.0, 0.7))

func _talk_search(e: Dictionary, n) -> void:
	if e.data.get("found", false):
		_reward(e)
		e.actors_rec = [world.player]
		finish(e, "пропажа найдена и возвращена", true)
	else:
		_talk(n, "«Пожалуйста, помоги! Следы ведут за город»")

func _timeout_search(e: Dictionary) -> void:
	finish(e, "поиски прекратились", false)

# ---- investigation: clues in order or any order, then the culprit
func _start_investigation(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var n := int(tpl.get("clues", 3))
	if tpl.has("npc"):
		e.data.giver = _npc(e, tpl.npc, e.pos, "villager", false)
	e.data.found = 0
	e.data.need = n
	for i in n:
		var p: Vector3 = _ring(e.pos, randf_range(9.0, 18.0), i, n)
		var idx := i
		_obj(e, "Улика %d" % (i + 1) if not tpl.get("order", false) else "Знак %d" % (i + 1), p, func(_pl): _clue(e, idx), "clue")
	e.objective = "Найти %d улик(и) вокруг" % n + (" по порядку" if tpl.get("order", false) else "")

func _clue(e: Dictionary, idx: int) -> void:
	if e.state != "running":
		return
	if e.tpl.get("order", false) and idx != int(e.data.found):
		Events.notify.emit("Не тот знак — порядок нарушен, начните с первого", Color(1.0, 0.6, 0.4))
		e.data.found = 0
		return
	if e.data.has("got_%d" % idx):
		return
	e.data["got_%d" % idx] = true
	e.data.found = int(e.data.found) + 1
	Events.notify.emit("Улика %d / %d" % [e.data.found, e.data.need], Color(0.6, 0.85, 1.0))
	if int(e.data.found) >= int(e.data.need):
		var culprit: String = e.tpl.get("culprit", "")
		if culprit != "":
			var cp = _npc(e, culprit, e.pos + Vector3(3, 0, 3), "villager", true)
			_say(cp, "Ладно, ладно… это был я.")
			var g = _nearest_guard(e.pos)
			if g:
				g.brain.investigate(e.pos, 6.0)
		_reward(e)
		e.actors_rec = [world.player]
		finish(e, "загадка раскрыта" + ((": виновен %s" % culprit) if culprit != "" else ""), true)

func _nearest_guard(p: Vector3):
	for a in Game.actors_near(p, 45.0):
		if not a.is_dead and a.get("role") == "guard" and a.get("brain") != null:
			return a
	return null

func _timeout_investigation(e: Dictionary) -> void:
	finish(e, "следы остыли — дело закрыто без ответа", false)

func _talk_investigation(e: Dictionary, n) -> void:
	_talk(n, "«Найдено улик: %d из %d. Ищи вокруг»" % [e.data.found, e.data.need])

# ---- dispute: argued out loud, settled by the hero or the guard, never a fight
func _start_dispute(e: Dictionary) -> void:
	var a = _npc(e, e.tpl.get("npc", "Спорщик"), e.pos + Vector3(-0.9, 0, 0), "villager", true)
	var b = _npc(e, e.tpl.get("npc", "Спорщик"), e.pos + Vector3(0.9, 0, 0), "villager", true)
	e.data.a = a
	e.data.b = b
	if a and b:
		a.face_dir(Vector3.RIGHT)
		b.face_dir(Vector3.LEFT)
	e.objective = "Рассудить спор (поговорить с любым из них)"

func _tick_dispute(e: Dictionary) -> void:
	for x in [e.data.get("a"), e.data.get("b")]:
		if x != null and is_instance_valid(x) and x.act.is_empty():
			x.start_action("work", 1.2, 0.5, {"anim": "talk"})
			if randf() < 0.4:
				_say(x, ["Это моё по праву!", "Ты ошибаешься!", "Пусть рассудят!", "Я не уступлю!"][randi() % 4])

func _talk_dispute(e: Dictionary, n) -> void:
	_talk(n, "«%s» Чью сторону ты примешь?" % e.tpl.desc, [
		{"text": "Поддержать первого", "cb": func(): finish(e, "спор решён в пользу первого", true)},
		{"text": "Поддержать второго", "cb": func(): finish(e, "спор решён в пользу второго", true)},
		{"text": "Предложить компромисс", "cb": func(): e.actors_rec = [world.player]; finish(e, "стороны пришли к компромиссу благодаря герою", true)}])

func _timeout_dispute(e: Dictionary) -> void:
	var g = _nearest_guard(e.pos)
	if g:
		_say(g, "Разойдитесь! Суд решит.")
	finish(e, "спор разобрала стража — без драки", true)

# ---- competition: sparring with rules; nobody dies
func _start_competition(e: Dictionary) -> void:
	_prop(e, "ring", e.pos)
	for k in e.tpl.get("props", []):
		if k != "ring":
			_prop(e, k, e.pos + Vector3(6, 0, 0))
	var a = _npc(e, e.tpl.get("npc", "Боец"), e.pos + Vector3(-2.0, 0, 0), "villager", true)
	var b = _npc(e, e.tpl.get("npc", "Боец"), e.pos + Vector3(2.0, 0, 0), "villager", true)
	e.data.a = a
	e.data.b = b
	for x in [a, b]:
		if x:
			x.set_meta("spar", e.uid)
			x.max_hp *= 2.0
			x.hp = x.max_hp
	_gather(e, e.pos, int(e.tpl.get("crowd", 6)), "watch")
	e.data.bouts = 0
	e.objective = "Посмотреть состязание (можно поговорить с участником)"

func _tick_competition(e: Dictionary) -> void:
	var a = e.data.get("a")
	var b = e.data.get("b")
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return
	for pair in [[a, b], [b, a]]:
		var x = pair[0]
		var y = pair[1]
		var to: Vector3 = y.global_position - x.global_position
		to.y = 0
		x.face_dir(to.normalized())
		if to.length() > 1.8:
			x.set_meta("walk_to", y.global_position)
		elif x.act.is_empty() and randf() < 0.5:
			x.start_action("melee", 0.55, 0.45, {"anim": ["slash", "thrust", "overhead"][randi() % 3], "mult": 0.4})
	for c in e.get("crowd", []):
		if is_instance_valid(c) and c.act.is_empty() and randf() < 0.3:
			c.start_action("work", 1.0, 0.5, {"anim": "cheer"})
	if a.hp <= a.max_hp * 0.35 or b.hp <= b.max_hp * 0.35:
		var w = a if a.hp > b.hp else b
		_say(w, "Победа!")
		e.actors_rec = [w]
		finish(e, "победил %s" % w.display_name, true)

func _timeout_competition(e: Dictionary) -> void:
	finish(e, "ничья по решению судей", true)

func _talk_competition(e: Dictionary, n) -> void:
	_talk(n, "«Бой до первого серьёзного удара, по правилам. Никто не умирает»")

# ---- hazard: leaks, floods, smog, anomalies; workers and valves
func _start_hazard(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var zk: String = tpl.get("zone", "none")
	if zk != "none":
		var z := Zone.create("ev_" + zk, null, e.pos, 4.5, float(tpl.dur) * 30.0 + 60.0, {"amount": 2.0 + Profile.current_era, "dtype": "fire" if zk == "steam" else "dark"}, {"no_res": true, "everyone": true})
		if z:
			z.tick = 1.0
			e.nodes.append(z)
			e.data.zone = z
	if tpl.get("weather", "") != "" and world.weather:
		world.weather.set_weather(tpl.weather, float(tpl.dur) * 30.0)
	var w = _npc(e, tpl.get("npc", "Рабочий"), e.pos + Vector3(5.5, 0, 0), "villager", true)
	e.data.worker = w
	var n := int(tpl.get("fix", 1))
	e.data.fixed = 0
	e.data.need = n
	for i in n:
		var idx := i
		_obj(e, "Устранить неисправность", _ring(e.pos, 6.5, i, maxi(1, n)), func(_pl): _fix(e, idx), "valve")
	_prop(e, "sign", e.pos + Vector3(-6.5, 0, 0))
	e.objective = ("Помочь устранить аварию (%d точки)" % n) if n > 0 else "Переждать или обойти опасную зону"
	if CityPeace.inst and tpl.cat == "danger":
		var c = CityPeace.inst.city_at(e.pos)
		if c:
			CityPeace.inst._set_state(c, "tense", tpl.name)

func _fix(e: Dictionary, idx: int) -> void:
	if e.data.has("fix_%d" % idx) or e.state != "running":
		return
	e.data["fix_%d" % idx] = true
	e.data.fixed = int(e.data.fixed) + 1
	Events.notify.emit("Устранено: %d / %d" % [e.data.fixed, e.data.need], Color(0.7, 1.0, 0.7))
	if int(e.data.fixed) >= int(e.data.need):
		Profile.char.gold += 15 * int(e.data.need)
		e.actors_rec = [world.player]
		finish(e, "авария устранена с помощью героя", true)

func _tick_hazard(e: Dictionary) -> void:
	var w = e.data.get("worker")
	if w != null and is_instance_valid(w) and w.act.is_empty():
		w.start_action("work", 0.7, 0.4, {"anim": "overhead"})

func _timeout_hazard(e: Dictionary) -> void:
	finish(e, "рабочие сами справились к концу смены", int(e.tpl.get("fix", 0)) == 0)

# ---- mystery: shrine, compass, find, forecast → lore, reward, maybe a rift
func _start_mystery(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	if tpl.has("npc"):
		e.data.giver = _npc(e, tpl.npc, e.pos + Vector3(2.5, 0, 0), "villager", true)
	_obj(e, "Исследовать", e.pos, func(_pl): _mystery_use(e), "monolith")
	e.objective = "Исследовать странное место"

func _mystery_use(e: Dictionary) -> void:
	if e.state != "running":
		return
	_reward(e)
	if randf() < float(e.tpl.get("rift_chance", 0.0)):
		var p: Vector3 = e.pos + Vector3(5, 0, 0)
		var portal := Poi.create({"id": e.uid, "type": "rift", "pos": Vector2(p.x, p.z), "name": "Пробудившийся разлом", "data": {"temporary": true}}, world)
		world.poi_root.add_child(portal)
		portal.global_position = p
		e.data.rift = portal
		get_tree().create_timer(300.0, false).timeout.connect(func():
			if is_instance_valid(portal) and world.dimension == "":
				portal.queue_free())
		e.actors_rec = [world.player]
		finish(e, "тайна раскрыта: открылся разлом", true)
	else:
		e.actors_rec = [world.player]
		finish(e, "тайна раскрыта", true)

func _timeout_mystery(e: Dictionary) -> void:
	finish(e, "место снова затихло", false)

# ---- raid: rare attack with a concrete target (through CityPeace)
func _start_raid(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var s: Dictionary = e.town
	var c := Vector3(s.pos.x, float(s.height), s.pos.y)
	if CityPeace.inst:
		CityPeace.inst.begin_attack(e.sid, tpl.name)
	var a := randf() * TAU
	var from: Vector3 = c + Vector3(cos(a), 0, sin(a)) * (float(s.radius) + 22.0)
	var target: Vector3 = e.pos
	for i in int(tpl.get("count", 4)):
		var m = _foe(e, tpl.get("foe", "bandit"), from + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
		if m and m.get("brain"):
			m.brain.goal = "travel"
			m.brain.dest = target
			m.brain.path = [target]
	e.data.target = target
	Events.banner.emit(tpl.name, "%s! Цель — %s." % [tpl.desc, {"warehouse": "склады", "shop": "лавки", "smithy": "мастерские", "square": "площадь"}.get(String(tpl.where), "город")], Color(1.0, 0.45, 0.35))
	e.objective = "Отбить нападение"

func _tick_raid(e: Dictionary) -> void:
	var alive := 0
	for m in e.foes:
		if is_instance_valid(m) and not m.is_dead:
			alive += 1
			if m.get("brain") and m.brain.goal in ["idle", "wander", "explore"]:
				m.brain.goal = "travel"
				m.brain.dest = e.data.target
				m.brain.path = [e.data.target]
	if alive == 0:
		if CityPeace.inst:
			CityPeace.inst.end_attack(e.sid, "нападение отбито")
		Profile.char.fame += 5.0
		finish(e, "нападение отбито", true)

func _timeout_raid(e: Dictionary) -> void:
	if CityPeace.inst:
		CityPeace.inst.end_attack(e.sid, "нападающие ушли с добычей")
	if CityEconomy.inst:
		CityEconomy.inst.cut_supply(e.sid, "goods", 1.0, 30.0, e.tpl.name)
	finish(e, "нападающие ушли с добычей", false)

# ---- outskirts: wolves, scouts, robbers outside town (or one rogue machine)
func _start_outskirts(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var p: Vector3 = e.pos
	if tpl.get("in_town", false):
		var s: Dictionary = e.town
		p = Vector3(s.pos.x, float(s.height), s.pos.y) + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
	for i in int(tpl.get("count", 2)):
		_foe(e, tpl.get("foe", "bandit"), p + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
	if tpl.has("npc"):
		var s2: Dictionary = e.town
		e.data.giver = _npc(e, tpl.npc, Vector3(s2.pos.x, float(s2.height), s2.pos.y) + Vector3(4, 0, 4), "villager", false)
	e.objective = "Разобраться с угрозой у окраины"

func _tick_outskirts(e: Dictionary) -> void:
	var alive := 0
	for m in e.foes:
		if is_instance_valid(m) and not m.is_dead:
			alive += 1
	if alive == 0:
		Profile.char.gold += 25
		e.actors_rec = [world.player]
		finish(e, "угроза устранена", true)

func _timeout_outskirts(e: Dictionary) -> void:
	finish(e, "угроза ушла сама", false)

func _talk_outskirts(e: Dictionary, n) -> void:
	_talk(n, "«%s» Помоги, если сможешь»" % e.tpl.desc)

# ---- visitor: a notable person (a real living legend when required)
func _start_visitor(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	var s: Dictionary = e.town
	var c := Vector3(s.pos.x, float(s.height), s.pos.y)
	var edge: Vector3 = c + (e.pos - c).normalized() * float(s.radius) * 0.9 if e.pos.distance_to(c) > 1.0 else c + Vector3(float(s.radius) * 0.9, 0, 0)
	if tpl.get("legend", false):
		var rec = _pick_legend()
		if rec != null:
			var n = world.spawner.spawn_bot(rec, edge)
			if n:
				n.brain = null
				n.set_meta("ev2", e.uid)
				n.set_meta("leaves", true)
				n.set_meta("walk_to", e.pos)
				e.npcs.append(n)
				e.data.legend = rec.id
				e.actors_rec = [rec.id]
				Chronicle.record("legend_visit", [rec.id], {"pos_v3": e.pos, "place": s.get("name", ""), "names": {rec.id: rec.name},
					"text": "%s «%s» прибыл(а) в %s." % [rec.name, rec.get("title", ""), s.get("name", "город")]})
	else:
		var v = _npc(e, tpl.get("npc", "Гость"), edge, "villager", true)
		if v:
			v.set_meta("walk_to", e.pos)
		for i in int(tpl.get("visitors", 0)) - 1:
			var w = _npc(e, tpl.get("npc", "Гость"), edge + Vector3(i, 0, 1.2), "villager", true)
			if w:
				w.set_meta("walk_to", e.pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
	if tpl.get("medic", false):
		e.data.medic = true
	_gather(e, e.pos, 3, "watch")
	e.objective = "Встретить гостя"

func _pick_legend():
	var best = null
	for r in world.legends.records():
		if r.get("legend", false) and r.get("alive", true) and not world.sim.active.has(r.id):
			best = r
			break
	return best

func _tick_visitor(e: Dictionary) -> void:
	if e.data.get("medic", false):
		for a in Game.actors_near(e.pos, 10.0):
			if not a.is_dead and a.get("role") in ["villager", "trader", "guard"] and a.hp < a.max_hp:
				a.heal(a.max_hp * 0.1)

func _talk_visitor(e: Dictionary, n) -> void:
	if e.data.has("legend"):
		var r: Dictionary = world.legends.record(e.data.legend)
		var bio: Dictionary = world.legends.biography(r)
		_talk(n, "«%s»\n\n%s" % [bio.get("backstory", ""), "\n".join(bio.get("chronicle", []).slice(-3))])
	elif e.data.get("medic", false):
		_talk(n, "«Я лечу всех, кому нужна помощь»", [{"text": "Попросить помощи", "cb": func():
			world.player.heal(world.player.max_hp)
			if world.has_method("sys") and world.sys("hardcore") and world.sys("hardcore").has_method("treat_all"):
				world.sys("hardcore").treat_all("doctor")}, {"text": "Уйти", "cb": func(): pass}])
	else:
		if e.tpl.has("reward_gold") and not e.data.get("paid", false):
			e.data.paid = true
			_reward(e)
		_talk(n, "«%s»" % e.tpl.desc)

func _timeout_visitor(e: Dictionary) -> void:
	finish(e, "гость отправился дальше", true)

# ---- outage: lights go out; generators to fix
func _start_outage(e: Dictionary) -> void:
	var s: Dictionary = e.town
	var c := Vector3(s.pos.x, float(s.height), s.pos.y)
	var lights: Array = []
	for l in get_tree().get_nodes_in_group("street_light") + world.terrain.find_children("*", "OmniLight3D", true, false):
		if is_instance_valid(l) and l.global_position.distance_to(c) < float(s.radius) + 10.0:
			lights.append([l, l.light_energy])
			l.light_energy = 0.0
	e.data.lights = lights
	var n := int(e.tpl.get("fix", 1))
	e.data.fixed = 0
	e.data.need = n
	for i in n:
		var idx := i
		_obj(e, "Восстановить питание", _ring(c, float(s.radius) * 0.5, i, maxi(1, n)), func(_pl): _fix(e, idx), "generator")
	if e.tpl.has("npc"):
		e.data.worker = _npc(e, e.tpl.npc, e.pos, "villager", true)
	if e.tpl.has("culprit"):
		var cu = _npc(e, e.tpl.culprit, c + Vector3(float(s.radius) * 0.7, 0, 0), "villager", true)
		if cu:
			cu.set_meta("walk_to", c + Vector3(float(s.radius) * 1.5, 0, 0))
	e.objective = "Восстановить питание (%d узла)" % n

func _timeout_outage(e: Dictionary) -> void:
	finish(e, "питание восстановили сами техники", false)

# ---- spectacle: fireworks, airship, holograms, bloom, inventions
func _start_spectacle(e: Dictionary) -> void:
	var node := EventProps.spectacle(String(e.tpl.get("fx", "sparks")), Profile.current_era)
	world.fx_root.add_child(node)
	node.global_position = e.pos
	e.nodes.append(node)
	if e.tpl.has("npc"):
		e.data.host = _npc(e, e.tpl.npc, e.pos + Vector3(0, 0, -2.5), "villager", true)
	_gather(e, e.pos, int(e.tpl.get("crowd", 6)), "watch")
	e.objective = "Посмотреть зрелище"

func _tick_spectacle(e: Dictionary) -> void:
	for c in e.get("crowd", []):
		if is_instance_valid(c) and c.act.is_empty() and randf() < 0.25:
			c.start_action("work", 1.0, 0.5, {"anim": "cheer"})

# ---- price shift: sales, tolls, fog, metro, contracts
func _start_price_shift(e: Dictionary) -> void:
	var tpl: Dictionary = e.tpl
	if CityEconomy.inst:
		for c in tpl.get("econ", {}):
			var v: float = tpl.econ[c]
			if v >= 0.0:
				CityEconomy.inst.deliver(e.sid, c, v, tpl.name)
			else:
				CityEconomy.inst.cut_supply(e.sid, c, float(tpl.dur) / 24.0, -v, tpl.name)
	if tpl.get("weather", "") != "" and world.weather:
		world.weather.set_weather(tpl.weather, float(tpl.dur) * 30.0)
	_prop(e, "sign", e.pos)
	e.objective = "Цены в городе изменились (см. торговцев)"

func _timeout_price_shift(e: Dictionary) -> void:
	finish(e, "цены вернулись к обычным", false)

# ---- echo: a real chronicle echo or an authored one
func _start_echo(e: Dictionary) -> void:
	var ec = world.sys("echoes")
	if ec == null:
		finish(e, "отголосок не проявился", false)
		return
	var cand: Dictionary = ec.pick(world.player.global_position)
	if cand.is_empty():
		# no real chronicle moment nearby: show the era's authored episode here
		for ep in HistoricalEchoes.AUTHORED:
			if int(ep.era) == Profile.current_era:
				cand = {"authored": ep, "pos": Vector2(e.pos.x, e.pos.z)}
				break
	if not cand.is_empty():
		ec.play(cand)      # the echo frees itself after a few seconds
		finish(e, "на улице мелькнул отголосок прошлого", true)
	else:
		finish(e, "отголосок не проявился", false)
