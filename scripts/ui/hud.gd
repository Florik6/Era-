class_name HUD
extends CanvasLayer
## In-game HUD: vitals, level/xp, minimap, current objective, notifications,
## banners, boss bar, weapon info, quick menu buttons, low-health vignette.

var root: Control
var hp_bar: ProgressBar
var mp_bar: ProgressBar
var st_bar: ProgressBar
var xp_bar: ProgressBar
var name_lbl: Label
var lvl_lbl: Label
var status_lbl: Label
var objective_lbl: RichTextLabel
var time_lbl: Label
var weapon_lbl: Label
var fps_lbl: Label
var feed: VBoxContainer
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_lbl: Label
var vignette: ColorRect
var minimap: Control
var touch: TouchControls
var hints: Hints
var event_lbl: Label
var _boss = null
var _banner_t := 0.0
var _font_title: Font

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_font_title = load("res://assets/fonts/Philosopher-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/Philosopher-Bold.ttf") else null
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)
	_build_vitals()
	_build_topright()
	_build_center()
	touch = TouchControls.new()
	root.add_child(touch)
	hints = Hints.new()
	root.add_child(hints)
	Events.notify.connect(_on_notify)
	Events.banner.connect(_on_banner)
	Events.boss_engaged.connect(func(b): _boss = b)
	Events.level_up.connect(func(a, l):
		if a == Game.player:
			_on_banner("Новый уровень: %d" % l, "Здоровье и мана восстановлены", Color(1.0, 0.85, 0.3)))
	Events.mastery_up.connect(func(a, cat, l):
		if a == Game.player:
			var nm: String = ItemDB.CAT_NAMES.get(cat, DBSkills.SCHOOLS.get(cat, {}).get("name", cat))
			_on_notify("Мастерство «%s»: %d (+очко навыка)" % [nm, l], Color(0.6, 0.9, 1.0))
			Audio.play_sfx("mastery_up", null, -4.0))

func _bar(col: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	bg.border_color = Color(0, 0, 0, 0.8)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b

func _label(sz: int, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_vitals() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(24, 14)
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	lvl_lbl = _label(22, Color(1.0, 0.85, 0.35))
	row.add_child(lvl_lbl)
	name_lbl = _label(20)
	row.add_child(name_lbl)
	hp_bar = _bar(Color(0.85, 0.2, 0.22), 300, 20)
	box.add_child(hp_bar)
	mp_bar = _bar(Color(0.25, 0.45, 0.95), 260, 13)
	box.add_child(mp_bar)
	st_bar = _bar(Color(0.95, 0.8, 0.3), 220, 7)
	box.add_child(st_bar)
	status_lbl = _label(15, Color(0.9, 0.9, 1.0))
	box.add_child(status_lbl)
	feed = VBoxContainer.new()
	feed.position = Vector2(24, 175)
	feed.custom_minimum_size = Vector2(420, 0)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed)
	xp_bar = _bar(Color(0.55, 0.35, 1.0), 100, 6)
	xp_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	xp_bar.offset_top = -7
	xp_bar.offset_bottom = -1
	root.add_child(xp_bar)

func _build_topright() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_left = -330
	col.offset_right = -16
	col.offset_top = 12
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(col)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 6)
	col.add_child(btns)
	for spec in [["≡", "pause"], ["Сумка", "inventory"], ["Навыки", "skills"], ["Карта", "map"]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(52 if spec[0] == "≡" else 0, 50)
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE
		var nm: String = spec[1]
		b.pressed.connect(func():
			Audio.play_sfx("ui_click")
			if Game.world and Game.world.ui:
				Game.world.ui.open(nm))
		btns.add_child(b)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(170, 170)
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(minimap)
	time_lbl = _label(14, Color(0.9, 0.9, 0.85))
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(time_lbl)
	event_lbl = _label(15, Color(1.0, 0.7, 0.4))
	event_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	event_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_lbl.custom_minimum_size = Vector2(200, 0)
	col.add_child(event_lbl)
	fps_lbl = _label(13, Color(0.6, 1.0, 0.6))
	fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(fps_lbl)
	weapon_lbl = _label(15, Color(1, 0.92, 0.75))
	weapon_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_lbl.offset_left = -520
	weapon_lbl.offset_right = -24
	weapon_lbl.offset_top = -30
	weapon_lbl.offset_bottom = -10
	weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(weapon_lbl)

func _build_center() -> void:
	objective_lbl = RichTextLabel.new()
	objective_lbl.bbcode_enabled = true
	objective_lbl.fit_content = true
	objective_lbl.scroll_active = false
	objective_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective_lbl.offset_left = -260
	objective_lbl.offset_right = 260
	objective_lbl.offset_top = 10
	objective_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_lbl.add_theme_font_size_override("normal_font_size", 16)
	objective_lbl.add_theme_constant_override("outline_size", 5)
	objective_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	root.add_child(objective_lbl)
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.offset_left = -300
	boss_box.offset_right = 300
	boss_box.offset_top = 70
	boss_box.visible = false
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boss_box)
	boss_lbl = _label(20, Color(1.0, 0.75, 0.6))
	boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_title:
		boss_lbl.add_theme_font_override("font", _font_title)
	boss_box.add_child(boss_lbl)
	boss_bar = _bar(Color(0.8, 0.12, 0.1), 600, 18)
	boss_box.add_child(boss_bar)
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER)
	banner_box.offset_left = -420
	banner_box.offset_right = 420
	banner_box.offset_top = -170
	banner_box.offset_bottom = -60
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.modulate.a = 0.0
	root.add_child(banner_box)
	banner_title = _label(36, Color(1.0, 0.85, 0.35))
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_title:
		banner_title.add_theme_font_override("font", _font_title)
	banner_box.add_child(banner_title)
	banner_sub = _label(19)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_sub)

