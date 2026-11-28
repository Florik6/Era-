class_name UIManager
extends CanvasLayer
## Opens/closes UI screens as a stack. Opening a screen pauses the game
## (Game.push_ui) and resets touch input so no button stays "held".

const SCREENS := {
	"inventory": "res://scripts/ui/screens/inventory.gd",
	"skills": "res://scripts/ui/screens/skills.gd",
	"factions": "res://scripts/ui/screens/factions.gd",
	"journal": "res://scripts/ui/screens/journal.gd",
	"map": "res://scripts/ui/screens/map.gd",
	"legends": "res://scripts/ui/screens/legends.gd",
	"chronicle": "res://scripts/ui/screens/chronicle.gd",
	"settings": "res://scripts/ui/screens/settings.gd",
	"pause": "res://scripts/ui/screens/pause.gd",
	"dialog": "res://scripts/ui/screens/dialog.gd",
	"trade": "res://scripts/ui/screens/trade.gd",
	"craft": "res://scripts/ui/screens/craft.gd",
	"death": "res://scripts/ui/screens/death.gd",
	"eras": "res://scripts/ui/screens/eras.gd",
	"altar": "res://scripts/ui/screens/altar.gd",
	"layout_editor": "res://scripts/ui/screens/layout_editor.gd",
	"character": "res://scripts/ui/screens/character.gd",
	"anatomy": "res://scripts/ui/screens/anatomy.gd",
	"storage": "res://scripts/ui/screens/storage.gd",
	"inspect": "res://scripts/ui/screens/inspect.gd",
	"tech": "res://scripts/ui/screens/tech.gd",
}

var stack: Array = []

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	UITheme.make()

func open(screen: String, args: Dictionary = {}) -> Control:
	if not SCREENS.has(screen):
		push_warning("UIManager: unknown screen " + screen)
		return null
	if screen != "dialog" and top_name() == screen:
		return stack.back()
	var script: GDScript = load(SCREENS[screen])
	var s = script.new()
	s.manager = self
	s.screen_name = screen
	s.args = args
	s.theme = UITheme.make()
	add_child(s)
	s.build()
	stack.append(s)
	Game.push_ui(screen)
	_animate_in(s)
	if has_node("/root/Audio"):
		get_node("/root/Audio").play_sfx("ui_open")
	return s

func _animate_in(s: Control) -> void:
	s.modulate.a = 0.0
	s.pivot_offset = s.get_viewport_rect().size * 0.5
	s.scale = Vector2(0.97, 0.97)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate:a", 1.0, 0.16)
	tw.tween_property(s, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close(s: Control) -> void:
	if s == null or not is_instance_valid(s):
		return
	var idx := stack.find(s)
	if idx < 0:
		s.queue_free()
		return
	stack.remove_at(idx)
	var nm: String = s.screen_name
	s.queue_free()
	Game.pop_ui(nm)
	if has_node("/root/Audio"):
		get_node("/root/Audio").play_sfx("ui_close")
	if not stack.is_empty() and stack.back().has_method("refresh"):
		stack.back().refresh()

func close_top() -> bool:
	if stack.is_empty():
		return false
	var top: Control = stack.back()
	# a modal inside a screen (item card) closes first
	var m := top.get_node_or_null("Modal")
	if m:
		m.queue_free()
		return true
	if top.screen_name == "death":
		return true
	close(top)
	return true

func close_all() -> void:
	while not stack.is_empty():
		close(stack.back())

func is_open() -> bool:
	return not stack.is_empty()

func top_name() -> String:
	if stack.is_empty():
		return ""
	return stack.back().screen_name

func get_screen(screen: String) -> Control:
	for s in stack:
		if s.screen_name == screen:
			return s
	return null
