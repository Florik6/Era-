extends Node
## Visual check of the magic / combat VFX in the real living world: stages each
## school (fire, ice, lightning, dark, space-time) plus combat feedback, boss
## telegraphs and loot rarity around the player against real enemies, and
## saves screenshots to docs/screenshots/vfx_*.png (copies in the scratchpad).
## Run: VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a godot --path . \
##      --rendering-method mobile --rendering-driver vulkan tests/vfx_showcase.tscn
## VFX_Q=low|medium|high picks the quality profile (default high).
const SCRATCH := "/tmp/claude-0/-home-user-Era-/4dd8d359-84a1-5cb8-8e5d-83e3c1e26fc1/scratchpad/"

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	var q := OS.get_environment("VFX_Q")
	Settings.quality = Settings.Quality.LOW if q == "low" else (Settings.Quality.MEDIUM if q == "medium" else Settings.Quality.HIGH)
	Settings.effective_quality = Settings.quality
	Profile.new_character("Тестер", "mage", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 0, "cloth": 2})
	Profile.current_era = 0
	var h := Driver.new()
	h.tag = "" if q == "" or q == "high" else q + "_"
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Driver:
	extends Node
	var tag := ""
	var p = null
	var foes: Array = []
	var shots: Array = []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()

	## Game-time wait (Engine.time_scale is lowered so software rendering at
	## ~2 fps still samples short effects every ~0.05 s of game time).
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, false).timeout

	func shot(nm: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var docs := ProjectSettings.globalize_path("res://docs/screenshots/")
		DirAccess.make_dir_recursive_absolute(docs)
		if tag == "":
			img.save_png(docs + "vfx_%s.png" % nm)
		img.save_png(SCRATCH + "vfx_%s%s.png" % [tag, nm])
		shots.append(nm)
		print("VFX shot ", nm, " fps=", Engine.get_frames_per_second(), " live_sys=", Game.world.vfx._live_sys.size(), " lights=", Game.world.vfx._lights_live)

	func cast(id: String, aim: Vector3) -> void:
		p.act = {}
		p.skill_cd.erase(id)
		Spells.cast_free(p, id, aim, 30.0)

	func clear_foes() -> void:
		for f in foes:
			if is_instance_valid(f):
				f.queue_free()
		foes.clear()

	func spawn_foes(center: Vector3, ids: Array, ring: float) -> void:
		var n := ids.size()
		for i in n:
			var a := TAU * i / n
			var pos := center + Vector3(cos(a), 0, sin(a)) * ring
			pos.y = Game.world.ground_height(pos) + 0.1
			var e = Game.world.spawner.spawn_enemy(ids[i], pos, 3)
			if e:
				e.set_physics_process(false)
				e.face_dir(p.global_position - e.global_position)
				foes.append(e)

	func reset_stage() -> void:
		clear_foes()
		p.act = {}
		p.hp = p.max_hp
		p.mana = p.max_mana
		await wait(1.6)

	func _run() -> void:
		await wait(5.0)
		p = Game.player
		if p == null:
			print("VFX: no player")
			get_tree().quit()
			return
		p.apply_status("invuln", 9999.0)
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			n.visible = false
		Engine.time_scale = 0.1
		Game.game_time = floorf(Game.game_time) + 0.45
		if Game.world.weather:
			Game.world.weather.set_weather("clear", 9999.0)
		var fwd := Vector3(0, 0, -1)
		var c: Vector3 = p.global_position
		p.face_dir(fwd)
		await wait(1.0)
		# ---------------------------------------------------------- FIRE
		spawn_foes(c + fwd * 6.0, ["skeleton", "bandit", "skeleton"], 2.2)
		await wait(0.4)
		cast("firewall", fwd)
		await wait(0.7)
		cast("meteor", fwd)
		await wait(0.65)
		cast("ignite", fwd)
		await wait(0.65)
		cast("fireball", fwd.rotated(Vector3.UP, 0.25))
		await wait(0.52)
		await shot("fire")
		await wait(0.5)
		await shot("fire_impact")
		await reset_stage()
		# ----------------------------------------------------------- ICE
		spawn_foes(c, ["skeleton", "bandit", "wolf", "skeleton"], 4.0)
		await wait(0.4)
		cast("freeze", fwd)
		await wait(0.75)
		cast("icewall", fwd.rotated(Vector3.UP, 1.2))
		await wait(0.65)
		cast("blizzard", -fwd)
		await wait(0.65)
		cast("frostbolt", fwd.rotated(Vector3.UP, -0.6))
		await wait(0.48)
		await shot("ice")
		await reset_stage()
		# ----------------------------------------------------- LIGHTNING
		spawn_foes(c + fwd * 6.0, ["skeleton", "bandit", "wolf", "skeleton", "bandit"], 2.8)
		await wait(0.4)
		cast("storm", fwd)
		await wait(0.65)
		cast("chain", fwd)
		await wait(0.4)
		await shot("lightning")
		await wait(0.3)
		cast("thunderclap", fwd)
		await wait(0.4)
		await shot("lightning_clap")
		await reset_stage()
		# ------------------------------------------------- DARK + TIME
		spawn_foes(c + fwd * 5.0, ["skeleton", "bandit", "wolf"], 2.0)
		await wait(0.4)
		cast("curse", fwd)
		await wait(0.65)
		cast("summon", fwd.rotated(Vector3.UP, 1.4))
		await wait(0.65)
		cast("timeslow", fwd)
		await wait(0.65)
		cast("timetrap", -fwd)
		await wait(0.65)
		cast("drain", fwd)
		await wait(0.42)
		await shot("dark_time")
		await wait(0.2)
		cast("blink", Vector3(1, 0, 0))
		await wait(0.4)
		await shot("blink")
		await wait(0.3)
		cast("nova", fwd)
		await wait(0.45)
		await shot("dark_nova")
		await reset_stage()
		# ------------------------------------- COMBAT / TELEGRAPHS / LOOT
		c = p.global_position
		spawn_foes(c + fwd * 4.0, ["skeleton", "knight_renegade", "wolf"], 2.0)
		await wait(0.3)
		VFX.telegraph(c + Vector3(-4, 0, -3), 3.5, 2.0, Color(1, 0.2, 0.1), "circle")
		VFX.telegraph(c + Vector3(3, 0, -2), 5.0, 2.0, Color(1, 0.2, 0.1), "cone", Vector3(0.3, 0, -1), 100.0)
		VFX.telegraph(c + Vector3(-2, 0, 3), 1.2, 2.0, Color(1, 0.2, 0.1), "line", Vector3(1, 0, 0.2), 360.0, 9.0)
		var it4 := ItemDB.random_for_era(0, 6, "boss")
		it4.rarity = 4
		var it5 := ItemDB.random_for_era(0, 6, "boss")
		it5.rarity = 5
		var it3 := ItemDB.random_for_era(0, 6, "boss")
		it3.rarity = 3
		Game.world.loot.spawn_drop(it4, c + Vector3(4.5, 0, 2.5))
		Game.world.loot.spawn_drop(it5, c + Vector3(-5.0, 0, 1.0))
		Game.world.loot.spawn_drop(it3, c + Vector3(1.5, 0, 4.5))
		await wait(1.1)
		for f in foes:
			if is_instance_valid(f):
				var d: Vector3 = (f.global_position - p.global_position).normalized()
				VFX.hit_fx(f.chest() - d * f.radius(), d, "slash", true, false)
		if foes.size() > 1 and is_instance_valid(foes[1]):
			VFX.parry_fx(foes[1].chest() + Vector3(0, 0.2, 0), Vector3(1, 0, 0))
		if foes.size() > 2 and is_instance_valid(foes[2]):
			VFX.hit_fx(foes[2].chest(), Vector3(0, 0, -1), "blunt", true, true)
		VFX.ground_impact(c + Vector3(2, 0, -5.5), 2.5)
		await wait(0.06)
		await shot("combat_loot")
		Engine.time_scale = 1.0
		print("VFX_DONE shots=", shots.size())
		get_tree().quit()
