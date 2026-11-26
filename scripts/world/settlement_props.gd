class_name SettlementProps
## Living settlement squares: a deterministic layout per settlement (market
## stalls, benches, carts, campfire, notice board, well/pump, forge corner with
## anvil and glowing hearth, banners in the owner's colour, lamps/torches,
## crates and barrels, fences) plus NPC activity points. Static pieces are
## merged into one cached mesh per settlement; only a few lamps get real
## lights (Visual Quality "lights" budget). Also builds crossroads signposts.

static var _mesh_cache := {}

# ---------------------------------------------------------------- layout
## {"items": [{t, p: Vector2, r: float}], "points": [{type, pos: Vector3, facing: Vector3}],
##  "lamps": [Vector2], "banners": [{p, r}], "crates": [Vector2], "fences": [{p, r}]}
static func layout(gen, s: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(s.id) + "|layout|" + str(gen.seed_v))
	var era: int = gen.era
	var sp: Vector2 = s.pos
	var R: float = s.radius
	var h: float = s.height
	var sq := R * RoadNet.plaza_ratio(str(s.type)) + 1.0
	var items: Array = []
	var points: Array = []
	var taken: Array = []          # [Vector2, radius]
	var forge_poi = null
	for q in gen.pois:
		if q.data.get("settlement", "") == s.id:
			taken.append([q.pos, 2.4])
			if q.type == "forge":
				forge_poi = q
	taken.append([sp, 3.2 if era != 1 else 3.6])          # centrepiece
	var spawn: Vector2 = gen.spawn_point()
	taken.append([spawn, 3.0])
	var fac := func(from: Vector2, to: Vector2) -> Vector3:
		var dv := (to - from).normalized()
		return Vector3(dv.x, 0, dv.y)
	var v3 := func(p: Vector2) -> Vector3:
		return Vector3(p.x, h, p.y)
	# market stalls around the square, facing the centre
	var n_st := 1
	match s.type:
		"town", "port": n_st = 3
		"city": n_st = 4
		"castle", "fort": n_st = 1
	var a0 := rng.randf() * TAU
	for i in n_st:
		for attempt in 8:
			var a := a0 + i * TAU / n_st + rng.randf_range(-0.3, 0.3) + attempt * 0.4
			var p := sp + Vector2(cos(a), sin(a)) * (sq + rng.randf_range(1.0, 3.0))
			if _free(gen, s, p, 1.8, taken):
				taken.append([p, 2.0])
				items.append({"t": "stall", "p": p, "r": atan2(sp.x - p.x, sp.y - p.y)})
				var dv := (sp - p).normalized()
				points.append({"type": "stall", "pos": v3.call(p - dv * 0.9), "facing": Vector3(dv.x, 0, dv.y)})
				break
	# benches on the square edge
	for i in rng.randi_range(2, 4):
		for attempt in 8:
			var a := rng.randf() * TAU
			var p := sp + Vector2(cos(a), sin(a)) * (sq * rng.randf_range(0.65, 0.95))
			if _free(gen, s, p, 1.3, taken):
				taken.append([p, 1.4])
				var r := atan2(sp.x - p.x, sp.y - p.y)
				items.append({"t": "bench", "p": p, "r": r})
				points.append({"type": "bench", "pos": v3.call(p), "facing": fac.call(p, sp)})
				break
	# well / pump (eras 0-1 use the centrepiece well/fountain)
	if era <= 1:
		var wa := rng.randf() * TAU
		var wp := sp + Vector2(cos(wa), sin(wa)) * (2.1 if era == 0 else 3.4)
		points.append({"type": "well", "pos": v3.call(wp), "facing": fac.call(wp, sp)})
	else:
		for attempt in 10:
			var a := rng.randf() * TAU
			var p := sp + Vector2(cos(a), sin(a)) * (sq * rng.randf_range(0.5, 0.9))
			if _free(gen, s, p, 1.2, taken):
				taken.append([p, 1.3])
				items.append({"t": "well", "p": p, "r": atan2(sp.x - p.x, sp.y - p.y)})
				var dv2 := (sp - p).normalized()
				points.append({"type": "well", "pos": v3.call(p + dv2 * 0.9), "facing": Vector3(-dv2.x, 0, -dv2.y)})
				break
	# forge corner next to the forge service point
	if forge_poi != null:
		var fp: Vector2 = forge_poi.pos
		var away := (fp - sp).normalized() if fp.distance_to(sp) > 0.5 else Vector2(1, 0)
		var side := Vector2(-away.y, away.x)
		var anvil := fp + side * 2.2
		var hearth := fp + side * 3.8 + away * 0.4
		items.append({"t": "anvil", "p": anvil, "r": atan2(away.x, away.y)})
		items.append({"t": "hearth", "p": hearth, "r": atan2(away.x, away.y)})
		items.append({"t": "quench", "p": anvil - side * 0.2 + away * 1.3, "r": 0.0})
		taken.append([anvil, 1.2])
		taken.append([hearth, 1.4])
		points.append({"type": "forge", "pos": v3.call(anvil - away * 1.0), "facing": Vector3(away.x, 0, away.y)})
	# campfire (villages, forts and camps of the early eras; braziers later)
	if s.type in ["village", "castle", "fort"] or era == 0:
		for attempt in 12:
			var a := rng.randf() * TAU
			var p := sp + Vector2(cos(a), sin(a)) * R * rng.randf_range(0.42, 0.62)
			if _free(gen, s, p, 3.0, taken):
				taken.append([p, 3.0])
				items.append({"t": "campfire", "p": p, "r": 0.0})
				for q in 3:
					var qa := a + q * TAU / 3.0
					var qp := p + Vector2(cos(qa), sin(qa)) * 1.7
					points.append({"type": "campfire", "pos": v3.call(qp), "facing": fac.call(qp, p)})
				break
	# carts / vehicles on the outskirts
	for i in (2 if s.type in ["town", "city", "port"] else 1):
		for attempt in 10:
			var a := rng.randf() * TAU
			var p := sp + Vector2(cos(a), sin(a)) * R * rng.randf_range(0.5, 0.8)
			if _free(gen, s, p, 2.6, taken):
				taken.append([p, 2.6])
				items.append({"t": "cart", "p": p, "r": rng.randf() * TAU})
				break
	# notice board + era extras on the square
	var extras: Array = ["sign"]
	match era:
		0: extras.append_array(["woodpile", "trough", "hay"])
		1: extras.append_array(["flowerpots", "flowerpots", "trough"])
		2: extras.append_array(["pipes", "coalcart", "lamp_post"])
		3: extras.append_array(["vending", "bus_stop", "bins"])
		4: extras.append_array(["holo_kiosk", "holo_kiosk", "drone_pad"])
	for t in extras:
		for attempt in 10:
			var a := rng.randf() * TAU
			var p := sp + Vector2(cos(a), sin(a)) * rng.randf_range(sq * 0.8, R * 0.7)
			if _free(gen, s, p, 1.6, taken):
				taken.append([p, 1.6])
				items.append({"t": t, "p": p, "r": atan2(sp.x - p.x, sp.y - p.y)})
				break
	# banners around the square (owner colour)
	var banners: Array = []
	var n_b := 4 if s.type in ["castle", "fort", "city"] else 2
	for i in n_b:
		for attempt in 8:
			var a := a0 + PI / n_b + i * TAU / n_b + attempt * 0.35
			var p := sp + Vector2(cos(a), sin(a)) * (sq + 0.6)
			if _free(gen, s, p, 0.8, taken):
				taken.append([p, 0.8])
				banners.append({"p": p, "r": atan2(sp.x - p.x, sp.y - p.y)})
				break
	# lamps / torches ring
	var lamps: Array = []
	var n_l := 6 if s.type == "city" else 4
	for i in n_l:
		var a := i * TAU / n_l + 0.3
		var lp := sp + Vector2(cos(a), sin(a)) * (sq + 1.0)
		if _free(gen, s, lp, 0.5, taken):
			taken.append([lp, 0.6])
			lamps.append(lp)
	# destructible crates / barrels near houses and the square
	var crates: Array = []
	for i in rng.randi_range(5, 9):
		var a := rng.randf() * TAU
		var dp := sp + Vector2(cos(a), sin(a)) * rng.randf_range(sq * 0.9, R * 0.75)
		if _free(gen, s, dp, 0.8, taken, true):
			taken.append([dp, 0.8])
			crates.append(dp)
		else:
			crates.append(Vector2.INF)
	# village fences on the outskirts
	var fences: Array = []
	if s.type == "village":
		for i in 6:
			var a := rng.randf() * TAU
			var fp2 := sp + Vector2(cos(a), sin(a)) * R * 0.92
			if _hits_building(s, fp2, 2.0) or gen.road_edge(fp2.x, fp2.y) < 1.5:
				fences.append(null)
				continue
			fences.append({"p": fp2, "r": -a + PI * 0.5})
	# patrol ring
	for i in 6:
		var a := i * TAU / 6.0 + 0.2
		var pp := sp + Vector2(cos(a), sin(a)) * R * 0.62
		if not _hits_building(s, pp, 1.0):
			points.append({"type": "patrol", "pos": v3.call(pp), "facing": Vector3(-sin(a), 0, cos(a))})
	# road entries ("crossroads" of the settlement)
	var last_hit := -10
	for i in 72:
		var a := i * TAU / 72.0
		var ep := sp + Vector2(cos(a), sin(a)) * R * 0.98
		if gen.road_type_at(ep) != "" and i - last_hit > 4:
			last_hit = i
			points.append({"type": "crossroads", "pos": v3.call(ep), "facing": Vector3(cos(a), 0, sin(a))})
	return {"items": items, "points": points, "lamps": lamps, "banners": banners, "crates": crates, "fences": fences}

