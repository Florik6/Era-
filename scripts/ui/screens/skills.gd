extends UIScreen
## «Восхождение силы»: class skills, weapon mastery trees (with the five
## new weapon skills each), the ten magic schools (each tab in its school's
## colours and sign), specialisations and magic rank, learned spells with
## favourites, the prepared set (two switchable pages, 3–4 slots, saved
## sets — changed only out of combat) and, in Hardcore, a healing panel that
## casts healing magic on a chosen injury. Every control is a big touch
## target (56 px), lists scroll with a finger.

const SCHOOL_SIGN := {"fire": "☄", "ice": "❄", "lightning": "⚡", "dark": "☾", "spacetime": "⟳", "earth": "⬢",
	"necro": "☠", "heal": "✚", "air": "↻", "light": "☀"}
const TIER_ROMAN := ["", "I", "II", "III", "IV", "V", "VI"]

var _tabs: TabContainer
var _current_tab := 0
var _sub := {}            # tab name -> current sub tab

func build() -> void:
	make_frame("Восхождение силы")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	refresh()

func refresh() -> void:
	if _tabs.get_tab_count() > 0:
		_current_tab = _tabs.current_tab
		for c in _tabs.get_children():
			if c is TabContainer:
				_sub[c.name] = c.current_tab
	clear(_tabs)
	var d := player_data()
	_tabs.add_child(_class_tab(d))
	_tabs.add_child(_weapon_tab(d))
	_tabs.add_child(_magic_tab(d))
	_tabs.add_child(_spec_tab(d))
	_tabs.add_child(_known_tab(d))
	_tabs.add_child(_set_tab(d))
	if Hardcore.active():
		_tabs.add_child(_heal_tab(d))
	for c in _tabs.get_children():
		if c is TabContainer and _sub.has(c.name):
			c.current_tab = clampi(int(_sub[c.name]), 0, c.get_tab_count() - 1)
	_tabs.current_tab = clampi(_current_tab, 0, _tabs.get_tab_count() - 1)

func _cat(d: CharData) -> String:
	if has_player():
		return Game.player.mastery_cat()
	var w: Dictionary = d.inv.equipped("main")
	return "unarmed" if w.is_empty() else ItemDB.base(w.base).get("cat", "unarmed")

static func ability_name(id: String) -> String:
	if id == "":
		return "— пусто —"
	if id.begins_with("art_"):
		return "✪ " + DBSkills.find_skill(id).get("name", id)
	var e: Dictionary = DBAbilities.get_ab(id)
	if not e.is_empty():
		if e.kind == "spell":
			return "%s %s [%s]" % [SCHOOL_SIGN.get(e.school, "✦"), e.name, TIER_ROMAN[int(e.tier)]]
		return "★ " + e.name
	var s := DBSkills.spell(id)
	if not s.is_empty():
		return "✦ " + s.name
	return DBSkills.find_skill(id).get("name", id)

func _in_combat() -> bool:
	return has_player() and Game.player.combat_t < 5.0

func _learn_button(d: CharData, id: String, nm: String) -> Button:
	var why := d.ability_block(id)
	var b := UITheme.button("Изучить", func():
		if d.learn_ability(id):
			Audio.play_sfx("mastery_up")
			show_toast("Изучено: " + nm)
			if has_player():
				Game.player.recalc_stats()
			refresh(), 56, 140)
	b.disabled = why != ""
	b.tooltip_text = why
	return b

