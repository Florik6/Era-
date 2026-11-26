class_name CombatOverlay
extends CanvasLayer
## Screen-space combat accents under the HUD: a short faint flash for
## heavy finishers/parries/ultimates and anime-style speed lines for dashes.
## Both are brief and translucent so enemies and danger zones stay visible.

var _flash: ColorRect
var _lines: Control
var _lines_t := 0.0
var _lines_dur := 0.3
var _lines_k := 1.0
var _seed := 0
var world

func setup(w) -> void:
	world = w
	layer = 9
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	_lines = Control.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	add_child(_lines)

func flash(c: Color, strength: float) -> void:
	if _flash == null:
		return
	_flash.color = Color(c.r, c.g, c.b, clampf(strength, 0.0, 0.35))
	var tw := _flash.create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.16).set_trans(Tween.TRANS_SINE)

func speed_lines(dur: float, strength: float = 1.0) -> void:
	_lines_t = dur
	_lines_dur = maxf(0.05, dur)
	_lines_k = strength
	_seed = randi()

func _process(delta: float) -> void:
	if _lines_t > 0.0:
		_lines_t -= delta / maxf(0.1, Engine.time_scale)
		_lines.queue_redraw()
	elif _lines_t > -1.0:
		_lines_t = -2.0
		_lines.queue_redraw()

func _draw_lines() -> void:
	if _lines_t <= 0.0:
		return
	var sz := _lines.size
	var c := sz * 0.5
	var a := clampf(_lines_t / _lines_dur, 0.0, 1.0) * 0.35 * _lines_k
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + int(_lines_t * 30.0)
	var n := 34
	var outer := sz.length() * 0.55
	for i in n:
		var ang := TAU * (float(i) + rng.randf() * 0.6) / n
		var dir := Vector2(cos(ang), sin(ang))
		var inner := outer * rng.randf_range(0.55, 0.78)
		var w := rng.randf_range(1.5, 4.0)
		_lines.draw_line(c + dir * inner, c + dir * outer, Color(1, 1, 1, a * rng.randf_range(0.5, 1.0)), w)
