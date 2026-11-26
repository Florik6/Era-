extends Node
## Road network logic test: determinism, connectivity, trails to POIs,
## bridges, crossroads, query API and overview map rendering.
## Prints ROADS_DONE fails=N; writes scratchpad/roads_map_eraN.png.

const OUT := "/tmp/claude-0/-home-user-Era-/4dd8d359-84a1-5cb8-8e5d-83e3c1e26fc1/scratchpad/"
var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)
	else:
		print("ok: ", msg)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for e in 5:
		var t0 := Time.get_ticks_usec()
		var g := WorldGen.new()
		g.setup(4242 + e, e, 1280.0)
		var t_gen := (Time.get_ticks_usec() - t0) / 1000.0
		var g2 := WorldGen.new()
		g2.setup(4242 + e, e, 1280.0)
		check(g.roads.size() == g2.roads.size() and g.crossroads.size() == g2.crossroads.size(), "era %d deterministic roads" % e)
		var n_main := 0
		var n_trail := 0
		var n_bridge := 0
		var len_main := 0.0
		var len_trail := 0.0
		for r in g.road_net:
			var l: float = (r.a as Vector2).distance_to(r.b)
			if r.bridge:
				n_bridge += 1
			if r.type == "main":
				n_main += 1
				len_main += l
			else:
				n_trail += 1
				len_trail += l
		print("ERA %d: gen %.0f ms, segs %d (main %d / %.0f m, trail %d / %.0f m), bridges %d, crossroads %d, lines %d" % [e, t_gen, g.roads.size(), n_main, len_main, n_trail, len_trail, n_bridge, g.crossroads.size(), g.net.lines.size()])
		check(n_main > 20 and n_trail > 20, "era %d has main roads and trails" % e)
		check(g.crossroads.size() >= 2, "era %d has crossroads (%d)" % [e, g.crossroads.size()])
		# every settlement reachable from the capital along roads
		var cap: Vector2 = g.settlements[0].pos
		var reach := 0
		for s in g.settlements:
			var p: Array = g.road_path(cap, s.pos)
			var ok: bool = p.size() >= 2 and (p[-2] as Vector2).distance_to(s.pos) < float(s.radius)
			if ok:
				reach += 1
			else:
				print("   unreachable ", s.name, " path size ", p.size())
		check(reach == g.settlements.size(), "era %d all %d settlements connected" % [e, g.settlements.size()])
		# trails reach POIs
		var linked := 0
		var total := 0
		for q in g.pois:
			if not q.type in WorldGen.TRAIL_POIS:
				continue
			total += 1
			var rp := g.nearest_road_point(q.pos)
			if rp.distance_to(q.pos) < float(q.get("r", 6.0)) + 8.0:
				linked += 1
		check(linked >= int(total * 0.8), "era %d trails reach %d/%d POIs" % [e, linked, total])
		# queries
		var seg: Dictionary = g.road_net[g.road_net.size() / 3]
		var mid: Vector2 = (seg.a + seg.b) * 0.5
		check(g.road_type_at(mid) == seg.type, "era %d road_type_at on road = %s" % [e, g.road_type_at(mid)])
		check(g.road_type_at(mid + Vector2(60, 60)) == "" or g.road_distance(mid.x + 60, mid.y + 60) < 4.0, "era %d road_type_at off road" % e)
		check(g.nearest_road_point(mid + Vector2(5, 0)).distance_to(mid + Vector2(5, 0)) <= 5.01, "era %d nearest_road_point" % e)
		var t1 := Time.get_ticks_usec()
		var far_a: Vector2 = g.settlements[1].pos
		var far_b: Vector2 = g.settlements[g.settlements.size() - 1].pos
		var pth: Array = g.road_path(far_a + Vector2(30, 10), far_b - Vector2(20, 5))
		var t_path := (Time.get_ticks_usec() - t1) / 1000.0
		check(pth.size() >= 4, "era %d road_path %d pts in %.1f ms" % [e, pth.size(), t_path])
		if g.crossroads.size() > 0:
			var br: Array = g.crossroad_branches(0)
			check(br.size() >= 2, "era %d signpost branches %s" % [e, str(br.map(func(b): return b.name))])
		# spawn still on land, not in water, height deterministic
		var sp: Vector2 = g.spawn_point()
		check(not g.is_water(sp.x, sp.y), "era %d spawn on land" % e)
		var t2 := Time.get_ticks_usec()
		var img := g.overview_image(512)
		var t_ov := (Time.get_ticks_usec() - t2) / 1000.0
		img.save_png(OUT + "roads_map_era%d.png" % e)
		print("   overview(512) %.0f ms" % t_ov)
		# height() cost
		var t3 := Time.get_ticks_usec()
		var acc := 0.0
		for i in 4000:
			acc += g.height(float(i % 200) * 3.1 - 300.0, float(i / 200) * 7.3 - 100.0)
		print("   height() %.2f us/call" % ((Time.get_ticks_usec() - t3) / 4000.0))
	print("ROADS_DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
