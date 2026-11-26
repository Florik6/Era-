class_name HUD
extends CanvasLayer
## In-game HUD, laid out inside the display safe area:
##  - compact vitals (level badge with XP ring, HP/mana/stamina, status chips)
##  - icon menu buttons, minimap, time/weather/event line (top right)
##  - compact objective pill with distance; tap to expand the details
##  - boss bar
##  - three notification tiers: major banners (queued, short), medium toasts
##    (rare loot, discoveries, quests) and a compact de-duplicated minor log
## Touch controls live on a separate full-screen layer so their coordinates
## always match raw touch positions.

var root: Control          # full screen (vignette, touch controls)
var safe: Control          # inset by the display safe area
var vitals: Control
var objective_pill: PanelContainer
var objective_lbl: RichTextLabel
var objective_short: Label
var objective_icon: Control
var time_lbl: Label
var weapon_lbl: Label
var fps_lbl: Label
var feed: VBoxContainer
var toast_box: VBoxContainer
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_lbl: Label
var vignette: ColorRect
var minimap: Control
var touch: TouchControls
var hints: Hints
var event_lbl: Label
var _boss = null
var _banner_t := 0.0
var _banner_queue: Array = []
var _banner_last := ""
var _font_title: Font
var _expanded_t := 0.0
var _feed_last := ""
var _feed_last_lbl: Label = null
var _feed_count := 1

const BANNER_TIME := 2.8
const STATUS_NAMES := {"burn": ["Горение", Color(1.0, 0.5, 0.15)], "freeze": ["Заморозка", Color(0.6, 0.9, 1.0)], "slow": ["Замедление", Color(0.6, 0.7, 1.0)],
	"stun": ["Оглушение", Color(1.0, 0.95, 0.4)], "wet": ["Мокрый", Color(0.4, 0.6, 1.0)], "curse": ["Проклят", Color(0.75, 0.4, 1.0)],
	"stealth": ["Скрыт", Color(0.6, 0.6, 0.8)], "unstoppable": ["Неудержим", Color(1.0, 0.6, 0.3)], "magic_shield": ["Щит", Color(0.55, 0.75, 1.0)],
	"timeslow": ["Время", Color(0.45, 1.0, 0.85)], "mutation": ["Мутация", Color(0.6, 1.0, 0.3)], "haste": ["Ускорение", Color(1.0, 1.0, 0.6)]}

# ------------------------------------------------------------------ widgets
class IconButton extends Button:
	var kind := "star"
	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(50, 50)
		focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, empty)
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, Color(0.05, 0.06, 0.09, 0.7 if not button_pressed and not is_pressed() else 0.9))
		draw_arc(c, r, 0, TAU, 32, Color(0.9, 0.75, 0.4, 0.75), 2.0, true)
		Icons.draw(self, kind, c, r * 0.52, Color(0.98, 0.95, 0.88))

