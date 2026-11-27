class_name BeastDungeon
extends Node3D
## One of the 25 «Beasts of the Ages» dungeons, generated from prepared room
## and corridor modules on a grid, by a seed.
##
## Layout: a main path (start → … → boss arena) by a seeded walk, side
## branches (treasure, traps, resources, a miniboss, a safe room, a secret
## room behind a breakable wall). The main path and the boss arena come from
## the dungeon's own seed (its architecture is always the same); branches,
## traps, chests and the enemy mix change with every visit.
## Checks: every room reachable from the start (BFS), the boss reachable,
## the way out reachable, doors on both sides of every passage, chests only
## inside rooms. Progress (cleared rooms, opened chests, boss) is saved in
## Game.world_state.dungeons and restored on the next visit.
## Rooms fill with their creatures only when the hero walks in (lazy), and
## everything is freed on leaving.

const CELL := 22.0
const ROOM := 15.0
const WALL_H := 2.7          # low enough for the over-the-shoulder camera
const DOOR := 4.2
const LIP := 0.8             # visible height of the walls on the camera side (south)

var dungeon_id := ""
var def := {}
var era := 0
var seed_base := 0
var visit := 0
var rooms := {}              # Vector2i -> room
var order: Array = []        # main path cells
var center := Vector3.ZERO
var radius := 60.0
var floor_y := 0.0
var title := ""
var subtitle := ""
var sky_top := Color(0.04, 0.04, 0.05)
var sky_horizon := Color(0.1, 0.1, 0.1)
var light := Color(1.0, 0.8, 0.6)     # the world "sun" colour while inside (dimmed)
var room_light := Color(1.0, 0.8, 0.6)
var player_spawn := Vector3.ZERO
var done := false
var boss = null
var boss_spawned := false
var exits: Array = []
var chests: Array = []
var secret_wall = null
var traps: Array = []
var stats := {"rooms": 0, "spawned": 0, "visited": 0, "chests": 0, "secret": false, "traps": 0, "amb": 0, "decals": 0, "resources": 0}
var report := {}             # validation results (tests)
var expedition := false      # the world's death handler: dungeon loot is never lost
var extra_bosses: Array = []  # other bosses of this dungeon (in a side hall)
var _t := 0.0
var _amb_t := 3.0
var _mat_floor: Material
var _mat_wall: Material
var _mat_accent: Material

# ------------------------------------------------------------------ build
func build_dungeon(id: String, offset: Vector3, opts: Dictionary = {}) -> void:
	dungeon_id = id
	def = DBBeasts.dungeon(id)
	era = int(def.era)
	title = def.name
	subtitle = DBBeasts.boss(def.boss).get("name", "")
	var st: Dictionary = state()
	seed_base = int(st.get("seed", hash(str(Profile.world_seed) + id)))
	st.seed = seed_base
	visit = int(st.get("visits", 0)) + int(opts.get("visit_bump", 1))
	st.visits = visit
	# underground: dark sky (ambient), a dim "sun"; rooms are lit by their own lamps
	sky_top = Color(0.01, 0.01, 0.012)
	sky_horizon = Color(def.wall).darkened(0.82)
	room_light = def.light
	light = Color(def.light).darkened(0.62)
	_mat_floor = MeshLib.mat(def.floor, 0.0, 0.95)
	_mat_wall = MeshLib.mat(def.wall, 0.0, 0.95)
	_mat_accent = MeshLib.mat(Color(def.wall).darkened(0.25), 0.0, 0.9)
	floor_y = offset.y
	for bb in DBBeasts.bosses().values():
		if str(bb.get("dungeon", "")) == id and str(bb.id) != str(def.boss):
			extra_bosses.append(str(bb.id))
	_layout()
	report = validate()
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for c in rooms:
		minp = minp.min(Vector2(c.x, c.y))
		maxp = maxp.max(Vector2(c.x, c.y))
	center = offset + Vector3((minp.x + maxp.x) * 0.5 * CELL, 0, (minp.y + maxp.y) * 0.5 * CELL)
	radius = maxf(40.0, (maxp - minp).length() * CELL * 0.5 + CELL)
	# the rock mass around the rooms: a dark floor far below the camera's view
	var rock := MeshLib.part(self, MeshLib.box(Vector3((maxp.x - minp.x) * CELL + 240.0, 0.2, (maxp.y - minp.y) * CELL + 240.0)),
		MeshLib.mat(Color(def.wall).darkened(0.86), 0.0, 1.0), Vector3(center.x - offset.x, -0.7, center.z - offset.z) + offset - global_position)
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in rooms:
		_build_room(offset, rooms[c])
	var start: Dictionary = rooms[order[0]]
	player_spawn = start.pos + Vector3(0, 0.4, 3.0)
	var ex := Dimension.DimensionExit.new()
	ex.dim = self
	add_child(ex)
	ex.global_position = start.pos + Vector3(0, 0, ROOM * 0.35)
	exits.append(ex)
	stats.rooms = rooms.size()

