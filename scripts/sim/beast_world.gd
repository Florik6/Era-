class_name BeastWorld
extends Node
## «Beasts of the Ages» in the living world.
##
## · Ecology: creatures of the era live by habitat (biome tags of DBCreatures),
##   appear around the hero out of sight, in groups for herd species, never
##   inside settlements (cities stay peaceful), with hard caps per quality
##   tier; far ones are removed. Peaceful species sleep at night (brain).
## · Rare variants (Альфа, Древний, Кристальный…): stronger, own glow,
##   better loot, recorded in the bestiary.
## · Lairs: creature dens away from towns: an elite with its pack and a cache,
##   respawning after a few days.
## · World boss director: the era's bosses without a dungeon live in lairs in
##   the wild. Rumours first, then traces near the lair, then the lair is
##   known. A world boss is leashed to its lair: it never walks to towns.
## · Hunting contracts at settlements target real creatures: a specific
##   marked beast spawned at its den, or N of a species.
## · Bestiary (Profile.bestiary): seen → studied (kills) → mastered, with
##   weaknesses opened progressively; bosses with their own records.
## · Boss loot: materials, trophy (once), relic (defined chance, never a
##   duplicate), an era legendary from the catalogue; one reward per kill.

static var inst: BeastWorld = null

const VARIANTS := {
	"alpha": {"name": "Альфа", "hp": 1.8, "dmg": 1.35, "scale": 1.18, "glow": Color(1.0, 0.85, 0.3)},
	"ancient": {"name": "Древний", "hp": 2.4, "dmg": 1.5, "scale": 1.3, "glow": Color(0.6, 0.9, 1.0)},
	"crystal": {"name": "Кристальный", "hp": 1.6, "dmg": 1.2, "scale": 1.08, "glow": Color(0.55, 0.8, 1.0), "res": {"slash": 0.3, "pierce": 0.3, "blunt": -0.3}},
	"plague": {"name": "Чумной", "hp": 1.5, "dmg": 1.2, "scale": 1.05, "glow": Color(0.6, 1.0, 0.3), "res": {"poison": 0.8}},
	"burning": {"name": "Пылающий", "hp": 1.5, "dmg": 1.25, "scale": 1.05, "glow": Color(1.0, 0.5, 0.15), "dtype": "fire", "res": {"fire": 0.8, "ice": -0.4}},
	"shadow": {"name": "Теневой", "hp": 1.4, "dmg": 1.3, "scale": 1.0, "glow": Color(0.6, 0.3, 1.0), "res": {"dark": 0.7, "light": -0.5}},
}
const VARIANT_CHANCE := 0.03
const ERA_OUTDOOR := [[], ["coast", "urban"], ["industrial"], ["urban", "anomaly"], ["anomaly", "urban"]]
const BIOME_TAGS := {"forest": ["forest"], "plains": ["plains", "forest"], "mountain": ["mountain"], "snow": ["snow", "mountain"], "swamp": ["swamp", "coast"], "sand": ["sand"]}
const ECO_NEAR := 95.0
const ECO_FAR := 150.0
const LAIRS_PER_ERA := 6

var world
var state := {}
var eco: Array = []                 # live ecology creatures
var lair_mobs := {}                 # lair id -> Array of actors
var lair_marks := {}                # lair id -> claw-mark nodes
var wboss := {}                     # boss id -> Boss (spawned world bosses)
var hunt_targets := {}              # quest id -> Actor
var leads := {}                     # dungeon id -> {stage, hunter}
var stats := {"eco_spawned": 0, "eco_removed": 0, "eco_blocked_town": 0, "variants": 0, "lairs": 0, "lair_spawns": 0,
	"wb_stage_ups": 0, "wb_spawned": 0, "hunts_offered": 0, "hunts_spawned": 0, "boss_loot": 0, "bestiary_new": 0}
var enabled := true                 # tests switch the living-world part off (like EventDirector2)
var _t := 0.0
var _eco_t := 1.0
var _seen_t := 0.0

func setup(w) -> void:
	world = w
	inst = self
	state = Game.world_state.get("beasts", {})
	for k in ["lairs", "world_bosses", "hunts", "kills", "rewarded", "leads"]:
		if not state.has(k):
			state[k] = {} if k != "lairs" else []
	Game.world_state["beasts"] = state
	if state.lairs.is_empty() and world.get("gen") != null and world.gen != null:
		_make_lairs()
	_init_world_bosses()
	if not Events.actor_killed.is_connected(_on_killed):
		Events.actor_killed.connect(_on_killed)

# =================================================================== ecology
func eco_cap() -> int:
	var q := int(Settings.effective_quality)
	return [4, 6, 8, 8, 9][clampi(q, 0, 4)]

