class_name BossBrain
extends RefCounted
## Boss fight director: phase transitions (visible: roar, banner, arena
## changes, summons, form change, rift transfer), telegraphed ability
## library, melee between abilities, escape logic.

var b
var target = null
var think_t := 0.0
var ability_cd := {}
var global_cd := 2.0
var casting := false
var spin_t := 0.0
var escape_checked := false

func _init(boss) -> void:
	b = boss

func tick(delta: float) -> void:
	for k in ability_cd.keys():
		ability_cd[k] -= delta
	global_cd -= delta
	if spin_t > 0.0:
		spin_t -= delta
	if not b.can_act():
		b.move_input = Vector3.ZERO
		return
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.3
		_pick_target()
		_check_phase()
	if target == null:
		var home: Vector3 = b.arena_center - b.global_position
		home.y = 0
		b.move_input = home.normalized() * 0.5 if home.length() > 3.0 else Vector3.ZERO
		if home.length() < 3.0 and b.hp < b.max_hp:
			b.hp = minf(b.max_hp, b.hp + b.max_hp * 0.02 * delta)
		return
	if casting:
		b.move_input = Vector3.ZERO
		return
	var to: Vector3 = target.global_position - b.global_position
	to.y = 0
	var d := to.length()
	var dir = to.normalized() if d > 0.01 else b.facing
	b.face_dir(dir)
	if global_cd <= 0.0 and _try_ability(d, dir):
		return
	var reach: float = b.natural_range + 0.6
	if d > reach:
		b.move_input = dir * (1.25 if b.statuses.has("enrage") else 1.0)
	else:
		b.move_input = Vector3.ZERO
		_melee(dir)

func _pick_target() -> void:
	var best = null
	var bd := 34.0
	for a in Game.actors_near(b.global_position, 34.0):
		if a.is_dead or not Game.is_enemy(b, a):
			continue
		var d: float = a.global_position.distance_to(b.global_position)
		if a.is_player:
			d -= 6.0
		if d < bd:
			bd = d
			best = a
	if best == null and target != null and is_instance_valid(target) and not target.is_dead and target.global_position.distance_to(b.global_position) < 60.0:
		return
	target = best

func _melee(dir: Vector3) -> void:
	if b.attack_cd > 0.0 or b.busy():
		return
	b.attack_cd = 1.6 if not b.statuses.has("enrage") else 1.1
	var anims := ["slash", "overhead", "slash2"]
	b.start_action("skill", 0.8, 0.55, {"anim": anims[randi() % 3], "cb": func():
		var info := {"amount": b.base_dmg, "dtype": b.natural_dtype, "src": b, "melee": true, "knock": 5.0}
		Combat.melee(b, b.natural_range + 0.8, 120.0, info)
		Audio.play_sfx("swing_heavy", b.global_position)})

func _check_phase() -> void:
	var phases: Array = b.def.phases
	var ratio: float = b.hp / maxf(1.0, b.max_hp)
	var np: int = b.phase
	for i in phases.size():
		if ratio <= phases[i].hp + 0.001:
			np = i
	if np > b.phase:
		b.phase = np
		_enter_phase(np)
	# escape (nemesis): strong bosses may flee at low health once
	if not escape_checked and ratio < 0.15 and b.can_escape and b.boss_id != "chronos_avatar" and Game.world and Game.world.dimension == "":
		escape_checked = true
		if randf() < 0.22 and b.times_escaped < 1:
			_escape()

