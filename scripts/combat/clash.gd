class_name Clash
## Combat Clash: two melee strikes that meet.
##
## Rules (checked at the moment a melee strike lands):
##  - direction: the two fighters face each other (within 60°) and stand
##    within reach of the longer weapon;
##  - timing: the other fighter's own strike lands within CLASH_PRE s after
##    or CLASH_POST s before this one;
##  - type: strong strikes (heavy weapons, finishers, counters, heavy
##    skills, a boss's cleave) clash. Strong vs strong → both strikes are
##    stopped, both are thrown back, the stronger side (weapon weight,
##    finisher/counter, level, a little luck) wins a counter window and the
##    loser is staggered. Strong vs light → the light strike is broken and
##    its owner staggered, the strong one goes through. Light vs light → no
##    clash (normal exchange).
## Works for anyone: hero, NPCs, monsters, bosses.
## Separately: a perfect parry of a boss's heavy attack staggers the boss,
## releases a shockwave and leaves it vulnerable for a few seconds.

const CLASH_PRE := 0.16
const CLASH_POST := 0.06
const FACE_DOT := 0.5
const STRONG := 1.0

static var count := 0
static var last := {}
static var boss_parries := 0

## How strong the actor's current action is for clashing (0 = cannot clash).
static func strength(a) -> float:
	if a == null or not is_instance_valid(a) or a.is_dead or a.act.is_empty():
		return 0.0
	var nm: String = a.act.get("name", "")
	var d: Dictionary = a.act.get("data", {})
	if nm == "skill":
		return 1.4 if (d.get("clash", false) or d.get("heavy", false)) else 0.0
	if nm != "melee":
		return 0.0
	var w := 0.5
	if a.data:
		w = float(CombatFeel.weapon_feel(a.weapon_cat()).weight)
	else:
		w = 0.55 + 0.25 * float(a.def.get("scale", 1.0)) if a.get("def") is Dictionary else 0.6
	var s := 0.5
	if w >= 0.9 or d.get("finisher", false) or d.get("counter", false) or str(d.get("anim", "")) in ["overhead", "slam", "spin"]:
		s = STRONG
	return s

static func power(a, s: float) -> float:
	var p := s
	var d: Dictionary = a.act.get("data", {})
	if a.data:
		p += float(CombatFeel.weapon_feel(a.weapon_cat()).weight)
	if a.kind == "boss":
		p += 1.2
	if d.get("finisher", false):
		p += 0.4
	if d.get("counter", false):
		p += 0.3
	p += 0.012 * float(a.level)
	return p + randf() * 0.15

## Time until the actor's strike lands (negative: it landed that long ago).
static func _until_impact(a) -> float:
	var t: float = a.act.get("t", 0.0)
	return float(a.act.get("dur", 0.0)) * float(a.act.get("impact", 0.0)) - t

## Called by Actor._on_impact before a melee strike resolves. Returns true
## when the strike is stopped by a clash (the caller then skips its damage).
static func try_clash(att, reach: float) -> bool:
	var sa := strength(att)
	if sa <= 0.0 or float(att.get_meta("clash_cd", 0.0)) > Time.get_ticks_msec() / 1000.0:
		return false
	var best = null
	var bs := 0.0
	for o in Game.actors_near(att.global_position, reach + 3.5):
		if o == att or o.is_dead or not Game.is_enemy(att, o):
			continue
		var so := strength(o)
		if so <= 0.0:
			continue
		if sa < STRONG and so < STRONG:
			continue
		var to: Vector3 = o.global_position - att.global_position
		to.y = 0
		var dist := to.length()
		var o_reach: float = o.weapon_range() if o.data else float(o.get("natural_range")) + 0.8
		if dist > maxf(reach, o_reach) + 0.8 or dist < 0.05:
			continue
		var dir := to / dist
		if att.facing.dot(dir) < FACE_DOT or o.facing.dot(-dir) < FACE_DOT:
			continue
		var u := _until_impact(o)
		if u > CLASH_PRE or u < -CLASH_POST:
			continue
		if so > bs:
			bs = so
			best = o
	if best == null:
		return false
	return _resolve(att, sa, best, bs)

