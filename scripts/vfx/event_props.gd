class_name EventProps
## Temporary dressing for world events, built from simple meshes in the
## era's materials (created only when an event starts, freed when it ends):
## stalls, banners, lantern strings, crates, carts, a train wagon, a
## tournament ring, a stage, notice signs; interactable markers; and
## spectacles (fireworks, airship, holograms, bloom, sparks, rebuild).

static func _era_cols(era: int) -> Dictionary:
	match era:
		0: return {"wood": Color(0.45, 0.3, 0.17), "cloth": Color(0.7, 0.2, 0.18), "metal": Color(0.45, 0.45, 0.48), "accent": Color(0.95, 0.75, 0.3)}
		1: return {"wood": Color(0.5, 0.33, 0.2), "cloth": Color(0.2, 0.35, 0.75), "metal": Color(0.7, 0.6, 0.35), "accent": Color(1.0, 0.85, 0.4)}
		2: return {"wood": Color(0.35, 0.27, 0.2), "cloth": Color(0.45, 0.2, 0.15), "metal": Color(0.3, 0.3, 0.33), "accent": Color(0.85, 0.55, 0.25)}
		3: return {"wood": Color(0.55, 0.56, 0.6), "cloth": Color(0.15, 0.5, 0.75), "metal": Color(0.6, 0.62, 0.66), "accent": Color(1.0, 0.85, 0.2)}
	return {"wood": Color(0.3, 0.32, 0.4), "cloth": Color(0.2, 0.6, 0.85), "metal": Color(0.5, 0.55, 0.65), "accent": Color(0.3, 0.95, 1.0)}

static func build(kind: String, era: int) -> Node3D:
	var root := Node3D.new()
	root.name = "EvProp_" + kind
	var c := _era_cols(era)
	var wood := MeshLib.mat(c.wood)
	var cloth := MeshLib.mat(c.cloth)
	var metal := MeshLib.mat(c.metal, 0.6, 0.4)
	var acc := MeshLib.mat(c.accent, 0.3, 0.5, 0.6 if era >= 3 else 0.0)
	match kind:
		"stall":
			MeshLib.part(root, MeshLib.box(Vector3(2.4, 0.9, 1.0)), wood, Vector3(0, 0.45, 0))
			for x in [-1.1, 1.1]:
				for z in [-0.45, 0.45]:
					MeshLib.part(root, MeshLib.cyl(0.05, 0.05, 2.2, 6), wood, Vector3(x, 1.1, z))
			MeshLib.part(root, MeshLib.box(Vector3(2.7, 0.08, 1.4)), cloth, Vector3(0, 2.25, 0), Vector3(-8, 0, 0))
			for i in 4:
				MeshLib.part(root, MeshLib.box(Vector3(0.3, 0.25, 0.3)), acc if i % 2 == 0 else metal, Vector3(-0.9 + i * 0.6, 1.02, 0))
		"banner":
			MeshLib.part(root, MeshLib.cyl(0.06, 0.07, 4.2, 6), wood, Vector3(0, 2.1, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.9, 1.6, 0.04)), cloth, Vector3(0.48, 3.2, 0))
			MeshLib.part(root, MeshLib.sphere(0.12, 8, 5), acc, Vector3(0, 4.3, 0))
		"lanterns":
			for i in 6:
				var x := -3.0 + i * 1.2
				MeshLib.part(root, MeshLib.sphere(0.16, 8, 5), MeshLib.glow(c.accent if era < 4 else Color(0.4, 0.9, 1.0), 2.0), Vector3(x, 2.6 - absf(sin(i * 0.9)) * 0.25, 0), Vector3.ZERO, Vector3.ONE, false)
			for x in [-3.4, 3.4]:
				MeshLib.part(root, MeshLib.cyl(0.05, 0.05, 2.8, 6), wood, Vector3(x, 1.4, 0))
		"crates":
			for i in 3:
				MeshLib.part(root, MeshLib.box(Vector3(0.8, 0.7, 0.8)), wood, Vector3(i * 0.6 - 0.6, 0.35 + (0.7 if i == 1 else 0.0), (i % 2) * 0.5))
		"cart", "wagon":
			var l := 2.6 if kind == "cart" else 6.0
			MeshLib.part(root, MeshLib.box(Vector3(1.6, 0.7, l)), wood if kind == "cart" else metal, Vector3(0, 0.9, 0))
			for z in [-l * 0.35, l * 0.35]:
				for x in [-0.85, 0.85]:
					MeshLib.part(root, MeshLib.cyl(0.45, 0.45, 0.12, 12), metal, Vector3(x, 0.45, z), Vector3(0, 0, 90))
			if kind == "wagon":
				MeshLib.part(root, MeshLib.box(Vector3(1.7, 1.6, l)), cloth, Vector3(0, 2.0, 0))
				for i in 4:
					MeshLib.part(root, MeshLib.box(Vector3(0.02, 0.5, 0.8)), MeshLib.glow(Color(1.0, 0.9, 0.6), 1.2), Vector3(0.86, 2.1, -2.0 + i * 1.3))
			else:
				MeshLib.part(root, MeshLib.box(Vector3(0.6, 0.5, 0.6)), cloth, Vector3(0, 1.5, 0.3))
		"ring":
			var ring := MeshLib.part(root, MeshLib.torus(5.8, 6.0), wood, Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.2, 1), false)
			ring.name = "Ring"
			for i in 8:
				var a := TAU * i / 8.0
				MeshLib.part(root, MeshLib.cyl(0.08, 0.08, 1.1, 6), wood, Vector3(cos(a) * 5.9, 0.55, sin(a) * 5.9))
		"stage":
			MeshLib.part(root, MeshLib.box(Vector3(4.0, 0.5, 2.6)), wood, Vector3(0, 0.25, 0))
			MeshLib.part(root, MeshLib.box(Vector3(4.2, 2.6, 0.1)), cloth, Vector3(0, 1.8, -1.3))
		"sign":
			MeshLib.part(root, MeshLib.cyl(0.05, 0.05, 1.6, 6), wood, Vector3(0, 0.8, 0))
			MeshLib.part(root, MeshLib.box(Vector3(0.9, 0.6, 0.05)), acc, Vector3(0, 1.5, 0))
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 70.0
	return root

