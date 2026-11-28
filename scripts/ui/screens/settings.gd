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
	for i in Q_NAMES.size():
		var qv: int = Q_VALUES[i]
		var b := UITheme.button(Q_NAMES[i], func():
			Settings.set_quality(qv)
			_update_q(), 56, 150)
		_qbtns.append(b)
		qrow.add_child(b)
	_update_q()
	vb.add_child(UITheme.wrap_label("Отдельные параметры ниже переопределяют профиль; «как в профиле» — следовать выбранному уровню. Настройки хранятся на этом устройстве.", 15))
	var follow := "Как в профиле"
	vb.add_child(_choice("Качество магии", [follow, "Низкое", "Среднее", "Высокое", "Максимум"], Settings.magic_quality + 1, func(i):
		Settings.magic_quality = i - 1
		Settings.apply()))
	vb.add_child(_choice("Частицы", [follow, "Мало", "Средне", "Много", "Максимум"], Settings.particles_q + 1, func(i):
		Settings.particles_q = i - 1
		Settings.apply()))
	vb.add_child(_choice("Тени", [follow, "Выкл", "Низкие", "Высокие"], Settings.shadows_q + 1, func(i):
		Settings.shadows_q = i - 1
		Settings.apply()))
	vb.add_child(_choice("Динамический свет (магия, вспышки)", [follow, "Минимум", "Средне", "Много", "Максимум"], Settings.lighting_q + 1, func(i):
		Settings.lighting_q = i - 1
		Settings.apply()))
	vb.add_child(_slider("Плотность погоды (дождь, снег)", 0.1, 1.0, 0.05, Settings.weather_density, func(v):
		Settings.weather_density = v
		Settings.apply(), true))
	vb.add_child(_header("Камера и вспышки"))
	vb.add_child(_choice("Режим камеры", ["Минимальный", "Стандартный", "Кинематографичный"], Settings.camera_mode, func(i): Settings.camera_mode = i))
	vb.add_child(_check("Тряска камеры", Settings.camera_shake, func(v): Settings.camera_shake = v))
	vb.add_child(_slider("Сила вспышек", 0.0, 1.0, 0.05, Settings.flash_strength, func(v): Settings.flash_strength = v, true))
	vb.add_child(_check("Без мерцания (мягкие одиночные вспышки вместо стробоскопа)", Settings.no_flicker, func(v): Settings.no_flicker = v))
	vb.add_child(_check("Исторические эхо (призраки событий из хроники)", Settings.echoes, func(v): Settings.echoes = v))
	vb.add_child(_slider("Масштаб рендера", 0.5, 1.0, 0.05, Settings.render_scale, func(v):
		Settings.render_scale = v
		Settings.apply(), true))
	vb.add_child(_choice("Туман", ["Выключен", "Слабый", "Стандартный"], Settings.fog_level, func(i):
		Settings.fog_level = i
		Settings.fog_enabled = i > 0
		Settings.apply()))
	vb.add_child(UITheme.wrap_label("Туман никогда не закрывает обзор полностью: персонаж, дорога, враги и предупреждения об атаках всегда видны.", 15))
	vb.add_child(_choice("Кинематографические сцены", ["Выключены", "Короткие", "Полные"], Settings.cinematics, func(i): Settings.cinematics = i))
	vb.add_child(_check("Динамическое качество в боях (держит FPS, снижая второстепенное)", Settings.dynamic_quality, func(v): Settings.dynamic_quality = v))
	vb.add_child(_choice("Целевая частота кадров", ["30", "60"], 0 if Settings.target_fps <= 30 else 1, func(i): Settings.target_fps = 30 if i == 0 else 60))
	vb.add_child(_choice("Боевые эффекты (замедления, вспышки, тряска)", ["Выкл", "Минимально", "Стандартно", "Эпично"], Settings.combat_fx, func(i): Settings.combat_fx = i))
	vb.add_child(_slider("Яркость эффектов событий (кровавая луна, вспышки)", 0.0, 1.0, 0.05, Settings.effects_intensity, func(v):
		Settings.effects_intensity = v, true))
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
	var ed_row := HBoxContainer.new()
	ed_row.add_theme_constant_override("separation", 10)
	vb.add_child(ed_row)
	ed_row.add_child(UITheme.button("Редактор интерфейса", func():
		Settings.save_settings()
		if manager:
			manager.open("layout_editor"), 58, 300))
	ed_row.add_child(UITheme.wrap_label("Перемещение и размер джойстика и кнопок, прозрачность, чувствительность, мёртвая зона.", 15))
	vb.add_child(_slider("Чувствительность джойстика", 0.5, 2.0, 0.05, Settings.joy_sensitivity, func(v): Settings.joy_sensitivity = v, true))
	vb.add_child(_slider("Мёртвая зона джойстика", 0.0, 0.4, 0.01, Settings.joy_deadzone, func(v): Settings.joy_deadzone = v, true))
	vb.add_child(_slider("Прозрачность кнопок", 0.3, 1.0, 0.05, Settings.ui_opacity, func(v): Settings.ui_opacity = v, true))
	vb.add_child(_slider("Размер джойстика", 0.7, 1.5, 0.05, Settings.joystick_size, func(v): Settings.joystick_size = v, true))
	vb.add_child(_slider("Размер кнопок", 0.7, 1.5, 0.05, Settings.button_size, func(v): Settings.button_size = v, true))
	vb.add_child(_slider("Приближение камеры", 0.7, 1.5, 0.05, Settings.camera_zoom, func(v): Settings.camera_zoom = v, true))
	vb.add_child(_check("Помощь в прицеливании", Settings.aim_assist, func(v): Settings.aim_assist = v))
	vb.add_child(_check("Автоподбор расходников", Settings.auto_pickup, func(v): Settings.auto_pickup = v))
	vb.add_child(_check("Вибрация", Settings.vibration, func(v): Settings.vibration = v))
	vb.add_child(_check("Автоперезарядка (когда магазин пуст и есть запас)", Settings.auto_reload, func(v): Settings.auto_reload = v))
	vb.add_child(_check("Подсказки для новичков", not Profile.hints_shown.get("_off", false), func(v): Profile.hints_shown["_off"] = not v))
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

const Q_NAMES := ["Низкое", "Среднее", "Высокое", "Максимум", "Авто"]
const Q_VALUES := [Settings.Quality.LOW, Settings.Quality.MEDIUM, Settings.Quality.HIGH, Settings.Quality.MAX, Settings.Quality.AUTO]

func _update_q() -> void:
	for i in _qbtns.size():
		var on: bool = Settings.quality == Q_VALUES[i]
		_qbtns[i].modulate = Color(1, 1, 1) if on else Color(0.6, 0.6, 0.6)
		_qbtns[i].text = Q_NAMES[i] + (" ✔" if on else "")

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

## Row of mutually exclusive buttons.
func _choice(t: String, names: Array, val: int, cb: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(300, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var btns: Array = []
	for i in names.size():
		var idx: int = i
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_pressed = i == val
		b.custom_minimum_size = Vector2(150, 54)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			for o in btns:
				o.button_pressed = o == b
			Audio.play_sfx("ui_click")
			cb.call(idx))
		btns.append(b)
		row.add_child(b)
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
