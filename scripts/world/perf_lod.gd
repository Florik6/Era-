class_name PerfLOD
extends Node
## Level-of-detail manager for cities and big fights (no visual downgrade
## near the camera):
##  - static lights in streamed chunks fade out with distance, never shadowed;
##  - vegetation / props multimeshes get draw distances by their size
##    (small tufts close, trees far), scaled by Dynamic Combat Quality;
##  - small destructibles/chests stop drawing far away;
##  - ambient GPU particles (butterflies, leaves, smoke, sparks) only
##    simulate near the camera;
##  - actors get an LOD tier (0 near / 1 mid / 2 far) used by AI and
##    physics; rigs drop shadows and small gear with distance.
## Gameplay is never affected: collisions, hitboxes, damage and danger
## telegraphs stay as they are.

var world
var detail_k := 1.0        # draw distance multiplier (DCQ lowers it)
var ambient_r := 42.0      # ambient particles simulate within this radius
var light_fade := 30.0     # static lights fade from here
var rig_shadow_r := 22.0   # actors cast shadows within this camera distance
var rig_detail_r := 40.0   # small gear visible within this camera distance
var ambient_on := true
var _t := 0.0
var _done := {}            # chunk key -> {id, t, rescanned}
var _ambient: Array = []
var _detail_applied := 1.0

func setup(w) -> void:
	world = w
	if Settings.effective_quality != Settings.Quality.HIGH:
		# turbulence is the most expensive part of the ambient particles on phones
		for k in AmbientLife._mats:
			var pm = AmbientLife._mats[k].get("pm")
			if pm is ParticleProcessMaterial:
				pm.turbulence_enabled = false

func cam_pos() -> Vector3:
	var c = world.cam if world and world.get("cam") != null else null
	if c and is_instance_valid(c):
		return c.global_position
	return world.player.global_position if world and world.player else Vector3.ZERO

func _process(delta: float) -> void:
	if world == null or world.player == null or not is_instance_valid(world.player):
		return
	_t += delta / maxf(0.05, Engine.time_scale)
	if _t < 0.5:
		return
	_t = 0.0
	_scan_chunks()
	_ambient_lod()
	_actor_lod()

# ------------------------------------------------------------------ chunks
func _scan_chunks() -> void:
	if world.terrain == null or world.terrain.get("chunks") == null:
		return
	var now := Time.get_ticks_msec()
	var budget := 3
	var chunks: Dictionary = world.terrain.chunks
	for k in chunks:
		var node = chunks[k]
		if node == null or not is_instance_valid(node):
			continue
		var e: Dictionary = _done.get(k, {})
		var fresh: bool = e.is_empty() or int(e.id) != node.get_instance_id()
		var rescan: bool = not fresh and not e.get("rescanned", false) and now - int(e.t) > 4000
		if fresh or rescan:
			_apply(node)
			_done[k] = {"id": node.get_instance_id(), "t": now, "rescanned": rescan or not fresh}
			budget -= 1
			if budget <= 0:
				break
	if absf(_detail_applied - detail_k) > 0.01:
		_detail_applied = detail_k
		for k in chunks:
			if is_instance_valid(chunks[k]):
				_apply_ranges(chunks[k])

func _apply(n: Node) -> void:
	if n is Light3D:
		var l := n as Light3D
		if not (n is DirectionalLight3D):
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = light_fade
			l.distance_fade_length = 8.0
	elif n is MultiMeshInstance3D:
		_range_for(n as GeometryInstance3D, true)
	elif n is GPUParticles3D:
		if not _ambient.has(n):
			_ambient.append(n)
	elif n is MeshInstance3D and (n.get_parent() is Destructible or n.get_parent() is Chest or (n.get_parent() and (n.get_parent().get_parent() is Destructible or n.get_parent().get_parent() is Chest))):
		_range_for(n as GeometryInstance3D, false)
	for c in n.get_children():
		_apply(c)

func _range_for(g: GeometryInstance3D, multimesh: bool) -> void:
	if not g.has_meta("lod_base"):
		var base := g.visibility_range_end
		if base <= 0.0:
			base = 55.0
			if multimesh:
				var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
				var h := 2.0
				if mm and mm.mesh:
					h = mm.mesh.get_aabb().size.y
				base = 38.0 if h < 1.0 else (80.0 if h < 3.5 else 170.0)
		g.set_meta("lod_base", base)
	g.visibility_range_end = float(g.get_meta("lod_base")) * detail_k
	g.visibility_range_end_margin = 3.0

func _apply_ranges(n: Node) -> void:
	if n is GeometryInstance3D and n.has_meta("lod_base"):
		(n as GeometryInstance3D).visibility_range_end = float(n.get_meta("lod_base")) * detail_k
	for c in n.get_children():
		_apply_ranges(c)

# ------------------------------------------------------------------ ambient particles
func _ambient_lod() -> void:
	var cp := cam_pos()
	var r2 := ambient_r * ambient_r
	for i in range(_ambient.size() - 1, -1, -1):
		var p = _ambient[i]
		if not is_instance_valid(p):
			_ambient.remove_at(i)
			continue
		var want: bool = ambient_on and (p as Node3D).global_position.distance_squared_to(cp) < r2
		if (p as GPUParticles3D).emitting != want:
			(p as GPUParticles3D).emitting = want

func ambient_count() -> int:
	var n := 0
	for p in _ambient:
		if is_instance_valid(p) and p.emitting:
			n += 1
	return n

# ------------------------------------------------------------------ actors
func _actor_lod() -> void:
	var pl = world.player
	var pp: Vector3 = pl.global_position
	var cp := cam_pos()
	var shadows: bool = bool(Settings.profile().get("shadows", true))
	for a in Game.actors:
		if not is_instance_valid(a) or a.is_player:
			continue
		var d: float = a.global_position.distance_to(pp)
		var tier := 0
		if d > 65.0 and not a.aggro.has("player"):
			tier = 2
		elif d > 32.0 and not a.aggro.has("player"):
			tier = 1
		a.lod_tier = tier
		var r = a.rig
		if r == null or not is_instance_valid(r):
			continue
		var dc: float = a.global_position.distance_to(cp)
		var want_shadow: bool = shadows and dc < rig_shadow_r and a.kind != "boss" or (shadows and a.kind == "boss" and dc < rig_shadow_r * 2.0)
		var want_detail: bool = dc < rig_detail_r or a.kind == "boss"
		var state := (1 if want_shadow else 0) + (2 if want_detail else 0)
		if int(r.get_meta("lod_state", -1)) != state:
			r.set_meta("lod_state", state)
			_rig_apply(r, want_shadow, want_detail)

func _rig_apply(r: Node3D, shadow: bool, detail: bool) -> void:
	# far away the gear layer (trims, pouches, pauldrons…) is a few pixels:
	# drop it, keep body, armour colours and the weapon
	var extras = r.get("extras")
	if extras is Array:
		for e in extras:
			if is_instance_valid(e) and e is Node3D:
				e.visible = detail
	_shadow_walk(r, shadow)

func _shadow_walk(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		if not g.has_meta("cs0"):
			g.set_meta("cs0", g.cast_shadow)
		g.cast_shadow = int(g.get_meta("cs0")) if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_shadow_walk(c, on)
