class_name HistoricalEchoes
extends Node
## Historical Echoes. Near a place where something notable really happened
## (a Chronicle entry with a position in the current era) a short ghostly
## replay appears: translucent figures re-enact the moment — with the real
## participants' looks when they are known — under the chronicle line.
## Sources are ONLY real chronicle entries or the explicitly authored
## episodes below (marked as such in the caption); nothing is generated.
## Short-lived (LIFE s), rare (global cool-down, each event once per long
## while), skipped inside rifts, switched off by Settings.echoes.

const TYPES := {"boss_kill": 3, "legend_died": 3, "battle": 3, "resonance_catastrophe": 3, "black_storm": 3,
	"settlement_captured": 2, "legend_born": 2, "duel": 2, "betrayal": 2, "mercy": 1, "kill": 1}
const RADIUS := 26.0
const MIN_DIST := 3.0
const GLOBAL_CD := 75.0
const EVENT_CD := 900.0
const LIFE := 7.0
const MIN_AGE_DAYS := 0.02       # the moment must already be "the past"
## Authored episodes: written lore, not generated. Anchored to the era capital.
const AUTHORED := [
	{"id": "a0", "era": 0, "off": Vector2(7, -5), "scene": "gathering", "text": "Летопись города: на этой площади короновали первого владыку столицы."},
	{"id": "a1", "era": 1, "off": Vector2(-6, 6), "scene": "duel", "text": "Летопись города: здесь мушкетёр и гвардеец кардинала дрались до первой крови."},
	{"id": "a2", "era": 2, "off": Vector2(8, 4), "scene": "gathering", "text": "Летопись города: здесь рабочие встали против хозяев фабрик."},
	{"id": "a3", "era": 3, "off": Vector2(-7, -6), "scene": "gathering", "text": "Летопись города: здесь объявили о конце долгой войны."},
	{"id": "a4", "era": 4, "off": Vector2(5, 7), "scene": "storm", "text": "Летопись города: здесь впервые разорвалась ткань времени."},
]

var world
var _t := 0.0
var _cd := 20.0
var seen := {}
var active: Array = []
var shown := 0
var last := {}

func setup(w) -> void:
	world = w

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(delta: float) -> void:
	_cd -= delta
	_t += delta
	if _t < 1.5:
		return
	_t = 0.0
	var alive: Array = []
	for e in active:
		if is_instance_valid(e):
			alive.append(e)
	active = alive
	if not Settings.echoes:
		for e in active:
			e.queue_free()
		active.clear()
		return
	if world == null or world.player == null or not is_instance_valid(world.player) or world.dimension != "" or Game.mode != "world":
		return
	if _cd > 0.0 or not active.is_empty():
		return
	var cand := pick(world.player.global_position)
	if not cand.is_empty():
		play(cand)

## Best echo source near a point: {"ev": chronicle entry} or {"authored": ep}.
func pick(pp: Vector3) -> Dictionary:
	var best := {}
	var bs := -1.0
	var now := _now()
	var evs: Array = Chronicle.events
	var lo := maxi(0, evs.size() - 400)
	for i in range(evs.size() - 1, lo - 1, -1):
		var ev: Dictionary = evs[i]
		if int(ev.get("era", -1)) != Profile.current_era or not TYPES.has(ev.type):
			continue
		var pos: Array = ev.get("pos", [0, 0])
		if pos.size() < 2 or (float(pos[0]) == 0.0 and float(pos[1]) == 0.0):
			continue
		var d := Vector2(float(pos[0]) - pp.x, float(pos[1]) - pp.z).length()
		if d > RADIUS or d < MIN_DIST:
			continue
		if Game.game_time - float(ev.get("t", 0.0)) < MIN_AGE_DAYS:
			continue
		if now - float(seen.get("c%d" % int(ev.id), -1e9)) < EVENT_CD:
			continue
		var sc: float = TYPES[ev.type] * 10.0 - d * 0.1
		if sc > bs:
			bs = sc
			best = {"ev": ev}
	if not best.is_empty():
		return best
	var cap: Dictionary = world.director.capital() if world.director.has_method("capital") else {}
	if cap.is_empty():
		return {}
	for ep in AUTHORED:
		if int(ep.era) != Profile.current_era:
			continue
		var ap: Vector2 = Vector2(cap.pos.x, cap.pos.y) + ep.off
		var d2 := Vector2(ap.x - pp.x, ap.y - pp.z).length()
		if d2 > RADIUS or d2 < MIN_DIST or now - float(seen.get(ep.id, -1e9)) < EVENT_CD * 2.0:
			continue
		return {"authored": ep, "pos": ap}
	return {}

