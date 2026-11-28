class_name Ammo
## Ammo Management System.
##
## Every bow, crossbow and firearm spends a real resource:
## · weapons with a magazine (muskets … pulse rifles) hold their loaded
##   rounds in the weapon item itself (`mag_cur`, saved with the item, kept
##   on weapon swaps) and reload from ammo items carried in the inventory;
## · bows and crossbows draw each arrow / bolt straight from the quiver
##   (the inventory), no magazine.
## A reload moves rounds from the reserve only when it COMPLETES; an
## interrupted reload (dodge, stun, weapon swap, firing what is left) moves
## nothing, so nothing is lost or duplicated. Energy weapons use energy units
## (impulse charges, cells, plasma batteries) the same way.
## Ammo items: 11 base types (one per weapon family) + 5 special ones
## (fire / rune arrows, alchemical charges, armour-piercing rounds, quantum
## cells). A special ammo is loaded by using it from the inventory: the
## rounds already in the magazine go back to the reserve.
## NPCs reload too (they pay the time) but carry an unlimited reserve.

const FAMILY_NAMES := {"ammo_arrow": "стрелы", "ammo_bolt": "болты", "ammo_ball": "пули", "ammo_revolver": "патроны",
	"ammo_rifle": "патроны", "ammo_shell": "патроны", "ammo_tesla": "заряды", "ammo_pistol": "патроны",
	"ammo_cell": "энергия", "ammo_pulse": "энергия", "ammo_plasma": "энергия"}
## Which weapons fire a family (item tooltips).
const FAMILY_WEAPONS := {"ammo_arrow": "луки", "ammo_bolt": "арбалеты", "ammo_ball": "мушкеты и кремнёвые пистоли",
	"ammo_revolver": "револьверы", "ammo_rifle": "винтовки и карабины", "ammo_shell": "дробовики", "ammo_tesla": "тесла-оружие",
	"ammo_pistol": "пистолеты и пистолеты-пулемёты", "ammo_cell": "умное оружие (энергоячейки)", "ammo_pulse": "импульсные винтовки",
	"ammo_plasma": "плазменные пушки"}

## id: [name, era, family, value per unit, desc, special mods]
const TYPES := {
	"ammo_arrow": ["Стрелы", 0, "ammo_arrow", 1, "Обычные стрелы для луков.", {}],
	"ammo_arrow_fire": ["Огненные стрелы", 0, "ammo_arrow", 6, "Стрелы с промасленной паклей: поджигают цель.", {"burn": 6.0}],
	"ammo_arrow_rune": ["Зачарованные стрелы", 0, "ammo_arrow", 9, "Руны на древке: урон ×1,35, светлая магия.", {"mult": 1.35, "dtype": "light"}],
	"ammo_bolt": ["Арбалетные болты", 0, "ammo_bolt", 1, "Тяжёлые болты для арбалетов.", {}],
	"ammo_ball": ["Пули и порох", 1, "ammo_ball", 2, "Свинцовые пули и порох для мушкетов и пистолей.", {}],
	"ammo_ball_alch": ["Алхимический заряд", 1, "ammo_ball", 10, "Пуля с алхимической начинкой: огненный разрыв 1,5 м.", {"splash": 1.5, "burn": 5.0, "dtype": "fire"}],
	"ammo_revolver": ["Револьверные патроны", 2, "ammo_revolver", 2, "Унитарные патроны для револьверов.", {}],
	"ammo_rifle": ["Винтовочные патроны", 2, "ammo_rifle", 3, "Патроны для винтовок и карабинов.", {}],
	"ammo_rifle_ap": ["Бронебойные патроны", 3, "ammo_rifle", 8, "Сердечник пробивает броню: −60% брони цели.", {"pen": 0.6}],
	"ammo_shell": ["Патроны для дробовика", 2, "ammo_shell", 3, "Картечь для дробовиков.", {}],
	"ammo_tesla": ["Электрические заряды", 2, "ammo_tesla", 4, "Лейденские заряды для тесла-излучателей.", {}],
	"ammo_pistol": ["Пистолетные патроны", 3, "ammo_pistol", 2, "Патроны для пистолетов и пистолетов-пулемётов.", {}],
	"ammo_cell": ["Энергетические ячейки", 3, "ammo_cell", 5, "Ячейки питания для энергетического оружия (1 ед. — 1 выстрел).", {}],
	"ammo_pulse": ["Импульсные заряды", 4, "ammo_pulse", 4, "Энергия для импульсных винтовок (1 ед. — 1 выстрел).", {}],
	"ammo_quantum": ["Квантовые элементы питания", 4, "ammo_pulse", 14, "Редкие элементы: урон ×1,4, выстрел пробивает цель.", {"mult": 1.4, "pierce": 1}],
	"ammo_plasma": ["Плазменные батареи", 4, "ammo_plasma", 12, "Батареи плазменных пушек (1 ед. — 1 выстрел).", {}],
}

