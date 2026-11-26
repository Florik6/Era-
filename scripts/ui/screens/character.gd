extends UIScreen
## Персонаж: overview (class, level, era, difficulty mode) and the «Здоровье»
## tab — vitals, Hardcore injuries and the way into «Анатомия».

var _body: VBoxContainer
var _tab := "overview"

func build() -> void:
	make_frame("Персонаж", 0.82, 0.92)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	tabs.add_child(UITheme.button("Обзор", func(): _show("overview"), 52, 180))
	tabs.add_child(UITheme.button("Здоровье", func(): _show("health"), 52, 180))
	tabs.add_child(UITheme.button("Снаряжение", func(): manager.open("inventory"), 52, 180))
	tabs.add_child(UITheme.button("Навыки", func(): manager.open("skills"), 52, 160))
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	var sc := UITheme.scroll(_body)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(sc)
	_show(str(args.get("tab", "overview")))

func refresh() -> void:
	_show(_tab)

func _show(tab: String) -> void:
	_tab = tab
	for c in _body.get_children():
		c.queue_free()
	var pl = Game.player
	var d: CharData = Profile.char
	if tab == "overview":
		var t := UITheme.rich()
		t.text = "[font_size=26][b]%s[/b][/font_size]\n%s · уровень %d\nЭпоха: %s\nРежим сложности: [b]%s[/b]\nЗолото: %d" % [d.name,
			DBSkills.CLASSES.get(d.class_id, {}).get("name", d.class_id), d.level, DBEras.era(Profile.current_era).name,
			"Hardcore" if Profile.difficulty == "hardcore" else "Обычный", d.gold]
		_body.add_child(t)
		return
	# --- Здоровье
	if pl:
		_body.add_child(UITheme.label("Здоровье %d / %d" % [int(pl.hp), int(pl.max_hp)], 20, UITheme.TEXT, "bold"))
		_body.add_child(UITheme.bar(pl.hp, pl.max_hp, Color(0.86, 0.2, 0.22), 16))
		_body.add_child(UITheme.label("Выносливость %d / %d · Мана %d / %d" % [int(pl.stamina), int(pl.max_stamina), int(pl.mana), int(pl.max_mana)], 17, UITheme.TEXT_DIM))
	var hc = Hardcore.inst
	if hc == null or not hc.enabled():
		_body.add_child(UITheme.wrap_label("Обычный режим: отдельные ранения не учитываются. Анатомическое меню доступно только в Hardcore Mode.", 17, UITheme.TEXT_DIM))
		var ab := UITheme.button("Анатомия (только Hardcore)", Callable(), 56, 320)
		ab.disabled = true
		_body.add_child(ab)
		return
	var l: Array = hc.list()
	var rt := UITheme.rich()
	if l.is_empty():
		rt.text = "[color=#8fd]Ранений нет.[/color]"
	else:
		var lines: Array = []
		for inj in l:
			lines.append("[color=#%s]■[/color] %s — %s (%s)%s%s" % [Hardcore.color_of(inj).to_html(false), Hardcore.ZONE_NAMES[inj.zone], Hardcore.TYPE_NAMES[inj.type].to_lower(),
				Hardcore.SEV_NAMES[int(inj.sev)], ", кровотечение" if int(inj.bleed) > 0 and not inj.bandaged else "", ", заражение" if inj.infected else ""])
		if hc.unstable():
			lines.push_front("[color=#ff6b5a][b]Нестабильное состояние: остановите кровотечение и обработайте раны![/b][/color]")
		rt.text = "\n".join(lines)
	_body.add_child(rt)
	_body.add_child(UITheme.button("Анатомия", func(): manager.open("anatomy"), 60, 320))
