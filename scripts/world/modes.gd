class_name GameModes
## Secondary modes sharing the same character/skills/items systems:
##  Arena   — compact slither-style run: start weak, eat orbs, outgrow rival
##            contenders; keeps 50% of mastery XP and arena tokens.
##  Trials  — 10 waves with champions using your real character; rewards at
##            waves 3/6/9 go to your inventory.
##  Chrono-dungeons — 3 rift rooms in a row; loot kept only on success.

static func arena_char() -> CharData:
	var c := CharData.new()
	var src: CharData = Profile.char
	c.name = src.name
	c.female = src.female
	c.appearance = src.appearance
	c.setup_class(src.class_id)
	for b in ItemDB.CLASS_KITS.get(src.class_id, []):
		var it := ItemDB.create(b, 0, 1, null, false)
		c.inv.add(it)
		if ItemDB.base(b).slot in ItemDB.SLOTS:
			c.inv.equip_item(it)
	return c

static func create(mode: String, world) -> Node:
	match mode:
		"arena":
			return ArenaMode.new(world)
		"trials":
			return TrialsMode.new(world)
		"dungeon":
			return DungeonMode.new(world)
	return Node.new()

class ArenaMode:
	extends Node
	var world
	var t := 0.0
	var wave := 0
	var wave_t := 20.0
	var bots: Array = []
	var kills := 0
	var ended := false
	var start_mastery := {}
	func _init(w) -> void:
		world = w
	func _ready() -> void:
		world.orbs.ambient_target = 180
		world.orbs.ambient_radius = 60.0
		start_mastery = world.player.data.mastery.duplicate(true)
		for i in 10:
			_spawn_bot()
		Events.actor_killed.connect(func(v, k):
			if k == world.player and is_instance_valid(v):
				kills += 1)
		Events.banner.emit("Арена", "Собирайте сферы, побеждайте соперников. Выживите как можно дольше!", Color(1.0, 0.8, 0.4))
	func _spawn_bot() -> void:
		var rec: Dictionary = world.legends.new_record(DBActors.rand_name(Profile.current_era, randf() < 0.35, Game.rng), {"level": 1 + randi() % 3})
		var a := randf() * TAU
		var p: Vector3 = world.dim_node.center + Vector3(cos(a), 0, sin(a)) * randf_range(15.0, 60.0)
		var n = world.spawner.spawn_bot(rec, p)
		n.archetype = ["aggressive", "hunter", "opportunist", "gatherer"][randi() % 4]
		bots.append(n)
	func _process(delta: float) -> void:
		if ended:
			return
		t += delta
		wave_t -= delta
		for b in bots.duplicate():
			if not is_instance_valid(b) or b.is_dead:
				bots.erase(b)
		if bots.size() < 10 and randf() < delta * 0.3:
			_spawn_bot()
		if wave_t <= 0.0:
			wave += 1
			wave_t = 40.0
			var ed: Dictionary = DBEras.era(Profile.current_era)
			for i in 2 + wave:
				var a := randf() * TAU
				var p: Vector3 = world.dim_node.center + Vector3(cos(a), 0, sin(a)) * 55.0
				var m = world.spawner.spawn_enemy(ed.enemies[randi() % ed.enemies.size()], p, mini(40, 1 + wave * 2))
				if m:
					m.add_aggro(world.player, 60.0)
			Events.notify.emit("Волна %d!" % wave, Color(1.0, 0.6, 0.4))
			if wave >= 10:
				Profile.unlock("arena_10")
	func objective_text() -> String:
		return "[color=#ffd36b]Арена[/color] · время %d:%02d · волна %d · побед %d · уровень %d" % [int(t) / 60, int(t) % 60, wave, kills, world.player.data.level]
	func on_player_died() -> void:
		ended = true
		var gained := 0
		var pm: Dictionary = Profile.char.mastery
		for cat in world.player.data.mastery:
			var d: Dictionary = world.player.data.mastery[cat]
			var total := 0
			for l in d.lvl:
				total += DBSkills.mastery_xp_needed(l)
			total += d.xp
			var before := 0
			if start_mastery.has(cat):
				for l in start_mastery[cat].lvl:
					before += DBSkills.mastery_xp_needed(l)
				before += start_mastery[cat].xp
			var g := int(maxi(0, total - before) * 0.5)
			if g > 0:
				Profile.char.add_mastery_xp(cat, g)
				gained += g
		var tokens := kills + wave * 3
		Profile.arena_tokens += tokens
		var score = kills * 10 + world.player.data.level * 20 + int(t)
		Profile.arena_best = maxi(Profile.arena_best, score)
		SaveSys.save_game()
		world.ui.open("death", {"text": "Арена окончена.\nВремя: %d:%02d · Волн: %d · Побед: %d · Уровень: %d\nОчки: %d (рекорд %d)\nПеренесено мастерства: %d опыта · жетонов арены: +%d" % [int(t) / 60, int(t) % 60, wave, kills, world.player.data.level, score, Profile.arena_best, gained, tokens],
			"respawn_text": "В главное меню", "menu": false, "respawn_cb": func(): Game.goto_menu()})

