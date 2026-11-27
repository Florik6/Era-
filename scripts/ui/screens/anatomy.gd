extends UIScreen
## Персонаж → Здоровье → Анатомия (Hardcore Mode only).
## A translucent 3D body (XrayView) in the middle; injured zones glow yellow /
## orange / red / purple and carry shape + text markers. Tap a zone (on the
## model or in the zone list) to see the injury, its severity, bleeding,
## infection risk, effect on stats, recovery and the treatment — with
## «Применить» buttons for the medicine you carry. Drag rotates, pinch zooms;
## buttons duplicate both for accessibility.

var xray: XrayView
var _zone_box: GridContainer
var _info: RichTextLabel
var _treat: VBoxContainer
var _zone := ""

func build() -> void:
	make_frame("Анатомия")
	var hc = Hardcore.inst
	if hc == null or not hc.enabled():
		content.add_child(UITheme.wrap_label("Анатомическое меню доступно только в Hardcore Mode (выбирается при создании нового героя: Новая игра → Режим сложности).", 20, UITheme.TEXT))
		return
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	xray = XrayView.new()
	xray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xray.size_flags_vertical = Control.SIZE_EXPAND_FILL
	xray.zone_tapped.connect(func(z): _select(z))
	left.add_child(xray)
	var ctl := HBoxContainer.new()
	ctl.add_theme_constant_override("separation", 6)
	left.add_child(ctl)
	ctl.add_child(UITheme.button("⟲", func(): xray.rotate_by(-60.0), 52, 64))
	ctl.add_child(UITheme.button("⟳", func(): xray.rotate_by(60.0), 52, 64))
	ctl.add_child(UITheme.button("+", func(): xray.zoom_by(0.85), 52, 64))
	ctl.add_child(UITheme.button("−", func(): xray.zoom_by(1.15), 52, 64))
	var hint := UITheme.wrap_label("Палец — вращение, два пальца — масштаб, касание зоны — подробности. Цвет: жёлтый — лёгкое, оранжевый — среднее, красный — тяжёлое, фиолетовый — магическое. Метки: I / II / III / М, КР — кровотечение, ИНФ — заражение, ПЕР — перелом.", 14, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.add_child(hint)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 460
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	right.add_child(UITheme.label("Зоны тела", 22, UITheme.GOLD, "title"))
	_zone_box = GridContainer.new()
	_zone_box.columns = 2
	right.add_child(_zone_box)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_info = UITheme.rich()
	_info.custom_minimum_size = Vector2(440, 0)
	box.add_child(_info)
	_treat = VBoxContainer.new()
	_treat.add_theme_constant_override("separation", 6)
	box.add_child(_treat)
	var sc := UITheme.scroll(box)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sc)
	# start on the worst zone
	var worst_z := ""
	var worst_s := -1
	for z in Hardcore.ZONES:
		var w: Dictionary = hc.worst(z)
		if not w.is_empty() and int(w.sev) > worst_s:
			worst_s = int(w.sev)
			worst_z = z
	_select(worst_z if worst_z != "" else "chest")

func refresh() -> void:
	if _zone_box == null:
		return
	var hc = Hardcore.inst
	for c in _zone_box.get_children():
		c.queue_free()
	for z in Hardcore.ZONES:
		var w: Dictionary = hc.worst(z)
		var tag: String = "цела" if w.is_empty() else ("М" if w.type == "magic" else ["", "I", "II", "III"][clampi(int(w.sev), 1, 3)])
		var b := UITheme.button("%s · %s" % [Hardcore.ZONE_NAMES[z], tag], func(): _select(z), 48, 220)
		if not w.is_empty():
			b.add_theme_color_override("font_color", Hardcore.color_of(w))
		if z == _zone:
			b.add_theme_color_override("font_color", Color(1, 1, 1))
			b.text = "▶ " + b.text
		_zone_box.add_child(b)
	_show_zone()
	if xray:
		xray.select(_zone)

func _select(z: String) -> void:
	_zone = z
	refresh()

