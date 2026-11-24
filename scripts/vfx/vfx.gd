class_name VFX
## Static facade for visual effects; forwards to the world's VFXManager.

static func _m():
	if Game.world and is_instance_valid(Game.world) and Game.world.vfx:
		return Game.world.vfx
	return null

static func text(pos: Vector3, s: String, c: Color = Color.WHITE, scl: float = 1.0) -> void:
	var m = _m()
	if m:
		m.text(pos, s, c, scl)

static func burst(pos: Vector3, c: Color, count: int = 10, size: float = 0.3) -> void:
	var m = _m()
	if m:
		m.burst(pos, c, count, size)

static func ring(pos: Vector3, r: float, c: Color, dur: float = 0.5) -> void:
	var m = _m()
	if m:
		m.ring(pos, r, c, dur)

static func beam(a: Vector3, b: Vector3, c: Color, dur: float = 0.2, width: float = 0.08, jagged: bool = false) -> void:
	var m = _m()
	if m:
		m.beam(a, b, c, dur, width, jagged)

static func flash(pos: Vector3, c: Color, dur: float = 0.1, energy: float = 3.0) -> void:
	var m = _m()
	if m:
		m.flash(pos, c, dur, energy)

static func explosion(pos: Vector3, r: float, c: Color) -> void:
	var m = _m()
	if m:
		m.explosion(pos, r, c)

static func telegraph(pos: Vector3, r: float, dur: float, c: Color = Color(1, 0.2, 0.1), shape: String = "circle", dir: Vector3 = Vector3.FORWARD, arc: float = 360.0, length: float = 0.0) -> void:
	var m = _m()
	if m:
		m.telegraph(pos, r, dur, c, shape, dir, arc, length)

static func shake(amount: float = 0.3) -> void:
	if Game.world and Game.world.has_method("camera_shake"):
		Game.world.camera_shake(amount)

## Weapon/spell hit feedback at the point of impact (dir = attack direction).
static func hit_fx(pos: Vector3, dir: Vector3, dtype: String = "slash", heavy: bool = false, metal: bool = false) -> void:
	var m = _m()
	if m and m.has_method("hit_fx"):
		m.hit_fx(pos, dir, dtype, heavy, metal)
	elif m:
		m.burst(pos, Color(1.0, 0.9, 0.8), 6, 0.25)

## Weapon clash on a successful parry.
static func parry_fx(pos: Vector3, dir: Vector3) -> void:
	var m = _m()
	if m and m.has_method("parry_fx"):
		m.parry_fx(pos, dir)
	elif m:
		m.burst(pos, Color(1.0, 1.0, 0.7), 12, 0.4)

## Blocked hit on a shield/weapon.
static func block_fx(pos: Vector3, dir: Vector3) -> void:
	var m = _m()
	if m and m.has_method("block_fx"):
		m.block_fx(pos, dir)
	elif m:
		m.burst(pos, Color(1.0, 0.9, 0.6), 6, 0.3)

## Ground impact of heavy attacks (dust, cracks).
static func ground_impact(pos: Vector3, r: float = 2.0) -> void:
	var m = _m()
	if m and m.has_method("ground_impact"):
		m.ground_impact(pos, r)
	elif m:
		m.ring(pos, r, Color(0.8, 0.7, 0.55), 0.3)

## Temporary decal on the ground (scorch, frost, footprint, crack, blood...).
static func decal(pos: Vector3, kind: String, size: float = 1.5, life: float = 20.0, rot: float = 0.0) -> void:
	var m = _m()
	if m and m.has_method("decal"):
		m.decal(pos, kind, size, life, rot)
