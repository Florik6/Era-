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
var _reload_hold := -1.0   # touch: holding «Перезарядка» on an energy weapon switches the boosted shot
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
	var look := look_from(data)
	var r := HumanoidRig.new()
	r.setup(look)
	set_rig(r)
	super._ready()
	faction_id = Game.world.factions.member_of() if (Game.world and Game.world.get("factions")) else ""
	refresh_gear()
	hp = max_hp
	mana = max_mana
	stamina = max_stamina
	ManaSys.restore_saved(self)      # a load / new scene keeps the mana the hero had

func _exit_tree() -> void:
	if not is_dead:
		ManaSys.store(self)
	super._exit_tree()

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
		var cat := mastery_cat()
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
	for i in data.slot_count():
		var act := "skill%d" % (i + 1)
		if (InputMap.has_action(act) and Input.is_action_just_pressed(act)) or (tc != null and tc.consume(act)):
			var a2 := aim if manual_aim else auto_aim(dir)
			var s: Array = data.active_slots(mastery_cat())
			if use_slot(i, a2):
				_record("skill", s[i])
	if (InputMap.has_action("skill_page") and Input.is_action_just_pressed("skill_page")) or (tc != null and tc.consume("skill_page")):
		data.ab_page = 1 - data.ab_page
		Events.notify.emit("Страница умений %d" % (data.ab_page + 1), Color(0.7, 0.8, 1.0))
	if Input.is_action_just_pressed("interact") or (tc != null and tc.consume("interact")):
		do_interact()
	if Input.is_action_just_pressed("swap") or (tc != null and tc.consume("swap")):
		swap_weapon()
	if InputMap.has_action("reload") and Input.is_action_just_pressed("reload"):
		reload()
	if InputMap.has_action("boost") and Input.is_action_just_pressed("boost"):
		toggle_boost()
	if tc != null:
		var rl_press: bool = tc.consume("reload")
		if not Ammo.is_energy(weapon_base()):
			_reload_hold = -1.0
			if rl_press:
				reload()
		elif tc.is_held("reload"):
			_reload_hold = maxf(_reload_hold, 0.0) + delta
			if _reload_hold >= 0.5 and _reload_hold - delta < 0.5:
				toggle_boost()
		elif _reload_hold >= 0.0:
			if _reload_hold < 0.5:
				reload()
			_reload_hold = -1.0
	if Input.is_action_just_pressed("potion") or (tc != null and tc.consume("potion")):
		quick_potion()
	if (InputMap.has_action("mana_potion") and Input.is_action_just_pressed("mana_potion")) or (tc != null and tc.consume("mana_potion")):
		quick_mana_potion()
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
	action_buffer.append({"t": Time.get_ticks_msec(), "type": type, "id": id, "cat": mastery_cat()})
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
	for o in Game.grid.query(global_position, 7.0, "interact"):
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
func _ritual_lock() -> bool:
	return Game.world != null and Game.world.get("active_ritual") != null and is_instance_valid(Game.world.active_ritual)

func equip_item(item: Dictionary) -> Dictionary:
	if _ritual_lock():
		return {"ok": false, "msg": "Нельзя менять снаряжение во время ритуала."}
	if ItemDB.base(item.base).get("slot", "") in ["main", "off"]:
		Ammo.cancel_reload(self, "смена оружия")
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
	if _ritual_lock():
		return {"ok": false, "msg": "Нельзя снимать снаряжение во время ритуала."}
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

## Dye palette for cloaks and cloth (appearance option, saved as an index).
const DYES := [Color(0.55, 0.1, 0.1), Color(0.12, 0.25, 0.55), Color(0.15, 0.4, 0.2), Color(0.45, 0.35, 0.15),
	Color(0.35, 0.15, 0.45), Color(0.12, 0.12, 0.14), Color(0.8, 0.78, 0.72), Color(0.7, 0.4, 0.1)]
const DYE_NAMES := ["Багровый", "Синий", "Лесной", "Охра", "Пурпур", "Чёрный", "Белый", "Медный"]

## Rig look from the saved appearance (also used by the inventory preview).
static func look_from(d: CharData) -> Dictionary:
	var a: Dictionary = d.appearance
	var look := {"build": "normal", "skin": a.get("skin", 1), "hair": a.get("hair", 1), "hair_color": a.get("hair_color", 0),
		"beard": a.get("beard", 0), "cloth": a.get("cloth", 0), "female": d.female, "hide_helm": int(a.get("hide_helm", 0)) == 1}
	var di := int(a.get("dye", -1))
	if di >= 0 and di < DYES.size():
		look["dye"] = DYES[di]
	return look

