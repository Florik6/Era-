class_name AbilityExec
## «Ascension of Power»: runs the 200 data-driven abilities of DBAbilities.
## One entry = requirements + costs + cast time + cool-down + a list of
## components ("fx"). Each component is a small, reusable piece of game logic
## (projectile, beam, area, aura, summon, buff, debuff, heal, movement,
## terrain …), so a new ability is mostly data. Visuals go through SpellVFX
## and never feed back into the rules.

const MAX_SUMMONS_PER_OWNER := 4
const MAX_SUMMONS_WORLD := 24
const MAX_TERRAIN := 40
const CATACLYSM_EXHAUST := 14.0
const ARCHMAGE_EXHAUST := 4.0
const HIGH_WINDOW := 6.0        # an archmage spell "occupies" its caster this long after the cast
const COST_FLOOR := 0.6         # all cost reductions together: at most −40 %

static var _last := {}          # actor_id -> {"id", "aim"} — last spell (for «Зеркало мгновения»)
static var _sustain := {}       # actor_id -> [[ability id, status key]]
static var _summons := {}       # actor_id -> [summoned actors]
static var _orbs := {}          # actor_id -> light orb node
static var deaths: Array = []   # [[position, msec]] recent deaths (necromancy)
static var cataclysm_until := 0 # msec: one cataclysm at a time in the world
static var cataclysm_by = null  # who cast the active one
static var stats := {"casts": 0, "by_id": {}, "summons": 0, "terrain": 0, "cataclysms": 0}
static var last_reveal := {}    # actor_id -> number of things revealed
static var _high_until := {}    # actor_id -> msec: an archmage/cataclysm spell is still active

# ===================================================================== use
## Why `a` cannot use ability `id` right now ("" = it can).
static func block_reason(a: Actor, id: String, aim := Vector3.ZERO) -> String:
	var e: Dictionary = DBAbilities.get_ab(id)
	if e.is_empty() or e.type != "active":
		return "это не активное умение"
	if a.data != null and not a.data.knows_ability(id):
		return "умение не изучено"
	if a.skill_cd.has(id):
		return "перезарядка %.1f с" % float(a.skill_cd[id])
	if a.statuses.has("silenced"):
		return "безмолвие"
	if e.kind == "weapon" and a.mastery_cat() != e.cat:
		return "нужно оружие: %s" % ItemDB.CAT_NAMES.get(e.cat, e.cat)
	var tk := TechKnow.skill_block(a, e)
	if tk != "":
		return tk
	var st := stamina_cost(a, e)
	var mn := mana_cost(a, e)
	if a.stamina < st:
		return "недостаточно выносливости"
	if a.mana < mn:
		return "недостаточно маны (%d / %d)" % [int(a.mana), int(mn)]
	var rounds := Ammo.ability_rounds(a, e)
	if rounds > 0:
		if a.reload_t > 0.0 and a.ammo <= 0:
			return "идёт перезарядка"
		if not Ammo.can_fire(a, 1):
			return "нет боеприпасов" if not Ammo.has_mag(a.weapon_base()) or Ammo.reserve(a) <= 0 else "магазин пуст — перезарядитесь"
	if int(e.get("tier", 0)) >= 5:
		if a.statuses.has("exhausted"):
			return "маг истощён (%.0f с)" % ceilf(float(a.statuses.exhausted.get("t", 0.0)))
		if int(_high_until.get(a.actor_id, 0)) > Time.get_ticks_msec():
			return "высшее заклинание ещё действует"
	if int(e.get("tier", 0)) == 6:
		var r := _cataclysm_block(a, e)
		if r != "":
			return r
	if _needs_target(e) and _pick_target(a, e, aim if aim.length() > 0.01 else a.facing) == null:
		return "нет цели"
	return ""

static func use(a: Actor, id: String, aim: Vector3) -> bool:
	var e: Dictionary = DBAbilities.get_ab(id)
	if e.is_empty() or a == null or a.is_dead:
		return false
	if a.data == null:
		return cast_free(a, id, aim, float(e.get("dmg", 20.0)) * (1.0 + 0.09 * (a.level - 1)))
	if aim.length() < 0.01:
		aim = a.facing
	aim.y = 0
	aim = aim.normalized()
	var why := block_reason(a, id, aim)
	if why != "":
		if why.begins_with("недостаточно маны"):
			ManaSys.refused(a)
		if a.is_player:
			Events.notify.emit("%s: %s" % [e.name, why], Color(0.9, 0.8, 0.45))
			Audio.play_sfx("error")
		return false
	a.stamina -= stamina_cost(a, e)
	var mc := mana_cost(a, e)
	a.mana = maxf(0.0, a.mana - mc)
	ManaSys.on_spent(a, mc, int(e.get("tier", 0)))
	if Ammo.ability_rounds(a, e) > 0:
		Ammo.cancel_reload(a)          # the skill fires what is in the magazine
	if int(e.get("tier", 0)) == 6 and a.is_player:
		a.data.inv.consume(cataclysm_reagent())
	a.skill_cd[id] = cooldown(a, e)
	_start(a, e, aim, spell_power(a, e) if e.kind == "spell" else 1.0, false)
	return true

## Healing from the anatomy / healing panel: the chosen injury is treated
## at once (the time spent in the menu is the casting), costs and cool-down
## are paid as usual. Returns "" or the reason it was refused.
static func cast_heal_now(a: Actor, id: String, injury_id: int) -> String:
	var e: Dictionary = DBAbilities.get_ab(id)
	if e.is_empty() or e.get("school", "") != "heal":
		return "это не заклинание исцеления"
	var why := block_reason(a, id)
	if why != "":
		return why
	var mc := mana_cost(a, e)
	a.mana = maxf(0.0, a.mana - mc)
	a.skill_cd[id] = cooldown(a, e)
	a.set_meta("heal_pick", injury_id)
	a.set_meta("heal_paid", [id, mc])
	stats.casts += 1
	_run(a, e, a.facing, spell_power(a, e), false)
	a.remove_meta("heal_paid")
	# Hardcore: a treatment the body refused (wrong injury, nothing to treat)
	# gives the mana and the cool-down back — only a real result is paid for.
	if a.has_meta("heal_refund"):
		var why2: String = str(a.get_meta("heal_refund"))
		a.remove_meta("heal_refund")
		ManaSys.restore(a, mc)
		a.skill_cd.erase(id)
		return why2 if why2 != "" else "лечение не подействовало"
	ManaSys.on_spent(a, mc, int(e.get("tier", 0)))
	if a.data != null:
		a.data.add_school_xp("heal", 3.0 + 1.5 * int(e.tier))
	return ""

## Monsters / bosses / scripted casters: no mana, no requirements.
static func cast_free(a: Actor, id: String, aim: Vector3, power: float) -> bool:
	var e: Dictionary = DBAbilities.get_ab(id)
	if e.is_empty() or a == null or a.is_dead or a.skill_cd.has(id) or a.busy() or not a.can_act():
		return false
	if int(e.get("tier", 0)) == 6 and Time.get_ticks_msec() < cataclysm_until:
		return false
	if int(e.get("tier", 0)) >= 5 and (a.statuses.has("exhausted") or int(_high_until.get(a.actor_id, 0)) > Time.get_ticks_msec()):
		return false      # bosses and monsters obey the archmage limits too
	if aim.length() < 0.01:
		aim = a.facing
	aim.y = 0
	aim = aim.normalized()
	if _needs_target(e) and _pick_target(a, e, aim) == null:
		return false
	a.skill_cd[id] = float(e.get("cd", 4.0)) * 1.4 + 0.5
	_start(a, e, aim, power, true)
	return true

