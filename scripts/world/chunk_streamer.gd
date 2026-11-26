class_name ChunkStreamer
extends Node3D
## Streams 64 m terrain chunks around a centre point: terrain mesh (detail
## shader) + heightmap collision, animated water, era-styled road strips,
## railway tracks, bridges, crossroads signposts, instanced vegetation and
## landscape detail (MultiMesh, faded by distance), settlement buildings and
## props, destructibles, chests, ambient life. Heavy per-chunk computation
## (heights, colours, road geometry, vegetation transforms) runs on a worker
## thread; nodes are created on the main thread within a time budget.
## Chunk changes (destroyed objects, opened chests) persist via `chunk_state`.

signal chunk_loaded(key: Vector2i, node: Node3D, pois: Array, settlements: Array)
signal chunk_unloaded(key: Vector2i)

const CHUNK := 64.0
const RES := 16
const STEP := 4.0
const VERTS := RES + 1
const BIOMES := ["plains", "forest", "mountain", "swamp", "sand", "snow", "urban"]

const TERRAIN_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley;
uniform float water_level = -1.2;
uniform vec3 rock_col : source_color = vec3(0.5, 0.48, 0.45);
uniform vec3 mud_col : source_color = vec3(0.35, 0.3, 0.22);
global uniform float weather_wet;
global uniform float weather_snow;
varying vec3 wpos;
varying vec3 wnrm;
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
}
void fragment() {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 base = COLOR.rgb * 0.8;
#else
	vec3 base = COLOR.rgb * COLOR.rgb;
#endif
	vec2 p = wpos.xz;
	float macro = vnoise(p * 0.011);
	float mid = vnoise(p * 0.085);
	float fine = vnoise(p * 0.55) * 0.6 + vnoise(p * 1.9) * 0.4;
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float grassy = clamp((base.g - max(base.r, base.b)) * 9.0, 0.0, 1.0);
	vec3 col = base * (0.8 + 0.3 * macro) * (0.9 + 0.2 * mid);
	col *= mix(1.0, 0.76 + 0.48 * fine, 0.28 + 0.4 * grassy);
	col = mix(col, col * vec3(1.18, 1.06, 0.68), grassy * smoothstep(0.62, 0.86, macro) * 0.6);
	col = mix(col, col * vec3(0.82, 1.06, 0.84), grassy * smoothstep(0.38, 0.12, macro) * 0.45);
	float rk = smoothstep(0.3, 0.55, slope + (fine - 0.5) * 0.2);
	float strata = 0.82 + 0.18 * sin(wpos.y * 2.7 + vnoise(p * 0.15) * 5.0);
	col = mix(col, rock_col * strata * (0.75 + 0.45 * fine), rk);
	float wet = 1.0 - smoothstep(water_level + 0.05, water_level + 1.1, wpos.y);
	col = mix(col, mud_col * (0.8 + 0.3 * fine), wet * 0.7);
	col *= 1.0 - wet * 0.25;
	// weather: rain darkens and glosses the ground, puddles gather on flat hollows
	float flatg = clamp(wnrm.y, 0.0, 1.0);
	float pud = smoothstep(0.6, 0.74, vnoise(p * 0.16) * 0.75 + fine * 0.25) * smoothstep(0.93, 0.99, flatg) * weather_wet * (1.0 - rk);
	col *= 1.0 - weather_wet * 0.26;
	col = mix(col, col * 0.35 + vec3(0.03, 0.035, 0.045), pud);
	// snow settles on faces that look up
	float snw = weather_snow * smoothstep(0.55, 0.85, flatg + (fine - 0.5) * 0.35 + (macro - 0.5) * 0.2);
	col = mix(col, vec3(0.64, 0.67, 0.72) * (0.9 + 0.1 * fine), snw * 0.9);
	ALBEDO = col;
	ROUGHNESS = mix(mix(mix(0.95, 0.4, wet), 0.5, weather_wet * 0.6), 0.05, pud) * (1.0 - snw * 0.25) + snw * 0.2;
	SPECULAR = 0.2 + wet * 0.3 + weather_wet * 0.2 + pud * 0.45;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_burley;
uniform vec4 deep : source_color = vec4(0.1, 0.25, 0.4, 0.85);
uniform vec4 shallow : source_color = vec4(0.25, 0.5, 0.6, 0.45);
uniform vec3 sky : source_color = vec3(0.6, 0.75, 0.9);
varying vec3 wpos;
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float depth = COLOR.r * 4.0;
	float t = TIME;
	vec2 p = wpos.xz;
	vec3 n = normalize(vec3(
		sin(p.x * 0.9 + t * 1.3) * 0.18 + sin((p.x + p.y) * 1.7 - t * 2.1) * 0.1 + (vnoise(p * 0.7 + t * 0.35) - 0.5) * 0.35,
		1.0,
		cos(p.y * 0.8 - t * 1.1) * 0.18 + sin((p.x - p.y) * 1.5 + t * 1.7) * 0.1 + (vnoise(p * 0.6 - t * 0.3) - 0.5) * 0.35));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float sh = 1.0 - smoothstep(0.0, 1.8, depth);
	vec3 col = mix(deep.rgb, shallow.rgb, sh);
	col = mix(col, sky, fres * 0.55);
	float foam = smoothstep(0.3, 0.0, depth) * (0.55 + 0.45 * sin(t * 2.2 + p.x * 0.6 + p.y * 0.4));
	col = mix(col, vec3(0.85, 0.9, 0.92), foam * 0.45);
	ALBEDO = col;
	ALPHA = clamp(mix(shallow.a, deep.a, 1.0 - sh) + fres * 0.25 + foam * 0.3, 0.0, 0.97);
	ROUGHNESS = 0.07;
	METALLIC = 0.05;
	SPECULAR = 0.65;
	EMISSION = col * 0.06;
}
"""

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
var _bld_jobs: Array = []        # deferred construction: [key, chunk_node, b, s, st] (b = Dictionary or job tag)
var _terrain_idx := PackedInt32Array()
var _terrain_tasks: Array = []   # [task_id, TerrainJob]
var _terrain_pending := {}
var use_threads := true
var _stage_jobs: Array = []      # chunks with terrain built, waiting for props/structures: [key, node, hs, st, data]
var _defer_buildings := false
var bld_times: Array = []
var stage_times := {"terrain": [], "props": [], "struct": [], "signal": []}
var _center_key := Vector2i(999999, 999999)
var _poi_idx := {}
var _set_idx := {}
var _bld_idx := {}
var _bridge_idx := {}            # Vector2i -> Array[int] bridge segments (by midpoint)
var _cross_idx := {}             # Vector2i -> Array[int] crossroads indices
var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _road_mat: ShaderMaterial
var _veg := {}
var _vq := {}                    # quality snapshot read by worker jobs
var _layouts := {}               # settlement id -> SettlementProps layout
var _banner_mats := {}           # settlement id -> StandardMaterial3D
var _lights_used := 0
var _chunk_lights := {}          # Vector2i -> lights taken by that chunk

func setup(g: WorldGen, cs: Dictionary) -> void:
	gen = g
	era = g.era
	chunk_state = cs
	_poi_idx.clear()
	_set_idx.clear()
	_bld_idx.clear()
	_bridge_idx.clear()
	_cross_idx.clear()
	for p in gen.pois:
		_idx_add(_poi_idx, key_of(p.pos), p)
	for s in gen.settlements:
		_idx_add(_set_idx, key_of(s.pos), s)
		for b in s.buildings:
			_idx_add(_bld_idx, key_of(b.pos), [b, s])
	var net: RoadNet = gen.net
	for si in net.sa.size():
		if net.s_flag[si] == RoadNet.FLAG_BRIDGE:
			_idx_add(_bridge_idx, key_of((net.sa[si] + net.sb[si]) * 0.5), si)
	for ci in gen.crossroads.size():
		_idx_add(_cross_idx, key_of(gen.crossroads[ci]), ci)
	var e: Dictionary = DBEras.era(era)
	var gc: Dictionary = e.ground
	var tsh := Shader.new()
	tsh.code = TERRAIN_SHADER
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = tsh
	_terrain_mat.set_shader_parameter("water_level", gen.water_level)
	_terrain_mat.set_shader_parameter("rock_col", gc.mountain)
	_terrain_mat.set_shader_parameter("mud_col", gc.sand.darkened(0.45).lerp(gc.road, 0.3))
	var wsh := Shader.new()
	wsh.code = WATER_SHADER
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = wsh
	var wc: Color = e.water
	_water_mat.set_shader_parameter("deep", Color(wc.r * 0.6, wc.g * 0.65, wc.b * 0.75, minf(0.95, wc.a + 0.1)))
	_water_mat.set_shader_parameter("shallow", Color(wc.r * 1.15 + 0.05, wc.g * 1.1 + 0.06, wc.b * 0.95 + 0.04, 0.42))
	_water_mat.set_shader_parameter("sky", e.sky_horizon)
	_road_mat = RoadNet.material(era)
	_veg = Props.veg_table(era)
	_snapshot_quality()
	# meshes are created and cached on the main thread only (worker jobs never touch caches)
	for b in _veg:
		for list_name in ["big", "small"]:
			for entry in _veg[b][list_name]:
				Props.prop_mesh(entry[0], era)
	for b in BIOMES:
		Props.prop_mesh("grass:" + b, era)
	for t in e.props:
		Props.prop_mesh(t, era)

func _snapshot_quality() -> void:
	var detail: float = Settings.vq("detail_dist", 40.0)
	_vq = {"grass": float(Settings.vq("grass", 0.7)), "props": float(Settings.vq("props", 0.8)), "detail": detail,
		"ambient": bool(Settings.vq("ambient_life", true)), "particles": float(Settings.vq("particles", 0.7)),
		"lights": int(Settings.vq("lights", 8)), "shadows": bool(Settings.vq("shadows", true))}
	Props.foliage_material().set_shader_parameter("fade_end", detail)

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

# ---------------------------------------------------------------- public settlement API
## Points NPCs can use in a settlement: [{type: "stall"|"forge"|"well"|"bench"|
## "campfire"|"patrol"|"crossroads", pos: Vector3, facing: Vector3}].
## Deterministic and available whether or not the settlement is loaded.
func activity_points(settlement_id: String) -> Array:
	var lay := settlement_layout(settlement_id)
	return lay.get("points", [])

## Recolours every banner of a settlement (owner faction colour).
func set_settlement_banner(settlement_id: String, color: Color) -> void:
	banner_material(settlement_id).albedo_color = color

func banner_material(settlement_id: String) -> StandardMaterial3D:
	var m: StandardMaterial3D = _banner_mats.get(settlement_id)
	if m == null:
		m = StandardMaterial3D.new()
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.8
		var c := Color(0.85, 0.8, 0.7)
		for s in gen.settlements:
			if s.id == settlement_id and str(s.owner) != "":
				c = DBEras.faction(s.owner).get("color", c)
		m.albedo_color = c
		_banner_mats[settlement_id] = m
	return m

func settlement_layout(settlement_id: String) -> Dictionary:
	if _layouts.has(settlement_id):
		return _layouts[settlement_id]
	for s in gen.settlements:
		if s.id == settlement_id:
			var lay := SettlementProps.layout(gen, s)
			_layouts[settlement_id] = lay
			return lay
	return {}

## Grants one real light to a chunk if the quality budget allows it.
func take_light(k: Vector2i) -> bool:
	var cap := maxi(1, int(_vq.get("lights", 8)))
	if _lights_used >= cap:
		return false
	_lights_used += 1
	_chunk_lights[k] = _chunk_lights.get(k, 0) + 1
	return true

func quality() -> Dictionary:
	return _vq

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
		_snapshot_quality()
		_queue.clear()
		for k in _desired(ck):
			if not chunks.has(k):
				_queue.append(k)
		for k in chunks.keys():
			if maxi(absi(k.x - ck.x), absi(k.y - ck.y)) > radius + 1:
				_unload(k)
	# Staged streaming: (1) finish chunks whose terrain exists, (2) start new
	# chunks (terrain + collision only), (3) build houses / props one by one.
	# At least one unit of work per frame; more only within the time budget.
	var t0 := Time.get_ticks_usec()
	var budget_us := int(budget_ms * 1000.0)
	var did := false
	while not _stage_jobs.is_empty() and (not did or Time.get_ticks_usec() - t0 < budget_us):
		var sj: Array = _stage_jobs.pop_front()
		if chunks.get(sj[0]) == sj[1] and is_instance_valid(sj[1]):
			_defer_buildings = true
			_finish_chunk(sj[0], sj[1], sj[2], sj[3], sj[4])
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
		if did and Time.get_ticks_usec() - t0 >= budget_us:
			# keep the finished data for the next frame
			_terrain_ready.append(job)
			continue
		_start_chunk(job.k, job.data)
		did = true
	while not _terrain_ready.is_empty() and (not did or Time.get_ticks_usec() - t0 < budget_us):
		var job2: TerrainJob = _terrain_ready.pop_front()
		if chunks.has(job2.k) or maxi(absi(job2.k.x - _center_key.x), absi(job2.k.y - _center_key.y)) > radius:
			continue
		_start_chunk(job2.k, job2.data)
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
		_run_job(j)
		did = true

var _terrain_ready: Array = []

func force_load_around(pos: Vector3) -> void:
	radius = int(Settings.profile().get("chunk_radius", 2))
	_snapshot_quality()
	var ck := key_of(Vector2(pos.x, pos.z))
	_center_key = ck
	_queue.clear()
	for k in _desired(ck):
		if not chunks.has(k):
			_build_chunk(k)
	while not _stage_jobs.is_empty():
		var sj: Array = _stage_jobs.pop_front()
		if chunks.get(sj[0]) == sj[1] and is_instance_valid(sj[1]):
			_finish_chunk(sj[0], sj[1], sj[2], sj[3], sj[4])
	_flush_buildings()

func _flush_buildings() -> void:
	while not _bld_jobs.is_empty():
		var j: Array = _bld_jobs.pop_front()
		if chunks.get(j[0]) == j[1] and is_instance_valid(j[1]):
			_run_job(j)

func _run_job(j: Array) -> void:
	var b = j[2]
	if b is Dictionary:
		_make_building(j[0], j[1], b, j[3], j[4])
		return
	var t0 := Time.get_ticks_usec()
	match str(b):
		"settlement":
			SettlementProps.build(self, j[1], j[0], j[3], j[4])
		"bridge":
			_build_bridge(j[1], int(j[3]))
	bld_times.append((Time.get_ticks_usec() - t0) / 1000.0)

func pending() -> int:
	return _queue.size() + _bld_jobs.size()

func unload_all() -> void:
	for k in chunks.keys():
		_unload(k)
	_queue.clear()
	_stage_jobs.clear()
	_bld_jobs.clear()
	_terrain_ready.clear()
	_center_key = Vector2i(999999, 999999)

func _unload(k: Vector2i) -> void:
	var n: Node3D = chunks.get(k)
	chunks.erase(k)
	heights.erase(k)
	buildings.erase(k)
	_lights_used = maxi(0, _lights_used - int(_chunk_lights.get(k, 0)))
	_chunk_lights.erase(k)
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
	_finish_chunk(sj[0], sj[1], sj[2], sj[3], sj[4])

## Stage 1: chunk node, terrain mesh, collision, water and roads (data may come from a worker thread).
func _start_chunk(k: Vector2i, data: Dictionary = {}) -> void:
	var t0 := Time.get_ticks_usec()
	var node := Node3D.new()
	node.name = "C%d_%d" % [k.x, k.y]
	node.position = Vector3(k.x * CHUNK, 0.0, k.y * CHUNK)
	add_child(node)
	chunks[k] = node
	var st := _state(k)
	var d: Dictionary = data if not data.is_empty() else _terrain_data(k)
	var hs := _terrain_nodes(node, d)
	heights[k] = hs
	_stage_jobs.append([k, node, hs, st, d])
	if stage_times.terrain.size() < 4000:
		stage_times.terrain.append((Time.get_ticks_usec() - t0) / 1000.0)

## Stage 2: props, structures, points of interest, then announce the chunk.
func _finish_chunk(k: Vector2i, node: Node3D, hs: PackedFloat32Array, st: Dictionary, d: Dictionary = {}) -> void:
	var t1 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%d|%d|%d" % [gen.seed_v, era, k.x, k.y])
	_build_props(node, k, d)
	var t2 := Time.get_ticks_usec()
	_build_structures(node, k, st, rng, d)
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

## Heights on the rendered triangle surface (matches the terrain mesh exactly),
## with a cache for grid points outside the chunk's precomputed border.
class HSampler:
	extends RefCounted
	var gen
	var big := PackedFloat32Array()
	var W := 0
	var ox := 0.0
	var oz := 0.0
	var cache := {}

	func grid_h(ix: int, iz: int) -> float:
		var bi := ix + 1
		var bj := iz + 1
		if bi >= 0 and bj >= 0 and bi < W and bj < W:
			return big[bj * W + bi]
		var k := Vector2i(ix, iz)
		if cache.has(k):
			return cache[k]
		var v: float = gen.height(ox + ix * 4.0, oz + iz * 4.0)
		cache[k] = v
		return v

	func h(lx: float, lz: float) -> float:
		var fx := lx / 4.0
		var fz := lz / 4.0
		var i := floori(fx)
		var j := floori(fz)
		var u := fx - i
		var v := fz - j
		var ha := grid_h(i, j)
		var hd := grid_h(i + 1, j + 1)
		if u >= v:
			var hb := grid_h(i + 1, j)
			return ha + (hb - ha) * u + (hd - hb) * v
		var hc := grid_h(i, j + 1)
		return ha + (hc - ha) * v + (hd - hc) * u

	func normal(lx: float, lz: float) -> Vector3:
		return Vector3(h(lx - 1.0, lz) - h(lx + 1.0, lz), 2.0, h(lx, lz - 1.0) - h(lx, lz + 1.0)).normalized()

## Pure computation (thread-safe: only reads generator / road data and noise).
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
	var bio := PackedByteArray()
	verts.resize(VERTS * VERTS)
	norms.resize(VERTS * VERTS)
	cols.resize(VERTS * VERTS)
	bio.resize(VERTS * VERTS)
	var e: Dictionary = DBEras.era(era)
	var g: Dictionary = e.ground
	var road_c: Color = g.road
	var wl := gen.water_level
	var net: RoadNet = gen.net
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
			bio[idx] = BIOMES.find(b)
			var c: Color = g.get(b, g.plains)
			var jit := gen.n_detail.get_noise_2d(x * 2.7, z * 2.7)
			if b == "urban":
				c = _settlement_ground(x, z, g, jit)
			else:
				c = _palette_variation(c, b, x, z, g)
			c = c.lightened(jit * 0.09) if jit > 0.0 else c.darkened(-jit * 0.12)
			var slope := 1.0 - norms[idx].y
			if slope > 0.25 and b != "urban":
				c = c.lerp(g.mountain, clampf((slope - 0.25) * 2.5, 0.0, 0.7))
			var rn := net.near(x, z)
			if rn.y >= 0.0:
				var ed: float = rn.x - net.s_hw[int(rn.y)]
				if ed < 2.5 and net.s_flag[int(rn.y)] != RoadNet.FLAG_BRIDGE:
					c = c.lerp(road_c.darkened(0.1), smoothstep(2.5, -0.5, ed) * 0.55)
			if h < wl + 0.6:
				c = c.lerp(g.sand.darkened(0.2).lerp(road_c, 0.35), clampf((wl + 0.6 - h) * 0.9, 0.0, 0.85))
			cols[idx] = c
	var hsam := HSampler.new()
	hsam.gen = gen
	hsam.big = big
	hsam.W = W
	hsam.ox = ox
	hsam.oz = oz
	var out := {"hs": hs, "verts": verts, "norms": norms, "cols": cols, "min_h": min_h}
	if min_h < wl:
		var wv := PackedVector3Array()
		var wcol := PackedColorArray()
		wv.resize(VERTS * VERTS)
		wcol.resize(VERTS * VERTS)
		for q in VERTS * VERTS:
			var vv: Vector3 = verts[q]
			wv[q] = Vector3(vv.x, wl, vv.z)
			wcol[q] = Color(clampf((wl - vv.y) / 4.0, 0.0, 1.0), 0, 0, 1)
		out["water"] = {"v": wv, "c": wcol}
	out["road"] = _road_data(k, hsam)
	out["veg"] = _veg_data(k, hs, norms, cols, bio)
	var signs: Array = []
	for ci in _cross_idx.get(k, []):
		signs.append({"pos": gen.crossroads[ci], "branches": gen.crossroad_branches(ci)})
	out["signs"] = signs
	return out

func _palette_variation(c: Color, b: String, x: float, z: float, g: Dictionary) -> Color:
	var m := gen.n_moist.get_noise_2d(x * 1.7, z * 1.7)
	var t := gen.n_temp.get_noise_2d(x * 2.3, z * 2.3)
	match b:
		"plains":
			if m < -0.15:
				c = c.lerp(Color(0.62, 0.58, 0.3) if era != 4 else Color(0.35, 0.3, 0.45), clampf((-0.15 - m) * 1.6, 0.0, 0.4))
			elif m > 0.15:
				c = c.lerp(g.forest, clampf((m - 0.15) * 1.4, 0.0, 0.35))
		"forest":
			c = c.lerp(c.darkened(0.25), clampf(t * 1.2, 0.0, 0.35))
		"swamp":
			c = c.lerp(Color(0.25, 0.27, 0.16), clampf(m * 1.5, 0.0, 0.4))
		"sand":
			c = c.lerp(c.darkened(0.15), clampf(t, 0.0, 0.3))
	if era == 2 and b in ["plains", "forest"]:
		c = c.lerp(Color(0.32, 0.31, 0.27), clampf(gen.n_ravine.get_noise_2d(x * 0.6, z * 0.6) + 0.15, 0.0, 0.35))
	return c

## Main-thread part: terrain mesh, collision, water and road meshes.
func _terrain_nodes(node: Node3D, d: Dictionary) -> PackedFloat32Array:
	var hs: PackedFloat32Array = d.hs
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
	var wd = d.get("water")
	if wd != null:
		var wa := []
		wa.resize(Mesh.ARRAY_MAX)
		wa[Mesh.ARRAY_VERTEX] = wd.v
		wa[Mesh.ARRAY_COLOR] = wd.c
		wa[Mesh.ARRAY_INDEX] = _terrain_idx
		var wm_mesh := ArrayMesh.new()
		wm_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wa)
		var wm := MeshInstance3D.new()
		wm.name = "Water"
		wm.mesh = wm_mesh
		wm.material_override = _water_mat
		wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(wm)
	var rd: Dictionary = d.get("road", {})
	if rd.has("v") and (rd.v as PackedVector3Array).size() > 0:
		var ra := []
		ra.resize(Mesh.ARRAY_MAX)
		ra[Mesh.ARRAY_VERTEX] = rd.v
		ra[Mesh.ARRAY_NORMAL] = rd.n
		ra[Mesh.ARRAY_TEX_UV] = rd.uv
		ra[Mesh.ARRAY_COLOR] = rd.c
		ra[Mesh.ARRAY_INDEX] = rd.i
		var rm := ArrayMesh.new()
		rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
		var rmi := MeshInstance3D.new()
		rmi.name = "Roads"
		rmi.mesh = rm
		rmi.material_override = _road_mat
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(rmi)
	for kind in ["sleeper", "rail"]:
		var buf = rd.get(kind)
		if buf == null or (buf as PackedFloat32Array).is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rail_mesh(kind)
		mm.instance_count = (buf as PackedFloat32Array).size() / 12
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Track_" + kind
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	return hs

func _rail_mesh(kind: String) -> Mesh:
	if kind == "sleeper":
		var bm := MeshLib.box(Vector3(2.5, 0.14, 0.26))
		bm.material = MeshLib.mat(Color(0.28, 0.2, 0.14))
		return bm
	var rm := MeshLib.box(Vector3(0.09, 0.14, 1.0))
	rm.material = MeshLib.mat(Color(0.55, 0.52, 0.5), 0.85, 0.35)
	return rm

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
		c = dirt.lerp(grass, clampf(0.45 + patch * 1.6 + (d - 0.45) * 1.1, 0.0, 0.9))
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

## Clear distance from the road surface (railway beds included); 999 if far.
func _road_clear(x: float, z: float) -> float:
	var net: RoadNet = gen.net
	var rn := net.near(x, z)
	if rn.y < 0.0:
		return 999.0
	var si := int(rn.y)
	return rn.x - net.s_hw[si] - net.s_ext[si]

# ---------------------------------------------------------------- roads (worker)
func _road_data(k: Vector2i, hsam: HSampler) -> Dictionary:
	var net: RoadNet = gen.net
	var R := {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array(),
		"sl": [], "rl": []}
	var ox := k.x * CHUNK
	var oz := k.y * CHUNK
	var segs = net.coarse.get(k)
	if segs != null:
		for si in segs:
			if net.s_flag[si] != RoadNet.FLAG_ROAD:
				continue
			var a := net.sa[si]
			var b := net.sb[si]
			if maxf(a.x, b.x) < ox - 8.0 or minf(a.x, b.x) > ox + CHUNK + 8.0 or maxf(a.y, b.y) < oz - 8.0 or minf(a.y, b.y) > oz + CHUNK + 8.0:
				continue
			var typ: int = net.s_type[si]
			var li: int = net.s_line[si]
			var hw: float = net.s_hw[si]
			var lift := (0.075 if typ == RoadNet.MAIN else 0.05) + float(li % 4) * 0.007
			_strip(R, k, hsam, si, 0.0, hw, RoadNet.margin_of(era, typ), 0.0 if typ == RoadNet.MAIN else 0.33, lift, false)
			if net.line_rail[li] == 1:
				_strip(R, k, hsam, si, RoadNet.RAIL_OFFSET, 1.45, 0.45, 0.66, 0.04, true)
	for s in _set_idx.get(k, []):
		_plaza(R, k, s)
	var out := {"v": R.v, "n": R.n, "uv": R.uv, "c": R.c, "i": R.i}
	if not (R.sl as Array).is_empty():
		out["sleeper"] = _pack(R.sl)
		out["rail"] = _pack(R.rl)
	return out

static func _pack(list: Array) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(list.size() * 12)
	var q := 0
	for e in list:
		var b: Basis = e[0]
		var o: Vector3 = e[1]
		buf[q] = b.x.x
		buf[q + 1] = b.y.x
		buf[q + 2] = b.z.x
		buf[q + 3] = o.x
		buf[q + 4] = b.x.y
		buf[q + 5] = b.y.y
		buf[q + 6] = b.z.y
		buf[q + 7] = o.y
		buf[q + 8] = b.x.z
		buf[q + 9] = b.y.z
		buf[q + 10] = b.z.z
		buf[q + 11] = o.z
		q += 12
	return buf

const _LAT_EDGE := [0.0, 0.8, 1.0, 1.0, 0.8, 0.0]

## One road (or railway bed) strip for segment `si`, laterally shifted by
## `offset`. Quads are owned by the chunk containing their centre, so strips
## are seamless across chunks. Miter joints at polyline vertices.
func _strip(R: Dictionary, k: Vector2i, hsam: HSampler, si: int, offset: float, hw: float, margin: float, kind: float, lift: float, rail: bool) -> void:
	var net: RoadNet = gen.net
	var a := net.sa[si]
	var b := net.sb[si]
	var L := a.distance_to(b)
	if L < 0.05:
		return
	var dir := (b - a) / L
	var perp := Vector2(-dir.y, dir.x)
	var d0 := dir
	var d1 := dir
	var ps: int = net.s_prev[si]
	if ps >= 0 and net.s_flag[ps] == RoadNet.FLAG_ROAD and net.sb[ps].distance_to(a) < 0.01:
		d0 = (dir + (net.sb[ps] - net.sa[ps]).normalized()).normalized()
	var ns: int = net.s_next[si]
	if ns >= 0 and net.s_flag[ns] == RoadNet.FLAG_ROAD and net.sa[ns].distance_to(b) < 0.01:
		d1 = (dir + (net.sb[ns] - net.sa[ns]).normalized()).normalized()
	var m := maxi(1, ceili(L / 2.0))
	var s0: float = net.s_s0[si]
	var E := hw + margin
	var lats := [-E, -hw, -hw / 3.0, hw / 3.0, hw, E]
	var ox := k.x * CHUNK
	var oz := k.y * CHUNK
	var org := Vector2(ox, oz)
	var vv: PackedVector3Array = R.v
	var nn: PackedVector3Array = R.n
	var uu: PackedVector2Array = R.uv
	var cc: PackedColorArray = R.c
	var ii: PackedInt32Array = R.i
	var wl := gen.water_level
	for q in m:
		var t0 := float(q) / m
		var t1 := float(q + 1) / m
		var mid := a.lerp(b, (t0 + t1) * 0.5) + perp * offset
		if key_of(mid) != k:
			continue
		if rail:
			if gen.settlement_at(mid.x, mid.y, 1.2) != null:
				continue
			if hsam.h(mid.x - ox, mid.y - oz) < wl + 0.25 or _near_poi(mid.x, mid.y, k, 2.0):
				continue
		var base := vv.size()
		var sec_c: Array = []
		for side in 2:
			var t := t0 if side == 0 else t1
			var dd := dir
			if side == 0 and q == 0:
				dd = d0
			elif side == 1 and q == m - 1:
				dd = d1
			var pp := Vector2(-dd.y, dd.x)
			var msc := 1.0 / maxf(0.5, pp.dot(perp))
			var c := a.lerp(b, t) + pp * offset * msc - org
			sec_c.append(Vector3(c.x, hsam.h(c.x, c.y), c.y))
			var hn := hsam.normal(c.x, c.y)
			for vi in 6:
				var off: float = lats[vi]
				var p2 := c + pp * off * msc
				vv.append(Vector3(p2.x, hsam.h(p2.x, p2.y) + lift, p2.y))
				nn.append(hn)
				uu.append(Vector2(off, s0 + t * L))
				cc.append(Color(_LAT_EDGE[vi], kind, (off / E + 1.0) * 0.5, hw / 8.0))
		for vi in 5:
			var i0 := base + vi
			var i1 := base + vi + 1
			var j0 := base + 6 + vi
			var j1 := base + 6 + vi + 1
			ii.append(i0)
			ii.append(j0)
			ii.append(j1)
			ii.append(i0)
			ii.append(j1)
			ii.append(i1)
		if rail:
			_track(R, sec_c[0], sec_c[1], s0 + t0 * L, s0 + t1 * L)
	R.v = vv
	R.n = nn
	R.uv = uu
	R.c = cc
	R.i = ii

func _track(R: Dictionary, p0: Vector3, p1: Vector3, a0: float, a1: float) -> void:
	var fwd := p1 - p0
	var ln := fwd.length()
	if ln < 0.01:
		return
	fwd /= ln
	var side := Vector3.UP.cross(fwd).normalized()
	var up := fwd.cross(side).normalized()
	var basis := Basis(side, up, fwd)
	var sl: Array = R.sl
	var rl: Array = R.rl
	var s := ceilf(a0 / 0.8) * 0.8
	while s < a1:
		var t := (s - a0) / (a1 - a0)
		sl.append([basis, p0.lerp(p1, t) + Vector3(0, 0.12, 0)])
		s += 0.8
	for sx in [-0.72, 0.72]:
		var rb := Basis(side, up, fwd * ln)
		rl.append([rb, (p0 + p1) * 0.5 + side * sx + Vector3(0, 0.25, 0)])

func _plaza(R: Dictionary, k: Vector2i, s: Dictionary) -> void:
	var sp: Vector2 = s.pos
	var rad: float = float(s.radius) * RoadNet.plaza_ratio(str(s.type))
	var y: float = float(s.height) + 0.04
	var pa := 0.2 if s.type == "village" else 0.6
	var c := Vector2(sp.x - k.x * CHUNK, sp.y - k.y * CHUNK)
	var vv: PackedVector3Array = R.v
	var nn: PackedVector3Array = R.n
	var uu: PackedVector2Array = R.uv
	var cc: PackedColorArray = R.c
	var ii: PackedInt32Array = R.i
	var base := vv.size()
	var seg := 28
	vv.append(Vector3(c.x, y, c.y))
	nn.append(Vector3.UP)
	uu.append(sp)
	cc.append(Color(1, 1, 0.5, pa))
	for q in seg:
		var a := TAU * q / seg
		var dv := Vector2(cos(a), sin(a))
		for ring in 2:
			var r := rad - 0.6 if ring == 0 else rad + 1.2
			var p := c + dv * r
			vv.append(Vector3(p.x, y, p.y))
			nn.append(Vector3.UP)
			uu.append(sp + dv * r)
			cc.append(Color(1.0 if ring == 0 else 0.0, 1, 0.5, pa))
	for q in seg:
		var qi := base + 1 + q * 2
		var qn := base + 1 + ((q + 1) % seg) * 2
		ii.append(base)
		ii.append(qi)
		ii.append(qn)
		ii.append(qi)
		ii.append(qi + 1)
		ii.append(qn + 1)
		ii.append(qi)
		ii.append(qn + 1)
		ii.append(qn)
	R.v = vv
	R.n = nn
	R.uv = uu
	R.c = cc
	R.i = ii

# ---------------------------------------------------------------- vegetation (worker)
func _veg_data(k: Vector2i, hs: PackedFloat32Array, norms: PackedVector3Array, cols: PackedColorArray, bio: PackedByteArray) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("veg|%d|%d|%d|%d" % [gen.seed_v, era, k.x, k.y])
	var ox := k.x * CHUNK
	var oz := k.y * CHUNK
	var pf: float = _vq.get("props", 0.8)
	var gf: float = _vq.get("grass", 0.7)
	var wl := gen.water_level
	var lists := {}       # type key -> Array[[Basis, Vector3, Color]]
	var colliders: Array = []
	var near_set := false
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if _set_idx.has(k + Vector2i(dx, dz)):
				near_set = true
	# --- big landscape objects and small detail
	for pass_i in 2:
		var cell := (6.0 if pass_i == 0 else 4.2) / sqrt(maxf(0.2, pf))
		var n := int(CHUNK / cell)
		for gz in n:
			for gx in n:
				var lx := (gx + rng.randf()) * cell
				var lz := (gz + rng.randf()) * cell
				var r1 := rng.randf()
				var r2 := rng.randf()
				var rs := rng.randf()
				var rr := rng.randf() * TAU
				var vi := clampi(roundi(lz / STEP), 0, RES) * VERTS + clampi(roundi(lx / STEP), 0, RES)
				var bname: String = BIOMES[bio[vi]] if bio[vi] < BIOMES.size() else "plains"
				var tab: Dictionary = _veg.get(bname, {})
				if tab.is_empty():
					continue
				var dens: float = tab.bd if pass_i == 0 else tab.sd
				if dens <= 0.0:
					continue
				var x := ox + lx
				var z := oz + lz
				var cl := gen.n_moist.get_noise_2d(x * 3.3, z * 3.3)
				dens *= clampf(0.55 + cl * 1.3, 0.15, 1.5)
				if r1 > dens:
					continue
				var h := _local_h(hs, lx, lz)
				if h < wl + 0.3:
					continue
				var slope := 1.0 - norms[vi].y
				var list: Array = tab.big if pass_i == 0 else tab.small
				if list.is_empty():
					continue
				var entry: Array = _pick_weighted(list, r2)
				var t: String = entry[0]
				var cat := Props.category(t)
				if slope > 0.4 and cat in ["tree", "small", "urban"]:
					continue
				var pad := 3.0 if pass_i == 0 else 1.2
				if _road_clear(x, z) < pad:
					continue
				if near_set and gen.settlement_at(x, z, 1.1) != null:
					continue
				if _near_poi(x, z, k, pad + 1.0):
					continue
				var sc: float = lerpf(entry[2], entry[3], rs)
				var tf_b := Basis(Vector3.UP, rr).scaled(Vector3(sc, sc, sc))
				var key := t
				if cat == "detail":
					key = "%s@%d" % [t, (1 if lx >= 32.0 else 0) + (2 if lz >= 32.0 else 0)]
				if not lists.has(key):
					lists[key] = []
				lists[key].append([tf_b, Vector3(lx, h - 0.05, lz), Color(1, 1, 1)])
				if pass_i == 0:
					var cd := Props.collider(t)
					if not cd.is_empty():
						colliders.append([cd, Vector3(lx, h, lz), rr, sc])
	# --- grass tufts and riverbank reeds
	if gf > 0.01:
		var gcell := 1.45 / sqrt(gf)
		var gn := int(CHUNK / gcell)
		for gz in gn:
			for gx in gn:
				var lx := (gx + rng.randf()) * gcell
				var lz := (gz + rng.randf()) * gcell
				var r1 := rng.randf()
				var rs := rng.randf()
				var rr := rng.randf() * TAU
				var vi := clampi(roundi(lz / STEP), 0, RES) * VERTS + clampi(roundi(lx / STEP), 0, RES)
				var bname: String = BIOMES[bio[vi]] if bio[vi] < BIOMES.size() else "plains"
				var tab: Dictionary = _veg.get(bname, {})
				var dens: float = tab.get("grass", 0.0)
				var x := ox + lx
				var z := oz + lz
				var h := _local_h(hs, lx, lz)
				var t := "grass:" + bname
				if h < wl + 0.15:
					continue
				if h < wl + 0.85 and bname in ["plains", "forest", "swamp"]:
					t = "reeds"
					dens = 0.55
				if dens <= 0.0:
					continue
				var cl := gen.n_moist.get_noise_2d(x * 2.1 + 40.0, z * 2.1)
				dens *= clampf(0.75 + cl * 1.2, 0.3, 1.4)
				if r1 > dens:
					continue
				if norms[vi].y < 0.72:
					continue
				if _road_clear(x, z) < 0.4:
					continue
				if near_set:
					var s = gen.settlement_at(x, z, 1.05)
					if s != null and not _grass_ok_in(s, x, z):
						continue
				if _near_poi(x, z, k, 0.5):
					continue
				var sc := lerpf(0.75, 1.35, rs)
				var tint := Color(1, 1, 1)
				var key := "%s@%d" % [t, (1 if lx >= 32.0 else 0) + (2 if lz >= 32.0 else 0)]
				if not lists.has(key):
					lists[key] = []
				lists[key].append([Basis(Vector3.UP, rr).scaled(Vector3(sc, sc * lerpf(0.8, 1.2, r1), sc)), Vector3(lx, h - 0.03, lz), tint])
	# pack buffers
	var mm := {}
	for key in lists:
		var arr: Array = lists[key]
		var t2: String = str(key).get_slice("@", 0)
		var colored := false
		var stride := 12
		var buf := PackedFloat32Array()
		buf.resize(arr.size() * stride)
		var q := 0
		for e in arr:
			var b: Basis = e[0]
			var o: Vector3 = e[1]
			buf[q] = b.x.x
			buf[q + 1] = b.y.x
			buf[q + 2] = b.z.x
			buf[q + 3] = o.x
			buf[q + 4] = b.x.y
			buf[q + 5] = b.y.y
			buf[q + 6] = b.z.y
			buf[q + 7] = o.y
			buf[q + 8] = b.x.z
			buf[q + 9] = b.y.z
			buf[q + 10] = b.z.z
			buf[q + 11] = o.z
			if colored:
				var c: Color = e[2]
				buf[q + 12] = c.r
				buf[q + 13] = c.g
				buf[q + 14] = c.b
				buf[q + 15] = 1.0
			q += stride
		mm[key] = {"type": t2, "buf": buf, "n": arr.size(), "colors": colored}
	return {"mm": mm, "cols": colliders}

func _grass_ok_in(s: Dictionary, x: float, z: float) -> bool:
	var sp: Vector2 = s.pos
	var p := Vector2(x, z)
	if p.distance_to(sp) < float(s.radius) * 0.36:
		return false
	for b in s.buildings:
		var bp: Vector2 = b.pos
		var bsz: Vector2 = b.size
		if p.distance_to(bp) < maxf(bsz.x, bsz.y) * 0.66 + 0.8:
			return false
	return true

func _pick_weighted(list: Array, r: float) -> Array:
	var total := 0.0
	for e in list:
		total += float(e[1])
	var acc := r * total
	for e in list:
		acc -= float(e[1])
		if acc <= 0.0:
			return e
	return list[list.size() - 1]

# ---------------------------------------------------------------- props (main thread)
func _build_props(node: Node3D, k: Vector2i, d: Dictionary) -> void:
	var vd: Dictionary = d.get("veg", {})
	if vd.is_empty():
		return
	var shadows: bool = _vq.get("shadows", true)
	var detail: float = _vq.get("detail", 40.0)
	var mmd: Dictionary = vd.mm
	for key in mmd:
		var e: Dictionary = mmd[key]
		var t: String = e.type
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = e.colors
		mm.mesh = Props.prop_mesh(t, era)
		mm.instance_count = e.n
		mm.buffer = e.buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "P_" + str(key)
		var cat := Props.category(t)
		if cat == "detail":
			mmi.visibility_range_end = detail + 24.0
		elif cat == "small":
			mmi.visibility_range_end = maxf(detail * 2.2, 90.0)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows and cat in ["tree", "urban", "rock"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)
	var cols: Array = vd.cols
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

func _build_structures(node: Node3D, k: Vector2i, st: Dictionary, rng: RandomNumberGenerator, d: Dictionary = {}) -> void:
	var origin := node.position
	buildings[k] = []
	# buildings whose centre is in this chunk (deferred while streaming)
	for pair in _bld_idx.get(k, []):
		if _defer_buildings:
			_bld_jobs.append([k, node, pair[0], pair[1], st])
		else:
			_make_building(k, node, pair[0], pair[1], st)
	# settlement squares: centrepiece, stalls, well, forge, lamps, banners, crates...
	for s in _set_idx.get(k, []):
		if _defer_buildings:
			_bld_jobs.append([k, node, "settlement", s, st])
		else:
			SettlementProps.build(self, node, k, s, st)
	# bridges and crossroads signposts
	for si in _bridge_idx.get(k, []):
		if _defer_buildings:
			_bld_jobs.append([k, node, "bridge", si, null])
		else:
			_build_bridge(node, si)
	for sg in d.get("signs", []):
		var sp: Vector2 = sg.pos
		SettlementProps.signpost(node, Vector3(sp.x - origin.x, gen.height(sp.x, sp.y), sp.y - origin.z), sg.branches, era, gen)
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
			if gen.is_water(x, z) or _road_clear(x, z) < 1.5 or _near_poi(x, z, k, 3.0):
				continue
			var c := Chest.new()
			c.configure("c%d_%d_ch" % [k.x, k.y], st, era, "normal", _chest_level(Vector2(x, z)), rng.randf())
			c.position = Vector3(lx, gen.height(x, z), lz)
			c.rotation.y = rng.randf() * TAU
			node.add_child(c)
			break
	# ambient life (butterflies, leaves, birds, dust...)
	if _vq.get("ambient", true):
		AmbientLife.populate(self, node, k, rng)

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

func _hits_building(s: Dictionary, p: Vector2, pad: float) -> bool:
	for b in s.buildings:
		var bp: Vector2 = b.pos
		var sz: Vector2 = b.size
		if p.distance_to(bp) < maxf(sz.x, sz.y) * 0.75 + pad:
			return true
	return false

# ---------------------------------------------------------------- bridges
static var _bridge_cache := {}

## Walkable bridge over water for bridge segment `si` (deck, railings,
## supports; era-styled), with box collision along the arched deck.
func _build_bridge(node: Node3D, si: int) -> void:
	var net: RoadNet = gen.net
	var a := net.sa[si]
	var b := net.sb[si]
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var hw: float = net.s_hw[si] + 0.3
	var ha := gen.height(a.x, a.y)
	var hb := gen.height(b.x, b.y)
	var wl := gen.water_level
	var n := maxi(2, ceili(L / 4.0))
	var arch := minf(1.6, L * 0.05)
	var pts: Array = []
	for i in n + 1:
		var t := float(i) / n
		var y := lerpf(ha, hb, t) + sin(t * PI) * arch
		y = maxf(y, wl + 0.7 + sin(t * PI) * 0.6) if (i > 0 and i < n) else y
		pts.append(Vector3(a.x + (b.x - a.x) * t, y + 0.12, a.y + (b.y - a.y) * t))
	var root := Node3D.new()
	root.name = "Bridge%d" % si
	node.add_child(root)
	var key := "%d|%d|%d" % [gen.seed_v, era, si]
	var mesh: ArrayMesh = _bridge_cache.get(key)
	var dir3 := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
	var side := Vector3.UP.cross(dir3).normalized()
	var origin := node.position
	if mesh == null:
		var m := Props.Merger.new()
		var deck_m: Material
		var rail_m: Material
		var sup_m: Material
		match era:
			0:
				deck_m = MeshLib.mat(Color(0.5, 0.36, 0.22))
				rail_m = MeshLib.mat(Color(0.4, 0.28, 0.17))
				sup_m = MeshLib.mat(Color(0.35, 0.25, 0.16))
			1:
				deck_m = MeshLib.mat(Color(0.72, 0.66, 0.56))
				rail_m = MeshLib.mat(Color(0.8, 0.75, 0.66))
				sup_m = MeshLib.mat(Color(0.62, 0.58, 0.5))
			2:
				deck_m = MeshLib.mat(Color(0.36, 0.3, 0.26))
				rail_m = MeshLib.mat(Color(0.25, 0.25, 0.27), 0.7, 0.45)
				sup_m = MeshLib.mat(Color(0.48, 0.26, 0.2))
			3:
				deck_m = MeshLib.mat(Color(0.3, 0.3, 0.32))
				rail_m = MeshLib.mat(Color(0.7, 0.72, 0.74), 0.6, 0.4)
				sup_m = MeshLib.mat(Color(0.62, 0.62, 0.6))
			_:
				deck_m = MeshLib.mat(Color(0.14, 0.15, 0.2), 0.6, 0.3)
				rail_m = MeshLib.mat(Color(0.25, 0.95, 1.0), 0.0, 0.4, 2.5)
				sup_m = MeshLib.mat(Color(0.25, 0.27, 0.32), 0.7, 0.35)
		for i in n:
			var p0: Vector3 = pts[i] - Vector3(origin.x, 0, origin.z)
			var p1: Vector3 = pts[i + 1] - Vector3(origin.x, 0, origin.z)
			var c := (p0 + p1) * 0.5
			var f := (p1 - p0)
			var fl := f.length()
			var fwd := f / fl
			var up := fwd.cross(side).normalized()
			var basis := Basis(side, up, fwd)
			m.add(MeshLib.box(Vector3(hw * 2.0, 0.28, 1.0)), deck_m, Transform3D(basis.scaled_local(Vector3(1, 1, fl + 0.05)), c))
			if era == 0:
				for q in 3:
					m.add(MeshLib.box(Vector3(hw * 2.0 + 0.1, 0.06, 0.18)), rail_m, Transform3D(basis, c + up * 0.15 + fwd * (q - 1) * fl * 0.33))
			for sx in [-1.0, 1.0]:
				var rp: Vector3 = c + side * float(sx) * (hw - 0.1)
				if era == 1:
					m.add(MeshLib.box(Vector3(0.3, 0.8, 1.0)), rail_m, Transform3D(basis.scaled_local(Vector3(1, 1, fl)), rp + up * 0.5))
				else:
					m.add(MeshLib.box(Vector3(0.09, 0.09, 1.0)), rail_m, Transform3D(basis.scaled_local(Vector3(1, 1, fl)), rp + up * 1.0))
					m.add(MeshLib.box(Vector3(0.12, 1.0, 0.12)), rail_m if era != 4 else sup_m, Transform3D(Basis(), p0 + side * sx * (hw - 0.1) + Vector3(0, 0.55, 0)))
			# supports down into the water
			if i > 0 and i % 2 == 0:
				var depth := p0.y - (wl - 2.2)
				if era == 1 or era == 3:
					m.add(MeshLib.box(Vector3(hw * 1.6, depth, 1.2)), sup_m, Transform3D(Basis(Vector3.UP, atan2(dir3.x, dir3.z)), p0 - Vector3(0, depth * 0.5 + 0.1, 0)))
				else:
					for sx2 in [-1.0, 1.0]:
						m.add(MeshLib.cyl(0.16, 0.2, depth, 6), sup_m, Transform3D(Basis(), p0 + side * sx2 * (hw - 0.4) - Vector3(0, depth * 0.5 + 0.1, 0)))
		if era == 2:
			# steel truss arcs
			for sx3 in [-1.0, 1.0]:
				for i in n:
					var q0: Vector3 = pts[i] - Vector3(origin.x, 0, origin.z)
					var q1: Vector3 = pts[i + 1] - Vector3(origin.x, 0, origin.z)
					var t0 := float(i) / n
					var t1 := float(i + 1) / n
					var u0: Vector3 = q0 + side * float(sx3) * hw + Vector3(0, 0.3 + sin(t0 * PI) * 2.6, 0)
					var u1: Vector3 = q1 + side * float(sx3) * hw + Vector3(0, 0.3 + sin(t1 * PI) * 2.6, 0)
					var f2: Vector3 = u1 - u0
					var b2 := Basis.looking_at(f2.normalized(), Vector3.UP)
					m.add(MeshLib.box(Vector3(0.14, 0.14, 1.0)), rail_m, Transform3D(b2.scaled_local(Vector3(1, 1, f2.length() + 0.1)), (u0 + u1) * 0.5))
					m.add(MeshLib.box(Vector3(0.08, 1.0, 0.08)), rail_m, Transform3D(Basis().scaled(Vector3(1, maxf(0.1, u0.y - q0.y), 1)), (u0 + q0) * 0.5))
		mesh = m.commit()
		_bridge_cache[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _vq.get("shadows", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	root.add_child(sb)
	for i in n:
		var p0: Vector3 = pts[i] - Vector3(origin.x, 0, origin.z)
		var p1: Vector3 = pts[i + 1] - Vector3(origin.x, 0, origin.z)
		var f := p1 - p0
		var fl := f.length()
		var fwd := f / fl
		var up := fwd.cross(side).normalized()
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(hw * 2.0, 0.3, fl + 0.1)
		cs.shape = bx
		cs.transform = Transform3D(Basis(side, up, fwd), (p0 + p1) * 0.5)
		sb.add_child(cs)
		# railings block falls
		for sx in [-1.0, 1.0]:
			var cr := CollisionShape3D.new()
			var rb := BoxShape3D.new()
			rb.size = Vector3(0.2, 1.1, fl + 0.1)
			cr.shape = rb
			cr.transform = Transform3D(Basis(side, up, fwd), (p0 + p1) * 0.5 + side * sx * hw + up * 0.6)
			sb.add_child(cr)

# ---------------------------------------------------------------- points of interest
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
			SettlementProps.campfire(self, node, local + Vector3(2.5, 0, 2.0), era, key_of(pp))
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
