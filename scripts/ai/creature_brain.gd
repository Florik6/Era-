class_name CreatureBrain
extends MonsterBrain
## Behaviour of the «Beasts of the Ages» creatures (on top of MonsterBrain:
## sensing, leash, chase, summons following owners).
##   predator    hunts the player AND weaker creatures, retreats badly hurt
##   territorial warns first (growl, "!"), attacks only if you stay / come close
##   herd        moves as a group; when one is hurt the group bolts
##   ambush      hides (low, stealthed) and strikes from close range
##   magic       keeps distance and casts its school's spells
##   construct   patrols its post, ignores fear, never flees
##   swarm       many weak bodies, erratic flanking
## Peaceful species (deer, forest spirits, ents) are neutral until attacked.
## Specials (from the species data): web, poison, howl, pounce, burrow,
## shock, breath, dive, blink, explode, regen, slam, charge, root, steam,
## drain, pull, blind. Everything is time-limited and capped.

var sp: Dictionary = {}
var beh := "predator"
var warn_t := 0.0
var warned := false
var flee_t := 0.0
var spec_cd := 0.0
var hidden := false
var _burrowed := false
var asleep := false
var _voiced := false
## the cry a species gives when it spots its prey (by body plan)
const VOICE := {"blob": "slime", "insect": "buzz", "arach": "shriek", "flyer": "wing_flap", "quad": "growl", "drake": "beast_roar",
	"giant": "beast_roar", "worm": "rock_crumble", "tree": "wood_break", "construct": "robot_hit", "orb": "resonance_hum"}

func _init(mon) -> void:
	super._init(mon)
	sp = DBCreatures.get_def(str(mon.get_meta("species", mon.def_id))) if mon.has_meta("species") else {}

func _species() -> Dictionary:
	if sp.is_empty() and m.has_meta("species"):
		sp = DBCreatures.get_def(str(m.get_meta("species")))
		beh = str(sp.get("beh", "predator"))
	return sp

func has_abil(a: String) -> bool:
	return a in _species().get("abil", [])

func tick(delta: float) -> void:
	_species()
	spec_cd -= delta
	flee_t -= delta
	if m.is_dead:
		return
	# sleeping creatures: night, nothing around (wake on damage — see actor aggro)
	if asleep:
		m.move_input = Vector3.ZERO
		if not m.aggro.is_empty() or not Game.is_night():
			asleep = false
			m.statuses.erase("sleep")
		return
	super.tick(delta)

func _think() -> void:
	_species()
	var own = _owner()
	if own != null:
		super._think()
		return
	# peaceful species only fight back
	if sp.get("beh_peaceful", false) and m.aggro.is_empty():
		target = null
		if beh == "herd" or true:
			_flee_from_threats()
		if Game.is_night() and randf() < 0.05 and beh in ["herd", "territorial"]:
			asleep = true
			m.apply_status("sleep", 999.0)
		return
	# predators also hunt weaker creatures around them
	if beh == "predator" and target == null and randf() < 0.3:
		for a in Game.actors_near(m.global_position, 14.0):
			if a == m or a.is_dead or a.team != "wildlife":
				continue
			if a.max_hp < m.max_hp * 0.9:
				target = a
				m.add_aggro(a, 20.0)
				break
	super._think()
	if target != null and not _voiced:
		_voiced = true
		var pl_n: String = str(sp.get("plan", ""))
		if VOICE.has(pl_n) and Audio.has_sfx(VOICE[pl_n]):
			Audio.play_sfx(VOICE[pl_n], m.global_position, -5.0)
	elif target == null:
		_voiced = false
	if target != null and beh == "territorial" and not warned and m.aggro.is_empty():
		var d: float = target.global_position.distance_to(m.global_position)
		if d > 5.0:
			# a warning before the attack
			warned = true
			warn_t = 3.0
			VFX.text(m.chest() + Vector3(0, 1.0, 0), "!", Color(1.0, 0.7, 0.2), 1.4)
			Audio.play_sfx("growl", m.global_position, -4.0)

func _flee_from_threats() -> void:
	for a in Game.actors_near(m.global_position, 9.0):
		if a == m or a.is_dead:
			continue
		if a.is_player or a.team in ["monster", "bandit"]:
			var away: Vector3 = m.global_position - a.global_position
			away.y = 0
			m.move_input = away.normalized()
			return
	m.move_input = Vector3.ZERO