func _process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	var dt := _t
	_t = 0.0
	if world == null or world.player == null or not is_instance_valid(world.player) or world.mode != "world":
		return
	# the bestiary notices creatures everywhere, dungeons included
	_seen_t -= dt
	if _seen_t <= 0.0:
		_seen_t = 1.5
		_scan_seen(world.player.global_position)
	if world.dimension != "":
		# the hero is in a dungeon or rift: wild creatures out there are not kept alive
		if not eco.is_empty():
			for m in eco:
				if is_instance_valid(m) and not m.is_dead:
					m.queue_free()
					stats.eco_removed += 1
			eco.clear()
		return
	if not enabled:
		return
	var pp: Vector3 = world.player.global_position
	_eco_t -= dt
	if _eco_t <= 0.0:
		_eco_t = 3.0
		_tick_ecology(pp)
		_tick_lairs(pp)
		_tick_world_bosses(pp)
		_tick_hunts(pp)
		_tick_leads(pp)

func live_eco() -> Array:
	eco = eco.filter(func(m): return is_instance_valid(m) and not m.is_dead)
	return eco

func _tick_ecology(pp: Vector3) -> void:
	# remove the far ones (not while they hunt the hero)
	for m in live_eco():
		var d: float = m.global_position.distance_to(pp)
		var hunting: bool = m.brain != null and m.brain.get("target") == world.player
		if d > ECO_FAR and (not hunting or d > ECO_FAR * 1.6):
			m.queue_free()
			stats.eco_removed += 1
	var near := 0
	for m in live_eco():
		if m.global_position.distance_to(pp) < ECO_NEAR:
			near += 1
	if near >= eco_cap():
		return
	spawn_ecology_near(pp)

## One encounter of the habitat around a point out of sight of the hero.
func spawn_ecology_near(pp: Vector3, rng: RandomNumberGenerator = null) -> Array:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var out: Array = []
	for attempt in 6:
		var a := r.randf() * TAU
		var p := pp + Vector3(cos(a), 0, sin(a)) * r.randf_range(42.0, 70.0)
		if not spawn_allowed(p):
			continue
		var cands := candidates_at(p)
		# near a town only peaceful animals appear: predators never hunt the hero into a city
		if near_town(pp):
			cands = cands.filter(func(e): return e.get("beh_peaceful", false))
		if cands.is_empty():
			continue
		var def: Dictionary = cands[r.randi() % cands.size()]
		var n := 1
		if def.beh in ["herd", "swarm"]:
			n = r.randi_range(2, 4)
		elif def.beh == "predator" and def.cat == "common":
			n = r.randi_range(1, 3)
		n = mini(n, eco_cap() - live_eco().size())
		for i in maxi(n, 1):
			var q: Vector3 = p + Vector3(r.randf_range(-3, 3), 0, r.randf_range(-3, 3))
			q.y = world.ground_height(q) + 0.3
			var m = world.spawner.spawn_enemy(def.id, q, -1)
			if m == null:
				continue
			m.set_meta("eco", true)
			if m.get("home") != null:
				m.home = p
			maybe_variant(m, r)
			eco.append(m)
			out.append(m)
			stats.eco_spawned += 1
		return out
	return out

func near_town(p: Vector3) -> bool:
	if world.get("gen") == null or world.gen == null:
		return false
	for st in world.gen.settlements:
		if Vector2(p.x, p.z).distance_to(st.pos) < float(st.radius) * 2.0 + 70.0:
			return true
	return false

## Never inside settlements (city peace), never in water, not in dimensions.
func spawn_allowed(p: Vector3) -> bool:
	if world.get("gen") == null or world.gen == null:
		return true
	if world.gen.settlement_at(p.x, p.z, 1.6) != null:
		stats.eco_blocked_town += 1
		return false
	if world.is_water(p):
		return false
	return true

## Species that live here (biome tags + era outdoor tags), never the cave- or
## lab-only ones (those live in dungeons) and rarely elites.
func candidates_at(p: Vector3) -> Array:
	var era := Profile.current_era
	var biome := "plains"
	if world.get("gen") != null and world.gen != null:
		biome = world.gen.biome(p.x, p.z)
	var tags: Array = BIOME_TAGS.get(biome, ["plains"]).duplicate()
	tags.append_array(ERA_OUTDOOR[clampi(era, 0, 4)])
	var night := Game.is_night()
	var out: Array = []
	for e in DBCreatures.of_era(era):
		if e.cat == "miniboss":
			continue
		var ok := false
		for t in e.hab:
			if t in tags:
				ok = true
		if not ok:
			continue
		var w := 3 if e.cat == "common" else (2 if e.cat == "dangerous" else 1)
		if e.get("nocturnal", false) and not night:
			w = 0
		if e.get("beh_peaceful", false) and night:
			w = 1
		for i in w:
			out.append(e)
	return out