func _enter_phase(i: int) -> void:
	var ph: Dictionary = b.def.phases[i]
	Events.boss_phase.emit(b, i)
	Audio.play_sfx("boss_phase", b.global_position)
	Audio.play_sfx("boss_roar", b.global_position)
	b.start_action("skill", 1.4, 0.95, {"anim": "roar"})
	b.apply_status("invuln", 1.4)
	VFX.ring(b.global_position, 8.0, Color(1.0, 0.3, 0.2), 0.8)
	MagicFX.phase_burst(b.global_position, Combat.element_color(b.natural_dtype) if b.natural_dtype in ["fire", "ice", "lightning", "dark", "time", "energy"] else Color(1.0, 0.35, 0.2), clampf(float(b.def.get("scale", 1.5)), 1.0, 2.5))
	VFX.shake(0.5)
	var cine = Game.world.sys("cinematic") if Game.world and Game.world.has_method("sys") else null
	if cine and cine.has_method("play"):
		cine.play("boss", "%s — фаза %d" % [b.display_name, i + 1], String(ph.get("msg", "")), "cine_bossphase_%s_%d" % [b.boss_id, i], b.global_position + Vector3(0, 2.0, 0))
	if ph.has("msg"):
		Events.banner.emit("%s — фаза %d" % [b.display_name, i + 1], ph.msg, Color(1.0, 0.45, 0.3))
	# the phase change is an event: shockwave pushes the hero back, a short
	# slow-motion beat, a title card, and the arena changes with the boss
	var pl = Game.player
	if pl and is_instance_valid(pl) and pl.global_position.distance_to(b.global_position) < 10.0:
		var away: Vector3 = pl.global_position - b.global_position
		away.y = 0
		pl.knockback = away.normalized() * 8.0
	VFX.shock(b.global_position, 9.0, Color(1.0, 0.45, 0.3), 0.5)
	CombatFeel.slowmo(0.4, 0.25)
	CombatFeel.flash(Color(1.0, 0.5, 0.35), 0.15)
	_arena_shift(i)
	if ph.get("enrage", false) or i >= 2:
		_rage_aura()
	if ph.get("enrage", false):
		b.apply_status("enrage", 9999.0)
		b.base_speed *= 1.2
	if ph.has("form"):
		var f: float = ph.form
		var tw = b.rig.create_tween()
		tw.tween_property(b.rig, "scale", b.rig.scale * f, 1.0)
		b.base_dmg *= 1.15
	if ph.get("arena", "") == "break" and Game.world:
		Game.world.boss_arena_break(b)
	for ab in b.bonus_abilities:
		ability_cd[ab] = 2.0
	global_cd = 1.6
	ability_cd.clear()

func _available() -> Array:
	var ph: Dictionary = b.def.phases[b.phase]
	var out: Array = []
	for ab in ph.use + b.bonus_abilities:
		if b.disabled_abilities.has(ab):
			continue
		if ability_cd.get(ab, 0.0) > 0.0:
			continue
		out.append(ab)
	return out

func _try_ability(d: float, dir: Vector3) -> bool:
	var av := _available()
	if av.is_empty():
		return false
	av.shuffle()
	for ab in av:
		var spec: Dictionary = b.def.abilities.get(ab, {})
		if spec.is_empty():
			continue
		var typ: String = spec.type
		if typ in ["cleave", "spin"] and d > 6.0:
			continue
		if typ == "slam" and d > spec.get("radius", 5.0) + 1.0:
			continue
		if typ == "portal" and (Game.world == null or Game.world.dimension != ""):
			ability_cd[ab] = 999.0
			continue
		ability_cd[ab] = spec.get("cd", 6.0) * (0.75 if b.statuses.has("enrage") else 1.0)
		global_cd = 1.2 if b.statuses.has("enrage") else 1.8
		_do(typ, spec, dir)
		return true
	return false

func _dmg(spec: Dictionary) -> Dictionary:
	return {"amount": b.base_dmg * spec.get("dmg", 1.0), "dtype": spec.get("dtype", b.natural_dtype), "src": b, "melee": false, "knock": 4.0}

func _later(t: float, cb: Callable) -> void:
	b.get_tree().create_timer(t, false).timeout.connect(func():
		if is_instance_valid(b) and not b.is_dead:
			cb.call())

func _cast(dur: float) -> void:
	casting = true
	_later(dur, func(): casting = false)

