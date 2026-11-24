class_name UIScreen
extends Control
## Base class for full-screen and modal UI screens opened through UIManager.

var manager = null
var screen_name := ""
var args := {}
var content: VBoxContainer
var title_lbl: Label
var frame: PanelContainer
var toast: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

func build() -> void:
	pass

func refresh() -> void:
	pass

## Builds dim background + framed panel with header/close. Returns content box.
## width/height <= 1.0 are fractions of the screen, > 1.0 are pixels.
func make_frame(title: String, width: float = 1.0, height: float = 1.0, closable: bool = true, dim: float = 0.62) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.02, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var sm := UITheme.safe_margins(get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(sm.x + 18))
	margin.add_theme_constant_override("margin_top", int(sm.y + 14))
	margin.add_theme_constant_override("margin_right", int(sm.z + 18))
	margin.add_theme_constant_override("margin_bottom", int(sm.w + 14))
	add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame = UITheme.panel(UITheme.PANEL_BG, UITheme.GOLD_DIM, 16, 18)
	if width >= 0.999 and width <= 1.0 and height >= 0.999 and height <= 1.0:
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(frame)
	else:
		margin.add_child(center)
		center.add_child(frame)
		var vs := get_viewport().get_visible_rect().size
		var w := width if width > 1.0 else vs.x * width
		var h := height if height > 1.0 else vs.y * height
		frame.custom_minimum_size = Vector2(minf(w, vs.x - sm.x - sm.z - 36), minf(h, vs.y - sm.y - sm.w - 28))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	frame.add_child(vb)
	var header := HBoxContainer.new()
	vb.add_child(header)
	title_lbl = UITheme.title_label(title, 32)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_lbl)
	toast = UITheme.label("", 18, UITheme.ACCENT)
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(toast)
	if closable:
		var cb := UITheme.button("×", close, 56, 64)
		cb.add_theme_font_size_override("font_size", 34)
		header.add_child(cb)
	vb.add_child(UITheme.separator())
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	vb.add_child(content)
	return content

func show_toast(text: String, color: Color = UITheme.ACCENT) -> void:
	if toast == null:
		return
	toast.text = text
	toast.add_theme_color_override("font_color", color)
	toast.modulate.a = 1.0
	var tw := toast.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)

func close() -> void:
	if manager and is_instance_valid(manager):
		manager.close(self)
	else:
		queue_free()

func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

## The character being viewed: live player in the world, otherwise the profile.
func player_data() -> CharData:
	if Game.player != null and is_instance_valid(Game.player) and Game.player.get("data") != null:
		return Game.player.data
	return Profile.char

func has_player() -> bool:
	return Game.player != null and is_instance_valid(Game.player)

func world_sys(sys_name: String):
	if Game.world == null or not is_instance_valid(Game.world):
		return null
	var s = Game.world.get(sys_name)
	return s

func call_sys(sys_name: String, method: String, call_args: Array = [], default = null):
	var s = world_sys(sys_name)
	if s == null or not is_instance_valid(s) or not s.has_method(method):
		return default
	return s.callv(method, call_args)

## A small modal overlay inside this screen (item card etc.). Returns its content box.
func modal(width: float = 640.0) -> VBoxContainer:
	var overlay := Control.new()
	overlay.name = "Modal"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	dim.gui_input.connect(func(ev):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			overlay.queue_free())
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(cc)
	var p := UITheme.panel(UITheme.PANEL_BG2, UITheme.GOLD, 14, 18)
	var vs := get_viewport().get_visible_rect().size
	p.custom_minimum_size = Vector2(minf(width, vs.x - 40), 0)
	cc.add_child(p)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	overlay.set_meta("panel", p)
	return vb

func close_modal() -> void:
	var m := get_node_or_null("Modal")
	if m:
		m.queue_free()

static func item_short(item: Dictionary) -> String:
	var nm := ItemDB.display_name(item)
	if item.get("qty", 1) > 1:
		nm += " ×%d" % item.qty
	return nm

## Rarity-coloured tile button for an item.
static func item_tile(item: Dictionary, size: Vector2 = Vector2(118, 86)) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.text = item_short(item)
	b.add_theme_font_size_override("font_size", 15)
	var rc: Color = ItemDB.rarity_color(item)
	b.add_theme_color_override("font_color", rc.lightened(0.15))
	b.add_theme_color_override("font_hover_color", rc.lightened(0.4))
	var bgc := Color(rc.r * 0.18, rc.g * 0.18, rc.b * 0.18, 0.95)
	b.add_theme_stylebox_override("normal", UITheme.sb(bgc, rc.darkened(0.15), 10, 2, 6))
	b.add_theme_stylebox_override("hover", UITheme.sb(bgc.lightened(0.08), rc, 10, 3, 6))
	b.add_theme_stylebox_override("pressed", UITheme.sb(bgc.lightened(0.15), rc.lightened(0.3), 10, 3, 6))
	if item.get("curse", {}).get("active", false):
		b.add_theme_stylebox_override("normal", UITheme.sb(bgc, Color(0.8, 0.1, 0.1), 10, 3, 6))
	return b
