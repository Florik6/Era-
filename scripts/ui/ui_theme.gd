class_name UITheme
## Shared visual style for every menu and screen: fonts, colours, styleboxes
## and small widget helpers. Theme is built once and cached.

const GOLD := Color(0.96, 0.79, 0.4)
const GOLD_DIM := Color(0.62, 0.5, 0.26)
const TEXT := Color(0.93, 0.91, 0.86)
const TEXT_DIM := Color(0.66, 0.64, 0.6)
const PANEL_BG := Color(0.06, 0.055, 0.08, 0.93)
const PANEL_BG2 := Color(0.1, 0.09, 0.13, 0.95)
const ACCENT := Color(0.42, 0.85, 0.95)
const GOOD := Color(0.45, 0.9, 0.45)
const BAD := Color(0.95, 0.38, 0.32)
const BTN_MIN_H := 56

static var _theme: Theme = null
static var _fonts := {}

static func font(kind: String = "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path := "res://assets/fonts/PT_Sans-Web-Regular.ttf"
	match kind:
		"bold": path = "res://assets/fonts/PT_Sans-Web-Bold.ttf"
		"title": path = "res://assets/fonts/Philosopher-Bold.ttf"
		"title_regular": path = "res://assets/fonts/Philosopher-Regular.ttf"
		"logo": path = "res://assets/fonts/RuslanDisplay-Regular.ttf"
		"symbols": path = "res://assets/fonts/UISymbols-DejaVuSubset.ttf"
		"italic":
			var fv := FontVariation.new()
			fv.base_font = font("body")
			fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
			_fonts[kind] = fv
			return fv
	var f: Font = load(path)
	if f == null:
		f = ThemeDB.fallback_font
	# Symbols (★ ✦ ● ✔ ▶ …) are missing from the text fonts; chain a tiny
	# DejaVu subset as fallback so they never render as empty boxes.
	if kind != "symbols" and f is FontFile:
		var sym := font("symbols")
		var fb: Array[Font] = []
		if sym:
			fb.append(sym)
		(f as FontFile).fallbacks = fb
	_fonts[kind] = f
	return f

static func sb(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 10, border_w: int = 0, margin: float = 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	s.anti_aliasing = true
	return s

static func make() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = 20
	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("outline_size", "Label", 0)
	# Buttons
	var bn := sb(Color(0.14, 0.12, 0.16, 0.95), GOLD_DIM, 10, 2, 16)
	var bh := sb(Color(0.22, 0.18, 0.22, 0.98), GOLD, 10, 2, 16)
	var bp := sb(Color(0.34, 0.26, 0.14, 1.0), GOLD, 10, 2, 16)
	var bd := sb(Color(0.1, 0.1, 0.11, 0.8), Color(0.3, 0.3, 0.3, 0.6), 10, 2, 16)
	var bf := sb(Color(0, 0, 0, 0), GOLD, 10, 2, 16)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", bf)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.8))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_color("font_focus_color", "Button", GOLD)
	t.set_font("font", "Button", font("bold"))
	t.set_font_size("font_size", "Button", 21)
	# Panels
	t.set_stylebox("panel", "PanelContainer", sb(PANEL_BG, GOLD_DIM, 14, 2, 18))
	t.set_stylebox("panel", "Panel", sb(PANEL_BG, GOLD_DIM, 14, 2, 18))
	# Progress bars
	t.set_stylebox("background", "ProgressBar", sb(Color(0.05, 0.05, 0.06, 0.9), Color(0.3, 0.27, 0.2), 6, 1, 0))
	t.set_stylebox("fill", "ProgressBar", sb(GOLD_DIM, Color(0, 0, 0, 0), 6, 0, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", 14)
	# LineEdit
	t.set_stylebox("normal", "LineEdit", sb(Color(0.04, 0.04, 0.05, 0.95), GOLD_DIM, 8, 2, 14))
	t.set_stylebox("focus", "LineEdit", sb(Color(0.06, 0.06, 0.07, 0.95), GOLD, 8, 2, 14))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_font_size("font_size", "LineEdit", 24)
	# CheckBox / CheckButton
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	t.set_color("font_pressed_color", "CheckBox", GOLD)
	t.set_stylebox("normal", "CheckBox", sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0, 8))
	t.set_stylebox("hover", "CheckBox", sb(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 6, 0, 8))
	t.set_stylebox("pressed", "CheckBox", sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0, 8))
	t.set_stylebox("hover_pressed", "CheckBox", sb(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 6, 0, 8))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_font_size("font_size", "CheckBox", 20)
	# Slider
	t.set_stylebox("slider", "HSlider", sb(Color(0.15, 0.14, 0.16, 1), Color(0, 0, 0, 0), 4, 0, 4))
	t.set_stylebox("grabber_area", "HSlider", sb(GOLD_DIM, Color(0, 0, 0, 0), 4, 0, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(GOLD, Color(0, 0, 0, 0), 4, 0, 4))
	t.set_icon("grabber", "HSlider", _circle_icon(14, GOLD))
	t.set_icon("grabber_highlight", "HSlider", _circle_icon(16, Color(1, 0.9, 0.6)))
	# Scroll
	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 4, 0, 3))
	t.set_stylebox("grabber", "VScrollBar", sb(GOLD_DIM, Color(0, 0, 0, 0), 4, 0, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", sb(GOLD, Color(0, 0, 0, 0), 4, 0, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", sb(GOLD, Color(0, 0, 0, 0), 4, 0, 3))
	t.set_stylebox("scroll", "HScrollBar", sb(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 4, 0, 3))
	t.set_stylebox("grabber", "HScrollBar", sb(GOLD_DIM, Color(0, 0, 0, 0), 4, 0, 3))
	# Tabs
	t.set_stylebox("tab_selected", "TabContainer", sb(Color(0.24, 0.19, 0.12, 1), GOLD, 8, 2, 16))
	t.set_stylebox("tab_unselected", "TabContainer", sb(Color(0.1, 0.09, 0.12, 0.95), GOLD_DIM, 8, 1, 16))
	t.set_stylebox("tab_hovered", "TabContainer", sb(Color(0.18, 0.15, 0.16, 1), GOLD, 8, 1, 16))
	t.set_stylebox("panel", "TabContainer", sb(Color(0.04, 0.04, 0.06, 0.6), GOLD_DIM, 10, 1, 12))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font("font", "TabContainer", font("bold"))
	t.set_font_size("font_size", "TabContainer", 19)
	# RichText
	t.set_font("normal_font", "RichTextLabel", font("body"))
	t.set_font("bold_font", "RichTextLabel", font("bold"))
	t.set_font("italics_font", "RichTextLabel", font("italic"))
	t.set_font("bold_italics_font", "RichTextLabel", font("bold"))
	t.set_font_size("normal_font_size", "RichTextLabel", 19)
	t.set_font_size("bold_font_size", "RichTextLabel", 19)
	t.set_font_size("italics_font_size", "RichTextLabel", 18)
	t.set_color("default_color", "RichTextLabel", TEXT)
	# Tooltip
	t.set_stylebox("panel", "TooltipPanel", sb(PANEL_BG2, GOLD_DIM, 8, 1, 10))
	# OptionButton/popup
	t.set_stylebox("panel", "PopupMenu", sb(PANEL_BG2, GOLD_DIM, 8, 2, 10))
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_constant("v_separation", "PopupMenu", 18)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 10)
	t.set_constant("v_separation", "GridContainer", 10)
	_theme = t
	return t

static func _circle_icon(r: int, c: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)

static func _check_icon(on: bool) -> ImageTexture:
	var s := 30
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in s:
		for x in s:
			var edge := x < 2 or y < 2 or x >= s - 2 or y >= s - 2
			if edge:
				img.set_pixel(x, y, GOLD_DIM if not on else GOLD)
			elif on and x >= 7 and x < s - 7 and y >= 7 and y < s - 7:
				img.set_pixel(x, y, GOLD)
			else:
				img.set_pixel(x, y, Color(0.05, 0.05, 0.06, 0.9))
	return ImageTexture.create_from_image(img)

# ---------------------------------------------------------------- helpers
static func label(text: String, size: int = 20, color: Color = TEXT, kind: String = "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if kind != "body":
		l.add_theme_font_override("font", font(kind))
	return l

static func title_label(text: String, size: int = 34, color: Color = GOLD) -> Label:
	var l := label(text, size, color, "title")
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	return l

static func wrap_label(text: String, size: int = 18, color: Color = TEXT_DIM) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l

static func panel(bg: Color = PANEL_BG, border: Color = GOLD_DIM, radius: int = 14, margin: float = 18.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, border, radius, 2, margin))
	return p

static func button(text: String, cb: Callable = Callable(), min_h: int = BTN_MIN_H, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(func():
			click()
			cb.call())
	return b

static func rich(text: String = "", fit: bool = true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = fit
	r.scroll_active = not fit
	r.text = text
	r.selection_enabled = false
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r

static func bar(value: float, max_v: float, color: Color, h: int = 14, show_text: bool = false) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxf(1.0, max_v)
	p.value = value
	p.show_percentage = show_text
	p.custom_minimum_size = Vector2(80, h)
	p.add_theme_stylebox_override("fill", sb(color, Color(0, 0, 0, 0), 6, 0, 0))
	return p

static func separator(c: Color = GOLD_DIM) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(c.r, c.g, c.b, 0.5)
	r.custom_minimum_size = Vector2(0, 2)
	return r

static func scroll(content: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s

static func swatch(c: Color, size: Vector2 = Vector2(18, 18)) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func click() -> void:
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("Audio"):
		Engine.get_main_loop().root.get_node("Audio").play_sfx("ui_click")

static func check(ok: bool) -> String:
	return "[color=#77ee77]✔[/color]" if ok else "[color=#ee6655]✖[/color]"

## Safe-area margins in viewport (UI) coordinates: left, top, right, bottom.
static func safe_margins(vp: Viewport) -> Vector4:
	var win := Vector2(DisplayServer.window_get_size())
	var sa := DisplayServer.get_display_safe_area()
	var vs := vp.get_visible_rect().size
	if win.x <= 0 or win.y <= 0 or sa.size.x <= 0:
		return Vector4.ZERO
	var k := vs / win
	var screen := Vector2(DisplayServer.screen_get_size())
	if sa.size.x >= screen.x and sa.size.y >= screen.y:
		return Vector4.ZERO
	var l := maxf(0.0, sa.position.x) * k.x
	var t := maxf(0.0, sa.position.y) * k.y
	var r := maxf(0.0, screen.x - sa.end.x) * k.x
	var b := maxf(0.0, screen.y - sa.end.y) * k.y
	return Vector4(l, t, r, b)
