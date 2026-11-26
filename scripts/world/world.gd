class_name World
extends Node3D
## Game scene root. Wires every subsystem together, owns modes (living world,
## arena, trials, chrono-dungeons), dimensions (rifts, boss arenas, Chronos
## Trial), death/respawn, era transitions, persistence and the public world
## API used by all systems (see docs/ARCHITECTURE.md).

const WORLD_HALF := 1280.0
const DIM_OFFSET := Vector3(6000, 0, 6000)
## Subsystems still being finished are kept out of the running game.
const DISABLED_SUBSYSTEMS: Array = []

var world_half := WORLD_HALF
var mode := "world"
var era := 0
var gen = null
var terrain = null
var day_night = null
var weather = null
var env: WorldEnvironment
var sun: DirectionalLight3D
var fx_root: Node3D
var actors_root: Node3D
var poi_root: Node3D
var vfx = null
var orbs: OrbSystem
var spawner: Spawner
var loot: Loot
var factions = null
var quests = null
var legends = null
var sim = null
var director = null
var dialogs = null
var ui = null
var hud: HUD
var touch: TouchControls
var cam: GameCamera
var zones: Array = []
var dimension := ""
var dim_node: Node3D = null
var dim_return := Vector3.ZERO
var portal_block_until := 0
var active_ritual = null          # AltarRitual in progress (gear is locked meanwhile)
var last_ritual_stages := 0     # Time.get_ticks_msec(): portals ignore the hero until then
var mode_ctl = null
var map_tex: ImageTexture = null
var poi_nodes := {}
var settlement_npcs := {}     # settlement id -> Array of NPC
var flat_ground := false
var player: Player
var ext := {}                 # optional subsystems: road_encounters, living_pois, tracking, discovery, traces, cinematic
var _death_pending := false
var _rift_picked: Array = []
var _base_env := {}

func _ready() -> void:
	Game.world = self
	mode = Game.mode
	era = Profile.current_era
	if mode == "world":
		Game.world_state = SaveSys.load_world_state(era)
		if Game.world_state.is_empty():
			Game.world_state = {"chunks": {}, "settlements": {}, "points": {}, "records": {}, "factions": {}, "quests": {}, "bosses": {}, "director": {}, "fortress": {}, "poi_state": {}, "time": 0.3}
		for k in ["chunks", "settlements", "points", "records", "factions", "quests", "bosses", "director", "fortress", "poi_state"]:
			if not Game.world_state.has(k):
				Game.world_state[k] = {}
		Game.game_time = float(Game.world_state.get("time", 0.3))
	else:
		Game.world_state = {"chunks": {}, "settlements": {}, "points": {}, "records": {}, "factions": {}, "quests": {}, "bosses": {}, "director": {}, "fortress": {}, "poi_state": {}}
	_build_environment()
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)
	actors_root = Node3D.new()
	actors_root.name = "Actors"
	add_child(actors_root)
	poi_root = Node3D.new()
	poi_root.name = "POI"
	add_child(poi_root)
	var vm = load("res://scripts/vfx/vfx_manager.gd").new()
	vm.name = "VFX"
	add_child(vm)
	vfx = vm
	orbs = OrbSystem.new()
	add_child(orbs)
	spawner = Spawner.new(self, actors_root)
	add_child(spawner)
	loot = Loot.new(self)
	add_child(loot)
	factions = FactionSystem.new(self)
	add_child(factions)
	legends = LegendSystem.new(self)
	add_child(legends)
	quests = QuestSystem.new(self)
	add_child(quests)
	sim = WorldSim.new(self)
	add_child(sim)
	director = WorldDirector.new(self)
	add_child(director)
	dialogs = Dialogs.new(self)
	add_child(dialogs)
	for spec in [["road_encounters", "res://scripts/sim/road_encounters.gd"], ["living_pois", "res://scripts/world/living_poi.gd"],
			["tracking", "res://scripts/world/tracking.gd"], ["discovery", "res://scripts/world/discovery.gd"],
			["traces", "res://scripts/world/event_traces.gd"], ["cinematic", "res://scripts/ui/cinematic.gd"],
			["music", "res://scripts/audio/music_director.gd"], ["combat_overlay", "res://scripts/ui/combat_overlay.gd"],
			["perf_lod", "res://scripts/world/perf_lod.gd"], ["dcq", "res://scripts/core/dynamic_quality.gd"],
			["resonance", "res://scripts/combat/resonance.gd"]]:
		if not spec[0] in DISABLED_SUBSYSTEMS:
			_attach_optional(spec[0], spec[1])
	cam = GameCamera.new()
	add_child(cam)
	hud = HUD.new()
	add_child(hud)
	touch = hud.touch
	if ResourceLoader.exists("res://scripts/ui/ui_manager.gd"):
		ui = load("res://scripts/ui/ui_manager.gd").new()
	else:
		ui = FallbackUI.new()
	add_child(ui)
	_build_sky_systems()
	match mode:
		"world":
			_setup_world()
		_:
			_setup_mode()
	_setup_optional()
	Events.actor_killed.connect(_on_actor_killed)
	Events.player_died.connect(_on_player_died)
	Events.chronicle.connect(_on_chronicle)
	Settings.apply()
	Events.settings_changed.connect(_apply_quality)
	_apply_quality()
	if mode == "world":
		Audio.play_music(DBEras.era(era).music)
		if not Profile.tutorial_done:
			Profile.tutorial_done = true
			get_tree().create_timer(1.5, false).timeout.connect(func():
				Events.banner.emit("ЭПОХА I: " + DBEras.era(era).name.to_upper() if era == 0 else DBEras.era(era).name, "Собирайте сферы опыта, ищите оружие, сражайтесь и становитесь легендой.", Color(1.0, 0.85, 0.4)))

