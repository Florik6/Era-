class_name Player
extends Actor
## The player: reads touch/keyboard input, auto-aim, interaction scanning,
## equipment/consumable operations used by the UI, action recording for the
## chrono double, death/respawn.

var interact_target = null
var _interact_t := 0.0
var respawn_point := Vector3.ZERO
var action_buffer: Array = []      # recorded actions for the chrono double
var notoriety := 0.0               # attracts hunters
var companion = null
var companion_mode := "follow"     # follow | attack | hold
var scripted_move := Vector3.ZERO  # tests / cutscenes override joystick input
var dimension := ""
var _attack_hold_t := 0.0
var _step_t := 0.0
var _aura_t := 0.0
var _last_cat := ""

func _ready() -> void:
	is_player = true
	team = "player"
	actor_id = "player"
	if data == null:
		data = Profile.char
	display_name = data.name
	kind = "humanoid"
	base_speed = 5.6
	var look := {"build": "normal", "skin": data.appearance.get("skin", 1), "hair": data.appearance.get("hair", 1),
		"hair_color": data.appearance.get("hair_color", 0), "beard": data.appearance.get("beard", 0),
		"cloth": data.appearance.get("cloth", 0), "female": data.female}
	var r := HumanoidRig.new()
	r.setup(look)
	set_rig(r)
	super._ready()
	faction_id = Game.world.factions.member_of() if (Game.world and Game.world.get("factions")) else ""
	refresh_gear()
	hp = max_hp
	mana = max_mana
	stamina = max_stamina

func recalc_stats() -> void:
	super.recalc_stats()
	if Game.world and Game.world.get("factions") and Game.world.factions != null and Game.mode == "world":
		var b: Dictionary = Game.world.factions.player_bonus()
		stats.dmg_pct += b.dmg
		stats.armor *= 1.0 + b.armor
		stats["xp_bonus"] = b.xp

func gain_xp(n: int) -> void:
	super.gain_xp(int(n * (1.0 + stat("xp_bonus"))))

func _physics_process(delta: float) -> void:
	if not is_dead:
		_read_input(delta)
		_interact_t -= delta
		if _interact_t <= 0.0:
			_interact_t = 0.15
			_scan_interact()
		_footsteps(delta)
		_aura_t += delta
		if _aura_t > 0.5:
			_aura_t = 0.0
			_tick_auras()
		var cat := weapon_cat()
		if cat != _last_cat:
			_last_cat = cat
			data.auto_slots(cat)
	super._physics_process(delta)

func _read_input(delta: float) -> void:
	var tc = Game.world.touch if Game.world else null
	var mv := Vector2.ZERO
	if tc:
		mv = tc.move_vec
	var kb := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if kb.length() > 0.1:
		mv = kb
	var cam_yaw: float = Game.world.cam.yaw if (Game.world and Game.world.get("cam")) else 0.0
	var dir := Vector3(mv.x, 0, mv.y).rotated(Vector3.UP, cam_yaw)
	if scripted_move.length() > 0.01:
		dir = scripted_move
	move_input = dir
	if Game.ui_is_open():
		move_input = Vector3.ZERO
		return
	var aim := Vector3.ZERO
	var manual_aim := false
	if tc and tc.aim_vec.length() > 0.3:
		aim = Vector3(tc.aim_vec.x, 0, tc.aim_vec.y).rotated(Vector3.UP, cam_yaw).normalized()
		manual_aim = true
	var attack_down = Input.is_action_pressed("attack") or (tc != null and tc.is_held("attack"))
	if attack_down:
		if not manual_aim:
			aim = auto_aim(dir)
		if attack(aim):
			_record("attack")
	if Input.is_action_pressed("secondary") or (tc != null and tc.is_held("block")):
		set_block(true)
	elif blocking:
		set_block(false)
	if Input.is_action_just_pressed("dodge") or (tc != null and tc.consume("dodge")):
		if dodge(dir if dir.length() > 0.1 else facing):
			_record("dodge")
	for i in 3:
		if Input.is_action_just_pressed("skill%d" % (i + 1)) or (tc != null and tc.consume("skill%d" % (i + 1))):
			var a2 := aim if manual_aim else auto_aim(dir)
			var s: Array = data.auto_slots(weapon_cat())
			if use_slot(i, a2):
				_record("skill", s[i])
	if Input.is_action_just_pressed("interact") or (tc != null and tc.consume("interact")):
		do_interact()
	if Input.is_action_just_pressed("swap") or (tc != null and tc.consume("swap")):
		swap_weapon()
	if Input.is_action_just_pressed("potion") or (tc != null and tc.consume("potion")):
		quick_potion()
	if Input.is_action_just_pressed("companion") or (tc != null and tc.consume("companion")):
		cycle_companion()
	if Input.is_action_just_pressed("inventory"):
		Game.world.ui.open("inventory")
	if Input.is_action_just_pressed("map"):
		Game.world.ui.open("map")
	if Input.is_action_just_pressed("journal"):
		Game.world.ui.open("journal")
	if Input.is_action_just_pressed("skills"):
		Game.world.ui.open("skills")

