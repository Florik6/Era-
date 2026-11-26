class_name Poi
extends Node3D
## Gameplay logic for points of interest: bandit camps, boss lairs, the
## Chronos Trial gate, rift portals, control points, dungeons, altars, the
## Mirror of Time, ruins, forges/labs/workshops/terminals, the claimable
## fortress, relic museum, monument, Last Witness, tourney, shrines.

var data := {}
var type := ""
var world
var interact_radius := 3.0
var _t := 0.0
var _spawned: Array = []
var _cp_progress := 0.0
var _flag: MeshInstance3D
var _label: Label3D
var _boss = null
var _ring: Node3D
var _info_t := 0.0
var _activating := false

const RIFT_KINDS := [["forgotten", "warped_medieval", "chronos"], ["forgotten", "warped_medieval", "mechanical"], ["mechanical", "chronos", "forgotten"],
	["mechanical", "future_rift", "chronos"], ["future_rift", "chronos", "mechanical"]]
const RIFT_TIER := {"forgotten": 1, "warped_medieval": 2, "mechanical": 2, "chronos": 3, "future_rift": 3}

static func create(p: Dictionary, w) -> Poi:
	var n := Poi.new()
	n.data = p
	n.type = p.type
	n.world = w
	n.name = "POI_" + p.type
	return n

func _ready() -> void:
	_build_visual()
	if type in ["trial", "rift", "dungeon", "altar", "mirror", "forge", "lab", "workshop", "terminal", "fortress", "relic_site", "monument", "tourney", "shrine", "cp"]:
		Game.grid.insert_deferred(self, "interact")
	if type == "witness":
		Witness.spawn_at(world, global_position)

func _exit_tree() -> void:
	Game.grid.remove(self, "interact")
	for a in _spawned:
		if is_instance_valid(a) and not a.is_dead:
			a.queue_free()

func _st() -> Dictionary:
	if not Game.world_state.has("poi_state"):
		Game.world_state["poi_state"] = {}
	var pts: Dictionary = Game.world_state.poi_state
	if not pts.has(data.id):
		pts[data.id] = {}
	return pts[data.id]

func _lbl(text: String, h: float, col: Color = Color(1, 0.95, 0.8)) -> void:
	_label = Label3D.new()
	_label.text = text
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 44
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.modulate = col
	_label.position.y = h
	_label.visibility_range_end = 45.0
	add_child(_label)

