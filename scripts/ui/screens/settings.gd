extends UIScreen
## Settings: graphics profile, fog, audio, controls, test options.

var _qbtns: Array = []
var _fog_slider: HSlider

func build() -> void:
	make_frame("Настройки", 980.0, 0.96)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	content.add_child(UITheme.scroll(vb))
	vb.add_child(_header("Графика"))
	var qrow := HBoxContainer.new()
	vb.add_child(qrow)
	var qnames := ["Низкое", "Среднее", "Высокое", "Авто"]
	for i in 4:
		var b := UITheme.button(qnames[i], func():
			Settings.set_quality(i)
			_update_q(), 56, 150)
		_qbtns.append(b)
		qrow.add_child(b)
	_update_q()
	vb.add_child(_slider("Масштаб рендера", 0.5, 1.0, 0.05, Settings.render_scale, func(v):
		Settings.render_scale = v
		Settings.apply(), true))
	vb.add_child(_check("Туман", Settings.fog_enabled, func(v):
		Settings.fog_enabled = v
		_fog_slider.editable = v
		Settings.apply()))
	var fs := _slider("Плотность тумана", 0.0, 1.0, 0.05, Settings.fog_density, func(v):
		Settings.fog_density = v
		Settings.apply(), true)
	_fog_slider = fs.get_meta("slider")
	_fog_slider.editable = Settings.fog_enabled
	vb.add_child(fs)
	vb.add_child(UITheme.wrap_label("Туман никогда не закрывает обзор полностью: даже на максимуме видны персонаж, дорога и враги.", 15))
	vb.add_child(_check("Показывать FPS", Settings.show_fps, func(v): Settings.show_fps = v))
	vb.add_child(_header("Звук"))
	vb.add_child(_slider("Музыка", 0.0, 1.0, 0.05, Settings.music_vol, func(v):
		Settings.music_vol = v
		Settings.apply(), true))
	vb.add_child(_slider("Звуки", 0.0, 1.0, 0.05, Settings.sfx_vol, func(v):
		Settings.sfx_vol = v
		Settings.apply()
		Audio.play_sfx("ui_click"), true))
	vb.add_child(_header("Управление"))
	vb.add_child(_slider("Размер джойстика", 0.7, 1.5, 0.05, Settings.joystick_size, func(v): Settings.joystick_size = v, true))
	vb.add_child(_slider("Размер кнопок", 0.7, 1.5, 0.05, Settings.button_size, func(v): Settings.button_size = v, true))
	vb.add_child(_slider("Отдаление камеры", 0.7, 1.5, 0.05, Settings.camera_zoom, func(v): Settings.camera_zoom = v, true))
	vb.add_child(_check("Помощь в прицеливании", Settings.aim_assist, func(v): Settings.aim_assist = v))
	vb.add_child(_check("Автоподбор расходников", Settings.auto_pickup, func(v): Settings.auto_pickup = v))
	vb.add_child(_check("Вибрация", Settings.vibration, func(v): Settings.vibration = v))
	vb.add_child(_header("Тестирование"))
	vb.add_child(_check("Открыть все эпохи (тестовый режим)", Settings.dev_unlock_all, func(v): Settings.dev_unlock_all = v))
	vb.add_child(UITheme.wrap_label("Тестовый режим позволяет сразу посетить любую эпоху без Суда Хроноса. Прогресс эпох при этом не засчитывается.", 15))
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(close_row)
	close_row.add_child(UITheme.button("Готово", close, 60, 220))

func close() -> void:
	Settings.save_settings()
	Settings.apply()
	Events.settings_changed.emit()
	super.close()

func _update_q() -> void:
	for i in _qbtns.size():
		var on := Settings.quality == i
		_qbtns[i].modulate = Color(1, 1, 1) if on else Color(0.6, 0.6, 0.6)
		_qbtns[i].text = ["Низкое", "Среднее", "Высокое", "Авто"][i] + (" ✔" if on else "")

func _header(t: String) -> Control:
	var l := UITheme.label(t, 24, UITheme.GOLD, "title")
	return l

func _slider(t: String, mn: float, mx: float, step: float, val: float, cb: Callable, show_pct: bool = false) -> Control:
	var row := HBoxContainer.new()
	var l := UITheme.label(t, 19)
	l.custom_minimum_size.x = 280
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(380, 48)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var vl := UITheme.label("", 18, UITheme.TEXT_DIM)
	vl.custom_minimum_size.x = 70
	row.add_child(vl)
	var upd := func(v): vl.text = ("%d%%" % roundi(v * 100.0)) if show_pct else ("%.2f" % v)
	upd.call(val)
	s.value_changed.connect(func(v):
		upd.call(v)
		cb.call(v))
	row.set_meta("slider", s)
	return row

func _check(t: String, val: bool, cb: Callable) -> Control:
	var c := CheckBox.new()
	c.text = t
	c.button_pressed = val
	c.custom_minimum_size.y = 52
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v):
		UITheme.click()
		cb.call(v))
	return c