func _act(delta: float) -> void:
	_species()
	if _owner() != null or sp.is_empty():
		super._act(delta)
		return
	var t = target
	# territorial warning: wait a moment unless the intruder comes close
	if t != null and beh == "territorial" and warned and warn_t > 0.0 and m.aggro.is_empty():
		warn_t -= delta
		var d0: float = t.global_position.distance_to(m.global_position)
		if d0 > 4.0:
			m.move_input = Vector3.ZERO
			m.face_dir((t.global_position - m.global_position).normalized())
			return
	# badly hurt predators and herds run
	var hpf: float = m.hp / maxf(1.0, m.max_hp)
	if beh in ["predator", "herd", "swarm"] and hpf < 0.22 and flee_t < -6.0:
		flee_t = 4.0
		if beh == "herd":
			for a in Game.actors_near(m.global_position, 12.0):
				if a != m and not a.is_dead and a.get_meta("species", "") == m.get_meta("species", "") and a.brain is CreatureBrain:
					a.brain.flee_t = 4.0
					a.brain.target = t
	if flee_t > 0.0 and t != null and is_instance_valid(t):
		var away: Vector3 = m.global_position - t.global_position
		away.y = 0
		m.move_input = away.normalized()
		return
	# ambushers wait hidden until the prey is close
	if beh == "ambush" and t != null and is_instance_valid(t):
		var da: float = t.global_position.distance_to(m.global_position)
		if da > 6.0 and m.aggro.is_empty():
			if not hidden:
				hidden = true
				m.apply_status("stealth", 30.0)
			m.move_input = Vector3.ZERO
			return
		if hidden:
			hidden = false
			m.statuses.erase("stealth")
			_special_pounce(t, true)
	if t != null and is_instance_valid(t) and not t.is_dead and spec_cd <= 0.0:
		_try_special(t)
	super._act(delta)

func _try_special(t) -> void:
	var d: float = t.global_position.distance_to(m.global_position)
	var abil: Array = sp.get("abil", [])
	if abil.is_empty():
		return
	abil = abil.duplicate()
	abil.shuffle()
	for a in abil:
		var used := true
		match a:
			"pounce", "dive":
				if d > 3.5 and d < 10.0:
					_special_pounce(t, false)
				else:
					used = false
			"charge":
				if d > 4.0 and d < 12.0:
					_special_pounce(t, false)
				else:
					used = false
			"web":
				if d < 12.0:
					Zone.create("mud", m, t.global_position, 2.5, 5.0, {"amount": 0.0, "status": {"slow": 0.35}}, {"no_res": true})
					VFX.burst(t.global_position + Vector3(0, 0.3, 0), Color(0.9, 0.9, 0.9), 10, 0.3)
				else:
					used = false
			"howl":
				Audio.play_sfx("wolf", m.global_position, -2.0)
				for o in Game.actors_near(m.global_position, 22.0):
					if o != m and not o.is_dead and o.get("brain") is MonsterBrain and o.brain.target == null and o.team == m.team:
						o.brain.target = t
			"burrow":
				if d < 14.0 and not _burrowed:
					_special_burrow(t)
				else:
					used = false
			"shock":
				if d < 4.0:
					VFX.lightning(m.chest(), t.chest(), Color(0.6, 0.8, 1.0), 0.15, 0.06, 1)
					Combat.deal(m, t, {"amount": m.base_dmg * 0.8, "dtype": "lightning", "status": {"stun": 0.3}, "src": m})
				else:
					used = false
			"breath":
				if d < 7.0:
					_special_breath(t)
				else:
					used = false
			"blink":
				if d > 3.0 and d < 16.0:
					var p: Vector3 = t.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
					MagicFX.blink_out(m, "time")
					m.global_position = Spells._safe_dest(m, p)
					MagicFX.blink_in(m, p, "time")
				else:
					used = false
			"regen":
				if m.hp < m.max_hp * 0.5:
					m.apply_status("regen_hot", 4.0, {"hot": m.max_hp * 0.03})
					VFX.burst(m.chest(), Color(0.5, 1.0, 0.5), 8, 0.3)
				else:
					used = false
			"slam", "root", "steam":
				if d < 4.5:
					var r := 3.5
					VFX.telegraph(m.global_position, r, 0.6, Color(1.0, 0.4, 0.2))
					var mm = m
					m.get_tree().create_timer(0.6, false).timeout.connect(func():
						if is_instance_valid(mm) and not mm.is_dead:
							VFX.ground_impact(mm.global_position, r)
							var st: Dictionary = {"stun": 0.4} if a == "slam" else ({"root": 1.5} if a == "root" else {"burn": 4.0})
							Combat.aoe(mm, mm.global_position, r, {"amount": mm.base_dmg * 1.2, "dtype": "blunt" if a != "steam" else "fire", "status": st, "src": mm}))
				else:
					used = false
			"drain":
				if d < 3.0:
					var got: float = Combat.deal(m, t, {"amount": m.base_dmg * 0.6, "dtype": str(m.natural_dtype), "src": m})
					m.heal(got)
				else:
					used = false
			"pull":
				if d < 10.0 and t.kind != "boss":
					var to: Vector3 = m.global_position - t.global_position
					to.y = 0
					t.knockback = to.normalized() * 7.0
					VFX.beam(m.chest(), t.chest(), Color(0.7, 0.5, 1.0), 0.3, 0.1)
				else:
					used = false
			"blind":
				if d < 3.0:
					t.apply_status("blind", 2.5)
				else:
					used = false
			_:
				used = false
		if used:
			spec_cd = randf_range(4.0, 7.0)
			return
	spec_cd = 1.5

