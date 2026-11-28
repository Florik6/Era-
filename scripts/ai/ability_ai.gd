class_name AbilityAI
## How NPCs use the «Ascension of Power» abilities. Every option is scored
## from the real situation — distance and line of sight, mana and stamina
## (with a reserve for healing), cool-downs, wounded allies, summons alive,
## nearby civilians and town rules, the NPC's specialisation (school
## mastery) — and the best one is used. Examples that fall out of it:
## • an earth mage raises a wall when shot at from afar, throws stone spears
##   down a line of foes and calls a golem when hard pressed;
## • a necromancer raises servants where someone just died, keeps a bone
##   shield up, curses the strongest foe and keeps its distance;
## • a healer stays behind the line, heals the most wounded ally, stops
##   bleeding and cleanses curses before attacking.

static var stats := {"used": 0, "by_use": {}, "refused_town": 0}

static func candidates(n) -> Array:
	var d: CharData = n.data
	if d == null:
		return []
	var t := Time.get_ticks_msec()
	if n.has_meta("ai_ab") and t - int(n.get_meta("ai_ab_t", 0)) < 5000:
		return n.get_meta("ai_ab")
	var out: Array = []
	for id in d.class_skills:
		if DBAbilities.get_ab(id).get("type", "") == "active":
			out.append(id)
	for id in d.mastery_of(n.mastery_cat()).nodes:
		if DBAbilities.has(id) and DBAbilities.get_ab(id).type == "active":
			out.append(id)
	for id in d.spells:
		out.append(id)
	n.set_meta("ai_ab", out)
	n.set_meta("ai_ab_t", t)
	return out

static func is_healer(n) -> bool:
	return n.data != null and n.data.knows_school("heal") and n.data.school_level("heal") >= maxi(2, n.data.school_level(n.data.best_school()) - 2)

## Preferred fighting distance for casters (healers stay behind).
static func preferred_range(n) -> Vector2:
	if is_healer(n):
		return Vector2(9.0, 14.0)
	if n.data != null and (n.data.knows_school("necro") or n.data.knows_school("earth")):
		return Vector2(7.0, 13.0)
	return Vector2(0.0, 0.0)

static func act(n, t, d: float, dir: Vector3) -> bool:
	if n.data == null or n.is_dead or not n.act.is_empty() or n.busy() or not n.can_act():
		return false
	var best := ""
	var bs := 0.0
	var best_aim := dir
	var cands: Array = candidates(n)
	# mana is scarce (ManaSys): a caster saves up for its signature spell
	# (a summon or its highest tier) instead of spending everything on small ones
	var sig := signature_spell(n, cands)
	var sig_cost := AbilityExec.mana_cost(n, DBAbilities.get_ab(sig)) if sig != "" else 0.0
	# an invulnerable target (dodge frames, a blessing) is not worth mana: only
	# shields, heals, buffs and escapes are used meanwhile
	var t_inv: bool = t != null and is_instance_valid(t) and t.statuses.has("invuln")
	for id in cands:
		var e: Dictionary = DBAbilities.get_ab(id)
		if e.is_empty() or n.skill_cd.has(id):
			continue
		if t_inv and str(e.get("ai", {}).get("use", "")) in ["ranged", "line", "melee", "aoe", "open", "burst", "summon", "gap", "cataclysm", "wall"]:
			continue
		var r := score(n, e, t, d)
		# only attacks wait for the big spell: walls, shields, heals and escapes never do
		if sig != "" and id != sig and e.kind == "spell" and str(e.get("ai", {}).get("use", "")) in ["ranged", "line", "melee", "aoe", "open", "burst"]:
			var c := AbilityExec.mana_cost(n, e)
			# cheap spells (≤ 15 % of the pool) stay allowed: they barely delay the big one
			if c > n.max_mana * 0.15 and n.mana - c < sig_cost and not (r.s >= 0.85):
				r.s *= 0.35
		if r.s <= bs:
			continue
		if AbilityExec.block_reason(n, id) != "":
			continue
		if not CityMagic.allowed(n, e, t.global_position if t != null and is_instance_valid(t) else n.global_position):
			stats.refused_town += 1
			continue
		bs = r.s
		best = id
		best_aim = r.aim
	if best == "" or bs < 0.3:
		return false
	var ok: bool = n.use_ability(best, best_aim)
	if ok:
		stats.used += 1
		var u := str(DBAbilities.get_ab(best).get("ai", {}).get("use", ""))
		stats.by_use[u] = int(stats.by_use.get(u, 0)) + 1
	return ok

## The spell this caster saves mana for: its summon, else its highest tier
## (never a cataclysm — those have their own limits), "" if none is worth it.
static func signature_spell(n, cands: Array) -> String:
	var best := ""
	var bv := 0.0
	for id in cands:
		var e: Dictionary = DBAbilities.get_ab(id)
		if e.is_empty() or e.kind != "spell" or n.skill_cd.has(id) or int(e.get("tier", 0)) >= 6:
			continue
		var v := float(e.tier) + (3.0 if str(e.get("ai", {}).get("use", "")) == "summon" and AbilityExec.live_summons(n).is_empty() else 0.0)
		if v > bv and AbilityExec.mana_cost(n, e) <= n.max_mana * 0.9:
			bv = v
			best = id
	return best if bv >= 3.0 else ""

