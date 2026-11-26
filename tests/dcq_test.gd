extends Node
## Dynamic Combat Quality behaviour with synthetic frame times:
## degrades under sustained load step by step, ignores small jitter,
## waits between changes, restores when stable, can be switched off.

var pass_n := 0
var fail_n := 0

class FakeWorld:
	extends Node
	func sys(_n: String):
		return null

func ck(nm: String, ok: bool, extra := "") -> void:
	if ok:
		pass_n += 1
	else:
		fail_n += 1
	print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")

func feed(dq: DynamicQuality, fps: float, secs: float, jitter := 0.0) -> void:
	var t := 0.0
	while t < secs:
		var f := fps + randf_range(-jitter, jitter)
		var dt := 1.0 / maxf(1.0, f)
		dq._process(dt)
		t += dt

func _ready() -> void:
	Settings.dynamic_quality = true
	Settings.target_fps = 30
	var fw := FakeWorld.new()
	add_child(fw)
	var dq := DynamicQuality.new()
	add_child(dq)
	dq.setup(fw)
	ck("starts at full quality", DynamicQuality.level == 0)
	feed(dq, 31.0, 20.0, 3.0)
	ck("small jitter around the target changes nothing", DynamicQuality.level == 0, "level %d" % DynamicQuality.level)
	feed(dq, 20.0, 4.0)
	ck("sustained low FPS lowers one step", DynamicQuality.level == 1, "level %d" % DynamicQuality.level)
	feed(dq, 20.0, 2.0)
	ck("no second step during the cool-down", DynamicQuality.level == 1, "level %d" % DynamicQuality.level)
	feed(dq, 18.0, 30.0)
	ck("keeps stepping down while overloaded (never past the max)", DynamicQuality.level >= 4 and DynamicQuality.level <= DynamicQuality.MAX_LEVEL, "level %d" % DynamicQuality.level)
	var lv := DynamicQuality.level
	feed(dq, 60.0, 9.5)
	ck("restores one step after stable high FPS", DynamicQuality.level == lv - 1, "level %d" % DynamicQuality.level)
	feed(dq, 60.0, 80.0)
	ck("fully restores when stable", DynamicQuality.level == 0, "level %d" % DynamicQuality.level)
	var ch := dq.changes
	feed(dq, 27.5, 30.0, 2.0)
	ck("FPS just under the target (within 10 %) doesn't flap", dq.changes == ch, "changes +%d" % (dq.changes - ch))
	feed(dq, 15.0, 5.0)
	Settings.dynamic_quality = false
	dq._process(0.016)
	ck("switching it off restores full quality", DynamicQuality.level == 0)
	Settings.dynamic_quality = true
	print("DCQ_DONE pass=%d fail=%d" % [pass_n, fail_n])
	get_tree().quit()
