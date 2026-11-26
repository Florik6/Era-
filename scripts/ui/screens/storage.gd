extends UIScreen
## Personal chest at home: the bag on the left, the shared home chest on the
## right. Tap «→» / «←» to move a whole stack, «½» to move half of a stack,
## filter by category, search by name, sort and merge stacks on both sides.
## The chest's capacity grows with storage upgrades and placed chests.

var _filter := {"group": "all", "query": "", "sort": "type"}
var _bag_box: VBoxContainer
var _chest_box: VBoxContainer
var _bag_lbl: Label
var _chest_lbl: Label

func build() -> void:
	make_frame("Личный сундук")
	var hs = Housing.inst
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	content.add_child(tools)
	tools.add_child(ItemFilter.bar(func(): refresh(), _filter))
	tools.add_child(UITheme.button("Сортировать", func():
		player_data().inv.sort_items(_filter.sort)
		Profile.home_chest.sort_items(_filter.sort)
		refresh(), 48, 150))
	tools.add_child(UITheme.button("Объединить", func():
		player_data().inv.merge_stacks()
		Profile.home_chest.merge_stacks()
		refresh(), 48, 140))
	tools.add_child(UITheme.button("Сложить ресурсы", func():
		for it in player_data().inv.items.duplicate():
			if ItemFilter.group_of(it) in ["resource"]:
				hs.move_to_chest(it)
		refresh(), 48, 190))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)
	for side in ["bag", "chest"]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var lbl := UITheme.label("", 21, UITheme.GOLD, "title")
		col.add_child(lbl)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var sc := UITheme.scroll(box)
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(sc)
		if side == "bag":
			_bag_box = box
			_bag_lbl = lbl
		else:
			_chest_box = box
			_chest_lbl = lbl
	var bid: String = str(args.get("bid", ""))
	if hs and bid != "":
		var h: Dictionary = hs.home(bid)
		if not h.is_empty():
			var lvl := int(h.upgrades.get("storage", 0))
			var u: Dictionary = Housing.UPGRADES.storage
			if lvl < int(u.max):
				var price: int = int(u.price[lvl]) * (Profile.current_era + 1)
				content.add_child(UITheme.button("Улучшить вместимость: +20 мест (%d)" % price, func():
					hs.upgrade(bid, "storage")
					refresh(), 50, 0))
	refresh()

func player_data() -> CharData:
	return Profile.char

func refresh() -> void:
	if _bag_box == null:
		return
	var hs = Housing.inst
	Profile.home_chest.capacity = hs.chest_capacity() if hs else Profile.home_chest.capacity
	_fill(_bag_box, player_data().inv.items, true)
	_fill(_chest_box, Profile.home_chest.items, false)
	_bag_lbl.text = "Сумка %d / %d" % [player_data().inv.items.size(), player_data().inv.capacity]
	_chest_lbl.text = "Сундук %d / %d" % [Profile.home_chest.items.size(), Profile.home_chest.capacity]

func _fill(box: VBoxContainer, items: Array, from_bag: bool) -> void:
	for c in box.get_children():
		c.queue_free()
	var shown: Array = ItemFilter.apply(items, _filter.group, _filter.query, "")
	if shown.is_empty():
		box.add_child(UITheme.label("Пусто", 17, UITheme.TEXT_DIM))
		return
	for it in shown:
		var item: Dictionary = it
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var q := int(item.get("qty", 1))
		var nm := UITheme.label("%s%s" % [ItemDB.display_name(item), (" ×%d" % q) if q > 1 else ""], 17, ItemDB.RARITY_COLORS[clampi(int(item.get("rarity", 0)), 0, 5)])
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		r.add_child(nm)
		if q > 1:
			r.add_child(UITheme.button("½", func(): _move(item, from_bag, q / 2), 44, 52))
		r.add_child(UITheme.button("→" if from_bag else "←", func(): _move(item, from_bag, -1), 44, 60))
		box.add_child(r)

func _move(item: Dictionary, from_bag: bool, n: int) -> void:
	var hs = Housing.inst
	if hs == null:
		return
	var ok: bool = hs.move_to_chest(item, n) if from_bag else hs.move_to_bag(item, n)
	if not ok:
		show_toast("Нет места", Color(1.0, 0.5, 0.4))
	refresh()
