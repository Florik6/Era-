class_name BossShield
extends RefCounted
## A boss's magic shield as a finite state machine — part of its tactics,
## never a lasting state.
##
##   INACTIVE → CHARGING (1–2 s, can be interrupted) → ACTIVE (5–8 s, a pool
##   of shield HP that absorbs damage; the counter element hits it twice as
##   hard; killing a supporting guardian tears off a third of it)
##   → BROKEN (pool emptied: flash, boss exposed for 3 s) or ENDED (time up)
##   → COOLDOWN (15–25 s, counted from the END of the shield) → INACTIVE.
##
## There is no invulnerability: damage above the pool goes through, and the
## pool disappears with the shield. The visual dome is created and removed
## by the same transitions that switch the real protection, so what the
## player sees is what the boss has. Death, phase changes and removal clean
## everything up.
##
## Old bug (fixed): "shield" made the boss fully invulnerable while summoned
## guardians lived — with no time limit — and the 30 s cool-down started at
## the CAST. Guardians that wandered off kept the shield up for minutes; by
## the time it fell the cool-down had long expired and the shield came right
## back. Phase changes also cleared all cool-downs, and the boss could recast
## the shield while shielded, piling up guardians.

enum {INACTIVE, CHARGING, ACTIVE, BROKEN, COOLDOWN}
const NAMES := ["неактивен", "подготовка", "активен", "разрушен", "восстановление"]

var b                      # Boss
var state := INACTIVE
var t := 0.0               # time left in the current state (game seconds)
var spec := {}
var pool := 0.0
var pool_max := 0.0
var guardians: Array = []
var dome: Node3D = null
var _vis_level := -1       # 0 full, 1 damaged, 2 critical
var _charge_taken := 0.0
var stats := {"casts": 0, "broken": 0, "expired": 0, "interrupted": 0, "absorbed": 0.0, "passed": 0.0, "active_time": 0.0, "longest": 0.0}
var history: Array = []    # [state name, game time] transitions (tests)
var _active_t := 0.0

func _init(boss) -> void:
	b = boss

static func defaults(s: Dictionary) -> Dictionary:
	return {"charge": float(s.get("charge", 1.5)), "dur": float(s.get("dur", 6.5)), "cd": float(s.get("cd_after", 20.0)),
		"pool": float(s.get("pool", 0.12)), "counter": s.get("counter", []), "enemy": str(s.get("enemy", "")),
		"count": mini(2, int(s.get("count", 0))), "interrupt": float(s.get("interrupt", 0.06))}

func can_start() -> bool:
	return state == INACTIVE and b != null and is_instance_valid(b) and not b.is_dead

func is_active() -> bool:
	return state == ACTIVE

## Begin charging (only from INACTIVE: never straight from an ended shield).
func start(s: Dictionary) -> bool:
	if not can_start():
		return false
	spec = defaults(s)
	_charge_taken = 0.0
	_to_state(CHARGING, spec.charge)
	stats.casts += 1
	b.start_action("skill", spec.charge + 0.2, 0.98, {"anim": "cast"})
	MagicFX.ground_rune(b.global_position, "sigil", _color(), 2.6, spec.charge + 0.3, 1.6, 1.2)
	VFX.telegraph(b.global_position, 2.2, spec.charge, _color())
	var ctext := ""
	if not spec.counter.is_empty():
		var names: Array = []
		for c in spec.counter:
			names.append(ItemDB.DTYPE_NAMES.get(c, c))
		ctext = " Уязвим: " + ", ".join(PackedStringArray(names)) + "."
	Events.notify.emit("%s готовит магический щит — прервите его!%s" % [b.display_name, ctext], Color(0.75, 0.75, 1.0))
	return true

func _to_state(s: int, dur: float) -> void:
	if state == ACTIVE and s != ACTIVE:
		stats.longest = maxf(stats.longest, _active_t)
	state = s
	t = dur
	history.append([NAMES[s], Game.game_time, Time.get_ticks_msec()])
	if history.size() > 40:
		history.pop_front()

