extends Node3D
## Visual + performance test for world generation. Builds every era's world,
## renders screenshots from the gameplay camera angle and prints timings.
## Args after "--": era list, e.g. `-- 0 2`. Output: scratchpad/world_*.png

const OUT := "/tmp/claude-0/-home-user-Era-/4dd8d359-84a1-5cb8-8e5d-83e3c1e26fc1/scratchpad/"

var env: WorldEnvironment
var sun: DirectionalLight3D
var cam: Camera3D
var gen: WorldGen
var streamer: ChunkStreamer
var dn: DayNight
var weather: Weather
var marker: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	Settings.effective_quality = Settings.Quality.MEDIUM
	var eras: Array = []
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			eras.append(int(a))
	if eras.is_empty():
		eras = [0, 1, 2, 3, 4]
	env = WorldEnvironment.new()
	add_child(env)
	sun = DirectionalLight3D.new()
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.far = 260.0
	add_child(cam)
	cam.make_current()
	marker = Node3D.new()
	add_child(marker)
	for e in eras:
		await _run_era(e)
	print("WORLD_TEST_DONE")
	get_tree().quit()

func _setup_era(e: int) -> void:
	if streamer:
		streamer.queue_free()
		dn.queue_free()
		weather.queue_free()
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	gen = WorldGen.new()
	gen.setup(4242, e)
	var t_gen := (Time.get_ticks_usec() - t0) / 1000.0
	streamer = ChunkStreamer.new()
	add_child(streamer)
	streamer.setup(gen, {})
	dn = DayNight.new()
	add_child(dn)
	dn.time_override = 10.5
	dn.setup(env, sun, e)
	weather = Weather.new()
	add_child(weather)
	weather.streamer = streamer
	weather.day_night = dn
	weather.follow = marker
	weather.auto_cycle = false
	weather.setup(env, e)
	dn.weather = weather
	var t1 := Time.get_ticks_usec()
	var img := gen.overview_image(192)
	var t_ov := (Time.get_ticks_usec() - t1) / 1000.0
	img.save_png(OUT + "world_map_era%d.png" % e)
	print("ERA %d: gen %.1f ms, overview(192) %.1f ms, settlements %d, pois %d, roads %d" % [e, t_gen, t_ov, gen.settlements.size(), gen.pois.size(), gen.roads.size()])

func _look(target: Vector3, dist: float = 1.0) -> void:
	# gameplay camera: ~11 m away, pitch 50 deg, looking along -Z
	var d := 11.0 * dist
	cam.global_position = target + Vector3(0, sin(deg_to_rad(50.0)) * d, cos(deg_to_rad(50.0)) * d)
	cam.look_at(target, Vector3.UP)
	marker.global_position = target

func _shot(nm: String, frames: int = 4) -> void:
	var t0 := Time.get_ticks_msec()
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + nm + ".png")
	print("shot %s (%d ms for %d frames)" % [nm, Time.get_ticks_msec() - t0, frames])

func _at(p: Vector2) -> Vector3:
	return Vector3(p.x, gen.height(p.x, p.y), p.y)

func _goto(t: Vector3) -> void:
	streamer.force_load_around(t)

## A point on a main road far from settlements (prefer near a crossroads).
func _road_spot() -> Vector2:
	for c in gen.crossroads:
		var cp: Vector2 = c
		var ok := true
		for s in gen.settlements:
			if cp.distance_to(s.pos) < float(s.radius) * 2.2:
				ok = false
		if ok and gen.road_type_at(cp) == "main":
			return cp + Vector2(0, -3)
	for r in gen.road_net:
		if r.type == "main" and not r.bridge:
			var m: Vector2 = (r.a + r.b) * 0.5
			if gen.settlement_at(m.x, m.y, 2.5) == null:
				return m
	return gen.spawn_point()

func _bridge_spot() -> Vector2:
	for r in gen.road_net:
		if r.bridge and r.type == "main":
			return (r.a + r.b) * 0.5
	for r in gen.road_net:
		if r.bridge:
			return (r.a + r.b) * 0.5
	return Vector2.INF

func _forest_spot() -> Vector2:
	for r in gen.road_net:
		if r.type == "trail" and not r.bridge:
			var m: Vector2 = (r.a + r.b) * 0.5
			if gen.biome(m.x, m.y) == "forest" and gen.settlement_at(m.x, m.y, 2.0) == null:
				return m + Vector2(4, 0)
	return gen.spawn_point() + Vector2(120, 40)

func _run_era(e: int) -> void:
	await _setup_era(e)
	var sp := gen.spawn_point()
	var t0 := Time.get_ticks_usec()
	var village := _at(sp)
	_goto(village)
	print("ERA %d: force_load %d chunks in %.0f ms" % [e, streamer.chunks.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	# village square with props (slightly zoomed out)
	var s0: Dictionary = gen.settlement_at(sp.x, sp.y)
	var vc := _at(s0.pos + Vector2(0, 4)) if s0 else village
	_look(vc, 2.3)
	await _shot("va_era%d_village" % e, 6)
	# road between settlements / crossroads with signpost
	var rs := _at(_road_spot())
	_goto(rs)
	_look(rs, 1.3)
	await _shot("va_era%d_road" % e, 6)
	var bs := _bridge_spot()
	if bs != Vector2.INF:
		var bt := _at(bs)
		bt.y = maxf(bt.y, gen.water_level)
		_goto(bt)
		_look(bt, 1.6)
		await _shot("va_era%d_bridge" % e, 6)
	# forest / landscape along a trail
	var fs := _at(_forest_spot())
	_goto(fs)
	_look(fs, 1.4)
	await _shot("va_era%d_forest" % e, 6)
	# interior with camera-side walls cut away
	_goto(village)
	var b: Building = null
	for arr in streamer.buildings.values():
		for bb in arr:
			if bb.kind in ["inn", "house", "hall"]:
				b = bb
				break
		if b:
			break
	if b:
		var inside := b.to_global(Vector3(0, 0.1, 0))
		b.viewer = marker
		_look(inside, 0.85)
		marker.global_position = inside
		await _shot("va_era%d_interior" % e, 10)
		b.viewer = null
	# night at the village
	dn.time_override = 22.5
	_look(vc, 1.3)
	for i in 6:
		await get_tree().process_frame
	await _shot("va_era%d_night" % e, 4)
	dn.time_override = 10.5
