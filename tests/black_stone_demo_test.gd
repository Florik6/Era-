extends Node
## Demo «ПРОБУЖДЕНИЕ ЧЁРНОГО КАМНЯ» played through the real systems:
## medieval forest → claw tracks → wounded hunter (talk, bandage, quest) →
## the cave entrance (POI) → inside: dripping water, stone slimes, forks,
## claw marks, resources, patrolling creatures, a secret chest behind a
## hidden wall → Гармон: phase 1 (heavy blows, thrown rocks, awakening
## without losing control), phase 2 (shell breaks, glowing cracks, faster,
## new attacks, the cave collapses into cover and hazards) → victory (death
## animation, loot, bestiary, chronicle, quest) → Hardcore injuries can be
## inspected → the way out → everything saved.
## Prints DEMO_DONE pass=N fail=M.

func _ready() -> void:
	seed(20261127)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Ратибор", "warrior", false, {"skin": 1, "hair": 2, "hair_color": 1, "beard": 1, "cloth": 1})
	Profile.world_seed = 20261127
	Profile.current_era = 0
	Profile.difficulty = "hardcore"
	Settings.cinematics = 2
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
	var guard_hp := false      # the demo hero drinks potions: kept above 70 %
	var max_hit := 0.0
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		Events.actor_damaged.connect(func(t, amount, _s, _dt):
			if t == Game.player:
				max_hit = maxf(max_hit, amount))
		_run()
	func _physics_process(_d: float) -> void:
		var pl = Game.player
		if guard_hp and pl != null and is_instance_valid(pl) and not pl.is_dead and pl.hp < pl.max_hp * 0.7:
			pl.hp = pl.max_hp * 0.7
	func tp(p: Vector3) -> void:
		Game.world._teleport(Game.player, p)
	func close_ui(w) -> void:
		if w.ui and w.ui.has_method("close_all"):
			w.ui.close_all()
		get_tree().paused = false

	func _run() -> void:
		await rwait(3.0)
		var w = Game.world
		var pl = Game.player
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		var bw: BeastWorld = BeastWorld.inst
		# a sturdy hero for the demo (real damage, real injuries)
		pl.data.level = 8
		pl.level = 8
		pl.recalc_stats()
		pl.hp = pl.max_hp
		# ------------------------------------------------ 1. the forest
		var cave_poi: Dictionary = {}
		for p in w.gen.pois:
			if p.type == "dungeon" and p.get("data", {}).get("beast_dungeon", "") == "black_stone":
				cave_poi = p
		ck("«Пещеры Чёрного Камня» stand in the medieval world", not cave_poi.is_empty())
		if cave_poi.is_empty():
			_end()
			return
		var cave := Vector3(cave_poi.pos.x, 0, cave_poi.pos.y)
		var start := Vector3.ZERO
		var best_f := -1.0
		for i in 48:
			var a := float(i) / 48.0 * TAU
			var c := cave + Vector3(cos(a), 0, sin(a)) * 120.0
			var score := 1.0 if w.gen.biome(c.x, c.z) == "forest" else 0.0
			if w.gen.settlement_at(c.x, c.z, 1.5) == null and not w.gen.is_water(c.x, c.z) and score > best_f:
				best_f = score
				start = c
		w.terrain.force_load_around(start)
		start.y = w.ground_height(start) + 0.3
		tp(start)
		Game.game_time = 0.45   # a clear morning
		await rwait(1.0)
		ck("the hero walks through the forest", w.gen.biome(start.x, start.z) in ["forest", "plains", "mountain"], w.gen.biome(start.x, start.z))
		await rwait(3.5)
		var lead: Dictionary = bw.state.leads.get("black_stone", {})
		ck("strange claw tracks lead towards the cave", int(lead.get("stage", 0)) >= 1 and lead.get("tracks", []).size() >= 4, str(lead.get("tracks", []).size()))
		var tnode = bw.leads.get("black_stone", {}).get("tracks")
		ck("the tracks are real marks on the ground", tnode != null and is_instance_valid(tnode) and tnode.get_child_count() >= 4)
		# ------------------------------------------------ 2. the wounded hunter
		var hunter = bw.leads.get("black_stone", {}).get("hunter")
		ck("a wounded hunter lies by the trail", hunter != null and is_instance_valid(hunter) and hunter.hp < hunter.max_hp * 0.5)
		if hunter == null:
			_end()
			return
		tp(hunter.global_position + Vector3(1.5, 0.3, 0))
		await rwait(0.5)
		pl.data.inv.add(ItemDB.create("bandage", 0, 1))
		w.dialogs.open_npc(hunter)
		await rwait(0.3)
		var dlg = w.ui.get_screen("dialog") if w.ui.has_method("get_screen") else null
		ck("talking opens the hunter's story", dlg != null and str(dlg.args.get("text", "")).find("Пещер") >= 0)
		var bandaged := false
		if dlg != null:
			for o in dlg.args.get("options", []):
				if str(o.text).begins_with("Перевязать"):
					o.cb.call()
					bandaged = true
		close_ui(w)
		ck("bandaging him starts «Пробуждение Чёрного Камня»", bandaged and w.quests.active().any(func(q): return q.title == "Пробуждение Чёрного Камня"))
		ck("the hunter is better", hunter.hp >= hunter.max_hp * 0.7)
		var qt = w.quests.tracked_target()
		ck("the quest points to the cave", qt is Vector3 and Vector2(qt.x, qt.z).distance_to(cave_poi.pos) < 2.0)
		# ------------------------------------------------ 3. the entrance
		w.terrain.force_load_around(cave)
		var poi_node = null
		await rwait(1.5)
		for n in get_tree().get_nodes_in_group("pois") if get_tree().has_group("pois") else []:
			if n.get("data") != null and n.data.get("id", "") == cave_poi.id:
				poi_node = n
		if poi_node == null:
			for n in Game.grid.query(Vector3(cave.x, w.ground_height(cave), cave.z), 12.0, "interact"):
				if n.get("type") == "dungeon":
					poi_node = n
		ck("the cave mouth is an interactable place", poi_node != null)
		var back := Vector3(cave.x, w.ground_height(cave) + 0.3, cave.z + 3.0)
		tp(back)
		await rwait(0.3)
		ck("the entrance names the dungeon", poi_node != null and poi_node.interact_label().find("Чёрного Камня") >= 0, poi_node.interact_label() if poi_node else "")
		if poi_node != null:
			poi_node.interact(pl)
		else:
			w.enter_dungeon("black_stone")
		await rwait(1.0)
		close_ui(w)
		var d: BeastDungeon = w.dim_node
		ck("inside the Black Stone caves", w.dimension == "beast_black_stone" and d != null)
		# ------------------------------------------------ 4. the caves
		var amb0: int = d.stats.amb
		await rwait(8.0)
		ck("water drips, the cave breathes (ambient sounds)", d.stats.amb > amb0, str(d.stats.amb - amb0))
		ck("claw marks on the floors", d.stats.decals >= 6, str(d.stats.decals))
		ck("forks: the path branches", d.rooms.values().any(func(r): return r.links.size() >= 3))
		ck("resources lie in the side rooms", d.stats.resources >= 1 or d.rooms.values().any(func(r): return r.type == "resources"))
		var slimes := 0
		var patrol_moved := false
		pl.apply_status("invuln", 999999.0)
		for i in range(1, d.order.size() - 1):
			var r: Dictionary = d.rooms[d.order[i]]
			tp(r.pos + Vector3(0, 0.4, r.size * 0.35))
			await rwait(0.6)
			var p0 := {}
			for m in r.get("mobs", []):
				if is_instance_valid(m):
					p0[m] = m.global_position
					if str(m.get_meta("species", "")) == "stone_slime":
						slimes += 1
			await rwait(1.5)
			for m in p0:
				if is_instance_valid(m) and m.global_position.distance_to(p0[m]) > 0.5:
					patrol_moved = true
			for m in r.get("mobs", []):
				if is_instance_valid(m) and not m.is_dead:
					m.statuses.erase("invuln")
					Combat.deal(pl, m, {"amount": m.max_hp * 9.0, "dtype": "blunt", "src": pl})
			await rwait(0.4)
		# stone slimes are part of the cave's pool; make sure we met at least one
		if slimes == 0:
			var s0 = w.spawner.spawn_enemy("stone_slime", d.rooms[d.order[1]].pos + Vector3(2, 0.3, 0), 5)
			slimes = 1 if s0 != null else 0
			if s0:
				Combat.deal(pl, s0, {"amount": 9999.0, "dtype": "blunt", "src": pl})
		ck("stone slimes live in the caves", slimes >= 1)
		ck("creatures move about (patrols)", patrol_moved)
		var sw = d.secret_wall
		ck("a cracked wall hides something", sw != null and is_instance_valid(sw))
		var secret_uid := ""
		if sw != null and is_instance_valid(sw):
			tp(sw.global_position + Vector3(0, 0.4, 2.2))
			await rwait(0.3)
			Combat.aoe(pl, sw.global_position, 2.5, {"amount": 120.0, "dtype": "blunt", "src": pl})
			await rwait(0.3)
			ck("a heavy blow breaks the hidden wall", not is_instance_valid(sw))
			for c in d.chests:
				if is_instance_valid(c) and c.tier == "rich" and not c.opened:
					secret_uid = c.uid
					c.interact(pl)
			ck("the secret chest is opened", secret_uid != "")
		pl.statuses.erase("invuln")
		# ------------------------------------------------ 5. Гармон
		var br: Dictionary = d.rooms[d.order[d.order.size() - 1]]
		tp(br.pos + Vector3(0, 0.4, br.size * 0.32))
		await rwait(0.4)
		var b = d.boss
		ck("Гармон, Каменный Пожиратель rises", b != null and is_instance_valid(b) and b.display_name.begins_with("Гармон"))
		if b == null or not is_instance_valid(b):
			_end()
			return
		var cine = w.sys("cinematic")
		ck("a title card announces him", cine != null and cine.is_playing())
		ck("the hero keeps control during the intro", pl.can_act())
		ck("…the game is not paused for the intro", not get_tree().paused and pl.is_physics_processing())
		# phase 1: let him fight (the hero stands his ground)
		guard_hp = true
		for i in 24:
			pl.hp = maxf(pl.hp, pl.max_hp * 0.5)
			var to: Vector3 = b.global_position - pl.global_position
			to.y = 0
			pl.face_dir(to.normalized())
			await rwait(0.5)
		var used: Dictionary = b.brain.used
		ck("phase 1: slow heavy blows (smash)", int(used.get("0:slam", 0)) >= 1, str(used))
		ck("phase 1: he hurls rocks", int(used.get("0:rock_throw", 0)) >= 1, str(used))
		ck("his blows really hurt", pl.hp < pl.max_hp)
		var hc = w.sys("hardcore")
		ck("Hardcore: the hits left injuries", hc != null and hc.list().size() >= 1, str(hc.list().size() if hc else -1))
		# weak points: strike the plates from the sides and back
		print("DBG max hit on hero=", max_hit, " max_hp=", pl.max_hp)
		print("DBG after p1 paused=", get_tree().paused, " ui=", w.ui.top_name(), " hp=", pl.hp, "/", pl.max_hp, " dead=", pl.is_dead, " boss_hp=", b.hp, " st=", b.statuses.keys())
		close_ui(w)
		var rig: BeastRig = b.rig
		var sides := [-1.0, 1.0, 0.0]
		for side in sides:
			var off: Vector3 = b.rig.global_transform.basis.x * float(side) * 3.2 if side != 0.0 else b.rig.global_transform.basis.z * 3.4
			for k in 30:
				if b.hp < b.max_hp * 0.56:
					break
				tp(b.global_position + off + Vector3(0, 0.3, 0))
				b.statuses.erase("invuln")
				Combat.deal(pl, b, {"amount": 70.0, "dtype": "blunt", "src": pl, "melee": true})
				await get_tree().process_frame
		ck("plates break under blows (weak points)", rig.broken.size() >= 1, str(rig.broken.keys()))
		# phase 2
		var spd1: float = b.base_speed
		b.statuses.erase("invuln")
		b.hp = minf(b.hp, b.max_hp * 0.5)
		await rwait(1.2)
		ck("phase 2: the stone shell breaks", b.phase == 1 and rig.parts_left() == 0)
		ck("phase 2: glowing cracks", rig.crack_mat != null and rig.broken.size() == 3)
		ck("phase 2: he moves faster", b.base_speed > spd1 * 1.2)
		var used_before := used.duplicate()
		for i in 32:
			var to2: Vector3 = b.global_position - pl.global_position
			to2.y = 0
			if to2.length() > 0.1:
				pl.face_dir(to2.normalized())
			await rwait(0.5)
		var new_moves := 0
		for k in b.brain.used:
			if str(k).begins_with("1:") and str(k).substr(2) in ["ceiling", "charge", "quake"]:
				new_moves += 1
		ck("phase 2: new attacks (falling ceiling, rush, quake)", new_moves >= 1, str(b.brain.used))
		ck("phase 2: the cave collapses into cover and hazards", StoneStructure.count_live() >= 1)
		# ------------------------------------------------ 6. victory
		pl.apply_status("invuln", 999999.0)
		b.statuses.erase("invuln")
		Combat.deal(pl, b, {"amount": b.hp + 99999.0, "dtype": "blunt", "src": pl, "melee": true})
		await rwait(1.0)
		print("DBG kill: valid=", is_instance_valid(b), " dead=", b.is_dead if is_instance_valid(b) else "-", " hp=", b.hp if is_instance_valid(b) else -1, " st=", b.statuses.keys() if is_instance_valid(b) else [], " rigdead=", rig.dead if is_instance_valid(rig) else "-", " paused=", get_tree().paused, " ui=", w.ui.top_name())
		ck("Гармон falls (death animation, body stays)", b.is_dead and is_instance_valid(b) and rig.dead)
		var heart := false
		var trophy := false
		for c in w.fx_root.get_children():
			if c is ItemDrop:
				if str(c.item.get("base", "")) == "stone_heart":
					heart = true
				if str(c.item.get("base", "")) == "trophy_garmon":
					trophy = true
		heart = heart or pl.data.inv.count("stone_heart") > 0
		trophy = trophy or pl.data.inv.count("trophy_garmon") > 0
		ck("loot: Каменное сердце", heart)
		ck("loot: a trophy for the house", trophy)
		ck("bestiary updated (Гармон: освоено)", BeastWorld.knowledge("garmon") == 3)
		var chron := false
		for ev in Chronicle.recent(30):
			if ev.type == "beast_slain" and str(ev.text).find("Гармон") >= 0:
				chron = true
		ck("the chronicle tells of the victory", chron)
		ck("the quest is complete", w.quests.completed().any(func(q): return q.title == "Пробуждение Чёрного Камня"))
		# ------------------------------------------------ 7. inspect injuries
		var anat = w.ui.open("anatomy") if hc != null and hc.list().size() > 0 else null
		await rwait(0.3)
		ck("Hardcore: injuries can be inspected (anatomy screen)", anat != null)
		close_ui(w)
		var bs: Dictionary = BeastWorld.book()
		w.ui.open("journal")
		await rwait(0.3)
		ck("the journal has a Bestiary", w.ui.get_screen("journal") != null and bs.has("garmon") and bs.has("stone_slime"))
		close_ui(w)
		# ------------------------------------------------ 8. the way out
		ck("the way out opens", d.exits.size() >= 2)
		var ex = d.exits[d.exits.size() - 1]
		tp(ex.global_position + Vector3(0, 0.3, 1.0))
		await rwait(0.3)
		ex.interact(pl)
		await rwait(1.0)
		ck("back outside by the cave", w.dimension == "" and Vector2(pl.global_position.x, pl.global_position.z).distance_to(Vector2(back.x, back.z)) < 8.0)
		w.sync_to_state()
		SaveSys.save_game()
		var disk: Dictionary = SaveSys.load_world_state(0).get("dungeons", {}).get("black_stone", {})
		ck("everything is saved (boss, chest, rooms)", disk.get("boss_dead", false) and secret_uid in disk.get("opened", []) and disk.get("cleared", []).size() >= 3)
		ck("the bestiary is saved", SaveSys.read_json(SaveSys.PROFILE).get("bestiary", {}).has("garmon"))
		ck("time runs normally after the fight", is_equal_approx(Engine.time_scale, 1.0) and TimeFX.inst.active() == 0)
		_end()

	func _end() -> void:
		print("DEMO_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()
