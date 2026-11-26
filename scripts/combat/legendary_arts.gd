class_name LegendaryArts
## Weapon arts of the 10 legendary and 5 mythic expansion weapons. Each art
## has an active use (a skill-slot button, own cool-down, visuals, sounds)
## and most also a passive trigger (on hit, after a perfect dodge, after a
## parry, while blocking, when an enemy winds up). State lives in actor
## metadata, so it works for anyone wielding the weapon.

const ARTS := {
	"ashen_verdict": {"name": "Пепельный приговор", "cd": 9.0, "desc": "Удары оставляют метки жара (до 5). Огненный разрез поджигает и взрывает метки."},
	"lightning_rain": {"name": "Дождь зарниц", "cd": 12.0, "desc": "После идеального уклонения — серия магических стрел-молний. Активно: дождь стрел по цели."},
	"comet_dance": {"name": "Танец кометы", "cd": 8.0, "desc": "После парирования — стремительная серия контратак. Активно: рывок-укол сквозь врагов."},
	"deferred_shot": {"name": "Выстрел отсрочки", "cd": 10.0, "desc": "Попадания дают отложенный повторный удар. Активно: метка, взрывающаяся через 1,5 с."},
	"ninth_thunder": {"name": "Удар девятого грома", "cd": 12.0, "desc": "Круговая электрическая волна, оглушает. Каждый 9-й удар — малая волна."},
	"mechanist_ricochet": {"name": "Рикошет механиста", "cd": 9.0, "desc": "Пули рикошетят ещё в 2 цели. Активно: веер рикошетов."},
	"polar_volley": {"name": "Полярный залп", "cd": 10.0, "desc": "Энергетический импульс конусом: урон и ослабление магической защиты на 6 с."},
	"silent_cut": {"name": "Беззвучный разрез", "cd": 8.0, "desc": "После уклонения следующий удар — беззвучная контратака. Активно: разрез с переносом за спину цели."},
	"phase_echo": {"name": "Фазовое эхо", "cd": 9.0, "desc": "Удары порождают отложенное фазовое эхо. Активно: волна фазовых эхо."},
	"dual_trajectory": {"name": "Двойственная траектория", "cd": 10.0, "desc": "Каждый выстрел дублируется фантомным снарядом. Активно: залп пяти фантомов."},
	"lesser_eclipse": {"name": "Малое Затмение", "cd": 14.0, "desc": "Блок копит энергию Затмения. Высвобождение — тёмная сфера, втягивающая и ранящая (нужно ≥30 энергии)."},
	"threads_of_fate": {"name": "Нити Судеб", "cd": 15.0, "desc": "Предвидение: опасные замахи врагов видны заранее. Активно: нити связывают до 4 врагов — замедление и общий урон."},
	"steam_storm": {"name": "Паровая буря", "cd": 5.0, "desc": "Паровой катаклизм и электрический шторм. Каждое применение греет оружие; при перегреве — блокировка и ожог."},
	"null_protocol": {"name": "Нулевой протокол", "cd": 14.0, "desc": "Выстрелы снимают энергетические щиты. Активно: поле пространственной нестабильности."},
	"first_era_rift": {"name": "Разрыв первой эпохи", "cd": 16.0, "desc": "Удары слегка притягивают врагов. Активно: гравитационный колодец, затем разрыв."},
}

static func art_of(a) -> String:
	if a == null or not is_instance_valid(a) or a.data == null:
		return ""
	return str(a.data.inv.equipped("main").get("art", ""))

static func skill_id(art: String) -> String:
	return "art_" + art

static func skill_dict(id: String) -> Dictionary:
	var art := id.trim_prefix("art_")
	var d: Dictionary = ARTS.get(art, {})
	if d.is_empty():
		return {}
	return {"id": id, "name": d.name, "cd": d.cd, "desc": d.desc, "cat": "art"}