func state() -> Dictionary:
	if not Game.world_state.has("dungeons"):
		Game.world_state["dungeons"] = {}
	var all: Dictionary = Game.world_state.dungeons
	if not all.has(dungeon_id):
		all[dungeon_id] = {"cleared": [], "opened": [], "boss_dead": false, "visits": 0, "secret": false, "extra_dead": []}
	var st: Dictionary = all[dungeon_id]
	for k in ["opened", "cleared", "extra_dead"]:
		if not st.has(k):
			st[k] = []
	return st

func _key(c: Vector2i) -> String:
	return "%d_%d" % [c.x, c.y]

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const AMBIENCE := {"factory": ["steam_burst", "growl_far", "elec_crackle"], "furnace": ["steam_burst", "cave_wind"], "gears": ["step_metal", "growl_far"],
	"electric": ["elec_crackle", "dark_hum"], "lab": ["dark_hum", "elec_crackle", "growl_far"], "bunker": ["dark_hum", "growl_far"],
	"anomaly": ["resonance_hum", "time_warp", "dark_hum"], "astral": ["resonance_hum", "cave_wind"], "nest": ["drip", "buzz", "shriek"],
	"crypt": ["cave_wind", "growl_far", "drip"], "carnival": ["dark_hum", "growl_far"], "flooded": ["drip", "drip", "cave_wind"]}

func _layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base
	var total := int(def.get("rooms", 9))
	var main_len := maxi(4, int(total * 0.6))
	var cur := Vector2i(0, 0)
	order = [cur]
	rooms[cur] = {"cell": cur, "type": "start", "links": []}
	var guard := 0
	while order.size() < main_len and guard < 400:
		guard += 1
		var dirs: Array = DIRS.duplicate()
		for i in range(dirs.size() - 1, 0, -1):
			var j := rng.randi() % (i + 1)
			var tmp = dirs[i]
			dirs[i] = dirs[j]
			dirs[j] = tmp
		# prefer going "deeper" (−z) so the dungeon has a direction
		if rng.randf() < 0.6:
			dirs.erase(Vector2i(0, -1))
			dirs.push_front(Vector2i(0, -1))
		var moved := false
		for d in dirs:
			var nx: Vector2i = cur + d
			if rooms.has(nx):
				continue
			rooms[nx] = {"cell": nx, "type": "hall", "links": [cur]}
			rooms[cur].links.append(nx)
			cur = nx
			order.append(cur)
			moved = true
			break
		if not moved:
			# dead end: step back along the path and try again
			cur = order[rng.randi() % order.size()]
	rooms[order[order.size() - 1]].type = "boss"
	if order.size() > 3:
		rooms[order[order.size() / 2]].type = "fork"
	# branches vary with the visit (architecture of the main path stays)
	var brng := RandomNumberGenerator.new()
	brng.seed = seed_base ^ (visit * 7919)
	var branch_types := ["treasure", "trap", "resources", "miniboss", "safe", "secret", "trap", "treasure"]
	var bi := 0
	guard = 0
	while rooms.size() < total and guard < 300:
		guard += 1
		var from: Vector2i = order[1 + brng.randi() % maxi(1, order.size() - 2)]
		if rooms[from].type in ["boss", "start"]:
			continue
		var d2: Vector2i = DIRS[brng.randi() % 4]
		var nc: Vector2i = from + d2
		if rooms.has(nc):
			continue
		var tp: String = branch_types[bi % branch_types.size()]
		bi += 1
		rooms[nc] = {"cell": nc, "type": tp, "links": [from]}
		rooms[from].links.append(nc)
	# a guaranteed secret room
	var has_secret := false
	for c in rooms:
		if rooms[c].type == "secret":
			has_secret = true
	if not has_secret:
		for c in rooms.keys():
			if rooms[c].type in ["treasure", "resources"]:
				rooms[c].type = "secret"
				break
	for c in rooms:
		var r: Dictionary = rooms[c]
		r.cleared = _key(c) in state().cleared
		r.spawned = false