func _do(typ: String, spec: Dictionary, dir: Vector3) -> void:
	var col: Color = Combat.element_color(spec.get("dtype", b.natural_dtype))
	var tpos: Vector3 = target.global_position if target and is_instance_valid(target) else b.global_position + dir * 5.0
	match typ:
		"cleave":
			var r: float = spec.get("radius", 4.5)
			var arc: float = spec.get("arc", 120.0)
			VFX.telegraph(b.global_position, r, 0.7, Color(1, 0.2, 0.1), "cone", dir, arc)
			b.start_action("skill", 1.0, 0.75, {"anim": "slash"})
			_cast(0.9)
			var f: Vector3 = dir
			_later(0.7, func():
				for a in Game.actors_near(b.global_position, r + 1.0):
					if a.is_dead or not Game.is_enemy(b, a):
						continue
					var to: Vector3 = a.global_position - b.global_position
					to.y = 0
					if to.length() - a.radius() <= r and (to.length() < 1.0 or f.angle_to(to.normalized()) <= deg_to_rad(arc * 0.5)):
						Combat.deal(b, a, _dmg(spec))
				Audio.play_sfx("swing_heavy", b.global_position)
				VFX.slash(b.global_position + Vector3(0, 1.0, 0), f, r, arc, "slash", Color(1.0, 0.7, 0.5))
				VFX.ground_impact(b.global_position + f * r * 0.6, 1.6)
				VFX.shake(0.25))
		"slam", "nova":
			var r2: float = spec.get("radius", 5.0)
			VFX.telegraph(b.global_position, r2, 0.9 if typ == "slam" else 1.1, col if typ == "nova" else Color(1, 0.2, 0.1))
			b.start_action("skill", 1.2, 0.75, {"anim": "slam" if typ == "slam" else "cast"})
			_cast(1.1)
			_later(0.9 if typ == "slam" else 1.1, func():
				VFX.explosion(b.global_position, r2, col if typ == "nova" else Color(0.8, 0.7, 0.5))
				var inf := _dmg(spec)
				if typ == "nova" and spec.get("dtype", "") == "ice":
					inf.status = {"slow": 0.4}
				Combat.aoe(b, b.global_position, r2, inf, false))
		"charge":
			var len := minf(14.0, b.global_position.distance_to(tpos) + 3.0)
			var f2: Vector3 = dir
			VFX.telegraph(b.global_position, 1.3, 0.6, Color(1, 0.2, 0.1), "line", f2, 360.0, len)
			_cast(1.1)
			_later(0.6, func():
				var start: Vector3 = b.global_position
				b.knockback = f2 * (len / 0.35)
				b.start_action("skill", 0.5, 0.1, {"anim": "thrust"})
				_later(0.35, func():
					b.knockback = Vector3.ZERO
					_dust_trail(start, b.global_position)
					for a in Game.actors_near((start + b.global_position) * 0.5, len):
						if a.is_dead or not Game.is_enemy(b, a):
							continue
						var cp := Geometry3D.get_closest_point_to_segment(a.global_position, start, b.global_position)
						if cp.distance_to(a.global_position) < 2.0:
							Combat.deal(b, a, _dmg(spec))
					VFX.shake(0.3)))
		"fan":
			var n: int = spec.get("count", 5)
			b.start_action("skill", 0.6, 0.5, {"anim": "cast" if b.def.rig != "humanoid" or not b.def.has("weapon") or ItemDB.base(b.def.weapon).get("cat", "") == "staff" else "shoot"})
			_later(0.3, func():
				for i in n:
					var a2: float = deg_to_rad(-40.0 + 80.0 * i / maxf(1.0, n - 1))
					var kind := "magic" if spec.get("dtype", "") in ["fire", "ice", "dark", "time", "lightning"] else "bullet"
					Projectile.spawn(b, b.chest() + dir * 1.2, dir.rotated(Vector3.UP, a2) * (20.0 if kind == "magic" else 40.0), _dmg(spec), kind, {"range": 26.0, "color": col, "splash": 1.5 if kind == "magic" else 0.0})
				Audio.play_sfx("fire_cast" if spec.get("dtype", "") == "fire" else "gun_rifle", b.global_position))
		"volley", "strikes":
			var n2: int = spec.get("count", 5)
			b.start_action("skill", 0.8, 0.5, {"anim": "cast"})
			for i in n2:
				var off := Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)) if i > 0 else Vector3.ZERO
				var pt: Vector3 = tpos + off
				if Game.world:
					pt.y = Game.world.ground_height(pt)
				var delay := 0.9 + i * (0.12 if typ == "volley" else 0.2)
				VFX.telegraph(pt, 2.4, delay, col)
				_later(delay, func():
					if typ == "strikes":
						MagicFX.sky_strike(pt, col, 2.4)
						Audio.play_sfx("thunder", pt, -6.0)
					else:
						VFX.explosion(pt, 2.4, col)
						Audio.play_sfx("explosion", pt, -6.0)
					Combat.aoe(b, pt, 2.4, _dmg(spec), false))
		"summon", "shield":
			var eid: String = spec.get("enemy", "skeleton")
			var cnt: int = spec.get("count", 2)
			b.start_action("skill", 1.0, 0.6, {"anim": "roar" if typ == "summon" else "cast"})
			_cast(0.9)
			var adds: Array = []
			MagicFX.summon_circle(b.global_position, 3.0, col)
			if Game.world and Game.world.get("spawner"):
				for i in cnt:
					var p2: Vector3 = b.global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
					var m = Game.world.spawner.spawn_enemy(eid, p2, maxi(1, b.level - 1))
					if m:
						m.team = "boss"
						adds.append(m)
						MagicFX.summon_puff(p2 + Vector3(0, 1, 0), col)
			if typ == "shield" and not adds.is_empty():
				b.shielded = true
				b.shield_adds = adds
				Events.notify.emit("%s неуязвим, пока живы его стражи!" % b.display_name, Color(0.7, 0.7, 1.0))
				_watch_shield()
		"beam":
			var f3: Vector3 = dir
			VFX.telegraph(b.global_position, 0.9, 0.8, col, "line", f3, 360.0, 22.0)
			b.start_action("skill", 1.1, 0.7, {"anim": "cast"})
			_cast(1.0)
			_later(0.8, func():
				var s: Vector3 = b.chest()
				var e: Vector3 = s + f3 * 22.0
				_boss_beam(s, e, col)
				Audio.play_sfx("laser", b.global_position)
				for a in Game.actors_near(b.global_position + f3 * 11.0, 13.0):
					if a.is_dead or not Game.is_enemy(b, a):
						continue
					var cp2 := Geometry3D.get_closest_point_to_segment(a.chest(), s, e)
					if cp2.distance_to(a.chest()) < 1.4 and Combat.line_of_sight(s, a.chest()):
						Combat.deal(b, a, _dmg(spec)))
		"blink":
			var dest: Vector3 = tpos + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
			if Game.world:
				dest.y = Game.world.ground_height(dest) + 0.1
			var bsch := MagicFX.school_from_color(col)
			if not (bsch in ["fire", "ice", "lightning", "dark", "time", "energy"]):
				bsch = "dark"
			var from: Vector3 = b.global_position
			MagicFX.blink_out(b, bsch)
			b.global_position = dest
			b.reset_physics_interpolation()
			MagicFX.blink_in(b, from, bsch)
			Audio.play_sfx("teleport", dest)
		"slowzone":
			Zone.create("timeslow", b, tpos, 5.0, 6.0, {})
			Audio.play_sfx("time_slow", tpos)
		"portal":
			if Game.world and Game.world.has_method("enter_dimension"):
				_cast(1.5)
				b.apply_status("invuln", 2.0)
				VFX.ring(b.global_position, 6.0, Color(0.6, 0.2, 1.0), 1.0)
				MagicFX.ground_rune(b.global_position, "rift", Color(0.6, 0.3, 1.0), 3.5, 1.6, 2.5, 1.0)
				Audio.play_sfx("portal_open", b.global_position)
				_later(1.2, func(): Game.world.enter_dimension(spec.get("dimension", "distorted"), {"boss": b}))
		"hook":
			var f4: Vector3 = dir
			VFX.telegraph(b.global_position, 0.8, 0.6, Color(1, 0.2, 0.1), "line", f4, 360.0, 14.0)
			b.start_action("skill", 0.9, 0.6, {"anim": "throw"})
			_later(0.6, func():
				if target and is_instance_valid(target) and not target.is_dead:
					var cp3 := Geometry3D.get_closest_point_to_segment(target.global_position, b.global_position, b.global_position + f4 * 14.0)
					if cp3.distance_to(target.global_position) < 1.6 and not target.invulnerable():
						VFX.beam(b.chest(), target.chest(), Color(0.7, 0.7, 0.75), 0.3, 0.06, false)
						target.knockback = (b.global_position - target.global_position).normalized() * 16.0
						Combat.deal(b, target, _dmg(spec))
						target.apply_status("slow", 1.5, {"f": 0.5})
				Audio.play_sfx("swing", b.global_position))
		"spin":
			var r3: float = spec.get("radius", 4.0)
			b.start_action("skill", 2.0, 0.05, {"anim": "spin"})
			for i in 5:
				_later(0.4 * i, func():
					VFX.slash(b.global_position + Vector3(0, 1.0, 0), b.facing.rotated(Vector3.UP, 1.3 * i), r3, 360.0, "spin", Color(1, 0.7, 0.5))
					VFX.shock(b.global_position, r3, Color(1, 0.6, 0.4, 0.6), 0.25)
					Combat.aoe(b, b.global_position, r3, _dmg(spec), false)
					Audio.play_sfx("swing_heavy", b.global_position, -4.0))
		"quake":
			b.start_action("skill", 1.2, 0.5, {"anim": "slam"})
			_cast(1.0)
			var f5: Vector3 = dir
			for i in 4:
				var pq: Vector3 = b.global_position + f5 * (3.0 + 3.0 * i)
				VFX.telegraph(pq, 2.6, 0.7 + i * 0.2, Color(1, 0.3, 0.1))
				_later(0.7 + i * 0.2, func():
					VFX.explosion(pq, 2.6, Color(0.7, 0.55, 0.4))
					Combat.aoe(b, pq, 2.6, _dmg(spec), false))
		"missiles":
			var n3: int = spec.get("count", 4)
			b.start_action("skill", 0.8, 0.4, {"anim": "cast"})
			for i in n3:
				_later(0.15 * i, func():
					var d3: Vector3 = dir.rotated(Vector3.UP, randf_range(-1.2, 1.2))
					Projectile.spawn(b, b.chest() + Vector3(0, 1.0, 0), d3 * 14.0 + Vector3(0, 3, 0), _dmg(spec), "magic", {"range": 30.0, "homing": 1.2, "splash": 2.0, "color": col}))
			Audio.play_sfx("plasma", b.global_position)
		"mines":
			var n4: int = spec.get("count", 6)
			for i in n4:
				var pm: Vector3 = b.global_position + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
				if Game.world:
					pm.y = Game.world.ground_height(pm)
				Zone.create("mine", b, pm, 1.2, 20.0, _dmg(spec))
			Audio.play_sfx("reload", b.global_position)

