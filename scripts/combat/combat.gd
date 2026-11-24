class_name Combat
## Damage pipeline: weapon info, hit detection with line-of-sight, area
## damage, ranged weapon firing, on-hit / on-kill effects, procs.

const PHYSICAL := ["slash", "pierce", "blunt"]

static func space() -> PhysicsDirectSpaceState3D:
	if Game.world:
		return Game.world.get_world_3d().direct_space_state
	return null

## True if nothing solid (walls, doors, terrain) is between a and b.
static func line_of_sight(a: Vector3, b: Vector3) -> bool:
	var sp := space()
	if sp == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(a, b, Actor.LAYER_WORLD | Actor.LAYER_DESTRUCT)
	var r := sp.intersect_ray(q)
	return r.is_empty()

static func weapon_info(att: Actor, mult: float = 1.0) -> Dictionary:
	var w := att.weapon()
	var b := att.weapon_base()
	var base := att.base_dmg
	var dtype := att.natural_dtype
	var cat := "unarmed"
	if not w.is_empty():
		base = ItemDB.stat(w, "dmg")
		dtype = b.get("dtype", "slash")
		cat = b.get("cat", "sword")
	elif att.data and att.kind == "humanoid":
		base = 5.0 + att.level * 1.5
		dtype = "blunt"
	var info := {"amount": base * mult, "dtype": dtype, "src": att, "melee": not att.is_ranged(), "knock": 1.5 + (2.0 if cat == "heavy" else 0.0), "status": {}, "cat": cat}
	if att.data:
		if att.stat("fire_dmg") > 0:
			info.amount += att.stat("fire_dmg")
			if randf() < 0.25:
				info.status.burn = att.stat("fire_dmg")
		if att.stat("ice_dmg") > 0:
			info.amount += att.stat("ice_dmg")
			if randf() < 0.3:
				info.status.slow = 0.6
		if att.stat("lightning_dmg") > 0:
			info.amount += att.stat("lightning_dmg")
			if randf() < 0.1:
				info.status.stun = 0.4
		var hy := att.data.hybrids()
		var bs := att.data.best_school()
		if bs != "" and (("spellblade" in hy and cat in DBSkills.MELEE_CATS) or ("arcane_archer" in hy and cat in DBSkills.RANGED_CATS)):
			info.amount *= 1.3
			info.status.merge(school_status(bs, info.amount * 0.2))
		if att.riposte and info.melee:
			info.amount *= 3.0
			info.riposte = true
			att.riposte = false
	return info

static func school_status(school: String, power: float) -> Dictionary:
	match school:
		"fire": return {"burn": maxf(3.0, power)}
		"ice": return {"slow": 0.5}
		"lightning": return {"stun": 0.3}
		"dark": return {"curse": 3.0}
		"spacetime": return {"slow": 0.6}
	return {}