## A rare variant: stronger, its own glow and title, better loot.
static func maybe_variant(m, rng: RandomNumberGenerator = null, force := "") -> String:
	if m == null or not is_instance_valid(m) or m is Boss:
		return ""
	if not m.has_meta("species"):
		return ""
	var roll := rng.randf() if rng != null else randf()
	if force == "" and roll > VARIANT_CHANCE:
		return ""
	var keys := VARIANTS.keys()
	var vk: String = force if force != "" else str(keys[(rng.randi() if rng != null else randi()) % keys.size()])
	var v: Dictionary = VARIANTS[vk]
	m.max_hp *= float(v.hp)
	m.hp = m.max_hp
	m.base_dmg *= float(v.dmg)
	m.elite = true
	m.display_name = "%s %s" % [v.name, m.display_name]
	if v.has("dtype"):
		m.natural_dtype = v.dtype
	for k in v.get("res", {}):
		m.resist[k] = float(m.resist.get(k, 0.0)) + float(v.res[k])
	if m.rig != null and is_instance_valid(m.rig):
		m.rig.scale *= float(v.scale)
		if m.rig.has_method("set_glow"):
			m.rig.set_glow(v.glow)
	m.set_meta("variant", vk)
	if inst != null:
		inst.stats.variants += 1
	if Game.world and Game.world.spawner:
		Game.world.spawner.name_tag(m, v.glow)
	return vk

# =================================================================== lairs
func _make_lairs() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(Profile.world_seed) + "lairs" + str(Profile.current_era))
	var era := Profile.current_era
	var dens: Array = DBCreatures.of_era(era).filter(func(e): return e.cat in ["dangerous", "elite"] and not e.get("beh_peaceful", false))
	if dens.is_empty():
		return
	var half: float = world.gen.get("half") if world.gen.get("half") != null else 900.0
	var made := 0
	for i in 200:
		if made >= LAIRS_PER_ERA:
			break
		var p := Vector2(r.randf_range(-half + 120, half - 120), r.randf_range(-half + 120, half - 120))
		if world.gen.settlement_at(p.x, p.y, 3.0) != null:
			continue
		if world.gen.is_water(p.x, p.y):
			continue
		var cands := candidates_at(Vector3(p.x, 0, p.y)).filter(func(e): return e.cat in ["dangerous", "elite"] and not e.get("beh_peaceful", false))
		var e: Dictionary = (cands if not cands.is_empty() else dens)[r.randi() % (cands.size() if not cands.is_empty() else dens.size())]
		state.lairs.append({"id": "lair_%d_%d" % [era, made], "species": e.id, "pos": [p.x, p.y], "cleared_day": -99, "chest": false})
		made += 1
	stats.lairs = made

func _tick_lairs(pp: Vector3) -> void:
	for l in state.lairs:
		var lp := Vector3(float(l.pos[0]), 0, float(l.pos[1]))
		var d := Vector2(lp.x - pp.x, lp.z - pp.z).length()
		var mobs: Array = lair_mobs.get(l.id, [])
		mobs = mobs.filter(func(m): return is_instance_valid(m))
		if d > 170.0:
			for m in mobs:
				if not m.is_dead:
					m.queue_free()
			lair_mobs.erase(l.id)
			for cm in lair_marks.get(l.id, []):
				if is_instance_valid(cm):
					cm.queue_free()
			lair_marks.erase(l.id)
			continue
		if d < 90.0 and mobs.is_empty() and Game.day() - int(l.cleared_day) >= 3:
			spawn_lair(l)
		elif not mobs.is_empty():
			var alive := mobs.filter(func(m): return not m.is_dead)
			if alive.is_empty() and Game.day() - int(l.cleared_day) >= 3:
				l.cleared_day = Game.day()
				lair_mobs.erase(l.id)
				var lvl: int = world.spawner.level_near_player(1)
				var it := ItemDB.random_for_era(Profile.current_era, lvl, "elite")
				lp.y = world.ground_height(lp)
				world.loot.spawn_drop(it, lp + Vector3(0, 0.3, 0))
				var mat := _species_mat(str(l.species))
				if mat != "":
					var mi := ItemDB.create(mat, 0, 1)
					mi.qty = 2
					world.loot.spawn_drop(mi, lp + Vector3(1, 0.3, 0))
				Events.notify.emit("Логово зачищено", Color(0.9, 0.8, 0.5))
				Chronicle.record("lair_cleared", [world.player], {"pos_v3": lp, "extra": {"species": DBCreatures.get_def(str(l.species)).get("name", "")}})