## Pick a target direction: nearest damageable enemy in a forward cone.
func auto_aim(move_dir: Vector3) -> Vector3:
	var ref := move_dir.normalized() if move_dir.length() > 0.2 else facing
	var rng := weapon_range() * 1.1 if is_ranged() else 4.5
	if not Settings.aim_assist and is_ranged():
		return ref
	var best = null
	var bs := INF
	for a in Game.actors_near(global_position, rng):
		if a == self or a.is_dead or not Game.can_damage(self, a):
			continue
		if a.team == "bot" and not Game.is_enemy(self, a) and a.combat_t > 6.0 and not a.actor_id in aggro:
			# do not auto-target peaceful contenders; manual aim still works
			continue
		var to: Vector3 = a.global_position - global_position
		to.y = 0
		var d := to.length()
		var ang := ref.angle_to(to.normalized()) if d > 0.1 else 0.0
		if ang > deg_to_rad(75.0) and d > 2.5:
			continue
		var score := d + ang * 4.0
		if score < bs:
			bs = score
			best = a
	if best:
		var t: Vector3 = best.global_position - global_position
		t.y = 0
		return t.normalized()
	return ref

func _record(type: String, id: String = "") -> void:
	action_buffer.append({"t": Time.get_ticks_msec(), "type": type, "id": id, "cat": weapon_cat()})
	if action_buffer.size() > 80:
		action_buffer.pop_front()

func _footsteps(delta: float) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv > 1.5 and is_on_floor():
		_step_t -= delta * hv
		if _step_t <= 0.0:
			_step_t = 2.2
			var heavy := stat("armor") > 25.0
			Audio.play_sfx("step_metal" if heavy else "step", global_position, -14.0, 0.15)

func _tick_auras() -> void:
	if _has_ability("frost_aura"):
		for a in Game.actors_near(global_position, 4.5):
			if a != self and not a.is_dead and Game.is_enemy(self, a):
				a.apply_status("slow", 0.8, {"f": 0.7})

# ---------------------------------------------------------------- interaction
func _scan_interact() -> void:
	var best = null
	var bd := INF
	for o in Game.grid.query(global_position, 4.0, "interact"):
		if not is_instance_valid(o) or o == self:
			continue
		var r: float = o.get("interact_radius") if o.get("interact_radius") != null else 2.0
		var d: float = o.global_position.distance_to(global_position)
		if d > r:
			continue
		if o.has_method("can_interact") and not o.can_interact(self):
			continue
		if d < bd:
			bd = d
			best = o
	if best != interact_target:
		interact_target = best
		Events.interact_changed.emit(best)

func interact_label() -> String:
	if interact_target and is_instance_valid(interact_target) and interact_target.has_method("interact_label"):
		return interact_target.interact_label()
	return ""

func do_interact() -> void:
	if interact_target and is_instance_valid(interact_target):
		start_action("interact", 0.35, 0.5, {"anim": "interact"})
		interact_target.interact(self)
		_interact_t = 0.0

