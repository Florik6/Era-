class_name Tracking
extends Node
## Tracking: trails of marks (footprints, drag marks, huge prints, magic
## residue, blood) that lead to REAL objects — bandit camps, boss lairs,
## dens, stashes, survivors, rifts. Marks appear progressively ahead of the
## hero; archers and rogues read them further, and the tracking skill grows
## with every trail followed. From the industrial era a scanner highlights
## them (holographic marks + distance on the HUD objective line).
## Ambient fresh tracks near the hero's path start new trails by themselves.
## API: start_trail(from, to, kind, opts{label,on_reach}), start_bounty(pos),
##      active_trails() -> [{points, target, label, kind}], skill()

const KIND_COL := {"footprints": Color(0.28, 0.22, 0.16), "drag": Color(0.3, 0.24, 0.18), "huge": Color(0.22, 0.17, 0.12),
	"magic": Color(0.7, 0.45, 1.0), "blood": Color(0.55, 0.06, 0.06), "tire": Color(0.15, 0.15, 0.15)}
const KIND_NAME := {"footprints": "Следы ног", "drag": "Следы волочения", "huge": "Огромные отпечатки", "magic": "Магический след", "blood": "Кровавый след", "tire": "Колея"}

var world
var trails: Array = []
var _t := 0.0
var _amb_t := 60.0
var _ambient_spot: Node3D = null

func setup(w) -> void:
	world = w
	if not Game.world_state.has("tracking"):
		Game.world_state["tracking"] = {"skill": 0, "followed": 0}

func skill() -> int:
	return int(Game.world_state.get("tracking", {}).get("skill", 0))

## How far ahead marks are revealed (class + skill + era tech).
func reveal_range() -> float:
	var r := 22.0 + skill() * 2.5
	var cls: String = Profile.char.class_id if Profile.char else ""
	if cls in ["archer", "rogue"]:
		r += 12.0
	if Profile.current_era >= 2:
		r += 10.0 * (Profile.current_era - 1)
	return minf(r, 90.0)

func _scanner() -> bool:
	return Profile.current_era >= 2

func start_trail(from: Vector3, to: Vector3, kind: String = "footprints", opts: Dictionary = {}) -> Dictionary:
	if world == null:
		return {}
	var pts: Array = []
	var d := Vector2(to.x - from.x, to.z - from.z)
	var n := maxi(3, int(d.length() / 4.0))
	var side := Vector2(-d.y, d.x).normalized()
	var seed_v := randf() * 10.0
	for i in n + 1:
		var k := float(i) / n
		var p := from.lerp(to, k)
		var wob := sin(k * 9.0 + seed_v) * minf(6.0, d.length() * 0.05) * (1.0 - absf(k - 0.5) * 2.0)
		p.x += side.x * wob
		p.z += side.y * wob
		pts.append(p)
	var tr := {"points": pts, "target": to, "kind": kind, "label": opts.get("label", KIND_NAME.get(kind, "Следы")),
		"on_reach": opts.get("on_reach", Callable()), "marks": {}, "next": 0, "t": 0.0, "done": false}
	trails.append(tr)
	Events.notify.emit("%s: идите по следу (%d м)" % [tr.label, int(d.length())], Color(0.9, 0.8, 0.55))
	_reveal(tr)
	return tr

## A trail to the nearest bandit camp (bounty hunters, informants).
func start_bounty(pos: Vector3) -> Dictionary:
	var best = null
	var bd := INF
	for p in world.gen.pois if world.gen else []:
		if p.type != "camp":
			continue
		var dd: float = Vector2(pos.x, pos.z).distance_to(p.pos)
		if dd < bd and dd > 20.0:
			bd = dd
			best = p
	if best == null:
		return {}
	return start_trail(pos, Vector3(best.pos.x, 0, best.pos.y), "footprints", {"label": "След разыскиваемых"})

func active_trails() -> Array:
	return trails.filter(func(t): return not t.done)

## Nearest unrevealed target of the active trail (for the objective/HUD).
func current_target():
	for t in trails:
		if not t.done:
			return t.target
	return null

