class_name TouchControls
extends Control
## Multi-touch mobile controls: dynamic left joystick, right-side action
## buttons (attack with drag-to-aim, block, dodge, three skills, interact,
## weapon swap, potion, companion). Tracks each finger independently and
## releases everything when a window opens or the app loses focus, so no
## presses ever get stuck.

var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var buttons := {}            # name -> {pos, r, label, held, finger, queued, visible}
var _joy_finger := -1
var _joy_center := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _joy_radius := 85.0
var _font: Font
var _t := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/PT_Sans-Web-Bold.ttf"):
		_font = load("res://assets/fonts/PT_Sans-Web-Bold.ttf")
	for b in ["attack", "block", "dodge", "skill1", "skill2", "skill3", "interact", "swap", "potion", "companion"]:
		buttons[b] = {"pos": Vector2.ZERO, "r": 40.0, "label": "", "held": false, "finger": -1, "queued": false, "visible": true}
	Events.input_reset.connect(reset)
	get_viewport().size_changed.connect(_layout)
	Events.settings_changed.connect(_layout)
	_layout()

func _layout() -> void:
	var sz := get_viewport_rect().size
	var safe := _safe_rect(sz)
	var bs: float = Settings.button_size
	var ac := Vector2(safe.end.x - 125.0 * bs, safe.end.y - 125.0 * bs)
	buttons.attack.pos = ac
	buttons.attack.r = 76.0 * bs
	var ring := 150.0 * bs
	var order := [["dodge", 180.0], ["skill1", 207.0], ["skill2", 234.0], ["skill3", 261.0], ["block", 288.0]]
	for o in order:
		var a := deg_to_rad(o[1])
		buttons[o[0]].pos = ac + Vector2(cos(a), sin(a)) * ring
		buttons[o[0]].r = 44.0 * bs
	buttons.interact.pos = ac + Vector2(-260.0, -150.0) * bs
	buttons.interact.r = 50.0 * bs
	buttons.swap.pos = Vector2(safe.end.x - 46.0 * bs, ac.y - 225.0 * bs)
	buttons.swap.r = 32.0 * bs
	buttons.potion.pos = Vector2(safe.end.x - 46.0 * bs, ac.y - 300.0 * bs)
	buttons.potion.r = 32.0 * bs
	buttons.companion.pos = Vector2(safe.end.x - 46.0 * bs, ac.y - 375.0 * bs)
	buttons.companion.r = 30.0 * bs
	_joy_radius = 85.0 * Settings.joystick_size

func _safe_rect(sz: Vector2) -> Rect2:
	var r := Rect2(Vector2(24, 16), sz - Vector2(48, 32))
	if OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var ws := DisplayServer.window_get_size()
		if ws.x > 0 and sa.size.x > 0:
			var k := sz.x / float(ws.x)
			r = Rect2(Vector2(sa.position) * k + Vector2(16, 12), Vector2(sa.size) * k - Vector2(32, 24))
	return r

func reset() -> void:
	_joy_finger = -1
	move_vec = Vector2.ZERO
	aim_vec = Vector2.ZERO
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

func _input(event: InputEvent) -> void:
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
			elif p.x < get_viewport_rect().size.x * 0.5 and p.y > get_viewport_rect().size.y * 0.22 and _joy_finger == -1:
				_joy_finger = e.index
				_joy_center = p
				_joy_knob = p
				move_vec = Vector2.ZERO
		else:
			if e.index == _joy_finger:
				_joy_finger = -1
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
			var off := d.position - _joy_center
			if off.length() > _joy_radius:
				# floating joystick follows the finger
				_joy_center = d.position - off.normalized() * _joy_radius
				off = d.position - _joy_center
			_joy_knob = d.position
			move_vec = off / _joy_radius
			if move_vec.length() < 0.12:
				move_vec = Vector2.ZERO
			queue_redraw()
		elif buttons.attack.finger == d.index:
			var off2: Vector2 = d.position - buttons.attack.pos
			aim_vec = off2.normalized() if off2.length() > buttons.attack.r * 0.35 else Vector2.ZERO
			queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	var pl = Game.player
	if pl and is_instance_valid(pl):
		buttons.interact.visible = pl.interact_target != null and is_instance_valid(pl.interact_target)
		buttons.companion.visible = pl.companion != null and is_instance_valid(pl.companion) and not pl.companion.is_dead
	queue_redraw()

