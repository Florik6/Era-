extends Node
## Magical Resonance: every pair reacts, thresholds/cool-downs/limits hold,
## projectiles meet in the air, spells cast by NPCs react against each other,
## a zone partner reacts, and a catastrophe goes through the World Director
## (sphere, chronicle, panic, guards, anomaly, rift). Prints
## RES_DONE pass=N fail=M.

func _ready() -> void:
	seed(4242)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Profile.new_character("Резонанс", "mage", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 0, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func frames(n: int) -> void:
		for i in n:
			await get_tree().physics_frame
	func _ready() -> void:
		_run()
	func open_spot() -> void:
		var w = Game.world
		var pl = Game.player
		var space = pl.get_world_3d().direct_space_state
		var base: Vector3 = pl.global_position
		for tries in 60:
			var a := randf() * TAU
			var p: Vector3 = base + Vector3(cos(a), 0, sin(a)) * randf_range(20.0, 160.0)
			w.terrain.force_load_around(p)
			p.y = w.ground_height(p) + 0.3
			if w.is_water(p):
				continue
			var clear := true
			for k in 8:
				var d := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + d * 14.0, 1)
				q.exclude = [pl.get_rid()]
				if not space.intersect_ray(q).is_empty():
					clear = false
					break
			if clear:
				w._teleport(pl, p)
				await frames(4)
				return
	func reset(res) -> void:
		res.reset()
		for z in res.active:
			if is_instance_valid(z):
				z.queue_free()
		res.active.clear()
		res.clock += 10.0
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 9999.0)
		w.director.set_process(false)
		await open_spot()
		var res = w.sys("resonance")
		ck("resonance subsystem attached", res != null and Resonance.inst == res)
		var c: Vector3 = pl.global_position + Vector3(0, 0, 8)
		c.y = w.ground_height(c)
		# --- each pair
		var pairs := [["fire", "ice", "steam"], ["lightning", "space", "node"], ["dark", "fire", "vortex"], ["time", "time", "instability"]]
		var i := 0
		var found := {}
		for pr in pairs:
			reset(res)
			var p: Vector3 = c + Vector3(i * 14.0, 0, 0)
			var n0: int = res.stats.reactions
			Resonance.imprint(pr[0], p, 30.0, "normal", null)
			Resonance.imprint(pr[1], p + Vector3(1.5, 0, 0), 30.0, "normal", null)
			await frames(2)
			ck("%s + %s → %s" % [pr[0], pr[1], pr[2]], res.stats.reactions == n0 + 1 and res.last.get("kind", "") == pr[2], "last %s" % res.last.get("kind", "-"))
			for z in res.active:
				if is_instance_valid(z):
					found[z.kind] = true
			i += 1
		ck("each reaction leaves its zone (steam / node / vortex / instability)", found.has("steam") and found.has("node") and found.has("vortex") and found.has("instability"), str(found.keys()))
		# --- non-pairs and thresholds
		reset(res)
		var n1: int = res.stats.reactions
		Resonance.imprint("fire", c, 40.0, "normal", null)
		Resonance.imprint("fire", c, 40.0, "normal", null)
		Resonance.imprint("ice", c + Vector3(30, 0, 0), 40.0, "normal", null)
		Resonance.imprint("lightning", c + Vector3(31, 0, 0), 40.0, "normal", null)
		ck("non-pairs (fire+fire, ice+lightning) don't react", res.stats.reactions == n1)
		reset(res)
		Resonance.imprint("fire", c, 10.0, "normal", null)
		Resonance.imprint("ice", c, 12.0, "normal", null)
		ck("weak pair below the threshold doesn't react", res.stats.reactions == n1 and res.stats.blocked_power > 0)
		reset(res)
		Resonance.imprint("fire", c, 14.0, "empowered", null)
		Resonance.imprint("ice", c, 14.0, "empowered", null)
		ck("empowered tier lifts the same pair over the threshold", res.stats.reactions == n1 + 1)
		reset(res)
		Resonance.imprint("fire", c, 30.0, "normal", null)
		Resonance.imprint("ice", c + Vector3(12, 0, 0), 30.0, "normal", null)
		ck("too far apart doesn't react", res.stats.reactions == n1 + 1)
		# --- window
		reset(res)
		Resonance.imprint("fire", c, 30.0, "normal", null)
		res.clock += Resonance.WINDOW + 0.5
		Resonance.imprint("ice", c, 30.0, "normal", null)
		ck("imprints expire after the window", res.stats.reactions == n1 + 1)
		# --- area cool-down
		reset(res)
		var n2: int = res.stats.reactions
		Resonance.imprint("fire", c, 30.0, "normal", null)
		Resonance.imprint("ice", c, 30.0, "normal", null)
		Resonance.imprint("fire", c + Vector3(1, 0, 0), 30.0, "normal", null)
		Resonance.imprint("ice", c + Vector3(1, 0, 0), 30.0, "normal", null)
		ck("area cool-down blocks a second reaction on the spot", res.stats.reactions == n2 + 1 and res.stats.blocked_cd > 0)
		# --- concurrent limit
		reset(res)
		var n3: int = res.stats.reactions
		for k in 5:
			var pk: Vector3 = c + Vector3(-40.0 + k * 9.0, 0, 20.0)
			Resonance.imprint("dark", pk, 30.0, "normal", null)
			Resonance.imprint("fire", pk, 30.0, "normal", null)
		var live := 0
		for z in res.active:
			if is_instance_valid(z):
				live += 1
		ck("no more than %d reaction zones at once" % Resonance.MAX_ACTIVE, live <= Resonance.MAX_ACTIVE and res.stats.blocked_limit > 0, "live %d, reactions +%d" % [live, res.stats.reactions - n3])
		ck("imprint list stays bounded", res.imprints.size() <= Resonance.MAX_IMPRINTS)
		# --- zone partner: frostbolt projectile lands in a fire wall
		reset(res)
		var n4: int = res.stats.reactions
		var fz := Zone.create("fire", null, c + Vector3(0, 0, 6), 1.6, 6.0, {"amount": 12.0, "dtype": "fire"})
		await frames(1)
		var dummy = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], c + Vector3(0, 0, 6), 1)
		dummy.base_speed = 0.0
		var pr2 := Projectile.spawn(pl, pl.chest(), (c + Vector3(0, 1, 6) - pl.chest()).normalized() * 26.0, {"amount": 30.0, "dtype": "ice", "status": {}}, "magic", {"range": 30.0})
		await wait(1.2)
		ck("frost projectile landing in a fire wall → steam", res.stats.reactions > n4 and res.last.get("kind", "") == "steam", "last %s" % res.last.get("kind", "-"))
		ck("fire and ice cancel: the fire zone dies down", not is_instance_valid(fz) or fz.life <= 0.7)
		if is_instance_valid(dummy):
			dummy.queue_free()
		# --- projectiles meet in the air
		reset(res)
		var ca = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], c + Vector3(-10, 0, 14), 1)
		var cb = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], c + Vector3(10, 0, 14), 1)
		ca.base_speed = 0.0
		cb.base_speed = 0.0
		ca.team = "bot"
		ca.add_aggro(cb, 600.0)
		cb.add_aggro(ca, 600.0)
		var cl0: int = res.stats.clashes
		var n5: int = res.stats.reactions
		var y := Vector3(0, 1.2, 0)
		Projectile.spawn(ca, c + Vector3(-6, 0, 14) + y, Vector3(18, 0, 0), {"amount": 30.0, "dtype": "fire", "status": {}}, "fireball", {"range": 20.0})
		Projectile.spawn(cb, c + Vector3(6, 0, 14) + y, Vector3(-18, 0, 0), {"amount": 30.0, "dtype": "ice", "status": {}}, "magic", {"range": 20.0})
		await wait(0.9)
		ck("opposing projectiles meet in the air", res.stats.clashes > cl0)
		ck("the mid-air meeting of fire and ice reacts", res.stats.reactions > n5)
		# --- NPC vs NPC with real spells
		reset(res)
		var n6: int = res.stats.reactions
		ca.global_position = c + Vector3(-4, 0, 24)
		cb.global_position = c + Vector3(4, 0, 24)
		await frames(3)
		var tgt: Vector3 = c + Vector3(0, 0, 24)
		ca.skill_cd.clear()
		cb.skill_cd.clear()
		ca.act = {}
		cb.act = {}
		Spells.cast_free(ca, "nova", Vector3.FORWARD, 40.0)
		var spot := Zone.create("fire", cb, tgt, 4.0, 4.0, {"amount": 14.0, "dtype": "fire"})
		await wait(1.0)
		ck("NPC spells react with each other (dark nova into a fire field)", res.stats.reactions > n6, "last %s" % res.last.get("kind", "-"))
		if res.stats.reactions > n6:
			ck("the reaction has an NPC owner, not the hero", res.last.owner != pl)
		else:
			ck("the reaction has an NPC owner, not the hero", false)
		for a in [ca, cb]:
			if is_instance_valid(a):
				a.queue_free()
		if is_instance_valid(spot):
			spot.queue_free()
		# --- spell tiers
		var mg = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], c + Vector3(0, 0, -10), 1)
		ck("tier: normal monster cast is normal", Spells.tier_for(mg, "fireball", "fire", false) == "normal")
		mg.elite = true
		ck("tier: elite cast is empowered", Spells.tier_for(mg, "fireball", "fire", false) == "empowered")
		ck("tier: hero ultimate is ultimate", Spells.tier_for(pl, "meteor", "fire", true) == "ultimate")
		mg.queue_free()
		# --- catastrophe via the World Director (power)
		reset(res)
		w.director.resonance_rift_chance = 1.0
		var guard = w.spawner.spawn_villager(w.gen.settlements[0], c + Vector3(30, 0, 0), "guard")
		var vill = w.spawner.spawn_villager(w.gen.settlements[0], c + Vector3(8, 0, 3), "villager")
		await frames(3)
		var ch0: int = Chronicle.events.size()
		var ev0: int = w.director.events.size()
		Resonance.imprint("fire", c, 90.0, "ultimate", pl)
		Resonance.imprint("ice", c, 40.0, "empowered", null)
		await frames(2)
		ck("strong ultimate pair → catastrophe", res.stats.catastrophes >= 1, "power %.0f" % res.last.get("power", 0.0))
		var rev = null
		for e in w.director.events:
			if e.type == "resonance":
				rev = e
		ck("the director runs it as a world event", rev != null and w.director.events.size() > ev0)
		var has_chron := false
		for k in range(ch0, Chronicle.events.size()):
			if Chronicle.events[k].type == "resonance_catastrophe":
				has_chron = true
		ck("chronicle entry written", has_chron)
		ck("an anomaly zone lingers", rev != null and rev.data.get("anomaly") != null and is_instance_valid(rev.data.anomaly))
		ck("villager panics (flees from the spot)", is_instance_valid(vill) and vill.brain.goal == "flee" and vill.brain.flee_pos != Vector3.INF, "goal %s" % (vill.brain.goal if is_instance_valid(vill) else "-"))
		ck("guard goes to check the disturbance", is_instance_valid(guard) and guard.brain.goal == "travel" and guard.has_meta("investigating"), "goal %s" % (guard.brain.goal if is_instance_valid(guard) else "-"))
		await wait(8.6)
		ck("the anomaly tears into a real rift", rev != null and rev.data.get("portal") != null and is_instance_valid(rev.data.portal))
		if rev != null and rev.data.get("portal") != null and is_instance_valid(rev.data.portal):
			var portal = rev.data.portal
			ck("the rift is temporary and enterable", portal.data.data.get("temporary", false) and portal.rift_block_reason() == "", portal.rift_block_reason())
		# --- global catastrophe cool-down
		var cat1: int = res.stats.catastrophes
		res.recent.clear()
		Resonance.imprint("fire", c + Vector3(40, 0, 40), 90.0, "ultimate", pl)
		Resonance.imprint("ice", c + Vector3(40, 0, 40), 40.0, "empowered", null)
		ck("catastrophes have a long global cool-down", res.stats.catastrophes == cat1)
		# --- event ends cleanly
		rev.t = rev.dur
		w.director._tick_event(rev, 0.1)
		await wait(0.5)
		ck("the event ends and cleans up its rift", not rev in w.director.events and (rev.data.get("portal") == null or not is_instance_valid(rev.data.portal)))
		print("RES_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
