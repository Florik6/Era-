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
var ammo := 0
var reload_t := 0.0
var blocking := false
var block_t := 0.0
var dodge_t := 0.0
var dodge_cd := 0.0
var dodge_dir := Vector3.ZERO
var dodge_total := 0.45
var dodge_kind := "roll"
var move_vel := Vector3.ZERO      # planar velocity with inertia
var lunge_vel := Vector3.ZERO     # attack step-in impulse
var _aggro_t := 2.0
var counter_t := 0.0              # window after a parry: next attack is a counter
var counter_target = null
var _skid_t := 0.0
var _ghost_t := 0.0
var _mstyle: Dictionary = {}
var _lean := 0.0
var _pitch := 0.0
var _prev_yaw := 0.0
var lod_tier := 0              # 0 near, 1 mid, 2 far (set by PerfLOD)
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
	var ratio := hp / maxf(1.0, max_hp)
	max_hp = (base_hp + s.hp) * (0.8 if s.has("frail") else 1.0)
	max_mana = base_mana + s.mana
	max_stamina = base_st
	stats = s
	if hp > 0:
		hp = clampf(max_hp * ratio, 1.0, max_hp)
	mana = minf(mana, max_mana)
	var w := weapon()
	if not w.is_empty():
		var b := ItemDB.base(w.base)
		if b.has("mag") and ammo <= 0 and reload_t <= 0.0:
			ammo = b.mag

func stat(k: String) -> float:
	return float(stats.get(k, 0.0))

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
	return data.mastery_level(weapon_cat()) if data else level

func speed() -> float:
	var sp := base_speed * (1.0 + stat("speed"))
	if statuses.has("slow"):
		sp *= statuses.slow.get("f", 0.5)
	if statuses.has("haste"):
		sp *= 1.35
	if statuses.has("timeslow"):
		sp *= 0.35
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
	return not act.is_empty() and act.t < act.dur * 0.75

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
			die(null)
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
	if reload_t > 0.0:
		reload_t -= delta
		if reload_t <= 0.0:
			ammo = weapon_base().get("mag", 1)
	if dodge_t > 0.0:
		dodge_t -= delta
		if dodge_t <= 0.0 and dodge_kind == "leap" and is_player:
			VFX.burst(global_position + Vector3(0, 0.1, 0), Color(0.62, 0.55, 0.42, 0.8), 5, 0.2)
	_aggro_t -= delta
	if _aggro_t <= 0.0:
		_aggro_t = 2.0
		_purge_aggro()
	if counter_t > 0.0:
		counter_t -= delta
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

func _regen(dt: float) -> void:
	var in_combat := combat_t < 5.0
	if not stats.has("no_regen") and not statuses.has("burn"):
		var r := stat("regen") + (0.0 if in_combat else max_hp * 0.012)
		hp = minf(max_hp, hp + r * dt)
	if stats.has("drain") and not in_combat:
		hp = maxf(1.0, hp - max_hp * 0.01 * dt)
	var mr := max_mana * (0.025 if in_combat else 0.05)
	if data and data.has_node("st_flow"):
		mr *= 1.6
	if stats.has("no_mana_regen") and not in_combat:
		mr = 0.0
	if Game.world and Game.world.get("director") and Game.world.director != null:
		mr *= Game.world.director.mods.get("mana_regen", 1.0)
	mana = minf(max_mana, mana + mr * dt)
	if not blocking:
		stamina = minf(max_stamina, stamina + 22.0 * dt)

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
		if s.t <= 0.0:
			statuses.erase(k)
			if k == "stealth" and rig:
				rig.crouch = false

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
	rig.move_speed = hv / 5.0
	if rig is HumanoidRig and rig.gait == "" and (is_player or data != null):
		rig.gait = String(move_style().get("step", ""))
	rig.blocking = blocking
	rig.dodging = dodge_t > 0.0 and dodge_kind in ["roll", "leap"]
	if dodge_t > 0.0:
		rig.dodge_p = 1.0 - dodge_t / maxf(0.05, dodge_total)
	if not act.is_empty():
		rig.action_p = clampf(act.t / act.dur, 0.0, 1.0)
	elif rig.action != "":
		rig.action = ""

# ---------------------------------------------------------------- actions
func face_dir(d: Vector3) -> void:
	d.y = 0
	if d.length() > 0.01:
		facing = d.normalized()

func start_action(nm: String, dur: float, impact: float, payload: Dictionary = {}) -> void:
	act = {"name": nm, "t": 0.0, "dur": maxf(0.05, dur), "impact": impact, "done": false, "data": payload}
	if rig:
		rig.trigger(payload.get("anim", nm))