func spawn_lair(l: Dictionary) -> Array:
	var lp := Vector3(float(l.pos[0]), 0, float(l.pos[1]))
	lp.y = world.ground_height(lp)
	var out: Array = []
	var leader = world.spawner.spawn_enemy(str(l.species), lp + Vector3(0, 0.3, 0), world.spawner.level_near_player(2))
	if leader:
		leader.set_meta("lair", l.id)
		if leader.get("home") != null:
			leader.home = lp
		maybe_variant(leader, null, "alpha")
		out.append(leader)
	var e: Dictionary = DBCreatures.get_def(str(l.species))
	var pack: Array = DBCreatures.of_era(int(e.get("era", 0))).filter(func(x): return x.cat == "common" and not x.get("beh_peaceful", false) and _shares_hab(x, e))
	for i in 2:
		if pack.is_empty():
			break
		var pid: String = pack[randi() % pack.size()].id
		var m = world.spawner.spawn_enemy(pid, lp + Vector3(randf_range(-4, 4), 0.3, randf_range(-4, 4)), -1)
		if m:
			m.set_meta("lair", l.id)
			out.append(m)
	# den dressing: bones and scratched stones, so the place reads as a lair
	for i in 4:
		var cp := lp + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		cp.y = world.ground_height(cp) + 0.02
		var cm := claw_mark(world.fx_root, cp, randf() * TAU, 1.2)
		if not lair_marks.has(l.id):
			lair_marks[l.id] = []
		lair_marks[l.id].append(cm)
	lair_mobs[l.id] = out
	stats.lair_spawns += 1
	return out

func _shares_hab(a: Dictionary, b: Dictionary) -> bool:
	for t in a.hab:
		if t in b.hab:
			return true
	return false

func _species_mat(sid: String) -> String:
	var e := DBCreatures.get_def(sid)
	for l in e.get("loot", []):
		if BeastItems.has(str(l[0])) or ItemDB.base(str(l[0])).size() > 0:
			return str(l[0])
	return ""

# =================================================================== world bosses
## Bosses of the era without a dungeon: rumour → traces → known lair.
func world_boss_ids(era: int = -1) -> Array:
	var e := Profile.current_era if era < 0 else era
	var out: Array = []
	for b in DBBeasts.bosses_of_era(e):
		if str(b.get("dungeon", "")) == "" or not DBBeasts.dungeons().has(str(b.get("dungeon", ""))):
			out.append(b.id)
	return out

func _init_world_bosses() -> void:
	if world.get("gen") == null or world.gen == null:
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(Profile.world_seed) + "wboss" + str(Profile.current_era))
	var half: float = world.gen.get("half") if world.gen.get("half") != null else 900.0
	for bid in world_boss_ids():
		if state.world_bosses.has(bid):
			continue
		var pos := Vector2.ZERO
		for i in 300:
			var p := Vector2(r.randf_range(-half + 150, half - 150), r.randf_range(-half + 150, half - 150))
			if _far_from_towns(p, 320.0) and not world.gen.is_water(p.x, p.y):
				pos = p
				break
		state.world_bosses[bid] = {"stage": 0, "pos": [pos.x, pos.y], "next_day": Game.day() + 1 + r.randi_range(0, 2), "defeated": false}

func _far_from_towns(p: Vector2, dist: float) -> bool:
	for s in world.gen.settlements:
		if p.distance_to(s.pos) < dist + float(s.radius):
			return false
	return true

const WB_STAGES := ["слухи", "следы", "логово"]

func _tick_world_bosses(pp: Vector3) -> void:
	for bid in state.world_bosses:
		var st: Dictionary = state.world_bosses[bid]
		if st.defeated:
			continue
		var bd: Dictionary = DBBeasts.boss(bid)
		if int(st.stage) < 2 and Game.day() >= int(st.next_day):
			advance_world_boss(bid)
		var lp := Vector3(float(st.pos[0]), 0, float(st.pos[1]))
		var d := Vector2(lp.x - pp.x, lp.z - pp.z).length()
		# traces around the lair once the rumour turned into tracks
		if int(st.stage) >= 1 and d < 140.0 and not st.get("traces_shown", false):
			st.traces_shown = true
			for i in 6:
				var a := float(i) / 6.0 * TAU
				var tp := lp + Vector3(cos(a), 0, sin(a)) * randf_range(25.0, 45.0)
				tp.y = world.ground_height(tp) + 0.02
				var cm := claw_mark(world.fx_root, tp, randf() * TAU, 3.0)
				cm.set_meta("wb_trace", bid)
			Events.notify.emit("Огромные следы: где-то рядом %s" % bd.get("name", "чудовище"), Color(1.0, 0.6, 0.4))
		var b = wboss.get(bid)
		if int(st.stage) >= 2 and d < 110.0 and (b == null or not is_instance_valid(b)):
			spawn_world_boss(bid)
		elif b != null and is_instance_valid(b) and d > 220.0 and not b.is_dead:
			b.queue_free()
			wboss.erase(bid)

func advance_world_boss(bid: String) -> void:
	var st: Dictionary = state.world_bosses[bid]
	st.stage = mini(2, int(st.stage) + 1)
	st.next_day = Game.day() + 1
	stats.wb_stage_ups += 1
	var bd: Dictionary = DBBeasts.boss(bid)
	match int(st.stage):
		1:
			Events.notify.emit("Слухи: путники видели %s в глуши" % bd.get("name", "чудовище"), Color(1.0, 0.75, 0.45))
		2:
			Events.notify.emit("Логово найдено: %s" % bd.get("name", "чудовище"), Color(1.0, 0.5, 0.35))
			Chronicle.record("rumour", [{"id": bid, "name": bd.get("name", "")}], {"pos_v3": Vector3(float(st.pos[0]), 0, float(st.pos[1])), "extra": {"text": "Логово найдено"}})