## Final damage computation and application. Returns dealt damage.
static func deal(att, tgt, info: Dictionary) -> float:
	if tgt == null or not is_instance_valid(tgt) or tgt.is_dead:
		return 0.0
	if att != null and is_instance_valid(att) and not Game.can_damage(att, tgt):
		return 0.0
	var amt: float = info.amount
	var crit := false
	if att != null and is_instance_valid(att):
		if att.data:
			amt *= 1.0 + att.stat("dmg_pct")
			var cat: String = info.get("cat", "")
			if cat != "":
				amt *= 1.0 + 0.035 * att.data.mastery_level(cat)
			if info.get("school", "") != "":
				amt *= 1.0 + att.stat("spell") + 0.05 * att.data.school_level(info.school)
				if att.data.school_level(info.school) >= 3:
					amt *= 1.1
			amt *= 1.0 + 0.03 * (att.level - 1)
		else:
			amt *= 1.0 + 0.09 * (att.level - 1)
		if att.statuses.has("curse"):
			amt *= 0.7
		if att.statuses.has("mutation") and att.statuses.mutation.get("good", true):
			amt *= 1.3
		# crit
		var cc: float = att.stat("crit") if att.data else 0.05
		if randf() < cc:
			crit = true
			amt *= 1.8
		# backstab
		var to_att: Vector3 = att.global_position - tgt.global_position
		to_att.y = 0
		if to_att.length() > 0.1 and tgt.facing.dot(to_att.normalized()) < -0.3 and info.get("melee", false):
			if att.data and att.data.has_node("dg_backstab"):
				amt *= 1.8
			else:
				amt *= 1.15
		if att.statuses.has("stealth"):
			amt *= 2.5
			att.statuses.erase("stealth")
			if att.rig:
				att.rig.crouch = false
		# legendary execute
		if att._has_ability("execute") and tgt.hp < tgt.max_hp * 0.25:
			amt *= 3.0
	var dtype: String = info.get("dtype", "slash")
	if Game.world and Game.world.get("director") and Game.world.director != null:
		var mods: Dictionary = Game.world.director.mods
		if att != null and is_instance_valid(att) and att.team in ["monster", "bandit", "boss"]:
			amt *= mods.get("enemy_dmg", 1.0)
		if info.get("school", "") != "":
			amt *= mods.get("spell", 1.0)
	if tgt.statuses.has("curse"):
		amt *= 1.25
	if dtype == "lightning" and tgt.statuses.has("wet"):
		amt *= 1.6
	if dtype in PHYSICAL:
		var armor: float = tgt.stat("armor") if tgt.data else tgt.stats.get("armor", 0.0)
		if tgt.statuses.has("armor_break"):
			armor *= 0.7
		amt *= 60.0 / (60.0 + maxf(0.0, armor))
	var res: float = tgt.resist.get(dtype, 0.0)
	if tgt.data:
		res += tgt.stat("res_" + dtype)
	amt *= 1.0 - clampf(res, -1.0, 0.85)
	info.amount = amt
	info.crit = crit
	var dealt: float = tgt.take_damage(info)
	if dealt > 0.0 and att != null and is_instance_valid(att):
		_on_hit(att, tgt, dealt, info)
		if att.is_player and info.get("melee", false) and not info.get("proc", false) and (crit or tgt.is_dead or dealt > tgt.max_hp * 0.2):
			Game.hit_stop(0.07 if tgt.is_dead else 0.045)
			if tgt.is_dead or crit:
				VFX.shake(0.12)
	return dealt

static func _on_hit(att: Actor, tgt: Actor, dealt: float, info: Dictionary) -> void:
	if att.data == null:
		return
	var cat: String = info.get("cat", "")
	if cat != "" and not info.get("proc", false):
		att.gain_mastery(cat, 2.0 + dealt * 0.06)
	if info.get("school", "") != "":
		var g := att.data.add_school_xp(info.school, 1.5 + dealt * 0.05)
		if g > 0:
			Events.mastery_up.emit(att, info.school, att.data.school_level(info.school))
			if att.data.school_level(info.school) >= 2 and att.is_player:
				Profile.milestone("learn_school")
	var ls := att.stat("lifesteal")
	if ls > 0.0:
		att.heal(dealt * ls)
	if info.get("proc", false):
		return
	if att._has_ability("leech_mana"):
		att.mana = minf(att.max_mana, att.mana + dealt * 0.08)
	if "battlemage" in att.data.hybrids() and info.get("melee", false):
		att.mana = minf(att.max_mana, att.mana + 2.0)
	if info.get("melee", false) and cat == "heavy" and att.data.has_node("hv_break"):
		tgt.apply_status("armor_break", 5.0)
	att.hit_count += 1
	var w := att.weapon()
	match w.get("ability", ""):
		"chain_proc":
			if randf() < 0.2:
				Spells.chain_lightning(att, tgt, dealt * 0.5, 3, true)
		"phantom":
			if att.hit_count % 3 == 0:
				var pi := info.duplicate()
				pi.amount = dealt * 0.6
				pi.proc = true
				pi.dtype = "dark"
				VFX.burst(tgt.chest(), Color(0.6, 0.4, 1.0), 10, 0.4)
				deal(att, tgt, pi)
	match w.get("mythic", ""):
		"time_echo":
			if not info.get("echo", false):
				att._echo_queue.append({"t": 0.6, "target": tgt, "info": info.duplicate(), "amount": dealt * 0.5})
		"rift_strike":
			if randf() < 0.25:
				Spells.micro_rift(att, tgt.global_position, dealt * 0.4)

static func echo_strike(att: Actor, e: Dictionary) -> void:
	var tgt = e.get("target")
	if tgt == null or not is_instance_valid(tgt) or tgt.is_dead:
		return
	var info: Dictionary = e.info
	info.amount = e.amount
	info.echo = true
	info.proc = true
	VFX.burst(tgt.chest(), Color(0.4, 1.0, 0.9), 12, 0.5)
	VFX.text(tgt.chest() + Vector3(0, 0.8, 0), "Эхо", Color(0.4, 1.0, 0.9), 0.8)
	deal(att, tgt, info)

