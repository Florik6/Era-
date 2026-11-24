extends UIScreen
## Quest journal + Chronos trial requirements of the current era.

var _tabs: TabContainer

func build() -> void:
	make_frame("Журнал заданий")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	refresh()

func refresh() -> void:
	var cur := _tabs.current_tab if _tabs.get_tab_count() > 0 else 0
	clear(_tabs)
	var active = call_sys("quests", "active", [], [])
	var done = call_sys("quests", "completed", [], [])
	_tabs.add_child(_quest_list("Активные (%d)" % (active.size() if active is Array else 0), active if active is Array else [], true))
	_tabs.add_child(_quest_list("Завершённые", done if done is Array else [], false))
	_tabs.add_child(_trial_tab())
	_tabs.current_tab = clampi(cur, 0, _tabs.get_tab_count() - 1)

func _quest_list(nm: String, quests: Array, active: bool) -> Control:
	var outer := VBoxContainer.new()
	outer.name = nm
	var list := VBoxContainer.new()
	if quests.is_empty():
		list.add_child(UITheme.wrap_label("Нет заданий. Поговорите с жителями поселений, офицерами группировок или исследуйте мир — события создают новые цели." if active else "Пока ничего не завершено.", 18))
	for q in quests:
		list.add_child(_quest_card(q, active))
	outer.add_child(UITheme.scroll(list))
	return outer

func _quest_card(q: Dictionary, active: bool) -> Control:
	var tracked: bool = q.get("tracked", false)
	var state: String = q.get("state", "active")
	var bc := UITheme.GOLD if tracked else UITheme.GOLD_DIM
	if state == "failed":
		bc = UITheme.BAD
	elif state == "done":
		bc = UITheme.GOOD
	var p := UITheme.panel(Color(0.08, 0.075, 0.1, 0.92), bc, 12, 14)
	var row := HBoxContainer.new()
	p.add_child(row)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	row.add_child(vb)
	var t := "[b][color=#f5c966]%s[/color][/b]" % q.get("title", "Задание")
	if q.get("type", "") != "":
		t += "  [color=#888888](%s)[/color]" % _type_name(q.type)
	if tracked:
		t += "  [color=#66ffcc]● отслеживается[/color]"
	if state == "failed":
		t += "  [color=#ee6655]провалено[/color]"
	vb.add_child(UITheme.rich(t))
	if q.get("giver", "") != "":
		vb.add_child(UITheme.label("Заказчик: " + str(q.giver), 16, UITheme.TEXT_DIM))
	if q.get("desc", "") != "":
		vb.add_child(UITheme.wrap_label(q.desc, 17, UITheme.TEXT))
	var ot := ""
	for o in q.get("objectives", []):
		var need: int = int(o.get("need", 1))
		var cur: int = int(o.get("cur", 0))
		ot += "%s %s%s\n" % [UITheme.check(o.get("done", false)), o.get("text", ""), (" (%d/%d)" % [cur, need]) if need > 1 else ""]
	if ot != "":
		vb.add_child(UITheme.rich(ot.strip_edges()))
	if q.get("reward_text", "") != "":
		vb.add_child(UITheme.rich("[color=#ffcc55]Награда:[/color] " + q.reward_text))
	if active:
		var btns := VBoxContainer.new()
		row.add_child(btns)
		var tb := UITheme.button("Отслеживать" if not tracked else "Отслеживается", func():
			call_sys("quests", "track", [q.get("id", "")])
			refresh(), 56, 200)
		tb.disabled = tracked
		btns.add_child(tb)
		if q.get("abandonable", true):
			btns.add_child(UITheme.button("Отказаться", func(): _confirm_abandon(q), 56, 200))
	return p

func _type_name(t: String) -> String:
	var m := {"bounty": "охота за головами", "escort": "сопровождение", "defend": "защита", "clear": "зачистка", "explore": "исследование",
		"artifact": "поиск артефакта", "infiltrate": "проникновение", "boss": "охота на босса", "expedition": "экспедиция", "ritual": "ритуал",
		"trial": "испытание", "faction": "фракционное", "capture": "захват", "retrieve": "возвращение", "release": "освобождение", "story": "история"}
	return m.get(t, t)

func _confirm_abandon(q: Dictionary) -> void:
	var vb := modal(540)
	vb.add_child(UITheme.title_label("Отказаться от задания?", 26))
	vb.add_child(UITheme.wrap_label("«%s» будет провалено. Это может повлиять на репутацию." % q.get("title", ""), 18, UITheme.TEXT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	row.add_child(UITheme.button("Отказаться", func():
		call_sys("quests", "abandon", [q.get("id", "")])
		close_modal()
		refresh(), 56, 180))
	row.add_child(UITheme.button("Отмена", close_modal, 56, 160))

func _trial_tab() -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Суд Хроноса"
	var era := Profile.current_era
	var e := DBEras.era(era)
	var vb := VBoxContainer.new()
	vb.add_child(UITheme.title_label("Эпоха %s — %s" % [e.roman, e.name], 26))
	vb.add_child(UITheme.wrap_label("Чтобы открыть следующую эпоху, выполните требования и пройдите Суд Хроноса у эпохального портала.", 17))
	var st := Profile.trial_status(era)
	var t := ""
	for line in st.lines:
		t += "%s %s\n" % [UITheme.check(line[1]), line[0]]
	t += "\n[b]%s[/b]" % ("[color=#77ee77]Все требования выполнены — отправляйтесь к порталу Суда Хроноса![/color]" if st.ready else "[color=#cccccc]Требования ещё не выполнены.[/color]")
	vb.add_child(UITheme.rich(t))
	vb.add_child(UITheme.separator())
	vb.add_child(UITheme.label("Вехи эпохи (освоенные механики)", 22, UITheme.GOLD, "title"))
	var ms: Dictionary = Profile.progress(era).milestones
	var mt := ""
	for k in e.milestones:
		mt += "%s %s\n" % [UITheme.check(ms.has(k)), e.milestones[k]]
	vb.add_child(UITheme.rich(mt))
	vb.add_child(UITheme.rich("[color=#999999]Особенности эпохи: %s[/color]" % e.mechanics))
	outer.add_child(UITheme.scroll(vb))
	return outer
