class_name CityLife
extends Node
## Daily Routine AI for townsfolk. Every settlement gets prepared places —
## shop counters and customer spots, the smith's anvil, the inn's bar,
## tables and stage, house beds, square benches and chat spots, guard posts
## and a patrol ring — computed from the town plan (no scene scan). A place
## is reserved while used, so ten people never queue for one stool.
## Each townsperson gets a profession, a home and work hours:
##   merchant  08–19 counter · 12–13 lunch · evening leisure · night home
##   smith     07–18 anvil   · 12–13 lunch · evening leisure · night home
##   innkeeper 10–24 bar     · night home
##   bard      18–23 inn stage (day: like a commoner)
##   commoner  07–17 work/errands · 12–13 lunch · 17–22 inn/bench/chat/market · night home
##   guard     posts (gates, market) and patrols in shifts, day and night
## Plans are recomputed once per half game hour (or when a place is lost),
## not every frame. Trade, tavern visits, songs and chats are counted and
## feed CityEconomy.

const BLOCK := 1.0 / 48.0              # half a game hour, in days
const LEISURE := ["inn", "inn", "bench", "chat", "market", "home"]

static var inst: CityLife = null

var world
var towns := {}                        # sid -> {spots: {kind: Array}, homes: Array, inns, shops, smithy, built}
var stats := {"trades": 0, "tavern_visits": 0, "songs": 0, "chats": 0, "sleeps": 0, "work_sessions": 0,
	"reservations": 0, "reservation_conflicts": 0, "plans": 0, "patrols": 0}

func setup(w) -> void:
	world = w
	inst = self

func _exit_tree() -> void:
	if inst == self:
		inst = null