static func _wdmg(a) -> float:
	var w: Dictionary = a.weapon() if a.has_method("weapon") else {}
	return float(ItemDB.stat(w, "dmg")) if not w.is_empty() else 20.0

static func _foes(a, center: Vector3, r: float) -> Array:
	var out: Array = []
	for t in Game.actors_near(center, r):
		if t != a and not t.is_dead and Game.can_damage(a, t):
			out.append(t)
	return out

static func _hit(a, t, amount: float, dtype: String, status := {}) -> float:
	return Combat.deal(a, t, {"amount": amount, "dtype": dtype, "status": status, "melee": false, "proc": true, "art": true})

# ---------------------------------------------------------------- active
static func use(a, id: String, aim: Vector3) -> bool:
	var art := id.trim_prefix("art_")
	if art != art_of(a) or not ARTS.has(art):
		return false
	var d: Dictionary = ARTS[art]
	if aim.length() < 0.01:
		aim = a.facing
	aim.y = 0
	aim = aim.normalized()
	a.face_dir(aim)
	var p: Vector3 = a.global_position
	var wd := _wdmg(a)
	match art:
		"ashen_verdict":
			a.start_action("skill", 0.6, 0.5, {"anim": "slash", "cb": func():
				for t in _foes(a, p + aim * 2.0, 4.0):
					var to: Vector3 = t.global_position - a.global_position
					to.y = 0
					if to.length() > 0.5 and aim.angle_to(to.normalized()) > deg_to_rad(75.0):
						continue
					var marks := int(t.get_meta("heat", 0))
					_hit(a, t, wd * (2.0 + 0.25 * marks), "fire", {"burn": wd * 0.3})
					t.set_meta("heat", 0)
					if marks >= 3:
						VFX.explosion(t.global_position + Vector3(0, 0.8, 0), 2.0, Color(1.0, 0.45, 0.1))
				VFX.slash(a.global_position + Vector3(0, 1.0, 0), aim, 4.5, 150.0, "slash", Color(1.0, 0.5, 0.15))
				VFX.decal(a.global_position + aim * 2.5, "scorch", 3.5, 15.0, randf() * TAU)
				Audio.play_sfx("fire_cast", a.global_position)})
		"lightning_rain":
			_lightning_rain(a, aim, 6)
		"comet_dance":
			_comet(a, aim, 3)
		"deferred_shot":
			# the mark sits on the nearest foe in the aim cone (or 10 m ahead)
			# and follows it until it bursts
			var mt = _nearest(a, p, 25.0, aim)
			var tp: Vector3 = mt.global_position if mt != null else p + aim * 10.0
			var mref: WeakRef = weakref(mt) if mt != null else null
			VFX.telegraph(tp, 3.0, 1.5, Color(0.9, 0.85, 0.6))
			VFX.beam(a.chest(), tp + Vector3(0, 1.0, 0), Color(0.95, 0.85, 0.5), 0.12, 0.2, false)
			Audio.play_sfx("gun_flint", p, -2.0)
			a.get_tree().create_timer(1.5, false).timeout.connect(func():
				if not is_instance_valid(a):
					return
				if mref != null:
					var m2 = mref.get_ref()
					if m2 != null and is_instance_valid(m2) and not m2.is_dead:
						tp = m2.global_position
				VFX.explosion(tp, 3.0, Color(0.95, 0.85, 0.55))
				Audio.play_sfx("explosion", tp)
				for t in _foes(a, tp, 3.0):
					_hit(a, t, wd * 2.2, "pierce", {"stun": 0.5}))
		"ninth_thunder":
			_thunder_wave(a, 6.0, wd * 1.8)
		"mechanist_ricochet":
			var first = _nearest(a, p, 20.0, aim)
			if first == null:
				return false
			_ricochet(a, first, wd * 1.1, 5)
			Audio.play_sfx("gun_revolver", p)
		"polar_volley":
			VFX.beam(a.chest(), a.chest() + aim * 20.0, Color(0.5, 0.85, 1.0), 0.3, 0.3, false)
			Audio.play_sfx("lightning", p)
			for t in _foes(a, p + aim * 10.0, 11.0):
				var to2: Vector3 = t.global_position - p
				to2.y = 0
				if to2.length() > 0.5 and aim.angle_to(to2.normalized()) <= deg_to_rad(18.0):
					_hit(a, t, wd * 1.6, "lightning")
					t.apply_status("res_down", 6.0)
		"silent_cut":
			var tgt = _nearest(a, p, 9.0, aim)
			if tgt == null:
				return false
			var behind: Vector3 = tgt.global_position - tgt.facing.normalized() * 1.2
			MagicFX.ghost(a, Color(0.6, 0.65, 0.8, 0.5), 0.4)
			a.global_position = Vector3(behind.x, a.global_position.y, behind.z)
			if a.has_method("reset_physics_interpolation"):
				a.reset_physics_interpolation()
			a.face_dir((tgt.global_position - a.global_position).normalized())
			_hit(a, tgt, wd * 2.6, "slash", {})
			VFX.slash(a.global_position + Vector3(0, 1.0, 0), a.facing, 2.8, 120.0, "slash", Color(0.85, 0.9, 1.0))
			Audio.play_sfx("dash_whoosh", a.global_position)
		"phase_echo":
			for i in 3:
				var ep: Vector3 = p + aim * (2.5 + i * 2.2)
				a.get_tree().create_timer(0.25 + i * 0.25, false).timeout.connect(func():
					if not is_instance_valid(a):
						return
					MagicFX.impact(ep + Vector3(0, 0.8, 0), "energy", 2.0)
					for t in _foes(a, ep, 2.4):
						_hit(a, t, wd * 1.2, "energy"))
			Audio.play_sfx("time_warp", p, -4.0)
		"dual_trajectory":
			for i in 5:
				var dir := aim.rotated(Vector3.UP, deg_to_rad(-20.0 + i * 10.0))
				Projectile.spawn(a, a.chest() + dir * 0.8, dir * 30.0, {"amount": wd * 0.7, "dtype": "energy", "status": {}, "tier": "empowered"}, "pulse", {"range": 30.0, "color": Color(0.6, 0.8, 1.0)})
			Audio.play_sfx("laser", p)
		"lesser_eclipse":
			var charge := float(a.get_meta("eclipse", 0.0))
			if charge < 30.0:
				Events.notify.emit("Мало энергии Затмения (%d/30): блокируйте удары" % int(charge), Color(0.7, 0.5, 1.0)) if a.is_player else null
				return false
			a.set_meta("eclipse", 0.0)
			var cp: Vector3 = p + aim * 3.0
			MagicFX.dark_nova(cp, 7.0)
			ResonanceFX.reaction_burst("vortex", cp, 6.0)
			Audio.play_sfx("dark_hum", cp)
			Audio.play_sfx("catastrophe_boom", cp, -8.0)
			for t in _foes(a, cp, 7.0):
				var pull: Vector3 = cp - t.global_position
				pull.y = 0
				t.knockback = pull.normalized() * 6.0 if pull.length() > 0.3 else Vector3.ZERO
				_hit(a, t, 40.0 + charge * 1.5, "dark", {"fear": 1.0})
		"threads_of_fate":
			var bound: Array = []
			for t in _foes(a, p, 10.0):
				if bound.size() >= 4:
					break
				bound.append(t)
			if bound.is_empty():
				return false
			for t in bound:
				t.apply_status("slow", 5.0, {"f": 0.5})
				t.set_meta("fate_link", Time.get_ticks_msec() + 5000)
				VFX.beam(a.chest(), t.chest(), Color(1.0, 0.85, 0.5), 0.6, 0.04, false)
			Audio.play_sfx("time_slow", p)
		"steam_storm":
			var heat := float(a.get_meta("heat_ss", 0.0))
			if float(a.get_meta("overheat_until", 0.0)) > Time.get_ticks_msec() / 1000.0:
				if a.is_player:
					Events.notify.emit("Перегрев! Оружие остывает", Color(1.0, 0.5, 0.3))
				return false
			heat += 40.0
			a.set_meta("heat_ss", heat)
			var sp: Vector3 = p + aim * 6.0
			Zone.create("steam", a, sp, 4.0, 4.0, {"amount": 0.0, "dtype": "fire"}, {"no_res": true})
			ResonanceFX.reaction_burst("steam", sp, 4.0)
			for i in 6:
				var q: Vector3 = sp + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
				a.get_tree().create_timer(0.15 * i, false).timeout.connect(func():
					if is_instance_valid(a):
						MagicFX.sky_strike(q, Color(0.6, 0.75, 1.0), 1.8)
						for t in _foes(a, q, 2.0):
							_hit(a, t, wd * 0.9, "lightning", {"stun": 0.3}))
			Audio.play_sfx("steam_burst", sp)
			Audio.play_sfx("thunder", sp, -4.0)
			if heat >= 100.0:
				a.set_meta("overheat_until", Time.get_ticks_msec() / 1000.0 + 8.0)
				a.set_meta("heat_ss", 0.0)
				Combat.deal(null, a, {"amount": a.max_hp * 0.06, "dtype": "fire", "proc": true})
				if a.is_player:
					Events.notify.emit("Сердце Паровой Бури перегрелось!", Color(1.0, 0.45, 0.25))
		"null_protocol":
			var np: Vector3 = p + aim * 9.0
			Zone.create("instability", a, np, 6.0, 6.0, {"amount": wd * 0.15, "dtype": "time"}, {"no_res": true})
			for t in _foes(a, np, 6.0):
				for sh in ["st_shield", "shield", "magic_shield"]:
					t.statuses.erase(sh)
			Audio.play_sfx("time_warp", np)
		"first_era_rift":
			var wp: Vector3 = p + aim * 6.0
			MagicFX.ground_rune(wp + Vector3(0, 0.06, 0), "rift", Color(0.6, 0.4, 1.0), 9.0, 1.6, 2.5, 1.2)
			Audio.play_sfx("portal_open", wp)
			for i in 6:
				a.get_tree().create_timer(0.2 * i, false).timeout.connect(func():
					if not is_instance_valid(a):
						return
					for t in _foes(a, wp, 9.0):
						var pl: Vector3 = wp - t.global_position
						pl.y = 0
						t.knockback = pl.normalized() * 5.0 if pl.length() > 0.5 else Vector3.ZERO)
			a.get_tree().create_timer(1.3, false).timeout.connect(func():
				if not is_instance_valid(a):
					return
				ResonanceFX.catastrophe(wp, 5.0, "instability")
				for t in _foes(a, wp, 6.0):
					_hit(a, t, wd * 2.8, "time", {"stun": 0.8}))
	a.skill_cd[id] = float(d.cd)
	if a.is_player:
		CombatFeel.punch(0.08, 0.25)
		Profile.add_stat("weapon_arts")
	return true