func _process(delta: float) -> void:
	if world == null or world.player == null or not is_instance_valid(world.player) or world.dimension != "":
		return
	_t += delta
	if _t < 0.4:
		return
	var dt := _t
	_t = 0.0
	var pp: Vector3 = world.player.global_position
	for tr in trails.duplicate():
		tr.t += dt
		if tr.done:
			continue
		_reveal(tr)
		var tg: Vector3 = tr.target
		if Vector2(pp.x - tg.x, pp.z - tg.z).length() < 7.0:
			_reach(tr)
		elif tr.t > 900.0 or Vector2(pp.x - tg.x, pp.z - tg.z).length() > 600.0:
			tr.done = true
			_clear_marks(tr)
	trails = trails.filter(func(t): return not (t.done and t.marks.is_empty()))
	_amb_t -= dt
	if _amb_t <= 0.0:
		_amb_t = randf_range(150.0, 260.0)
		_ambient_tracks()

func _reveal(tr: Dictionary) -> void:
	var pp: Vector3 = world.player.global_position
	var rr := reveal_range()
	var pts: Array = tr.points
	# marks within reveal range of the hero, up to 14 alive at once
	for i in pts.size():
		var p: Vector3 = pts[i]
		var near: bool = Vector2(p.x - pp.x, p.z - pp.z).length() < rr
		if near and not tr.marks.has(i) and tr.marks.size() < 14:
			tr.marks[i] = _make_mark(tr, p, pts[mini(i + 1, pts.size() - 1)] - p)
		elif not near and tr.marks.has(i) and Vector2(p.x - pp.x, p.z - pp.z).length() > rr + 20.0:
			var m = tr.marks[i]
			if is_instance_valid(m):
				m.queue_free()
			tr.marks.erase(i)

func _make_mark(tr: Dictionary, p: Vector3, dir: Vector3) -> Node3D:
	var n := Node3D.new()
	world.fx_root.add_child(n)
	p.y = world.ground_height(p) + 0.04
	n.global_position = p
	if dir.length() > 0.01:
		n.rotation.y = atan2(dir.x, dir.z)
	var kind: String = tr.kind
	var c: Color = KIND_COL.get(kind, Color(0.3, 0.25, 0.2))
	var glow := _scanner() or kind == "magic"
	var mat: Material = MeshLib.glow(Color(0.35, 0.85, 1.0) if _scanner() and kind != "magic" else c.lightened(0.2), 1.6) if glow else MeshLib.mat(c)
	match kind:
		"huge":
			for t in [Vector3(-0.5, 0, 0), Vector3(0.6, 0, 1.4)]:
				MeshLib.part(n, MeshLib.box(Vector3(0.9, 0.02, 1.3)), mat, t)
				for k in 3:
					MeshLib.part(n, MeshLib.box(Vector3(0.18, 0.02, 0.35)), mat, t + Vector3(-0.3 + k * 0.3, 0, 0.85))
		"drag", "tire":
			MeshLib.part(n, MeshLib.box(Vector3(0.25, 0.015, 3.2)), mat, Vector3(-0.35, 0, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.25, 0.015, 3.2)), mat, Vector3(0.35, 0, 0))
		"blood":
			for k in 3:
				MeshLib.part(n, MeshLib.cyl(0.12 + k * 0.04, 0.12 + k * 0.04, 0.015, 8), mat, Vector3(randf_range(-0.4, 0.4), 0, k * 0.9))
		"magic":
			MeshLib.part(n, MeshLib.torus(0.28, 0.36), mat, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			MeshLib.part(n, MeshLib.box(Vector3(0.08, 0.015, 0.4)), mat, Vector3(0, 0, 0))
		_:
			MeshLib.part(n, MeshLib.box(Vector3(0.2, 0.015, 0.36)), mat, Vector3(-0.18, 0, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.2, 0.015, 0.36)), mat, Vector3(0.18, 0, 1.1))
	for c2 in n.get_children():
		if c2 is GeometryInstance3D:
			c2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c2.visibility_range_end = 70.0
	return n

func _clear_marks(tr: Dictionary) -> void:
	for k in tr.marks:
		var m = tr.marks[k]
		if is_instance_valid(m):
			var tw: Tween = m.create_tween()
			tw.tween_property(m, "scale", Vector3.ONE * 0.05, 0.6)
			tw.tween_callback(m.queue_free)
	tr.marks.clear()