func _portal_ring(col: Color, r: float = 1.8) -> void:
	_ring = Node3D.new()
	add_child(_ring)
	_ring.position.y = r + 0.2
	var ring := MeshLib.part(_ring, MeshLib.torus(r * 0.85, r), MeshLib.glow(col, 2.5), Vector3.ZERO, Vector3(90, 0, 0))
	var inner := MeshLib.part(_ring, MeshLib.cyl(r * 0.85, r * 0.85, 0.05, 20), MeshLib.mat(Color(col.r, col.g, col.b, 0.45), 0.0, 1.0, 2.0, true), Vector3.ZERO, Vector3(90, 0, 0))
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 1.5
	l.omni_range = 7.0
	l.shadow_enabled = false
	_ring.add_child(l)
	var p := CPUParticles3D.new()
	p.amount = int(20 * Settings.profile().particles) + 2
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r
	p.gravity = Vector3(0, 0.5, 0)
	p.mesh = MeshLib.box(Vector3(0.07, 0.07, 0.07))
	p.material_override = MeshLib.mat(col, 0.0, 1.0, 3.0, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.add_child(p)

func _build_visual() -> void:
	var stone := MeshLib.mat(Color(0.45, 0.43, 0.42))
	var dark := MeshLib.mat(Color(0.12, 0.1, 0.12))
	var nm: String = data.get("name", "")
	match type:
		"camp":
			for i in 3:
				var a := TAU * i / 3.0
				MeshLib.part(self, MeshLib.prism(Vector3(2.2, 1.8, 2.4)), MeshLib.mat(Color(0.5, 0.38, 0.25)), Vector3(cos(a) * 5, 0.9, sin(a) * 5), Vector3(0, rad_to_deg(-a), 0))
			MeshLib.part(self, MeshLib.cyl(0.5, 0.6, 0.3, 8), stone, Vector3(0, 0.15, 0))
			var fire := OmniLight3D.new()
			fire.light_color = Color(1.0, 0.55, 0.2)
			fire.light_energy = 1.5
			fire.omni_range = 8.0
			fire.position.y = 1.0
			fire.shadow_enabled = false
			add_child(fire)
			MeshLib.part(self, MeshLib.prism(Vector3(0.5, 0.7, 0.5)), MeshLib.glow(Color(1.0, 0.5, 0.1), 3.0), Vector3(0, 0.5, 0))
		"lair":
			for i in 6:
				var a2 := TAU * i / 6.0
				MeshLib.part(self, MeshLib.box(Vector3(1.0, 5.0, 1.0)), dark, Vector3(cos(a2) * 13, 2.5, sin(a2) * 13), Vector3(0, rad_to_deg(a2), 0))
			MeshLib.part(self, MeshLib.cyl(14.0, 14.5, 0.2, 24), MeshLib.mat(Color(0.2, 0.15, 0.15)), Vector3(0, 0.05, 0))
			_lbl(nm if nm != "" else "Логово", 6.5, Color(1.0, 0.4, 0.35))
		"trial":
			_portal_ring(Color(1.0, 0.85, 0.3), 2.6)
			for i in 8:
				var a3 := TAU * i / 8.0
				MeshLib.part(self, MeshLib.box(Vector3(0.6, 3.5, 0.6)), MeshLib.mat(Color(0.85, 0.75, 0.5), 0.6, 0.4), Vector3(cos(a3) * 6, 1.75, sin(a3) * 6))
			_lbl("Суд Хроноса", 6.5, Color(1.0, 0.85, 0.3))
			interact_radius = 5.0
		"rift":
			_portal_ring(Color(0.65, 0.3, 1.0), 1.9)
			_lbl(nm if nm != "" else "Разлом", 4.8, Color(0.8, 0.6, 1.0))
			_label.visibility_range_end = 60.0
			interact_radius = 4.5
		"cp":
			MeshLib.part(self, MeshLib.cyl(4.0, 4.2, 0.3, 16), stone, Vector3(0, 0.15, 0))
			MeshLib.part(self, MeshLib.cyl(0.08, 0.08, 6.0, 6), MeshLib.mat(Color(0.3, 0.25, 0.2)), Vector3(0, 3.0, 0))
			_flag = MeshLib.part(self, MeshLib.box(Vector3(1.6, 1.0, 0.05)), MeshLib.mat(Color(0.8, 0.8, 0.8)), Vector3(0.8, 5.3, 0))
			_lbl(nm, 6.8)
			interact_radius = 4.5
			_update_flag()
		"dungeon":
			MeshLib.part(self, MeshLib.box(Vector3(4, 2.5, 0.8)), stone, Vector3(0, 1.25, -1.5))
			MeshLib.part(self, MeshLib.box(Vector3(2.4, 2.0, 0.9)), dark, Vector3(0, 1.0, -1.45))
			_lbl("Подземелье", 3.6)
		"altar":
			MeshLib.part(self, MeshLib.box(Vector3(2.0, 1.0, 1.2)), stone, Vector3(0, 0.5, 0))
			MeshLib.part(self, MeshLib.sphere(0.3, 8, 6), MeshLib.glow(Color(0.5, 1.0, 0.8), 2.0), Vector3(0, 1.4, 0))
			_lbl(Curses.flavour(Profile.current_era).title, 2.6, Color(0.6, 1.0, 0.85))
			for i in 6:
				var ra := TAU * i / 6.0
				MeshLib.part(self, MeshLib.box(Vector3(0.08, 0.02, 0.2)), MeshLib.glow(Color(0.5, 1.0, 0.8), 1.6), Vector3(cos(ra) * 0.55, 1.01, sin(ra) * 0.35), Vector3(0, rad_to_deg(-ra), 0))
			interact_radius = 3.5
		"mirror":
			MeshLib.part(self, MeshLib.box(Vector3(1.8, 3.0, 0.2)), MeshLib.mat(Color(0.75, 0.9, 1.0), 0.95, 0.05, 0.4), Vector3(0, 1.8, 0))
			MeshLib.part(self, MeshLib.box(Vector3(2.1, 3.3, 0.15)), MeshLib.mat(Color(0.7, 0.55, 0.3), 0.8, 0.4), Vector3(0, 1.8, 0.05))
			_lbl("Зеркало времени", 3.8, Color(0.6, 1.0, 1.0))
		"forge", "lab", "workshop", "terminal":
			var c = {"forge": Color(0.9, 0.4, 0.15), "lab": Color(0.4, 1.0, 0.5), "workshop": Color(1.0, 0.7, 0.3), "terminal": Color(0.3, 0.8, 1.0)}[type]
			MeshLib.part(self, MeshLib.box(Vector3(1.6, 1.0, 1.0)), MeshLib.mat(Color(0.3, 0.3, 0.32), 0.6, 0.4), Vector3(0, 0.5, 0))
			MeshLib.part(self, MeshLib.box(Vector3(0.6, 0.3, 0.6)), MeshLib.glow(c, 2.0), Vector3(0, 1.15, 0))
			_lbl({"forge": "Кузница", "lab": "Алхимическая лаборатория", "workshop": "Мастерская", "terminal": "Терминал"}[type], 2.2, c)
		"fortress":
			for i in 4:
				var a4 := TAU * i / 4.0 + PI / 4
				MeshLib.part(self, MeshLib.cyl(1.6, 1.8, 7.0, 10), stone, Vector3(cos(a4) * 10, 3.5, sin(a4) * 10))
			MeshLib.part(self, MeshLib.box(Vector3(5, 4, 5)), stone, Vector3(0, 2, 0))
			_lbl("Крепость: " + (nm if nm != "" else "Заброшенная твердыня"), 6.0, Color(0.95, 0.8, 0.5))
			interact_radius = 6.0
		"relic_site", "monument":
			MeshLib.part(self, MeshLib.box(Vector3(1.2, 1.4, 1.2)), MeshLib.mat(Color(0.85, 0.82, 0.75), 0.2, 0.5), Vector3(0, 0.7, 0))
			MeshLib.part(self, MeshLib.box(Vector3(0.9, 0.9, 0.9)), MeshLib.mat(Color(0.6, 0.85, 1.0, 0.4), 0.2, 0.1, 0.5), Vector3(0, 1.85, 0))
			_lbl("Музей истории" if type == "relic_site" else "Памятник прошлому", 3.0)
		"tourney":
			MeshLib.part(self, MeshLib.cyl(12.0, 12.0, 0.15, 24), MeshLib.mat(Color(0.65, 0.55, 0.4)), Vector3(0, 0.07, 0))
			for i in 10:
				var a5 := TAU * i / 10.0
				MeshLib.part(self, MeshLib.box(Vector3(0.3, 2.5, 0.3)), MeshLib.mat(Color(0.8, 0.2, 0.2) if i % 2 == 0 else Color(0.9, 0.85, 0.3)), Vector3(cos(a5) * 12, 1.25, sin(a5) * 12))
			_lbl("Рыцарский турнир", 3.5, Color(1.0, 0.85, 0.4))
			interact_radius = 5.0
		"shrine":
			MeshLib.part(self, MeshLib.cyl(1.0, 1.3, 0.6, 10), stone, Vector3(0, 0.3, 0))
			MeshLib.part(self, MeshLib.sphere(0.35, 8, 6), MeshLib.glow(Color(0.5, 1.0, 0.6), 2.5), Vector3(0, 1.3, 0))
			_lbl("Святилище", 2.4, Color(0.6, 1.0, 0.7))
		"ruins":
			for i in 5:
				MeshLib.part(self, MeshLib.box(Vector3(1.0, randf_range(1.0, 4.0), 1.0)), stone, Vector3(randf_range(-6, 6), 1.0, randf_range(-6, 6)), Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)))
			_lbl(nm if nm != "" else "Руины", 4.0)

