class_name EventTraces
extends Node
## Traces of real events stay in the world: graves where named people and
## bosses fell, scorched battlefields after world events and battles,
## burnt ruins after a settlement changed hands. Each trace can be
## examined and tells what happened there (from the actual event).
## Stored in world_state.traces (capped), shown only near the hero.

const MAX := 60
var world
var _nodes := {}     # index key -> Node3D
var _t := 0.0

func setup(w) -> void:
	world = w
	if not Game.world_state.has("traces"):
		Game.world_state["traces"] = []
	Events.actor_killed.connect(_on_killed)
	Events.world_event_ended.connect(_on_event_end)
	Events.settlement_changed.connect(_on_settlement)

func _list() -> Array:
	return Game.world_state.get("traces", [])

func add(kind: String, pos: Vector3, text: String) -> void:
	if world == null or world.dimension != "":
		return
	var l := _list()
	for t in l:
		if t.kind == kind and Vector2(t.pos[0] - pos.x, t.pos[1] - pos.z).length() < 6.0:
			return
	l.append({"kind": kind, "pos": [snappedf(pos.x, 0.1), snappedf(pos.z, 0.1)], "text": text, "day": Game.day(), "id": Game.new_uid("tr")})
	while l.size() > MAX:
		var old: Dictionary = l.pop_front()
		_drop(old.id)
	Game.world_state["traces"] = l

func _on_killed(victim, killer) -> void:
	if victim == null or not is_instance_valid(victim) or world == null or world.dimension != "":
		return
	var named: bool = victim.get("record") is Dictionary and not victim.record.is_empty()
	if not named and victim.kind != "boss":
		return
	var kn := "неизвестного"
	if killer != null and is_instance_valid(killer):
		kn = killer.display_name if killer.get("display_name") else kn
	add("grave", victim.global_position, "Здесь пал(а) %s от руки %s. День %d." % [victim.display_name, kn, Game.day() + 1])

func _on_event_end(ev: Dictionary) -> void:
	if not ev.has("pos"):
		return
	var p: Vector3 = ev.pos if ev.pos is Vector3 else Vector3(ev.pos[0], 0, ev.pos[1]) if ev.pos is Array else Vector3.ZERO
	add("battlefield", p, "Следы события «%s». %s" % [ev.get("name", "?"), ev.get("outcome", "")])

func _on_settlement(s: Dictionary) -> void:
	if not s.has("pos"):
		return
	var sp: Vector2 = s.pos if s.pos is Vector2 else Vector2(s.pos[0], s.pos[1])
	var a := randf() * TAU
	add("burnt", Vector3(sp.x + cos(a) * 14.0, 0, sp.y + sin(a) * 14.0), "Следы штурма поселения «%s». День %d." % [s.get("name", "?"), Game.day() + 1])

func _process(delta: float) -> void:
	if world == null or world.player == null or not is_instance_valid(world.player) or world.dimension != "":
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var pp: Vector3 = world.player.global_position
	for t in _list():
		var d := Vector2(t.pos[0] - pp.x, t.pos[1] - pp.z).length()
		var shown: bool = _nodes.has(t.id) and is_instance_valid(_nodes[t.id])
		if d < 80.0 and not shown:
			_spawn(t)
		elif d > 110.0 and shown:
			_drop(t.id)

func _drop(id: String) -> void:
	if _nodes.has(id) and is_instance_valid(_nodes[id]):
		_nodes[id].queue_free()
	_nodes.erase(id)

func _spawn(t: Dictionary) -> void:
	var root := Node3D.new()
	match t.kind:
		"grave":
			root.add_child(RoadEncounters.make_prop("grave", world.era, randf() * TAU))
		"battlefield":
			root.add_child(RoadEncounters.make_prop("scorch", world.era, 0.0))
			var b := RoadEncounters.make_prop("bones", world.era, 1.0)
			root.add_child(b)
			b.position = Vector3(1.8, 0, -1.0)
		_:
			root.add_child(RoadEncounters.make_prop("burnt", world.era, randf() * TAU))
	var spot := LivingPOIs.StorySpot.new()
	spot.label = {"grave": "Осмотреть могилу", "battlefield": "Осмотреть поле боя", "burnt": "Осмотреть пепелище"}.get(t.kind, "Осмотреть")
	var txt: String = t.text
	spot.on_interact = func(_a):
		world.ui.open("dialog", {"title": spot.label.replace("Осмотреть ", "").capitalize(), "text": txt, "options": [{"text": "Почтить память" if t.kind == "grave" else "Уйти", "cb": func(): pass}]})
	root.add_child(spot)
	spot.position = Vector3(0, 0, 1.2)
	world.fx_root.add_child(root)
	var p := Vector3(t.pos[0], 0, t.pos[1])
	p.y = world.ground_height(p)
	root.global_position = p
	_nodes[t.id] = root
