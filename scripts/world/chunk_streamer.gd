class_name ChunkStreamer
extends Node3D
## Streams 64 m terrain chunks around a centre point: terrain mesh + heightmap
## collision, water, instanced props (MultiMesh), settlement buildings,
## destructibles, chests and static decor for points of interest. Builds at
## most a time budget per frame and unloads far chunks. Chunk changes
## (destroyed objects, opened chests) persist through `chunk_state`.

signal chunk_loaded(key: Vector2i, node: Node3D, pois: Array, settlements: Array)
signal chunk_unloaded(key: Vector2i)

const CHUNK := 64.0
const RES := 16
const STEP := 4.0
const VERTS := RES + 1

var gen: WorldGen
var era := 0
var chunk_state: Dictionary = {}
var chunks := {}                # Vector2i -> Node3D
var heights := {}               # Vector2i -> PackedFloat32Array (VERTS*VERTS)
var buildings := {}             # Vector2i -> Array[Building]
var build_poi_decor := true
var budget_ms := 5.0
var radius := 2
var build_times: Array = []
var _queue: Array = []
var _bld_jobs: Array = []        # deferred building construction: [key, chunk_node, b, s, st]
var _terrain_idx := PackedInt32Array()
var _terrain_tasks: Array = []   # [task_id, TerrainJob]
var _terrain_pending := {}
var use_threads := true
var _stage_jobs: Array = []      # chunks with terrain built, waiting for props/structures: [key, node, hs, st]
var _defer_buildings := false
var bld_times: Array = []
var stage_times := {"terrain": [], "props": [], "struct": [], "signal": []}
var _center_key := Vector2i(999999, 999999)
var _poi_idx := {}
var _set_idx := {}
var _bld_idx := {}
var _terrain_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _water_mesh: PlaneMesh

func setup(g: WorldGen, cs: Dictionary) -> void:
	gen = g
	era = g.era
	chunk_state = cs
	_poi_idx.clear()
	_set_idx.clear()
	_bld_idx.clear()
	for p in gen.pois:
		_idx_add(_poi_idx, key_of(p.pos), p)
	for s in gen.settlements:
		_idx_add(_set_idx, key_of(s.pos), s)
		for b in s.buildings:
			_idx_add(_bld_idx, key_of(b.pos), [b, s])
	_terrain_mat = StandardMaterial3D.new()
	_terrain_mat.vertex_color_use_as_albedo = true
	_terrain_mat.vertex_color_is_srgb = true
	_terrain_mat.roughness = 0.95
	_terrain_mat.metallic_specular = 0.15
	_water_mat = StandardMaterial3D.new()
	var wc: Color = DBEras.era(era).water
	_water_mat.albedo_color = wc
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.metallic = 0.3
	_water_mat.roughness = 0.08
	_water_mat.emission_enabled = true
	_water_mat.emission = Color(wc.r, wc.g, wc.b) * 0.25
	_water_mesh = PlaneMesh.new()
	_water_mesh.size = Vector2(CHUNK, CHUNK)

func _idx_add(idx: Dictionary, k: Vector2i, v) -> void:
	if not idx.has(k):
		idx[k] = []
	idx[k].append(v)

static func key_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))

static func key_str(k: Vector2i) -> String:
	return "%d,%d" % [k.x, k.y]

func _state(k: Vector2i) -> Dictionary:
	var ks := key_str(k)
	if not chunk_state.has(ks):
		chunk_state[ks] = {"destroyed": [], "opened": []}
	var st: Dictionary = chunk_state[ks]
	if not st.has("destroyed"):
		st["destroyed"] = []
	if not st.has("opened"):
		st["opened"] = []
	return st

# ---------------------------------------------------------------- streaming
func _desired(center: Vector2i) -> Array:
	var out: Array = []
	var lim := int(gen.half / CHUNK)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx * dx + dz * dz > (radius + 0.5) * (radius + 0.5):
				continue
			var k := center + Vector2i(dx, dz)
			if k.x < -lim or k.y < -lim or k.x >= lim or k.y >= lim:
				continue
			out.append(k)
	out.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
	return out