# ---------------------------------------------------------------- places
func town(sid: String) -> Dictionary:
	if towns.has(sid):
		return towns[sid]
	var s = world._settlement(sid)
	if s == null:
		return {}
	var t := {"sid": sid, "spots": {}, "homes": [], "house_geo": {}, "has": {}, "center": Vector3(s.pos.x, float(s.height), s.pos.y), "r": float(s.radius)}
	var h := float(s.height)
	for b in s.get("buildings", []):
		var base := Vector3(b.pos.x, h, b.pos.y)
		var bas := Basis(Vector3.UP, float(b.rot))
		var w: float = b.size.x
		var d: float = b.size.y
		var L := func(x: float, z: float) -> Vector3: return base + bas * Vector3(x, 0, z)
		var into: Vector3 = bas * Vector3(0, 0, -1)
		var door: Vector3 = L.call(0.0, d * 0.5 + 1.4)
		var bid: String = str(b.id)
		match String(b.kind):
			"inn":
				_add(t, "inn_keeper", L.call(0.0, -d * 0.5 + 0.75), -into, bid, door)
				for p in [Vector2(-0.25, -0.02), Vector2(0.25, -0.02), Vector2(-0.25, 0.22), Vector2(0.25, 0.22), Vector2(-0.08, 0.1), Vector2(0.08, 0.1)]:
					var sp: Vector3 = L.call(p.x * w, p.y * d)
					var tbl: Vector3 = L.call(0.0, 0.1 * d)
					_add(t, "inn_seat", sp, (tbl - sp).normalized() if tbl.distance_to(sp) > 0.1 else into, bid, door)
				_add(t, "inn_stage", L.call(-w * 0.36, d * 0.3), bas * Vector3(1, 0, -0.3).normalized(), bid, door)
				t.has.inn = true
			"shop":
				_add(t, "shop_keeper", L.call(0.0, -d * 0.5 + 0.7), -into, bid, door)
				_add(t, "shop_customer", L.call(-0.6, -d * 0.5 + 2.1), into, bid, door)
				_add(t, "shop_customer", L.call(0.6, -d * 0.5 + 2.1), into, bid, door)
				t.has.shop = true
			"smithy":
				_add(t, "smith_work", L.call(0.5, 0.45), into, bid, door)
				_add(t, "shop_customer", L.call(-0.9, 1.6), bas * Vector3(1, 0, -1).normalized(), bid, door)
				t.has.smithy = true
			"house":
				if Housing.is_private(bid):
					continue          # the player's house (for sale or owned): no residents, no routines
				_add(t, "home_bed", L.call(-w * 0.5 + 0.75, -d * 0.5 + 1.45), into, bid, door)
				t.homes.append(bid)
				t.house_geo[bid] = {"base": base, "rot": float(b.rot), "w": w, "d": d, "door": door}
	# square: chat pairs, benches, a musician spot
	var c: Vector3 = t.center
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var m: Vector3 = c + Vector3(cos(a), 0, sin(a)) * 6.5
		var side := Vector3(cos(a + PI * 0.5), 0, sin(a + PI * 0.5))
		_add(t, "chat", m + side * 0.75, -side, "", Vector3.INF)
		_add(t, "chat", m - side * 0.75, side, "", Vector3.INF)
	for j in world.activity_points(sid):
		var k: String = String(j.kind)
		if k in ["bench", "well", "campfire"]:
			_add(t, "bench", j.pos, j.get("face", Vector3.FORWARD), "", Vector3.INF)
		elif k == "stall":
			_add(t, "stall_keeper", j.pos, j.get("face", Vector3.FORWARD), "", Vector3.INF)
			_add(t, "shop_customer", j.pos + j.get("face", Vector3.FORWARD) * 1.6, -j.get("face", Vector3.FORWARD), "", Vector3.INF)
	_add(t, "street_music", c + Vector3(3.0, 0, -2.0), Vector3(-1, 0, 0.5).normalized(), "", Vector3.INF)
	# guard posts: four approaches + the market; a patrol ring around the square
	for i in 4:
		var a2 := TAU * i / 4.0
		_add(t, "guard_post", c + Vector3(cos(a2), 0, sin(a2)) * t.r * 0.78, Vector3(cos(a2), 0, sin(a2)), "", Vector3.INF)
	_add(t, "guard_post", c + Vector3(0, 0, 4.5), Vector3(0, 0, -1), "", Vector3.INF)
	var ring: Array = []
	for i in 6:
		var a3 := TAU * i / 6.0
		ring.append(c + Vector3(cos(a3), 0, sin(a3)) * t.r * 0.45)
	t.patrol = ring
	towns[sid] = t
	return t

## Drop every spot of a building (it became the player's house) and re-home
## whoever lived there.
func forget_building(sid: String, bid: String) -> void:
	var t: Dictionary = towns.get(sid, {})
	if t.is_empty():
		return
	t.homes.erase(bid)
	t.house_geo.erase(bid)
	for k in t.spots:
		t.spots[k] = t.spots[k].filter(func(sp): return sp.bid != bid)
	for a in world.settlement_npcs.get(sid, []):
		if is_instance_valid(a) and a.get_meta("home_bid", "") == bid:
			a.remove_meta("home_bid")
			if not t.homes.is_empty():
				a.set_meta("home_bid", t.homes[absi(hash(a.actor_id)) % t.homes.size()])
			a.remove_meta("plan")

func _add(t: Dictionary, kind: String, pos: Vector3, face: Vector3, bid: String, door: Vector3) -> void:
	if not t.spots.has(kind):
		t.spots[kind] = []
	pos.y = world.ground_height(pos) if bid == "" else pos.y
	t.spots[kind].append({"id": "%s:%s:%d" % [t.sid, kind, t.spots[kind].size()], "kind": kind, "pos": pos, "face": face.normalized() if face.length() > 0.01 else Vector3.FORWARD,
		"bid": bid, "door": door, "by": ""})

func reserve(spot: Dictionary, a) -> bool:
	if spot.by != "" and spot.by != a.actor_id:
		var holder = _by_id(spot.by)
		if holder != null and is_instance_valid(holder) and not holder.is_dead and holder.get_meta("spot_id", "") == spot.id:
			stats.reservation_conflicts += 1
			return false
	release(a)
	spot.by = a.actor_id
	a.set_meta("spot_id", spot.id)
	stats.reservations += 1
	return true