func _color() -> Color:
	return Combat.element_color(str(b.natural_dtype)) if b.natural_dtype in ["fire", "ice", "lightning", "dark", "time", "energy"] else Color(0.6, 0.7, 1.0)

func tick(delta: float) -> void:
	if b == null or not is_instance_valid(b):
		return
	if b.is_dead:
		clear()
		return
	match state:
		CHARGING:
			# a stun / freeze breaks the preparation (interrupting blows call interrupt())
			if not b.can_act():
				interrupt("подготовка сорвана")
				return
			t -= delta
			if t <= 0.0:
				_activate()
		ACTIVE:
			t -= delta
			_active_t += delta
			stats.active_time += delta
			for g in guardians.duplicate():
				if not is_instance_valid(g) or g.is_dead:
					guardians.erase(g)
					hit_pool(pool_max * 0.34, "", true)
					if state != ACTIVE:
						return
			if t <= 0.0:
				_end(false)
		BROKEN:
			t -= delta
			if t <= 0.0:
				_to_state(COOLDOWN, spec.cd)
		COOLDOWN:
			t -= delta
			if t <= 0.0:
				_to_state(INACTIVE, 0.0)

func interrupt(why := "прервано") -> void:
	if state != CHARGING:
		return
	stats.interrupted += 1
	VFX.text(b.chest() + Vector3(0, 1.2, 0), "Щит сорван!", Color(1.0, 0.9, 0.5))
	Events.notify.emit("%s: %s" % [b.display_name, why], Color(1.0, 0.9, 0.5))
	_to_state(COOLDOWN, spec.cd * 0.5)

func _activate() -> void:
	pool_max = maxf(60.0, b.max_hp * spec.pool)
	pool = pool_max
	_active_t = 0.0
	_to_state(ACTIVE, spec.dur)
	_build_dome()
	if spec.enemy != "" and spec.count > 0 and Game.world and Game.world.get("spawner"):
		for i in spec.count:
			var an: float = TAU * i / float(spec.count)
			var p: Vector3 = b.global_position + Vector3(cos(an), 0, sin(an)) * 4.0
			var m = Game.world.spawner.spawn_enemy(spec.enemy, p, maxi(1, b.level - 2))
			if m:
				m.team = "boss"
				m.summon_time = spec.dur + 4.0      # guardians never outlive the shield for long
				m.owner_actor = b
				guardians.append(m)
				MagicFX.summon_puff(p + Vector3(0, 1, 0), _color())
	Audio.play_sfx("portal_open", b.global_position, -2.0)

## Called by Boss.take_damage. Returns the damage that passes through.
func absorb(info: Dictionary) -> float:
	var amt := float(info.get("amount", 0.0))
	if state != ACTIVE:
		return amt
	var k := 2.0 if str(info.get("dtype", "")) in spec.counter else 1.0
	var into := amt * k
	var taken := minf(pool, into)
	hit_pool(taken, str(info.get("dtype", "")))
	var passed := maxf(0.0, (into - taken) / k)
	stats.absorbed += taken
	stats.passed += passed
	return passed

func hit_pool(n: float, _dtype := "", from_guardian := false) -> void:
	if state != ACTIVE:
		return
	pool -= n
	if from_guardian:
		VFX.text(b.chest() + Vector3(0, 1.4, 0), "Страж пал — щит слабеет!", Color(0.8, 0.85, 1.0))
	if pool <= 0.0:
		pool = 0.0
		_end(true)
	else:
		_update_dome()

