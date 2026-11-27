class_name Combat
## Damage pipeline: weapon info, hit detection with line-of-sight, area
## damage, ranged weapon firing, on-hit / on-kill effects, procs.

const PHYSICAL := ["slash", "pierce", "blunt"]
## Elemental damage that is still partly physical: armour counts at half.
const HALF_PHYSICAL := ["earth", "air"]

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
		cat = att.mastery_cat()
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
			amt *= _passive_mult(att, tgt, info)
		else:
			amt *= 1.0 + 0.09 * (att.level - 1)
			amt *= 1.0 + att.stat("dmg_pct")
		if att.statuses.has("curse"):
			amt *= 0.7
		if att.statuses.has("mutation") and att.statuses.mutation.get("good", true):
			amt *= 1.3
		# crit
		var cc: float = att.stat("crit") if att.data else 0.05
		if randf() < cc:
			crit = true
			amt *= 1.8 + att.hook("crit_dmg")
		# backstab
		var to_att: Vector3 = att.global_position - tgt.global_position
		to_att.y = 0
		if to_att.length() > 0.1 and tgt.facing.dot(to_att.normalized()) < -0.3 and info.get("melee", false):
			if att.data and att.data.has_node("dg_backstab"):
				amt *= 1.8
			else:
				amt *= 1.15
		if att.statuses.has("stealth"):
			amt *= 3.5 if att.hook("ambush") > 0.0 else 2.5
			if att.hook("ambush") > 0.0 and info.get("melee", false) and tgt.kind != "boss":
				info.status = info.get("status", {}).duplicate()
				info.status["stun"] = 1.0
			att.set_meta("stealth_hit_ms", Time.get_ticks_msec())
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
	if tgt.statuses.has("vulnerable"):
		amt *= 1.4      # opened up by a perfect parry
	amt *= maxf(0.1, 1.0 + tgt.stat("taken_pct"))
	for sk in tgt.statuses:
		var sd: Dictionary = tgt.statuses[sk]
		if sd.has("vuln"):
			amt *= 1.0 + float(sd.vuln.get(dtype_of(info), 0.0))
		if sd.has("vuln_school") and info.get("school", "") != "":
			amt *= 1.0 + float(sd.vuln_school.get(info.school, 0.0))
	if dtype_of(info) == "light" and is_undead(tgt):
		amt *= 1.5
	if tgt.statuses.has("res_down") and info.get("dtype", "") in ["fire", "ice", "lightning", "dark", "time", "energy"]:
		amt *= 1.3      # «Полярный залп» weakened its magic defence
	if dtype == "lightning" and tgt.statuses.has("wet"):
		amt *= 1.6
	if dtype in PHYSICAL or dtype in HALF_PHYSICAL:
		var armor: float = tgt.stat("armor")
		armor *= maxf(0.0, 1.0 + tgt.stat("armor_pct"))
		if tgt.statuses.has("armor_break"):
			armor *= 0.7
		if att != null and is_instance_valid(att) and att.data != null:
			if not info.get("melee", false):
				armor *= 1.0 - att.hook("armor_pen")
			elif att.weapon_cat() == "heavy":
				armor *= 1.0 - att.hook("anti_armor")
		if dtype in HALF_PHYSICAL:
			armor *= 0.5
		amt *= 60.0 / (60.0 + maxf(0.0, armor))
	var res: float = tgt.resist.get(dtype, 0.0)
	if tgt.data:
		res += tgt.stat("res_" + dtype)
	else:
		res += float(tgt._buff_mods.get("res_" + dtype, 0.0))
	if dtype == "energy" and att != null and is_instance_valid(att) and att.hook("phase_tune") > 0.0 and res > 0.0:
		res *= 1.0 - att.hook("phase_tune")
		info.shield_pen = att.hook("phase_tune")
	amt *= 1.0 - clampf(res, -1.0, 0.85)
	if info.get("crit_force", false) and not crit:
		crit = true
		amt *= 1.6
	info.amount = amt
	info.crit = crit
	if att != null and is_instance_valid(att) and info.get("src") == null:
		info.src = att      # spells and zones: the target learns who hurt it (aggro, kill credit)
	var dealt: float = tgt.take_damage(info)
	# venomous creatures poison what they bite (Hardcore: the wound turns septic faster)
	if dealt > 0.0 and att != null and is_instance_valid(att) and info.get("melee", false) and att.has_meta("species"):
		if "poison" in DBCreatures.get_def(str(att.get_meta("species"))).get("abil", []):
			tgt.apply_status("decay", 5.0, {"dot": att.base_dmg * 0.25, "dtype": "poison", "src": att})
			if tgt.is_player and Hardcore.active():
				Hardcore.inst.poison_last()
	if dealt > 0.0 and att != null and is_instance_valid(att):
		_on_hit(att, tgt, dealt, info)
		if att.is_player and not info.get("proc", false):
			CombatFeel.on_player_hit(att, tgt, dealt, info)
	return dealt