## Marker mesh of an interactable event object.
static func object_mesh(kind: String) -> Node3D:
	var n := Node3D.new()
	match kind:
		"monolith":
			MeshLib.part(n, MeshLib.box(Vector3(0.9, 2.6, 0.5)), MeshLib.mat(Color(0.35, 0.33, 0.4)), Vector3(0, 1.3, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.5, 0.5, 0.06)), MeshLib.glow(Color(0.6, 0.5, 1.0), 2.5), Vector3(0, 1.7, 0.27), Vector3.ZERO, Vector3.ONE, false)
		"valve", "generator":
			MeshLib.part(n, MeshLib.box(Vector3(0.7, 1.0, 0.5)), MeshLib.mat(Color(0.35, 0.35, 0.38), 0.6, 0.4), Vector3(0, 0.5, 0))
			MeshLib.part(n, MeshLib.torus(0.18, 0.24), MeshLib.mat(Color(0.8, 0.2, 0.15), 0.4, 0.4), Vector3(0, 1.1, 0.26), Vector3(90, 0, 0))
		"dog", "pet":
			MeshLib.part(n, MeshLib.box(Vector3(0.35, 0.35, 0.75)), MeshLib.mat(Color(0.55, 0.4, 0.25) if kind == "dog" else Color(0.6, 0.65, 0.75), 0.3 if kind == "pet" else 0.0), Vector3(0, 0.4, 0))
			MeshLib.part(n, MeshLib.box(Vector3(0.28, 0.28, 0.3)), MeshLib.mat(Color(0.5, 0.36, 0.22) if kind == "dog" else Color(0.7, 0.75, 0.85)), Vector3(0, 0.62, -0.45))
		"person":
			MeshLib.part(n, MeshLib.cyl(0.22, 0.25, 1.1, 8), MeshLib.mat(Color(0.5, 0.4, 0.3)), Vector3(0, 0.55, 0))
			MeshLib.part(n, MeshLib.sphere(0.18, 8, 6), MeshLib.mat(Color(0.85, 0.7, 0.55)), Vector3(0, 1.25, 0))
		"boat":
			MeshLib.part(n, MeshLib.box(Vector3(1.2, 0.5, 3.0)), MeshLib.mat(Color(0.45, 0.3, 0.18)), Vector3(0, 0.25, 0))
		"machine":
			MeshLib.part(n, MeshLib.box(Vector3(0.6, 0.9, 0.5)), MeshLib.mat(Color(0.5, 0.45, 0.35), 0.7, 0.4), Vector3(0, 0.6, 0))
			MeshLib.part(n, MeshLib.sphere(0.12, 8, 5), MeshLib.glow(Color(1.0, 0.4, 0.2), 2.0), Vector3(0, 0.9, -0.26))
		_:
			MeshLib.part(n, MeshLib.box(Vector3(0.35, 0.25, 0.35)), MeshLib.glow(Color(1.0, 0.85, 0.4), 1.4), Vector3(0, 0.15, 0))
	return n

