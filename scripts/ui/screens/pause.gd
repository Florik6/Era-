extends UIScreen
## Pause menu with access to every game screen.

func build() -> void:
	make_frame("Пауза", 760.0, 0.9)
	var info := UITheme.label("%s · %s" % [DBEras.era(Profile.current_era).name, Game.time_string()], 18, UITheme.TEXT_DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(grid)
	var items := [
		["Продолжить", close],
		["Инвентарь", func(): manager.open("inventory")],
		["Навыки", func(): manager.open("skills")],
		["Задания", func(): manager.open("journal")],
		["Карта", func(): manager.open("map")],
		["Группировки", func(): manager.open("factions")],
		["Легенды", func(): manager.open("legends")],
		["Хроника", func(): manager.open("chronicle")],
		["Настройки", func(): manager.open("settings")],
		["Сохранить", _save],
	]
	for it in items:
		grid.add_child(UITheme.button(it[0], it[1], 60, 320))
	var mb := UITheme.button("В главное меню", _to_menu, 60, 650)
	mb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(mb)

func _save() -> void:
	var ok := SaveSys.save_game()
	show_toast("Игра сохранена" if ok else "Сохранение недоступно в этом режиме", UITheme.GOOD if ok else UITheme.BAD)

func _to_menu() -> void:
	var vb := modal(560)
	vb.add_child(UITheme.title_label("Выйти в главное меню?", 26))
	vb.add_child(UITheme.wrap_label("Прогресс живого мира будет сохранён автоматически." if Game.mode == "world" else "Забег в этом режиме будет завершён.", 18, UITheme.TEXT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	row.add_child(UITheme.button("Выйти", func():
		manager.close_all()
		Game.goto_menu(), 56, 180))
	row.add_child(UITheme.button("Отмена", close_modal, 56, 160))