static func dtype_of(info: Dictionary) -> String:
	return str(info.get("dtype", "slash"))

static func is_undead(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var d: Dictionary = DBActors.eget(t.def_id, {})
	if d.get("skeleton", false) or d.get("undead", false):
		return true
	var id := str(t.def_id)
	return id.contains("skeleton") or id.contains("wraith") or id.contains("lich") or id.contains("zombie") or id.contains("ghost")

## «Ascension» passive skills of the attacker that change a hit.
static func _passive_mult(att: Actor, tgt, info: Dictionary) -> float:
	var m := 1.0
	var melee: bool = info.get("melee", false)
	var proc: bool = info.get("proc", false)
	if att.hook("relentless") > 0.0 and melee and not proc:
		m *= 1.0 + att.hook("relentless") * att._relentless
		att._relentless = mini(5, att._relentless + 1)
		att._relentless_t = 2.0
	if melee and att.statuses.has("counter_ready"):
		m *= 1.0 + att.hook("block_counter")
		att.statuses.erase("counter_ready")
	if melee and att.statuses.has("dodge_strike"):
		m *= 1.0 + att.hook("dodge_strike")
		att.statuses.erase("dodge_strike")
	if not proc and att.statuses.has("last_blade"):
		m *= 1.0 + att.hook("last_blade")
		att.statuses.erase("last_blade")
	if not melee and not proc and att.statuses.has("retribution"):
		m *= 2.0
		att.statuses.erase("retribution")
	if tgt.statuses.has("hidden_mark") and str(tgt.statuses.hidden_mark.get("by", "")) == att.actor_id and not proc:
		m *= 1.6
		tgt.statuses.erase("hidden_mark")
		info.status = info.get("status", {}).duplicate()
		info.status["bleed"] = 6.0 + att.level * 0.8
	if att.hook("big_game") > 0.0 and (tgt.kind == "boss" or tgt._scale() >= 1.45 or tgt.max_hp >= 900.0):
		m *= 1.0 + att.hook("big_game")
	if att.hook("high_ground") > 0.0 and not melee and att.global_position.y - tgt.global_position.y >= 1.5:
		m *= 1.0 + att.hook("high_ground")
	if att.hook("instinct") > 0.0 and tgt.hp < tgt.max_hp * 0.4:
		m *= 1.0 + att.hook("instinct")
	if att.hook("precise") > 0.0:
		for k in ["vulnerable", "marked", "stun", "hidden_mark", "radiant", "tracked"]:
			if tgt.statuses.has(k):
				m *= 1.0 + att.hook("precise")
				break
	if att.hook("steady") > 0.0 and not melee and att._still_t >= 0.6:
		m *= 1.0 + att.hook("steady")
	if att.hook("switch") > 0.0 and not melee and not proc:
		var last := str(att.get_meta("last_tgt", ""))
		if last != "" and last != tgt.actor_id and Time.get_ticks_msec() - int(att.get_meta("last_tgt_ms", 0)) < 3000:
			m *= 1.0 + att.hook("switch")
		att.set_meta("last_tgt", tgt.actor_id)
		att.set_meta("last_tgt_ms", Time.get_ticks_msec())
	return m

static func _on_hit(att: Actor, tgt: Actor, dealt: float, info: Dictionary) -> void:
	if att.data == null:
		return
	LegendaryArts.on_hit(att, tgt, dealt, info)
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
				MagicFX.hit(tgt.chest(), att.facing, "dark", true)
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
	MagicFX.hit(tgt.chest(), Vector3.UP, "time", true)
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
	_swing_fx(att, rng, arc_deg, anim)
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
		if att.statuses.has("blind") and randf() < 0.5:
			VFX.text(t.chest(), "Промах", Color(0.85, 0.85, 0.85), 0.8)
			continue
		var inf := info.duplicate()
		inf.hit_pos = strike_point(att, t, anim)
		var dealt := deal(att, t, inf)
		hits.append({"target": t, "dmg": dealt, "metal_hit": DBActors.eget(t.def_id, {}).get("metal", false)})
	_hit_destructibles(att, att.global_position, rng + 0.6, arc_deg, info)
	return hits

## Where a melee blow lands on the target, from the swing itself: the height
## of the strike (attacker size and swing kind — overhead, thrust, low sweep,
## creature bite) and the side it comes from (attacker position relative to
## the target, alternating with the combo swing direction). Used by Hardcore
## to pick the injured body zone from real combat data.
static func strike_point(att: Actor, t, anim: String) -> Vector3:
	var s: float = att._scale()
	var h: float
	var edef: Dictionary = DBActors.eget(att.def_id, {}) if att.get("def_id") != null else {}
	var rk: String = str(edef.get("rig", "humanoid"))
	if rk == "beast":
		# Beasts of the Ages: the body plan decides where the blow lands
		rk = {"quad": "wolf", "arach": "spider", "insect": "spider", "worm": "spider", "blob": "blob", "flyer": "wraith", "orb": "wraith",
			"giant": "troll", "tree": "troll", "construct": "golem", "drake": "troll"}.get(str(edef.get("plan", "quad")), "wolf")
	if rk in ["wolf", "spider", "blob", "mimic"]:
		h = 0.45 * s                                       # low beasts bite and grab the legs
	elif rk in ["wraith", "drone"]:
		h = 1.45 * s                                       # floating things strike at head height
	elif rk in ["troll", "golem", "colossus"]:
		h = 1.35 * s                                       # giants swing down from above
	elif att.rig == null:
		h = 0.75 * s
	else:
		match anim:
			"overhead", "slam", "leap":
				h = 1.6 * s
			"thrust", "stab", "lunge":
				h = 1.15 * s
			"sweep", "low", "spin":
				h = 0.6 * s
			_:
				h = 1.25 * s
	var base_y: float = att.global_position.y
	var ts: float = t._scale()
	var y := clampf(base_y + h, t.global_position.y + 0.1, t.global_position.y + 1.8 * ts)
	var to_att: Vector3 = att.global_position - t.global_position
	to_att.y = 0.0
	var dir: Vector3 = to_att.normalized() if to_att.length() > 0.05 else -t.facing
	var right: Vector3 = t.facing.cross(Vector3.UP).normalized() if t.facing.length() > 0.1 else Vector3.RIGHT
	# horizontal swings land on the side they come from; combo swings alternate
	var swing := 0.0
	if anim in ["slash", "sweep", "spin", ""]:
		swing = 0.3 if att.combo % 2 == 0 else -0.3
	var p: Vector3 = t.global_position + dir * t.radius() * 0.9 + right * (to_att.normalized().dot(right) * 0.35 + swing) * ts
	p.y = y
	return p

## Swing visuals: weapon wielders get a blade trail from VFXManager, so only
## wide sweeps draw an arc for them; creatures (claws, jaws) always do.
static func _swing_fx(att: Actor, rng: float, arc_deg: float, anim: String) -> void:
	var rig = att.rig
	var has_trail: bool = rig != null and is_instance_valid(rig) and is_instance_valid(rig.get("weapon_node"))
	var origin := att.global_position + Vector3(0, 0.95 * att._scale(), 0)
	if not has_trail:
		var c := Color(1.0, 0.75, 0.6) if att.kind in ["creature", "boss"] else Color(0.9, 0.93, 1.0)
		VFX.slash(origin, att.facing, rng, arc_deg, anim if anim != "" else "slash", c)
	elif arc_deg >= 359.0 or anim in ["overhead", "slam"]:
		VFX.slash(origin, att.facing, rng, arc_deg, anim, Color(0.9, 0.93, 1.0, 0.8))
	if anim == "slam":
		VFX.ground_impact(att.global_position + att.facing * minf(rng, 2.0), 1.4 * att._scale())

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
		spread *= maxf(0.2, 1.0 - att.hook("recoil_ctrl"))
		if att._still_t >= 0.6:
			spread *= maxf(0.2, 1.0 - att.hook("true_string")) * (0.5 if att.hook("steady") > 0.0 else 1.0)
		elif att.hook("move_shot") <= 0.0 and Vector2(att.velocity.x, att.velocity.z).length() > 1.5:
			spread *= 1.6       # shooting on the run scatters (unless trained)
		if att.statuses.has("blind"):
			spread *= 3.0
		# energy weapons heat up; «Тепловой контроль» halves it, «Синхронизация» stops it
		if att.mastery_cat() == "energy":
			var no_heat := false
			for sk in att.statuses:
				if att.statuses[sk].get("no_heat", false):
					no_heat = true
			if not no_heat:
				att._heat += 9.0 * (1.0 - att.hook("heat_ctrl"))
				if att._heat >= 100.0:
					att._heat = 0.0
					att._overheat_t = 2.0
					if att.is_player:
						Events.notify.emit("Перегрев!", Color(1.0, 0.6, 0.3))
			if att.hook("resonant") > 0.0:
				att._resonant_n += 1
				if att._resonant_n >= 5:
					att._resonant_n = 0
					info.resonant = true
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
		if info.get("resonant", false) and i == 0:
			opts.on_end = func(pos: Vector3):
				VFX.explosion(pos, 2.0, Color(0.4, 0.9, 1.0))
				aoe(att if is_instance_valid(att) else null, pos, 2.0, {"amount": info.amount * 0.6, "dtype": "energy", "proc": true})
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
	VFX.muzzle(muzzle, att.facing, model, kind)

static func staff_bolt(att: Actor) -> void:
	var info := weapon_info(att)
	info.melee = false
	var school := att.data.best_school() if att.data else ""
	if school != "":
		info.dtype = DBSkills.SCHOOLS[school].dtype
		info.school = school
		info.status = school_status(school, info.amount * 0.25)
	var muzzle := att.chest() + att.facing * 1.0 + Vector3(0, 0.2, 0)
	MagicFX.release(MagicFX.hand_pos(att), att.facing, MagicFX.school(str(info.get("school", info.dtype))))
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
		"earth": return Color(0.72, 0.58, 0.38)
		"air": return Color(0.8, 0.96, 0.96)
		"light": return Color(1.0, 0.93, 0.6)
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
	if k.hook("silent_kill") > 0.0 and Time.get_ticks_msec() - int(k.get_meta("stealth_hit_ms", 0)) < 400:
		k.apply_status("stealth", k.hook("silent_kill"))
	k.gain_xp(int(victim.xp_value() * 0.35))
	var cat: String = k.mastery_cat()
	k.gain_mastery(cat, 8.0 + victim.level * 1.5)
	var w: Dictionary = k.weapon()
	if w.get("ability", "") == "nova_kill":
		var inf := {"amount": 15.0 + k.level * 4.0, "dtype": "fire", "status": {"burn": 5.0}, "proc": true}
		MagicFX.impact(k.global_position + Vector3(0, 0.5, 0), "fire", 4.0)
		aoe(k, k.global_position, 4.0, inf)
	if w.get("mythic", "") == "soul_harvest" and victim.kind != "boss":
		Spells.summon(k, "spirit", 1, victim.global_position, 15.0)
	var u: Dictionary = ItemDB.UNIQUES.get(w.get("unique", ""), {})
	if u.has("on_kill_heal"):
		k.heal(k.max_hp * u.on_kill_heal)
	# living weapon growth
	if w.get("living", {}).size() > 0:
		LivingWeapon.add_xp(k, w, 6 + (40 if victim.kind == "boss" else 0) + (10 if victim.elite else 0), victim)