## Optional subsystems are plain nodes with setup(world); missing scripts are skipped.
func _attach_optional(nm: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var scr = load(path)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		push_warning("optional subsystem %s failed to load" % nm)
		return
	var n = scr.new()
	if n == null:
		return
	n.name = nm
	add_child(n)
	ext[nm] = n

func sys(nm: String):
	return ext.get(nm)

func _setup_optional() -> void:
	for k in ext:
		if ext[k].has_method("setup"):
			ext[k].setup(self)

func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	var ed: Dictionary = DBEras.era(era)
	sm.sky_top_color = ed.sky_top
	sm.sky_horizon_color = ed.sky_horizon
	sm.ground_horizon_color = ed.sky_horizon
	sm.ground_bottom_color = ed.sky_horizon.darkened(0.5)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = ed.fog_color
	e.fog_density = Settings.fog_value(ed.fog_base) * 0.35
	e.fog_sky_affect = 0.3
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = ed.sun
	sun.light_energy = 1.15
	sun.shadow_enabled = Settings.profile().shadows
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)

func _build_sky_systems() -> void:
	if ResourceLoader.exists("res://scripts/world/day_night.gd"):
		day_night = load("res://scripts/world/day_night.gd").new()
		add_child(day_night)
		if day_night.has_method("setup"):
			day_night.setup(env, sun, era)
	if ResourceLoader.exists("res://scripts/world/weather.gd"):
		weather = load("res://scripts/world/weather.gd").new()
		add_child(weather)
		if weather.has_method("setup"):
			weather.setup(env, era)

func _apply_quality() -> void:
	var p := Settings.profile()
	sun.shadow_enabled = p.shadows
	if env and env.environment:
		env.environment.glow_enabled = p.glow
		if not weather:
			env.environment.fog_density = Settings.fog_value(DBEras.era(era).fog_base) * 0.35

# ---------------------------------------------------------------- setup
func _setup_world() -> void:
	if ResourceLoader.exists("res://scripts/world/world_gen.gd") and ResourceLoader.exists("res://scripts/world/chunk_streamer.gd"):
		gen = load("res://scripts/world/world_gen.gd").new()
		gen.setup(Profile.world_seed + era * 7919, era, WORLD_HALF)
		terrain = load("res://scripts/world/chunk_streamer.gd").new()
		terrain.name = "Terrain"
		add_child(terrain)
		terrain.build_poi_decor = false
		terrain.setup(gen, Game.world_state.chunks)
		terrain.chunk_loaded.connect(_on_chunk_loaded)
		terrain.chunk_unloaded.connect(_on_chunk_unloaded)
	else:
		_build_flat_ground(260.0)
	factions.setup()
	legends.setup()
	sim.setup()
	quests.setup()
	director.setup()
	Legacy.apply_to_world(self)
	var sp := Vector3.ZERO
	var saved = Game.world_state.get("player_pos")
	if saved is Array and saved.size() == 3:
		sp = Vector3(saved[0], saved[1], saved[2])
	elif gen:
		var s2: Vector2 = gen.spawn_point()
		sp = Vector3(s2.x, 0, s2.y)
	if terrain and terrain.has_method("force_load_around"):
		terrain.force_load_around(sp)
	sp.y = ground_height(sp) + 0.3
	_spawn_player(sp)
	player.respawn_point = sp
	portal_block_until = Time.get_ticks_msec() + 4000   # loading next to a portal never re-enters it
	if Profile.char.companion.size() > 0:
		summon_companion(player, false)

func _setup_mode() -> void:
	var dim := Dimension.new()
	add_child(dim)
	var kind = {"arena": "arena", "trials": "trial_arena", "dungeon": "chronos_void"}.get(mode, "arena")
	dim.build(kind, Game.rng.randi(), Vector3.ZERO, era)
	dim_node = dim
	dimension = "mode_" + mode
	_apply_dim_env(dim)
	factions.setup()
	legends.setup()
	_spawn_player(dim.player_spawn)
	mode_ctl = GameModes.create(mode, self)
	add_child(mode_ctl)
	Audio.play_music("boss" if mode == "trials" else ("rift" if mode == "dungeon" else DBEras.era(era).music))

