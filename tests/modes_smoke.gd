extends Node
## Smoke test for Arena / Trials / Chrono-dungeon modes and a late era world.
var shots := ""
func _ready() -> void:
	shots = OS.get_environment("SHOTS_DIR")
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Profile.new_character("Тест", OS.get_environment("SMOKE_CLASS") if OS.get_environment("SMOKE_CLASS") != "" else "mage", true, {"hair": 2})
	var m := OS.get_environment("SMOKE_MODE")
	Profile.current_era = int(OS.get_environment("SMOKE_ERA")) if OS.get_environment("SMOKE_ERA") != "" else 0
	if Profile.current_era > 0:
		Profile.char.level = 32
		Profile.char.add_xp(0)
		Profile.unlocked_eras = [0, 1, 2, 3, 4]
	var h := H.new()
	h.shots = shots
	h.mode = m
	get_tree().root.add_child.call_deferred(h)
	Game.start(m)
class H:
	extends Node
	var shots := ""
	var mode := ""
	func _ready():
		process_mode = Node.PROCESS_MODE_ALWAYS
		await get_tree().create_timer(6.0, true, false, true).timeout
		var w = Game.world
		print("MODE ", Game.mode, " era=", Profile.current_era, " actors=", Game.actors.size(), " objective=", w.objective_text())
		print("DRAW_CALLS ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " OBJECTS ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME), " PRIMS ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots + "/mode_%s_era%d.png" % [mode, Profile.current_era])
		# fight a bit with skills
		var p = Game.player
		for k in 40:
			var tgt = null
			var bd := 30.0
			for a in Game.actors_near(p.global_position, 30.0):
				if a != p and not a.is_dead and Game.can_damage(p, a) and a.global_position.distance_to(p.global_position) < bd:
					bd = a.global_position.distance_to(p.global_position)
					tgt = a
			p.hp = p.max_hp
			p.mana = p.max_mana
			if tgt:
				var d: Vector3 = (tgt.global_position - p.global_position).normalized()
				p.attack(d)
				if k % 5 == 0:
					p.use_slot(k % 3, d)
			await get_tree().create_timer(0.15, true, false, true).timeout
		print("AFTER_FIGHT actors=", Game.actors.size(), " lvl=", p.data.level, " objective=", w.objective_text())
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots + "/mode_%s_era%d_b.png" % [mode, Profile.current_era])
		if mode != "world":
			p.die(null)
			await get_tree().create_timer(3.0, true, false, true).timeout
			print("DEATH_UI ", w.ui.top_name() if w.ui.has_method("top_name") else "?")
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots + "/mode_%s_end.png" % mode)
		print("MODES_DONE")
		get_tree().quit()