## Graph checks: everything reachable from the start, boss reachable,
## passages symmetric (a door on both sides).
func validate() -> Dictionary:
	var seen := {order[0]: true}
	var q: Array = [order[0]]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for n in rooms[c].links:
			if not seen.has(n):
				seen[n] = true
				q.append(n)
	var sym := true
	for c in rooms:
		for n in rooms[c].links:
			if not rooms.has(n) or not c in rooms[n].links:
				sym = false
	var boss_cell: Vector2i = order[order.size() - 1]
	return {"rooms": rooms.size(), "reachable": seen.size(), "all_reachable": seen.size() == rooms.size(),
		"boss_reachable": seen.has(boss_cell), "doors_symmetric": sym, "exit_reachable": seen.has(order[0])}

# ------------------------------------------------------------------ geometry
## vis_h > 0: the visible block is only that tall (camera-side walls are a low
## lip so they never hide the hero), the collision keeps the full height.
func _static_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y := 0.0, vis_h := -1.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = Actor.LAYER_WORLD
	sb.collision_mask = 0
	parent.add_child(sb)
	sb.position = pos
	sb.rotation.y = rot_y
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var vs := size
	var vo := Vector3.ZERO
	if vis_h > 0.0 and vis_h < size.y:
		vs.y = vis_h
		vo.y = -(size.y - vis_h) * 0.5
	var mi := MeshLib.part(sb, MeshLib.box(vs), mat, vo)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sb

func _build_room(offset: Vector3, r: Dictionary) -> void:
	var c: Vector2i = r.cell
	var node := Node3D.new()
	node.name = "Room_%s" % _key(c)
	add_child(node)
	var pos := offset + Vector3(c.x * CELL, 0, c.y * CELL)
	node.global_position = pos
	r.pos = pos
	r.node = node
	var size := ROOM * (1.5 if r.type == "boss" else 1.0)
	r.size = size
	# floor and ceiling-less walls with door gaps toward linked rooms
	_static_box(node, Vector3(size, 0.6, size), Vector3(0, -0.3, 0), _mat_floor)
	var half := size * 0.5
	for d in DIRS:
		var linked: bool = (c + d) in r.links
		var horizontal: bool = d.y != 0
		var wall_pos := Vector3(d.x * half, WALL_H * 0.5, d.y * half)
		if linked:
			var seg := (size - DOOR) * 0.5
			for s in [-1.0, 1.0]:
				var off: float = s * (DOOR * 0.5 + seg * 0.5)
				var p := wall_pos + (Vector3(off, 0, 0) if horizontal else Vector3(0, 0, off))
				_static_box(node, Vector3(seg, WALL_H, 0.8) if horizontal else Vector3(0.8, WALL_H, seg), p, _mat_wall, 0.0, LIP if d.y > 0 else -1.0)
			# corridor to the neighbour (built once, from the lower cell)
			if d.x > 0 or d.y > 0:
				var gap := CELL - (size + ROOM * (1.5 if rooms[c + d].type == "boss" else 1.0)) * 0.5
				var mid := Vector3(d.x, 0, d.y) * (half + gap * 0.5)
				_static_box(node, Vector3(gap + 1.0, 0.6, DOOR + 1.6) if not horizontal else Vector3(DOOR + 1.6, 0.6, gap + 1.0), mid + Vector3(0, -0.3, 0), _mat_floor)
				for s2 in [-1.0, 1.0]:
					var cw := mid + (Vector3(0, WALL_H * 0.5, s2 * (DOOR * 0.5 + 0.4)) if not horizontal else Vector3(s2 * (DOOR * 0.5 + 0.4), WALL_H * 0.5, 0))
					_static_box(node, Vector3(gap + 1.0, WALL_H, 0.8) if not horizontal else Vector3(0.8, WALL_H, gap + 1.0), cw, _mat_wall, 0.0, LIP if (not horizontal and s2 > 0.0) else -1.0)
				# the secret room hides behind a cracked, breakable wall
				if rooms[c + d].type == "secret" or r.type == "secret":
					_secret_wall(node, mid, horizontal)
		else:
			_static_box(node, Vector3(size, WALL_H, 0.8) if horizontal else Vector3(0.8, WALL_H, size), wall_pos, _mat_wall, 0.0, LIP if d.y > 0 else -1.0)
	_decorate(node, r)
	# one light per room (no shadows)
	var l := OmniLight3D.new()
	l.light_color = room_light
	l.light_energy = 2.0 if r.type != "boss" else 2.8
	l.omni_range = size * 0.9
	l.shadow_enabled = false
	node.add_child(l)
	l.position = Vector3(0, WALL_H - 0.3, 0)
	_room_content_static(node, r)

