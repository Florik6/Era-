extends Node
## Full-game weather check: starts the living world and cycles every weather
## state (plus night), screenshotting and logging fog density (30+ s).
const OUT := "/tmp/claude-0/-home-user-Era-/4dd8d359-84a1-5cb8-8e5d-83e3c1e26fc1/scratchpad/"

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Тестер", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.current_era = int(OS.get_environment("WT_ERA")) if OS.get_environment("WT_ERA") != "" else 0
	var h := Driver.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Driver:
	extends Node
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	func _run() -> void:
		await wait(4.0)
		var w = Game.world.weather if Game.world else null
		if w == null:
			print("WT: no weather")
			get_tree().quit()
			return
		var env: Environment = Game.world.env.environment
		var era := Profile.current_era
		var t0 := Time.get_ticks_msec()
		for kind in ["clear", "cloudy", "rain", "storm", "fog", "snow", "wind"]:
			w.set_weather(kind, 999.0)
			await wait(5.0)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OUT + "game_era%d_%s.png" % [era, kind])
			print("WT %s t=%.0fs fog_enabled=%s density=%.5f fps=%d" % [kind, (Time.get_ticks_msec() - t0) / 1000.0, env.fog_enabled, env.fog_density, Engine.get_frames_per_second()])
		Game.game_time = floorf(Game.game_time) + 23.0 / 24.0
		w.set_weather("rain", 999.0)
		await wait(4.0)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT + "game_era%d_night_rain.png" % era)
		print("WT night density=%.5f" % env.fog_density)
		print("WT_DONE")
		get_tree().quit()
