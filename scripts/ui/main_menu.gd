extends Node3D
## Main menu: 3D era diorama with the hero, game modes, character creation,
## eras, achievements, legends archive and settings.

const HAIR_NAMES := ["Лысый", "Короткая", "Длинная", "Хвост", "Ирокез"]
const BEARD_NAMES := ["Нет", "Щетина", "Борода"]
const VERSION_TEXT := "ERA: Восхождение · версия 0.14 · одиночная игра"

var bg: MenuBackground
var ui: UIManager
var layer: CanvasLayer
var root: Control
var left_col: Control
var left_vbox: VBoxContainer
var right_panel: PanelContainer
var right_box: VBoxContainer
var char_info: Label
var btn_continue: Button
var _panel_name := ""
var _pending_mode := "world"
# creation form state
var cf := {"name": "", "class": "warrior", "female": false, "skin": 1, "hair": 1, "hair_color": 0, "beard": 0, "cloth": 0, "difficulty": "normal"}
var _class_desc: Label
var _form_labels := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	# the menu is up and rendering: this launch succeeded
	get_tree().create_timer(2.0, true).timeout.connect(func():
		BootGuard.mark("ok")
		BootGuard.log_line("main menu ok, fps=%d" % Engine.get_frames_per_second()))
	if SaveSys.has_save() and not Profile.has_character:
		SaveSys.load_profile()
	bg = MenuBackground.new()
	add_child(bg)
	bg.set_era(Profile.current_era if Profile.has_character else 0)
	_show_profile_character()
	layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.make()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	ui = UIManager.new()
	add_child(ui)
	_build_left()
	_build_right()
	_build_footer()
	Audio.play_music("menu")
	# intro fade
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", 0.0, 1.0)
	tw.tween_callback(fade.queue_free)
	left_col.position.x = -60
	left_col.modulate.a = 0.0
	var tw2 := left_col.create_tween().set_parallel(true)
	tw2.tween_property(left_col, "position:x", 0.0, 0.7).set_delay(0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw2.tween_property(left_col, "modulate:a", 1.0, 0.7).set_delay(0.25)

func _show_profile_character() -> void:
	if Profile.has_character:
		var look := _look_from(Profile.char.appearance, Profile.char.female)
		bg.set_character(look, Profile.char.inv.equip)
	else:
		var eq := {}
		for b in ["sword_iron", "shield_kite", "armor_chain", "helm_kettle"]:
			var it := ItemDB.create(b, 1 if b == "sword_iron" else 0, 1, null, false)
			eq[ItemDB.base(b).slot] = it
		bg.set_character({"build": "normal", "skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0, "female": false}, eq)

func _look_from(app: Dictionary, female: bool) -> Dictionary:
	return {"build": "normal", "skin": int(app.get("skin", 1)), "hair": int(app.get("hair", 1)), "hair_color": int(app.get("hair_color", 0)),
		"beard": int(app.get("beard", 0)), "cloth": int(app.get("cloth", 0)), "female": female}

# ---------------------------------------------------------------- layout
func _build_left() -> void:
	var sm := UITheme.safe_margins(get_viewport())
	left_col = Control.new()
	left_col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_col.custom_minimum_size.x = 440
	left_col.size.x = 440
	left_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left_col)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.04, 0.88))
	g.set_color(1, Color(0.02, 0.02, 0.04, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 64
	gt.height = 8
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_col.add_child(grad)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(sm.x + 44))
	margin.add_theme_constant_override("margin_top", int(sm.y + 16))
	margin.add_theme_constant_override("margin_bottom", int(sm.w + 30))
	margin.add_theme_constant_override("margin_right", 30)
	left_col.add_child(margin)
	left_vbox = VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(left_vbox)
	var logo := UITheme.label("ERA", 78, UITheme.GOLD, "logo")
	logo.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.0, 0.95))
	logo.add_theme_constant_override("outline_size", 10)
	logo.add_theme_color_override("font_shadow_color", Color(1.0, 0.6, 0.2, 0.35))
	logo.add_theme_constant_override("shadow_offset_y", 4)
	left_vbox.add_child(logo)
	var sub := UITheme.title_label("ВОСХОЖДЕНИЕ", 34, Color(0.95, 0.9, 0.8))
	sub.add_theme_constant_override("outline_size", 8)
	left_vbox.add_child(sub)
	var tag := UITheme.label("Пять эпох. Одна легенда.", 20, Color(0.8, 0.85, 0.9), "italic")
	left_vbox.add_child(tag)
	var sp := Control.new()
	sp.custom_minimum_size.y = 6
	left_vbox.add_child(sp)
	var items := [
		["Играть", func(): _open_panel("play")],
		["Продолжить", _continue],
		["Персонаж", func(): _open_panel("character")],
		["Эпохи", func(): _open_panel("eras")],
		["Достижения", func(): _open_panel("achievements")],
		["Архив легенд", func():
			_close_panel()
			ui.open("legends", {"archive": true})],
		["Настройки", func():
			_close_panel()
			ui.open("settings")],
		["Выход", _quit],
	]
	for it in items:
		var b := UITheme.button(it[0], it[1], 50, 320)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 21)
		b.add_theme_stylebox_override("normal", UITheme.sb(Color(0.08, 0.07, 0.1, 0.72), Color(0.62, 0.5, 0.26, 0.6), 8, 1, 20))
		left_vbox.add_child(b)
		if it[0] == "Продолжить":
			btn_continue = b
	btn_continue.disabled = not SaveSys.has_save()