static func _start(a: Actor, e: Dictionary, aim: Vector3, power: float, free: bool) -> void:
	a.face_dir(aim)
	a.combat_t = 0.0
	var ct := cast_time(a, e)
	var anim: String = e.get("anim", "cast" if e.kind == "spell" else _default_anim(e))
	var tier: int = int(e.get("tier", 0))
	var steady: bool = tier >= 5 and a.hook("high_focus") > 0.0
	var payload := {"anim": anim, "ab": e.id, "steady": steady, "cb": func(): _run(a, e, aim, power, free)}
	var nm := "spell" if e.kind == "spell" else "skill"
	if ct > 0.06:
		a.start_action(nm, ct + 0.25, ct / (ct + 0.25), payload)
		SpellVFX.fx("charge", e, {"a": a, "dur": ct})
	else:
		a.start_action(nm, 0.38, 0.3, payload)
	if tier >= 5:
		_high_until[a.actor_id] = Time.get_ticks_msec() + int((ct + HIGH_WINDOW) * 1000.0)
	if tier == 6:
		cataclysm_until = Time.get_ticks_msec() + int((ct + 12.0) * 1000.0)
		cataclysm_by = a
		stats.cataclysms += 1
		CityMagic.on_cast(a, e, a.global_position + aim * 10.0)
	elif e.kind == "spell":
		CityMagic.on_cast(a, e, a.global_position + aim * 6.0)
	stats.casts += 1
	stats.by_id[e.id] = int(stats.by_id.get(e.id, 0)) + 1
	if e.kind == "spell" and a.data != null:
		a._last_cast_ms = Time.get_ticks_msec()
		if not free:
			a.data.add_school_xp(e.school, 3.0 + 1.5 * tier)
			if a.is_player:
				Profile.add_stat("spells")
		if e.id != "t_instant_mirror" and tier <= 4:
			_last[a.actor_id] = {"id": e.id, "aim": aim}

static func _default_anim(e: Dictionary) -> String:
	for f in e.fx:
		match str(f.c):
			"melee":
				return str(f.get("anim", "slash"))
			"melee_seq":
				return str(f.seq[0][0])
			"shots", "sky_volley":
				return "shoot"
			"move", "behind":
				return "thrust"
			"nova", "blast":
				return "slam"
	return "cast"

# ===================================================================== costs
static func stamina_cost(a: Actor, e: Dictionary) -> float:
	return float(e.get("stamina", 0.0))

static func mana_cost(a: Actor, e: Dictionary) -> float:
	var m := float(e.get("mana", 0.0))
	if e.kind != "spell":
		return m
	var tier: int = int(e.tier)
	if tier <= 2:
		m *= 1.0 - a.hook("mana_weak")
	if tier >= 5:
		m *= 1.0 - a.hook("high_focus")
	if a.weapon_cat() == "staff":
		m *= 1.0 - 0.5 * a.hook("conduit")
	if e.school == "necro" and a.statuses.has("liturgy"):
		m *= 0.7
	if e.id == "n_raise_servant" and near_recent_death(a.global_position, 10.0):
		m *= 0.6
	if a.data != null and a.data.school_level(e.school) >= int(e.slvl) + 6:
		m *= 0.9
	# discounts multiply, but never below COST_FLOOR of the price
	return roundf(maxf(m, float(e.get("mana", 0.0)) * COST_FLOOR))

static func cooldown(a: Actor, e: Dictionary) -> float:
	var cd := float(e.get("cd", 2.0))
	if e.kind == "spell" and int(e.tier) <= 4 and a.hook("catalyst") > 0.0:
		cd *= 0.85
	return cd

static func cast_time(a: Actor, e: Dictionary) -> float:
	var ct := float(e.get("cast", 0.0))
	if e.kind == "spell":
		if int(e.tier) <= 2:
			ct *= 1.0 - a.hook("quick_cast")
		if a.hook("catalyst") > 0.0:
			ct *= 0.9
	return ct

## Spell power before Combat.deal (which then adds the school level, the
## magic stat of items/talents/artifacts and the character level bonus).
static func spell_power(a: Actor, e: Dictionary) -> float:
	var p := power_parts(a, e)
	return float(p.total)

## All factors of a spell's power, for the skill screen and tests.
static func power_parts(a: Actor, e: Dictionary) -> Dictionary:
	var out := {"base": float(e.get("dmg", 0.0))}
	out.level = 1.0 + 0.12 * (a.level - 1)
	var talent := 1.0
	if a.weapon_cat() == "staff":
		talent += a.hook("conduit")
	for k in a.statuses:
		var sp = a.statuses[k].get("school_pow")
		if sp is Dictionary:
			talent += float(sp.get(e.get("school", ""), 0.0))
	out.talent = talent
	var focus := 0.9
	if a.weapon_cat() == "staff":
		var w := a.weapon()
		focus = 1.0 + minf(0.35, ItemDB.stat(w, "dmg") / 300.0) + 0.03 * int(w.get("rarity", 0))
	out.focus = focus
	var rank := a.data.magic_rank() if a.data != null else 2
	out.rank = 1.0 + 0.03 * rank
	out.charge = 1.3 if a.statuses.has("seal_charge") else 1.0
	# shown only (applied inside Combat.deal):
	if a.data != null:
		var sl := a.data.school_level(str(e.get("school", "")))
		out.school = (1.0 + 0.05 * sl) * (1.1 if sl >= 3 else 1.0)
		out.magic = 1.0 + a.stat("spell")
	out.total = out.base * out.level * out.talent * out.focus * out.rank * out.charge
	return out

# =============================================================== cataclysm
static func cataclysm_reagent() -> String:
	var era := 0
	if Game.world and Game.world.get("era") != null:
		era = int(Game.world.era)
	return DBAbilities.CATACLYSM_REAGENT[clampi(era, 0, DBAbilities.CATACLYSM_REAGENT.size() - 1)]

static func _cataclysm_block(a: Actor, e: Dictionary) -> String:
	if Time.get_ticks_msec() < cataclysm_until:
		return "другой катаклизм ещё не утих"
	if a.statuses.has("exhausted"):
		return "маг истощён"
	if a.data != null:
		if not e.id in a.data.prepared_cataclysms():
			return "катаклизм не подготовлен в наборе"
		if a.is_player and a.data.inv.count(cataclysm_reagent()) <= 0:
			return "нужен реагент: %s" % ItemDB.base(cataclysm_reagent()).get("name", cataclysm_reagent())
	return ""

static func _exhaust(a: Actor, secs: float) -> void:
	if a == null or not is_instance_valid(a) or a.is_dead:
		return
	a.apply_status("exhausted", secs * (1.0 - a.hook("recoil")))

# ================================================================ targets
static func _needs_target(e: Dictionary) -> bool:
	for f in e.fx:
		if (f.c == "debuff" and f.get("to", "") == "target") or f.c == "behind" or (f.c == "blast" and f.get("at", "") == "target"):
			return true
	return false

static func _pick_target(a: Actor, e: Dictionary, aim: Vector3) -> Actor:
	for f in e.fx:
		if f.c in ["debuff", "behind", "blast"]:
			return Spells._target(a, aim if aim.length() > 0.01 else a.facing, float(f.get("rng", 8.0)), 75.0)
	return null

static func is_ally(a, b) -> bool:
	if b == null or a == null or not is_instance_valid(b) or b.is_dead:
		return false
	if b == a:
		return true
	if Game.is_enemy(a, b) or Game.can_damage(a, b):
		return false
	if b.team in ["monster", "boss"] and not a.team in ["monster", "boss"]:
		return false
	return true

static func enemies_in(a: Actor, center: Vector3, r: float) -> Array:
	var out: Array = []
	for t in Game.actors_near(center, r + 1.0):
		if t == a or t.is_dead:
			continue
		if a != null and is_instance_valid(a) and not Game.can_damage(a, t):
			continue
		var d: float = Vector2(t.global_position.x - center.x, t.global_position.z - center.z).length() - t.radius()
		if d <= r and absf(t.global_position.y - center.y) < 4.0:
			out.append(t)
	return out

static func allies_in(a: Actor, center: Vector3, r: float) -> Array:
	var out: Array = []
	for t in Game.actors_near(center, r + 1.0):
		if t.global_position.distance_to(center) <= r + t.radius() and is_ally(a, t):
			out.append(t)
	return out

