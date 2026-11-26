extends Node3D
## Headless logic checks for world generation and world objects.
var fails := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		fails += 1

class FakePlayer extends Node3D:
	var is_player := true

func _ready() -> void:
	print("WORLD LOGIC TEST")
	# determinism + layout
	for e in 5:
		var a := WorldGen.new()
		a.setup(777, e)
		var b := WorldGen.new()
		b.setup(777, e)
		check(a.settlements.size() == b.settlements.size() and a.pois.size() == b.pois.size() and a.spawn_point() == b.spawn_point(), "era %d deterministic layout" % e)
		check(absf(a.height(123.4, -55.0) - b.height(123.4, -55.0)) < 0.0001, "era %d deterministic height" % e)
		var types := {}
		for p in a.pois:
			types[p.type] = types.get(p.type, 0) + 1
		check(types.get("lair", 0) == 3, "era %d has 3 boss lairs" % e)
		check(types.get("trial", 0) == 1 and types.get("fortress", 0) == 1 and types.get("mirror", 0) == 1 and types.get("witness", 0) == 1, "era %d unique POIs" % e)
		check(types.get("cp", 0) >= 10 and types.get("camp", 0) >= 10 and types.get("rift", 0) >= 4 and types.get("shrine", 0) == 2, "era %d cp/camp/rift/shrine counts %s" % [e, str(types)])
		check((types.get("tourney", 0) == 1) == (e == 0), "era %d tourney rule" % e)
		var svc := {1: "lab", 2: "workshop", 3: "terminal", 4: "terminal"}
		if svc.has(e):
			check(types.get(svc[e], 0) == a.settlements.size(), "era %d service POI per settlement" % e)
		var forts := 0
		var cap := false
		for s in a.settlements:
			if s.type in ["fort", "castle"]:
				forts += 1
			if s.name == DBEras.era(e).capital:
				cap = true
			check(s.buildings.size() >= 5 and s.buildings.size() <= 14, "era %d %s has %d buildings" % [e, s.name, s.buildings.size()])
		check(forts == 1 and cap, "era %d capital + one fortress" % e)
		var sp := a.spawn_point()
		check(not a.is_water(sp.x, sp.y), "era %d spawn on land" % e)
		check(a.nearest_place(sp) != "", "era %d nearest_place: %s" % [e, a.nearest_place(sp)])
	# streaming, buildings, persistence
	var g := WorldGen.new()
	g.setup(4242, 0)
	var st := {}
	var cs := ChunkStreamer.new()
	add_child(cs)
	cs.setup(g, st)
	var sp2 := g.spawn_point()
	var tp := Vector3(sp2.x, 0, sp2.y)
	cs.force_load_around(tp)
	check(cs.chunks.size() > 10, "force_load_around loaded %d chunks" % cs.chunks.size())
	await get_tree().physics_frame
	await get_tree().physics_frame
	# ground height vs physics ray
	var space := get_world_3d().direct_space_state
	var maxerr := 0.0
	for i in 20:
		var p := tp + Vector3(randf_range(-50, 50), 0, randf_range(-50, 50))
		var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 80, 0), p - Vector3(0, 80, 0), 1))
		if not r.is_empty() and _is_terrain(r.collider) and cs.building_at(r.position) == null and absf(r.position.y - cs.ground_height(p)) < 2.0:
			maxerr = maxf(maxerr, absf(r.position.y - cs.ground_height(p)))
	check(maxerr < 0.35, "ground_height matches collision (max err %.3f)" % maxerr)
	# buildings
	var bld: Building = null
	for arr in cs.buildings.values():
		for b in arr:
			bld = b
			break
		if bld:
			break
	check(bld != null, "buildings instanced")
	if bld:
		check(bld.contains(bld.to_global(Vector3(0, 0.5, 0))), "building.contains(interior)")
		check(not bld.contains(bld.door_out), "door_out is outside")
		check(bld.contains(bld.door_in), "door_in is inside")
		check(cs.building_at(bld.to_global(Vector3(0, 0.5, 0))) == bld, "building_at finds building")
		check(bld.interior_points.size() >= 3, "interior points")
		# roof hiding
		var fp := FakePlayer.new()
		add_child(fp)
		fp.global_position = bld.to_global(Vector3(0, 0.2, 0))
		bld.viewer = fp
		await get_tree().create_timer(0.3).timeout
		check(not bld._roof.visible, "roof hidden when viewer inside")
		fp.global_position = bld.door_out + Vector3(0, 0, 0) + (bld.door_out - bld.global_position).normalized() * 6.0
		await get_tree().create_timer(0.3).timeout
		check(bld._roof.visible, "roof visible when viewer outside")
		# cellar trapdoor
		var cellar_b: Building = null
		for arr in cs.buildings.values():
			for b in arr:
				if b.has_cellar:
					cellar_b = b
		if cellar_b:
			var tdoor = null
			for c in cellar_b.get_children():
				if c is Building.Trapdoor:
					tdoor = c
			check(tdoor != null, "trapdoor exists")
			if tdoor:
				fp.global_position = tdoor.global_position
				tdoor.interact(fp)
				check(cellar_b.in_cellar(fp.global_position), "trapdoor takes player into the cellar")
				check(cs.building_at(fp.global_position) == cellar_b, "building_at reports cellar")
		else:
			print("  (no cellar in loaded area, building a test house)")
		var tb: Building = null
		for i in 200:
			var cand := Building.new()
			cand.configure({"id": "cellar_test_%d" % i, "kind": "house", "size": Vector2(7, 6)}, 0, {"destroyed": [], "opened": []})
			if cand.has_cellar:
				tb = cand
				break
			cand.free()
		check(tb != null, "a house with a cellar can be generated")
		if tb:
			add_child(tb)
			tb.global_position = tp + Vector3(0, 200, 0)
			tb.build()
			var td2 = null
			for c in tb.get_children():
				if c is Building.Trapdoor:
					td2 = c
			check(td2 != null, "trapdoor exists")
			if td2:
				fp.global_position = td2.global_position
				td2.interact(fp)
				check(tb.in_cellar(fp.global_position), "trapdoor takes player into the cellar")
				var up = null
				for c in tb.get_node("Cellar").get_children():
					if c is Building.Trapdoor:
						up = c
				check(up != null, "cellar has an exit")
				if up:
					up.interact(fp)
					check(tb.contains(fp.global_position), "exit returns the player into the house")
				var bot := Node3D.new()
				add_child(bot)
				var before := bot.global_position
				td2.interact(bot)
				check(bot.global_position == before, "bots cannot use trapdoors")
	# destructibles: hit, destroy, persistence across reload
	var d: Destructible = null
	for n in get_tree().get_nodes_in_group("destructibles"):
		if n.kind == "crate" and not n.is_destroyed:
			d = n
			break
	check(d != null, "found a crate")
	if d:
		var uid := d.uid
		d.take_hit(5.0, "slash", null)
		check(not d.is_destroyed and d.hp < d.max_hp, "crate damaged")
		d.take_hit(100.0, "blunt", null)
		check(d.is_destroyed and d.collision_layer == 0, "crate destroyed, no collision")
		var found := false
		for k in st:
			if uid in st[k].destroyed:
				found = true
		check(found, "destroyed id persisted in chunk state")
	# fire spreads to flammables
	var door: Destructible = null
	for n in get_tree().get_nodes_in_group("destructibles"):
		if n.kind == "door" and not n.is_destroyed:
			door = n
			break
	if door:
		door.take_hit(1.0, "fire", null)
		check(door.burning, "fire ignites a wooden door")
	# chest open persistence
	var ch: Chest = null
	for n in get_tree().get_nodes_in_group("chests"):
		if not n.opened and not n.is_mimic:
			ch = n
			break
	check(ch != null, "found a closed chest")
	if ch:
		var cuid := ch.uid
		ch.interact(null)
		check(ch.opened, "chest opened")
		var f2 := false
		for k in st:
			if cuid in st[k].opened:
				f2 = true
		check(f2, "opened chest persisted")
	# reload: unload all and rebuild -> destroyed/open state restored
	cs.unload_all()
	await get_tree().process_frame
	cs.force_load_around(tp)
	var restored := true
	if d:
		for n in get_tree().get_nodes_in_group("destructibles"):
			if is_instance_valid(n) and n.uid == d.uid and not n.is_destroyed:
				restored = false
	check(restored, "destroyed crate stays destroyed after reload")
	# water freezing + ice wall
	var wp := Vector3.ZERO
	var found_w := false
	for i in 4000:
		var x := randf_range(-1100, 1100)
		var z := randf_range(-1100, 1100)
		if g.is_water(x, z):
			wp = Vector3(x, g.water_level, z)
			found_w = true
			break
	check(found_w, "found water")
	if found_w:
		var n_ice := WorldFX.freeze_water(self, g, wp, 6.0)
		check(n_ice > 0, "freeze_water made %d ice cells" % n_ice)
	var wall := WorldFX.spawn_ice_wall(self, tp, Vector3(1, 0, 0), 2.0)
	check(wall != null and wall.collision_layer == 1, "ice wall spawned on world layer")
	# overview
	var img := g.overview_image(64)
	check(img.get_width() == 64, "overview image")
	print("WORLD_LOGIC_DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Only the heightmap counts as ground (props, fences and wells have colliders too).
func _is_terrain(c) -> bool:
	if c == null or not (c is Node):
		return false
	for ch in c.get_children():
		if ch is CollisionShape3D and ch.shape is HeightMapShape3D:
			return true
	return false