static var _cache := {}

static func base(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	if not TYPES.has(id):
		return {}
	var t: Array = TYPES[id]
	var d := {"name": t[0], "era": int(t[1]), "slot": "ammo", "stack": true, "value": int(t[3]), "group": "ammo", "family": t[2],
		"desc": t[4], "ammo_mods": t[5], "special": not (t[5] as Dictionary).is_empty()}
	_cache[id] = d
	return d

static func has(id: String) -> bool:
	return TYPES.has(id)

static func ids() -> Array:
	return TYPES.keys()

# ------------------------------------------------------------------ weapons
## The ammo family (= base ammo item id) a weapon fires; "" if it needs none.
static func family_for(b: Dictionary) -> String:
	var cat := str(b.get("cat", ""))
	if not cat in ["bow", "firearm"]:
		return ""
	var model := str(b.get("model", ""))
	var proj := str(b.get("proj", "arrow"))
	match proj:
		"arrow": return "ammo_arrow"
		"bolt": return "ammo_bolt"
		"pellet": return "ammo_shell"
		"spark": return "ammo_tesla"
		"plasma": return "ammo_plasma"
		"pulse": return "ammo_cell" if model == "smart_gun" else "ammo_pulse"
	match model:
		"musket", "pistol_old": return "ammo_ball"
		"revolver": return "ammo_revolver"
		"rifle", "carbine": return "ammo_rifle"
		"pistol", "smg": return "ammo_pistol"
		"smart_gun": return "ammo_cell"
	return "ammo_pistol" if int(b.get("era", 3)) >= 3 else "ammo_ball"

static func uses_ammo(b: Dictionary) -> bool:
	return family_for(b) != ""

static func has_mag(b: Dictionary) -> bool:
	return int(b.get("mag", 0)) > 0

static func is_energy(b: Dictionary) -> bool:
	return family_for(b) in ["ammo_cell", "ammo_pulse", "ammo_plasma", "ammo_tesla"]

static func unit_name(b: Dictionary) -> String:
	return "энергии" if is_energy(b) else "патронов"

## Ammo item the weapon is set to fire (its family, or a special of it).
static func kind_of(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	var b := ItemDB.base(it.base)
	var fam := family_for(b)
	var k := str(it.get("ammo_kind", fam))
	if k == "" or not TYPES.has(k) or str(base(k).family) != fam:
		return fam
	return k

## Rounds loaded in the weapon (bows: what is in the quiver).
static func loaded(a) -> int:
	var it: Dictionary = a.weapon()
	if it.is_empty():
		return 0
	var b := ItemDB.base(it.base)
	if not has_mag(b):
		return reserve(a) if uses_ammo(b) else 0
	if not it.has("mag_cur"):
		# NPC guns come loaded; the hero's found / bought guns are empty
		return 0 if a.is_player else int(b.mag)
	return clampi(int(it.mag_cur), 0, int(b.mag))

static func set_loaded(a, n: int) -> void:
	var it: Dictionary = a.weapon()
	if it.is_empty():
		return
	var b := ItemDB.base(it.base)
	if has_mag(b):
		it["mag_cur"] = clampi(n, 0, int(b.mag))

## Spare rounds of the loaded kind carried in the inventory.
static func reserve(a, kind := "") -> int:
	if a.data == null:
		return 0
	var k := kind if kind != "" else kind_of(a.weapon())
	if k == "":
		return 0
	return a.data.inv.count(k)

## NPCs never run dry (they still reload); the hero and companions do.
static func unlimited(a) -> bool:
	return not a.is_player

static func can_fire(a, n := 1) -> bool:
	var it: Dictionary = a.weapon()
	if it.is_empty():
		return false
	var b := ItemDB.base(it.base)
	if not uses_ammo(b):
		return true
	if has_mag(b):
		return loaded(a) >= n
	return unlimited(a) or reserve(a) >= n

## Spend n rounds for a shot that is really fired. False: nothing to fire.
static func consume(a, n := 1) -> bool:
	var it: Dictionary = a.weapon()
	if it.is_empty():
		return false
	var b := ItemDB.base(it.base)
	if not uses_ammo(b):
		return true
	if has_mag(b):
		var cur := loaded(a)
		if cur < n:
			return false
		it["mag_cur"] = cur - n
		stats.shots += n
		return true
	if unlimited(a):
		return true
	if not a.data.inv.consume(kind_of(it), n):
		return false
	stats.shots += n
	return true

## Begin a reload. Returns "" or why it can't start.
static func start_reload(a) -> String:
	var it: Dictionary = a.weapon()
	if it.is_empty():
		return "нет оружия"
	var b := ItemDB.base(it.base)
	if not has_mag(b):
		return "этому оружию не нужна перезарядка"
	if a.reload_t > 0.0:
		return "уже перезаряжается"
	if loaded(a) >= int(b.mag):
		return "магазин полон"
	if not unlimited(a) and reserve(a) <= 0:
		return "нет запасных боеприпасов (%s)" % base(kind_of(it)).get("name", "")
	var t: float = float(b.get("reload", 1.5))
	if a.data and a.data.has_node("fa_reload"):
		t *= 0.6
	a.reload_t = t
	a.set_meta("reload_uid", int(it.get("uid", 0)))
	stats.reloads_started += 1
	if a.rig and a.rig.has_method("trigger"):
		a.rig.trigger("reload")
	Audio.play_sfx("reload", a.global_position, -4.0)
	return ""

## The reload finished: move rounds from the reserve into the magazine.
static func finish_reload(a) -> void:
	var it: Dictionary = a.weapon()
	var uid := int(a.get_meta("reload_uid", -1)) if a.has_meta("reload_uid") else -1
	if a.has_meta("reload_uid"):
		a.remove_meta("reload_uid")
	if it.is_empty() or int(it.get("uid", 0)) != uid:
		stats.reloads_cancelled += 1
		return
	var b := ItemDB.base(it.base)
	if not has_mag(b):
		return
	var cur := loaded(a)
	var need := int(b.mag) - cur
	if need <= 0:
		return
	var take := need
	if not unlimited(a):
		take = mini(need, reserve(a))
		if take <= 0:
			return
		a.data.inv.consume(kind_of(it), take)
	it["mag_cur"] = cur + take
	stats.reloads_done += 1

## Interrupt a reload: nothing is moved, so nothing is lost or created.
static func cancel_reload(a, why := "") -> void:
	if a.reload_t <= 0.0:
		return
	a.reload_t = 0.0
	if a.has_meta("reload_uid"):
		a.remove_meta("reload_uid")
	stats.reloads_cancelled += 1
	if a.is_player and why != "":
		Events.notify.emit("Перезарядка прервана: " + why, Color(0.9, 0.75, 0.5))

## Load a special ammo kind: unload the magazine back into the reserve.
static func select_kind(a, kind: String) -> String:
	var it: Dictionary = a.weapon()
	if it.is_empty():
		return "нет оружия в руках"
	var b := ItemDB.base(it.base)
	var fam := family_for(b)
	if not TYPES.has(kind) or str(base(kind).family) != fam:
		return "не подходит к оружию «%s»" % b.get("name", "")
	if kind_of(it) == kind:
		return "уже заряжено"
	cancel_reload(a)
	if has_mag(b):
		var cur := loaded(a)
		if cur > 0:
			var back := ItemDB.create(kind_of(it), 0, 1)
			back.qty = cur
			if not a.data.inv.add(back):
				return "некуда убрать патроны из магазина"
		it["mag_cur"] = 0
	it["ammo_kind"] = kind
	return ""

## Effects of a special ammo on a fired shot.
static func shot_mods(a, info: Dictionary, opts: Dictionary) -> void:
	var it: Dictionary = a.weapon()
	if it.is_empty() or a.data == null:
		return
	var m: Dictionary = base(kind_of(it)).get("ammo_mods", {})
	if m.is_empty():
		return
	info.amount = float(info.amount) * float(m.get("mult", 1.0))
	if m.has("dtype"):
		info.dtype = m.dtype
	if m.has("burn"):
		var st: Dictionary = info.get("status", {})
		st["burn"] = float(m.burn)
		info.status = st
	if m.has("pen"):
		info.armor_pen = float(m.pen)
	if m.has("splash"):
		opts.splash = maxf(float(opts.get("splash", 0.0)), float(m.splash))
	if m.has("pierce"):
		opts.pierce = int(opts.get("pierce", 0)) + int(m.pierce)

# ------------------------------------------------------------ boosted shot
## Energy weapons have a boosted mode: one shot spends BOOST_COST units of
## the cell, hits ×BOOST_MULT and pierces one more target. The mode is kept
## on the weapon item (so it is saved with it).
const BOOST_COST := 5
const BOOST_MULT := 4.0

static func boost_on(a) -> bool:
	if not a.is_player:
		return false
	var it: Dictionary = a.weapon()
	return not it.is_empty() and bool(it.get("boost", false)) and is_energy(ItemDB.base(it.base))

## Units one press of «Атака» spends.
static func shot_cost(a) -> int:
	return BOOST_COST if boost_on(a) else 1

static func toggle_boost(a) -> String:
	var it: Dictionary = a.weapon()
	if it.is_empty() or not is_energy(ItemDB.base(it.base)):
		return "усиленный выстрел есть только у энергетического оружия"
	it["boost"] = not bool(it.get("boost", false))
	return ""

## Rounds an ability shoots (weapon skills with the "shots"/"sky_volley"
## components): every projectile is one round, none is free.
static func ability_rounds(a, e: Dictionary) -> int:
	if a.data == null or not uses_ammo(a.weapon_base()):
		return 0
	var n := 0
	for f in e.get("fx", []):
		match str(f.get("c", "")):
			"shots":
				n += int(f.get("n", 1))
			"sky_volley":
				n += 1         # each further arrow is paid when it is loosed
	return n

## Label for the HUD counter.
static func hud_label(a) -> String:
	var b: Dictionary = a.weapon_base()
	if not uses_ammo(b):
		return ""
	if is_energy(b):
		return "Заряд"
	match family_for(b):
		"ammo_arrow": return "Стрелы"
		"ammo_bolt": return "Болты"
	return "Патроны"

## HUD text: "23 / 120" (magazine / reserve) or "45" for a quiver.
static func hud_text(a) -> String:
	var it: Dictionary = a.weapon()
	if it.is_empty():
		return ""
	var b := ItemDB.base(it.base)
	if not uses_ammo(b):
		return ""
	if has_mag(b):
		if a.reload_t > 0.0:
			return "перезарядка…"
		if boost_on(a):
			return "%d / %d ×%d" % [loaded(a), reserve(a), BOOST_COST]
		return "%d / %d" % [loaded(a), reserve(a)]
	return "%d" % reserve(a)

# ------------------------------------------------------------------ economy
## Ammo the shops of an era sell (families of that era and earlier).
static func shop_stock(era: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var stock := {
		0: [["ammo_arrow", 40], ["ammo_bolt", 30], ["ammo_arrow_fire", 10, 0.4], ["ammo_arrow_rune", 6, 0.2]],
		1: [["ammo_arrow", 30], ["ammo_bolt", 24], ["ammo_ball", 30], ["ammo_ball_alch", 6, 0.35]],
		2: [["ammo_ball", 20], ["ammo_revolver", 36], ["ammo_rifle", 30], ["ammo_shell", 20], ["ammo_tesla", 24]],
		3: [["ammo_pistol", 60], ["ammo_rifle", 60], ["ammo_shell", 24], ["ammo_cell", 30], ["ammo_rifle_ap", 12, 0.4]],
		4: [["ammo_pulse", 90], ["ammo_cell", 40], ["ammo_plasma", 12], ["ammo_quantum", 10, 0.3]],
	}
	for s in stock.get(clampi(era, 0, 4), []):
		if s.size() > 2 and rng.randf() > float(s[2]):
			continue
		var it := ItemDB.create(s[0], 0, 1)
		it.qty = int(s[1])
		out.append(it)
	return out

## A small ammo find for loot: fits the hero's ranged weapon when there is one.
static func loot_for(pl, era: int, rng: RandomNumberGenerator, big := false) -> Dictionary:
	var fam := ""
	if pl != null and is_instance_valid(pl) and pl.data != null:
		for sl in ["main", "off"]:
			var w: Dictionary = pl.data.inv.equipped(sl)
			if not w.is_empty():
				var f := family_for(ItemDB.base(w.base))
				if f != "":
					fam = f
		if fam == "":
			for w2 in pl.data.inv.items:
				var f2 := family_for(ItemDB.base(w2.base))
				if f2 != "":
					fam = f2
	if fam == "":
		var era_fams: Array = [["ammo_arrow", "ammo_bolt"], ["ammo_ball", "ammo_arrow"], ["ammo_revolver", "ammo_rifle", "ammo_shell"],
			["ammo_pistol", "ammo_rifle", "ammo_cell"], ["ammo_pulse", "ammo_cell", "ammo_plasma"]][clampi(era, 0, 4)]
		fam = era_fams[rng.randi() % era_fams.size()]
	return stack(fam, rng, big)

## A found stack of one ammo family (sizes per family: a few musket balls,
## a handful of arrows, a pack of pulse charges).
static func stack(fam: String, rng: RandomNumberGenerator, big := false) -> Dictionary:
	var it := ItemDB.create(fam, 0, 1)
	var per := {"ammo_arrow": 12, "ammo_bolt": 8, "ammo_ball": 5, "ammo_revolver": 8, "ammo_rifle": 8, "ammo_shell": 5,
		"ammo_tesla": 8, "ammo_pistol": 12, "ammo_cell": 10, "ammo_pulse": 15, "ammo_plasma": 2}
	it.qty = maxi(1, int(per.get(fam, 6) * (2.5 if big else 1.0) * rng.randf_range(0.7, 1.3)))
	return it

static func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r

## What a fallen shooter leaves: part of the ammunition it carried.
static func victim_drop(victim, era: int) -> Dictionary:
	var rng := _rng()
	var fam := family_for(victim.weapon_base()) if victim.has_method("weapon_base") else ""
	if fam != "" and rng.randf() < 0.55:
		return stack(fam, rng)
	if rng.randf() < 0.12:
		return loot_for(Game.player, era, rng)
	return {}

## Crafting: [station, ammo id, qty, cost dict, gold, min era]
const RECIPES := [
	["forge", "ammo_arrow", 20, {"iron_ore": 1, "herbs": 1}, 2, 0],
	["forge", "ammo_bolt", 15, {"iron_ore": 2}, 3, 0],
	["forge", "ammo_ball", 12, {"iron_ore": 2}, 4, 1],
	["forge", "ammo_revolver", 12, {"iron_ore": 2, "gears": 1}, 6, 2],
	["forge", "ammo_rifle", 10, {"iron_ore": 2, "gears": 1}, 8, 2],
	["forge", "ammo_shell", 8, {"iron_ore": 2}, 6, 2],
	["forge", "ammo_rifle_ap", 6, {"iron_ore": 3, "circuits": 1}, 25, 3],
	["lab", "ammo_arrow_fire", 10, {"herbs": 2}, 12, 0],
	["lab", "ammo_arrow_rune", 6, {"herbs": 2, "spirit_essence": 1}, 20, 0],
	["lab", "ammo_ball_alch", 6, {"herbs": 2, "iron_ore": 1}, 18, 1],
	["workshop", "ammo_tesla", 12, {"gears": 2}, 10, 2],
	["workshop", "ammo_pistol", 20, {"iron_ore": 2, "circuits": 1}, 8, 3],
	["workshop", "ammo_cell", 20, {"circuits": 2}, 12, 3],
	["workshop", "ammo_pulse", 30, {"circuits": 3}, 15, 4],
	["workshop", "ammo_plasma", 4, {"circuits": 3}, 30, 4],
	["workshop", "ammo_quantum", 6, {"circuits": 4, "chrono_shard": 1}, 60, 4],
]

static func recipes_for(world, station: String) -> Array:
	var out: Array = []
	var era := Profile.current_era
	var pd = world.player.data
	for r in RECIPES:
		if r[0] != station or int(r[5]) > era:
			continue
		var bid: String = r[1]
		var qty: int = r[2]
		var cost: Dictionary = r[3]
		var gold: int = r[4]
		out.append({"name": "%s ×%d" % [base(bid).name, qty], "desc": str(base(bid).desc), "cost": cost, "gold": gold, "group": "ammo",
			"cb": func():
				if not Stations._pay(world, cost, gold):
					return false
				var it := ItemDB.create(bid, 0, 1)
				it.qty = qty
				if not pd.inv.add(it):
					world.loot.spawn_drop(it, world.player.global_position + Vector3(1, 0, 0))
				stats.crafted += qty
				Audio.play_sfx("reload")
				return true})
	return out

## One-time grant for saves made before ammo existed and for new heroes:
## each ranged weapon the hero owns gets a loaded magazine and a reserve.
static func starter_supply(d, weapons: Array) -> int:
	var given := 0
	for it in weapons:
		if it.is_empty():
			continue
		var b := ItemDB.base(it.base)
		var fam := family_for(b)
		if fam == "":
			continue
		if has_mag(b) and not it.has("mag_cur"):
			it["mag_cur"] = int(b.mag)
		if d.inv.count(fam) <= 0:
			var res := ItemDB.create(fam, 0, 1)
			res.qty = maxi(int(b.get("mag", 0)) * 3, 40 if fam in ["ammo_arrow", "ammo_bolt"] else 12)
			if d.inv.add(res):
				given += res.qty
	return given

static var stats := {"shots": 0, "reloads_started": 0, "reloads_done": 0, "reloads_cancelled": 0, "crafted": 0, "dry_clicks": 0}
static var flash_ms := -100000      # HUD: the ammo counter flashes red after a dry click
