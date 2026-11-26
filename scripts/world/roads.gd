class_name RoadNet
extends RefCounted
## Road network of one world: "main" roads between settlements and "trail"
## paths to points of interest, with bridges over water, crossroads, a spatial
## index for fast thread-safe distance queries and A* routing along the graph.
## The layout is planned once by `Planner` (deterministic for a seed + era);
## after `finalize()` all data is read-only and safe to query from worker
## threads (chunk streaming).

const MAIN := 0
const TRAIL := 1
const HW_MAIN := 3.0
const HW_TRAIL := 1.35
const FLAG_ROAD := 0
const FLAG_BRIDGE := 1
const FLAG_HIDDEN := 2            # link from a plaza edge to the settlement centre (graph only)
const RAIL_OFFSET := 5.4            # railway centre line distance from the road centre
const FINE := 16.0
const FINE_MARGIN := 11.0
const COARSE := 64.0
const COARSE_MARGIN := 44.0

# polylines (construction data, kept for rendering)
var lines: Array = []             # Array[PackedVector2Array]
var line_flags: Array = []        # Array[PackedByteArray] flag of segment i -> i+1
var line_type := PackedByteArray()
var line_rail := PackedByteArray()
var protected := {}               # Vector2i -> true (junction points that must survive edits)
var labels := {}                  # Vector2i -> {name, kind, id, type}

# segments
var sa := PackedVector2Array()
var sb := PackedVector2Array()
var s_type := PackedByteArray()
var s_hw := PackedFloat32Array()
var s_flag := PackedByteArray()
var s_line := PackedInt32Array()
var s_s0 := PackedFloat32Array()  # arclength of the segment start along its polyline
var s_ext := PackedFloat32Array() # extra flattened margin (railway beside the road)
var s_na := PackedInt32Array()
var s_nb := PackedInt32Array()
var s_prev := PackedInt32Array()  # previous connected segment of the same polyline or -1
var s_next := PackedInt32Array()
var fine := {}                    # Vector2i -> Array[int]
var coarse := {}                  # Vector2i -> Array[int] (coarse cell == chunk key)

# graph
var node_pos := PackedVector2Array()
var node_adj: Array = []          # Array[Array[int]] neighbour nodes
var node_eseg: Array = []         # Array[Array[int]] segment index per neighbour
var node_label: Array = []        # per node: label Dictionary or {}
var crossroads: Array = []        # Vector2
var cross_nodes := PackedInt32Array()

static func key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 2.0), roundi(p.y * 2.0))

func clear() -> void:
	lines.clear()
	line_flags.clear()
	line_type = PackedByteArray()
	line_rail = PackedByteArray()
	protected.clear()
	labels.clear()
	_clear_final()

func _clear_final() -> void:
	sa = PackedVector2Array()
	sb = PackedVector2Array()
	s_type = PackedByteArray()
	s_hw = PackedFloat32Array()
	s_flag = PackedByteArray()
	s_line = PackedInt32Array()
	s_s0 = PackedFloat32Array()
	s_ext = PackedFloat32Array()
	s_na = PackedInt32Array()
	s_nb = PackedInt32Array()
	s_prev = PackedInt32Array()
	s_next = PackedInt32Array()
	fine.clear()
	coarse.clear()
	node_pos = PackedVector2Array()
	node_adj.clear()
	node_eseg.clear()
	node_label.clear()
	crossroads.clear()
	cross_nodes = PackedInt32Array()

func add_line(pts: PackedVector2Array, typ: int) -> int:
	lines.append(pts)
	var fl := PackedByteArray()
	fl.resize(maxi(0, pts.size() - 1))
	line_flags.append(fl)
	line_type.append(typ)
	line_rail.append(0)
	return lines.size() - 1

func hw_of(typ: int) -> float:
	return HW_MAIN if typ == MAIN else HW_TRAIL

# ---------------------------------------------------------------- finalize
## Builds segments, the graph, crossroads and spatial indexes from the polylines.
func finalize(settlements: Array) -> void:
	_clear_final()
	var node_of := {}
	for s in settlements:
		labels[key(s.pos)] = {"name": s.name, "kind": "settlement", "id": s.id, "type": s.type}
	for li in lines.size():
		var pts: PackedVector2Array = lines[li]
		var fl: PackedByteArray = line_flags[li]
		if pts.size() < 2:
			continue
		var hw := hw_of(line_type[li])
		var acc := 0.0
		var prev_seg := -1
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ln := a.distance_to(b)
			if ln < 0.05:
				continue
			var na := _node(node_of, a)
			var nb := _node(node_of, b)
			var si := sa.size()
			sa.append(a)
			sb.append(b)
			s_type.append(line_type[li])
			s_hw.append(hw)
			s_flag.append(fl[i] if i < fl.size() else 0)
			s_line.append(li)
			s_s0.append(acc)
			s_ext.append(RAIL_OFFSET + 1.4 - hw if line_rail[li] == 1 else 0.0)
			s_na.append(na)
			s_nb.append(nb)
			s_prev.append(prev_seg)
			s_next.append(-1)
			if prev_seg >= 0:
				s_next[prev_seg] = si
			prev_seg = si
			node_adj[na].append(nb)
			node_eseg[na].append(si)
			node_adj[nb].append(na)
			node_eseg[nb].append(si)
			acc += ln
	# spatial indexes
	for si in sa.size():
		_index(fine, si, FINE, FINE_MARGIN)
		_index(coarse, si, COARSE, COARSE_MARGIN)
	# crossroads: junctions of 3+ visible roads outside settlements
	for n in node_pos.size():
		var deg := 0
		for e in node_eseg[n]:
			if s_flag[e] != FLAG_HIDDEN:
				deg += 1
		if deg < 3:
			continue
		var p := node_pos[n]
		var inside := false
		for s in settlements:
			if p.distance_to(s.pos) < float(s.radius) * 1.3:
				inside = true
				break
		if inside:
			continue
		var dup := false
		for c in crossroads:
			if p.distance_to(c) < 14.0:
				dup = true
				break
		if not dup:
			crossroads.append(p)
			cross_nodes.append(n)

func _node(node_of: Dictionary, p: Vector2) -> int:
	var k := key(p)
	var n = node_of.get(k)
	if n != null:
		return n
	var id := node_pos.size()
	node_of[k] = id
	node_pos.append(p)
	node_adj.append([])
	node_eseg.append([])
	node_label.append(labels.get(k, {}))
	return id