func _secret_wall(node: Node3D, mid: Vector3, horizontal: bool) -> void:
	if secret_wall != null and is_instance_valid(secret_wall):
		return
	if state().get("secret", false):
		stats.secret = true
		return
	var w := SecretWall.new()
	w.dungeon = self
	node.add_child(w)
	w.position = mid
	w.setup(Vector3(DOOR + 0.6, WALL_H, 1.0) if horizontal else Vector3(1.0, WALL_H, DOOR + 0.6), _mat_wall)
	secret_wall = w

## Theme dressing with real collisions, kept out of doorways and the centre.
func _decorate(node: Node3D, r: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_key(r.cell)) ^ seed_base
	var theme: String = def.theme
	var n := 3 if r.type != "boss" else 6
	var spread: float = r.size * 0.38
	for i in n:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(spread * 0.55, spread)
		# not in front of a door
		var bad := false
		for d in DIRS:
			if (r.cell + d) in r.links:
				var door_p: Vector3 = Vector3(d.x, 0, d.y) * float(r.size) * 0.5
				if p.distance_to(door_p) < 4.5:
					bad = true
		if bad:
			continue
		match theme:
			"cave", "mine", "hall":
				var h := rng.randf_range(1.5, 3.5)
				_static_box(node, Vector3(1.2, h, 1.2), p + Vector3(0, h * 0.5, 0), _mat_accent, rng.randf() * TAU)
			"nest":
				var web := MeshLib.part(node, MeshLib.sphere(1.0, 8, 6), MeshLib.mat(Color(0.9, 0.9, 0.88, 0.5), 0.0, 1.0, 0.2, true), p + Vector3(0, 1.0, 0))
				web.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"crypt", "flooded", "carnival":
				_static_box(node, Vector3(0.9, WALL_H, 0.9), p + Vector3(0, WALL_H * 0.5, 0), _mat_accent)
			"lab", "lab_old", "bunker":
				_static_box(node, Vector3(1.6, 0.9, 0.8), p + Vector3(0, 0.45, 0), _mat_accent, rng.randf() * TAU)
			"factory", "furnace", "gears", "electric":
				_static_box(node, Vector3(1.0, 2.5, 1.0), p + Vector3(0, 1.25, 0), MeshLib.mat(Color(0.35, 0.33, 0.3), 0.6, 0.4))
			_:
				var cr := MeshLib.part(node, MeshLib.cyl(0.0, 0.5, 2.2, 5), MeshLib.glow(light, 1.5), p + Vector3(0, 1.1, 0))
				cr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# claw marks and cracks on the floor (signs of the inhabitants)
	if r.type in ["hall", "fork", "boss", "miniboss"]:
		for i in (3 if r.type == "boss" else 2):
			var cp: Vector3 = r.pos + Vector3(rng.randf_range(-4, 4), 0.02, rng.randf_range(-4, 4))
			BeastWorld.claw_mark(node, cp, rng.randf() * TAU, 1.6 if r.type == "boss" else 1.1)
			stats.decals += 1

## Chests, resources, traps (placed at build; enemies come on entry).
func _room_content_static(node: Node3D, r: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_base ^ (visit * 31)) + hash(_key(r.cell))
	var st := state()
	match r.type:
		"treasure", "secret", "boss":
			if r.type != "boss":
				_chest(r, Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5)), "rich" if r.type == "secret" else "normal")
		"resources":
			for i in 3:
				var it := ItemDB.create(["iron_ore", "herbs", "crystal_shard", "beast_hide"][rng.randi() % 4], 0, 1)
				if Game.world and Game.world.get("loot") != null:
					Game.world.loot.spawn_drop(it, r.pos + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)))
					stats.resources += 1
		"trap", "hall", "fork":
			var trap_kinds: Array = def.get("traps", ["spikes"])
			if r.type == "trap" or rng.randf() < 0.35:
				for i in (3 if r.type == "trap" else 1):
					var tr := DungeonTrap.new()
					tr.kind = trap_kinds[rng.randi() % trap_kinds.size()]
					tr.dungeon = self
					tr.position = Vector3(rng.randf_range(-4.5, 4.5), 0.05, rng.randf_range(-4.5, 4.5))
					node.add_child(tr)
					traps.append(tr)
					stats.traps += 1