## Melee hit detection: range + arc + vertical tolerance + line of sight.
static func melee(att: Actor, rng: float, arc_deg: float, info: Dictionary, max_targets: int = 99) -> Array:
	var hits: Array = []
	var origin := att.global_position + Vector3(0, 1.0 * att._scale(), 0)
	var cands := Game.actors_near(att.global_position, rng + 3.0)
	cands.sort_custom(func(a, b): return a.global_position.distance_squared_to(att.global_position) < b.global_position.distance_squared_to(att.global_position))
	var limit := max_targets
	var anim: String = att.act.get("data", {}).get("anim", "")
	if anim in ["thrust", "stab"] and att.weapon_cat() in ["spear", "dagger", "sword"]:
		limit = mini(limit, 2 if (att.data and att.data.has_node("sp_impale")) else 1)
	for t in cands:
		if hits.size() >= limit:
			break
		if t == att or t.is_dead or not Game.can_damage(att, t):
			continue
		var to: Vector3 = t.global_position - att.global_position
		to.y = 0
		var d = to.length() - t.radius()
		if d > rng:
			continue
		if absf(t.global_position.y - att.global_position.y) > 2.5 * maxf(1.0, t._scale()):
			continue
		if arc_deg < 359.0 and to.length() > 0.4:
			if att.facing.angle_to(to.normalized()) > deg_to_rad(arc_deg * 0.5):
				continue
		if not line_of_sight(origin, t.chest()):
			continue
		var dealt := deal(att, t, info.duplicate())
		hits.append({"target": t, "dmg": dealt, "metal_hit": DBActors.ENEMIES.get(t.def_id, {}).get("metal", false)})
		VFX.burst(t.chest(), Color(1.0, 0.9, 0.8) if dealt > 0 else Color(0.6, 0.6, 0.6), 6, 0.25)
	_hit_destructibles(att, att.global_position, rng + 0.6, arc_deg, info)
	return hits

static func _hit_destructibles(att: Actor, center: Vector3, rng: float, arc_deg: float, info: Dictionary) -> void:
	for d in Game.grid.query(center, rng + 1.0, "destructible"):
		if not is_instance_valid(d) or not d.has_method("take_hit"):
			continue
		var to: Vector3 = d.global_position - center
		to.y = 0
		if to.length() > rng + d.get("hit_radius"):
			continue
		if arc_deg < 359.0 and att and to.length() > 0.3 and att.facing.angle_to(to.normalized()) > deg_to_rad(arc_deg * 0.5 + 15.0):
			continue
		d.take_hit(info.amount, info.get("dtype", "blunt"), att)

## Area damage with line of sight from the center (no damage through walls).
static func aoe(att, center: Vector3, r: float, info: Dictionary, need_los: bool = true) -> Array:
	var hits: Array = []
	var eye := center + Vector3(0, 0.8, 0)
	for t in Game.actors_near(center, r + 1.0):
		if t.is_dead or t == att:
			continue
		if att != null and is_instance_valid(att) and not Game.can_damage(att, t):
			continue
		if att == null and t.team in ["monster", "boss"]:
			continue
		var d: float = (t.global_position - center).length() - t.radius()
		if d > r:
			continue
		if need_los and not line_of_sight(eye, t.chest()):
			continue
		var dealt := deal(att, t, info.duplicate())
		hits.append(t)
		if dealt > 0 and info.get("pull", 0.0) > 0.0:
			t.knockback = (center - t.global_position).normalized() * info.pull
	for dd in Game.grid.query(center, r + 1.0, "destructible"):
		if is_instance_valid(dd) and dd.has_method("take_hit"):
			dd.take_hit(info.amount, info.get("dtype", "blunt"), att)
	return hits