func _reach(tr: Dictionary) -> void:
	tr.done = true
	_clear_marks(tr)
	var st: Dictionary = Game.world_state.tracking
	st.followed = int(st.get("followed", 0)) + 1
	if st.followed % 2 == 0:
		st.skill = int(st.get("skill", 0)) + 1
		Events.notify.emit("Навык следопыта: %d" % st.skill, Color(0.7, 1.0, 0.7))
	world.player.gain_xp(25 + 10 * Profile.current_era)
	Events.notify.emit("%s привёл к цели" % tr.label, Color(0.9, 0.85, 0.6))
	var cb: Callable = tr.on_reach
	if cb.is_valid():
		cb.call()

## Fresh tracks beside the hero's path lead to a real nearby object: a camp,
## a lair, ruins or a dungeon — or to a hidden stash that is placed for real.
func _ambient_tracks() -> void:
	if not trails.filter(func(t): return not t.done).is_empty():
		return
	if _ambient_spot and is_instance_valid(_ambient_spot):
		return
	var pl = world.player
	var pp: Vector3 = pl.global_position
	var target = null
	var kind := "footprints"
	var label := "Свежие следы"
	var bd := INF
	for p in world.gen.pois if world.gen else []:
		if not p.type in ["camp", "lair", "ruins", "dungeon", "shrine"]:
			continue
		var dd: float = Vector2(pp.x, pp.z).distance_to(p.pos)
		if dd > 60.0 and dd < 320.0 and dd < bd:
			bd = dd
			target = p
	var to: Vector3
	var stash := false
	if target != null:
		to = Vector3(target.pos.x, 0, target.pos.y)
		if target.type == "lair":
			kind = "huge"
			label = "Следы чудовища"
	else:
		var a := randf() * TAU
		to = pp + Vector3(cos(a), 0, sin(a)) * randf_range(70.0, 120.0)
		stash = true
		label = "Следы к тайнику"
	if Profile.current_era >= 3 and kind == "footprints":
		kind = "tire"
		label = "Колея" if not stash else label
	var fwd: Vector3 = pl.facing if pl.facing.length() > 0.1 else Vector3(0, 0, -1)
	var sp := pp + fwd * 9.0 + fwd.cross(Vector3.UP) * 3.0
	sp.y = world.ground_height(sp)
	var spot := Area3DSpot.new()
	spot.label = "Изучить: " + label
	spot.mark_col = KIND_COL.get(kind, Color(0.3, 0.25, 0.2))
	var k2 := kind
	var l2 := label
	var to2 := to
	spot.on_interact = func(_a):
		spot.queue_free()
		var opts := {"label": l2}
		if stash:
			opts["on_reach"] = func():
				if ResourceLoader.exists("res://scripts/world/chest.gd"):
					var ch = load("res://scripts/world/chest.gd").new()
					ch.set("tier", "rich")
					ch.set("lvl", world.spawner.level_near_player(1))
					world.fx_root.add_child(ch)
					var cp := to2
					cp.y = world.ground_height(cp)
					ch.global_position = cp
					Events.banner.emit("Тайник найден", "Следы привели к спрятанному сундуку.", Color(0.95, 0.85, 0.5))
		start_trail(sp, to2, k2, opts)
	world.fx_root.add_child(spot)
	spot.global_position = sp
	_ambient_spot = spot

## Small interactable used for ambient fresh tracks.
class Area3DSpot:
	extends Node3D
	var label := "Изучить следы"
	var interact_radius := 2.8
	var on_interact: Callable
	var mark_col := Color(0.3, 0.25, 0.2)
	var _life := 240.0
	func _ready() -> void:
		for i in 4:
			var m := MeshLib.part(self, MeshLib.box(Vector3(0.2, 0.015, 0.36)), MeshLib.mat(mark_col), Vector3(-0.2 + (i % 2) * 0.4, 0.03, i * 0.7 - 1.0))
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lb := Label3D.new()
		lb.text = "?"
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 48
		lb.pixel_size = 0.006
		lb.outline_size = 10
		lb.modulate = Color(1.0, 0.9, 0.6)
		lb.position.y = 1.2
		lb.visibility_range_end = 30.0
		add_child(lb)
		Game.grid.insert_deferred(self, "interact")
	func _exit_tree() -> void:
		Game.grid.remove(self, "interact")
	func _process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
	func interact_label() -> String:
		return label
	func interact(a) -> void:
		if a.is_player and on_interact.is_valid():
			on_interact.call(a)