func spawn_world_boss(bid: String):
	var st: Dictionary = state.world_bosses[bid]
	var lp := Vector3(float(st.pos[0]), 0, float(st.pos[1]))
	lp.y = world.ground_height(lp)
	var b = world.spawner.spawn_boss(bid, lp + Vector3(0, 0.5, 0), world.spawner.level_near_player(int(DBBeasts.boss(bid).get("lvl", 6)) / 3))
	if b == null:
		return null
	b.arena_center = lp
	b.leash_radius = 38.0
	b.lair_id = "wb_" + bid
	b.can_escape = false
	wboss[bid] = b
	stats.wb_spawned += 1
	return b

## Markers for the map: known world-boss lairs and creature dens.
func map_markers() -> Array:
	var out: Array = []
	for bid in state.get("world_bosses", {}):
		var st: Dictionary = state.world_bosses[bid]
		if int(st.stage) >= 2:
			out.append({"pos": Vector2(float(st.pos[0]), float(st.pos[1])), "kind": "lair", "name": DBBeasts.boss(bid).get("name", "Логово"),
				"color": Color(0.45, 0.45, 0.45) if st.defeated else Color(1.0, 0.3, 0.2)})
	return out

func rumour_line() -> String:
	for bid in state.get("world_bosses", {}):
		var st: Dictionary = state.world_bosses[bid]
		if not st.defeated and int(st.stage) <= 1:
			return "«Говорят, в глуши бродит %s. Охотники боятся туда ходить»." % DBBeasts.boss(bid).get("name", "чудовище")
	return ""

# =================================================================== hunts
## Two contracts per settlement: a marked beast at its den, and a cull.
func hunt_offers(s: Dictionary, qs) -> Array:
	var out: Array = []
	var era := Profile.current_era
	var lvl: int = world.player.level if world.player else 1
	var gmul := (era + 1) * 30
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(s.id) + str(Game.day()))
	var pool: Array = DBCreatures.of_era(era).filter(func(e): return e.cat in ["dangerous", "elite"] and not e.get("beh_peaceful", false) and _outdoor(e))
	if not pool.is_empty():
		var e: Dictionary = pool[r.randi() % pool.size()]
		var sp := Vector2(s.pos.x, s.pos.y)
		var p := sp
		for i in 60:
			var a := r.randf() * TAU
			var c := sp + Vector2(cos(a), sin(a)) * r.randf_range(140.0, 260.0)
			if world.gen.settlement_at(c.x, c.y, 1.8) == null and not world.gen.is_water(c.x, c.y):
				p = c
				break
		var tid := "hunt_%d" % (hash(str(s.id) + e.id + str(Game.day())) & 0xffffff)
		out.append(qs._q("hunt", "Охота: матёрый %s" % String(e.name).to_lower(), "Охотники %s выследили матёрого зверя — %s. Он задрал скот у дорог. Найдите логово и убейте его." % [s.name, e.name],
			[qs._obj("kill_target", "Убить: матёрый %s" % String(e.name).to_lower(), 1, {"target_id": tid, "pos": [p.x, p.y]})],
			{"gold": gmul * 3, "xp": 180 + lvl * 20, "item": "elite"}, {"giver": s.name, "hunt_species": e.id, "hunt_pos": [p.x, p.y], "hunt_tid": tid}))
	var commons: Array = DBCreatures.of_era(era).filter(func(e): return e.cat == "common" and not e.get("beh_peaceful", false) and _outdoor(e))
	if not commons.is_empty():
		var c2: Dictionary = commons[r.randi() % commons.size()]
		var need := 4 + era
		out.append(qs._q("hunt", "Отстрел: %s" % c2.name, "Расплодились %s. Сократите их число в округе %s." % [String(c2.name).to_lower(), s.name],
			[qs._obj("kill_species", "Убить: %s" % c2.name, need, {"species": c2.id})], {"gold": gmul * 2, "xp": 120 + lvl * 15}, {"giver": s.name, "hunt_species": c2.id}))
	stats.hunts_offered += out.size()
	return out

func _outdoor(e: Dictionary) -> bool:
	var tags: Array = ["forest", "plains", "mountain", "snow", "swamp", "sand"] + ERA_OUTDOOR[clampi(int(e.era), 0, 4)]
	for t in e.hab:
		if t in tags:
			return true
	return false

func on_hunt_accepted(q: Dictionary) -> void:
	if q.has("hunt_tid"):
		state.hunts[q.id] = {"tid": q.hunt_tid, "species": q.hunt_species, "pos": q.hunt_pos}