func _watch_shield() -> void:
	_later(0.5, func():
		var alive := false
		for a in b.shield_adds:
			if is_instance_valid(a) and not a.is_dead:
				alive = true
		if alive:
			_watch_shield()
		else:
			b.shielded = false
			b.shield_adds = []
			Events.notify.emit("Щит босса пал!", Color(1.0, 0.85, 0.4))
			Audio.play_sfx("ice_shatter", b.global_position))

func _escape() -> void:
	b.times_escaped += 1
	Events.banner.emit("%s отступает!" % b.display_name, "Он запомнит эту встречу и вернётся сильнее.", Color(1.0, 0.6, 0.3))
	MagicFX.blink_out(b, "dark")
	var mg = VFX.mgr()
	if mg:
		mg.emit(b.chest(), {"n": 30, "life": 1.6, "mat": "mix", "col": Color(0.15, 0.14, 0.16, 0.85), "ramp": "smoke", "size": 2.0, "shape": "sphere", "rad": 1.2, "v0": 1.0, "v1": 3.0, "damp": 2.0, "grav": Vector3(0, 0.5, 0), "curve": "puff", "critical": true})
	Audio.play_sfx("teleport", b.global_position)
	if Game.world and Game.world.has_method("on_boss_escaped"):
		Game.world.on_boss_escaped(b, target)
	b.queue_free()