func _index(grid: Dictionary, si: int, cell: float, margin: float) -> void:
	var a := sa[si]
	var b := sb[si]
	var x0 := floori((minf(a.x, b.x) - margin) / cell)
	var x1 := floori((maxf(a.x, b.x) + margin) / cell)
	var z0 := floori((minf(a.y, b.y) - margin) / cell)
	var z1 := floori((maxf(a.y, b.y) + margin) / cell)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			# skip cells farther than the margin from the segment
			var cc := Vector2((cx + 0.5) * cell, (cz + 0.5) * cell)
			var cp := Geometry2D.get_closest_point_to_segment(cc, a, b)
			if cp.distance_to(cc) > margin + cell * 0.7072:
				continue
			var k := Vector2i(cx, cz)
			if not grid.has(k):
				grid[k] = []
			grid[k].append(si)

# ---------------------------------------------------------------- queries (thread-safe)
## Nearest segment within ~9 m: Vector2(distance, segment index) or (999, -1).
func near(x: float, z: float) -> Vector2:
	var arr = fine.get(Vector2i(floori(x / FINE), floori(z / FINE)))
	if arr == null:
		return Vector2(999.0, -1.0)
	var p := Vector2(x, z)
	var best := 999.0
	var bi := -1
	for i in arr:
		var d := Geometry2D.get_closest_point_to_segment(p, sa[i], sb[i]).distance_to(p)
		if d < best:
			best = d
			bi = i
	return Vector2(best, bi)

## Distance to the closest road (exact up to ~44 m, otherwise 999).
func dist(x: float, z: float) -> float:
	var arr = coarse.get(Vector2i(floori(x / COARSE), floori(z / COARSE)))
	if arr == null:
		return 999.0
	var p := Vector2(x, z)
	var best := 999.0
	for i in arr:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, sa[i], sb[i]).distance_to(p))
	return best

## Distance from the road edge (negative = on the road surface); 999 when far.
func edge(x: float, z: float) -> float:
	var r := near(x, z)
	if r.y < 0.0:
		return 999.0
	return r.x - s_hw[int(r.y)]

func nearest_point(p: Vector2) -> Vector2:
	var arr = coarse.get(Vector2i(floori(p.x / COARSE), floori(p.y / COARSE)))
	var best := 1e12
	var bp := p
	var cand: Array = arr if arr != null else []
	if cand.is_empty():
		cand = range(sa.size())
	for i in cand:
		if s_flag[i] == FLAG_HIDDEN:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(p, sa[i], sb[i])
		var d := cp.distance_squared_to(p)
		if d < best:
			best = d
			bp = cp
	if best > 1e11 and arr != null:
		return nearest_point_global(p)
	return bp

func nearest_point_global(p: Vector2) -> Vector2:
	var best := 1e12
	var bp := p
	for i in sa.size():
		if s_flag[i] == FLAG_HIDDEN:
			continue
		var cp := Geometry2D.get_closest_point_to_segment(p, sa[i], sb[i])
		var d := cp.distance_squared_to(p)
		if d < best:
			best = d
			bp = cp
	return bp

func nearest_segment(p: Vector2) -> int:
	var arr = coarse.get(Vector2i(floori(p.x / COARSE), floori(p.y / COARSE)))
	var cand: Array = arr if arr != null else []
	if cand.is_empty():
		cand = range(sa.size())
	var best := 1e12
	var bi := -1
	for i in cand:
		var d := Geometry2D.get_closest_point_to_segment(p, sa[i], sb[i]).distance_squared_to(p)
		if d < best:
			best = d
			bi = i
	return bi

func type_at(p: Vector2) -> String:
	var r := near(p.x, p.y)
	if r.y < 0.0:
		return ""
	var si := int(r.y)
	if r.x > s_hw[si] + 0.4:
		return ""
	return "main" if s_type[si] == MAIN else "trail"

## Waypoints from `from` to `to` following the road graph (A*).
## [from, entry point on the road, ...graph nodes..., exit point, to].
func path(from: Vector2, to: Vector2) -> Array:
	var out: Array = [from]
	if sa.is_empty():
		out.append(to)
		return out
	var s0 := nearest_segment(from)
	var s1 := nearest_segment(to)
	var e0 := Geometry2D.get_closest_point_to_segment(from, sa[s0], sb[s0])
	var e1 := Geometry2D.get_closest_point_to_segment(to, sa[s1], sb[s1])
	out.append(e0)
	if s0 == s1:
		out.append(e1)
		out.append(to)
		return out
	# start: both ends of s0 with their partial costs; goal: both ends of s1
	var n := node_pos.size()
	var g := PackedFloat32Array()
	g.resize(n)
	g.fill(1e20)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	var heap := Heap.new()
	for nd in [s_na[s0], s_nb[s0]]:
		var c0 := e0.distance_to(node_pos[nd])
		if c0 < g[nd]:
			g[nd] = c0
			heap.push(c0 + node_pos[nd].distance_to(e1), nd)
	var goal_a := s_na[s1]
	var goal_b := s_nb[s1]
	var found := -1
	while heap.size() > 0:
		var c := heap.pop()
		if closed[c] == 1:
			continue
		closed[c] = 1
		if c == goal_a or c == goal_b:
			found = c
			break
		var adj: Array = node_adj[c]
		for j in adj.size():
			var nb: int = adj[j]
			if closed[nb] == 1:
				continue
			var nd2 := g[c] + node_pos[c].distance_to(node_pos[nb])
			if nd2 < g[nb]:
				g[nb] = nd2
				prev[nb] = c
				heap.push(nd2 + node_pos[nb].distance_to(e1), nb)
	if found < 0:
		out.append(to)
		return out
	var chain: Array = []
	var cur := found
	while cur != -1:
		chain.append(node_pos[cur])
		cur = prev[cur]
	chain.reverse()
	# drop nearly collinear intermediate points
	var simp: Array = []
	for i in chain.size():
		if i == 0 or i == chain.size() - 1 or simp.is_empty():
			simp.append(chain[i])
			continue
		var a: Vector2 = simp[-1]
		var b: Vector2 = chain[i]
		var c2: Vector2 = chain[i + 1]
		var d1 := (b - a)
		var d2 := (c2 - b)
		if d1.length() > 0.01 and d2.length() > 0.01 and d1.normalized().dot(d2.normalized()) > 0.9975 and a.distance_to(b) < 40.0:
			continue
		simp.append(b)
	out.append_array(simp)
	out.append(e1)
	out.append(to)
	return out

