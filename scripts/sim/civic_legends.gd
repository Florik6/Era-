class_name CivicLegends
extends Node
## Peaceful careers on top of the Living Legends system. Not every legend is a
## warrior: the town smith, a guard, a merchant, the healer, the innkeeper, a
## bard — and explorers, scientists, inventors and travellers met in events —
## grow through REAL deeds only:
##   smith      — the hero crafts at the town's forge / workshop; a rare or
##                legendary item made there counts triple;
##   guard      — fights raiders during a real raid, survives the defence;
##   merchant   — real trade with the hero (every ~300 coins), deliveries;
##   healer     — treats the hero's wounds;
##   innkeeper / bard — gatherings and performances that really happened;
##   explorer / scientist / inventor / traveller — successful events.
## Each deed is a Chronicle entry with the NPC as actor, so it lands in the
## NPC's real biography (LegendSystem.biography); ranks rise at fixed deed
## points and the top rank makes the NPC a living legend (Chronicle
## "legend_born"). Townsfolk keep a stable identity per town and profession
## (Game.world_state.civic), so the same smith greets you on every visit.

const CAREERS := {
	"smith": {"ranks": ["подмастерье", "кузнец", "мастер-оружейник", "легендарный оружейник"], "need": [0, 3, 7, 12]},
	"guard": {"ranks": ["стражник", "старший стражник", "сержант стражи", "капитан городской стражи"], "need": [0, 2, 5, 9]},
	"merchant": {"ranks": ["лавочник", "купец", "торговый мастер", "знаменитый торговец"], "need": [0, 3, 7, 12]},
	"healer": {"ranks": ["целитель", "опытный лекарь", "мастер врачевания", "прославленный целитель"], "need": [0, 2, 5, 9]},
	"innkeeper": {"ranks": ["трактирщик", "хозяин таверны", "знаменитый трактирщик"], "need": [0, 3, 7]},
	"bard": {"ranks": ["уличный музыкант", "бард", "знаменитый бард"], "need": [0, 2, 5]},
	"explorer": {"ranks": ["следопыт", "исследователь", "знаменитый исследователь"], "need": [0, 2, 5]},
	"scientist": {"ranks": ["подмастерье науки", "учёный", "выдающийся учёный"], "need": [0, 2, 5]},
	"inventor": {"ranks": ["механик", "изобретатель", "великий изобретатель"], "need": [0, 2, 5]},
	"traveler": {"ranks": ["путник", "путешественник", "легендарный путешественник"], "need": [0, 2, 5]},
}
const DEED_TEXT := {
	"craft": "%s помог(ла) герою %s выковать «%s» в мастерской поселения «%s».",
	"rare_craft": "%s вместе с героем %s создал(а) редкое изделие «%s» — о мастерской «%s» заговорили.",
	"defense": "%s защищал(а) жителей поселения «%s» во время налёта и получил(а) награду.",
	"raider": "%s сразил(а) налётчика у поселения «%s».",
	"trade": "%s заключил(а) крупную сделку с героем %s в поселении «%s».",
	"heal": "%s вылечил(а) раны героя %s в поселении «%s».",
	"event": "%s: %s («%s»).",
}

static var inst: CivicLegends = null

var world
var stats := {"deeds": 0, "promotions": 0, "legends": 0, "adopted": 0}
var _raid_part := {}            # actor_id -> true: guards that fought raiders in the current raid

func setup(w) -> void:
	world = w
	inst = self
	if not Game.world_state.has("civic"):
		Game.world_state.civic = {}
	Events.actor_damaged.connect(_on_damaged)
	Events.actor_killed.connect(_on_killed)

func _exit_tree() -> void:
	if inst == self:
		inst = null

func _legends():
	return world.legends if world else null

# ------------------------------------------------------------------ identity
## Give a townsperson their persistent record (create it on the first visit).
func adopt(n, prof: String) -> void:
	if n == null or not is_instance_valid(n) or n.has_meta("civic_id") or not CAREERS.has(prof) or _legends() == null:
		return
	var sid: String = str(n.get("settlement_id"))
	var idx := 0
	for o in world.settlement_npcs.get(sid, []):
		if is_instance_valid(o) and o != n and o.get_meta("prof", "") == prof and o.has_meta("civic_id"):
			idx += 1
	var key := "%s:%s:%d" % [sid, prof, idx]
	var map: Dictionary = Game.world_state.civic
	var rec: Dictionary = _legends().record(str(map.get(key, "")))
	if rec.is_empty():
		rec = _legends().new_record(n.data.name, {"role": "civic", "level": n.data.level, "pos": [n.global_position.x, n.global_position.z]})
		rec.civic = prof
		rec.civic_points = 0
		rec.civic_rank = 0
		rec.town = sid
		rec.female = bool(n.rig.look.get("female", false)) if n.rig else false
		rec.look = n.rig.look.duplicate() if n.rig else {}
		map[key] = rec.id
	else:
		# the same person as on the last visit: name and face
		n.data.name = rec.name
		if n.rig and not rec.get("look", {}).is_empty() and n.rig.look != rec.look:
			var r := HumanoidRig.new()
			r.setup(rec.look)
			n.rig.queue_free()
			n.set_rig(r)
			n.refresh_gear()
	n.set_meta("civic_id", rec.id)
	_name_tag(n, rec)
	stats.adopted += 1