class VitalsPanel extends Control:
	var font: Font
	var hp_shown := 1.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(300, 92)
	func _bar(p: Vector2, w: float, h: float, frac: float, col: Color, lag := -1.0) -> void:
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, h + 2)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p, Vector2(w, h)), Color(0.08, 0.08, 0.1, 0.65))
		if lag > frac:
			draw_rect(Rect2(p, Vector2(w * clampf(lag, 0, 1), h)), Color(1.0, 0.9, 0.7, 0.55))
		draw_rect(Rect2(p, Vector2(w * clampf(frac, 0, 1), h)), col)
		draw_rect(Rect2(p, Vector2(w * clampf(frac, 0, 1), h * 0.35)), Color(1, 1, 1, 0.14))
	func _draw() -> void:
		var pl = Game.player
		if pl == null or not is_instance_valid(pl) or pl.data == null:
			return
		var bc := Vector2(30, 32)
		# level badge with XP ring
		draw_circle(bc, 27, Color(0.05, 0.05, 0.08, 0.8))
		var xpf: float = float(pl.data.xp) / maxf(1.0, float(pl.data.xp_needed()))
		draw_arc(bc, 26, -PI * 0.5, -PI * 0.5 + TAU, 40, Color(0.25, 0.2, 0.35, 0.9), 4.0, true)
		if xpf > 0.0:
			draw_arc(bc, 26, -PI * 0.5, -PI * 0.5 + TAU * clampf(xpf, 0, 1), 40, Color(0.7, 0.5, 1.0), 4.0, true)
		var lv := str(pl.data.level)
		var fs := 22 if lv.length() < 3 else 17
		var tw := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string_outline(font, bc + Vector2(-tw.x * 0.5, fs * 0.36), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(font, bc + Vector2(-tw.x * 0.5, fs * 0.36), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.4))
		var x0 := 64.0
		var nm: String = pl.data.name
		if pl.faction_id != "":
			nm += "  ·  " + String(DBEras.faction(pl.faction_id).name)
		draw_string_outline(font, Vector2(x0, 14), nm, HORIZONTAL_ALIGNMENT_LEFT, 230, 14, 4, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(x0, 14), nm, HORIZONTAL_ALIGNMENT_LEFT, 230, 14, Color(0.95, 0.93, 0.88))
		var hpf: float = pl.hp / maxf(1.0, pl.max_hp)
		hp_shown = maxf(hpf, move_toward(hp_shown, hpf, get_process_delta_time() * 0.5))
		var hcol := Color(0.86, 0.2, 0.22) if hpf > 0.3 else Color(1.0, 0.15, 0.1).lerp(Color(1.0, 0.45, 0.4), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.01))
		_bar(Vector2(x0, 20), 220, 15, hpf, hcol, hp_shown)
		var ht := "%d / %d" % [int(ceil(pl.hp)), int(pl.max_hp)]
		draw_string_outline(font, Vector2(x0 + 6, 32), ht, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(x0 + 6, 32), ht, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))
		if pl.shield_hp > 0.0:
			_bar(Vector2(x0, 20), 220, 3, pl.shield_hp / maxf(1.0, pl.max_hp), Color(0.6, 0.8, 1.0, 0.95))
		_bar(Vector2(x0, 38), 190, 8, pl.mana / maxf(1.0, pl.max_mana), Color(0.28, 0.5, 1.0))
		_bar(Vector2(x0, 49), 160, 4, pl.stamina / maxf(1.0, pl.max_stamina), Color(0.98, 0.82, 0.32))
		# status chips
		var sx := x0
		for k in pl.statuses:
			var spec = HUD.STATUS_NAMES.get(k)
			if spec == null:
				continue
			var label: String = spec[0]
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0
			if sx + w > size.x + 40:
				break
			draw_rect(Rect2(Vector2(sx, 60), Vector2(w, 17)), Color(0, 0, 0, 0.55))
			draw_rect(Rect2(Vector2(sx, 60), Vector2(3, 17)), spec[1])
			draw_string(font, Vector2(sx + 7, 73), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, spec[1].lightened(0.3))
			sx += w + 4.0

class DiamondIcon extends Control:
	var col := Color(1.0, 0.83, 0.42)
	var pulse := 0.0
	func _ready() -> void:
		custom_minimum_size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		pulse += delta
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var s := 6.0 + sin(pulse * 3.0) * 0.6
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)

# ------------------------------------------------------------------ build
func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_font_title = load("res://assets/fonts/Philosopher-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/Philosopher-Bold.ttf") else null
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.6, 0.0, 0.0, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)
	touch = TouchControls.new()
	root.add_child(touch)
	safe = Control.new()
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(safe)
	_build_vitals()
	_build_topright()
	_build_center()
	hints = Hints.new()
	safe.add_child(hints)
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)
	Events.notify.connect(_on_notify)
	Events.banner.connect(_on_banner)
	Events.boss_engaged.connect(func(b): _boss = b)
	Events.level_up.connect(func(a, l):
		if a == Game.player:
			_on_banner("Новый уровень: %d" % l, "Здоровье и мана восстановлены", Color(1.0, 0.85, 0.3)))
	Events.mastery_up.connect(func(a, cat, l):
		if a == Game.player:
			var nm: String = ItemDB.CAT_NAMES.get(cat, DBSkills.SCHOOLS.get(cat, {}).get("name", cat))
			toast("Мастерство «%s»: %d" % [nm, l], Color(0.6, 0.9, 1.0), "star")
			Audio.play_sfx("mastery_up", null, -4.0))
	if Events.has_signal("toast"):
		Events.connect("toast", toast)

func _apply_safe_area() -> void:
	var sz := root.get_viewport_rect().size
	var ins := Vector4(16, 10, 16, 8)    # left, top, right, bottom
	if OS.has_feature("mobile"):
		var sa := DisplayServer.get_display_safe_area()
		var ws := DisplayServer.window_get_size()
		if ws.x > 0 and sa.size.x > 0:
			var k := sz.x / float(ws.x)
			ins = Vector4(maxf(16.0, sa.position.x * k + 8.0), maxf(10.0, sa.position.y * k + 6.0),
				maxf(16.0, (ws.x - sa.end.x) * k + 8.0), maxf(8.0, (ws.y - sa.end.y) * k + 4.0))
	safe.offset_left = ins.x
	safe.offset_top = ins.y
	safe.offset_right = -ins.z
	safe.offset_bottom = -ins.w