func _build_footer() -> void:
	var sm := UITheme.safe_margins(get_viewport())
	var ver := UITheme.label(VERSION_TEXT, 14, Color(0.7, 0.7, 0.72, 0.8))
	ver.anchor_left = 0.0
	ver.anchor_right = 0.0
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = sm.x + 44
	ver.offset_right = sm.x + 644
	ver.offset_top = -(sm.w + 30)
	ver.offset_bottom = -(sm.w + 8)
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ver)
	char_info = UITheme.label("", 18, Color(0.95, 0.9, 0.8))
	char_info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	char_info.add_theme_constant_override("outline_size", 6)
	char_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_info.anchor_left = 0.66
	char_info.anchor_right = 0.66
	char_info.anchor_top = 1.0
	char_info.anchor_bottom = 1.0
	char_info.offset_left = -260
	char_info.offset_right = 260
	char_info.offset_top = -(sm.w + 76)
	char_info.offset_bottom = -(sm.w + 20)
	char_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(char_info)
	_update_char_info()

func _update_char_info() -> void:
	if char_info == null:
		return
	if Profile.has_character:
		var c := Profile.char
		char_info.text = "%s · %s · ур. %d\nЭпоха: %s" % [c.name, DBSkills.CLASSES.get(c.class_id, {}).get("name", ""), c.level, DBEras.era(Profile.current_era).name]
	else:
		char_info.text = "Создайте героя, чтобы начать восхождение"
	char_info.visible = _panel_name == ""

func _build_right() -> void:
	var sm := UITheme.safe_margins(get_viewport())
	right_panel = UITheme.panel(Color(0.05, 0.045, 0.07, 0.9), UITheme.GOLD_DIM, 16, 20)
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_left = -500 - sm.z
	right_panel.offset_right = -24 - sm.z
	right_panel.offset_top = 22 + sm.y
	right_panel.offset_bottom = -22 - sm.w
	right_panel.visible = false
	root.add_child(right_panel)
	right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_box)

