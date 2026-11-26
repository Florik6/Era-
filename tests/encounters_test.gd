extends Node
## Road Encounter Director check: every template is forced next to the hero,
## ticked for a while (the hero walks into it and uses its first spot/dialog
## option), then cleaned up. Counts script errors through the log; prints
## ENCOUNTERS_DONE ok=N bad=M.

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Тестер", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.current_era = int(OS.get_environment("ENC_ERA")) if OS.get_environment("ENC_ERA") != "" else 0
	var h := Harness.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Harness:
	extends Node
	var ok_n := 0
	var bad_n := 0
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func wait(sec: float) -> void:
		await get_tree().create_timer(sec, true, false, true).timeout
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 99999.0)
		var re = load("res://scripts/sim/road_encounters.gd").new()
		re.name = "road_encounters_test"
		w.add_child(re)
		re.setup(w)
		w.ext["road_encounters"] = re
		print("ENC templates=", re.TEMPLATES.size())
		for tpl in re.TEMPLATES:
			var p: Vector3 = pl.global_position + Vector3(8, 0, 0)
			var e: Dictionary = re.force(tpl, p)
			if e.is_empty():
				print("ENC FAIL ", tpl, " did not start")
				bad_n += 1
				continue
			await wait(1.0)
			var spots := 0
			for n in e.nodes:
				if is_instance_valid(n) and n.has_method("interact"):
					spots += 1
					n.interact(pl)
					await wait(0.2)
					if w.ui.top_name() == "dialog":
						var dlg = w.ui.stack.back()
						var opts: Array = dlg.args.get("options", [])
						if opts.size() > 0 and opts[0].has("cb"):
							w.ui.close(dlg)
							opts[0].cb.call()
					w.ui.close_all()
					break
			# walk around the encounter for a few ticks
			for i in 6:
				pl.scripted_move = (e.pos - pl.global_position).normalized() if i < 3 else Vector3.ZERO
				await wait(0.5)
			pl.scripted_move = Vector3.ZERO
			for a in e.actors.duplicate():
				if is_instance_valid(a) and not a.is_dead and Game.is_enemy(pl, a):
					a.die(pl)
			await wait(1.5)
			var real: bool = e.actors.size() > 0 or e.nodes.size() > 0
			print("ENC ", "OK   " if real else "EMPTY ", tpl, " actors=", e.actors.size(), " nodes=", e.nodes.size(), " spots=", spots, " state=", e.state, " result=", e.result)
			if real:
				ok_n += 1
			else:
				bad_n += 1
			re._cleanup(e)
			w.ui.close_all()
			await wait(0.3)
		print("ENCOUNTERS_DONE ok=%d bad=%d" % [ok_n, bad_n])
		get_tree().quit()