func _row(d: CharData, e: Dictionary, col: Color, learned: bool) -> Control:
	var p := UITheme.panel(Color(0.09, 0.08, 0.11, 0.92), (UITheme.GOOD if learned else col).darkened(0.3), 10, 12)
	var row := HBoxContainer.new()
	p.add_child(row)
	var badge := UITheme.label("★" if e.type == "active" else "◆", 30, UITheme.GOOD if learned else col)
	badge.custom_minimum_size.x = 36
	row.add_child(badge)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	row.add_child(vb)
	vb.add_child(UITheme.label("%s  [%s]" % [e.name, "активный" if e.type == "active" else "пассивный"], 20, UITheme.GOOD if learned else col, "bold"))
	vb.add_child(UITheme.wrap_label(e.desc, 17, UITheme.TEXT))
	var info: Array = []
	match str(e.kind):
		"class":
			info.append("ур. персонажа %d · очков класса %d" % [int(e.lvl), int(e.cost)])
		"weapon":
			info.append("мастерство %d · 1 очко мастерства" % int(e.lvl))
		"spell":
			info.append("ступень %s · мастерство школы %d · очков школы %d" % [TIER_ROMAN[int(e.tier)], int(e.slvl), int(e.cost)])
	if float(e.get("cd", 0.0)) > 0.0:
		info.append("перезарядка %.0f с" % float(e.cd))
	if float(e.get("mana", 0.0)) > 0.0:
		info.append("мана %d" % roundi(AbilityExec.mana_cost(Game.player, e) if has_player() else float(e.mana)))
	if float(e.get("stamina", 0.0)) > 0.0:
		info.append("выносл. %d" % int(e.stamina))
	if float(e.get("cast", 0.0)) > 0.0:
		info.append("подготовка %.1f с" % float(e.cast))
	if e.kind == "spell" and float(e.get("dmg", 0.0)) > 0.0 and has_player():
		info.append("сила %d" % roundi(AbilityExec.spell_power(Game.player, e) * float(AbilityExec.power_parts(Game.player, e).get("school", 1.0)) * float(AbilityExec.power_parts(Game.player, e).get("magic", 1.0))))
	vb.add_child(UITheme.label(" · ".join(PackedStringArray(info)), 15, UITheme.TEXT_DIM))
	if not learned:
		var why := d.ability_block(e.id)
		if why != "":
			vb.add_child(UITheme.label("✕ " + why, 15, UITheme.BAD))
		row.add_child(_learn_button(d, e.id, e.name))
	else:
		row.add_child(UITheme.label("Изучено", 18, UITheme.GOOD, "bold"))
	return p

# ---------------------------------------------------------------- class
func _class_tab(d: CharData) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Класс"
	var cd: Dictionary = DBSkills.CLASSES.get(d.class_id, {})
	var hdr := HBoxContainer.new()
	outer.add_child(hdr)
	hdr.add_child(UITheme.label("%s · уровень %d" % [cd.get("name", d.class_id), d.level], 24, cd.get("color", UITheme.GOLD).lightened(0.3), "title"))
	var pts := UITheme.label("Очки класса: %d" % d.class_pts, 22, UITheme.GOOD if d.class_pts > 0 else UITheme.TEXT_DIM, "bold")
	pts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(pts)
	outer.add_child(UITheme.wrap_label("Очко класса даётся за каждый уровень персонажа. Высшие техники требуют высокого уровня и нескольких очков.", 16))
	var list := VBoxContainer.new()
	for e in DBAbilities.class_skills(d.class_id):
		list.add_child(_row(d, e, cd.get("color", UITheme.GOLD).lightened(0.35), e.id in d.class_skills))
	outer.add_child(UITheme.scroll(list))
	return outer

# ---------------------------------------------------------------- weapons
func _weapon_tab(d: CharData) -> Control:
	var tc := TabContainer.new()
	tc.name = "Оружие"
	var cur := _cat(d)
	for cat in ["sword", "heavy", "spear", "dagger", "bow", "firearm", "staff", "energy", "unarmed"]:
		tc.add_child(_tree_tab(d, cat, cat == cur))
	return tc