func _open_panel(nm: String) -> void:
	_panel_name = nm
	for c in right_box.get_children():
		right_box.remove_child(c)
		c.queue_free()
	var hdr := HBoxContainer.new()
	right_box.add_child(hdr)
	var titles := {"play": "Выберите режим", "character": "Персонаж", "create": "Создание героя", "eras": "Эпохи", "achievements": "Достижения"}
	var t := UITheme.title_label(titles.get(nm, ""), 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(t)
	var x := UITheme.button("×", _close_panel, 54, 60)
	x.add_theme_font_size_override("font_size", 32)
	hdr.add_child(x)
	right_box.add_child(UITheme.separator())
	match nm:
		"play": _panel_play()
		"character": _panel_character()
		"create": _panel_create()
		"eras": _panel_eras()
		"achievements": _panel_achievements()
	var creating := nm == "create"
	bg.set_framing(0.9 if creating else -0.35)
	left_col.visible = not creating
	right_panel.visible = true
	right_panel.modulate.a = 0.0
	right_panel.pivot_offset = Vector2(right_panel.size.x, 0)
	var tw := right_panel.create_tween().set_parallel(true)
	tw.tween_property(right_panel, "modulate:a", 1.0, 0.22)
	right_panel.position.x += 40
	tw.tween_property(right_panel, "position:x", right_panel.position.x - 40, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_update_char_info()

func _close_panel() -> void:
	if _panel_name == "":
		return
	if _panel_name == "create" or _panel_name == "eras":
		_show_profile_character()
		bg.set_era(Profile.current_era if Profile.has_character else 0)
	_panel_name = ""
	right_panel.visible = false
	left_col.visible = true
	bg.set_framing(-1.15)
	_update_char_info()

func _scroll_box() -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	right_box.add_child(UITheme.scroll(vb))
	return vb

func _card_button(title: String, desc: String, cb: Callable, enabled: bool = true) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 94)
	b.disabled = not enabled
	b.pressed.connect(func():
		UITheme.click()
		cb.call())
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_top", 8)
	b.add_child(m)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	m.add_child(vb)
	var t := UITheme.label(title, 21, UITheme.GOLD, "title")
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)
	var d := UITheme.wrap_label(desc, 15, UITheme.TEXT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(d)
	return b

# ---------------------------------------------------------------- panels
func _panel_play() -> void:
	var vb := _scroll_box()
	vb.add_child(UITheme.label("Живой мир", 22, UITheme.GOLD, "title"))
	vb.add_child(UITheme.wrap_label("Открытый мир, задания, группировки, живые легенды, боссы, разломы и пять исторических эпох.", 16))
	var row := HBoxContainer.new()
	vb.add_child(row)
	if SaveSys.has_save():
		var cb := UITheme.button("Продолжить", _continue, 58, 200)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cb)
		var nb := UITheme.button("Новая игра", func(): _confirm_new("world"), 58, 200)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nb)
	else:
		var nb2 := UITheme.button("Новая игра", func(): _start_create("world"), 58, 0)
		nb2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nb2)
	vb.add_child(UITheme.separator())
	var modes := [
		["arena", "Арена", "Компактная карта, сферы опыта и постоянные схватки — быстрый рост силы. Мастерство сохраняется."],
		["trials", "Испытания", "Волны противников и поединки с чемпионами эпохи. Награды попадают в инвентарь героя."],
		["dungeon", "Хроноподземелья", "Экспедиции через порталы в особые измерения. Лут сохраняется только при успешном выходе."],
	]
	for m in modes:
		var mode: String = m[0]
		vb.add_child(_card_button(m[1], m[2], func(): _start_mode(mode)))
	if not Profile.has_character:
		vb.add_child(UITheme.wrap_label("Для дополнительных режимов сначала будет создан герой.", 15, UITheme.TEXT_DIM))

func _start_mode(mode: String) -> void:
	if not Profile.has_character and SaveSys.has_save():
		SaveSys.load_profile()
	if not Profile.has_character:
		_start_create(mode)
		return
	_launch(mode, {})

func _continue() -> void:
	if not SaveSys.has_save():
		return
	if not Profile.has_character:
		if not SaveSys.load_profile():
			_open_message("Не удалось загрузить сохранение", "Файл сохранения повреждён, а резервная копия недоступна.")
			return
	_launch("world", {})

func _launch(mode: String, opts: Dictionary) -> void:
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	var lbl := UITheme.title_label("Сквозь время…", 36)
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.modulate.a = 0.0
	root.add_child(lbl)
	Audio.play_sfx("portal_enter")
	var tw := fade.create_tween().set_parallel(true)
	tw.tween_property(fade, "color:a", 1.0, 0.45)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.45)
	tw.chain().tween_callback(func(): Game.start(mode, opts))