func _spawn_pillars() -> void:
	if not ResourceLoader.exists("res://scripts/world/destructible.gd"):
		return
	var D = load("res://scripts/world/destructible.gd")
	for i in 4:
		var d = D.new()
		d.set("kind", "pillar")
		add_child(d)
		var a := TAU * i / 4.0 + 0.4
		d.position = Vector3(cos(a) * 7.0, 0, sin(a) * 7.0)

func _spawn_ruins_chest() -> void:
	if _st().get("opened", false) or not ResourceLoader.exists("res://scripts/world/chest.gd"):
		return
	var ch = load("res://scripts/world/chest.gd").new()
	ch.set("tier", "rich")
	ch.set("lvl", world.spawner.level_near_player(1))
	add_child(ch)
	ch.position = Vector3(0, 0, 2)

func can_interact(_a) -> bool:
	return true

func interact_label() -> String:
	match type:
		"trial": return "Суд Хроноса"
		"rift":
			var why := rift_block_reason()
			return ("Войти: " + rift_title()) if why == "" else ("Закрыто: " + why)
		"cp": return "Контрольная точка"
		"dungeon": return "Спуститься в подземелье"
		"altar": return "Использовать алтарь"
		"mirror": return "Коснуться зеркала"
		"forge": return "Кузница"
		"lab": return "Варить зелья"
		"workshop": return "Мастерская"
		"terminal": return "Взломать терминал"
		"fortress": return "Крепость"
		"relic_site": return "Осмотреть реликвии"
		"monument": return "Прочитать надпись"
		"tourney": return "Турнир"
		"shrine": return "Помолиться"
	return "?"

