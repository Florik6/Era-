extends UIScreen
## INVENTORY → ITEM → STUDY. The item's 3D model in the centre (rotate, zoom),
## numbered interactive parts on it, the hero's knowledge on the right, and
## short trials: "what is this part for?". Studying the parts gives basic
## understanding of the technology (stage III); special parts of rare items
## unlock their special abilities. Common mechanics for every weapon family;
## rare / mythic items add their own special part.

var item: Dictionary = {}
var view: InspectView
var info: RichTextLabel
var part_box: VBoxContainer
var msg: Label
var bar: ProgressBar
var stage_lbl: Label
var sel_part := ""
var _attempt := 0
var _cool := 0.0

func build() -> void:
	item = args.get("item", {})
	var c := make_frame("Изучение предмета")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_child(row)
	# left: the model and zoom controls
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	view = InspectView.new()
	view.item = item
	left.add_child(view)
	view.part_pressed.connect(_select_part)
	var zr := HBoxContainer.new()
	zr.alignment = BoxContainer.ALIGNMENT_CENTER
	zr.add_theme_constant_override("separation", 8)
	left.add_child(zr)
	zr.add_child(UITheme.button("−", func(): view.zoom(1.15), 52, 64))
	zr.add_child(UITheme.button("+", func(): view.zoom(0.87), 52, 64))
	zr.add_child(UITheme.button("⟲", func(): view.spin(-0.6), 52, 64))
	zr.add_child(UITheme.button("⟳", func(): view.spin(0.6), 52, 64))
	var hint := UITheme.label("Вращайте модель пальцем, щипок — приближение. Цифры — детали, которые можно изучить.", 15, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)
	# right: knowledge, actions, part details
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(440, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	stage_lbl = UITheme.label("", 19, UITheme.GOLD, "bold")
	stage_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(stage_lbl)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	right.add_child(bar)
	info = UITheme.rich("", false)
	info.custom_minimum_size = Vector2(0, 130)
	info.scroll_active = true
	right.add_child(info)
	var acts := GridContainer.new()
	acts.columns = 3
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	right.add_child(acts)
	acts.add_child(_small("Осмотреть", func(): _act("examine")))
	acts.add_child(_small("Назначение", func(): _act("identify")))
	acts.add_child(_small("Сравнить", func(): _act("compare")))
	acts.add_child(_small("Специалист", func(): _act("specialist")))
	acts.add_child(_small("Ознакомиться", func(): _act("familiarize")))
	acts.add_child(_small("Знания", func(): manager.open("tech")))
	part_box = VBoxContainer.new()
	part_box.add_theme_constant_override("separation", 6)
	part_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var psc := UITheme.scroll(part_box)
	psc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(psc)
	msg = UITheme.label("", 17, UITheme.ACCENT)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(msg)
	refresh()

func _small(text: String, cb: Callable) -> Button:
	var b := UITheme.button(text, cb, 46, 138)
	b.add_theme_font_size_override("font_size", 17)
	return b

func pd():
	return Profile.char

func refresh() -> void:
	if item.is_empty() or pd() == null:
		return
	var d = pd()
	var fam := TechKnow.item_family(item)
	var parts: Array = []
	for p in TechKnow.parts_of(item):
		parts.append([str(p[0]), str(p[1]), float(p[3]), TechKnow.part_known(d, item, str(p[0]))])
	view.set_parts(parts)
	var t := ""
	var nm := ItemDB.display_name(item)
	t += "[b]%s[/b]\n" % nm
	if fam != "":
		var x := TechKnow.fam_xp(d, fam)
		var st := TechKnow.stage_of_xp(x)
		var a = Game.player
		var ist: int = TechKnow.item_stage(a, item) if a != null else st
		stage_lbl.text = "Стадия %s — %s" % [TechKnow.STAGE_SHORT[ist], TechKnow.STAGE_NAMES[ist]]
		var lo: float = TechKnow.XP_STAGE[st]
		var hi: float = TechKnow.XP_STAGE[mini(st + 1, 5)]
		bar.max_value = 100.0
		bar.value = 100.0 if st >= 5 else clampf((x - lo) / maxf(1.0, hi - lo) * 100.0, 0.0, 100.0)
		if st >= 2 or bool(d.tech_models.get(str(item.base), {}).get("identified", false)):
			t += "Технология: [b]%s[/b] (%s)\n" % [TechKnow.fam_name(fam), TechKnow.CATS[TechKnow.fam_cat(fam)]]
		else:
			t += "Технология: неизвестна\n"
		var mr: Dictionary = d.tech_models.get(str(item.base), {})
		if st >= 3 and not TechKnow.model_known(d, str(item.base)):
			t += "[color=#ffcc66]Новая модель знакомой технологии: нужно короткое ознакомление.[/color]\n"
		if TechKnow.gap(d, fam) >= 2:
			t += "[color=#ff9966]Технология намного опережает всё, что вы видели: без знаний эпохи догадки придётся подтверждать серией испытаний.[/color]\n"
		var eff := ""
		match ist:
			1, 2:
				eff = "Пользоваться нельзя: непонятно, как устройство срабатывает."
			3:
				eff = "Можно стрелять: низкая точность, медленная подготовка и перезарядка, особые режимы недоступны."
			4:
				eff = "Уверенное владение: особые режимы и первые оружейные навыки."
			5:
				eff = "Мастер: полная точность, особые боеприпасы, продвинутые приёмы."
		t += "%s\n" % eff
		t += "Опыт освоения: %d (%s)\n" % [int(x), "исследованием — до %d, дальше только практикой" % int(TechKnow.RESEARCH_CAP) if st < 3 else "растёт от тренировок и боя"]
		if bool(mr.get("examined", false)):
			t += "[color=#aaaaaa]%s[/color]\n" % TechKnow._looks(item)
	else:
		stage_lbl.text = "Знакомый предмет"
		bar.value = 100.0
	if TechKnow.has_special(item):
		var sp: bool = bool(d.tech_models.get(str(item.base), {}).get("special", false))
		t += "Особый узел: %s\n" % ("[color=#88ff99]понятен — особые способности доступны[/color]" if sp else "[color=#ffcc66]не изучен — особые способности недоступны[/color]")
	info.text = t
	_show_part()

func _act(kind: String) -> void:
	var d = pd()
	var r := ""
	match kind:
		"examine":
			r = TechKnow.examine(d, item)
			view.spin(0.9, 0.1)
		"identify":
			r = TechKnow.identify(d, item)
		"compare":
			r = TechKnow.compare(d, item)
		"familiarize":
			r = TechKnow.familiarize(d, item)
		"specialist":
			r = _specialist_text()
	msg.text = r if r != "" else "Нечего добавить."
	refresh()

func _specialist_text() -> String:
	var fam := TechKnow.item_family(item)
	if fam == "":
		return "Особые предметы объясняет Последний Свидетель — путешественник между эпохами."
	var fe := TechKnow.fam_era(fam)
	var lines: Array = []
	lines.append("%s эпохи «%s» обучает этой технологии." % [TechKnow.TEACHER_TITLES[fe], DBEras.era(fe).name])
	lines.append("Последний Свидетель (путешественник между эпохами) учит в любой эпохе.")
	lines.append("Трактат «%s» и фрагменты технологий из разломов тоже помогут." % TechKnow.CATS[TechKnow.fam_cat(fam)])
	lines.append("Можно разобраться и самому: изучайте детали на модели.")
	return " ".join(lines)

func _select_part(pid: String) -> void:
	sel_part = pid
	_attempt = 0
	_show_part()

func _show_part() -> void:
	for ch in part_box.get_children():
		ch.queue_free()
	if sel_part == "":
		part_box.add_child(UITheme.label("Выберите деталь на модели (цифры).", 16, UITheme.TEXT_DIM))
		return
	var d = pd()
	var p := TechKnow.part_def(item, sel_part)
	if p.is_empty():
		return
	var known := TechKnow.part_known(d, item, sel_part)
	var hd := UITheme.label(str(p[1]), 20, UITheme.GOLD, "bold")
	part_box.add_child(hd)
	if known:
		var l := UITheme.label("Назначение: %s." % str(p[2]), 17, UITheme.GOOD)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		part_box.add_child(l)
		return
	if sel_part == "special" and not TechKnow.special_study_ok(d, item):
		var l2 := UITheme.label(TechKnow.special_need_text(d, item), 16, UITheme.BAD)
		l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		part_box.add_child(l2)
		return
	var fam := TechKnow.item_family(item)
	var need := TechKnow.trials_needed(d, fam, bool(p[4])) if fam != "" else 1
	var q := UITheme.label("Испытание: для чего служит эта деталь?" + (" (без знаний эпохи — %d верных догадки подряд)" % need if need > 1 else ""), 16, UITheme.TEXT)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	part_box.add_child(q)
	for o in TechKnow.trial_options(item, sel_part, _attempt):
		var choice: String = o
		var b := UITheme.button(choice, func(): _answer(choice), 46, 400)
		b.add_theme_font_size_override("font_size", 17)
		b.disabled = _cool > 0.0
		part_box.add_child(b)

func _answer(choice: String) -> void:
	if _cool > 0.0:
		return
	var res := TechKnow.answer(pd(), item, sel_part, choice)
	msg.text = str(res.msg)
	_attempt += 1
	if not bool(res.ok):
		_cool = 1.2           # a short pause before the next guess (no penalty)
	if bool(res.done):
		Audio.play_sfx("pickup", null, -4.0)
	refresh()

func _process(delta: float) -> void:
	if _cool > 0.0:
		_cool -= delta
		if _cool <= 0.0:
			_show_part()