## Nearest damageable target in the aim cone; real enemies come first, so an
## art never locks onto a bystander while a hostile is in reach.
static func _nearest(a, p: Vector3, r: float, aim := Vector3.ZERO):
	var best = null
	var bd := INF
	var best_foe := false
	for t in _foes(a, p, r):
		var to: Vector3 = t.global_position - p
		to.y = 0
		if aim.length() > 0.1 and to.length() > 0.5 and aim.angle_to(to.normalized()) > deg_to_rad(60.0):
			continue
		var foe: bool = Game.is_enemy(a, t)
		if (foe and not best_foe) or (foe == best_foe and to.length() < bd):
			bd = to.length()
			best = t
			best_foe = foe
	return best

static func _lightning_rain(a, aim: Vector3, n: int) -> void:
	var wd := _wdmg(a)
	for i in n:
		a.get_tree().create_timer(0.12 * i, false).timeout.connect(func():
			if not is_instance_valid(a):
				return
			var t = _nearest(a, a.global_position, 24.0)
			var dir: Vector3 = (t.chest() - a.chest()).normalized() if t != null else aim.rotated(Vector3.UP, randf_range(-0.3, 0.3))
			Projectile.spawn(a, a.chest() + dir * 0.6, dir * 34.0, {"amount": wd * 0.6, "dtype": "lightning", "status": {"stun": 0.15}}, "spark", {"range": 28.0, "homing": 0.6, "color": Color(0.7, 0.8, 1.0)}))
	Audio.play_sfx("lightning", a.global_position, -3.0)

