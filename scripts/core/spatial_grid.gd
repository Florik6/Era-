class_name SpatialGrid
extends RefCounted
## Uniform hash grid for fast proximity queries (actors, pickups, interactables,
## destructibles). Objects store their current cell in metadata.

var cell := 16.0
var cells := {}     # category -> {Vector2i: Array}
var _pending: Array = []
var _flush_queued := false

func _init(cell_size: float = 16.0) -> void:
	cell = cell_size

func key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell), floori(p.z / cell))

func insert(obj: Object, p: Vector3, cat: String) -> void:
	var k := key(p)
	if not cells.has(cat):
		cells[cat] = {}
	var c: Dictionary = cells[cat]
	if not c.has(k):
		c[k] = []
	c[k].append(obj)
	obj.set_meta("_gk_" + cat, k)

## Registers a static node at its *final* position at the end of the frame.
## Nodes are usually added to the tree first and positioned afterwards, so
## inserting from _ready() would file them under the parent's origin and
## proximity queries (interaction, pickups) would never find them.
func insert_deferred(obj: Node3D, cat: String) -> void:
	_pending.append([obj, cat])
	if not _flush_queued:
		_flush_queued = true
		call_deferred("_flush_pending")

func _flush_pending() -> void:
	_flush_queued = false
	var batch := _pending
	_pending = []
	for e in batch:
		var o = e[0]
		if is_instance_valid(o) and o.is_inside_tree() and not o.is_queued_for_deletion():
			update(o, o.global_position, e[1])

func remove(obj: Object, cat: String) -> void:
	var mk := "_gk_" + cat
	if not obj.has_meta(mk):
		return
	var k: Vector2i = obj.get_meta(mk)
	var c: Dictionary = cells.get(cat, {})
	if c.has(k):
		c[k].erase(obj)
		if c[k].is_empty():
			c.erase(k)
	obj.remove_meta(mk)

func update(obj: Object, p: Vector3, cat: String) -> void:
	var mk := "_gk_" + cat
	var k := key(p)
	if obj.has_meta(mk) and obj.get_meta(mk) == k:
		return
	remove(obj, cat)
	insert(obj, p, cat)

func query(p: Vector3, r: float, cat: String) -> Array:
	var out: Array = []
	var c: Dictionary = cells.get(cat, {})
	if c.is_empty():
		return out
	var k0 := key(p - Vector3(r, 0, r))
	var k1 := key(p + Vector3(r, 0, r))
	var r2 := r * r
	for x in range(k0.x, k1.x + 1):
		for z in range(k0.y, k1.y + 1):
			var arr = c.get(Vector2i(x, z))
			if arr == null:
				continue
			for o in arr:
				if not is_instance_valid(o):
					continue
				var op: Vector3 = o.global_position
				var dx := op.x - p.x
				var dz := op.z - p.z
				if dx * dx + dz * dz <= r2:
					out.append(o)
	return out

func nearest(p: Vector3, r: float, cat: String, filter: Callable = Callable()) -> Object:
	var best: Object = null
	var bd := INF
	for o in query(p, r, cat):
		if filter.is_valid() and not filter.call(o):
			continue
		var d: float = (o.global_position - p).length_squared()
		if d < bd:
			bd = d
			best = o
	return best

func clear() -> void:
	cells.clear()