class TrialsMode:
	extends Node
	var world
	var wave := 0
	var rest := 5.0
	var current: Array = []
	var ended := false
	func _init(w) -> void:
		world = w
	func _process(delta: float) -> void:
		if ended:
			return
		var alive := 0
		for a in current:
			if is_instance_valid(a) and not a.is_dead:
				alive += 1
		if alive > 0:
			return
		if wave > 0 and current.size() > 0:
			current.clear()
			_reward()
			if wave >= 10:
				_finish(true)
				return
		rest -= delta
		if rest > 0.0:
			return
		rest = 6.0
		wave += 1
		var ed: Dictionary = DBEras.era(Profile.current_era)
		var lvl: int = world.spawner.level_near_player(wave / 3)
		if wave == 10:
			var bid: String = ed.bosses[randi() % ed.bosses.size()]
			var b = world.spawner.spawn_boss(bid, world.dim_node.center + Vector3(0, 0, -10), lvl + 1)
			if b:
				b.def = b.def.duplicate()
				b.def["reward"] = ""
				b.can_escape = false
				b.arena_center = world.dim_node.center
				current.append(b)
			Events.banner.emit("Финальная волна", "Чемпион эпохи!", Color(1.0, 0.4, 0.3))
			return
		for i in 3 + wave:
			var a := randf() * TAU
			var p: Vector3 = world.dim_node.center + Vector3(cos(a), 0, sin(a)) * 25.0
			var m = world.spawner.spawn_enemy(ed.enemies[randi() % ed.enemies.size()], p, lvl)
			if m:
				m.add_aggro(world.player, 99.0)
				current.append(m)
		if wave % 3 == 0:
			var c = world.spawner.spawn_enemy(ed.enemies[ed.enemies.size() - 1], world.dim_node.center + Vector3(0, 0, -15), lvl + 2)
			if c:
				c.elite = true
				c.display_name = "Чемпион: " + c.display_name
				c.max_hp *= 2.5
				c.hp = c.max_hp
				c.add_aggro(world.player, 99.0)
				current.append(c)
		Events.notify.emit("Волна %d/10" % wave, Color(1.0, 0.7, 0.4))
	func _reward() -> void:
		world.player.heal(world.player.max_hp * 0.3)
		if wave in [3, 6, 9]:
			var it := ItemDB.random_for_era(Profile.current_era, world.player.level, "elite" if wave < 9 else "boss")
			it.history.append("Награда за %d-ю волну Испытаний" % wave)
			world.player.data.inv.add(it)
			Events.banner.emit("Награда испытаний", ItemDB.display_name(it), ItemDB.rarity_color(it))
	func _finish(win: bool) -> void:
		ended = true
		SaveSys.save_game()
		world.ui.open("death", {"text": ("Испытания пройдены! Все 10 волн отбиты." if win else "Испытания окончены на волне %d." % wave) + "\nНаграды сохранены в инвентаре.",
			"respawn_text": "В главное меню", "menu": false, "respawn_cb": func(): Game.goto_menu()})
	func objective_text() -> String:
		return "[color=#ffd36b]Испытания[/color] · волна %d/10" % wave
	func on_player_died() -> void:
		_finish(false)

class DungeonMode:
	extends Node
	var world
	var room := 1
	var picked: Array = []
	var ended := false
	func _init(w) -> void:
		world = w
	func _ready() -> void:
		Events.item_picked.connect(func(a, it):
			if a == world.player:
				picked.append(it.uid))
		_room()
	func _room() -> void:
		var kinds := ["forgotten", "chronos", "mechanical", "warped_medieval", "future_rift"]
		if world.dim_node:
			world.dim_node.queue_free()
		var d := Dimension.new()
		world.add_child(d)
		d.build(kinds[(room + Profile.current_era) % kinds.size()], Game.rng.randi(), Vector3(0, 0, room * 400.0), Profile.current_era, {"expedition": true})
		world.dim_node = d
		world._apply_dim_env(d)
		world._teleport(world.player, d.player_spawn)
		Events.banner.emit("Хроноподземелье: зал %d/3" % room, d.title, Color(0.6, 0.85, 1.0))
	func on_exit() -> void:
		if room < 3:
			room += 1
			_room()
		else:
			ended = true
			SaveSys.save_game()
			Profile.milestone("rift_clear")
			world.ui.open("death", {"text": "Экспедиция завершена успешно! Вся добыча сохранена.", "respawn_text": "В главное меню", "menu": false, "respawn_cb": func(): Game.goto_menu()})
	func objective_text() -> String:
		return "[color=#9fd0ff]Хроноподземелье · зал %d/3[/color] · %s" % [room, world.dim_node.objective_text() if world.dim_node else ""]
	func on_player_died() -> void:
		ended = true
		var lost := 0
		for uid in picked:
			if not world.player.data.inv.remove(uid).is_empty():
				lost += 1
		SaveSys.save_game()
		world.ui.open("death", {"text": "Вы пали в хроноподземелье. Потеряно предметов: %d." % lost, "respawn_text": "В главное меню", "menu": false, "respawn_cb": func(): Game.goto_menu()})