func _bar(col: Color, w: float, h: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, h)
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	bg.border_color = Color(0, 0, 0, 0.8)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
	fg.set_corner_radius_all(4)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b

func _label(sz: int, col: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _font() -> Font:
	if ResourceLoader.exists("res://assets/fonts/PT_Sans-Web-Bold.ttf"):
		return load("res://assets/fonts/PT_Sans-Web-Bold.ttf")
	return ThemeDB.fallback_font

func _build_vitals() -> void:
	var vp := VitalsPanel.new()
	vp.font = _font()
	vp.position = Vector2(0, 0)
	safe.add_child(vp)
	vitals = vp
	# minor log under the vitals
	feed = VBoxContainer.new()
	feed.position = Vector2(4, 98)
	feed.custom_minimum_size = Vector2(360, 0)
	feed.add_theme_constant_override("separation", 1)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(feed)
	# medium toasts (rare loot, discoveries, quests) — left-centre
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	toast_box.offset_left = 0
	toast_box.offset_top = -150
	toast_box.custom_minimum_size = Vector2(380, 0)
	toast_box.add_theme_constant_override("separation", 6)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(toast_box)

func _build_topright() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	col.offset_left = -240
	col.offset_right = 0
	col.offset_top = 0
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(col)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 8)
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(btns)
	for spec in [["map", "map"], ["skills", "skills"], ["bag", "inventory"], ["menu", "pause"]]:
		var b := IconButton.new(spec[0])
		var nm: String = spec[1]
		b.pressed.connect(func():
			Audio.play_sfx("ui_click")
			if Game.world and Game.world.ui:
				Game.world.ui.open(nm))
		btns.add_child(b)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(176, 176)
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(minimap)
	time_lbl = _label(13, Color(0.9, 0.9, 0.85))
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(time_lbl)
	event_lbl = _label(14, Color(1.0, 0.7, 0.4))
	event_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	event_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_lbl.custom_minimum_size = Vector2(200, 0)
	col.add_child(event_lbl)
	fps_lbl = _label(12, Color(0.6, 1.0, 0.6))
	fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(fps_lbl)
	weapon_lbl = _label(13, Color(1, 0.92, 0.75))
	weapon_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_lbl.offset_left = -520
	weapon_lbl.offset_right = 0
	weapon_lbl.offset_top = -20
	weapon_lbl.offset_bottom = 0
	weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	safe.add_child(weapon_lbl)

func _build_center() -> void:
	# compact objective pill (tap to expand)
	objective_pill = PanelContainer.new()
	objective_pill.set_anchors_preset(Control.PRESET_CENTER_TOP)
	objective_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	objective_pill.offset_top = 0
	objective_pill.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.62)
	sb.set_corner_radius_all(16)
	sb.border_color = Color(0.95, 0.8, 0.45, 0.35)
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	objective_pill.add_theme_stylebox_override("panel", sb)
	safe.add_child(objective_pill)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_pill.add_child(vb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(row)
	objective_icon = DiamondIcon.new()
	objective_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(objective_icon)
	objective_short = _label(15, Color(0.97, 0.95, 0.88))
	objective_short.add_theme_constant_override("outline_size", 3)
	row.add_child(objective_short)
	objective_lbl = RichTextLabel.new()
	objective_lbl.bbcode_enabled = true
	objective_lbl.fit_content = true
	objective_lbl.scroll_active = false
	objective_lbl.custom_minimum_size = Vector2(420, 0)
	objective_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_lbl.add_theme_font_size_override("normal_font_size", 14)
	objective_lbl.visible = false
	vb.add_child(objective_lbl)
	objective_pill.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
			_expanded_t = 0.0 if _expanded_t > 0.0 else 8.0
			Audio.play_sfx("ui_click", null, -8.0)
			objective_pill.accept_event())
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.offset_left = -300
	boss_box.offset_right = 300
	boss_box.offset_top = 46
	boss_box.visible = false
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(boss_box)
	boss_lbl = _label(19, Color(1.0, 0.75, 0.6))
	boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_title:
		boss_lbl.add_theme_font_override("font", _font_title)
	boss_box.add_child(boss_lbl)
	boss_bar = _bar(Color(0.8, 0.12, 0.1), 600, 16)
	boss_box.add_child(boss_bar)
	banner_box = VBoxContainer.new()
	banner_box.set_anchors_preset(Control.PRESET_CENTER)
	banner_box.offset_left = -420
	banner_box.offset_right = 420
	banner_box.offset_top = -190
	banner_box.offset_bottom = -90
	banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_box.modulate.a = 0.0
	safe.add_child(banner_box)
	banner_title = _label(32, Color(1.0, 0.85, 0.35))
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font_title:
		banner_title.add_theme_font_override("font", _font_title)
	banner_box.add_child(banner_title)
	banner_sub = _label(17)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_box.add_child(banner_sub)

