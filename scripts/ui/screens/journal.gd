extends UIScreen
## Quest journal + Chronos trial requirements of the current era + the
## Bestiary (Beasts of the Ages): creatures and bosses of every era, with
## knowledge opened step by step (seen → studied → mastered).

var _tabs: TabContainer
var _best_era := -1
var _best_sel := ""

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
	_tabs.add_child(_bestiary_tab(false))
	_tabs.add_child(_bestiary_tab(true))
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
		"trial": "испытание", "faction": "фракционное", "capture": "захват", "retrieve": "возвращение", "release": "освобождение", "story": "история", "hunt": "охота на зверя", "lead": "след чудовища"}
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

# ------------------------------------------------------------------ bestiary
const KNOW_NAMES := ["неизвестно", "замечено", "изучено", "освоено"]
const HAB_NAMES := {"forest": "лес", "plains": "равнины", "mountain": "горы", "snow": "снега", "swamp": "болота", "sand": "пустоши", "cave": "пещеры",
	"ruins": "руины", "coast": "побережье", "urban": "окраины городов", "industrial": "промзоны", "lab": "лаборатории", "anomaly": "аномалии", "dungeon": "подземелья"}
const ERA_LABEL := ["Средневековье", "Возрождение", "Индустриальная эпоха", "Современность", "Будущее"]
const RES_NAMES := {"slash": "режущий", "pierce": "колющий", "blunt": "дробящий", "fire": "огонь", "ice": "лёд", "lightning": "молния", "dark": "тьма",
	"light": "свет", "poison": "яд", "time": "время", "energy": "энергия", "earth": "земля", "air": "воздух"}

func _bestiary_tab(bosses: bool) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Боссы" if bosses else "Бестиарий"
	if _best_era < 0:
		_best_era = Profile.current_era
	var top := HBoxContainer.new()
	outer.add_child(top)
	for e in 5:
		var era_i := e
		var b := UITheme.button(DBEras.era(e).roman, func():
			_best_era = era_i
			_best_sel = ""
			refresh(), 48, 70)
		b.disabled = _best_era == e
		top.add_child(b)
	var ids: Array = []
	if bosses:
		for bd in DBBeasts.bosses_of_era(_best_era):
			ids.append(bd.id)
	else:
		for cd in DBCreatures.of_era(_best_era):
			ids.append(cd.id)
	var known := 0
	for id in ids:
		if BeastWorld.knowledge(id) > 0:
			known += 1
	top.add_child(UITheme.label("  Открыто: %d / %d" % [known, ids.size()], 18, UITheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(row)
	var list := VBoxContainer.new()
	var sc := UITheme.scroll(list)
	sc.custom_minimum_size.x = 360
	sc.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(sc)
	for id in ids:
		var k := BeastWorld.knowledge(id)
		var nm: String = (DBBeasts.boss(id).name if bosses else DBCreatures.get_def(id).name) if k > 0 else "???"
		var sid: String = id
		var bt := UITheme.button(nm, func():
			_best_sel = sid
			refresh(), 48, 340)
		bt.disabled = k == 0
		list.add_child(bt)
	var det := VBoxContainer.new()
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(UITheme.scroll(det))
	if _best_sel != "" and _best_sel in ids:
		det.add_child(_beast_card(_best_sel, bosses))
	else:
		det.add_child(UITheme.wrap_label("Выберите существо. Сведения открываются, когда вы встречаете существо (замечено), побеждаете его несколько раз (изучено: слабости и добыча) и становитесь опытным охотником (освоено: редкие формы)." if not bosses else
			"Боссы эпохи: подземелья, логова и титаны. Победа над боссом открывает его полную запись, трофей и редкую добычу.", 17))
	return outer

func _beast_card(id: String, boss: bool) -> Control:
	var d: Dictionary = DBBeasts.boss(id) if boss else DBCreatures.get_def(id)
	var e: Dictionary = BeastWorld.book().get(id, {})
	var k := BeastWorld.knowledge(id)
	var vb := VBoxContainer.new()
	if k == 0:
		vb.add_child(UITheme.title_label("???", 26))
		vb.add_child(UITheme.wrap_label("Существо ещё не встречено. Запись появится после первой встречи.", 17))
		return vb
	vb.add_child(UITheme.title_label(d.name, 26))
	var cat: String = DBCreatures.CAT_NAMES.get(d.get("cat", ""), {"dungeon": "босс подземелья", "world": "мировой босс", "titan": "титан"}.get(d.get("cat", ""), ""))
	var sub := "%s · %s" % [cat, KNOW_NAMES[k]]
	if not boss:
		sub += " · " + DBCreatures.BEH_NAMES.get(d.get("beh", ""), "")
	vb.add_child(UITheme.label(sub, 17, UITheme.GOLD_DIM))
	vb.add_child(UITheme.wrap_label(String(d.get("desc", "")), 18, UITheme.TEXT))
	var t := "[color=#bbbbbb]Эпоха: %s · Встречено: %d · Побеждено: %d[/color]\n" % [ERA_LABEL[clampi(int(d.get("era", 0)), 0, 4)], int(e.get("seen", 0)), int(e.get("kills", 0))]
	if not boss:
		var habs: Array = []
		for h in d.get("hab", []):
			habs.append(HAB_NAMES.get(str(h), str(h)))
		t += "Обитает: %s\n" % ", ".join(habs)
		var danger: String = {"common": "низкая", "dangerous": "средняя", "elite": "высокая", "miniboss": "очень высокая"}.get(str(d.get("cat", "")), "?")
		t += "Опасность: %s\n" % danger
	if k >= 2:
		var weak: Array = []
		var strong: Array = []
		var res: Dictionary = d.get("res", {})
		for r in res:
			if float(res[r]) < 0.0:
				weak.append(RES_NAMES.get(r, r))
			elif float(res[r]) > 0.0:
				strong.append(RES_NAMES.get(r, r))
		t += "[color=#77ee77]Уязвимость:[/color] %s\n" % (", ".join(weak) if not weak.is_empty() else "нет явной")
		t += "[color=#ee9966]Сопротивление:[/color] %s\n" % (", ".join(strong) if not strong.is_empty() else "нет")
		var loot: Array = []
		for l in d.get("loot", []):
			var b := ItemDB.base(str(l[0]))
			loot.append("%s (%d%%)" % [b.get("name", str(l[0])), int(float(l[1]) * 100.0)])
		if not loot.is_empty():
			t += "Добыча: %s\n" % ", ".join(loot)
		if boss:
			var parts: Dictionary = d.get("parts", {})
			if not parts.is_empty():
				t += "[color=#ffcc55]Слабые места:[/color] разрушаемые части (%d)\n" % parts.size()
			t += "Фаз боя: %d\n" % d.get("phases", []).size()
	else:
		t += "[color=#888888]Слабости и добыча откроются после нескольких побед.[/color]\n"
	if k >= 3 and not boss:
		var vars: Array = []
		for vk in e.get("variants", {}):
			vars.append("%s ×%d" % [BeastWorld.VARIANTS[vk].name, int(e.variants[vk])])
		t += "Редкие формы: %s\n" % (", ".join(vars) if not vars.is_empty() else "не встречались")
	vb.add_child(UITheme.rich(t))
	return vb