func _build_flat_ground(r: float) -> void:
	flat_ground = true
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(r * 2, 1, r * 2)
	cs.shape = bx
	cs.position.y = -0.5
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.box(Vector3(r * 2, 1, r * 2))
	mi.material_override = MeshLib.mat(DBEras.era(era).ground.plains)
	mi.position.y = -0.5
	sb.add_child(mi)
	add_child(sb)
	world_half = r

func _spawn_player(p: Vector3) -> void:
	player = Player.new()
	if mode == "arena":
		player.data = GameModes.arena_char()
	actors_root.add_child(player)
	player.global_position = p
	player.reset_physics_interpolation()
	Game.player = player
	cam.target = player
	cam.snap()

# ---------------------------------------------------------------- frame
func _process(_delta: float) -> void:
	if player and is_instance_valid(player) and terrain and dimension == "":
		terrain.update_center(player.global_position)

# ---------------------------------------------------------------- world API
func ground_height(p: Vector3) -> float:
	if dim_node and _in_dim_region(p):
		return dim_node.floor_y
	if terrain and terrain.has_method("ground_height"):
		return terrain.ground_height(p)
	return 0.0

func _in_dim_region(p: Vector3) -> bool:
	if dim_node == null:
		return false
	return Vector2(p.x - dim_node.center.x, p.z - dim_node.center.z).length() < dim_node.radius + 40.0

func is_water(p: Vector3) -> bool:
	if gen and dimension == "" and gen.has_method("is_water"):
		return gen.is_water(p.x, p.z)
	return false

var water_level: float:
	get:
		return gen.water_level if gen else -100.0

func place_name(p: Vector3) -> String:
	if dim_node and _in_dim_region(p):
		return dim_node.title
	if gen and gen.has_method("nearest_place"):
		return gen.nearest_place(Vector2(p.x, p.z))
	return "Арена"

func clamp_to_world(a) -> void:
	var p: Vector3 = a.global_position
	var changed := false
	if dim_node and _in_dim_region(p):
		var off := Vector2(p.x - dim_node.center.x, p.z - dim_node.center.z)
		if off.length() > dim_node.radius - 1.0:
			off = off.normalized() * (dim_node.radius - 1.0)
			p.x = dim_node.center.x + off.x
			p.z = dim_node.center.z + off.y
			changed = true
		if p.y < dim_node.floor_y - 4.0:
			p.y = dim_node.floor_y + 0.5
			changed = true
	else:
		var lim := world_half - 4.0
		if absf(p.x) > lim or absf(p.z) > lim:
			p.x = clampf(p.x, -lim, lim)
			p.z = clampf(p.z, -lim, lim)
			changed = true
		if terrain or flat_ground:
			var gh := ground_height(p)
			if p.y < gh - 3.0:
				p.y = gh + 0.5
				a.velocity.y = 0
				changed = true
	if changed:
		a.global_position = p
	a.in_water = is_water(p) and p.y < water_level - 0.25

func timeslow_at(p: Vector3, src) -> bool:
	for z in zones:
		if is_instance_valid(z) and z.kind == "timeslow" and z.global_position.distance_to(p) < z.radius:
			if src == null or not is_instance_valid(src) or (z.src != null and is_instance_valid(z.src) and Game.can_damage(z.src, src)):
				return true
	return false

func freeze_water(p: Vector3, r: float) -> void:
	if gen and ResourceLoader.exists("res://scripts/world/world_fx.gd"):
		var wfx = load("res://scripts/world/world_fx.gd")
		if wfx.has_method("freeze_water"):
			wfx.freeze_water(fx_root, gen, p, r)

func spawn_ice_wall(p: Vector3, dir: Vector3, life: float) -> void:
	if ResourceLoader.exists("res://scripts/world/world_fx.gd"):
		var wfx = load("res://scripts/world/world_fx.gd")
		if wfx.has_method("spawn_ice_wall"):
			wfx.spawn_ice_wall(fx_root, p, dir, life)
			return
	# fallback wall
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(5, 2.5, 0.8)
	cs.shape = bx
	cs.position.y = 1.25
	sb.add_child(cs)
	MeshLib.part(sb, MeshLib.box(Vector3(5, 2.5, 0.8)), MeshLib.mat(Color(0.7, 0.9, 1.0, 0.75), 0.2, 0.1, 0.5), Vector3(0, 1.25, 0))
	fx_root.add_child(sb)
	sb.global_position = Vector3(p.x, ground_height(p), p.z)
	sb.look_at(sb.global_position + Vector3(dir.x, 0, dir.z), Vector3.UP)
	get_tree().create_timer(life, false).timeout.connect(sb.queue_free)

func camera_snap() -> void:
	if cam:
		cam.snap()

func camera_shake(a: float) -> void:
	if cam:
		cam.shake(a)

