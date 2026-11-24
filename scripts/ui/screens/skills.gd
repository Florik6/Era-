extends UIScreen
## Skills: independent weapon mastery trees, magic schools, ability slots, hybrids.

var _tabs: TabContainer
var _current_tab := 0

func build() -> void:
	make_frame("Навыки и мастерство")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	refresh()

func refresh() -> void:
	if _tabs.get_tab_count() > 0:
		_current_tab = _tabs.current_tab
	clear(_tabs)
	var d := player_data()
	var cur_cat := _current_cat(d)
	_tabs.add_child(_slots_tab(d, cur_cat))
	for cat in DBSkills.TREES:
		_tabs.add_child(_tree_tab(d, cat, cat == cur_cat))
	_tabs.add_child(_magic_tab(d))
	_tabs.add_child(_hybrid_tab(d))
	_tabs.current_tab = clampi(_current_tab, 0, _tabs.get_tab_count() - 1)

func _current_cat(d: CharData) -> String:
	if has_player() and Game.player.has_method("weapon_cat"):
		return Game.player.weapon_cat()
	var w: Dictionary = d.inv.equipped("main")
	if w.is_empty():
		return "unarmed"
	return ItemDB.base(w.base).get("cat", "unarmed")

static func ability_name(id: String) -> String:
	if id == "":
		return "— пусто —"
	var s := DBSkills.spell(id)
	if not s.is_empty():
		return "✦ " + s.name
	var n := DBSkills.find_skill(id)
	return n.get("name", id)

func _slots_tab(d: CharData, cat: String) -> Control:
	var vb := VBoxContainer.new()
	vb.name = "Ячейки"
	vb.add_child(UITheme.label("Текущее оружие: %s" % ItemDB.CAT_NAMES.get(cat, cat), 22, UITheme.GOLD, "title"))
	vb.add_child(UITheme.wrap_label("Три кнопки способностей на экране используют выбранные приёмы текущей категории оружия. Заклинания изученных школ можно поставить в ячейку при любом оружии — воин тоже может колдовать.", 17))
	var slots: Array = d.slots_for(cat)
	var pool: Array = d.known_actives(cat) + d.known_spells()
	for i in 3:
		var row := HBoxContainer.new()
		vb.add_child(row)
		var l := UITheme.label("Ячейка %d" % (i + 1), 20, UITheme.TEXT, "bold")
		l.custom_minimum_size.x = 130
		row.add_child(l)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(420, 56)
		ob.focus_mode = Control.FOCUS_NONE
		ob.add_theme_font_size_override("font_size", 20)
		ob.add_item("— пусто —")
		ob.set_item_metadata(0, "")
		var sel := 0
		for j in pool.size():
			ob.add_item(ability_name(pool[j]))
			ob.set_item_metadata(j + 1, pool[j])
			if pool[j] == slots[i]:
				sel = j + 1
		ob.select(sel)
		var idx := i
		ob.item_selected.connect(func(k):
			var id: String = ob.get_item_metadata(k)
			for q in 3:
				if q != idx and slots[q] == id and id != "":
					slots[q] = ""
			slots[idx] = id
			UITheme.click()
			refresh())
		row.add_child(ob)
		if slots[i] != "":
			var info := _ability_info(slots[i])
			row.add_child(UITheme.wrap_label(info, 16))
	if pool.is_empty():
		vb.add_child(UITheme.wrap_label("Пока нет активных приёмов: повышайте мастерство оружия и изучайте узлы дерева.", 18, UITheme.BAD))
	return vb

func _ability_info(id: String) -> String:
	var s := DBSkills.spell(id)
	if not s.is_empty():
		return "%s · мана %d · %.1f с" % [DBSkills.SCHOOLS[s.school].name, s.mana, s.cd]
	var n := DBSkills.find_skill(id)
	var cost := ""
	if n.has("stamina"):
		cost = "выносл. %d" % n.stamina
	elif n.has("mana"):
		cost = "мана %d" % n.mana
	return "%s · %.0f с" % [cost, n.get("cd", 0.0)]

