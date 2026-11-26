class_name Dimension
extends Node3D
## Pocket spaces built far from the main map: rift expeditions (Forgotten
## Dimension, Void of Chronos, Warped Middle Ages, Mechanical Dimension,
## Future Rift), small dungeons, boss arenas (Archmage's distorted realm),
## the Chronos Trial, and the arenas of the Arena/Trials/Dungeon modes.
## Real geometry, real enemies, traps, chests, objectives and an exit.

var kind := ""
var center := Vector3.ZERO
var radius := 40.0
var floor_y := 0.0
var title := ""
var subtitle := ""
var sky_top := Color(0.2, 0.1, 0.3)
var sky_horizon := Color(0.5, 0.3, 0.6)
var light := Color(1, 1, 1)
var player_spawn := Vector3.ZERO
var expedition := false
var era := 0
var opts := {}
var stage := 0
var stage_enemies: Array = []
var done := false
var _check_t := 0.0
var _trap_nodes: Array = []
var _theme := {}
var anchors: Array = []
var _retreat: Node3D = null

## Echo bosses: a rift copies a boss of its theme. Echoes never touch the
## real boss's world state (lair, escapes, unique reward).
const ECHO_BOSS := {"forgotten": "necro_lord", "warped_medieval": "executioner", "mechanical": "steam_colossus",
	"chronos": "chrono_devourer", "future_rift": "rift_archon"}

const THEMES := {
	"forgotten": {"title": "Забытое измерение", "sub": "Серые руины мира, которого никогда не было.", "floor": Color(0.35, 0.35, 0.4), "top": Color(0.15, 0.15, 0.22), "hor": Color(0.45, 0.45, 0.55), "light": Color(0.8, 0.85, 1.0), "obst": "ruin", "enemies": ["wraith", "skeleton", "cursed_warrior"], "trap": "dark"},
	"chronos": {"title": "Пустота Хроноса", "sub": "Здесь время течёт неправильно.", "floor": Color(0.2, 0.35, 0.4), "top": Color(0.02, 0.08, 0.12), "hor": Color(0.2, 0.7, 0.7), "light": Color(0.6, 1.0, 0.95), "obst": "crystal", "enemies": ["chrono_anomaly", "chrono_soldier"], "trap": "timeslow"},
	"warped_medieval": {"title": "Искажённое Средневековье", "sub": "Эхо прошлого, вывернутое наизнанку.", "floor": Color(0.35, 0.25, 0.35), "top": Color(0.25, 0.05, 0.2), "hor": Color(0.7, 0.35, 0.5), "light": Color(1.0, 0.7, 0.8), "obst": "ruin", "enemies": ["cursed_warrior", "knight_renegade", "dark_mage", "wraith"], "trap": "fire"},
	"mechanical": {"title": "Механическое измерение", "sub": "Бесконечные шестерни и пар.", "floor": Color(0.4, 0.32, 0.22), "top": Color(0.2, 0.15, 0.1), "hor": Color(0.7, 0.5, 0.3), "light": Color(1.0, 0.85, 0.6), "obst": "gear", "enemies": ["automaton", "steam_spider", "clockwork_golem", "combat_drone"], "trap": "electric"},
	"future_rift": {"title": "Разлом будущего", "sub": "Пространство, собранное из обломков завтрашнего дня.", "floor": Color(0.15, 0.15, 0.25), "top": Color(0.05, 0.02, 0.15), "hor": Color(0.6, 0.2, 0.7), "light": Color(0.8, 0.6, 1.0), "obst": "neon", "enemies": ["combat_robot", "android", "synthetic", "chrono_anomaly"], "trap": "timeslow"},
	"distorted": {"title": "Искажённое измерение", "sub": "Архимаг перенёс битву в своё царство!", "floor": Color(0.3, 0.15, 0.4), "top": Color(0.1, 0.0, 0.2), "hor": Color(0.6, 0.2, 0.8), "light": Color(0.9, 0.6, 1.0), "obst": "crystal", "enemies": ["wraith"], "trap": "dark"},
	"dungeon": {"title": "Подземелье", "sub": "Сырые залы, полные опасностей и сокровищ.", "floor": Color(0.3, 0.28, 0.26), "top": Color(0.05, 0.05, 0.06), "hor": Color(0.25, 0.22, 0.2), "light": Color(1.0, 0.8, 0.6), "obst": "ruin", "enemies": [], "trap": "fire"},
	"chronos_trial": {"title": "Суд Хроноса", "sub": "Докажите, что достойны новой эпохи.", "floor": Color(0.55, 0.48, 0.3), "top": Color(0.15, 0.1, 0.02), "hor": Color(0.9, 0.75, 0.4), "light": Color(1.0, 0.9, 0.7), "obst": "pillar", "enemies": [], "trap": "timeslow"},
	"arena": {"title": "Арена", "sub": "Собирайте сферы, растите в силе, побеждайте соперников.", "floor": Color(0.5, 0.42, 0.3), "top": Color(0.3, 0.45, 0.75), "hor": Color(0.85, 0.8, 0.7), "light": Color(1.0, 0.95, 0.85), "obst": "pillar", "enemies": [], "trap": ""},
	"trial_arena": {"title": "Испытания", "sub": "Волна за волной.", "floor": Color(0.45, 0.4, 0.38), "top": Color(0.2, 0.15, 0.25), "hor": Color(0.7, 0.55, 0.5), "light": Color(1.0, 0.85, 0.75), "obst": "pillar", "enemies": [], "trap": ""},
	"chronos_void": {"title": "Хроноподземелье", "sub": "Экспедиция сквозь разорванное время.", "floor": Color(0.22, 0.3, 0.38), "top": Color(0.03, 0.05, 0.1), "hor": Color(0.3, 0.55, 0.7), "light": Color(0.75, 0.9, 1.0), "obst": "crystal", "enemies": ["chrono_anomaly", "chrono_soldier", "wraith"], "trap": "timeslow"},
}