func record_of(n) -> Dictionary:
	if n == null or not is_instance_valid(n) or not n.has_meta("civic_id") or _legends() == null:
		return {}
	return _legends().record(str(n.get_meta("civic_id")))

func rank_name(rec: Dictionary) -> String:
	var c: Dictionary = CAREERS.get(str(rec.get("civic", "")), {})
	if c.is_empty():
		return ""
	return c.ranks[clampi(int(rec.get("civic_rank", 0)), 0, c.ranks.size() - 1)]

func _name_tag(n, rec: Dictionary) -> void:
	var rn := rank_name(rec)
	if str(rec.get("civic", "")) == "healer":
		rn = Spawner.HEALER_TITLES[clampi(Profile.current_era, 0, 4)] if int(rec.civic_rank) == 0 else rn
	n.display_name = "%s (%s)" % [rec.name, rn]

func _npc_of(rec_id: String):
	for a in Game.actors:
		if is_instance_valid(a) and not a.is_dead and a.get_meta("civic_id", "") == rec_id:
			return a
	return null

# ------------------------------------------------------------------ deeds
## Record a real deed: Chronicle entry (→ biography), points, promotion.
func deed(rec: Dictionary, kind: String, points: int, text: String, pos := Vector3.INF) -> void:
	if rec.is_empty():
		return
	var data := {"text": text, "extra": {"civic": rec.get("civic", ""), "deed": kind}}
	if pos != Vector3.INF:
		data.pos_v3 = pos
	var actors: Array = [{"id": rec.id, "name": rec.name}]
	if kind in ["craft", "rare_craft", "trade", "heal"]:
		actors.append({"id": "player", "name": Profile.char.name})
	Chronicle.record("civic_deed", actors, data)
	rec.civic_points = int(rec.get("civic_points", 0)) + points
	rec.renown = float(rec.renown) + 4.0 * points
	stats.deeds += 1
	_promote(rec)

func _promote(rec: Dictionary) -> void:
	var c: Dictionary = CAREERS.get(str(rec.get("civic", "")), {})
	if c.is_empty():
		return
	var r := 0
	for i in c.need.size():
		if int(rec.civic_points) >= int(c.need[i]):
			r = i
	if r <= int(rec.get("civic_rank", 0)):
		return
	rec.civic_rank = r
	stats.promotions += 1
	var top: bool = r == c.ranks.size() - 1
	var title: String = String(c.ranks[r])
	var n = _npc_of(rec.id)
	if n:
		_name_tag(n, rec)
	if top and not rec.legend:
		rec.legend = true
		rec.title = title.substr(0, 1).to_upper() + title.substr(1)
		stats.legends += 1
		var ev := Chronicle.record("legend_born", [{"id": rec.id, "name": rec.name}], {"extra": {"title": rec.title}})
		if not rec.events.has(ev.id):
			rec.events.append(ev.id)
		Events.banner.emit("Новая легенда города", "%s — %s" % [rec.name, title], Color(1.0, 0.8, 0.4))
		if n and world.spawner.has_method("name_tag"):
			world.spawner.name_tag(n, Color(1.0, 0.75, 0.25))
	else:
		Chronicle.record("civic_rank", [{"id": rec.id, "name": rec.name}], {"text": "%s теперь — %s." % [rec.name, title], "extra": {"rank": title}})
		Events.notify.emit("%s теперь — %s" % [rec.name, title], Color(1.0, 0.85, 0.5))

func _town_name(sid: String) -> String:
	var s = world._settlement(sid)
	return str(s.get("name", "")) if s != null else ""

func _nearest_town(p: Vector3) -> String:
	if CityPeace.inst == null:
		return ""
	var c = CityPeace.inst.city_at(p, 30.0)
	return str(c.id) if c != null else ""

func _townsperson(sid: String, prof: String):
	for n in world.settlement_npcs.get(sid, []):
		if is_instance_valid(n) and not n.is_dead and n.get_meta("prof", "") == prof:
			if not n.has_meta("civic_id"):
				adopt(n, prof)
			return n
	return null

