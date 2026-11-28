extends Node
## «Ammo & Mana Overhaul» — the mandatory tests, run in the real game world.
## AMMO (A1–A10): pulse rifle 30 shots then nothing, boosted shot = 5 units,
##   automatic fire pays every shot, reload only from the reserve, reload
##   interrupted by dodge / stun / firing (nothing created or lost), bows and
##   crossbows spend arrows / bolts, weapon swap keeps each magazine, saves
##   keep magazine / reserve / ammo type / mode, no free refill on stat
##   recalculation (the old bug), special ammo / storage / shop / craft /
##   loot, weapon skills pay rounds.
## MANA (M1–M12): exact spell cost, refusal without mana (never negative),
##   pause after a cast, regeneration out of / in combat, capped bonuses,
##   catastrophic spells cannot be spammed, tier price bands, mana potions,
##   leech cap, saves / inventory / gear never refill, Hardcore healing paid
##   only for a real result; plus NPC / boss resource limits.
## Prints AMMO_MANA_DONE pass=N fail=M.

func _ready() -> void:
	seed(515151)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Стрелок", "mage", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 515151
	Profile.current_era = 0
	Settings.cinematics = 0
	Settings.auto_reload = false
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var shots := 0          # projectiles the hero really fired
	var last_info := {}
	var w
	var pl

	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")

	func rwait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()

	func _on_fx(n: Node) -> void:
		if n is Projectile and n.src == pl:
			shots += 1
			last_info = n.info

	func _run() -> void:
		await rwait(3.0)
		w = Game.world
		pl = Game.player
		pl.apply_status("invuln", 999999.0)
		pl.apply_status("test_cool", 999999.0, {"no_heat": true})   # energy overheating is not under test
		w.director._t = -100000.0
		for sn in ["events2", "beasts"]:
			if w.sys(sn):
				w.sys(sn).enabled = false
		TimeFX.inst.set_base(1.0)
		w.fx_root.child_entered_tree.connect(_on_fx)
		_clear_foes()
		await _ammo_tests()
		await _mana_tests()
		await _ai_tests()
		print("AMMO_MANA_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()

	func _clear_foes() -> void:
		for a in Game.actors_near(pl.global_position, 80.0):
			if a != pl and not a.is_dead and Game.can_damage(a, pl):
				a.queue_free()

	# ------------------------------------------------------------ helpers
	func give(base: String, n: int) -> void:
		if n <= 0:
			return
		var it := ItemDB.create(base, 0, 1, null, false)
		it.qty = n
		pl.data.inv.add(it)

	func take_all(base: String) -> void:
		var c: int = pl.data.inv.count(base)
		if c > 0:
			pl.data.inv.consume(base, c)

	func arm(base: String) -> Dictionary:
		for it in pl.data.inv.items:
			if it.base == base:
				pl.equip_item(it)
				return pl.weapon()
		if pl.weapon().get("base", "") == base:
			return pl.weapon()
		var nw := ItemDB.create(base, 0, 5, null, false)
		pl.data.inv.add(nw)
		pl.equip_item(nw)
		return pl.weapon()

	## Hold «Атака» for `secs` (automatic fire: attack() every physics frame).
	func hold_fire(secs: float) -> void:
		var end := Time.get_ticks_msec() + int(secs * 1000.0)
		while Time.get_ticks_msec() < end:
			pl.attack(pl.facing)
			await get_tree().physics_frame
		await rwait(0.3)

	func idle() -> void:
		pl.act = {}
		pl.attack_cd = 0.0
		pl.reload_t = 0.0
		pl.statuses.erase("stun")

	# ================================================================ AMMO
	func _ammo_tests() -> void:
		Settings.auto_reload = false
		# A1 — the pulse rifle: 30 shots, then not one more projectile
		var rifle := arm("pulse_rifle")
		take_all("ammo_pulse")
		Ammo.set_loaded(pl, 30)
		idle()
		shots = 0
		var dry0: int = Ammo.stats.dry_clicks
		await hold_fire(10.0)
		ck("A1 pulse rifle: 30 units → exactly 30 projectiles", shots == 30, "shots %d" % shots)
		ck("A1 …magazine empty, no infinite fire, dry clicks registered", pl.ammo == 0 and Ammo.stats.dry_clicks > dry0, "mag %d dry %d" % [pl.ammo, Ammo.stats.dry_clicks - dry0])
		shots = 0
		await hold_fire(2.0)
		ck("A1 …an empty rifle creates no projectile", shots == 0, "%d" % shots)
		ck("A1 …reload without reserve is refused", pl.reload() != "" and pl.ammo == 0)
		ck("A1 pulse rifle magazine is 30", int(ItemDB.base("pulse_rifle").mag) == 30)

		# A2 — boosted shot = 5 units (normal = 1)
		Ammo.set_loaded(pl, 12)
		idle()
		shots = 0
		pl.toggle_boost()
		ck("A2 boosted mode on (kept on the weapon item)", Ammo.boost_on(pl) and rifle.get("boost", false) and Ammo.shot_cost(pl) == 5)
		await hold_fire(4.0)
		var boost_amt := float(last_info.get("amount", 0.0))
		ck("A2 12 units → 2 boosted shots, 2 units left", shots == 2 and pl.ammo == 2, "shots %d mag %d" % [shots, pl.ammo])
		pl.toggle_boost()
		idle()
		shots = 0
		await hold_fire(2.0)
		var norm_amt := float(last_info.get("amount", 1.0))
		ck("A2 normal mode: the last 2 units = 2 shots", shots == 2 and pl.ammo == 0, "shots %d mag %d" % [shots, pl.ammo])
		ck("A2 a boosted shot hits much harder (×%d)" % int(Ammo.BOOST_MULT), boost_amt > norm_amt * 2.5, "%.0f vs %.0f" % [boost_amt, norm_amt])

		# A3 — automatic weapon: every round of a burst is paid
		arm("smg")
		take_all("ammo_pistol")
		Ammo.set_loaded(pl, int(ItemDB.base("smg").mag))
		idle()
		var before: int = pl.ammo
		shots = 0
		await hold_fire(1.2)
		var spent: int = before - pl.ammo
		ck("A3 automatic fire: projectiles == rounds spent", spent > 3 and shots == spent, "spent %d shots %d" % [spent, shots])

		# A4 — reload moves rounds from the reserve, never creates them
		arm("pulse_rifle")
		Ammo.set_loaded(pl, 0)
		take_all("ammo_pulse")
		give("ammo_pulse", 10)
		idle()
		ck("A4 reload starts with a reserve", pl.reload() == "" and pl.reload_t > 0.0)
		await rwait(2.4)
		ck("A4 10 in reserve → magazine 10, reserve 0", pl.ammo == 10 and Ammo.reserve(pl) == 0, "mag %d res %d" % [pl.ammo, Ammo.reserve(pl)])
		give("ammo_pulse", 50)
		pl.reload()
		await rwait(2.4)
		ck("A4 then 50 in reserve → 30 / 30 (total 60 conserved)", pl.ammo == 30 and Ammo.reserve(pl) == 30, "mag %d res %d" % [pl.ammo, Ammo.reserve(pl)])

		# A5 — a dodge interrupts the reload: nothing moves
		Ammo.set_loaded(pl, 5)
		take_all("ammo_pulse")
		give("ammo_pulse", 40)
		idle()
		pl.stamina = pl.max_stamina
		pl.reload()
		await rwait(0.5)
		pl.dodge(pl.facing)
		var cut_by_dodge: bool = pl.reload_t <= 0.0
		await rwait(2.5)
		ck("A5 dodge interrupts the reload", cut_by_dodge)
		ck("A5 …no rounds created or lost (5 / 40)", pl.ammo == 5 and Ammo.reserve(pl) == 40, "mag %d res %d" % [pl.ammo, Ammo.reserve(pl)])

		# A6 — a stun and firing interrupt it too; rounds are conserved
		idle()
		pl.reload()
		await rwait(0.4)
		pl.statuses.erase("invuln")
		pl.apply_status("stun", 0.3)
		pl.apply_status("invuln", 999999.0)
		var cut_by_stun: bool = pl.reload_t <= 0.0
		await rwait(2.2)
		ck("A6 a stun interrupts the reload, nothing moves", cut_by_stun and pl.ammo == 5 and Ammo.reserve(pl) == 40, "mag %d res %d" % [pl.ammo, Ammo.reserve(pl)])
		idle()
		pl.reload()
		await rwait(0.3)
		shots = 0
		await hold_fire(0.25)
		await rwait(2.2)
		ck("A6 firing with rounds left cancels the reload: mag + reserve + fired = 45", pl.ammo + Ammo.reserve(pl) + shots == 45 and shots >= 1, "mag %d res %d fired %d" % [pl.ammo, Ammo.reserve(pl), shots])

		# A7 — bows and crossbows spend arrows / bolts
		arm("bow_short")
		take_all("ammo_arrow")
		give("ammo_arrow", 3)
		idle()
		shots = 0
		await hold_fire(5.0)
		ck("A7 3 arrows → 3 shots, quiver empty, then nothing", shots == 3 and pl.data.inv.count("ammo_arrow") == 0, "shots %d left %d" % [shots, pl.data.inv.count("ammo_arrow")])
		arm("crossbow_light")
		take_all("ammo_bolt")
		give("ammo_bolt", 2)
		idle()
		shots = 0
		await hold_fire(5.0)
		ck("A7 2 bolts → 2 crossbow shots", shots == 2 and pl.data.inv.count("ammo_bolt") == 0, "shots %d" % shots)

		# A8 — weapon swap during a reload: cancelled, each weapon keeps its magazine
		var rev := arm("revolver")
		Ammo.set_loaded(pl, 2)
		var pr := arm("pulse_rifle")
		Ammo.set_loaded(pl, 10)
		for it in pl.data.inv.items.duplicate():
			if ItemDB.base(it.base).get("slot", "") == "main" and it.uid != rev.uid:
				pl.data.inv.remove(it.uid)
		take_all("ammo_pulse")
		give("ammo_pulse", 40)
		idle()
		pl.reload()
		await rwait(0.4)
		pl.swap_weapon()
		var cut_by_swap: bool = pl.reload_t <= 0.0 and pl.weapon().get("uid", -1) == rev.uid
		await rwait(2.2)
		ck("A8 swap cancels the reload", cut_by_swap, "reload_t %.2f weapon %s" % [pl.reload_t, str(pl.weapon().get("base", ""))])
		ck("A8 revolver keeps 2, rifle keeps 10, reserve 40", int(rev.get("mag_cur", -1)) == 2 and int(pr.get("mag_cur", -1)) == 10 and pl.data.inv.count("ammo_pulse") == 40,
			"rev %s rifle %s res %d" % [str(rev.get("mag_cur")), str(pr.get("mag_cur")), pl.data.inv.count("ammo_pulse")])
		arm("pulse_rifle")

		# A9 — saves: magazine, reserve, ammo type, mode; nothing duplicated
		take_all("ammo_quantum")
		give("ammo_quantum", 20)
		Ammo.set_loaded(pl, 0)
		pl.weapon()["ammo_kind"] = "ammo_quantum"
		Ammo.set_loaded(pl, 17)
		pl.weapon()["boost"] = true
		var units_before: int = pl.data.inv.count("ammo_pulse") + pl.data.inv.count("ammo_quantum") + pl.ammo
		var text := JSON.stringify(pl.data.to_dict())
		var back := CharData.new()
		back.from_dict(JSON.parse_string(text))
		var bw: Dictionary = back.inv.equipped("main")
		ck("A9 save keeps magazine 17, quantum ammo, boosted mode", int(bw.get("mag_cur", -1)) == 17 and Ammo.kind_of(bw) == "ammo_quantum" and bool(bw.get("boost", false)),
			"%s %s %s" % [str(bw.get("mag_cur")), Ammo.kind_of(bw), str(bw.get("boost"))])
		var units_after: int = back.inv.count("ammo_pulse") + back.inv.count("ammo_quantum") + int(bw.get("mag_cur", 0))
		ck("A9 …and the reserve, without duplication", units_after == units_before and back.inv.count("ammo_quantum") == 20, "%d → %d" % [units_before, units_after])
		ck("A9 the one-time old-save ammo grant is already used for this hero", bool(Profile.legacy.flags.get("ammo_v1", false)))
		pl.weapon()["boost"] = false

		# A10 — the old bug: recalculating stats refilled an empty magazine
		Ammo.set_loaded(pl, 0)
		for i in 5:
			pl.recalc_stats()
		var robe: Dictionary = pl.data.inv.equipped("chest")
		if not robe.is_empty():
			pl.unequip_slot("chest")
			pl.equip_item(robe)
		w.ui.open("inventory")
		await rwait(0.6)
		w.ui.close_all()
		await rwait(0.3)
		ck("A10 stat recalculation / gear change / inventory never refill the magazine", pl.ammo == 0, "mag %d" % pl.ammo)
		# special ammo: switching unloads into the reserve (conserved)
		pl.weapon()["ammo_kind"] = ""
		take_all("ammo_pulse")
		give("ammo_pulse", 5)
		Ammo.set_loaded(pl, 10)
		take_all("ammo_quantum")
		give("ammo_quantum", 6)
		var sel := Ammo.select_kind(pl, "ammo_quantum")
		ck("A10 loading special ammo unloads the magazine into the reserve", sel == "" and pl.ammo == 0 and pl.data.inv.count("ammo_pulse") == 15, "%s mag %d res %d" % [sel, pl.ammo, pl.data.inv.count("ammo_pulse")])
		idle()
		pl.reload()
		await rwait(2.3)
		ck("A10 …and loads 6 quantum charges from the reserve", pl.ammo == 6 and pl.data.inv.count("ammo_quantum") == 0)
		# storage at home (the real Housing transfer): to the chest and back
		Profile.homes["test_home"] = {"type": str(Housing.TYPES[0].id), "era": Profile.current_era, "furniture": [], "upgrades": {}}
		var stack: Dictionary = {}
		for it in pl.data.inv.items:
			if it.base == "ammo_pulse":
				stack = it
		var to_chest: bool = Housing.inst.move_to_chest(stack, 5)
		var split_ok: bool = Profile.home_chest.count("ammo_pulse") == 5 and pl.data.inv.count("ammo_pulse") == 10
		var c_stack: Dictionary = {}
		for it in Profile.home_chest.items:
			if it.base == "ammo_pulse":
				c_stack = it
		var to_bag: bool = Housing.inst.move_to_bag(c_stack)
		ck("A10 home chest: 5 of 15 stored and taken back, no duplication", to_chest and split_ok and to_bag and pl.data.inv.count("ammo_pulse") == 15 and Profile.home_chest.count("ammo_pulse") == 0,
			"%s %s %s inv %d chest %d" % [str(to_chest), str(split_ok), str(to_bag), pl.data.inv.count("ammo_pulse"), Profile.home_chest.count("ammo_pulse")])
		Profile.homes.erase("test_home")
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var sells_pulse := false
		for it in Ammo.shop_stock(4, rng):
			sells_pulse = sells_pulse or it.base == "ammo_pulse"
		var era0 := Profile.current_era
		Profile.current_era = 4
		var can_craft := false
		for r in Ammo.recipes_for(w, "workshop"):
			can_craft = can_craft or str(r.name).begins_with(Ammo.base("ammo_pulse").name)
		Profile.current_era = era0
		var found: Dictionary = Ammo.loot_for(pl, 4, rng)
		ck("A10 pulse charges are sold (era 4), crafted (workshop) and found (loot fits the weapon)", sells_pulse and can_craft and found.get("base", "") == "ammo_pulse", "%s %s %s" % [str(sells_pulse), str(can_craft), str(found.get("base", ""))])
		ck("A10 16 ammo types with unique ids across all eras", Ammo.ids().size() == 16 and ItemDB.has_base("ammo_plasma") and ItemDB.has_base("ammo_ball"))
		# weapon skill: «Подавляющий огонь» shoots 8 — with 3 rounds only 3 fly
		var revo := arm("revolver")
		pl.data.mastery_of("firearm").nodes.append("wf_suppressive_fire")
		Ammo.set_loaded(pl, 3)
		take_all("ammo_revolver")
		idle()
		pl.skill_cd.clear()
		pl.stamina = pl.max_stamina
		shots = 0
		var used: bool = pl.use_ability("wf_suppressive_fire", pl.facing)
		await rwait(1.6)
		ck("A10 weapon skill with 3 rounds: fires 3 of 8, magazine 0", used and shots == 3 and pl.ammo == 0, "used %s shots %d mag %d" % [str(used), shots, pl.ammo])
		pl.skill_cd.clear()
		idle()
		ck("A10 …and with an empty magazine the skill is refused", AbilityExec.block_reason(pl, "wf_suppressive_fire") != "" and not pl.use_ability("wf_suppressive_fire", pl.facing))
		revo.erase("mag_cur")

	# ================================================================ MANA
	func _mana_tests() -> void:
		var d: CharData = pl.data
		d.level = 30
		for s in DBAbilities.SCHOOL_ORDER:
			d.learn_school(s)
			d.schools[s].lvl = 26
		for e in DBAbilities.of_kind("spell"):
			if not e.id in d.spells:
				d.spells.append(e.id)
		var st := ItemDB.create("staff_oak", 0, 20, null, false)
		d.inv.add(st)
		pl.equip_item(st)
		pl.recalc_stats()
		idle()
		var weak: Dictionary = DBAbilities.school_spells("fire")[0]
		var master: Dictionary = DBAbilities.school_spells("fire")[6]
		var arch_a: Dictionary = DBAbilities.school_spells("fire")[8]
		var arch_b: Dictionary = DBAbilities.school_spells("ice")[8]
		var cata: Dictionary = DBAbilities.school_spells("earth")[9]

		# M1 — a cast costs exactly its price
		pl.mana = pl.max_mana
		pl.mana_delay_t = 0.0
		var cost: float = AbilityExec.mana_cost(pl, weak)
		var m0: float = pl.mana
		var ok1: bool = pl.use_ability(weak.id, pl.facing)
		ck("M1 a tier I spell is cast and costs exactly %d" % int(cost), ok1 and absf((m0 - pl.mana) - cost) < 0.6, "spent %.1f" % (m0 - pl.mana))
		await rwait(1.0)
		ck("M1 the mana bar shows the drop (pause after the cast)", pl.mana < pl.max_mana - cost * 0.9 and pl.mana_delay_t > 0.0)

		# M2 — not enough mana: refused, nothing spent, never negative
		idle()
		pl.skill_cd.clear()
		pl.mana = cost - 1.0
		var ref0: int = ManaSys.stats.refused_mana
		var ok2: bool = pl.use_ability(weak.id, pl.facing)
		ck("M2 too little mana → refused, nothing spent", not ok2 and absf(pl.mana - (cost - 1.0)) < 0.01 and ManaSys.stats.refused_mana == ref0 + 1)
		pl.mana = 0.0
		pl.use_ability(weak.id, pl.facing)
		ck("M2 mana never goes negative", pl.mana >= 0.0)

		# M3 — regeneration pauses after a cast (3 s, 5 s after a strong one)
		idle()
		pl.skill_cd.clear()
		pl.mana = pl.max_mana
		pl.combat_t = 100.0
		var ok3: bool = pl.use_ability(master.id, pl.facing)
		await rwait(1.5)
		var after_cast: float = pl.mana
		await rwait(2.5)
		ck("M3 strong spell (tier IV): no regeneration for 4 s after the cast", ok3 and absf(pl.mana - after_cast) < 0.01, "%.2f → %.2f" % [after_cast, pl.mana])
		await rwait(2.5)
		ck("M3 …then mana slowly returns", pl.mana > after_cast)

		# M4 — out of combat ≈ 1 % of max per second
		pl.mana = pl.max_mana * 0.5
		pl.mana_delay_t = 0.0
		pl.combat_t = 100.0
		var expect4: float = ManaSys.regen_rate(pl) * 5.0
		var a4: float = pl.mana
		await rwait(5.0)
		var got4: float = pl.mana - a4
		var pct4: float = got4 / pl.max_mana / 5.0 * 100.0
		ck("M4 out of combat: %.2f %%/s (base 1 %%/s, bonuses ≤ +100 %%)" % pct4, pct4 >= 0.6 and pct4 <= 2.05 and absf(got4 - expect4) < expect4 * 0.3 + 0.5, "got %.1f expect %.1f" % [got4, expect4])

		# M5 — in combat ≈ 0.3 %/s
		pl.mana = pl.max_mana * 0.5
		var a5: float = pl.mana
		var end5 := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < end5:
			pl.combat_t = 0.0
			await get_tree().physics_frame
		var pct5: float = (pl.mana - a5) / pl.max_mana / 5.0 * 100.0
		ck("M5 in combat: %.2f %%/s (0.2–0.6 %%/s with bonuses)" % pct5, pct5 > 0.1 and pct5 <= 0.62)

		# M6 — bonuses add up to +100 % at most, one effect never stacks with itself
		pl.combat_t = 100.0
		pl.mana_delay_t = 0.0
		var base6: float = pl.max_mana * ManaSys.REGEN_IDLE
		pl.apply_status("mana_surge", 30.0, {"k": 5.0})
		pl.apply_status("mana_surge", 30.0, {"k": 5.0})
		pl.apply_status("mana_surge", 30.0, {"k": 5.0})
		ck("M6 huge stacked bonuses are capped at ×2 of the base", ManaSys.regen_rate(pl) <= base6 * 2.0 + 0.001 and ManaSys.regen_bonus(pl) <= ManaSys.BONUS_CAP, "%.2f vs %.2f" % [ManaSys.regen_rate(pl), base6])
		pl.statuses.erase("mana_surge")
		pl._recalc_buffs()

		# M7 — catastrophic spells cannot be spammed
		idle()
		pl.skill_cd.clear()
		pl.statuses.erase("exhausted")
		AbilityExec.cataclysm_until = 0
		AbilityExec._high_until.clear()
		ck("M7 cataclysm prepared", d.set_slot("staff", 1, 0, cata.id) == "")
		give(AbilityExec.cataclysm_reagent(), 10)
		pl.mana = pl.max_mana
		var cata_cost: float = AbilityExec.mana_cost(pl, cata)
		var std24: float = DBAbilities.standard_pool(24)
		var ok7: bool = pl.use_ability(cata.id, pl.facing)
		ck("M7 the cataclysm costs ≥ 80 %% of the standard pool (after discounts ≥ 60 %%)", ok7 and DBAbilities.get_ab(cata.id).mana >= std24 * 0.8 and cata_cost >= std24 * 0.8 * AbilityExec.COST_FLOOR - 1.0, "%.0f of %.0f" % [cata_cost, std24])
		var casts := 1
		var end7 := Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < end7:
			pl.mana = pl.max_mana            # even with a full bar every time…
			if pl.act.is_empty() and pl.use_ability(cata.id, pl.facing):
				casts += 1
			await rwait(0.5)
		ck("M7 …20 s of attempts with mana refilled each time: still only 1 cataclysm", casts == 1, "%d" % casts)
		ck("M7 the caster is exhausted / the cataclysm is on cool-down", pl.skill_cd.has(cata.id) or pl.statuses.has("exhausted"))
		# with natural mana only, the second one is refused for lack of mana
		pl.skill_cd.clear()
		pl.statuses.erase("exhausted")
		AbilityExec.cataclysm_until = 0
		AbilityExec._high_until.clear()
		pl.mana = pl.max_mana * 0.3
		ck("M7 without mana the next cataclysm is refused", AbilityExec.block_reason(pl, cata.id).begins_with("недостаточно маны"), AbilityExec.block_reason(pl, cata.id))
		# archmage: one high spell at a time
		idle()
		pl.skill_cd.clear()
		pl.mana = pl.max_mana
		var okA: bool = pl.use_ability(arch_a.id, pl.facing)
		await rwait(0.2)
		idle()
		pl.mana = pl.max_mana
		var why_b := AbilityExec.block_reason(pl, arch_b.id)
		ck("M7 archmage: a second tier V spell right after the first is refused", okA and why_b != "", why_b)

		# M8 — tier price bands over all 100 spells
		var bad := []
		for e in DBAbilities.of_kind("spell"):
			var t: int = int(e.tier)
			var frac: float = float(e.mana) / DBAbilities.standard_pool(DBAbilities.TIER_SCHOOL_LVL[t])
			var band: Array = DBAbilities.TIER_BANDS[t]
			if frac < float(band[0]) - 0.01 or frac > float(band[1]) + 0.01:
				bad.append("%s %.2f" % [e.id, frac])
		ck("M8 every spell costs its tier band (5–10 / 12–20 / 25–40 / 40–55 / 60–75 / 80–100 %)", bad.is_empty() and DBAbilities.of_kind("spell").size() == 100, str(bad.slice(0, 4)))

		# M9 — mana potions
		pl.potion_mana_cd = 0.0
		for b in ManaSys.POTIONS:
			take_all(b)
		give("potion_mana_small", 2)
		give("potion_mana", 1)
		give("potion_mana_big", 1)
		give("potion_mana_elixir", 1)
		pl.mana = pl.max_mana * 0.1
		var m9: float = pl.mana
		idle()
		var small: Dictionary = {}
		for it in d.inv.items:
			if it.base == "potion_mana_small":
				small = it
		var used9: bool = pl.use_item(small)
		var expect9: float = 25.0 + pl.max_mana * 0.10
		ck("M9 small potion: +25 and 10 %% (%.0f), one potion spent" % expect9, used9 and absf(pl.mana - m9 - expect9) < 1.0 and d.inv.count("potion_mana_small") == 1, "+%.1f left %d" % [pl.mana - m9, d.inv.count("potion_mana_small")])
		var m9b: float = pl.mana
		idle()
		pl.quick_mana_potion()
		ck("M9 a second potion during the 8 s cool-down is refused and not spent", absf(pl.mana - m9b) < 0.5 and pl.mana_potion_count() == 4)
		await rwait(8.3)
		pl.mana = pl.max_mana - 5.0
		var big: Dictionary = {}
		for it in d.inv.items:
			if it.base == "potion_mana_big":
				big = it
		idle()
		pl.use_item(big)
		ck("M9 a big potion near full never exceeds the maximum", pl.mana <= pl.max_mana + 0.001 and absf(pl.mana - pl.max_mana) < 0.01 and d.inv.count("potion_mana_big") == 0)
		await rwait(8.3)
		pl.mana = pl.max_mana * 0.2
		pl.mana_delay_t = 0.0
		pl.combat_t = 100.0
		var r_before: float = ManaSys.regen_rate(pl)
		var elx: Dictionary = {}
		for it in d.inv.items:
			if it.base == "potion_mana_elixir":
				elx = it
		idle()
		pl.use_item(elx)
		var r_after: float = ManaSys.regen_rate(pl)
		ck("M9 rare elixir: temporary regeneration boost, within the cap", pl.statuses.has("mana_surge") and r_after > r_before * 1.3 and r_after <= pl.max_mana * ManaSys.REGEN_IDLE * 2.0 + 0.001, "%.2f → %.2f" % [r_before, r_after])
		pl.statuses.erase("mana_surge")
		pl._recalc_buffs()

		# M10 — mana leech is capped per second
		pl.mana = 0.0
		ManaSys.leech(pl, 1000.0)
		ManaSys.leech(pl, 1000.0)
		ManaSys.leech(pl, 1000.0)
		ck("M10 leech: at most 4 %% of max mana per second (%.1f)" % pl.mana, pl.mana <= pl.max_mana * ManaSys.LEECH_CAP + 0.01 and pl.mana > 0.0)

		# M11 — saves keep mana; inventory / gear never refill it
		pl.mana = pl.max_mana * 0.375
		pl.mana_delay_t = 2.0
		pl.potion_mana_cd = 5.0
		ManaSys.store(pl)
		var copy := CharData.new()
		copy.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())))
		var keep: Dictionary = d.vitals
		d.vitals = copy.vitals
		pl.mana = pl.max_mana
		pl.mana_delay_t = 0.0
		pl.potion_mana_cd = 0.0
		ManaSys.restore_saved(pl)
		ck("M11 load restores 37.5 %% mana, the pause and the potion cool-down", absf(pl.mana - pl.max_mana * 0.375) < 0.5 and pl.mana_delay_t > 1.5 and pl.potion_mana_cd > 4.5, "%.1f %.1f %.1f" % [pl.mana, pl.mana_delay_t, pl.potion_mana_cd])
		d.vitals = keep
		var m11: float = pl.mana
		w.ui.open("inventory")
		await rwait(1.5)
		var in_ui: float = pl.mana
		w.ui.close_all()
		var stf: Dictionary = pl.weapon()
		pl.unequip_slot("main")
		pl.equip_item(stf)
		ck("M11 opening the inventory and re-equipping gear do not refill mana", absf(in_ui - m11) < 0.5 and pl.mana <= m11 + 0.5, "%.1f → %.1f → %.1f" % [m11, in_ui, pl.mana])

		# M12 — Hardcore healing: paid only for a real result
		Profile.difficulty = "hardcore"
		var hc = Hardcore.inst
		ck("M12 Hardcore active", Hardcore.active())
		if Hardcore.active():
			hc.list().clear()
			var frac_inj: Dictionary = hc.add_injury("arm_l", "fracture", 2)
			var cut: Dictionary = hc.add_injury("leg_l", "cut", 1)
			idle()
			pl.skill_cd.clear()
			pl.statuses.erase("exhausted")
			pl.mana = pl.max_mana * 0.8
			var mh: float = pl.mana
			var why_fr := AbilityExec.cast_heal_now(pl, "h_close_wound", int(frac_inj.id))
			ck("M12 «Закрытие раны» on a fracture is refused: mana and cool-down given back", why_fr != "" and absf(pl.mana - mh) < 0.01 and not pl.skill_cd.has("h_close_wound"), "%s %.1f→%.1f" % [why_fr, mh, pl.mana])
			var hcost: float = AbilityExec.mana_cost(pl, DBAbilities.get_ab("h_close_wound"))
			var why_cut := AbilityExec.cast_heal_now(pl, "h_close_wound", int(cut.id))
			ck("M12 on a light cut it works and costs %d mana" % int(hcost), why_cut == "" and absf((mh - pl.mana) - hcost) < 0.6 and pl.skill_cd.has("h_close_wound") and bool(cut.get("treated", false)), "%s spent %.1f" % [why_cut, mh - pl.mana])
			hc.list().clear()
		Profile.difficulty = "normal"
		# the staff's basic bolt is free (mana is for spells)
		idle()
		pl.mana = 40.0
		pl.mana_delay_t = 3.0
		var mb: float = pl.mana
		pl.attack(pl.facing)
		await rwait(0.8)
		ck("extra: the staff's basic bolt costs no mana", absf(pl.mana - mb) < 0.01)

	# ============================================================ NPC / boss
	func _ai_tests() -> void:
		var arch: Dictionary = DBAbilities.school_spells("fire")[8]
		# a data-mage NPC: no cast without mana
		var caster = w.spawner.spawn_enemy("bandit", pl.global_position + pl.facing * 12.0, 10)
		if caster != null:
			caster.apply_status("root", 9999.0)
			if caster.get("brain") != null and caster.brain.has_method("shutdown"):
				caster.brain.shutdown()
		if caster != null and caster.data == null:
			caster = null
		if caster != null:
			caster.data.learn_school("fire")
			caster.data.schools["fire"].lvl = 26
			if not arch.id in caster.data.spells:
				caster.data.spells.append(arch.id)
			caster.mana = 5.0
			ck("NPC mage: «недостаточно маны» blocks a spell it cannot pay for", AbilityExec.block_reason(caster, arch.id).begins_with("недостаточно маны"), AbilityExec.block_reason(caster, arch.id))
			ck("NPC: guns are reloaded with time, never fired without rounds", Ammo.unlimited(caster) and not Ammo.unlimited(pl))
		else:
			ck("NPC mage found for the test", false)
		# a boss / monster casting for free still obeys archmage limits
		var m: Actor = w.spawner.spawn_enemy("wolf", pl.global_position + pl.facing * -12.0, 10)
		if m != null:
			m.skill_cd.clear()
			m.apply_status("exhausted", 10.0)
			ck("boss/monster: free casting of a tier V spell is blocked while exhausted", not AbilityExec.cast_free(m, arch.id, Vector3.FORWARD, 50.0))
		else:
			ck("monster found for the boss-limit test", false)