# ---------------------------------------------------------------- ranged
static func fire_weapon(att: Actor) -> void:
	var b := att.weapon_base()
	var model: String = b.get("model", "bow")
	var cat: String = b.get("cat", "bow")
	var info := weapon_info(att)
	info.melee = false
	info.knock = 1.0
	var muzzle := att.chest() + att.facing * (0.5 + WeaponModels.muzzle_length(model) * 0.6) + Vector3(0, 0.1, 0)
	var spread: float = b.get("spread", 2.0)
	if att.data:
		if att.data.has_node("fa_steady"):
			spread *= 0.5
		spread *= maxf(0.3, 1.0 - 0.025 * att.mastery_lvl())
	var pellets: int = b.get("pellets", 1)
	var kind: String = b.get("proj", "arrow")
	var spd := 38.0
	match kind:
		"bolt": spd = 46.0
		"bullet": spd = 85.0
		"pellet": spd = 70.0
		"pulse": spd = 60.0
		"plasma": spd = 30.0
		"spark": spd = 40.0
	var pierce := 0
	if cat == "bow" and att.data and att.data.has_node("bw_pierce"):
		pierce = 1
	var range_m := att.weapon_range() * 1.15
	if pellets > 1:
		info.amount = info.amount
	for i in pellets:
		var ang := deg_to_rad(randf_range(-spread, spread) * (0.5 if pellets == 1 else 1.0))
		var dir := att.facing.rotated(Vector3.UP, ang)
		var opts := {"pierce": pierce, "range": range_m, "splash": b.get("splash", 0.0), "homing": b.get("homing", 0.0)}
		if att._has_ability("explosive"):
			opts.splash = maxf(opts.splash, 2.5)
		Projectile.spawn(att, muzzle, dir * spd, info.duplicate(), kind, opts)
	var snd := "bow_release"
	match model:
		"crossbow": snd = "crossbow"
		"musket", "pistol_old": snd = "gun_flint"
		"revolver": snd = "gun_revolver"
		"rifle": snd = "gun_rifle"
		"shotgun": snd = "gun_shotgun"
		"pistol", "smg", "carbine": snd = "gun_modern"
		"pulse_rifle", "smart_gun": snd = "laser"
		"plasma_cannon": snd = "plasma"
		"tesla_gun": snd = "lightning"
	Audio.play_sfx(snd, att.global_position, -3.0 if not att.is_player else 0.0)
	if cat == "firearm":
		VFX.flash(muzzle, Color(1.0, 0.8, 0.4) if kind in ["bullet", "pellet"] else Color(0.5, 0.8, 1.0), 0.06)
		VFX.burst(muzzle, Color(0.8, 0.8, 0.8, 0.6), 4, 0.15)

static func staff_bolt(att: Actor) -> void:
	var info := weapon_info(att)
	info.melee = false
	var school := att.data.best_school() if att.data else ""
	if school != "":
		info.dtype = DBSkills.SCHOOLS[school].dtype
		info.school = school
		info.status = school_status(school, info.amount * 0.25)
	var muzzle := att.chest() + att.facing * 1.0 + Vector3(0, 0.2, 0)
	Projectile.spawn(att, muzzle, att.facing * 26.0, info, "magic", {"range": att.weapon_range() * 1.1, "color": element_color(info.dtype)})
	Audio.play_sfx("fire_cast" if info.dtype == "fire" else "ice_cast" if info.dtype == "ice" else "dark_cast", att.global_position, -6.0)

static func element_color(dtype: String) -> Color:
	match dtype:
		"fire": return Color(1.0, 0.5, 0.15)
		"ice": return Color(0.55, 0.9, 1.0)
		"lightning": return Color(0.75, 0.8, 1.0)
		"dark": return Color(0.65, 0.25, 0.9)
		"time": return Color(0.4, 1.0, 0.85)
		"energy": return Color(0.3, 0.85, 1.0)
	return Color(1.0, 0.95, 0.8)

# ---------------------------------------------------------------- kills
static func on_kill(killer, victim) -> void:
	if killer == null or not is_instance_valid(killer) or killer == victim:
		return
	var k = killer
	if k.owner_actor != null and is_instance_valid(k.owner_actor):
		k = k.owner_actor
	if not (k is Actor) or k.data == null:
		return
	k.data.kills += 1
	k.gain_xp(int(victim.xp_value() * 0.35))
	var cat: String = k.weapon_cat()
	k.gain_mastery(cat, 8.0 + victim.level * 1.5)
	var w: Dictionary = k.weapon()
	if w.get("ability", "") == "nova_kill":
		var inf := {"amount": 15.0 + k.level * 4.0, "dtype": "fire", "status": {"burn": 5.0}, "proc": true}
		VFX.ring(k.global_position, 4.0, Color(1.0, 0.5, 0.15), 0.4)
		aoe(k, k.global_position, 4.0, inf)
	if w.get("mythic", "") == "soul_harvest" and victim.kind != "boss":
		Spells.summon(k, "spirit", 1, victim.global_position, 15.0)
	var u: Dictionary = ItemDB.UNIQUES.get(w.get("unique", ""), {})
	if u.has("on_kill_heal"):
		k.heal(k.max_hp * u.on_kill_heal)
	# living weapon growth
	if w.get("living", {}).size() > 0:
		LivingWeapon.add_xp(k, w, 6 + (40 if victim.kind == "boss" else 0) + (10 if victim.elite else 0), victim)
