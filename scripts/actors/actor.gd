class_name Actor
extends CharacterBody3D
## Shared base for the player, bots, monsters, bosses, companions and summons.
## Owns vitals, statuses, the weapon/attack state machine, blocking/parry,
## dodging, skills/spells dispatch, damage intake and death.

signal died(actor, killer)

const LAYER_WORLD := 1
const LAYER_ACTOR := 2
const LAYER_DESTRUCT := 4

var actor_id := ""
var display_name := ""
var title := ""
var team := "neutral"
var faction_id := ""
var owner_actor = null
var kind := "humanoid"            # humanoid | creature | boss
var def_id := ""
var data: CharData = null
var record: Dictionary = {}       # living-legend record (shared reference) if significant
var aggro := {}                   # actor_id -> expire time (ms)
var level := 1
var is_dead := false
var is_player := false
var elite := false
var hunting_player := false
var summon_time := -1.0           # >0 = temporary summon lifetime
var base_hp_override := 0.0       # enemies: hp from data tables instead of class

var hp := 100.0
var max_hp := 100.0
var mana := 50.0
var max_mana := 50.0
var stamina := 100.0
var max_stamina := 100.0
var stats := {}
var base_dmg := 10.0
var natural_dtype := "slash"
var natural_range := 2.0
var resist := {}

var move_input := Vector3.ZERO
var facing := Vector3(0, 0, -1)
var base_speed := 5.2
var knockback := Vector3.ZERO
var combat_t := 99.0              # seconds since last combat activity
var rig: Node3D = null

var act := {}
var attack_cd := 0.0
var combo := 0
var combo_t := 0.0
## Rounds in the equipped weapon's magazine (stored in the weapon item, see Ammo).
var ammo: int:
	get:
		return Ammo.loaded(self)
	set(v):
		Ammo.set_loaded(self, v)
var reload_t := 0.0
var reload_total := 1.0
var blocking := false
var block_t := 0.0
var dodge_t := 0.0
var dodge_cd := 0.0
var dodge_dir := Vector3.ZERO
var dodge_total := 0.45
var dodge_kind := "roll"
var move_vel := Vector3.ZERO      # planar velocity with inertia
var lunge_vel := Vector3.ZERO     # attack step-in impulse
var counter_t := 0.0              # window after a parry: next attack is a counter
var counter_target = null
var _skid_t := 0.0
var _ghost_t := 0.0
var _mstyle: Dictionary = {}
var _lean := 0.0
var _pitch := 0.0
var _prev_yaw := 0.0
var lod_tier := 0              # 0 near, 1 mid, 2 far (set by PerfLOD)
# «Ascension of Power»: buff stat changes from statuses, passive skill hooks
var _buff_mods := {}
var _hooks := {}
var _relentless := 0
var _relentless_t := 0.0
var _heat := 0.0
var _overheat_t := 0.0
var _still_t := 0.0
var _run_t := 0.0
var _dodge_chain := 0
var _last_dodge_ms := 0
var _resonant_n := 0
var _anti_charge_cd := 0.0
var _passive_t := 0.0
var _last_cast_ms := 0
var mana_delay_t := 0.0          # no mana regeneration right after a cast (ManaSys)
var _mana_fresh := true          # an NPC that has not cast yet enters the world with a full pool
var potion_mana_cd := 0.0        # shared cool-down of mana potions
var _lod_n := 0
var _lod_sum := 0.0
var _lod_dt := 0.0
var _lod_pre := false          # subclass already did the LOD gate this tick
var skill_cd := {}
var statuses := {}
var riposte := false
var shield_hp := 0.0
var last_attacker = null
var damage_log := {}
var rewind_cd := 0.0
var hit_count := 0
var dead_t := 0.0
var in_water := false
var gravity := 24.0
var _grid_t := 1.0     # first physics tick re-files the actor at its real position
var _regen_t := 0.0
var _echo_queue: Array = []

func _ready() -> void:
	collision_layer = LAYER_ACTOR
	collision_mask = LAYER_WORLD | LAYER_DESTRUCT
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(50)
	if actor_id == "":
		actor_id = Game.new_uid("a")
	if get_node_or_null("Col") == null:
		var cs := CollisionShape3D.new()
		cs.name = "Col"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35 * _scale()
		cap.height = 1.8 * _scale()
		cs.shape = cap
		cs.position.y = 0.9 * _scale()
		add_child(cs)
	Game.register_actor(self)

func _exit_tree() -> void:
	Game.unregister_actor(self)

func _scale() -> float:
	return rig.scale.x if rig else 1.0

func radius() -> float:
	return 0.4 * _scale()

func chest() -> Vector3:
	return global_position + Vector3(0, 1.2 * _scale(), 0)

# ---------------------------------------------------------------- setup / stats
func set_rig(r: Node3D) -> void:
	rig = r
	add_child(r)

func refresh_gear() -> void:
	if data and rig:
		var fc := Color(0, 0, 0, 0)
		if faction_id != "":
			fc = DBEras.faction(faction_id).get("color", fc)
		rig.set_gear(data.inv.equip, fc, record.get("legend", false) or record.get("commander", false))
	recalc_stats()

func recalc_stats() -> void:
	var s := {"armor": 0.0, "hp": 0.0, "mana": 0.0, "crit": 0.05, "speed": 0.0, "aspd": 0.0, "dmg_pct": 0.0, "lifesteal": 0.0,
		"fire_dmg": 0.0, "ice_dmg": 0.0, "lightning_dmg": 0.0, "regen": 0.0, "luck": 0.0, "spell": 0.0, "block": 0.0,
		"res_fire": 0.0, "res_ice": 0.0, "res_lightning": 0.0, "detect": 0.0}
	var base_hp := 100.0
	var base_mana := 40.0
	var base_st := 100.0
	if data:
		var c: Dictionary = DBSkills.CLASSES.get(data.class_id, {})
		base_hp = c.get("hp", 100) * 1.15 + (data.level - 1) * 14.0
		base_mana = c.get("mana", 40) + (data.level - 1) * 4.0
		base_st = c.get("stamina", 100)
		s.armor += c.get("armor", 0.0)
		s.crit += c.get("crit", 0.0)
		s.speed += c.get("speed", 0.0)
		s.spell += c.get("spell", 0.0)
		for it in data.inv.equip.values():
			for k in s:
				s[k] += ItemDB.stat(it, k)
			var cu: Dictionary = it.get("curse", {})
			if cu.size() > 0 and (cu.get("active", false) or not cu.get("bound", false)):
				match cu.id:
					"frail": s["frail"] = 1.0
					"clumsy": s.aspd -= 0.15
					"bloodlust": s["no_regen"] = 1.0
					"mana_burn": s["no_mana_regen"] = 1.0
					"drain": s["drain"] = 1.0
		if data.has_node("bw_eagle"):
			s.crit += 0.15
		if data.has_node("st_focus"):
			s.spell += 0.2
		var hy := data.hybrids()
		if "weapon_master" in hy:
			s.dmg_pct += 0.1 * data.weapon_categories_at(5)
		level = data.level
		if base_hp_override > 0.0:
			base_hp = base_hp_override
	else:
		base_hp = max_hp if stats.is_empty() else stats.get("base_hp", max_hp)
		s["base_hp"] = base_hp
	if data:
		_apply_passives(s)
	if is_player and Hardcore.active():
		Hardcore.inst.mods_into(s)      # Hardcore injuries: real stat penalties
	var ratio := hp / maxf(1.0, max_hp)
	max_hp = (base_hp + s.hp) * (0.8 if s.has("frail") else 1.0) * (1.0 - float(s.get("hc_hp", 0.0)))
	max_mana = (base_mana + s.mana) * (1.0 - float(s.get("hc_mana", 0.0)))
	max_stamina = base_st * (1.0 - float(s.get("hc_st", 0.0)))
	stats = s
	if hp > 0:
		hp = clampf(max_hp * ratio, 1.0, max_hp)
	mana = minf(mana, max_mana)
	if _mana_fresh and not is_player:
		mana = max_mana       # NPCs spawn with full mana (the default 50 was hidden by the old fast regen)
	stamina = minf(stamina, max_stamina)

