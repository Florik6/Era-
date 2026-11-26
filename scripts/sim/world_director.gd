class_name WorldDirector
extends Node
## Central event manager. Considers era, player position and power, active
## threats, recent events, faction state and history to start world events
## with a beginning, development, end and consequences, while avoiding
## endless chaos. Also keeps the ambient enemy population around the player.

var world
var events: Array = []
var cooldowns := {}
var mods := {"enemy_dmg": 1.0, "spell": 1.0, "mana_regen": 1.0, "spawn": 1.0, "loot": 0.0}
var _t := 0.0
var _amb_t := 0.0
var _check_t := 0.0
var ambient: Array = []
var hunters_queue: Array = []
var intensity := 0.0

const EVENT_NAMES := {"bandit_raid": "Нашествие разбойников", "blood_moon": "Кровавая луна", "magic_storm": "Магическая буря", "cursed_fog": "Проклятый туман",
	"caravan_attack": "Нападение на караван", "siege": "Осада", "meteor": "Падение метеорита", "world_boss": "Мировой босс", "rift_open": "Открытие разлома",
	"chrono_catastrophe": "Хронокатастрофа", "uprising": "Восстание", "rare_find": "Редкая находка", "hunters": "Охотники за головами", "battle": "Битва фракций",
	"caravan": "Караван", "raid": "Нападение на поселение", "boss_return": "Возвращение босса", "invasion": "Историческое вторжение"}

func _init(w) -> void:
	world = w

func setup() -> void:
	var s: Dictionary = Game.world_state.get("director", {})
	cooldowns = s.get("cooldowns", {})

func save_state() -> void:
	Game.world_state.director = {"cooldowns": cooldowns}

func active_events() -> Array:
	return events

func event_near(p: Vector3, r: float):
	for e in events:
		if e.has("pos") and e.pos.distance_to(p) < r and e.type in ["meteor", "rare_find", "world_boss", "rift_open", "battle", "invasion", "chrono_catastrophe"]:
			return e
	return null

func status_text() -> String:
	var parts: Array = []
	for e in events:
		if e.type in ["caravan", "raid"]:
			parts.append(e.name)
		else:
			var left := int(e.dur - e.t)
			parts.append("%s (%d с)" % [e.name, maxi(0, left)])
	return "\n".join(parts)

func _ev(type: String, pos: Vector3, dur: float, data: Dictionary = {}) -> Dictionary:
	var e := {"id": Game.new_uid("ev"), "type": type, "name": EVENT_NAMES.get(type, type), "pos": pos, "t": 0.0, "dur": dur, "actors": [], "data": data}
	events.append(e)
	Events.world_event_started.emit(e)
	if not type in ["caravan", "raid"]:
		Chronicle.record("world_event", [], {"pos_v3": pos, "extra": {"name": e.name}})
	return e

func _end(e: Dictionary, outcome: String) -> void:
	events.erase(e)
	Events.world_event_ended.emit(e)
	if outcome != "":
		Chronicle.record("world_event_end", [], {"pos_v3": e.pos, "extra": {"name": e.name, "outcome": outcome}})
		Events.notify.emit("%s: %s" % [e.name, outcome], Color(1.0, 0.75, 0.45))

func _alive(arr: Array) -> int:
	var n := 0
	for a in arr:
		if is_instance_valid(a) and not a.is_dead:
			n += 1
	return n

func _ring_pos(center: Vector3, rmin: float, rmax: float) -> Vector3:
	var a := randf() * TAU
	var p := center + Vector3(cos(a), 0, sin(a)) * randf_range(rmin, rmax)
	if world.is_water(p):
		p = center + Vector3(cos(a + PI), 0, sin(a + PI)) * randf_range(rmin, rmax)
	return p

# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if world.player == null or not is_instance_valid(world.player):
		return
	for e in events.duplicate():
		e.t += delta
		_tick_event(e, delta)
	if Game.mode != "world" or world.dimension != "":
		return
	_amb_t += delta
	if _amb_t > 3.0:
		_amb_t = 0.0
		_ambient_population()
	_t += delta
	if _t > 25.0:
		_t = 0.0
		_maybe_start_event()
	_check_t += delta
	if _check_t > 5.0:
		_check_t = 0.0
		_check_boss_returns()
		_check_hunters()

