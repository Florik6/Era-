extends Node
## Correctness of the performance LOD: far NPCs keep living (move, stay on
## the ground) with cheaper updates and return to full physics when near;
## building interiors hidden from outside and shown inside; ambient
## particles pause far away; distant enemy spell decoration is skipped
## while the hero's own effects never are. Prints LOD_DONE pass=N fail=M.

func _ready() -> void:
	seed(99)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Profile.new_character("Замер", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
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
	func _ready() -> void:
		_run()
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 9999.0)
		w.director.set_process(false)
		var lod = w.sys("perf_lod")
		ck("perf LOD and dynamic quality attached", lod != null and w.sys("dcq") != null)
		# far NPC
		var rec: Dictionary = w.legends.new_record("Путник", {"level": 2})
		var far_p: Vector3 = pl.global_position + Vector3(85, 0, 0)
		w.terrain.force_load_around(far_p)
		var n = w.spawner.spawn_bot(rec, far_p)
		await wait(1.5)
		ck("NPC 85 m away gets LOD tier 2", n.lod_tier == 2, "tier %d" % n.lod_tier)
		var p0: Vector3 = n.global_position
		n.brain.goal = "travel"
		n.brain.dest = p0 + Vector3(0, 0, 20)
		n.brain.path = [n.brain.dest]
		await wait(3.0)
		var moved := Vector2(n.global_position.x - p0.x, n.global_position.z - p0.z).length()
		ck("far NPC still moves with the cheap update", moved > 2.0, "%.1f m" % moved)
		ck("far NPC stays on the ground", absf(n.global_position.y - w.ground_height(n.global_position)) < 0.6, "dy %.2f" % (n.global_position.y - w.ground_height(n.global_position)))
		w._teleport(pl, n.global_position + Vector3(6, 0, 0))
		await wait(1.2)
		ck("near again: back to full update (tier 0)", n.lod_tier == 0, "tier %d" % n.lod_tier)
		# rig LOD: distant actor drops shadows
		var far2 = w.spawner.spawn_enemy(DBEras.era(0).enemies[0], pl.global_position + Vector3(0, 0, 50), 1)
		far2.base_speed = 0.0
		await wait(1.2)
		var shadow_on := false
		for c in far2.rig.find_children("*", "GeometryInstance3D", true, false):
			if (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadow_on = true
		ck("distant actor casts no shadow", not shadow_on)
		far2.queue_free()
		# building interiors
		var bld = null
		for b in get_tree().get_nodes_in_group("buildings"):
			if b.get("_interior") != null and b.global_position.distance_to(pl.global_position) < 400.0:
				bld = b
				break
		if bld == null:
			for s in w.gen.settlements:
				var sp := Vector3(s.pos.x, 0, s.pos.y)
				w.terrain.force_load_around(sp)
				await wait(1.0)
				for b in get_tree().get_nodes_in_group("buildings"):
					if b.get("_interior") != null:
						bld = b
						break
				if bld:
					break
		if bld:
			w._teleport(pl, bld.global_position + Vector3(0, 0.5, bld.d * 0.5 + 6.0))
			await wait(1.0)
			bld._check = 0.0
			bld._process(0.2)
			var hidden := true
			for i in bld._interior:
				if is_instance_valid(i) and i.visible:
					hidden = false
			ck("interior hidden while outside (roof covers it)", hidden, "%d items" % bld._interior.size())
			w._teleport(pl, bld.global_position + Vector3(0, 0.3, 0))
			await wait(0.5)
			bld._check = 0.0
			bld._process(0.2)
			var shown := true
			for i in bld._interior:
				if is_instance_valid(i) and not i.visible:
					shown = false
			ck("interior visible inside", shown)
		else:
			ck("found a building", false)
		# ambient particles
		await wait(1.0)
		var near_on := 0
		var far_on := 0
		var cp: Vector3 = lod.cam_pos()
		for e in lod._ambient:
			if is_instance_valid(e):
				var d: float = e.global_position.distance_to(cp)
				if e.emitting and d > lod.ambient_r + 2.0:
					far_on += 1
				elif e.emitting:
					near_on += 1
		ck("ambient particles pause beyond the radius", far_on == 0, "far emitting %d, near %d, total %d" % [far_on, near_on, lod._ambient.size()])
		# magic LOD
		var far_pos: Vector3 = pl.global_position + Vector3(0, 0, 70)
		ck("distant enemy decoration is skipped", MagicFX.lod_far(far_pos, null))
		ck("the hero's own effects are never skipped", not MagicFX.lod_far(far_pos, pl))
		ck("near effects are kept", not MagicFX.lod_far(pl.global_position + Vector3(3, 0, 0), null))
		print("LOD_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