func interact(a) -> void:
	if not a.is_player:
		return
	Audio.play_sfx("ui_open")
	match type:
		"trial": _trial_dialog()
		"rift": _enter_rift()
		"cp": _cp_info()
		"dungeon": world.enter_dimension("dungeon", {"expedition": true, "poi": data.id})
		"altar": _altar()
		"mirror": _mirror()
		"forge", "lab", "workshop", "terminal": Stations.open(world, type, self)
		"fortress": Fortress.open(world, self)
		"relic_site": Legacy.relic_dialog(world)
		"monument": Legacy.monument_dialog(world, data)
		"tourney": _tourney()
		"shrine":
			world.player.respawn_point = global_position + Vector3(2, 0, 2)
			world.player.heal(world.player.max_hp)
			world.player.mana = world.player.max_mana
			Events.notify.emit("Святилище: точка возрождения сохранена, силы восстановлены.", Color(0.6, 1.0, 0.7))
			Audio.play_sfx("heal")
			SaveSys.save_game()

# ---------------------------------------------------------------- per-type logic
func _process(delta: float) -> void:
	_t += delta
	if _ring:
		_ring.rotation.y += delta * 0.6
	if world.player == null or not is_instance_valid(world.player):
		return
	var d: float = world.player.global_position.distance_to(global_position)
	if type == "rift":
		_rift_tick(delta, d)
		return
	match type:
		"camp":
			if _t > 1.0:
				_t = 0.0
				_camp_tick(d)
		"lair":
			if _t > 0.5:
				_t = 0.0
				_lair_tick(d)
		"cp":
			_cp_tick(delta, d)

