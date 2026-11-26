class_name Minimap
extends Control
## Readable minimap: terrain overview with roads and rivers, vector roads on
## top, discovered places with icons, active events and road encounters,
## active tracking trails, nearby enemies/bosses/allies, the selected
## quest target (clamped to the edge with an arrow when off-map) and the
## player arrow. Tap → full map.

var view_m := 140.0
var _t := 0.0
var _font: Font
var _pulse := 0.0
var _road_cache: Array = []
var _road_cache_ok := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/PT_Sans-Web-Bold.ttf"):
		_font = load("res://assets/fonts/PT_Sans-Web-Bold.ttf")
	gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			if Game.world and Game.world.ui:
				Game.world.ui.open("map"))

func _process(delta: float) -> void:
	_t += delta
	_pulse += delta
	if _t > 0.1:
		_t = 0.0
		queue_redraw()

func _w2m(p: Vector3, center: Vector3, sz: Vector2) -> Vector2:
	var d := Vector2(p.x - center.x, p.z - center.z) / view_m
	return sz * 0.5 + d * sz.x * 0.5

func _roads(w) -> Array:
	if not _road_cache_ok and w.gen and w.gen.has_method("road_polylines"):
		_road_cache = w.gen.road_polylines()
		_road_cache_ok = true
	return _road_cache

func _icon(kind: String, p: Vector2, col: Color) -> void:
	var dark := Color(0, 0, 0, 0.75)
	match kind:
		"settlement":
			draw_rect(Rect2(p + Vector2(-5, -2), Vector2(10, 7)), dark)
			draw_rect(Rect2(p + Vector2(-4, -1), Vector2(8, 5)), col)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-6, -1), p + Vector2(0, -7), p + Vector2(6, -1)]), col)
		"lair", "boss":
			draw_circle(p, 6.0, dark)
			draw_circle(p, 5.0, col)
			draw_circle(p + Vector2(-1.8, -0.5), 1.2, dark)
			draw_circle(p + Vector2(1.8, -0.5), 1.2, dark)
		"camp":
			draw_colored_polygon(PackedVector2Array([p + Vector2(-6, 4), p + Vector2(0, -6), p + Vector2(6, 4)]), dark)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-4.5, 3), p + Vector2(0, -4.5), p + Vector2(4.5, 3)]), col)
		"rift", "trial":
			draw_arc(p, 5.0, 0, TAU, 14, dark, 4.0)
			draw_arc(p, 5.0, 0, TAU, 14, col, 2.0)
		"event", "encounter":
			var s := 5.5 + sin(_pulse * 5.0) * 1.2
			draw_circle(p, s + 1.0, dark)
			draw_circle(p, s, col)
			var t := "!" if kind == "event" else "?"
			draw_string(_font, p + Vector2(-2.5, 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.1, 0.05, 0.0))
		"trail":
			draw_rect(Rect2(p + Vector2(-4, -3), Vector2(3, 5)), col)
			draw_rect(Rect2(p + Vector2(1, -1), Vector2(3, 5)), col)
		_:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), dark)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -3.8), p + Vector2(3.8, 0), p + Vector2(0, 3.8), p + Vector2(-3.8, 0)]), col)