static func _hits_building(s: Dictionary, p: Vector2, pad: float) -> bool:
	for b in s.buildings:
		var bp: Vector2 = b.pos
		var sz: Vector2 = b.size
		if p.distance_to(bp) < maxf(sz.x, sz.y) * 0.72 + pad:
			return true
	return false

static func _free(gen, s: Dictionary, p: Vector2, pad: float, taken: Array, allow_road: bool = false) -> bool:
	var sp: Vector2 = s.pos
	if p.distance_to(sp) > float(s.radius) * 0.9:
		return false
	if _hits_building(s, p, pad):
		return false
	if not allow_road and gen.road_edge(p.x, p.y) < pad * 0.5 + 0.5:
		return false
	for t in taken:
		if p.distance_to(t[0]) < float(t[1]) + pad:
			return false
	return true

# ---------------------------------------------------------------- build
static func build(streamer, node: Node3D, k: Vector2i, s: Dictionary, st: Dictionary) -> void:
	var gen = streamer.gen
	var era: int = gen.era
	var lay: Dictionary = streamer.settlement_layout(s.id)
	var origin := node.position
	var sp: Vector2 = s.pos
	var h: float = s.height
	var base := Vector3(sp.x - origin.x, h, sp.y - origin.z)
	var cp := Props.centerpiece(era)
	cp.position = base
	node.add_child(cp)
	var root := Node3D.new()
	root.name = "SettlementProps"
	root.position = base
	node.add_child(root)
	# merged static props
	var key := "%d|%d|%s" % [gen.seed_v, era, s.id]
	var mesh: ArrayMesh = _mesh_cache.get(key)
	if mesh == null:
		var m := Props.Merger.new()
		for it in lay.items:
			_item(m, it, sp, era)
		for bn in lay.banners:
			var bp: Vector2 = bn.p - sp
			_pole(m, Vector3(bp.x, 0, bp.y), bn.r, era)
		mesh = m.commit()
		_mesh_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Static"
	root.add_child(mi)
	# colliders
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	root.add_child(sb)
	for it in lay.items:
		var sz := _footprint(str(it.t))
		if sz == Vector3.ZERO:
			continue
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = sz
		cs.shape = bx
		var ip: Vector2 = it.p - sp
		cs.position = Vector3(ip.x, sz.y * 0.5, ip.y)
		cs.rotation.y = it.r
		sb.add_child(cs)
	# banners (owner colour, shared material per settlement)
	var bm: StandardMaterial3D = streamer.banner_material(s.id)
	for bn in lay.banners:
		var bp: Vector2 = bn.p - sp
		var cloth := MeshInstance3D.new()
		cloth.mesh = MeshLib.box(Vector3(0.9, 1.5, 0.04))
		cloth.material_override = bm
		cloth.position = Vector3(bp.x, 3.0, bp.y) + Vector3(cos(-bn.r), 0, sin(-bn.r)) * 0.5
		cloth.rotation.y = bn.r + PI * 0.5
		cloth.rotation.z = 0.0
		root.add_child(cloth)
	# lamps / torches, a few with real lights
	var lamp_t: String = ["", "lamppost_oil", "lamppost_oil", "streetlight", "neon_pillar"][era]
	var li := 0
	for lp in lay.lamps:
		var lpos := Vector3(lp.x - sp.x, 0, lp.y - sp.y)
		var top := 2.4
		if era == 0:
			MeshLib.part(root, MeshLib.cyl(0.07, 0.09, 2.2, 6), MeshLib.mat(Color(0.35, 0.24, 0.14)), lpos + Vector3(0, 1.1, 0))
			MeshLib.part(root, MeshLib.cyl(0.0, 0.16, 0.4, 6), MeshLib.mat(Color(1.0, 0.6, 0.2), 0.0, 0.5, 3.0), lpos + Vector3(0, 2.4, 0), Vector3.ZERO, Vector3.ONE, false)
		else:
			var lm := MeshInstance3D.new()
			lm.mesh = Props.prop_mesh(lamp_t, era)
			lm.position = lpos
			lm.rotation.y = -atan2(lp.y - sp.y, lp.x - sp.x)
			root.add_child(lm)
			top = [2.4, 3.2, 3.2, 4.9, 3.6][era]
		if li % 2 == 0 and streamer.take_light(k):
			var ol := OmniLight3D.new()
			ol.light_color = [Color(1.0, 0.62, 0.3), Color(1.0, 0.8, 0.5), Color(1.0, 0.78, 0.45), Color(1.0, 0.95, 0.85), Color(0.5, 0.9, 1.0)][era]
			ol.light_energy = 1.3
			ol.omni_range = 9.0
			ol.shadow_enabled = false
			ol.position = lpos + Vector3(0, top, 0)
			root.add_child(ol)
		li += 1
	# glowing forge hearth + campfire flames
	for it in lay.items:
		var ip2: Vector2 = it.p - sp
		var local := Vector3(ip2.x, 0, ip2.y)
		match str(it.t):
			"hearth":
				if streamer.take_light(k):
					var fl := OmniLight3D.new()
					fl.light_color = Color(1.0, 0.5, 0.2)
					fl.light_energy = 1.6
					fl.omni_range = 6.0
					fl.position = local + Vector3(0, 1.3, 0)
					root.add_child(fl)
				if streamer.quality().get("ambient", true):
					AmbientLife.sparks(root, local + Vector3(0, 1.1, 0), float(streamer.quality().get("particles", 0.7)))
					AmbientLife.smoke(root, local + Vector3(0, 2.6, 0), float(streamer.quality().get("particles", 0.7)), 0.7)
			"campfire":
				campfire(streamer, root, local, era, k, false)
	# destructible crates / barrels (persistent ids)
	var crates: Array = lay.crates
	var crng := RandomNumberGenerator.new()
	crng.seed = hash(str(s.id) + "|crates")
	for i in crates.size():
		var dp: Vector2 = crates[i]
		var kind := "crate" if crng.randf() < 0.55 else "barrel"
		var expl := crng.randf() < 0.25
		var rot := crng.randf() * TAU
		if dp == Vector2.INF:
			continue
		var de := Destructible.new()
		de.configure(kind, "%s_sd%d" % [s.id, i], st, era)
		if kind == "barrel" and era >= 1 and expl:
			de.explosive = true
		de.position = Vector3(dp.x - origin.x, h, dp.y - origin.z)
		de.rotation.y = rot
		node.add_child(de)
	var fences: Array = lay.fences
	for i in fences.size():
		var f = fences[i]
		if f == null:
			continue
		var fp: Vector2 = f.p
		var fe := Destructible.new()
		fe.configure("fence", "%s_f%d" % [s.id, i], st, era, Vector3.ZERO, f.r)
		fe.position = Vector3(fp.x - origin.x, gen.height(fp.x, fp.y), fp.y - origin.z)
		node.add_child(fe)