func release(a) -> void:
	var sid: String = a.get_meta("spot_id", "")
	if sid == "":
		return
	a.remove_meta("spot_id")
	var tsid: String = sid.get_slice(":", 0)
	var t: Dictionary = towns.get(tsid, {})
	for k in t.get("spots", {}):
		for sp in t.spots[k]:
			if sp.id == sid and sp.by == a.actor_id:
				sp.by = ""
				return

func _by_id(id: String):
	for a in Game.actors:
		if is_instance_valid(a) and a.actor_id == id:
			return a
	return null

func free_spot(t: Dictionary, kind: String, near: Vector3, a = null):
	var best = null
	var bd := INF
	for sp in t.spots.get(kind, []):
		if sp.by != "" and (a == null or sp.by != a.actor_id):
			var holder = _by_id(sp.by)
			if holder != null and is_instance_valid(holder) and not holder.is_dead and holder.get_meta("spot_id", "") == sp.id:
				continue
			sp.by = ""
		var dd: float = sp.pos.distance_squared_to(near)
		if dd < bd:
			bd = dd
			best = sp
	return best

# ---------------------------------------------------------------- residents
func assign(n) -> void:
	if n.has_meta("prof"):
		return
	var sid: String = str(n.get("settlement_id"))
	var t := town(sid)
	if t.is_empty():
		return
	var prof := "commoner"
	var role := str(n.get("role"))
	if role == "guard":
		prof = "guard"
	elif role == "trader":
		prof = "merchant"
	elif role == "healer":
		prof = "healer"
	else:
		var taken := {}
		for o in world.settlement_npcs.get(sid, []):
			if is_instance_valid(o) and o != n and o.has_meta("prof"):
				taken[o.get_meta("prof")] = true
		if t.has.get("smithy", false) and not taken.has("smith"):
			prof = "smith"
		elif t.has.get("inn", false) and not taken.has("innkeeper"):
			prof = "innkeeper"
		elif t.has.get("inn", false) and not taken.has("bard"):
			prof = "bard"
	n.set_meta("prof", prof)
	if not t.homes.is_empty():
		n.set_meta("home_bid", t.homes[absi(hash(n.actor_id)) % t.homes.size()])