func _tree_tab(d: CharData, cat: String, current: bool) -> Control:
	var outer := VBoxContainer.new()
	outer.name = ItemDB.CAT_NAMES.get(cat, cat).split(" ")[0] + (" •" if current else "")
	var m: Dictionary = d.mastery.get(cat, {"lvl": 0, "xp": 0, "pts": 0, "nodes": []})
	var hdr := HBoxContainer.new()
	outer.add_child(hdr)
	hdr.add_child(UITheme.label("%s: мастерство %d" % [ItemDB.CAT_NAMES.get(cat, cat), int(m.lvl)], 22, UITheme.GOLD, "title"))
	var xpb := UITheme.bar(m.xp, DBSkills.mastery_xp_needed(m.lvl), Color(0.85, 0.65, 0.25), 18)
	xpb.custom_minimum_size.x = 200
	xpb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hdr.add_child(xpb)
	var pts := UITheme.label("Очки: %d" % int(m.pts), 22, UITheme.GOOD if int(m.pts) > 0 else UITheme.TEXT_DIM, "bold")
	pts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hdr.add_child(pts)
	outer.add_child(UITheme.wrap_label("Мастерство растёт только от настоящего боя этим оружием. Пассивные приёмы оружия действуют, пока оно в руках.", 16))
	var list := VBoxContainer.new()
	for n in DBSkills.TREES.get(cat, []):
		list.add_child(_old_node_row(d, cat, n, m))
	for e in DBAbilities.weapon_skills(cat):
		list.add_child(_row(d, e, Color(0.95, 0.8, 0.5), d.has_node(e.id)))
	outer.add_child(UITheme.scroll(list))
	return outer

func _old_node_row(d: CharData, cat: String, n: Dictionary, m: Dictionary) -> Control:
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
	row.add_child(vb)
	vb.add_child(UITheme.label("%s  [%s]" % [n.name, "активный" if n.type == "active" else "пассивный"], 20, col, "bold"))
	vb.add_child(UITheme.wrap_label(n.desc, 17, UITheme.TEXT))
	var req := "Требуется мастерство %d" % n.lvl
	if n.req != "":
		req += " и «%s»" % DBSkills.node(cat, n.req).get("name", n.req)
	vb.add_child(UITheme.label(req, 15, UITheme.TEXT_DIM))
	if learned:
		row.add_child(UITheme.label("Изучено", 18, UITheme.GOOD, "bold"))
	else:
		var b := UITheme.button("Изучить", func():
			if d.learn_node(cat, n.id):
				Audio.play_sfx("mastery_up")
				show_toast("Изучено: " + n.name)
				if has_player():
					Game.player.refresh_gear()
				refresh(), 56, 140)
		b.disabled = not can
		row.add_child(b)
	return p

# ---------------------------------------------------------------- magic
func _magic_tab(d: CharData) -> Control:
	var tc := TabContainer.new()
	tc.name = "Магия"
	for s in DBAbilities.SCHOOL_ORDER:
		tc.add_child(_school_tab(d, s))
	return tc