func map_texture() -> Texture2D:
	if map_tex == null:
		var img: Image
		if gen and gen.has_method("overview_image"):
			img = gen.overview_image(512)
		else:
			img = Image.create(64, 64, false, Image.FORMAT_RGB8)
			img.fill(DBEras.era(era).ground.plains.darkened(0.2))
		map_tex = ImageTexture.create_from_image(img)
	return map_tex

func map_markers(minimap: bool = false) -> Array:
	var out: Array = []
	if gen == null:
		return out
	var disc = sys("discovery")
	var pp: Vector3 = player.global_position if player and is_instance_valid(player) else Vector3.ZERO
	for s in gen.settlements:
		if disc and not disc.is_discovered(s.id):
			continue
		var owner_fid: String = factions.settlement_owner(s.id) if factions else ""
		out.append({"pos": s.pos, "kind": "settlement", "name": s.name + ((" [%s]" % DBEras.faction(owner_fid).name) if owner_fid != "" else ""), "color": DBEras.faction(owner_fid).get("color", Color(1, 1, 1)) if owner_fid != "" else Color(0.95, 0.95, 0.9)})
	var names := {"lair": "Логово", "trial": "Суд Хроноса", "rift": "Разлом", "cp": "Контрольная точка", "dungeon": "Подземелье", "altar": "Алтарь",
		"mirror": "Зеркало времени", "fortress": "Крепость", "witness": "?", "tourney": "Турнир", "shrine": "Святилище", "camp": "Лагерь", "ruins": "Руины", "monument": "Памятник", "relic_site": "Музей"}
	var cols := {"lair": Color(1, 0.15, 0.15), "trial": Color(1, 0.85, 0.3), "rift": Color(0.6, 0.3, 1.0), "cp": Color(0.3, 0.8, 1.0), "camp": Color(0.8, 0.4, 0.3),
		"fortress": Color(0.9, 0.7, 0.4), "shrine": Color(0.5, 1.0, 0.6), "altar": Color(0.5, 1.0, 0.85), "dungeon": Color(0.75, 0.7, 0.6)}
	for p in gen.pois:
		var known: bool = disc == null or disc.is_discovered(p.id) or p.type == "trial"
		if not known:
			continue
		var col: Color = cols.get(p.type, Color(0.85, 0.85, 0.85))
		var nm: String = p.get("name", names.get(p.type, p.type))
		if p.type == "cp" and factions:
			var ow: String = factions.point_owner(p.id)
			if ow != "":
				col = DBEras.faction(ow).get("color", col) if ow != "player" else Color(0.3, 1.0, 0.4)
		if p.type == "lair" and Game.world_state.bosses.get(p.data.get("boss_id", ""), {}).get("defeated", false):
			col = Color(0.4, 0.4, 0.4)
		out.append({"pos": p.pos, "kind": p.type, "name": nm, "color": col})
	if director:
		for ev in director.active_events():
			if ev.has("pos"):
				out.append({"pos": Vector2(ev.pos.x, ev.pos.z), "kind": "event", "name": ev.name, "color": Color(1.0, 0.5, 0.1)})
	var re = sys("road_encounters")
	if re and re.get("active") != null:
		for e in re.active:
			if e.state == "active":
				out.append({"pos": Vector2(e.pos.x, e.pos.z), "kind": "encounter", "name": e.name, "color": Color(1.0, 0.8, 0.35)})
	var lp = sys("living_pois")
	if lp:
		out.append_array(lp.markers())
	var tr = sys("tracking")
	if tr:
		for t in tr.active_trails():
			var tg: Vector3 = t.target
			if minimap or Vector2(tg.x - pp.x, tg.z - pp.z).length() < 400.0:
				out.append({"pos": Vector2(tg.x, tg.z), "kind": "trail", "name": t.label, "color": Color(0.95, 0.8, 0.5)})
	return out

func objective_text() -> String:
	if mode_ctl and mode_ctl.has_method("objective_text"):
		return mode_ctl.objective_text()
	if dim_node and dim_node.has_method("objective_text") and dimension != "":
		return dim_node.objective_text()
	if quests:
		return quests.tracked_text()
	return ""

func quest_target():
	if dim_node and dimension != "" and dim_node.has_method("target_pos"):
		return dim_node.target_pos()
	if quests:
		return quests.tracked_target()
	return null

# ---------------------------------------------------------------- chunks / POIs
func _on_chunk_loaded(key: Vector2i, node: Node3D, pois: Array, settlements: Array) -> void:
	for p in pois:
		if poi_nodes.has(p.id) and is_instance_valid(poi_nodes[p.id]):
			continue
		var n := Poi.create(p, self)
		if n:
			node.add_child(n)
			var pos3 := Vector3(p.pos.x, 0, p.pos.y)
			pos3.y = ground_height(pos3)
			n.global_position = pos3
			poi_nodes[p.id] = n
	for s in settlements:
		_populate_settlement(s)