func _show_zone() -> void:
	var hc = Hardcore.inst
	for c in _treat.get_children():
		c.queue_free()
	var l: Array = hc.of_zone(_zone)
	var t := "[font_size=24][b]%s[/b][/font_size]\n" % Hardcore.ZONE_NAMES[_zone]
	if l.is_empty():
		t += "[color=#8fd]Повреждений нет.[/color]"
		_info.text = t
		return
	var pl = Game.player
	for inj in l:
		var col: Color = Hardcore.color_of(inj)
		t += "\n[color=#%s][b]%s[/b][/color] — тяжесть: [b]%s[/b]\n" % [col.to_html(false), Hardcore.TYPE_NAMES[inj.type], Hardcore.SEV_NAMES[int(inj.sev)]]
		var b := int(inj.bleed)
		t += "Кровотечение: %s\n" % ("нет" if b == 0 else ("остановлено повязкой" if inj.bandaged else ["", "слабое", "умеренное", "сильное — опасно!"][b]))
		if inj.infected:
			t += "Заражение: [color=#b4f05a]ЕСТЬ — состояние ухудшается[/color]\n"
		elif Hardcore._is_open(inj):
			t += "Риск заражения: %s\n" % ("нет (рана обработана)" if inj.treated else "%d%%" % roundi(clampf(float(inj.infect), 0.0, 1.0) * 100.0))
		if inj.type == "fracture":
			t += "Шина: %s\n" % ("наложена" if inj.splinted else "[color=#ff9a6a]нет — кость не срастается[/color]")
		var fx: Array = Hardcore.mods_text(hc.inj_mods(inj))
		t += "Влияние: %s\n" % (", ".join(PackedStringArray(fx)) if not fx.is_empty() else "незначительное")
		var stalled: bool = (b > 0 and not inj.bandaged) or inj.infected or (inj.type == "fracture" and int(inj.sev) >= 2 and not inj.splinted)
		var left_d: float = (1.0 - float(inj.heal)) * float(Hardcore.HEAL_DAYS[clampi(int(inj.sev), 1, 3)])
		t += "Восстановление: %s\n" % ("остановлено (нужна помощь)" if stalled else "%d%% · ещё ≈%d ч игрового времени (отдых ускоряет)" % [roundi(float(inj.heal) * 100.0), ceili(left_d * 24.0)])
		for tr in hc.treatments_for(inj):
			var names: Array = []
			var have: Array = []
			for id in tr.items:
				names.append(ItemDB.base(id).get("name", id))
				if pl and pl.data.inv.count(id) > 0:
					have.append(id)
			t += "• %s: %s\n" % [tr.proc, ", ".join(PackedStringArray(names.slice(0, 4))) if not names.is_empty() else "у целителя или врача"]
			for id in have:
				var iid: String = id
				var inj_id: int = int(inj.id)
				var bt := UITheme.button("Применить: %s (×%d) → %s" % [ItemDB.base(iid).name, pl.data.inv.count(iid), Hardcore.TYPE_NAMES[inj.type].to_lower()], func(): _apply(iid, inj_id), 48, 0)
				_treat.add_child(bt)
	# healing magic on the selected zone's injuries (school «Исцеление»)
	if pl and pl.data:
		for inj in l:
			for e in DBAbilities.school_spells("heal"):
				if not e.id in pl.data.spells or int(e.tier) >= 6:
					continue
				var op := ""
				for f in e.fx:
					op = str(f.get("hc", op))
				if op == "" or op == "soothe":
					continue
				var eid: String = e.id
				var inj_id2: int = int(inj.id)
				var why := AbilityExec.block_reason(pl, eid)
				var bt2 := UITheme.button("✚ %s → %s%s" % [e.name, Hardcore.TYPE_NAMES[inj.type].to_lower(), "" if why == "" else " (%s)" % why], func(): _cast(eid, inj_id2), 48, 0)
				bt2.disabled = why != ""
				_treat.add_child(bt2)
	t += "\n[color=#9ab]Целители и врачи в городах, медицинская станция дома и отдых тоже лечат.[/color]"
	_info.text = t

func _cast(spell_id: String, inj_id: int) -> void:
	var pl = Game.player
	if pl == null:
		return
	var why := AbilityExec.cast_heal_now(pl, spell_id, inj_id)
	if why != "":
		show_toast(why, Color(1.0, 0.7, 0.5))
	refresh()

func _apply(base: String, inj_id: int) -> void:
	var pl = Game.player
	var hc = Hardcore.inst
	if pl == null or pl.data.inv.count(base) <= 0:
		return
	if hc.apply_medicine(pl, base, ItemDB.base(base).get("med", {}), inj_id):
		pl.data.inv.consume(base, 1)
		show_toast("Применено: " + ItemDB.base(base).name, Color(0.6, 1.0, 0.7))
	refresh()
