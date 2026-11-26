extends Node
## Boot / loader. Shows a real loading screen right away (title, progress
## bar, status), loads the main menu in the background with progress, and
## protects the start-up:
##  - if the previous launch did not reach the menu, safe graphics are
##    switched on automatically and the player is told why;
##  - if loading fails, the error is shown with "Повторить" and
##    "Безопасный режим" buttons instead of a frozen black screen;
##  - every step goes to user://boot.log.

var _bar: ProgressBar
var _status: Label
var _hint: Label
var _err_box: VBoxContainer
var _t := 0.0
var _loading := false
var _stalled_t := 0.0
var _last_p := -1.0
var _safe_note := ""

func _ready() -> void:
	BootGuard.log_line("boot start, renderer=%s, os=%s, model=%s" % [RenderingServer.get_current_rendering_method(), OS.get_name(), OS.get_model_name()])
	if BootGuard.previous_failed():
		BootGuard.apply_safe_graphics()
		_safe_note = "Прошлый запуск не завершился — включены безопасные настройки графики. Их можно изменить в настройках."
		BootGuard.log_line("previous boot failed (%d) → safe graphics" % BootGuard.fail_count())
	BootGuard.mark("booting")
	get_tree().root.theme = UITheme.make()
	_build_ui()
	# give the loading screen one frame to appear before any heavy work
	await get_tree().process_frame
	await get_tree().process_frame
	_status.text = "Профиль и настройки…"
	if SaveSys.has_save():
		SaveSys.load_profile()
	Settings.apply()
	BootGuard.log_line("profile + settings ok")
	_start_load()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	if ResourceLoader.exists("res://assets/icon/splash.png"):
		var tr := TextureRect.new()
		tr.texture = load("res://assets/icon/splash.png")
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.add_child(tr)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -330
	box.offset_right = 330
	box.offset_top = -150
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(660, 14)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0, 0, 0, 0.6)
	bgs.set_corner_radius_all(7)
	var fgs := StyleBoxFlat.new()
	fgs.bg_color = Color(0.96, 0.79, 0.4)
	fgs.set_corner_radius_all(7)
	_bar.add_theme_stylebox_override("background", bgs)
	_bar.add_theme_stylebox_override("fill", fgs)
	box.add_child(_bar)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", Color(0.9, 0.87, 0.8))
	_status.text = "Запуск…"
	box.add_child(_status)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	_hint.text = _safe_note
	box.add_child(_hint)
	_err_box = VBoxContainer.new()
	_err_box.visible = false
	_err_box.add_theme_constant_override("separation", 8)
	box.add_child(_err_box)

func _start_load() -> void:
	_status.text = "Загрузка мира эпох…"
	var err := ResourceLoader.load_threaded_request(Game.MENU_SCENE, "", true)
	if err != OK:
		BootGuard.log_line("threaded request failed: %d, loading synchronously" % err)
		var ps: PackedScene = load(Game.MENU_SCENE)
		_finish(ps)
		return
	_loading = true

func _process(delta: float) -> void:
	_t += delta
	if not _loading:
		return
	var prog := []
	var st := ResourceLoader.load_threaded_get_status(Game.MENU_SCENE, prog)
	var p: float = prog[0] if prog.size() > 0 else 0.0
	_bar.value = lerpf(_bar.value, 0.15 + 0.8 * p, minf(1.0, delta * 8.0))
	if absf(p - _last_p) > 0.001:
		_last_p = p
		_stalled_t = 0.0
	else:
		_stalled_t += delta
	if _stalled_t > 6.0:
		_hint.text = "Первый запуск дольше обычного: подготавливается графика устройства. Пожалуйста, подождите…"
	match st:
		ResourceLoader.THREAD_LOAD_LOADED:
			_loading = false
			_finish(ResourceLoader.load_threaded_get(Game.MENU_SCENE))
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_loading = false
			_fail("Не удалось загрузить главное меню (код %d)." % st)

func _finish(ps: PackedScene) -> void:
	if ps == null:
		_fail("Сцена меню повреждена или отсутствует.")
		return
	_bar.value = 1.0
	_status.text = "Готово"
	BootGuard.log_line("menu loaded in %.1fs" % _t)
	await get_tree().process_frame
	var e := get_tree().change_scene_to_packed(ps)
	if e != OK:
		_fail("Ошибка смены сцены (код %d)." % e)

func _fail(msg: String) -> void:
	BootGuard.log_line("FAIL: " + msg)
	_status.text = msg
	_hint.text = "Попробуйте ещё раз или включите безопасный режим графики."
	_err_box.visible = true
	for c in _err_box.get_children():
		c.queue_free()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_err_box.add_child(row)
	var b1 := Button.new()
	b1.text = "Повторить"
	b1.custom_minimum_size = Vector2(220, 60)
	b1.pressed.connect(func():
		_err_box.visible = false
		_start_load())
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "Безопасный режим"
	b2.custom_minimum_size = Vector2(260, 60)
	b2.pressed.connect(func():
		BootGuard.apply_safe_graphics()
		Settings.apply()
		_err_box.visible = false
		_start_load())
	row.add_child(b2)
