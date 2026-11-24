extends UIScreen
## Living Legends: notable NPCs with biographies built from real events,
## first-person memories, relations; archive of fallen legends.

var _list: VBoxContainer
var _detail: RichTextLabel
var _mode := "living"   # living | fallen | hall
var _tab_btns := {}

func build() -> void:
	var archive: bool = args.get("archive", false)
	make_frame("Архив легенд" if archive else "Живые легенды")
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	if not archive:
		_tab_btns["living"] = UITheme.button("Живые", func(): _set_mode("living"), 56, 170)
		tabs.add_child(_tab_btns.living)
	else:
		_mode = "fallen"
	_tab_btns["fallen"] = UITheme.button("Павшие легенды", func(): _set_mode("fallen"), 56, 220)
	tabs.add_child(_tab_btns.fallen)
	_tab_btns["hall"] = UITheme.button("Зал славы эпох", func(): _set_mode("hall"), 56, 220)
	tabs.add_child(_tab_btns.hall)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)
	_list = VBoxContainer.new()
	var ls := UITheme.scroll(_list)
	ls.custom_minimum_size.x = 380
	ls.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(ls)
	var dp := UITheme.panel(Color(0.05, 0.05, 0.07, 0.85), UITheme.GOLD_DIM, 12, 16)
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(dp)
	_detail = UITheme.rich("", false)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.scroll_active = true
	dp.add_child(_detail)
	refresh()

func _set_mode(m: String) -> void:
	_mode = m
	refresh()

func _records() -> Array:
	match _mode:
		"fallen":
			var f: Array = Profile.fallen_legends.duplicate()
			f.reverse()
			return f
		"hall":
			return Profile.hall_of_legends.duplicate()
	var recs = call_sys("legends", "records", [], [])
	if not (recs is Array):
		return []
	var arr: Array = recs.duplicate()
	arr.sort_custom(func(a, b):
		if a.get("legend", false) != b.get("legend", false):
			return a.get("legend", false)
		return float(a.get("renown", 0)) > float(b.get("renown", 0)))
	return arr

func refresh() -> void:
	for k in _tab_btns:
		_tab_btns[k].modulate = Color(1, 1, 1) if k == _mode else Color(0.65, 0.65, 0.65)
	clear(_list)
	var recs := _records()
	if recs.is_empty():
		var msg := "Пока никто не стал легендой. Выдающиеся воины прославятся победами, редкими находками и захватами территорий."
		if _mode == "fallen":
			msg = "Ни одна легенда ещё не пала."
		elif _mode == "hall":
			msg = "Зал славы пополняется при переходе между эпохами."
		_list.add_child(UITheme.wrap_label(msg, 17))
		_detail.text = ""
		return
	for r in recs:
		_list.add_child(_entry(r))
	_show(recs[0])

