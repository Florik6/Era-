extends UIScreen
## Factions of the current era: reputation, ranks, relations, joining, vendors.

var _list: VBoxContainer

func build() -> void:
	make_frame("Группировки — " + DBEras.era(Profile.current_era).name)
	_list = VBoxContainer.new()
	content.add_child(UITheme.scroll(_list))
	refresh()

func refresh() -> void:
	clear(_list)
	var fids = call_sys("factions", "list", [], null)
	var live := fids != null
	if fids == null:
		fids = DBEras.factions_of(Profile.current_era)
		_list.add_child(UITheme.wrap_label("Подробные сведения доступны в игровом мире.", 17, UITheme.TEXT_DIM))
	var mine: String = call_sys("factions", "member_of", [], "")
	for fid in fids:
		_list.add_child(_card(fid, live, mine))

func _card(fid: String, live: bool, mine: String) -> Control:
	var f := DBEras.faction(fid)
	var col: Color = f.get("color", Color.WHITE)
	var p := UITheme.panel(Color(col.r * 0.08, col.g * 0.08, col.b * 0.08, 0.92), col.darkened(0.1) if fid == mine else col.darkened(0.5), 12, 14)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	p.add_child(row)
	var em := _emblem(col, f.get("emblem", ""))
	row.add_child(em)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	row.add_child(vb)
	var title = f.get("name", fid) + ("   — вы состоите" if fid == mine else "")
	var tc := col.lightened(0.3)
	if tc.get_luminance() < 0.55:
		tc = tc.lerp(Color(0.9, 0.88, 0.95), 0.6)
	vb.add_child(UITheme.label(title, 24, tc, "title"))
	vb.add_child(UITheme.wrap_label(f.get("desc", ""), 17, UITheme.TEXT))
	if live:
		var rep: float = call_sys("factions", "rep", [fid], 0.0)
		var rank_name: String = call_sys("factions", "rank_name", [fid], "")
		var rel: String = call_sys("factions", "relation_text", [fid], "")
		var st = call_sys("factions", "strength", [fid], 0.0)
		var terr = call_sys("factions", "territory", [fid], 0)
		var leader: String = call_sys("factions", "leader_name", [fid], "")
		var info := "[color=#cccccc]Репутация:[/color] [b]%d[/b]%s   [color=#cccccc]Сила:[/color] %d   [color=#cccccc]Территории:[/color] %d" % [
			roundi(rep), (" (%s)" % rank_name) if rank_name != "" else "", roundi(float(st)), int(terr)]
		if leader != "":
			info += "   [color=#cccccc]Лидер:[/color] %s" % leader
		if rel != "":
			info += "\n[color=#cccccc]Отношения:[/color] %s" % rel
		var nxt := DBEras.rank_for_rep(rep) + 1
		if nxt < DBEras.RANK_REP.size():
			info += "\n[color=#999999]До звания «%s»: %d репутации[/color]" % [f.get("ranks", DBEras.FACTION_RANKS)[nxt], DBEras.RANK_REP[nxt] - roundi(rep)]
		vb.add_child(UITheme.rich(info))
		var rep_bar := UITheme.bar(clampf(rep, 0, DBEras.RANK_REP[-1]), DBEras.RANK_REP[-1], col, 10)
		vb.add_child(rep_bar)
		var perks = call_sys("factions", "perks", [fid], [])
		if perks is Array and not perks.is_empty():
			var pt := "[color=#66ffcc]Привилегии:[/color] " + "; ".join(PackedStringArray(perks))
			vb.add_child(UITheme.rich(pt))
	var ranks: Array = f.get("ranks", DBEras.FACTION_RANKS)
	vb.add_child(UITheme.label("Звания: " + " → ".join(PackedStringArray(ranks)), 15, UITheme.TEXT_DIM))
	if not f.get("enemies", []).is_empty():
		var en: Array = []
		for e in f.enemies:
			en.append(DBEras.faction(e).get("name", e))
		vb.add_child(UITheme.label("Враги: " + ", ".join(PackedStringArray(en)), 15, Color(0.9, 0.5, 0.45)))
	var btns := VBoxContainer.new()
	btns.custom_minimum_size.x = 190
	row.add_child(btns)
	if live:
		if fid == mine:
			btns.add_child(UITheme.button("Покинуть", func(): _confirm_leave(fid), 56, 180))
		else:
			var cj = call_sys("factions", "can_join", [fid], {"ok": false, "reason": ""})
			var jb := UITheme.button("Вступить", func():
				var r = call_sys("factions", "join", [fid], null)
				if r is Dictionary and not r.get("ok", true):
					show_toast(r.get("msg", "Невозможно"), UITheme.BAD)
				else:
					show_toast("Вступительное испытание выдано!" if not (r is Dictionary) or r.get("msg", "") == "" else r.msg)
				refresh(), 56, 180)
			jb.disabled = not (cj is Dictionary and cj.get("ok", false))
			btns.add_child(jb)
			if cj is Dictionary and not cj.get("ok", false) and cj.get("reason", "") != "":
				btns.add_child(UITheme.wrap_label(cj.reason, 14, UITheme.BAD))
		var vb_btn := UITheme.button("Торговец", func(): call_sys("factions", "open_vendor", [fid]), 56, 180)
		vb_btn.disabled = world_sys("factions") == null or not world_sys("factions").has_method("open_vendor")
		btns.add_child(vb_btn)
	return p

func _confirm_leave(fid: String) -> void:
	var vb := modal(560)
	vb.add_child(UITheme.title_label("Покинуть организацию?", 26))
	vb.add_child(UITheme.wrap_label("Вы потеряете звание и часть репутации. Враги этой организации могут это запомнить.", 18, UITheme.TEXT))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	row.add_child(UITheme.button("Покинуть", func():
		call_sys("factions", "leave", [])
		close_modal()
		refresh(), 56, 180))
	row.add_child(UITheme.button("Отмена", close_modal, 56, 160))

## Simple procedural emblem drawn with a Control.
func _emblem(col: Color, kind: String) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(84, 84)
	c.draw.connect(func():
		var ctr := Vector2(42, 42)
		c.draw_circle(ctr, 40, col.darkened(0.6))
		c.draw_arc(ctr, 40, 0, TAU, 40, col, 3.0, true)
		var pts := PackedVector2Array()
		var n := 3
		match kind:
			"lion", "lily", "gear_shield", "skull_wing": n = 5
			"raven", "triangle", "flame": n = 3
			"hex", "gear", "atom": n = 6
			"flask", "anchor", "mask", "moon", "hourglass", "star": n = 4
		for i in n * 2:
			var r := 30.0 if i % 2 == 0 else (14.0 if kind in ["star", "lion", "flame"] else 24.0)
			var a := -PI / 2 + PI * i / n
			pts.append(ctr + Vector2(cos(a), sin(a)) * r)
		c.draw_colored_polygon(pts, col)
		c.draw_circle(ctr, 7, col.darkened(0.6)))
	return c