func _end(broken: bool) -> void:
	_remove_dome(broken)
	for g in guardians:
		if is_instance_valid(g) and not g.is_dead:
			g.summon_time = minf(g.summon_time, 3.0) if g.summon_time > 0.0 else 3.0
	guardians.clear()
	pool = 0.0
	if broken:
		stats.broken += 1
		# exposed: a short window of extra damage, the boss keeps fighting
		b.apply_status("exposed", 3.0, {"mods": {"taken_pct": 0.3}})
		Events.notify.emit("Щит разрушен! %s уязвим" % b.display_name, Color(1.0, 0.85, 0.4))
		Audio.play_sfx("ice_shatter", b.global_position)
		_to_state(BROKEN, 3.0)
	else:
		stats.expired += 1
		Events.notify.emit("Щит %s рассеялся" % b.display_name, Color(0.8, 0.8, 1.0))
		_to_state(COOLDOWN, spec.cd)

## Phase change: an active or charging shield ends (shorter cool-down).
func on_phase() -> void:
	if state == ACTIVE:
		_remove_dome(false)
		for g in guardians:
			if is_instance_valid(g) and not g.is_dead:
				g.summon_time = 3.0
		guardians.clear()
		pool = 0.0
		_to_state(COOLDOWN, spec.cd * 0.5)
	elif state == CHARGING:
		_to_state(COOLDOWN, spec.cd * 0.5)

## Death / removal: nothing of the shield may survive the boss.
func clear() -> void:
	_remove_dome(false)
	for g in guardians:
		if is_instance_valid(g) and not g.is_dead:
			AbilityExec.despawn(g)
	guardians.clear()
	pool = 0.0
	if state != INACTIVE:
		_to_state(INACTIVE, 0.0)

func ratio() -> float:
	return pool / maxf(1.0, pool_max)

# ------------------------------------------------------------------ visuals
func _build_dome() -> void:
	_remove_dome(false)
	var d := MeshInstance3D.new()
	d.name = "ShieldDome"
	var sc: float = b._scale()
	d.mesh = MeshLib.sphere(1.0, 20, 12)
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var c := _color()
	d.material_override = MagicFX.smat("fresnel", {"col": Color(c.r, c.g, c.b, 0.42), "power": 1.6, "glint": 0.0}, "")
	b.add_child(d)
	d.position = Vector3(0, 1.1 * sc, 0)
	d.scale = Vector3.ONE * 0.1
	d.create_tween().tween_property(d, "scale", Vector3.ONE * 1.55 * sc, 0.25).set_ease(Tween.EASE_OUT)
	dome = d
	_vis_level = 0

func _update_dome() -> void:
	if dome == null or not is_instance_valid(dome):
		return
	var lvl := 0 if ratio() > 0.66 else (1 if ratio() > 0.33 else 2)
	if lvl == _vis_level:
		return
	_vis_level = lvl
	var m := dome.material_override as ShaderMaterial
	var c := _color()
	match lvl:
		1:
			# cracks: glints and an unsteady glow
			m.set_shader_parameter("glint", 0.8)
			m.set_shader_parameter("col", Color(c.r, c.g, c.b, 0.32))
			VFX.burst(b.chest(), c, 8, 0.25)
		2:
			# critical: energy tears, flicker
			m.set_shader_parameter("glint", 1.0)
			m.set_shader_parameter("bands", 9.0)
			m.set_shader_parameter("col", Color(1.0, 0.85, 0.8, 0.24))
			var tw := dome.create_tween().set_loops(20)
			tw.tween_property(dome, "visible", false, 0.06)
			tw.tween_property(dome, "visible", true, 0.12)
			VFX.burst(b.chest(), Color(1.0, 0.9, 0.8), 12, 0.3)

func _remove_dome(broken: bool) -> void:
	if dome != null and is_instance_valid(dome):
		if broken and VFX.mgr() != null:
			VFX.burst(dome.global_position, _color(), 24, 0.35)
			VFX.mgr().shock(dome.global_position, 3.0 * b._scale(), _color(), 0.35)
		dome.queue_free()
	dome = null
	_vis_level = -1

func visual_present() -> bool:
	return dome != null and is_instance_valid(dome) and not dome.is_queued_for_deletion()