# ------------------------------------------------------------------ hooks
## Crafting at a town forge / workshop / lab (Recipes, Stations).
func on_craft(item: Dictionary) -> void:
	var pl = world.player
	if pl == null or item.is_empty():
		return
	var sid := _nearest_town(pl.global_position)
	if sid == "":
		return
	var smith = _townsperson(sid, "smith")
	if smith == null:
		return
	var rec := record_of(smith)
	var rare: bool = int(item.get("rarity", 0)) >= 3
	var nm := ItemDB.display_name(item)
	deed(rec, "rare_craft" if rare else "craft", 3 if rare else 1, DEED_TEXT["rare_craft" if rare else "craft"] % [rec.name, Profile.char.name, nm, _town_name(sid)], smith.global_position)

## Trade with a merchant: one deed per ~300 coins of real business.
func on_trade(n, price: int) -> void:
	var rec := record_of(n)
	if rec.is_empty() or str(rec.get("civic", "")) != "merchant":
		return
	rec.trade_acc = int(rec.get("trade_acc", 0)) + price
	while int(rec.trade_acc) >= 300:
		rec.trade_acc = int(rec.trade_acc) - 300
		deed(rec, "trade", 1, DEED_TEXT.trade % [rec.name, Profile.char.name, _town_name(str(rec.get("town", "")))], n.global_position)

func on_heal(n) -> void:
	var rec := record_of(n)
	if rec.is_empty():
		return
	deed(rec, "heal", 1, DEED_TEXT.heal % [rec.name, Profile.char.name, _town_name(str(rec.get("town", "")))], n.global_position)

## A guard (or any townsperson with a career) hurting a raider during an attack.
func _on_damaged(t, _amount: float, src, _dt: String) -> void:
	if src == null or not is_instance_valid(src) or t == null or not is_instance_valid(t):
		return
	if not src.has_meta("civic_id") or not CityPeace.hostile_kind(t):
		return
	_raid_part[src.actor_id] = true

func _on_killed(victim, killer) -> void:
	if killer == null or not is_instance_valid(killer) or not killer.has_meta("civic_id"):
		return
	if victim == null or not CityPeace.hostile_kind(victim):
		return
	var rec := record_of(killer)
	if rec.is_empty() or str(rec.get("civic", "")) != "guard":
		return
	deed(rec, "raider", 1, DEED_TEXT.raider % [rec.name, _town_name(str(rec.get("town", "")))], killer.global_position)

## Called by CityPeace when an attack on a town ends.
func on_attack_end(sid: String, outcome: String) -> void:
	for n in world.settlement_npcs.get(sid, []):
		if not is_instance_valid(n) or n.is_dead or n.get_meta("prof", "") != "guard":
			continue
		if not n.has_meta("civic_id"):
			adopt(n, "guard")
		var rec := record_of(n)
		var fought: bool = _raid_part.has(n.actor_id)
		if fought:
			deed(rec, "defense", 2, DEED_TEXT.defense % [rec.name, _town_name(sid)], n.global_position)
	_raid_part.clear()

## Successful events: hosts with a career get a deed; visiting explorers,
## scientists, inventors and travellers get (or continue) their own record.
func on_event_done(e: Dictionary, ok: bool) -> void:
	if not ok:
		return
	var tpl: Dictionary = e.tpl
	var host = e.get("data", {}).get("host")
	var arch: String = str(tpl.get("arch", ""))
	var career := ""
	match arch:
		"search", "outskirts":
			career = "explorer"
		"mystery", "investigation", "echo":
			career = "scientist" if int(tpl.era) >= 1 else "explorer"
		"outage", "hazard":
			career = "inventor" if int(tpl.era) >= 2 else ""
		"visitor":
			career = "traveler"
		"gathering", "spectacle", "competition":
			career = "bard"
		"merchant", "shortage", "price_shift":
			career = "merchant"
	if career == "":
		return
	var rec := {}
	if host != null and is_instance_valid(host):
		if host.has_meta("civic_id"):
			rec = record_of(host)
		elif career in ["explorer", "scientist", "inventor", "traveler"]:
			# the event's own person: a real record from now on
			rec = _legends().new_record(str(host.data.name if host.get("data") else host.display_name), {"role": "civic"})
			rec.civic = career
			rec.civic_points = 0
			rec.civic_rank = 0
			rec.town = str(e.get("sid", ""))
			host.set_meta("civic_id", rec.id)
	if rec.is_empty() and career in ["bard", "merchant"]:
		var prof := "bard" if career == "bard" else "merchant"
		var tp = _townsperson(str(e.get("sid", "")), prof)
		if tp:
			rec = record_of(tp)
	if rec.is_empty():
		return
	deed(rec, "event", 2, DEED_TEXT.event % [rec.name, str(e.get("result", tpl.name)), tpl.name], e.get("pos", Vector3.INF))