static func _status_on(t, e: Dictionary) -> bool:
	for f in e.fx:
		if f.has("status") and f.status is String and t.statuses.has(f.status):
			return true
	return false

static func score(n, e: Dictionary, t, d: float) -> Dictionary:
	var ai: Dictionary = e.get("ai", {})
	var use := str(ai.get("use", ""))
	var rng := float(ai.get("rng", 6.0))
	var dir: Vector3 = n.facing
	var tv: bool = t != null and is_instance_valid(t) and not t.is_dead
	if tv:
		var to: Vector3 = t.global_position - n.global_position
		to.y = 0
		if to.length() > 0.01:
			dir = to.normalized()
	var s := 0.0
	var hpf: float = n.hp / maxf(1.0, n.max_hp)
	match use:
		"ranged", "line":
			if tv and d <= rng and d > 2.0:
				s = 0.5
				if use == "line":
					s += 0.12 * _foes_near(n, t.global_position, 3.0)
		"melee":
			if tv and d <= rng:
				s = 0.55
		"aoe":
			if tv and d <= rng + 1.0:
				var k := _foes_near(n, t.global_position, 4.0)
				s = 0.25 + 0.2 * k
		"open":
			if tv and d <= rng and not _status_on(t, e):
				s = 0.45 + (0.15 if t.hp > t.max_hp * 0.5 else 0.0)
		"interrupt":
			if tv and d <= rng and not t.act.is_empty() and t.act.name in ["skill", "spell", "charge"]:
				s = 0.95
		"gap":
			if tv and d > 3.5 and d <= rng:
				s = 0.5
		"burst":
			if tv and d <= rng and t.hp > t.max_hp * 0.35:
				s = 0.45 + (0.2 if t.kind == "boss" or t.get("elite") == true else 0.0)
		"defend":
			var has_shield := false
			for f in e.fx:
				if f.c == "shield" or (f.c == "buff" and str(f.get("status", "")) == "deflect"):
					has_shield = true
			if has_shield:
				# shields go up as soon as a fight is on, not only when cornered
				if not n.statuses.has("magic_shield") and not n.statuses.has("deflect") and tv and d < 18.0:
					s = 0.5 + (0.2 if hpf < 0.7 else 0.0)
			else:
				var close := _foes_near(n, n.global_position, maxf(3.0, rng))
				if close > 0 and (hpf < 0.75 or close >= 2):
					s = 0.5 + 0.1 * close
		"wall":
			# shot at from afar: raise a wall between us
			if tv and d > 6.0 and t.has_method("is_ranged") and t.is_ranged():
				s = 0.8
		"summon":
			var mine := AbilityExec.live_summons(n)
			var same := mine.filter(func(m): return m.get_meta("ab", "") == e.id).size()
			if same == 0 and tv and d < 22.0:
				s = 0.65
				if e.id == "n_raise_servant" and AbilityExec.near_recent_death(n.global_position, 10.0):
					s = 0.9
				if hpf < 0.6:
					s += 0.15
		"buff":
			var key := AbilityExec._sustain_status(e)
			if key != "" and not n.statuses.has(key) and tv and d < 18.0:
				s = 0.5 + (0.2 if key == "magic_shield" and hpf < 0.7 else 0.0)
		"heal":
			var worst = null
			var wr := 1.0
			for a in AbilityExec.allies_in(n, n.global_position, 10.0):
				var r: float = a.hp / maxf(1.0, a.max_hp)
				if r < wr:
					wr = r
					worst = a
			if worst != null and wr < 0.6:
				s = 0.9 - wr * 0.5
				if worst != n:
					dir = (worst.global_position - n.global_position).normalized()
			# cleansing / bleeding: something to remove on ourselves
			for f in e.fx:
				for k in f.get("cleanse", []):
					if n.statuses.has(k):
						s = maxf(s, 0.7)
		"escape":
			if hpf < 0.35 and _foes_near(n, n.global_position, 5.0) > 0:
				s = 0.8
				dir = -dir
		"cataclysm":
			if tv and d <= rng and _foes_near(n, t.global_position, float(e.fx[0].get("r", 10.0)) * 0.6) >= 3:
				s = 0.95
	if s <= 0.0:
		return {"s": 0.0, "aim": dir}
	# line of sight for anything aimed at the target
	if use in ["ranged", "line", "open", "aoe", "burst", "cataclysm"] and tv and not Combat.line_of_sight(n.chest(), t.chest()):
		s *= 0.2
	# specialisation: the NPC's best schools are used more
	if e.kind == "spell":
		s *= 0.8 + 0.015 * n.data.school_level(e.school)
		# keep mana for healing if this NPC is a healer
		if is_healer(n) and e.school != "heal" and n.mana - AbilityExec.mana_cost(n, e) < n.max_mana * 0.35:
			s *= 0.4
	return {"s": s, "aim": dir}

static func _foes_near(n, p: Vector3, r: float) -> int:
	var k := 0
	for a in Game.actors_near(p, r):
		if a != n and not a.is_dead and Game.can_damage(n, a):
			k += 1
	return k