func _chest(r: Dictionary, local: Vector3, tier: String) -> void:
	# chests are keyed by room; an opened one stays open on the next visit
	var uid := "%s_%s" % [dungeon_id, _key(r.cell)]
	var ch := Chest.new()
	ch.configure(uid, state(), era, tier, Game.world.spawner.level_near_player(2) if Game.world else 3, 1.0)
	r.node.add_child(ch)
	# inside the room, away from walls
	var lim: float = r.size * 0.5 - 1.5
	local.x = clampf(local.x, -lim, lim)
	local.z = clampf(local.z, -lim, lim)
	ch.position = local
	ch.set_meta("dungeon_chest", uid)
	chests.append(ch)
	stats.chests += 1

func chest_inside_rooms() -> bool:
	for ch in chests:
		if not is_instance_valid(ch):
			continue
		var ok := false
		for c in rooms:
			var r: Dictionary = rooms[c]
			var lp: Vector3 = ch.global_position - r.pos
			if absf(lp.x) < r.size * 0.5 - 0.8 and absf(lp.z) < r.size * 0.5 - 0.8:
				ok = true
		if not ok:
			return false
	return true

# ------------------------------------------------------------------ runtime
func room_at(p: Vector3) -> Dictionary:
	for c in rooms:
		var r: Dictionary = rooms[c]
		var lp: Vector3 = p - r.pos
		if absf(lp.x) < r.size * 0.5 and absf(lp.z) < r.size * 0.5:
			return r
	return {}

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.3:
		return
	_t = 0.0
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	var r := room_at(pl.global_position)
	if not r.is_empty() and not r.spawned:
		_enter_room(r)
	_amb_t -= 0.3
	if _amb_t <= 0.0:
		_amb_t = randf_range(3.0, 7.0)
		var amb: Array = AMBIENCE.get(str(def.theme), ["drip", "drip", "cave_wind", "growl_far"])
		var snd: String = amb[randi() % amb.size()]
		stats.amb += 1
		Audio.play_sfx(snd, pl.global_position + Vector3(randf_range(-10, 10), 2, randf_range(-10, 10)), -10.0)
	# room cleared?
	for c in rooms:
		var rr: Dictionary = rooms[c]
		if rr.spawned and not rr.cleared and rr.has("mobs"):
			var alive := 0
			for m in rr.mobs:
				if is_instance_valid(m) and not m.is_dead:
					alive += 1
			if alive == 0:
				rr.cleared = true
				var k := _key(c)
				if not k in state().cleared:
					state().cleared.append(k)

func _enter_room(r: Dictionary) -> void:
	r.spawned = true
	stats.visited += 1
	r.mobs = []
	if r.type == "boss":
		_spawn_boss(r)
		return
	if r.cleared or r.type in ["start", "safe"]:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_base ^ (visit * 131)) + hash(_key(r.cell))
	var pool: Array = def.pool
	var n := 0
	match r.type:
		"hall", "fork":
			n = rng.randi_range(2, 4)
		"trap", "resources", "treasure":
			n = rng.randi_range(1, 2)
		"secret", "miniboss":
			n = 1
	var lvl: int = Game.world.spawner.level_near_player(2) if Game.world else 3
	# a side hall may hold the dungeon's second boss (e.g. the Bone Devourer)
	if r.type == "miniboss":
		for xb in extra_bosses:
			if not xb in state().extra_dead:
				var b2 = Game.world.spawner.spawn_boss(xb, r.pos + Vector3(0, 0.5, -2.0), Game.world.spawner.level_near_player(3))
				if b2:
					b2.arena_center = r.pos
					b2.leash_radius = r.size * 0.5 + 4.0
					b2.can_escape = false
					b2.lair_id = dungeon_id
					r.mobs.append(b2)
					stats.spawned += 1
					return
	for i in n:
		var id: String = pool[rng.randi() % pool.size()]
		if r.type == "miniboss" and str(def.get("miniboss", "")) != "":
			id = def.miniboss
		var p: Vector3 = r.pos + Vector3(rng.randf_range(-4.5, 4.5), 0.3, rng.randf_range(-4.5, 4.5))
		var m = Game.world.spawner.spawn_enemy(id, p, lvl + (2 if r.type == "miniboss" else 0))
		if m:
			if m.get("home") != null:
				m.home = r.pos
			if m.get("leash") != null:
				m.leash = r.size
			m.set_meta("dungeon", dungeon_id)
			BeastWorld.maybe_variant(m, rng)
			r.mobs.append(m)
			stats.spawned += 1