## Destinations reachable from crossroads node `n`: one per branch,
## [{dir: Vector2, name: String, dist: float, kind: String}].
func branches(n: int) -> Array:
	var out: Array = []
	var adj: Array = node_adj[n]
	for j in adj.size():
		var si: int = node_eseg[n][j]
		if s_flag[si] == FLAG_HIDDEN:
			continue
		var nb: int = adj[j]
		var dir := (node_pos[nb] - node_pos[n]).normalized()
		var dest := _branch_dest(n, nb, s_type[si] == MAIN)
		if dest.is_empty():
			continue
		dest["dir"] = dir
		out.append(dest)
	return out

func _branch_dest(block: int, start: int, settlements_only: bool) -> Dictionary:
	var gcost := {start: node_pos[block].distance_to(node_pos[start])}
	var heap := Heap.new()
	heap.push(gcost[start], start)
	var closed := {block: true}
	var steps := 0
	while heap.size() > 0 and steps < 4000:
		steps += 1
		var c := heap.pop()
		if closed.has(c):
			continue
		closed[c] = true
		var lb: Dictionary = node_label[c]
		if not lb.is_empty() and (not settlements_only or lb.kind == "settlement"):
			return {"name": lb.name, "dist": gcost[c], "kind": lb.kind, "id": lb.id}
		var adj: Array = node_adj[c]
		for nb in adj:
			if closed.has(nb):
				continue
			var nd: float = gcost[c] + node_pos[c].distance_to(node_pos[nb])
			if nd < gcost.get(nb, 1e20):
				gcost[nb] = nd
				heap.push(nd, nb)
	if settlements_only:
		return _branch_dest(block, start, false)
	return {}

func to_dicts() -> Array:
	var out: Array = []
	for i in sa.size():
		out.append({"a": sa[i], "b": sb[i], "type": "main" if s_type[i] == MAIN else "trail", "width": s_hw[i] * 2.0,
			"bridge": s_flag[i] == FLAG_BRIDGE, "hidden": s_flag[i] == FLAG_HIDDEN, "route": s_line[i]})
	return out

func line_length(li: int) -> float:
	var pts: PackedVector2Array = lines[li]
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l

# ---------------------------------------------------------------- binary heap
class Heap:
	extends RefCounted
	var k := PackedFloat32Array()
	var v := PackedInt32Array()

	func size() -> int:
		return v.size()

	func push(key_v: float, val: int) -> void:
		k.append(key_v)
		v.append(val)
		var i := v.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if k[p] <= k[i]:
				break
			var tk := k[p]
			k[p] = k[i]
			k[i] = tk
			var tv := v[p]
			v[p] = v[i]
			v[i] = tv
			i = p

	func pop() -> int:
		var top := v[0]
		var last := v.size() - 1
		k[0] = k[last]
		v[0] = v[last]
		k.resize(last)
		v.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			if l >= last:
				break
			var m := l
			if l + 1 < last and k[l + 1] < k[l]:
				m = l + 1
			if k[i] <= k[m]:
				break
			var tk := k[m]
			k[m] = k[i]
			k[i] = tk
			var tv := v[m]
			v[m] = v[i]
			v[i] = tv
			i = m
		return top

