class_name OrbSystem
extends MultiMeshInstance3D
## Slither-style experience orbs: thousands-capable pool rendered with one
## MultiMesh and a bobbing emissive shader. Ambient orbs are seeded around the
## player; defeated actors burst into orbs. Player and NPCs collect them
## (with a magnet radius that grows with level).

const MAX := 900
const CELL := 12.0

var pos := PackedVector3Array()
var val := PackedInt32Array()
var alive := PackedByteArray()
var free_list: Array = []
var buckets := {}           # Vector2i -> Array[int]
var count := 0
var _t := 0.0
var _seed_t := 0.0
var ambient_target := 70
var ambient_radius := 45.0
var _dirty := false

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float time_offset = 0.0;
varying vec3 col;
void vertex() {
	float ph = float(INSTANCE_ID) * 1.7;
	VERTEX.y += sin(TIME * 3.0 + ph) * 0.12;
	float s = 1.0 + 0.15 * sin(TIME * 5.0 + ph);
	VERTEX.xz *= s;
	col = INSTANCE_CUSTOM.rgb;
}
void fragment() {
	ALBEDO = col * 1.6;
	EMISSION = col * 2.2;
}
"""

func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = MAX
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	sm.radial_segments = 6
	sm.rings = 3
	mm.mesh = sm
	multimesh = mm
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pos.resize(MAX)
	val.resize(MAX)
	alive.resize(MAX)
	for i in MAX:
		alive[i] = 0
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
		free_list.append(MAX - 1 - i)
	custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 400, 10000))

func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

func spawn(p: Vector3, value: int) -> int:
	if free_list.is_empty():
		return -1
	var i: int = free_list.pop_back()
	if Game.world and Game.world.has_method("ground_height"):
		p.y = Game.world.ground_height(p) + 0.45
	pos[i] = p
	val[i] = value
	alive[i] = 1
	count += 1
	var k := _key(p)
	if not buckets.has(k):
		buckets[k] = []
	buckets[k].append(i)
	var s := 0.8 + clampf(value / 20.0, 0.0, 1.6)
	multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), p))
	var c := Color(0.35, 0.65, 1.0)
	if value >= 25:
		c = Color(1.0, 0.8, 0.25)
	elif value >= 8:
		c = Color(0.8, 0.4, 1.0)
	elif value >= 4:
		c = Color(0.3, 1.0, 0.6)
	multimesh.set_instance_custom_data(i, c)
	return i

func _remove(i: int) -> void:
	if alive[i] == 0:
		return
	alive[i] = 0
	count -= 1
	var k := _key(pos[i])
	if buckets.has(k):
		buckets[k].erase(i)
		if buckets[k].is_empty():
			buckets.erase(k)
	multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
	free_list.append(i)

## Scatter a total amount of XP as several orbs (death bursts).
func burst(center: Vector3, total: int, n: int = -1) -> void:
	if total <= 0:
		return
	if n < 0:
		n = clampi(total / 6, 3, 18)
	var each := maxi(1, total / n)
	for k in n:
		var a := randf() * TAU
		var r := randf_range(0.5, 3.5)
		spawn(center + Vector3(cos(a) * r, 0, sin(a) * r), each)

func count_near(p: Vector3, r: float) -> int:
	var c := 0
	for i in _indices_near(p, r):
		c += 1
	return c

func nearest_orb(p: Vector3, r: float) -> Vector3:
	var best := Vector3.INF
	var bd := r * r
	for i in _indices_near(p, r):
		var d := pos[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = pos[i]
	return best

func _indices_near(p: Vector3, r: float) -> Array:
	var out: Array = []
	var k0 := _key(p - Vector3(r, 0, r))
	var k1 := _key(p + Vector3(r, 0, r))
	var r2 := r * r
	for x in range(k0.x, k1.x + 1):
		for z in range(k0.y, k1.y + 1):
			var arr = buckets.get(Vector2i(x, z))
			if arr == null:
				continue
			for i in arr:
				var dx: float = pos[i].x - p.x
				var dz: float = pos[i].z - p.z
				if dx * dx + dz * dz <= r2:
					out.append(i)
	return out

func clear_all() -> void:
	for i in MAX:
		if alive[i] == 1:
			_remove(i)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 0.1:
		return
	var dt := _t
	_t = 0.0
	var pl = Game.player
	# collection for player and nearby humanoid actors
	var collectors: Array = []
	if pl and is_instance_valid(pl) and not pl.is_dead:
		collectors.append(pl)
		for a in Game.actors_near(pl.global_position, 70.0):
			if a != pl and not a.is_dead and a.data != null and a.get("role") in ["bot", "enemy", "hunter"]:
				collectors.append(a)
	for a in collectors:
		var magnet: float = 1.4 + minf(3.0, a.data.level * 0.08)
		if a.is_player:
			magnet += 1.0
		var got := 0
		for i in _indices_near(a.global_position, magnet + 1.5):
			var to: Vector3 = a.global_position + Vector3(0, 0.6, 0) - pos[i]
			var d := to.length()
			if d < 0.9:
				got += val[i]
				_remove(i)
			elif d < magnet + 1.5:
				var np: Vector3 = pos[i] + to.normalized() * minf(d, dt * 14.0)
				var ok := _key(pos[i])
				var nk := _key(np)
				if ok != nk:
					buckets[ok].erase(i)
					if buckets[ok].is_empty():
						buckets.erase(ok)
					if not buckets.has(nk):
						buckets[nk] = []
					buckets[nk].append(i)
				pos[i] = np
				var s := 0.8 + clampf(val[i] / 20.0, 0.0, 1.6)
				multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), np))
		if got > 0:
			a.gain_xp(got)
			if a.is_player:
				Events.xp_gained.emit(a, got)
				Audio.play_sfx("xp", a.global_position, -12.0, 0.2)
	# ambient seeding around the player (slither.io feeling)
	_seed_t += dt
	if pl and is_instance_valid(pl) and _seed_t > 0.5 and Game.mode != "trials":
		_seed_t = 0.0
		var near := count_near(pl.global_position, ambient_radius)
		var need := ambient_target - near
		for k in mini(need, 8):
			var a2 := randf() * TAU
			var r2 := randf_range(12.0, ambient_radius)
			var sp: Vector3 = pl.global_position + Vector3(cos(a2) * r2, 0, sin(a2) * r2)
			if Game.world and Game.world.has_method("is_water") and Game.world.is_water(sp):
				continue
			spawn(sp, 1 + (randi() % 3) + (5 if randf() < 0.05 else 0))
		# recycle far orbs
		if count > MAX - 80:
			for i in MAX:
				if alive[i] == 1 and pos[i].distance_squared_to(pl.global_position) > 160.0 * 160.0:
					_remove(i)