func _camp_tick(d: float) -> void:
	var st := _st()
	var cleared_day: int = int(st.get("cleared_day", -99))
	if _spawned.is_empty() and d < 70.0 and Game.day() - cleared_day >= 2:
		var era_d: Dictionary = DBEras.era(Profile.current_era)
		var bandits: Array = era_d.enemies.filter(func(x): return DBActors.ENEMIES[x].team == "bandit")
		if bandits.is_empty():
			bandits = era_d.enemies
		bandits = world.spawner.suitable(bandits)
		for i in 2 + mini(3, world.spawner.era_progress_levels() / 2) + randi() % 2:
			var m = world.spawner.spawn_enemy(bandits[randi() % bandits.size()], global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)))
			if m:
				m.home = m.global_position
				_spawned.append(m)
		st.active = true
	elif not _spawned.is_empty() and st.get("active", false):
		var alive := 0
		for a in _spawned:
			if is_instance_valid(a) and not a.is_dead:
				alive += 1
		if alive == 0:
			st.active = false
			st.cleared_day = Game.day()
			_spawned.clear()
			world.quests.on_camp_cleared(data.id)
			Events.notify.emit("Лагерь зачищен: " + data.get("name", ""), Color(0.7, 1.0, 0.6))
			world.loot.spawn_drop(ItemDB.random_for_era(Profile.current_era, world.player.level, "chest"), global_position)
			world.player.data.fame += 3.0

func _lair_tick(d: float) -> void:
	var bid: String = data.data.get("boss_id", "")
	var st: Dictionary = Game.world_state.bosses.get(bid, {})
	if st.get("defeated", false):
		# bosses rise again after several days (renewed challenge)
		if Game.day() - int(st.get("defeated_day", 0)) < 5:
			return
		st.defeated = false
	if st.get("returned_active", false):
		return
	if (_boss == null or not is_instance_valid(_boss)) and d < 42.0 and float(st.get("returns_at", 0.0)) <= Game.game_time:
		_boss = world.spawner.spawn_boss(bid, global_position + Vector3(0, 0, -4), -1, int(st.get("escaped", 0)))
		if _boss:
			_boss.lair_id = data.id
			Events.banner.emit(_boss.display_name, DBActors.BOSSES[bid].lore, Color(1.0, 0.4, 0.35))
			Audio.play_sfx("boss_roar", global_position)
			Audio.play_music("boss")
	elif _boss != null and is_instance_valid(_boss) and d > 90.0 and not _boss.is_dead:
		_boss.queue_free()
		_boss = null
		Audio.play_music(DBEras.era(Profile.current_era).music)

func _update_flag() -> void:
	if _flag == null:
		return
	var o: String = world.factions.point_owner(data.id) if world.factions else ""
	var c := Color(0.85, 0.85, 0.85)
	if o == "player":
		c = Color(0.3, 1.0, 0.4)
	elif o != "":
		c = DBEras.faction(o).get("color", c)
	_flag.material_override = MeshLib.mat(c)
	if _label:
		_label.text = "%s\n%s" % [data.get("name", ""), "Ваша" if o == "player" else DBEras.faction(o).get("name", "Ничья")]

func _cp_tick(delta: float, d: float) -> void:
	var owner_f: String = world.factions.point_owner(data.id)
	var mine: String = world.factions.member_of()
	var claimer := mine if mine != "" else "player"
	if owner_f == claimer:
		_cp_progress = 0.0
		return
	if d > 6.0 or world.player.is_dead:
		_cp_progress = maxf(0.0, _cp_progress - delta * 0.3)
		return
	var contested := false
	for a in Game.actors_near(global_position, 8.0):
		if not a.is_dead and a != world.player and Game.is_enemy(world.player, a):
			contested = true
			break
	if contested:
		return
	_cp_progress += delta / 8.0
	if int(_cp_progress * 10) != int((_cp_progress - delta / 8.0) * 10):
		VFX.text(global_position + Vector3(0, 3, 0), "Захват %d%%" % int(minf(1.0, _cp_progress) * 100), Color(0.6, 1.0, 0.6), 0.9)
	if _cp_progress >= 1.0:
		_cp_progress = 0.0
		world.factions.capture_point(data.id, claimer, world.player)
		Audio.play_sfx("capture")
		Events.banner.emit("Точка захвачена", data.get("name", ""), Color(0.4, 1.0, 0.5))
		_update_flag()
		# defenders try to take it back later
		if owner_f != "" and owner_f != "player":
			get_tree().create_timer(40.0, false).timeout.connect(func():
				if is_instance_valid(self) and world.factions.point_owner(data.id) == claimer and world.player.global_position.distance_to(global_position) < 150.0:
					world.director.start_battle(owner_f, claimer if claimer != "player" else "", "cp", data.id, global_position))

