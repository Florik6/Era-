extends Node
## Historical Echoes: appear only from real chronicle entries (or authored
## episodes), near their place, short-lived, rare, and can be switched off.
## Prints ECHO_DONE pass=N fail=M.

func _ready() -> void:
	seed(31337)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Profile.new_character("Летописец", "rogue", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 0, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func _ready() -> void:
		_run()
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 9999.0)
		w.director.set_process(false)
		var ec = w.sys("echoes")
		ck("echoes subsystem attached", ec != null)
		Settings.echoes = true
		ec._cd = 0.0
		# nothing has happened here yet → no echo
		await wait(2.0)
		ck("no echo without a real event nearby", ec.active.is_empty() and ec.shown == 0, "shown %d" % ec.shown)
		# a real chronicle entry 10 m away (a fallen boss)
		var rec: Dictionary = w.legends.new_record("Сэр Доран", {"level": 5})
		var pos: Vector3 = pl.global_position + Vector3(10, 0, 0)
		var ev := Chronicle.record("boss_kill", [rec.id, "boss_x"], {"pos_v3": pos, "names": {rec.id: rec.name, "boss_x": "Палач"}, "extra": {"boss": "Палач Чёрной Башни"}})
		ck("fresh events are not yet echoes (must be the past)", ec.pick(pl.global_position).is_empty())
		Game.game_time += 0.1
		await wait(2.0)
		ck("an echo appears near the place of a real event", ec.active.size() == 1 and ec.shown == 1)
		ck("it replays that exact chronicle entry", ec.last.get("source", "") == "chronicle" and int(ec.last.get("id", -1)) == int(ev.id) and str(ec.last.text).contains(ev.text), str(ec.last.get("text", "")))
		var found := false
		for e2 in Chronicle.events:
			if int(e2.id) == int(ec.last.get("id", -2)):
				found = true
		ck("its source exists in the chronicle (nothing invented)", found)
		var node = ec.active[0] if ec.active.size() > 0 else null
		ck("echo shows ghost figures", node != null and node.find_children("*", "HumanoidRig", true, false).size() >= 2)
		await wait(HistoricalEchoes.LIFE + 1.0)
		ck("echo is short-lived", node == null or not is_instance_valid(node))
		# cool-down: same place, same event → no repeat right away
		ec._t = 2.0
		await wait(2.0)
		ck("rare: no immediate repeat (cool-downs)", ec.shown == 1)
		# far away events are ignored
		ec._cd = 0.0
		ec.seen.clear()
		w._teleport(pl, pl.global_position + Vector3(200, 0, 200))
		await wait(2.5)
		ck("events far away don't echo", ec.shown == 1 or ec.last.get("source", "") == "authored")
		# switched off
		w._teleport(pl, pos + Vector3(-8, 0, 0))
		await wait(1.0)
		Settings.echoes = false
		ec._cd = 0.0
		ec.seen.clear()
		var s0: int = ec.shown
		await wait(2.5)
		ck("switched off: no echoes", ec.shown == s0 and ec.active.is_empty())
		Settings.echoes = true
		Settings.save_settings()
		Settings.echoes = false
		Settings.load_settings()
		ck("the echoes setting persists", Settings.echoes == true)
		print("ECHO_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