func _confirm_new(mode: String) -> void:
	_open_message("Начать новую игру?", "Текущее сохранение героя и всех эпох будет перезаписано. Это действие нельзя отменить.",
		[["Начать заново", func(): _start_create(mode)], ["Отмена", func(): pass]])

func _open_message(title: String, text: String, buttons: Array = []) -> void:
	var opts: Array = []
	for b in buttons:
		opts.append({"text": b[0], "cb": b[1]})
	if opts.is_empty():
		opts.append({"text": "Понятно"})
	ui.open("dialog", {"title": title, "text": text, "options": opts})

func _start_create(mode: String) -> void:
	_pending_mode = mode
	cf = {"name": "", "class": "warrior", "female": false, "skin": 1, "hair": 1, "hair_color": 0, "beard": 0, "cloth": 0, "difficulty": "normal"}
	_open_panel("create")
	_preview()

func _panel_character() -> void:
	var vb := _scroll_box()
	if not Profile.has_character:
		vb.add_child(UITheme.wrap_label("У вас ещё нет героя.", 18, UITheme.TEXT))
		vb.add_child(UITheme.button("Создать героя", func(): _start_create("world"), 58, 0))
		return
	var c := Profile.char
	var t := "[font_size=26][color=#f5c966]%s[/color][/font_size]\n%s · уровень %d\nЭпоха: %s · открыто эпох: %d/5\n" % [
		c.name, DBSkills.CLASSES.get(c.class_id, {}).get("name", ""), c.level, DBEras.era(Profile.current_era).name, Profile.unlocked_eras.size()]
	t += "Золото: %d · убийств: %d · слава: %d\n" % [c.gold, c.kills, roundi(c.fame)]
	var hours := Profile.play_time / 3600.0
	t += "Время в игре: %d ч %d мин\n" % [int(hours), int(fmod(Profile.play_time / 60.0, 60.0))]
	t += "\n[b][color=#f5c966]Мастерство[/color][/b]\n"
	var any := false
	for cat in c.mastery:
		if int(c.mastery[cat].lvl) > 0:
			any = true
			t += "%s — %d\n" % [ItemDB.CAT_NAMES.get(cat, cat), int(c.mastery[cat].lvl)]
	if not any:
		t += "—\n"
	if not c.schools.is_empty():
		t += "\n[b][color=#f5c966]Школы магии[/color][/b]\n"
		for s in c.schools:
			t += "%s — %d\n" % [DBSkills.SCHOOLS[s].name, int(c.schools[s].lvl)]
	t += "\n[b][color=#f5c966]Снаряжение[/color][/b]\n"
	for slot in ItemDB.SLOTS:
		var it: Dictionary = c.inv.equipped(slot)
		if not it.is_empty():
			t += "%s: [color=#%s]%s[/color]\n" % [ItemDB.SLOT_NAMES[slot], ItemDB.rarity_color(it).to_html(false), ItemDB.display_name(it)]
	vb.add_child(UITheme.rich(t))
	var row := HBoxContainer.new()
	vb.add_child(row)
	var inv := UITheme.button("Инвентарь", func(): ui.open("inventory"), 56, 0)
	inv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inv)
	var sk := UITheme.button("Навыки", func(): ui.open("skills"), 56, 0)
	sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sk)
	vb.add_child(UITheme.button("Новый персонаж", func(): _confirm_new("world"), 56, 0))