func _ambient_population() -> void:
	var pp: Vector3 = world.player.global_position
	for a in ambient.duplicate():
		if not is_instance_valid(a) or a.is_dead:
			ambient.erase(a)
		elif a.global_position.distance_to(pp) > 110.0:
			a.queue_free()
			ambient.erase(a)
	for a in Game.actors.duplicate():
		if not is_instance_valid(a) or a == world.player or a.is_dead:
			continue
		if a.team == "player" or a.record.size() > 0 or a.get("settlement_id") != null and a.settlement_id != "":
			continue
		if a is Boss and a.lair_id != "":
			continue
		if a.global_position.distance_to(pp) > 170.0 and not world._in_dim_region(a.global_position):
			a.queue_free()
	var target := 6 + mini(3, world.spawner.era_progress_levels() / 2) + (2 if Game.is_night() else 0)
	target = int(target * mods.spawn)
	if ambient.size() >= target:
		return
	var era_d: Dictionary = DBEras.era(Profile.current_era)
	var pool: Array = era_d.night_enemies if (Game.is_night() and randf() < 0.6) else era_d.enemies
	pool = world.spawner.suitable(pool)
	var id: String = pool[randi() % pool.size()]
	var center := _ring_pos(pp, 30.0, 48.0)
	var prog: int = world.spawner.era_progress_levels()
	var pack := 1 + (randi() % (1 + mini(2, prog / 2)) if DBActors.ENEMIES[id].rig == "wolf" or DBActors.ENEMIES[id].team == "bandit" else 0)
	for i in pack:
		var m = world.spawner.spawn_enemy(id, center + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
		if m:
			ambient.append(m)
			if blood_moon_active() and randf() < 0.35:
				_make_blood_variant(m)

func _maybe_start_event() -> void:
	if events.size() >= 2:
		return
	var pp: Vector3 = world.player.global_position
	var now := Game.game_time
	var lvl: int = world.player.level
	var cands: Array = []
	var w := {"bandit_raid": 1.0, "magic_storm": 0.7, "cursed_fog": 0.6, "meteor": 0.6, "rift_open": 0.9, "rare_find": 0.8, "uprising": 0.35,
		"chrono_catastrophe": 0.35 + Profile.current_era * 0.1, "world_boss": 0.25 if lvl >= 6 else 0.0, "caravan_attack": 0.6, "invasion": 0.5}
	if Game.is_night():
		w["blood_moon"] = 0.8
	for k in w:
		if float(cooldowns.get(k, 0.0)) > now:
			continue
		if w[k] <= 0.0:
			continue
		cands.append([k, w[k]])
	if cands.is_empty() or randf() > 0.55:
		return
	var total := 0.0
	for c in cands:
		total += c[1]
	var r := randf() * total
	for c in cands:
		r -= c[1]
		if r <= 0.0:
			_start(c[0], pp)
			cooldowns[c[0]] = now + 0.6 + randf() * 0.6
			return

func _start(type: String, pp: Vector3) -> void:
	var era := Profile.current_era
	match type:
		"bandit_raid":
			var s = _nearest_settlement(pp, 250.0)
			if s != null:
				start_raid_on(s.id, "")
		"blood_moon":
			var e := _ev("blood_moon", pp, 150.0)
			mods.enemy_dmg = 1.25
			mods.spawn = 1.7
			mods.loot = 0.15
			if world.day_night and world.day_night.has_method("set_override"):
				world.day_night.set_override("blood_moon", true)
			e.data.embers = _blood_embers()
			# a unique champion of the night
			var night_pool: Array = DBEras.era(era).night_enemies
			var champ = world.spawner.spawn_enemy(night_pool[night_pool.size() - 1], _ring_pos(pp, 30.0, 40.0), world.spawner.level_near_player(2))
			if champ:
				_make_blood_variant(champ, true)
				e.actors.append(champ)
			Events.banner.emit("Кровавая луна", "Враги сильнее, бродит Вестник Кровавой Луны. Добыча богаче.", Color(1.0, 0.3, 0.3))
			Audio.play_sfx("boss_phase", null, -8.0)
		"magic_storm":
			_ev("magic_storm", pp, 120.0)
			mods.spell = 1.25
			mods.mana_regen = 2.0
			Audio.set_ambient("magic_storm_loop", true)
			Events.banner.emit("Магическая буря", "Сила заклинаний +25%, мана восстанавливается вдвое быстрее. Берегитесь молний!", Color(0.6, 0.5, 1.0))
		"cursed_fog":
			var e2 := _ev("cursed_fog", pp, 150.0)
			if world.weather and world.weather.has_method("set_override"):
				world.weather.set_override("cursed_fog", true)
			mods.spawn = 1.6
			var fog_pool: Array = world.spawner.suitable(DBEras.era(era).night_enemies)
			for i in 2 + mini(2, world.spawner.era_progress_levels() / 2):
				var nid: String = fog_pool[randi() % fog_pool.size()]
				var m = world.spawner.spawn_enemy(nid, _ring_pos(pp, 25.0, 40.0))
				if m:
					e2.actors.append(m)
			Events.banner.emit("Проклятый туман", "Из тумана поднимаются порождения тьмы.", Color(0.5, 0.9, 0.5))
		"meteor":
			var p := _ring_pos(pp, 30.0, 60.0)
			p.y = world.ground_height(p)
			var e3 := _ev("meteor", p, 160.0)
			VFX.telegraph(p, 7.0, 3.0, Color(1.0, 0.5, 0.1))
			Events.banner.emit("Падение метеорита", "С неба падает огненная звезда! Отметка на карте.", Color(1.0, 0.6, 0.2))
			get_tree().create_timer(3.0, false).timeout.connect(func():
				VFX.beam(p + Vector3(20, 60, 0), p, Color(1.0, 0.5, 0.1), 0.4, 1.2, false)
				VFX.explosion(p, 7.0, Color(1.0, 0.45, 0.1))
				Combat.aoe(null, p, 7.0, {"amount": 60.0 * (era + 1), "dtype": "fire", "status": {"burn": 10.0}}, false)
				Audio.play_sfx("explosion", p)
				var sh := ItemDB.create("chrono_shard", 0, 1)
				sh.qty = 2
				world.loot.spawn_drop(sh, p)
				world.loot.spawn_drop(ItemDB.random_for_era(era, world.player.level, "event"), p + Vector3(1.5, 0, 0))
				var ids: Array = DBEras.era(era).enemies
				var elite_id: String = ids[ids.size() - 1]
				var m2 = world.spawner.spawn_enemy(elite_id, p + Vector3(3, 0, 0), world.spawner.level_near_player(2))
				if m2:
					m2.elite = true
					m2.display_name = "Звёздный " + m2.display_name
					m2.max_hp *= 1.5
					m2.hp = m2.max_hp
					e3.actors.append(m2))
		"rift_open", "invasion":
			var p2 := _ring_pos(pp, 25.0, 45.0)
			p2.y = world.ground_height(p2)
			var e4 := _ev("invasion" if type == "invasion" else "rift_open", p2, 180.0)
			var portal := Poi.create({"id": e4.id, "type": "rift", "pos": Vector2(p2.x, p2.z), "name": "Временный разлом", "data": {"temporary": true}}, world)
			world.poi_root.add_child(portal)
			portal.global_position = p2
			e4.data.portal = portal
			if type == "invasion" or randf() < 0.6:
				_invasion(e4, p2)
			Events.banner.emit("Открылся разлом", "В него можно войти. Из него лезут чужаки!" if type == "invasion" else "Неподалёку открылся временный разлом.", Color(0.7, 0.4, 1.0))
		"chrono_catastrophe":
			var e5 := _ev("chrono_catastrophe", pp, 120.0)
			for i in 3:
				var zp := _ring_pos(pp, 10.0, 30.0)
				zp.y = world.ground_height(zp)
				Zone.create("timeslow", null, zp, 5.0, 60.0, {})
			_invasion(e5, _ring_pos(pp, 20.0, 30.0))
			Events.banner.emit("Хронокатастрофа", "Время рвётся: аномалии замедления и гости из других эпох.", Color(0.4, 1.0, 0.85))
		"uprising":
			var s2 = _nearest_settlement(pp, 600.0)
			if s2 != null and world.factions.settlement_owner(s2.id) != "":
				_ev("uprising", Vector3(s2.pos.x, 0, s2.pos.y), 10.0)
				world.factions.change_settlement_owner(s2.id, "", "восстание жителей")
		"rare_find":
			var p3 := _ring_pos(pp, 60.0, 120.0)
			p3.y = world.ground_height(p3)
			var e6 := _ev("rare_find", p3, 240.0)
			if ResourceLoader.exists("res://scripts/world/chest.gd"):
				var ch = load("res://scripts/world/chest.gd").new()
				ch.set("tier", "rich")
				ch.set("lvl", world.player.level + 2)
				world.poi_root.add_child(ch)
				ch.global_position = p3
				e6.data.chest = ch
			else:
				world.loot.spawn_drop(ItemDB.random_for_era(era, world.player.level, "event", 0.3), p3)
			Events.banner.emit("Редкая находка", "Ходят слухи о сокровище неподалёку. Охотники за реликвиями уже в пути!", Color(1.0, 0.85, 0.3))
		"world_boss":
			var bosses: Array = DBEras.era(era).bosses
			var bid: String = bosses[randi() % bosses.size()]
			var p4 := _ring_pos(pp, 35.0, 50.0)
			var e7 := _ev("world_boss", p4, 300.0)
			var b = world.spawner.spawn_boss(bid, p4, world.spawner.level_near_player(2))
			if b:
				b.display_name = "Тень: " + b.display_name
				b.max_hp *= 0.6
				b.hp = b.max_hp
				b.def = b.def.duplicate()
				b.def["reward"] = ""
				e7.actors.append(b)
			Events.banner.emit("Мировой босс", "Тень грозного врага бродит по округе.", Color(1.0, 0.3, 0.3))
		"caravan_attack":
			var q := {"id": "", "objectives": [{"pos": [pp.x + 150.0, pp.z], "from": [pp.x - 20.0, pp.z]}]}
			start_caravan(q, true)

func blood_moon_active() -> bool:
	for e in events:
		if e.type == "blood_moon":
			return true
	return false

## Drifting crimson motes around the player (cheap, few particles).
func _blood_embers() -> Node3D:
	var p := CPUParticles3D.new()
	p.amount = int(24 * Settings.profile().get("particles", 0.7)) + 4
	p.lifetime = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(18, 4, 14)
	p.direction = Vector3(0.3, 1, 0)
	p.spread = 30.0
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.9
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = MeshLib.box(Vector3(0.07, 0.07, 0.07))
	p.material_override = MeshLib.mat(Color(1.0, 0.25, 0.2), 0.0, 1.0, 3.0, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.fx_root.add_child(p)
	if world.player:
		p.global_position = world.player.global_position + Vector3(0, 6, 0)
	p.emitting = true
	return p

## Blood-moon enemies: tougher, red glow, better loot (elite), named.
func _make_blood_variant(m, champion: bool = false) -> void:
	m.set_meta("blood_variant", true)
	m.elite = true
	m.display_name = ("Вестник Кровавой Луны: " if champion else "Кровавый ") + m.display_name
	var k := 2.5 if champion else 1.35
	if m.data:
		m.base_hp_override *= k
		m.refresh_gear()
	else:
		m.max_hp *= k
		m.stats["base_hp"] = m.max_hp
	m.hp = m.max_hp
	if Settings.profile().get("fx", 1) >= 1 or champion:
		var l := OmniLight3D.new()
		l.name = "BloodGlow"
		l.light_color = Color(1.0, 0.18, 0.15)
		l.light_energy = 0.9 if champion else 0.5
		l.omni_range = 3.5 if champion else 2.2
		l.position = Vector3(0, 1.6, 0)
		l.shadow_enabled = false
		m.add_child(l)
	world.spawner.name_tag(m, Color(1.0, 0.35, 0.3))

func _invasion(e: Dictionary, p: Vector3) -> void:
	var era := Profile.current_era
	var others: Array = []
	for i in DBEras.ERA_COUNT:
		if i != era:
			others.append(i)
	var from_era: int = others[randi() % others.size()]
	var ed: Dictionary = DBEras.era(from_era)
	for i in 2 + mini(3, world.spawner.era_progress_levels() / 2) + randi() % 2:
		var id: String = ed.enemies[randi() % ed.enemies.size()]
		var m = world.spawner.spawn_enemy(id, p + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), world.spawner.level_near_player(0))
		if m:
			world.spawner.normalize_to_era(m, from_era)
			m.display_name = "%s (%s)" % [m.display_name, ed.name]
			m.team = "monster"
			e.actors.append(m)
	e.data.from = ed.name
	e.name = "Вторжение из эпохи «%s»" % ed.name
	Chronicle.record("invasion", [], {"pos_v3": p, "extra": {"from": ed.name}})

func _tick_event(e: Dictionary, _delta: float) -> void:
	match e.type:
		"blood_moon":
			var emb = e.data.get("embers")
			if emb != null and is_instance_valid(emb) and world.player:
				emb.global_position = world.player.global_position + Vector3(0, 6, 0)
			if e.t >= e.dur or not Game.is_night():
				mods.enemy_dmg = 1.0
				mods.spawn = 1.0
				mods.loot = 0.0
				if world.day_night and world.day_night.has_method("set_override"):
					world.day_night.set_override("blood_moon", false)
				if emb != null and is_instance_valid(emb):
					emb.queue_free()
				for a in Game.actors.duplicate():
					if is_instance_valid(a) and a.has_meta("blood_variant") and not a.is_dead:
						a.remove_meta("blood_variant")
						var gl = a.get_node_or_null("BloodGlow")
						if gl:
							gl.queue_free()
				_end(e, "Кровавая луна зашла.")
		"magic_storm":
			if randf() < 0.02:
				var p: Vector3 = world.player.global_position + Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
				p.y = world.ground_height(p)
				VFX.telegraph(p, 2.0, 0.8, Color(0.6, 0.5, 1.0))
				get_tree().create_timer(0.8, false).timeout.connect(func():
					VFX.beam(p + Vector3(0, 15, 0), p, Color(0.7, 0.6, 1.0), 0.2, 0.15, true)
					Combat.aoe(null, p, 2.0, {"amount": 15.0 * (Profile.current_era + 1), "dtype": "lightning", "status": {"stun": 0.4}}, false))
			if e.t >= e.dur:
				mods.spell = 1.0
				mods.mana_regen = 1.0
				Audio.set_ambient("magic_storm_loop", false)
				_end(e, "Буря утихла.")
		"cursed_fog":
			if e.t >= e.dur:
				mods.spawn = 1.0
				if world.weather and world.weather.has_method("set_override"):
					world.weather.set_override("cursed_fog", false)
				_end(e, "Туман рассеялся.")
		"meteor", "world_boss", "chrono_catastrophe":
			if e.t > 5.0 and e.actors.size() > 0 and _alive(e.actors) == 0:
				_end(e, "Угроза устранена.")
			elif e.t >= e.dur:
				for a in e.actors:
					if is_instance_valid(a):
						a.queue_free()
				_end(e, "Угроза ушла сама.")
		"rift_open", "invasion":
			var done = e.t >= e.dur or (e.t > 5.0 and e.actors.size() > 0 and _alive(e.actors) == 0 and e.type == "invasion")
			if done:
				var portal = e.data.get("portal")
				if portal != null and is_instance_valid(portal) and world.dimension == "":
					portal.queue_free()
				if e.actors.size() > 0 and _alive(e.actors) == 0:
					world.loot.spawn_drop(ItemDB.random_for_era(Profile.current_era, world.player.level, "event"), e.pos)
					_end(e, "Захватчики из эпохи «%s» уничтожены. Остались чужеродные трофеи." % e.data.get("from", "?"))
				else:
					_end(e, "Разлом закрылся.")
		"rare_find":
			var ch = e.data.get("chest")
			if (ch != null and (not is_instance_valid(ch) or ch.get("opened"))) or e.t >= e.dur:
				_end(e, "Сокровище найдено." if ch == null or not is_instance_valid(ch) or ch.get("opened") else "Слухи оказались пустыми.")
		"uprising":
			if e.t >= e.dur:
				_end(e, "Поселение объявило себя свободным.")
		"raid":
			_tick_raid(e)
		"battle":
			_tick_battle(e)
		"caravan":
			_tick_caravan(e)
		"hunters":
			if e.t > 3.0 and _alive(e.actors) == 0:
				_end(e, "Охотники за головами повержены.")
				Profile.char.fame = maxf(0.0, Profile.char.fame - 30.0)
			elif e.t >= 400.0:
				for a in e.actors:
					if is_instance_valid(a):
						a.queue_free()
				_end(e, "Охотники потеряли след.")

# ---------------------------------------------------------------- raids
func start_raid_on(sid: String, qid: String) -> void:
	var s = world._settlement(sid)
	if s == null:
		return
	var c := Vector3(s.pos.x, 0, s.pos.y)
	var e := _ev("raid", c, 200.0, {"sid": sid, "qid": qid})
	e.name = "Нападение на %s" % s.name
	var era_d: Dictionary = DBEras.era(Profile.current_era)
	var bandits: Array = era_d.enemies.filter(func(x): return DBActors.ENEMIES[x].team == "bandit")
	if bandits.is_empty():
		bandits = era_d.enemies
	bandits = world.spawner.suitable(bandits)
	var from := _ring_pos(c, 35.0, 45.0)
	for i in 3 + mini(3, world.spawner.era_progress_levels() / 2):
		var m = world.spawner.spawn_enemy(bandits[randi() % bandits.size()], from + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
		if m:
			m.brain.goal = "travel"
			m.brain.dest = c
			m.brain.path = [c]
			e.actors.append(m)
	Events.banner.emit("Нападение!", "Разбойники атакуют %s!" % s.name, Color(1.0, 0.4, 0.3))

func _tick_raid(e: Dictionary) -> void:
	for a in e.actors:
		if is_instance_valid(a) and not a.is_dead and a.brain and a.brain.goal in ["idle", "wander", "explore"]:
			a.brain.path = [e.pos]
			a.brain.goal = "travel"
	var alive := _alive(e.actors)
	if alive == 0:
		var sid: String = e.data.sid
		if world.factions.settlements.has(sid):
			world.factions.settlements[sid].security = minf(1.0, world.factions.settlements[sid].security + 0.2)
		if e.data.qid != "":
			world.quests.on_defend_result(e.data.qid, true)
		elif world.player.global_position.distance_to(e.pos) < 80.0:
			var m: String = world.factions.member_of()
			var owner_f: String = world.factions.settlement_owner(sid)
			if owner_f != "":
				world.factions.add_rep(owner_f, 20.0, "оборона поселения")
		_end(e, "Нападение отбито.")
	elif e.t >= e.dur:
		var sid2: String = e.data.sid
		if world.factions.settlements.has(sid2):
			var st: Dictionary = world.factions.settlements[sid2]
			st.security = maxf(0.1, st.security - 0.3)
			st.population = maxi(2, st.population - 2)
			st.resources = maxf(0.0, st.resources - 40.0)
		for a in e.actors:
			if is_instance_valid(a):
				a.queue_free()
		if e.data.qid != "":
			world.quests.on_defend_result(e.data.qid, false)
		_end(e, "Разбойники разграбили поселение.")

# ---------------------------------------------------------------- faction battles near the player
func start_battle(att: String, def_f: String, kind: String, target_id: String, pos: Vector3) -> void:
	var e := _ev("battle", pos, 180.0, {"att": att, "def": def_f, "kind": kind, "target": target_id, "a": [], "d": []})
	e.name = "Битва: %s против %s" % [DBEras.faction(att).name, DBEras.faction(def_f).get("name", "защитников")]
	var lvl: int = world.spawner.level_near_player(0)
	var roles := ["infantry", "infantry", "archer", "heavy", "mage", "scout"]
	var from := _ring_pos(pos, 30.0, 40.0)
	for i in 5:
		var n = world.spawner.spawn_soldier(att, roles[i % roles.size()], from + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)), lvl)
		n.squad = {"faction": att, "order": "attack", "pos": pos}
		e.data.a.append(n)
	var cmd = world.spawner.spawn_soldier(att, "commander", from, lvl + 2)
	cmd.squad = {"faction": att, "order": "attack", "pos": pos}
	e.data.a.append(cmd)
	if def_f != "":
		for i in 4:
			var d = world.spawner.spawn_soldier(def_f, roles[(i + 1) % roles.size()], pos + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), lvl)
			d.squad = {"faction": def_f, "order": "defend", "pos": pos}
			e.data.d.append(d)
	Events.banner.emit("Битва фракций", e.name + ". Вмешайтесь, чтобы склонить чашу весов!", Color(1.0, 0.75, 0.4))

