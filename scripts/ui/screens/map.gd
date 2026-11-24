extends UIScreen
## World map: overview texture, markers, player arrow; drag to pan, pinch /
## buttons to zoom, tap a marker to see its name.

var _view: MapView
var _info: Label
var _legend: VBoxContainer

class MapView extends Control:
	var tex: Texture2D = null
	var half := 1280.0
	var markers: Array = []
	var zoom := 1.0
	var pan := Vector2.ZERO          # world-space centre (x, z)
	var on_pick: Callable
	var _touches := {}
	var _pinch_d := 0.0
	var _drag_moved := 0.0
	var _press_pos := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func base_scale() -> float:
		return minf(size.x, size.y) / (half * 2.0)

	func world_to_screen(w: Vector2) -> Vector2:
		return size * 0.5 + (w - pan) * base_scale() * zoom

	func screen_to_world(s: Vector2) -> Vector2:
		return pan + (s - size * 0.5) / (base_scale() * zoom)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.07))
		var tl := world_to_screen(Vector2(-half, -half))
		var br := world_to_screen(Vector2(half, half))
		if tex:
			draw_texture_rect(tex, Rect2(tl, br - tl), false)
		else:
			draw_rect(Rect2(tl, br - tl), Color(0.18, 0.24, 0.16))
			var f := UITheme.font("body")
			draw_string(f, size * 0.5 - Vector2(160, 0), "Карта недоступна вне игрового мира", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UITheme.TEXT_DIM)
		draw_rect(Rect2(tl, br - tl), UITheme.GOLD_DIM, false, 2.0)
		# grid
		var step := 256.0
		var gx := -half
		while gx <= half:
			var a := world_to_screen(Vector2(gx, -half))
			var b := world_to_screen(Vector2(gx, half))
			draw_line(a, b, Color(1, 1, 1, 0.05), 1.0)
			var c := world_to_screen(Vector2(-half, gx))
			var d := world_to_screen(Vector2(half, gx))
			draw_line(c, d, Color(1, 1, 1, 0.05), 1.0)
			gx += step
		var font := UITheme.font("bold")
		for m in markers:
			var p := world_to_screen(m.get("pos", Vector2.ZERO))
			var col: Color = m.get("color", Color.WHITE)
			var r := 7.0 if m.get("kind", "") not in ["settlement", "city", "capital"] else 10.0
			draw_circle(p, r + 2.0, Color(0, 0, 0, 0.7))
			draw_circle(p, r, col)
			if zoom >= 1.6 or m.get("kind", "") in ["settlement", "city", "capital", "quest", "trial"]:
				draw_string_outline(font, p + Vector2(r + 4, 6), str(m.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color(0, 0, 0, 0.85))
				draw_string(font, p + Vector2(r + 4, 6), str(m.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col.lightened(0.3))
		# player arrow
		if Game.player != null and is_instance_valid(Game.player):
			var pp: Vector3 = Game.player.global_position
			var fwd: Vector3 = Game.player.get("facing") if Game.player.get("facing") != null else Vector3(0, 0, -1)
			var c2 := world_to_screen(Vector2(pp.x, pp.z))
			var dir := Vector2(fwd.x, fwd.z).normalized()
			if dir.length() < 0.1:
				dir = Vector2(0, -1)
			var side := Vector2(-dir.y, dir.x)
			var tri := PackedVector2Array([c2 + dir * 16, c2 - dir * 10 + side * 10, c2 - dir * 5, c2 - dir * 10 - side * 10])
			draw_colored_polygon(tri, Color(1, 1, 1))
			draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0, 0, 0), 2.0)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventScreenTouch:
			if ev.pressed:
				_touches[ev.index] = ev.position
				if _touches.size() == 1:
					_drag_moved = 0.0
					_press_pos = ev.position
				if _touches.size() == 2:
					var k := _touches.keys()
					_pinch_d = _touches[k[0]].distance_to(_touches[k[1]])
			else:
				_touches.erase(ev.index)
				if _touches.is_empty() and _drag_moved < 12.0:
					_pick(ev.position)
			accept_event()
		elif ev is InputEventScreenDrag:
			_touches[ev.index] = ev.position
			if _touches.size() >= 2:
				var k2 := _touches.keys()
				var d: float = _touches[k2[0]].distance_to(_touches[k2[1]])
				if _pinch_d > 0.0:
					set_zoom(zoom * d / _pinch_d)
				_pinch_d = d
				_drag_moved += 99.0
			else:
				pan -= ev.relative / (base_scale() * zoom)
				_drag_moved += ev.relative.length()
				_clamp()
				queue_redraw()
			accept_event()
		elif ev is InputEventMouseButton and ev.device != InputEvent.DEVICE_ID_EMULATION:
			if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
				set_zoom(zoom * 1.2)
			elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
				set_zoom(zoom / 1.2)
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					_drag_moved = 0.0
				elif _drag_moved < 8.0:
					_pick(ev.position)
		elif ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
			pan -= ev.relative / (base_scale() * zoom)
			_drag_moved += ev.relative.length()
			_clamp()
			queue_redraw()

	func set_zoom(z: float) -> void:
		zoom = clampf(z, 1.0, 8.0)
		_clamp()
		queue_redraw()

	func _clamp() -> void:
		pan.x = clampf(pan.x, -half, half)
		pan.y = clampf(pan.y, -half, half)

	func _pick(pos: Vector2) -> void:
		var best = null
		var bd := 30.0
		for m in markers:
			var d := world_to_screen(m.get("pos", Vector2.ZERO)).distance_to(pos)
			if d < bd:
				bd = d
				best = m
		if on_pick.is_valid():
			on_pick.call(best)

