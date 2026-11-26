class_name RoadEncounters
extends Node
## Road Encounter Director: real situations along the road network ahead of
## the player (ambushes, wounded travellers, traders, duels, rituals, tracks to
## lairs, fugitives, messengers…). Each encounter spawns real NPCs/props,
## offers real actions (dialog options / interactables), gives rewards,
## reputation, Chronicle entries or quests, and cleans up afterwards.
## Also keeps a few ambient travellers/traders/patrols walking along roads.

const MAX_ACTIVE := 2
const TEMPLATES := {
	"looted_caravan": {"name": "Разграбленный караван", "w": 1.0},
	"ambush": {"name": "Засада разбойников", "w": 1.2},
	"wounded_traveler": {"name": "Раненый путник", "w": 1.0},
	"suspicious_trader": {"name": "Подозрительный торговец", "w": 0.8},
	"wandering_smith": {"name": "Бродячий кузнец", "w": 0.7},
	"npc_fight": {"name": "Схватка на дороге", "w": 0.9},
	"duel": {"name": "Дуэль у дороги", "w": 0.7},
	"abandoned_cart": {"name": "Брошенная повозка", "w": 1.0},
	"lost_mage": {"name": "Заблудившийся маг", "w": 0.7},
	"ritual": {"name": "Ритуал у дороги", "w": 0.6, "night": 2.0},
	"monster_tracks": {"name": "Следы чудовища", "w": 0.8},
	"rich_caravan": {"name": "Богатый караван", "w": 0.6},
	"mercy_bandit": {"name": "Разбойник просит пощады", "w": 0.7},
	"cursed_chest": {"name": "Зловещий сундук", "w": 0.6},
	"mimic_chest": {"name": "Сундук у обочины", "w": 0.6},
	"campfire_stranger": {"name": "Незнакомец у костра", "w": 0.9, "night": 1.6},
	"broken_bridge": {"name": "Перекрытая дорога", "w": 0.6},
	"relic_hunters": {"name": "Охотники за реликвиями", "w": 0.6},
	"fugitive": {"name": "Беглец", "w": 0.7},
	"temporal_trail": {"name": "Временной след", "w": 0.6},
	"beast_attack": {"name": "Нападение зверей", "w": 0.9},
	"lost_relic": {"name": "Потерянная реликвия", "w": 0.5},
	"wandering_champion": {"name": "Бродячий чемпион", "w": 0.5},
	"dying_messenger": {"name": "Умирающий гонец", "w": 0.6},
	"battle_aftermath": {"name": "Следы недавней битвы", "w": 0.7},
}
const CART := ["телега", "фургон", "паровой фургон", "грузовик", "транспортник"]
const TRAVELER := ["путник", "странник", "путешественник", "водитель", "колонист"]
const MAGE := ["маг", "алхимик", "инженер-теслианец", "исследователь аномалий", "хронист"]
const CULT := ["культисты", "алхимики-еретики", "оккультисты", "сектанты", "хроно-культисты"]
const MESSENGER := ["гонец", "курьер", "телеграфист", "связной", "курьер Колоний"]
const RANGED := ["bow_short", "musket", "rifle_lever", "carbine", "pulse_rifle"]

var world
var active: Array = []
var travelers: Array = []
var state := {}
var _t := 0.0
var _check_t := 8.0
var _amb_t := 0.0
var _last_start := -999.0
var _graph := {}          # fallback road graph: key -> {p: Vector2, n: [keys]}

func setup(w) -> void:
	world = w
	state = Game.world_state.get("road", {})
	if not state.has("count"):
		state["count"] = {}
	if not state.has("cool"):
		state["cool"] = {}
	Game.world_state["road"] = state
	_build_graph()

# ================================================================ helpers
func era() -> int:
	return Profile.current_era

func player():
	return world.player if world and is_instance_valid(world.player) else null

func ground(p: Vector3) -> Vector3:
	p.y = world.ground_height(p)
	return p

func _key(p: Vector2) -> String:
	return "%d,%d" % [roundi(p.x), roundi(p.y)]

func _build_graph() -> void:
	_graph.clear()
	if world.gen == null:
		return
	for seg in world.gen.roads:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ka := _key(a)
		var kb := _key(b)
		if not _graph.has(ka):
			_graph[ka] = {"p": a, "n": []}
		if not _graph.has(kb):
			_graph[kb] = {"p": b, "n": []}
		if not kb in _graph[ka].n:
			_graph[ka].n.append(kb)
		if not ka in _graph[kb].n:
			_graph[kb].n.append(ka)

