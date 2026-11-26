extends UIScreen
## Настройки → Управление → Редактор интерфейса.
## Drag the joystick and any combat button to a new place, tap one to
## select it and change its size; global opacity, stick sensitivity and
## dead zone; restore the default layout. Bases move only here.
## Everything is saved to the settings file when leaving.

var tc: TouchControls
var panel: PanelContainer
var _sel_lbl: Label
var _size_slider: HSlider
var _snapshot := {}

func build() -> void:
	_snapshot = {"layout": Settings.ui_layout.duplicate(true), "op": Settings.ui_opacity, "sens": Settings.joy_sensitivity,
		"dz": Settings.joy_deadzone, "js": Settings.joystick_size, "bs": Settings.button_size}
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.06, 0.55 if Game.world != null else 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	# a faint horizon + hero silhouette so placement can be judged from the menu too
	var mock := Control.new()
	mock.set_anchors_preset(Control.PRESET_FULL_RECT)
	mock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mock.draw.connect(func():
		var vs := mock.size
		mock.draw_rect(Rect2(Vector2(0, vs.y * 0.55), Vector2(vs.x, vs.y * 0.45)), Color(0.12, 0.16, 0.1, 0.35))
		mock.draw_circle(vs * Vector2(0.5, 0.52), 22.0, Color(0.85, 0.75, 0.6, 0.35))
		mock.draw_rect(Rect2(vs * Vector2(0.5, 0.52) + Vector2(-16, 18), Vector2(32, 54)), Color(0.5, 0.3, 0.25, 0.35)))
	add_child(mock)
	tc = TouchControls.new()
	tc.edit_mode = true
	tc.preview = true
	add_child(tc)
	tc.element_selected.connect(_on_selected)
	# compact control panel at the top
	panel = UITheme.panel(Color(0.06, 0.055, 0.08, 0.94), UITheme.GOLD_DIM, 14, 12)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = UITheme.safe_margins(get_viewport()).y + 8
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	var t := UITheme.title_label("Редактор интерфейса", 24)
	top.add_child(t)
	_sel_lbl = UITheme.label("Перетащите элемент или нажмите на него", 17, UITheme.TEXT_DIM)
	_sel_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_sel_lbl)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	vb.add_child(r1)
	_size_slider = _mini_slider(r1, "Размер", 0.5, 1.8, 1.0, func(v):
		if tc.selected != "":
			tc.set_element_scale(tc.selected, v))
	_mini_slider(r1, "Прозрачность", 0.3, 1.0, Settings.ui_opacity, func(v):
		Settings.ui_opacity = v
		tc.queue_redraw())
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	vb.add_child(r2)
	_mini_slider(r2, "Чувствительность", 0.5, 2.0, Settings.joy_sensitivity, func(v): Settings.joy_sensitivity = v)
	_mini_slider(r2, "Мёртвая зона", 0.0, 0.4, Settings.joy_deadzone, func(v):
		Settings.joy_deadzone = v
		tc.queue_redraw())
	var r3 := HBoxContainer.new()
	r3.alignment = BoxContainer.ALIGNMENT_CENTER
	r3.add_theme_constant_override("separation", 10)
	vb.add_child(r3)
	r3.add_child(UITheme.button("Сбросить раскладку", _reset, 52, 230))
	r3.add_child(UITheme.button("Отмена", _cancel, 52, 150))
	r3.add_child(UITheme.button("Готово", _done, 52, 170))

func _mini_slider(row: HBoxContainer, title: String, mn: float, mx: float, val: float, cb: Callable) -> HSlider:
	var l := UITheme.label(title, 16)
	l.custom_minimum_size.x = 150
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 0.01
	s.value = val
	s.custom_minimum_size = Vector2(170, 44)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(cb)
	row.add_child(s)
	return s

func _process(_delta: float) -> void:
	if panel and tc:
		tc.edit_ignore_rect = panel.get_global_rect().grow(6.0)

func _on_selected(nm: String) -> void:
	_sel_lbl.text = "Выбрано: " + TouchControls.ELEMENT_NAMES.get(nm, nm)
	_sel_lbl.add_theme_color_override("font_color", UITheme.GOLD)
	_size_slider.set_value_no_signal(tc.element_scale(nm))

func _reset() -> void:
	Settings.reset_layout()
	tc._layout()
	tc.selected = ""
	_sel_lbl.text = "Стандартная раскладка восстановлена"
	_size_slider.set_value_no_signal(1.0)
	UITheme.click()

func _done() -> void:
	Settings.save_settings()
	Events.settings_changed.emit()
	close()

func _cancel() -> void:
	Settings.ui_layout = _snapshot.layout
	Settings.ui_opacity = _snapshot.op
	Settings.joy_sensitivity = _snapshot.sens
	Settings.joy_deadzone = _snapshot.dz
	Settings.joystick_size = _snapshot.js
	Settings.button_size = _snapshot.bs
	Events.settings_changed.emit()
	close()
