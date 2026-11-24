class_name NPC
extends Actor
## Humanoid AI actor: contenders (bots), bandits, villagers, traders, guards,
## faction soldiers, hunters, relic hunters, the Last Witness, chrono doubles.

var brain = null
var role := "bot"            # bot | enemy | villager | trader | guard | soldier | hunter | double | witness | companion
var archetype := "explorer"
var home := Vector3.ZERO
var settlement_id := ""
var squad := {}              # {id, faction, order: attack|defend|patrol, pos: Vector3}
var yielding := false
var yield_t := 0.0
var spared_by := ""
var dialog_kind := ""        # villager | trader | quest | faction | witness | guard | legend
var can_loot := true
var relic_hunter := false
var unit_role := ""          # infantry | archer | mage | heavy | scout | commander
var _ig_t := 0.0
var _in_interact_grid := false

func _ready() -> void:
	kind = "humanoid"
	super._ready()
	if brain == null:
		brain = BotBrain.new(self)
	home = global_position if home == Vector3.ZERO else home

func _physics_process(delta: float) -> void:
	if not is_dead and brain != null:
		brain.tick(delta)
	super._physics_process(delta)
	_ig_t -= delta
	if _ig_t <= 0.0:
		_ig_t = 0.5
		_update_interact_grid()

func _update_interact_grid() -> void:
	var want := not is_dead and (dialog_kind != "" or yielding)
	if want:
		Game.grid.update(self, global_position, "interact")
		_in_interact_grid = true
	elif _in_interact_grid:
		Game.grid.remove(self, "interact")
		_in_interact_grid = false

func _exit_tree() -> void:
	Game.grid.remove(self, "interact")
	if brain and brain.has_method("shutdown"):
		brain.shutdown()
	super._exit_tree()

var interact_radius := 2.6

func can_interact(a) -> bool:
	if is_dead:
		return false
	if yielding:
		return true
	return dialog_kind != "" and not Game.is_enemy(self, a)

func interact_label() -> String:
	if yielding:
		return "Пощадить: " + display_name
	match dialog_kind:
		"trader": return "Торговать: " + display_name
		"quest": return "Задание: " + display_name
		"faction": return "Говорить: " + display_name
	return "Говорить: " + display_name

func interact(a) -> void:
	if yielding:
		spare(a)
		return
	face_dir(a.global_position - global_position)
	if Game.world and Game.world.get("dialogs"):
		Game.world.dialogs.open_npc(self)

func start_yield() -> void:
	if yielding or is_dead:
		return
	yielding = true
	yield_t = 12.0
	act = {}
	blocking = false
	move_input = Vector3.ZERO
	if rig:
		rig.yielding = true
	VFX.text(chest() + Vector3(0, 0.6, 0), "Пощади!", Color(1.0, 0.9, 0.6))
	_update_interact_grid()

func end_yield() -> void:
	yielding = false
	if rig:
		rig.yielding = false
	_update_interact_grid()

func spare(by) -> void:
	end_yield()
	spared_by = by.actor_id
	aggro.erase(by.actor_id)
	by.aggro.erase(actor_id)
	heal(max_hp * 0.3)
	if brain:
		brain.on_spared(by)
	Chronicle.record("mercy", [by, self], {"pos_v3": global_position})
	if by.is_player:
		Profile.unlock("mercy")
		Events.notify.emit("%s запомнит вашу милость." % display_name, Color(0.8, 1.0, 0.8))

func _on_death(_killer) -> void:
	end_yield()
	Game.grid.remove(self, "interact")
