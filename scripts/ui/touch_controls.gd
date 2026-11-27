class_name TouchControls
extends Control
## Multi-touch mobile controls.
##  - Left stick with a FIXED base: only the knob moves, clamped to the
##    radius; sensitivity and dead zone from settings; releasing recentres
##    it and stops the hero. The base never follows the finger.
##  - Right side: attack (drag to aim), block, dodge, up to three skills
##    (only those actually available), contextual interact, swap, potion,
##    companion. Vector icons, no text placeholders.
##  - Every finger is tracked independently (move + attack + skill at once);
##    everything is released when a window opens, a teleport happens or the
##    app loses focus, so nothing gets stuck.
##  - Layout editor mode: drag/resize elements; positions are stored as
##    fractions of the safe area in Settings.ui_layout.

const ELEMENTS := ["joystick", "attack", "block", "dodge", "skill1", "skill2", "skill3", "skill4", "skill_page", "interact", "swap", "potion", "companion"]
const ELEMENT_NAMES := {"joystick": "Джойстик", "attack": "Атака", "block": "Блок", "dodge": "Рывок", "skill1": "Умение 1", "skill2": "Умение 2",
	"skill3": "Умение 3", "skill4": "Умение 4", "skill_page": "Страница умений", "interact": "Взаимодействие", "swap": "Смена оружия", "potion": "Зелье", "companion": "Спутник"}
const BASE_R := {"attack": 76.0, "skill1": 44.0, "skill2": 44.0, "skill3": 44.0, "skill4": 40.0, "skill_page": 26.0, "dodge": 46.0, "block": 44.0, "interact": 48.0, "swap": 30.0, "potion": 30.0, "companion": 30.0}

var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var buttons := {}            # name -> {pos, r, held, finger, queued, visible}
var _joy_finger := -1
var _joy_base := Vector2.ZERO    # fixed centre of the stick
var _joy_knob := Vector2.ZERO
var _joy_radius := 85.0
var _font: Font
var _t := 0.0
var _safe := Rect2()
# layout editor
var edit_mode := false
var preview := false             # draw without a live player (editor from the main menu)
var selected := ""
var edit_ignore_rect := Rect2()
var _drag_finger := -2
var _drag_off := Vector2.ZERO
signal element_selected(nm: String)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/PT_Sans-Web-Bold.ttf"):
		_font = load("res://assets/fonts/PT_Sans-Web-Bold.ttf")
	for b in ELEMENTS:
		if b == "joystick":
			continue
		buttons[b] = {"pos": Vector2.ZERO, "r": 40.0, "held": false, "finger": -1, "queued": false, "visible": true}
	Events.input_reset.connect(reset)
	get_viewport().size_changed.connect(_layout)
	Events.settings_changed.connect(_layout)
	_layout()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_VISIBILITY_CHANGED]:
		if not buttons.is_empty():
			reset()

# ------------------------------------------------------------------ layout
func default_layout(sz: Vector2) -> Dictionary:
	var safe := _safe_rect(sz)
	var bs: float = Settings.button_size
	var out := {}
	out["joystick"] = Vector2(safe.position.x + 150.0 * Settings.joystick_size, safe.end.y - 150.0 * Settings.joystick_size)
	var ac := Vector2(safe.end.x - 125.0 * bs, safe.end.y - 125.0 * bs)
	out["attack"] = ac
	for o in [["skill1", 222.0], ["skill2", 254.0], ["skill3", 286.0]]:
		var a := deg_to_rad(o[1])
		out[o[0]] = ac + Vector2(cos(a), sin(a)) * 172.0 * bs
	out["skill4"] = ac + Vector2(-148.0, -237.0) * bs
	out["skill_page"] = ac + Vector2(-215.0, -205.0) * bs
	out["dodge"] = ac + Vector2(-172.0, 38.0) * bs
	out["block"] = ac + Vector2(-282.0, 44.0) * bs
	out["interact"] = ac + Vector2(-268.0, -112.0) * bs
	var small_y := ac.y - 262.0 * bs
	out["swap"] = Vector2(safe.end.x - 36.0 * bs, small_y)
	out["potion"] = Vector2(safe.end.x - 104.0 * bs, small_y)
	out["companion"] = Vector2(safe.end.x - 172.0 * bs, small_y)
	return out

func _layout() -> void:
	var sz := get_viewport_rect().size
	_safe = _safe_rect(sz)
	var def := default_layout(sz)
	for nm in ELEMENTS:
		var p: Vector2 = def[nm]
		var sc := 1.0
		var o = Settings.ui_layout.get(nm)
		if o is Dictionary:
			if o.has("x") and o.has("y"):
				p = _safe.position + Vector2(float(o.x), float(o.y)) * _safe.size
			sc = clampf(float(o.get("s", 1.0)), 0.5, 1.8)
		if nm == "joystick":
			_joy_base = p
			_joy_radius = 85.0 * Settings.joystick_size * sc
			if _joy_finger == -1:
				_joy_knob = _joy_base
		else:
			buttons[nm].pos = p
			buttons[nm].r = BASE_R[nm] * Settings.button_size * sc
	queue_redraw()