func _school_tab(d: CharData, s: String) -> Control:
	var sd: Dictionary = DBSkills.SCHOOLS[s]
	var c: Color = sd.color
	var known := d.knows_school(s)
	var lvl := d.school_level(s)
	var outer := VBoxContainer.new()
	outer.name = "%s %s" % [SCHOOL_SIGN.get(s, "✦"), sd.name]
	# each school has its own look: tinted backdrop, its sign, its colours
	var head := UITheme.panel(Color(c.r * 0.18, c.g * 0.18, c.b * 0.18, 0.95), c, 12, 14)
	outer.add_child(head)
	var hb := HBoxContainer.new()
	head.add_child(hb)
	var sign := UITheme.label(SCHOOL_SIGN.get(s, "✦"), 46, c, "symbols")
	sign.custom_minimum_size.x = 60
	hb.add_child(sign)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(hv)
	hv.add_child(UITheme.label("Школа: %s" % sd.name, 24, c.lightened(0.25), "title"))
	if known:
		var r2 := HBoxContainer.new()
		hv.add_child(r2)
		r2.add_child(UITheme.label("мастерство %d" % lvl, 19, UITheme.TEXT, "bold"))
		var xb := UITheme.bar(d.schools[s].xp, DBSkills.mastery_xp_needed(lvl), c, 16)
		xb.custom_minimum_size.x = 180
		xb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r2.add_child(xb)
		r2.add_child(UITheme.label("очки школы: %d" % int(d.schools[s].get("pts", 0)), 19, UITheme.GOOD if int(d.schools[s].get("pts", 0)) > 0 else UITheme.TEXT_DIM, "bold"))
		hv.add_child(UITheme.label("Ранг мага: %s" % DBAbilities.RANK_NAMES[d.magic_rank()], 16, UITheme.TEXT_DIM))
	else:
		hv.add_child(UITheme.wrap_label("Школа не изучена: найдите «Фолиант» или наставника. Мастерство школы растёт от применения её заклинаний.", 16))
	var list := VBoxContainer.new()
	# the original spells of the school (learned automatically by mastery)
	for sp in sd.spells:
		var open: bool = known and lvl >= sp.lvl
		var t := "[b][color=#%s]✦ %s[/color][/b] — %s\n[color=#999999]мастерство %d · мана %d · %.1f с[/color]" % [
			(c if open else Color(0.5, 0.5, 0.5)).to_html(false), sp.name, sp.desc, sp.lvl, sp.mana, sp.cd]
		var rl := UITheme.rich(t)
		rl.add_theme_font_size_override("normal_font_size", 16)
		list.add_child(rl)
	var last_tier := 0
	for e in DBAbilities.school_spells(s):
		if int(e.tier) != last_tier:
			last_tier = int(e.tier)
			var tl := UITheme.label("Ступень %s — %s" % [TIER_ROMAN[last_tier], DBAbilities.TIER_NAMES[last_tier]], 19, c, "title")
			list.add_child(tl)
			if last_tier == 5:
				list.add_child(UITheme.wrap_label("Нужны знания: наставник-архимаг или древний трактат.", 15, UITheme.TEXT_DIM))
			if last_tier == 6:
				list.add_child(UITheme.wrap_label("Катаклизм: специализация «Путь архимага», испытание школы, трактат, ранг «Архимаг» и реагент эпохи при каждом применении. Готовится только один.", 15, UITheme.TEXT_DIM))
		list.add_child(_row(d, e, c.lightened(0.2), e.id in d.spells))
	outer.add_child(UITheme.scroll(list))
	return outer

# ---------------------------------------------------------------- specialisations
func _spec_tab(d: CharData) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Специализации"
	var list := VBoxContainer.new()
	var rk := d.magic_rank()
	list.add_child(UITheme.label("Ранг мага: %s" % DBAbilities.RANK_NAMES[rk], 24, UITheme.GOLD, "title"))
	var req := ["", "любая изученная школа", "мастерство школы 4", "мастерство 8 и заклинание III ступени",
		"мастерство 12, ступень IV, сумма мастерства школ 20", "мастерство 16 и две заклинания IV ступени в школе",
		"мастерство 20 и заклинание V ступени", "мастерство 24, «Путь архимага» и пройденное испытание",
		"катаклизм и вторая школа с мастерством 20"]
	for i in range(1, 9):
		var on := rk >= i
		list.add_child(UITheme.rich("%s [b]%s[/b] — [color=#999999]%s[/color]" % [UITheme.check(on), DBAbilities.RANK_NAMES[i], req[i]]))
	list.add_child(UITheme.separator())
	var arch := "cm_archmage_path" in d.class_skills
	list.add_child(UITheme.rich("%s [b]Путь архимага[/b] — доступ к рангу архимага и катаклизмам" % UITheme.check(arch)))
	list.add_child(UITheme.label("Длительных заклинаний одновременно: %d · подготовленных катаклизмов: %d" % [1 + (1 if "cm_second_contour" in d.class_skills else 0), d.cataclysm_cap()], 17, UITheme.TEXT))
	var trials: Array = []
	for k in d.knowledge:
		if str(k).begins_with("trial_"):
			trials.append(DBSkills.SCHOOLS.get(str(k).trim_prefix("trial_"), {}).get("name", k))
	list.add_child(UITheme.label("Пройденные испытания: %s" % (", ".join(PackedStringArray(trials)) if not trials.is_empty() else "нет"), 17, UITheme.TEXT))
	list.add_child(UITheme.separator())
	list.add_child(UITheme.label("Гибридные способности", 20, UITheme.GOLD, "title"))
	var act := d.hybrids()
	for h in DBSkills.HYBRIDS:
		var hd: Dictionary = DBSkills.HYBRIDS[h]
		list.add_child(UITheme.rich("%s [b]%s[/b]\n%s" % [UITheme.check(h in act), hd.name, hd.desc]))
	outer.add_child(UITheme.scroll(list))
	return outer

