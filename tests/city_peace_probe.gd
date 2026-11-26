extends Node
## Diagnostic: what actually happens in a city when the world just lives.
## The hero stands in the capital doing nothing (invulnerable, never
## attacks); the world director, living sim, road encounters, factions all
## run normally. Every hit and kill is logged by who-vs-who category.
## Env: PROBE_SECS (real seconds, default 120), PROBE_SCALE (time scale,
## default 2), PROBE_OUT (json). Prints PROBE_RESULT {...}.

func _ready() -> void:
	seed(int(OS.get_environment("PROBE_SEED")) if OS.get_environment("PROBE_SEED") != "" else 1234)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Наблюдатель", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 777001
	Profile.current_era = int(OS.get_environment("PROBE_ERA")) if OS.get_environment("PROBE_ERA") != "" else 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var hits := {}
	var kills := {}
	var hit_n := 0
	var kill_n := 0
	var events := {}
	var cats := {}
	var fight_goals := 0
	var samples := 0
	var peace_states := {}
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Events.actor_damaged.connect(_on_dmg)
		Events.actor_killed.connect(_on_kill)
		Events.world_event_started.connect(func(e): events[e.type] = int(events.get(e.type, 0)) + 1)
		_run()
	func wait(s: float) -> void:
		await get_tree().create_timer(s, true, false, true).timeout
	func cat(a) -> String:
		if a == null or not is_instance_valid(a):
			return "env"
		if a.is_player:
			return "player"
		var r: String = str(a.get("role")) if a.get("role") != null else ""
		if r == "":
			r = a.kind
		return "%s/%s" % [r, a.team]
	func _on_dmg(t, amount: float, src, _dt: String) -> void:
		if amount <= 0.0:
			return
		var k := cat(src) + " -> " + cat(t)
		hits[k] = int(hits.get(k, 0)) + 1
		hit_n += 1
	func _on_kill(v, killer) -> void:
		var k := cat(killer) + " x " + cat(v)
		kills[k] = int(kills.get(k, 0)) + 1
		kill_n += 1
	func _run() -> void:
		await wait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		var cap: Dictionary = w.director.capital() if w.director.has_method("capital") else w.gen.settlements[0]
		var cp := Vector3(cap.pos.x, 0, cap.pos.y)
		w.terrain.force_load_around(cp)
		await wait(1.0)
		cp.y = w.ground_height(cp) + 0.5
		w._teleport(pl, cp)
		await wait(2.0)
		var secs := float(OS.get_environment("PROBE_SECS")) if OS.get_environment("PROBE_SECS") != "" else 120.0
		Engine.time_scale = float(OS.get_environment("PROBE_SCALE")) if OS.get_environment("PROBE_SCALE") != "" else 2.0
		var t := 0.0
		var g0 := Game.game_time
		while t < secs:
			await wait(1.0)
			t += 1.0
			# sample: how many NPCs within 45 m are in the "fight" goal
			for a in Game.actors_near(pl.global_position, 45.0):
				if a == pl or a.is_dead:
					continue
				var c := cat(a)
				cats[c] = int(cats.get(c, 0)) + 1
				samples += 1
				if a.get("brain") != null and str(a.brain.get("goal")) == "fight":
					fight_goals += 1
			var cps = w.sys("city_peace")
			if cps != null and cps.has_method("state_of"):
				var st: String = cps.state_of(cap.id)
				peace_states[st] = int(peace_states.get(st, 0)) + 1
		Engine.time_scale = 1.0
		var res := {"city": cap.get("name", ""), "real_s": secs, "game_hours": snappedf((Game.game_time - g0) * 24.0, 0.01),
			"hits": hit_n, "kills": kill_n, "fight_share": snappedf(float(fight_goals) / maxf(1.0, samples), 0.001),
			"hits_by": hits, "kills_by": kills, "events": events, "npc_seen": cats, "peace_states": peace_states}
		print("PROBE_RESULT ", JSON.stringify(res))
		var out := OS.get_environment("PROBE_OUT")
		if out != "":
			var f := FileAccess.open(out, FileAccess.WRITE)
			f.store_string(JSON.stringify(res, "  "))
			f.close()
		get_tree().quit()