func use_item(item: Dictionary) -> bool:
	var b := ItemDB.base(item.base)
	if b.get("slot", "") in ItemDB.SLOTS:
		return equip_item(item).ok
	if b.get("slot", "") == "ammo":
		# loading a special ammo: what is in the magazine goes back to the reserve
		var why := Ammo.select_kind(self, item.base)
		if why != "":
			Events.notify.emit("%s: %s" % [b.name, why], Color(1.0, 0.7, 0.4))
			return false
		Events.notify.emit("Заряжено: %s" % b.name, Color(0.8, 0.95, 1.0))
		if Ammo.has_mag(weapon_base()):
			reload()
		return true
	var eff: String = b.get("effect", "")
	var ok := true
	match eff:
		"med":
			# medicine: in Hardcore it treats wounds (bleeding, infection, fractures…);
			# in the normal mode it heals a little
			var hc = Game.world.sys("hardcore") if Game.world else null
			if hc != null and hc.enabled():
				ok = hc.apply_medicine(self, item.base, b.get("med", {}))
			else:
				heal(max_hp * float(b.get("med", {}).get("heal", 0.05)))
				VFX.burst(chest(), Color(0.6, 1.0, 0.7), 8, 0.25)
				Audio.play_sfx("heal", global_position, -4.0)
		"heal":
			heal(max_hp * b.power)
			VFX.burst(chest(), Color(0.4, 1.0, 0.4), 12, 0.3)
			Audio.play_sfx("heal", global_position)
		"mana":
			var why := ManaSys.drink(self, item.base)
			if why != "":
				Events.notify.emit("%s: %s" % [b.name, why], Color(0.7, 0.8, 1.0))
				return false
		"heal_full":
			if potion_mana_cd > 0.0:
				Events.notify.emit("%s: подождите %.0f с" % [b.name, ceilf(potion_mana_cd)], Color(0.7, 0.8, 1.0))
				return false
			hp = max_hp
			mana = max_mana
			potion_mana_cd = ManaSys.POTION_CD
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
				data.auto_slots(mastery_cat())
				Profile.milestone("learn_school")
			else:
				Events.notify.emit("Эта школа уже изучена", Color(0.8, 0.8, 0.8))
				ok = false
		"learn_knowledge":
			var kk: String = str(item.get("knowledge", ""))
			if kk == "" or data.knowledge.has(kk):
				Events.notify.emit("Это знание уже ваше" if kk != "" else "Страницы истлели", Color(0.8, 0.8, 0.8))
				ok = false
			else:
				data.knowledge[kk] = true
				var sp: Dictionary = DBAbilities.get_ab(kk.trim_prefix("tome_"))
				Events.banner.emit("Древнее знание", "«%s» — теперь его можно изучить" % sp.get("name", kk), DBAbilities.school_info(str(sp.get("school", ""))).get("color", Color(1.0, 0.85, 0.5)))
				Audio.play_sfx("mastery_up")
				Profile.milestone("treatise")
				data.inv.remove(int(item.uid))
				return true
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
	Ammo.cancel_reload(self, "смена оружия")
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
	if hp >= max_hp * 0.95:
		quick_mana_potion()
		return
	var order := ["potion_hp", "potion_big"]
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

## Energy weapons: normal shot (1 unit) ↔ boosted shot (5 units, ×4).
func toggle_boost() -> void:
	var why := Ammo.toggle_boost(self)
	if why != "":
		Events.notify.emit(why, Color(0.8, 0.8, 0.8))
		return
	if Ammo.boost_on(self):
		Events.notify.emit("Усиленный выстрел: %d ед. заряда, урон ×%d" % [Ammo.BOOST_COST, int(Ammo.BOOST_MULT)], Color(0.45, 0.85, 1.0))
	else:
		Events.notify.emit("Обычный выстрел: 1 ед. заряда", Color(0.8, 0.9, 1.0))
	Audio.play_sfx("ui_click", global_position, -4.0)

## Quick mana potion (HUD button): the smallest one that does the job.
func quick_mana_potion() -> void:
	var need := max_mana - mana
	var order := ["potion_mana_small", "potion_mana", "potion_mana_big", "potion_mana_elixir"]
	if need > max_mana * 0.45:
		order = ["potion_mana_big", "potion_mana", "potion_mana_elixir", "potion_mana_small"]
	elif need > max_mana * 0.25:
		order = ["potion_mana", "potion_mana_big", "potion_mana_small", "potion_mana_elixir"]
	for bid in order:
		for it in data.inv.items:
			if it.base == bid:
				use_item(it)
				return
	Events.notify.emit("Нет зелий маны", Color(0.7, 0.8, 1.0))

func mana_potion_count() -> int:
	var n := 0
	for bid in ManaSys.POTIONS:
		n += data.inv.count(bid)
	return n

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
