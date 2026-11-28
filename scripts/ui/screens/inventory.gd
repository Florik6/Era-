extends UIScreen
## Inventory: equipment slots, character stats, bag grid and item cards.

var _equip_box: GridContainer
var _bag: GridContainer
var _stats: RichTextLabel
var _gold: Label
var _press_t := {}
var _filter := {"group": "all", "query": "", "sort": "type"}
var _preview: GearPreview

func build() -> void:
	make_frame("Инвентарь")
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)
	# left: equipment + stats
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 400
	row.add_child(left)
	left.add_child(UITheme.label("Снаряжение", 22, UITheme.GOLD, "title"))
	_equip_box = GridContainer.new()
	_equip_box.columns = 3
	left.add_child(_equip_box)
	# try-on preview: drag to rotate, pinch to zoom
	_preview = GearPreview.new()
	_preview.custom_minimum_size = Vector2(380, 300)
	left.add_child(_preview)
	var look_row := HBoxContainer.new()
	look_row.add_theme_constant_override("separation", 6)
	left.add_child(look_row)
	look_row.add_child(UITheme.button("Шлем: вкл/выкл", func(): _toggle_helm(), 46, 170))
	look_row.add_child(UITheme.button("Цвет плаща", func(): _next_dye(), 46, 150))
	_stats = UITheme.rich()
	_stats.custom_minimum_size = Vector2(380, 0)
	left.add_child(UITheme.scroll(_stats))
	# right: bag
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var hdr := HBoxContainer.new()
	right.add_child(hdr)
	var bl := UITheme.label("Сумка", 22, UITheme.GOLD, "title")
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(bl)
	_gold = UITheme.label("", 20, Color(1.0, 0.85, 0.4), "bold")
	hdr.add_child(_gold)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	right.add_child(tools)
	tools.add_child(ItemFilter.bar(func(): refresh(), _filter))
	tools.add_child(UITheme.button("Сортировать", func():
		player_data().inv.sort_items(_filter.sort)
		refresh(), 48, 150))
	tools.add_child(UITheme.button("Объединить", func():
		player_data().inv.merge_stacks()
		refresh(), 48, 140))
	tools.add_child(UITheme.button("Технологии", func(): manager.open("tech"), 48, 150))
	_bag = GridContainer.new()
	_bag.columns = 6
	right.add_child(UITheme.scroll(_bag))
	refresh()

func _cols_for_bag() -> int:
	var w := get_viewport().get_visible_rect().size.x - 400 - 100
	return clampi(int(w / 128.0), 3, 9)

func refresh() -> void:
	var d := player_data()
	clear(_equip_box)
	for slot in ItemDB.SLOTS:
		var it: Dictionary = d.inv.equipped(slot)
		var b: Button
		if it.is_empty():
			b = Button.new()
			b.custom_minimum_size = Vector2(124, 78)
			b.text = ItemDB.SLOT_NAMES.get(slot, slot)
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 15)
			b.add_theme_color_override("font_color", UITheme.TEXT_DIM)
			b.add_theme_stylebox_override("normal", UITheme.sb(Color(0.08, 0.08, 0.1, 0.8), Color(0.3, 0.28, 0.24), 10, 1, 6))
			b.disabled = true
		else:
			b = item_tile(it, Vector2(124, 78))
			b.tooltip_text = ItemDB.SLOT_NAMES.get(slot, slot)
			_wire_tile(b, it, slot)
		_equip_box.add_child(b)
	clear(_bag)
	_bag.columns = _cols_for_bag()
	for it in ItemFilter.apply(d.inv.items, _filter.group, _filter.query):
		var t := item_tile(it)
		_wire_tile(t, it, "")
		_bag.add_child(t)
	for i in maxi(0, Inventory.CAPACITY - d.inv.items.size()):
		if i > 11:
			break
		var e := Panel.new()
		e.custom_minimum_size = Vector2(118, 86)
		e.add_theme_stylebox_override("panel", UITheme.sb(Color(0.05, 0.05, 0.07, 0.5), Color(0.2, 0.19, 0.17), 10, 1, 4))
		_bag.add_child(e)
	_gold.text = "Золото: %d   Вес: %d/%d" % [d.gold, d.inv.items.size(), Inventory.CAPACITY]
	_stats.text = _stats_text(d)