## Spectacle: a self-animating node (freed with its event).
static func spectacle(fx: String, era: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Spectacle_" + fx
	var mg = MagicFX.mgr()
	match fx:
		"fireworks":
			var t := Timer.new()
			t.wait_time = 1.4
			t.autostart = true
			root.add_child(t)
			t.timeout.connect(func():
				if mg == null or not is_instance_valid(root):
					return
				var p: Vector3 = root.global_position + Vector3(randf_range(-10, 10), randf_range(16, 24), randf_range(-10, 10))
				var col := Color.from_hsv(randf(), 0.7, 1.0)
				mg.emit(p, {"n": 36, "life": 1.4, "mat": "add", "col": col, "size": 0.25, "v0": 5.0, "v1": 9.0, "grav": Vector3(0, -3.0, 0), "damp": 1.0, "curve": "shrink", "critical": true})
				mg.light(p, col, 2.0 * Settings.flash_k(), 30.0, 0.5)
				Audio.play_sfx("explosion", p, -18.0))
		"airship":
			var ship := Node3D.new()
			root.add_child(ship)
			MeshLib.part(ship, MeshLib.sphere(1.0, 16, 10), MeshLib.mat(Color(0.75, 0.7, 0.6)), Vector3.ZERO, Vector3.ZERO, Vector3(3.0, 2.2, 9.0), false)
			MeshLib.part(ship, MeshLib.box(Vector3(1.4, 0.9, 3.2)), MeshLib.mat(Color(0.4, 0.3, 0.2)), Vector3(0, -2.6, 0), Vector3.ZERO, Vector3.ONE, false)
			ship.position = Vector3(-90, 30, 0)
			ship.create_tween().tween_property(ship, "position", Vector3(90, 32, 10), 150.0)
		"holo":
			for i in 6:
				var h := MeshInstance3D.new()
				h.mesh = MeshLib.box(Vector3(1.2, 1.2, 1.2)) if i % 2 == 0 else MeshLib.sphere(0.8, 12, 8)
				h.material_override = MagicFX.smat("fresnel", {"col": Color.from_hsv(0.5 + i * 0.07, 0.6, 1.0, 0.5), "power": 1.5, "bands": 3.0})
				h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(h)
				var a := TAU * i / 6.0
				h.position = Vector3(cos(a) * 6.0, 3.0 + i * 0.3, sin(a) * 6.0)
				h.create_tween().set_loops().tween_property(h, "rotation:y", TAU, 4.0 + i).as_relative()
		"bloom":
			if mg:
				var e: CPUParticles3D = mg.make_emitter({"n": 30, "life": 4.0, "mat": "add", "col": Color(1.0, 0.6, 0.8, 0.8), "size": 0.14, "shape": "box", "box": Vector3(8, 0.5, 8), "v0": 0.2, "v1": 0.6, "dir": Vector3.UP, "spread": 40.0, "grav": Vector3(0, -0.2, 0), "ramp": "pop", "local": true, "expl": 0.0})
				if e:
					root.add_child(e)
					e.position.y = 3.0
					e.emitting = true
		"sparks", "rebuild":
			var dev := Node3D.new()
			root.add_child(dev)
			MeshLib.part(dev, MeshLib.cyl(0.4, 0.6, 1.4, 10), MeshLib.mat(Color(0.5, 0.45, 0.35), 0.7, 0.35), Vector3(0, 0.7, 0))
			MeshLib.part(dev, MeshLib.torus(0.5, 0.62), MeshLib.glow(Color(0.4, 0.8, 1.0), 2.0), Vector3(0, 1.6, 0), Vector3.ZERO, Vector3.ONE, false)
			if fx == "rebuild":
				dev.scale = Vector3(1, 0.2, 1)
				dev.create_tween().set_loops().tween_property(dev, "scale", Vector3(1.6, 2.5, 1.6), 6.0).set_trans(Tween.TRANS_SINE)
			var t2 := Timer.new()
			t2.wait_time = 0.9
			t2.autostart = true
			root.add_child(t2)
			t2.timeout.connect(func():
				if mg != null and is_instance_valid(root):
					mg.emit(root.global_position + Vector3(0, 1.7, 0), {"n": 10, "life": 0.5, "mat": "streak", "col": Color(0.6, 0.85, 1.0), "size": 0.2, "v0": 3.0, "v1": 6.0, "grav": Vector3(0, -6, 0), "curve": "shrink"}))
	return root
