extends Node
## Long-run soak test: an autopilot player roams, fights, loots and opens
## windows while day/night, weather, director events, faction strategy and the
## background simulation run accelerated. Reports script errors indirectly
## (grep the log), leaks (node/actor counts over time) and world activity.
## Run: godot --headless --fixed-fps 30 --path . tests/soak_test.tscn
## Env: SOAK_MINUTES (game minutes, default 12), SOAK_ERA (default 0).

func _ready() -> void:
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Автопилот", ["warrior", "archer", "rogue", "mage"][randi() % 4], false, {})
	Profile.current_era = int(OS.get_environment("SOAK_ERA")) if OS.get_environment("SOAK_ERA") != "" else 0
	if Profile.current_era > 0:
		# arrive like a real player: at the era's entry level with era-appropriate gear
		Profile.char.level = [1, 8, 15, 22, 30][Profile.current_era]
		var kit := {1: ["rapier", "armor_doublet"], 2: ["revolver", "armor_coat"], 3: ["carbine", "vest_kevlar"], 4: ["pulse_rifle", "armor_energy"]}
		for b in kit[Profile.current_era]:
			var it := ItemDB.create(b, 2, Profile.char.level, null, false)
			Profile.char.inv.add(it)
			Profile.char.inv.equip_item(it)
	var h := Pilot.new()
	h.minutes = float(OS.get_environment("SOAK_MINUTES")) if OS.get_environment("SOAK_MINUTES") != "" else 12.0
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class Pilot:
	extends Node
	var minutes := 12.0
	var t := 0.0
	var goal := Vector3.ZERO
	var goal_t := 0.0
	var ui_t := 0.0
	var ev_t := 0.0
	var rep_t := 0.0
	var deaths := 0
	var started := false
	var events_seen := {}
	var max_nodes := 0
	var ui_names := ["inventory", "skills", "factions", "journal", "map", "legends", "chronicle", "pause"]
	var ev_types := ["bandit_raid", "blood_moon", "magic_storm", "cursed_fog", "meteor", "rift_open", "rare_find", "uprising", "chrono_catastrophe", "world_boss", "caravan_attack", "invasion"]
	var ev_i := 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Events.world_event_started.connect(func(e): events_seen[e.type] = events_seen.get(e.type, 0) + 1)
		Events.player_died.connect(func():
			deaths += 1
			var p = Game.player
			var la = p.last_attacker
			var top := []
			for k in p.damage_log:
				top.append("%s=%d" % [k, int(p.damage_log[k])])
			print("DEATH t=%d by=%s lvl=%s hp_max=%d armor=%.0f st=%s log=%s" % [int(t), la.display_name if la != null and is_instance_valid(la) else "?", str(la.level) if la != null and is_instance_valid(la) else "?", int(p.max_hp), p.stat("armor"), str(p.statuses.keys()), ",".join(top.slice(-4))]))

	func _physics_process(delta: float) -> void:
		var w = Game.world
		if w == null or Game.player == null or not is_instance_valid(Game.player):
			return
		if not started:
			started = true
			Game.day_length = 120.0
			print("SOAK start class=", Game.player.data.class_id, " era=", Profile.current_era)
		t += delta
		var p = Game.player
		# handle death / windows
		if p.is_dead:
			if w.ui.is_open() or w._death_pending:
				w.ui.close_all()
				w._respawn()
			return
		ui_t += delta
		if Game.ui_is_open():
			if ui_t > 0.4:
				w.ui.close_all()
				ui_t = 0.0
			return
		if ui_t > 20.0:
			ui_t = 0.0
			w.ui.open(ui_names[randi() % ui_names.size()])
			return
		# force a director event regularly so every type is exercised
		ev_t += delta
		if ev_t > 25.0 and w.director.events.size() < 3:
			ev_t = 0.0
			w.director._start(ev_types[ev_i % ev_types.size()], p.global_position)
			ev_i += 1
		# faction strategy faster
		w.factions._strat_t += delta * 3.0
		# fight or roam
		var tgt = null
		var bd := 18.0
		for a in Game.actors_near(p.global_position, 18.0):
			if a != p and not a.is_dead and Game.is_enemy(p, a):
				var d: float = a.global_position.distance_to(p.global_position)
				if d < bd:
					bd = d
					tgt = a
		if p.hp < p.max_hp * 0.35:
			p.quick_potion()
			if p.hp < p.max_hp * 0.25:
				p.heal(p.max_hp * 0.5)   # pilot cheat to keep exploring
		if tgt:
			var dir: Vector3 = tgt.global_position - p.global_position
			dir.y = 0
			var r: float = p.weapon_range()
			p.scripted_move = dir.normalized() if dir.length() > r * 0.8 else Vector3.ZERO
			p.attack(dir.normalized())
			if randf() < 0.02:
				p.use_slot(randi() % 3, dir.normalized())
			if randf() < 0.01:
				p.dodge(dir.cross(Vector3.UP))
		else:
			goal_t -= delta
			if goal_t <= 0.0 or p.global_position.distance_to(goal) < 4.0:
				goal_t = 30.0
				if w.gen and randf() < 0.7:
					var poi: Dictionary = w.gen.pois[randi() % w.gen.pois.size()]
					goal = Vector3(poi.pos.x, 0, poi.pos.y)
					if goal.distance_to(p.global_position) > 250.0:
						goal = p.global_position + (goal - p.global_position).normalized() * 120.0
				else:
					goal = p.global_position + Vector3(randf_range(-80, 80), 0, randf_range(-80, 80))
			var dg: Vector3 = goal - p.global_position
			dg.y = 0
			p.scripted_move = dg.normalized()
			if p.interact_target != null and is_instance_valid(p.interact_target) and randf() < 0.05:
				var it = p.interact_target
				if not (it is NPC) and not (it is Poi and it.type in ["trial", "fortress", "tourney", "terminal", "mirror"]):
					p.do_interact()
					if Game.ui_is_open():
						w.ui.close_all()
		# equip better gear sometimes
		if randf() < 0.002:
			for it in p.data.inv.items.duplicate():
				if ItemDB.is_equipment(it):
					var slot: String = ItemDB.base(it.base).slot
					if ItemDB.power(it) > ItemDB.power(p.data.inv.equipped(slot)) and it.get("curse", {}).is_empty():
						p.equip_item(it)
		rep_t += delta
		if rep_t > 60.0:
			rep_t = 0.0
			_report()
		if t > minutes * 60.0:
			_report()
			SaveSys.save_game()
			print("SOAK events_seen=", events_seen)
			print("SOAK chronicle_types=", _chron_types())
			print("SOAK max_nodes=", max_nodes, " deaths=", deaths)
			print("SOAK_DONE")
			get_tree().quit()

	func _report() -> void:
		var w = Game.world
		var p = Game.player
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		max_nodes = maxi(max_nodes, nodes)
		var legends := 0
		var alive := 0
		for k in w.legends.recs:
			if w.legends.recs[k].alive:
				alive += 1
				if w.legends.recs[k].legend:
					legends += 1
		var br := {}
		for c in w.get_children():
			br[str(c.name)] = _count(c)
		var kinds := {}
		for c in w.actors_root.get_children():
			var key := "%s/%s/%s/%s" % [c.get_class(), str(c.get("role")), str(c.get("settlement_id")), "dead" if c.get("is_dead") else "alive"]
			kinds[key] = kinds.get(key, 0) + 1
		print("SOAK actor_kinds ", kinds)
		print("SOAK branches ", br, " drops=", w.fx_root.get_children().filter(func(x): return x is ItemDrop).size())
		print("SOAK t=%d lvl=%d kills=%d gold=%d nodes=%d actors=%d orbs=%d zones=%d events=%d chron=%d recs_alive=%d legends=%d quests=%d day=%d hour=%.1f weather=%s mem=%.1fMB" % [
			int(t), p.data.level, p.data.kills, p.data.gold, nodes, Game.actors.size(), w.orbs.count, w.zones.size(), w.director.events.size(),
			Chronicle.events.size(), alive, legends, w.quests.quests.size(), Game.day(), Game.hour(), w.weather.current if w.weather else "?",
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])

	func _count(n: Node) -> int:
		var c := 1
		for k in n.get_children():
			c += _count(k)
		return c

	func _chron_types() -> Dictionary:
		var d := {}
		for e in Chronicle.events:
			d[e.type] = d.get(e.type, 0) + 1
		return d