func _tick_hunts(pp: Vector3) -> void:
	for qid in state.hunts.keys():
		var h: Dictionary = state.hunts[qid]
		var active := false
		for q in world.quests.active():
			if q.id == qid:
				active = true
		if not active:
			state.hunts.erase(qid)
			var t0 = hunt_targets.get(qid)
			if t0 != null and is_instance_valid(t0) and not t0.is_dead:
				t0.queue_free()
			hunt_targets.erase(qid)
			continue
		var hp := Vector3(float(h.pos[0]), 0, float(h.pos[1]))
		var t = hunt_targets.get(qid)
		var d := Vector2(hp.x - pp.x, hp.z - pp.z).length()
		if (t == null or not is_instance_valid(t)) and d < 120.0:
			spawn_hunt_target(qid)
		elif t != null and is_instance_valid(t) and not t.is_dead and d > 220.0:
			t.queue_free()
			hunt_targets.erase(qid)

func spawn_hunt_target(qid: String):
	var h: Dictionary = state.hunts[qid]
	var hp := Vector3(float(h.pos[0]), 0, float(h.pos[1]))
	hp.y = world.ground_height(hp) + 0.3
	var m = world.spawner.spawn_enemy(str(h.species), hp, world.spawner.level_near_player(2))
	if m == null:
		return null
	m.actor_id = str(h.tid)
	m.max_hp *= 1.6
	m.hp = m.max_hp
	m.base_dmg *= 1.2
	m.elite = true
	m.display_name = "Матёрый " + m.display_name.to_lower()
	m.set_meta("hunt", qid)
	if m.get("home") != null:
		m.home = hp
	world.spawner.name_tag(m, Color(1.0, 0.7, 0.3))
	hunt_targets[qid] = m
	stats.hunts_spawned += 1
	return m

# =================================================================== leads (dungeon story hooks)
## «Пробуждение Чёрного Камня»: near the first dungeon of the era the hero
## finds claw tracks, then a wounded hunter who points at the cave.
func _tick_leads(pp: Vector3) -> void:
	if world.get("gen") == null or world.gen == null:
		return
	for p in world.gen.pois:
		if p.type != "dungeon" or not p.get("data", {}).has("beast_dungeon"):
			continue
		var did: String = p.data.beast_dungeon
		var dd: Dictionary = DBBeasts.dungeon(did)
		if int(dd.get("n", 0)) != 1:
			continue
		var ds: Dictionary = Game.world_state.get("dungeons", {}).get(did, {})
		if ds.get("boss_dead", false):
			continue
		var d: float = Vector2(pp.x, pp.z).distance_to(p.pos)
		var l: Dictionary = state.leads.get(did, {"stage": 0})
		state.leads[did] = l
		if d < 160.0 and int(l.stage) == 0:
			start_lead(did, p)
		elif d < 160.0 and int(l.stage) >= 1 and not leads.has(did):
			_restore_lead(did, l)

## After loading a save: the tracks and (if still needed) the hunter return.
func _restore_lead(did: String, l: Dictionary) -> void:
	var tnode := Node3D.new()
	tnode.name = "BeastTracks_" + did
	world.add_child(tnode)
	for t in l.get("tracks", []):
		var tp := Vector3(float(t[0]), 0, float(t[1]))
		tp.y = world.ground_height(tp) + 0.02
		claw_mark(tnode, tp, 0.0, 1.4)
	var h = null
	if int(l.stage) == 1 and l.has("hunter_pos"):
		var hp := Vector3(float(l.hunter_pos[0]), 0, float(l.hunter_pos[1]))
		hp.y = world.ground_height(hp) + 0.3
		h = spawn_wounded_hunter(hp, did)
	leads[did] = {"hunter": h, "tracks": tnode}

func start_lead(did: String, p: Dictionary) -> Dictionary:
	var l: Dictionary = state.leads.get(did, {"stage": 0})
	state.leads[did] = l
	var cave := Vector3(p.pos.x, 0, p.pos.y)
	var pl = world.player
	var from: Vector3 = pl.global_position if pl else cave + Vector3(60, 0, 0)
	var dir := (cave - from)
	dir.y = 0
	var dist := dir.length()
	dir = dir.normalized() if dist > 0.1 else Vector3.FORWARD
	# a trail of claw tracks from the hero towards the cave
	var tracks: Array = []
	var tnode := Node3D.new()
	tnode.name = "BeastTracks_" + did
	world.add_child(tnode)
	var n := clampi(int(dist / 9.0), 4, 14)
	for i in n:
		var tp := from + dir * (dist * (0.15 + 0.8 * float(i) / float(n))) + dir.cross(Vector3.UP) * sin(i * 1.3) * 1.5
		tp.y = world.ground_height(tp) + 0.02
		claw_mark(tnode, tp, atan2(dir.x, dir.z), 1.4)
		tracks.append([tp.x, tp.z])
	l.tracks = tracks
	# the wounded hunter halfway, off the trail
	var hp := from + dir * dist * 0.55 + dir.cross(Vector3.UP) * 3.0
	hp.y = world.ground_height(hp) + 0.3
	var h = spawn_wounded_hunter(hp, did)
	l.stage = 1
	l.hunter_pos = [hp.x, hp.z]
	stats.leads = int(stats.get("leads", 0)) + 1
	Events.notify.emit("Странные следы когтей на земле…", Color(0.95, 0.8, 0.55))
	leads[did] = {"hunter": h, "tracks": tnode}
	return l