func update_center(pos: Vector3) -> void:
	if gen == null:
		return
	radius = int(Settings.profile().get("chunk_radius", 2))
	var ck := key_of(Vector2(pos.x, pos.z))
	if ck != _center_key:
		_center_key = ck
		_queue.clear()
		for k in _desired(ck):
			if not chunks.has(k):
				_queue.append(k)
		for k in chunks.keys():
			if maxi(absi(k.x - ck.x), absi(k.y - ck.y)) > radius + 1:
				_unload(k)
	# Staged streaming: (1) finish chunks whose terrain exists, (2) start new
	# chunks (terrain + collision only), (3) build houses one by one.
	# At least one unit of work per frame; more only within the time budget.
	var t0 := Time.get_ticks_usec()
	var budget_us := int(budget_ms * 1000.0)
	var did := false
	while not _stage_jobs.is_empty() and (not did or Time.get_ticks_usec() - t0 < budget_us):
		var sj: Array = _stage_jobs.pop_front()
		if chunks.get(sj[0]) == sj[1] and is_instance_valid(sj[1]):
			_defer_buildings = true
			_finish_chunk(sj[0], sj[1], sj[2], sj[3])
			_defer_buildings = false
			did = true
	# completed background terrain computations → nodes (cheap)
	for i in range(_terrain_tasks.size() - 1, -1, -1):
		var tt: Array = _terrain_tasks[i]
		if not WorkerThreadPool.is_task_completed(tt[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(tt[0])
		_terrain_tasks.remove_at(i)
		var job: TerrainJob = tt[1]
		_terrain_pending.erase(job.k)
		if chunks.has(job.k) or maxi(absi(job.k.x - _center_key.x), absi(job.k.y - _center_key.y)) > radius:
			continue
		_start_chunk(job.k, job.data)
		did = true
	while not _queue.is_empty():
		var k: Vector2i = _queue.pop_front()
		if chunks.has(k) or _terrain_pending.has(k):
			continue
		if use_threads and OS.get_processor_count() > 1:
			if _terrain_tasks.size() >= 2:
				_queue.push_front(k)
				break
			var job := TerrainJob.new()
			job.k = k
			var tid := WorkerThreadPool.add_task(func(): job.data = _terrain_data(job.k), false, "terrain")
			_terrain_tasks.append([tid, job])
			_terrain_pending[k] = true
		else:
			if did and Time.get_ticks_usec() - t0 >= budget_us:
				_queue.push_front(k)
				break
			_start_chunk(k)
			did = true
	while not _bld_jobs.is_empty() and (not did or Time.get_ticks_usec() - t0 < budget_us):
		var j: Array = _bld_jobs.pop_front()
		if chunks.get(j[0]) != j[1] or not is_instance_valid(j[1]):
			continue
		_make_building(j[0], j[1], j[2], j[3], j[4])
		did = true

func force_load_around(pos: Vector3) -> void:
	radius = int(Settings.profile().get("chunk_radius", 2))
	var ck := key_of(Vector2(pos.x, pos.z))
	_center_key = ck
	_queue.clear()
	for k in _desired(ck):
		if not chunks.has(k):
			_build_chunk(k)
	while not _stage_jobs.is_empty():
		var sj: Array = _stage_jobs.pop_front()
		if chunks.get(sj[0]) == sj[1] and is_instance_valid(sj[1]):
			_finish_chunk(sj[0], sj[1], sj[2], sj[3])
	_flush_buildings()

func _flush_buildings() -> void:
	while not _bld_jobs.is_empty():
		var j: Array = _bld_jobs.pop_front()
		if chunks.get(j[0]) == j[1] and is_instance_valid(j[1]):
			_make_building(j[0], j[1], j[2], j[3], j[4])

func pending() -> int:
	return _queue.size() + _bld_jobs.size()

func unload_all() -> void:
	for k in chunks.keys():
		_unload(k)
	_queue.clear()
	_stage_jobs.clear()
	_bld_jobs.clear()
	_center_key = Vector2i(999999, 999999)

func _unload(k: Vector2i) -> void:
	var n: Node3D = chunks.get(k)
	chunks.erase(k)
	heights.erase(k)
	buildings.erase(k)
	chunk_unloaded.emit(k)
	if n and is_instance_valid(n):
		n.queue_free()

# ---------------------------------------------------------------- queries
func ground_height(p: Vector3) -> float:
	var k := key_of(Vector2(p.x, p.z))
	var hs = heights.get(k)
	if hs == null:
		return gen.height(p.x, p.z) if gen else 0.0
	var lx := (p.x - k.x * CHUNK) / STEP
	var lz := (p.z - k.y * CHUNK) / STEP
	var i := clampi(floori(lx), 0, RES - 1)
	var j := clampi(floori(lz), 0, RES - 1)
	var fx := clampf(lx - i, 0.0, 1.0)
	var fz := clampf(lz - j, 0.0, 1.0)
	var h00: float = hs[j * VERTS + i]
	var h10: float = hs[j * VERTS + i + 1]
	var h01: float = hs[(j + 1) * VERTS + i]
	var h11: float = hs[(j + 1) * VERTS + i + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)

func building_at(p: Vector3):
	var k := key_of(Vector2(p.x, p.z))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr = buildings.get(k + Vector2i(dx, dz))
			if arr == null:
				continue
			for b in arr:
				if is_instance_valid(b) and (b.contains(p) or b.in_cellar(p)):
					return b
	return null

func is_loaded(p: Vector3) -> bool:
	return chunks.has(key_of(Vector2(p.x, p.z)))

# ---------------------------------------------------------------- chunk build
## Synchronous full build (spawn, teleports).
func _build_chunk(k: Vector2i) -> void:
	_start_chunk(k)
	var sj: Array = _stage_jobs.pop_back()
	_finish_chunk(sj[0], sj[1], sj[2], sj[3])

## Stage 1: chunk node, terrain mesh and collision (data may come from a worker thread).
func _start_chunk(k: Vector2i, data: Dictionary = {}) -> void:
	var t0 := Time.get_ticks_usec()
	var node := Node3D.new()
	node.name = "C%d_%d" % [k.x, k.y]
	node.position = Vector3(k.x * CHUNK, 0.0, k.y * CHUNK)
	add_child(node)
	chunks[k] = node
	var st := _state(k)
	var hs := _terrain_nodes(node, data if not data.is_empty() else _terrain_data(k))
	heights[k] = hs
	_stage_jobs.append([k, node, hs, st])
	if stage_times.terrain.size() < 4000:
		stage_times.terrain.append((Time.get_ticks_usec() - t0) / 1000.0)

## Stage 2: props, structures, points of interest, then announce the chunk.
func _finish_chunk(k: Vector2i, node: Node3D, hs: PackedFloat32Array, st: Dictionary) -> void:
	var t1 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%d|%d|%d" % [gen.seed_v, era, k.x, k.y])
	_build_props(node, k, hs, rng)
	var t2 := Time.get_ticks_usec()
	_build_structures(node, k, st, rng)
	var t3 := Time.get_ticks_usec()
	var pois: Array = _poi_idx.get(k, [])
	var sets: Array = _set_idx.get(k, [])
	chunk_loaded.emit(k, node, pois, sets)
	var t4 := Time.get_ticks_usec()
	build_times.append((t4 - t1) / 1000.0)
	if stage_times.props.size() < 4000:
		stage_times.props.append((t2 - t1) / 1000.0)
		stage_times.struct.append((t3 - t2) / 1000.0)
		stage_times.signal.append((t4 - t3) / 1000.0)

func _build_terrain(node: Node3D, k: Vector2i) -> PackedFloat32Array:
	return _terrain_nodes(node, _terrain_data(k))

## Pure computation (thread-safe: only reads generator data and noise).
func _terrain_data(k: Vector2i) -> Dictionary:
	var ox := k.x * CHUNK
	var oz := k.y * CHUNK
	var W := VERTS + 2
	var big := PackedFloat32Array()
	big.resize(W * W)
	for j in W:
		for i in W:
			big[j * W + i] = gen.height(ox + (i - 1) * STEP, oz + (j - 1) * STEP)
	var hs := PackedFloat32Array()
	hs.resize(VERTS * VERTS)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(VERTS * VERTS)
	norms.resize(VERTS * VERTS)
	cols.resize(VERTS * VERTS)
	var e: Dictionary = DBEras.era(era)
	var g: Dictionary = e.ground
	var road_c: Color = g.road
	var wl := gen.water_level
	var min_h := 1e9
	for j in VERTS:
		for i in VERTS:
			var h: float = big[(j + 1) * W + (i + 1)]
			hs[j * VERTS + i] = h
			min_h = minf(min_h, h)
			var x := ox + i * STEP
			var z := oz + j * STEP
			var idx := j * VERTS + i
			verts[idx] = Vector3(i * STEP, h, j * STEP)
			var hl: float = big[(j + 1) * W + i]
			var hr: float = big[(j + 1) * W + i + 2]
			var hd: float = big[j * W + i + 1]
			var hu: float = big[(j + 2) * W + i + 1]
			norms[idx] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			var b := gen.biome_at(x, z, h)
			var c: Color = g.get(b, g.plains)
			var jit := gen.n_detail.get_noise_2d(x * 2.7, z * 2.7)
			if b == "urban":
				c = _settlement_ground(x, z, g, jit)
			c = c.lightened(jit * 0.09) if jit > 0.0 else c.darkened(-jit * 0.12)
			var slope := 1.0 - norms[idx].y
			if slope > 0.25 and b != "urban":
				c = c.lerp(g.mountain, clampf((slope - 0.25) * 2.5, 0.0, 0.7))
			var rd := gen.road_distance(x, z)
			if rd < 4.5:
				c = c.lerp(road_c, smoothstep(4.5, 1.5, rd) * 0.9)
			if h < wl + 0.25:
				c = c.lerp(g.sand.darkened(0.25), clampf((wl + 0.25 - h) * 0.8, 0.0, 0.85))
			cols[idx] = c.lightened(0.06)
	return {"hs": hs, "verts": verts, "norms": norms, "cols": cols, "min_h": min_h}

## Main-thread part: mesh, collision and water from computed arrays.
func _terrain_nodes(node: Node3D, d: Dictionary) -> PackedFloat32Array:
	var hs: PackedFloat32Array = d.hs
	var wl := gen.water_level
	var min_h: float = d.min_h
	if _terrain_idx.is_empty():
		_terrain_idx.resize(RES * RES * 6)
		var q := 0
		for j in RES:
			for i in RES:
				var a := j * VERTS + i
				var b2 := a + 1
				var c2 := a + VERTS
				var d2 := c2 + 1
				_terrain_idx[q] = a
				_terrain_idx[q + 1] = b2
				_terrain_idx[q + 2] = d2
				_terrain_idx[q + 3] = a
				_terrain_idx[q + 4] = d2
				_terrain_idx[q + 5] = c2
				q += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d.verts
	arrays[Mesh.ARRAY_NORMAL] = d.norms
	arrays[Mesh.ARRAY_COLOR] = d.cols
	arrays[Mesh.ARRAY_INDEX] = _terrain_idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	am.surface_set_material(0, _terrain_mat)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = am
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var sb := StaticBody3D.new()
	sb.name = "Ground"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = VERTS
	hm.map_depth = VERTS
	hm.map_data = hs
	cs.shape = hm
	cs.position = Vector3(CHUNK * 0.5, 0.0, CHUNK * 0.5)
	cs.scale = Vector3(STEP, 1.0, STEP)
	sb.add_child(cs)
	node.add_child(sb)
	if min_h < wl:
		var wm := MeshInstance3D.new()
		wm.name = "Water"
		wm.mesh = _water_mesh
		wm.material_override = _water_mat
		wm.position = Vector3(CHUNK * 0.5, wl, CHUNK * 0.5)
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(wm)
	return hs

func _settlement_ground(x: float, z: float, g: Dictionary, jit: float) -> Color:
	var s = gen.settlement_at(x, z, 0.8)
	var urban: Color = g.urban
	var dirt: Color = g.road
	var grass: Color = g.plains
	if s == null:
		return urban
	var sp: Vector2 = s.pos
	var d := Vector2(x - sp.x, z - sp.y).length() / float(s.radius)
	var patch := gen.n_moist.get_noise_2d(x * 9.0, z * 9.0)
	var c: Color
	if era >= 3 or s.type == "city":
		c = urban.lerp(dirt, 0.25)
		if d < 0.3:
			c = urban.lightened(0.18)
	else:
		c = dirt.lerp(grass, clampf(0.35 + patch * 1.6 + (d - 0.5) * 0.9, 0.0, 0.85))
		if d < 0.3:
			c = urban.lightened(0.12).lerp(dirt, 0.25)
	return c

func _local_h(hs: PackedFloat32Array, lx: float, lz: float) -> float:
	var fi := clampf(lx / STEP, 0.0, RES - 0.001)
	var fj := clampf(lz / STEP, 0.0, RES - 0.001)
	var i := int(fi)
	var j := int(fj)
	var fx := fi - i
	var fz := fj - j
	return lerpf(lerpf(hs[j * VERTS + i], hs[j * VERTS + i + 1], fx), lerpf(hs[(j + 1) * VERTS + i], hs[(j + 1) * VERTS + i + 1], fx), fz)

func _near_poi(x: float, z: float, k: Vector2i, pad: float) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var arr = _poi_idx.get(k + Vector2i(dx, dz))
			if arr == null:
				continue
			for p in arr:
				var pp: Vector2 = p.pos
				if Vector2(x - pp.x, z - pp.y).length() < float(p.get("r", 6.0)) + pad:
					return true
	return false

func _build_props(node: Node3D, k: Vector2i, hs: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var e: Dictionary = DBEras.era(era)
	var trees: Array = []
	var rocks: Array = []
	var small: Array = []
	var urban: Array = []
	for t in e.props:
		match Props.category(t):
			"tree": trees.append(t)
			"rock": rocks.append(t)
			"small": small.append(t)
			_: urban.append(t)
	if small.is_empty():
		small = rocks
	var factor: float = Settings.profile().get("props", 1.0)
	var attempts := int(80 * factor)
	var ox := k.x * CHUNK
	var oz := k.y * CHUNK
	var by_type := {}
	var cols: Array = []
	for n in attempts:
		var lx := rng.randf() * CHUNK
		var lz := rng.randf() * CHUNK
		var x := ox + lx
		var z := oz + lz
		var h := _local_h(hs, lx, lz)
		if h < gen.water_level + 0.25:
			continue
		if gen.settlement_at(x, z, 1.08) != null:
			continue
		if gen.road_distance(x, z) < 4.0:
			continue
		if _near_poi(x, z, k, 4.0):
			continue
		var b := gen.biome_at(x, z, h)
		var r := rng.randf()
		var t := ""
		match b:
			"forest":
				t = _pick(trees, rng) if r < 0.72 else (_pick(small, rng) if r < 0.9 else _pick(rocks, rng))
			"plains":
				if r < 0.15:
					t = _pick(trees, rng)
				elif r < 0.55:
					t = _pick(small, rng)
				elif r < 0.65:
					t = _pick(rocks, rng)
				elif r < 0.7 and not urban.is_empty():
					t = _pick(urban, rng)
			"mountain", "snow":
				t = _pick(rocks, rng) if r < 0.6 else (_pick(trees, rng) if r < 0.85 else "")
			"swamp":
				t = _pick(trees, rng) if r < 0.4 else (_pick(small, rng) if r < 0.7 else (_pick(rocks, rng) if r < 0.8 else ""))
			"sand":
				t = _pick(rocks, rng) if r < 0.35 else (_pick(urban, rng) if r < 0.45 and not urban.is_empty() else "")
		if t == "":
			continue
		var s := rng.randf_range(0.8, 1.3)
		if Props.category(t) == "rock":
			s = rng.randf_range(0.7, 1.6)
		var rot := rng.randf() * TAU
		var tf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, s, s)), Vector3(lx, h - 0.05, lz))
		if not by_type.has(t):
			by_type[t] = []
		by_type[t].append(tf)
		var cd := Props.collider(t)
		if not cd.is_empty():
			cols.append([cd, Vector3(lx, h, lz), rot, s])
	var shadows: bool = Settings.profile().get("shadows", true)
	for t in by_type:
		var arr: Array = by_type[t]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Props.prop_mesh(t, era)
		mm.instance_count = arr.size()
		for i in arr.size():
			mm.set_instance_transform(i, arr[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "P_" + t
		var cat := Props.category(t)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows and cat in ["tree", "urban"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	if not cols.is_empty():
		var sb := StaticBody3D.new()
		sb.name = "PropCols"
		sb.collision_layer = 1
		sb.collision_mask = 0
		for c in cols:
			var cd: Dictionary = c[0]
			var s2: float = c[3]
			var cs := CollisionShape3D.new()
			if cd.shape == "cyl":
				var cy := CylinderShape3D.new()
				cy.radius = float(cd.r) * s2
				cy.height = float(cd.h) * s2
				cs.shape = cy
				cs.position = c[1] + Vector3(0, cy.height * 0.5, 0)
			else:
				var bx := BoxShape3D.new()
				var sz: Vector3 = cd.size
				bx.size = sz * s2
				cs.shape = bx
				cs.position = c[1] + Vector3(0, bx.size.y * 0.5, 0)
				cs.rotation.y = c[2]
			sb.add_child(cs)
		node.add_child(sb)

func _pick(arr: Array, rng: RandomNumberGenerator) -> String:
	if arr.is_empty():
		return ""
	return arr[rng.randi() % arr.size()]

func _chest_level(p: Vector2) -> int:
	return 1 + int(p.length() / 220.0)

func _build_structures(node: Node3D, k: Vector2i, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var origin := node.position
	buildings[k] = []
	# buildings whose centre is in this chunk (deferred while streaming)
	for pair in _bld_idx.get(k, []):
		if _defer_buildings:
			_bld_jobs.append([k, node, pair[0], pair[1], st])
		else:
			_make_building(k, node, pair[0], pair[1], st)
	# settlement centres: centrepiece, lamps, destructibles
	for s in _set_idx.get(k, []):
		_build_settlement_decor(node, s, st, rng)
	# points of interest
	for p in _poi_idx.get(k, []):
		_build_poi(node, p, st, rng)
	# wilderness chests
	var center := Vector2(origin.x + CHUNK * 0.5, origin.z + CHUNK * 0.5)
	if gen.settlement_at(center.x, center.y, 1.5) == null and rng.randf() < 0.3:
		for i in 6:
			var lx := rng.randf_range(6.0, CHUNK - 6.0)
			var lz := rng.randf_range(6.0, CHUNK - 6.0)
			var x := origin.x + lx
			var z := origin.z + lz
			if gen.is_water(x, z) or gen.road_distance(x, z) < 3.0 or _near_poi(x, z, k, 3.0):
				continue
			var c := Chest.new()
			c.configure("c%d_%d_ch" % [k.x, k.y], st, era, "normal", _chest_level(Vector2(x, z)), rng.randf())
			c.position = Vector3(lx, gen.height(x, z), lz)
			c.rotation.y = rng.randf() * TAU
			node.add_child(c)
			break

class TerrainJob:
	extends RefCounted
	var k := Vector2i.ZERO
	var data := {}

func _exit_tree() -> void:
	for tt in _terrain_tasks:
		WorkerThreadPool.wait_for_task_completion(tt[0])
	_terrain_tasks.clear()

func _make_building(k: Vector2i, node: Node3D, b: Dictionary, s: Dictionary, st: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var bld := Building.new()
	bld.configure(b, era, st, s.id, _chest_level(s.pos))
	var bp: Vector2 = b.pos
	bld.position = Vector3(bp.x - node.position.x, float(s.height), bp.y - node.position.z)
	bld.rotation.y = b.rot
	node.add_child(bld)
	bld.build()
	if not buildings.has(k):
		buildings[k] = []
	buildings[k].append(bld)
	bld_times.append((Time.get_ticks_usec() - t0) / 1000.0)

func _build_settlement_decor(node: Node3D, s: Dictionary, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var origin := node.position
	var sp: Vector2 = s.pos
	var h: float = s.height
	var cp := Props.centerpiece(era)
	cp.position = Vector3(sp.x - origin.x, h, sp.y - origin.z)
	node.add_child(cp)
	var sq: float = float(s.radius) * 0.28
	var lamp: String = ["", "lamppost_oil", "lamppost_oil", "streetlight", "neon_pillar"][era]
	var torch := era == 0
	var n_l := 6 if s.type == "city" else 4
	for i in n_l:
		var a := i * TAU / n_l + 0.3
		var lp := sp + Vector2(cos(a), sin(a)) * (sq + 1.0)
		if _hits_building(s, lp, 1.0):
			continue
		var pos := Vector3(lp.x - origin.x, h, lp.y - origin.z)
		if torch:
			MeshLib.part(node, MeshLib.cyl(0.07, 0.09, 2.2, 6), MeshLib.mat(Color(0.35, 0.24, 0.14)), pos + Vector3(0, 1.1, 0))
			MeshLib.part(node, MeshLib.cyl(0.0, 0.16, 0.4, 6), MeshLib.mat(Color(1.0, 0.6, 0.2), 0.0, 0.5, 3.0), pos + Vector3(0, 2.4, 0), Vector3.ZERO, Vector3.ONE, false)
		else:
			var mi := MeshInstance3D.new()
			mi.mesh = Props.prop_mesh(lamp, era)
			mi.position = pos
			mi.rotation.y = -a
			node.add_child(mi)
	# market stalls in towns and cities
	if s.type in ["town", "city", "port"]:
		for i in 2:
			var a2 := rng.randf() * TAU
			var mp := sp + Vector2(cos(a2), sin(a2)) * sq * 0.65
			if mp.distance_to(gen.spawn_point()) < 4.0:
				continue
			_stall(node, Vector3(mp.x - origin.x, h, mp.y - origin.z), -a2, rng)
	# destructibles around the square
	var n_d := rng.randi_range(5, 9)
	for i in n_d:
		var a3 := rng.randf() * TAU
		var dp := sp + Vector2(cos(a3), sin(a3)) * rng.randf_range(sq * 0.9, float(s.radius) * 0.75)
		if _hits_building(s, dp, 1.2) or dp.distance_to(gen.spawn_point()) < 3.0:
			continue
		var kind := "crate" if rng.randf() < 0.55 else "barrel"
		var de := Destructible.new()
		de.configure(kind, "%s_sd%d" % [s.id, i], st, era)
		if kind == "barrel" and era >= 1 and rng.randf() < 0.25:
			de.explosive = true
		de.position = Vector3(dp.x - origin.x, h, dp.y - origin.z)
		de.rotation.y = rng.randf() * TAU
		node.add_child(de)
	# fences on the outskirts of villages
	if s.type == "village":
		for i in 6:
			var a4 := rng.randf() * TAU
			var fp := sp + Vector2(cos(a4), sin(a4)) * float(s.radius) * 0.92
			if _hits_building(s, fp, 2.0) or gen.road_distance(fp.x, fp.y) < 4.0:
				continue
			var fe := Destructible.new()
			fe.configure("fence", "%s_f%d" % [s.id, i], st, era, Vector3.ZERO, -a4 + PI * 0.5)
			fe.position = Vector3(fp.x - origin.x, gen.height(fp.x, fp.y), fp.y - origin.z)
			node.add_child(fe)

func _stall(node: Node3D, pos: Vector3, rot: float, rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rot
	node.add_child(n)
	var wood := MeshLib.mat(Color(0.45, 0.3, 0.17))
	var cloth_c: Color = [Color(0.8, 0.25, 0.2), Color(0.25, 0.45, 0.75), Color(0.85, 0.75, 0.3), Color(0.3, 0.6, 0.35)][rng.randi() % 4]
	MeshLib.part(n, MeshLib.box(Vector3(2.2, 0.9, 1.0)), wood, Vector3(0, 0.45, 0))
	for sx in [-1.0, 1.0]:
		MeshLib.part(n, MeshLib.box(Vector3(0.1, 2.3, 0.1)), wood, Vector3(sx * 1.05, 1.15, 0.45))
	MeshLib.part(n, MeshLib.box(Vector3(2.5, 0.06, 1.5)), MeshLib.mat(cloth_c), Vector3(0, 2.3, 0.2), Vector3(-12, 0, 0))
	for i in 3:
		MeshLib.part(n, MeshLib.sphere(0.13, 6, 4), MeshLib.mat([Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.2), Color(0.5, 0.8, 0.3)][i]), Vector3(-0.6 + i * 0.6, 1.0, 0))
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 1.0, 1.0)
	cs.shape = bs
	cs.position.y = 0.5
	sb.add_child(cs)
	n.add_child(sb)

func _hits_building(s: Dictionary, p: Vector2, pad: float) -> bool:
	for b in s.buildings:
		var bp: Vector2 = b.pos
		var sz: Vector2 = b.size
		if p.distance_to(bp) < maxf(sz.x, sz.y) * 0.75 + pad:
			return true
	return false

func _build_poi(node: Node3D, p: Dictionary, st: Dictionary, rng: RandomNumberGenerator) -> void:
	var origin := node.position
	var pp: Vector2 = p.pos
	var h := gen.height(pp.x, pp.y)
	var local := Vector3(pp.x - origin.x, h, pp.y - origin.z)
	if build_poi_decor:
		var dec := Props.poi_decor(p, era)
		dec.name = "POI_" + str(p.id)
		dec.position = local
		dec.set_meta("poi_id", p.id)
		node.add_child(dec)
	match p.type:
		"camp":
			var segs := 10
			for i in segs:
				if i == 0 or i == 5:
					continue
				var a := i * TAU / segs
				var pal := Destructible.new()
				pal.configure("palisade", "%s_pal%d" % [p.id, i], st, era, Vector3.ZERO, -a + PI * 0.5)
				pal.position = local + Vector3(cos(a), 0, sin(a)) * 12.5
				node.add_child(pal)
			for i in 4:
				var a2 := rng.randf() * TAU
				var de := Destructible.new()
				var kind := "crate" if i % 2 == 0 else "barrel"
				de.configure(kind, "%s_cd%d" % [p.id, i], st, era)
				if kind == "barrel" and era >= 1 and rng.randf() < 0.35:
					de.explosive = true
				de.position = local + Vector3(cos(a2), 0, sin(a2)) * rng.randf_range(3.0, 9.0)
				node.add_child(de)
			var c := Chest.new()
			c.configure(str(p.id) + "_chest", st, era, "normal", _chest_level(pp) + 1, rng.randf())
			c.position = local + Vector3(0, 0, -3.5)
			node.add_child(c)
		"lair":
			for i in 6:
				var a3 := i * TAU / 6.0 + 0.5
				var pil := Destructible.new()
				pil.configure("pillar", "%s_pil%d" % [p.id, i], st, era)
				pil.position = local + Vector3(cos(a3), 0, sin(a3)) * 11.0
				node.add_child(pil)
		"ruins":
			var c2 := Chest.new()
			c2.configure(str(p.id) + "_chest", st, era, "rich" if rng.randf() < 0.5 else "normal", _chest_level(pp) + 1, rng.randf())
			c2.position = local + Vector3(1.5, 0, 1.5)
			node.add_child(c2)