func _special_pounce(t, ambush: bool) -> void:
	var start: Vector3 = m.global_position
	var to: Vector3 = t.global_position - start
	to.y = 0
	var dest: Vector3 = Spells._safe_dest(m, t.global_position - to.normalized() * 1.2)
	m.face_dir(to.normalized())
	if m.rig:
		m.rig.trigger("attack")
	var tw: Tween = m.create_tween()
	tw.tween_property(m, "global_position", dest, 0.25).set_trans(Tween.TRANS_QUAD)
	var mm = m
	m.get_tree().create_timer(0.25, false).timeout.connect(func():
		if is_instance_valid(mm) and not mm.is_dead and is_instance_valid(t) and not t.is_dead and t.global_position.distance_to(mm.global_position) < 2.6:
			Combat.deal(mm, t, {"amount": mm.base_dmg * (1.8 if ambush else 1.3), "dtype": str(mm.natural_dtype), "melee": true, "knock": 3.0, "src": mm,
				"hit_pos": t.chest() + Vector3(0, -0.5 if mm.rig and str(mm.rig.get("plan")) in ["quad", "arach", "insect", "worm"] else 0.2, 0)}))

func _special_burrow(t) -> void:
	_burrowed = true
	m.apply_status("invuln", 1.6)
	VFX.burst(m.global_position, Color(0.5, 0.42, 0.32), 14, 0.35)
	if m.rig:
		m.rig.visible = false
	var mm = m
	m.get_tree().create_timer(1.4, false).timeout.connect(func():
		if not is_instance_valid(mm) or mm.is_dead:
			return
		var p: Vector3 = t.global_position if is_instance_valid(t) else mm.global_position
		VFX.telegraph(p, 2.5, 0.5, Color(0.8, 0.5, 0.3))
		mm.get_tree().create_timer(0.5, false).timeout.connect(func():
			if not is_instance_valid(mm) or mm.is_dead:
				return
			mm.global_position = Spells._safe_dest(mm, p)
			if mm.rig:
				mm.rig.visible = true
			VFX.ground_impact(p, 2.5)
			Combat.aoe(mm, p, 2.5, {"amount": mm.base_dmg * 1.5, "dtype": "pierce", "status": {"stun": 0.4}, "src": mm, "knock": 4.0})
			if mm.brain is CreatureBrain:
				mm.brain._burrowed = false))

func _special_breath(t) -> void:
	var dir: Vector3 = (t.global_position - m.global_position)
	dir.y = 0
	dir = dir.normalized()
	m.face_dir(dir)
	VFX.telegraph(m.global_position, 6.0, 0.5, Color(1.0, 0.4, 0.1), "cone", dir, 60.0)
	var mm = m
	var dt: String = str(m.natural_dtype) if str(m.natural_dtype) in ["fire", "ice", "lightning", "energy", "poison", "time", "dark"] else "fire"
	m.get_tree().create_timer(0.5, false).timeout.connect(func():
		if not is_instance_valid(mm) or mm.is_dead:
			return
		var o: Vector3 = mm.chest() + dir * 0.8
		if VFX.mgr() != null:
			VFX.mgr().emit(o, {"n": 24, "life": 0.5, "mat": "add", "ramp": "fire" if dt == "fire" else "fade", "col": Combat.element_color(dt), "size": 0.7, "v0": 7.0, "v1": 12.0, "dir": dir, "spread": 30.0, "grav": Vector3.ZERO, "damp": 2.0})
		for a in Game.actors_near(mm.global_position, 6.5):
			if a == mm or a.is_dead or not Game.can_damage(mm, a):
				continue
			var to2: Vector3 = a.global_position - mm.global_position
			to2.y = 0
			if to2.length() < 6.5 and dir.angle_to(to2.normalized()) < deg_to_rad(32.0):
				Combat.deal(mm, a, {"amount": mm.base_dmg * 1.1, "dtype": dt, "status": {"burn": 4.0} if dt == "fire" else {}, "src": mm}))
