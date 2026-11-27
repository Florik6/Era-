class_name TimeFX
extends Node
## The only owner of Engine.time_scale (global game speed).
##
## Every change of global speed is a REQUEST with an id, a source, a kind,
## a scale, a start, a real-time duration and an optional owner object.
## The global speed is the slowest active request, or exactly 1.0 when there
## are none. Requests end by themselves on the real clock (never on game
## time, which they slow down), when their owner node is freed or dies, when
## cancelled, and on scene changes. A watchdog clamps any request to the
## maximum of its category, so nothing can freeze the game for long.
##
## Categories (kept apart on purpose):
##   hitstop    — a tiny freeze on heavy hits (≤ 0.3 s, ≥ 0.25 s apart)
##   cinematic  — short dramatic slow motion (≤ 2.5 s)
## Time magic is NOT global: it slows actors / projectiles in its area
## (Actor statuses "timeslow" / "stasis", Zone "timeslow"). Menu pause is
## SceneTree.paused, handled by Game.push_ui / pop_ui — also not here.
##
## Root cause of the old stuck slow motion (fixed here): Game.slow_motion
## restored speed from a SceneTreeTimer, but only if the wall clock had
## passed a deadline. The timer counts frame steps (smoothed by the engine),
## the deadline used Time.get_ticks_msec(); the timer regularly fired a few
## to ~70 ms "early" by the wall clock, the restore was skipped and no later
## timer existed, so the game stayed slow until the next hit-stop wrote
## time_scale = 1.0 unconditionally (that is why a heavy blow "fixed" it).

const KINDS := {
	"hitstop": {"max": 0.3, "min_gap": 0.25, "lo": 0.03},
	"cinematic": {"max": 2.5, "min_gap": 0.0, "lo": 0.1},
}

static var inst: TimeFX = null

var requests := {}          # id -> request
## Base speed (1.0 in the game; automated tests may run the world faster).
var base_scale := 1.0
var _next := 1
var _last_kind_ms := {}     # kind -> msec of the last accepted request
var _applied := 1.0
var stats := {"requests": 0, "ended": 0, "cancelled": 0, "owner_gone": 0, "watchdog": 0, "rejected_gap": 0,
	"cleared": 0, "external_fix": 0}
var log: Array = []         # last few events (tests / debugging)

func _ready() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

static func now_ms() -> int:
	return Time.get_ticks_msec()

## Ask for a global speed change. Returns the request id (0 = refused).
## owner: optional Node — the request ends when it is freed (or, for an
## Actor, when it dies).
func request(kind: String, scale: float, real_dur: float, source := "", owner = null) -> int:
	var def: Dictionary = KINDS.get(kind, {})
	if def.is_empty() or real_dur <= 0.0:
		return 0
	var t := now_ms()
	if float(def.min_gap) > 0.0 and t - int(_last_kind_ms.get(kind, -999999)) < int(float(def.min_gap) * 1000.0):
		stats.rejected_gap += 1
		return 0
	var dur := real_dur
	if dur > float(def.max):
		dur = float(def.max)
		stats.watchdog += 1
		_log("clamped %s from %.2f to %.2f s (%s)" % [kind, real_dur, dur, source])
	var id := _next
	_next += 1
	var rq := {"id": id, "kind": kind, "scale": clampf(scale, float(def.lo), 1.0), "source": source,
		"start": t, "end": t + int(dur * 1000.0), "owner": owner.get_instance_id() if owner is Object else 0}
	requests[id] = rq
	_last_kind_ms[kind] = t
	stats.requests += 1
	_apply()
	set_process(true)
	return id

func cancel(id: int, reason := "cancelled") -> void:
	if requests.erase(id):
		stats.cancelled += 1
		_log("%d %s" % [id, reason])
		_apply()

## End every request of a source (an ability, an attack, a cutscene…).
func cancel_source(source: String) -> void:
	for id in requests.keys():
		if str(requests[id].source) == source:
			requests.erase(id)
			stats.cancelled += 1
	_apply()

## Scene change, death of the hero, forced reset of the combat state.
func clear_all(reason := "clear") -> void:
	if not requests.is_empty():
		stats.cleared += requests.size()
		_log("clear_all %d (%s)" % [requests.size(), reason])
	requests.clear()
	_apply()

func active(kind := "") -> int:
	if kind == "":
		return requests.size()
	var n := 0
	for id in requests:
		if requests[id].kind == kind:
			n += 1
	return n

func desired_scale() -> float:
	var s := 1.0
	for id in requests:
		s = minf(s, float(requests[id].scale))
	return s * base_scale

## Tests: run the whole world faster/slower (still owned by TimeFX).
func set_base(x: float) -> void:
	base_scale = clampf(x, 0.1, 8.0)
	_apply()

func _apply() -> void:
	var s := desired_scale()
	_applied = s
	if not is_equal_approx(Engine.time_scale, s):
		Engine.time_scale = s

## Runs only while there are requests (or until the speed is back to 1).
func _process(_delta: float) -> void:
	var t := now_ms()
	for id in requests.keys():
		var rq: Dictionary = requests[id]
		if t >= int(rq.end):
			requests.erase(id)
			stats.ended += 1
			continue
		var oid: int = int(rq.owner)
		if oid != 0:
			var o = instance_from_id(oid)
			if o == null or not is_instance_valid(o) or (o.get("is_dead") == true):
				requests.erase(id)
				stats.owner_gone += 1
				_log("%d owner gone (%s)" % [id, rq.source])
	# someone wrote Engine.time_scale behind our back: put it back (logged)
	if not is_equal_approx(Engine.time_scale, _applied):
		stats.external_fix += 1
		_log("external time_scale %.2f -> %.2f" % [Engine.time_scale, desired_scale()])
	_apply()
	if requests.is_empty():
		set_process(false)

func _log(s: String) -> void:
	log.append("%d %s" % [now_ms(), s])
	if log.size() > 40:
		log.pop_front()
