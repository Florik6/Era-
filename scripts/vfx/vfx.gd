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
