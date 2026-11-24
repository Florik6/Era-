extends UIScreen
## Era portal: travel between unlocked eras, see Chronos trial requirements.

func build() -> void:
	make_frame(args.get("title", "Эпохальный портал"))
	var list := VBoxContainer.new()
	content.add_child(UITheme.scroll(list))
	for i in DBEras.ERA_COUNT:
		list.add_child(_card(i))

func _card(i: int) -> Control:
	var e := DBEras.era(i)
	var open := Profile.is_era_unlocked(i)
	var current := i == Profile.current_era
	var col: Color = e.sky_horizon.lerp(UITheme.GOLD, 0.4)
	var p := UITheme.panel(Color(0.07, 0.065, 0.09, 0.92), UITheme.GOLD if current else (col.darkened(0.3) if open else Color(0.25, 0.25, 0.25)), 12, 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	p.add_child(row)
	var num := UITheme.title_label(e.roman, 48, col if open else Color(0.4, 0.4, 0.4))
	num.custom_minimum_size.x = 90
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(num)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	row.add_child(vb)
	var ttl := "%s · %s%s" % [e.name, e.year, "  — вы здесь" if current else ""]
	vb.add_child(UITheme.label(ttl, 24, UITheme.GOLD if open else UITheme.TEXT_DIM, "title"))
	vb.add_child(UITheme.wrap_label(e.desc, 17, UITheme.TEXT if open else UITheme.TEXT_DIM))
	if open:
		vb.add_child(UITheme.wrap_label("Особенности: " + e.mechanics, 15))
	if i > 0 and not Profile.is_era_unlocked(i):
		var st := Profile.trial_status(i - 1)
		var t := "[color=#cccccc]Для открытия — Суд Хроноса эпохи «%s»:[/color]\n" % DBEras.era(i - 1).name
		for line in st.lines:
			t += "%s %s   " % [UITheme.check(line[1]), line[0]]
		vb.add_child(UITheme.rich(t))
	var cb: Callable = args.get("select_cb", Callable())
	var b := UITheme.button("Отправиться" if open and not current else ("Текущая" if current else "Закрыто"), func():
		close()
		if cb.is_valid():
			cb.call(i), 60, 190)
	b.disabled = not open or current or not cb.is_valid()
	row.add_child(b)
	return p
