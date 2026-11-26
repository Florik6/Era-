extends Node
## Touch controls checks: fixed stick base, knob clamp, dead zone and
## sensitivity, multi-touch (move + attack + skill), release/reset, layout
## editor drag + resize, persistence of the layout across a reload.
## Prints CHECK lines and CONTROLS_DONE pass=N fail=M.

var pass_n := 0
var fail_n := 0
var tc: TouchControls

func ck(nm: String, ok: bool, extra := "") -> void:
	if ok:
		pass_n += 1
	else:
		fail_n += 1
	print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")

func touch(idx: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = p
	e.pressed = pressed
	tc._input(e)

func drag(idx: int, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = p
	tc._input(e)

func _ready() -> void:
	Settings.reset_layout()
	await get_tree().process_frame
	tc = TouchControls.new()
	tc.preview = false
	add_child(tc)
	await get_tree().process_frame
	var base := tc.joystick_base()
	var r := tc.joystick_radius()
	ck("stick base inside the screen", get_viewport().get_visible_rect().has_point(base), str(base))
	# 1: press near the base
	touch(0, base + Vector2(30, 0), true)
	ck("finger captured by the stick", tc._joy_finger == 0)
	ck("base did not move on press", tc.joystick_base() == base)
	# 2: drag far away → knob clamped, base fixed
	drag(0, base + Vector2(400, 0))
	ck("base stays fixed when the finger leaves the radius", tc.joystick_base() == base, str(tc.joystick_base()))
	ck("knob clamped to the radius", absf(tc._joy_knob.distance_to(base) - r) < 0.5, "%.1f vs %.1f" % [tc._joy_knob.distance_to(base), r])
	ck("full deflection to the right", tc.move_vec.x > 0.99 and absf(tc.move_vec.y) < 0.01, str(tc.move_vec))
	drag(0, base + Vector2(0, -r * 0.5))
	ck("half deflection up is proportional", tc.move_vec.y < -0.3 and tc.move_vec.y > -0.7, str(tc.move_vec))
	# 3: dead zone
	drag(0, base + Vector2(r * Settings.joy_deadzone * 0.5, 0))
	ck("inside the dead zone → no movement", tc.move_vec == Vector2.ZERO, str(tc.move_vec))
	# sensitivity
	Settings.joy_sensitivity = 2.0
	drag(0, base + Vector2(r * 0.6, 0))
	ck("higher sensitivity reaches full speed sooner", tc.move_vec.length() > 0.99, str(tc.move_vec))
	Settings.joy_sensitivity = 1.0
	# 4: multi-touch — attack + skill while moving
	var ap: Vector2 = tc.buttons.attack.pos
	touch(1, ap, true)
	ck("attack held while moving", tc.is_held("attack") and tc._joy_finger == 0)
	var sp: Vector2 = tc.buttons.skill1.pos
	touch(2, sp, true)
	ck("skill pressed with two other fingers down", tc.consume("skill1"))
	ck("stick still engaged with three fingers", tc._joy_finger == 0 and tc.move_vec.length() > 0.1)
	drag(1, ap + Vector2(0, -120))
	ck("drag on attack aims", tc.aim_vec.y < -0.9, str(tc.aim_vec))
	# 5: release
	touch(0, base, false)
	ck("release stops movement", tc.move_vec == Vector2.ZERO)
	ck("knob recentred", tc._joy_knob == base)
	ck("attack still held after stick release", tc.is_held("attack"))
	touch(1, ap, false)
	touch(2, sp, false)
	ck("attack released", not tc.is_held("attack") and tc.aim_vec == Vector2.ZERO)
	# touches far from the stick don't grab it (base never jumps)
	touch(3, Vector2(base.x + r * 3.0, base.y - r * 2.5), true)
	ck("touch away from the stick doesn't capture it", tc._joy_finger == -1 and tc.joystick_base() == base)
	touch(3, Vector2(base.x + r * 3.0, base.y - r * 2.5), false)
	# 6: reset clears everything (menu opened / focus lost)
	touch(0, base + Vector2(50, 0), true)
	touch(1, ap, true)
	Events.input_reset.emit()
	ck("reset releases stick and buttons", tc._joy_finger == -1 and tc.move_vec == Vector2.ZERO and not tc.is_held("attack"))
	tc._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ck("focus loss keeps everything released", tc._joy_finger == -1)
	# 7: layout editor — drag the stick and the attack button
	tc.edit_mode = true
	var e1 := InputEventScreenTouch.new()
	e1.index = 0
	e1.position = base
	e1.pressed = true
	tc._input(e1)
	ck("editor selects the stick", tc.selected == "joystick")
	var d1 := InputEventScreenDrag.new()
	d1.index = 0
	d1.position = base + Vector2(120, -60)
	tc._input(d1)
	ck("editor moves the stick base", tc.joystick_base().distance_to(base + Vector2(120, -60)) < 1.0, str(tc.joystick_base()))
	e1.pressed = false
	tc._input(e1)
	tc.set_element_scale("attack", 1.4)
	var ar: float = tc.buttons.attack.r
	ck("editor resizes a button", ar > 76.0 * Settings.button_size * 1.35)
	tc.edit_mode = false
	var new_base := tc.joystick_base()
	# gameplay drag never moves the base
	touch(0, new_base, true)
	drag(0, new_base + Vector2(500, 500))
	ck("outside the editor the base never moves", tc.joystick_base() == new_base)
	touch(0, new_base, false)
	# 8: persistence across a reload of the settings file
	Settings.ui_opacity = 0.6
	Settings.joy_deadzone = 0.2
	Settings.save_settings()
	Settings.ui_layout = {}
	Settings.ui_opacity = 0.85
	Settings.joy_deadzone = 0.12
	Settings.load_settings()
	ck("layout persisted", Settings.ui_layout.has("joystick") and Settings.ui_layout.has("attack"))
	ck("opacity and dead zone persisted", absf(Settings.ui_opacity - 0.6) < 0.001 and absf(Settings.joy_deadzone - 0.2) < 0.001)
	var tc2 := TouchControls.new()
	add_child(tc2)
	await get_tree().process_frame
	ck("a fresh control layer uses the saved layout", tc2.joystick_base().distance_to(new_base) < 1.5 and absf(tc2.buttons.attack.r - ar) < 0.5, "%s vs %s" % [tc2.joystick_base(), new_base])
	# 9: reset to default
	Settings.reset_layout()
	tc2._layout()
	ck("restore default layout", tc2.joystick_base().distance_to(base) < 1.0)
	Settings.save_settings()
	print("CONTROLS_DONE pass=%d fail=%d" % [pass_n, fail_n])
	get_tree().quit()
