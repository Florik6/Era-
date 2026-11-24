class_name WorldFX
## Environmental magic effects: freezing water into walkable ice and
## temporary ice walls.

## Creates temporary walkable ice over water cells within radius r (about 20 s).
static func freeze_water(parent: Node3D, gen, p: Vector3, r: float) -> int:
	if gen == null or parent == null:
		return 0
	var wl: float = gen.water_level
	var made := 0
	var step := 2.0
	var ice_m := MeshLib.mat(Color(0.75, 0.9, 1.0, 0.85), 0.2, 0.15, 0.25)
	var cells: Array = []
	var n := int(r / step)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var off := Vector2(ix * step, iz * step)
			if off.length() > r:
				continue
			var x := p.x + off.x
			var z := p.z + off.y
			if gen.is_water(x, z):
				cells.append(Vector3(x, wl, z))
	if cells.is_empty():
		return 0
	var root := Node3D.new()
	root.name = "IceFloe"
	parent.add_child(root)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	root.add_child(sb)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = MeshLib.box(Vector3(step + 0.05, 0.25, step + 0.05))
	mm.instance_count = cells.size()
	for i in cells.size():
		var c: Vector3 = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(i % 4) * 0.05), c + Vector3(0, 0.0, 0)))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(step, 0.3, step)
		cs.shape = bs
		cs.position = c
		sb.add_child(cs)
		made += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = ice_m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	VFX.burst(p + Vector3(0, 0.5, 0), Color(0.75, 0.92, 1.0), 16, 0.35)
	var tw := root.create_tween()
	tw.tween_interval(18.0)
	tw.tween_property(mmi, "transparency", 1.0, 2.0)
	tw.tween_callback(root.queue_free)
	return made

## Temporary ice wall perpendicular to `dir`; blocks movement and projectiles.
static func spawn_ice_wall(parent: Node3D, p: Vector3, dir: Vector3, life: float = 9.0) -> Node3D:
	if parent == null:
		return null
	var gh := p.y
	if Game.world and Game.world.has_method("ground_height"):
		gh = Game.world.ground_height(p)
	var wall := StaticBody3D.new()
	wall.name = "IceWall"
	wall.collision_layer = 1
	wall.collision_mask = 0
	parent.add_child(wall)
	wall.global_position = Vector3(p.x, gh, p.z)
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		d = Vector3(0, 0, -1)
	wall.look_at(wall.global_position + d.normalized(), Vector3.UP)
	var size := Vector3(6.0, 2.6, 0.8)
	var vis := Node3D.new()
	wall.add_child(vis)
	var ice := MeshLib.mat(Color(0.7, 0.9, 1.0, 0.8), 0.2, 0.1, 0.5)
	for i in 5:
		var x := -2.4 + i * 1.2
		var hh := 2.2 + float((i * 7) % 5) * 0.15
		MeshLib.part(vis, MeshLib.prism(Vector3(1.2, hh, 0.8)), ice, Vector3(x, hh * 0.5, 0), Vector3(0, 0, (i % 2) * 6.0 - 3.0))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y * 0.5
	wall.add_child(cs)
	vis.scale = Vector3(1, 0.05, 1)
	var tw := wall.create_tween()
	tw.tween_property(vis, "scale", Vector3.ONE, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.5, life - 1.0))
	tw.tween_property(vis, "scale", Vector3(1, 0.05, 1), 0.8)
	tw.tween_callback(wall.queue_free)
	Audio.play_sfx("ice_shatter", wall.global_position, -4.0)
	return wall
