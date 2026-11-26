class_name Hints
extends PanelContainer
## Contextual one-time tips for new players (touch controls, combat, loot,
## skills, night, rifts, quests). Each tip is shown once per profile and can
## be disabled in settings (Profile.hints_shown["_off"]).

const TIPS := {
	"move": "Левая половина экрана — джойстик. Идите к светящимся сферам опыта, чтобы расти в силе.",
	"attack": "Удерживайте «АТАКА»: удары сами наводятся на ближайшего врага. Потяните палец от кнопки, чтобы целиться вручную.",
	"enemy": "Враг рядом! «БЛОК» в момент удара — парирование и оглушение врага. «РЫВОК» — уклонение с неуязвимостью.",
	"loot": "Предметы светятся цветом редкости. Пройдите по ним или нажмите «!», чтобы подобрать.",
	"level": "Новый уровень! Мастерство оружия растёт отдельно. Откройте «Навыки», чтобы выучить приёмы и назначить их на кнопки.",
	"night": "Наступила ночь: враги опаснее, жители прячутся по домам. Святилища восстанавливают силы и запоминают точку возрождения.",
	"rift": "Разлом времени! Войдите через «!». Добыча сохранится, только если вы выберетесь живым.",
	"settlement": "Поговорите с жителями — у них есть задания. Торговцы продают зелья и фолианты магии.",
	"curse": "Некоторые красивые вещи прокляты. Свиток распознавания или алтарь раскроют скрытую ауру.",
	"boss": "Босс! Следите за красными зонами на земле — это предупреждение о мощной атаке.",
}

var _label: RichTextLabel
var _queue: Array = []
var _t := 0.0
var _check_t := 0.0
var _elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -330
	offset_right = 330
	offset_top = 46
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.86)
	sb.border_color = Color(0.95, 0.78, 0.4, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(620, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 18)
	add_child(_label)
	visible = false
	gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			_t = 0.0)
	Events.level_up.connect(func(a, _l):
		if a == Game.player:
			show_tip("level"))
	Events.boss_engaged.connect(func(_b): show_tip("boss"))
	Events.item_picked.connect(func(a, it):
		if a == Game.player and it.get("curse", {}).size() > 0:
			show_tip("curse"))

func enabled() -> bool:
	return not Profile.get("hints_shown").get("_off", false)

func show_tip(id: String) -> void:
	if not enabled() or Game.mode != "world":
		return
	var shown: Dictionary = Profile.hints_shown
	if shown.has(id) or id in _queue:
		return
	shown[id] = true
	_queue.append(id)

func _process(delta: float) -> void:
	if Game.player == null or not is_instance_valid(Game.player) or Game.ui_is_open():
		return
	_elapsed += delta
	if _t > 0.0:
		_t -= delta
		if _t <= 0.0:
			var tw := create_tween()
			tw.tween_property(self, "modulate:a", 0.0, 0.35)
			tw.tween_callback(func(): visible = false)
	elif not _queue.is_empty() and not _cine_playing():
		var id: String = _queue.pop_front()
		_label.text = "[color=#ffd36b]Подсказка:[/color] " + TIPS.get(id, id)
		visible = true
		modulate.a = 0.0
		var tw2 := create_tween()
		tw2.tween_property(self, "modulate:a", 1.0, 0.3)
		_t = 7.0
	_check_t += delta
	if _check_t < 0.5:
		return
	_check_t = 0.0
	var p = Game.player
	if _elapsed > 4.0:
		show_tip("move")
	if _elapsed > 12.0:
		show_tip("attack")
	for a in Game.actors_near(p.global_position, 16.0):
		if a != p and not a.is_dead and Game.is_enemy(p, a):
			show_tip("enemy")
			break
	if not Game.grid.query(p.global_position, 10.0, "pickup").is_empty():
		show_tip("loot")
	if Game.is_night():
		show_tip("night")
	if _elapsed < 20.0:
		return
	for o in Game.grid.query(p.global_position, 14.0, "interact"):
		if o is Poi and o.type == "rift":
			show_tip("rift")
		elif o is NPC and o.get("role") in ["villager", "trader"]:
			show_tip("settlement")

func _cine_playing() -> bool:
	var c = Game.world.sys("cinematic") if Game.world and Game.world.has_method("sys") else null
	return c != null and c.has_method("is_playing") and c.is_playing()