static func _comet(a, aim: Vector3, hits: int) -> void:
	var wd := _wdmg(a)
	var start: Vector3 = a.global_position
	var end: Vector3 = start + aim * 5.0
	MagicFX.ghost(a, Color(1.0, 0.35, 0.3, 0.5), 0.35)
	a.global_position = Vector3(end.x, a.global_position.y, end.z)
	if a.has_method("reset_physics_interpolation"):
		a.reset_physics_interpolation()
	for t in _foes(a, (start + end) * 0.5, 4.5):
		for i in hits:
			_hit(a, t, wd * 0.8, "pierce", {})
	VFX.beam(start + Vector3(0, 1.0, 0), end + Vector3(0, 1.0, 0), Color(1.0, 0.35, 0.3), 0.25, 0.12, false)
	Audio.play_sfx("dash_whoosh", end)

static func _thunder_wave(a, r: float, dmg: float) -> void:
	MagicFX.thunderclap(a.global_position, r)
	Audio.play_sfx("thunder", a.global_position)
	for t in _foes(a, a.global_position, r):
		_hit(a, t, dmg, "lightning", {"stun": 0.6})

static func _ricochet(a, first, dmg: float, jumps: int) -> void:
	var hit := {}
	var cur = first
	var from: Vector3 = a.chest()
	for i in jumps:
		if cur == null:
			break
		hit[cur.actor_id] = true
		VFX.beam(from, cur.chest(), Color(1.0, 0.75, 0.4), 0.12, 0.04, false)
		_hit(a, cur, dmg * pow(0.7, i), "pierce")
		from = cur.chest()
		var nxt = null
		var bd := 8.0
		for t in _foes(a, cur.global_position, 8.0):
			if hit.has(t.actor_id):
				continue
			var d: float = t.global_position.distance_to(cur.global_position)
			if d < bd:
				bd = d
				nxt = t
		cur = nxt