func _cp_info() -> void:
	var o: String = world.factions.point_owner(data.id)
	var t := "[b]%s[/b] (%s)\nВладелец: %s\n\nСтойте в круге без врагов рядом 8 секунд, чтобы захватить. Захваченные точки дают бонусы опыта, урона и защиты, а лидеру — доход." % [data.get("name", ""), data.data.get("cp_type", ""), "вы" if o == "player" else DBEras.faction(o).get("name", "никто")]
	world.ui.open("dialog", {"title": "Контрольная точка", "text": t, "options": [{"text": "Понятно", "cb": func(): pass}]})

func _trial_dialog() -> void:
	var era := Profile.current_era
	var ts: Dictionary = Profile.trial_status(era)
	var lines: Array = []
	for l in ts.lines:
		lines.append(("[color=#7dff8a]✔[/color] " if l[1] else "[color=#ff7a6b]✖[/color] ") + l[0])
	var opts: Array = []
	if ts.ready or Settings.dev_unlock_all:
		opts.append({"text": "Начать Суд Хроноса", "cb": func(): world.enter_dimension("chronos_trial", {"trial": true})})
	var unlocked: Array = Profile.unlocked_eras
	if unlocked.size() > 1 or Settings.dev_unlock_all:
		opts.append({"text": "Портал эпох", "cb": func(): world.ui.open("eras", {"select_cb": func(i): world.change_era(i)})})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": "Суд Хроноса", "text": "Чтобы открыть следующую эпоху, нужно доказать мастерство:\n\n" + "\n".join(lines), "portrait_color": Color(1.0, 0.85, 0.3), "options": opts})

# ---------------------------------------------------------------- rifts
func rift_kind() -> String:
	var opts: Array = RIFT_KINDS[clampi(Profile.current_era, 0, 4)]
	return data.data.get("rift_kind", opts[hash(data.id) % opts.size()])

func rift_title() -> String:
	return Dimension.THEMES.get(rift_kind(), {}).get("title", "Разлом")

## Empty string when the rift can be entered, otherwise the reason it is shut.
func rift_block_reason() -> String:
	var st := _st()
	if Game.day() - int(st.get("cleared_day", -99)) < 1 and not data.data.get("temporary", false):
		return "разлом покорён сегодня и нестабилен до завтра"
	if world.dimension != "":
		return "вы уже в другом измерении"
	if world.get("mode") != null and world.mode != "world":
		return "недоступно в этом режиме"
	var pl = world.player
	if pl == null or not is_instance_valid(pl) or pl.is_dead:
		return "герой не готов"
	for a in Game.actors_near(pl.global_position, 9.0):
		if a != pl and not a.is_dead and Game.is_enemy(pl, a) and a.aggro.has("player"):
			return "рядом враги — сначала отбейтесь"
	if world.get("portal_block_until") != null and Time.get_ticks_msec() < int(world.portal_block_until):
		return "портал восстанавливается"
	return ""

func _rift_danger() -> String:
	var tier: int = RIFT_TIER.get(rift_kind(), 2)
	var lvl: int = world.spawner.level_near_player(2) if world.spawner else 1
	return "Опасность: %s · ур. ~%d" % ["◆".repeat(tier) + "◇".repeat(3 - tier), lvl]

func _rift_tick(delta: float, d: float) -> void:
	# label: name, danger and access state, refreshed while the hero is near
	_info_t -= delta
	if _info_t <= 0.0 and _label:
		_info_t = 0.5
		if d < 40.0:
			var why := rift_block_reason()
			_label.text = "%s\n%s\n%s" % [rift_title(), _rift_danger(), "Открыт — войдите в кольцо" if why == "" else "Закрыт: " + why]
			_label.modulate = Color(0.85, 0.65, 1.0) if why == "" else Color(0.7, 0.6, 0.75)
		else:
			_label.text = data.get("name", "Разлом")
	# walking through the ring enters it directly (with a short re-entry guard)
	if not _activating and d < 1.6 and rift_block_reason() == "":
		var pl = world.player
		var v: Vector3 = pl.velocity if pl is CharacterBody3D else Vector3.ZERO
		if Vector2(v.x, v.z).length() > 0.5:
			_enter_rift()