# ---------------------------------------------------------------- equipment
func equip_item(item: Dictionary) -> Dictionary:
	var res: Dictionary = data.inv.equip_item(item)
	if res.ok:
		Audio.play_sfx("pickup", global_position, -4.0)
		if res.get("bound", false):
			Audio.play_sfx("curse_bind", global_position)
			VFX.ring(global_position, 2.0, Color(0.8, 0.1, 0.2), 0.8)
			VFX.burst(chest(), Color(0.9, 0.15, 0.25), 24, 0.35)
			Events.banner.emit("Проклятие!", res.msg, Color(0.9, 0.2, 0.25))
			Chronicle.record("curse_bound", [self], {"pos_v3": global_position, "extra": {"item": ItemDB.display_name(item)}})
			_maybe_start_release_quest(item)
		refresh_gear()
		Events.item_equipped.emit(self, item)
	return res

func unequip_slot(slot: String) -> Dictionary:
	var res: Dictionary = data.inv.unequip(slot)
	if res.ok:
		refresh_gear()
	elif res.msg != "":
		Audio.play_sfx("error")
	return res

func drop_item(item: Dictionary) -> bool:
	for s in data.inv.equip:
		if data.inv.equip[s].uid == item.uid:
			var r := unequip_slot(s)
			if not r.ok:
				Events.notify.emit(r.msg, Color(1, 0.4, 0.4))
				return false
	var it := data.inv.remove(item.uid)
	if it.is_empty():
		return false
	if Game.world and Game.world.get("loot"):
		Game.world.loot.spawn_drop(it, global_position + facing * 1.2, true)
	return true

func use_item(item: Dictionary) -> bool:
	var b := ItemDB.base(item.base)
	if b.get("slot", "") in ItemDB.SLOTS:
		return equip_item(item).ok
	var eff: String = b.get("effect", "")
	var ok := true
	match eff:
		"heal":
			heal(max_hp * b.power)
			VFX.burst(chest(), Color(0.4, 1.0, 0.4), 12, 0.3)
			Audio.play_sfx("heal", global_position)
		"mana":
			mana = minf(max_mana, mana + max_mana * b.power)
			Audio.play_sfx("heal", global_position)
		"heal_full":
			hp = max_hp
			mana = max_mana
			Audio.play_sfx("heal", global_position)
		"mutation":
			var good := randf() < 0.75
			apply_status("mutation", 30.0, {"good": good})
			if not good:
				apply_status("slow", 10.0, {"f": 0.7})
			Events.notify.emit("Мутация: +30% урона" if good else "Неудачная мутация: замедление", Color(0.5, 1.0, 0.4))
			Profile.milestone("alchemy")
		"identify":
			ok = identify_all() > 0 or true
		"purify":
			ok = purify("purify")
		"release_any":
			ok = purify("artifact")
		"bomb":
			throw_bomb(item.base)
		"learn_school":
			if data.learn_school(b.school):
				Events.banner.emit("Новая школа магии", DBSkills.SCHOOLS[b.school].name, DBSkills.SCHOOLS[b.school].color)
				Audio.play_sfx("mastery_up")
				data.auto_slots(weapon_cat())
				Profile.milestone("learn_school")
			else:
				Events.notify.emit("Эта школа уже изучена", Color(0.8, 0.8, 0.8))
				ok = false
		"chrono_double":
			if Game.world and Game.world.has_method("spawn_chrono_double"):
				Game.world.spawn_chrono_double(self)
		"companion":
			if Game.world and Game.world.has_method("summon_companion"):
				Game.world.summon_companion(self)
		_:
			ok = false
	if ok:
		data.inv.consume(item.base, 1)
		_record("item", item.base)
	return ok

func identify_all() -> int:
	var n := 0
	for it in data.inv.items + data.inv.equip.values():
		var c: Dictionary = it.get("curse", {})
		if c.size() > 0 and c.get("hidden", false):
			c.hidden = false
			n += 1
	Events.notify.emit("Распознано проклятий: %d" % n if n > 0 else "Скрытых проклятий не найдено", Color(0.8, 0.7, 1.0))
	if n > 0:
		Profile.milestone("identify_curse")
		Audio.play_sfx("dark_cast")
	return n

