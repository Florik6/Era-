extends Node
## Measures the worst per-frame cost of chunk streaming while travelling
## through every settlement (where building construction is heaviest).
func _ready() -> void:
	for era in [0, 2, 4]:
		var gen := WorldGen.new()
		gen.setup(4242 + era, era, 1280.0)
		var cs := ChunkStreamer.new()
		add_child(cs)
		cs.setup(gen, {})
		var frames: Array = []
		var start: Vector2 = gen.spawn_point()
		cs.force_load_around(Vector3(start.x, 0, start.y))
		var pts: Array = [start]
		for s in gen.settlements:
			pts.append(s.pos)
		var pos := start
		for target in pts:
			while pos.distance_to(target) > 4.0:
				pos = pos.move_toward(target, 6.0 * 0.0333)   # ~6 m/s at 30 fps
				var t0 := Time.get_ticks_usec()
				cs.update_center(Vector3(pos.x, 0, pos.y))
				frames.append((Time.get_ticks_usec() - t0) / 1000.0)
				if frames.size() % 30 == 0:
					await get_tree().process_frame
			for i in 60:
				var t1 := Time.get_ticks_usec()
				cs.update_center(Vector3(pos.x, 0, pos.y))
				frames.append((Time.get_ticks_usec() - t1) / 1000.0)
		frames.sort()
		var n := frames.size()
		var bt: Array = cs.bld_times.duplicate()
		bt.sort()
		print("ERA %d frames=%d p50=%.2fms p95=%.2fms p99=%.2fms max=%.1fms | building p50=%.1fms max=%.1fms count=%d" % [era, n, frames[n / 2], frames[int(n * 0.95)], frames[int(n * 0.99)], frames[n - 1], bt[bt.size() / 2] if bt.size() > 0 else 0.0, bt[-1] if bt.size() > 0 else 0.0, bt.size()])
		for st_name in cs.stage_times:
			var a: Array = cs.stage_times[st_name].duplicate()
			a.sort()
			if a.size() > 0:
				print("   stage %s p50=%.2f p95=%.2f max=%.2f" % [st_name, a[a.size() / 2], a[int(a.size() * 0.95)], a[-1]])
		cs.queue_free()
		await get_tree().process_frame
	get_tree().quit()