func _on_chunk_unloaded(key: Vector2i) -> void:
	for sid in settlement_npcs.keys():
		var s = _settlement(sid)
		if s == null:
			continue
		var ck := Vector2i(floori(s.pos.x / 64.0), floori(s.pos.y / 64.0))
		if ck == key:
			for n in settlement_npcs[sid]:
				if is_instance_valid(n):
					n.queue_free()
			settlement_npcs.erase(sid)

func _settlement(sid: String):
	if gen == null:
		return null
	for s in gen.settlements:
		if s.id == sid:
			return s
	return null

func _populate_settlement(s: Dictionary) -> void:
	if settlement_npcs.has(s.id):
		return
	var arr: Array = []
	var st: Dictionary = factions.settlement_state(s.id) if factions else {}
	var pop: int = clampi(int(st.get("population", 6)), 2, 10)
	var guards: int = clampi(int(st.get("guards", 2)), 0, 6)
	var c := Vector3(s.pos.x, 0, s.pos.y)
	var owner_s := s.duplicate()
	owner_s.owner = st.get("owner", s.get("owner", ""))
	var jobs := activity_points(s.id)
	var used := {}
	for i in pop:
		var p := c + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))
		var v = spawner.spawn_villager(owner_s, p, "trader" if i == 0 else "villager")
		arr.append(v)
		# give the villager a workplace: trader → stall, first villager → forge
		var want: Array = ["stall"] if i == 0 else (["forge"] if i == 1 else ["well", "bench", "field", "wood", "campfire", "stall"])
		for j in jobs:
			var key: String = str(j.pos)
			if String(j.kind) in want and not used.has(key):
				used[key] = true
				v.set_meta("job", j)
				break
	for i in guards:
		var p2 := c + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
		arr.append(spawner.spawn_villager(owner_s, p2, "guard"))
	settlement_npcs[s.id] = arr
	if quests:
		quests.on_settlement_visited(s)

## Workplaces of a settlement: {kind, pos: Vector3, face: Vector3}. Uses the
## streamer's real props when available, otherwise spots around the square.
var _activity_cache := {}
func activity_points(sid: String) -> Array:
	if terrain and terrain.has_method("activity_points"):
		var pts: Array = terrain.activity_points(sid)
		if not pts.is_empty():
			var out: Array = []
			for p in pts:
				var pos: Vector3 = p.get("pos", Vector3.ZERO) if p.get("pos") is Vector3 else Vector3(p.pos[0], 0, p.pos[1]) if p.get("pos") is Array else Vector3.ZERO
				pos.y = ground_height(pos)
				out.append({"kind": String(p.get("kind", "bench")), "pos": pos, "face": p.get("face", Vector3.ZERO)})
			return out
	if _activity_cache.has(sid):
		return _activity_cache[sid]
	var s = _settlement(sid)
	var out2: Array = []
	if s != null:
		var c := Vector3(s.pos.x, 0, s.pos.y)
		var h := hash(sid)
		var spots := [["stall", Vector3(5, 0, 3)], ["forge", Vector3(-6, 0, 4)], ["well", Vector3(0, 0, -6)], ["bench", Vector3(7, 0, -4)],
			["field", Vector3(-11, 0, -9)], ["wood", Vector3(12, 0, 8)], ["campfire", Vector3(-4, 0, -11)], ["stall", Vector3(8, 0, 6)]]
		for sp in spots:
			var off: Vector3 = (sp[1] as Vector3).rotated(Vector3.UP, float(h % 628) / 100.0)
			var pos2: Vector3 = c + off
			pos2.y = ground_height(pos2)
			out2.append({"kind": sp[0], "pos": pos2, "face": (c - pos2).normalized() if sp[0] in ["stall", "bench", "campfire"] else -off.normalized()})
	_activity_cache[sid] = out2
	return out2

# ---------------------------------------------------------------- events
func _on_actor_killed(victim, killer) -> void:
	if not is_instance_valid(victim):
		return
	if victim is Actor and not victim.is_player:
		var xp: int = victim.xp_value()
		if victim.team != "summon" and victim.team != "player":
			orbs.burst(victim.global_position, int(xp * 0.65))
			loot.drop_for(victim, killer)
	var k = killer
	if k != null and is_instance_valid(k) and k.owner_actor != null and is_instance_valid(k.owner_actor):
		k = k.owner_actor
	if victim is Boss:
		_on_boss_defeated(victim, k)
	if k != null and is_instance_valid(k) and k.is_player:
		Profile.add_stat("kills")
		Profile.unlock("first_blood")
		if victim.def_id == "mimic":
			Profile.unlock("mimic")
		if victim.record.get("legend", false):
			Profile.unlock("legend_slain")
		if victim.get("role") == "double":
			_on_double_defeated(victim)
		if Profile.char.companion.size() > 0 and player.companion and is_instance_valid(player.companion):
			var cd: Dictionary = Profile.char.companion
			cd.xp = int(cd.get("xp", 0)) + 5
			if cd.xp >= 40 * int(cd.lvl):
				cd.xp = 0
				cd.lvl = int(cd.lvl) + 1
				Events.notify.emit("Спутник вырос: уровень %d" % cd.lvl, Color(0.6, 0.9, 1.0))
	# significant kills enter the chronicle
	var notable: bool = victim.kind == "boss" or victim.record.size() > 0 or victim.elite or (k != null and is_instance_valid(k) and k.record.size() > 0 and randf() < 0.3)
	if notable and victim.kind != "boss":
		Chronicle.record("kill", [k if (k != null and is_instance_valid(k)) else {"id": "unknown", "name": "неизвестный"}, victim], {"pos_v3": victim.global_position})