static func _footprint(t: String) -> Vector3:
	match t:
		"stall": return Vector3(2.3, 1.0, 1.1)
		"bench": return Vector3(1.6, 0.5, 0.5)
		"cart": return Vector3(1.6, 1.2, 3.0)
		"well": return Vector3(1.0, 1.2, 1.0)
		"anvil": return Vector3(0.8, 0.8, 0.5)
		"hearth": return Vector3(1.4, 1.1, 1.2)
		"sign": return Vector3(1.4, 2.0, 0.3)
		"trough": return Vector3(1.8, 0.6, 0.6)
		"vending": return Vector3(0.9, 1.9, 0.8)
		"bus_stop": return Vector3(2.6, 2.4, 1.2)
		"holo_kiosk": return Vector3(1.2, 2.0, 1.2)
		"woodpile": return Vector3(1.6, 1.0, 0.8)
		"coalcart": return Vector3(1.2, 1.1, 2.0)
		"hay": return Vector3(1.2, 1.0, 1.2)
	return Vector3.ZERO

static func _x(p: Vector3, r: float, off: Vector3 = Vector3.ZERO, rot_extra: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
	var b := Basis(Vector3.UP, r)
	var b2 := b * Basis.from_euler(rot_extra * (PI / 180.0)).scaled(scl)
	return Transform3D(b2, p + b * off)

static func _item(m: Props.Merger, it: Dictionary, sp: Vector2, era: int) -> void:
	var ip: Vector2 = it.p - sp
	var p := Vector3(ip.x, 0, ip.y)
	var r: float = it.r
	var wood := MeshLib.mat(Color(0.45, 0.3, 0.17))
	var dark_wood := MeshLib.mat(Color(0.32, 0.22, 0.13))
	var metal := MeshLib.mat(Color(0.3, 0.31, 0.33), 0.7, 0.4)
	var stone := MeshLib.mat(Color(0.55, 0.53, 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(it.p)
	match str(it.t):
		"stall":
			if era >= 3:
				var kc: Color = [Color(0.85, 0.3, 0.2), Color(0.2, 0.5, 0.8), Color(0.95, 0.75, 0.2)][rng.randi() % 3]
				m.add(MeshLib.box(Vector3(2.2, 1.0, 1.0)), MeshLib.mat(Color(0.75, 0.75, 0.78), 0.4, 0.5), _x(p, r, Vector3(0, 0.5, 0)))
				m.add(MeshLib.box(Vector3(2.4, 0.08, 1.5)), MeshLib.mat(kc if era == 3 else Color(0.2, 0.9, 1.0), 0.0, 0.5, 0.0 if era == 3 else 2.0), _x(p, r, Vector3(0, 2.3, 0.2), Vector3(-10, 0, 0)))
				for sx in [-1.0, 1.0]:
					m.add(MeshLib.box(Vector3(0.08, 2.3, 0.08)), metal, _x(p, r, Vector3(sx * 1.1, 1.15, -0.45)))
				m.add(MeshLib.box(Vector3(1.6, 0.5, 0.05)), MeshLib.mat(Color(0.3, 0.8, 1.0) if era == 4 else Color(0.95, 0.95, 0.9), 0.0, 0.4, 1.2), _x(p, r, Vector3(0, 1.6, -0.45)))
			else:
				var cloth_c: Color = [Color(0.8, 0.25, 0.2), Color(0.25, 0.45, 0.75), Color(0.85, 0.75, 0.3), Color(0.3, 0.6, 0.35)][rng.randi() % 4]
				m.add(MeshLib.box(Vector3(2.2, 0.9, 1.0)), wood, _x(p, r, Vector3(0, 0.45, 0)))
				for sx in [-1.0, 1.0]:
					m.add(MeshLib.box(Vector3(0.1, 2.3, 0.1)), wood, _x(p, r, Vector3(sx * 1.05, 1.15, -0.45)))
					m.add(MeshLib.box(Vector3(0.1, 1.9, 0.1)), wood, _x(p, r, Vector3(sx * 1.05, 0.95, 0.5)))
				m.add(MeshLib.box(Vector3(2.5, 0.06, 1.6)), MeshLib.mat(cloth_c), _x(p, r, Vector3(0, 2.1, 0.0), Vector3(12, 0, 0)))
				for i in 4:
					var gc: Color = [Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.2), Color(0.5, 0.8, 0.3), Color(0.75, 0.55, 0.3)][(i + rng.randi()) % 4]
					m.add(MeshLib.sphere(0.13, 6, 4), MeshLib.mat(gc), _x(p, r, Vector3(-0.75 + i * 0.5, 1.0, 0.1)))
				m.add(MeshLib.box(Vector3(0.5, 0.35, 0.4)), dark_wood, _x(p, r, Vector3(0.6, 0.18, -0.9)))
		"bench":
			var bmat: Material = wood if era <= 2 else (MeshLib.mat(Color(0.25, 0.4, 0.3), 0.5, 0.5) if era == 3 else MeshLib.mat(Color(0.2, 0.22, 0.28), 0.6, 0.3))
			m.add(MeshLib.box(Vector3(1.6, 0.08, 0.45)), bmat, _x(p, r, Vector3(0, 0.45, 0)))
			m.add(MeshLib.box(Vector3(1.6, 0.4, 0.06)), bmat, _x(p, r, Vector3(0, 0.7, -0.22), Vector3(-10, 0, 0)))
			for sx in [-0.7, 0.7]:
				m.add(MeshLib.box(Vector3(0.08, 0.45, 0.4)), metal if era >= 2 else dark_wood, _x(p, r, Vector3(sx, 0.22, 0)))
			if era == 4:
				m.add(MeshLib.box(Vector3(1.5, 0.03, 0.03)), MeshLib.mat(Color(0.3, 0.9, 1.0), 0.0, 0.4, 2.5), _x(p, r, Vector3(0, 0.42, 0.24)))
		"well":
			match era:
				2:
					m.add(MeshLib.cyl(0.18, 0.22, 1.1, 8), metal, _x(p, r, Vector3(0, 0.55, 0)))
					m.add(MeshLib.box(Vector3(0.08, 0.08, 0.7)), metal, _x(p, r, Vector3(0, 1.05, -0.3), Vector3(-25, 0, 0)))
					m.add(MeshLib.cyl(0.04, 0.05, 0.3, 6), metal, _x(p, r, Vector3(0, 0.75, 0.25), Vector3(70, 0, 0)))
					m.add(MeshLib.box(Vector3(0.8, 0.35, 0.5)), stone, _x(p, r, Vector3(0, 0.17, 0.5)))
				3:
					m.add(MeshLib.box(Vector3(0.5, 1.0, 0.5)), MeshLib.mat(Color(0.7, 0.7, 0.72)), _x(p, r, Vector3(0, 0.5, 0)))
					m.add(MeshLib.box(Vector3(0.6, 0.08, 0.6)), MeshLib.mat(Color(0.6, 0.62, 0.65), 0.7, 0.3), _x(p, r, Vector3(0, 1.02, 0)))
				_:
					m.add(MeshLib.cyl(0.4, 0.5, 1.2, 6), MeshLib.mat(Color(0.2, 0.22, 0.28), 0.7, 0.3), _x(p, r, Vector3(0, 0.6, 0)))
					m.add(MeshLib.cyl(0.3, 0.3, 0.06, 12), MeshLib.mat(Color(0.3, 0.8, 1.0, 0.8), 0.0, 0.2, 2.0), _x(p, r, Vector3(0, 1.22, 0)))
		"anvil":
			m.add(MeshLib.cyl(0.3, 0.34, 0.5, 8), dark_wood, _x(p, r, Vector3(0, 0.25, 0)))
			m.add(MeshLib.box(Vector3(0.3, 0.2, 0.25)), metal, _x(p, r, Vector3(0, 0.6, 0)))
			m.add(MeshLib.box(Vector3(0.6, 0.12, 0.25)), metal, _x(p, r, Vector3(0.05, 0.76, 0)))
			m.add(MeshLib.prism(Vector3(0.25, 0.12, 0.2)), metal, _x(p, r, Vector3(0.42, 0.76, 0), Vector3(0, 0, -90)))
			m.add(MeshLib.box(Vector3(0.05, 0.05, 0.35)), metal, _x(p, r, Vector3(-0.2, 0.85, 0.05), Vector3(0, 30, 0)))
		"hearth":
			m.add(MeshLib.box(Vector3(1.4, 0.9, 1.2)), stone, _x(p, r, Vector3(0, 0.45, 0)))
			m.add(MeshLib.box(Vector3(1.0, 0.12, 0.8)), MeshLib.mat(Color(1.0, 0.45, 0.12), 0.0, 0.5, 3.5), _x(p, r, Vector3(0, 0.92, 0)))
			m.add(MeshLib.cyl(0.25, 0.4, 1.6, 6), stone, _x(p, r, Vector3(0, 1.9, -0.35)))
			m.add(MeshLib.box(Vector3(0.5, 0.4, 0.4)), dark_wood, _x(p, r, Vector3(0.95, 0.2, 0.2)))
		"quench":
			m.add(MeshLib.cyl(0.36, 0.4, 0.8, 9), dark_wood, _x(p, r, Vector3(0, 0.4, 0)))
			m.add(MeshLib.cyl(0.33, 0.33, 0.04, 9), MeshLib.mat(Color(0.15, 0.25, 0.3), 0.0, 0.15), _x(p, r, Vector3(0, 0.78, 0)))
		"campfire":
			for i in 8:
				var a := i * TAU / 8.0
				m.add(MeshLib.sphere(0.18, 5, 3), stone, Transform3D(Basis().scaled(Vector3(1.2, 0.7, 1.0)), p + Vector3(cos(a) * 0.65, 0.08, sin(a) * 0.65)))
			for i in 3:
				m.add(MeshLib.cyl(0.07, 0.08, 1.0, 5), dark_wood, _x(p, i * 2.1, Vector3(0, 0.15, 0), Vector3(0, 0, 80)))
			m.add(MeshLib.cyl(0.0, 0.32, 0.8, 6), MeshLib.mat(Color(1.0, 0.55, 0.15), 0.0, 0.5, 4.0), _x(p, 0.0, Vector3(0, 0.5, 0)))
			m.add(MeshLib.cyl(0.0, 0.18, 0.55, 5), MeshLib.mat(Color(1.0, 0.85, 0.35), 0.0, 0.5, 4.0), _x(p, 0.7, Vector3(0.08, 0.5, 0.05)))
			m.add(MeshLib.box(Vector3(1.4, 0.35, 0.35)), dark_wood, _x(p, 0.6, Vector3(0, 0.17, 1.5)))
		"cart":
			match era:
				0, 1:
					m.add(MeshLib.box(Vector3(1.4, 0.5, 2.2)), wood, _x(p, r, Vector3(0, 0.75, 0)))
					m.add(MeshLib.box(Vector3(1.5, 0.35, 0.08)), dark_wood, _x(p, r, Vector3(0, 1.15, 1.08)))
					for sx in [-0.78, 0.78]:
						m.add(MeshLib.cyl(0.45, 0.45, 0.1, 10), dark_wood, _x(p, r, Vector3(sx, 0.45, -0.2), Vector3(0, 0, 90)))
						m.add(MeshLib.box(Vector3(0.07, 0.07, 1.6)), wood, _x(p, r, Vector3(sx * 0.5, 0.55, 1.8), Vector3(-8, 0, 0)))
					m.add(MeshLib.sphere(0.4, 6, 4), MeshLib.mat(Color(0.85, 0.72, 0.36)), Transform3D(Basis().scaled(Vector3(1.4, 0.6, 2.0)), p + Basis(Vector3.UP, r) * Vector3(0, 1.1, -0.2)))
				2:
					m.add(MeshLib.box(Vector3(1.3, 0.8, 2.0)), MeshLib.mat(Color(0.3, 0.28, 0.27), 0.6, 0.5), _x(p, r, Vector3(0, 0.85, 0)))
					m.add(MeshLib.cyl(0.0, 0.6, 0.5, 6), MeshLib.mat(Color(0.08, 0.08, 0.08)), _x(p, r, Vector3(0, 1.45, 0)))
					for sx in [-0.7, 0.7]:
						for sz in [-0.6, 0.6]:
							m.add(MeshLib.cyl(0.3, 0.3, 0.1, 10), metal, _x(p, r, Vector3(sx, 0.3, sz), Vector3(0, 0, 90)))
				3:
					var paint: Color = [Color(0.75, 0.15, 0.12), Color(0.15, 0.35, 0.65), Color(0.85, 0.85, 0.82), Color(0.2, 0.2, 0.22)][rng.randi() % 4]
					m.add(MeshLib.box(Vector3(1.8, 0.7, 4.0)), MeshLib.mat(paint, 0.5, 0.35), _x(p, r, Vector3(0, 0.6, 0)))
					m.add(MeshLib.box(Vector3(1.6, 0.6, 2.0)), MeshLib.mat(Color(0.15, 0.2, 0.25), 0.4, 0.2), _x(p, r, Vector3(0, 1.2, -0.2)))
					for sx in [-0.85, 0.85]:
						for sz in [-1.3, 1.3]:
							m.add(MeshLib.cyl(0.33, 0.33, 0.22, 10), MeshLib.mat(Color(0.08, 0.08, 0.08)), _x(p, r, Vector3(sx, 0.33, sz), Vector3(0, 0, 90)))
				_:
					m.add(MeshLib.sphere(1.0, 10, 6), MeshLib.mat(Color(0.75, 0.78, 0.85), 0.7, 0.25), Transform3D(Basis(Vector3.UP, r).scaled(Vector3(0.9, 0.45, 1.8)), p + Vector3(0, 0.9, 0)))
					m.add(MeshLib.box(Vector3(1.4, 0.05, 2.8)), MeshLib.mat(Color(0.3, 0.9, 1.0), 0.0, 0.4, 3.0), _x(p, r, Vector3(0, 0.45, 0)))
		"sign":
			for sx in [-0.6, 0.6]:
				m.add(MeshLib.box(Vector3(0.1, 2.0, 0.1)), dark_wood if era < 3 else metal, _x(p, r, Vector3(sx, 1.0, 0)))
			m.add(MeshLib.box(Vector3(1.4, 0.9, 0.06)), wood if era < 3 else MeshLib.mat(Color(0.2, 0.3, 0.45), 0.0, 0.5, 0.0 if era == 3 else 1.5), _x(p, r, Vector3(0, 1.5, 0)))
			for i in 4:
				m.add(MeshLib.box(Vector3(0.25, 0.3, 0.02)), MeshLib.mat(Color(0.92, 0.88, 0.75)), _x(p, r, Vector3(-0.45 + i * 0.3, 1.5 + (0.12 if i % 2 == 0 else -0.12), 0.04)))
		"woodpile":
			for i in 9:
				m.add(MeshLib.cyl(0.12, 0.12, 1.4, 6), MeshLib.mat(Color(0.5, 0.36, 0.22)), _x(p, r, Vector3(-0.5 + (i % 4) * 0.27 + (i / 4) * 0.13, 0.13 + (i / 4) * 0.23, 0), Vector3(0, 0, 90)))
		"trough":
			m.add(MeshLib.box(Vector3(1.8, 0.5, 0.6)), wood if era == 0 else stone, _x(p, r, Vector3(0, 0.25, 0)))
			m.add(MeshLib.box(Vector3(1.6, 0.04, 0.45)), MeshLib.mat(Color(0.18, 0.3, 0.38), 0.0, 0.15), _x(p, r, Vector3(0, 0.47, 0)))
		"hay":
			m.add(MeshLib.box(Vector3(1.1, 0.7, 0.7)), MeshLib.mat(Color(0.85, 0.72, 0.36)), _x(p, r, Vector3(0, 0.35, 0)))
			m.add(MeshLib.box(Vector3(1.1, 0.6, 0.7)), MeshLib.mat(Color(0.8, 0.68, 0.33)), _x(p, r, Vector3(0.2, 0.95, 0.1), Vector3(0, 20, 0)))
		"flowerpots":
			for i in 3:
				m.add(MeshLib.cyl(0.25, 0.18, 0.4, 8), MeshLib.mat(Color(0.7, 0.38, 0.25)), _x(p, r, Vector3(-0.7 + i * 0.7, 0.2, 0)))
				m.add(MeshLib.sphere(0.28, 6, 4), MeshLib.mat([Color(0.85, 0.3, 0.35), Color(0.95, 0.85, 0.3), Color(0.35, 0.6, 0.3)][i]), _x(p, r, Vector3(-0.7 + i * 0.7, 0.55, 0)))
		"pipes":
			m.add(MeshLib.cyl(0.3, 0.3, 3.0, 10), MeshLib.mat(Color(0.5, 0.3, 0.18), 0.6, 0.6), _x(p, r, Vector3(0, 0.3, 0), Vector3(0, 0, 90)))
			m.add(MeshLib.cyl(0.3, 0.3, 3.0, 10), MeshLib.mat(Color(0.42, 0.28, 0.2), 0.6, 0.6), _x(p, r, Vector3(0.2, 0.3, 0.62), Vector3(0, 0, 90)))
			m.add(MeshLib.cyl(0.3, 0.3, 3.0, 10), MeshLib.mat(Color(0.5, 0.3, 0.18), 0.6, 0.6), _x(p, r, Vector3(0.1, 0.82, 0.31), Vector3(0, 0, 90)))
		"coalcart":
			m.add(MeshLib.box(Vector3(1.1, 0.7, 1.8)), metal, _x(p, r, Vector3(0, 0.6, 0)))
			m.add(MeshLib.cyl(0.0, 0.55, 0.4, 6), MeshLib.mat(Color(0.08, 0.08, 0.08)), _x(p, r, Vector3(0, 1.1, 0)))
			for sz in [-0.6, 0.6]:
				m.add(MeshLib.cyl(0.25, 0.25, 1.2, 8), metal, _x(p, r, Vector3(0, 0.25, sz), Vector3(0, 0, 90)))
		"lamp_post":
			m.add(MeshLib.cyl(0.06, 0.1, 3.2, 6), MeshLib.mat(Color(0.12, 0.12, 0.13), 0.6, 0.5), _x(p, r, Vector3(0, 1.6, 0)))
			m.add(MeshLib.box(Vector3(0.35, 0.45, 0.35)), MeshLib.mat(Color(1.0, 0.8, 0.45), 0.0, 0.5, 2.5), _x(p, r, Vector3(0, 3.4, 0)))
		"vending":
			m.add(MeshLib.box(Vector3(0.9, 1.9, 0.8)), MeshLib.mat(Color(0.75, 0.12, 0.12), 0.3, 0.4), _x(p, r, Vector3(0, 0.95, 0)))
			m.add(MeshLib.box(Vector3(0.6, 1.0, 0.04)), MeshLib.mat(Color(0.8, 0.95, 1.0), 0.0, 0.3, 1.5), _x(p, r, Vector3(-0.08, 1.15, 0.41)))
		"bus_stop":
			m.add(MeshLib.box(Vector3(2.6, 0.08, 1.2)), metal, _x(p, r, Vector3(0, 2.4, 0)))
			m.add(MeshLib.box(Vector3(2.6, 2.3, 0.05)), MeshLib.mat(Color(0.7, 0.85, 0.95, 0.45), 0.1, 0.1), _x(p, r, Vector3(0, 1.2, -0.55)))
			for sx in [-1.25, 1.25]:
				m.add(MeshLib.box(Vector3(0.08, 2.4, 0.08)), metal, _x(p, r, Vector3(sx, 1.2, -0.5)))
			m.add(MeshLib.box(Vector3(2.0, 0.08, 0.4)), MeshLib.mat(Color(0.25, 0.4, 0.3)), _x(p, r, Vector3(0, 0.45, -0.3)))
		"bins":
			for i in 2:
				m.add(MeshLib.box(Vector3(0.6, 0.9, 0.6)), MeshLib.mat([Color(0.2, 0.45, 0.25), Color(0.25, 0.35, 0.6)][i], 0.3, 0.6), _x(p, r, Vector3(-0.4 + i * 0.8, 0.45, 0)))
		"holo_kiosk":
			m.add(MeshLib.cyl(0.5, 0.6, 1.1, 6), MeshLib.mat(Color(0.18, 0.2, 0.26), 0.7, 0.3), _x(p, r, Vector3(0, 0.55, 0)))
			m.add(MeshLib.box(Vector3(1.0, 0.7, 0.03)), MeshLib.mat(Color(0.3, 0.9, 1.0, 0.6), 0.0, 0.3, 2.5), _x(p, r, Vector3(0, 1.7, 0)))
			m.add(MeshLib.torus(0.45, 0.52), MeshLib.mat(Color(1.0, 0.3, 0.85), 0.0, 0.3, 2.5), _x(p, r, Vector3(0, 1.12, 0)))
		"drone_pad":
			m.add(MeshLib.cyl(1.2, 1.2, 0.08, 16), MeshLib.mat(Color(0.2, 0.22, 0.28), 0.6, 0.3), _x(p, r, Vector3(0, 0.04, 0)))
			m.add(MeshLib.torus(1.0, 1.08), MeshLib.mat(Color(0.3, 1.0, 0.6), 0.0, 0.3, 2.5), _x(p, r, Vector3(0, 0.09, 0)))

static func _pole(m: Props.Merger, p: Vector3, r: float, era: int) -> void:
	var pm := MeshLib.mat(Color(0.35, 0.25, 0.15)) if era <= 1 else MeshLib.mat(Color(0.3, 0.3, 0.32), 0.7, 0.4)
	m.add(MeshLib.cyl(0.05, 0.07, 4.0, 6), pm, Transform3D(Basis(), p + Vector3(0, 2.0, 0)))
	var dirv := Vector3(cos(-r), 0, sin(-r))
	m.add(MeshLib.box(Vector3(1.0, 0.05, 0.05)), pm, Transform3D(Basis(Vector3.UP, r + PI * 0.5), p + Vector3(0, 3.78, 0) + dirv * 0.5))
	m.add(MeshLib.sphere(0.08, 6, 4), MeshLib.mat(Color(0.85, 0.7, 0.3), 0.8, 0.35), Transform3D(Basis(), p + Vector3(0, 4.05, 0)))

## Campfire with flames, sparks, smoke and (budget permitting) a warm light.
static func campfire(streamer, parent: Node3D, local: Vector3, era: int, k: Vector2i, with_mesh: bool = true) -> void:
	if with_mesh:
		var m := Props.Merger.new()
		_item(m, {"t": "campfire", "p": Vector2(local.x, local.z), "r": 0.0}, Vector2.ZERO, era)
		var mi := MeshInstance3D.new()
		mi.mesh = m.commit()
		mi.position = Vector3(0, local.y, 0)
		parent.add_child(mi)
	var q: Dictionary = streamer.quality()
	if streamer.take_light(k):
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.55, 0.25)
		ol.light_energy = 1.5
		ol.omni_range = 7.0
		ol.position = local + Vector3(0, 1.0, 0)
		parent.add_child(ol)
	if q.get("ambient", true):
		AmbientLife.sparks(parent, local + Vector3(0, 0.6, 0), float(q.get("particles", 0.7)))
		AmbientLife.smoke(parent, local + Vector3(0, 1.2, 0), float(q.get("particles", 0.7)), 0.8)

# ---------------------------------------------------------------- signposts
## Era-styled signpost at a crossroads: one arrow board per branch with the
## destination name and road distance (labels readable from the camera).
static func signpost(parent: Node3D, pos: Vector3, branches: Array, era: int, gen) -> void:
	var n := Node3D.new()
	n.name = "Signpost"
	n.position = pos
	parent.add_child(n)
	# stand on the verge, not in the middle of the junction
	var avg := Vector2.ZERO
	for b in branches:
		avg += b.dir
	var off := -avg.normalized() if avg.length() > 0.3 else Vector2(1, 1).normalized()
	var spot := Vector2(pos.x + parent.position.x, pos.z + parent.position.z) + off * 4.5
	for i in 6:
		if gen.road_edge(spot.x, spot.y) > 0.6:
			break
		spot += off * 1.2
	n.position = Vector3(spot.x - parent.position.x, gen.height(spot.x, spot.y), spot.y - parent.position.z)
	var post_m: Material
	var board_m: Material
	var text_c := Color(0.15, 0.1, 0.05)
	match era:
		0:
			post_m = MeshLib.mat(Color(0.36, 0.25, 0.15))
			board_m = MeshLib.mat(Color(0.62, 0.48, 0.3))
		1:
			post_m = MeshLib.mat(Color(0.8, 0.76, 0.68))
			board_m = MeshLib.mat(Color(0.9, 0.84, 0.7))
		2:
			post_m = MeshLib.mat(Color(0.18, 0.18, 0.19), 0.7, 0.45)
			board_m = MeshLib.mat(Color(0.12, 0.13, 0.15), 0.4, 0.5)
			text_c = Color(0.95, 0.9, 0.75)
		3:
			post_m = MeshLib.mat(Color(0.6, 0.62, 0.64), 0.7, 0.3)
			board_m = MeshLib.mat(Color(0.1, 0.42, 0.22), 0.1, 0.5)
			text_c = Color(1, 1, 1)
		_:
			post_m = MeshLib.mat(Color(0.18, 0.2, 0.26), 0.7, 0.3)
			board_m = MeshLib.mat(Color(0.2, 0.85, 1.0, 0.75), 0.0, 0.3, 2.0)
			text_c = Color(0.9, 1.0, 1.0)
	var top := 2.4 + 0.5 * mini(4, branches.size())
	MeshLib.part(n, MeshLib.cyl(0.07, 0.09, top, 6), post_m, Vector3(0, top * 0.5, 0))
	if era <= 1:
		MeshLib.part(n, MeshLib.box(Vector3(0.18, 0.22, 0.18)), MeshLib.mat(Color(1.0, 0.8, 0.45), 0.0, 0.5, 2.5), Vector3(0, top + 0.12, 0), Vector3.ZERO, Vector3.ONE, false)
	var shown := 0
	for b in branches:
		if shown >= 4:
			break
		var dv: Vector2 = b.dir
		var y := top - 0.35 - shown * 0.5
		var ang := atan2(dv.x, dv.y)
		var board := Node3D.new()
		board.position = Vector3(0, y, 0)
		board.rotation.y = ang
		n.add_child(board)
		var bm := MeshLib.part(board, MeshLib.box(Vector3(0.06, 0.3, 1.3)), board_m, Vector3(0, 0, 0.75))
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		MeshLib.part(board, MeshLib.prism(Vector3(0.3, 0.3, 0.06)), board_m, Vector3(0, 0, 1.52), Vector3(90, 0, 90), Vector3.ONE, false)
		var lbl := Label3D.new()
		var dist_m := int(round(float(b.get("dist", 0.0)) / 10.0) * 10.0)
		lbl.text = "%s  %d м" % [b.name, dist_m]
		lbl.font_size = 40
		lbl.pixel_size = 0.0055
		lbl.outline_size = 10
		lbl.modulate = text_c if era >= 2 else Color(1.0, 0.95, 0.82)
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
		lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lbl.no_depth_test = false
		lbl.position = Vector3(0, y + 0.02, 0) + Vector3(dv.x, 0, dv.y) * 0.9
		lbl.visibility_range_end = 45.0
		n.add_child(lbl)
		shown += 1
