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
var shield: BossShield = null   # magic shield state machine (see boss_shield.gd)
var shielded: bool:
	get:
		return shield != null and shield.is_active()
var _shield_txt_ms := 0
var arena_center := Vector3.ZERO
var lair_id := ""
var leash_radius := 0.0      # >0: never leaves its lair farther than this (world bosses)
var can_escape := true
var returning := false
var times_escaped := 0
var bonus_abilities: Array = []

func setup_boss(id: String, lvl: int) -> void:
	shield = BossShield.new(self)
	boss_id = id
	def = DBActors.bget(id)
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
	elif def.rig == "beast":
		var br := BeastRig.new()
		br.setup({"plan": def.get("plan", "giant"), "f": def.get("f", {}), "body": def.get("body", Color(0.5, 0.5, 0.5)), "accent": def.get("accent", Color(0.3, 0.3, 0.3)),
			"glow": def.get("glow", Color(1.0, 0.6, 0.2)), "metal": def.get("metal", false), "scale": def.get("scale", 2.0)})
		set_rig(br)
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
	if shield != null and shield.state != BossShield.INACTIVE:
		shield.tick(delta)
	super._physics_process(delta)

func take_damage(info: Dictionary) -> float:
	# the shield is a pool of shield HP, not invulnerability
	if shield != null and shield.is_active():
		var passed := shield.absorb(info)
		if passed <= 0.0:
			if Time.get_ticks_msec() - _shield_txt_ms > 400:
				_shield_txt_ms = Time.get_ticks_msec()
				VFX.text(chest() + Vector3(0, 1, 0), "Щит %d%%" % roundi(shield.ratio() * 100.0), Color(0.7, 0.75, 1.0))
			if not engaged and info.get("src") != null:
				engaged = true
				Events.boss_engaged.emit(self)
			return 0.0
		info = info.duplicate()
		info.amount = passed
	if not engaged and info.get("src") != null:
		engaged = true
		Events.boss_engaged.emit(self)
	# parry stance: melee blows are turned aside and answered (wait it out or use spells / arrows)
	if statuses.has("parry_stance") and info.get("melee", false) and info.get("src") != null and is_instance_valid(info.src):
		var src_a = info.src
		VFX.parry_fx(chest() + facing * 0.8, facing)
		VFX.text(chest() + Vector3(0, 1.0, 0), "Парировано!", Color(0.9, 0.9, 1.0))
		Audio.play_sfx("parry", global_position)
		if rig:
			rig.trigger("thrust")
		if src_a is Actor and global_position.distance_to(src_a.global_position) < natural_range + 2.0:
			Combat.deal(self, src_a, {"amount": base_dmg * 0.9, "dtype": natural_dtype, "src": self, "melee": true, "knock": 4.0})
		return 0.0
	# weak points: every destroyed part makes the boss take more damage
	if not parts.is_empty():
		var broken_n := 0
		for k in parts:
			if parts[k] <= 0.0:
				broken_n += 1
		if broken_n > 0:
			info = info.duplicate()
			info.amount = float(info.amount) * (1.0 + 0.15 * broken_n)
	# time-immune bosses shrug off slowing time
	var dealt := super.take_damage(info)
	if shield != null and shield.state == BossShield.CHARGING and dealt > 0.0:
		shield._charge_taken += dealt
		if shield._charge_taken >= max_hp * float(shield.spec.get("interrupt", 0.06)):
			shield.interrupt("сильный урон сорвал подготовку щита")
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
	# named weak points (Beasts of the Ages): left / right / back by where the blow comes from
	for k in parts:
		if parts[k] <= 0:
			continue
		if str(k).ends_with("back") and local.z > 0.8:
			return k
		if str(k).ends_with("_l") and local.x < 0.0 and local.z <= 0.8:
			return k
		if str(k).ends_with("_r") and local.x >= 0.0 and local.z <= 0.8:
			return k
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
	var names := {"left_arm": "левая рука", "right_arm": "правая рука", "boiler": "котёл", "plate_l": "левая пластина", "plate_r": "правая пластина",
		"plate_back": "спинной панцирь", "flask_l": "левая колба", "flask_r": "правая колба", "gear_l": "левая шестерня", "gear_r": "правая шестерня",
		"module_l": "левый модуль", "module_r": "правый модуль", "module_back": "спинной модуль", "rune_l": "левая руна", "rune_r": "правая руна", "rune_back": "спинная руна"}
	Events.banner.emit("Часть разрушена!", "%s: %s" % [display_name, names.get(pn, pn)], Color(1.0, 0.7, 0.3))
	Profile.milestone("boss_part")

func _corpse_time() -> float:
	return 12.0

func _on_death(killer) -> void:
	if shield != null:
		shield.clear()
	super._on_death(killer)

func _exit_tree() -> void:
	if shield != null:
		shield.clear()
	super._exit_tree()