# ------------------------------------------------------------------ notifications
static func _plain(bb: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(bb, "", true)

## Minor tier: compact log, identical consecutive messages collapse into ×N.
func _on_notify(text: String, col: Color) -> void:
	if _is_medium(text):
		toast(text, col, "star" if not text.begins_with("Открыто") else "map")
		return
	if text == _feed_last and _feed_last_lbl != null and is_instance_valid(_feed_last_lbl):
		_feed_count += 1
		_feed_last_lbl.text = "%s  ×%d" % [text, _feed_count]
		_feed_last_lbl.modulate.a = 1.0
		_restart_fade(_feed_last_lbl, 3.5)
		return
	_feed_last = text
	_feed_count = 1
	var l := _label(14, col)
	l.text = text
	l.add_theme_constant_override("outline_size", 4)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	feed.add_child(l)
	_feed_last_lbl = l
	var kids := feed.get_children()
	for i in maxi(0, kids.size() - 4):
		kids[i].queue_free()
	_restart_fade(l, 3.5)

func _restart_fade(l: Label, hold: float) -> void:
	if l.has_meta("tw"):
		var old = l.get_meta("tw")
		if old is Tween and old.is_valid():
			old.kill()
	var tw := l.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)
	l.set_meta("tw", tw)

func _is_medium(text: String) -> bool:
	for p in ["Открыто", "Обнаружено", "Задание выполнено", "Новое задание", "Легендар", "Мифическ", "Достижение"]:
		if text.begins_with(p):
			return true
	return false

## Medium tier: one-line toast with an icon and a coloured edge.
func toast(text: String, col: Color = Color(1, 0.9, 0.6), icon: String = "star") -> void:
	for t in toast_box.get_children():
		if t.get_meta("text", "") == text:
			return
	var p := PanelContainer.new()
	p.set_meta("text", text)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.72)
	sb.border_color = col
	sb.border_width_left = 4
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(22, 22)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.draw.connect(func(): Icons.draw(ic, icon, ic.size * 0.5, 10.0, col))
	hb.add_child(ic)
	var l := _label(16, col.lerp(Color.WHITE, 0.35))
	l.text = text
	l.add_theme_constant_override("outline_size", 3)
	hb.add_child(l)
	toast_box.add_child(p)
	var kids := toast_box.get_children()
	for i in maxi(0, kids.size() - 3):
		kids[i].queue_free()
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

## Major tier: centred banner. Banners queue (max 3) instead of overwriting
## each other; overflow and duplicates are demoted to toasts.
func _on_banner(title: String, sub: String, col: Color) -> void:
	var cine = Game.world.sys("cinematic") if Game.world and Game.world.has_method("sys") else null
	if cine and cine.has_method("claims") and cine.claims(title):
		return
	var key := title + "|" + sub
	if key == _banner_last and _banner_t > 0.0:
		return
	for q in _banner_queue:
		if q[0] + "|" + q[1] == key:
			return
	if _banner_t > 0.0:
		if _banner_queue.size() >= 2:
			toast(title + (" — " + sub if sub != "" else ""), col, "star")
			return
		_banner_queue.append([title, sub, col])
		return
	_show_banner(title, sub, col)

