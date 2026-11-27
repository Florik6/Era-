class_name Cataclysm
## The ten tier-VI spells. Spectacular but readable: every blow is announced
## (runes, telegraphs, a rising core or cloud) before it lands, damage falls
## off towards the edge, and allies are never hurt. One cataclysm at a time
## in the world (AbilityExec.cataclysm_until); the caster is exhausted after.

static var last := {}       # kind -> summary of the last run (tests / reports)

static func run(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var p := AbilityExec._center(a, f, aim)
	p = MagicFX.ground_point(p)
	var r := float(f.get("r", 12.0))
	var kind := str(f.get("kind", "sun"))
	last[kind] = {"pos": p, "r": r, "hits": 0, "t": Time.get_ticks_msec()}
	SpellVFX.fx("cataclysm_start", e, {"a": a, "pos": p, "r": r, "kind": kind})
	match kind:
		"sun": _sun(a, e, f, p, r, power)
		"winter": _winter(a, e, f, p, r, power)
		"storm": _storm(a, e, f, p, r, power)
		"void": _void(a, e, f, p, r, power)
		"rift_seconds": _rift(a, e, f, p, r, power)
		"quake": _quake(a, e, f, p, r, power)
		"march": _march(a, e, f, p, r)
		"dawn": _dawn(a, e, f, p, r)
		"hurricane": _hurricane(a, e, f, p, r, power)
		"verdict": _verdict(a, e, f, p, r, power)

static func _src(a):
	return a if a != null and is_instance_valid(a) and not a.is_dead else null

static func _info(a, e: Dictionary, f: Dictionary, amount: float) -> Dictionary:
	var sch: String = e.school
	return {"amount": amount, "dtype": DBSkills.SCHOOLS[sch].dtype, "school": sch, "melee": false, "knock": 2.0,
		"status": f.get("status", {}).duplicate(), "tier": "ultimate", "ab": e.id, "src": _src(a), "cat_hit": true}

## Damage everyone hostile in r, with falloff to 55% at the edge.
static func _ring_hit(a, e: Dictionary, f: Dictionary, p: Vector3, r: float, amount: float, kind: String, knock_out := 0.0, knock_up := 0.0) -> int:
	var src = _src(a)
	var n := 0
	for t in AbilityExec.enemies_in(src, p, r):
		var d: float = Vector2(t.global_position.x - p.x, t.global_position.z - p.z).length()
		var k := lerpf(1.0, 0.55, clampf(d / maxf(1.0, r), 0.0, 1.0))
		var info := _info(a, e, f, amount * k)
		if knock_out > 0.0 and t.kind != "boss":
			var away: Vector3 = t.global_position - p
			away.y = 0
			t.knockback = (away.normalized() if away.length() > 0.2 else Vector3(1, 0, 0)) * knock_out / maxf(1.0, t._scale())
			info.knock = 0.0
		if knock_up > 0.0 and t.kind != "boss" and t.is_on_floor():
			t.velocity.y = knock_up / maxf(1.0, t._scale())
		if Combat.deal(src, t, info) > 0.0 or float(info.amount) > 0.0:
			n += 1
	if last.has(kind):
		last[kind].hits = int(last[kind].hits) + n
	return n

static func _t(a, secs: float, cb: Callable) -> void:
	AbilityExec._later(a, secs, cb)

# ------------------------------------------------------------------ fire
static func _sun(a, e, f, p: Vector3, r: float, power: float) -> void:
	SpellVFX.fx("sun_core", e, {"pos": p + Vector3(0, 9.0, 0), "dur": 1.2, "r": r})
	_t(a, 1.2 + float(f.get("delay", 0.4)), func():
		SpellVFX.fx("cataclysm_blast", e, {"pos": p, "r": r})
		_ring_hit(a, e, f, p, r, power, "sun", 7.0)
		if f.has("after_zone"):
			var inf := _info(a, e, f, power * 0.05)
			inf.status = {"burn": 6.0}
			Zone.create(str(f.after_zone), _src(a), p, 4.5, 6.0, inf, {"ab": e.id}))

# ------------------------------------------------------------------ ice
static func _winter(a, e, f, p: Vector3, r: float, power: float) -> void:
	var waves := int(f.get("waves", 3))
	for i in waves:
		_t(a, 0.5 + 0.9 * i, func():
			var rr := r * (0.5 + 0.5 * float(i + 1) / float(waves))
			SpellVFX.fx("frost_wave", e, {"pos": p, "r": rr})
			var ff: Dictionary = f.duplicate()
			ff.status = f.get("status", {}) if i == waves - 1 else {"slow": 0.3}
			_ring_hit(a, e, ff, p, rr, power / waves, "winter")
			for k in 4 + 2 * i:
				var an := TAU * k / (4 + 2 * i) + i * 0.4
				StoneStructure.spawn("ice_spike", MagicFX.ground_point(p + Vector3(cos(an), 0, sin(an)) * rr * 0.85), Vector3(cos(an), 0, sin(an)), {"life": 9.0, "solid": false, "scale": 1.1}))
	_t(a, 0.5 + 0.9 * waves, func():
		if f.has("after_zone"):
			Zone.create(str(f.after_zone), _src(a), p, r * 0.6, 6.0, _info(a, e, {"status": {"slow": 0.3}}, power * 0.03), {"ab": e.id}))

# ------------------------------------------------------------------ lightning
static func _storm(a, e, f, p: Vector3, r: float, power: float) -> void:
	SpellVFX.fx("storm_cloud", e, {"pos": p + Vector3(0, 11.0, 0), "r": r, "dur": 6.0})
	var strikes := int(f.get("strikes", 8))
	for i in strikes:
		var final := i == strikes - 1
		_t(a, 0.6 + 0.55 * i, func():
			var tp := p
			if not final:
				var pool := AbilityExec.enemies_in(_src(a), p, r)
				if pool.is_empty():
					var an := randf() * TAU
					tp = p + Vector3(cos(an), 0, sin(an)) * randf_range(1.0, r * 0.8)
				else:
					tp = pool[randi() % pool.size()].global_position
			tp = MagicFX.ground_point(tp)
			var rr := 4.0 if final else 2.4
			SpellVFX.fx("telegraph", e, {"pos": tp, "r": rr, "dur": 0.5, "f": {"sky": true}})
			_t(a, 0.5, func():
				SpellVFX.fx("sky_bolt", e, {"pos": tp, "r": rr, "big": final})
				_ring_hit(a, e, f, tp, rr, power * (2.0 if final else 1.0), "storm")))

# ------------------------------------------------------------------ dark
static func _void(a, e, f, p: Vector3, r: float, power: float) -> void:
	if _src(a) != null:
		SpellVFX.fx("void_crown", e, {"a": a, "dur": 4.0})
	var seals := int(f.get("seals", 6))
	var pool := AbilityExec.enemies_in(_src(a), p, r)
	var pts: Array = []
	for i in seals:
		if i < pool.size():
			pts.append(pool[i].global_position)
		else:
			var an := TAU * i / seals
			pts.append(p + Vector3(cos(an), 0, sin(an)) * r * 0.55)
	for i in pts.size():
		var sp: Vector3 = MagicFX.ground_point(pts[i])
		SpellVFX.fx("telegraph", e, {"pos": sp, "r": 2.6, "dur": 0.8 + 0.35 * i, "f": {}})
		_t(a, 0.8 + 0.35 * i, func():
			SpellVFX.fx("blast", e, {"pos": sp, "r": 2.6, "f": {"big": true}})
			_ring_hit(a, e, f, sp, 2.6, power * 0.35, "void", 4.0))

# ------------------------------------------------------------------ time
static func _rift(a, e, f, p: Vector3, r: float, power: float) -> void:
	var dur := float(f.get("dur", 10.0))
	var z := Zone.create("timeslow", _src(a), p, r, dur, _info(a, e, f, 0.0), {"f": 0.2, "ab": e.id, "haste_allies": true})
	var pulses := int(f.get("pulses", 5))
	for i in pulses:
		_t(a, dur * float(i + 1) / float(pulses + 1), func():
			SpellVFX.fx("time_pulse", e, {"pos": p, "r": r})
			_ring_hit(a, e, f, p, r, power, "rift_seconds"))

# ------------------------------------------------------------------ earth
## «Великое Землетрясение»: runes → rising stones → three readable
## shockwaves with real damage → temporary slabs that change the arena →
## after 10 s everything sinks back.
static func _quake(a, e, f, p: Vector3, r: float, power: float) -> void:
	var waves := int(f.get("waves", 3))
	var plats := int(f.get("platforms", 7))
	var life := 10.0
	var summary: Dictionary = last.quake
	summary.slabs = 0
	summary.waves = 0
	SpellVFX.fx("quake_runes", e, {"pos": p, "r": r, "dur": 1.0 + 0.9 * waves + 1.0})
	# rising stones: slabs pushed up around the area (solid, temporary)
	for i in plats:
		var an := TAU * i / plats + randf() * 0.3
		var sp := MagicFX.ground_point(p + Vector3(cos(an), 0, sin(an)) * r * randf_range(0.45, 0.8))
		_t(a, 0.25 + 0.08 * i, func():
			var s := StoneStructure.spawn("slab", sp, Vector3(cos(an), 0, sin(an)), {"life": life, "solid": true, "hp": 220.0})
			if s:
				summary.slabs = int(summary.slabs) + 1)
	for w in waves:
		_t(a, 1.0 + 0.9 * w, func():
			summary.waves = int(summary.waves) + 1
			SpellVFX.fx("shockwave", e, {"pos": p, "r": r, "i": w})
			var ff: Dictionary = f.duplicate()
			ff.status = f.get("status", {}) if w == 0 else {"stun": 0.4}
			_ring_hit(a, e, ff, p, r, power / waves, "quake", 3.0 + 1.5 * w, 4.0 if w == waves - 1 else 0.0)
			# enemies react: the weak lose their nerve
			for t in AbilityExec.enemies_in(_src(a), p, r + 4.0):
				if t.kind != "boss" and t.level <= (a.level if is_instance_valid(a) else 99) and randf() < 0.4:
					t.apply_status("fear", 2.0)
			for dd in Game.grid.query(p, r * 0.6, "destructible"):
				if is_instance_valid(dd) and dd.has_method("take_hit"):
					dd.take_hit(power * 0.2, "blunt", _src(a)))

# ------------------------------------------------------------------ necro
static func _march(a, e, f, p: Vector3, r: float) -> void:
	if _src(a) == null:
		return
	var life := float(f.get("life", 20.0))
	_t(a, 0.6, func():
		if _src(a) == null:
			return
		var ids := ["spectral_warrior", "bone_warrior", "spectral_warrior", "bone_warrior"]
		var mine := AbilityExec.live_summons(a)
		while mine.size() + ids.size() > AbilityExec.MAX_SUMMONS_PER_OWNER + 2 and not mine.is_empty():
			AbilityExec.despawn(mine.pop_front())
		var n := 0
		for i in ids.size():
			var an := TAU * i / ids.size()
			var out := Spells.summon(a, ids[i], 1, p + Vector3(cos(an), 0, sin(an)) * 3.0, life)
			for m in out:
				m.set_meta("ab", e.id)
				m.max_hp *= 1.0 + 0.04 * a.data.school_level("necro") if a.data else 1.0
				m.hp = m.max_hp
				AbilityExec._summons[a.actor_id] = AbilityExec.live_summons(a) + [m]
				n += 1
		last.march.summons = n
		CityMagic.on_necromancy(a, p))

# ------------------------------------------------------------------ heal
static func _dawn(a, e, f, p: Vector3, r: float) -> void:
	_t(a, 0.3, func():
		var src = _src(a)
		if src == null:
			return
		var n := 0
		for t in AbilityExec.allies_in(src, src.global_position, r):
			t.heal(t.max_hp * 0.6)
			for k in ["bleed", "decay", "wither", "burn", "fear", "stun"]:
				t.statuses.erase(k)
			t._recalc_buffs()
			if t.is_player and Hardcore.active():
				Hardcore.inst.spell_op(t, "dawn", src.data.school_level("heal") if src.data else 10, -1)
			SpellVFX.fx("heal", e, {"a": src, "t": t})
			n += 1
		last.dawn.healed = n
		SpellVFX.fx("dawn_light", e, {"pos": src.global_position, "r": r}))

# ------------------------------------------------------------------ air
static func _hurricane(a, e, f, p: Vector3, r: float, power: float) -> void:
	var dur := float(f.get("dur", 7.0))
	var z := Zone.create("whirl", _src(a), p, r, dur, _info(a, e, f, power * 0.12), {"pull": 4.5, "ab": e.id, "big": true})
	var pulses := int(f.get("pulses", 6))
	for i in pulses:
		_t(a, dur * float(i + 1) / float(pulses + 1), func():
			_ring_hit(a, e, f, p, r, power, "hurricane"))
	_t(a, dur, func():
		SpellVFX.fx("shockwave", e, {"pos": p, "r": r, "i": 0})
		_ring_hit(a, e, f, p, r, power * 0.8, "hurricane", 12.0, 3.0))

# ------------------------------------------------------------------ light
static func _verdict(a, e, f, p: Vector3, r: float, power: float) -> void:
	SpellVFX.fx("heaven_seal", e, {"pos": p + Vector3(0, 12.0, 0), "r": r, "dur": 4.0})
	var strikes := int(f.get("strikes", 8))
	for i in strikes:
		_t(a, 0.6 + 0.3 * i, func():
			var pool := AbilityExec.enemies_in(_src(a), p, r)
			var tp := p + Vector3(cos(i * 0.8), 0, sin(i * 0.8)) * r * 0.5
			if not pool.is_empty():
				tp = pool[i % pool.size()].global_position
			tp = MagicFX.ground_point(tp)
			SpellVFX.fx("ray", e, {"from": p + Vector3(0, 12.0, 0), "to": tp + Vector3(0, 0.5, 0), "big": true})
			_ring_hit(a, e, f, tp, 1.8, power, "verdict"))
	_t(a, 0.6 + 0.3 * strikes + 0.5, func():
		SpellVFX.fx("telegraph", e, {"pos": p, "r": 3.0, "dur": 0.5, "f": {"pillar": true}})
		_t(a, 0.5, func():
			SpellVFX.fx("blast", e, {"pos": p, "r": 3.0, "f": {"pillar": true, "big": true}})
			_ring_hit(a, e, f, p, 3.0, power * 2.0, "verdict")))