## The lord of the dungeon wakes up when the hero enters its hall: a short
## awakening (dust, roar, title card) during which the hero keeps full
## control; the boss starts fighting after ~1.6 s or at once if attacked.
func _spawn_boss(r: Dictionary) -> void:
	if boss_spawned or state().get("boss_dead", false):
		if state().get("boss_dead", false) and exits.size() < 2:
			_open_exit(r)
		return
	boss_spawned = true
	var bid: String = def.boss
	var bd: Dictionary = DBBeasts.boss(bid)
	var b = Game.world.spawner.spawn_boss(bid, r.pos + Vector3(0, 0.5, -r.size * 0.25), Game.world.spawner.level_near_player(3))
	if b == null:
		return
	b.arena_center = r.pos
	b.leash_radius = r.size * 0.5 + 4.0
	b.can_escape = false
	b.lair_id = dungeon_id
	boss = b
	r.mobs.append(b)
	if Game.player:
		b.face_dir((Game.player.global_position - b.global_position).normalized())
	# awakening: the brain waits, the hero does not
	if b.brain != null:
		b.brain.dormant = 1.6
	VFX.burst(b.global_position + Vector3(0, 1.0, 0), Color(def.wall).lightened(0.2), 24, 0.5)
	VFX.shake(0.35)
	Audio.play_sfx("rock_crumble", b.global_position)
	Audio.play_sfx("boss_roar", b.global_position)
	Audio.play_music("boss")
	var cine = Game.world.sys("cinematic") if Game.world else null
	if cine != null:
		cine.play("boss", b.display_name, String(bd.get("desc", "")), "cine_beast_" + bid, b.global_position + Vector3(0, 2.0, 0))
	else:
		Events.banner.emit(b.display_name, String(bd.get("desc", "")), Color(1.0, 0.45, 0.3))
	b.engaged = true
	Events.boss_engaged.emit(b)

## Called by World._on_boss_defeated after the boss's loot.
func on_boss_killed(b) -> void:
	if b == null or not is_instance_valid(b):
		return
	var bid: String = str(b.get("boss_id"))
	var killer = b.get("last_attacker")
	BeastWorld.on_boss_defeated(bid, b.global_position, killer)
	if bid != str(def.boss):
		if not bid in state().extra_dead:
			state().extra_dead.append(bid)
		return
	state().boss_dead = true
	done = true
	var r: Dictionary = rooms[order[order.size() - 1]]
	_open_exit(r)
	Chronicle.record("dungeon_cleared", [Game.player], {"extra": {"dungeon": title}})
	Audio.play_music("rift")

func _open_exit(r: Dictionary) -> void:
	var ex := Dimension.DimensionExit.new()
	ex.dim = self
	add_child(ex)
	ex.global_position = r.pos + Vector3(0, 0, r.size * 0.3)
	exits.append(ex)

func finish_and_leave() -> void:
	if Game.world:
		Game.world.leave_dimension(true)

func objective_text() -> String:
	if state().get("boss_dead", false):
		return "Хозяин подземелья повержен — выход открыт"
	return "Найдите логово: %s" % subtitle

func target_pos():
	return rooms[order[order.size() - 1]].pos if not order.is_empty() else null