func _panel_create() -> void:
	var vb := _scroll_box()
	vb.add_child(UITheme.label("Имя", 19, UITheme.GOLD, "bold"))
	var le := LineEdit.new()
	le.placeholder_text = "Странник"
	le.max_length = 18
	le.custom_minimum_size.y = 56
	le.text = cf.name
	le.text_changed.connect(func(t): cf.name = t)
	vb.add_child(le)
	vb.add_child(UITheme.label("Класс", 19, UITheme.GOLD, "bold"))
	var crow := GridContainer.new()
	crow.columns = 2
	vb.add_child(crow)
	var cbtns := {}
	for cid in DBSkills.CLASSES:
		var b := UITheme.button(DBSkills.CLASSES[cid].name, func():
			cf["class"] = cid
			_refresh_toggle(cbtns, cid)
			_class_desc.text = DBSkills.CLASSES[cid].desc + "\n" + _class_extra(cid)
			_preview(), 56, 200)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cbtns[cid] = b
		crow.add_child(b)
	_refresh_toggle(cbtns, cf["class"])
	_class_desc = UITheme.wrap_label(DBSkills.CLASSES[cf["class"]].desc + "\n" + _class_extra(cf["class"]), 16, UITheme.TEXT)
	vb.add_child(_class_desc)
	vb.add_child(UITheme.label("Пол", 19, UITheme.GOLD, "bold"))
	var grow := HBoxContainer.new()
	vb.add_child(grow)
	var gbtns := {}
	for gi in [false, true]:
		var gb := UITheme.button("Женский" if gi else "Мужской", func():
			cf.female = gi
			if gi:
				cf.beard = 0
				if cf.hair == 1:
					cf.hair = 2
				_set_form_label("beard", BEARD_NAMES[0])
				_set_form_label("hair", HAIR_NAMES[cf.hair])
			_refresh_toggle(gbtns, gi)
			_preview(), 56, 0)
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gbtns[gi] = gb
		grow.add_child(gb)
	_refresh_toggle(gbtns, cf.female)
	vb.add_child(_swatch_row("Кожа", "skin", HumanoidRig.SKINS))
	vb.add_child(_cycle_row("Причёска", "hair", HAIR_NAMES))
	vb.add_child(_swatch_row("Цвет волос", "hair_color", HumanoidRig.HAIR_COLORS))
	vb.add_child(_cycle_row("Борода", "beard", BEARD_NAMES))
	vb.add_child(_swatch_row("Одежда", "cloth", HumanoidRig.CLOTH_COLORS))
	vb.add_child(UITheme.separator())
	# Режим сложности: Hardcore turns on anatomical injuries; the normal mode is untouched
	vb.add_child(UITheme.label("Режим сложности", 19, UITheme.GOLD, "bold"))
	var drow := HBoxContainer.new()
	vb.add_child(drow)
	var dbtns := {}
	var ddesc := UITheme.wrap_label("", 15, UITheme.TEXT_DIM)
	var dtexts := {"normal": "Обычный режим: ранения не учитываются, зелья и отдых восстанавливают здоровье.",
		"hardcore": "Hardcore Mode: удары ранят конкретные части тела (голова, грудь, живот, руки, ноги). Порезы кровоточат, раны могут воспалиться, переломы замедляют. Лечите их бинтами, антисептиками, у врачей и целителей, отдыхом и на медстанциях. Зелье здоровья тяжёлые раны не лечит."}
	for dk in ["normal", "hardcore"]:
		var db := UITheme.button("Обычный" if dk == "normal" else "Hardcore", func():
			cf.difficulty = dk
			_refresh_toggle(dbtns, dk)
			ddesc.text = dtexts[dk], 56, 0)
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dbtns[dk] = db
		drow.add_child(db)
	_refresh_toggle(dbtns, cf.get("difficulty", "normal"))
	ddesc.text = dtexts[cf.get("difficulty", "normal")]
	vb.add_child(ddesc)
	var go := UITheme.button("Начать восхождение", _confirm_create, 64, 0)
	go.add_theme_font_size_override("font_size", 24)
	go.add_theme_color_override("font_color", UITheme.GOLD)
	vb.add_child(go)

func _class_extra(cid: String) -> String:
	var c: Dictionary = DBSkills.CLASSES[cid]
	var m: Array = []
	for cat in c.mastery:
		m.append("%s %d" % [ItemDB.CAT_NAMES.get(cat, cat), c.mastery[cat]])
	var t := "Здоровье %d · мана %d · выносливость %d\nСтартовое мастерство: %s" % [c.hp, c.mana, c.stamina, ", ".join(PackedStringArray(m))]
	if not c.schools.is_empty():
		var s: Array = []
		for sc in c.schools:
			s.append(DBSkills.SCHOOLS[sc].name)
		t += "\nШколы магии: " + ", ".join(PackedStringArray(s))
	return t