func spawn_wounded_hunter(pos: Vector3, did: String):
	var n: NPC = world.spawner.spawn_villager({"id": "", "owner": ""}, pos, "villager")
	if n == null:
		return null
	n.display_name = "Раненый охотник"
	n.hp = n.max_hp * 0.3
	n.set_meta("wounded", true)
	n.set_meta("talk_cb", func(npc): hunter_dialog(npc, did))
	n.brain = null           # too weak to walk: stays where he fell
	n.move_input = Vector3.ZERO
	world.spawner.name_tag(n, Color(1.0, 0.75, 0.5))
	return n

func hunter_dialog(n, did: String) -> void:
	var dd: Dictionary = DBBeasts.dungeon(did)
	var bd: Dictionary = DBBeasts.boss(str(dd.boss))
	var l: Dictionary = state.leads.get(did, {"stage": 1})
	var opts: Array = []
	var text := ""
	if str(dd.boss) == "garmon":
		text = "«Не подходи к пещере… Там, в «%s», проснулось нечто. Камень ожил — %s. Моих товарищей раздавило, как орехи. Я видел, как он сбрасывает пластины на спине — под ними светится руда… Бей туда, если хватит духу»." % [dd.name, bd.get("name", "чудовище")]
	else:
		text = "«Не ходи туда… В «%s» проснулось нечто — %s. Мы шли по следу и не вернулись все. %s»" % [dd.name, bd.get("name", "чудовище"), String(bd.get("desc", ""))]
	if int(l.stage) < 2:
		opts.append({"text": "Перевязать раны (бинт)", "cb": func():
			var pl = world.player
			if pl.data.inv.count("bandage") > 0:
				pl.data.inv.consume("bandage", 1)
			n.hp = n.max_hp * 0.8
			l.stage = 2
			var q: Dictionary = world.quests._q("lead", "Пробуждение Чёрного Камня", "Раненый охотник рассказал о чудовище в пещере «%s»." % dd.name,
				[world.quests._obj("boss", "Победить: %s" % bd.get("name", "?"), 1, {"boss_id": str(dd.boss), "pos": _dungeon_pos(did)})],
				{"gold": 200, "xp": 400}, {"giver": "Раненый охотник"})
			world.quests.accept(q)
			Events.notify.emit("Охотник: «Спасибо… Вход — к северу, у скал»", Color(0.9, 0.85, 0.6))})
	opts.append({"text": "Уйти", "cb": func(): pass})
	world.ui.open("dialog", {"title": n.display_name, "text": text, "portrait_color": Color(0.7, 0.5, 0.35), "options": opts})

func _dungeon_pos(did: String) -> Array:
	for p in world.gen.pois:
		if p.type == "dungeon" and p.get("data", {}).get("beast_dungeon", "") == did:
			return [p.pos.x, p.pos.y]
	return [0.0, 0.0]

## Claw marks: three dark grooves on the ground (own geometry, so they are
## never recycled by the decal pool).
static func claw_mark(parent: Node3D, pos: Vector3, rot: float, scl := 1.0) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.global_position = pos
	n.rotation.y = rot
	var mat := MeshLib.mat(Color(0.08, 0.06, 0.05), 0.0, 1.0)
	for i in 3:
		var g := MeshLib.part(n, MeshLib.box(Vector3(0.07 * scl, 0.02, 0.75 * scl)), mat, Vector3((i - 1) * 0.16 * scl, 0.01, 0.0), Vector3(0, (i - 1) * 6.0, 0), Vector3.ONE, false)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

# =================================================================== bestiary
static func book() -> Dictionary:
	return Profile.bestiary

static func entry(id: String) -> Dictionary:
	var b := book()
	if not b.has(id):
		b[id] = {"seen": 0, "kills": 0, "first_day": Game.day(), "variants": {}}
		if inst != null:
			inst.stats.bestiary_new += 1
	return b[id]

## Knowledge level: 0 unknown, 1 seen, 2 studied (3 kills, 1 for bosses), 3 mastered (10 kills)
static func knowledge(id: String) -> int:
	var b := book()
	if not b.has(id):
		return 0
	var e: Dictionary = b[id]
	var k := int(e.get("kills", 0))
	if DBBeasts.has_boss(id):
		return 3 if k >= 1 else 1
	if k >= 10:
		return 3
	if k >= 3:
		return 2
	return 1

