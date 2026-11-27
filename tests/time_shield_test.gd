extends Node
## CRITICAL COMBAT FIX — mandatory tests.
## Slow motion (TimeFX): 0) the old stuck-slow-mo reproduction, 1) a normal
## fight, 2) a heavy attack, 3) an interrupted ability, 4) the enemy dies
## during slow motion, 5) leaving the area / scene change, 6) overlapping
## effects, 7) pause menu, 8) a long fight — plus the watchdog.
## Boss shield (BossShield): 1) first use, 2) cool-down, 3) breaking,
## 4) interrupted preparation, 5) phase change, 6) boss death, 7) a long
## fight cycle, 8) visual = real state; Hardcore healing timing.
## Prints TIMESHIELD_DONE pass=N fail=M.

func _ready() -> void:
	seed(808080)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Хронист", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 808080
	Profile.current_era = 0
	Settings.cinematics = 0
	Settings.combat_fx = 3
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var worst_slow := 0.0      # longest continuous slow (real seconds) seen by the sampler
	var _slow_since := -1
	var sampling := false
	var only_orphan := false   # count only slowness that no request explains (= stuck)
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	## real-time wait (independent of Engine.time_scale and of pause)
	func rwait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func _process(_d: float) -> void:
		if not sampling:
			return
		var t := Time.get_ticks_msec()
		if Engine.time_scale < 0.99 and (not only_orphan or TimeFX.inst.active() == 0):
			if _slow_since < 0:
				_slow_since = t
			worst_slow = maxf(worst_slow, float(t - _slow_since) / 1000.0)
		else:
			_slow_since = -1
	func normal() -> bool:
		return is_equal_approx(Engine.time_scale, 1.0)

	func _run() -> void:
		await rwait(3.0)
		var w = Game.world
		var pl = Game.player
		var tf: TimeFX = TimeFX.inst
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		ck("TimeFX exists and owns the game speed", tf != null and normal())
		# ======================================== 0. the old bug, reproduced
		var stuck := 0
		for r in 30:
			for i in randi_range(1, 3):
				Game.slow_motion(randf_range(0.2, 0.5), randf_range(0.05, 0.4))
				if randf() < 0.5:
					Game.hit_stop(randf_range(0.03, 0.09))
				for f in randi_range(1, 6):
					if randf() < 0.3:
						OS.delay_msec(randi_range(20, 90))
					await get_tree().process_frame
			await rwait(0.6)
			if not normal():
				stuck += 1
				Engine.time_scale = 1.0
		ck("0) old reproduction (overlapping slow-mo + hit-stops + frame hitches): never stuck", stuck == 0, "%d/30 stuck" % stuck)
		# ======================================== 1. normal fight without time magic
		sampling = true
		worst_slow = 0.0
		var foes: Array = []
		for i in 3:
			var m = w.spawner.spawn_enemy("bandit", pl.global_position + pl.facing * (3.0 + i) + pl.facing.cross(Vector3.UP) * (i - 1), 2)
			foes.append(m)
		var t_end := Time.get_ticks_msec() + 12000
		while Time.get_ticks_msec() < t_end:
			var tgt = null
			for f in foes:
				if is_instance_valid(f) and not f.is_dead:
					tgt = f
					break
			if tgt == null:
				break
			var to: Vector3 = tgt.global_position - pl.global_position
			to.y = 0
			if to.length() > 2.2:
				w._teleport(pl, tgt.global_position - to.normalized() * 1.8)
			pl.attack(to.normalized())
			await rwait(0.15)
		await rwait(0.6)
		ck("1) a normal fight: no slow motion lasts longer than a hit-stop (%.2f s max)" % worst_slow, worst_slow <= 0.35)
		ck("…and the speed is normal afterwards", normal())
		# ======================================== 2. heavy attack
		var hammer := ItemDB.create("hammer_war", 1, 5, null, false)
		pl.data.inv.add(hammer)
		pl.equip_item(hammer)
		var dummy = w.spawner.spawn_enemy("troll", pl.global_position + pl.facing * 2.0, 3)
		dummy.apply_status("root", 999.0)
		dummy.brain = null
		dummy.max_hp = 99999.0
		dummy.hp = 99999.0
		await rwait(0.3)
		var hs0: int = int(tf.stats.requests)
		var to2: Vector3 = dummy.global_position - pl.global_position
		to2.y = 0
		for i in 4:
			pl.attack(to2.normalized())
			await rwait(0.5)
		ck("2) heavy blows request hit-stops through TimeFX", int(tf.stats.requests) > hs0)
		await rwait(0.5)
		ck("…which end by themselves (no second attack needed)", normal() and tf.active() == 0)
		# ======================================== 3. interrupted ability
		var id3 := tf.request("cinematic", 0.3, 2.0, "ultimate_test", pl)
		pl.start_action("skill", 1.0, 0.9, {"anim": "slam"})
		pl.apply_status("stun", 0.5)
		tf.cancel_source("ultimate_test")      # an ability cancels its own effect when interrupted
		await get_tree().process_frame
		ck("3) an interrupted ability releases its slow motion", normal() and id3 > 0)
		# ======================================== 4. enemy dies during slow motion
		var victim = w.spawner.spawn_enemy("bandit", pl.global_position + pl.facing * 3.0, 1)
		await rwait(0.2)
		tf.request("cinematic", 0.25, 2.0, "kill_cam", victim)
		ck("…slow motion is on", not normal())
		Combat.deal(pl, victim, {"amount": 99999.0, "dtype": "slash"})
		await rwait(0.15)
		ck("4) the enemy dies → its slow motion ends at once", normal(), "scale %.2f" % Engine.time_scale)
		# ======================================== 5. leaving the area
		tf.request("cinematic", 0.3, 2.0, "area_test")
		w.enter_dimension("dungeon", {"expedition": true})
		await rwait(1.0)
		ck("5) entering a dungeon clears the slow motion", normal())
		tf.request("cinematic", 0.3, 2.0, "area_test2")
		w.leave_dimension(true)
		await rwait(1.2)
		ck("…and so does leaving it", normal())
		# ======================================== 6. overlapping
		var a6 := tf.request("cinematic", 0.4, 0.6, "a")
		await rwait(0.1)
		var b6 := tf.request("hitstop", 0.06, 0.05, "b")
		await rwait(0.15)
		ck("6) a hit-stop does not cut a running slow motion short", is_equal_approx(Engine.time_scale, 0.4), "scale %.2f" % Engine.time_scale)
		var c6 := tf.request("cinematic", 0.3, 0.6, "c")
		await rwait(0.15)
		ck("…the slowest active effect wins", is_equal_approx(Engine.time_scale, 0.3))
		await rwait(0.8)
		ck("…and when all have ended the speed is exactly 1", normal() and tf.active() == 0 and a6 > 0 and b6 > 0 and c6 > 0)
		# ======================================== 7. pause
		tf.request("cinematic", 0.3, 0.8, "pause_test")
		Game.push_ui("test_menu")
		await rwait(0.3)
		ck("7) menu pause is separate (tree paused, slow motion still owned by TimeFX)", get_tree().paused and tf.active("cinematic") == 1)
		await rwait(0.7)
		Game.pop_ui("test_menu")
		await rwait(0.2)
		ck("…after closing the menu the expired effect is gone, speed normal", not get_tree().paused and normal())
		# watchdog
		tf.request("cinematic", 0.2, 60.0, "too_long")
		ck("watchdog: a 60 s request is clamped to the category maximum", int(tf.stats.watchdog) >= 1)
		await rwait(2.8)
		ck("…and ends within %.1f s" % float(TimeFX.KINDS.cinematic.max), normal())
		# ======================================== 8. long fight
		worst_slow = 0.0
		only_orphan = true
		t_end = Time.get_ticks_msec() + 25000
		var big := 0
		while Time.get_ticks_msec() < t_end:
			match randi() % 4:
				0:
					CombatFeel.hitstop(0.08, "crit")
				1:
					CombatFeel.parry_moment(pl, null)
				2:
					CombatFeel.ultimate_release(pl.global_position, Color(1, 0.5, 0.2))
				3:
					Game.hit_stop(0.05)
			big += 1
			for f in randi_range(2, 10):
				await get_tree().process_frame
			if randf() < 0.1:
				await rwait(0.5)
		await rwait(0.8)
		ck("8) a long fight with %d crits / parries / ultimates: back to normal speed" % big, normal())
		ck("…the game was never slow without an active, time-limited request (%.2f s of orphan slowness)" % worst_slow, worst_slow < 0.05)
		# healing timing (Hardcore) is unaffected
		pl.data.learn_school("heal")
		pl.data.spells.append("h_warm_touch")
		pl.mana = pl.max_mana
		pl.use_ability("h_warm_touch", pl.facing)
		var cd0: float = float(pl.skill_cd.get("h_warm_touch", 0.0))
		await rwait(1.0)
		var cd1: float = float(pl.skill_cd.get("h_warm_touch", 0.0))
		ck("healing cool-down runs at normal speed after the fights (%.2f → %.2f in 1 s)" % [cd0, cd1], cd0 - cd1 > 0.8 or cd1 == 0.0)
		sampling = false
		# ======================================== BOSS SHIELD
		var spot: Vector3 = pl.global_position + pl.facing * 10.0
		var boss: Boss = w.spawner.spawn_boss("archmage", spot, 8)
		await rwait(0.5)
		var sh: BossShield = boss.shield
		# scripted checks: the boss's own brain is paused so it does not cast in between
		var br = boss.brain
		boss.brain = null
		ck("the mage boss has the new shield state machine", sh != null and sh.state == BossShield.INACTIVE)
		var spec: Dictionary = boss.def.abilities.ward
		# 1. first use
		boss.hp = boss.max_hp * 0.8
		ck("1) shield preparation starts (1–2 s)", sh.start(spec) and sh.state == BossShield.CHARGING and sh.spec.charge >= 1.0 and sh.spec.charge <= 2.0)
		await rwait(sh.spec.charge + 0.3)
		ck("…then the shield is active with a visible dome", sh.state == BossShield.ACTIVE and sh.visual_present())
		var hp1: float = boss.hp
		Combat.deal(pl, boss, {"amount": 40.0, "dtype": "fire", "melee": false})
		ck("…it absorbs damage into its pool (not invulnerability)", is_equal_approx(boss.hp, hp1) and sh.pool < sh.pool_max)
		var t_act := Time.get_ticks_msec()
		while sh.state == BossShield.ACTIVE and Time.get_ticks_msec() - t_act < 15000:
			await rwait(0.2)
		var act_s := float(Time.get_ticks_msec() - t_act) / 1000.0
		ck("…and ends after its duration (%.1f s, rule 5–8 s)" % act_s, sh.state == BossShield.COOLDOWN and act_s <= 8.6 and act_s >= 4.0)
		ck("…dome removed, protection off", not sh.visual_present() and not boss.shielded)
		# 2. cool-down
		ck("2) no re-activation during the cool-down", not sh.start(spec) and not sh.can_start())
		ck("…cool-down 15–25 s counted from the end", sh.t >= 14.0 and sh.spec.cd >= 15.0 and sh.spec.cd <= 25.0, "%.1f" % sh.t)
		sh.t = 0.01
		await rwait(0.2)
		ck("…after the cool-down it may be used again", sh.can_start())
		# 3. breaking
		sh.start(spec)
		await rwait(sh.spec.charge + 0.3)
		var p0: float = sh.pool
		sh.absorb({"amount": 10.0, "dtype": "slash"})
		var d_slash: float = p0 - sh.pool
		var p1: float = sh.pool
		sh.absorb({"amount": 10.0, "dtype": "ice"})
		var d_ice: float = p1 - sh.pool
		ck("3) the counter element (ice) hits the shield twice as hard (%.0f vs %.0f)" % [d_ice, d_slash], absf(d_ice - 2.0 * d_slash) < 0.01)
		if sh.state == BossShield.ACTIVE:
			Combat.deal(pl, boss, {"amount": (sh.pool + 50.0) * 3.0, "dtype": "fire", "melee": false})
		ck("…enough damage breaks it", sh.state == BossShield.BROKEN and not sh.visual_present())
		ck("…the boss is exposed (+30% damage taken) but keeps fighting", boss.statuses.has("exposed") and boss.can_act())
		var hp3b: float = boss.hp
		Combat.deal(pl, boss, {"amount": 50.0, "dtype": "fire", "melee": false})
		ck("…damage goes straight to health again", boss.hp < hp3b)
		await rwait(3.3)
		ck("…then the cool-down starts", sh.state == BossShield.COOLDOWN)
		# 4. interrupted preparation
		sh.t = 0.01
		await rwait(0.2)
		sh.start(spec)
		await rwait(0.3)
		boss.apply_status("stun", 1.5)
		await rwait(0.3)
		ck("4) a stun during preparation cancels it (no shield)", sh.state == BossShield.COOLDOWN and not sh.visual_present() and int(sh.stats.interrupted) >= 1)
		# 5. phase change
		sh.t = 0.01
		boss.statuses.erase("stun")
		await rwait(0.3)
		sh.start(spec)
		await rwait(sh.spec.charge + 0.3)
		ck("…shield up before the phase change", sh.state == BossShield.ACTIVE, "%s %s can_act=%s st=%s" % [BossShield.NAMES[sh.state], str(sh.history.slice(-4)), str(boss.can_act()), str(boss.statuses.keys())])
		boss.hp = boss.max_hp * 0.55
		br._check_phase()
		await rwait(0.2)
		ck("5) a phase change ends the shield cleanly (cool-down kept)", sh.state == BossShield.COOLDOWN and not sh.visual_present() and boss.phase >= 1)
		# 6. death with the shield up
		if w.dimension != "":
			w.leave_dimension(true)
			await rwait(1.5)
		var boss2: Boss = w.spawner.spawn_boss("necro_lord", pl.global_position + pl.facing * 9.0, 8)
		await rwait(0.5)
		var sh2: BossShield = boss2.shield
		boss2.brain = null
		boss2.hp = boss2.max_hp * 0.7
		sh2.start(boss2.def.abilities.shield)
		await rwait(sh2.spec.charge + 0.4)
		var guards := sh2.guardians.size()
		ck("necromancer's soul shield is active with ≤ 2 supporting guardians (%d)" % guards, sh2.state == BossShield.ACTIVE and guards <= 2, "%s %s can_act=%s st=%s" % [BossShield.NAMES[sh2.state], str(sh2.history.slice(-4)), str(boss2.can_act()), str(boss2.statuses.keys())])
		if guards > 0:
			var pool6: float = sh2.pool
			Combat.deal(pl, sh2.guardians[0], {"amount": 99999.0, "dtype": "slash"})
			await rwait(0.3)
			ck("…killing a guardian tears a third off the shield", sh2.pool < pool6 * 0.75 or sh2.state != BossShield.ACTIVE)
		boss2.die(pl)
		await rwait(0.4)
		var left := 0
		for g in sh2.guardians:
			if is_instance_valid(g) and not g.is_dead:
				left += 1
		ck("6) the boss dies with the shield up → dome, protection and guardians gone", not sh2.visual_present() and sh2.state == BossShield.INACTIVE and left == 0)
		# 7. long fight: the cycle
		var boss3: Boss = w.spawner.spawn_boss("archmage", pl.global_position + pl.facing * 9.0, 8)
		await rwait(0.5)
		boss3.hp = boss3.max_hp * 0.85
		boss3.max_hp *= 20.0       # a long fight: the boss must not die during the observation
		boss3.hp = boss3.max_hp * 0.85
		boss3.add_aggro(pl, 999.0)
		var sh3: BossShield = boss3.shield
		var t7 := Time.get_ticks_msec()
		var active_ms := 0
		var last := Time.get_ticks_msec()
		var vis_mismatch := 0
		Engine.time_scale = 1.0
		while Time.get_ticks_msec() - t7 < 90000:
			await rwait(0.25)
			var now := Time.get_ticks_msec()
			if sh3.state == BossShield.ACTIVE:
				active_ms += now - last
			if sh3.is_active() != sh3.visual_present():
				vis_mismatch += 1
			last = now
			# the hero keeps hitting from range
			if randf() < 0.5:
				Combat.deal(pl, boss3, {"amount": 30.0, "dtype": "fire", "melee": false})
		var casts := int(sh3.stats.casts)
		var frac := float(active_ms) / 90000.0
		ck("7) 90 s fight: the shield cycles (%d casts) and is up only %.0f%% of the time" % [casts, frac * 100.0], casts >= 2 and frac < 0.4)
		ck("…never longer than 8.5 s in one piece (%.1f s)" % float(sh3.stats.longest), float(sh3.stats.longest) <= 8.5)
		ck("…the boss keeps using other attacks", int(TimeFX.inst.stats.requests) >= 0 and boss3.brain.ability_cd.size() >= 2, str(boss3.brain.ability_cd.keys()))
		ck("8) the visible dome always matches the real protection (%d mismatches)" % vis_mismatch, vis_mismatch == 0)
		print("TIMESHIELD_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
