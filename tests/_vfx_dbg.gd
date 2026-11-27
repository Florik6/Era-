extends Node3D
class FakeWorld:
	extends Node3D
	var vfx = null
	var fx_root: Node3D = null
	func ground_height(_p: Vector3) -> float:
		return 0.0
	func camera_shake(_a: float) -> void:
		pass
var w
func _ready() -> void:
	Settings.quality = Settings.Quality.HIGH
	Settings.effective_quality = Settings.Quality.HIGH
	w = FakeWorld.new()
	add_child(w)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.4, 0.5, 0.6)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	w.add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	g.mesh = pm
	g.material_override = MeshLib.mat(Color(0.75, 0.68, 0.55))
	w.add_child(g)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(0, 9, 8)
	cam.look_at(Vector3(0, 0, 0))
	cam.current = true
	w.fx_root = Node3D.new()
	w.add_child(w.fx_root)
	var vm = load("res://scripts/vfx/vfx_manager.gd").new()
	w.add_child(vm)
	w.vfx = vm
	Game.world = w
	_run()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var vm = w.vfx
	TimeFX.inst.set_base(0.05)
	vm.decal(Vector3(-4, 0, 0), "frost", 3.0, 30.0, 0.0)
	vm.decal(Vector3(-4, 0, 3), "scorch", 3.0, 30.0, 0.0)
	vm.decal(Vector3(4, 0, 3), "crack", 3.0, 30.0, 0.0)
	vm.glow(Vector3(0, 1, 0), Color(1, 0.6, 0.2), 1.5, 5.0)
	vm.shock(Vector3(3, 0, -2), 2.0, Color(0.5, 0.9, 1.0), 5.0)
	vm.emit(Vector3(-2, 1, -2), {"n": 10, "life": 5.0, "mat": "mix", "col": Color(0.7, 0.6, 0.5, 0.8), "ramp": "smoke", "size": 1.0, "v0": 0.2, "v1": 0.5, "grav": Vector3.ZERO, "critical": true})
	vm.emit(Vector3(2, 1, 0), {"n": 20, "life": 5.0, "mat": "streak", "col": Color(1, 0.8, 0.4), "size": 0.4, "v0": 0.5, "v1": 1.0, "grav": Vector3.ZERO, "critical": true})
	MagicFX.ground_rune(Vector3(0, 0, 3), "sigil", Color(0.7, 0.3, 1.0), 1.5, 30.0)
	MagicFX.ground_rune(Vector3(-3, 0, -4), "clock", Color(0.4, 1.0, 0.85), 1.5, 30.0)
	MagicFX.ground_rune(Vector3(4, 0, -4), "frost", Color(0.6, 0.9, 1.0), 1.5, 30.0)
	vm.telegraph(Vector3(0, 0, -5), 2.5, 20.0, Color(1, 0.2, 0.1), "cone", Vector3(0, 0, 1), 90.0, 0.0)
	await get_tree().create_timer(0.6, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/-home-user-Era-/4dd8d359-84a1-5cb8-8e5d-83e3c1e26fc1/scratchpad/dbg/a.png")
	get_tree().quit()