func _scan_seen(pp: Vector3) -> void:
	for a in Game.actors_near(pp, 26.0):
		if a.is_dead:
			continue
		var sid := ""
		if a is Boss and DBBeasts.has_boss(a.boss_id):
			sid = a.boss_id
		elif a.has_meta("species"):
			sid = str(a.get_meta("species"))
		if sid == "":
			continue
		var e := entry(sid)
		if int(e.seen) == 0:
			Events.notify.emit("Бестиарий: %s" % _name_of(sid), Color(0.8, 0.9, 1.0))
		e.seen = int(e.seen) + 1

static func _name_of(id: String) -> String:
	if DBBeasts.has_boss(id):
		return DBBeasts.boss(id).name
	return DBCreatures.get_def(id).get("name", id)

func _on_killed(victim, killer) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var k = killer
	if k != null and is_instance_valid(k) and k.get("owner_actor") != null and is_instance_valid(k.owner_actor):
		k = k.owner_actor
	if k == null or not is_instance_valid(k) or not k.is_player:
		return
	var sid := ""
	if victim is Boss and DBBeasts.has_boss(victim.boss_id):
		sid = victim.boss_id
	elif victim.has_meta("species"):
		sid = str(victim.get_meta("species"))
	if sid == "":
		return
	var e := entry(sid)
	e.seen = maxi(1, int(e.seen))
	var before := knowledge(sid)
	e.kills = int(e.kills) + 1
	if victim.has_meta("variant"):
		var vk := str(victim.get_meta("variant"))
		e.variants[vk] = int(e.variants.get(vk, 0)) + 1
	state.kills[sid] = int(state.kills.get(sid, 0)) + 1
	var after := knowledge(sid)
	if after > before and after >= 2:
		Events.notify.emit("Бестиарий: изучено — %s" % _name_of(sid), Color(0.7, 1.0, 0.8))

# =================================================================== boss rewards
## Called by Loot.boss_rewards for the 40 new bosses. One reward per kill
## (the boss instance is marked), trophy only once, relic never duplicated.
static func boss_loot(boss) -> Array:
	var out: Array = []
	if boss == null or not is_instance_valid(boss) or boss.has_meta("beast_loot_done"):
		return out
	boss.set_meta("beast_loot_done", true)
	var bd: Dictionary = DBBeasts.boss(boss.boss_id)
	if bd.is_empty():
		return out
	var pl = Game.player
	var p: Vector3 = boss.global_position
	var lvl: int = boss.level
	var era := int(bd.era)
	for l in bd.get("loot", []):
		var id := str(l[0])
		var ch := float(l[1])
		if randf() > ch:
			continue
		if id.begins_with("x_"):
			# relic: never a duplicate
			if pl != null and (pl.data.inv.count(id) > 0 or _equipped(pl, id)):
				continue
			out.append(ItemDB.create(id, 4, lvl, null, false))
		else:
			var it := ItemDB.create(id, 0, lvl, null, false)
			if it.get("stack", false) or BeastItems.MATS.has(id):
				it.qty = 2 if ch >= 1.0 else 1
			out.append(it)
	if bd.get("trophy", false):
		var tid := "trophy_" + str(bd.id)
		var got: Dictionary = Game.world_state.get("beasts", {}).get("rewarded", {})
		if not got.has(tid):
			got[tid] = true
			out.append(ItemDB.create(tid, 3, 1, null, false))
	# an era legendary from the catalogue (titans always, others 30%)
	if Game.world and Game.world.get("loot") != null and (bd.cat == "titan" or randf() < 0.3):
		var named: Dictionary = Game.world.loot.named_drop(boss, era)
		if not named.is_empty():
			out.append(named)
	for it in out:
		if it.is_empty():
			continue
		if Game.world and Game.world.get("loot") != null:
			Game.world.loot.spawn_drop(it, p + Vector3(randf_range(-2, 2), 0.3, randf_range(-2, 2)))
	if inst != null:
		inst.stats.boss_loot += 1
	return out

static func _equipped(pl, id: String) -> bool:
	for sl in pl.data.inv.equip:
		if str(pl.data.inv.equip[sl].get("base", "")) == id:
			return true
	return false

## The kill itself: bestiary, chronicle, world state, quests.
static func on_boss_defeated(boss_id: String, pos: Vector3, killer) -> void:
	var bd: Dictionary = DBBeasts.boss(boss_id)
	var bs: Dictionary = Game.world_state.get("beasts", {})
	if bs.has("world_bosses") and bs.world_bosses.has(boss_id):
		bs.world_bosses[boss_id].defeated = true
	Chronicle.record("beast_slain", [killer if (killer != null and is_instance_valid(killer)) else {"id": "unknown", "name": "неизвестный"}, {"id": boss_id, "name": bd.get("name", boss_id)}],
		{"pos_v3": pos, "extra": {"boss": bd.get("name", boss_id)}})

func save_state() -> void:
	Game.world_state["beasts"] = state