func _tick_battle(e: Dictionary) -> void:
	var a := _alive(e.data.a)
	var d := _alive(e.data.d)
	if a == 0 or d == 0 or e.t >= e.dur:
		var winner: String = e.data.att if (d == 0 and a > 0) else e.data.def
		var place: String = world.place_name(e.pos)
		Chronicle.record("battle", [], {"place": place, "extra": {"a": DBEras.faction(e.data.att).name, "b": DBEras.faction(e.data.def).get("name", "защитники"), "winner": DBEras.faction(winner).get("name", "защитники")}})
		world.legends.battle_outcome(e.data.att, e.data.def, winner, place)
		if winner == e.data.att:
			if e.data.kind == "cp":
				world.factions.capture_point(e.data.target, e.data.att)
			else:
				world.factions.change_settlement_owner(e.data.target, e.data.att, "битва")
		_end(e, "Победа: %s" % DBEras.faction(winner).get("name", "защитники"))
		get_tree().create_timer(30.0, false).timeout.connect(func():
			for x in e.data.a + e.data.d:
				if is_instance_valid(x) and not x.is_dead:
					x.queue_free())

# ---------------------------------------------------------------- caravans (dynamic chain)
func start_caravan(q: Dictionary, ambushed_only: bool = false) -> void:
	var from_v: Array = q.objectives[0].get("from", [world.player.global_position.x, world.player.global_position.z])
	var to_v: Array = q.objectives[0].pos
	var start := Vector3(from_v[0], 0, from_v[1])
	var dest := Vector3(to_v[0], 0, to_v[1])
	var e := _ev("caravan", start, 600.0, {"qid": q.get("id", ""), "dest": dest, "ambushed": false, "thief": null, "stolen": {}})
	e.name = "Караван"
	var leader = world.spawner.spawn_villager({"id": "", "owner": ""}, start, "trader")
	leader.display_name = "Купец каравана"
	leader.role = "villager"
	leader.archetype = "cautious"
	e.actors.append(leader)
	e.data.leader = leader
	var guard = world.spawner.spawn_villager({"id": "", "owner": ""}, start + Vector3(2, 0, 0), "guard")
	e.actors.append(guard)
	e.data.guard = guard
	if ambushed_only:
		e.data.ambush_at = 0.05
	else:
		e.data.ambush_at = randf_range(0.3, 0.6)
	e.data.total = start.distance_to(dest)