## Current routine activity for a townsperson. Returns {} when the town or
## the person has no routine (caller falls back to its older behaviour).
func plan(n) -> Dictionary:
	if world.get("director") and world.director.has_method("blood_moon_active") and world.director.blood_moon_active():
		return {}
	var sid: String = str(n.get("settlement_id"))
	if sid == "" or CityPeace.inst == null:
		return {}
	var st: String = CityPeace.inst.state_of(sid)
	if st in ["alarm", "attack"]:
		return {}
	assign(n)
	var t := town(sid)
	if t.is_empty():
		return {}
	var cached: Dictionary = n.get_meta("plan", {})
	if not cached.is_empty() and float(cached.until) > Game.game_time and cached.get("spot_id", "") == n.get_meta("spot_id", ""):
		return cached
	stats.plans += 1
	var h := Game.hour()
	var prof: String = n.get_meta("prof", "commoner")
	var blk := int(Game.game_time / BLOCK)
	var act := ""
	var kinds: Array = []
	match prof:
		"guard":
			var shift := absi(hash(n.actor_id)) % 2
			var night := h >= 22.0 or h < 6.0
			if night and shift == 0:
				act = "sleep"
				kinds = ["home_bed"]
			elif (blk + shift) % 3 == 0:
				act = "patrol"
			else:
				act = "post"
				kinds = ["guard_post"]
		"merchant":
			if h >= 8.0 and h < 19.0 and not (h >= 12.0 and h < 12.5):
				act = "trade"
				kinds = ["shop_keeper", "stall_keeper"]
			elif h >= 12.0 and h < 12.5:
				act = "eat"
				kinds = ["inn_seat", "bench"]
			elif h >= 22.0 or h < 7.0:
				act = "sleep"
				kinds = ["home_bed"]
			else:
				act = _leisure(n, blk)
		"smith":
			if h >= 7.0 and h < 18.0 and not (h >= 12.0 and h < 12.5):
				act = "work"
				kinds = ["smith_work"]
			elif h >= 12.0 and h < 12.5:
				act = "eat"
				kinds = ["inn_seat", "bench"]
			elif h >= 22.0 or h < 6.5:
				act = "sleep"
				kinds = ["home_bed"]
			else:
				act = _leisure(n, blk)
		"healer":
			# receives the sick at the square by day
			if h >= 8.0 and h < 20.0 and not (h >= 13.0 and h < 13.5):
				act = "bench"
				kinds = ["bench", "chat"]
			elif h >= 13.0 and h < 13.5:
				act = "eat"
				kinds = ["inn_seat", "bench"]
			elif h >= 22.0 or h < 7.0:
				act = "sleep"
				kinds = ["home_bed"]
			else:
				act = _leisure(n, blk)
		"innkeeper":
			if h >= 10.0 or h < 0.5:
				act = "serve"
				kinds = ["inn_keeper"]
			else:
				act = "sleep"
				kinds = ["home_bed"]
		_:
			if prof == "bard" and h >= 18.0 and h < 23.0:
				act = "play"
				kinds = ["inn_stage", "street_music"]
			elif h >= 22.0 or h < 6.5:
				act = "sleep"
				kinds = ["home_bed"]
			elif h >= 12.0 and h < 13.0:
				act = "eat"
				kinds = ["inn_seat", "bench"]
			elif h >= 7.0 and h < 17.0:
				if n.has_meta("job") and (blk % 3) != 2:
					act = "job"
				else:
					act = "shop"
					kinds = ["shop_customer"]
			else:
				act = _leisure(n, blk)
	if kinds.is_empty():
		match act:
			"inn":
				kinds = ["inn_seat", "bench"]
			"bench":
				kinds = ["bench", "chat"]
			"chat":
				kinds = ["chat", "bench"]
			"market", "shop":
				kinds = ["shop_customer", "bench"]
			"home":
				kinds = ["home_bed"]
	var out := {"act": act, "until": (blk + 1) * BLOCK, "spot_id": ""}
	if act == "patrol":
		out.patrol = t.patrol
		stats.patrols += 1
	elif act == "job":
		out.job = true
	else:
		var spot = null
		var home_bid: String = n.get_meta("home_bid", "")
		for k in kinds:
			if k == "home_bed" and home_bid != "":
				for sp in t.spots.get("home_bed", []):
					if sp.bid == home_bid:
						spot = sp
				if spot != null and spot.by != "" and spot.by != n.actor_id:
					spot = free_spot(t, "home_bed", n.global_position, n)
			else:
				spot = free_spot(t, k, n.global_position, n)
			if spot != null and reserve(spot, n):
				break
			spot = null
		if spot == null and act == "sleep" and home_bid != "" and t.house_geo.has(home_bid):
			release(n)
			# the family bed is taken: sleep elsewhere in the same house
			# (not a reserved place — a house holds the whole household)
			var g: Dictionary = t.house_geo[home_bid]
			var k2 := absi(hash(n.actor_id)) % 4
			var off := Vector3((-0.25 + 0.5 * (k2 % 2)) * float(g.w), 0, (0.05 + 0.2 * (k2 / 2)) * float(g.d))
			spot = {"id": "", "kind": "home_floor", "pos": g.base + Basis(Vector3.UP, g.rot) * off, "face": Vector3.FORWARD, "bid": home_bid, "door": g.door, "by": ""}
		if spot == null:
			out.act = "stroll"
		else:
			out.spot = spot
			out.spot_id = spot.id
	n.set_meta("plan", out)
	return out