func _refresh_toggle(btns: Dictionary, sel) -> void:
	for k in btns:
		var on: bool = k == sel
		btns[k].modulate = Color(1, 1, 1) if on else Color(0.6, 0.6, 0.6)
		btns[k].add_theme_stylebox_override("normal", UITheme.sb(Color(0.3, 0.23, 0.12, 1) if on else Color(0.14, 0.12, 0.16, 0.95), UITheme.GOLD if on else UITheme.GOLD_DIM, 10, 2, 16))

func _swatch_row(title: String, key: String, colors: Array) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.add_child(UITheme.label(title, 18, UITheme.GOLD, "bold"))
	var row := HBoxContainer.new()
	vb.add_child(row)
	var btns := {}
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 52)
		b.focus_mode = Control.FOCUS_NONE
		var c: Color = colors[i]
		b.add_theme_stylebox_override("normal", UITheme.sb(c, Color(0, 0, 0, 0.6), 26, 2, 0))
		b.add_theme_stylebox_override("hover", UITheme.sb(c.lightened(0.1), UITheme.GOLD, 26, 3, 0))
		b.add_theme_stylebox_override("pressed", UITheme.sb(c, UITheme.GOLD, 26, 4, 0))
		var idx := i
		b.pressed.connect(func():
			UITheme.click()
			cf[key] = idx
			for k in btns:
				btns[k].add_theme_stylebox_override("normal", UITheme.sb(colors[k], UITheme.GOLD if k == idx else Color(0, 0, 0, 0.6), 26, 4 if k == idx else 2, 0))
			_preview())
		btns[i] = b
		row.add_child(b)
	var sel: int = cf[key]
	if btns.has(sel):
		btns[sel].add_theme_stylebox_override("normal", UITheme.sb(colors[sel], UITheme.GOLD, 26, 4, 0))
	return vb

func _cycle_row(title: String, key: String, names: Array) -> Control:
	var row := HBoxContainer.new()
	var l := UITheme.label(title, 18, UITheme.GOLD, "bold")
	l.custom_minimum_size.x = 120
	row.add_child(l)
	var val := UITheme.label(names[cf[key]], 19, UITheme.TEXT)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_form_labels[key] = {"label": val, "names": names}
	row.add_child(UITheme.button("◀", func():
		cf[key] = posmod(cf[key] - 1, names.size())
		val.text = names[cf[key]]
		_preview(), 56, 64))
	row.add_child(val)
	row.add_child(UITheme.button("▶", func():
		cf[key] = posmod(cf[key] + 1, names.size())
		val.text = names[cf[key]]
		_preview(), 56, 64))
	return row

func _set_form_label(key: String, text: String) -> void:
	if _form_labels.has(key):
		_form_labels[key].label.text = text

func _preview() -> void:
	var look := {"build": "normal", "skin": cf.skin, "hair": cf.hair, "hair_color": cf.hair_color, "beard": cf.beard, "cloth": cf.cloth, "female": cf.female}
	var eq := {}
	for b in ItemDB.CLASS_KITS.get(cf["class"], []):
		var base := ItemDB.base(b)
		if base.slot in ItemDB.SLOTS and not eq.has(base.slot):
			eq[base.slot] = ItemDB.create(b, 0, 1, null, false)
	bg.set_character(look, eq)

func _confirm_create() -> void:
	var nm: String = cf.name.strip_edges()
	if nm == "":
		nm = "Странник"
	var app := {"skin": cf.skin, "hair": cf.hair, "hair_color": cf.hair_color, "beard": cf.beard, "cloth": cf.cloth, "cape": 0}
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character(nm, cf["class"], cf.female, app)
	Profile.difficulty = str(cf.get("difficulty", "normal"))
	SaveSys.save_game()
	btn_continue.disabled = false
	_launch(_pending_mode, {"new": true})