func _tick_caravan(e: Dictionary) -> void:
	var leader = e.data.leader
	var dest: Vector3 = e.data.dest
	if not is_instance_valid(leader) or leader.is_dead:
		if e.data.qid != "":
			world.quests.on_escort_result(e.data.qid, false, "Купец погиб.")
		_end(e, "Караван уничтожен.")
		return
	e.pos = leader.global_position
	var to = dest - leader.global_position
	to.y = 0
	var enemies_near := false
	for a in Game.actors_near(leader.global_position, 12.0):
		if not a.is_dead and Game.is_enemy(leader, a):
			enemies_near = true
			break
	if not enemies_near:
		leader.brain.goal = "travel"
		leader.brain.path = [dest]
		var g = e.data.guard
		if is_instance_valid(g) and not g.is_dead and g.brain.goal != "fight":
			g.brain.goal = "travel"
			g.brain.path = [leader.global_position]
	var progress: float = 1.0 - to.length() / maxf(1.0, e.data.total)
	if not e.data.ambushed and progress >= e.data.ambush_at:
		e.data.ambushed = true
		_ambush(e)
	# thief behaviour
	var th = e.data.thief
	if th != null and is_instance_valid(th) and not th.is_dead and e.data.stolen.size() > 0:
		if th.global_position.distance_to(world.player.global_position) > 70.0:
			_thief_escaped(e, th)
	if to.length() < 12.0:
		if e.data.qid != "":
			world.quests.on_escort_result(e.data.qid, true)
		world.player.data.gold += 20 * (Profile.current_era + 1)
		_end(e, "Караван благополучно прибыл.")

