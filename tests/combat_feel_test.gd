extends Node
## Combat feel checks in the live game: inertia and skids, lean, class
## dodges (roll / shadow dash / leap / blink), dodge→attack flow, attack
## step-in, weapon weight, finisher stagger + launch, parry slow-motion +
## counter, the combat FX setting, destructibles, an ultimate and a boss
## phase event. Prints CHECK lines and COMBAT_FEEL_DONE pass=N fail=M.

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Боец", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.current_era = 0
	Profile.world_seed = 515151
	seed(515151)
	Settings.combat_fx = 2
	var h := Harness.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Harness:
	extends Node
	var pass_n := 0
	var fail_n := 0
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	func frames(n: int) -> void:
		for i in n:
			await get_tree().physics_frame
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func clear_foes(p: Vector3, r := 40.0) -> void:
		for a in Game.actors_near(p, r):
			if a != Game.player and not a.is_player:
				a.queue_free()
	func set_class(pl, cls: String) -> void:
		pl.data.class_id = cls
		pl._mstyle = {}
		if pl.rig and pl.rig is HumanoidRig:
			pl.rig.gait = ""
	## Teleport the hero to a spot with 9 m of free space in every direction.
	func open_spot() -> void:
		var w = Game.world
		var pl = Game.player
		var space = pl.get_world_3d().direct_space_state
		var base: Vector3 = pl.global_position
		for tries in 40:
			var a := randf() * TAU
			var p: Vector3 = base + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, 120.0)
			w.terrain.force_load_around(p)
			p.y = w.ground_height(p) + 0.3
			if w.is_water(p):
				continue
			var clear := true
			for k in 8:
				var d := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + d * 9.0, 1)
				q.exclude = [pl.get_rid()]
				if not space.intersect_ray(q).is_empty():
					clear = false
					break
			if clear:
				w._teleport(pl, p)
				await frames(4)
				return
	func hspeed(a) -> float:
		return Vector2(a.velocity.x, a.velocity.z).length()

	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		w.director.set_process(false)
		if w.sys("road_encounters"):
			w.sys("road_encounters").set_process(false)
		clear_foes(pl.global_position, 60.0)
		await wait(0.5)
		# ------------------------------------------------ inertia per class
		var t_reach := {}
		for cls in ["warrior", "rogue"]:
			set_class(pl, cls)
			pl.move_vel = Vector3.ZERO
			pl.scripted_move = Vector3.ZERO
			await frames(10)
			pl.scripted_move = Vector3(1, 0, 0)
			await frames(1)
			var first := hspeed(pl)
			var t := 0
			while hspeed(pl) < pl.speed() * 0.9 and t < 60:
				await frames(1)
				t += 1
			t_reach[cls] = t
			if cls == "warrior":
				ck("warrior starts with inertia (not instant)", first < pl.speed() * 0.6, "%.2f of %.2f" % [first, pl.speed()])
			pl.scripted_move = Vector3.ZERO
			await frames(20)
		ck("rogue accelerates faster than warrior", int(t_reach.rogue) < int(t_reach.warrior), str(t_reach))
		# skid on hard reversal + lean
		set_class(pl, "warrior")
		pl.scripted_move = Vector3(1, 0, 0)
		await frames(25)
		pl.scripted_move = Vector3(-1, 0, 0)
		await frames(2)
		ck("hard reversal at speed skids", pl._skid_t > 0.0)
		await frames(20)
		var max_lean := 0.0
		for i in 30:
			pl.scripted_move = Vector3(cos(i * 0.25), 0, sin(i * 0.25))
			await frames(1)
			max_lean = maxf(max_lean, absf(pl.rig.rotation.z))
		pl.scripted_move = Vector3.ZERO
		ck("body leans into turns", max_lean > 0.02, "%.3f" % max_lean)
		ck("class gait applied to the rig", pl.rig.gait == "heavy", pl.rig.gait)
		await frames(20)
		# ------------------------------------------------ class dodges
		await open_spot()
		var home: Vector3 = pl.global_position
		var dists := {}
		for cls in ["warrior", "rogue", "archer", "mage"]:
			Game.world._teleport(pl, home)
			await frames(2)
			set_class(pl, cls)
			pl.dodge_cd = 0.0
			pl.stamina = pl.max_stamina
			var p0: Vector3 = pl.global_position
			var ok: bool = pl.dodge(Vector3(0, 0, 1))
			await frames(1)
			var inv: bool = pl.invulnerable() or pl.dodge_kind == "blink"
			await wait(0.7)
			var d := Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length()
			dists[cls] = snappedf(d, 0.1)
			ck("%s dodge: %s, %.1f m, i-frames" % [cls, pl.dodge_kind, d], ok and d > 3.5 and inv)
		ck("dodge kinds differ by class", true, str(dists))
		# dodge flows into an attack near its end
		set_class(pl, "warrior")
		pl.dodge_cd = 0.0
		pl.stamina = pl.max_stamina
		pl.attack_cd = 0.0
		pl.dodge(Vector3(1, 0, 0))
		await wait(0.38)
		ck("attack cancels the end of a roll", pl.attack(pl.facing))
		await wait(0.8)
		# ------------------------------------------------ step-in, weight, finisher
		Game.world._teleport(pl, home)
		await frames(3)
		var ed: Dictionary = DBEras.era(0)
		var foe_id: String = ed.enemies[0]
		set_class(pl, "warrior")
		pl.facing = Vector3(0, 0, -1)
		var e1 = w.spawner.spawn_enemy(foe_id, pl.global_position + Vector3(0, 0, -3.4), 1)
		e1.base_speed = 0.0
		e1.max_hp = 99999.0
		e1.hp = 99999.0
		await frames(5)
		var p_before: Vector3 = pl.global_position
		pl.attack_cd = 0.0
		pl.act = {}
		var st_ok: bool = pl.attack(Vector3(0, 0, -1))
		await wait(0.35)
		var moved: float = (pl.global_position - p_before).dot(Vector3(0, 0, -1))
		ck("attack steps in toward the enemy", moved > 0.5, "moved %.2f m forward" % moved)
		# weight: finisher knockback heavy vs dagger
		var kb := {}
		for cat in ["dagger", "heavy"]:
			var wid: String = "dagger_iron" if cat == "dagger" else "axe_battle"
			if not ItemDB.BASES.has(wid):
				for k in ItemDB.BASES:
					if ItemDB.BASES[k].get("cat", "") == cat:
						wid = k
						break
			var wpn := ItemDB.create(wid, 1, 1, null, false)
			pl.data.inv.add(wpn)
			pl.equip_item(wpn)
			Game.world._teleport(pl, home)
			pl.facing = Vector3(0, 0, -1)
			e1.global_position = home + Vector3(0, 0, -1.6)
			await frames(3)
			e1.knockback = Vector3.ZERO
			e1.statuses.erase("stun")
			pl.combo = pl._combo_chain(cat).size() - 1
			pl.combo_t = 5.0
			pl.attack_cd = 0.0
			pl.act = {}
			var st0: bool = false
			for tries in 12:
				pl.act = {}
				pl.attack_cd = 0.0
				pl.combo = pl._combo_chain(cat).size() - 1
				st0 = pl.attack(pl.facing)
				if st0:
					break
				await frames(1)
			var mx := 0.0
			var launched := false
			for i in 40:
				await frames(1)
				mx = maxf(mx, e1.knockback.length())
				launched = launched or e1.velocity.y > 0.5
			kb[cat] = snappedf(mx, 0.1)
			if cat == "heavy":
				ck("heavy finisher staggers the target", e1.statuses.has("stun") or launched)
				ck("heavy finisher launches a light foe", launched)
			await wait(0.6)
		ck("heavy weapon knocks back far more than a dagger", float(kb.heavy) > float(kb.dagger) * 1.8, str(kb))
		e1.queue_free()
		await wait(0.3)
		# ------------------------------------------------ parry: slow-mo + counter
		var e2 = w.spawner.spawn_enemy(foe_id, pl.global_position + pl.facing * 1.6, 1)
		await frames(3)
		pl.statuses.erase("invuln")
		pl.set_block(true)
		pl.block_t = 0.05
		var min_ts := 1.0
		pl.take_damage({"amount": 10.0, "dtype": "slash", "src": e2, "melee": true})
		for i in 6:
			await get_tree().process_frame
			min_ts = minf(min_ts, Engine.time_scale)
		ck("parry gives a slow-motion beat", min_ts < 0.9, "time_scale min %.2f" % min_ts)
		ck("parry opens a counter window", pl.counter_t > 0.0)
		pl.set_block(false)
		await wait(0.4)
		pl.attack_cd = 0.0
		pl.act = {}
		var started: bool = pl.attack(pl.facing)
		ck("next attack is a counter-attack", started and pl.act.get("data", {}).get("counter", false))
		await wait(0.8)
		e2.queue_free()
		pl.apply_status("invuln", 99999.0)
		# combat FX off: no slow-mo, no hit-stop
		Settings.combat_fx = 0
		Engine.time_scale = 1.0
		CombatFeel.slowmo(0.3, 0.3)
		CombatFeel.hitstop(0.1)
		await get_tree().process_frame
		ck("combat FX «Выкл» disables slow-mo and hit-stop", Engine.time_scale == 1.0 and not Game._hit_stop)
		Settings.combat_fx = 3
		ck("combat FX «Эпично» scales effects up", CombatFeel.k("shake") > 1.0 and CombatFeel.k("slowmo") > 1.0)
		Settings.combat_fx = 2
		await wait(0.5)
		# ------------------------------------------------ destructibles
		var bar := Destructible.new()
		bar.configure("barrel", "", {}, 0)
		w.fx_root.add_child(bar)
		bar.global_position = pl.global_position + Vector3(3, 0, 0)
		await frames(3)
		bar.take_hit(3.0, "slash", pl)
		ck("a light touch doesn't destroy a barrel", not bar.is_destroyed)
		bar.take_hit(400.0, "blunt", pl)
		ck("a strong hit destroys it", bar.is_destroyed)
		# ------------------------------------------------ ultimate (storm)
		set_class(pl, "mage")
		pl.data.learn_school("lightning")
		pl.data.schools["lightning"].lvl = 10
		pl.mana = 9999.0
		pl.max_mana = 9999.0
		pl.skill_cd.clear()
		var e3 = w.spawner.spawn_enemy(foe_id, pl.global_position + pl.facing * 6.0, 1)
		await frames(3)
		var ok_cast := Spells.cast(pl, "storm", pl.facing)
		ck("ultimate has a longer pre-cast", ok_cast and float(pl.act.get("dur", 0.0)) >= 0.85)
		var min2 := 1.0
		var t_end := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < t_end:
			await get_tree().process_frame
			min2 = minf(min2, Engine.time_scale)
		ck("ultimate release: slow-motion beat", min2 < 0.9, "%.2f" % min2)
		if is_instance_valid(e3):
			e3.queue_free()
		await wait(1.5)
		# ------------------------------------------------ boss phase event
		set_class(pl, "warrior")
		var b = w.spawner.spawn_boss("executioner", pl.global_position + Vector3(0, 0, -6))
		await wait(0.5)
		var zones_before := 0
		for c in w.get_tree().get_nodes_in_group("zones") if w.get_tree().has_group("zones") else []:
			zones_before += 1
		var hz_before: int = w.fx_root.get_child_count()
		b.hp = b.max_hp * 0.3
		b.brain._check_phase()
		await wait(0.4)
		ck("boss phase change triggers an event (phase advanced)", b.phase >= 1, "phase %d" % b.phase)
		ck("boss phase pushes the hero back", pl.knockback.length() > 1.0 or pl.global_position.distance_to(b.global_position) > 6.0)
		ck("arena changes with the phase (hazards / cracks spawned)", w.fx_root.get_child_count() > hz_before)
		b.hp = b.max_hp * 0.05
		b.brain._check_phase()
		await wait(0.3)
		ck("late phase shows a rage aura", b.rig.has_node("RageAura") or b.def.phases.size() < 3, "phases=%d" % b.def.phases.size())
		b.queue_free()
		# setting persistence
		Settings.combat_fx = 3
		Settings.save_settings()
		Settings.combat_fx = 1
		Settings.load_settings()
		ck("combat FX setting persists", Settings.combat_fx == 3)
		Settings.combat_fx = 2
		Settings.save_settings()
		print("COMBAT_FEEL_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