func _nearest_node(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for k in _graph:
		var d: float = (_graph[k].p as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = k
	return best

## Road path between two points (uses the generator's road graph if available).
func road_path(from: Vector2, to: Vector2) -> Array:
	if world.gen and world.gen.has_method("road_path"):
		var rp: Array = world.gen.road_path(from, to)
		if not rp.is_empty():
			return rp
	if _graph.is_empty():
		return [from, to]
	var s := _nearest_node(from)
	var g := _nearest_node(to)
	if s == "" or g == "":
		return [from, to]
	# Dijkstra on the small settlement road graph
	var dist := {s: 0.0}
	var prev := {}
	var open: Array = [s]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if dist[open[i]] < dist[open[bi]]:
				bi = i
		var u: String = open[bi]
		open.remove_at(bi)
		if u == g:
			break
		done[u] = true
		for v in _graph[u].n:
			if done.has(v):
				continue
			var nd: float = dist[u] + (_graph[u].p as Vector2).distance_to(_graph[v].p)
			if nd < dist.get(v, INF):
				dist[v] = nd
				prev[v] = u
				if not v in open:
					open.append(v)
	var path: Array = [to]
	var c := g
	var guard := 0
	while c != s and prev.has(c) and guard < 200:
		path.push_front(_graph[c].p)
		c = prev[c]
		guard += 1
	path.push_front(_graph[s].p)
	path.push_front(from)
	return path

## Closest point on any road to p (Vector2, or INF vector when no roads).
func nearest_road_point(p: Vector2) -> Vector2:
	if world.gen and world.gen.has_method("nearest_road_point"):
		return world.gen.nearest_road_point(p)
	var best := Vector2.INF
	var bd := INF
	if world.gen:
		for seg in world.gen.roads:
			var cp := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
			var d := cp.distance_squared_to(p)
			if d < bd:
				bd = d
				best = cp
	return best

## A point on a road 40–90 m ahead of the player (falls back to off-road).
func spot_ahead(min_d: float = 40.0, max_d: float = 90.0) -> Vector3:
	var pl = player()
	if pl == null:
		return Vector3.ZERO
	var pp: Vector3 = pl.global_position
	var fwd: Vector3 = pl.facing
	if pl.velocity.length() > 1.0:
		fwd = Vector3(pl.velocity.x, 0, pl.velocity.z).normalized()
	var p2 := Vector2(pp.x, pp.z)
	var f2 := Vector2(fwd.x, fwd.z)
	var cands: Array = []
	if world.gen:
		for seg in world.gen.roads:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var cp := Geometry2D.get_closest_point_to_segment(p2, a, b)
			if cp.distance_to(p2) > max_d + 40.0:
				continue
			var steps := int(a.distance_to(b) / 10.0) + 1
			for i in steps + 1:
				var q: Vector2 = a.lerp(b, float(i) / steps)
				var d := q.distance_to(p2)
				if d >= min_d and d <= max_d:
					var dot := (q - p2).normalized().dot(f2)
					cands.append([q, dot + randf() * 0.4])
	if not cands.is_empty():
		cands.sort_custom(func(x, y): return x[1] > y[1])
		var pick: Vector2 = cands[randi() % mini(4, cands.size())][0]
		return ground(Vector3(pick.x, 0, pick.y))
	var ang := randf_range(-0.6, 0.6)
	var dir := fwd.rotated(Vector3.UP, ang)
	return ground(pp + dir * randf_range(min_d, max_d))

func _dir_along_road(p: Vector3) -> Vector3:
	var p2 := Vector2(p.x, p.z)
	if world.gen:
		var bd := INF
		var best := Vector2.RIGHT
		for seg in world.gen.roads:
			var cp := Geometry2D.get_closest_point_to_segment(p2, seg[0], seg[1])
			var d := cp.distance_squared_to(p2)
			if d < bd:
				bd = d
				best = ((seg[1] as Vector2) - (seg[0] as Vector2)).normalized()
		return Vector3(best.x, 0, best.y)
	return Vector3.RIGHT

func _side(p: Vector3, dist: float) -> Vector3:
	var d := _dir_along_road(p)
	var s := d.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	return ground(p + s * dist)

func dialog(title: String, text: String, opts: Array, col: Color = Color(0.8, 0.7, 0.5)) -> void:
	if world.ui and world.ui.has_method("open"):
		world.ui.open("dialog", {"title": title, "text": text, "portrait_color": col, "options": opts})

func chron(text: String, actors: Array, pos: Vector3) -> void:
	Chronicle.record("road_event", actors, {"text": text, "pos_v3": pos})

func reward(gold: int, xp: int, table: String = "", note: String = "") -> void:
	var pl = player()
	if pl == null:
		return
	var cur: String = DBEras.era(era()).currency
	if gold > 0:
		pl.data.gold += gold
		Audio.play_sfx("coin", pl.global_position)
	if xp > 0:
		pl.gain_xp(xp)
	var it_name := ""
	if table != "":
		var it := ItemDB.random_for_era(era(), pl.level, table, 0.05)
		if not pl.data.inv.add(it):
			world.loot.spawn_drop(it, pl.global_position + pl.facing)
		it_name = ItemDB.display_name(it)
	var parts: Array = []
	if gold > 0:
		parts.append("+%d %s" % [gold, cur])
	if xp > 0:
		parts.append("+%d опыта" % xp)
	if it_name != "":
		parts.append(it_name)
	Events.notify.emit(("%s: " % note if note != "" else "Награда: ") + ", ".join(parts), Color(1.0, 0.85, 0.4))

func gold_k() -> int:
	return 20 * (era() + 1)

func lvl() -> int:
	return world.spawner.level_near_player(0)

func bandit_ids(ranged_only: bool = false) -> Array:
	var out: Array = []
	for id in DBEras.era(era()).enemies:
		var d: Dictionary = DBActors.ENEMIES[id]
		if d.team == "bandit" and d.rig == "humanoid":
			if not ranged_only or d.ai == "ranged":
				out.append(id)
	if out.is_empty():
		out = DBEras.era(era()).enemies.duplicate()
	return world.spawner.suitable(out) if not ranged_only else out

func beast_ids() -> Array:
	var out: Array = []
	for id in DBEras.era(era()).enemies + DBEras.era(era()).night_enemies:
		var d: Dictionary = DBActors.ENEMIES[id]
		if d.rig != "humanoid" and d.team == "monster" and not id in out:
			out.append(id)
	if out.is_empty():
		out = ["wolf"]
	return out

func caster_ids() -> Array:
	var out: Array = []
	for id in DBEras.era(era()).enemies + DBEras.era(era()).night_enemies:
		if DBActors.ENEMIES[id].ai == "caster" and DBActors.ENEMIES[id].rig == "humanoid":
			out.append(id)
	if out.is_empty():
		out = bandit_ids()
	return out

# ---- spawning
func spawn_enemy(e: Dictionary, id: String, pos: Vector3, lvl_off: int = 0):
	var m = world.spawner.spawn_enemy(id, pos, maxi(1, lvl() + lvl_off))
	if m:
		e.actors.append(m)
	return m

func give_ranged(n) -> void:
	if n == null or n.data == null:
		return
	var w := ItemDB.create(RANGED[clampi(era(), 0, 4)], 0, maxi(1, n.level), null, false)
	n.data.inv.add(w)
	n.data.inv.equip_item(w)
	n.refresh_gear()

func spawn_npc(e: Dictionary, role: String, pos: Vector3, nm: String = "", owner_f: String = ""):
	var n = world.spawner.spawn_villager({"id": "", "owner": owner_f}, pos, role)
	if n == null:
		return null
	if nm != "":
		n.display_name = nm
	n.dialog_kind = ""
	e.actors.append(n)
	return n

func spawn_record_bot(e: Dictionary, nm: String, pos: Vector3, extra: Dictionary = {}):
	var rec: Dictionary = world.legends.new_record(nm, extra)
	rec.pos = [pos.x, pos.z]
	var n = world.spawner.spawn_bot(rec, pos)
	if n:
		world.sim.active[rec.id] = n
		e.actors.append(n)
	return n

func freeze(n, pose: String = "") -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.brain and n.brain.has_method("shutdown"):
		n.brain.shutdown()
	n.brain = null
	n.move_input = Vector3.ZERO
	if n.rig:
		match pose:
			"kneel": n.rig.yielding = true
			"sit": n.rig.crouch = true

func unfreeze(n) -> void:
	if n == null or not is_instance_valid(n) or n.is_dead:
		return
	if n.rig:
		n.rig.yielding = false
		n.rig.crouch = false
	if n.brain == null:
		n.brain = BotBrain.new(n)

## Walk an NPC along road waypoints (brain resumes when in danger or arrived).
func walk(n, to: Vector2) -> void:
	if n == null or not is_instance_valid(n) or n.brain == null:
		return
	var from := Vector2(n.global_position.x, n.global_position.z)
	var pts: Array = road_path(from, to)
	var path3: Array = []
	for p in pts:
		path3.append(Vector3(p.x, 0, p.y))
	n.brain.path = path3
	n.brain.goal = "travel"
	n.brain.think_t = 9999.0
	n.home = Vector3(to.x, 0, to.y)
	n.set_meta("road_walk", true)

func _keep_walking(n) -> void:
	if n == null or not is_instance_valid(n) or n.is_dead or n.brain == null or not n.has_meta("road_walk"):
		return
	var danger := false
	for a in Game.actors_near(n.global_position, 12.0):
		if a != n and not a.is_dead and Game.is_enemy(n, a):
			danger = true
			break
	if danger:
		n.brain.think_t = minf(n.brain.think_t, 0.1)
	elif n.brain.goal == "travel" and not n.brain.path.is_empty():
		n.brain.think_t = 9999.0
	elif n.brain.path.is_empty():
		n.remove_meta("road_walk")

func spot(e: Dictionary, at, label: String, cb: Callable, radius: float = 2.6) -> Spot:
	var s := Spot.new()
	s.label = label
	s.on_interact = cb
	s.interact_radius = radius
	if at is Node3D:
		at.add_child(s)
		s.position = Vector3(0, 0.5, 0)
	else:
		add_child(s)
		s.global_position = at
	e.nodes.append(s)
	return s

func prop(e: Dictionary, kind: String, pos: Vector3, rot: float = 0.0) -> Node3D:
	var n := make_prop(kind, era(), rot)
	add_child(n)
	n.global_position = ground(pos)
	if e.size() > 0:
		e.nodes.append(n)
	return n

func chest_at(e: Dictionary, pos: Vector3, tier: String = "rich", mimic: bool = false) -> Chest:
	var c := Chest.new()
	c.configure("", {"opened": []}, era(), tier, lvl() + 1, 0.0 if mimic else 1.0)
	add_child(c)
	c.global_position = ground(pos)
	e.nodes.append(c)
	return c

func tracking():
	return world.sys("tracking") if world.has_method("sys") else null

# ================================================================ director
func _process(delta: float) -> void:
	if world == null or Game.mode != "world" or world.dimension != "" or player() == null:
		return
	_t += delta
	if _t >= 0.5:
		var dt := _t
		_t = 0.0
		for e in active.duplicate():
			e.t += dt
			_tick(e)
		for n in travelers.duplicate():
			if not is_instance_valid(n) or n.is_dead:
				travelers.erase(n)
			else:
				_keep_walking(n)
				if n.global_position.distance_to(player().global_position) > 140.0:
					travelers.erase(n)
					n.queue_free()
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 6.0
		var in_town: bool = CityPeace.inst != null and CityPeace.inst.city_at(player().global_position, 45.0) != null
		if not in_town and active.size() < MAX_ACTIVE and Game.game_time * 720.0 - _last_start > 30.0:
			if randf() < 0.45:
				var tpl := pick_template()
				if tpl != "":
					force(tpl)
	_amb_t += delta
	if _amb_t > 4.0:
		_amb_t = 0.0
		_ambient_travelers()

func pick_template() -> String:
	var now := Game.game_time
	var total := 0.0
	var pool: Array = []
	var night := Game.is_night()
	var tension := 0.0
	for fid in world.factions.list():
		for o in world.factions.list():
			if world.factions.at_war(fid, o):
				tension += 0.5
	for k in TEMPLATES:
		if float(state.cool.get(k, 0.0)) > now:
			continue
		var w: float = TEMPLATES[k].w
		if night:
			w *= TEMPLATES[k].get("night", 0.8)
		if k in ["npc_fight", "battle_aftermath", "fugitive"]:
			w *= 1.0 + tension * 0.3
		if k == "temporal_trail":
			w *= 1.0 + era() * 0.25
		w /= 1.0 + float(state.count.get(k, 0)) * 0.3   # variety: rarely repeat
		pool.append([k, w])
		total += w
	if pool.is_empty():
		return ""
	var r := randf() * total
	for x in pool:
		r -= x[1]
		if r <= 0.0:
			return x[0]
	return pool[0][0]

## Start a template now (tests can pass an explicit position).
func force(tpl: String, pos = null) -> Dictionary:
	if not TEMPLATES.has(tpl):
		return {}
	var p: Vector3 = pos if pos is Vector3 else spot_ahead()
	var e := {"id": Game.new_uid("re"), "tpl": tpl, "name": TEMPLATES[tpl].name, "pos": ground(p), "t": 0.0, "state": "active",
		"nodes": [], "actors": [], "data": {}, "actions": {}, "result": ""}
	active.append(e)
	_last_start = Game.game_time * 720.0
	state.cool[tpl] = Game.game_time + 0.35
	state.count[tpl] = int(state.count.get(tpl, 0)) + 1
	call("_start_" + tpl, e)
	return e

func finish(e: Dictionary, result: String = "done") -> void:
	if e.state != "active":
		return
	e.state = "done"
	e.result = result

func _tick(e: Dictionary) -> void:
	var pl = player()
	var d: float = pl.global_position.distance_to(e.pos) if pl else 0.0
	if e.state == "active":
		var m = "_tick_" + e.tpl
		if has_method(m):
			call(m, e)
		if d > 170.0 or e.t > 900.0:
			e.state = "expired"
	if e.state != "active" and (d > 70.0 or e.t > 1200.0):
		_cleanup(e)

func _cleanup(e: Dictionary) -> void:
	for n in e.nodes:
		if is_instance_valid(n):
			n.queue_free()
	for a in e.actors:
		if is_instance_valid(a) and a.record.is_empty():
			a.queue_free()
	active.erase(e)

func alive(arr: Array) -> int:
	var c := 0
	for a in arr:
		if is_instance_valid(a) and not a.is_dead:
			c += 1
	return c

func _ambient_travelers() -> void:
	if world.gen == null or world.gen.settlements.size() < 2:
		return
	var pl = player()
	if travelers.size() >= 3 or randf() > 0.5:
		return
	var p := spot_ahead(55.0, 95.0)
	var dest: Dictionary = world.gen.settlements[randi() % world.gen.settlements.size()]
	var roll := randf()
	var n
	if roll < 0.45:
		n = world.spawner.spawn_villager({"id": "", "owner": ""}, p, "trader")
		n.display_name = "Странствующий торговец"
	elif roll < 0.75:
		n = world.spawner.spawn_villager({"id": "", "owner": ""}, p, "villager")
		n.display_name = TRAVELER[era()].capitalize()
		n.dialog_kind = "villager"
	else:
		var fl: Array = world.factions.list()
		var fid: String = fl[randi() % fl.size()]
		n = world.spawner.spawn_soldier(fid, "infantry", p, lvl())
		n.display_name = "Патрульный: " + n.display_name
		n.squad = {}
		var cross := p
		if world.gen.has_method("crossroads") or world.gen.get("crossroads") != null:
			var cr = world.gen.get("crossroads")
			if cr is Array and not cr.is_empty():
				var best: Vector2 = cr[0]
				for c in cr:
					if (c as Vector2).distance_to(Vector2(p.x, p.z)) < best.distance_to(Vector2(p.x, p.z)):
						best = c
				cross = Vector3(best.x, 0, best.y)
		n.home = cross
	if n:
		travelers.append(n)
		walk(n, dest.pos)

# ================================================================ templates
# 1. Looted caravan → tracks to the attackers' camp
func _start_looted_caravan(e: Dictionary) -> void:
	var p: Vector3 = e.pos
	prop(e, "wrecked_cart", p, randf() * TAU)
	prop(e, "corpse", p + Vector3(2.0, 0, 1.0), randf() * TAU)
	prop(e, "crate_broken", p + Vector3(-1.5, 0, 1.5))
	VFX.decal(p, "ruts", 3.0, 600.0, randf() * TAU)
	var camp_pos := _find_target(p, ["camp"], 60.0, 220.0)
	var made_camp := false
	if camp_pos == Vector3.INF:
		camp_pos = _side(p + _dir_along_road(p) * 25.0, 55.0)
		made_camp = true
	e.data.camp = camp_pos
	e.data.made_camp = made_camp
	spot(e, p + Vector3(0, 0, 1), "Осмотреть разбитую %s" % CART[era()], func(_a):
		dialog(e.name, "Разбитая %s, рассыпанный груз. Следы нескольких человек и тяжёлых мешков уходят прочь от дороги. Кто-то унёс ценности." % CART[era()], [
			{"text": "Пойти по следам", "cb": func(): _follow_to_camp(e)},
			{"text": "Обыскать обломки", "cb": func():
				world.loot.spawn_drop(ItemDB.random_consumable(era()), p + Vector3(1, 0, 0))
				world.loot.spawn_drop({}, p + Vector3(-1, 0, 0), false, gold_k())},
			{"text": "Уйти", "cb": func(): pass}]))

func _follow_to_camp(e: Dictionary) -> void:
	e.data.following = true
	var cp: Vector3 = e.data.camp
	if e.data.made_camp:
		prop(e, "tent", cp + Vector3(3, 0, 0), 0.5)
		prop(e, "campfire", cp)
		var c := chest_at(e, cp + Vector3(-2, 0, 1))
		c.tier = "rich"
		for i in 3:
			spawn_enemy(e, bandit_ids()[randi() % bandit_ids().size()], cp + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
	var tr = tracking()
	if tr:
		tr.start_trail(e.pos, cp, "footprints", {"label": "Следы грабителей", "on_reach": func():
			Events.notify.emit("Логово грабителей найдено!", Color(1.0, 0.7, 0.4))
			chron("%s выследил(а) грабителей каравана." % Profile.char.name, [player()], cp)
			finish(e, "camp_found")})
	else:
		finish(e)

# 2. Bandit ambush with archers
func _start_ambush(e: Dictionary) -> void:
	var p: Vector3 = e.pos
	var ids := bandit_ids()
	for i in 2 + mini(2, world.spawner.era_progress_levels() / 2):
		var m = spawn_enemy(e, ids[randi() % ids.size()], _side(p + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), 8.0))
		if m:
			m.apply_status("stealth", 999.0)
			if m.rig:
				m.rig.crouch = true
			m.brain.think_t = 9999.0
	for i in 2:
		var a = spawn_enemy(e, ids[0], _side(p, 14.0))
		if a:
			give_ranged(a)
			a.apply_status("stealth", 999.0)
			a.brain.think_t = 9999.0
	e.data.sprung = false

func _tick_ambush(e: Dictionary) -> void:
	var pl = player()
	if not e.data.sprung and pl.global_position.distance_to(e.pos) < 13.0:
		e.data.sprung = true
		for a in e.actors:
			if is_instance_valid(a):
				a.statuses.erase("stealth")
				if a.rig:
					a.rig.crouch = false
				a.brain.think_t = 0.0
				a.add_aggro(pl, 60.0)
		Events.banner.emit("Засада!", "Разбойники выскакивают из укрытий.", Color(1.0, 0.45, 0.3))
		Audio.play_sfx("swing_heavy", e.pos)
	if e.data.sprung and alive(e.actors) == 0:
		reward(gold_k() * 2, 40 + lvl() * 6, "normal", "Засада отбита")
		chron("%s отбил(а) засаду разбойников на дороге." % Profile.char.name, [pl], e.pos)
		finish(e, "cleared")

# 3. Wounded traveler → potion / escort quest
func _start_wounded_traveler(e: Dictionary) -> void:
	var n = spawn_npc(e, "villager", e.pos, "Раненый %s" % TRAVELER[era()])
	freeze(n, "kneel")
	n.hp = n.max_hp * 0.25
	prop(e, "blood", e.pos + Vector3(0.5, 0, 0.3))
	e.data.npc = n
	e.actions["potion"] = func(): _wounded_potion(e)
	e.actions["escort"] = func(): _wounded_escort(e)
	spot(e, n, "Помочь раненому", func(_a):
		var has_potion: bool = player().data.inv.count("potion_hp") > 0
		dialog(n.display_name, "«На меня напали у моста… Помогите, прошу. Мне нужно добраться до ближайшего поселения»." , [
			{"text": "Отдать зелье здоровья", "disabled": not has_potion, "cb": e.actions["potion"]},
			{"text": "Проводить до поселения", "cb": e.actions["escort"]},
			{"text": "Пройти мимо", "cb": func(): finish(e, "ignored")}]))

func _wounded_potion(e: Dictionary) -> void:
	var n = e.data.npc
	if player().data.inv.consume("potion_hp", 1) and is_instance_valid(n):
		n.heal(n.max_hp)
		unfreeze(n)
		reward(gold_k() * 2, 30, "", "Благодарность путника")
		var near := _nearest_undiscovered()
		if near != "":
			Events.notify.emit("Путник рассказал о месте «%s»." % near, Color(0.8, 1.0, 0.8))
		chron("%s спас(ла) раненого путника на дороге." % Profile.char.name, [player(), n], e.pos)
		finish(e, "healed")

func _wounded_escort(e: Dictionary) -> void:
	var n = e.data.npc
	if not is_instance_valid(n) or world.gen == null:
		return
	var s: Dictionary = _nearest_settlement(n.global_position)
	unfreeze(n)
	n.heal(n.max_hp * 0.3)
	n.role = "companion"
	n.owner_actor = player()
	n.team = "player"
	var q: Dictionary = world.quests._q("escort", "Проводить путника", "Раненый путник просит проводить его до %s." % s.name,
		[world.quests._obj("escort_npc", "Довести путника до %s" % s.name, 1, {"pos": [s.pos.x, s.pos.y]})],
		{"gold": gold_k() * 4, "xp": 80 + lvl() * 10, "item": "chest"}, {"giver": n.display_name})
	world.quests.accept(q)
	e.data.quest = q
	e.data.dest = Vector3(s.pos.x, 0, s.pos.y)
	e.data.escort = true

func _tick_wounded_traveler(e: Dictionary) -> void:
	if not e.data.get("escort", false):
		return
	var n = e.data.npc
	var q: Dictionary = e.data.quest
	if not is_instance_valid(n) or n.is_dead:
		if q.state == "active":
			world.quests._fail(q, "Путник погиб.")
		finish(e, "failed")
		return
	var pl = player()
	var to: Vector3 = pl.global_position - n.global_position
	to.y = 0
	n.move_input = to.normalized() if to.length() > 3.0 else Vector3.ZERO
	if n.brain:
		n.brain.think_t = 9999.0 if not _danger(n) else 0.1
	var dest: Vector3 = e.data.dest
	if Vector2(n.global_position.x, n.global_position.z).distance_to(Vector2(dest.x, dest.z)) < 18.0:
		complete_custom(q, "escort_npc")
		n.owner_actor = null
		n.team = "neutral"
		n.role = "villager"
		chron("%s проводил(а) раненого путника до безопасного места." % Profile.char.name, [pl, n], dest)
		finish(e, "escorted")

func _danger(n) -> bool:
	for a in Game.actors_near(n.global_position, 12.0):
		if a != n and not a.is_dead and Game.is_enemy(n, a):
			return true
	return false

## Complete a custom objective kind on a quest.
func complete_custom(q: Dictionary, kind: String) -> void:
	if q.is_empty() or q.get("state", "") != "active":
		return
	for o in q.objectives:
		if o.kind == kind and not o.done:
			o.cur = o.need
			o.done = true
			Events.quest_updated.emit(q)
			world.quests._check_complete(q)
			return

# 4. Suspicious trader (cheap, sometimes cursed goods)
func _start_suspicious_trader(e: Dictionary) -> void:
	var n = spawn_npc(e, "trader", e.pos + Vector3(0, 0, 2), "Подозрительный торговец")
	freeze(n)
	prop(e, "cart", e.pos, randf() * TAU)
	var items: Array = []
	for i in 4:
		var it := ItemDB.random_for_era(era(), lvl(), "elite", 0.15)
		if ItemDB.is_equipment(it) and randf() < 0.55 and it.curse.is_empty():
			var ck := ItemDB.CURSES.keys()
			it.curse = {"id": ck[randi() % ck.size()], "bound": randf() < 0.5, "hidden": true, "release": ["purify", "ritual", "artifact"][randi() % 3]}
			it.history.append("Куплено у подозрительного торговца")
		items.append(it)
	e.data.items = items
	e.actions["trade"] = func():
		world.ui.open("trade", {"title": "Подозрительный торговец", "items": items, "price_mult": 0.6, "sell": true, "sell_mult": 0.25,
			"buy_cb": func(it): return world.factions.buy(it, 0.6)})
	spot(e, n, "Говорить: торговец", func(_a):
		dialog(n.display_name, "«Редкие вещицы, почти даром! Откуда? Не задавай лишних вопросов…»", [
			{"text": "Посмотреть товар", "cb": e.actions["trade"]},
			{"text": "Спросить о происхождении", "cb": func():
				Events.notify.emit("Торговец бегает глазами. Часть товара может быть проклята.", Color(0.9, 0.6, 0.6))},
			{"text": "Уйти", "cb": func(): finish(e, "left")}]))

# 5. Wandering smith (cheap upgrades)
func _start_wandering_smith(e: Dictionary) -> void:
	var n = spawn_npc(e, "villager", e.pos + Vector3(1.5, 0, 0), "Бродячий кузнец")
	freeze(n)
	prop(e, "anvil", e.pos)
	prop(e, "campfire", e.pos + Vector3(-2, 0, 1))
	e.actions["upgrade"] = func(): _smith_upgrade(e)
	spot(e, n, "Говорить: кузнец", func(_a):
		var w: Dictionary = player().weapon()
		var cost := (25 + int(w.get("upg", 0)) * 20) * (era() + 1)
		dialog(n.display_name, "«Хорошее оружие любит заботу. Подточу, перекую — дешевле, чем в городе»." , [
			{"text": "Улучшить оружие (%d)" % cost, "disabled": w.is_empty() or player().data.gold < cost or int(w.get("upg", 0)) >= 10, "cb": e.actions["upgrade"]},
			{"text": "Уйти", "cb": func(): finish(e, "left")}]))

func _smith_upgrade(e: Dictionary) -> void:
	var pl = player()
	var w: Dictionary = pl.weapon()
	if w.is_empty():
		return
	var cost := (25 + int(w.get("upg", 0)) * 20) * (era() + 1)
	if pl.data.gold < cost:
		return
	pl.data.gold -= cost
	w.upg = int(w.get("upg", 0)) + 1
	w.history.append("Улучшено бродячим кузнецом, день %d" % (Game.day() + 1))
	pl.refresh_gear()
	Audio.play_sfx("hit_metal", e.pos)
	VFX.burst(e.pos + Vector3(0, 1, 0), Color(1.0, 0.7, 0.3), 14, 0.3)
	Events.notify.emit("Оружие улучшено: %s" % ItemDB.display_name(w), Color(1.0, 0.85, 0.4))
	e.data.used = true

# 6. Two NPCs fighting (real records; intervene or not)
func _start_npc_fight(e: Dictionary) -> void:
	var a = spawn_record_bot(e, DBActors.rand_name(era(), false, Game.rng), e.pos + Vector3(-2, 0, 0), {"archetype": "aggressive", "level": lvl()})
	var b = spawn_record_bot(e, DBActors.rand_name(era(), randf() < 0.4, Game.rng), e.pos + Vector3(2, 0, 0), {"archetype": "vengeful", "level": lvl()})
	if a and b:
		a.add_aggro(b, 120.0)
		b.add_aggro(a, 120.0)
	e.data.a = a
	e.data.b = b
	e.data.helped = ""
	for n in [a, b]:
		if n:
			var nn = n
			spot(e, n, "Вмешаться: помочь %s" % n.display_name, func(_x): _help_fighter(e, nn), 4.0)

func _help_fighter(e: Dictionary, n) -> void:
	if e.data.helped != "" or not is_instance_valid(n):
		return
	e.data.helped = n.actor_id
	var other = e.data.b if n == e.data.a else e.data.a
	if is_instance_valid(other):
		other.add_aggro(player(), 60.0)
		player().add_aggro(other, 60.0)
	Events.notify.emit("Вы вступились за %s." % n.display_name, Color(0.8, 1.0, 0.8))

func _tick_npc_fight(e: Dictionary) -> void:
	var a = e.data.a
	var b = e.data.b
	var da: bool = a == null or not is_instance_valid(a) or a.is_dead
	var db: bool = b == null or not is_instance_valid(b) or b.is_dead
	if da or db:
		var winner = b if da else a
		if winner and is_instance_valid(winner) and not winner.is_dead:
			if e.data.helped == winner.actor_id:
				Chronicle.record("help", [player(), winner], {"pos_v3": winner.global_position})
				winner.brain.r_of("player").gratitude += 1.0
				reward(gold_k() * 2, 50, "", "%s благодарит вас" % winner.display_name)
		finish(e, "resolved")

# 7. Duel (bet / challenge the winner)
func _start_duel(e: Dictionary) -> void:
	prop(e, "ring", e.pos)
	var a = spawn_record_bot(e, DBActors.rand_name(era(), false, Game.rng) + " Клинок", e.pos + Vector3(-3, 0, 0), {"archetype": "ambitious", "level": lvl() + 1})
	var b = spawn_record_bot(e, DBActors.rand_name(era(), randf() < 0.4, Game.rng) + " Быстрый", e.pos + Vector3(3, 0, 0), {"archetype": "hunter", "level": lvl() + 1})
	for n in [a, b]:
		if n:
			freeze(n)
	e.data.a = a
	e.data.b = b
	e.data.bet = ""
	e.data.started = false
	var host = spawn_npc(e, "villager", e.pos + Vector3(0, 0, 5), "Распорядитель дуэли")
	freeze(host)
	e.actions["bet_a"] = func(): _duel_start(e, "a")
	e.actions["bet_b"] = func(): _duel_start(e, "b")
	e.actions["watch"] = func(): _duel_start(e, "")
	spot(e, host, "Дуэль", func(_x):
		var stake := gold_k() * 2
		dialog("Дуэль у дороги", "Двое бойцов готовятся к поединку до первой крови. Можно сделать ставку (%d)." % stake, [
			{"text": "Ставка на %s" % (a.display_name if a else "?"), "disabled": player().data.gold < stake, "cb": e.actions["bet_a"]},
			{"text": "Ставка на %s" % (b.display_name if b else "?"), "disabled": player().data.gold < stake, "cb": e.actions["bet_b"]},
			{"text": "Просто смотреть", "cb": e.actions["watch"]}]))

func _duel_start(e: Dictionary, bet: String) -> void:
	if e.data.started:
		return
	e.data.started = true
	e.data.bet = bet
	if bet != "":
		player().data.gold -= gold_k() * 2
	var a = e.data.a
	var b = e.data.b
	for n in [a, b]:
		unfreeze(n)
	if a and b and is_instance_valid(a) and is_instance_valid(b):
		a.add_aggro(b, 120.0)
		b.add_aggro(a, 120.0)
	Events.banner.emit("Дуэль!", "%s против %s" % [a.display_name if a else "?", b.display_name if b else "?"], Color(1.0, 0.8, 0.4))

func _tick_duel(e: Dictionary) -> void:
	if not e.data.started:
		return
	var a = e.data.a
	var b = e.data.b
	var a_out: bool = a == null or not is_instance_valid(a) or a.is_dead or a.yielding or a.hp < a.max_hp * 0.3
	var b_out: bool = b == null or not is_instance_valid(b) or b.is_dead or b.yielding or b.hp < b.max_hp * 0.3
	if a_out or b_out:
		var winner_key := "b" if a_out else "a"
		var winner = e.data[winner_key]
		var loser = e.data["a" if winner_key == "b" else "b"]
		for n in [a, b]:
			if n and is_instance_valid(n) and not n.is_dead:
				n.aggro.clear()
				n.brain.goal = "idle"
		if winner and is_instance_valid(winner):
			Chronicle.record("duel", [winner, loser if (loser and is_instance_valid(loser)) else {"id": "x", "name": "соперник"}], {"pos_v3": e.pos, "extra": {"winner": winner.display_name}})
			Profile.milestone("duel")
			if e.data.bet == winner_key:
				reward(gold_k() * 5, 20, "", "Выигрыш по ставке")
			elif e.data.bet != "":
				Events.notify.emit("Ставка проиграна.", Color(0.9, 0.6, 0.5))
			var w2 = winner
			spot(e, winner, "Вызвать победителя на дуэль", func(_x): world.legends.start_duel(w2))
		finish(e, "resolved")

# 8. Abandoned cart: loot / trap / clue
func _start_abandoned_cart(e: Dictionary) -> void:
	prop(e, "cart", e.pos, randf() * TAU)
	e.data.kind = ["loot", "trap", "clue"][randi() % 3]
	e.actions["search"] = func(): _cart_search(e)
	spot(e, e.pos + Vector3(0, 0, 1.3), "Обыскать %s" % CART[era()], func(_a): e.actions["search"].call())

func _cart_search(e: Dictionary) -> void:
	if e.data.get("searched", false):
		return
	e.data.searched = true
	var p: Vector3 = e.pos
	match e.data.kind:
		"loot":
			world.loot.spawn_drop(ItemDB.random_for_era(era(), lvl(), "chest"), p + Vector3(1, 0, 1))
			world.loot.spawn_drop({}, p + Vector3(-1, 0, 1), false, gold_k() * 2)
			Events.notify.emit("В повозке остались припасы!", Color(0.9, 0.85, 0.5))
			finish(e, "loot")
		"trap":
			VFX.explosion(p, 3.0, Color(1.0, 0.5, 0.2))
			Audio.play_sfx("explosion", p)
			Combat.aoe(null, p, 3.0, {"amount": 10.0 + lvl() * 3.0, "dtype": "fire"}, false)
			var ids := bandit_ids()
			for i in 3:
				var m = spawn_enemy(e, ids[randi() % ids.size()], _side(p, 10.0))
				if m:
					m.add_aggro(player(), 60.0)
			Events.banner.emit("Ловушка!", "Брошенная повозка была приманкой.", Color(1.0, 0.45, 0.3))
			e.data.trap_wave = true
		"clue":
			var target := _side(p + _dir_along_road(p) * 40.0, 50.0)
			e.data.target = target
			var victim = spawn_npc(e, "villager", target, "Похищенный %s" % TRAVELER[era()])
			freeze(victim, "kneel")
			var ids2 := bandit_ids()
			for i in 2:
				spawn_enemy(e, ids2[randi() % ids2.size()], target + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
			e.data.victim = victim
			dialog(e.name, "Повозка цела, но хозяина нет. На земле следы борьбы — его утащили в сторону леса.", [
				{"text": "Идти по следам", "cb": func():
					var tr = tracking()
					if tr:
						tr.start_trail(p, target, "drag", {"label": "Следы похищения"})}])

func _tick_abandoned_cart(e: Dictionary) -> void:
	if e.data.get("trap_wave", false) and alive(e.actors) == 0:
		reward(gold_k(), 30, "normal", "Засада у повозки отбита")
		finish(e, "trap_cleared")
	if e.data.kind == "clue" and e.data.get("searched", false):
		var hostiles := 0
		for a in e.actors:
			if is_instance_valid(a) and not a.is_dead and a != e.data.get("victim"):
				hostiles += 1
		var v = e.data.get("victim")
		if hostiles == 0 and v and is_instance_valid(v) and not v.is_dead and not e.data.get("rescued", false):
			e.data.rescued = true
			var vv = v
			spot(e, v, "Освободить пленника", func(_x):
				unfreeze(vv)
				reward(gold_k() * 3, 60, "chest", "Спасённый пленник")
				Chronicle.record("help", [player(), vv], {"pos_v3": vv.global_position})
				walk(vv, _nearest_settlement(vv.global_position).pos)
				finish(e, "rescued"))

# 9. Lost mage → find the artifact
func _start_lost_mage(e: Dictionary) -> void:
	var n = spawn_npc(e, "villager", e.pos, "Заблудившийся %s" % MAGE[era()])
	freeze(n)
	e.data.npc = n
	e.actions["accept"] = func(): _mage_accept(e)
	spot(e, n, "Говорить: %s" % MAGE[era()], func(_a):
		if e.data.get("artifact_uid", -1) != -1 and player().data.inv.find(e.data.artifact_uid).size() > 0:
			_mage_return(e)
			return
		dialog(n.display_name, "«Мой резонансный кристалл упал где-то здесь, когда на меня напали твари. Без него мне не вернуться. Найдёте — щедро заплачу»." , [
			{"text": "Помочь найти кристалл", "cb": e.actions["accept"]},
			{"text": "Отказаться", "cb": func(): finish(e, "refused")}]))

func _mage_accept(e: Dictionary) -> void:
	if e.data.has("artifact_uid"):
		return
	var it := ItemDB.create("amulet_bone", 3, lvl(), null, false)
	it.name = "Резонансный кристалл"
	it.history.append("Принадлежит заблудившемуся магу")
	e.data.artifact_uid = it.uid
	var spot_pos := _side(e.pos + _dir_along_road(e.pos) * randf_range(-30.0, 30.0), 35.0)
	world.loot.spawn_drop(it, spot_pos)
	var ids := beast_ids()
	for i in 2:
		spawn_enemy(e, ids[randi() % ids.size()], spot_pos + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
	var q: Dictionary = world.quests._q("artifact", "Кристалл мага", "Найти резонансный кристалл и вернуть его магу.",
		[world.quests._obj("find_item", "Найти резонансный кристалл", 1, {"pos": [spot_pos.x, spot_pos.z]}), world.quests._obj("return_item", "Вернуть кристалл магу", 1, {"pos": [e.pos.x, e.pos.z]})],
		{"gold": gold_k() * 3, "xp": 90 + lvl() * 10}, {"giver": "Маг"})
	world.quests.accept(q)
	e.data.quest = q

func _tick_lost_mage(e: Dictionary) -> void:
	var q: Dictionary = e.data.get("quest", {})
	if q.is_empty():
		return
	if e.data.has("artifact_uid") and player().data.inv.find(e.data.artifact_uid).size() > 0:
		complete_custom(q, "find_item")

func _mage_return(e: Dictionary) -> void:
	var pl = player()
	pl.data.inv.remove(e.data.artifact_uid)
	complete_custom(e.data.quest, "find_item")
	complete_custom(e.data.quest, "return_item")
	var tomes := ["tome_fire", "tome_ice", "tome_lightning", "tome_dark", "tome_spacetime"]
	pl.data.inv.add(ItemDB.create(tomes[randi() % tomes.size()], 0, 1))
	Events.notify.emit("Маг дарит вам фолиант магии.", Color(0.7, 0.8, 1.0))
	Chronicle.record("help", [pl, e.data.npc], {"pos_v3": e.pos})
	unfreeze(e.data.npc)
	finish(e, "returned")

# 10. Roadside ritual: interrupt or let it finish (summons an elite)
func _start_ritual(e: Dictionary) -> void:
	prop(e, "ritual_circle", e.pos)
	var ids := caster_ids()
	for i in 3:
		var a := TAU * i / 3.0
		var m = spawn_enemy(e, ids[randi() % ids.size()], e.pos + Vector3(cos(a), 0, sin(a)) * 3.0)
		if m:
			m.team = "bandit"
			freeze(m)
			m.set_meta("casting_ritual", true)
			if m.rig and "casting" in m.rig:
				m.rig.casting = true
	e.data.timer = 40.0
	e.data.interrupted = false
	spot(e, e.pos + Vector3(0, 0, 4.5), "Осмотреть ритуал", func(_a):
		dialog(e.name, "%s в капюшонах читают заклинание над светящимся кругом. Воздух дрожит — что-то пытается прорваться." % CULT[era()].capitalize(), [
			{"text": "Прервать ритуал", "cb": func(): _ritual_interrupt(e)},
			{"text": "Наблюдать издалека", "cb": func(): pass}]))

func _ritual_interrupt(e: Dictionary) -> void:
	if e.data.interrupted:
		return
	e.data.interrupted = true
	for a in e.actors:
		if is_instance_valid(a) and not a.is_dead:
			if a.rig and "casting" in a.rig:
				a.rig.casting = false
			unfreeze(a)
			a.add_aggro(player(), 60.0)
	Events.notify.emit("Ритуал прерван!", Color(0.8, 0.5, 1.0))

func _tick_ritual(e: Dictionary) -> void:
	var pl = player()
	if not e.data.interrupted:
		if pl.global_position.distance_to(e.pos) < 4.0 or alive(e.actors) < 3:
			_ritual_interrupt(e)
		e.data.timer -= 0.5
		if e.data.timer <= 0.0 and alive(e.actors) > 0:
			var pool: Array = DBEras.era(era()).night_enemies
			var boss = spawn_enemy(e, pool[pool.size() - 1], e.pos, 2)
			if boss:
				boss.elite = true
				boss.display_name = "Призванный: " + boss.display_name
				boss.max_hp *= 2.0
				boss.hp = boss.max_hp
				world.spawner.name_tag(boss, Color(0.8, 0.4, 1.0))
			VFX.ring(e.pos, 6.0, Color(0.7, 0.2, 1.0), 1.0)
			Events.banner.emit("Ритуал завершён", "Из круга вырвалось существо!", Color(0.8, 0.4, 1.0))
			_ritual_interrupt(e)
	elif alive(e.actors) == 0:
		reward(gold_k() * 2, 60, "elite", "Ритуал остановлен")
		chron("%s остановил(а) ритуал %s у дороги." % [Profile.char.name, CULT[era()]], [pl], e.pos)
		finish(e, "stopped")

# 11. Monster tracks → a lair (real boss lair or a monster den)
func _start_monster_tracks(e: Dictionary) -> void:
	var target := _find_target(e.pos, ["lair"], 80.0, 400.0)
	var den := false
	if target == Vector3.INF:
		target = _side(e.pos + _dir_along_road(e.pos) * 30.0, 70.0)
		den = true
	e.data.target = target
	e.data.den = den
	prop(e, "huge_print", e.pos, randf() * TAU)
	prop(e, "broken_crate", e.pos + Vector3(2, 0, 1))
	spot(e, e.pos + Vector3(0, 0, 1), "Изучить огромные следы", func(_a):
		var tr = tracking()
		if tr:
			tr.start_trail(e.pos, target, "huge", {"label": "Следы чудовища", "on_reach": func(): _den_reached(e)})
		Events.notify.emit("Огромные отпечатки ведут прочь от дороги…", Color(1.0, 0.7, 0.5))
		e.data.following = true)

func _den_reached(e: Dictionary) -> void:
	if e.data.den and not e.data.get("den_spawned", false):
		e.data.den_spawned = true
		var t: Vector3 = e.data.target
		prop(e, "bones", t)
		chest_at(e, t + Vector3(2, 0, 0))
		var ids := beast_ids()
		var m = spawn_enemy(e, ids[ids.size() - 1], t + Vector3(-3, 0, 0), 2)
		if m:
			m.elite = true
			m.max_hp *= 2.2
			m.hp = m.max_hp
			m.display_name = "Хозяин логова: " + m.display_name
			world.spawner.name_tag(m, Color(1.0, 0.55, 0.4))
	Events.banner.emit("Логово найдено", "Следы привели к логову чудовища.", Color(1.0, 0.6, 0.4))
	finish(e, "lair_found")

# 12. Rich caravan passing (trade rare goods)
func _start_rich_caravan(e: Dictionary) -> void:
	var lead = spawn_npc(e, "trader", e.pos, "Купец богатого каравана")
	var g1 = spawn_npc(e, "guard", e.pos + Vector3(2, 0, 1), "")
	var g2 = spawn_npc(e, "guard", e.pos + Vector3(-2, 0, 1), "")
	if world.gen and world.gen.settlements.size() > 0:
		var dest: Dictionary = world.gen.settlements[randi() % world.gen.settlements.size()]
		for n in [lead, g1, g2]:
			if n:
				walk(n, dest.pos)
	e.data.lead = lead
	var items: Array = []
	for i in 4:
		items.append(ItemDB.random_for_era(era(), lvl(), "boss" if i == 0 else "elite", 0.2))
	e.actions["trade"] = func():
		world.ui.open("trade", {"title": "Богатый караван", "items": items, "price_mult": 1.5, "sell": true, "sell_mult": 0.45,
			"buy_cb": func(it): return world.factions.buy(it, 1.5)})
	spot(e, lead, "Торговать: богатый караван", func(_a):
		e.data.traded = true
		e.actions["trade"].call())

func _tick_rich_caravan(e: Dictionary) -> void:
	for a in e.actors:
		_keep_walking(a)
	var lead = e.data.lead
	if lead == null or not is_instance_valid(lead) or lead.is_dead:
		finish(e, "gone")

# 13. Bandit begging for mercy
func _start_mercy_bandit(e: Dictionary) -> void:
	var ids := bandit_ids()
	var n = spawn_enemy(e, ids[randi() % ids.size()], e.pos, 0)
	if n == null:
		finish(e, "fail")
		return
	n.team = "neutral"
	n.hp = n.max_hp * 0.2
	freeze(n, "kneel")
	n.display_name = DBActors.rand_name(era(), false, Game.rng) + " " + DBActors.NICKNAMES[randi() % DBActors.NICKNAMES.size()]
	world.spawner.name_tag(n, Color(1.0, 0.9, 0.6))
	e.data.npc = n
	for i in 2:
		prop(e, "corpse", e.pos + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), randf() * TAU)
	e.actions["spare"] = func(): _mercy_spare(e)
	e.actions["rob"] = func(): _mercy_rob(e)
	e.actions["kill"] = func(): _mercy_kill(e)
	spot(e, n, "Говорить: раненый разбойник", func(_a):
		dialog(n.display_name, "«Мою банду перебили… Пощади! Я ещё пригожусь тебе — клянусь!»", [
			{"text": "Пощадить и отпустить", "cb": e.actions["spare"]},
			{"text": "Забрать его золото", "cb": e.actions["rob"]},
			{"text": "Покончить с ним", "cb": e.actions["kill"]}]))

func _mercy_spare(e: Dictionary) -> void:
	var n = e.data.npc
	if not is_instance_valid(n):
		return
	var rec: Dictionary = world.legends.new_record(n.display_name, {"archetype": "opportunist", "level": n.level, "pos": [n.global_position.x, n.global_position.z]})
	rec.data = n.data.to_dict()
	rec.backstory = "Бывший разбойник, которого пощадили на дороге."
	n.record = rec
	n.actor_id = rec.id
	n.team = "bot"
	n.role = "bot"
	unfreeze(n)
	world.sim.active[rec.id] = n
	Chronicle.record("mercy", [player(), n], {"pos_v3": n.global_position})
	n.brain.on_spared(player())
	Profile.unlock("mercy")
	Events.notify.emit("%s запомнит вашу милость." % n.display_name, Color(0.8, 1.0, 0.8))
	finish(e, "spared")

func _mercy_rob(e: Dictionary) -> void:
	var n = e.data.npc
	if not is_instance_valid(n):
		return
	reward(gold_k() * 2, 0, "", "Золото разбойника")
	var rec: Dictionary = world.legends.new_record(n.display_name, {"archetype": "vengeful", "level": n.level, "pos": [n.global_position.x, n.global_position.z]})
	rec.rel.grudge = 1.2
	rec.backstory = "Разбойник, которого ограбили и унизили на дороге. Затаил злобу."
	n.record = rec
	n.actor_id = rec.id
	n.team = "bot"
	n.role = "bot"
	unfreeze(n)
	world.sim.active[rec.id] = n
	n.brain.goal = "flee"
	n.brain.threat = player()
	chron("%s ограбил(а) поверженного разбойника %s." % [Profile.char.name, n.display_name], [player(), n], n.global_position)
	finish(e, "robbed")

func _mercy_kill(e: Dictionary) -> void:
	var n = e.data.npc
	if is_instance_valid(n) and not n.is_dead:
		n.team = "bandit"
		n._apply_raw_damage(n.hp + 1.0, player(), "slash")
	finish(e, "killed")

# 14. Cursed chest
func _start_cursed_chest(e: Dictionary) -> void:
	prop(e, "cursed_glow", e.pos)
	e.actions["open"] = func(): _cursed_open(e)
	spot(e, e.pos, "Открыть зловещий сундук", func(_a):
		dialog(e.name, "Сундук покрыт рунами и источает холод. Внутри что-то ценное… и что-то ещё.", [
			{"text": "Открыть", "cb": e.actions["open"]},
			{"text": "Не трогать", "cb": func(): finish(e, "left")}]))

func _cursed_open(e: Dictionary) -> void:
	if e.data.get("opened", false):
		return
	e.data.opened = true
	var it := ItemDB.random_for_era(era(), lvl() + 2, "elite", 0.3)
	if ItemDB.is_equipment(it):
		var ck := ItemDB.CURSES.keys()
		it.curse = {"id": ck[randi() % ck.size()], "bound": true, "hidden": true, "release": ["purify", "ritual", "quest", "artifact"][randi() % 4]}
		if it.stats.has("dmg"):
			it.stats.dmg = snappedf(it.stats.dmg * 1.4, 0.01)
		if it.stats.has("armor"):
			it.stats.armor = snappedf(it.stats.armor * 1.4, 0.01)
	it.history.append("Найден в зловещем сундуке у дороги")
	world.loot.spawn_drop(it, e.pos + Vector3(1, 0, 0))
	if randf() < 0.5:
		player().apply_status("curse", 20.0)
		Events.notify.emit("Холод проклятия касается вас…", Color(0.7, 0.4, 0.9))
	VFX.burst(e.pos + Vector3(0, 0.6, 0), Color(0.6, 0.2, 0.9), 18, 0.35)
	Audio.play_sfx("curse_bind", e.pos)
	finish(e, "opened")

# 15. Mimic (a chest by the road — always a mimic)
func _start_mimic_chest(e: Dictionary) -> void:
	var c := chest_at(e, e.pos, "rich", true)
	e.data.chest = c

func _tick_mimic_chest(e: Dictionary) -> void:
	var c = e.data.chest
	if c == null or not is_instance_valid(c) or c.opened:
		finish(e, "triggered")

# 16. Stranger at a campfire: info / trade / bounty with tracks / food
func _start_campfire_stranger(e: Dictionary) -> void:
	prop(e, "campfire", e.pos)
	var n = spawn_npc(e, "villager", e.pos + Vector3(1.6, 0, 0), "Незнакомец у костра")
	freeze(n, "sit")
	e.data.npc = n
	e.actions["info"] = func(): _stranger_info(e)
	e.actions["bounty"] = func(): _stranger_bounty(e)
	spot(e, n, "Подсесть к костру", func(_a):
		dialog(n.display_name, "«Садись, путник. Ночи нынче опасные. Хочешь — расскажу, что видел на дорогах»." , [
			{"text": "Послушать рассказы", "cb": e.actions["info"]},
			{"text": "Спросить о работе", "cb": e.actions["bounty"]},
			{"text": "Отдохнуть у огня", "cb": func():
				player().heal(player().max_hp * 0.5)
				player().mana = player().max_mana
				Events.notify.emit("Вы отдохнули у костра.", Color(1.0, 0.8, 0.5))},
			{"text": "Уйти", "cb": func(): finish(e, "left")}]))

func _stranger_info(e: Dictionary) -> void:
	var disc = world.sys("discovery") if world.has_method("sys") else null
	var target = _nearest_undiscovered_poi()
	if target != null and disc and disc.has_method("reveal"):
		disc.reveal(target.id)
		Events.notify.emit("Незнакомец рассказал о месте «%s». Отмечено на карте." % target.get("name", "?"), Color(0.8, 0.9, 1.0))
	else:
		Events.notify.emit("«Говорят, у старых руин видели странный свет»", Color(0.8, 0.9, 1.0))
	e.data.info = true

func _stranger_bounty(e: Dictionary) -> void:
	if e.data.get("bounty", false):
		return
	e.data.bounty = true
	var tr = tracking()
	if tr and tr.has_method("start_bounty"):
		tr.start_bounty(e.pos)
	finish(e, "bounty")

# 17. Broken bridge / blocked road: clear the barricade
func _start_broken_bridge(e: Dictionary) -> void:
	var d := _dir_along_road(e.pos)
	var side := d.cross(Vector3.UP)
	e.data.walls = []
	for i in range(-2, 3):
		var dd := Destructible.new()
		dd.configure("palisade", "", {"destroyed": []}, era(), Vector3.ZERO, atan2(side.x, side.z))
		add_child(dd)
		dd.global_position = ground(e.pos + side * i * 1.6)
		e.nodes.append(dd)
		e.data.walls.append(dd)
	prop(e, "debris", e.pos + d * 2.0)
	spot(e, e.pos - d * 3.0, "Осмотреть завал", func(_a):
		dialog(e.name, "Дорога перекрыта завалом из брёвен и обломков. Торговцы застряли. Завал можно разрушить оружием или огнём.", [
			{"text": "Понятно", "cb": func(): pass}]))

func _tick_broken_bridge(e: Dictionary) -> void:
	var left := 0
	for w in e.data.walls:
		if is_instance_valid(w) and not w.is_destroyed:
			left += 1
	if left <= 1:
		var s: Dictionary = _nearest_settlement(e.pos)
		var owner_f: String = world.factions.settlement_owner(s.get("id", ""))
		if owner_f != "":
			world.factions.add_rep(owner_f, 15.0, "расчищена дорога")
		reward(gold_k() * 2, 40, "", "Дорога расчищена")
		chron("%s расчистил(а) перекрытую дорогу у %s." % [Profile.char.name, s.get("name", "поселения")], [player()], e.pos)
		finish(e, "cleared")

# 18. Relic hunters competing for ruins treasure
func _start_relic_hunters(e: Dictionary) -> void:
	var ruins := _find_target(e.pos, ["ruins", "dungeon", "altar"], 40.0, 300.0)
	if ruins == Vector3.INF:
		ruins = _side(e.pos + _dir_along_road(e.pos) * 30.0, 45.0)
		prop(e, "ruin_pillars", ruins)
	var c := chest_at(e, ruins + Vector3(1.5, 0, 1.5), "rich")
	e.data.chest = c
	e.data.ruins = ruins
	e.data.hunters = []
	for i in 2:
		var n = spawn_record_bot(e, DBActors.rand_name(era(), randf() < 0.4, Game.rng) + " Искатель", e.pos + Vector3(i * 2.0, 0, 0), {"archetype": "treasure", "relic_hunter": true, "level": lvl()})
		if n:
			n.brain.path = [ruins]
			n.brain.goal = "travel"
			n.brain.think_t = 2.0
			e.data.hunters.append(n)
	Events.notify.emit("Охотники за реликвиями направляются к руинам. Успейте первыми!", Color(1.0, 0.85, 0.5))

func _tick_relic_hunters(e: Dictionary) -> void:
	var c = e.data.chest
	if c == null or not is_instance_valid(c) or c.opened:
		var by_hunter := false
		for h in e.data.hunters:
			if is_instance_valid(h) and h.global_position.distance_to(e.data.ruins) < 6.0:
				by_hunter = true
		if by_hunter:
			chron("Охотники за реликвиями опередили %s и забрали сокровище руин." % Profile.char.name, e.data.hunters, e.data.ruins)
		finish(e, "hunters" if by_hunter else "player")

# 19. Fugitive chased by pursuers (help or hand over)
func _start_fugitive(e: Dictionary) -> void:
	var f = spawn_npc(e, "villager", e.pos, "Беглец")
	e.data.f = f
	e.data.p = []
	var ids := bandit_ids()
	for i in 2:
		var m = spawn_enemy(e, ids[randi() % ids.size()], e.pos - _dir_along_road(e.pos) * (14.0 + i * 2))
		if m:
			m.team = "neutral"
			m.display_name = "Преследователь"
			m.add_aggro(f, 120.0)
			e.data.p.append(m)
	var pl = player()
	if f:
		f.brain.goal = "flee"
		f.brain.threat = e.data.p[0] if not e.data.p.is_empty() else pl
		f.brain.think_t = 6.0
	e.actions["help"] = func(): _fugitive_help(e)
	e.actions["hand"] = func(): _fugitive_hand(e)
	spot(e, f, "Говорить: беглец", func(_a):
		dialog("Беглец", "«Они хотят моей смерти за то, что я видел! Помогите!» Преследователи кричат: «Отдай нам вора — заплатим!»", [
			{"text": "Защитить беглеца", "cb": e.actions["help"]},
			{"text": "Выдать преследователям", "cb": e.actions["hand"]}]), 3.5)

func _fugitive_help(e: Dictionary) -> void:
	e.data.choice = "help"
	for m in e.data.p:
		if is_instance_valid(m):
			m.team = "bandit"
			m.add_aggro(player(), 60.0)

func _fugitive_hand(e: Dictionary) -> void:
	e.data.choice = "hand"
	var f = e.data.f
	if is_instance_valid(f):
		freeze(f, "kneel")
	reward(gold_k() * 3, 0, "", "Награда преследователей")
	chron("%s выдал(а) беглеца преследователям." % Profile.char.name, [player()], e.pos)
	finish(e, "handed")

func _tick_fugitive(e: Dictionary) -> void:
	var f = e.data.f
	if e.data.get("choice", "") == "help" and alive(e.data.p) == 0:
		if f and is_instance_valid(f) and not f.is_dead:
			reward(gold_k() * 2, 60, "chest", "Спасённый беглец отдаёт тайник")
			Chronicle.record("help", [player(), f], {"pos_v3": f.global_position})
		finish(e, "saved")
	elif f == null or not is_instance_valid(f) or f.is_dead:
		finish(e, "dead")

# 20. Temporal trail leading to a real rift
func _start_temporal_trail(e: Dictionary) -> void:
	var rift := _find_target(e.pos, ["rift"], 50.0, 450.0)
	var temp := false
	if rift == Vector3.INF:
		rift = _side(e.pos + _dir_along_road(e.pos) * 30.0, 60.0)
		temp = true
	e.data.rift = rift
	e.data.temp = temp
	prop(e, "anomaly", e.pos)
	spot(e, e.pos, "Изучить временной след", func(_a):
		var tr = tracking()
		if tr:
			tr.start_trail(e.pos, rift, "magic", {"label": "Временной след", "on_reach": func(): _rift_reached(e)})
		Events.notify.emit("Мерцающие частицы тянутся прочь от дороги.", Color(0.5, 1.0, 0.9)))

func _rift_reached(e: Dictionary) -> void:
	if e.data.temp and not e.data.get("opened", false):
		e.data.opened = true
		var portal := Poi.create({"id": e.id + "_rift", "type": "rift", "pos": Vector2(e.data.rift.x, e.data.rift.z), "name": "Скрытый разлом", "data": {"temporary": true}}, world)
		world.poi_root.add_child(portal)
		portal.global_position = ground(e.data.rift)
		e.nodes.append(portal)
		Audio.play_sfx("portal_open", e.data.rift)
	Events.banner.emit("Разлом найден", "Временной след привёл к разлому.", Color(0.5, 1.0, 0.9))
	finish(e, "rift_found")

# 21. Wild beasts attack travelers
func _start_beast_attack(e: Dictionary) -> void:
	var t1 = spawn_npc(e, "villager", e.pos, TRAVELER[era()].capitalize())
	var t2 = spawn_npc(e, "guard", e.pos + Vector3(1.5, 0, 0), "Охранник путников")
	e.data.tr = [t1, t2]
	e.data.beasts = []
	var ids := beast_ids()
	for i in 2 + mini(2, world.spawner.era_progress_levels() / 2):
		var m = spawn_enemy(e, ids[randi() % ids.size()], e.pos + Vector3(randf_range(-7, 7), 0, randf_range(-7, 7)))
		if m:
			m.brain.target = t1 if randf() < 0.5 else t2
			e.data.beasts.append(m)

func _tick_beast_attack(e: Dictionary) -> void:
	if alive(e.data.beasts) == 0:
		var saved := alive(e.data.tr)
		if saved > 0:
			reward(gold_k() * 2 * saved, 40, "normal" if saved > 1 else "", "Спасённые путники")
			for t in e.data.tr:
				if is_instance_valid(t) and not t.is_dead:
					Chronicle.record("help", [player(), t], {"pos_v3": t.global_position})
		finish(e, "saved")
	elif alive(e.data.tr) == 0:
		finish(e, "lost")

# 22. Lost relic: keep it or return it to its owner (real record)
func _start_lost_relic(e: Dictionary) -> void:
	var it := ItemDB.random_for_era(era(), lvl(), "elite", 0.3)
	if ItemDB.is_equipment(it):
		it.rarity = maxi(int(it.rarity), 3)
	var owner_name := DBActors.rand_name(era(), randf() < 0.4, Game.rng)
	it.history.append("Фамильная реликвия рода %s" % owner_name)
	e.data.uid = it.uid
	e.data.owner = owner_name
	var d = world.loot.spawn_drop(it, e.pos)
	if d:
		e.nodes.append(d)
	e.data.timer = -1.0

func _tick_lost_relic(e: Dictionary) -> void:
	var pl = player()
	if e.data.timer < 0.0 and pl.data.inv.find(e.data.uid).size() > 0:
		e.data.timer = 20.0
	elif e.data.timer > 0.0:
		e.data.timer -= 0.5
		if e.data.timer <= 0.0 and not e.data.has("owner_npc"):
			var p := ground(pl.global_position + pl.facing.rotated(Vector3.UP, 2.5) * 9.0)
			var o = spawn_record_bot(e, e.data.owner, p, {"archetype": "defender", "level": lvl()})
			if o:
				freeze(o)
				e.data.owner_npc = o
				var oo = o
				spot(e, o, "Говорить: %s" % o.display_name, func(_a):
					dialog(oo.display_name, "«Это реликвия моего рода! Я искал её много дней. Верни — и я не останусь в долгу»." , [
						{"text": "Вернуть реликвию", "cb": func(): _relic_return(e)},
						{"text": "Оставить себе", "cb": func(): _relic_keep(e)}]))
				Events.notify.emit("Кто-то ищет вас: «Эй! Это моя вещь!»", Color(1.0, 0.85, 0.5))

func _relic_return(e: Dictionary) -> void:
	var o = e.data.owner_npc
	var pl = player()
	if pl.data.inv.remove(e.data.uid).is_empty():
		return
	unfreeze(o)
	o.record.rel.gratitude += 1.5
	o.brain.r_of("player").gratitude += 1.5
	reward(gold_k() * 5, 80, "elite", "Благодарность рода")
	Chronicle.record("help", [pl, o], {"pos_v3": o.global_position})
	finish(e, "returned")

func _relic_keep(e: Dictionary) -> void:
	var o = e.data.owner_npc
	unfreeze(o)
	o.record.rel.grudge += 1.5
	o.record.archetype = "vengeful"
	o.add_aggro(player(), 60.0)
	chron("%s присвоил(а) реликвию рода %s. Хозяин поклялся вернуть её." % [Profile.char.name, o.display_name], [player(), o], o.global_position)
	finish(e, "kept")

# 23. Wandering champion offers a duel
func _start_wandering_champion(e: Dictionary) -> void:
	var c = spawn_record_bot(e, DBActors.rand_name(era(), randf() < 0.3, Game.rng) + " Непобедимый", e.pos, {"archetype": "ambitious", "level": lvl() + 2})
	if c == null:
		finish(e, "fail")
		return
	c.record.renown = 40.0
	freeze(c)
	e.data.c = c
	e.actions["accept"] = func():
		unfreeze(c)
		world.legends.start_duel(c)
		e.data.dueling = true
	spot(e, c, "Говорить: чемпион", func(_a):
		dialog(c.display_name, "«Я обошёл все дороги эпохи и не встретил равного. Сразишься со мной один на один?»", [
			{"text": "Принять вызов", "cb": e.actions["accept"]},
			{"text": "Отказаться", "cb": func():
				unfreeze(c)
				finish(e, "declined")}]))

func _tick_wandering_champion(e: Dictionary) -> void:
	var c = e.data.c
	if e.data.get("dueling", false) and (c == null or not is_instance_valid(c) or c.is_dead):
		reward(gold_k() * 6, 120 + lvl() * 10, "elite", "Победа над чемпионом")
		player().data.fame += 10.0
		finish(e, "won")

# 24. Dying messenger: deliver the message
func _start_dying_messenger(e: Dictionary) -> void:
	var n = spawn_npc(e, "villager", e.pos, "Умирающий %s" % MESSENGER[era()])
	freeze(n, "kneel")
	n.hp = n.max_hp * 0.1
	e.data.npc = n
	prop(e, "blood", e.pos)
	e.actions["take"] = func(): _messenger_take(e)
	spot(e, n, "Выслушать гонца", func(_a):
		dialog(n.display_name, "«Письмо… доставь его… в руки… Не дай… им…» Он протягивает запечатанный пакет.", [
			{"text": "Взять письмо", "cb": e.actions["take"]}]))

func _messenger_take(e: Dictionary) -> void:
	if e.data.get("taken", false) or world.gen == null:
		return
	e.data.taken = true
	var s: Dictionary = world.gen.settlements[randi() % world.gen.settlements.size()]
	var fid: String = world.factions.settlement_owner(s.id)
	var q: Dictionary = world.quests._q("deliver", "Последнее письмо", "Доставить письмо умирающего гонца в %s." % s.name,
		[world.quests._obj("reach", "Доставить письмо в %s" % s.name, 1, {"pos": [s.pos.x, s.pos.y], "radius": 18.0})],
		{"gold": gold_k() * 4, "xp": 90 + lvl() * 10, "rep": ({fid: 25} if fid != "" else {})}, {"giver": "Гонец"})
	world.quests.accept(q)
	var n = e.data.npc
	if is_instance_valid(n):
		n._apply_raw_damage(n.hp + 1.0, null, "slash", true)
	chron("Умирающий гонец передал %s последнее письмо." % Profile.char.name, [player()], e.pos)
	finish(e, "taken")

# 25. Battle aftermath: items, clues, a wounded survivor
func _start_battle_aftermath(e: Dictionary) -> void:
	var fl: Array = world.factions.list()
	var fa: String = fl[randi() % fl.size()]
	var fb: String = fl[(fl.find(fa) + 1) % fl.size()]
	for ev in Chronicle.recent(30):
		if ev.type == "battle":
			for f in fl:
				if DBEras.faction(f).name == ev.extra.get("a", ""):
					fa = f
				if DBEras.faction(f).name == ev.extra.get("b", ""):
					fb = f
			break
	e.data.fa = fa
	e.data.fb = fb
	for i in 4:
		prop(e, "corpse", e.pos + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), randf() * TAU)
	prop(e, "banner_" + fa, e.pos + Vector3(-3, 0, 2))
	prop(e, "banner_" + fb, e.pos + Vector3(3, 0, -2))
	VFX.decal(e.pos, "scorch", 4.0, 600.0)
	for i in 2:
		world.loot.spawn_drop(ItemDB.random_for_era(era(), lvl(), "normal"), e.pos + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
	var surv_pos := _side(e.pos, 22.0)
	var s = spawn_npc(e, "villager", surv_pos, "Раненый боец «%s»" % DBEras.faction(fa).name)
	freeze(s, "kneel")
	e.data.s = s
	spot(e, e.pos, "Осмотреть поле боя", func(_a):
		dialog(e.name, "Здесь недавно сражались «%s» и «%s». Кровавый след уводит в сторону — кто-то выжил." % [DBEras.faction(fa).name, DBEras.faction(fb).name], [
			{"text": "Идти по кровавому следу", "cb": func():
				var tr = tracking()
				if tr:
					tr.start_trail(e.pos, surv_pos, "blood", {"label": "Кровавый след"})},
			{"text": "Уйти", "cb": func(): pass}]))
	var ss = s
	spot(e, s, "Помочь раненому бойцу", func(_a):
		unfreeze(ss)
		world.factions.add_rep(fa, 20.0, "помощь раненому")
		reward(gold_k() * 2, 50, "", "Благодарность бойца")
		Chronicle.record("help", [player(), ss], {"pos_v3": ss.global_position})
		finish(e, "helped"))

# ================================================================ targets
func _find_target(from: Vector3, types: Array, min_d: float, max_d: float) -> Vector3:
	if world.gen == null:
		return Vector3.INF
	var best := Vector3.INF
	var bd := INF
	var f2 := Vector2(from.x, from.z)
	for p in world.gen.pois:
		if not p.type in types:
			continue
		if p.type == "lair" and Game.world_state.bosses.get(p.data.get("boss_id", ""), {}).get("defeated", false):
			continue
		var d: float = f2.distance_to(p.pos)
		if d >= min_d and d <= max_d and d < bd:
			bd = d
			best = Vector3(p.pos.x, 0, p.pos.y)
	return best

func _nearest_settlement(p: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	if world.gen:
		for s in world.gen.settlements:
			var d: float = Vector2(p.x, p.z).distance_to(s.pos)
			if d < bd:
				bd = d
				best = s
	if best.is_empty():
		best = {"id": "", "name": "поселения", "pos": Vector2(p.x, p.z)}
	return best

func _nearest_undiscovered_poi():
	var disc = world.sys("discovery") if world.has_method("sys") else null
	if world.gen == null:
		return null
	var pp: Vector3 = player().global_position
	var best = null
	var bd := INF
	for p in world.gen.pois:
		if disc and disc.has_method("is_discovered") and disc.is_discovered(p.id):
			continue
		var d: float = Vector2(pp.x, pp.z).distance_to(p.pos)
		if d < bd and d > 30.0:
			bd = d
			best = p
	return best

func _nearest_undiscovered() -> String:
	var p = _nearest_undiscovered_poi()
	if p == null:
		return ""
	var disc = world.sys("discovery") if world.has_method("sys") else null
	if disc and disc.has_method("reveal"):
		disc.reveal(p.id)
	return p.get("name", "?")

# ================================================================ props
static func make_prop(kind: String, era_i: int, rot: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = rot
	var wood := MeshLib.mat(Color(0.45, 0.31, 0.18))
	var dark := MeshLib.mat(Color(0.18, 0.15, 0.13))
	var metal := MeshLib.mat(Color(0.45, 0.46, 0.5), 0.7, 0.4)
	var cloth := MeshLib.mat(Color(0.6, 0.55, 0.42))
	match kind:
		"cart", "wrecked_cart":
			var wreck := kind == "wrecked_cart"
			var body_c := wood
			if era_i == 2:
				body_c = MeshLib.mat(Color(0.35, 0.3, 0.26), 0.5, 0.5)
			elif era_i == 3:
				body_c = MeshLib.mat(Color(0.5, 0.15, 0.12), 0.4, 0.5)
			elif era_i == 4:
				body_c = MeshLib.mat(Color(0.75, 0.78, 0.85), 0.6, 0.3)
			var sb := StaticBody3D.new()
			sb.collision_layer = 1
			root.add_child(sb)
			var cs := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(1.6, 1.0, 2.8)
			cs.shape = bx
			cs.position.y = 0.6
			sb.add_child(cs)
			var body := MeshLib.part(sb, MeshLib.box(Vector3(1.5, 0.6, 2.6)), body_c, Vector3(0, 0.75 if not wreck else 0.45, 0), Vector3(0, 0, 18.0 if wreck else 0.0))
			if era_i <= 1:
				MeshLib.part(sb, MeshLib.cyl(0.03, 0.03, 1.6, 4), wood, Vector3(0.35, 0.6, -2.0), Vector3(90, 0, 0))
				MeshLib.part(sb, MeshLib.cyl(0.03, 0.03, 1.6, 4), wood, Vector3(-0.35, 0.6, -2.0), Vector3(90, 0, 0))
			elif era_i == 2:
				MeshLib.part(sb, MeshLib.cyl(0.3, 0.3, 0.9, 10), metal, Vector3(0, 1.3, -0.8))
				MeshLib.part(sb, MeshLib.cyl(0.07, 0.07, 0.9, 6), dark, Vector3(0, 1.9, -0.8))
			elif era_i == 3:
				MeshLib.part(sb, MeshLib.box(Vector3(1.4, 0.6, 1.0)), MeshLib.mat(Color(0.3, 0.45, 0.6, 0.8)), Vector3(0, 1.35, -0.6))
			else:
				MeshLib.part(sb, MeshLib.box(Vector3(1.6, 0.08, 2.7)), MeshLib.glow(Color(0.3, 0.9, 1.0), 2.0), Vector3(0, 0.38, 0))
			if era_i <= 3:
				var wheel_m := wood if era_i <= 1 else MeshLib.mat(Color(0.08, 0.08, 0.08))
				var wn := 0
				for wp in [Vector3(0.8, 0.4, 0.9), Vector3(-0.8, 0.4, 0.9), Vector3(0.8, 0.4, -0.9), Vector3(-0.8, 0.4, -0.9)]:
					wn += 1
					if wreck and wn == 2:
						MeshLib.part(sb, MeshLib.cyl(0.4, 0.4, 0.12, 10), wheel_m, Vector3(-1.6, 0.06, 1.4), Vector3(90, 0, 30))
						continue
					MeshLib.part(sb, MeshLib.cyl(0.4, 0.4, 0.12, 10), wheel_m, wp, Vector3(0, 0, 90))
			if wreck:
				for i in 3:
					MeshLib.part(root, MeshLib.box(Vector3(0.5, 0.35, 0.5)), wood, Vector3(randf_range(-2, 2), 0.17, randf_range(-2, 2)), Vector3(0, randf() * 90.0, randf_range(-20, 20)))
		"crate_broken", "broken_crate", "debris":
			for i in (3 if kind != "debris" else 6):
				MeshLib.part(root, MeshLib.box(Vector3(randf_range(0.3, 0.9), 0.08, randf_range(0.1, 0.3))), wood, Vector3(randf_range(-1, 1), 0.05, randf_range(-1, 1)), Vector3(0, randf() * 180.0, 0))
			if kind == "debris":
				for i in 3:
					MeshLib.part(root, MeshLib.cyl(0.18, 0.2, 2.2, 6), wood, Vector3(randf_range(-1.5, 1.5), 0.2, randf_range(-1, 1)), Vector3(0, randf() * 180.0, 90))
		"corpse":
			var cm := MeshLib.mat(Color(0.35, 0.3, 0.28))
			MeshLib.part(root, MeshLib.capsule(0.2, 1.2), cm, Vector3(0, 0.18, 0), Vector3(90, 0, 0))
			MeshLib.part(root, MeshLib.sphere(0.14, 8, 5), MeshLib.mat(Color(0.75, 0.6, 0.5)), Vector3(0, 0.15, -0.75))
			MeshLib.part(root, MeshLib.box(Vector3(0.05, 0.02, 0.8)), metal, Vector3(0.45, 0.03, 0.2), Vector3(0, 30, 0))
			MeshLib.part(root, MeshLib.cyl(0.5, 0.5, 0.01, 10), MeshLib.mat(Color(0.4, 0.05, 0.05, 0.7)), Vector3(0.1, 0.01, 0.1), Vector3.ZERO, Vector3.ONE, false)
		"blood":
			MeshLib.part(root, MeshLib.cyl(0.6, 0.6, 0.01, 10), MeshLib.mat(Color(0.45, 0.04, 0.04, 0.75)), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.4, 1, 0.8), false)
		"campfire":
			for i in 4:
				MeshLib.part(root, MeshLib.cyl(0.07, 0.07, 0.8, 5), wood, Vector3(0, 0.08, 0), Vector3(0, i * 45.0, 90))
			MeshLib.part(root, MeshLib.prism(Vector3(0.5, 0.7, 0.5)), MeshLib.glow(Color(1.0, 0.55, 0.15), 3.0), Vector3(0, 0.4, 0), Vector3.ZERO, Vector3.ONE, false)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.6, 0.3)
			l.light_energy = 1.4
			l.omni_range = 7.0
			l.position.y = 0.8
			l.shadow_enabled = false
			root.add_child(l)
			var p := CPUParticles3D.new()
			p.amount = 10
			p.lifetime = 1.2
			p.direction = Vector3.UP
			p.spread = 15.0
			p.initial_velocity_min = 0.8
			p.initial_velocity_max = 1.6
			p.gravity = Vector3(0, 0.5, 0)
			p.mesh = MeshLib.box(Vector3(0.04, 0.04, 0.04))
			p.material_override = MeshLib.mat(Color(1.0, 0.6, 0.2), 0.0, 1.0, 3.0, true)
			p.position.y = 0.5
			root.add_child(p)
		"tent":
			MeshLib.part(root, MeshLib.prism(Vector3(2.4, 1.8, 2.6)), cloth, Vector3(0, 0.9, 0))
		"anvil":
			MeshLib.part(root, MeshLib.box(Vector3(0.4, 0.5, 0.4)), wood, Vector3(0, 0.25, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.8, 0.25, 0.35)), metal, Vector3(0, 0.62, 0))
		"ring":
			MeshLib.part(root, MeshLib.torus(5.6, 6.0), MeshLib.mat(Color(0.75, 0.65, 0.45)), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE, false)
			for i in 6:
				var a := TAU * i / 6.0
				MeshLib.part(root, MeshLib.cyl(0.08, 0.08, 1.4, 5), wood, Vector3(cos(a) * 6, 0.7, sin(a) * 6))
		"ritual_circle":
			MeshLib.part(root, MeshLib.torus(2.6, 2.9), MeshLib.glow(Color(0.7, 0.2, 1.0), 2.5), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE, false)
			MeshLib.part(root, MeshLib.cyl(2.6, 2.6, 0.02, 20), MeshLib.mat(Color(0.4, 0.1, 0.6, 0.35), 0.0, 1.0, 1.0, true), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3.ONE, false)
			for i in 5:
				var a2 := TAU * i / 5.0
				MeshLib.part(root, MeshLib.cyl(0.05, 0.05, 0.3, 5), MeshLib.mat(Color(0.95, 0.92, 0.8)), Vector3(cos(a2) * 2.75, 0.15, sin(a2) * 2.75))
			var l2 := OmniLight3D.new()
			l2.light_color = Color(0.7, 0.3, 1.0)
			l2.light_energy = 1.5
			l2.omni_range = 7.0
			l2.position.y = 1.0
			l2.shadow_enabled = false
			root.add_child(l2)
		"huge_print":
			for i in 3:
				MeshLib.part(root, MeshLib.cyl(0.45, 0.45, 0.02, 8), MeshLib.mat(Color(0.18, 0.13, 0.08, 0.8)), Vector3(i * 0.2 - 0.2, 0.02, -i * 1.6), Vector3.ZERO, Vector3(1.0, 1, 1.5), false)
		"bones":
			var bm := MeshLib.mat(Color(0.9, 0.87, 0.78))
			for i in 7:
				MeshLib.part(root, MeshLib.cyl(0.05, 0.04, randf_range(0.4, 0.9), 5), bm, Vector3(randf_range(-1.5, 1.5), 0.05, randf_range(-1.5, 1.5)), Vector3(0, randf() * 180.0, 90))
			MeshLib.part(root, MeshLib.sphere(0.18, 8, 5), bm, Vector3(0.4, 0.15, 0.3))
		"cursed_glow":
			MeshLib.part(root, MeshLib.cyl(1.2, 1.2, 0.02, 16), MeshLib.mat(Color(0.5, 0.1, 0.7, 0.35), 0.0, 1.0, 1.5, true), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
			MeshLib.part(root, MeshLib.box(Vector3(0.9, 0.55, 0.6)), MeshLib.mat(Color(0.25, 0.15, 0.25)), Vector3(0, 0.28, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.92, 0.06, 0.62)), MeshLib.glow(Color(0.7, 0.2, 1.0), 2.0), Vector3(0, 0.5, 0))
		"anomaly":
			MeshLib.part(root, MeshLib.torus(0.9, 1.1), MeshLib.glow(Color(0.4, 1.0, 0.9), 2.5), Vector3(0, 1.2, 0), Vector3(70, 0, 0), Vector3.ONE, false)
			var p2 := CPUParticles3D.new()
			p2.amount = 16
			p2.lifetime = 1.6
			p2.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p2.emission_sphere_radius = 1.2
			p2.gravity = Vector3(0, 0.4, 0)
			p2.mesh = MeshLib.box(Vector3(0.06, 0.06, 0.06))
			p2.material_override = MeshLib.mat(Color(0.4, 1.0, 0.9), 0.0, 1.0, 3.0, true)
			p2.position.y = 1.0
			root.add_child(p2)
		"ruin_pillars":
			var st := MeshLib.mat(Color(0.5, 0.48, 0.45))
			for i in 4:
				MeshLib.part(root, MeshLib.box(Vector3(0.8, randf_range(1.0, 3.0), 0.8)), st, Vector3(randf_range(-4, 4), 0.8, randf_range(-4, 4)), Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)))
		"grave":
			MeshLib.part(root, MeshLib.box(Vector3(0.7, 0.9, 0.18)), MeshLib.mat(Color(0.55, 0.55, 0.58)), Vector3(0, 0.45, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.9, 0.2, 1.8)), MeshLib.mat(Color(0.32, 0.25, 0.18)), Vector3(0, 0.1, 0.9))
		"scorch":
			MeshLib.part(root, MeshLib.cyl(1.6, 1.6, 0.01, 12), MeshLib.mat(Color(0.08, 0.07, 0.06, 0.7)), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
		"burnt":
			MeshLib.part(root, MeshLib.cyl(1.0, 1.0, 0.01, 10), MeshLib.mat(Color(0.1, 0.09, 0.08, 0.75)), Vector3(0, 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
			for i in 4:
				MeshLib.part(root, MeshLib.box(Vector3(randf_range(0.4, 0.9), 0.08, 0.12)), MeshLib.mat(Color(0.1, 0.08, 0.07)), Vector3(randf_range(-0.7, 0.7), 0.05, randf_range(-0.7, 0.7)), Vector3(0, randf() * 180.0, 0))
		_:
			if kind.begins_with("banner_"):
				var fid := kind.substr(7)
				var fc: Color = DBEras.faction(fid).get("color", Color(0.6, 0.6, 0.6))
				MeshLib.part(root, MeshLib.cyl(0.05, 0.05, 2.6, 5), wood, Vector3(0, 1.3, 0), Vector3(0, 0, 12))
				MeshLib.part(root, MeshLib.box(Vector3(0.7, 0.9, 0.03)), MeshLib.mat(fc), Vector3(0.45, 2.1, 0), Vector3(0, 0, 12))
			else:
				MeshLib.part(root, MeshLib.box(Vector3(0.6, 0.6, 0.6)), wood, Vector3(0, 0.3, 0))
	return root

## Generic interactable for encounters (works with the player's interact scan).
class Spot:
	extends Node3D
	var label := "Осмотреть"
	var interact_radius := 2.6
	var on_interact: Callable
	var active := true
	var _reg := false
	var _t := 0.0
	func _ready() -> void:
		call_deferred("_register")
	func _register() -> void:
		if is_inside_tree() and not _reg:
			Game.grid.insert(self, global_position, "interact")
			_reg = true
	func _exit_tree() -> void:
		if _reg:
			Game.grid.remove(self, "interact")
			_reg = false
	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.3 and _reg:
			_t = 0.0
			var par = get_parent()
			if par is Actor and par.is_dead:
				active = false
			Game.grid.update(self, global_position, "interact")
	func can_interact(_a = null) -> bool:
		return active
	func interact_label() -> String:
		return label
	func interact(a) -> void:
		if active and on_interact.is_valid():
			on_interact.call(a)