func _draw() -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	# joystick
	if _joy_finger != -1:
		draw_circle(_joy_center, _joy_radius, Color(0, 0, 0, 0.25))
		draw_arc(_joy_center, _joy_radius, 0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		var kp := _joy_center + move_vec * _joy_radius
		draw_circle(kp, _joy_radius * 0.42, Color(1, 1, 1, 0.45))
	else:
		var hint := Vector2(get_viewport_rect().size.x * 0.15, get_viewport_rect().size.y * 0.75)
		draw_arc(hint, _joy_radius * 0.8, 0, TAU, 40, Color(1, 1, 1, 0.12), 2.0)
	var slots: Array = pl.data.auto_slots(pl.weapon_cat()) if pl.data else ["", "", ""]
	for b in buttons:
		var bt: Dictionary = buttons[b]
		if not bt.visible:
			continue
		var c: Vector2 = bt.pos
		var r: float = bt.r
		var col := Color(0.08, 0.08, 0.12, 0.55)
		var ring := Color(0.95, 0.8, 0.45, 0.85)
		var label := ""
		var cd_frac := 0.0
		var enabled := true
		match b:
			"attack":
				label = _attack_label(pl)
				ring = Color(1.0, 0.55, 0.35, 0.95)
			"block":
				label = "БЛОК"
			"dodge":
				label = "РЫВОК"
				if pl.dodge_cd > 0.0:
					cd_frac = pl.dodge_cd / 0.9
			"interact":
				label = "!"
				ring = Color(0.5, 1.0, 0.6, 0.95)
			"swap":
				label = "ОРУЖ."
			"potion":
				label = "%d" % pl.potion_count()
				ring = Color(1.0, 0.35, 0.35, 0.9)
				enabled = pl.potion_count() > 0
			"companion":
				label = {"follow": "СЛЕД", "attack": "АТК", "hold": "СТОЙ"}.get(pl.companion_mode, "?")
			_:
				var idx := int(b.substr(5)) - 1
				var id: String = slots[idx] if idx < slots.size() else ""
				if id == "":
					enabled = false
					label = "—"
				else:
					var spd := DBSkills.spell(id)
					var sk := DBSkills.find_skill(id)
					var nm: String = spd.get("name", sk.get("name", id))
					label = _short(nm)
					var total: float = spd.get("cd", sk.get("cd", 1.0))
					cd_frac = pl.cooldown_of(id) / maxf(0.1, total)
					if not spd.is_empty():
						ring = DBSkills.SCHOOLS[spd.school].color
						enabled = pl.mana >= spd.mana
		if bt.held:
			col = Color(0.3, 0.25, 0.15, 0.7)
		if not enabled:
			ring = Color(0.5, 0.5, 0.5, 0.5)
		draw_circle(c, r, col)
		draw_arc(c, r, 0, TAU, 40, ring, 3.0 if b != "attack" else 4.0)
		if cd_frac > 0.0:
			var pts := PackedVector2Array([c])
			var steps := 24
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * cd_frac * float(i) / steps
				pts.append(c + Vector2(cos(a), sin(a)) * (r - 3.0))
			draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		var fs := 15 if label.length() > 3 else 22
		if b == "attack":
			fs = 18
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(_font, c + Vector2(-tw.x * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.95 if enabled else 0.5))
		if b == "interact":
			var il: String = pl.interact_label()
			var tw2 := _font.get_string_size(il, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
			var rp := c + Vector2(-tw2.x * 0.5, -r - 12)
			draw_rect(Rect2(rp - Vector2(8, 18), tw2 + Vector2(16, 8)), Color(0, 0, 0, 0.6))
			draw_string(_font, rp, il, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 1.0, 0.8))
	# aim indicator
	if aim_vec.length() > 0.1:
		var ac: Vector2 = buttons.attack.pos
		draw_line(ac, ac + aim_vec * (buttons.attack.r + 40.0), Color(1, 0.6, 0.3, 0.9), 4.0)

func _attack_label(pl) -> String:
	var b: Dictionary = pl.weapon_base()
	if b.has("mag"):
		if pl.reload_t > 0.0:
			return "ПЕРЕЗ."
		return "%d/%d" % [pl.ammo, b.mag]
	match pl.weapon_cat():
		"bow": return "ВЫСТРЕЛ"
		"staff": return "МАГИЯ"
	return "АТАКА"

func _short(s: String) -> String:
	var words := s.split(" ")
	if words.size() == 1:
		return s.substr(0, 7)
	return (words[0].substr(0, 5) + "." + words[1].substr(0, 3)).to_upper() if s.length() > 9 else s
