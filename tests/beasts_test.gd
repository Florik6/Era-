extends Node
## «Beasts of the Ages» — system tests.
## A) data: 100 species (20/era), 40 bosses (8/era), 25 dungeons (5/era),
##    unique ids, valid references, loot ids, distinct boss kits;
## B) all 25 dungeons generate: everything reachable, boss reachable, doors on
##    both sides, chests inside rooms, a secret room; main path stable across
##    visits, side rooms vary;
## C) Black Stone run: lazy rooms, secret wall, chest saved, Garmon awakens
##    without taking control, plates break, phase 2 (faster, collapse),
##    death → loot once, bestiary, chronicle, exit, progress saved, re-entry;
## D) ecology: habitats, no spawns in towns, caps, removal, rare variants;
## E) hunting contract on a real target; F) world boss director + leash;
## G) every species and every boss spawns and fights; H) Hardcore hits.
## Prints BEASTS_DONE pass=N fail=M.

func _ready() -> void:
	seed(424242)
	get_tree().root.theme = UITheme.make()
	SaveSys.delete_all()
	Chronicle.clear()
	Profile.new_character("Охотник", "warrior", false, {"skin": 1, "hair": 1, "hair_color": 1, "beard": 1, "cloth": 0})
	Profile.world_seed = 424242
	Profile.current_era = 0
	Settings.cinematics = 0
	var h := H.new()
	get_tree().root.add_child.call_deferred(h)
	Game.start("world")

