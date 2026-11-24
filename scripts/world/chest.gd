class_name Chest
extends StaticBody3D
## Lootable chest. ~7% are mimics with subtle tells (odd tint, faint breathing).
## Interactable protocol: grid category "interact", interact_radius,
## interact_label(), interact(actor).

var uid := ""
var tier := "normal"        # normal | rich
var lvl := 1
var era := 0
var is_mimic := false
var opened := false
var state: Dictionary = {}
var interact_radius := 1.9
var bot_ignore := false
var _lid: Node3D
var _base: Node3D
var _t := 0.0
var _registered := false

func configure(id: String, st: Dictionary, era_i: int, chest_tier: String = "normal", level: int = 1, mimic_roll: float = 1.0) -> void:
	uid = id
	state = st
	era = era_i
	tier = chest_tier
	lvl = level
	is_mimic = mimic_roll < 0.07

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("chests")
	if uid != "" and state.has("opened") and uid in state.opened:
		opened = true
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.95, 0.7, 0.65)
	cs.shape = sh
	cs.position.y = 0.35
	add_child(cs)
	_build()
	if opened:
		_lid.rotation.x = -1.9
		is_mimic = false
	else:
		Game.grid.insert(self, global_position, "interact")
		_registered = true
	set_process(is_mimic and not opened)

func _exit_tree() -> void:
	if _registered:
		Game.grid.remove(self, "interact")
		_registered = false

func _build() -> void:
	_base = Node3D.new()
	add_child(_base)
	var wood_c := Color(0.48, 0.32, 0.16)
	var trim_c := Color(0.35, 0.33, 0.3)
	if tier == "rich":
		wood_c = Color(0.38, 0.12, 0.12)
		trim_c = Color(0.9, 0.72, 0.25)
	if era >= 3:
		wood_c = Color(0.3, 0.34, 0.3) if era == 3 else Color(0.2, 0.22, 0.3)
		trim_c = Color(0.6, 0.62, 0.65) if tier != "rich" else Color(0.9, 0.72, 0.25)
	if is_mimic:
		wood_c = wood_c.lerp(Color(0.5, 0.22, 0.18), 0.22)
	var wm := MeshLib.mat(wood_c)
	var tm := MeshLib.mat(trim_c, 0.75, 0.35)
	MeshLib.part(_base, MeshLib.box(Vector3(0.9, 0.5, 0.6)), wm, Vector3(0, 0.25, 0))
	MeshLib.part(_base, MeshLib.box(Vector3(0.92, 0.06, 0.62)), tm, Vector3(0, 0.47, 0))
	MeshLib.part(_base, MeshLib.box(Vector3(0.06, 0.5, 0.62)), tm, Vector3(-0.3, 0.25, 0))
	MeshLib.part(_base, MeshLib.box(Vector3(0.06, 0.5, 0.62)), tm, Vector3(0.3, 0.25, 0))
	_lid = MeshLib.pivot(_base, Vector3(0, 0.5, 0.3))
	MeshLib.part(_lid, MeshLib.box(Vector3(0.9, 0.2, 0.6)), wm, Vector3(0, 0.1, -0.3))
	MeshLib.part(_lid, MeshLib.box(Vector3(0.12, 0.12, 0.05)), MeshLib.mat(Color(0.95, 0.78, 0.3), 0.8, 0.3), Vector3(0, 0.0, -0.61))
	if tier == "rich" and not opened:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.35)
		l.light_energy = 0.6
		l.omni_range = 3.0
		l.position = Vector3(0, 0.9, 0)
		l.shadow_enabled = false
		add_child(l)

func _process(delta: float) -> void:
	if not is_mimic or opened:
		return
	_t += delta
	# the tell: a faint, slow breathing and a twitching lid
	_base.scale = Vector3(1.0, 1.0 + sin(_t * 1.6) * 0.018, 1.0)
	_lid.rotation.x = -absf(sin(_t * 0.9)) * 0.03

func interact_label() -> String:
	return "Открыть богатый сундук" if tier == "rich" else "Открыть сундук"

func can_interact(_actor = null) -> bool:
	return not opened

func interact(actor) -> void:
	if opened:
		return
	opened = true
	if _registered:
		Game.grid.remove(self, "interact")
		_registered = false
	if uid != "" and state.has("opened") and not uid in state.opened:
		state.opened.append(uid)
	if is_mimic:
		Audio.play_sfx("mimic", global_position)
		var spawned = null
		if Game.world and Game.world.get("spawner") and Game.world.spawner and Game.world.spawner.has_method("spawn_enemy"):
			spawned = Game.world.spawner.spawn_enemy("mimic", global_position, lvl)
		if spawned == null:
			VFX.burst(global_position + Vector3(0, 0.5, 0), Color(0.6, 0.2, 0.2), 14, 0.35)
		queue_free()
		return
	Audio.play_sfx("chest_open", global_position)
	var tw := _lid.create_tween()
	tw.tween_property(_lid, "rotation:x", -1.9, 0.35).set_ease(Tween.EASE_OUT)
	VFX.burst(global_position + Vector3(0, 0.7, 0), Color(1.0, 0.85, 0.4), 10, 0.25)
	Events.chest_opened.emit(actor, self)
	if Game.world and Game.world.get("loot") and Game.world.loot and Game.world.loot.has_method("roll_chest"):
		Game.world.loot.roll_chest(self, actor)
	set_process(false)
