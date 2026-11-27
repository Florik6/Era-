extends Node
## All 25 «Beasts of the Ages» dungeons played start to finish (scripted
## kills, real systems): enter, every room fills with its era's creatures,
## the boss wakes up in its hall, every phase triggers, the boss dies, the
## loot drops once, the exit opens, the hero leaves and progress is saved.
## The second boss of a dungeon (side hall) is checked too.
## Prints DUNGEONS_ALL_DONE pass=N fail=M.

func _ready() -> void:
	seed(252525)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Скиталец", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 252525
	Profile.current_era = 0
	Settings.cinematics = 0
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
	func rwait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()
	func kill(a, by) -> void:
		if a == null or not is_instance_valid(a) or a.is_dead:
			return
		a.statuses.erase("invuln")
		if a is Boss and a.shield != null:
			a.shield.clear()
		Combat.deal(by, a, {"amount": a.max_hp * 9.0 + 99999.0, "dtype": "slash", "src": by})

	func _run() -> void:
		await rwait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		var ok_all := 0
		var bad: Array = []
		var extra_ok := 0
		var extra_n := 0
		for did in DBBeasts.dungeons():
			var res := await _one(w, pl, did)
			if res.ok:
				ok_all += 1
			else:
				bad.append("%s: %s" % [did, res.why])
			extra_n += int(res.extra_n)
			extra_ok += int(res.extra_ok)
			ck("dungeon %s (%s) playable start to finish" % [did, DBBeasts.dungeon(did).name], res.ok, res.why)
		ck("all 25 dungeons are complete experiences", ok_all == 25, str(bad))
		ck("second bosses in side halls fight and fall", extra_ok == extra_n, "%d/%d" % [extra_ok, extra_n])
		var disk: Dictionary = {}
		Profile.current_era = 0          # the world being played is era 0 (levels were per dungeon era)
		w.sync_to_state()
		SaveSys.save_game()
		disk = SaveSys.load_world_state(0).get("dungeons", {})
		var saved := 0
		for did in disk:
			if disk[did].get("boss_dead", false):
				saved += 1
		ck("every cleared dungeon is in the save", saved == 25, str(saved))
		var bk: Dictionary = BeastWorld.book()
		var bosses_in_book := 0
		for bid in DBBeasts.bosses():
			if int(bk.get(bid, {}).get("kills", 0)) >= 1:
				bosses_in_book += 1
		ck("bestiary holds every dungeon boss that fell", bosses_in_book >= 25, str(bosses_in_book))
		print("DUNGEONS_ALL_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()

	func _one(w, pl, did: String) -> Dictionary:
		var out := {"ok": false, "why": "", "extra_n": 0, "extra_ok": 0}
		var dd: Dictionary = DBBeasts.dungeon(did)
		Profile.current_era = int(dd.era)
		var d: BeastDungeon = w.enter_dungeon(did)
		await rwait(0.4)
		if d == null:
			out.why = "no dungeon"
			return out
		# every room except the boss hall
		var mobs_seen := 0
		for c in d.rooms:
			var r: Dictionary = d.rooms[c]
			if r.type == "boss":
				continue
			w._teleport(pl, r.pos + Vector3(0, 0.4, 0))
			await rwait(0.35)
			for m in r.get("mobs", []):
				if is_instance_valid(m):
					mobs_seen += 1
					if m is Boss:
						out.extra_n += 1
						var bid2: String = m.boss_id
						kill(m, pl)
						await rwait(0.3)
						if bid2 in d.state().extra_dead:
							out.extra_ok += 1
					else:
						kill(m, pl)
			await get_tree().process_frame
		if mobs_seen < 3:
			out.why = "too few creatures (%d)" % mobs_seen
		if d.secret_wall != null and is_instance_valid(d.secret_wall):
			d.secret_wall.take_hit(999.0, "blunt", pl)
		# the boss
		var br: Dictionary = d.rooms[d.order[d.order.size() - 1]]
		w._teleport(pl, br.pos + Vector3(0, 0.4, br.size * 0.3))
		await rwait(0.5)
		var b = d.boss
		if b == null or not is_instance_valid(b) or b.boss_id != dd.boss:
			out.why = "boss missing"
			d.finish_and_leave()
			await rwait(0.5)
			return out
		b.brain.dormant = 0.0
		await rwait(1.0)
		var phases: int = b.def.phases.size()
		for i in range(1, phases):
			if not is_instance_valid(b) or b.is_dead:
				break
			b.statuses.erase("invuln")
			if b.shield != null:
				b.shield.clear()
			b.hp = b.max_hp * (float(b.def.phases[i].hp) - 0.02)
			await rwait(1.2)
		var reached: int = b.phase + 1 if is_instance_valid(b) else 0
		if reached < phases:
			out.why += " phases %d/%d" % [reached, phases]
		var lc: int = BeastWorld.inst.stats.boss_loot
		kill(b, pl)
		await rwait(1.0)
		if not d.state().get("boss_dead", false):
			out.why += " boss not recorded dead"
		if BeastWorld.inst.stats.boss_loot != lc + 1:
			out.why += " loot rolls=%d" % (BeastWorld.inst.stats.boss_loot - lc)
		if d.exits.size() < 2:
			out.why += " no exit"
		d.finish_and_leave()
		await rwait(0.6)
		if w.dimension != "":
			out.why += " still inside"
		out.ok = out.why == ""
		# leave the next entry its cool-down
		w.portal_block_until = 0
		return out
