extends Node
## World Event Director 2.0: the 160 templates (32 per era), their launch
## conditions, the category weights, and a real run of every template in
## each era: participants/objects appear, peaceful events stay peaceful,
## every event ends with a result and a chronicle entry, temporary objects
## are freed, a running template is never duplicated.
## Prints EVENTS_DONE pass=N fail=M and EVENTS_STATS.

func _ready() -> void:
	seed(160160)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Летописец", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	var per_era := {}
	func ck(nm: String, ok: bool, extra := "") -> void:
		if ok:
			pass_n += 1
		else:
			fail_n += 1
		print("CHECK ", "OK   " if ok else "FAIL ", nm, ("  (" + extra + ")") if extra != "" else "")
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func load_era(era: int) -> void:
		Profile.current_era = era
		Profile.unlock_era(era)
		Game.start("world")
		await wait(4.0)
	func _run() -> void:
		await wait(3.0)
		# ---------------- registry
		var all: Array = DBEvents.all()
		ck("exactly 160 event templates", all.size() == 160, "%d" % all.size())
		var ids := {}
		for e in all:
			ids[e.id] = true
		ck("every template has a unique id", ids.size() == 160)
		var counts := []
		for era in 5:
			counts.append(DBEvents.of_era(era).size())
		ck("exactly 32 templates per era", counts == [32, 32, 32, 32, 32], str(counts))
		var bad_arch := []
		var bad_cat := []
		var d2 := EventDirector2.new()
		for e in all:
			if not d2.has_method("_start_" + String(e.arch)):
				bad_arch.append(e.id)
			if not e.cat in DBEvents.CATS:
				bad_cat.append(e.id)
		d2.free()
		ck("every template has a scenario implementation", bad_arch.is_empty(), str(bad_arch))
		ck("every template has a valid category", bad_cat.is_empty(), str(bad_cat))
		var dangers := 0
		for e in all:
			if e.cat == "danger":
				dangers += 1
		ck("most templates are not combat", dangers <= 40, "%d danger of 160" % dangers)
		# ---------------- per era
		var total_started := 0
		for era in 5:
			if era > 0:
				await load_era(era)
			var w = Game.world
			var pl = Game.player
			pl.apply_status("invuln", 999999.0)
			w.director._t = -100000.0
			var ev2 = w.sys("events2")
			ev2.enabled = false
			var cap: Dictionary = w.director.capital()
			var cp := Vector3(cap.pos.x, 0, cap.pos.y)
			w.terrain.force_load_around(cp)
			await wait(1.0)
			cp.y = w.ground_height(cp) + 0.5
			w._teleport(pl, cp)
			await wait(3.0)
			# a living legend for visitor events
			var rec: Dictionary = w.legends.new_record("Ветеран", {"level": 9})
			rec.legend = true
			rec.title = "Щит Заставы"
			rec.renown = 300.0
			if era == 0:
				# conditions: wrong hour, missing building, no blood moon
				var ctx: Dictionary = ev2._context()
				ctx.hour = 3.0
				ck("a daytime event is refused at night", ev2.why_not(DBEvents.get_event("med_harvest_fest"), ctx) == "не то время суток")
				ctx.hour = 22.0
				var vigil: String = ev2.why_not(DBEvents.get_event("med_blood_vigil"), ctx, true)
				ck("blood-moon vigil needs a blood moon", vigil == "нет кровавой луны", vigil)
				var tpl_x: Dictionary = DBEvents.get_event("med_smith_no_iron").duplicate()
				tpl_x.needs = ["observatory"]
				ctx.hour = 12.0
				ck("an event needing a missing building is refused", ev2.why_not(tpl_x, ctx, true) == "нет нужного здания")
				# weights: many picks in a town at noon
				var tally := {}
				var n_pick := 0
				for i in 1500:
					var c2: Dictionary = ev2._context()
					c2.hour = [9.0, 13.0, 18.5, 21.0][i % 4]
					var t: Dictionary = ev2.pick(c2)
					if not t.is_empty():
						tally[t.cat] = int(tally.get(t.cat, 0)) + 1
						n_pick += 1
				var peaceful := float(int(tally.get("social", 0)) + int(tally.get("economic", 0))) / maxf(1.0, n_pick)
				var danger := float(int(tally.get("danger", 0))) / maxf(1.0, n_pick)
				ck("town picks: mostly social/economic", peaceful >= 0.45, "%.2f %s" % [peaceful, str(tally)])
				ck("town picks: danger is rare", danger <= 0.12, "%.2f" % danger)
			var ok_n := 0
			var refused := {}
			var empty := []
			var peace_bad := []
			var no_chron := []
			var leaked := []
			for tpl in DBEvents.of_era(era):
				# a fitting hour for the template
				var hh: float = float(tpl.hours[0]) + 0.4
				Game.game_time = floor(Game.game_time) + 1.0 + fmod(hh, 24.0) / 24.0
				if CityPeace.inst:
					CityPeace.inst.cities[cap.id].state = "peaceful"
					CityPeace.inst.cities[cap.id].last_raid = -99.0
				if tpl.get("world", "") == "blood_moon":
					w.director._start("blood_moon", pl.global_position)
				var hits0: int = ev2.stats.peace_hits
				var ch0: int = Chronicle.events.size()
				var e: Dictionary = ev2.start(tpl, {}, true)
				if e.has("refused"):
					refused[tpl.id] = e.refused
					continue
				total_started += 1
				await wait(1.2)
				var dup: Dictionary = ev2.start(tpl, {}, true)
				if not dup.has("refused"):
					leaked.append(tpl.id + ":dup")
				var real: int = e.npcs.size() + e.nodes.size() + e.foes.size() + e.get("crowd", []).size()
				if real == 0 and (e.state == "running" or not e.ok):
					empty.append(tpl.id)
				var nodes: Array = e.nodes.duplicate()
				# end it
				if e.state == "running":
					e.until = Game.game_time - 0.001
					ev2._tick(e)
				await wait(0.3)
				if tpl.cat != "danger" and not tpl.arch in ["competition", "hazard"] and ev2.stats.peace_hits != hits0:
					peace_bad.append(tpl.id)
				var chron := false
				for k in range(ch0, Chronicle.events.size()):
					if Chronicle.events[k].type == "event2" and Chronicle.events[k].extra.get("id", "") == tpl.id:
						chron = true
				if not chron:
					no_chron.append(tpl.id)
				for n in nodes:
					if is_instance_valid(n) and not n.is_queued_for_deletion():
						leaked.append(tpl.id)
						break
				if e in ev2.active:
					leaked.append(tpl.id + ":active")
				if tpl.get("world", "") == "blood_moon":
					for de in w.director.events.duplicate():
						if de.type == "blood_moon":
							de.t = de.dur
							w.director._tick_event(de, 0.1)
				for f in e.foes:
					if is_instance_valid(f):
						f.queue_free()
				ok_n += 1
			per_era[era] = {"ran": ok_n, "refused": refused}
			print("ERA %d: ran %d / 32, refused %s" % [era, ok_n, str(refused)])
			ck("era %d: every template runs (or is refused only for a real missing condition)" % era, ok_n + refused.size() == 32 and _refusals_ok(refused), str(refused))
			ck("era %d: every running event has real participants or objects" % era, empty.is_empty(), str(empty))
			ck("era %d: peaceful events cause no violence" % era, peace_bad.is_empty(), str(peace_bad))
			ck("era %d: every event ends with a chronicle entry" % era, no_chron.is_empty(), str(no_chron))
			ck("era %d: temporary objects freed, no duplicates, nothing stays active" % era, leaked.is_empty(), str(leaked))
		ck("events persist in the save (history)", Game.world.sys("events2").history.size() > 0)
		Game.world.sys("events2").save_state()
		ck("history saved into the world state", Game.world_state.has("events2") and Game.world_state.events2.history.size() > 0)
		print("EVENTS_STATS ", JSON.stringify({"started": total_started, "per_era": per_era}))
		print("EVENTS_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
	func _refusals_ok(r: Dictionary) -> bool:
		for k in r:
			if not String(r[k]) in ["нет нужного здания", "нет здания для места", "нет живой легенды", "нет кровавой луны", "нет жителей"]:
				return false
		return true