# ---------------------------------------------------------------- passive
## Combat._on_hit for the wielder of an art weapon.
static func on_hit(a, t, dealt: float, info: Dictionary) -> void:
	if info.get("art", false) or info.get("proc", false):
		return
	var art := art_of(a)
	if art == "":
		return
	match art:
		"ashen_verdict":
			t.set_meta("heat", mini(5, int(t.get_meta("heat", 0)) + 1))
		"deferred_shot":
			var tt = t
			a.get_tree().create_timer(1.2, false).timeout.connect(func():
				if is_instance_valid(a) and is_instance_valid(tt) and not tt.is_dead:
					_hit(a, tt, dealt * 0.4, "pierce")
					VFX.burst(tt.chest(), Color(0.95, 0.85, 0.55), 6, 0.15))
		"ninth_thunder":
			var n := int(a.get_meta("hits9", 0)) + 1
			a.set_meta("hits9", n % 9)
			if n >= 9:
				_thunder_wave(a, 3.5, dealt * 0.8)
		"mechanist_ricochet":
			if randf() < 0.5:
				var nxt = null
				for o in _foes(a, t.global_position, 7.0):
					if o != t:
						nxt = o
						break
				if nxt:
					_ricochet(a, nxt, dealt * 0.5, 2)
		"phase_echo":
			var t2 = t
			a.get_tree().create_timer(0.8, false).timeout.connect(func():
				if is_instance_valid(a) and is_instance_valid(t2) and not t2.is_dead:
					MagicFX.impact(t2.chest(), "energy", 0.8, false)
					_hit(a, t2, dealt * 0.35, "energy"))
		"dual_trajectory":
			var dir: Vector3 = (t.chest() - a.chest()).normalized().rotated(Vector3.UP, 0.25)
			Projectile.spawn(a, a.chest() + dir * 0.7, dir * 30.0, {"amount": dealt * 0.35, "dtype": "energy", "status": {}, "art": true}, "pulse", {"range": 30.0, "homing": 1.0, "color": Color(0.6, 0.8, 1.0)})
		"null_protocol":
			for sh in ["st_shield", "shield", "magic_shield"]:
				t.statuses.erase(sh)
		"first_era_rift":
			var pl: Vector3 = a.global_position - t.global_position
			pl.y = 0
			if pl.length() > 1.5:
				t.knockback += pl.normalized() * 1.5
	# fate links share part of the damage
	if int(t.get_meta("fate_link", 0)) > Time.get_ticks_msec():
		for o in _foes(a, t.global_position, 14.0):
			if o != t and int(o.get_meta("fate_link", 0)) > Time.get_ticks_msec():
				_hit(a, o, dealt * 0.3, "time")

