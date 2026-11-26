extends Node
## Combat Clash rules (type, direction, timing) between NPCs, and the
## perfect parry of a boss's heavy attack. Prints CLASH_DONE pass=N fail=M.

func _ready() -> void:
	seed(777)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Profile.new_character("Дуэлянт", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var spot := Vector3.ZERO
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
		for tries in 60:
			var a := randf() * TAU
			var p: Vector3 = pl.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(20.0, 140.0)
			w.terrain.force_load_around(p)
			p.y = w.ground_height(p) + 0.2
			if w.is_water(p):
				continue
			var clear := true
			for k in 8:
				var d := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0) + d * 10.0, 1)
				q.exclude = [pl.get_rid()]
				if not space.intersect_ray(q).is_empty():
					clear = false
					break
			if clear:
				spot = p
				w._teleport(pl, p + Vector3(0, 0, -12))
				await frames(4)
				return
	func fighter(weapon: String, pos: Vector3):
		var w = Game.world
		var rec: Dictionary = w.legends.new_record("Боец", {"level": 6, "class_id": "warrior"})
		var n = w.spawner.spawn_bot(rec, pos)
		var it := ItemDB.create(weapon, 0, 6, null, false)
		n.data.inv.add(it)
		n.data.inv.equip_item(it)
		n.refresh_gear()
		n.brain = null
		n.max_hp = 2000.0
		n.hp = 2000.0
		return n
	func pair(wa: String, wb: String, dist := 2.0):
		var a = fighter(wa, spot + Vector3(-dist * 0.5, 0, 0))
		var b = fighter(wb, spot + Vector3(dist * 0.5, 0, 0))
		await frames(3)
		a.global_position = spot + Vector3(-dist * 0.5, 0, 0)
		b.global_position = spot + Vector3(dist * 0.5, 0, 0)
		a.face_dir(Vector3.RIGHT)
		b.face_dir(Vector3.LEFT)
		a.add_aggro(b, 600.0)
		b.add_aggro(a, 600.0)
		a.set_meta("clash_cd", 0.0)
		b.set_meta("clash_cd", 0.0)
		await frames(2)
		return [a, b]
	func strike(x, anim: String, fin: bool, delay := 0.0) -> void:
		x.act = {}
		x.start_action("melee", 0.6, 0.5, {"anim": anim, "mult": 1.0, "finisher": fin})
		x.act.t = -delay
	func cleanup(arr: Array) -> void:
		for x in arr:
			if is_instance_valid(x):
				x.queue_free()
		await frames(2)
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 9999.0)
		w.director.set_process(false)
		await open_spot()
		# 1. strong vs strong
		var ab: Array = await pair("hammer_war", "hammer_war")
		var a = ab[0]
		var b = ab[1]
		var c0 := Clash.count
		var ha: float = a.hp
		var hb: float = b.hp
		strike(a, "overhead", true)
		strike(b, "overhead", true)
		await wait(0.5)
		ck("strong vs strong facing, same moment → clash", Clash.count == c0 + 1 and Clash.last.get("kind", "") == "strong", "count +%d" % (Clash.count - c0))
		ck("neither strike deals damage", a.hp == ha and b.hp == hb, "%.0f/%.0f" % [ha - a.hp, hb - b.hp])
		var win = Clash.last.get("winner")
		var lose = Clash.last.get("loser")
		ck("the winner gets a counter window, the loser is staggered", win != null and win.counter_t > 0.0 and lose.statuses.has("stun"))
		ck("both are thrown back", a.global_position.x < spot.x - 1.0 and b.global_position.x > spot.x + 1.0, "%.2f / %.2f" % [a.global_position.x - spot.x, b.global_position.x - spot.x])
		await cleanup([a, b])
		# 2. strong vs light
		ab = await pair("hammer_war", "dagger_iron")
		a = ab[0]
		b = ab[1]
		c0 = Clash.count
		hb = b.hp
		strike(a, "overhead", true)
		strike(b, "stab", false)
		await wait(0.5)
		ck("strong vs light → the light strike breaks", Clash.count == c0 + 1 and Clash.last.get("kind", "") == "break" and Clash.last.get("loser") == b)
		ck("the strong strike goes through", b.hp < hb, "%.0f dmg" % (hb - b.hp))
		await cleanup([a, b])
		# 3. light vs light
		ab = await pair("dagger_iron", "dagger_iron")
		a = ab[0]
		b = ab[1]
		c0 = Clash.count
		strike(a, "stab", false)
		strike(b, "stab", false)
		await wait(0.5)
		ck("light vs light → no clash (normal exchange)", Clash.count == c0)
		await cleanup([a, b])
		# 4. direction: one turned away
		ab = await pair("hammer_war", "hammer_war")
		a = ab[0]
		b = ab[1]
		b.face_dir(Vector3.RIGHT)
		await frames(2)
		c0 = Clash.count
		strike(a, "overhead", true)
		strike(b, "overhead", true)
		b.face_dir(Vector3.RIGHT)
		await wait(0.5)
		ck("not facing each other → no clash", Clash.count == c0)
		await cleanup([a, b])
		# 5. timing: the other strike lands half a second later
		ab = await pair("hammer_war", "hammer_war")
		a = ab[0]
		b = ab[1]
		c0 = Clash.count
		strike(a, "overhead", true)
		strike(b, "overhead", true, 0.5)
		await wait(0.35)
		ck("strikes far apart in time → no clash", Clash.count == c0)
		await cleanup([a, b])
		# 6. boss: perfect parry of a heavy attack
		var bosses: Array = DBEras.era(0).bosses
		var boss = w.spawner.spawn_boss(bosses[0], spot + Vector3(3.0, 0, 0), 5)
		await frames(3)
		boss.brain = null if boss.get("brain") != null else null
		boss.set_physics_process(true)
		boss.global_position = spot + Vector3(3.0, 0, 0)
		w._teleport(pl, spot + Vector3(0.5, 0, 0))
		await frames(3)
		pl.statuses.erase("invuln")
		pl.hp = pl.max_hp
		pl.face_dir((boss.global_position - pl.global_position).normalized())
		boss.face_dir((pl.global_position - boss.global_position).normalized())
		pl.set_block(true)
		pl.block_t = 0.05
		var php: float = pl.hp
		var bp0 := Clash.boss_parries
		Combat.deal(boss, pl, {"amount": 60.0, "dtype": "slash", "src": boss, "melee": true, "heavy": true, "knock": 4.0})
		ck("perfect parry of a boss heavy attack → unique reaction", Clash.boss_parries == bp0 + 1)
		ck("no damage taken", pl.hp == php, "%.0f" % (php - pl.hp))
		ck("the boss reels (long stagger despite boss stun resistance)", boss.statuses.has("stun") and float(boss.statuses.stun.t) >= 1.5)
		ck("the boss is left vulnerable", boss.statuses.has("vulnerable"))
		ck("the hero gets a long counter window on the boss", pl.counter_t >= 1.9 and pl.counter_target == boss)
		var info1 := {"amount": 50.0, "dtype": "slash", "melee": true}
		var bhp: float = boss.hp
		Combat.deal(null, boss, info1.duplicate())
		var d_vuln: float = bhp - boss.hp
		boss.statuses.erase("vulnerable")
		bhp = boss.hp
		Combat.deal(null, boss, info1.duplicate())
		var d_norm: float = bhp - boss.hp
		ck("vulnerable boss takes more damage", d_vuln > d_norm * 1.3, "%.0f vs %.0f" % [d_vuln, d_norm])
		pl.set_block(false)
		pl.block_t = 1.0
		# 7. a normal (non-perfect) block of the same attack is just a block
		boss.statuses.erase("stun")
		pl.set_block(true)
		pl.block_t = 5.0
		bp0 = Clash.boss_parries
		php = pl.hp
		Combat.deal(boss, pl, {"amount": 60.0, "dtype": "slash", "src": boss, "melee": true, "heavy": true, "knock": 4.0})
		ck("late block is not a perfect parry (damage reduced, no stagger)", Clash.boss_parries == bp0 and pl.hp < php and not boss.statuses.has("vulnerable"))
		pl.set_block(false)
		pl.apply_status("invuln", 9999.0)
		print("CLASH_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