func play(src: Dictionary) -> Node3D:
	var text := ""
	var scene := "single"
	var looks: Array = []
	var p := Vector3.ZERO
	var key := ""
	if src.has("ev"):
		var ev: Dictionary = src.ev
		p = Vector3(float(ev.pos[0]), 0, float(ev.pos[1]))
		text = "Эхо прошлого · день %d\n%s" % [int(ev.get("t", 0.0)) + 1, ev.get("text", "")]
		key = "c%d" % int(ev.id)
		match ev.type:
			"kill", "duel", "boss_kill", "legend_died", "betrayal":
				scene = "duel"
			"battle", "settlement_captured":
				scene = "battle"
			"resonance_catastrophe", "black_storm":
				scene = "storm"
			_:
				scene = "single"
		for id in ev.get("actors", []):
			var rec = world.legends.recs.get(id) if world.legends and world.legends.get("recs") is Dictionary else null
			looks.append(rec.get("look", {}) if rec is Dictionary else {})
		last = {"source": "chronicle", "id": int(ev.id), "type": ev.type, "text": text}
	else:
		var ep: Dictionary = src.authored
		p = Vector3(src.pos.x, 0, src.pos.y)
		scene = ep.scene
		text = "Эхо прошлого (летопись)\n%s" % ep.text
		key = ep.id
		last = {"source": "authored", "id": ep.id, "text": text}
	p.y = world.ground_height(p)
	seen[key] = _now()
	_cd = GLOBAL_CD
	shown += 1
	var root := Node3D.new()
	root.name = "Echo"
	world.fx_root.add_child(root)
	root.global_position = p
	var mat := MagicFX.smat("fresnel", {"col": Color(0.62, 0.86, 1.0, 0.5), "power": 1.3, "bands": 2.0}) as ShaderMaterial
	var boss_scale: bool = src.has("ev") and src.ev.type == "boss_kill"
	match scene:
		"duel":
			_figure(root, "F0", looks[0] if looks.size() > 0 else {}, Vector3(-1.1, 0, 0), Vector3.RIGHT, mat)
			var b := _figure(root, "F1", looks[1] if looks.size() > 1 else {}, Vector3(1.1, 0, 0), Vector3.LEFT, mat)
			if boss_scale:
				b.scale = Vector3.ONE * 1.8
			_at(root, 1.2, "F0", "slash")
			_at(root, 1.7, "F1", "hit")
			_at(root, 2.6, "F0", "overhead")
			_at(root, 3.0, "F1", "dead")
		"battle":
			for i in 4:
				var side := -1.0 if i < 2 else 1.0
				_figure(root, "F%d" % i, looks[i] if looks.size() > i else {}, Vector3(side * 1.3, 0, (i % 2) * 1.6 - 0.8), Vector3(-side, 0, 0), mat)
				_at(root, 0.8 + i * 0.35, "F%d" % i, "slash")
			_at(root, 3.2, "F1", "dead")
		"storm":
			_figure(root, "F0", looks[0] if looks.size() > 0 else {}, Vector3.ZERO, Vector3.FORWARD, mat)
			_at(root, 0.8, "F0", "cast")
			MagicFX.ground_rune(p + Vector3(0, 0.06, 0), "rift", Color(0.7, 0.55, 1.0, 0.6), 4.0, LIFE * 0.8, 0.6, 0.7)
		"gathering":
			for i in 3:
				var an := TAU * i / 3.0
				_figure(root, "F%d" % i, {}, Vector3(cos(an), 0, sin(an)) * 1.6, -Vector3(cos(an), 0, sin(an)), mat)
				_at(root, 1.0 + i * 0.4, "F%d" % i, "cast")
		_:
			_figure(root, "F0", looks[0] if looks.size() > 0 else {}, Vector3.ZERO, Vector3.FORWARD, mat)
			_at(root, 1.0, "F0", "cast")
	var lb := Label3D.new()
	lb.text = text
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font_size = 30
	lb.pixel_size = 0.005
	lb.outline_size = 8
	lb.modulate = Color(0.8, 0.92, 1.0, 0.0)
	lb.width = 560
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.position.y = 3.2
	root.add_child(lb)
	var tw := root.create_tween()
	tw.tween_property(lb, "modulate:a", 0.95, 0.8)
	tw.parallel().tween_method(func(v: float): mat.set_shader_parameter("col", Color(0.62, 0.86, 1.0, v)), 0.0, 0.5, 0.8)
	tw.tween_interval(LIFE - 2.0)
	tw.tween_property(lb, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_method(func(v: float): mat.set_shader_parameter("col", Color(0.62, 0.86, 1.0, v)), 0.5, 0.0, 1.2)
	tw.tween_callback(root.queue_free)
	var mg = VFX.mgr()
	if mg != null:
		mg.emit(p + Vector3(0, 1.0, 0), {"n": 16, "life": 2.5, "mat": "add", "col": Color(0.7, 0.9, 1.0, 0.7), "size": 0.15, "shape": "sphere", "rad": 2.0, "v0": 0.1, "v1": 0.4, "grav": Vector3(0, 0.3, 0), "ramp": "pop"})
	Audio.play_sfx("time_warp", p, -14.0)
	active.append(root)
	return root

func _figure(root: Node3D, nm: String, look: Dictionary, off: Vector3, face: Vector3, mat: Material) -> HumanoidRig:
	var r := HumanoidRig.new()
	r.name = nm
	var lk := look
	if lk.is_empty():
		lk = {"skin": randi() % 4, "hair": randi() % 5, "hair_color": randi() % 5, "beard": randi() % 3, "cloth": randi() % 4}
	r.setup(lk)
	root.add_child(r)
	r.position = off
	if face.length() > 0.01:
		r.look_at(r.global_position - face, Vector3.UP)
	MagicFX._strip_ghost(r, mat)
	return r

## Timed pose of one figure; looks the figure up by name so a timer never
## holds a reference to a freed node.
func _at(root: Node3D, t: float, fig: String, what: String) -> void:
	var wr: WeakRef = weakref(root)
	get_tree().create_timer(t, false).timeout.connect(func():
		var r = wr.get_ref()
		if r == null:
			return
		var f = r.get_node_or_null(fig)
		if f == null:
			return
		_pose(f, what))

func _pose(f, what: String) -> void:
	if what == "hit":
		f.on_hit(Vector3.RIGHT, true)
	elif what == "dead":
		f.dead = true
	else:
		f.trigger(what)
