extends UIScreen
## Historical chronicle: every recorded world event grouped by day.

const FILTERS := {
	"all": ["Все", []],
	"battles": ["Битвы", ["kill", "boss_kill", "battle", "duel", "invasion", "boss_escaped", "boss_returned", "destroyed", "fortress_raid", "chrono_double"]],
	"legends": ["Легенды", ["legend_born", "legend_died", "heir", "commander", "leader", "mercy", "betrayal", "help", "witness", "level_up"]],
	"factions": ["Группировки", ["faction_join", "faction_leave", "rank_up", "capture", "settlement_captured", "commander", "leader", "battle"]],
	"quests": ["Задания", ["quest_done", "quest_failed", "rift_cleared", "era_unlocked", "loot_stolen"]],
	"events": ["События", ["world_event", "world_event_end", "invasion", "hunted", "curse_bound", "curse_broken", "living_evolved", "item_found", "relic_left", "fortress"]],
}

var _filter := "all"
var _era := -1
var _list: VBoxContainer
var _fbtns := {}

func build() -> void:
	make_frame("Историческая хроника")
	var row := HBoxContainer.new()
	content.add_child(row)
	for k in FILTERS:
		var b := UITheme.button(FILTERS[k][0], func():
			_filter = k
			refresh(), 56, 0)
		b.custom_minimum_size.x = 120
		_fbtns[k] = b
		row.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(230, 56)
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_item("Все эпохи", 0)
	for i in DBEras.ERA_COUNT:
		ob.add_item(DBEras.era(i).name, i + 1)
	ob.item_selected.connect(func(idx):
		_era = idx - 1
		refresh())
	row.add_child(ob)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	content.add_child(UITheme.scroll(_list))
	refresh()

func refresh() -> void:
	for k in _fbtns:
		_fbtns[k].modulate = Color(1, 1, 1) if k == _filter else Color(0.62, 0.62, 0.62)
	clear(_list)
	var evs: Array = Chronicle.recent(400, _era)
	var types: Array = FILTERS[_filter][1]
	var day := -999
	var shown := 0
	var buf := ""
	for ev in evs:
		if not types.is_empty() and not ev.get("type", "") in types:
			continue
		var d := int(floor(float(ev.get("t", 0.0))))
		if d != day:
			if buf != "":
				_list.add_child(UITheme.rich(buf))
				buf = ""
			day = d
			_list.add_child(UITheme.label("День %d — %s" % [d + 1, DBEras.era(int(ev.get("era", 0))).name], 21, UITheme.GOLD, "title"))
		var col := _type_color(ev.get("type", ""))
		buf += "[color=#%s]•[/color] %s\n" % [col.to_html(false), ev.get("text", "")]
		shown += 1
		if shown >= 250:
			break
	if buf != "":
		_list.add_child(UITheme.rich(buf))
	if shown == 0:
		_list.add_child(UITheme.wrap_label("Хроника пуста. История пишется вашими поступками и событиями живого мира.", 18))

func _type_color(t: String) -> Color:
	if t in FILTERS.battles[1]:
		return Color(0.95, 0.45, 0.4)
	if t in FILTERS.legends[1]:
		return Color(1.0, 0.82, 0.35)
	if t in FILTERS.factions[1]:
		return Color(0.5, 0.75, 1.0)
	if t in FILTERS.quests[1]:
		return Color(0.5, 0.95, 0.6)
	return Color(0.75, 0.6, 1.0)