# ---------------------------------------------------------------- visuals only
func _dust_trail(a: Vector3, e: Vector3) -> void:
	var mg = VFX.mgr()
	if mg == null or a.distance_to(e) < 0.5:
		return
	var d := e - a
	d.y = 0
	var bs := Basis.looking_at(d.normalized() if d.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
	mg.emit((a + e) * 0.5 + Vector3(0, 0.3, 0), {"n": int(6 + d.length() * 2.0), "life": 1.0, "mat": "mix", "col": Color(0.7, 0.62, 0.5, 0.7), "ramp": "smoke", "size": 1.4, "shape": "box", "box": Vector3(0.8, 0.2, d.length() * 0.5), "basis": bs, "v0": 0.5, "v1": 1.5, "dir": Vector3.UP, "spread": 50.0, "damp": 2.0, "grav": Vector3(0, 0.2, 0), "curve": "puff", "critical": true})
	VFX.ground_impact(e, 2.0)

func _boss_beam(s: Vector3, e: Vector3, col: Color) -> void:
	VFX.beam(s, e, col, 0.4, 0.5, false)
	VFX.beam(s, e, Color(1, 1, 1), 0.3, 0.15, false)
	var mg = VFX.mgr()
	if mg == null:
		return
	var d := e - s
	mg.emit((s + e) * 0.5, {"n": 30, "life": 0.5, "mat": "add", "col": col, "size": 0.3, "shape": "box", "box": Vector3(0.3, 0.3, d.length() * 0.5), "basis": Basis.looking_at(d.normalized() if d.length() > 0.01 else Vector3.FORWARD, Vector3.UP), "v0": 0.5, "v1": 2.0, "grav": Vector3.ZERO, "curve": "shrink", "critical": true})
	mg.glow(s, col, 2.0, 0.4)
	mg.light((s + e) * 0.5, col, 4.0, 10.0, 0.35)
	mg.decal(MagicFX.ground_point(e), "scorch", 2.0, 12.0, randf() * TAU)


## Arena reacts to the phase: hazards in the boss's element around the arena.
func _arena_shift(i: int) -> void:
	var center: Vector3 = b.arena_center if b.get("arena_center") != null and b.arena_center != Vector3.ZERO else b.global_position
	var dt: String = String(b.natural_dtype)
	var n := 3 + i * 2
	for k in n:
		var a := TAU * k / n + randf() * 0.4
		var p: Vector3 = center + Vector3(cos(a), 0, sin(a)) * randf_range(6.0, 11.0)
		match dt:
			"fire":
				Zone.create("fire", b, p, 1.4, 8.0, {"amount": 6.0 + b.level, "dtype": "fire", "status": {"burn": 4.0}})
			"ice":
				MagicFX.ice_spikes(p, 1.6, 4)
				Zone.create("blizzard", b, p, 1.6, 6.0, {"amount": 4.0 + b.level, "dtype": "ice", "status": {"slow": 0.5}})
			"lightning", "energy":
				var pp := p
				b.get_tree().create_timer(0.4 * k, false).timeout.connect(func():
					if is_instance_valid(b) and not b.is_dead:
						VFX.telegraph(pp, 2.0, 0.8, Color(0.7, 0.8, 1.0))
						b.get_tree().create_timer(0.8, false).timeout.connect(func():
							MagicFX.sky_strike(pp, Color(0.8, 0.85, 1.0), 2.0)
							Combat.aoe(b if is_instance_valid(b) else null, pp, 2.0, {"amount": 10.0 + b.level * 1.5, "dtype": "lightning"})))
			"dark", "time":
				Zone.create("timeslow" if dt == "time" else "dark", b, p, 1.8, 7.0, {"amount": 5.0 + b.level, "dtype": "dark"}, {"hostile_all": false})
			_:
				VFX.decal(p, "crack", 3.0, 25.0, randf() * TAU)
				VFX.ground_impact(p, 2.0)

## Persistent rage aura: embers swirling around the boss.
func _rage_aura() -> void:
	if b.rig == null or b.rig.has_node("RageAura"):
		return
	var pr := CPUParticles3D.new()
	pr.name = "RageAura"
	pr.amount = CombatFeel.particles(26)
	pr.lifetime = 1.0
	pr.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	pr.emission_sphere_radius = 1.2 * float(b.def.get("scale", 1.5))
	pr.direction = Vector3.UP
	pr.spread = 25.0
	pr.gravity = Vector3(0, 2.0, 0)
	pr.initial_velocity_min = 0.6
	pr.initial_velocity_max = 1.6
	pr.mesh = MeshLib.box(Vector3(0.08, 0.08, 0.08))
	var c := Combat.element_color(b.natural_dtype) if b.natural_dtype in ["fire", "ice", "lightning", "dark", "time", "energy"] else Color(1.0, 0.3, 0.15)
	pr.material_override = MeshLib.glow(c, 3.0)
	pr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pr.position.y = 1.4
	b.rig.add_child(pr)
