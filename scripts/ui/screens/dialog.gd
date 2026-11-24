extends UIScreen
## Generic NPC dialog: {title, text, portrait_color, options:[{text, cb, disabled, close}]}

func build() -> void:
	make_frame(args.get("title", ""), 900.0, 0.0, args.get("closable", true), 0.45)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	content.add_child(row)
	var pc: Color = args.get("portrait_color", Color(0, 0, 0, 0))
	if pc.a > 0.0:
		var port := Control.new()
		port.custom_minimum_size = Vector2(96, 96)
		port.draw.connect(func():
			port.draw_circle(Vector2(48, 48), 46, pc.darkened(0.55))
			port.draw_circle(Vector2(48, 40), 18, pc.lightened(0.2))
			port.draw_rect(Rect2(22, 60, 52, 30), pc)
			port.draw_arc(Vector2(48, 48), 46, 0, TAU, 48, UITheme.GOLD, 3.0, true))
		row.add_child(port)
	var text: String = str(args.get("text", ""))
	var txt := UITheme.rich(text)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.custom_minimum_size = Vector2(600, 96)
	var vs := get_viewport().get_visible_rect().size
	var opts_n: int = maxi(1, args.get("options", []).size())
	if text.length() > 380 or opts_n > 5:
		var sc := UITheme.scroll(txt)
		sc.custom_minimum_size = Vector2(0, clampf(vs.y - 230.0 - opts_n * 68.0, 120.0, 320.0))
		row.add_child(sc)
	else:
		row.add_child(txt)
	var opts: Array = args.get("options", [])
	if opts.is_empty():
		opts = [{"text": "Уйти"}]
	var ob := VBoxContainer.new()
	content.add_child(ob)
	for o in opts:
		var b := UITheme.button(str(o.get("text", "…")), func(): _choose(o), 58, 0)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = o.get("disabled", false)
		ob.add_child(b)

func _choose(o: Dictionary) -> void:
	var cb: Callable = o.get("cb", Callable())
	if o.get("close", true):
		close()
	if cb.is_valid():
		cb.call()
