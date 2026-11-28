extends UIScreen
## «Технологическое познание»: the hero's knowledge of the technologies of
## all eras — 8 knowledge indices, technology families with their stage,
## the Tech Cognition skills and the Historical Knowledge Memory.

var body: VBoxContainer

func build() -> void:
	var c := make_frame("Технологическое познание")
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc := UITheme.scroll(body)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.add_child(sc)
	refresh()

func refresh() -> void:
	clear(body)
	var d = Profile.char
	if d == null:
		return
	body.add_child(UITheme.label("Знания принадлежат герою и сохраняются при переходах между эпохами.", 16, UITheme.TEXT_DIM))
	# --- 8 knowledge indices
	body.add_child(UITheme.label("Показатели знаний", 22, UITheme.GOLD, "title"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	body.add_child(grid)
	for cat in TechKnow.CAT_ORDER:
		var st := cat_stage(d, cat)
		var l := UITheme.label("%s — %s" % [TechKnow.CATS[cat], TechKnow.STAGE_SHORT[st] + " " + TechKnow.STAGE_NAMES[st]], 17, UITheme.TEXT if st >= 3 else UITheme.TEXT_DIM)
		grid.add_child(l)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(200, 12)
		pb.show_percentage = false
		pb.max_value = 4.0
		pb.value = float(st - 1)          # I … V
		grid.add_child(pb)
	# --- families
	body.add_child(UITheme.label("Технологические семейства", 22, UITheme.GOLD, "title"))
	var fg := GridContainer.new()
	fg.columns = 3
	fg.add_theme_constant_override("h_separation", 18)
	body.add_child(fg)
	for fam in TechKnow.FAMILIES:
		var x := TechKnow.fam_xp(d, fam)
		var st2 := TechKnow.stage_of_xp(x)
		fg.add_child(UITheme.label(TechKnow.fam_name(fam), 17, UITheme.TEXT if st2 >= 3 else UITheme.TEXT_DIM))
		fg.add_child(UITheme.label("%s — %s" % [TechKnow.STAGE_SHORT[st2], TechKnow.STAGE_NAMES[st2]], 16, UITheme.ACCENT if st2 >= 4 else UITheme.TEXT_DIM))
		var pb2 := ProgressBar.new()
		pb2.custom_minimum_size = Vector2(180, 12)
		pb2.show_percentage = false
		var lo: float = TechKnow.XP_STAGE[st2]
		var hi: float = TechKnow.XP_STAGE[mini(st2 + 1, 5)]
		pb2.max_value = 100.0
		pb2.value = 100.0 if st2 >= 5 else clampf((x - lo) / maxf(1.0, hi - lo) * 100.0, 0.0, 100.0)
		fg.add_child(pb2)
	# --- Tech Cognition skills
	body.add_child(UITheme.label("Ветвь «Технологическое познание» — очков: %d" % int(d.tech_pts), 22, UITheme.GOLD, "title"))
	for s in TechKnow.SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		var learned: bool = str(s[0]) in d.tech_skills
		var txt := UITheme.label("%s%s (%d) — %s%s" % ["✓ " if learned else "", str(s[1]), int(s[3]), str(s[2]), (" Требует: «%s»." % TechKnow.skill_name(str(s[4]))) if str(s[4]) != "" else ""], 16, UITheme.GOOD if learned else UITheme.TEXT)
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(txt)
		if not learned:
			var sid: String = s[0]
			var b := UITheme.button("Изучить", func():
				var why := TechKnow.learn_skill(d, sid)
				show_toast("Навык изучен" if why == "" else why, UITheme.GOOD if why == "" else UITheme.BAD)
				refresh(), 46, 130)
			row.add_child(b)
	# --- memory
	body.add_child(UITheme.label("Память эпох", 22, UITheme.GOLD, "title"))
	var mem: Dictionary = d.tech_mem
	var eras: Array = []
	for e in mem.get("eras", []):
		eras.append(str(DBEras.era(int(e)).name))
	var lines: Array = []
	lines.append("Посещённые эпохи: %s" % (", ".join(eras) if not eras.is_empty() else "—"))
	lines.append("Изученные схемы и трактаты: %s" % _names(mem.get("schemas", [])))
	lines.append("Пройденное обучение: %s" % _names(mem.get("training", [])))
	lines.append("Известные способы обслуживания: %s" % _names(mem.get("maint", [])))
	var mastered: Array = []
	for b2 in d.tech_models:
		if bool(d.tech_models[b2].get("fam", false)):
			mastered.append(str(ItemDB.base(str(b2)).get("name", b2)))
	lines.append("Освоенные модели: %s" % (", ".join(mastered.slice(0, 12)) if not mastered.is_empty() else "—"))
	var r := UITheme.rich("\n".join(lines))
	body.add_child(r)

func _names(arr: Array) -> String:
	if arr.is_empty():
		return "—"
	var out: Array = []
	for k in arr:
		var key := str(k)
		out.append(TechKnow.CATS.get(key, TechKnow.fam_name(key) if TechKnow.FAMILIES.has(key) else key))
	return ", ".join(out)

## A category's stage: the best of its general knowledge and its families.
static func cat_stage(d, cat: String) -> int:
	var st := TechKnow.stage_of_xp(minf(TechKnow.cat_xp(d, cat), TechKnow.RESEARCH_CAP))
	for fam in TechKnow.FAMILIES:
		if TechKnow.fam_cat(fam) == cat:
			st = maxi(st, TechKnow.stage_of_xp(TechKnow.fam_xp(d, fam)))
	if cat == "anomalous":
		for b in d.tech_models:
			if bool(d.tech_models[b].get("special", false)):
				st = maxi(st, 3)
	return st