func _entry(r: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(360, 64)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var star := "★ " if r.get("legend", false) else ""
	var ttl: String = r.get("title", "")
	b.text = "%s%s%s\n%s" % [star, r.get("name", "?"), (" «%s»" % ttl) if ttl != "" else "", _sub(r)]
	b.add_theme_font_size_override("font_size", 16)
	var col := Color(1.0, 0.82, 0.35) if r.get("legend", false) else UITheme.TEXT
	if _mode == "fallen":
		col = Color(0.8, 0.7, 0.7)
	b.add_theme_color_override("font_color", col)
	b.pressed.connect(func():
		UITheme.click()
		_show(r))
	return b

func _sub(r: Dictionary) -> String:
	var parts: Array = []
	parts.append("ур. %d" % int(r.get("level", 1)))
	var arch: String = DBActors.ARCHETYPES.get(r.get("archetype", ""), {}).get("name", "")
	if arch != "":
		parts.append(arch)
	var fid: String = r.get("faction", "")
	if fid != "":
		parts.append(DBEras.faction(fid).get("name", fid))
	if r.has("era") and _mode != "living":
		parts.append(DBEras.era(int(r.era)).name)
	return " · ".join(PackedStringArray(parts))

func _bio(r: Dictionary) -> Dictionary:
	if _mode == "living":
		var b = call_sys("legends", "biography", [r], null)
		if b is Dictionary:
			return b
	# build from stored record fields (fallen / archived)
	var mem: Array = []
	for m in r.get("memories", []):
		mem.append(m.get("text", "") if m is Dictionary else str(m))
	var eq: Array = []
	var equip = r.get("equip", {})
	if equip is Dictionary:
		for s in equip:
			var it = equip[s]
			if it is Dictionary and not it.is_empty():
				eq.append(ItemDB.display_name(it))
	var rel := ""
	var rd: Dictionary = r.get("rel", {})
	if not rd.is_empty():
		rel = _rel_text(rd)
	var ach: Array = []
	if int(r.get("boss_kills", 0)) > 0:
		ach.append("Побед над боссами: %d" % int(r.boss_kills))
	if int(r.get("rare_items", 0)) > 0:
		ach.append("Редких находок: %d" % int(r.rare_items))
	if r.get("commander", false):
		ach.append("Командир")
	if r.get("leader", false):
		ach.append("Лидер организации")
	return {"backstory": r.get("backstory", ""), "chronicle": r.get("chronicle_text", []), "memories": mem,
		"victories": int(r.get("kills", 0)), "defeats": int(r.get("defeats", 0)), "relations": rel, "equipment": eq,
		"achievements": ach, "holdings": r.get("holdings", []), "era_history": r.get("era_history", []),
		"title": r.get("title", ""), "alive": r.get("alive", false), "cause": r.get("cause_of_death", "")}

static func _rel_text(rd: Dictionary) -> String:
	var parts: Array = []
	var names := {"respect": "уважение", "fear": "страх", "rivalry": "соперничество", "gratitude": "благодарность", "grudge": "обида"}
	for k in names:
		var v := float(rd.get(k, 0.0))
		if absf(v) >= 0.1:
			parts.append("%s %d%%" % [names[k], roundi(v * 100.0)])
	return "К вам: " + (", ".join(PackedStringArray(parts)) if not parts.is_empty() else "безразличие")

func _show(r: Dictionary) -> void:
	var b := _bio(r)
	var t := "[font_size=30][color=#f5c966]%s[/color][/font_size]" % r.get("name", "?")
	if b.get("title", "") != "":
		t += "  [i][color=#e8c070]«%s»[/color][/i]" % b.title
	t += "\n[color=#999999]%s[/color]\n" % _sub(r)
	if not b.get("alive", true) or _mode == "fallen":
		t += "[color=#cc7766]Пал(а): %s[/color]\n" % (b.get("cause", "") if b.get("cause", "") != "" else "обстоятельства неизвестны")
	t += _section("Предыстория", str(b.get("backstory", "")))
	t += _list_section("Хроника жизни", b.get("chronicle", []), "Записей пока нет.")
	t += _list_section("Воспоминания", b.get("memories", []), "Ничего не записано.", true)
	t += _section("Победы и поражения", "Побед: %d · Поражений: %d" % [int(b.get("victories", 0)), int(b.get("defeats", 0))])
	t += _section("Отношения", str(b.get("relations", "")))
	t += _list_section("Снаряжение", b.get("equipment", []), "—")
	t += _list_section("Достижения", b.get("achievements", []), "—")
	t += _list_section("Владения", b.get("holdings", []), "Нет владений.")
	t += _list_section("Переходы между эпохами", b.get("era_history", []), "Не покидал(а) свою эпоху.")
	_detail.text = t
	_detail.scroll_to_line(0)

func _section(h: String, body: String) -> String:
	if body.strip_edges() == "":
		body = "—"
	return "\n[b][color=#f5c966]%s[/color][/b]\n%s\n" % [h, body]

func _list_section(h: String, items, empty: String, italic: bool = false) -> String:
	var body := ""
	if items is Array and not items.is_empty():
		for x in items:
			body += ("• [i]«%s»[/i]\n" if italic else "• %s\n") % str(x)
	else:
		body = "[color=#888888]%s[/color]\n" % empty
	return "\n[b][color=#f5c966]%s[/color][/b]\n%s" % [h, body]