func _panel_eras() -> void:
	var vb := _scroll_box()
	if not Profile.has_character:
		vb.add_child(UITheme.wrap_label("Создайте героя, чтобы путешествовать между эпохами. Ниже — обзор эпох.", 16, UITheme.TEXT_DIM))
	for i in DBEras.ERA_COUNT:
		var e := DBEras.era(i)
		var open := Profile.has_character and Profile.is_era_unlocked(i)
		var p := UITheme.panel(Color(0.08, 0.07, 0.1, 0.9), UITheme.GOLD if i == Profile.current_era and Profile.has_character else (UITheme.GOLD_DIM if open else Color(0.25, 0.25, 0.25)), 10, 12)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 4)
		p.add_child(pv)
		var hr := HBoxContainer.new()
		pv.add_child(hr)
		var rn := UITheme.title_label(e.roman, 32, UITheme.GOLD if open else Color(0.45, 0.45, 0.45))
		rn.custom_minimum_size.x = 56
		hr.add_child(rn)
		var tl := UITheme.label("%s\n%s" % [e.name, e.year], 19, UITheme.TEXT if open else UITheme.TEXT_DIM, "title")
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hr.add_child(tl)
		var idx := i
		var vbtn := UITheme.button("Вид", func(): bg.set_era(idx), 52, 70)
		hr.add_child(vbtn)
		pv.add_child(UITheme.wrap_label(e.desc, 15, UITheme.TEXT if open else UITheme.TEXT_DIM))
		if open:
			var b := UITheme.button("Отправиться" if i != Profile.current_era else "Продолжить здесь", func():
				Profile.current_era = idx
				SaveSys.save_game()
				_launch("world", {}), 54, 0)
			pv.add_child(b)
		elif i > 0:
			var st := Profile.trial_status(i - 1)
			var t := "[color=#aaaaaa]Закрыто. Суд Хроноса эпохи «%s»:[/color]\n" % DBEras.era(i - 1).name
			for line in st.lines:
				t += "%s %s\n" % [UITheme.check(line[1]), line[0]]
			var r := UITheme.rich(t.strip_edges())
			r.add_theme_font_size_override("normal_font_size", 15)
			pv.add_child(r)
		vb.add_child(p)

func _panel_achievements() -> void:
	var vb := _scroll_box()
	var total := Profile.ACHIEVEMENTS.size()
	var got := 0
	for k in Profile.ACHIEVEMENTS:
		if Profile.achievements.has(k):
			got += 1
	vb.add_child(UITheme.label("Получено: %d / %d" % [got, total], 20, UITheme.GOLD, "bold"))
	vb.add_child(UITheme.bar(got, total, UITheme.GOLD, 12))
	for k in Profile.ACHIEVEMENTS:
		var a: Array = Profile.ACHIEVEMENTS[k]
		var on := Profile.achievements.has(k)
		var p := UITheme.panel(Color(0.08, 0.07, 0.1, 0.9), UITheme.GOLD if on else Color(0.22, 0.22, 0.22), 10, 10)
		var row := HBoxContainer.new()
		p.add_child(row)
		var icon := UITheme.label("★" if on else "☆", 30, UITheme.GOLD if on else Color(0.4, 0.4, 0.4))
		icon.custom_minimum_size.x = 40
		row.add_child(icon)
		var pv := VBoxContainer.new()
		pv.add_theme_constant_override("separation", 0)
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pv)
		pv.add_child(UITheme.label(a[0], 19, UITheme.GOLD if on else UITheme.TEXT_DIM, "bold"))
		pv.add_child(UITheme.wrap_label(a[1], 15, UITheme.TEXT if on else UITheme.TEXT_DIM))
		if on:
			var dt := Time.get_datetime_dict_from_unix_time(int(Profile.achievements[k]))
			pv.add_child(UITheme.label("%02d.%02d.%d" % [dt.day, dt.month, dt.year], 13, UITheme.TEXT_DIM))
		vb.add_child(p)

func _quit() -> void:
	Settings.save_settings()
	get_tree().quit()

func on_back_pressed() -> void:
	if ui.is_open():
		ui.close_top()
	elif _panel_name != "":
		_close_panel()
	else:
		_quit()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.physical_keycode == KEY_ESCAPE:
		on_back_pressed()