static func _center(a: Actor, f: Dictionary, aim: Vector3) -> Vector3:
	match str(f.get("at", "self")):
		"aim":
			return Spells._aim_point(a, aim, float(f.get("rng", 12.0)))
		"target":
			var t := Spells._target(a, aim, float(f.get("rng", 12.0)), 75.0)
			return t.global_position if t else a.global_position + aim * float(f.get("rng", 12.0)) * 0.5
		"front":
			return a.global_position + aim * float(f.get("dist", 2.0))
	return a.global_position

# ============================================================== info / dmg
static func _info(a: Actor, e: Dictionary, f: Dictionary, power: float) -> Dictionary:
	var mult := float(f.get("mult", 1.0))
	var info: Dictionary
	if f.get("wpn", false) or e.kind != "spell":
		info = Combat.weapon_info(a, mult) if a.data != null or a.kind == "humanoid" else {"amount": a.base_dmg * mult, "dtype": a.natural_dtype, "status": {}}
		if f.get("school", "") == "best" and a.data != null and a.data.best_school() != "":
			var bs: String = a.data.best_school()
			info.dtype = DBSkills.SCHOOLS[bs].dtype
			info.school = bs
	else:
		var sch: String = e.school
		info = {"amount": power * mult, "dtype": DBSkills.SCHOOLS[sch].dtype, "school": sch, "melee": false, "knock": 1.0, "status": {}}
		info.tier = "ultimate" if int(e.tier) >= 5 else ("empowered" if a.data != null and a.data.school_level(sch) >= 6 else "normal")
	info.src = a
	info.ab = e.id
	if f.has("status") and f.status is Dictionary:
		var st: Dictionary = info.get("status", {}).duplicate()
		for k in f.status:
			st[k] = f.status[k]
		info.status = st
	if f.has("knock"):
		info.knock = float(f.knock)
	if e.kind != "spell" and float(e.get("cast", 0.0)) > 0.0 and a.hook("full_draw") > 0.0:
		info.amount *= 1.0 + a.hook("full_draw")
	return info

## Deal damage, or (zero-damage effects) just apply the statuses.
static func _hit(a: Actor, t: Actor, info: Dictionary) -> float:
	if float(info.get("amount", 0.0)) <= 0.0:
		if a != null and is_instance_valid(a) and not Game.can_damage(a, t):
			return 0.0
		apply_statuses(t, info.get("status", {}), a)
		t.add_aggro(a)
		return 0.0
	return Combat.deal(a, t, info.duplicate())

static func apply_statuses(t: Actor, st: Dictionary, src) -> void:
	for k in st:
		var v = st[k]
		match k:
			"burn":
				t.apply_status("burn", 4.0, {"dps": float(v), "src": src})
			"slow":
				t.apply_status("slow", 2.5, {"f": float(v)})
			"bleed", "decay":
				t.apply_status(k, 5.0, {"dot": float(v), "dtype": "slash" if k == "bleed" else "dark", "src": src})
			"weakness":
				t.apply_status("weakness", float(v), {"mods": {"dmg_pct": -0.25}})
			"suppressed":
				t.apply_status("suppressed", float(v), {"mods": {"dmg_pct": -0.2, "speed": -0.35}})
			"fear":
				if t.kind != "boss":
					t.apply_status("fear", float(v))
			_:
				t.apply_status(k, float(v))

# ================================================================== run
static func _run(a: Actor, e: Dictionary, aim: Vector3, power: float, free: bool) -> void:
	if a == null or not is_instance_valid(a) or a.is_dead:
		return
	if e.kind == "spell":
		SpellVFX.fx("release", e, {"a": a, "aim": aim})
		if a.statuses.has("seal_charge"):
			var sc: Dictionary = a.statuses.seal_charge
			sc.charges = int(sc.get("charges", 1)) - 1
			if int(sc.charges) <= 0:
				a.statuses.erase("seal_charge")
	if e.get("sustain", false):
		_sustain_take(a, e)
	var t := 0.0
	var moved := false
	for f in e.fx:
		var delay := float(f.get("t", 0.0))
		if f.c in ["melee", "melee_seq", "nova"] and moved:
			delay = maxf(delay, 0.16)
		if f.c in ["move", "behind"]:
			moved = true
		if delay > 0.0:
			var ff: Dictionary = f
			a.get_tree().create_timer(delay, false).timeout.connect(func():
				if is_instance_valid(a) and not a.is_dead:
					_component(a, e, ff, aim, power))
		else:
			_component(a, e, f, aim, power)
	if e.get("sfx", "") != "":
		Audio.play_sfx(str(e.sfx), a.global_position, -2.0 if a.is_player else -6.0)
	match int(e.get("tier", 0)):
		5:
			_exhaust(a, ARCHMAGE_EXHAUST)
		6:
			_exhaust(a, CATACLYSM_EXHAUST)

## Magical Resonance: spell effects leave elemental imprints where they land.
static func _imprint(a, e: Dictionary, pos: Vector3, info: Dictionary, r: float) -> void:
	if e.kind != "spell" or Resonance.inst == null:
		return
	Resonance.from_spell(a if (a != null and is_instance_valid(a)) else null, e.id, pos, info, r)