func _toggle_helm() -> void:
	var a: Dictionary = player_data().appearance
	a.hide_helm = 0 if int(a.get("hide_helm", 0)) == 1 else 1
	_apply_look()

func _next_dye() -> void:
	var a: Dictionary = player_data().appearance
	a.dye = (int(a.get("dye", -1)) + 2) % (Player.DYES.size() + 1) - 1
	_apply_look()
	Events.notify.emit("Цвет: %s" % (Player.DYE_NAMES[a.dye] if int(a.dye) >= 0 else "исходный"), Color(0.9, 0.85, 0.7))

func _apply_look() -> void:
	if has_player() and Game.player.rig:
		var lk := Player.look_from(player_data())
		for k in ["hide_helm", "dye"]:
			if lk.has(k):
				Game.player.rig.look[k] = lk[k]
			else:
				Game.player.rig.look.erase(k)
		Game.player.refresh_gear()
	if _preview:
		_preview.clear_try_on()

func _stats_text(d: CharData) -> String:
	var t := "[b][color=#f5c966]%s[/color][/b] · %s · ур. %d\n" % [d.name, DBSkills.CLASSES.get(d.class_id, {}).get("name", ""), d.level]
	t += "Опыт: %d / %d\n" % [d.xp, d.xp_needed()]
	if has_player():
		var p = Game.player
		t += "Здоровье: [color=#ff7766]%d / %d[/color]\n" % [roundi(p.hp), roundi(p.max_hp)]
		t += "Мана: [color=#77aaff]%d / %d[/color]   Выносл.: %d\n" % [roundi(p.mana), roundi(p.max_mana), roundi(p.max_stamina)]
		if p.has_method("stat"):
			t += "Броня: %d   Крит: %d%%   Скорость: %+d%%\n" % [roundi(p.stat("armor")), roundi(p.stat("crit") * 100.0), roundi(p.stat("speed") * 100.0)]
			t += "Урон: %+d%%   Сила магии: %+d%%   Вампиризм: %d%%\n" % [roundi(p.stat("dmg_pct") * 100.0), roundi(p.stat("spell") * 100.0), roundi(p.stat("lifesteal") * 100.0)]
	else:
		var armor := 0.0
		var hp := 0.0
		for it in d.inv.equip.values():
			armor += ItemDB.stat(it, "armor")
			hp += ItemDB.stat(it, "hp")
		t += "Броня: %d   Бонус здоровья: +%d\n" % [roundi(armor), roundi(hp)]
	var w: Dictionary = d.inv.equipped("main")
	if not w.is_empty():
		var b := ItemDB.base(w.base)
		t += "Оружие: %s — урон %d, мастерство %d\n" % [ItemDB.CAT_NAMES.get(b.get("cat", ""), ""), roundi(ItemDB.stat(w, "dmg")), d.mastery_level(b.get("cat", ""))]
	var hy := d.hybrids()
	if not hy.is_empty():
		var names: Array = []
		for h in hy:
			names.append(DBSkills.HYBRIDS[h].name)
		t += "[color=#66ffcc]Гибриды: %s[/color]\n" % ", ".join(names)
	t += "Убийств: %d   Слава: %d" % [d.kills, roundi(d.fame)]
	return t

func _wire_tile(b: Button, it: Dictionary, slot: String) -> void:
	b.pressed.connect(func():
		UITheme.click()
		_card(it, slot))
	# long press also opens the card (touch habit)
	b.button_down.connect(func(): _press_t[b] = Time.get_ticks_msec())
	b.button_up.connect(func(): _press_t.erase(b))

func _process(_dt: float) -> void:
	for b in _press_t.keys():
		if not is_instance_valid(b):
			_press_t.erase(b)
			continue
		if Time.get_ticks_msec() - _press_t[b] > 450:
			_press_t.erase(b)
			b.emit_signal("pressed")