func _show_banner(title: String, sub: String, col: Color) -> void:
	_banner_last = title + "|" + sub
	banner_title.text = title
	banner_title.add_theme_color_override("font_color", col)
	banner_sub.text = sub
	_banner_t = BANNER_TIME
	banner_box.scale = Vector2(0.94, 0.94)
	banner_box.pivot_offset = banner_box.size * 0.5
	var tw := banner_box.create_tween().set_parallel(true)
	tw.tween_property(banner_box, "modulate:a", 1.0, 0.2)
	tw.tween_property(banner_box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl):
		return
	vitals.queue_redraw()
	var w: Dictionary = pl.weapon()
	var cat: String = pl.weapon_cat()
	weapon_lbl.text = "%s · %s %d" % [ItemDB.display_name(w) if not w.is_empty() else "Кулаки", ItemDB.CAT_NAMES.get(cat, ""), pl.data.mastery_level(cat)]
	var wt := ""
	if Game.world and Game.world.weather and Game.world.weather.get("current") != null:
		wt = {"clear": "ясно", "cloudy": "облачно", "rain": "дождь", "storm": "гроза", "fog": "туман", "snow": "снег", "wind": "ветер"}.get(Game.world.weather.current, "")
	time_lbl.text = "%s · %s · %s" % [DBEras.era(Profile.current_era).name, Game.time_string(), wt]
	fps_lbl.visible = Settings.show_fps
	if Settings.show_fps:
		fps_lbl.text = "FPS %d" % Engine.get_frames_per_second()
	_update_objective(pl, delta)
	event_lbl.text = Game.world.director.status_text() if (Game.world and Game.world.get("director") and Game.world.director != null and Game.world.director.has_method("status_text")) else ""
	# boss bar
	if _boss != null and is_instance_valid(_boss) and not _boss.is_dead and _boss.global_position.distance_to(pl.global_position) < 50.0:
		boss_box.visible = true
		boss_bar.max_value = _boss.max_hp
		boss_bar.value = _boss.hp
		boss_lbl.text = "%s · фаза %d%s" % [_boss.display_name, _boss.phase + 1, "  [ЩИТ]" if _boss.shielded else ""]
		_expanded_t = 0.0
	else:
		boss_box.visible = false
		if _boss != null and (not is_instance_valid(_boss) or _boss.is_dead):
			_boss = null
	var low: float = 1.0 - pl.hp / maxf(1.0, pl.max_hp)
	vignette.color.a = clampf((low - 0.6) * 0.8, 0.0, 0.35) * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.008))
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			if _banner_queue.size() > 0:
				var nx: Array = _banner_queue.pop_front()
				_show_banner(nx[0], nx[1], nx[2])
			else:
				var tw := banner_box.create_tween()
				tw.tween_property(banner_box, "modulate:a", 0.0, 0.45)

func _update_objective(pl, delta: float) -> void:
	var obj := ""
	if Game.world and Game.world.has_method("objective_text"):
		obj = Game.world.objective_text()
	objective_pill.visible = obj != ""
	if obj == "":
		return
	var plain := _plain(obj).strip_edges()
	var first := plain.split("\n")[0]
	# compact line: objective without the quest title, plus distance
	var colon := first.find(": ")
	var short := first.substr(colon + 2) if colon > 0 and colon < 40 else first
	if short.length() > 46:
		short = short.substr(0, 44) + "…"
	var tgt = Game.world.quest_target() if Game.world.has_method("quest_target") else null
	if tgt != null:
		var dd := Vector2(tgt.x - pl.global_position.x, tgt.z - pl.global_position.z).length()
		if dd > 12.0:
			short += "  ·  %d м" % int(dd)
	objective_short.text = short
	if _expanded_t > 0.0:
		_expanded_t -= delta
		objective_lbl.visible = true
		objective_lbl.text = _objective_details(obj)
	else:
		objective_lbl.visible = false
	objective_pill.reset_size()

func _objective_details(obj: String) -> String:
	var q: Dictionary = {}
	if Game.world.get("quests") and Game.world.quests and Game.world.quests.has_method("tracked_quest") and Game.world.get("mode_ctl") == null and String(Game.world.get("dimension")) == "":
		q = Game.world.quests.tracked_quest()
	if q.is_empty():
		return obj
	var lines: Array = ["[color=#ffd36b][b]%s[/b][/color]" % q.title]
	if String(q.get("desc", "")) != "":
		lines.append("[color=#c9c4b8]%s[/color]" % q.desc)
	for o in q.get("objectives", []):
		var prog := (" (%d/%d)" % [o.cur, o.need]) if o.get("need", 1) > 1 else ""
		lines.append(("[color=#7fdc8a]✓[/color] [color=#9a9a9a]%s[/color]" if o.done else "• %s") % (String(o.text) + prog))
	if String(q.get("reward_text", "")) != "":
		lines.append("[color=#e8c86a]Награда:[/color] %s" % q.reward_text)
	return "\n".join(lines)