func _enter_rift() -> void:
	if _activating:
		return
	var why := rift_block_reason()
	if why != "":
		Events.notify.emit("Разлом закрыт: " + why + ".", Color(0.8, 0.6, 1.0))
		Audio.play_sfx("error")
		return
	_activating = true
	var pl = world.player
	# return point: a few metres in front of the ring, outside the trigger
	var away: Vector3 = pl.global_position - global_position
	away.y = 0.0
	if away.length() < 0.5:
		away = Vector3(0, 0, 1)
	var ret: Vector3 = global_position + away.normalized() * 5.0
	pl.apply_status("invuln", 2.0)
	Audio.play_sfx("portal_open", global_position)
	VFX.ring(global_position, 5.0, Color(0.65, 0.3, 1.0), 0.7)
	VFX.flash(global_position + Vector3(0, 2.0, 0), Color(0.75, 0.45, 1.0), 0.5, 9.0)
	if world.cam:
		world.cam.shake(0.25)
	if _ring:
		var tw := _ring.create_tween()
		tw.tween_property(_ring, "scale", Vector3(1.35, 1.35, 1.35), 0.45).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_ring, "scale", Vector3.ONE, 0.3)
	var k := rift_kind()
	get_tree().create_timer(0.55, false).timeout.connect(func():
		_activating = false
		if not is_instance_valid(self) or world.dimension != "" or pl.is_dead:
			return
		world.enter_dimension(k, {"expedition": true, "poi": data.id, "return_pos": ret, "portal_name": rift_title()}))

func _altar() -> void:
	world.ui.open("altar", {"altar": self, "station": "altar"})

func _mirror() -> void:
	var st := _st()
	if Game.day() - int(st.get("used_day", -99)) < 1:
		Events.notify.emit("Зеркало потускнело. Вернитесь завтра.", Color(0.7, 0.9, 1.0))
		return
	st.used_day = Game.day()
	world.spawn_chrono_double(world.player)

func _tourney() -> void:
	var st := _st()
	if Game.day() - int(st.get("day", -99)) < 1:
		Events.notify.emit("Следующий турнир — завтра.", Color(1.0, 0.85, 0.4))
		return
	world.ui.open("dialog", {"title": "Рыцарский турнир", "text": "Три поединка подряд против рыцарей. Награда победителю — эпическое оружие и слава.", "options": [
		{"text": "Выйти на ристалище", "cb": func():
			st.day = Game.day()
			_tourney_round(1)},
		{"text": "Уйти", "cb": func(): pass}]})

func _tourney_round(i: int) -> void:
	if i > 3:
		var it := ItemDB.random_for_era(Profile.current_era, world.player.level, "elite", 0.3)
		it.history.append("Приз рыцарского турнира, день %d" % (Game.day() + 1))
		world.loot.spawn_drop(it, global_position)
		world.player.data.fame += 15.0
		Chronicle.record("duel", [world.player, {"id": "tourney", "name": "рыцари турнира"}], {"pos_v3": global_position, "extra": {"winner": Profile.char.name}})
		Events.banner.emit("Победитель турнира!", "Слава о вас разносится по округе.", Color(1.0, 0.85, 0.3))
		return
	var k = world.spawner.spawn_enemy("knight_renegade", global_position + Vector3(0, 0, -6), world.spawner.level_near_player(i - 1))
	if k:
		k.display_name = "Рыцарь турнира (%d/3)" % i
		k.team = "bandit"
		k.add_aggro(world.player, 999.0)
		_spawned.append(k)
		Events.notify.emit("Поединок %d из 3!" % i, Color(1.0, 0.85, 0.4))
		k.died.connect(func(_a, _k): get_tree().create_timer(2.0, false).timeout.connect(func(): _tourney_round(i + 1)), CONNECT_ONE_SHOT)
