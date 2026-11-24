extends UIScreen
## Crafting / upgrade / alchemy: {title, recipes:[{name, desc, cost:{base:n}, gold, cb}]}

var _list: VBoxContainer
var _gold: Label

func build() -> void:
	make_frame(args.get("title", "Мастерская"), 1000.0, 0.95)
	_gold = UITheme.label("", 21, Color(1.0, 0.85, 0.4), "bold")
	content.add_child(_gold)
	_list = VBoxContainer.new()
	content.add_child(UITheme.scroll(_list))
	refresh()

func _affordable(d: CharData, rc: Dictionary) -> bool:
	if d.gold < int(rc.get("gold", 0)):
		return false
	var cost: Dictionary = rc.get("cost", {})
	for b in cost:
		if d.inv.count(b) < int(cost[b]):
			return false
	return rc.get("enabled", true)

func refresh() -> void:
	var d := player_data()
	_gold.text = "Золото: %d" % d.gold
	clear(_list)
	var recipes: Array = args.get("recipes", [])
	if recipes.is_empty():
		_list.add_child(UITheme.wrap_label("Нет доступных рецептов.", 18))
	for rc in recipes:
		var ok := _affordable(d, rc)
		var p := UITheme.panel(Color(0.08, 0.075, 0.1, 0.9), UITheme.GOLD_DIM if ok else Color(0.25, 0.25, 0.25), 10, 12)
		var row := HBoxContainer.new()
		p.add_child(row)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 2)
		row.add_child(vb)
		vb.add_child(UITheme.label(str(rc.get("name", "?")), 21, UITheme.GOLD if ok else UITheme.TEXT, "bold"))
		if rc.get("desc", "") != "":
			vb.add_child(UITheme.wrap_label(rc.desc, 16, UITheme.TEXT))
		var ct := ""
		var cost: Dictionary = rc.get("cost", {})
		for b in cost:
			var have := d.inv.count(b)
			var need := int(cost[b])
			ct += "[color=#%s]%s %d/%d[/color]   " % ["77ee77" if have >= need else "ee6655", ItemDB.base(b).get("name", b), have, need]
		if int(rc.get("gold", 0)) > 0:
			ct += "[color=#%s]Золото %d[/color]" % ["ffd966" if d.gold >= int(rc.gold) else "ee6655", int(rc.gold)]
		if ct != "":
			vb.add_child(UITheme.rich(ct))
		var btn := UITheme.button(str(rc.get("button", "Создать")), func(): _make(rc), 56, 170)
		btn.disabled = not ok
		row.add_child(btn)
		_list.add_child(p)

func _make(rc: Dictionary) -> void:
	var d := player_data()
	if not _affordable(d, rc):
		return
	var cb: Callable = rc.get("cb", Callable())
	var res = cb.call() if cb.is_valid() else false
	if res is String:
		show_toast(res, UITheme.ACCENT)
		Audio.play_sfx("quest_done")
	elif res == true:
		show_toast("Готово!", UITheme.GOOD)
		Audio.play_sfx("quest_done")
	else:
		show_toast("Не удалось", UITheme.BAD)
		Audio.play_sfx("error")
	refresh()