## A perfect dodge (the blow passed through the i-frames).
static func on_dodge(a, src) -> void:
	match art_of(a):
		"lightning_rain":
			if float(a.get_meta("rain_cd", 0.0)) <= Time.get_ticks_msec() / 1000.0:
				a.set_meta("rain_cd", Time.get_ticks_msec() / 1000.0 + 3.0)
				_lightning_rain(a, a.facing, 4)
		"silent_cut":
			a.set_meta("silent_until", Time.get_ticks_msec() / 1000.0 + 1.5)
			if src != null and is_instance_valid(src) and src is Actor:
				a.counter_t = 1.5
				a.counter_target = src

static func on_parry(a, src) -> void:
	if art_of(a) == "comet_dance" and src != null and is_instance_valid(src):
		var aim: Vector3 = (src.global_position - a.global_position)
		aim.y = 0
		_comet(a, aim.normalized() if aim.length() > 0.1 else a.facing, 3)

static func on_block(a, amount: float) -> void:
	if art_of(a) == "lesser_eclipse":
		a.set_meta("eclipse", minf(100.0, float(a.get_meta("eclipse", 0.0)) + amount * 0.5 + 4.0))

## Foresight (Astrolabe of Fates): an enemy near the wielder starts a heavy
## or skill action → a warning thread and a brief slow-down (once per 4 s).
static func on_enemy_windup(enemy, act_name: String) -> void:
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or art_of(pl) != "threads_of_fate":
		return
	if act_name != "skill" or enemy.global_position.distance_to(pl.global_position) > 12.0 or not Game.is_enemy(enemy, pl):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if float(pl.get_meta("foresight_cd", 0.0)) > now:
		return
	pl.set_meta("foresight_cd", now + 4.0)
	VFX.beam(enemy.chest(), pl.chest(), Color(1.0, 0.85, 0.4), 0.5, 0.03, false)
	VFX.text(enemy.global_position + Vector3(0, 2.6, 0), "Предвидение!", Color(1.0, 0.85, 0.4), 0.9)
	CombatFeel.slowmo(0.5, 0.25)

static func tick(a, delta: float) -> void:
	var h := float(a.get_meta("heat_ss", 0.0))
	if h > 0.0:
		a.set_meta("heat_ss", maxf(0.0, h - 8.0 * delta))
