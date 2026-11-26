class_name ItemFilter
## Shared item filtering for the bag, home storage and crafting lists:
## category, text search and sorting.

const GROUPS := ["all", "weapon", "armor", "accessory", "medicine", "resource", "home", "other"]
const GROUP_NAMES := {"all": "Все", "weapon": "Оружие", "armor": "Броня", "accessory": "Аксессуары", "medicine": "Лекарства",
	"resource": "Материалы", "home": "Для дома", "other": "Прочее"}
const SORTS := ["type", "rarity", "name", "value"]
const SORT_NAMES := {"type": "По типу", "rarity": "По редкости", "name": "По названию", "value": "По цене"}

static func group_of(it: Dictionary) -> String:
	var b := ItemDB.base(str(it.get("base", "")))
	var slot: String = b.get("slot", "")
	if slot in ["main", "off"]:
		return "weapon"
	if slot in ["head", "body", "hands", "legs", "feet", "cloak"]:
		return "armor"
	if slot in ["ring", "amulet", "module"]:
		return "accessory"
	if b.get("effect", "") in ["med", "heal", "mana", "heal_full"]:
		return "medicine"
	if slot == "mat":
		return "resource"
	if slot == "home":
		return "home"
	return "other"

static func apply(items: Array, group := "all", query := "", sort_mode := "") -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	for it in items:
		if group != "all" and group_of(it) != group:
			continue
		if q != "" and not ItemDB.display_name(it).to_lower().contains(q) and not str(ItemDB.base(it.base).get("name", "")).to_lower().contains(q):
			continue
		out.append(it)
	if sort_mode != "":
		var tmp := Inventory.new()
		tmp.items = out
		tmp.sort_items(sort_mode)
		out = tmp.items
	return out

## A compact control row: category, search, sort. on_change(group, query, sort).
static func bar(on_change: Callable, state: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cat := OptionButton.new()
	for g in GROUPS:
		cat.add_item(GROUP_NAMES[g])
	cat.selected = GROUPS.find(state.get("group", "all"))
	cat.custom_minimum_size = Vector2(170, 48)
	cat.focus_mode = Control.FOCUS_NONE
	row.add_child(cat)
	var search := LineEdit.new()
	search.placeholder_text = "Поиск…"
	search.text = state.get("query", "")
	search.custom_minimum_size = Vector2(200, 48)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(search)
	var srt := OptionButton.new()
	for k in SORTS:
		srt.add_item(SORT_NAMES[k])
	srt.selected = maxi(0, SORTS.find(state.get("sort", "type")))
	srt.custom_minimum_size = Vector2(160, 48)
	srt.focus_mode = Control.FOCUS_NONE
	row.add_child(srt)
	var emit := func():
		state.group = GROUPS[cat.selected]
		state.query = search.text
		state.sort = SORTS[srt.selected]
		on_change.call()
	cat.item_selected.connect(func(_i): emit.call())
	srt.item_selected.connect(func(_i): emit.call())
	search.text_changed.connect(func(_t): emit.call())
	return row