func purify(method: String, boss_id: String = "") -> bool:
	var freed: Array = data.inv.release_curse(method, boss_id)
	# non-bound curses can always be purified by scrolls/altars
	if method in ["purify", "artifact"]:
		for it in data.inv.items + data.inv.equip.values():
			var c: Dictionary = it.get("curse", {})
			if c.size() > 0 and not c.get("bound", false):
				it.curse = {}
				freed.append(it)
	if freed.is_empty():
		Events.notify.emit("Нечего очищать этим способом", Color(0.8, 0.8, 0.8))
		return false
	for it in freed:
		Chronicle.record("curse_broken", [self], {"pos_v3": global_position, "extra": {"item": ItemDB.display_name(it)}})
	Events.banner.emit("Проклятие снято", ", ".join(freed.map(func(x): return ItemDB.display_name(x))), Color(0.6, 1.0, 0.9))
	Profile.unlock("curse_broken")
	Audio.play_sfx("heal")
	refresh_gear()
	return true

func _maybe_start_release_quest(item: Dictionary) -> void:
	var c: Dictionary = item.get("curse", {})
	if c.get("release", "") == "quest" and Game.world and Game.world.get("quests"):
		Game.world.quests.start_release_quest(item)

func throw_bomb(base_id: String) -> void:
	var target := global_position + auto_aim(move_input) * 8.0
	start_action("skill", 0.45, 0.5, {"anim": "throw", "cb": func():
		var info := {"amount": 30.0 + level * 6.0, "dtype": "fire", "status": {"burn": 6.0}, "src": self}
		Projectile.spawn(self, chest() + facing * 0.5, (target - global_position).normalized() * 16.0 + Vector3(0, 4, 0), info, "magic", {"range": 12.0, "splash": 3.5, "color": Color(1.0, 0.6, 0.2)})})

func swap_weapon() -> void:
	var cur := weapon()
	var cur_cat := weapon_cat()
	var best := {}
	for it in data.inv.items:
		var b := ItemDB.base(it.base)
		if b.get("slot", "") == "main" and b.get("cat", "") != cur_cat:
			if best.is_empty() or ItemDB.power(it) > ItemDB.power(best):
				best = it
	if best.is_empty():
		for it in data.inv.items:
			if ItemDB.base(it.base).get("slot", "") == "main" and it.uid != cur.get("uid", -1):
				best = it
				break
	if best.is_empty():
		Events.notify.emit("Нет другого оружия", Color(0.8, 0.8, 0.8))
		return
	var r := equip_item(best)
	if r.ok:
		Events.notify.emit("Оружие: " + ItemDB.display_name(best), ItemDB.rarity_color(best))
		Audio.play_sfx("swing", global_position, -6.0)
	else:
		Events.notify.emit(r.msg, Color(1, 0.4, 0.4))

func quick_potion() -> void:
	var order := ["potion_hp", "potion_big"] if hp < max_hp * 0.95 else ["potion_mana"]
	for b in order:
		for it in data.inv.items:
			if it.base == b:
				use_item(it)
				return
	Events.notify.emit("Нет подходящих зелий", Color(0.8, 0.8, 0.8))

func cycle_companion() -> void:
	if companion == null or not is_instance_valid(companion) or companion.is_dead:
		return
	var modes := ["follow", "attack", "hold"]
	companion_mode = modes[(modes.find(companion_mode) + 1) % modes.size()]
	var names := {"follow": "За мной", "attack": "Атаковать", "hold": "Стоять"}
	Events.notify.emit("Спутник: " + names[companion_mode], Color(0.6, 0.9, 1.0))

func potion_count() -> int:
	return data.inv.count("potion_hp") + data.inv.count("potion_big")

# ---------------------------------------------------------------- death
func _on_death(killer) -> void:
	Profile.add_stat("deaths")
	Events.player_died.emit()

func _remove_corpse() -> void:
	pass   # the world handles respawn

func respawn_at(p: Vector3) -> void:
	is_dead = false
	dead_t = 0.0
	collision_layer = LAYER_ACTOR
	statuses.clear()
	hp = max_hp
	mana = max_mana
	stamina = max_stamina
	if rig:
		rig.dead = false
	global_position = p
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	Events.player_respawned.emit()
