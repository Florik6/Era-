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
	cam.fov = 50.0
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
	cam.global_position = target + Vector3(0, 14, 10) * dist
	cam.look_at(target, Vector3.UP)
	marker.global_position = target

func _shot(nm: String, frames: int = 6) -> void:
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + nm + ".png")

func _run_era(e: int) -> void:
	await _setup_era(e)
	var sp := gen.spawn_point()
	var target := Vector3(sp.x, gen.height(sp.x, sp.y), sp.y)
	var t0 := Time.get_ticks_usec()
	streamer.force_load_around(target)
	var t_load := (Time.get_ticks_usec() - t0) / 1000.0
	var bt: Array = streamer.build_times
	var mx := 0.0
	var sum := 0.0
	for x in bt:
		mx = maxf(mx, x)
		sum += x
	print("ERA %d: force_load %d chunks in %.0f ms (avg %.1f, max %.1f ms per chunk)" % [e, bt.size(), t_load, sum / maxf(1, bt.size()), mx])
	_look(target)
	await _shot("world_era%d" % e)
	# wider overview of the village from higher up
	_look(target, 1.9)
	await _shot("world_era%d_wide" % e)
	# wilderness: walk the camera to a forest/camp area and stream incrementally
	var camp: Dictionary = gen.pois_of("camp")[0]
	var cp: Vector2 = camp.pos
	var ct := Vector3(cp.x, gen.height(cp.x, cp.y), cp.y)
	streamer.build_times.clear()
	for i in 60:
		streamer.update_center(ct)
		await get_tree().process_frame
	var bt2: Array = streamer.build_times
	var mx2 := 0.0
	for x in bt2:
		mx2 = maxf(mx2, x)
	print("ERA %d: streamed %d chunks incrementally, max %.1f ms" % [e, bt2.size(), mx2])
	_look(ct)
	await _shot("world_era%d_camp" % e)
	if e == 0 or e == 4:
		# building interior with roof cut away
		streamer.force_load_around(target)
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
			_look(inside, 0.8)
			marker.global_position = inside
			await _shot("world_era%d_interior" % e, 10)
			b.viewer = null
		# lair
		var lair: Dictionary = gen.pois_of("lair")[0]
		var lp: Vector2 = lair.pos
		var lt := Vector3(lp.x, gen.height(lp.x, lp.y), lp.y)
		streamer.force_load_around(lt)
		_look(lt, 1.6)
		await _shot("world_era%d_lair" % e)
		# night + rain at the village
		streamer.force_load_around(target)
		dn.time_override = 23.0
		weather.set_weather("rain", 999.0)
		_look(target)
		for i in 30:
			await get_tree().process_frame
		await _shot("world_era%d_night_rain" % e)
		dn.time_override = 10.5
		weather.set_weather("fog", 999.0)
		for i in 40:
			await get_tree().process_frame
		await _shot("world_era%d_fog" % e)
		weather.set_weather("clear", 999.0)
