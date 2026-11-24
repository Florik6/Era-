extends UIScreen
## Death screen: {text, respawn_cb, menu}

func build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.18, 0.0, 0.02, 0.0)
	add_child(bg)
	bg.create_tween().tween_property(bg, "color:a", 0.72, 0.8)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	cc.add_child(vb)
	var t := UITheme.title_label("ВЫ ПАЛИ", 72, Color(0.95, 0.3, 0.25))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var txt := UITheme.rich("[center]%s[/center]" % args.get("text", "Ваша история ещё не окончена."))
	txt.custom_minimum_size = Vector2(720, 0)
	vb.add_child(txt)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var rb := UITheme.button(str(args.get("respawn_text", "Возродиться")), _respawn, 64, 280)
	row.add_child(rb)
	if args.get("menu", true):
		row.add_child(UITheme.button("В главное меню", func():
			if manager:
				manager.close_all()
			Game.goto_menu(), 64, 260))
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)

func _respawn() -> void:
	var cb: Callable = args.get("respawn_cb", Callable())
	close()
	if cb.is_valid():
		cb.call()
