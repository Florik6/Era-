extends Node
func _ready() -> void:
	var g := WorldGen.new()
	g.setup(4242, 0)
	var s := ChunkStreamer.new()
	add_child(s)
	s.setup(g, {})
	var sp := g.spawn_point()
	print("start")
	var t0 := Time.get_ticks_usec()
	s.force_load_around(Vector3(sp.x, 0, sp.y))
	print("force_load ms ", (Time.get_ticks_usec() - t0) / 1000.0, " chunks ", s.chunks.size())
	var mx := 0.0
	for x in s.build_times: mx = maxf(mx, x)
	print("max chunk ms ", mx)
	get_tree().quit()