## Learned passive class / weapon skills: stat mods and behaviour hooks.
## Weapon passives work only with their weapon category.
func _apply_passives(s: Dictionary) -> void:
	_hooks = {}
	var mc := mastery_cat()
	for id in data.passive_ids():
		var e: Dictionary = DBAbilities.get_ab(id)
		if e.is_empty() or e.type != "passive":
			continue
		if e.kind == "weapon" and e.cat != mc:
			continue
		for k in e.get("mods", {}):
			s[k] = float(s.get(k, 0.0)) + float(e.mods[k])
		for k in e.get("hooks", {}):
			_hooks[k] = float(_hooks.get(k, 0.0)) + float(e.hooks[k])

func stat(k: String) -> float:
	return float(stats.get(k, 0.0)) + float(_buff_mods.get(k, 0.0))

## Passive skill behaviour value (0 when the actor has no such skill).
func hook(k: String) -> float:
	return float(_hooks.get(k, 0.0))

## Category used by weapon mastery and skill trees: energy guns (firearms
## dealing energy damage) have their own tree; otherwise the item category.
func mastery_cat() -> String:
	var c := weapon_cat()
	if c == "firearm" and str(weapon_base().get("proj", "")) in ["pulse", "plasma", "spark"]:
		return "energy"
	return c

func _recalc_buffs() -> void:
	_buff_mods = {}
	for k in statuses:
		var md = statuses[k].get("mods")
		if md is Dictionary:
			for m in md:
				_buff_mods[m] = float(_buff_mods.get(m, 0.0)) + float(md[m])

func _no_knock() -> bool:
	for k in ["steadfast", "banner"]:
		if statuses.has(k) and statuses[k].get("no_knock", false):
			return true
	return false

func weapon() -> Dictionary:
	if data == null:
		return {}
	return data.inv.equipped("main")

func weapon_base() -> Dictionary:
	var w := weapon()
	return ItemDB.base(w.base) if not w.is_empty() else {}

func weapon_cat() -> String:
	return weapon_base().get("cat", "unarmed")

func weapon_range() -> float:
	var b := weapon_base()
	if b.is_empty():
		return natural_range
	var r: float = b.get("range", 2.0)
	if weapon_cat() == "spear" and data and data.has_node("sp_reach"):
		r *= 1.25
	if weapon_cat() == "bow" and data and data.has_node("bw_eagle"):
		r *= 1.2
	return r

func is_ranged() -> bool:
	return weapon_cat() in ["bow", "firearm", "staff"]

func mastery_lvl() -> int:
	return data.mastery_level(mastery_cat()) if data else level

func speed() -> float:
	if statuses.has("root"):
		return 0.0
	var sp := base_speed * (1.0 + stat("speed"))
	if statuses.has("exhausted"):
		sp *= 0.7
	if statuses.has("slow"):
		sp *= statuses.slow.get("f", 0.5)
	if statuses.has("haste"):
		sp *= 1.35
	if statuses.has("timeslow"):
		sp *= float(statuses.timeslow.get("f", 0.35))
	if blocking:
		sp *= 0.45
	if in_water and not statuses.has("on_ice"):
		sp *= 0.55
	if statuses.has("stealth"):
		sp *= 0.8
	return sp

func can_act() -> bool:
	return not is_dead and not statuses.has("stun") and not statuses.has("freeze") and not statuses.has("stasis")

func busy() -> bool:
	# an action stays busy until its impact: a paid spell whose release comes
	# late (long cast) must not be replaced by an attack and lost
	return not act.is_empty() and (act.t < act.dur * 0.75 or not act.get("done", false))

# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	if _lod_pre:
		_lod_pre = false
	elif _lod_skip(delta):
		return
	else:
		delta = _lod_dt
	if Perf.enabled:
		var t0 := Time.get_ticks_usec()
		_physics_step(delta)
		Perf.add("actor_phys", Time.get_ticks_usec() - t0)
	else:
		_physics_step(delta)

## Far actors (LOD tier 2) update every third physics tick with the summed
## time step; returns true when this tick is skipped. _lod_dt holds the step.
func _lod_skip(delta: float) -> bool:
	if lod_tier < 2 or is_player or is_dead:
		_lod_dt = delta
		_lod_n = 0
		_lod_sum = 0.0
		return false
	_lod_n += 1
	_lod_sum += delta
	if _lod_n < 3:
		return true
	_lod_dt = _lod_sum
	_lod_n = 0
	_lod_sum = 0.0
	return false

func _physics_step(delta: float) -> void:
	if is_dead:
		dead_t += delta
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= gravity * delta
			move_and_slide()
		if dead_t > _corpse_time():
			_remove_corpse()
		return
	if summon_time > 0.0:
		summon_time -= delta
		if summon_time <= 0.0:
			# a summon's time ran out: it leaves (no corpse, no kill credit)
			AbilityExec.despawn(self)
			return
	_tick_timers(delta)
	_tick_statuses(delta)
	_tick_action(delta)
	_move(delta)
	_grid_t += delta
	if _grid_t > 0.2:
		_grid_t = 0.0
		Game.grid.update(self, global_position, "actor")
	if rig:
		_update_rig(delta)

func _corpse_time() -> float:
	return 2.5 if is_player else 7.0

func _remove_corpse() -> void:
	queue_free()