# ------------------------------------------------------------------ pieces
## A cracked wall: break it (any damage) to reveal the secret room.
class SecretWall:
	extends StaticBody3D
	var dungeon
	var hp := 60.0
	var hit_radius := 2.6
	func setup(size: Vector3, mat: Material) -> void:
		collision_layer = Actor.LAYER_DESTRUCT
		collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		add_child(cs)
		cs.position.y = size.y * 0.5
		var mi := MeshLib.part(self, MeshLib.box(size), mat, Vector3(0, size.y * 0.5, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# a visible hint: a crack across the stones
		MeshLib.part(self, MeshLib.box(Vector3(0.08, size.y * 0.7, 0.05)), MeshLib.mat(Color(0.1, 0.1, 0.1)), Vector3(0.2, size.y * 0.5, -size.z * 0.51), Vector3(0, 0, 20), Vector3.ONE, false)
		Game.grid.insert_deferred(self, "destructible")
	func _exit_tree() -> void:
		Game.grid.remove(self, "destructible")
	func take_hit(amount: float, _dtype: String = "blunt", _src = null) -> void:
		hp -= amount
		VFX.burst(global_position + Vector3(0, 1.5, 0), Color(0.5, 0.45, 0.4), 6, 0.25)
		if hp <= 0.0:
			if dungeon and is_instance_valid(dungeon):
				dungeon.state().secret = true
				dungeon.stats.secret = true
			VFX.burst(global_position + Vector3(0, 1.5, 0), Color(0.5, 0.45, 0.4), 20, 0.4)
			Audio.play_sfx("wood_break", global_position)
			Events.notify.emit("Скрытый проход!", Color(1.0, 0.85, 0.4))
			queue_free()

## A trap: announced (telegraph), then it acts; persistent kinds are zones.
class DungeonTrap:
	extends Node3D
	var kind := "spikes"
	var dungeon
	var period := 3.5
	var _t := 0.0
	var triggered := 0
	var _zone = null
	func _exit_tree() -> void:
		if _zone != null and is_instance_valid(_zone):
			_zone.queue_free()
	func _ready() -> void:
		_t = randf() * period
		var c := Color(0.6, 0.55, 0.5)
		match kind:
			"poison", "gas", "web", "water", "timeslow", "steam":
				var zk: String = {"poison": "dark", "gas": "dark", "web": "mud", "water": "mud", "timeslow": "timeslow", "steam": "fire"}[kind]
				var info := {"amount": 4.0 if kind in ["poison", "gas", "steam"] else 0.0, "dtype": "poison" if kind != "steam" else "fire", "status": {"slow": 0.5} if kind in ["web", "water"] else {}}
				_zone = Zone.create(zk, null, global_position, 2.2, 9999.0, info, {"no_res": true, "hostile_all": true})
			_:
				MeshLib.part(self, MeshLib.cyl(1.1, 1.1, 0.05, 12), MeshLib.mat(c.darkened(0.3)), Vector3(0, 0.03, 0))
	func _process(delta: float) -> void:
		if kind in ["poison", "gas", "web", "water", "timeslow", "steam"]:
			return
		_t += delta
		if _t < period:
			return
		_t = 0.0
		var pl = Game.player
		if pl == null or not is_instance_valid(pl) or pl.global_position.distance_to(global_position) > 18.0:
			return
		var col := Color(1.0, 0.5, 0.2) if kind in ["fire", "rocks", "spikes", "blades"] else Color(0.6, 0.8, 1.0)
		VFX.telegraph(global_position, 1.2, 0.8, col)
		get_tree().create_timer(0.8, false).timeout.connect(func():
			if not is_instance_valid(self):
				return
			triggered += 1
			var dt: String = {"fire": "fire", "lightning": "lightning", "lasers": "energy", "rocks": "blunt", "blades": "slash", "spikes": "pierce", "roots": "blunt", "illusion": "dark"}.get(kind, "pierce")
			match kind:
				"rocks":
					VFX.ground_impact(global_position, 1.3)
				"lightning", "lasers":
					VFX.lightning(global_position + Vector3(0, 3, 0), global_position, col, 0.2, 0.06, 1)
				"fire":
					VFX.explosion(global_position, 1.2, col)
				_:
					VFX.burst(global_position, col, 8, 0.3)
			for a in Game.actors_near(global_position, 1.6):
				if a.is_dead or a.team in ["monster", "boss", "wildlife"]:
					continue
				var st := {"root": 1.0} if kind == "roots" else ({"burn": 4.0} if kind == "fire" else {})
				Combat.deal(null, a, {"amount": 12.0 + 6.0 * (dungeon.era if dungeon else 0), "dtype": dt, "status": st, "knock": 2.0}))
