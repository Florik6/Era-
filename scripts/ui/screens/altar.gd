extends UIScreen
## Cleansing ritual screen of altars (and the era equivalents: alchemical
## altar, occult workshop, anomaly lab, deactivation station).
## Left: cursed items (equipped first). Right: the selected item — rarity,
## stats, positive and identified negative properties, curse type, bond,
## every way to free it with ingredients, cost and availability.
## Tap a ritual → confirmation with consequences → «Начать очищение».
## args: {altar: Node3D, station: "altar"|"tech"}

var cursed: Array = []
var _list: VBoxContainer
var _details: RichTextLabel
var _rituals: VBoxContainer
var _sel_uid := -1
var _gold_lbl: Label

func build() -> void:
	var fl := Curses.flavour(Profile.current_era)
	var station: String = args.get("station", "altar")
	var title: String = (fl.title if station == "altar" else "Терминал отключения блокировок").to_upper()
	make_frame(title)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	left.add_child(UITheme.label("Проклятые предметы", 21, UITheme.GOLD, "title"))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	var ls := UITheme.scroll(_list)
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(ls)
	_gold_lbl = UITheme.label("", 18, Color(1.0, 0.85, 0.4), "bold")
	left.add_child(_gold_lbl)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 6)
	left.add_child(quick)
	quick.add_child(UITheme.button("Помолиться", _pray, 52, 140))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details = UITheme.rich()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(_details)
	inner.add_child(UITheme.label("Способы освобождения", 21, UITheme.GOLD, "title"))
	_rituals = VBoxContainer.new()
	_rituals.add_theme_constant_override("separation", 8)
	inner.add_child(_rituals)
	var rs := UITheme.scroll(inner)
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(rs)
	refresh()

func refresh() -> void:
	if not has_player():
		return
	var pl = Game.player
	cursed = Curses.cursed_items(pl.data)
	_gold_lbl.text = "%d %s" % [pl.data.gold, DBEras.era(Profile.current_era).currency]
	clear(_list)
	if cursed.is_empty():
		_list.add_child(UITheme.wrap_label("У вас нет проклятых предметов. Алтарь спокоен.", 18, UITheme.TEXT_DIM))
		_sel_uid = -1
	else:
		var still := false
		for e in cursed:
			if int(e.item.uid) == _sel_uid:
				still = true
		if not still:
			_sel_uid = int(cursed[0].item.uid)
		for e in cursed:
			var it: Dictionary = e.item
			var b := UIScreen.item_tile(it, Vector2(290, 70))
			var tag := "надето · " if e.equipped else "в сумке · "
			tag += "несъёмный" if Curses.is_bound(it) and e.equipped else ("связан" if Curses.is_bound(it) else "проклят")
			b.text = ItemDB.display_name(it) + "\n" + tag
			if int(it.uid) == _sel_uid:
				b.add_theme_stylebox_override("normal", UITheme.sb(Color(0.2, 0.08, 0.1, 0.95), UITheme.GOLD, 10, 3, 6))
			var uid := int(it.uid)
			b.pressed.connect(func():
				UITheme.click()
				select_uid(uid))
			_list.add_child(b)
	_show_selected()

func select_uid(uid: int) -> void:
	_sel_uid = uid
	refresh()

func _selected() -> Dictionary:
	for e in cursed:
		if int(e.item.uid) == _sel_uid:
			return e
	return {}

func details_text() -> String:
	return _details.get_parsed_text() if _details else ""

func _show_selected() -> void:
	clear(_rituals)
	var e := _selected()
	if e.is_empty():
		_details.text = "[color=#a8a39a]Подойдите сюда с проклятым снаряжением, чтобы распознать, ослабить или снять проклятие.\n\nПроклятые вещи бывают очень сильны: иногда разумнее разорвать связь и оставить силу.[/color]"
		return
	var it: Dictionary = e.item
	var c: Dictionary = it.curse
	var pl = Game.player
	var t := ItemDB.describe(it)
	t += "\n\n[b][color=#e05a5a]Проклятие[/color][/b]\n"
	t += "Тип: %s · %s\n" % [Curses.KIND_NAMES.get(Curses.kind(it), ""), Curses.SEVERITY_NAMES[Curses.severity(it)]]
	if c.get("hidden", true):
		t += "[color=#8a8a8a]Отрицательные свойства: не определены. Сначала проведите определение.[/color]\n"
	else:
		t += "Отрицательное свойство: [color=#ff8a7a]%s — %s[/color]\n" % [Curses.curse_name(it), Curses.curse_desc(it)]
		t += "Родной способ освобождения: %s\n" % ItemDB.RELEASE_METHODS.get(c.get("release", ""), "—")
		if c.get("release", "") == "boss":
			var bid: String = c.get("boss_id", "")
			var bd: bool = Game.world_state.get("bosses", {}).get(bid, {}).get("defeated", false)
			t += "  Связанный босс: %s — %s\n" % [DBActors.BOSSES.get(bid, {}).get("name", "?"), "[color=#7fdc8a]повержен[/color]" if bd else "жив"]
	if Curses.is_bound(it):
		t += "[color=#ff6a5a]Несъёмность: %s[/color]\n" % ("предмет нельзя снять или заменить" if e.equipped and c.get("active", false) else "свяжет владельца при надевании")
	else:
		t += "[color=#9adfa0]Связи нет: предмет можно снять.[/color]\n"
	_details.text = t
	var station: String = args.get("station", "altar")
	var rit: Array = Curses.rituals_for(it, pl, station)
	if rit.is_empty():
		_rituals.add_child(UITheme.wrap_label("Здесь нельзя ничего сделать с этим предметом.", 17))
	for r in rit:
		_rituals.add_child(_ritual_card(it, r))

