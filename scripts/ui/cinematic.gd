class_name CinematicDirector
extends CanvasLayer
## Cinematic Event Director: short, skippable presentation for big moments —
## world boss appearance, legendary/mythic finds, rift entry, arrival in a
## new era, cleansing of a powerful curse, a living artifact awakening.
## Letterbox bars + title card + a brief camera focus. Never takes control
## away: input keeps working, and with enemies hunting the hero only a
## small title is shown (no bars, no camera move).
## Settings.cinematics: 0 off, 1 short, 2 full. Seen moments replay short
## with a skip button.

var world
var _top: ColorRect
var _bot: ColorRect
var _title: Label
var _sub: Label
var _skip: Button
var _t := 0.0
var _dur := 0.0
var _playing := false
var _recent := {}            # title -> time (lets the HUD drop duplicate banners)
var _clock := 0.0
var _focus_until := 0.0

const COLORS := {"boss": Color(1.0, 0.42, 0.35), "legendary": Color(1.0, 0.8, 0.25), "mythic": Color(1.0, 0.2, 0.3), "rift": Color(0.75, 0.5, 1.0),
	"era": Color(1.0, 0.86, 0.4), "cleanse": Color(0.6, 1.0, 0.9), "artifact": Color(0.4, 1.0, 0.8)}

func setup(w) -> void:
	world = w
	layer = 12
	_top = ColorRect.new()
	_bot = ColorRect.new()
	for r in [_top, _bot]:
		r.color = Color(0, 0, 0, 0.92)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_TOP_WIDE if r == _top else Control.PRESET_BOTTOM_WIDE)
		r.custom_minimum_size.y = 0
		add_child(r)
	_title = Label.new()
	_sub = Label.new()
	var tf: Font = load("res://assets/fonts/Philosopher-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/Philosopher-Bold.ttf") else null
	for l in [_title, _sub]:
		l.set_anchors_preset(Control.PRESET_CENTER_TOP)
		l.offset_left = -560
		l.offset_right = 560
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		l.add_theme_constant_override("outline_size", 8)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.modulate.a = 0.0
		add_child(l)
	if tf:
		_title.add_theme_font_override("font", tf)
	_title.add_theme_font_size_override("font_size", 44)
	_sub.add_theme_font_size_override("font_size", 20)
	_title.offset_top = 150
	_sub.offset_top = 210
	_skip = Button.new()
	_skip.text = "Пропустить ▸"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.custom_minimum_size = Vector2(180, 52)
	_skip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip.offset_left = -220
	_skip.offset_top = -120
	_skip.offset_right = -30
	_skip.offset_bottom = -68
	_skip.visible = false
	_skip.pressed.connect(func(): _t = maxf(_t, _dur - 0.35))
	add_child(_skip)
	Events.boss_engaged.connect(_on_boss)
	Events.item_picked.connect(_on_item)
	Events.dimension_entered.connect(_on_dimension)
	# arrival in an era (the world restarts on an era change)
	var key := "cine_era_%d" % w.era
	if w.mode == "world" and not Profile.hints_shown.get(key, false):
		var ed: Dictionary = DBEras.era(w.era)
		get_tree().create_timer(1.2, false).timeout.connect(func(): play("era", String(ed.name), String(ed.get("year", "")), key))

func is_playing() -> bool:
	return _playing

## True if this title was just shown as a cinematic (HUD skips the banner).
func claims(title: String) -> bool:
	for t in _recent:
		if _clock - float(_recent[t]) < 5.0 and (t == title or title.find(t) >= 0 or t.find(title) >= 0):
			return true
	return false

func _danger() -> bool:
	var pl = world.player if world else null
	if pl == null or not is_instance_valid(pl):
		return false
	for a in Game.actors_near(pl.global_position, 14.0):
		if a != pl and not a.is_dead and a.kind != "boss" and Game.is_enemy(pl, a) and a.aggro.has("player"):
			return true
	return false

## kind: boss/legendary/mythic/rift/era/cleanse/artifact; seen_key marks repeats.
func play(kind: String, title: String, sub: String = "", seen_key: String = "", focus = null) -> void:
	if Settings.cinematics <= 0 or world == null:
		return
	if seen_key == "":
		seen_key = "cine_" + kind
	var seen: bool = Profile.hints_shown.get(seen_key, false)
	Profile.hints_shown[seen_key] = true
	var full: bool = Settings.cinematics >= 2 and not seen
	var danger := _danger()
	_dur = (3.4 if full else 1.9) if not danger else 1.6
	_t = 0.0
	_playing = true
	_recent[title] = _clock
	var col: Color = COLORS.get(kind, Color(1, 0.9, 0.6))
	_title.text = title
	_sub.text = sub
	_title.add_theme_color_override("font_color", col)
	_sub.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_skip.visible = seen and not danger
	var bars := 0.0 if danger else (86.0 if full else 54.0) * clampf(Settings.effects_intensity * 1.2, 0.5, 1.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_top, "custom_minimum_size:y", bars, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_bot, "custom_minimum_size:y", bars, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_title, "modulate:a", 1.0, 0.3)
	tw.tween_property(_sub, "modulate:a", 1.0, 0.45)
	_title.scale = Vector2(0.92, 0.92)
	_title.pivot_offset = Vector2(560, 24)
	tw.tween_property(_title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if full and not danger and focus is Vector3 and world.cam:
		world.cam.cine_focus = focus
		_focus_until = _clock + 1.4
	match kind:
		"legendary":
			Audio.play_sting("legendary_sting")
		"mythic":
			Audio.play_sting("mythic_sting")
		"era":
			Audio.play_sting("era_unlock")

func _process(delta: float) -> void:
	_clock += delta
	if _focus_until > 0.0 and _clock > _focus_until:
		_focus_until = 0.0
		if world and world.cam and world.get("active_ritual") == null:
			world.cam.cine_focus = null
	if not _playing:
		return
	_t += delta
	if _t >= _dur:
		_playing = false
		_skip.visible = false
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_top, "custom_minimum_size:y", 0.0, 0.4)
		tw.tween_property(_bot, "custom_minimum_size:y", 0.0, 0.4)
		tw.tween_property(_title, "modulate:a", 0.0, 0.35)
		tw.tween_property(_sub, "modulate:a", 0.0, 0.3)
		if world and world.cam and _focus_until > 0.0:
			world.cam.cine_focus = null
			_focus_until = 0.0

# ------------------------------------------------------------------ hooks
func _on_boss(b) -> void:
	if b == null or not is_instance_valid(b):
		return
	var lore: String = String(DBActors.BOSSES.get(b.get("boss_id"), {}).get("lore", "")) if b.get("boss_id") != null else ""
	play("boss", b.display_name, lore, "cine_boss_" + String(b.get("boss_id") if b.get("boss_id") != null else "x"), b.global_position + Vector3(0, 2.0, 0))

func _on_item(a, it: Dictionary) -> void:
	if world == null or a != world.player:
		return
	var r: int = it.get("rarity", 0)
	if r >= 5:
		play("mythic", ItemDB.display_name(it), "Мифическая находка", "cine_mythic")
	elif r == 4 and ItemDB.is_equipment(it):
		play("legendary", ItemDB.display_name(it), "Легендарная находка", "cine_legendary")

func _on_dimension(kind: String) -> void:
	if world == null or world.dim_node == null:
		return
	play("rift", world.dim_node.title, world.dim_node.subtitle, "cine_dim_" + kind)
