class_name Monster
extends Actor
## Non-humanoid creatures (wolves, drones, spiders, wraiths, blobs, mimics,
## trolls/golems built on the humanoid rig) and summoned allies/companions.

var brain = null
var home := Vector3.ZERO
var leash := 45.0
var spells: Array = []
var proj_kind := ""
var is_companion := false
var companion_kind := ""

func _ready() -> void:
	if kind == "humanoid":
		kind = "creature"
	super._ready()
	if home == Vector3.ZERO:
		home = global_position
	if brain == null:
		brain = MonsterBrain.new(self)

func _physics_process(delta: float) -> void:
	if not is_dead and brain != null:
		brain.tick(delta)
	super._physics_process(delta)

func is_ranged() -> bool:
	return proj_kind != "" or not spells.is_empty()

func weapon_range() -> float:
	if proj_kind != "":
		return 16.0
	if not spells.is_empty():
		return 14.0
	return natural_range

## Natural ranged attack (drones, turrets).
func shoot_at(t) -> void:
	if attack_cd > 0.0 or not can_act():
		return
	attack_cd = 1.1
	var dir: Vector3 = (t.chest() - chest()).normalized()
	face_dir(dir)
	var info := {"amount": base_dmg, "dtype": natural_dtype, "src": self, "melee": false, "knock": 0.5, "status": {}}
	var muzzle := chest() + Vector3(0, 0.6 if rig and rig.get("kind") == "drone" else 0.0, 0) + dir * 0.6
	Projectile.spawn(self, muzzle, dir * 55.0, info, proj_kind if proj_kind != "" else "bullet", {"range": 22.0})
	Audio.play_sfx("gun_modern" if proj_kind == "bullet" else "laser", global_position, -6.0)
	if rig:
		rig.trigger("shoot")
		act = {"name": "shoot_nat", "t": 0.0, "dur": 0.3, "impact": 2.0, "done": true, "data": {}}

func _on_death(_killer) -> void:
	if is_companion and Game.player and Game.player.companion == self:
		Events.notify.emit("Спутник пал. Его можно призвать снова.", Color(1.0, 0.6, 0.5))
