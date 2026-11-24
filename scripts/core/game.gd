extends Node
## Central game hub: current mode, player/world references, time, hostility
## rules, spatial index, scene flow and Android lifecycle handling.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"

var player = null
var world = null
var mode := "world"            # world | arena | trials | dungeon
var mode_opts := {}
var game_time := 0.3           # days; fraction = time of day (0.25 = 06:00)
var day_length := 720.0        # real seconds per in-game day
var grid := SpatialGrid.new(16.0)
var world_state := {}          # persistent state of the current era world
var actors: Array = []
var ui_stack: Array = []
var rng := RandomNumberGenerator.new()
var _uid := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	_setup_input()

func _process(delta: float) -> void:
	if world != null and not get_tree().paused:
		game_time += delta / day_length

func new_uid(prefix: String = "a") -> String:
	_uid += 1
	return "%s%d_%d" % [prefix, Time.get_ticks_msec() % 1000000, _uid]

func hour() -> float:
	return fmod(game_time, 1.0) * 24.0

func day() -> int:
	return int(game_time)

func is_night() -> bool:
	var h := hour()
	return h < 5.5 or h > 20.5

func time_string() -> String:
	var h := hour()
	return "День %d, %02d:%02d" % [day() + 1, int(h), int(fmod(h, 1.0) * 60.0)]

var _hit_stop := false
var _hit_stop_next := 0

## Brief freeze-frame on heavy hits (adds weight to combat).
func hit_stop(dur: float = 0.05) -> void:
	if _hit_stop or get_tree().paused or Time.get_ticks_msec() < _hit_stop_next:
		return
	_hit_stop = true
	_hit_stop_next = Time.get_ticks_msec() + 300
	Engine.time_scale = 0.06
	get_tree().create_timer(dur, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0
		_hit_stop = false)

# ---------------------------------------------------------------- scene flow
func start(new_mode: String, opts: Dictionary = {}) -> void:
	mode = new_mode
	mode_opts = opts
	grid.clear()
	actors.clear()
	ui_stack.clear()
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)

func goto_menu() -> void:
	if world != null and mode == "world":
		SaveSys.save_game()
	world = null
	player = null
	grid.clear()
	actors.clear()
	ui_stack.clear()
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)

func push_ui(ui_name: String) -> void:
	ui_stack.append(ui_name)
	get_tree().paused = true
	Events.input_reset.emit()
	Events.ui_opened.emit(ui_name)

func pop_ui(ui_name: String) -> void:
	ui_stack.erase(ui_name)
	if ui_stack.is_empty():
		get_tree().paused = false
	Events.input_reset.emit()
	Events.ui_closed.emit(ui_name)

func ui_is_open() -> bool:
	return not ui_stack.is_empty()

# ---------------------------------------------------------------- actors
func register_actor(a) -> void:
	if not a in actors:
		actors.append(a)
	grid.insert(a, a.global_position, "actor")
	Events.actor_spawned.emit(a)

func unregister_actor(a) -> void:
	actors.erase(a)
	grid.remove(a, "actor")

func actors_near(p: Vector3, r: float) -> Array:
	return grid.query(p, r, "actor")

func _team_root(a):
	var o = a
	var guard := 0
	while o != null and is_instance_valid(o) and o.get("owner_actor") != null and is_instance_valid(o.owner_actor) and guard < 4:
		o = o.owner_actor
		guard += 1
	return o

## Base hostility between two actors, independent of personal aggro.
func is_enemy(a, b) -> bool:
	if a == null or b == null or a == b or not is_instance_valid(a) or not is_instance_valid(b):
		return false
	if a.is_dead or b.is_dead:
		return false
	var ra = _team_root(a)
	var rb = _team_root(b)
	if ra == rb:
		return false
	if a.actor_id in b.aggro or b.actor_id in a.aggro or ra.actor_id in rb.aggro or rb.actor_id in ra.aggro:
		return true
	var ta: String = ra.team
	var tb: String = rb.team
	if ta == tb and ta != "bot":
		return false
	if ta == "monster" or tb == "monster" or ta == "boss" or tb == "boss":
		return not ((ta == "monster" or ta == "boss") and (tb == "monster" or tb == "boss"))
	if ta == "bandit" or tb == "bandit":
		return true
	var fa: String = ra.faction_id
	var fb: String = rb.faction_id
	if fa != "" and fb != "":
		if fa == fb:
			return false
		if world and world.factions and world.factions.at_war(fa, fb):
			return true
	if ta == "player" and fb != "" and world and world.factions:
		return world.factions.rep(fb) <= -30.0
	if tb == "player" and fa != "" and world and world.factions:
		return world.factions.rep(fa) <= -30.0
	if (ta == "player" and rb.get("hunting_player")) or (tb == "player" and ra.get("hunting_player")):
		return true
	return false

## Can attacker's swing/projectile damage target? Contenders (bots) are fair game.
func can_damage(attacker, target) -> bool:
	if attacker == null or target == null or not is_instance_valid(target) or target.is_dead:
		return false
	if is_enemy(attacker, target):
		return true
	var ra = _team_root(attacker)
	if ra == null or not is_instance_valid(ra) or ra == _team_root(target):
		return false
	if target.team == "bot" and (ra.team == "player" or ra.team == "bot") and ra.faction_id != target.faction_id:
		return true
	return false

# ---------------------------------------------------------------- input
func _setup_input() -> void:
	var map := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"attack": [KEY_J], "secondary": [KEY_K], "dodge": [KEY_SPACE], "skill1": [KEY_1], "skill2": [KEY_2], "skill3": [KEY_3],
		"interact": [KEY_F, KEY_E], "swap": [KEY_TAB, KEY_R], "potion": [KEY_H], "inventory": [KEY_I], "map": [KEY_M],
		"journal": [KEY_L], "skills": [KEY_O], "pause": [KEY_ESCAPE, KEY_P], "companion": [KEY_C],
	}
	for action in map:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", mb)
	var mb2 := InputEventMouseButton.new()
	mb2.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("secondary", mb2)

# ---------------------------------------------------------------- lifecycle
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if world != null and mode == "world":
				SaveSys.save_game()
			Settings.save_settings()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			if world != null and mode == "world":
				SaveSys.save_game()
			Settings.save_settings()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Events.input_reset.emit()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if world != null and world.has_method("on_back_pressed"):
				world.on_back_pressed()
			elif get_tree().current_scene and get_tree().current_scene.has_method("on_back_pressed"):
				get_tree().current_scene.on_back_pressed()