func _ritual_card(it: Dictionary, r: Dictionary) -> Control:
	var p := UITheme.panel(Color(0.09, 0.08, 0.11, 0.95), UITheme.GOLD if r.available else Color(0.35, 0.32, 0.3), 12, 12)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var nm := UITheme.label(r.name + ("  · родной способ" if r.get("native", false) else ""), 19, UITheme.GOLD if r.available else UITheme.TEXT_DIM, "bold")
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(nm)
	var btn_text: String = {"reveal": "Определить", "unbind": "Разорвать связь", "cleanse": "Очистить"}.get(r.effect, "Выбрать")
	var b := UITheme.button(btn_text, func(): _confirm(int(it.uid), r), 52, 170)
	b.disabled = not r.available
	hb.add_child(b)
	vb.add_child(UITheme.wrap_label(r.desc, 16, UITheme.TEXT))
	var costs: Array = Curses.cost_lines(Game.player, r.costs)
	if not costs.is_empty():
		var ct := "Требуется: "
		var parts: Array = []
		for cl in costs:
			parts.append("[color=%s]%s[/color]" % ["#9adfa0" if cl[1] else "#ff7a6b", cl[0]])
		var rl := UITheme.rich(ct + ", ".join(parts))
		vb.add_child(rl)
	else:
		vb.add_child(UITheme.wrap_label("Бесплатно", 16, UITheme.GOOD))
	if not r.available:
		vb.add_child(UITheme.wrap_label("Недоступно: " + r.reason, 16, UITheme.BAD))
	return p

func _confirm(uid: int, r: Dictionary) -> void:
	var it: Dictionary = Curses.find_item(Game.player.data, uid)
	if it.is_empty():
		return
	var m := modal(680)
	m.add_theme_constant_override("separation", 10)
	m.add_child(UITheme.title_label(r.name, 26))
	m.add_child(UITheme.rich("[b]%s[/b]" % ItemDB.display_name(it)))
	m.add_child(UITheme.wrap_label("Последствия: " + r.consequence, 17, UITheme.TEXT))
	var parts: Array = []
	for cl in Curses.cost_lines(Game.player, r.costs):
		parts.append(cl[0])
	m.add_child(UITheme.wrap_label("Будет израсходовано после успешного ритуала: " + (", ".join(parts) if not parts.is_empty() else "ничего"), 16, UITheme.TEXT_DIM))
	m.add_child(UITheme.wrap_label("Ритуал прервётся без затрат, если вас ранят, рядом появится враг или вы отойдёте от алтаря.", 15, UITheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(row)
	var go_text: String = {"reveal": "Начать определение", "unbind": "Начать разрыв связи", "cleanse": "Начать очищение"}.get(r.effect, "Начать")
	row.add_child(UITheme.button(go_text, func():
		close_modal()
		start_ritual(uid, r.id), 58, 260))
	row.add_child(UITheme.button("Отмена", close_modal, 58, 160))

## Starts the in-world ritual (re-validated here). Closes the screen.
func start_ritual(uid: int, ritual_id: String) -> bool:
	if not has_player() or Game.world == null:
		return false
	var pl = Game.player
	if Game.world.get("active_ritual") != null and is_instance_valid(Game.world.active_ritual):
		show_toast("Ритуал уже идёт", UITheme.BAD)
		return false
	var it: Dictionary = Curses.find_item(pl.data, uid)
	if it.is_empty() or not Curses.is_cursed(it):
		show_toast("Предмет не проклят", UITheme.BAD)
		return false
	var r: Dictionary = {}
	for x in Curses.rituals_for(it, pl, args.get("station", "altar")):
		if x.id == ritual_id:
			r = x
	if r.is_empty():
		show_toast("Этот ритуал здесь недоступен", UITheme.BAD)
		return false
	if not r.available:
		show_toast("Недоступно: " + r.reason, UITheme.BAD)
		Audio.play_sfx("error")
		return false
	for a in Game.actors_near(pl.global_position, 9.0):
		if a != pl and not a.is_dead and Game.is_enemy(pl, a) and a.aggro.has("player"):
			show_toast("Рядом враги — ритуал невозможен", UITheme.BAD)
			return false
	var altar: Node3D = args.get("altar")
	if altar == null or not is_instance_valid(altar):
		altar = pl
	AltarRitual.begin(Game.world, altar, it, r, args.get("station", "altar"))
	close()
	return true

func _pray() -> void:
	if not has_player():
		return
	var pl = Game.player
	pl.heal(pl.max_hp)
	Audio.play_sfx("heal")
	show_toast("Силы восстановлены", UITheme.GOOD)