func _draw() -> void:
	var sz := size
	var cen := sz * 0.5
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.05, 0.07, 0.8))
	var pl = Game.player
	var w = Game.world
	if pl == null or not is_instance_valid(pl) or w == null:
		return
	var c: Vector3 = pl.global_position
	var in_dim: bool = w.get("dimension") != null and w.dimension != ""
	if not in_dim and w.has_method("map_texture"):
		var tex: Texture2D = w.map_texture()
		if tex:
			var half: float = w.world_half
			var tsz := tex.get_size()
			var px_per_m := tsz.x / (half * 2.0)
			var src := Rect2((c.x + half - view_m) * px_per_m, (c.z + half - view_m) * px_per_m, view_m * 2.0 * px_per_m, view_m * 2.0 * px_per_m)
			draw_texture_rect_region(tex, Rect2(Vector2.ZERO, sz), src, Color(1, 1, 1, 0.95))
		# vector roads on top
		var k := sz.x / (view_m * 2.0)
		for r in _roads(w):
			var pts: PackedVector2Array = r.get("pts", PackedVector2Array())
			if pts.size() < 2:
				continue
			var lp := PackedVector2Array()
			for v in pts:
				lp.append(cen + (v - Vector2(c.x, c.z)) * k)
			var rw: float = clampf(float(r.get("w", 3.0)) * k, 1.5, 4.0)
			draw_polyline(lp, Color(0, 0, 0, 0.45), rw + 1.5)
			draw_polyline(lp, r.get("col", Color(0.86, 0.76, 0.55)), rw)
	elif in_dim and w.dim_node:
		var dn = w.dim_node
		var dc := _w2m(dn.center, c, sz)
		draw_circle(dc, dn.radius / view_m * sz.x * 0.5, Color(dn.sky_horizon.r, dn.sky_horizon.g, dn.sky_horizon.b, 0.35))
		draw_arc(dc, dn.radius / view_m * sz.x * 0.5, 0, TAU, 40, Color(dn.light.r, dn.light.g, dn.light.b, 0.8), 2.0)
	var rect := Rect2(Vector2(6, 6), sz - Vector2(12, 12))
	# places, events, encounters, trails
	if not in_dim and w.has_method("map_markers"):
		for m in w.map_markers(true):
			var mp := _w2m(Vector3(m.pos.x, 0, m.pos.y), c, sz)
			if rect.has_point(mp):
				_icon(m.kind, mp, m.color)
	if in_dim and w.dim_node:
		for an in w.dim_node.get("anchors") if w.dim_node.get("anchors") != null else []:
			if is_instance_valid(an):
				_icon("rift", _w2m(an.global_position, c, sz), Color(0.85, 0.6, 1.0))
	# actors
	for a in Game.actors_near(c, view_m):
		if a == pl or a.is_dead:
			continue
		var col := Color(0.9, 0.9, 0.9)
		var r := 2.6
		if a.kind == "boss":
			var bp := _w2m(a.global_position, c, sz)
			if rect.has_point(bp):
				_icon("boss", bp, Color(1.0, 0.15, 0.1))
			continue
		elif Game.is_enemy(pl, a):
			col = Color(1.0, 0.3, 0.25) if not a.elite else Color(1.0, 0.55, 0.2)
			r = 2.8 if not a.elite else 4.0
		elif a.team == "bot":
			col = Color(1.0, 0.85, 0.3) if not a.record.get("legend", false) else Color(1.0, 0.6, 0.0)
			r = 3.0 if not a.record.get("legend", false) else 4.5
		elif a.team == "player" or (a.faction_id != "" and a.faction_id == pl.faction_id):
			col = Color(0.4, 1.0, 0.5)
		else:
			continue
		var mp2 := _w2m(a.global_position, c, sz)
		if rect.has_point(mp2):
			draw_circle(mp2, r + 0.8, Color(0, 0, 0, 0.6))
			draw_circle(mp2, r, col)
	# quest target: star, clamped to the edge with a pointer
	if w.has_method("quest_target"):
		var qt = w.quest_target()
		if qt != null:
			var qp := _w2m(qt, c, sz)
			var inside := rect.has_point(qp)
			if not inside:
				var dir := (qp - cen).normalized()
				qp = cen + dir * (minf(sz.x, sz.y) * 0.5 - 10.0)
				var tip := qp + dir * 8.0
				draw_colored_polygon(PackedVector2Array([tip, qp + dir.rotated(2.4) * 6.0, qp + dir.rotated(-2.4) * 6.0]), Color(1.0, 0.85, 0.2))
			var pts: Array = []
			for i in 10:
				var rr := 7.0 if i % 2 == 0 else 3.2
				var ang := -PI * 0.5 + i * PI / 5.0
				pts.append(qp + Vector2(cos(ang), sin(ang)) * rr)
			draw_colored_polygon(PackedVector2Array(pts), Color(0, 0, 0, 0.7))
			var pts2 := PackedVector2Array()
			for v in pts:
				pts2.append(qp + (v - qp) * 0.78)
			draw_colored_polygon(pts2, Color(1.0, 0.88, 0.25))
	# player arrow
	var f: Vector3 = pl.facing
	var ang2 := atan2(f.z, f.x)
	var tip2 := cen + Vector2(cos(ang2), sin(ang2)) * 10.0
	var l := cen + Vector2(cos(ang2 + 2.5), sin(ang2 + 2.5)) * 7.0
	var rr2 := cen + Vector2(cos(ang2 - 2.5), sin(ang2 - 2.5)) * 7.0
	draw_colored_polygon(PackedVector2Array([tip2, l, cen, rr2]), Color(0, 0, 0, 0.6))
	draw_colored_polygon(PackedVector2Array([tip2 * 0.9 + cen * 0.1, l * 0.85 + cen * 0.15, cen, rr2 * 0.85 + cen * 0.15]), Color(1, 1, 1))
	# north marker + frame
	draw_string(_font, Vector2(sz.x * 0.5 - 4, 14), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.7))
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.9, 0.75, 0.4, 0.85), false, 2.0)