static func _component(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	match str(f.c):
		"move": _c_move(a, e, f, aim, power)
		"behind": _c_behind(a, e, f, aim)
		"melee": _c_melee(a, e, f, power)
		"melee_seq": _c_melee_seq(a, e, f, power)
		"shots": _c_shots(a, e, f, aim, power)
		"sky_volley": _c_sky_volley(a, e, f, power)
		"shadow_dance": _c_shadow_dance(a, e, f, power)
		"proj": _c_proj(a, e, f, aim, power)
		"bolt": _c_bolt(a, e, f, aim, power)
		"beam": _c_beam(a, e, f, aim, power)
		"cone": _c_cone(a, e, f, aim, power)
		"nova": _c_nova(a, e, f, power)
		"blast": _c_blast(a, e, f, aim, power)
		"wave": _c_wave(a, e, f, aim, power)
		"chain": _c_chain(a, e, f, aim, power)
		"rays": _c_rays(a, e, f, power)
		"fissures": _c_fissures(a, e, f, aim, power)
		"zone": _c_zone(a, e, f, aim, power)
		"buff": _c_buff(a, e, f)
		"debuff": _c_debuff(a, e, f, aim)
		"shield": _c_shield(a, e, f)
		"heal": _c_heal(a, e, f)
		"push": _c_push(a, e, f)
		"mirror": _c_mirror(a, e, f)
		"summon": _c_summon(a, e, f, aim)
		"terrain": _c_terrain(a, e, f, aim, power)
		"decoy": _c_decoy(a, e, f, power)
		"prop": SpellVFX.fx("banner", e, {"a": a, "pos": a.global_position + a.facing * 0.8, "life": float(f.get("life", 10.0))})
		"light_orb": _c_light_orb(a, e, f)
		"reveal": _c_reveal(a, e, f)
		"cataclysm": Cataclysm.run(a, e, f, aim, power)

# ============================================================ components
static func _c_move(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var kind := str(f.get("kind", "dash"))
	var dist := float(f.get("dist", 5.0))
	var dir := aim
	if kind == "side":
		dir = aim.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	var start := a.global_position
	var dest := Spells._safe_dest(a, start + dir * dist)
	if float(f.get("invuln", 0.0)) > 0.0:
		a.apply_status("invuln", float(f.invuln))
	if kind in ["dash", "side"] and a.statuses.has("root"):
		dest = start          # rooted: the body cannot slide (magic blinks still work)
	if kind in ["blink", "blink_path"]:
		SpellVFX.fx("blink_out", e, {"a": a})
		a.global_position = dest
		if a.has_method("reset_physics_interpolation"):
			a.reset_physics_interpolation()
		SpellVFX.fx("blink_in", e, {"a": a, "from": start})
	else:
		# a fast slide: a short tween so walls still stop it (dest is ray-safe)
		a.apply_status("dashing", 0.2)
		var tw := a.create_tween()
		tw.tween_property(a, "global_position", dest, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		SpellVFX.fx("dash", e, {"a": a, "from": start, "to": dest})
	if float(f.get("mult", 0.0)) > 0.0 or f.has("knock") or f.has("status"):
		var info := _info(a, e, f, power)
		if not f.has("mult"):
			info.amount = 0.0
		var hit := {}
		for t in Game.actors_near((start + dest) * 0.5, start.distance_to(dest) * 0.5 + 2.5):
			if t == a or t.is_dead or hit.has(t.actor_id) or not Game.can_damage(a, t):
				continue
			var cp := Geometry3D.get_closest_point_to_segment(t.global_position, start, dest)
			if cp.distance_to(t.global_position) < 1.6 + t.radius():
				hit[t.actor_id] = true
				var inf := info.duplicate()
				if f.has("knock"):
					var side: Vector3 = (t.global_position - cp)
					side.y = 0
					t.knockback = (dir + side.normalized() * 0.6).normalized() * float(f.knock) / maxf(1.0, t._scale())
				_hit(a, t, inf)

static func _c_behind(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3) -> void:
	var t := Spells._target(a, aim, float(f.get("rng", 8.0)), 75.0)
	if t == null:
		return
	var from := a.global_position
	var p := t.global_position - t.facing * (1.1 + t.radius())
	p = Spells._safe_dest(a, p)
	SpellVFX.fx("blink_out", e, {"a": a})
	a.global_position = p
	if a.has_method("reset_physics_interpolation"):
		a.reset_physics_interpolation()
	var to := t.global_position - p
	to.y = 0
	a.face_dir(to.normalized())
	SpellVFX.fx("blink_in", e, {"a": a, "from": from})

static func _c_melee(a: Actor, e: Dictionary, f: Dictionary, power: float) -> void:
	var anim := str(f.get("anim", e.get("anim", "slash")))
	# soft auto-aim: a technique swings at the nearest foe in reach
	var near := Spells._target(a, a.facing, a.weapon_range() + float(f.get("rng_add", 0.0)) + 1.5, 100.0)
	if near != null:
		var to := near.global_position - a.global_position
		to.y = 0
		if to.length() > 0.2:
			a.face_dir(to.normalized())
	if a.rig:
		a.rig.trigger(anim)
	if not a.act.is_empty():
		a.act.data.anim = anim
	var info := _info(a, e, f, power)
	info.melee = true
	var rng := a.weapon_range() + float(f.get("rng_add", 0.0))
	var max_t := 99
	if f.has("pierce"):
		max_t = 1 + int(f.pierce)
	var arc := float(f.get("arc", 110.0))
	var hits := Combat.melee(a, rng, arc, info, max_t)
	SpellVFX.fx("slash", e, {"a": a, "rng": rng, "arc": arc, "anim": anim})
	if f.get("interrupt", false):
		for h in hits:
			var t = h.target
			if is_instance_valid(t) and t is Boss and t.shield != null and t.shield.state == BossShield.CHARGING:
				t.shield.interrupt("приём сорвал подготовку щита")
			if is_instance_valid(t) and not t.act.is_empty() and t.act.name in ["skill", "spell", "charge", "boss"]:
				t.act = {}
				VFX.text(t.chest() + Vector3(0, 0.4, 0), "Сорвано!", Color(1.0, 0.95, 0.6))
	if hits.size() > 0:
		Audio.play_sfx("hit_metal" if hits[0].get("metal_hit", false) else "hit_flesh", a.global_position, -2.0)

static func _c_melee_seq(a: Actor, e: Dictionary, f: Dictionary, power: float) -> void:
	var seq: Array = f.seq
	var n := seq.size()
	if f.has("need_off"):
		var off: Dictionary = a.data.inv.equipped("off") if a.data else {}
		if off.is_empty() or ItemDB.base(off.base).get("cat", "") != str(f.need_off):
			n = 1
	var iv := float(f.get("interval", 0.25))
	for i in n:
		var step: Array = seq[i]
		var ff := {"mult": float(step[1]), "arc": float(step[2]), "anim": str(step[0])}
		if f.has("status"):
			ff.status = f.status
		if f.has("knock"):
			ff.knock = f.knock
		if f.has("max"):
			ff.pierce = int(f.max) - 1
		if i == 0:
			_c_melee(a, e, ff, power)
		else:
			a.get_tree().create_timer(iv * i, false).timeout.connect(func():
				if is_instance_valid(a) and not a.is_dead and a.can_act():
					_c_melee(a, e, ff, power))

static func _shot_kind(a: Actor) -> String:
	var b := a.weapon_base()
	if b.get("cat", "") in ["bow", "firearm"]:
		return str(b.get("proj", "arrow"))
	return "arrow"

static func _c_shots(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var n := int(f.get("n", 1))
	var iv := float(f.get("interval", 0.0))
	var spread := float(f.get("spread", 0.0))
	var t := Spells._target(a, aim, 32.0, 35.0)
	var dir := aim
	if t:
		dir = (t.chest() - a.chest()).normalized()
	var paid := Ammo.ability_rounds(a, e) > 0
	for i in n:
		var ang := 0.0
		if spread > 0.0 and n > 1:
			ang = deg_to_rad(-spread * 0.5 + spread * float(i) / float(n - 1))
		elif n > 1:
			ang = deg_to_rad(randf_range(-2.0, 2.0))
		var d2 := dir.rotated(Vector3.UP, ang)
		var shoot := func():
			if not is_instance_valid(a) or a.is_dead:
				return
			if paid and not Ammo.consume(a, 1):
				if a.is_player and i > 0:
					Audio.play_sfx("ui_click", a.global_position, -6.0)
				return            # out of rounds: the rest of the burst is not fired
			var info := _info(a, e, f, power)
			info.melee = false
			if f.get("crit", false):
				info.crit_force = true
			var kind := _shot_kind(a)
			var spd := float(f.get("spd", 60.0 if kind in ["bullet", "pellet", "pulse"] else 42.0))
			var muzzle := a.chest() + a.facing * 0.6 + Vector3(0, 0.1, 0)
			var p := Projectile.spawn(a, muzzle, d2 * spd, info, kind, {"pierce": int(f.get("pierce", 0)), "range": maxf(24.0, a.weapon_range() * 1.2)})
			SpellVFX.fx("shot", e, {"a": a, "p": p, "pos": muzzle, "dir": d2})
			if a.rig:
				a.rig.trigger("shoot")
		if iv > 0.0 and i > 0:
			a.get_tree().create_timer(iv * i, false).timeout.connect(shoot)
		else:
			shoot.call()

static func _c_sky_volley(a: Actor, e: Dictionary, f: Dictionary, power: float) -> void:
	var rng := float(f.get("rng", 30.0))
	var mx := int(f.get("max", 6))
	var marked: Array = []
	var others: Array = []
	for t in enemies_in(a, a.global_position, rng):
		if t.statuses.has("marked") or t.statuses.has("tracked") or t.statuses.has("radiant"):
			marked.append(t)
		else:
			others.append(t)
	others.sort_custom(func(x, y): return x.global_position.distance_squared_to(a.global_position) < y.global_position.distance_squared_to(a.global_position))
	var targets: Array = marked.slice(0, mx) if not marked.is_empty() else others.slice(0, 3)
	if Ammo.ability_rounds(a, e) > 0:
		# one arrow per target, paid now; no arrows — no volley
		var can := 0
		while can < targets.size() and Ammo.consume(a, 1):
			can += 1
		targets = targets.slice(0, can)
	var i := 0
	for t in targets:
		var tid: int = t.get_instance_id()
		var info := _info(a, e, f, power)
		info.melee = false
		SpellVFX.fx("telegraph", e, {"pos": t.global_position, "r": 1.2, "dur": 0.5})
		a.get_tree().create_timer(0.35 + 0.08 * i, false).timeout.connect(func():
			var tt = _obj(tid)
			if tt != null:
				var top: Vector3 = tt.chest() + Vector3(randf_range(-0.5, 0.5), 14.0, randf_range(-0.5, 0.5))
				var p := Projectile.spawn(a if is_instance_valid(a) else null, top, (tt.chest() - top).normalized() * 55.0, info, "arrow", {"range": 18.0})
				SpellVFX.fx("shot", e, {"a": a, "p": p, "pos": top, "dir": Vector3.DOWN}))
		i += 1

static func _c_shadow_dance(a: Actor, e: Dictionary, f: Dictionary, power: float) -> void:
	var targets := enemies_in(a, a.global_position, float(f.get("rng", 7.0)))
	targets.sort_custom(func(x, y): return x.global_position.distance_squared_to(a.global_position) < y.global_position.distance_squared_to(a.global_position))
	targets = targets.slice(0, int(f.get("targets", 4)))
	if targets.is_empty():
		return
	var hits := int(f.get("hits", 6))
	a.apply_status("invuln", hits * 0.12 + 0.2)
	for i in hits:
		var tid: int = targets[i % targets.size()].get_instance_id()
		a.get_tree().create_timer(0.12 * i, false).timeout.connect(func():
			var tt = _obj(tid)
			if not is_instance_valid(a) or a.is_dead or tt == null:
				return
			SpellVFX.fx("afterimage", e, {"a": a})
			var side := Vector3(cos(i * 2.3), 0, sin(i * 2.3))
			var p := Spells._safe_dest(a, tt.global_position + side * (1.0 + tt.radius()))
			a.global_position = p
			if a.has_method("reset_physics_interpolation"):
				a.reset_physics_interpolation()
			var to: Vector3 = tt.global_position - p
			to.y = 0
			a.face_dir(to.normalized())
			if a.rig:
				a.rig.trigger("stab" if i % 2 == 0 else "slash")
			var info := _info(a, e, f, power)
			info.melee = true
			info.hit_pos = tt.chest()
			Combat.deal(a, tt, info))

static func _c_proj(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var n := int(f.get("n", 1))
	var spread := float(f.get("spread", 0.0))
	var spd := float(f.get("spd", 30.0)) * (1.0 + a.hook("fine_tune"))
	var t := Spells._target(a, aim, float(f.get("rng", 20.0)), 30.0)
	var dir := aim
	var muzzle := MagicFX.hand_pos(a) if a.rig else a.chest() + aim * 0.6
	if t:
		dir = (t.chest() - muzzle).normalized()
	var col: Color = e.get("vis", {}).get("col", Combat.element_color(DBSkills.SCHOOLS[e.school].dtype))
	for i in n:
		var ang := 0.0
		if n > 1:
			ang = deg_to_rad(-spread * 0.5 + spread * float(i) / float(n - 1))
		var d2 := dir.rotated(Vector3.UP, ang)
		var info := _info(a, e, f, power)
		var kind := "magic"
		var opts := {"pierce": int(f.get("pierce", 0)), "range": float(f.get("rng", 20.0)), "color": col}
		if a.hook("fine_tune") > 0.0:
			opts.homing = 0.6
		var origin: Vector3 = muzzle + d2 * 0.3
		if t != null and t.global_position.distance_to(a.global_position) < 2.5:
			origin = a.chest()      # point-blank: start inside the caster so the sweep covers it
		var p := Projectile.spawn(a, origin, d2 * spd, info, kind, opts)
		SpellVFX.fx("proj", e, {"a": a, "p": p, "kind": str(f.get("kind", "magic"))})

static func _c_bolt(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var t := Spells._target(a, aim, float(f.get("rng", 12.0)), float(f.get("cone", 50.0)))
	var from := MagicFX.hand_pos(a) if a.rig else a.chest()
	if t == null:
		SpellVFX.fx("bolt", e, {"a": a, "from": from, "to": from + aim * float(f.get("rng", 8.0)) * 0.7, "miss": true})
		return
	SpellVFX.fx("bolt", e, {"a": a, "from": from, "to": t.chest(), "t": t})
	var info := _info(a, e, f, power)
	info.hit_pos = t.chest()
	_imprint(a, e, t.global_position, info, 0.0)
	var dealt := _hit(a, t, info)
	if f.has("drain") and dealt > 0.0:
		var back := dealt * float(f.drain)
		if t.max_mana > 0.0 and t.mana > 0.0:
			var took := minf(t.mana, back)
			t.mana -= took
			t._mana_fresh = false
			ManaSys.leech(a, took)          # drained mana obeys the same per-second cap
		else:
			a.heal(back)

static func _c_beam(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var rng := float(f.get("rng", 14.0))
	var from := MagicFX.hand_pos(a) if a.rig else a.chest()
	var t := Spells._target(a, aim, rng, 30.0)
	var dir := aim
	if t:
		dir = (t.chest() - from).normalized()
	var to := from + dir * rng
	var sp := Combat.space()
	if sp:
		var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Actor.LAYER_WORLD | Actor.LAYER_DESTRUCT))
		if not r.is_empty():
			to = r.position
	var w := float(f.get("w", 1.0))
	var cands: Array = []
	for c in Game.actors_near((from + to) * 0.5, from.distance_to(to) * 0.5 + 2.0):
		if c == a or c.is_dead or not Game.can_damage(a, c):
			continue
		var cp := Geometry3D.get_closest_point_to_segment(c.chest(), from, to)
		if cp.distance_to(c.chest()) < w * 0.5 + c.radius():
			cands.append([from.distance_squared_to(cp), c])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	if f.get("single", false) and not cands.is_empty():
		cands = [cands[0]]
		to = cands[0][1].chest()
	SpellVFX.fx("beam", e, {"a": a, "from": from, "to": to})
	for c in cands:
		var info := _info(a, e, f, power)
		_hit(a, c[1], info)

static func _c_cone(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var r := float(f.get("r", 4.0))
	var ang := float(f.get("ang", 60.0))
	SpellVFX.fx("cone", e, {"a": a, "r": r, "ang": ang, "aim": aim})
	_imprint(a, e, a.global_position + aim * r * 0.5, _info(a, e, f, power), r * 0.5)
	for t in enemies_in(a, a.global_position, r):
		var to: Vector3 = t.global_position - a.global_position
		to.y = 0
		if to.length() > 0.5 and aim.angle_to(to.normalized()) > deg_to_rad(ang * 0.5):
			continue
		if not Combat.line_of_sight(a.chest(), t.chest()):
			continue
		if f.get("weak_only", false) and (t.kind == "boss" or t.level > a.level or t.get("elite") == true):
			continue
		var info := _info(a, e, f, power)
		if f.has("knock"):
			var light: bool = t.kind != "boss" and t._scale() <= 1.25
			if not f.get("light_only", false) or light:
				t.knockback = to.normalized() * float(f.knock) / maxf(1.0, t._scale())
			info.knock = 0.0
		_hit(a, t, info)

static func _c_nova(a: Actor, e: Dictionary, f: Dictionary, power: float) -> void:
	var r := float(f.get("r", 4.0))
	var c := a.global_position
	var info := _info(a, e, f, power)
	SpellVFX.fx("nova", e, {"a": a, "pos": c, "r": r, "dtype": info.get("dtype", "")})
	_imprint(a, e, c, info, r)
	for t in enemies_in(a, c, r):
		if not Combat.line_of_sight(c + Vector3(0, 0.8, 0), t.chest()):
			continue
		var inf := info.duplicate()
		if f.has("wet_freeze") and t.statuses.has("wet"):
			inf.status = inf.status.duplicate()
			inf.status["freeze"] = float(f.wet_freeze)
		if f.has("knock"):
			var away: Vector3 = t.global_position - c
			away.y = 0
			t.knockback = away.normalized() * float(f.knock) / maxf(1.0, t._scale())
			inf.knock = 0.0
		_hit(a, t, inf)
	for dd in Game.grid.query(c, r, "destructible"):
		if is_instance_valid(dd) and dd.has_method("take_hit"):
			dd.take_hit(float(info.amount) * 0.5, str(info.get("dtype", "blunt")), a)

static func _c_blast(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var center := _center(a, f, aim)
	var n := int(f.get("n", 1))
	var iv := float(f.get("interval", 0.2))
	var delay := float(f.get("delay", 0.0))
	var r := float(f.get("r", 2.5))
	var scatter := float(f.get("scatter", 0.0))
	var pts: Array = []
	var pool: Array = []
	if f.get("prefer_targets", false):
		pool = enemies_in(a, center, scatter + 1.0)
	for i in n:
		var p := center
		if not pool.is_empty():
			p = pool[i % pool.size()].global_position
		elif scatter > 0.0 and n > 1:
			var an := randf() * TAU
			p = center + Vector3(cos(an), 0, sin(an)) * randf_range(0.0, scatter)
		pts.append(MagicFX.ground_point(p))
	for i in n:
		var p: Vector3 = pts[i]
		var t0 := iv * i
		if f.get("telegraph", false) or delay > 0.0:
			_later(a, t0, func(): SpellVFX.fx("telegraph", e, {"pos": p, "r": r, "dur": maxf(0.25, delay), "f": f}))
		_later(a, t0 + delay, func():
			var src = a if is_instance_valid(a) and not a.is_dead else null
			var info := _info(a, e, f, power) if src != null else {"amount": power * float(f.get("mult", 1.0)), "dtype": DBSkills.SCHOOLS.get(e.get("school", "fire"), {}).get("dtype", "fire"), "status": f.get("status", {})}
			SpellVFX.fx("blast", e, {"pos": p, "r": r, "f": f})
			_imprint(src, e, p, info, r)
			for t in enemies_in(src, p, r):
				var inf := info.duplicate()
				if f.has("knock"):
					var away: Vector3 = t.global_position - p
					away.y = 0
					t.knockback = (away.normalized() if away.length() > 0.2 else Vector3(1, 0, 0)) * float(f.knock) / maxf(1.0, t._scale())
					inf.knock = 0.0
				_hit(src, t, inf)
			for dd in Game.grid.query(p, r, "destructible"):
				if is_instance_valid(dd) and dd.has_method("take_hit"):
					dd.take_hit(float(info.amount) * 0.5, str(info.get("dtype", "blunt")), src))

## Timers keep only an instance id of other actors (a freed target must not
## be captured by a lambda).
static func _obj(id: int):
	var o = instance_from_id(id)
	if o == null or not is_instance_valid(o) or o.is_dead:
		return null
	return o

static func _later(a, t: float, cb: Callable) -> void:
	if t <= 0.0:
		cb.call()
		return
	var tree: SceneTree = a.get_tree() if a != null and is_instance_valid(a) and a.is_inside_tree() else Engine.get_main_loop() as SceneTree
	tree.create_timer(t, false).timeout.connect(cb)

static func _c_wave(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var length := float(f.get("len", 12.0))
	var w := float(f.get("w", 1.8))
	var spd := float(f.get("spd", 12.0))
	var start := a.global_position + aim * 0.8
	var hit := {}
	var steps := int(ceil(length / (spd * 0.1)))
	var info := _info(a, e, f, power)
	for i in steps + 1:
		var p := start + aim * minf(length, spd * 0.1 * i)
		_later(a, 0.1 * i, func():
			var src = a if is_instance_valid(a) and not a.is_dead else null
			var gp := MagicFX.ground_point(p)
			SpellVFX.fx("wave", e, {"pos": gp, "w": w, "dir": aim})
			for t in enemies_in(src, gp, w):
				if hit.has(t.actor_id):
					continue
				hit[t.actor_id] = true
				_hit(src, t, info))

static func _c_chain(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var t := Spells._target(a, aim, float(f.get("rng", 16.0)), 60.0)
	if t == null:
		SpellVFX.fx("bolt", e, {"a": a, "from": MagicFX.hand_pos(a), "to": a.chest() + aim * 8.0, "miss": true})
		return
	Spells.chain_lightning(a, t, power, int(f.get("jumps", 4)), false, MagicFX.hand_pos(a))

static func _c_rays(a: Actor, e: Dictionary, f: Dictionary, power: float) -> void:
	var rng := float(f.get("rng", 18.0))
	var list := enemies_in(a, a.global_position, rng)
	list.sort_custom(func(x, y):
		var mx := 0 if (x.statuses.has("radiant") or x.statuses.has("marked")) else 1
		var my := 0 if (y.statuses.has("radiant") or y.statuses.has("marked")) else 1
		if mx != my:
			return mx < my
		return x.global_position.distance_squared_to(a.global_position) < y.global_position.distance_squared_to(a.global_position))
	var n := int(f.get("n", 7))
	if list.is_empty():
		return
	for i in n:
		var tid: int = list[i % list.size()].get_instance_id()
		_later(a, 0.07 * i, func():
			var t = _obj(tid)
			if t == null or not is_instance_valid(a):
				return
			SpellVFX.fx("ray", e, {"from": a.chest() + Vector3(0, 1.4, 0), "to": t.chest()})
			var info := _info(a, e, f, power)
			if i >= list.size():
				info.amount *= 0.5       # extra rays on the same target hurt less
			_hit(a, t, info))

static func _c_fissures(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var c := _center(a, f, aim)
	var n := int(f.get("n", 5))
	var length := float(f.get("len", 8.0))
	var hit := {}
	SpellVFX.fx("telegraph", e, {"pos": c, "r": 2.0, "dur": 0.4, "f": f})
	for k in n:
		var dir := Vector3(cos(TAU * k / n + randf() * 0.3), 0, sin(TAU * k / n + randf() * 0.3))
		var steps := int(length / 1.6)
		for s in steps:
			var p := MagicFX.ground_point(c + dir * (1.0 + 1.6 * s))
			_later(a, 0.4 + 0.07 * s, func():
				var src = a if is_instance_valid(a) and not a.is_dead else null
				StoneStructure.spawn("stone_spike", p, dir, {"life": 2.5, "solid": false, "scale": 0.8 + 0.1 * s, "src": src})
				SpellVFX.fx("blast", e, {"pos": p, "r": 1.4, "f": {"small": true}})
				for t in enemies_in(src, p, 1.5):
					if hit.has(t.actor_id):
						continue
					hit[t.actor_id] = true
					var info := _info(a, e, f, power) if src != null else {"amount": power, "dtype": "earth", "status": f.get("status", {})}
					t.knockback = Vector3(0, 0, 0)
					if t.is_on_floor() and t.kind != "boss":
						t.velocity.y = 5.0
					_hit(src, t, info))

static func _c_zone(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var kind := str(f.get("kind", "fire"))
	var r := float(f.get("r", 3.0))
	var dur := float(f.get("dur", 5.0)) * (1.0 + a.hook("zone_dur"))
	var info := _info(a, e, f, power)
	info.amount = float(info.amount) * (float(f.mult) if f.has("mult") else 0.5)
	info.proc = true
	var prm: Dictionary = f.get("prm", {}).duplicate()
	prm.ab = e.id
	if f.has("move"):
		prm.vel = aim * float(f.move)
	if f.get("follow", false):
		prm.follow = a
	if str(f.get("at", "")) == "line":
		var length := float(f.get("len", 8.0))
		var nseg := maxi(2, int(length / (r * 1.6)))
		for i in nseg:
			var p := a.global_position + aim * (1.2 + length * float(i) / float(nseg - 1))
			Zone.create(kind, a, MagicFX.ground_point(p), r, dur, info, prm)
		return
	var c := _center(a, f, aim)
	var z := Zone.create(kind, a, c, r, dur, info, prm)
	if z and kind in ["fire", "blizzard", "dark", "electric", "timeslow"]:
		CityMagic.on_area(a, e, c, r)

static func _status_targets(a: Actor, f: Dictionary) -> Array:
	match str(f.get("to", "self")):
		"ally":
			var best = null
			var bd := INF
			for t in allies_in(a, a.global_position, float(f.get("r", 8.0))):
				if t == a:
					continue
				var d: float = t.global_position.distance_to(a.global_position)
				if d < bd:
					bd = d
					best = t
			return [best if best != null else a]
		"allies":
			return allies_in(a, a.global_position, float(f.get("r", 6.0)))
	return [a]

static func _c_buff(a: Actor, e: Dictionary, f: Dictionary) -> void:
	var prm: Dictionary = f.get("prm", {}).duplicate(true)
	if prm.has("per_lvl") and a.data != null and e.kind == "spell":
		var mods: Dictionary = prm.get("mods", {})
		var sl := a.data.school_level(e.school)
		for k in prm.per_lvl:
			mods[k] = float(mods.get(k, 0.0)) + float(prm.per_lvl[k]) * sl
		prm.mods = mods
		prm.erase("per_lvl")
	prm.ab = e.id
	for t in _status_targets(a, f):
		t.apply_status(str(f.status), float(f.get("dur", 5.0)), prm)
		SpellVFX.fx("buff", e, {"a": a, "t": t})

static func _c_debuff(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3) -> void:
	var t := Spells._target(a, aim, float(f.get("rng", 12.0)), 75.0)
	if t == null:
		return
	var prm: Dictionary = f.get("prm", {}).duplicate(true)
	prm.ab = e.id
	if prm.get("by_me", false):
		prm.by = a.actor_id
		prm.caster = a
	if prm.has("dot"):
		prm.src = a
		if a.data != null and e.kind == "spell":
			prm.dot = float(prm.dot) * (1.0 + 0.06 * a.data.school_level(e.school)) * (1.0 + 0.04 * (a.level - 1))
	if prm.get("no_stealth", false):
		t.statuses.erase("stealth")
	t.apply_status(str(f.status), float(f.get("dur", 5.0)), prm)
	t.add_aggro(a, 20.0)
	SpellVFX.fx("debuff", e, {"a": a, "t": t})

static func _c_shield(a: Actor, e: Dictionary, f: Dictionary) -> void:
	var amt := float(f.get("amt", 40.0))
	if a.data != null and e.kind == "spell":
		amt += float(f.get("per_lvl", 0.0)) * a.data.school_level(e.school)
	var dur := float(f.get("dur", 8.0))
	for t in _status_targets(a, f):
		t.shield_hp = maxf(t.shield_hp, amt)
		t.apply_status("magic_shield", dur, {"ab": e.id, "orbit": str(f.get("orbit", ""))})
		SpellVFX.fx("shield", e, {"a": a, "t": t, "dur": dur})

static func _c_heal(a: Actor, e: Dictionary, f: Dictionary) -> void:
	var t: Actor = a
	if str(f.get("to", "self")) == "ally_or_self":
		var worst: Actor = a
		var wr := a.hp / maxf(1.0, a.max_hp)
		for o in allies_in(a, a.global_position, float(f.get("r", 8.0))):
			var r: float = o.hp / maxf(1.0, o.max_hp)
			if r < wr - 0.05:
				wr = r
				worst = o
		t = worst
	var sl := a.data.school_level("heal") if a.data != null else 4
	var mult := 1.0 + 0.03 * sl + a.stat("spell") * 0.5
	var op := str(f.get("hc", ""))
	var hc_done := false
	if op != "" and t.is_player and Hardcore.active():
		var pick := int(t.get_meta("heal_pick", -1)) if t.has_meta("heal_pick") else -1
		var res: Dictionary = Hardcore.inst.spell_op(t, op, sl, pick)
		hc_done = res.get("ok", false)
		if not hc_done and pick >= 0 and a.has_meta("heal_paid"):
			a.set_meta("heal_refund", str(res.get("reason", "")))
		if t.has_meta("heal_pick"):
			t.remove_meta("heal_pick")
	var amt := float(f.get("amt", 0.0))
	if op in ["close_wound", "tissue"] and hc_done:
		amt *= 0.4     # in Hardcore the spell spends itself on the wound, not on raw health
	if amt > 0.0:
		t.heal(t.max_hp * amt * mult)
	if float(f.get("hot", 0.0)) > 0.0 and not (op == "tissue" and hc_done):
		t.apply_status("regen_hot", float(f.get("hot_dur", 5.0)), {"hot": t.max_hp * float(f.hot) * mult})
	for k in f.get("cleanse", []):
		if t.statuses.has(k):
			t.statuses.erase(k)
	t._recalc_buffs()
	SpellVFX.fx("heal", e, {"a": a, "t": t})

static func _c_push(a: Actor, e: Dictionary, f: Dictionary) -> void:
	var r := float(f.get("r", 3.0))
	for t in enemies_in(a, a.global_position, r):
		if t.kind == "boss":
			continue
		var away: Vector3 = t.global_position - a.global_position
		away.y = 0
		t.knockback = (away.normalized() if away.length() > 0.1 else a.facing) * float(f.get("force", 5.0)) / maxf(1.0, t._scale())
	SpellVFX.fx("push", e, {"a": a, "r": r})

static func _c_mirror(a: Actor, e: Dictionary, f: Dictionary) -> void:
	var last: Dictionary = _last.get(a.actor_id, {})
	if last.is_empty():
		if a.is_player:
			Events.notify.emit("Зеркало мгновения: нечего повторить", Color(0.7, 1.0, 0.95))
		return
	var src: Dictionary = DBAbilities.get_ab(last.id)
	if src.is_empty() or int(src.get("tier", 9)) > 4:
		return
	SpellVFX.fx("mirror", e, {"a": a})
	var pw := spell_power(a, src) * float(f.get("pow", 0.7))
	_later(a, 0.15, func():
		if is_instance_valid(a) and not a.is_dead:
			_run(a, src, a.facing, pw, true))

static func _c_summon(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3) -> void:
	if Game.world == null:
		return
	var id := str(f.get("id", "skeleton_minion"))
	var mine: Array = live_summons(a)
	var same: Array = mine.filter(func(s): return s.def_id == id)
	var limit := int(f.get("limit", 1))
	while same.size() >= limit and not same.is_empty():
		despawn(same.pop_front())
	mine = live_summons(a)
	while mine.size() >= MAX_SUMMONS_PER_OWNER and not mine.is_empty():
		despawn(mine.pop_front())
	if world_summons() >= MAX_SUMMONS_WORLD:
		if a.is_player:
			Events.notify.emit("Слишком много призванных существ вокруг", Color(0.8, 0.8, 0.8))
		return
	var pos := _center(a, f, aim)
	SpellVFX.fx("summon", e, {"a": a, "pos": pos})
	var out := Spells.summon(a, id, int(f.get("n", 1)), pos, float(f.get("life", 20.0)))
	for m in out:
		m.set_meta("ab", e.id)
		if a.data != null and e.kind == "spell":
			var sl := a.data.school_level(e.school)
			m.max_hp *= 1.0 + 0.04 * sl
			m.hp = m.max_hp
			m.base_dmg *= 1.0 + 0.03 * sl
		_summons[a.actor_id] = live_summons(a) + [m]
		stats.summons += 1
	if e.school == "necro":
		CityMagic.on_necromancy(a, pos)

static func live_summons(a) -> Array:
	if a == null or not is_instance_valid(a):
		return []
	var out: Array = []
	for s in _summons.get(a.actor_id, []):
		if is_instance_valid(s) and not s.is_dead:
			out.append(s)
	_summons[a.actor_id] = out
	return out

static func world_summons() -> int:
	var n := 0
	for k in _summons.keys():
		var alive: Array = []
		for s in _summons[k]:
			if is_instance_valid(s) and not s.is_dead:
				alive.append(s)
		_summons[k] = alive
		n += alive.size()
	return n

## A summon leaves without dying (no corpse, no kill credit, no loot).
static func despawn(m) -> void:
	if m == null or not is_instance_valid(m) or m.is_dead:
		return
	MagicFX.summon_puff(m.chest(), Color(0.6, 0.85, 0.7))
	m.is_dead = true
	m.collision_layer = 0
	m.queue_free()

static func _c_terrain(a: Actor, e: Dictionary, f: Dictionary, aim: Vector3, power: float) -> void:
	var kind := str(f.get("kind", "stone_spike"))
	var n := int(f.get("n", 1))
	var life := float(f.get("life", 5.0))
	var at := str(f.get("at", "front"))
	var info := _info(a, e, f, power)
	var pts: Array = []
	var dirs: Array = []
	match at:
		"line":
			var length := float(f.get("len", 8.0))
			var t := Spells._target(a, aim, length + 2.0, 35.0)
			var dir := aim
			if t:
				var to := t.global_position - a.global_position
				to.y = 0
				dir = to.normalized()
			for i in n:
				pts.append(a.global_position + dir * (1.5 + (length - 1.5) * float(i) / float(maxi(1, n - 1))))
				dirs.append(dir)
		"front":
			var c := a.global_position + aim * float(f.get("dist", 3.0))
			var side := aim.cross(Vector3.UP).normalized()
			var width := float(f.get("r", 6.0))
			for i in n:
				var o := -width * 0.5 + width * (float(i) + 0.5) / float(n)
				pts.append(c + side * o)
				dirs.append(aim)
		_:
			var c2 := _center(a, f, aim)
			var rr := float(f.get("r", 4.0))
			for i in n:
				var an := TAU * i / n + randf() * 0.4
				pts.append(c2 + Vector3(cos(an), 0, sin(an)) * rr * 0.7)
				dirs.append(Vector3(-sin(an), 0, cos(an)))
	for i in pts.size():
		var p: Vector3 = MagicFX.ground_point(pts[i])
		var d: Vector3 = dirs[i]
		_later(a, 0.07 * i, func():
			var src = a if is_instance_valid(a) and not a.is_dead else null
			var opts := {"life": life, "solid": f.get("solid", kind in ["stone_wall", "ice_wall", "ice_spike"]), "hp": float(f.get("hp", 0.0)), "src": src}
			if kind in ["stone_wall", "ice_wall"]:
				opts.width = float(f.get("r", 6.0)) / float(maxi(1, n)) * 1.05 if at == "front" else 2.6
			# the spike strikes first, then stands (and shoves the survivors aside)
			var victims: Array = enemies_in(src, p, float(f.get("r", 1.2))) if kind in ["stone_spike", "ice_spike"] and float(info.get("amount", 0.0)) > 0.0 else []
			var s := StoneStructure.spawn(kind, p, d, opts)
			if s != null:
				stats.terrain += 1
			if not victims.is_empty():
				for t in victims:
					if not is_instance_valid(t) or t.is_dead:
						continue
					if t.kind != "boss" and float(f.get("knock_up", 0.0)) > 0.0:
						t.velocity.y = float(f.knock_up) / maxf(1.0, t._scale())
						var push: Vector3 = t.global_position - p
						push.y = 0
						t.knockback = (push.normalized() if push.length() > 0.1 else d.cross(Vector3.UP)) * 2.5
					_hit(src, t, info))

static func _c_decoy(a: Actor, e: Dictionary, f: Dictionary, power: float) -> void:
	if Game.world == null:
		return
	var pos := a.global_position
	var arr := Spells.summon(a, "decoy_image", 1, pos, float(f.get("life", 4.0)))
	if arr.is_empty():
		return
	var d: Actor = arr[0]
	d.global_position = pos
	d.face_dir(a.facing)
	d.set_meta("ab", e.id)
	SpellVFX.fx("decoy", e, {"a": a, "d": d})
	# enemies chasing the caster turn to the illusion
	for t in Game.actors_near(pos, 14.0):
		if t == a or t.is_dead or t.get("brain") == null:
			continue
		var br = t.brain
		if br.get("target") == a:
			br.target = d
		t.aggro.erase(a.actor_id)
		t.add_aggro(d, float(f.get("life", 4.0)))
	if float(f.get("burst", 0.0)) > 0.0:
		var burst := power * float(f.burst) * 0.25
		var did := d.get_instance_id()
		_later(a, float(f.get("life", 4.0)) - 0.05, func():
			var d2 = _obj(did)
			if d2 != null:
				var p: Vector3 = d2.global_position
				SpellVFX.fx("blast", e, {"pos": p, "r": 3.0, "f": {}})
				for t in enemies_in(a if is_instance_valid(a) else null, p, 3.0):
					Combat.deal(a if is_instance_valid(a) else null, t, {"amount": burst, "dtype": "dark", "school": "dark", "status": {"slow": 0.5}}))
	_summons[a.actor_id] = live_summons(a) + [d]

static func _c_light_orb(a: Actor, e: Dictionary, f: Dictionary) -> void:
	var old = _orbs.get(a.actor_id)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var orb = SpellVFX.light_orb(a, float(f.get("life", 60.0)), float(f.get("r", 6.0)))
	_orbs[a.actor_id] = orb

static func _c_reveal(a: Actor, e: Dictionary, f: Dictionary) -> void:
	var r := float(f.get("r", 35.0))
	var n := 0
	var what := str(f.get("what", "magic"))
	SpellVFX.fx("pulse", e, {"a": a, "r": r})
	if what == "magic":
		for t in Game.actors_near(a.global_position, r):
			if t == a or t.is_dead:
				continue
			var magical: bool = (t.data != null and not t.data.schools.is_empty()) or (t.get("spells") is Array and not t.spells.is_empty()) or t.kind == "boss"
			if magical:
				t.apply_status("revealed", float(f.get("dur", 8.0)))
				SpellVFX.fx("mark", e, {"pos": t.global_position, "dur": float(f.get("dur", 8.0))})
				n += 1
		if Game.world:
			for k in ["rifts", "portals"]:
				var arr = Game.world.get(k)
				if arr is Array:
					for rf in arr:
						if is_instance_valid(rf) and rf is Node3D and rf.global_position.distance_to(a.global_position) < r:
							SpellVFX.fx("mark", e, {"pos": rf.global_position, "dur": float(f.get("dur", 8.0))})
							n += 1
	else:
		var now := Time.get_ticks_msec()
		for d in deaths:
			if now - int(d[1]) < 600000 and (d[0] as Vector3).distance_to(a.global_position) < r:
				SpellVFX.fx("mark", e, {"pos": d[0], "dur": float(f.get("dur", 10.0))})
				n += 1
		for t in Game.actors_near(a.global_position, r):
			if not t.is_dead and (DBActors.eget(t.def_id, {}).get("skeleton", false) or t.team == "summon"):
				t.apply_status("revealed", float(f.get("dur", 10.0)))
				n += 1
	last_reveal[a.actor_id] = n
	if a.is_player:
		Events.notify.emit("%s: найдено %d" % [e.name, n], e.get("vis", {}).get("col", Color(0.8, 0.8, 1.0)))

# ============================================================== sustain
static func sustain_cap(a: Actor) -> int:
	return 1 + int(a.hook("sustain_cap"))

static func _sustain_take(a: Actor, e: Dictionary) -> void:
	var key := _sustain_status(e)
	var arr: Array = _sustain.get(a.actor_id, [])
	arr = arr.filter(func(x): return a.statuses.has(x[1]) and a.statuses[x[1]].get("ab", "") == x[0])
	arr = arr.filter(func(x): return x[0] != e.id)
	while arr.size() >= sustain_cap(a):
		var old: Array = arr.pop_front()
		a.statuses.erase(old[1])
		if old[1] == "magic_shield":
			a.shield_hp = 0.0
		a._recalc_buffs()
		if a.is_player:
			Events.notify.emit("«%s» рассеивается: держать можно %d длительн. закл." % [DBAbilities.get_ab(old[0]).get("name", old[0]), sustain_cap(a)], Color(0.8, 0.8, 1.0))
	arr.append([e.id, key])
	_sustain[a.actor_id] = arr

static func _sustain_status(e: Dictionary) -> String:
	for f in e.fx:
		if f.c == "buff":
			return str(f.status)
		if f.c == "shield":
			return "magic_shield"
	return ""

static func sustained(a: Actor) -> Array:
	var arr: Array = _sustain.get(a.actor_id, [])
	return arr.filter(func(x): return a.statuses.has(x[1]) and a.statuses[x[1]].get("ab", "") == x[0]).map(func(x): return x[0])

# ============================================================== deaths
static func note_death(p: Vector3) -> void:
	deaths.append([p, Time.get_ticks_msec()])
	if deaths.size() > 40:
		deaths.pop_front()

static func near_recent_death(p: Vector3, r: float, secs: float = 60.0) -> bool:
	var now := Time.get_ticks_msec()
	for d in deaths:
		if now - int(d[1]) < int(secs * 1000.0) and (d[0] as Vector3).distance_to(p) < r:
			return true
	return false

static func reset() -> void:
	_last.clear()
	_sustain.clear()
	_summons.clear()
	_orbs.clear()
	deaths.clear()
	cataclysm_until = 0
	cataclysm_by = null
	last_reveal.clear()
