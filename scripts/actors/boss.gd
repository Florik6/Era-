class_name Boss
extends Actor
## Boss actor: multi-phase fights driven by BossBrain, damageable parts,
## shields, form changes, arena effects, escape-and-return (nemesis) logic.

var boss_id := ""
var def := {}
var phase := 0
var brain = null
var parts := {}              # part -> hp
var disabled_abilities := {}
var engaged := false
var shielded := false
var shield_adds: Array = []
var arena_center := Vector3.ZERO
var lair_id := ""
var can_escape := true
var returning := false
var times_escaped := 0
var bonus_abilities: Array = []

func setup_boss(id: String, lvl: int) -> void:
	boss_id = id
	def = DBActors.BOSSES[id]
	def_id = id
	level = lvl
	display_name = def.name
	team = "boss"
	kind = "boss"
	elite = true
	actor_id = "boss_" + id
	max_hp = def.hp * (1.0 + 0.12 * (lvl - 1)) * (1.0 + 0.3 * times_escaped)
	hp = max_hp
	base_dmg = def.dmg
	natural_dtype = def.get("dtype", "blunt")
	natural_range = 3.2 * def.get("scale", 1.5) * 0.7
	base_speed = 4.6 * def.get("speed", 1.0)
	stats = {"armor": 20.0 + lvl * 2.0, "base_hp": max_hp}
	for pn in def.get("parts", {}):
		parts[pn] = float(def.parts[pn]) * (1.0 + 0.12 * (lvl - 1))
	if def.rig in ["humanoid", "golem", "troll", "colossus"]:
		var r := HumanoidRig.new()
		var b := "normal"
		match def.rig:
			"golem": b = "golem"
			"troll": b = "bulky"
			"colossus": b = "colossus"
		if def.get("robot", false):
			b = "robot"
		r.setup({"build": b, "scale": def.get("scale", 1.6), "cloth_color": def.get("cloth", Color(0.3, 0.1, 0.1)),
			"body": def.get("body", Color(0.5, 0.5, 0.5)), "metal": def.get("metal", false), "glow": def.get("glow", Color(0, 0, 0, 0)),
			"hair": 0, "skin": 2, "armor": def.get("armor", ""), "hat": def.get("hat", "")})
		set_rig(r)
		if def.has("weapon"):
			data = CharData.new()
			data.level = lvl
			var w := ItemDB.create(def.weapon, 3, lvl, null, false)
			data.inv.add(w)
			data.inv.equip_item(w)
			r.set_gear(data.inv.equip)
	else:
		var cr := CreatureRig.new()
		cr.setup({"rig": def.rig, "body": def.get("body", Color(0.5, 0.5, 0.5)), "scale": def.get("scale", 2.0), "glow": def.get("glow", Color(1, 1, 1)), "metal": def.get("metal", false)})
		set_rig(cr)

func _ready() -> void:
	super._ready()
	brain = BossBrain.new(self)
	if arena_center == Vector3.ZERO:
		arena_center = global_position

func recalc_stats() -> void:
	pass   # bosses keep their scripted stats

func weapon_range() -> float:
	return natural_range + 0.8

func is_ranged() -> bool:
	return false

func _physics_process(delta: float) -> void:
	if not is_dead and brain != null:
		brain.tick(delta)
	super._physics_process(delta)

func take_damage(info: Dictionary) -> float:
	if shielded:
		VFX.text(chest() + Vector3(0, 1, 0), "Щит!", Color(0.7, 0.7, 1.0))
		return 0.0
	if not engaged and info.get("src") != null:
		engaged = true
		Events.boss_engaged.emit(self)
	var dealt := super.take_damage(info)
	if dealt > 0.0 and not parts.is_empty():
		var src = info.get("src")
		var pn := _part_hit(src)
		if pn != "" and parts[pn] > 0.0:
			parts[pn] -= dealt * 0.8
			if parts[pn] <= 0.0:
				_break_part(pn)
	return dealt

func _part_hit(src) -> String:
	if src == null or not is_instance_valid(src):
		return ""
	var local: Vector3 = (src.global_position - global_position).rotated(Vector3.UP, -rig.rotation.y)
	if local.z > 1.0 and parts.has("boiler") and parts.boiler > 0:
		return "boiler"
	if local.x < 0 and parts.has("left_arm") and parts.left_arm > 0:
		return "left_arm"
	if parts.has("right_arm") and parts.right_arm > 0:
		return "right_arm"
	for k in parts:
		if parts[k] > 0:
			return k
	return ""

func _break_part(pn: String) -> void:
	rig.break_part(pn)
	for ab in def.abilities:
		if def.abilities[ab].get("part", "") == pn:
			disabled_abilities[ab] = true
	_apply_raw_damage(max_hp * 0.06, null, "blunt")
	apply_status("stun", 2.0)
	VFX.explosion(chest(), 3.0, Color(1.0, 0.6, 0.2))
	Audio.play_sfx("robot_hit", global_position)
	var names := {"left_arm": "левая рука", "right_arm": "правая рука", "boiler": "котёл"}
	Events.banner.emit("Часть разрушена!", "%s: %s" % [display_name, names.get(pn, pn)], Color(1.0, 0.7, 0.3))
	Profile.milestone("boss_part")

func _corpse_time() -> float:
	return 12.0