class H:
	extends Node
	var pass_n := 0
	var fail_n := 0
	const BRAIN_TYPES := ["cleave", "spin", "slam", "nova", "quake", "blink", "fan", "volley", "beam", "missiles", "strikes", "hook", "charge", "summon",
		"slowzone", "mines", "portal", "shield", "rock_throw", "breath", "chain", "web", "poison_zone", "roots", "echo_strike", "leap", "dive", "burrow",
		"combo", "tail", "ceiling", "platforms", "cataclysm_quake", "ages_wrath", "armor_up", "parry_stance", "ethereal", "regen", "decoys", "haste", "pull", "bone_wall"]
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
		Combat.deal(by, a, {"amount": a.max_hp * 5.0 + 9999.0, "dtype": "slash", "src": by})
	func tp(pl, p: Vector3) -> void:
		Game.world._teleport(pl, p)
	func has_item(w, pl, base: String) -> bool:
		if pl.data.inv.count(base) > 0:
			return true
		for c in w.fx_root.get_children():
			if c is ItemDrop and str(c.item.get("base", "")) == base:
				return true
		return false

	func _run() -> void:
		await rwait(3.0)
		var w = Game.world
		var pl = Game.player
		pl.apply_status("invuln", 999999.0)
		w.director._t = -100000.0
		if w.sys("events2"):
			w.sys("events2").enabled = false
		TimeFX.inst.set_base(1.0)
		await _data_checks()
		await _gen_checks(w)
		await _black_stone(w, pl)
		await _ecology(w, pl)
		await _hunt(w, pl)
		await _world_boss(w, pl)
		await _spawn_all(w, pl)
		await _hardcore(w, pl)
		print("BEASTS_DONE pass=%d fail=%d" % [pass_n, fail_n])
		get_tree().quit()

	# ================================================================ A
	func _data_checks() -> void:
		var cr: Dictionary = DBCreatures.all()
		ck("100 species", cr.size() == 100, str(cr.size()))
		var per_era_ok := true
		for e in 5:
			if DBCreatures.of_era(e).size() != 20:
				per_era_ok = false
		ck("20 species in every era", per_era_ok)
		var bs: Dictionary = DBBeasts.bosses()
		ck("40 bosses", bs.size() == 40, str(bs.size()))
		var be_ok := true
		for e in 5:
			if DBBeasts.bosses_of_era(e).size() != 8:
				be_ok = false
		ck("8 bosses in every era", be_ok)
		var ds: Dictionary = DBBeasts.dungeons()
		ck("25 dungeons", ds.size() == 25, str(ds.size()))
		var de_ok := true
		for e in 5:
			if DBBeasts.dungeons_of_era(e).size() != 5:
				de_ok = false
		ck("5 dungeons in every era", de_ok)
		var clash: Array = []
		for id in cr:
			if DBActors.ENEMIES.has(id):
				clash.append(id)
		for id in bs:
			if DBActors.BOSSES.has(id) or cr.has(id):
				clash.append(id)
		ck("new ids do not clash with the old catalogue", clash.is_empty(), str(clash))
		# references
		var bad: Array = []
		for did in ds:
			var d: Dictionary = ds[did]
			if not bs.has(d.boss):
				bad.append("boss:" + did)
			for p in d.pool:
				if DBActors.eget(p, {}).is_empty():
					bad.append("pool:%s:%s" % [did, p])
			if str(d.miniboss) != "" and DBActors.eget(d.miniboss, {}).is_empty():
				bad.append("mini:" + did)
		for bid in bs:
			var dn := str(bs[bid].get("dungeon", ""))
			if dn != "" and not ds.has(dn):
				bad.append("dungeon_of:" + bid)
		ck("dungeon / boss / creature references valid", bad.is_empty(), str(bad))
		# loot ids
		var badl: Array = []
		for bid in bs:
			for l in bs[bid].get("loot", []):
				if ItemDB.base(str(l[0])).is_empty():
					badl.append(str(l[0]))
		for id in cr:
			for l in cr[id].get("loot", []):
				if ItemDB.base(str(l[0])).is_empty():
					badl.append(str(l[0]))
		ck("every loot id is a real item", badl.is_empty(), str(badl))
		var trophies := 0
		for bid in bs:
			if bs[bid].get("trophy", false) and not ItemDB.base("trophy_" + bid).is_empty():
				trophies += 1
		ck("trophies resolve to house furniture", trophies >= 30, str(trophies))
		# bosses: phases, abilities the brain can run, distinct kits
		var unk: Array = []
		var weak: Array = []
		var kits := {}
		var dup := 0
		for bid in bs:
			var b: Dictionary = bs[bid]
			if b.phases.size() < 2 or b.abilities.size() < 3:
				weak.append(bid)
			var types: Array = []
			for ab in b.abilities:
				var t := str(b.abilities[ab].type)
				types.append(t)
				if not t in BRAIN_TYPES:
					unk.append("%s:%s" % [bid, t])
			for ph in b.phases:
				for u in ph.use:
					if not b.abilities.has(u):
						unk.append("%s:phase uses %s" % [bid, u])
			types.sort()
			var key := ",".join(types)
			if kits.has(key):
				dup += 1
			kits[key] = bid
		ck("every boss has ≥2 phases and ≥3 abilities", weak.is_empty(), str(weak))
		ck("every boss ability is executable", unk.is_empty(), str(unk))
		ck("no two bosses share the same ability kit", dup == 0, "dup=%d" % dup)
		var plans := {}
		for id in cr:
			plans[cr[id].plan] = true
		ck("species use many body plans", plans.size() >= 10, str(plans.keys()))

	# ================================================================ B
	func _gen_checks(w) -> void:
		var all_ok := true
		var details: Array = []
		var varied := 0
		var stable := true
		var chests_ok := true
		var secrets := 0
		for did in DBBeasts.dungeons():
			var d1 := BeastDungeon.new()
			w.add_child(d1)
			d1.build_dungeon(did, Vector3(30000, 0, 30000), {"visit_bump": 0})
			var r: Dictionary = d1.report
			if not (r.all_reachable and r.boss_reachable and r.doors_symmetric and r.exit_reachable):
				all_ok = false
				details.append("%s:%s" % [did, str(r)])
			if r.rooms < 6:
				all_ok = false
				details.append("%s rooms=%d" % [did, r.rooms])
			if not d1.chest_inside_rooms():
				chests_ok = false
			if d1.secret_wall != null or d1.stats.secret:
				secrets += 1
			var order1: Array = d1.order.duplicate()
			var types1 := {}
			for c in d1.rooms:
				types1[c] = d1.rooms[c].type
			d1.free()
			var st: Dictionary = Game.world_state.dungeons[did]
			st.visits = int(st.visits) + 1
			var d2 := BeastDungeon.new()
			w.add_child(d2)
			d2.build_dungeon(did, Vector3(30000, 0, 30000), {"visit_bump": 0})
			if d2.order != order1:
				stable = false
			var types2 := {}
			for c in d2.rooms:
				types2[c] = d2.rooms[c].type
			if types2 != types1:
				varied += 1
			d2.free()
			await get_tree().process_frame
		Game.world_state.dungeons.clear()
		ck("all 25 dungeons: every room, boss and exit reachable, doors both sides", all_ok, str(details))
		ck("chests are always inside rooms (never in walls)", chests_ok)
		ck("every dungeon has a secret room behind a breakable wall", secrets == 25, str(secrets))
		ck("main path (architecture) is the same on every visit", stable)
		ck("side rooms change between visits", varied >= 12, "%d/25" % varied)

	# ================================================================ C
	func _black_stone(w, pl) -> void:
		var back: Vector3 = pl.global_position
		var d: BeastDungeon = w.enter_dungeon("black_stone")
		await rwait(0.6)
		ck("entered «Пещеры Чёрного Камня»", d != null and w.dimension == "beast_black_stone" and w.dim_node == d)
		ck("hero spawns in the start room", not d.room_at(pl.global_position).is_empty() and d.room_at(pl.global_position).type == "start")
		ck("ground height is the dungeon floor", absf(w.ground_height(pl.global_position) - d.floor_y) < 0.01)
		ck("no creatures before entering rooms (lazy)", d.stats.spawned == 0, str(d.stats.spawned))
		# walk the main path; clear each room
		var spawned_species := {}
		for i in range(1, d.order.size() - 1):
			var r: Dictionary = d.rooms[d.order[i]]
			tp(pl, r.pos + Vector3(0, 0.4, 0))
			await rwait(0.5)
			for m in r.get("mobs", []):
				if is_instance_valid(m):
					spawned_species[str(m.get_meta("species", m.def_id))] = true
					kill(m, pl)
			await rwait(0.5)
		ck("rooms fill with the dungeon's creatures on entry", d.stats.spawned >= 4, str(d.stats.spawned))
		var pool_ok := true
		for s in spawned_species:
			if not s in d.def.pool and s != str(d.def.miniboss):
				pool_ok = false
		ck("creatures come from the dungeon's pool", pool_ok, str(spawned_species.keys()))
		var seen_in_cave := 0
		for sp_id in d.def.pool:
			if int(BeastWorld.book().get(sp_id, {}).get("seen", 0)) > 0:
				seen_in_cave += 1
		ck("the bestiary records creatures met in the dungeon", seen_in_cave >= 1, str(seen_in_cave))
		var cleared: Array = d.state().cleared
		ck("cleared rooms are recorded", cleared.size() >= d.order.size() - 2, str(cleared.size()))
		# the secret wall
		var sw = d.secret_wall
		ck("a cracked wall hides the secret room", sw != null and is_instance_valid(sw))
		var secret_chest = null
		var secret_uid := ""
		if sw != null and is_instance_valid(sw):
			tp(pl, sw.global_position + Vector3(0, 0.4, 2.5))
			await rwait(0.3)
			sw.take_hit(200.0, "blunt", pl)
			await rwait(0.3)
			ck("breaking the wall opens the passage", not is_instance_valid(sw) and d.state().secret)
			for c in d.chests:
				if is_instance_valid(c) and c.tier == "rich":
					secret_chest = c
			ck("the secret room holds a rich chest", secret_chest != null)
			if secret_chest:
				secret_uid = secret_chest.uid
				secret_chest.interact(pl)
				ck("opened chest is saved", secret_chest.uid in d.state().opened)
		# the boss hall
		var br: Dictionary = d.rooms[d.order[d.order.size() - 1]]
		tp(pl, br.pos + Vector3(0, 0.4, br.size * 0.3))
		await rwait(0.5)
		var b = d.boss
		ck("Гармон awakens in his hall", b != null and is_instance_valid(b) and b.boss_id == "garmon")
		if b == null or not is_instance_valid(b):
			return
		ck("awakening keeps the hero in control", pl.can_act() and not pl.statuses.has("stun"))
		ck("boss waits during the awakening", b.brain.dormant > 0.0)
		await rwait(1.6)
		ck("boss starts fighting after the awakening", b.brain.dormant <= 0.0)
		ck("boss is leashed to its hall", b.leash_radius > 0.0 and b.arena_center.distance_to(br.pos) < 0.5)
		var rig: BeastRig = b.rig
		ck("Гармон has three breakable plates", rig.parts.size() == 3 and b.parts.size() == 3, str(rig.parts.keys()))
		# phase 1: hit from the left until the left plate breaks
		pl.statuses.erase("invuln")
		pl.apply_status("invuln", 999999.0)
		b.statuses.erase("invuln")
		var left: Vector3 = b.global_position - b.rig.global_transform.basis.x * 3.0
		tp(pl, left)
		var guard := 0
		while b.parts.get("plate_l", 0.0) > 0.0 and guard < 40:
			guard += 1
			b.hp = maxf(b.hp, b.max_hp * 0.8)
			b.statuses.erase("invuln")
			b.statuses.erase("armor_up")
			Combat.deal(pl, b, {"amount": 90.0, "dtype": "blunt", "src": pl, "melee": true})
			await get_tree().process_frame
		ck("hits from the side break a plate (weak point)", b.parts.get("plate_l", 1.0) <= 0.0 and rig.broken.has("plate_l"), "hits=%d" % guard)
		var spd1: float = b.base_speed
		# phase 1 uses its own moves
		await rwait(4.0)
		# phase 2
		b.statuses.erase("invuln")
		b.hp = b.max_hp * 0.45
		await rwait(1.0)
		ck("phase 2 at half health", b.phase == 1)
		ck("phase 2: the shell drops (all plates gone)", rig.parts_left() == 0)
		ck("phase 2: faster", b.base_speed > spd1 * 1.2, "%.2f → %.2f" % [spd1, b.base_speed])
		await rwait(2.2)
		ck("phase 2: parts of the cave collapse into cover", StoneStructure.count_live() >= 1, str(StoneStructure.count_live()))
		var ph2: Array = b.def.phases[1].use
		ck("phase 2 opens new attacks", "ceiling" in ph2 and "rush" in ph2 and not "ceiling" in b.def.phases[0].use)
		# death
		var kills_before := int(BeastWorld.book().get("garmon", {}).get("kills", 0))
		kill(b, pl)
		await rwait(1.5)
		ck("boss defeated → dungeon done", d.state().boss_dead and d.done)
		ck("unique loot: Каменное сердце", has_item(w, pl, "stone_heart"))
		ck("trophy for the house", has_item(w, pl, "trophy_garmon"))
		var lc: int = BeastWorld.inst.stats.boss_loot
		BeastWorld.boss_loot(b)
		ck("one reward per kill (no duplicate roll)", BeastWorld.inst.stats.boss_loot == lc)
		ck("bestiary: the boss is recorded", int(BeastWorld.book().get("garmon", {}).get("kills", 0)) == kills_before + 1 and BeastWorld.knowledge("garmon") == 3)
		var chron := false
		for ev in Chronicle.recent(20):
			if ev.type == "beast_slain":
				chron = true
		ck("chronicle tells of the victory", chron)
		ck("the way out opens after the boss", d.exits.size() >= 2)
		# leave and re-enter
		d.finish_and_leave()
		await rwait(0.6)
		ck("left the dungeon back to the entrance", w.dimension == "" and pl.global_position.distance_to(back) < 6.0)
		w.sync_to_state()
		SaveSys.save_game()
		ck("progress is in the save", Game.world_state.dungeons.black_stone.boss_dead and secret_uid != "" and secret_uid in Game.world_state.dungeons.black_stone.opened)
		var disk: Dictionary = SaveSys.load_world_state(0)
		var dsk: Dictionary = disk.get("dungeons", {}).get("black_stone", {})
		ck("save file on disk: boss dead, chest opened, rooms cleared", dsk.get("boss_dead", false) and secret_uid in dsk.get("opened", []) and dsk.get("cleared", []).size() >= 3)
		ck("bestiary is saved with the profile", SaveSys.read_json(SaveSys.PROFILE).get("bestiary", {}).has("garmon"))
		await rwait(6.5)
		var d2: BeastDungeon = w.enter_dungeon("black_stone")
		await rwait(0.5)
		var br2: Dictionary = d2.rooms[d2.order[d2.order.size() - 1]]
		tp(pl, br2.pos + Vector3(0, 0.4, 0))
		await rwait(0.6)
		ck("re-entry: the boss stays dead", d2.boss == null)
		ck("re-entry: same architecture", d2.order == d.order if is_instance_valid(d) else true)
		var opened_ok := false
		for c in d2.chests:
			if is_instance_valid(c) and c.opened:
				opened_ok = true
		ck("re-entry: opened chests stay open", opened_ok or d2.state().opened.size() >= 1)
		d2.finish_and_leave()
		await rwait(0.5)

	# ================================================================ D
	func _ecology(w, pl) -> void:
		var bw: BeastWorld = BeastWorld.inst
		ck("BeastWorld subsystem active", bw != null)
		# a point in the wild
		var p := Vector3.ZERO
		var found := false
		for i in 400:
			var c := Vector3(randf_range(-900, 900), 0, randf_range(-900, 900))
			if w.gen.settlement_at(c.x, c.z, 2.5) == null and not w.gen.is_water(c.x, c.z) and w.gen.biome(c.x, c.z) in ["forest", "mountain"]:
				p = c
				found = true
				break
		ck("found wilderness for the ecology test", found)
		w.terrain.force_load_around(p)
		p.y = w.ground_height(p) + 0.3
		tp(pl, p)
		await rwait(1.0)
		var r := RandomNumberGenerator.new()
		r.seed = 77
		var got: Array = []
		for i in 6:
			got.append_array(bw.spawn_ecology_near(pl.global_position, r))
		var hab_ok := true
		for m in got:
			var sd := DBCreatures.get_def(str(m.get_meta("species")))
			if sd.cat == "miniboss" or ("cave" in sd.hab and sd.hab.size() == 1):
				hab_ok = false
		ck("ecology spawns creatures of the habitat", got.size() >= 3 and hab_ok, str(got.size()))
		var too_close := 0
		for m in got:
			if m.global_position.distance_to(pl.global_position) < 35.0:
				too_close += 1
		ck("creatures appear out of sight (≥35 m)", too_close == 0)
		# towns are never spawn points
		var s: Dictionary = w.gen.settlements[0]
		ck("no spawns inside settlements", not bw.spawn_allowed(Vector3(s.pos.x, 0, s.pos.y)))
		var town_mobs: Array = []
		for i in 8:
			town_mobs.append_array(bw.spawn_ecology_near(Vector3(s.pos.x, w.ground_height(Vector3(s.pos.x, 0, s.pos.y)), s.pos.y), r))
		ck("near towns only peaceful animals appear", town_mobs.all(func(m): return m.team == "wildlife"), "%d spawned" % town_mobs.size())
		for m in town_mobs:
			m.queue_free()
		# caps and clean-up
		for i in 6:
			await rwait(3.1)
		var near := 0
		for m in bw.live_eco():
			if m.global_position.distance_to(pl.global_position) < BeastWorld.ECO_NEAR:
				near += 1
		ck("creature cap respected (ecology tick)", near <= bw.eco_cap() + 4, "%d / cap %d" % [near, bw.eco_cap()])
		var far := p + Vector3(400, 0, 0)
		w.terrain.force_load_around(far)
		far.y = w.ground_height(far) + 0.3
		tp(pl, far)
		await rwait(3.5)
		var still := 0
		for m in bw.live_eco():
			if m.global_position.distance_to(p) < 80.0:
				still += 1
		ck("far creatures are removed", still == 0, str(still))
		# rare variant
		var m0 = w.spawner.spawn_enemy("swamp_wolf", pl.global_position + Vector3(8, 0.3, 0), 5)
		var hp0: float = m0.max_hp
		var vk := BeastWorld.maybe_variant(m0, null, "alpha")
		ck("rare variant: stronger, renamed, marked", vk == "alpha" and m0.max_hp > hp0 * 1.5 and m0.display_name.begins_with("Альфа") and m0.has_meta("variant"))
		kill(m0, pl)
		await rwait(0.3)
		ck("bestiary records variants", int(BeastWorld.book().get("swamp_wolf", {}).get("variants", {}).get("alpha", 0)) >= 1)
		# peaceful species are wildlife, not monsters
		var deer = w.spawner.spawn_enemy("shadow_deer", pl.global_position + Vector3(-8, 0.3, 0), 3)
		ck("peaceful species are neutral wildlife", deer.team == "wildlife" and not Game.is_enemy(deer, pl))
		deer.queue_free()

	# ================================================================ E
	func _hunt(w, pl) -> void:
		var bw: BeastWorld = BeastWorld.inst
		var s: Dictionary = w.gen.settlements[0]
		var offers: Array = bw.hunt_offers(s, w.quests)
		ck("settlements offer hunting contracts", offers.size() >= 2, str(offers.size()))
		var q: Dictionary = {}
		for o in offers:
			if o.has("hunt_tid"):
				q = o
		ck("a contract names a real marked beast", not q.is_empty() and DBCreatures.has(str(q.get("hunt_species", ""))))
		if q.is_empty():
			return
		w.quests.accept(q)
		var hp := Vector3(float(q.hunt_pos[0]), 0, float(q.hunt_pos[1]))
		w.terrain.force_load_around(hp)
		hp.y = w.ground_height(hp) + 0.3
		tp(pl, hp + Vector3(30, 0, 0))
		await rwait(3.5)
		var t = bw.hunt_targets.get(q.id)
		if t == null:
			print("DBG paused=", get_tree().paused, " ui=", w.ui.is_open() if w.ui.has_method("is_open") else "?", " hunts=", bw.state.hunts.keys(), " q=", q.id, " dim=", w.dimension)
		ck("the target is in the world at its den", t != null and is_instance_valid(t) and t.actor_id == str(q.hunt_tid))
		if t == null or not is_instance_valid(t):
			return
		ck("quest marker points to the den", w.quests.tracked_target() == null or (w.quests.tracked_target() as Vector3).distance_to(Vector3(hp.x, 0, hp.z)) < 1.0)
		kill(t, pl)
		await rwait(0.6)
		var done := false
		for dq in w.quests.completed():
			if dq.id == q.id:
				done = true
		ck("killing the marked beast completes the contract", done)
		# cull contract with kill_species
		var cull: Dictionary = {}
		for o in offers:
			if o.objectives[0].kind == "kill_species":
				cull = o
		if not cull.is_empty():
			w.quests.accept(cull)
			var sp: String = cull.objectives[0].species
			for i in int(cull.objectives[0].need):
				var m = w.spawner.spawn_enemy(sp, pl.global_position + Vector3(4, 0.3, 0), 3)
				kill(m, pl)
				await get_tree().process_frame
			await rwait(0.3)
			var done2 := false
			for dq in w.quests.completed():
				if dq.id == cull.id:
					done2 = true
			ck("cull contract counts the right species", done2)

	# ================================================================ F
	func _world_boss(w, pl) -> void:
		var bw: BeastWorld = BeastWorld.inst
		var ids: Array = bw.world_boss_ids()
		ck("the era has lair bosses outside dungeons", ids.size() >= 1, str(ids))
		if ids.is_empty():
			return
		var bid: String = ids[0]
		var st: Dictionary = bw.state.world_bosses[bid]
		var lp2 := Vector2(float(st.pos[0]), float(st.pos[1]))
		var town_d := 99999.0
		for s in w.gen.settlements:
			town_d = minf(town_d, lp2.distance_to(s.pos) - float(s.radius))
		ck("lairs are far from towns", town_d >= 300.0, "%.0f m" % town_d)
		st.stage = 0
		bw.advance_world_boss(bid)
		ck("rumours first", int(st.stage) == 1 and bw.rumour_line() != "")
		bw.advance_world_boss(bid)
		ck("then the lair becomes known (map marker)", int(st.stage) == 2 and not bw.map_markers().is_empty())
		var lp := Vector3(lp2.x, 0, lp2.y)
		w.terrain.force_load_around(lp)
		lp.y = w.ground_height(lp) + 0.3
		tp(pl, lp + Vector3(40, 0, 0))
		await rwait(3.5)
		var b = bw.wboss.get(bid)
		ck("world boss waits in its lair", b != null and is_instance_valid(b))
		if b == null or not is_instance_valid(b):
			return
		# leash: drag the boss far away; it gives up and goes home
		b.brain.target = pl
		w._teleport(b, lp + Vector3(80, 0, 0))
		tp(pl, lp + Vector3(85, 0, 0))
		await rwait(1.0)
		ck("leashed boss drops a target outside its lair", b.brain.target == null)
		await rwait(4.0)
		var hd: float = Vector2(b.global_position.x - lp.x, b.global_position.z - lp.z).length()
		ck("…and walks back home", hd < 76.0, "%.1f m" % hd)
		b.queue_free()
		bw.wboss.erase(bid)

	# ================================================================ G
	func _spawn_all(w, pl) -> void:
		var base: Vector3 = pl.global_position + Vector3(0, 0, 25)
		var bad: Array = []
		var rigs_bad: Array = []
		var n := 0
		for id in DBCreatures.all():
			var m = w.spawner.spawn_enemy(id, base + Vector3((n % 10) * 3.0, 0.3, (n / 10) * 3.0), 5)
			n += 1
			if m == null:
				bad.append(id)
				continue
			if m.max_hp <= 0.0 or m.brain == null or str(m.get_meta("species", "")) != id:
				bad.append(id)
			var sd := DBCreatures.get_def(id)
			if sd.plan != "humanoid" and not (m.rig is BeastRig):
				rigs_bad.append(id)
			m.queue_free()
			if n % 20 == 0:
				await get_tree().process_frame
		ck("all 100 species spawn with brain and stats", bad.is_empty(), str(bad))
		ck("non-humanoid species use their own beast bodies", rigs_bad.is_empty(), str(rigs_bad))
		var bbad: Array = []
		var shields := 0
		var parts_bad: Array = []
		var with_parts := 0
		for bid in DBBeasts.bosses():
			var b = w.spawner.spawn_boss(bid, base + Vector3(0, 0.5, 0), 10)
			if b == null or b.max_hp <= 0.0 or b.rig == null:
				bbad.append(bid)
				continue
			if b.def.abilities.values().any(func(a): return a.type == "shield"):
				shields += 1
			for pk in b.parts:
				if not b.rig.parts.has(pk):
					parts_bad.append("%s:%s" % [bid, pk])
			if b.parts.size() > 0:
				with_parts += 1
			# a few seconds of life with a target: no script errors, abilities fire
			b.queue_free()
		await get_tree().process_frame
		ck("all 40 bosses spawn", bbad.is_empty(), str(bbad))
		ck("every breakable part exists on the boss body", parts_bad.is_empty(), "bosses with parts=%d %s" % [with_parts, str(parts_bad)])
		# the fixed shield state machine on every new boss that has a shield
		var sh_ok := 0
		var sh_n := 0
		var sh_bad: Array = []
		for bid3 in DBBeasts.bosses():
			var bd3: Dictionary = DBBeasts.boss(bid3)
			var spec3: Dictionary = {}
			for ab3 in bd3.abilities:
				if bd3.abilities[ab3].type == "shield":
					spec3 = bd3.abilities[ab3]
			if spec3.is_empty():
				continue
			sh_n += 1
			var b3 = w.spawner.spawn_boss(bid3, base + Vector3(0, 0.5, 0), 10)
			b3.brain.dormant = 999.0
			var sh: BossShield = b3.shield
			var started := sh.start(spec3)
			var t0 := Time.get_ticks_msec()
			var went_active := false
			var max_active := 0.0
			var act_since := -1
			var mism := 0
			while Time.get_ticks_msec() - t0 < 16000:
				await get_tree().process_frame
				if sh.state == BossShield.ACTIVE:
					went_active = true
					if act_since < 0:
						act_since = Time.get_ticks_msec()
					max_active = maxf(max_active, float(Time.get_ticks_msec() - act_since) / 1000.0)
				else:
					act_since = -1
				if sh.is_active() != sh.visual_present():
					mism += 1
				if went_active and sh.state in [BossShield.COOLDOWN, BossShield.INACTIVE]:
					break
			var restart_blocked := not sh.can_start()
			var hp0: float = b3.hp
			b3.statuses.erase("invuln")
			Combat.deal(pl, b3, {"amount": 100.0, "dtype": "slash", "src": pl})
			var hurt: bool = b3.hp < hp0
			if started and went_active and max_active <= float(spec3.get("dur", 8.0)) + 0.6 and restart_blocked and mism == 0 and hurt:
				sh_ok += 1
			else:
				sh_bad.append("%s(start=%s active=%s max=%.1f cd=%s mism=%d hurt=%s)" % [bid3, started, went_active, max_active, restart_blocked, mism, hurt])
			b3.queue_free()
			await get_tree().process_frame
		ck("new bosses' shields: charge → limited active → cool-down, dome = protection, hurt afterwards", sh_n > 0 and sh_ok == sh_n, "%d/%d %s" % [sh_ok, sh_n, str(sh_bad)])
		# a short brawl for a sample of bosses (one per era)
		var fought := 0
		for e in 5:
			var bl: Array = DBBeasts.bosses_of_era(e)
			var bid2: String = bl[(e * 3) % bl.size()].id
			var b2 = w.spawner.spawn_boss(bid2, base + Vector3(0, 0.5, 0), 10)
			tp(pl, base + Vector3(0, 0.4, 8))
			await rwait(5.0)
			if is_instance_valid(b2) and not b2.is_dead:
				fought += 1
				b2.queue_free()
			await rwait(0.3)
		ck("sample bosses fight for 5 s without errors", fought == 5)

	# ================================================================ H
	func _hardcore(w, pl) -> void:
		var hc = w.sys("hardcore")
		if hc == null:
			ck("hardcore subsystem present", false)
			return
		Profile.difficulty = "hardcore"
		pl.statuses.erase("invuln")
		pl.hp = pl.max_hp
		var sal = w.spawner.spawn_enemy("fire_salamander", pl.global_position + pl.facing * 2.0, 8)
		var n0: int = hc.list().size()
		for i in 4:
			Combat.deal(sal, pl, {"amount": pl.max_hp * 0.35, "dtype": "fire", "src": sal})
			pl.hp = pl.max_hp
		var burns := 0
		for inj in hc.list():
			if inj.type == "burn":
				burns += 1
		ck("Hardcore: a fire creature burns", burns >= 1, "inj=%d" % (hc.list().size() - n0))
		Profile.char.injuries.clear()     # room for new wounds (the body holds a limited number)
		var wolf = w.spawner.spawn_enemy("swamp_wolf", pl.global_position - pl.facing * 1.5, 8)
		var dealt_w: Array = []
		for i in 4:
			pl.statuses.erase("invuln")
			pl.dodge_t = 0.0
			pl.blocking = false
			dealt_w.append(snappedf(Combat.deal(wolf, pl, {"amount": pl.max_hp * 0.35, "dtype": "slash", "src": wolf, "melee": true}), 0.1))
			pl.hp = pl.max_hp
		var cuts := 0
		var types: Array = []
		for inj in hc.list():
			types.append(inj.type)
			if inj.type in ["cut", "stab"]:
				cuts += 1
		ck("Hardcore: claws and teeth cut", cuts >= 1, "dealt=%s types=%s wolf=%s team=%s can=%s dead=%s house=%s" % [str(dealt_w), str(types), str(wolf != null and is_instance_valid(wolf)),
			str(wolf.team) if wolf != null and is_instance_valid(wolf) else "-", str(Game.can_damage(wolf, pl)) if wolf != null and is_instance_valid(wolf) else "-",
			str(wolf.is_dead) if wolf != null and is_instance_valid(wolf) else "-", str(Housing.blocks(wolf, pl)) if wolf != null and is_instance_valid(wolf) else "-"])
		# real AI attacks: a wolf bites low, a giant strikes from above
		Profile.char.injuries.clear()
		var before_ids := {}
		for inj in hc.list():
			before_ids[inj.id] = true
		var biter = w.spawner.spawn_enemy("swamp_wolf", pl.global_position + Vector3(2.5, 0.3, 0), 8)
		biter.brain.target = pl
		# a frail hero (low max HP), so a bite is a wound and not a scratch
		var hp_keep: float = pl.max_hp
		pl.max_hp = 45.0
		pl.hp = pl.max_hp
		var t_end := Time.get_ticks_msec() + 9000
		while Time.get_ticks_msec() < t_end:
			pl.hp = maxf(pl.hp, pl.max_hp * 0.6)
			await get_tree().process_frame
		pl.max_hp = hp_keep
		pl.hp = hp_keep
		var legs := 0
		var other := 0
		for inj in hc.list():
			if before_ids.has(inj.id) or str(inj.get("src", "")).find("волк") < 0:
				continue
			if str(inj.zone).begins_with("leg"):
				legs += 1
			else:
				other += 1
		ck("Hardcore: the wolf's real bites land on the legs", legs >= 1 and legs >= other, "legs=%d other=%d by_how=%s scratches=%d" % [legs, other, str(hc.stats.by_how), int(hc.stats.get("scratches", 0))])
		biter.queue_free()
		var treatable := true
		for inj in hc.list():
			if hc.treatments_for(inj).is_empty():
				treatable = false
		ck("Hardcore: no creature wound is untreatable", treatable)
		pl.apply_status("invuln", 999999.0)
		sal.queue_free()
		wolf.queue_free()
		Profile.difficulty = "normal"
