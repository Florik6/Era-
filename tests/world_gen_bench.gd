extends SceneTree
func _init() -> void:
	var t0 := Time.get_ticks_usec()
	var g := WorldGen.new()
	g.setup(4242, 0)
	print("gen ms ", (Time.get_ticks_usec() - t0) / 1000.0, " s=", g.settlements.size(), " p=", g.pois.size(), " r=", g.roads.size())
	var t1 := Time.get_ticks_usec()
	var acc := 0.0
	for i in 2000:
		acc += g.height(randf_range(-1000, 1000), randf_range(-1000, 1000))
	print("height us/call ", (Time.get_ticks_usec() - t1) / 2000.0)
	quit()