func build(k: String, seed: int, offset: Vector3, era_i: int, o: Dictionary = {}) -> void:
	kind = k
	era = era_i
	opts = o
	_theme = THEMES.get(k, THEMES.forgotten).duplicate(true)
	center = offset
	floor_y = offset.y
	title = _theme.title
	subtitle = _theme.sub
	sky_top = _theme.top
	sky_horizon = _theme.hor
	light = _theme.light
	expedition = o.get("expedition", false)
	radius = {"arena": 70.0, "trial_arena": 38.0, "dungeon": 26.0, "chronos_trial": 34.0, "distorted": 30.0, "chronos_void": 36.0}.get(k, 34.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	position = Vector3.ZERO
	_build_floor()
	_build_obstacles(rng)
	player_spawn = center + Vector3(0, 0.3, radius * 0.7)
	if k == "dungeon" or k.begins_with("chronos_void"):
		_theme.enemies = DBEras.era(era).night_enemies + DBEras.era(era).enemies if _theme.enemies.is_empty() else _theme.enemies
	if expedition or k == "chronos_trial":
		_start_stage(1)
	if expedition:
		_spawn_chests(rng, 2 if k != "dungeon" else 2)
		_spawn_traps(rng)
		_retreat = DimensionExit.new()
		_retreat.dim = self
		_retreat.retreat = true
		add_child(_retreat)
		_retreat.global_position = center + Vector3(3.5, 0, radius * 0.7 + 2.0)
	if k == "distorted" or o.has("boss"):
		_spawn_traps(rng)
		for i in 2:
			var m = Game.world.spawner.spawn_enemy(_theme.enemies[0] if not _theme.enemies.is_empty() else "wraith", center + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12)))
			if m:
				m.team = "boss"
				stage_enemies.append(m)