func _ambush(e: Dictionary) -> void:
	var leader = e.data.leader
	var era_d: Dictionary = DBEras.era(Profile.current_era)
	var bandits: Array = era_d.enemies.filter(func(x): return DBActors.ENEMIES[x].team == "bandit" and DBActors.ENEMIES[x].rig == "humanoid")
	if bandits.is_empty():
		return
	var p := _ring_pos(leader.global_position, 14.0, 18.0)
	for i in 3 + Profile.current_era / 2:
		var m = world.spawner.spawn_enemy(bandits[randi() % bandits.size()], p + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
		if m:
			m.add_aggro(leader, 60.0)
			e.actors.append(m)
	# the thief grabs cargo and runs
	var thief = world.spawner.spawn_enemy(bandits[0], leader.global_position + Vector3(2, 0, 2))
	if thief:
		thief.display_name = "Вор " + DBActors.rand_name(Profile.current_era, false, Game.rng)
		var stolen := ItemDB.random_for_era(Profile.current_era, world.player.level, "elite")
		stolen.history.append("Похищен из каравана, день %d" % (Game.day() + 1))
		thief.data.inv.add(stolen)
		e.data.thief = thief
		e.data.stolen = stolen
		thief.brain.goal = "flee"
		thief.brain.threat = world.player
		thief.brain.think_t = 60.0
		thief.died.connect(func(_a, k):
			if e.data.stolen.size() > 0:
				world.loot.spawn_drop(e.data.stolen, thief.global_position)
				Events.notify.emit("Похищенный груз возвращён! Бонус +%d" % (60 * (Profile.current_era + 1)), Color(0.7, 1.0, 0.6))
				world.player.data.gold += 60 * (Profile.current_era + 1)
				e.data.stolen = {}, CONNECT_ONE_SHOT)
		Chronicle.record("loot_stolen", [thief], {"pos_v3": thief.global_position, "extra": {"item": ItemDB.display_name(stolen)}})
		Events.banner.emit("Засада!", "Вор хватает ценный груз и убегает — догоните его!", Color(1.0, 0.5, 0.3))

func _thief_escaped(e: Dictionary, th) -> void:
	var stolen: Dictionary = e.data.stolen
	e.data.stolen = {}
	var rec: Dictionary = world.legends.new_record(th.display_name, {"archetype": "opportunist", "level": th.level, "pos": [th.global_position.x + 150.0, th.global_position.z + 80.0]})
	var cd := CharData.new()
	cd.from_dict(th.data.to_dict())
	cd.name = th.display_name
	rec.data = cd.to_dict()
	rec.backstory = "Вор, ограбивший караван и сумевший скрыться."
	th.queue_free()
	world.quests.start_thief_chase({"display_name": rec.name, "actor_id": rec.id}, stolen)
	Events.notify.emit("Вор скрылся! Новое задание: найти украденное.", Color(1.0, 0.6, 0.4))

# ---------------------------------------------------------------- nemesis & hunters
func _check_boss_returns() -> void:
	for bid in Game.world_state.bosses:
		var st: Dictionary = Game.world_state.bosses[bid]
		if st.get("escaped", 0) > 0 and not st.get("defeated", false) and float(st.get("returns_at", 99999.0)) < Game.game_time and not st.get("returned_active", false):
			if not bid in DBEras.era(Profile.current_era).bosses:
				continue
			st.returned_active = true
			var p := _ring_pos(world.player.global_position, 30.0, 40.0)
			var e := _ev("boss_return", p, 400.0)
			var b = world.spawner.spawn_boss(bid, p, -1, int(st.escaped))
			if b:
				e.actors.append(b)
				Chronicle.record("boss_returned", [b], {"pos_v3": p})
				Events.banner.emit("Он вернулся!", "%s ищет вас, став сильнее." % b.display_name, Color(1.0, 0.3, 0.3))
				b.died.connect(func(_a, _k): st.returned_active = false, CONNECT_ONE_SHOT)

func queue_hunters(nm: String, fid: String = "") -> void:
	hunters_queue.append({"name": nm, "faction": fid})

func _check_hunters() -> void:
	var fame: float = Profile.char.fame
	var hostile_fac := ""
	for fid in world.factions.list():
		if world.factions.rep(fid) <= -40.0:
			hostile_fac = fid
	if hunters_queue.is_empty() and (fame > 120.0 or hostile_fac != "") and randf() < 0.04 and float(cooldowns.get("hunters", 0.0)) < Game.game_time:
		hunters_queue.append({"name": "Охотники за головами", "faction": hostile_fac})
	if hunters_queue.is_empty() or events.size() >= 3:
		return
	var h: Dictionary = hunters_queue.pop_front()
	cooldowns["hunters"] = Game.game_time + 1.0
	var p := _ring_pos(world.player.global_position, 40.0, 55.0)
	var e := _ev("hunters", p, 400.0)
	e.name = h.name
	var ids := ["mercenary", "assassin", "mercenary_rifle", "elite_operative", "cyber_hunter"]
	var eid: String = ids[clampi(Profile.current_era, 0, 4)]
	for i in 2 + Profile.current_era / 2:
		var m = world.spawner.spawn_enemy(eid, p + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), world.spawner.level_near_player(2))
		if m:
			m.hunting_player = true
			m.role = "hunter"
			m.add_aggro(world.player, 999.0)
			e.actors.append(m)
	Chronicle.record("hunted", [world.player])
	Events.banner.emit("Охота на вас!", "%s вышли на ваш след." % h.name, Color(1.0, 0.4, 0.3))

func _nearest_settlement(p: Vector3, r: float):
	if world.gen == null:
		return null
	var best = null
	var bd := r
	for s in world.gen.settlements:
		var d: float = Vector2(p.x, p.z).distance_to(s.pos)
		if d < bd:
			bd = d
			best = s
	return best