func _safe_rect(sz: Vector2) -> Rect2:
	var r := Rect2(Vector2(24, 16), sz - Vector2(48, 32))
	if OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var ws := DisplayServer.window_get_size()
		if ws.x > 0 and sa.size.x > 0:
			var k := sz.x / float(ws.x)
			r = Rect2(Vector2(sa.position) * k + Vector2(16, 12), Vector2(sa.size) * k - Vector2(32, 24))
	return r

func element_pos(nm: String) -> Vector2:
	return _joy_base if nm == "joystick" else buttons[nm].pos

func element_radius(nm: String) -> float:
	return _joy_radius if nm == "joystick" else buttons[nm].r

## Stores an element's position (and optionally scale) in the settings.
func set_element(nm: String, pos: Vector2, scale = null) -> void:
	var cur = Settings.ui_layout.get(nm)
	var o: Dictionary = cur.duplicate() if cur is Dictionary else {}
	var r := element_radius(nm)
	pos.x = clampf(pos.x, _safe.position.x + r * 0.6, _safe.end.x - r * 0.6)
	pos.y = clampf(pos.y, _safe.position.y + r * 0.6, _safe.end.y - r * 0.6)
	var f := (pos - _safe.position) / _safe.size
	o["x"] = snappedf(f.x, 0.0001)
	o["y"] = snappedf(f.y, 0.0001)
	if scale != null:
		o["s"] = clampf(float(scale), 0.5, 1.8)
	Settings.ui_layout[nm] = o
	_layout()

func element_scale(nm: String) -> float:
	var o = Settings.ui_layout.get(nm)
	return float(o.get("s", 1.0)) if o is Dictionary else 1.0

func set_element_scale(nm: String, sc: float) -> void:
	set_element(nm, element_pos(nm), sc)

# ------------------------------------------------------------------ state
func reset() -> void:
	_joy_finger = -1
	_joy_knob = _joy_base
	move_vec = Vector2.ZERO
	aim_vec = Vector2.ZERO
	_drag_finger = -2
	for b in buttons:
		buttons[b].held = false
		buttons[b].finger = -1
		buttons[b].queued = false
	queue_redraw()

func is_held(nm: String) -> bool:
	return buttons.has(nm) and buttons[nm].held

## True once per press.
func consume(nm: String) -> bool:
	if buttons.has(nm) and buttons[nm].queued:
		buttons[nm].queued = false
		return true
	return false

func joystick_base() -> Vector2:
	return _joy_base

func joystick_radius() -> float:
	return _joy_radius

