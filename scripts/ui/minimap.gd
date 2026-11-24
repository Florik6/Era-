class_name Minimap
extends Control
## Square minimap: world overview texture around the player plus live markers
## (enemies, contenders, allies, bosses, points of interest, quest target).

var view_m := 150.0
var _t := 0.0
var _font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			if Game.world and Game.world.ui:
				Game.world.ui.open("map"))

func _process(delta: float) -> void:
	_t += delta
	if _t > 0.15:
		_t = 0.0
		queue_redraw()

func _w2m(p: Vector3, center: Vector3, sz: Vector2) -> Vector2:
	var d := Vector2(p.x - center.x, p.z - center.z) / view_m
	return sz * 0.5 + d * sz.x * 0.5

func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.05, 0.07, 0.75))
	var pl = Game.player
	var w = Game.world
	if pl == null or not is_instance_valid(pl) or w == null:
		return
	var c: Vector3 = pl.global_position
	if w.has_method("map_texture"):
		var tex: Texture2D = w.map_texture()
		if tex:
			var half: float = w.world_half
			var tsz := tex.get_size()
			var px_per_m := tsz.x / (half * 2.0)
			var src := Rect2((c.x + half - view_m) * px_per_m, (c.z + half - view_m) * px_per_m, view_m * 2.0 * px_per_m, view_m * 2.0 * px_per_m)
			draw_texture_rect_region(tex, Rect2(Vector2.ZERO, sz), src, Color(1, 1, 1, 0.9))
	# markers
	if w.has_method("map_markers"):
		for m in w.map_markers(true):
			var mp := _w2m(Vector3(m.pos.x, 0, m.pos.y), c, sz)
			if Rect2(Vector2.ZERO, sz).has_point(mp):
				draw_circle(mp, 4.0, m.color)
	for a in Game.actors_near(c, view_m):
		if a == pl or a.is_dead:
			continue
		var col := Color(0.9, 0.9, 0.9)
		var r := 2.5
		if a.kind == "boss":
			col = Color(1.0, 0.1, 0.1)
			r = 6.0
		elif Game.is_enemy(pl, a):
			col = Color(1.0, 0.3, 0.25)
		elif a.team == "bot":
			col = Color(1.0, 0.85, 0.3) if not a.record.get("legend", false) else Color(1.0, 0.6, 0.0)
			r = 3.0 if not a.record.get("legend", false) else 4.5
		elif a.team == "player" or (a.faction_id != "" and a.faction_id == pl.faction_id):
			col = Color(0.4, 1.0, 0.5)
		else:
			continue
		var mp2 := _w2m(a.global_position, c, sz)
		if Rect2(Vector2.ZERO, sz).has_point(mp2):
			draw_circle(mp2, r, col)
	# quest target
	if w.has_method("quest_target"):
		var qt = w.quest_target()
		if qt != null:
			var qp := _w2m(qt, c, sz)
			qp = qp.clamp(Vector2(6, 6), sz - Vector2(6, 6))
			draw_circle(qp, 6.0, Color(1.0, 0.9, 0.2))
			draw_arc(qp, 8.0, 0, TAU, 16, Color(0, 0, 0), 2.0)
	# player arrow
	var center := sz * 0.5
	var f: Vector3 = pl.facing
	var ang := atan2(f.z, f.x)
	var tip := center + Vector2(cos(ang), sin(ang)) * 9.0
	var l := center + Vector2(cos(ang + 2.5), sin(ang + 2.5)) * 6.0
	var rr := center + Vector2(cos(ang - 2.5), sin(ang - 2.5)) * 6.0
	draw_colored_polygon(PackedVector2Array([tip, l, rr]), Color(1, 1, 1))
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.9, 0.75, 0.4, 0.8), false, 2.0)