func _card(it: Dictionary, slot: String) -> void:
	close_modal()
	var vb := modal(720)
	var desc := ItemDB.describe(it)
	var r := UITheme.rich(desc)
	r.custom_minimum_size = Vector2(660, 0)
	if desc.count("\n") > 9:
		var sc := UITheme.scroll(r)
		sc.custom_minimum_size = Vector2(0, 300)
		vb.add_child(sc)
	else:
		vb.add_child(r)
	var d := player_data()
	var b := ItemDB.base(it.base)
	var bslot: String = b.get("slot", "")
	if slot == "" and bslot in ItemDB.SLOTS:
		var cur: Dictionary = d.inv.equipped(bslot)
		if not cur.is_empty():
			vb.add_child(UITheme.separator())
			var cmp := "[color=#aaaaaa]Сейчас надето:[/color]\n" + ItemDB.describe(cur)
			var delta := ""
			if b.has("dmg"):
				var dv := ItemDB.stat(it, "dmg") - ItemDB.stat(cur, "dmg")
				delta += "Урон %s%d  " % ["+" if dv >= 0 else "", roundi(dv)]
			var av := ItemDB.stat(it, "armor") - ItemDB.stat(cur, "armor")
			if absf(av) > 0.01:
				delta += "Броня %s%d" % ["+" if av >= 0 else "", roundi(av)]
			if delta != "":
				cmp = "[b]Сравнение: %s[/b]\n" % delta + cmp
			var r2 := UITheme.rich(cmp)
			r2.add_theme_font_size_override("normal_font_size", 16)
			var sc2 := UITheme.scroll(r2)
			sc2.custom_minimum_size = Vector2(0, 150)
			vb.add_child(sc2)
	var msg := UITheme.label("", 18, UITheme.BAD)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	if slot != "":
		row.add_child(UITheme.button("Снять", func(): _do_unequip(slot, msg), 60, 150))
	elif bslot in ItemDB.SLOTS:
		row.add_child(UITheme.button("Надеть", func(): _do_equip(it, msg), 60, 150))
	elif bslot == "use":
		var ub := UITheme.button("Использовать", func(): _do_use(it, msg), 60, 190)
		ub.disabled = not has_player()
		row.add_child(ub)
	if TechKnow.item_family(it) != "" or TechKnow.has_special(it):
		row.add_child(UITheme.button("Изучить", func():
			close_modal()
			manager.open("inspect", {"item": it}), 60, 150))
	if slot == "" and bslot in ItemDB.SLOTS:
		row.add_child(UITheme.button("Примерить", func():
			if _preview:
				_preview.try_on(it)
			close_modal(), 60, 160))
	if slot == "" and int(it.get("qty", 1)) > 1:
		row.add_child(UITheme.button("Разделить", func():
			var part := d.inv.split(it.uid, int(it.qty) / 2)
			msg.text = "Стопка разделена" if not part.is_empty() else "Нет места в сумке"
			refresh(), 60, 150))
	if slot == "":
		var db := UITheme.button("Выбросить", func(): _do_drop(it, msg), 60, 160)
		db.disabled = not has_player()
		row.add_child(db)
	row.add_child(UITheme.button("Закрыть", close_modal, 60, 140))

func _result(res, msg: Label) -> void:
	var ok := true
	var text := ""
	if res is Dictionary:
		ok = res.get("ok", true)
		text = res.get("msg", "")
	elif res is bool:
		ok = res
	if not ok:
		msg.text = text if text != "" else "Невозможно."
		Audio.play_sfx("error")
		return
	close_modal()
	if text != "":
		show_toast(text, UITheme.BAD if res is Dictionary and res.get("bound", false) else UITheme.ACCENT)
	if has_player() and Game.player.has_method("refresh_gear"):
		Game.player.refresh_gear()
	refresh()

func _do_equip(it: Dictionary, msg: Label) -> void:
	var res
	if has_player() and Game.player.has_method("equip_item"):
		res = Game.player.equip_item(it)
	else:
		res = player_data().inv.equip_item(it)
	_result(res, msg)

func _do_unequip(slot: String, msg: Label) -> void:
	var res
	if has_player() and Game.player.has_method("unequip_slot"):
		res = Game.player.unequip_slot(slot)
	else:
		res = player_data().inv.unequip(slot)
	_result(res, msg)

func _do_use(it: Dictionary, msg: Label) -> void:
	if has_player() and Game.player.has_method("use_item"):
		_result(Game.player.use_item(it), msg)
	else:
		msg.text = "Доступно только в игре."

func _do_drop(it: Dictionary, msg: Label) -> void:
	if has_player() and Game.player.has_method("drop_item"):
		Game.player.drop_item(it)
		_result(true, msg)
	else:
		msg.text = "Доступно только в игре."