func _tick_timers(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	combo_t = maxf(0.0, combo_t - delta)
	if combo_t <= 0.0:
		combo = 0
	dodge_cd = maxf(0.0, dodge_cd - delta)
	rewind_cd = maxf(0.0, rewind_cd - delta)
	combat_t += delta
	if blocking:
		block_t += delta
	for k in skill_cd.keys():
		skill_cd[k] -= delta
		if skill_cd[k] <= 0.0:
			skill_cd.erase(k)
	if mana_delay_t > 0.0:
		mana_delay_t = maxf(0.0, mana_delay_t - delta)
	if potion_mana_cd > 0.0:
		potion_mana_cd = maxf(0.0, potion_mana_cd - delta)
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			reload_t = 0.0
			Ammo.finish_reload(self)        # rounds move from the reserve only now
	if dodge_t > 0.0:
		dodge_t -= delta
		if dodge_t <= 0.0 and dodge_kind == "leap" and is_player:
			VFX.burst(global_position + Vector3(0, 0.1, 0), Color(0.62, 0.55, 0.42, 0.8), 5, 0.2)
	if has_meta("heat_ss"):
		LegendaryArts.tick(self, delta)
	if counter_t > 0.0:
		counter_t -= delta
	if _heat > 0.0:
		_heat = maxf(0.0, _heat - 25.0 * delta)
	if _overheat_t > 0.0:
		_overheat_t -= delta
	if _anti_charge_cd > 0.0:
		_anti_charge_cd -= delta
	_relentless_t -= delta
	if _relentless_t <= 0.0:
		_relentless = 0
	if data and not _hooks.is_empty():
		_passive_tick(delta)
	_regen_t += delta
	if _regen_t >= 0.5:
		_regen(_regen_t)
		_regen_t = 0.0
	# time echo queue (mythic)
	for i in range(_echo_queue.size() - 1, -1, -1):
		_echo_queue[i].t -= delta
		if _echo_queue[i].t <= 0.0:
			var e: Dictionary = _echo_queue[i]
			_echo_queue.remove_at(i)
			Combat.echo_strike(self, e)
	var now := Time.get_ticks_msec()
	for k in aggro.keys():
		if aggro[k] < now:
			aggro.erase(k)

## Periodic passive behaviours (stand still / run trackers, surrounded,
## forest cover, wounded-prey marks, quick halt).
func _passive_tick(delta: float) -> void:
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 1.2
	if moving:
		_run_t += delta
		_still_t = 0.0
	else:
		if _run_t > 1.2 and hook("quick_aim") > 0.0:
			apply_status("quick_aim", 1.5, {"mods": {"aspd": hook("quick_aim")}})
		_run_t = 0.0
		_still_t += delta
	_passive_t += delta
	if _passive_t < 0.5:
		return
	_passive_t = 0.0
	if hook("surrounded") > 0.0:
		var n := 0
		for a in Game.actors_near(global_position, 5.0):
			if a != self and not a.is_dead and Game.is_enemy(self, a):
				n += 1
		if n >= 3:
			apply_status("fortress", 0.8, {"mods": {"armor": 15.0, "taken_pct": -0.1}})
	if hook("forest") > 0.0 and Game.world and Game.world.has_method("biome_at"):
		var bm := str(Game.world.biome_at(global_position))
		if bm.contains("forest") or bm.contains("wood") or bm.contains("taiga"):
			apply_status("forest_cover", 0.8, {"mods": {"crit": 0.1, "speed": 0.05}})
	if hook("anti_charge") > 0.0 and _anti_charge_cd <= 0.0 and can_act():
		for a in Game.actors_near(global_position, 3.6):
			if a == self or a.is_dead or not Game.can_damage(self, a):
				continue
			var to_me: Vector3 = global_position - a.global_position
			to_me.y = 0
			var closing: float = Vector3(a.velocity.x, 0, a.velocity.z).dot(to_me.normalized())
			if closing > 5.0 or a.act.get("name", "") == "charge" or a.statuses.has("dashing"):
				_anti_charge_cd = 4.0
				face_dir(-to_me.normalized())
				if rig:
					rig.trigger("thrust")
				var inf := Combat.weapon_info(self, hook("anti_charge"))
				inf.status = {"stun": 1.0}
				inf.knock = 5.0
				Combat.deal(self, a, inf)
				VFX.text(chest() + Vector3(0, 0.4, 0), "Остановка натиска!", Color(1.0, 0.9, 0.55), 0.9)
				break
	if hook("instinct") > 0.0 and is_player:
		for a in Game.actors_near(global_position, 30.0):
			if a != self and not a.is_dead and Game.is_enemy(self, a) and a.hp < a.max_hp * 0.4:
				a.apply_status("tracked", 1.0)

func _regen(dt: float) -> void:
	var in_combat := combat_t < 5.0
	if not stats.has("no_regen") and not statuses.has("burn"):
		var r := (stat("regen") + (0.0 if in_combat else max_hp * 0.012)) * (1.0 - clampf(stat("hc_regen"), 0.0, 1.0))
		hp = minf(max_hp, hp + r * dt)
	if stats.has("drain") and not in_combat:
		hp = maxf(1.0, hp - max_hp * 0.01 * dt)
	# mana: slow, state-dependent regeneration with a pause after casts (ManaSys)
	var mr := ManaSys.regen_rate(self)
	if mr > 0.0 and mana < max_mana:
		var before := mana
		mana = minf(max_mana, mana + mr * dt)
		ManaSys.stats.regen += mana - before
	if not blocking:
		stamina = minf(max_stamina, stamina + 22.0 * dt * (1.0 - clampf(stat("hc_st_regen"), 0.0, 0.8)))

func _tick_statuses(delta: float) -> void:
	for k in statuses.keys():
		if is_dead or not statuses.has(k):
			continue
		var s: Dictionary = statuses[k]
		s.t -= delta
		if k == "burn":
			s["acc"] = s.get("acc", 0.0) + delta
			if s.acc >= 0.5:
				s.acc = 0.0
				var rain_f := 0.5 if (Game.world and Game.world.weather and Game.world.weather.is_raining()) else 1.0
				_apply_raw_damage(s.get("dps", 4.0) * 0.5 * rain_f, s.get("src"), "fire", true)
				if rain_f < 1.0:
					s.t -= 0.5
			if statuses.has("wet"):
				s.t = 0.0
		elif k == "regen_buff":
			hp = minf(max_hp, hp + s.get("hps", 5.0) * delta)
		if s.has("dot"):
			s["dacc"] = s.get("dacc", 0.0) + delta
			if s.dacc >= 0.5:
				s.dacc = 0.0
				_apply_raw_damage(float(s.dot) * 0.5, s.get("src"), str(s.get("dtype", "dark")), true)
		if s.has("hot"):
			hp = minf(max_hp, hp + float(s.hot) * delta)
		if s.t <= 0.0:
			statuses.erase(k)
			if k == "stealth" and rig:
				rig.crouch = false
			if s.has("mods"):
				_recalc_buffs()
			if s.has("after"):
				apply_status(str(s.after), 6.0, {"mods": {"aspd": -0.3}})

func move_style() -> Dictionary:
	if _mstyle.is_empty():
		_mstyle = CombatFeel.move_style(self)
	return _mstyle

func _move(delta: float) -> void:
	var ms := move_style()
	var v := Vector3.ZERO
	if dodge_t > 0.0:
		v = dodge_dir * (float(ms.dist) / maxf(0.05, dodge_total)) if dodge_kind != "blink" else Vector3.ZERO
		move_vel = v * 0.45
		if dodge_kind == "shadow":
			_ghost_t -= delta
			if _ghost_t <= 0.0 and rig:
				_ghost_t = 0.05
				MagicFX.ghost(self, Color(0.45, 0.3, 0.8, 0.55), 0.35)
	elif can_act():
		var mi := move_input
		mi.y = 0
		if mi.length() > 1.0:
			mi = mi.normalized()
		var spd := speed()
		if busy() and not is_ranged():
			spd *= 0.35
		var target := mi * spd
		var cur_len := move_vel.length()
		# hard reversal at speed: a short skid with dust (feels the body's weight)
		if ms.skid and _skid_t <= 0.0 and cur_len > spd * 0.6 and target.length() > 0.1 and move_vel.normalized().dot(target.normalized()) < -0.25:
			_skid_t = 0.16 + 0.1 * float(CombatFeel.weapon_feel(weapon_cat()).weight)
			if is_on_floor():
				VFX.burst(global_position + Vector3(0, 0.1, 0) + move_vel.normalized() * 0.3, Color(0.6, 0.52, 0.4, 0.8), 6, 0.22)
		var rate: float = ms.accel if target.length() > cur_len * 0.95 else ms.decel
		if _skid_t > 0.0:
			_skid_t -= delta
			target = Vector3.ZERO
			rate = float(ms.decel) * 1.7
		move_vel = move_vel.move_toward(target, rate * delta)
		v = move_vel
	else:
		move_vel = move_vel.move_toward(Vector3.ZERO, 30.0 * delta)
	if statuses.has("fear") and last_attacker and is_instance_valid(last_attacker):
		v = (global_position - last_attacker.global_position).normalized() * speed()
		v.y = 0
	v += knockback + lunge_vel
	knockback = knockback.move_toward(Vector3.ZERO, delta * 20.0)
	lunge_vel = lunge_vel.move_toward(Vector3.ZERO, delta * 60.0)
	velocity.x = v.x
	velocity.z = v.z
	if lod_tier >= 2 and not is_player and Game.world and Game.world.has_method("ground_height"):
		# far away: cheap kinematic step on the terrain, no collision solve
		global_position += Vector3(v.x, 0.0, v.z) * delta
		global_position.y = Game.world.ground_height(global_position)
		velocity.y = 0.0
	elif not is_player and v.length_squared() < 0.0004 and is_on_floor() and velocity.y <= 0.0:
		# standing still on the ground (villagers at work, guards on post): sleep
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		if is_on_floor():
			velocity.y = -0.5 if velocity.y <= 0.0 else velocity.y - gravity * delta
		else:
			velocity.y -= gravity * delta
		move_and_slide()
	# world bounds and fall-through guard
	if Game.world and Game.world.has_method("clamp_to_world"):
		Game.world.clamp_to_world(self)
	# facing: class turn rate
	var want := facing
	if act.is_empty() and v.length() > 0.5 and dodge_t <= 0.0 and not blocking:
		want = Vector3(v.x, 0, v.z).normalized()
		facing = facing.slerp(want, minf(1.0, delta * float(ms.turn))).normalized()
	if rig:
		var target_yaw := atan2(-facing.x, -facing.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, target_yaw, minf(1.0, delta * (float(ms.turn) + 4.0)))
		# lean into turns and accelerations (humanoids with a class style)
		if float(ms.lean) > 0.0 and delta > 0.0:
			var yaw_rate := wrapf(rig.rotation.y - _prev_yaw, -PI, PI) / delta
			# lean into the turn (positive yaw rate = turning left = lean left)
			_lean = lerpf(_lean, clampf(yaw_rate * float(ms.lean) * 0.08, -0.22, 0.22), minf(1.0, delta * 8.0))
			var want_pitch := 0.0
			if _skid_t > 0.0:
				want_pitch = 0.16          # braking: lean back
			elif move_input.length() > 0.2 and Vector2(move_vel.x, move_vel.z).length() < speed() * 0.6:
				want_pitch = -0.1          # pushing off into a run: lean forward
			_pitch = lerpf(_pitch, want_pitch, minf(1.0, delta * 9.0))
			rig.rotation.z = _lean
			rig.rotation.x = _pitch
		_prev_yaw = rig.rotation.y

func _update_rig(delta: float) -> void:
	var hv := Vector2(velocity.x, velocity.z).length()
	if rig is HumanoidRig and data != null:
		rig.handling = TechKnow.handling(self)
	rig.move_speed = hv / 5.0
	if rig is HumanoidRig and rig.gait == "" and (is_player or data != null):
		rig.gait = String(move_style().get("step", ""))
	rig.blocking = blocking
	rig.dodging = dodge_t > 0.0 and dodge_kind in ["roll", "leap"]
	if dodge_t > 0.0:
		rig.dodge_p = 1.0 - dodge_t / maxf(0.05, dodge_total)
	if not act.is_empty():
		rig.action_p = clampf(act.t / act.dur, 0.0, 1.0)
	elif reload_t > 0.0 and rig is HumanoidRig:
		rig.action = "reload"
		rig.action_p = clampf(1.0 - reload_t / maxf(0.1, reload_total), 0.0, 1.0)
	elif rig.action != "":
		rig.action = ""

# ---------------------------------------------------------------- actions
func face_dir(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		facing = d.normalized()

func start_action(nm: String, dur: float, impact: float, payload: Dictionary = {}) -> void:
	act = {"name": nm, "t": 0.0, "dur": maxf(0.05, dur), "impact": impact, "done": false, "data": payload}
	if nm == "skill" and not is_player and data == null:
		LegendaryArts.on_enemy_windup(self, nm)
	if rig:
		rig.trigger(payload.get("anim", nm))

func _tick_action(delta: float) -> void:
	if act.is_empty():
		return
	if not can_act():
		act = {}
		return
	var tscale: float = float(statuses.timeslow.get("f", 0.35)) if statuses.has("timeslow") else 1.0
	act.t += delta * tscale
	if not act.done and act.t >= act.dur * act.impact:
		act.done = true
		_on_impact(act)
		if act.is_empty():
			return
	if act.t >= act.dur:
		var fin := act
		act = {}
		_on_action_end(fin)

func _on_action_end(_a: Dictionary) -> void:
	pass

func attack_interval() -> float:
	var spd: float = weapon_base().get("spd", 1.3) if data else 1.0
	if data and TechKnow.item_family(weapon()) != "":
		spd /= float(TechKnow.mods(self).interval)     # an unsure hand prepares the weapon slower
	spd *= 1.0 + stat("aspd")
	if weapon_cat() == "firearm" and data and data.has_node("fa_recoil"):
		spd *= 1.2
	if statuses.has("timeslow"):
		spd *= 0.4
	return 1.0 / maxf(0.2, spd)

## Primary attack toward aim (xz direction). Returns true if an attack started.
func attack(aim: Vector3 = Vector3.ZERO) -> bool:
	# the end of a dodge can flow straight into an attack
	if dodge_t > 0.0 and dodge_t < dodge_total * 0.35 and attack_cd <= 0.0:
		dodge_t = 0.0
	if not can_act() or attack_cd > 0.0 or busy() or dodge_t > 0.0:
		return false
	if aim.length() > 0.01:
		face_dir(aim)
	combat_t = 0.0
	if blocking:
		set_block(false)
	var cat := weapon_cat()
	var interval := attack_interval()
	attack_cd = interval
	if statuses.has("stealth") and cat != "dagger" and not (cat == "bow" and hook("silent_shot") > 0.0):
		statuses.erase("stealth")
	if _overheat_t > 0.0 and mastery_cat() == "energy":
		attack_cd = 0.1
		return false
	if data and not TechKnow.can_fire(self):
		_unknown_weapon()
		return false
	match cat:
		"bow":
			if not Ammo.can_fire(self):
				_dry_fire()
				return false
			start_action("shoot", interval * 0.85, 0.55, {"anim": "shoot"})
			Audio.play_sfx("bow_draw", global_position, -8.0)
		"firearm":
			if reload_t > 0.0:
				if ammo > 0:
					Ammo.cancel_reload(self)    # fire what is left: the reload stops, nothing moves
				else:
					attack_cd = 0.1
					return false
			if not Ammo.can_fire(self, Ammo.shot_cost(self)):
				_dry_fire()
				return false
			if Ammo.boost_on(self):
				attack_cd = interval * 2.2     # a boosted shot charges longer
			start_action("shoot", minf(0.25, interval * 0.8), 0.05, {"anim": "shoot"})
		"staff":
			# the staff's basic bolt is free: mana is for real spells (see ManaSys)
			start_action("cast_bolt", minf(0.55, interval * 0.9), 0.45, {"anim": "cast"})
		_:
			var chain := _combo_chain(cat)
			var idx := combo % chain.size()
			var mult = [1.0, 1.1, 1.3, 1.6][mini(idx, 3)]
			var anim: String = chain[idx]
			var fin := idx == chain.size() - 1
			var counter := counter_t > 0.0
			var wf := CombatFeel.weapon_feel(cat)
			# heavier weapons swing slower, light blades faster
			var dur := clampf(interval * 0.95 * lerpf(0.85, 1.2, float(wf.weight)), 0.26, 0.85)
			if anim == "spin":
				dur = 0.6
			if fin:
				dur *= 1.12
			start_action("melee", dur, 0.42, {"anim": anim, "mult": mult * (1.6 if counter else 1.0), "combo": idx, "finisher": fin, "counter": counter})
			combo += 1
			combo_t = interval + 0.6
			# step in toward the target (magnetised lunge), longer for counters and finishers
			var tgt = counter_target if counter and counter_target != null and is_instance_valid(counter_target) else _melee_target(weapon_range() + float(wf.lunge) + 1.0)
			if tgt != null:
				var to: Vector3 = tgt.global_position - global_position
				to.y = 0
				var gap := to.length() - weapon_range() * 0.7
				if gap > 0.1:
					var step := minf(gap, float(wf.lunge) * (1.8 if counter else (1.3 if fin else 1.0)))
					lunge_vel = to.normalized() * sqrt(2.0 * 60.0 * step)
				face_dir(to)
			if counter:
				counter_t = 0.0
				VFX.text(chest() + Vector3(0, 0.6, 0), "Контратака!", Color(1.0, 0.85, 0.4))
				if is_player:
					CombatFeel.speed_lines(0.25, 1.0)
			Audio.play_sfx("swing_heavy" if cat == "heavy" or fin else "swing", global_position, -4.0 if not fin else -1.0)
	return true

## Nearest enemy in front within r (for the attack step-in).
func _melee_target(r: float):
	var best = null
	var bd := INF
	for a in Game.actors_near(global_position, r):
		if a == self or a.is_dead or not Game.is_enemy(self, a):
			continue
		var to: Vector3 = a.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > 0.1 and facing.angle_to(to / d) > deg_to_rad(70.0):
			continue
		if d < bd:
			bd = d
			best = a
	return best

func _combo_chain(cat: String) -> Array:
	match cat:
		"sword":
			return ["slash", "slash2", "thrust", "spin"] if (data and data.has_node("sw_combo")) else ["slash", "slash2", "thrust"]
		"dagger":
			return ["stab", "slash", "stab", "slash2"]
		"spear":
			return ["thrust", "thrust", "slash"]
		"heavy":
			return ["overhead", "slash", "slam"]
	return ["stab", "slash"]

func _on_impact(a: Dictionary) -> void:
	match a.name:
		"melee":
			var p: Dictionary = a.data
			var anim: String = p.get("anim", "slash")
			if is_player and TechKnow.item_family(weapon()) != "":
				TechKnow.practice(self, 1.0)
			var arc := 110.0
			if anim in ["thrust", "stab"]:
				arc = 50.0
			elif anim == "spin" or anim == "slam":
				arc = 360.0
			var r := weapon_range() if data else natural_range
			var info := Combat.weapon_info(self, p.get("mult", 1.0))
			if p.get("combo", 0) == 2 and weapon_cat() == "heavy" and data and data.has_node("hv_combo"):
				info.status = {"stun": 1.0}
			if anim == "spin" or anim == "slam":
				r *= 1.1
			var wf := CombatFeel.weapon_feel(weapon_cat())
			var fin: bool = p.get("finisher", false)
			info.knock = maxf(float(info.get("knock", 0.0)), float(wf.fin_knock) if fin else float(wf.knock))
			if fin:
				info.finisher = true
				info.launch = float(wf.launch)
				r *= 1.15
				arc = maxf(arc, 140.0)
			if p.get("counter", false):
				info.crit_force = true
			if Clash.try_clash(self, r):
				return
			var hits := Combat.melee(self, r, arc, info)
			if hits.size() > 0:
				Audio.play_sfx("hit_metal" if hits[0].get("metal_hit", false) else "hit_flesh", global_position, -2.0)
			if fin and is_player:
				_finisher_fx(r, hits.size() > 0)
		"shoot":
			# the round is spent only by a shot that is really fired
			if Ammo.consume(self, Ammo.shot_cost(self)):
				Combat.fire_weapon(self)
				TechKnow.practice(self, 1.0)        # experience of handling: only real shots count
				if Ammo.has_mag(weapon_base()) and ammo <= 0 and (not is_player or (Settings.auto_reload and Ammo.reserve(self) > 0)):
					reload()
			else:
				_dry_fire()
		"cast_bolt":
			Combat.staff_bolt(self)
		"skill", "spell":
			var cb: Callable = a.data.get("cb", Callable())
			if cb.is_valid():
				cb.call()

## Visual/physical accent of the last hit of a combo.
func _finisher_fx(r: float, landed: bool) -> void:
	var wf := CombatFeel.weapon_feel(weapon_cat())
	var heavy: bool = float(wf.weight) >= 0.9
	var c := Color(1.0, 0.85, 0.55) if not heavy else Color(1.0, 0.6, 0.3)
	VFX.slash(global_position + Vector3(0, 1.0, 0), facing, r * 1.25, 150.0, "slash", c)
	if heavy:
		VFX.ground_impact(global_position + facing * 1.4, 2.6)
		VFX.decal(global_position + facing * 1.4, "crack", 2.4, 14.0, randf() * TAU)
		VFX.shock(global_position + facing * 1.2, 3.6, c, 0.35)
		Audio.play_sfx("impact_heavy", global_position, -1.0)
		Audio.play_sfx("ground_crack", global_position, -6.0)
	else:
		VFX.shock(global_position + facing * 0.8, 2.2, c, 0.25)
		Audio.play_sfx("slash_air", global_position, -3.0)
	if landed:
		CombatFeel.punch(0.08, 0.22)

func reload() -> String:
	var why := Ammo.start_reload(self)
	if why == "":
		reload_total = maxf(0.1, reload_t)
	elif is_player and why != "магазин полон" and why != "уже перезаряжается":
		Events.notify.emit("Перезарядка невозможна: " + why, Color(1.0, 0.6, 0.4))
	return why

## Trigger pulled with nothing to fire: a dry click and a clear reason.
## The weapon in hand is an unknown technology: no shot, an unsure look at it.
func _unknown_weapon() -> void:
	attack_cd = 0.9
	TechKnow.stats.refused += 1
	if not is_player:
		return
	start_action("inspect", 1.1, 0.99, {"anim": "inspect"})
	Audio.play_sfx("ui_click", global_position, -8.0)
	var st := TechKnow.weapon_stage(self)
	Events.notify.emit("Вы не знаете, как пользоваться этим оружием" + (" — изучите его: Инвентарь → Изучить" if st <= 2 else ""), Color(1.0, 0.75, 0.4))

func _dry_fire() -> void:
	Ammo.stats.dry_clicks += 1
	if is_player:
		Ammo.flash_ms = Time.get_ticks_msec()
	attack_cd = 0.35
	var b := weapon_base()
	if not is_player:
		if Ammo.has_mag(b):
			reload()
		return
	Audio.play_sfx("ui_click", global_position, -6.0)
	if Ammo.boost_on(self) and ammo > 0 and (Ammo.reserve(self) <= 0 or not Settings.auto_reload):
		Events.notify.emit("Мало заряда для усиленного выстрела (нужно %d) — переключите режим или перезарядитесь" % Ammo.BOOST_COST, Color(1.0, 0.75, 0.4))
		return
	if Ammo.has_mag(b) and Ammo.reserve(self) > 0:
		if Settings.auto_reload:
			reload()
		else:
			Events.notify.emit("Магазин пуст — нажмите «Перезарядка»", Color(1.0, 0.75, 0.4))
	else:
		Events.notify.emit("Нет боеприпасов: %s" % Ammo.base(Ammo.kind_of(weapon())).get("name", "боеприпасы"), Color(1.0, 0.5, 0.4))

func set_block(on: bool) -> void:
	if on and (not can_act() or stamina < 5.0 or dodge_t > 0.0):
		return
	if on and not blocking:
		block_t = 0.0
	blocking = on

func block_value() -> float:
	var off: Dictionary = data.inv.equipped("off") if data else {}
	var v := 0.35
	if not off.is_empty():
		v = maxf(v, ItemDB.stat(off, "block") if ItemDB.stat(off, "block") > 0 else 0.35)
	return clampf(v + stat("block") * 0.0, 0.0, 0.9)

func parry_window() -> float:
	var w := 0.22
	if data and data.has_node("sw_parry"):
		w += 0.15
	return w + hook("parry_window")

func dodge(dir: Vector3) -> bool:
	if not can_act() or stamina < 18.0:
		return false
	if reload_t > 0.0 and dodge_cd <= 0.0:
		Ammo.cancel_reload(self, "уклонение")
	if dodge_cd > 0.0:
		# «Цепочка теней»: extra dashes right after a dash
		if hook("dodge_chain") > 0.0 and _dodge_chain < int(hook("dodge_chain")) and Time.get_ticks_msec() - _last_dodge_ms < 1200 and stamina >= 33.0 and dodge_t <= 0.0:
			_dodge_chain += 1
			stamina -= 15.0
			dodge_cd = 0.0
		else:
			return false
	else:
		_dodge_chain = 0
	dir.y = 0
	if dir.length() < 0.1:
		dir = facing
	dodge_dir = dir.normalized()
	face_dir(dodge_dir)
	var ms := move_style()
	dodge_kind = String(ms.dodge)
	dodge_total = float(ms.dur)
	var cd := 0.9 if dodge_kind != "blink" else 1.1
	if data and data.has_node("dg_evasion"):
		cd *= 0.6
		dodge_total *= 1.1
	if hook("dodge_master") > 0.0:
		cd *= 1.0 - hook("dodge_master")
		dodge_total *= 1.12
	if statuses.has("storm_wings"):
		cd *= 1.0 - float(statuses.storm_wings.get("dodge_cd", 0.4))
	_last_dodge_ms = Time.get_ticks_msec()
	if hook("falcon") > 0.0:
		apply_status("falcon", 2.0, {"mods": {"aspd": hook("falcon")}})
	if hook("dodge_strike") > 0.0:
		apply_status("dodge_strike", 1.2)
	dodge_t = dodge_total
	dodge_cd = cd
	stamina -= 18.0
	act = {}
	blocking = false
	move_vel = Vector3.ZERO
	match dodge_kind:
		"blink":
			# short teleport, stops before walls
			var from := global_position
			var dist := float(ms.dist)
			if is_inside_tree():
				var q := PhysicsRayQueryParameters3D.create(chest(), chest() + dodge_dir * dist, 1)
				q.exclude = [get_rid()]
				var hit := get_world_3d().direct_space_state.intersect_ray(q)
				if not hit.is_empty():
					dist = maxf(0.0, (hit.position - chest()).length() - 0.6)
			MagicFX.blink_out(self, "time")
			global_position = from + dodge_dir * dist
			if Game.world and Game.world.has_method("ground_height"):
				global_position.y = maxf(global_position.y, Game.world.ground_height(global_position))
			if has_method("reset_physics_interpolation"):
				reset_physics_interpolation()
			MagicFX.blink_in(self, from, "time")
			Audio.play_sfx("teleport", global_position, -4.0)
		"shadow":
			_ghost_t = 0.0
			Audio.play_sfx("dash_whoosh", global_position, -2.0)
			if is_player:
				CombatFeel.speed_lines(0.28, 0.9)
		"leap":
			Audio.play_sfx("dash_whoosh", global_position, -5.0)
			if is_player:
				CombatFeel.speed_lines(0.22, 0.6)
		_:
			Audio.play_sfx("dodge", global_position, -6.0)
			VFX.burst(global_position + Vector3(0, 0.1, 0), Color(0.62, 0.55, 0.42, 0.8), 5, 0.22)
	if data and "shadow_dancer" in data.hybrids():
		Spells.shadow_clone_burst(self, global_position)
	return true

func invulnerable() -> bool:
	if statuses.has("invuln"):
		return true
	if dodge_t <= 0.0:
		return false
	var p := 1.0 - dodge_t / maxf(0.05, dodge_total)
	return p < 0.88       # i-frames start immediately (forgiving on touch screens)

## Use the skill in slot i (0..2) of the current weapon category.
func use_slot(i: int, aim: Vector3 = Vector3.ZERO) -> bool:
	if data == null or not can_act():
		return false
	var s: Array = data.active_slots(mastery_cat())
	if i >= s.size() or s[i] == "":
		return false
	return use_ability(s[i], aim)

func use_ability(id: String, aim: Vector3 = Vector3.ZERO) -> bool:
	if not can_act() or skill_cd.has(id) or busy():
		return false
	if aim.length() > 0.01:
		face_dir(aim)
	combat_t = 0.0
	var ok := false
	if statuses.has("silenced"):
		if is_player:
			Events.notify.emit("Безмолвие: умения недоступны", Color(0.7, 0.5, 1.0))
		return false
	if id.begins_with("art_"):
		ok = LegendaryArts.use(self, id, aim)
	elif DBAbilities.has(id):
		ok = AbilityExec.use(self, id, aim)
	elif DBSkills.is_spell(id):
		ok = Spells.cast(self, id, aim)
	else:
		ok = Skills.use(self, id, aim)
	return ok

func cooldown_of(id: String) -> float:
	return skill_cd.get(id, 0.0)

# ---------------------------------------------------------------- damage
func add_aggro(other, secs: float = 25.0) -> void:
	if other == null or not is_instance_valid(other) or other == self:
		return
	aggro[other.actor_id] = Time.get_ticks_msec() + int(secs * 1000.0)

func apply_status(id: String, dur: float, params: Dictionary = {}) -> void:
	if is_dead:
		return
	if id in ["stun", "freeze"] and statuses.has("unstoppable"):
		return
	if kind == "boss" and id in ["stun", "freeze", "fear", "stasis"]:
		dur *= 0.35
	if id == "silenced" and kind == "boss":
		return          # bosses are never fully silenced (spells only slow them)
	if kind == "boss" and id in ["timeslow", "stasis"] and get("def") is Dictionary and get("def").get("time_immune", false):
		VFX.text(chest(), "Неподвластен времени", Color(0.5, 1.0, 0.9), 0.8)
		return
	# a mage holding a spell: high-focus casts are not broken, a steady focus often holds
	if id == "stun" and not act.is_empty() and act.name == "spell":
		if act.data.get("steady", false):
			return
		if hook("cast_steady") > 0.0 and randf() < hook("cast_steady"):
			VFX.text(chest(), "Концентрация", Color(0.7, 0.8, 1.0), 0.8)
			return
	if id in ["stun", "freeze", "knockdown", "stasis", "fear"] and reload_t > 0.0:
		Ammo.cancel_reload(self, "оглушение")
	var s := params.duplicate()
	s.t = maxf(dur, statuses.get(id, {}).get("t", 0.0))
	var had_mods: bool = statuses.has(id) and statuses[id].has("mods")
	statuses[id] = s
	if s.has("mods") or had_mods:
		_recalc_buffs()
	if id == "freeze" and statuses.has("burn"):
		statuses.erase("burn")
	if id == "burn" and statuses.has("freeze"):
		statuses.erase("freeze")

## Main damage intake. info: {amount, dtype, src, melee, crit, knock, status{}, proj}
func take_damage(info: Dictionary) -> float:
	if is_dead:
		return 0.0
	var src = info.get("src")
	if invulnerable():
		VFX.text(chest(), "Уклонение", Color(0.8, 0.8, 1.0))
		if dodge_t > 0.0 and data != null:
			LegendaryArts.on_dodge(self, src)
			if hook("retribution") > 0.0:
				apply_status("retribution", 3.0)
			if hook("last_blade") > 0.0:
				apply_status("last_blade", 2.5)
		return 0.0
	# deflection (staff spin, air shield, wind throne): projectiles bounce off
	if statuses.has("deflect") and info.get("proj", "") != "":
		var dfl: Dictionary = statuses.deflect
		var weak_cap: float = float(dfl.get("weak", 0.0))
		if dfl.get("all", false) or (weak_cap > 0.0 and info.get("school", "") == "" and float(info.get("amount", 0.0)) <= weak_cap * (1.0 + 0.05 * level)):
			VFX.text(chest(), "Отражено", Color(0.85, 1.0, 1.0))
			VFX.burst(chest(), Color(0.85, 1.0, 1.0), 8, 0.2)
			return 0.0
	var amount: float = info.get("amount", 0.0)
	var from_dir := Vector3.ZERO
	if src and is_instance_valid(src):
		from_dir = (src.global_position - global_position)
		from_dir.y = 0
		from_dir = from_dir.normalized()
		add_aggro(src)
		last_attacker = src
	# mythic auto-parry
	var w := weapon()
	if info.get("melee", false) and w.get("mythic", "") == "auto_parry" and randf() < 0.3:
		_parry(src)
		return 0.0
	# block / parry
	if blocking and from_dir.length() > 0.1 and facing.dot(from_dir) > 0.25:
		if info.get("melee", false) and block_t <= parry_window():
			_parry(src, info)
			return 0.0
		var bv := block_value()
		if data != null:
			LegendaryArts.on_block(self, amount * bv)
		amount *= 1.0 - bv
		var st_cost: float = 10.0 + info.get("amount", 0.0) * 0.15
		if hook("low_hp_block") > 0.0 and hp < max_hp * 0.35:
			st_cost *= 1.0 - hook("low_hp_block")
		if src and is_instance_valid(src) and src.has_method("hook"):
			st_cost += src.hook("guard_break")
			if src.hook("anti_armor") > 0.0 and src.weapon_cat() == "heavy":
				st_cost *= 2.0
		stamina -= st_cost
		if hook("block_counter") > 0.0:
			apply_status("counter_ready", 2.5)
		if hook("block_stamina") > 0.0:
			stamina = minf(max_stamina, stamina + hook("block_stamina"))
		if stamina <= 0.0:
			stamina = 0.0
			blocking = false
			apply_status("stun", 0.6)
		Audio.play_sfx("block", global_position, -3.0)
		VFX.block_fx(chest() + from_dir * 0.5, -from_dir)
	if statuses.has("unstoppable"):
		amount *= 0.6
	# shield
	if shield_hp > 0.0:
		var absorbed := minf(shield_hp, amount * (1.0 - float(info.get("shield_pen", 0.0))))
		shield_hp -= absorbed
		amount -= absorbed
		if shield_hp <= 0.0:
			statuses.erase("magic_shield")
	var dealt := _apply_raw_damage(amount, src, info.get("dtype", "slash"), false, info)
	if is_player and dealt > 0.0 and Hardcore.active():
		Hardcore.inst.on_hit(self, dealt, info, src, from_dir)
	# thorns
	if info.get("melee", false) and src and is_instance_valid(src) and _has_ability("thorns"):
		src._apply_raw_damage(dealt * 0.25, self, "pierce", true)
	if dealt > 0.0 and not is_dead:
		var kb: float = info.get("knock", 0.0)
		if kb > 0.0 and from_dir.length() > 0.1 and kind != "boss" and not _no_knock():
			# heavier bodies (big scale) are pushed less
			knockback = -from_dir * kb / maxf(1.0, _scale())
		# finishers stagger and can briefly launch lighter foes off their feet
		if info.get("finisher", false) and kind != "boss" and not statuses.has("unstoppable"):
			act = {}
			apply_status("stun", 0.35)
			var la: float = info.get("launch", 0.0)
			if la > 0.0 and _scale() <= 1.3 and is_on_floor() and not _no_knock():
				velocity.y = la
		for st in info.get("status", {}):
			var sv = info.status[st]
			if st == "burn":
				apply_status("burn", 4.0, {"dps": float(sv), "src": src})
			elif st == "slow":
				apply_status("slow", 2.5, {"f": float(sv)})
			elif st in ["bleed", "decay"]:
				apply_status(st, 5.0, {"dot": float(sv), "dtype": "slash" if st == "bleed" else "dark", "src": src})
			elif st == "weakness":
				apply_status("weakness", float(sv), {"mods": {"dmg_pct": -0.25}})
			elif st == "suppressed":
				apply_status("suppressed", float(sv), {"mods": {"dmg_pct": -0.2, "speed": -0.35}})
			else:
				apply_status(st, float(sv))
		var heavy_hit: bool = dealt > max_hp * 0.18 or info.get("crit", false) or info.get("knock", 0.0) >= 5.0
		VFX.hit_fx(chest() + from_dir * radius(), -from_dir, info.get("dtype", "slash"), heavy_hit, DBActors.eget(def_id, {}).get("metal", false) or stat("armor") > 20.0)
		if rig and (kind != "boss" or dealt > max_hp * 0.03):
			rig.on_hit(-from_dir, heavy_hit)
			if act.get("name", "") == "melee" and dealt > max_hp * 0.12 and kind == "humanoid" and not statuses.has("unstoppable"):
				act = {}
	return dealt

func _parry(src, info: Dictionary = {}) -> void:
	if info.get("heavy", false) and src and is_instance_valid(src) and src is Actor and src.kind == "boss":
		Clash.boss_perfect_parry(self, src)
		block_t = 999.0
		return
	Audio.play_sfx("parry", global_position, 0.0)
	VFX.parry_fx(chest() + facing * 0.6, facing)
	VFX.text(chest() + Vector3(0, 0.5, 0), "Парирование!", Color(1.0, 0.95, 0.5))
	if src and is_instance_valid(src) and src is Actor:
		var st := 1.0
		if data and data.has_node("sw_parry"):
			st = 1.6
		src.apply_status("stun", st)
		src.act = {}
	if data and data.has_node("sw_riposte"):
		riposte = true
	if data != null:
		LegendaryArts.on_parry(self, src)
	# «Перехват клинка»: an instant counter-strike after a parry
	if hook("parry_counter") > 0.0 and src and is_instance_valid(src) and src is Actor:
		var mult := hook("parry_counter")
		get_tree().create_timer(0.12, false).timeout.connect(func():
			if is_instance_valid(self) and not is_dead:
				if rig:
					rig.trigger("thrust")
				Combat.melee(self, weapon_range() + 0.3, 90.0, Combat.weapon_info(self, mult)))
	if is_player:
		CombatFeel.parry_moment(self, src)
	block_t = 999.0

func _apply_raw_damage(amount: float, src, dtype: String, quiet: bool = false, info: Dictionary = {}) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	amount = maxf(1.0, amount)
	# chrono rewind (mythic): survive a lethal blow once per minute
	if amount >= hp and rewind_cd <= 0.0 and weapon().get("mythic", "") == "chrono_rewind":
		rewind_cd = 60.0
		hp = max_hp * 0.5
		VFX.ring(global_position, 3.0, Color(0.4, 1.0, 0.9), 0.6)
		VFX.text(chest(), "Откат времени!", Color(0.4, 1.0, 0.9))
		Audio.play_sfx("time_slow", global_position)
		return 0.0
	# sanctioned sparring (tournaments, training bouts): nobody gets killed
	if has_meta("spar") and src != null and is_instance_valid(src) and src.has_meta("spar") and src.get_meta("spar") == get_meta("spar"):
		amount = minf(amount, maxf(0.0, hp - max_hp * 0.3))
	hp -= amount
	combat_t = 0.0
	if src and is_instance_valid(src):
		damage_log[src.actor_id] = damage_log.get(src.actor_id, 0.0) + amount
		src.combat_t = 0.0
	if not quiet or amount >= 3.0:
		var col := Color(1, 1, 1)
		if is_player:
			col = Color(1.0, 0.35, 0.3)
		elif info.get("crit", false):
			col = Color(1.0, 0.85, 0.2)
		elif dtype in ["fire"]:
			col = Color(1.0, 0.55, 0.2)
		elif dtype in ["ice"]:
			col = Color(0.6, 0.9, 1.0)
		elif dtype in ["lightning", "energy"]:
			col = Color(0.75, 0.8, 1.0)
		elif dtype in ["dark", "time"]:
			col = Color(0.8, 0.5, 1.0)
		VFX.text(chest() + Vector3(randf_range(-0.3, 0.3), 0.4, 0), ("%d" % roundi(amount)) + ("!" if info.get("crit", false) else ""), col, 1.4 if info.get("crit", false) else 1.0)
	Events.actor_damaged.emit(self, amount, src, dtype)
	if hp <= 0.0:
		hp = 0.0
		die(src)
	return amount

func heal(amount: float) -> void:
	if is_dead:
		return
	hp = minf(max_hp, hp + amount)

func _has_ability(ab: String) -> bool:
	if data == null:
		return false
	for it in data.inv.equip.values():
		if it.get("ability", "") == ab and (not is_player or TechKnow.special_ok(self, it)):
			return true
	return false

func die(killer) -> void:
	if is_dead:
		return
	is_dead = true
	hp = 0.0
	act = {}
	blocking = false
	# «Печать души»: the sealer drinks back a quarter of its mana
	var seal: Dictionary = statuses.get("soul_seal", {})
	var sealer = seal.get("caster")
	if sealer != null and is_instance_valid(sealer) and not sealer.is_dead:
		sealer.mana = minf(sealer.max_mana, sealer.mana + sealer.max_mana * 0.25)
		VFX.beam(chest(), sealer.chest(), Color(0.45, 0.9, 0.6), 0.4, 0.1)
	statuses.clear()
	if rig:
		rig.dead = true
	collision_layer = 0
	AbilityExec.note_death(global_position)
	Audio.play_sfx("death_monster" if kind == "creature" else "death", global_position, -2.0)
	# credit the top damage dealer if the killing blow was environmental
	if killer == null or not is_instance_valid(killer):
		var best := 0.0
		for a in Game.actors_near(global_position, 40.0):
			if damage_log.get(a.actor_id, 0.0) > best and a != self:
				best = damage_log[a.actor_id]
				killer = a
	Combat.on_kill(killer, self)
	_on_death(killer)
	died.emit(self, killer)
	Events.actor_killed.emit(self, killer)

func _on_death(_killer) -> void:
	pass

## Experience reward for killing this actor.
func xp_value() -> int:
	var v := 0
	if data:
		v = 30 + data.level * 15 + int(data.xp * 0.25)
	else:
		v = 16 + level * 9
	if elite:
		v *= 2
	return v

func gain_xp(n: int) -> void:
	if data == null or n <= 0:
		return
	var lv := data.add_xp(n)
	if lv > 0:
		recalc_stats()
		hp = max_hp
		mana = max_mana
		Events.level_up.emit(self, data.level)
		VFX.ring(global_position, 2.5, Color(1.0, 0.85, 0.3), 0.8)
		if is_player:
			Audio.play_sfx("level_up")

func gain_mastery(cat: String, n: float) -> void:
	if data == null:
		return
	var lv := data.add_mastery_xp(cat, n)
	if lv > 0:
		Events.mastery_up.emit(self, cat, data.mastery_level(cat))
		if not is_player:
			data.auto_learn()
			data.auto_slots(cat)