static func _resolve(a, sa: float, b, sb: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	a.set_meta("clash_cd", now + 0.6)
	b.set_meta("clash_cd", now + 0.6)
	var mid: Vector3 = (a.chest() + b.chest()) * 0.5
	var ab: Vector3 = b.global_position - a.global_position
	ab.y = 0
	ab = ab.normalized() if ab.length() > 0.01 else a.facing
	count += 1
	var involved_player: bool = a.is_player or b.is_player
	if sa >= STRONG and sb >= STRONG:
		var pa := power(a, sa)
		var pb := power(b, sb)
		var win = a if pa >= pb else b
		var lose = b if win == a else a
		a.act = {}
		b.act = {}
		b.set_meta("clash_cancel_until", now + 0.4)
		a.set_meta("clash_cancel_until", now + 0.4)
		a.knockback = -ab * (4.0 + 2.0 * clampf(pb - pa + 1.0, 0.0, 2.0))
		b.knockback = ab * (4.0 + 2.0 * clampf(pa - pb + 1.0, 0.0, 2.0))
		_stagger(lose, 0.45)
		win.counter_t = 1.0
		win.counter_target = lose
		_fx(mid, ab, true, involved_player)
		VFX.text(mid + Vector3(0, 0.6, 0), "Столкновение!", Color(1.0, 0.9, 0.5), 1.2)
		last = {"kind": "strong", "winner": win, "loser": lose, "pos": mid}
		return true
	# strong vs light: the light strike breaks
	var strong = a if sa >= STRONG else b
	var light = b if strong == a else a
	light.act = {}
	light.set_meta("clash_cancel_until", now + 0.4)
	light.knockback = (light.global_position - strong.global_position).normalized() * 3.5
	_stagger(light, 0.5)
	_fx(mid, ab, false, involved_player)
	VFX.text(mid + Vector3(0, 0.6, 0), "Удар сломлен!", Color(1.0, 0.75, 0.45), 1.0)
	last = {"kind": "break", "winner": strong, "loser": light, "pos": mid}
	return light == a

static func _stagger(x, dur: float) -> void:
	if x.kind == "boss":
		x.statuses["stun"] = {"t": dur * 0.5}
	else:
		x.apply_status("stun", dur)

static func _fx(mid: Vector3, dir: Vector3, big: bool, player: bool) -> void:
	VFX.parry_fx(mid, dir)
	VFX.parry_fx(mid, -dir)
	var mg = VFX.mgr()
	if mg != null:
		mg.shock_v(mid, 2.4 if big else 1.6, Color(1.0, 0.92, 0.7, 0.9), 0.3)
		mg.light(mid, Color(1.0, 0.9, 0.7), 3.5 * Settings.flash_k(), 6.0, 0.18)
		if big:
			mg.emit(mid, {"n": 22, "life": 0.6, "mat": "streak", "col": Color(1.0, 0.85, 0.5), "size": 0.3, "v0": 6.0, "v1": 12.0, "grav": Vector3(0, -8.0, 0), "curve": "shrink", "critical": true})
	Audio.play_sfx("parry_ring", mid, 0.0 if big else -3.0)
	Audio.play_sfx("impact_heavy", mid, -2.0 if big else -6.0)
	if player:
		CombatFeel.hitstop(0.09 if big else 0.05)
		CombatFeel.punch(0.1 if big else 0.06, 0.25)
		CombatFeel.shake(0.25 if big else 0.12)
		if big:
			CombatFeel.slowmo(0.4, 0.18)

## Perfect parry of a boss's heavy attack: the boss reels, a shockwave
## bursts from the blades and the boss stays open for a few seconds.
static func boss_perfect_parry(def, boss) -> void:
	boss_parries += 1
	boss.act = {}
	boss.set_meta("clash_cancel_until", Time.get_ticks_msec() / 1000.0 + 0.5)
	boss.statuses["stun"] = {"t": 1.6}           # bypasses the usual boss stun reduction
	boss.statuses["vulnerable"] = {"t": 3.5}
	var away: Vector3 = boss.global_position - def.global_position
	away.y = 0
	boss.knockback = away.normalized() * 6.0 if away.length() > 0.01 else Vector3.ZERO
	var mid: Vector3 = (def.chest() + boss.chest()) * 0.5
	var mg = VFX.mgr()
	if mg != null:
		mg.shock(def.global_position, 6.0, Color(1.0, 0.9, 0.6), 0.6)
		mg.shock_v(mid, 3.5, Color(1.0, 0.95, 0.75), 0.45)
		mg.light(mid, Color(1.0, 0.9, 0.65), 5.0 * Settings.flash_k(), 9.0, 0.35)
		mg.emit(mid, {"n": 30, "life": 0.8, "mat": "streak", "col": Color(1.0, 0.85, 0.45), "size": 0.35, "v0": 7.0, "v1": 14.0, "grav": Vector3(0, -7.0, 0), "curve": "shrink", "critical": true})
		mg.decal(def.global_position, "crack", 4.0, 18.0, randf() * TAU)
	# the shockwave also pushes the boss's minions away
	for a in Game.actors_near(def.global_position, 6.0):
		if a != def and a != boss and not a.is_dead and Game.is_enemy(def, a):
			var aw: Vector3 = a.global_position - def.global_position
			aw.y = 0
			a.knockback = aw.normalized() * 7.0 if aw.length() > 0.01 else Vector3.ZERO
			a.apply_status("stun", 0.6)
	Audio.play_sfx("parry_ring", mid, 3.0)
	Audio.play_sfx("impact_heavy", mid, 0.0)
	Audio.play_sfx("boss_phase", mid, -6.0)
	VFX.text(mid + Vector3(0, 1.0, 0), "Сокрушающее парирование!", Color(1.0, 0.92, 0.45), 1.5)
	def.counter_t = 2.0
	def.counter_target = boss
	if def.is_player:
		CombatFeel.slowmo(0.25, 0.4)
		CombatFeel.punch(0.16, 0.35)
		CombatFeel.flash(Color(1.0, 0.95, 0.75), 0.25)
		CombatFeel.shake(0.35)
		Profile.add_stat("boss_perfect_parries")