func _tick_action(delta: float) -> void:
	if act.is_empty():
		return
	if not can_act():
		act = {}
		return
	var tscale := 0.35 if statuses.has("timeslow") else 1.0
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
	if statuses.has("stealth") and cat != "dagger":
		statuses.erase("stealth")
	match cat:
		"bow":
			start_action("shoot", interval * 0.85, 0.55, {"anim": "shoot"})
			Audio.play_sfx("bow_draw", global_position, -8.0)
		"firearm":
			if reload_t > 0.0:
				attack_cd = 0.1
				return false
			if ammo <= 0:
				reload()
				return false
			ammo -= 1
			start_action("shoot", minf(0.25, interval * 0.8), 0.05, {"anim": "shoot"})
		"staff":
			if mana >= 3.0:
				mana -= 3.0
				start_action("cast_bolt", minf(0.55, interval * 0.9), 0.45, {"anim": "cast"})
			else:
				start_action("melee", 0.55, 0.45, {"anim": "overhead", "mult": 0.6})
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
			Combat.fire_weapon(self)
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

func reload() -> void:
	var b := weapon_base()
	if not b.has("mag") or reload_t > 0.0 or ammo >= b.mag:
		return
	var t: float = b.get("reload", 1.5)
	if data and data.has_node("fa_reload"):
		t *= 0.6
	reload_t = t
	Audio.play_sfx("reload", global_position, -4.0)

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
	return w

func dodge(dir: Vector3) -> bool:
	if not can_act() or dodge_cd > 0.0 or stamina < 18.0:
		return false
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
	var s: Array = data.auto_slots(weapon_cat())
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
	if DBSkills.is_spell(id):
		ok = Spells.cast(self, id, aim)
	else:
		ok = Skills.use(self, id, aim)
	return ok

func cooldown_of(id: String) -> float:
	return skill_cd.get(id, 0.0)

# ---------------------------------------------------------------- damage
## Expired grudges are dropped so fights end (they used to persist forever).
func _purge_aggro() -> void:
	if aggro.is_empty():
		return
	var now := Time.get_ticks_msec()
	for k in aggro.keys():
		if int(aggro[k]) <= now:
			aggro.erase(k)

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
	var s := params.duplicate()
	s.t = maxf(dur, statuses.get(id, {}).get("t", 0.0))
	statuses[id] = s
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
		amount *= 1.0 - bv
		stamina -= 10.0 + info.get("amount", 0.0) * 0.15
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
		var absorbed := minf(shield_hp, amount)
		shield_hp -= absorbed
		amount -= absorbed
		if shield_hp <= 0.0:
			statuses.erase("magic_shield")
	var dealt := _apply_raw_damage(amount, src, info.get("dtype", "slash"), false, info)
	# thorns
	if info.get("melee", false) and src and is_instance_valid(src) and _has_ability("thorns"):
		src._apply_raw_damage(dealt * 0.25, self, "pierce", true)
	if dealt > 0.0 and not is_dead:
		var kb: float = info.get("knock", 0.0)
		if kb > 0.0 and from_dir.length() > 0.1 and kind != "boss":
			# heavier bodies (big scale) are pushed less
			knockback = -from_dir * kb / maxf(1.0, _scale())
		# finishers stagger and can briefly launch lighter foes off their feet
		if info.get("finisher", false) and kind != "boss" and not statuses.has("unstoppable"):
			act = {}
			apply_status("stun", 0.35)
			var la: float = info.get("launch", 0.0)
			if la > 0.0 and _scale() <= 1.3 and is_on_floor():
				velocity.y = la
		for st in info.get("status", {}):
			var sv = info.status[st]
			if st == "burn":
				apply_status("burn", 4.0, {"dps": float(sv), "src": src})
			elif st == "slow":
				apply_status("slow", 2.5, {"f": float(sv)})
			else:
				apply_status(st, float(sv))
		var heavy_hit: bool = dealt > max_hp * 0.18 or info.get("crit", false) or info.get("knock", 0.0) >= 5.0
		VFX.hit_fx(chest() + from_dir * radius(), -from_dir, info.get("dtype", "slash"), heavy_hit, DBActors.ENEMIES.get(def_id, {}).get("metal", false) or stat("armor") > 20.0)
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
		if it.get("ability", "") == ab:
			return true
	return false

func die(killer) -> void:
	if is_dead:
		return
	is_dead = true
	hp = 0.0
	act = {}
	blocking = false
	statuses.clear()
	if rig:
		rig.dead = true
	collision_layer = 0
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