# ---------------------------------------------------------------- learned spells
func _known_tab(d: CharData) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Изученные"
	outer.add_child(UITheme.wrap_label("★ — избранное: такие заклинания первыми предлагаются в наборе.", 16))
	var list := VBoxContainer.new()
	var spells := d.known_spells()
	spells.sort_custom(func(x, y): return (0 if x in d.favorites else 1) < (0 if y in d.favorites else 1))
	for id in spells:
		var row := HBoxContainer.new()
		var fav: bool = id in d.favorites
		var fb := UITheme.button("★" if fav else "☆", func():
			if id in d.favorites:
				d.favorites.erase(id)
			else:
				d.favorites.append(id)
			refresh(), 56, 64)
		row.add_child(fb)
		var lb := UITheme.label(ability_name(id), 19, UITheme.GOLD if fav else UITheme.TEXT)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		list.add_child(row)
	if spells.is_empty():
		list.add_child(UITheme.wrap_label("Пока нет заклинаний.", 18, UITheme.TEXT_DIM))
	outer.add_child(UITheme.scroll(list))
	return outer

# ---------------------------------------------------------------- prepared set
func _set_tab(d: CharData) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Набор"
	var cat := _cat(d)
	var top := HBoxContainer.new()
	outer.add_child(top)
	top.add_child(UITheme.label("Оружие: %s" % ItemDB.CAT_NAMES.get(cat, cat), 20, UITheme.GOLD, "title"))
	for pg in 2:
		var b := UITheme.button("Страница %d%s" % [pg + 1, " •" if d.ab_page == pg else ""], func():
			d.ab_page = pg
			refresh(), 56, 170)
		top.add_child(b)
	outer.add_child(UITheme.wrap_label("Страница 1 заполняется сама; страницу 2 собирайте под задачу. Кнопка «⇄» на экране переключает страницы. Менять набор можно только вне боя.", 16))
	var locked := _in_combat()
	if locked:
		outer.add_child(UITheme.label("Идёт бой — набор менять нельзя.", 18, UITheme.BAD, "bold"))
	var pool: Array = []
	for id in d.favorites:
		if d.knows_slot_id(id, cat):
			pool.append(id)
	for id in d.known_actives(cat) + d.known_spells():
		if not id in pool:
			pool.append(id)
	var page := d.ab_page
	var slots: Array = d.page_slots(cat, page) if page == 1 else d.auto_slots(cat)
	for i in d.slot_count():
		var row := HBoxContainer.new()
		outer.add_child(row)
		var l := UITheme.label("Ячейка %d" % (i + 1), 20, UITheme.TEXT, "bold")
		l.custom_minimum_size.x = 120
		row.add_child(l)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(440, 56)
		ob.focus_mode = Control.FOCUS_NONE
		ob.add_theme_font_size_override("font_size", 19)
		ob.add_item("— пусто —")
		ob.set_item_metadata(0, "")
		var sel := 0
		for j in pool.size():
			ob.add_item(ability_name(pool[j]))
			ob.set_item_metadata(j + 1, pool[j])
			if i < slots.size() and pool[j] == slots[i]:
				sel = j + 1
		ob.select(sel)
		ob.disabled = locked
		var idx := i
		ob.item_selected.connect(func(k):
			var id: String = ob.get_item_metadata(k)
			var arr: Array = d.page_slots(cat, page) if page == 1 else d.slots_for(cat)
			for q in arr.size():
				if q != idx and arr[q] == id and id != "":
					arr[q] = ""
			var why := d.set_slot(cat, page, idx, id)
			if why != "":
				show_toast(why)
			UITheme.click()
			refresh())
		row.add_child(ob)
	outer.add_child(UITheme.separator())
	outer.add_child(UITheme.label("Сохранённые наборы", 20, UITheme.GOLD, "title"))
	var sv := HBoxContainer.new()
	outer.add_child(sv)
	for nm in ["Бой", "Защита", "Поддержка"]:
		var has := d.saved_sets.has(nm)
		var bs := UITheme.button("Сохранить «%s»" % nm, func():
			d.save_set(nm)
			show_toast("Набор «%s» сохранён" % nm)
			refresh(), 56, 0)
		bs.disabled = locked
		sv.add_child(bs)
		var bl := UITheme.button("Взять «%s»" % nm, func():
			if _in_combat():
				show_toast("Во время боя набор не меняется")
				return
			d.load_set(nm)
			show_toast("Набор «%s»" % nm)
			refresh(), 56, 0)
		bl.disabled = locked or not has
		sv.add_child(bl)
	return outer