func _tree_tab(d: CharData, cat: String, current: bool) -> Control:
	var outer := VBoxContainer.new()
	outer.name = ItemDB.CAT_NAMES.get(cat, cat) + (" •" if current else "")
	var m: Dictionary = d.mastery.get(cat, {"lvl": 0, "xp": 0, "pts": 0, "nodes": []})
	var hdr := HBoxContainer.new()
	outer.add_child(hdr)
	hdr.add_child(UITheme.label("Мастерство: %d" % m.lvl, 24, UITheme.GOLD, "title"))
	var xpb := UITheme.bar(m.xp, DBSkills.mastery_xp_needed(m.lvl), Color(0.85, 0.65, 0.25), 18)
	xpb.custom_minimum_size.x = 240
	xpb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hdr.add_child(xpb)
	hdr.add_child(UITheme.label("%d / %d опыта" % [m.xp, DBSkills.mastery_xp_needed(m.lvl)], 17, UITheme.TEXT_DIM))
	var pts := UITheme.label("Очки: %d" % m.pts, 22, UITheme.GOOD if m.pts > 0 else UITheme.TEXT_DIM, "bold")
	pts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(pts)
	var list := VBoxContainer.new()
	for n in DBSkills.TREES[cat]:
		list.add_child(_node_row(d, cat, n, m))
	outer.add_child(UITheme.scroll(list))
	return outer

func _node_row(d: CharData, cat: String, n: Dictionary, m: Dictionary) -> Control:
	var learned: bool = n.id in m.get("nodes", [])
	var can := d.can_learn(cat, n.id)
	var col := UITheme.GOOD if learned else (UITheme.GOLD if can else UITheme.TEXT_DIM)
	var p := UITheme.panel(Color(0.09, 0.08, 0.11, 0.9), col.darkened(0.3), 10, 12)
	var row := HBoxContainer.new()
	p.add_child(row)
	var badge := UITheme.label("★" if n.type == "active" else "◆", 30, col)
	badge.custom_minimum_size.x = 36
	row.add_child(badge)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	row.add_child(vb)
	var title := "%s  [%s]" % [n.name, "активный" if n.type == "active" else "пассивный"]
	vb.add_child(UITheme.label(title, 20, col, "bold"))
	vb.add_child(UITheme.wrap_label(n.desc, 17, UITheme.TEXT))
	var req := "Требуется мастерство %d" % n.lvl
	if n.req != "":
		req += " и «%s»" % DBSkills.node(cat, n.req).get("name", n.req)
	if n.has("cd"):
		req += " · перезарядка %.0f с" % n.cd
	vb.add_child(UITheme.label(req, 15, UITheme.TEXT_DIM))
	if learned:
		row.add_child(UITheme.label("Изучено", 18, UITheme.GOOD, "bold"))
	else:
		var b := UITheme.button("Изучить", func():
			if d.learn_node(cat, n.id):
				Audio.play_sfx("mastery_up")
				show_toast("Изучено: " + n.name)
				if has_player() and Game.player.has_method("refresh_gear"):
					Game.player.refresh_gear()
				refresh(), 56, 140)
		b.disabled = not can
		row.add_child(b)
	return p

