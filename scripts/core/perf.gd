class_name Perf
extends RefCounted
## Tiny opt-in CPU profiler for subsystems (AI, rigs, actor physics, VFX).
## Disabled by default (one bool check per call). Benchmarks switch it on
## and read the per-frame microsecond totals.

static var enabled := false
static var acc := {}       # key -> usec accumulated since last take()
static var calls := {}     # key -> calls since last take()

static func add(key: String, usec: int) -> void:
	acc[key] = int(acc.get(key, 0)) + usec
	calls[key] = int(calls.get(key, 0)) + 1

## Returns {key: usec} and resets the counters.
static func take() -> Dictionary:
	var out := acc.duplicate()
	acc.clear()
	calls.clear()
	return out