func _leisure(n, blk: int) -> String:
	var k := absi(hash(n.actor_id + str(blk / 4))) % LEISURE.size()
	return LEISURE[k]

## Called by the brain while the person performs the activity at its spot.
func perform(n, pl: Dictionary, delta: float) -> void:
	var sp: Dictionary = pl.get("spot", {})
	var act: String = pl.act
	var cd := float(n.get_meta("act_cd", 0.0)) - delta
	n.set_meta("act_cd", cd)
	if cd > 0.0 or not n.act.is_empty():
		return
	match act:
		"trade", "serve":
			n.set_meta("act_cd", randf_range(4.0, 7.0))
			n.start_action("work", 0.5, 0.3, {"anim": "interact"})
		"shop", "market":
			n.set_meta("act_cd", randf_range(6.0, 10.0))
			var keeper = _keeper_near(n, sp.pos)
			if keeper != null:
				n.start_action("work", 0.5, 0.3, {"anim": "interact"})
				keeper.start_action("work", 0.5, 0.3, {"anim": "interact"})
				stats.trades += 1
				if CityEconomy.inst:
					CityEconomy.inst.sale(str(n.get("settlement_id")), "goods")
				if Game.player and n.global_position.distance_to(Game.player.global_position) < 30.0:
					VFX.burst(n.chest() + n.facing * 0.5, Color(1.0, 0.85, 0.3), 5, 0.12)
			else:
				n.start_action("work", 0.5, 0.3, {"anim": "talk"})
		"work":
			n.set_meta("act_cd", 1.4)
			n.start_action("work", 0.6, 0.35, {"anim": "overhead"})
			stats.work_sessions += 1
			if Game.player and n.global_position.distance_to(Game.player.global_position) < 35.0:
				var hp: Vector3 = n.global_position + n.facing * 0.9 + Vector3(0, 0.9, 0)
				VFX.burst(hp, Color(1.0, 0.7, 0.3), 6, 0.16)
				Audio.play_sfx("hit_metal", hp, -15.0, 0.15)
		"eat", "inn":
			n.set_meta("act_cd", randf_range(5.0, 9.0))
			n.start_action("work", 0.9, 0.5, {"anim": "drink" if randf() < 0.55 else "talk"})
		"chat":
			n.set_meta("act_cd", randf_range(3.0, 6.0))
			n.start_action("work", 1.2, 0.5, {"anim": "talk"})
		"play":
			n.set_meta("act_cd", 2.2)
			n.start_action("work", 2.0, 0.5, {"anim": "play"})
			if Game.player and n.global_position.distance_to(Game.player.global_position) < 25.0 and randf() < 0.4:
				VFX.text(n.global_position + Vector3(0, 2.3, 0), "♪", Color(1.0, 0.9, 0.6), 0.8)
		"watch":
			n.set_meta("act_cd", randf_range(3.0, 7.0))
			n.start_action("work", 1.0, 0.5, {"anim": "cheer" if randf() < 0.35 else "talk"})
		"post", "bench":
			n.set_meta("act_cd", randf_range(6.0, 12.0))
			if randf() < 0.3:
				n.start_action("work", 1.0, 0.5, {"anim": "talk"})

## Counted once when a person settles at a spot.
func arrived(n, pl: Dictionary) -> void:
	match String(pl.act):
		"eat", "inn":
			stats.tavern_visits += 1
		"play":
			stats.songs += 1
		"chat":
			stats.chats += 1
		"sleep":
			stats.sleeps += 1

func _keeper_near(n, p: Vector3):
	for a in Game.actors_near(p, 3.2):
		if a != n and not a.is_dead and a.has_meta("plan") and String(a.get_meta("plan").get("act", "")) in ["trade", "serve", "work"]:
			return a
	return null

## Is this merchant at its counter right now (trade dialogs ask this)?
func is_open(n) -> bool:
	var pl: Dictionary = n.get_meta("plan", {})
	return String(pl.get("act", "")) in ["trade", "serve", "work"] or not n.has_meta("prof")