func _magic_tab(d: CharData) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Магия"
	var list := VBoxContainer.new()
	for s in DBSkills.SCHOOLS:
		var sd: Dictionary = DBSkills.SCHOOLS[s]
		var known := d.knows_school(s)
		var lvl := d.school_level(s)
		var p := UITheme.panel(Color(0.08, 0.08, 0.11, 0.9), sd.color.darkened(0.2) if known else Color(0.25, 0.25, 0.25), 10, 12)
		var vb := VBoxContainer.new()
		p.add_child(vb)
		var hdr := HBoxContainer.new()
		vb.add_child(hdr)
		hdr.add_child(UITheme.swatch(sd.color, Vector2(22, 22)))
		hdr.add_child(UITheme.label("Школа: %s" % sd.name, 22, sd.color if known else UITheme.TEXT_DIM, "title"))
		if known:
			hdr.add_child(UITheme.label("уровень %d" % lvl, 19, UITheme.TEXT, "bold"))
			var xb := UITheme.bar(d.schools[s].xp, DBSkills.mastery_xp_needed(lvl), sd.color, 16)
			xb.custom_minimum_size.x = 200
			xb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hdr.add_child(xb)
			var bonus := []
			if lvl >= 3:
				bonus.append("+10% урона школы")
			if lvl >= 6:
				bonus.append("-15% затрат маны")
			if not bonus.is_empty():
				hdr.add_child(UITheme.label("· " + ", ".join(bonus), 16, UITheme.GOOD))
		else:
			hdr.add_child(UITheme.label("не изучена — найдите или купите «Фолиант»", 17, UITheme.TEXT_DIM))
		var grid := GridContainer.new()
		grid.columns = 2
		vb.add_child(grid)
		for sp in sd.spells:
			var open: bool = known and lvl >= sp.lvl
			var t := "[b][color=#%s]%s[/color][/b] — %s\n[color=#999999]ур. школы %d · мана %d · %.1f с%s[/color]" % [
				(sd.color if open else Color(0.5, 0.5, 0.5)).to_html(false), sp.name, sp.desc, sp.lvl, sp.mana, sp.cd,
				(" · урон %d" % sp.dmg) if sp.dmg > 0 else ""]
			var r := UITheme.rich(t)
			r.custom_minimum_size = Vector2(520, 0)
			r.add_theme_font_size_override("normal_font_size", 16)
			r.add_theme_font_size_override("bold_font_size", 17)
			grid.add_child(r)
		list.add_child(p)
	outer.add_child(UITheme.scroll(list))
	return outer

func _hybrid_tab(d: CharData) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Гибриды"
	outer.add_child(UITheme.wrap_label("Гибридные способности открываются автоматически при развитии нескольких специализаций.", 17))
	var active := d.hybrids()
	var list := VBoxContainer.new()
	for h in DBSkills.HYBRIDS:
		var hd: Dictionary = DBSkills.HYBRIDS[h]
		var on: bool = h in active
		var req := _hybrid_req(hd)
		var r := UITheme.rich("%s [b][color=#%s]%s[/color][/b]\n%s\n[color=#999999]%s[/color]" % [
			UITheme.check(on), ("66ffcc" if on else "aaaaaa"), hd.name, hd.desc, req])
		var p := UITheme.panel(Color(0.08, 0.08, 0.11, 0.9), UITheme.GOOD.darkened(0.3) if on else Color(0.25, 0.25, 0.25), 10, 12)
		p.add_child(r)
		list.add_child(p)
	outer.add_child(UITheme.scroll(list))
	return outer

func _hybrid_req(hd: Dictionary) -> String:
	var a: String = hd.a
	var an := ""
	match a:
		"melee": an = "любое оружие ближнего боя"
		"ranged": an = "лук или огнестрельное"
		"multi": return "Мастерство %d в двух и более категориях оружия" % hd.a_lvl
		_:
			var parts: Array = []
			for c in a.split("|"):
				parts.append(ItemDB.CAT_NAMES.get(c, c))
			an = " / ".join(parts)
	var bn := ""
	if hd.b == "school":
		bn = "любая школа магии"
	else:
		var parts2: Array = []
		for s in String(hd.b).split("|"):
			parts2.append(DBSkills.SCHOOLS.get(s, {}).get("name", s))
		bn = "школа " + " / ".join(parts2)
	return "Требуется: %s (мастерство %d) + %s (уровень %d)" % [an, hd.a_lvl, bn, hd.b_lvl]