func _on_boss_defeated(b: Boss, k) -> void:
	if b.has_meta("rift_echo"):
		# a rift's echo: real fight and loot, but the true boss stays untouched
		for i in 2:
			loot.spawn_drop(ItemDB.random_for_era(era, b.level, "boss"), b.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)))
		Chronicle.record("boss_kill", [k if (k != null and is_instance_valid(k)) else {"id": "unknown", "name": "неизвестный"}, b], {"pos_v3": b.global_position, "extra": {"boss": b.display_name}})
		Events.boss_defeated.emit(b)
		if k != null and is_instance_valid(k) and k.is_player:
			Events.banner.emit("Эхо повержено!", b.display_name, Color(1.0, 0.75, 0.9))
		Audio.play_music("rift")
		if dimension != "" and dim_node and dim_node.has_method("on_boss_killed"):
			dim_node.on_boss_killed(b)
		return
	loot.boss_rewards(b)
	var st: Dictionary = Game.world_state.bosses.get(b.boss_id, {})
	st.defeated = true
	st.defeated_day = Game.day()
	Game.world_state.bosses[b.boss_id] = st
	Chronicle.record("boss_kill", [k if (k != null and is_instance_valid(k)) else {"id": "unknown", "name": "неизвестный"}, b], {"pos_v3": b.global_position, "extra": {"boss": b.display_name}})
	Events.boss_defeated.emit(b)
	if k != null and is_instance_valid(k) and k.is_player:
		Profile.boss_defeated(b.boss_id)
		player.purify("boss", b.boss_id)
		Events.banner.emit("Босс повержен!", b.display_name, Color(1.0, 0.85, 0.3))
		if b.boss_id == "chrono_devourer":
			Profile.unlock("ascension")
	Audio.play_music(DBEras.era(era).music if dimension == "" else "rift")
	if dimension != "" and dim_node and dim_node.has_method("on_boss_killed"):
		dim_node.on_boss_killed(b)

func on_boss_escaped(b: Boss, from_actor) -> void:
	var st: Dictionary = Game.world_state.bosses.get(b.boss_id, {})
	st.escaped = int(st.get("escaped", 0)) + 1
	st.returns_at = Game.game_time + 0.4
	Game.world_state.bosses[b.boss_id] = st
	Chronicle.record("boss_escaped", [from_actor if (from_actor != null and is_instance_valid(from_actor)) else {"id": "unknown", "name": "кто-то"}, b], {"pos_v3": b.global_position})
	if legends:
		legends.boss_nemesis(b, st.escaped)

func boss_arena_break(b: Boss) -> void:
	for d in Game.grid.query(b.global_position, 22.0, "destructible"):
		if is_instance_valid(d) and d.get("kind") in ["pillar", "palisade", "crate", "barrel"] and d.has_method("take_hit"):
			d.take_hit(99999.0, "blunt", null)
	for i in 4:
		var p: Vector3 = b.global_position + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
		p.y = ground_height(p)
		Zone.create("fire", b, p, 2.0, 25.0, {"amount": b.base_dmg * 0.3, "dtype": "fire"})
	VFX.shake(0.7)
	Audio.play_sfx("explosion", b.global_position)

func _on_chronicle(ev: Dictionary) -> void:
	if quests:
		quests.on_chronicle(ev)

# ---------------------------------------------------------------- death
func _on_player_died() -> void:
	if _death_pending:
		return
	_death_pending = true
	get_tree().create_timer(1.6, false).timeout.connect(_show_death)

func _show_death() -> void:
	if player == null or not player.is_dead:
		_death_pending = false
		return
	if mode_ctl and mode_ctl.has_method("on_player_died"):
		mode_ctl.on_player_died()
		return
	var lost_text := ""
	if dimension != "" and dim_node and dim_node.expedition:
		lost_text = _lose_rift_loot()
	var gold_lost := int(player.data.gold * 0.2)
	player.data.gold -= gold_lost
	var xp_lost := int(player.data.xp * 0.25)
	player.data.xp -= xp_lost
	orbs.burst(player.global_position, xp_lost)
	var text := "Вы пали у места «%s».\nПотеряно: %d %s и часть опыта.%s" % [place_name(player.global_position), gold_lost, DBEras.era(era).currency, lost_text]
	ui.open("death", {"text": text, "respawn_cb": _respawn})