func _button_at(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for b in buttons:
		var bt: Dictionary = buttons[b]
		if not bt.visible:
			continue
		var d := p.distance_to(bt.pos)
		if d <= bt.r * 1.18 and d < bd:
			bd = d
			best = b
	return best

func _joy_zone(p: Vector2) -> bool:
	return p.distance_to(_joy_base) <= _joy_radius * 1.9

## Knob offset → movement vector with dead zone and sensitivity.
func _update_stick(finger_pos: Vector2) -> void:
	var off := finger_pos - _joy_base
	if off.length() > _joy_radius:
		off = off.normalized() * _joy_radius
	_joy_knob = _joy_base + off
	var raw := off / maxf(1.0, _joy_radius)
	var l := raw.length()
	var dz := clampf(Settings.joy_deadzone, 0.0, 0.6)
	if l <= dz:
		move_vec = Vector2.ZERO
	else:
		var k := clampf((l - dz) / (1.0 - dz) * Settings.joy_sensitivity, 0.0, 1.0)
		move_vec = raw.normalized() * k

# ------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if edit_mode:
		_edit_input(event)
		return
	if Game.ui_is_open() or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		var p := e.position
		if e.pressed:
			var b := _button_at(p)
			if b != "":
				buttons[b].held = true
				buttons[b].finger = e.index
				buttons[b].queued = true
				if Settings.vibration and OS.has_feature("mobile") and b == "attack":
					Input.vibrate_handheld(8)
			elif _joy_finger == -1 and _joy_zone(p):
				_joy_finger = e.index
				_update_stick(p)
		else:
			if e.index == _joy_finger:
				_joy_finger = -1
				_joy_knob = _joy_base
				move_vec = Vector2.ZERO
			for b in buttons:
				if buttons[b].finger == e.index:
					buttons[b].held = false
					buttons[b].finger = -1
					if b == "attack":
						aim_vec = Vector2.ZERO
		queue_redraw()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _joy_finger:
			_update_stick(d.position)
			queue_redraw()
		elif buttons.attack.finger == d.index:
			var off2: Vector2 = d.position - buttons.attack.pos
			aim_vec = off2.normalized() if off2.length() > buttons.attack.r * 0.35 else Vector2.ZERO
			queue_redraw()

func _element_at(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for nm in ELEMENTS:
		var d := p.distance_to(element_pos(nm))
		if d <= element_radius(nm) * 1.3 + 8.0 and d < bd:
			bd = d
			best = nm
	return best

func _edit_input(event: InputEvent) -> void:
	var pressed := false
	var released := false
	var moved := false
	var p := Vector2.ZERO
	var idx := -1
	if event is InputEventScreenTouch:
		p = event.position
		idx = event.index
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		p = event.position
		idx = event.index
		moved = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position
		idx = -10
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and _drag_finger == -10:
		p = event.position
		idx = -10
		moved = true
	else:
		return
	if pressed:
		if edit_ignore_rect.has_point(p):
			return
		var nm := _element_at(p)
		if nm != "":
			selected = nm
			_drag_finger = idx
			_drag_off = element_pos(nm) - p
			element_selected.emit(nm)
			get_viewport().set_input_as_handled()
	elif moved and idx == _drag_finger and selected != "":
		set_element(selected, p + _drag_off)
		get_viewport().set_input_as_handled()
	elif released and idx == _drag_finger:
		_drag_finger = -2
	queue_redraw()

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	_t += delta
	var pl = Game.player
	if edit_mode or preview:
		for b in buttons:
			buttons[b].visible = true
		queue_redraw()
		return
	if pl and is_instance_valid(pl):
		buttons.interact.visible = pl.interact_target != null and is_instance_valid(pl.interact_target)
		buttons.companion.visible = pl.companion != null and is_instance_valid(pl.companion) and not pl.companion.is_dead
		# skill buttons exist only for techniques/spells that are actually available
		var slots: Array = pl.data.active_slots(pl.mastery_cat()) if pl.data else []
		var any := false
		for sid in slots:
			any = any or String(sid) != ""
		buttons.skill_page.visible = pl.data != null and (any or pl.data.ab_page == 1)
		for i in 4:
			var nm := "skill%d" % (i + 1)
			var vis: bool = i < slots.size() and String(slots[i]) != "" and (i < 3 or pl.data.slot_count() >= 4)
			if not vis and buttons[nm].held:
				buttons[nm].held = false
				buttons[nm].finger = -1
			buttons[nm].visible = vis
	queue_redraw()

func _a(c: Color) -> Color:
	return Color(c.r, c.g, c.b, c.a * clampf(Settings.ui_opacity, 0.2, 1.0))

func _draw() -> void:
	var pl = Game.player
	var live: bool = pl != null and is_instance_valid(pl) and not (edit_mode or preview)
	if not live and not (edit_mode or preview):
		return
	# fixed joystick base, knob inside
	var engaged := _joy_finger != -1
	draw_circle(_joy_base, _joy_radius, _a(Color(0, 0, 0, 0.32 if engaged else 0.22)))
	draw_arc(_joy_base, _joy_radius, 0, TAU, 48, _a(Color(1, 1, 1, 0.5 if engaged else 0.32)), 3.0, true)
	draw_arc(_joy_base, _joy_radius * maxf(0.08, Settings.joy_deadzone), 0, TAU, 24, _a(Color(1, 1, 1, 0.12)), 1.5, true)
	var kp := _joy_knob if engaged else _joy_base
	draw_circle(kp, _joy_radius * 0.42, _a(Color(1, 1, 1, 0.55 if engaged else 0.35)))
	draw_arc(kp, _joy_radius * 0.42, 0, TAU, 32, _a(Color(0, 0, 0, 0.35)), 2.0, true)
	var slots: Array = pl.data.active_slots(pl.mastery_cat()) if live and pl.data else ["", "", "", ""]
	for b in buttons:
		var bt: Dictionary = buttons[b]
		if not bt.visible:
			continue
		var c: Vector2 = bt.pos
		var r: float = bt.r
		var col := Color(0.06, 0.07, 0.1, 0.5)
		var ring := Color(0.95, 0.8, 0.45, 0.8)
		var icon := ""
		var icol := Color(1, 1, 1, 0.95)
		var badge := ""
		var cd_frac := 0.0
		var enabled := true
		match b:
			"attack":
				icon = Icons.for_weapon(pl.weapon_cat()) if live else "sword"
				ring = Color(1.0, 0.55, 0.35, 0.95)
				if live:
					var wb: Dictionary = pl.weapon_base()
					if wb.has("mag"):
						badge = "…" if pl.reload_t > 0.0 else "%d" % pl.ammo
			"block":
				icon = "shield"
			"dodge":
				icon = "dodge"
				if live and pl.dodge_cd > 0.0:
					cd_frac = pl.dodge_cd / 0.9
			"interact":
				icon = "hand"
				ring = Color(0.5, 1.0, 0.6, 0.95)
			"swap":
				icon = "swap"
			"potion":
				icon = "potion"
				ring = Color(1.0, 0.35, 0.35, 0.9)
				if live:
					badge = "%d" % pl.potion_count()
					enabled = pl.potion_count() > 0
			"skill_page":
				icon = "swap"
				ring = Color(0.7, 0.8, 1.0, 0.9)
				if live and pl.data:
					badge = "%d" % (pl.data.ab_page + 1)
			"companion":
				icon = "paw"
				if live:
					badge = {"follow": "→", "attack": "!", "hold": "■"}.get(pl.companion_mode, "?")
			_:
				if not live:
					icon = ["fire", "lightning", "whirl", "star"][int(b.substr(5)) - 1]
				else:
					var idx := int(b.substr(5)) - 1
					var id: String = slots[idx] if idx < slots.size() else ""
					if id == "":
						continue
					var spd := DBSkills.spell(id)
					var sk := DBSkills.find_skill(id)
					icon = Icons.for_skill(id)
					var total: float = spd.get("cd", sk.get("cd", 1.0))
					cd_frac = pl.cooldown_of(id) / maxf(0.1, total)
					var ae: Dictionary = DBAbilities.get_ab(id)
					if not ae.is_empty():
						ring = SpellVFX.col(ae) if ae.kind == "spell" else Color(1.0, 0.75, 0.4, 0.9)
						enabled = pl.mana >= AbilityExec.mana_cost(pl, ae) and pl.stamina >= float(ae.get("stamina", 0.0))
						if int(ae.get("tier", 0)) >= 5:
							badge = ["", "", "", "", "", "V", "VI"][int(ae.tier)]
					elif not spd.is_empty():
						ring = DBSkills.SCHOOLS[spd.school].color
						enabled = pl.mana >= spd.mana
					else:
						ring = Color(1.0, 0.75, 0.4, 0.9)
		if bt.held:
			col = Color(0.3, 0.25, 0.15, 0.7)
		if not enabled:
			ring = Color(0.5, 0.5, 0.5, 0.5)
			icol = Color(0.7, 0.7, 0.7, 0.55)
		draw_circle(c, r, _a(col))
		draw_arc(c, r, 0, TAU, 40, _a(ring), 3.0 if b != "attack" else 4.0, true)
		Icons.draw(self, icon, c, r * (0.5 if b == "attack" else 0.56), _a(icol))
		if cd_frac > 0.03:
			var pts := PackedVector2Array([c])
			var steps := 24
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * minf(cd_frac, 0.999) * float(i) / steps
				pts.append(c + Vector2(cos(a), sin(a)) * (r - 3.0))
			draw_colored_polygon(pts, _a(Color(0, 0, 0, 0.55)))
		if badge != "":
			var bp := c + Vector2(r * 0.62, r * 0.62)
			draw_circle(bp, 13.0, _a(Color(0, 0, 0, 0.75)))
			var tw := _font.get_string_size(badge, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
			draw_string(_font, bp + Vector2(-tw.x * 0.5, 5.5), badge, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(1, 1, 1, 0.95))
		if b == "interact" and live:
			var il: String = pl.interact_label()
			var tw2 := _font.get_string_size(il, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
			var rp := c + Vector2(-tw2.x * 0.5, -r - 14)
			draw_rect(Rect2(rp - Vector2(10, 20), tw2 + Vector2(20, 10)), Color(0, 0, 0, 0.65))
			draw_string(_font, rp, il, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.8, 1.0, 0.8))
	# aim indicator
	if aim_vec.length() > 0.1:
		var ac: Vector2 = buttons.attack.pos
		draw_line(ac, ac + aim_vec * (buttons.attack.r + 40.0), Color(1, 0.6, 0.3, 0.9), 4.0)
	if edit_mode:
		for nm in ELEMENTS:
			var ep := element_pos(nm)
			var er := element_radius(nm)
			var sel: bool = nm == selected
			draw_arc(ep, er + 6.0, 0, TAU, 40, Color(1.0, 0.85, 0.3, 0.95) if sel else Color(1, 1, 1, 0.35), 3.0 if sel else 1.5, true)
			var lbl: String = ELEMENT_NAMES.get(nm, nm)
			var tw3 := _font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
			draw_string(_font, ep + Vector2(-tw3.x * 0.5, er + 22.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.8, 0.95 if sel else 0.7))
