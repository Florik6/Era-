class_name EventObject
extends Node3D
## Interactable thing created by an event (clue, valve, generator, lost pet,
## shrine). Shows a small glowing marker; interacting calls on_use(player).

var label := "Осмотреть"
var kind := "clue"
var on_use: Callable = Callable()
var interact_radius := 2.6
var used := false

func _ready() -> void:
	Game.grid.insert_deferred(self, "interact")
	var mesh := EventProps.object_mesh(kind)
	add_child(mesh)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.4) if kind != "monolith" else Color(0.6, 0.5, 1.0)
	l.light_energy = 0.7
	l.omni_range = 3.0
	l.position.y = 0.8
	l.shadow_enabled = false
	add_child(l)

func _exit_tree() -> void:
	Game.grid.remove(self, "interact")

func can_interact(_a) -> bool:
	return not used

func interact_label() -> String:
	return label

func interact(a) -> void:
	if used:
		return
	if kind in ["clue", "valve", "generator", "dog", "pet", "person", "boat", "item", "machine"]:
		used = true
		visible = kind in ["valve", "generator"]
	if on_use.is_valid():
		on_use.call(a)