# ---------------------------------------------------------------- planner
## Plans the network on a coarse cost grid (32 m cells): slope, water,
## mountains and a little noise for natural curves. Roads join existing roads
## (T-junctions become crossroads) and end at settlement centres through
## gaps between houses. Used only during world generation.
class Planner:
	extends RefCounted
	const CELL := 32.0
	const DX := [1, -1, 0, 0, 1, 1, -1, -1]
	const DZ := [0, 0, 1, -1, 1, -1, 1, -1]
	var gen                       # WorldGen (only during generation)
	var net: RoadNet
	var G := 80
	var half := 1280.0
	var cost := PackedFloat32Array()
	var hh := PackedFloat32Array()
	var netc := PackedInt32Array()   # -1 free, >=0 polyline id, <=-2 settlement (-2 - index)
	var setl := PackedInt32Array()   # settlement index or -1
	var pen := PackedFloat32Array()  # extra penalty (around points of interest)
	var spokes := {}                 # settlement index -> Array[float] used entry angles
	var _done := 0                   # polylines already post-processed

	func _init(g, n: RoadNet) -> void:
		gen = g
		net = n
		half = g.half
		G = int(ceil(half * 2.0 / CELL))
		var cnt := G * G
		cost.resize(cnt)
		hh.resize(cnt)
		netc.resize(cnt)
		netc.fill(-1)
		setl.resize(cnt)
		setl.fill(-1)
		pen.resize(cnt)
		var wl: float = g.water_level
		for cz in G:
			for cx in G:
				var c := cz * G + cx
				var p := center(c)
				hh[c] = g.raw_height(p.x, p.y)
		for cz in G:
			for cx in G:
				var c := cz * G + cx
				var p := center(c)
				var k := 1.0
				var h := hh[c]
				if h < wl + 0.25:
					k += 9.0
				k += g.mountain_mask(p.x, p.y) * 3.5
				k += (g.n_detail.get_noise_2d(p.x * 0.11, p.y * 0.11) + 1.0) * 0.45
				var edge_d := minf(minf(cx, cz), minf(G - 1 - cx, G - 1 - cz))
				if edge_d < 4:
					k += (4 - edge_d) * 6.0
				cost[c] = k

	func center(c: int) -> Vector2:
		return Vector2(-half + (c % G + 0.5) * CELL, -half + (c / G + 0.5) * CELL)

	func cell_of(p: Vector2) -> int:
		var cx := clampi(floori((p.x + half) / CELL), 0, G - 1)
		var cz := clampi(floori((p.y + half) / CELL), 0, G - 1)
		return cz * G + cx

	func _mark_settlement(si: int, s: Dictionary, as_network: bool) -> void:
		var r: float = float(s.radius) * 0.95
		var sp: Vector2 = s.pos
		var c0 := cell_of(sp - Vector2(r, r))
		var c1 := cell_of(sp + Vector2(r, r))
		for cz in range(c0 / G, c1 / G + 1):
			for cx in range(c0 % G, c1 % G + 1):
				var c := cz * G + cx
				if center(c).distance_to(sp) < r or c == cell_of(sp):
					setl[c] = si
					if as_network:
						netc[c] = -2 - si

	## Dijkstra / A* over the cost grid. to_network: stop at the first network
	## cell that does not belong to settlement `self_s`.
	func route(start: int, goal: int, to_network: bool, self_s: int, max_cost: float) -> PackedInt32Array:
		var n := G * G
		var dist := PackedFloat32Array()
		dist.resize(n)
		dist.fill(1e20)
		var prev := PackedInt32Array()
		prev.resize(n)
		prev.fill(-1)
		var closed := PackedByteArray()
		closed.resize(n)
		var heap := RoadNet.Heap.new()
		dist[start] = 0.0
		heap.push(0.0, start)
		var gx := goal % G if goal >= 0 else 0
		var gz := goal / G if goal >= 0 else 0
		var found := -1
		while heap.size() > 0:
			var c := heap.pop()
			if closed[c] == 1:
				continue
			closed[c] = 1
			if c != start:
				if to_network:
					var nc := netc[c]
					if nc != -1 and nc != -2 - self_s:
						found = c
						break
				elif c == goal:
					found = c
					break
			var dc := dist[c]
			if dc > max_cost:
				break
			var cx := c % G
			var cz := c / G
			for d in 8:
				var nx: int = cx + DX[d]
				var nz: int = cz + DZ[d]
				if nx < 0 or nz < 0 or nx >= G or nz >= G:
					continue
				var nn := nz * G + nx
				if closed[nn] == 1:
					continue
				var ln := 1.41421 if d >= 4 else 1.0
				var grade := absf(hh[c] - hh[nn]) / (ln * CELL)
				var ec := ln * (0.5 * (cost[c] + cost[nn]) + pen[nn] + grade * 14.0 + grade * grade * 260.0)
				var s_other := setl[nn]
				if s_other >= 0 and s_other != self_s and netc[nn] == -1:
					ec += ln * 3.0
				var nd := dc + ec
				if nd < dist[nn]:
					dist[nn] = nd
					prev[nn] = c
					var hv := 0.0
					if not to_network:
						hv = Vector2(nx - gx, nz - gz).length()
					heap.push(nd + hv, nn)
		if found < 0:
			return PackedInt32Array()
		var out := PackedInt32Array()
		var c2 := found
		while c2 != -1:
			out.append(c2)
			c2 = prev[c2]
		out.reverse()
		return out

	func _jitter(c: int) -> Vector2:
		var h := hash(c * 92821 + int(gen.seed_v) * 31 + int(gen.era) * 7)
		return Vector2(float(h & 1023) / 1023.0 - 0.5, float((h >> 10) & 1023) / 1023.0 - 0.5) * 15.0

	## Point on the network at anchor cell `c`, seen from `toward`. Inserts a
	## junction vertex into an existing polyline when needed.
	func _anchor(c: int, toward: Vector2) -> Vector2:
		var nc := netc[c]
		if nc <= -2:
			return gen.settlements[-2 - nc].pos
		var pts: PackedVector2Array = net.lines[nc]
		var best := 1e12
		var bi := 0
		var bp := pts[0]
		for i in pts.size() - 1:
			var cp := Geometry2D.get_closest_point_to_segment(toward, pts[i], pts[i + 1])
			var d := cp.distance_squared_to(toward)
			if d < best:
				best = d
				bi = i
				bp = cp
		# reuse a vertex when close
		if bp.distance_to(pts[bi]) < 3.0:
			bp = pts[bi]
		elif bp.distance_to(pts[bi + 1]) < 3.0:
			bp = pts[bi + 1]
		else:
			pts.insert(bi + 1, bp)
			var fl: PackedByteArray = net.line_flags[nc]
			fl.insert(bi + 1, fl[bi] if bi < fl.size() else 0)
			net.lines[nc] = pts
			net.line_flags[nc] = fl
		net.protected[RoadNet.key(bp)] = true
		return bp

	## Adds the pieces of a cell path that are not already on the network.
	func add_path(path: PackedInt32Array, start_pt, end_pt, typ: int) -> Array:
		var made: Array = []
		var i := 0
		var n := path.size()
		while i < n:
			if netc[path[i]] != -1 and not (i == 0 and start_pt != null):
				i += 1
				continue
			# run of free cells [i, j)
			var j := i
			while j < n and (netc[path[j]] == -1 or (j == 0 and start_pt != null)):
				j += 1
			var pts := PackedVector2Array()
			var first_free := center(path[i]) + _jitter(path[i])
			if i == 0:
				pts.append(start_pt)
			else:
				pts.append(_anchor(path[i - 1], first_free))
			for q in range(i, j):
				if q == 0:
					continue
				pts.append(center(path[q]) + _jitter(path[q]))
			if j < n:
				pts.append(_anchor(path[j], pts[pts.size() - 1]))
			elif end_pt != null:
				pts.append(end_pt)
			if pts.size() >= 2:
				var line := _smooth(pts)
				if _length(line) > 6.0:
					var li := net.add_line(line, typ)
					_rasterize(li)
					made.append(li)
			i = j
		return made

	func _length(p: PackedVector2Array) -> float:
		var l := 0.0
		for i in p.size() - 1:
			l += p[i].distance_to(p[i + 1])
		return l

	func _smooth(p: PackedVector2Array) -> PackedVector2Array:
		var cur := p
		for it in 2:
			if cur.size() < 3:
				break
			var nx := PackedVector2Array()
			nx.append(cur[0])
			for i in cur.size() - 1:
				var a := cur[i]
				var b := cur[i + 1]
				if i > 0:
					nx.append(a.lerp(b, 0.25))
				if i < cur.size() - 2:
					nx.append(a.lerp(b, 0.75))
			nx.append(cur[cur.size() - 1])
			cur = nx
		return resample(cur, 9.0)

	static func resample(p: PackedVector2Array, step: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		if p.size() < 2:
			return p
		out.append(p[0])
		var carry := 0.0
		for i in p.size() - 1:
			var a := p[i]
			var b := p[i + 1]
			var ln := a.distance_to(b)
			if ln < 0.001:
				continue
			var t := step - carry
			while t < ln:
				out.append(a.lerp(b, t / ln))
				t += step
			carry = ln - (t - step)
		var last := p[p.size() - 1]
		if out[out.size() - 1].distance_to(last) < step * 0.4 and out.size() > 1:
			out[out.size() - 1] = last
		else:
			out.append(last)
		return out

	func _rasterize(li: int) -> void:
		var pts: PackedVector2Array = net.lines[li]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var steps := int(a.distance_to(b) / 8.0) + 1
			for q in steps + 1:
				var c := cell_of(a.lerp(b, float(q) / steps))
				if netc[c] == -1:
					netc[c] = li

	# ---------------------------------------------------------------- main roads
	func build_main(settlements: Array) -> void:
		var n := settlements.size()
		for si in n:
			_mark_settlement(si, settlements[si], si == 0)
		if n < 2:
			return
		var connected := [0]
		var direct := {}
		while connected.size() < n:
			var bj := -1
			var bd := 1e12
			for j in n:
				if j in connected:
					continue
				for i in connected:
					var d: float = settlements[i].pos.distance_to(settlements[j].pos)
					if d < bd:
						bd = d
						bj = j
			var s: Dictionary = settlements[bj]
			var path := route(cell_of(s.pos), -1, true, bj, 1e9)
			if path.size() >= 2:
				add_path(path, s.pos, null, RoadNet.MAIN)
			_mark_settlement(bj, s, true)
			connected.append(bj)
		# loops: link nearby settlements whose road distance is a long detour
		net.finalize(settlements)
		var node_of := {}
		for ni in net.node_pos.size():
			node_of[RoadNet.key(net.node_pos[ni])] = ni
		var cands: Array = []
		for i in n:
			for j in range(i + 1, n):
				var d: float = settlements[i].pos.distance_to(settlements[j].pos)
				if d > 720.0:
					continue
				var rd := _graph_dist(node_of.get(RoadNet.key(settlements[i].pos), -1), node_of.get(RoadNet.key(settlements[j].pos), -1))
				if rd > d * 1.6:
					cands.append([rd / d, i, j])
		cands.sort_custom(func(a, b): return a[0] > b[0])
		var used := {}
		var loops := 0
		for cd in cands:
			if loops >= 3:
				break
			var i2: int = cd[1]
			var j2: int = cd[2]
			if used.get(i2, 0) >= 2 or used.get(j2, 0) >= 2:
				continue
			var path2 := route(cell_of(settlements[i2].pos), cell_of(settlements[j2].pos), false, i2, 1e9)
			if path2.size() < 3:
				continue
			if add_path(path2, null, null, RoadNet.MAIN).is_empty():
				continue
			used[i2] = used.get(i2, 0) + 1
			used[j2] = used.get(j2, 0) + 1
			loops += 1

	func _graph_dist(a: int, b: int) -> float:
		if a < 0 or b < 0:
			return 1e9
		var g := {a: 0.0}
		var heap := RoadNet.Heap.new()
		heap.push(0.0, a)
		var closed := {}
		while heap.size() > 0:
			var c := heap.pop()
			if closed.has(c):
				continue
			closed[c] = true
			if c == b:
				return g[c]
			for nb in net.node_adj[c]:
				var nd: float = g[c] + net.node_pos[c].distance_to(net.node_pos[nb])
				if nd < g.get(nb, 1e20):
					g[nb] = nd
					heap.push(nd, nb)
		return 1e9

	# ---------------------------------------------------------------- trails
	func build_trails(pois: Array, types: Array) -> void:
		pen.fill(0.0)
		for q in pois:
			var r: float = float(q.get("r", 6.0)) + 18.0
			var qp: Vector2 = q.pos
			var c0 := cell_of(qp - Vector2(r, r))
			var c1 := cell_of(qp + Vector2(r, r))
			for cz in range(c0 / G, c1 / G + 1):
				for cx in range(c0 % G, c1 % G + 1):
					var c := cz * G + cx
					if center(c).distance_to(qp) < r + 16.0:
						pen[c] = maxf(pen[c], 6.0)
		for q in pois:
			if not q.type in types:
				continue
			var qp: Vector2 = q.pos
			var r2: float = maxf(float(q.get("r", 6.0)) * 0.85, 3.0)
			var start := cell_of(qp)
			# no penalty around the POI being connected
			var saved := {}
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var cx2 := start % G + dx
					var cz2 := start / G + dz
					if cx2 >= 0 and cz2 >= 0 and cx2 < G and cz2 < G:
						var cc := cz2 * G + cx2
						saved[cc] = pen[cc]
						pen[cc] = 0.0
			var path := route(start, -1, true, -1, 60.0)
			for cc in saved:
				pen[cc] = saved[cc]
			if path.size() < 2:
				continue
			var nxt := center(path[1]) if path.size() > 2 else _anchor_peek(path[path.size() - 1], qp)
			var dir := (nxt - qp)
			if dir.length() < 0.1:
				dir = Vector2(1, 0)
			var sp := qp + dir.normalized() * r2
			var made := add_path(path, sp, null, RoadNet.TRAIL)
			if not made.is_empty():
				net.labels[RoadNet.key(sp)] = {"name": q.name, "kind": "poi", "id": q.id, "type": q.type}
				net.protected[RoadNet.key(sp)] = true

	func _anchor_peek(c: int, toward: Vector2) -> Vector2:
		var nc := netc[c]
		if nc <= -2:
			return gen.settlements[-2 - nc].pos
		if nc < 0:
			return center(c)
		var pts: PackedVector2Array = net.lines[nc]
		var best := 1e12
		var bp := pts[0]
		for i in pts.size() - 1:
			var cp := Geometry2D.get_closest_point_to_segment(toward, pts[i], pts[i + 1])
			var d := cp.distance_squared_to(toward)
			if d < best:
				best = d
				bp = cp
		return bp

	# ---------------------------------------------------------------- post-processing
	## Settlement entries through gaps between houses, bridges over water,
	## railway flags. Processes polylines added since the previous call.
	func finish(settlements: Array, rails: bool) -> void:
		for li in range(_done, net.lines.size()):
			var pts: PackedVector2Array = net.lines[li]
			if pts.size() < 2:
				continue
			for si in settlements.size():
				var sp: Vector2 = settlements[si].pos
				if pts[pts.size() - 1].distance_to(sp) < 0.5:
					_spoke(li, si, settlements[si], false)
					pts = net.lines[li]
				if pts[0].distance_to(sp) < 0.5:
					_spoke(li, si, settlements[si], true)
					pts = net.lines[li]
		for li in range(_done, net.lines.size()):
			_bridges(li)
		if rails:
			for li in range(_done, net.lines.size()):
				if net.line_type[li] == RoadNet.MAIN and net.line_length(li) > 220.0 and li % 2 == 0:
					net.line_rail[li] = 1
		_done = net.lines.size()

	func _spoke(li: int, si: int, s: Dictionary, at_start: bool) -> void:
		var pts: PackedVector2Array = net.lines[li]
		var fl: PackedByteArray = net.line_flags[li]
		if at_start:
			pts.reverse()
			fl.reverse()
		var sp: Vector2 = s.pos
		var R: float = s.radius
		# drop points inside the settlement (from the centre end)
		while pts.size() > 1 and pts[pts.size() - 1].distance_to(sp) < R * 1.12 and not net.protected.has(RoadNet.key(pts[pts.size() - 1])):
			pts.remove_at(pts.size() - 1)
			if fl.size() > 0:
				fl.remove_at(fl.size() - 1)
		var last := pts[pts.size() - 1]
		var desired := atan2(last.y - sp.y, last.x - sp.x)
		var th := _free_angle(si, s, desired)
		var add := PackedVector2Array()
		var ring := R * 1.28
		if last.distance_to(sp) > R * 1.15:
			var diff := wrapf(th - desired, -PI, PI)
			var steps := int(absf(diff) / 0.33)
			var cur_a := atan2(last.y - sp.y, last.x - sp.x)
			for q in range(1, steps + 1):
				var a := cur_a + diff * float(q) / float(steps + 1)
				add.append(sp + Vector2(cos(a), sin(a)) * ring)
			add.append(sp + Vector2(cos(th), sin(th)) * ring)
		var dv := Vector2(cos(th), sin(th))
		add.append(sp + dv * R * 0.98)
		var pr := RoadNet.plaza_ratio(str(s.type))
		add.append(sp + dv * R * 0.62)
		add.append(sp + dv * R * pr)
		add.append(sp)
		for q in add.size():
			pts.append(add[q])
			fl.append(RoadNet.FLAG_HIDDEN if q == add.size() - 1 else RoadNet.FLAG_ROAD)
		if at_start:
			pts.reverse()
			fl.reverse()
		net.lines[li] = pts
		net.line_flags[li] = fl
		if not spokes.has(si):
			spokes[si] = []
		spokes[si].append(th)

	func _free_angle(si: int, s: Dictionary, desired: float) -> float:
		var sp: Vector2 = s.pos
		var R: float = s.radius
		var used: Array = spokes.get(si, [])
		var best := desired
		var best_score := -1e9
		for q in 90:
			var a := desired + (float(q) * 0.0698 if q % 2 == 0 else -float(q + 1) * 0.0698) * 0.5
			var dv := Vector2(cos(a), sin(a))
			var p0 := sp + dv * R * 0.3
			var p1 := sp + dv * R * 1.05
			var clear := 1e9
			for b in s.buildings:
				var bp: Vector2 = b.pos
				var bsz: Vector2 = b.size
				var cp := Geometry2D.get_closest_point_to_segment(bp, p0, p1)
				clear = minf(clear, cp.distance_to(bp) - maxf(bsz.x, bsz.y) * 0.62 - RoadNet.HW_MAIN - 0.8)
			var sep := PI
			for u in used:
				sep = minf(sep, absf(wrapf(a - float(u), -PI, PI)))
			var score := minf(clear, 0.0) * 10.0 - absf(wrapf(a - desired, -PI, PI)) * 2.0
			if sep < 0.55:
				score -= 40.0
			if score > best_score:
				best_score = score
				best = a
		return best

	func _water(p: Vector2) -> bool:
		return gen.ground_base(p.x, p.y) < gen.water_level + 0.15

	func _bridges(li: int) -> void:
		var pts: PackedVector2Array = net.lines[li]
		var fl: PackedByteArray = net.line_flags[li]
		if pts.size() < 3:
			return
		var npts := PackedVector2Array()
		var nfl := PackedByteArray()
		var n := pts.size()
		var i := 0
		while i < n:
			if i > 0 and _water(pts[i]):
				var j := i
				var prot := false
				while j < n and _water(pts[j]):
					if net.protected.has(RoadNet.key(pts[j])):
						prot = true
					j += 1
				if j < n and not prot:
					# straight bridge from pts[i-1] (already in npts) to pts[j]
					nfl[nfl.size() - 1] = RoadNet.FLAG_BRIDGE
					npts.append(pts[j])
					nfl.append(fl[j] if j < fl.size() else 0)
					i = j + 1
					continue
				for q in range(i, j):
					npts.append(pts[q])
					nfl.append(fl[q] if q < fl.size() else 0)
				i = j
				continue
			npts.append(pts[i])
			nfl.append(fl[i] if i < fl.size() else 0)
			i += 1
		nfl.resize(maxi(0, npts.size() - 1))
		net.lines[li] = npts
		net.line_flags[li] = nfl

# ---------------------------------------------------------------- rendering
## Road surface shader. Vertex data: UV = (lateral offset m, arclength m) for
## roads, world xz for plazas; COLOR.r = edge factor (0 outer .. 1 inner),
## COLOR.g = kind (0 main, .33 trail, .66 rail ballast, 1 plaza),
## COLOR.b = lateral position 0..1, COLOR.a = half width / 8.
const ROAD_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_burley;
uniform int style = 0;
uniform vec3 c_main : source_color = vec3(0.5, 0.42, 0.3);
uniform vec3 c_trail : source_color = vec3(0.45, 0.38, 0.28);
uniform vec3 c_stone : source_color = vec3(0.6, 0.58, 0.55);
uniform vec3 c_edge : source_color = vec3(0.7, 0.7, 0.7);
uniform vec3 c_grass : source_color = vec3(0.3, 0.45, 0.2);
uniform vec3 c_glow : source_color = vec3(0.2, 0.9, 1.0);
uniform float margin = 0.9;
global uniform float weather_wet;
global uniform float weather_snow;
varying vec3 wpos;
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
vec3 voro(vec2 x) {
	vec2 n = floor(x); vec2 f = fract(x);
	float d1 = 8.0; float d2 = 8.0; float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash2(n + g), hash2(n + g + 17.31));
			vec2 r = g + o * 0.85 - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; id = hash2(n + g + 3.7); } else if (d < d2) { d2 = d; }
		}
	}
	return vec3(sqrt(d1), sqrt(d2) - sqrt(d1), id);
}
vec3 lin(vec3 c) { return c * c; }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float kind = COLOR.g;
	float hw = COLOR.a * 8.0;
	float edge = COLOR.r;
	vec2 wp = wpos.xz;
	float lat = UV.x;
	float alng = UV.y;
	float n1 = vnoise(wp * 0.7);
	float n2 = vnoise(wp * 3.3);
	bool is_trail = kind > 0.16 && kind < 0.5;
	bool is_ballast = kind >= 0.5 && kind < 0.83;
	bool is_plaza = kind >= 0.83;
	vec3 col = c_main;
	float rough = 0.92;
	vec3 emit = vec3(0.0);
	float alpha_noise = 0.6;
	float sharp = 0.0;
	if (is_ballast) {
		vec3 v = voro(wp * 6.0);
		col = mix(vec3(0.22, 0.2, 0.19), vec3(0.5, 0.48, 0.45) * (0.7 + 0.6 * v.z), smoothstep(0.02, 0.12, v.y));
	} else if (is_plaza) {
		if (style == 3) {
			vec2 t = fract(wp / 1.5);
			col = c_edge * (0.85 + 0.25 * hash2(floor(wp / 1.5))) * mix(0.7, 1.0, step(0.04, t.x) * step(0.04, t.y));
		} else if (style == 4) {
			vec2 t = fract(wp / 2.0);
			col = c_main * (0.9 + 0.2 * hash2(floor(wp / 2.0)));
			float seam = 1.0 - step(0.03, t.x) * step(0.03, t.y);
			col = mix(col, c_glow * 0.4, seam * 0.6);
			emit = c_glow * seam * 0.25;
			rough = 0.3;
		} else if (style == 0 && COLOR.a < 0.4) {
			col = c_main * (0.82 + 0.3 * n1) * (0.92 + 0.16 * n2);
			vec3 v = voro(wp * 1.3);
			float stone = (1.0 - smoothstep(0.2, 0.32, v.x)) * step(0.62, v.z);
			col = mix(col, c_stone * (0.6 + 0.4 * v.z), stone * 0.85);
			col = mix(col, c_grass, smoothstep(0.62, 0.8, vnoise(wp * 0.3)) * 0.35);
		} else {
			vec3 v = voro(wp * 2.1);
			vec3 stone = c_stone * (0.62 + 0.42 * v.z) * (0.9 + 0.2 * n1);
			vec3 mortar = style == 0 ? c_main * 0.7 : c_stone * 0.4;
			col = mix(mortar, stone, smoothstep(0.03, 0.12, v.y));
			if (style == 0) { col = mix(col, c_main * (0.8 + 0.3 * n1), smoothstep(0.66, 0.82, vnoise(wp * 0.35)) * 0.5); }
		}
		alpha_noise = 0.35;
	} else if (is_trail) {
		col = c_trail * (0.78 + 0.35 * n1) * (0.9 + 0.2 * n2);
		if (style == 1) { vec3 v = voro(wp * 7.0); col = mix(col * 0.75, c_stone * (0.8 + 0.4 * v.z), smoothstep(0.03, 0.1, v.y) * 0.7); }
		if (style == 2) { col = mix(col, vec3(0.12, 0.11, 0.11), 0.35 + 0.3 * n2); }
		if (style == 3) {
			vec2 t = fract(vec2(lat + 0.5, alng) / vec2(1.0, 1.2));
			col = c_edge * (0.82 + 0.2 * hash2(floor(vec2(lat + 0.5, alng) / vec2(1.0, 1.2)))) * mix(0.75, 1.0, step(0.05, t.y));
			sharp = 1.0;
		}
		if (style == 4) {
			col = c_main * (0.9 + 0.2 * n2);
			float dots = step(abs(lat), 0.08) * step(fract(alng / 2.0 - TIME * 0.4), 0.3);
			emit = c_glow * dots * 1.6;
			rough = 0.35;
			sharp = 1.0;
		}
		// grass strip in the middle of footpaths
		if (style <= 2) { col = mix(col, c_grass, exp(-lat * lat / 0.05) * 0.45 * smoothstep(0.35, 0.7, n1)); }
	} else if (style == 0) {
		col = c_main * (0.8 + 0.32 * n1) * (0.92 + 0.16 * n2);
		float rut = exp(-pow((abs(lat) - hw * 0.42) / 0.32, 2.0));
		col *= 1.0 - 0.32 * rut;
		col = mix(col, c_grass, exp(-lat * lat / 0.22) * 0.25 * smoothstep(0.4, 0.8, n1));
		vec3 v = voro(wp * 1.6);
		float stone = (1.0 - smoothstep(0.16, 0.26, v.x)) * step(0.86, v.z);
		col = mix(col, c_stone * (0.5 + 0.3 * v.z), stone * 0.75);
		float puddle = smoothstep(0.66, 0.74, vnoise(wp * 0.22 + 7.3)) * (1.0 - smoothstep(0.5, 0.9, abs(lat) / hw));
		col = mix(col, col * 0.45 + vec3(0.02, 0.03, 0.05), puddle);
		rough = mix(0.92, 0.12, puddle);
	} else if (style == 1) {
		vec3 v = voro(vec2(lat, alng) * 1.9 + wp * 0.001);
		vec3 stone = c_stone * (0.7 + 0.55 * v.z) * (0.9 + 0.2 * n1);
		col = mix(c_stone * 0.4, stone, smoothstep(0.03, 0.11, v.y));
		float curb = smoothstep(hw - 0.45, hw - 0.3, abs(lat));
		vec2 cb = vec2(alng / 0.9, 0.0);
		col = mix(col, c_edge * (0.8 + 0.25 * hash2(floor(cb))) * step(0.06, fract(cb.x)), curb);
		alpha_noise = 0.3;
	} else if (style == 2) {
		vec2 b = vec2(alng / 0.46, lat / 0.22);
		b.x += floor(b.y) * 0.5;
		vec2 f = fract(b);
		float mortar = step(0.07, f.x) * step(0.1, f.y);
		vec3 brick = c_main * (0.75 + 0.45 * hash2(floor(b)));
		col = mix(vec3(0.18, 0.17, 0.16), brick, mortar);
		col *= 0.8 + 0.3 * n1;
		float curb = smoothstep(hw - 0.4, hw - 0.28, abs(lat));
		col = mix(col, c_edge * (0.85 + 0.2 * n2), curb);
		alpha_noise = 0.3;
	} else if (style == 3) {
		col = c_main * (0.82 + 0.25 * n2) * (0.9 + 0.2 * n1);
		float al = abs(lat);
		float centre = step(al, 0.07) * step(fract(alng / 6.0), 0.5);
		float side = step(hw - 0.45, al) * step(al, hw - 0.3);
		col = mix(col, c_stone, max(centre, side) * 0.95);
		float curb = step(hw, al) * step(al, hw + 0.22);
		float walk = step(hw + 0.22, al);
		vec2 sl = vec2(alng / 1.4, 0.0);
		col = mix(col, c_edge * 0.95, curb);
		col = mix(col, c_edge * (0.78 + 0.18 * hash2(floor(sl))) * mix(0.8, 1.0, step(0.04, fract(sl.x))), walk);
		rough = 0.85;
		sharp = 1.0;
	} else {
		vec2 t = fract(vec2(lat, alng) / vec2(1.5, 3.0));
		col = c_main * (0.92 + 0.16 * hash2(floor(vec2(lat, alng) / vec2(1.5, 3.0))));
		float seam = 1.0 - step(0.025, t.x) * step(0.02, t.y);
		col = mix(col, c_main * 2.0, seam * 0.5);
		float al = abs(lat);
		float strip = step(hw - 0.35, al) * step(al, hw - 0.18);
		float chev = step(al, 0.12) * step(fract(alng / 5.0 - TIME * 0.6), 0.25);
		emit = c_glow * (strip * 2.2 + chev * 1.4);
		col = mix(col, c_glow, max(strip, chev) * 0.7);
		rough = 0.28;
		sharp = 1.0;
	}
	float a = edge + (n1 * 0.7 + n2 * 0.3 - 0.5) * alpha_noise * (1.0 - sharp);
	if (sharp > 0.5) { a = edge * 4.0 - 0.4; }
	ALPHA = clamp(a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// weather: wet roads darken and shine, puddles collect in ruts and
	// between stones; snow covers the road but keeps the wheel ruts
	float pud = smoothstep(0.64, 0.78, vnoise(wp * 0.35) * 0.7 + n2 * 0.3) * weather_wet * (is_trail ? 1.0 : 0.8);
	col *= 1.0 - weather_wet * 0.3;
	col = mix(col, col * 0.3 + vec3(0.03, 0.035, 0.045), pud);
	rough = mix(mix(rough, 0.35, weather_wet * 0.7), 0.04, pud);
	float rut = 1.0 - smoothstep(0.08, 0.16, abs(abs(lat - 0.5) - 0.22));
	float snw = weather_snow * (0.85 - rut * 0.55) * (0.8 + 0.2 * n1);
	col = mix(col, vec3(0.65, 0.68, 0.73), clamp(snw, 0.0, 0.85));
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = col * 0.8;
#else
	ALBEDO = col;
#endif
	ROUGHNESS = rough;
	SPECULAR = 0.3 + weather_wet * 0.25 + pud * 0.4;
	EMISSION = emit;
}
"""

static var _road_mats := {}

## Era road material (shared). Styles: 0 dirt + ruts, 1 cobblestone,
## 2 brick + granite curbs, 3 asphalt + markings + sidewalks, 4 tech lanes.
static func material(era: int) -> ShaderMaterial:
	if _road_mats.has(era):
		return _road_mats[era]
	var sh := Shader.new()
	sh.code = ROAD_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var e: Dictionary = DBEras.era(era)
	var g: Dictionary = e.ground
	m.set_shader_parameter("style", era)
	m.set_shader_parameter("c_grass", g.plains)
	match era:
		0:
			m.set_shader_parameter("c_main", Color(0.5, 0.4, 0.28))
			m.set_shader_parameter("c_trail", Color(0.47, 0.38, 0.27))
			m.set_shader_parameter("c_stone", Color(0.52, 0.5, 0.47))
			m.set_shader_parameter("margin", 0.9)
		1:
			m.set_shader_parameter("c_main", Color(0.56, 0.5, 0.42))
			m.set_shader_parameter("c_trail", Color(0.58, 0.52, 0.42))
			m.set_shader_parameter("c_stone", Color(0.62, 0.57, 0.5))
			m.set_shader_parameter("c_edge", Color(0.7, 0.66, 0.6))
			m.set_shader_parameter("margin", 0.7)
		2:
			m.set_shader_parameter("c_main", Color(0.5, 0.27, 0.2))
			m.set_shader_parameter("c_trail", Color(0.33, 0.3, 0.28))
			m.set_shader_parameter("c_stone", Color(0.45, 0.43, 0.41))
			m.set_shader_parameter("c_edge", Color(0.55, 0.55, 0.55))
			m.set_shader_parameter("margin", 0.7)
		3:
			m.set_shader_parameter("c_main", Color(0.22, 0.22, 0.24))
			m.set_shader_parameter("c_trail", Color(0.5, 0.48, 0.42))
			m.set_shader_parameter("c_stone", Color(0.92, 0.9, 0.82))
			m.set_shader_parameter("c_edge", Color(0.62, 0.62, 0.6))
			m.set_shader_parameter("margin", 1.6)
		_:
			m.set_shader_parameter("c_main", Color(0.13, 0.14, 0.19))
			m.set_shader_parameter("c_trail", Color(0.16, 0.17, 0.22))
			m.set_shader_parameter("c_stone", Color(0.4, 0.42, 0.5))
			m.set_shader_parameter("c_edge", Color(0.3, 0.32, 0.4))
			m.set_shader_parameter("c_glow", Color(0.25, 0.95, 1.0))
			m.set_shader_parameter("margin", 0.6)
	_road_mats[era] = m
	return m

## Radius of the paved square relative to the settlement radius.
static func plaza_ratio(typ: String) -> float:
	match typ:
		"village": return 0.2
		"town", "port": return 0.24
		"castle", "fort": return 0.22
	return 0.28

## Lateral soft margin beyond the half width (sidewalks for the modern era).
static func margin_of(era: int, typ: int) -> float:
	if typ == TRAIL:
		return 0.7 if era != 3 else 0.35
	return [0.9, 0.7, 0.7, 1.6, 0.6][era]
