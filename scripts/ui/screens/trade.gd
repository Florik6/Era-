extends UIScreen
## Trade: {title, items, price_mult, buy_cb(item)->bool, sell, sell_mult}

var _tab := "buy"
var _list: VBoxContainer
var _gold: Label
var _btn_buy: Button
var _btn_sell: Button

func build() -> void:
	make_frame(args.get("title", "Торговец"), 1060.0, 0.95)
	var row := HBoxContainer.new()
	content.add_child(row)
	_btn_buy = UITheme.button("Купить", func():
		_tab = "buy"
		refresh(), 56, 170)
	row.add_child(_btn_buy)
	if args.get("sell", true):
		_btn_sell = UITheme.button("Продать", func():
			_tab = "sell"
			refresh(), 56, 170)
		row.add_child(_btn_sell)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_gold = UITheme.label("", 22, Color(1.0, 0.85, 0.4), "bold")
	row.add_child(_gold)
	_list = VBoxContainer.new()
	content.add_child(UITheme.scroll(_list))
	refresh()

func _price(it: Dictionary) -> int:
	return maxi(1, roundi(ItemDB.value(it) * float(args.get("price_mult", 1.0))))

func _sell_price(it: Dictionary) -> int:
	return maxi(1, roundi(ItemDB.value(it) * float(args.get("sell_mult", 0.35)) * it.get("qty", 1)))

func refresh() -> void:
	var d := player_data()
	_gold.text = "Золото: %d" % d.gold
	_btn_buy.modulate = Color(1, 1, 1) if _tab == "buy" else Color(0.6, 0.6, 0.6)
	if _btn_sell:
		_btn_sell.modulate = Color(1, 1, 1) if _tab == "sell" else Color(0.6, 0.6, 0.6)
	clear(_list)
	if _tab == "buy":
		var items: Array = args.get("items", [])
		if items.is_empty():
			_list.add_child(UITheme.wrap_label("Товаров нет.", 18))
		for it in items:
			var p := _price(it)
			_list.add_child(_row(it, "Купить · %d" % p, d.gold >= p, func(): _buy(it, p)))
	else:
		var any := false
		for it in d.inv.items:
			if ItemDB.base(it.base).get("relic", false):
				continue
			any = true
			var sp := _sell_price(it)
			_list.add_child(_row(it, "Продать · %d" % sp, true, func(): _sell(it, sp)))
		if not any:
			_list.add_child(UITheme.wrap_label("В сумке нечего продать (надетые вещи и реликвии не продаются).", 18))

func _row(it: Dictionary, btn_text: String, enabled: bool, cb: Callable) -> Control:
	var p := UITheme.panel(Color(0.08, 0.075, 0.1, 0.9), ItemDB.rarity_color(it).darkened(0.4), 10, 10)
	var row := HBoxContainer.new()
	p.add_child(row)
	var info := Button.new()
	info.flat = true
	info.focus_mode = Control.FOCUS_NONE
	info.alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.y = 56
	var b := ItemDB.base(it.base)
	var sub: String = ItemDB.SLOT_NAMES.get(b.get("slot", ""), "")
	if b.has("cat"):
		sub = "%s · урон %d" % [ItemDB.CAT_NAMES.get(b.cat, ""), roundi(ItemDB.stat(it, "dmg"))]
	elif ItemDB.stat(it, "armor") > 0:
		sub += " · броня %d" % roundi(ItemDB.stat(it, "armor"))
	info.text = "%s\n%s · %s" % [item_short(it), ItemDB.RARITY_NAMES[clampi(it.get("rarity", 0), 0, 5)], sub]
	info.add_theme_font_size_override("font_size", 17)
	info.add_theme_color_override("font_color", ItemDB.rarity_color(it).lightened(0.15))
	info.pressed.connect(func(): _card(it))
	row.add_child(info)
	var bb := UITheme.button(btn_text, cb, 56, 200)
	bb.disabled = not enabled
	row.add_child(bb)
	return p

func _card(it: Dictionary) -> void:
	var vb := modal(680)
	var r := UITheme.rich(ItemDB.describe(it))
	var sc := UITheme.scroll(r)
	sc.custom_minimum_size = Vector2(620, 340)
	vb.add_child(sc)
	vb.add_child(UITheme.button("Закрыть", close_modal, 56, 160))

func _buy(it: Dictionary, price: int) -> void:
	var d := player_data()
	var cb: Callable = args.get("buy_cb", Callable())
	var ok := false
	if cb.is_valid():
		var r = cb.call(it)
		ok = r == true or (r is Dictionary and r.get("ok", false))
	else:
		if d.gold >= price and not d.inv.is_full():
			var copy: Dictionary = it.duplicate(true)
			copy.uid = ItemDB.next_uid()
			if d.inv.add(copy):
				d.gold -= price
				ok = true
	if ok:
		Audio.play_sfx("coin")
		show_toast("Куплено: " + ItemDB.display_name(it))
		if CivicLegends.inst != null and args.get("npc") != null and is_instance_valid(args.npc):
			CivicLegends.inst.on_trade(args.npc, price)       # real business → the merchant's career
	else:
		Audio.play_sfx("error")
		show_toast("Не хватает золота или места", UITheme.BAD)
	refresh()

func _sell(it: Dictionary, price: int) -> void:
	var d := player_data()
	if d.inv.remove(it.uid).is_empty():
		return
	d.gold += price
	var cb: Callable = args.get("sell_cb", Callable())
	if cb.is_valid():
		cb.call(it)
	Audio.play_sfx("coin")
	show_toast("Продано за %d" % price)
	if CivicLegends.inst != null and args.get("npc") != null and is_instance_valid(args.npc):
		CivicLegends.inst.on_trade(args.npc, price)
	refresh()