func build() -> void:
	make_frame("Карта мира — " + DBEras.era(Profile.current_era).name)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	_view = MapView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_view)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 280
	row.add_child(side)
	var zr := HBoxContainer.new()
	side.add_child(zr)
	zr.add_child(UITheme.button("+", func(): _view.set_zoom(_view.zoom * 1.5), 56, 80))
	zr.add_child(UITheme.button("−", func(): _view.set_zoom(_view.zoom / 1.5), 56, 80))
	zr.add_child(UITheme.button("Я", _center_player, 56, 80))
	_info = UITheme.wrap_label("Нажмите на метку, чтобы узнать название.", 17, UITheme.TEXT)
	_info.custom_minimum_size = Vector2(260, 70)
	side.add_child(_info)
	side.add_child(UITheme.separator())
	_legend = VBoxContainer.new()
	side.add_child(UITheme.scroll(_legend))
	_view.on_pick = func(m):
		if m == null:
			_info.text = "Здесь ничего не отмечено."
		else:
			var d := ""
			if has_player():
				var pp: Vector3 = Game.player.global_position
				d = " — %d м" % roundi(Vector2(pp.x, pp.z).distance_to(m.get("pos", Vector2.ZERO)))
			_info.text = "%s%s" % [m.get("name", "?"), d]
	refresh()
	_center_player()

func refresh() -> void:
	var tex = null
	if Game.world != null and is_instance_valid(Game.world):
		if Game.world.has_method("map_texture"):
			tex = Game.world.map_texture()
		if Game.world.get("world_half") != null:
			_view.half = float(Game.world.world_half)
		if Game.world.has_method("map_markers"):
			var mk = Game.world.map_markers()
			_view.markers = mk if mk is Array else []
	_view.tex = tex
	clear(_legend)
	var kinds := {}
	for m in _view.markers:
		var k: String = m.get("kind", "")
		if not kinds.has(k):
			kinds[k] = m.get("color", Color.WHITE)
	var names := {"settlement": "Поселения", "city": "Города", "capital": "Столица", "camp": "Лагеря", "lair": "Логова боссов", "trial": "Суд Хроноса",
		"rift": "Разломы", "cp": "Контрольные точки", "dungeon": "Подземелья", "altar": "Алтари", "quest": "Цели заданий", "fortress": "Крепость",
		"shrine": "Святилища", "event": "События", "legend": "Легенды", "ruins": "Руины", "witness": "Свидетель", "mirror": "Зеркала", "forge": "Мастерские"}
	for k in kinds:
		var r := HBoxContainer.new()
		r.add_child(UITheme.swatch(kinds[k], Vector2(16, 16)))
		r.add_child(UITheme.label(names.get(k, k), 16, UITheme.TEXT))
		_legend.add_child(r)
	_view.queue_redraw()

func _center_player() -> void:
	if has_player():
		var pp: Vector3 = Game.player.global_position
		_view.pan = Vector2(pp.x, pp.z)
		if _view.zoom < 2.0:
			_view.set_zoom(2.5)
	_view.queue_redraw()

func _process(_dt: float) -> void:
	if _view and is_visible_in_tree():
		_view.queue_redraw()