func _on_notify(text: String, col: Color) -> void:
	var l := _label(16, col)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	feed.add_child(l)
	var kids := feed.get_children()
	var extra := kids.size() - 6
	for i in maxi(0, extra):
		kids[i].queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)

func _on_banner(title: String, sub: String, col: Color) -> void:
	banner_title.text = title
	banner_title.add_theme_color_override("font_color", col)
	banner_sub.text = sub
	_banner_t = 4.0
	var tw := banner_box.create_tween()
	tw.tween_property(banner_box, "modulate:a", 1.0, 0.25)

func _process(delta: float) -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	hp_bar.max_value = pl.max_hp
	hp_bar.value = pl.hp
	mp_bar.max_value = pl.max_mana
	mp_bar.value = pl.mana
	st_bar.max_value = pl.max_stamina
	st_bar.value = pl.stamina
	xp_bar.max_value = pl.data.xp_needed()
	xp_bar.value = pl.data.xp
	lvl_lbl.text = "%d " % pl.data.level
	name_lbl.text = pl.data.name + ("  [%s]" % DBEras.faction(pl.faction_id).name if pl.faction_id != "" else "")
	var st: Array = []
	var names := {"burn": "Горение", "freeze": "Заморозка", "slow": "Замедление", "stun": "Оглушение", "wet": "Мокрый", "curse": "Проклят",
		"stealth": "Скрыт", "unstoppable": "Неудержим", "magic_shield": "Щит", "timeslow": "Время замедлено", "mutation": "Мутация", "haste": "Ускорение"}
	for k in pl.statuses:
		if names.has(k):
			st.append(names[k])
	if pl.shield_hp > 0.0:
		st.append("Щит %d" % pl.shield_hp)
	status_lbl.text = "  ".join(st)
	var w: Dictionary = pl.weapon()
	var cat: String = pl.weapon_cat()
	weapon_lbl.text = "%s · %s %d" % [ItemDB.display_name(w) if not w.is_empty() else "Кулаки", ItemDB.CAT_NAMES.get(cat, ""), pl.data.mastery_level(cat)]
	var wt := ""
	if Game.world and Game.world.weather and Game.world.weather.get("current") != null:
		wt = {"clear": "ясно", "cloudy": "облачно", "rain": "дождь", "storm": "гроза", "fog": "туман", "snow": "снег", "wind": "ветер"}.get(Game.world.weather.current, "")
	time_lbl.text = "%s · %s · %s" % [DBEras.era(Profile.current_era).name, Game.time_string(), wt]
	fps_lbl.visible = Settings.show_fps
	if Settings.show_fps:
		fps_lbl.text = "FPS %d" % Engine.get_frames_per_second()
	# objective
	var obj := ""
	if Game.world and Game.world.has_method("objective_text"):
		obj = Game.world.objective_text()
	objective_lbl.text = "[center]%s[/center]" % obj
	event_lbl.text = Game.world.director.status_text() if (Game.world and Game.world.get("director") and Game.world.director != null and Game.world.director.has_method("status_text")) else ""
	# boss bar
	if _boss != null and is_instance_valid(_boss) and not _boss.is_dead and _boss.global_position.distance_to(pl.global_position) < 50.0:
		boss_box.visible = true
		boss_bar.max_value = _boss.max_hp
		boss_bar.value = _boss.hp
		boss_lbl.text = "%s · фаза %d%s" % [_boss.display_name, _boss.phase + 1, "  [ЩИТ]" if _boss.shielded else ""]
	else:
		boss_box.visible = false
		if _boss != null and (not is_instance_valid(_boss) or _boss.is_dead):
			_boss = null
	var low: float = 1.0 - pl.hp / maxf(1.0, pl.max_hp)
	vignette.color.a = clampf((low - 0.6) * 0.8, 0.0, 0.35) * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.008))
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			var tw := banner_box.create_tween()
			tw.tween_property(banner_box, "modulate:a", 0.0, 0.6)