func _build_floor() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	add_child(sb)
	sb.global_position = center
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius + 6.0
	cyl.height = 2.0
	cs.shape = cyl
	cs.position.y = -1.0
	sb.add_child(cs)
	MeshLib.part(sb, MeshLib.cyl(radius + 6.0, radius + 4.0, 2.0, 40), MeshLib.mat(_theme.floor), Vector3(0, -1.0, 0))
	# glowing rim and inner pattern
	MeshLib.part(sb, MeshLib.torus(radius - 0.5, radius + 0.3), MeshLib.glow(_theme.light.lerp(_theme.hor, 0.5), 1.5), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE, false)
	MeshLib.part(sb, MeshLib.torus(radius * 0.3, radius * 0.32), MeshLib.mat(_theme.floor.lightened(0.2)), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	# invisible boundary wall
	for i in 24:
		var a := TAU * i / 24.0
		var w := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(radius * TAU / 24.0 + 1.0, 8.0, 1.0)
		w.shape = bx
		w.position = Vector3(cos(a) * (radius + 1.5), 4.0, sin(a) * (radius + 1.5))
		w.rotation.y = -a + PI / 2
		sb.add_child(w)
	var amb := OmniLight3D.new()
	amb.light_color = _theme.light
	amb.light_energy = 1.2
	amb.omni_range = radius * 1.5
	amb.position = Vector3(0, 12, 0)
	amb.shadow_enabled = false
	sb.add_child(amb)

func _build_obstacles(rng: RandomNumberGenerator) -> void:
	var n := int(radius / 3.5)
	var st = _theme.obst
	for i in n:
		var a := rng.randf() * TAU
		var r := rng.randf_range(radius * 0.25, radius * 0.9)
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		if p.distance_to(center + Vector3(0, 0, radius * 0.7)) < 5.0:
			continue
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		add_child(sb)
		sb.global_position = p
		var cs := CollisionShape3D.new()
		var h := rng.randf_range(2.0, 5.0)
		var bx := BoxShape3D.new()
		match st:
			"crystal":
				bx.size = Vector3(1.4, h, 1.4)
				MeshLib.part(sb, MeshLib.prism(Vector3(1.6, h, 1.6)), MeshLib.mat(_theme.light.lerp(Color(1, 1, 1), 0.2), 0.3, 0.2, 1.0), Vector3(0, h * 0.5, 0), Vector3(0, rng.randf() * 90.0, rng.randf_range(-10, 10)))
			"gear":
				bx.size = Vector3(2.4, 2.4, 0.6)
				MeshLib.part(sb, MeshLib.cyl(1.4, 1.4, 0.5, 12), MeshLib.mat(Color(0.6, 0.45, 0.25), 0.8, 0.35), Vector3(0, 1.4, 0), Vector3(90, 0, 0))
				MeshLib.part(sb, MeshLib.cyl(0.3, 0.3, 0.7, 8), MeshLib.mat(Color(0.3, 0.3, 0.3), 0.8, 0.3), Vector3(0, 1.4, 0), Vector3(90, 0, 0))
				h = 2.8
			"neon":
				bx.size = Vector3(1.0, h, 1.0)
				MeshLib.part(sb, MeshLib.box(Vector3(1.0, h, 1.0)), MeshLib.mat(Color(0.12, 0.12, 0.18), 0.6, 0.3), Vector3(0, h * 0.5, 0))
				MeshLib.part(sb, MeshLib.box(Vector3(1.05, 0.12, 1.05)), MeshLib.glow(Color(0.9, 0.3, 1.0), 3.0), Vector3(0, h * 0.8, 0))
			"pillar":
				bx.size = Vector3(1.6, h + 1.0, 1.6)
				MeshLib.part(sb, MeshLib.cyl(0.75, 0.85, h + 1.0, 10), MeshLib.mat(_theme.floor.lightened(0.25)), Vector3(0, (h + 1.0) * 0.5, 0))
			_:
				bx.size = Vector3(2.0, h, 1.2)
				MeshLib.part(sb, MeshLib.box(Vector3(2.0, h, 1.2)), MeshLib.mat(_theme.floor.lightened(0.15)), Vector3(0, h * 0.5, 0), Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
		cs.shape = bx
		cs.position.y = bx.size.y * 0.5
		sb.add_child(cs)
		sb.rotation.y = rng.randf() * TAU

func _spawn_chests(rng: RandomNumberGenerator, n: int) -> void:
	if not ResourceLoader.exists("res://scripts/world/chest.gd"):
		return
	for i in n:
		var ch = load("res://scripts/world/chest.gd").new()
		ch.set("tier", "rich")
		ch.set("lvl", Game.world.spawner.level_near_player(1))
		add_child(ch)
		var a := rng.randf() * TAU
		ch.global_position = center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(radius * 0.4, radius * 0.8)

func _spawn_traps(rng: RandomNumberGenerator) -> void:
	var tk: String = _theme.trap
	if tk == "":
		return
	for i in 4:
		var a := rng.randf() * TAU
		var p := center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(6.0, radius * 0.8)
		var lvl = Game.world.spawner.level_near_player(0)
		var z: Zone
		if tk == "timeslow":
			z = Zone.create("timeslow", null, p, 3.5, 9999.0, {}, {"hostile_all": true})
		else:
			z = Zone.create(tk, null, p, 2.2, 9999.0, {"amount": 4.0 + lvl * 1.5, "dtype": "fire" if tk == "fire" else ("lightning" if tk == "electric" else "dark")}, {"hostile_all": true})
		if z:
			z.reparent(self)
			_trap_nodes.append(z)

func _process(delta: float) -> void:
	# spatial traps drift (future/chronos rifts)
	if kind in ["future_rift", "chronos", "chronos_void"]:
		for z in _trap_nodes:
			if is_instance_valid(z):
				var off: Vector3 = z.global_position - center
				z.global_position = center + off.rotated(Vector3.UP, delta * 0.15)
	_check_t += delta
	if _check_t < 0.5 or done:
		return
	_check_t = 0.0
	if stage > 0 and (expedition or kind == "chronos_trial"):
		var alive := 0
		for a in stage_enemies:
			if is_instance_valid(a) and not a.is_dead:
				alive += 1
		if alive == 0 and stage_enemies.size() > 0 and not (stage == 2 and not anchors.is_empty()):
			_next_stage()

func _enemy_pool() -> Array:
	var pool: Array = _theme.enemies.duplicate()
	if pool.is_empty():
		pool = DBEras.era(era).enemies.duplicate()
	return pool

func _start_stage(s: int) -> void:
	stage = s
	stage_enemies.clear()
	var w = Game.world
	var lvl: int = w.spawner.level_near_player(0)
	if kind == "chronos_trial":
		var ed: Dictionary = DBEras.era(era)
		match s:
			1:
				for i in 7:
					var melee: Array = ed.enemies.filter(func(x): return DBActors.ENEMIES[x].ai in ["melee", "beast"])
					_spawn(melee[i % melee.size()] if not melee.is_empty() else ed.enemies[0], lvl)
				Events.banner.emit("Суд Хроноса: этап 1", "Сила клинка", Color(1.0, 0.85, 0.3))
			2:
				for i in 5:
					var ranged: Array = ed.enemies.filter(func(x): return DBActors.ENEMIES[x].ai in ["ranged", "caster"])
					_spawn(ranged[i % ranged.size()] if not ranged.is_empty() else ed.night_enemies[0], lvl + 1)
				for i in 2:
					var zp := center + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
					var z := Zone.create("timeslow", null, zp, 4.0, 9999.0, {}, {"hostile_all": true})
					z.reparent(self)
				Events.banner.emit("Суд Хроноса: этап 2", "Время против вас: используйте рывки и магию", Color(1.0, 0.85, 0.3))
			3:
				var b: Boss = w.spawner.spawn_boss("chronos_avatar", center + Vector3(0, 0, -12), lvl + 2)
				if b:
					b.max_hp *= 1.0 + era * 2.5
					b.hp = b.max_hp
					b.base_dmg *= 1.0 + era * 1.4
					b.can_escape = false
					b.arena_center = center
					stage_enemies.append(b)
				Events.banner.emit("Суд Хроноса: финал", "Аватар Хроноса", Color(1.0, 0.85, 0.3))
				Audio.play_music("boss")
		return
	var pool := _enemy_pool()
	if s == 1:
		for i in 5 + era:
			_spawn(pool[randi() % pool.size()], lvl)
		Events.notify.emit("Этап 1: уничтожьте стражей разлома", Color(0.8, 0.6, 1.0))
	elif s == 2 and ECHO_BOSS.has(kind):
		# close three anchors: stand in each circle (or strike the crystal) while defenders pour out
		for i in 3:
			var a := TAU * i / 3.0 + 0.6
			var an := RiftAnchor.new()
			an.dim = self
			an.col = _theme.light.lerp(Color(0.8, 0.4, 1.0), 0.5)
			add_child(an)
			an.global_position = center + Vector3(cos(a), 0, sin(a)) * radius * 0.55
			anchors.append(an)
		Events.banner.emit("Якоря разлома", "Закройте три якоря: стойте в круге или бейте кристалл.", Color(0.8, 0.5, 1.0))
	elif s == 3 and ECHO_BOSS.has(kind):
		var bid: String = ECHO_BOSS[kind]
		var b: Boss = w.spawner.spawn_boss(bid, center + Vector3(0, 0, -radius * 0.35), lvl + 1)
		if b:
			b.set_meta("rift_echo", true)
			b.display_name = "Эхо разлома: " + String(DBActors.BOSSES[bid].name)
			w.spawner.normalize_to_era(b, int(DBActors.BOSSES[bid].get("era", era)))
			b.max_hp *= 0.6
			b.hp = b.max_hp
			b.can_escape = false
			b.arena_center = center
			b.add_aggro(Game.player, 80.0)
			stage_enemies.append(b)
			Events.boss_engaged.emit(b)
			Audio.play_music("boss")
			Events.banner.emit(b.display_name, "Сердце разлома приняло облик чудовища.", Color(1.0, 0.45, 0.6))
		else:
			_spawn_guardian(pool, lvl)
	else:
		_spawn_guardian(pool, lvl)

func _spawn_guardian(pool: Array, lvl: int) -> void:
	var g = _spawn(pool[pool.size() - 1], lvl + 3)
	if g:
		g.elite = true
		g.display_name = "Хранитель: " + g.display_name
		g.max_hp *= 3.0
		g.hp = g.max_hp
		g.base_dmg *= 1.5
	Events.banner.emit("Хранитель разлома", "Победите стража, чтобы открыть выход.", Color(0.8, 0.5, 1.0))

## Called by an anchor when it closes; defenders it spawned keep fighting.
func on_anchor_closed(an) -> void:
	anchors.erase(an)
	VFX.ring(an.global_position, 6.0, Color(0.9, 0.7, 1.0), 0.8)
	Audio.play_sfx("capture", an.global_position)
	if anchors.is_empty():
		Events.notify.emit("Все якоря закрыты!", Color(0.9, 0.7, 1.0))
		_start_stage(3)
	else:
		Events.notify.emit("Якорь закрыт. Осталось: %d" % anchors.size(), Color(0.9, 0.7, 1.0))

func _spawn(id: String, lvl: int):
	var a := randf() * TAU
	var p := center + Vector3(cos(a), 0, sin(a)) * randf_range(radius * 0.2, radius * 0.6)
	var m = Game.world.spawner.spawn_enemy(id, p, lvl)
	if m:
		Game.world.spawner.normalize_to_era(m, Game.world.spawner.enemy_era(id))
		m.team = "monster"
		if m is Monster:
			m.home = p
			m.leash = radius * 2.0
		m.add_aggro(Game.player, 60.0)
		stage_enemies.append(m)
	return m

func _next_stage() -> void:
	if kind == "chronos_trial":
		if stage < 3:
			_start_stage(stage + 1)
		else:
			_trial_victory()
		return
	if stage == 1:
		_start_stage(2)
	elif stage == 2 and ECHO_BOSS.has(kind):
		return   # anchors drive stage 2 → 3
	else:
		_complete()

func _complete() -> void:
	done = true
	stage_enemies.clear()
	_open_exit()
	var w = Game.world
	if expedition:
		var it := ItemDB.random_for_era(era, w.player.level, "rift")
		w.loot.spawn_drop(it, center)
		var sh := ItemDB.create("chrono_shard", 0, 1)
		sh.qty = 1 + era / 2
		w.loot.spawn_drop(sh, center + Vector3(1.5, 0, 0))
		var ess := ItemDB.create("spirit_essence", 0, 1)
		if not ess.is_empty():
			ess.qty = 2 + era / 2
			w.loot.spawn_drop(ess, center + Vector3(-1.5, 0, 0))
		if ResourceLoader.exists("res://scripts/world/chest.gd"):
			var ch = load("res://scripts/world/chest.gd").new()
			ch.set("tier", "rich")
			ch.set("lvl", w.spawner.level_near_player(2))
			add_child(ch)
			ch.global_position = center + Vector3(0, 0, -2.5)
		Events.banner.emit("Разлом покорён", "Выход открыт. Сундук хранителя и добыча ждут вас.", Color(0.7, 1.0, 0.8))

func on_boss_killed(_b) -> void:
	if kind == "chronos_trial":
		return
	if not expedition:
		done = true
		_open_exit()

func _open_exit() -> void:
	var ex := DimensionExit.new()
	ex.dim = self
	add_child(ex)
	ex.global_position = center + Vector3(0, 0, radius * 0.5)

func finish_and_leave() -> void:
	var w = Game.world
	if expedition and done:
		Chronicle.record("rift_cleared", [w.player], {"extra": {"rift": title}})
		Profile.milestone("rift_clear")
		var n := Profile.add_stat("rifts")
		if n >= 5:
			Profile.unlock("rift_master")
		var pid: String = opts.get("poi", "")
		if pid != "":
			if not Game.world_state.poi_state.has(pid):
				Game.world_state.poi_state[pid] = {}
			Game.world_state.poi_state[pid].cleared_day = Game.day()
	w.leave_dimension(true)

func _trial_victory() -> void:
	done = true
	var w = Game.world
	var t: Dictionary = DBEras.era(era).trial
	if not Settings.dev_unlock_all or Profile.trial_status(era).ready:
		w.player.data.inv.consume("chrono_shard", t.get("shards", 0))
		w.player.data.inv.consume(t.get("relic", ""), 1)
	Profile.unlock_era(era + 1)
	Chronicle.record("era_unlocked", [w.player], {"extra": {"era": DBEras.era(era + 1).name}})
	Audio.play_sting("era_unlock")
	Events.banner.emit("Новая эпоха открыта!", DBEras.era(era + 1).name + " — " + DBEras.era(era + 1).year, Color(1.0, 0.85, 0.3))
	SaveSys.save_game()
	_open_exit()
	w.get_tree().create_timer(2.5, false).timeout.connect(func():
		w.ui.open("dialog", {"title": "Врата эпох", "text": "Суд Хроноса пройден. Ваше мастерство, школы магии, достижения и важные артефакты сохранятся.\n\nОтправиться в эпоху «%s» прямо сейчас?" % DBEras.era(era + 1).name,
			"options": [{"text": "Отправиться", "cb": func(): w.change_era(era + 1)}, {"text": "Позже (вернуться в мир)", "cb": func(): w.leave_dimension(true)}]}))

func objective_text() -> String:
	if done:
		return "[color=#9dffb0]Выход открыт — войдите в портал[/color]"
	var alive := 0
	for a in stage_enemies:
		if is_instance_valid(a) and not a.is_dead:
			alive += 1
	if kind == "chronos_trial":
		return "[color=#ffd36b]Суд Хроноса, этап %d/3:[/color] осталось врагов %d" % [stage, alive]
	if expedition:
		if stage == 2 and not anchors.is_empty():
			return "[color=#c9a0ff]%s:[/color] закройте якоря разлома (%d/3)" % [title, 3 - anchors.size()]
		var what := "уничтожьте стражей" if stage == 1 else ("победите эхо-босса" if stage == 3 else "победите хранителя")
		return "[color=#c9a0ff]%s:[/color] %s (%d)" % [title, what, alive]
	return "[color=#c9a0ff]%s[/color]" % title

func target_pos():
	if done:
		return center + Vector3(0, 0, radius * 0.5)
	if stage == 2 and not anchors.is_empty():
		var best = null
		var bd := INF
		for an in anchors:
			if is_instance_valid(an):
				var d: float = an.global_position.distance_to(Game.player.global_position)
				if d < bd:
					bd = d
					best = an.global_position
		if best != null:
			return best
	for a in stage_enemies:
		if is_instance_valid(a) and not a.is_dead:
			return a.global_position
	return null

class DimensionExit:
	extends Node3D
	var dim
	var retreat := false          # always-open way back (keeps loot, no completion reward)
	var interact_radius := 3.5
	func _ready() -> void:
		var c := Color(0.5, 1.0, 0.7) if not retreat else Color(0.55, 0.75, 1.0)
		var sc := 1.0 if not retreat else 0.7
		var ring := MeshLib.part(self, MeshLib.torus(1.6 * sc, 1.9 * sc), MeshLib.glow(c, 3.0), Vector3(0, 2.1 * sc, 0), Vector3(90, 0, 0))
		MeshLib.part(self, MeshLib.cyl(1.6 * sc, 1.6 * sc, 0.05, 20), MeshLib.mat(Color(c.r, c.g, c.b, 0.4), 0.0, 1.0, 2.0, true), Vector3(0, 2.1 * sc, 0), Vector3(90, 0, 0))
		var lb := Label3D.new()
		lb.text = "Выход" if not retreat else "Отступить"
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 40
		lb.pixel_size = 0.006
		lb.outline_size = 10
		lb.modulate = c
		lb.position.y = 4.2 * sc + 0.4
		add_child(lb)
		var l := OmniLight3D.new()
		l.light_color = c
		l.light_energy = 2.0
		l.omni_range = 8.0
		l.position.y = 2.0
		add_child(l)
		Game.grid.insert_deferred(self, "interact")
		Audio.play_sfx("portal_open", global_position)
	func _exit_tree() -> void:
		Game.grid.remove(self, "interact")
	func interact_label() -> String:
		return "Выйти из измерения" if not retreat else "Отступить из разлома"
	func interact(a) -> void:
		if a.is_player and dim and is_instance_valid(dim):
			if retreat and not dim.done:
				Game.world.ui.open("dialog", {"title": "Отступить?", "text": "Портал вернёт вас к входу в разлом.\nДобытые предметы и опыт сохранятся, но награда хранителя будет потеряна, а разлом останется непокорённым.",
					"options": [{"text": "Отступить", "cb": func(): Game.world.leave_dimension(false)}, {"text": "Остаться", "cb": func(): pass}]})
				return
			if Game.mode == "world":
				dim.finish_and_leave()
			elif Game.world.mode_ctl and Game.world.mode_ctl.has_method("on_exit"):
				Game.world.mode_ctl.on_exit()

## Rift anchor: a crystal over a glowing circle. Standing inside (no
## matter the class) or striking the crystal closes it; while it is being
## closed it periodically vomits defenders.
class RiftAnchor:
	extends Node3D
	var dim
	var col := Color(0.8, 0.5, 1.0)
	var progress := 0.0
	var hit_radius := 1.0
	var _crystal: Node3D
	var _ring_mat: Material
	var _spawn_t := 1.5
	var _closed := false
	func _ready() -> void:
		_crystal = Node3D.new()
		add_child(_crystal)
		MeshLib.part(_crystal, MeshLib.prism(Vector3(1.0, 2.6, 1.0)), MeshLib.glow(col, 2.5), Vector3(0, 1.8, 0))
		MeshLib.part(_crystal, MeshLib.prism(Vector3(0.5, 1.2, 0.5)), MeshLib.glow(col.lightened(0.3), 3.0), Vector3(0.7, 1.0, 0.2), Vector3(0, 0, 25))
		MeshLib.part(self, MeshLib.torus(3.0, 3.25), MeshLib.glow(col, 1.6), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE, false)
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.4
		l.omni_range = 7.0
		l.position.y = 2.0
		l.shadow_enabled = false
		add_child(l)
		var lb := Label3D.new()
		lb.name = "Lbl"
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 36
		lb.pixel_size = 0.006
		lb.outline_size = 8
		lb.position.y = 4.0
		lb.modulate = col.lightened(0.3)
		add_child(lb)
		Game.grid.insert_deferred(self, "destructible")
	func _exit_tree() -> void:
		Game.grid.remove(self, "destructible")
	func take_hit(amount: float, _dtype: String = "blunt", _src = null) -> void:
		if _closed:
			return
		progress += clampf(amount / 300.0, 0.02, 0.12)
		VFX.burst(global_position + Vector3(0, 1.6, 0), col, 6, 0.3)
	func _process(delta: float) -> void:
		if _closed:
			return
		_crystal.rotation.y += delta * (0.8 + progress * 4.0)
		var pl = Game.player
		if pl == null or not is_instance_valid(pl) or pl.is_dead:
			return
		var d := Vector2(pl.global_position.x - global_position.x, pl.global_position.z - global_position.z).length()
		var active := d < 3.2 or progress > 0.0
		if d < 3.2:
			progress += delta / 6.0
		var lb: Label3D = get_node("Lbl")
		lb.text = "Якорь %d%%" % int(minf(progress, 1.0) * 100.0)
		if active:
			_spawn_t -= delta
			if _spawn_t <= 0.0 and dim and is_instance_valid(dim):
				_spawn_t = 5.0
				var pool: Array = dim._enemy_pool()
				var m = dim._spawn(pool[randi() % pool.size()], Game.world.spawner.level_near_player(0))
				if m:
					m.global_position = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
		if progress >= 1.0:
			_closed = true
			var tw := _crystal.create_tween()
			tw.tween_property(_crystal, "scale", Vector3(0.05, 0.05, 0.05), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(_crystal.queue_free)
			lb.text = "Закрыт"
			if dim and is_instance_valid(dim):
				dim.on_anchor_closed(self)