func _respawn() -> void:
	_death_pending = false
	if dimension != "":
		leave_dimension(false)
	var p := _nearest_respawn()
	if terrain and terrain.has_method("force_load_around"):
		terrain.force_load_around(p)
	p.y = ground_height(p) + 0.3
	player.respawn_at(p)
	player.apply_status("invuln", 4.0)
	for a in Game.actors_near(p, 30.0):
		if is_instance_valid(a) and not a.is_dead and Game.is_enemy(player, a) and a.record.is_empty() and not (a is Boss):
			a.aggro.erase("player")
			if a.global_position.distance_to(p) < 14.0:
				a.queue_free()
	cam.snap()

func _nearest_respawn() -> Vector3:
	var best := player.respawn_point
	if gen:
		var bd := INF
		for poi in gen.pois:
			if poi.type == "shrine":
				var d: float = Vector2(player.global_position.x, player.global_position.z).distance_to(poi.pos)
				if d < bd:
					bd = d
					best = Vector3(poi.pos.x + 3.0, 0, poi.pos.y + 3.0)
		for s in gen.settlements:
			var d2: float = Vector2(player.global_position.x, player.global_position.z).distance_to(s.pos)
			if d2 < bd:
				bd = d2
				best = Vector3(s.pos.x + 4.0, 0, s.pos.y + 4.0)
	return best

# ---------------------------------------------------------------- dimensions
func enter_dimension(kind: String, opts: Dictionary = {}) -> void:
	if dimension != "":
		return
	dim_return = opts.get("return_pos", player.global_position)
	var d := Dimension.new()
	add_child(d)
	d.build(kind, Game.rng.randi(), DIM_OFFSET, era, opts)
	dim_node = d
	dimension = kind
	_rift_picked.clear()
	_apply_dim_env(d)
	var tp: Vector3 = d.player_spawn
	_teleport(player, tp)
	if player.companion and is_instance_valid(player.companion):
		_teleport(player.companion, tp + Vector3(2, 0, 0))
	var boss = opts.get("boss")
	if boss != null and is_instance_valid(boss):
		_teleport(boss, d.center + Vector3(0, 0, -10))
		boss.arena_center = d.center
		boss.can_escape = false
	Audio.play_sfx("portal_enter")
	Audio.play_music("boss" if boss != null or kind == "chronos_trial" else "rift")
	VFX.ring(tp, 4.0, Color(0.6, 0.3, 1.0), 0.8)
	Events.dimension_entered.emit(kind)
	Events.banner.emit(d.title, d.subtitle, Color(0.7, 0.5, 1.0))
	if not Events.item_picked.is_connected(_track_rift_pick):
		Events.item_picked.connect(_track_rift_pick)

func _track_rift_pick(a, it: Dictionary) -> void:
	if a == player and dimension != "":
		_rift_picked.append(it.uid)

func _lose_rift_loot() -> String:
	var n := 0
	for uid in _rift_picked:
		if not player.data.inv.remove(uid).is_empty():
			n += 1
	_rift_picked.clear()
	return "\nДобыча разлома потеряна: %d предм." % n if n > 0 else ""

func leave_dimension(success: bool = true) -> void:
	if dim_node == null or mode != "world":
		return
	var kind := dimension
	dimension = ""
	_rift_picked.clear()
	if terrain and terrain.has_method("force_load_around"):
		terrain.force_load_around(dim_return)
	var back := dim_return
	back.y = ground_height(back) + 0.3
	_teleport(player, back)
	if player.companion and is_instance_valid(player.companion):
		_teleport(player.companion, back + Vector3(2, 0, 0))
	for a in Game.actors_near(dim_node.center, dim_node.radius + 20.0):
		if a != player and a != player.companion and is_instance_valid(a):
			a.queue_free()
	dim_node.queue_free()
	dim_node = null
	_restore_env()
	Audio.play_music(DBEras.era(era).music)
	Audio.play_sfx("portal_enter")
	portal_block_until = Time.get_ticks_msec() + 6000
	player.apply_status("invuln", 2.0)
	Events.dimension_left.emit(kind)

func _teleport(a: Node3D, p: Vector3) -> void:
	a.global_position = p
	if a is CharacterBody3D:
		(a as CharacterBody3D).velocity = Vector3.ZERO
	if a.has_method("reset_physics_interpolation"):
		a.reset_physics_interpolation()
	if a == player:
		cam.snap()
		Events.input_reset.emit()