# ---------------------------------------------------------------- Hardcore healing
func _heal_tab(d: CharData) -> Control:
	var outer := VBoxContainer.new()
	outer.name = "Лечение"
	outer.add_child(UITheme.wrap_label("Выберите травму, затем заклинание исцеления. Заклинание действует на выбранную рану и честно отказывает, если не подходит (например, не снимает заражение и не сращивает кость при кровотечении).", 16))
	var heals: Array = []
	for e in DBAbilities.school_spells("heal"):
		if e.id in d.spells and int(e.tier) < 6:
			heals.append(e)
	var list := VBoxContainer.new()
	var injuries: Array = Hardcore.inst.list() if Hardcore.inst else []
	if injuries.is_empty():
		list.add_child(UITheme.label("Травм нет.", 18, UITheme.GOOD))
	for inj in injuries:
		var p := UITheme.panel(Color(0.1, 0.08, 0.08, 0.92), Hardcore.color_of(inj), 10, 10)
		var vb := VBoxContainer.new()
		p.add_child(vb)
		var st: Array = [Hardcore.TYPE_NAMES.get(inj.type, inj.type), Hardcore.SEV_NAMES[int(inj.sev)]]
		if int(inj.bleed) > 0 and not inj.bandaged:
			st.append("кровотечение")
		if inj.infected:
			st.append("заражение")
		vb.add_child(UITheme.label("%s — %s" % [Hardcore.ZONE_NAMES.get(inj.zone, inj.zone), ", ".join(PackedStringArray(st))], 18, Hardcore.color_of(inj).lightened(0.3), "bold"))
		var hb := HFlowContainer.new()
		vb.add_child(hb)
		for e in heals:
			var iid := int(inj.id)
			var eid: String = e.id
			var b := UITheme.button(e.name, func():
				if not has_player():
					return
				var why := AbilityExec.cast_heal_now(Game.player, eid, iid)
				if why != "":
					show_toast(why)
				refresh(), 56, 0)
			b.disabled = has_player() and AbilityExec.block_reason(Game.player, eid) != ""
			hb.add_child(b)
		list.add_child(p)
	if heals.is_empty():
		list.add_child(UITheme.wrap_label("Заклинания исцеления не изучены (школа «Исцеление»).", 17, UITheme.TEXT_DIM))
	outer.add_child(UITheme.scroll(list))
	return outer