func _apply_dim_env(d) -> void:
	var e: Environment = env.environment
	_base_env = {"fog": e.fog_light_color, "density": e.fog_density, "sky_top": (e.sky.sky_material as ProceduralSkyMaterial).sky_top_color,
		"sky_hor": (e.sky.sky_material as ProceduralSkyMaterial).sky_horizon_color, "sun": sun.light_color}
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = d.sky_top
	sm.sky_horizon_color = d.sky_horizon
	sm.ground_horizon_color = d.sky_horizon
	e.fog_light_color = d.sky_horizon
	e.fog_density = Settings.fog_value(0.004) * 0.35
	sun.light_color = d.light
	if weather and weather.has_method("set_weather"):
		weather.set_weather("clear", 9999.0)

func _restore_env() -> void:
	if _base_env.is_empty():
		return
	var e: Environment = env.environment
	var sm := e.sky.sky_material as ProceduralSkyMaterial
	sm.sky_top_color = _base_env.sky_top
	sm.sky_horizon_color = _base_env.sky_hor
	sm.ground_horizon_color = _base_env.sky_hor
	e.fog_light_color = _base_env.fog
	e.fog_density = _base_env.density
	sun.light_color = _base_env.sun
	if weather and weather.has_method("set_weather"):
		weather.set_weather("clear", 60.0)

# ---------------------------------------------------------------- special spawns
func spawn_chrono_double(src: Player) -> void:
	var n := NPC.new()
	n.role = "double"
	n.team = "bandit"
	n.archetype = "aggressive"
	n.can_loot = false
	var cd := CharData.new()
	cd.from_dict(src.data.to_dict())
	cd.name = "Хронодвойник"
	n.data = cd
	n.display_name = "Хронодвойник " + src.data.name
	n.brain = ChronoBrain.new(n, src.action_buffer.duplicate())
	var look: Dictionary = src.rig.look.duplicate()
	look.glow = Color(0.4, 1.0, 0.9)
	var r := HumanoidRig.new()
	r.setup(look)
	n.set_rig(r)
	var p: Vector3 = src.global_position + src.facing * 6.0
	p.y = ground_height(p) + 0.2
	actors_root.add_child(n)
	n.global_position = p
	n.reset_physics_interpolation()
	n.refresh_gear()
	n.hp = n.max_hp
	n.add_aggro(src, 999.0)
	VFX.ring(p, 3.0, Color(0.4, 1.0, 0.9), 0.8)
	Audio.play_sfx("time_slow", p)
	Events.banner.emit("Хронодвойник", "Время отразило вас. Победите себя.", Color(0.4, 1.0, 0.9))

func _on_double_defeated(d) -> void:
	Profile.unlock("chrono_double")
	Profile.milestone("chrono_double")
	var it := ItemDB.random_for_era(era, player.level, "boss")
	it.history.append("Награда за победу над собственным хронодвойником")
	loot.spawn_drop(it, d.global_position)
	Chronicle.record("chrono_double", [player], {"pos_v3": d.global_position, "extra": {"outcome": "Двойник повержен."}})

func summon_companion(owner_a: Player, announce: bool = true) -> void:
	if owner_a.companion and is_instance_valid(owner_a.companion) and not owner_a.companion.is_dead:
		owner_a.companion.queue_free()
	var p: Vector3 = owner_a.global_position + Vector3(2, 0, 1)
	owner_a.companion = spawner.spawn_companion(owner_a, p)
	if announce:
		Events.banner.emit("Новый спутник", owner_a.companion.display_name, Color(0.6, 0.9, 1.0))

# ---------------------------------------------------------------- eras
func change_era(new_era: int) -> void:
	if not Profile.is_era_unlocked(new_era):
		return
	sync_to_state()
	Legacy.on_leave_era(self, era, new_era)
	SaveSys.save_game()
	Profile.current_era = new_era
	for it in player.data.inv.all_equipped() + player.data.inv.items:
		if it.get("living", {}).size() > 0 or it.get("rarity", 0) >= 4:
			if int(it.get("era_seen", era)) != new_era:
				LivingWeapon.tech_upgrade(it, new_era)
				it.era_seen = new_era
	Game.world_state = {}
	SaveSys.save_game()
	Audio.play_sfx("era_transition")
	Audio.play_sting("era_unlock")
	Game.start("world")

# ---------------------------------------------------------------- persistence
func sync_to_state() -> void:
	if mode != "world":
		return
	Game.world_state.time = Game.game_time
	if player and is_instance_valid(player) and dimension == "":
		Game.world_state.player_pos = [player.global_position.x, player.global_position.y, player.global_position.z]
	elif dimension != "":
		Game.world_state.player_pos = [dim_return.x, dim_return.y, dim_return.z]
	if factions:
		factions.save_state()
	if legends:
		legends.save_state()
	if sim:
		sim.save_state()
	if quests:
		quests.save_state()
	if director:
		director.save_state()

func on_back_pressed() -> void:
	if ui and ui.is_open():
		ui.close_top()
	elif ui:
		ui.open("pause")

class FallbackUI:
	extends CanvasLayer
	func open(_n: String, _a := {}) -> void:
		pass
	func close_top() -> void:
		pass
	func close_all() -> void:
		pass
	func is_open() -> bool:
		return false
