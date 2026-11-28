class_name ManaSys
## Mana Resource System.
##
## Root cause of the "infinite mana" (fixed here): mana came back at 5 % of
## the maximum per second out of combat and 2.5 % in combat (a full bar in
## 20–40 s; with «Поток» ×1.6 in 12 s), regeneration ran right through and
## after every cast, hooks and buffs multiplied each other without a limit,
## and «Похищение маны» returned 8 % of every hit. So even a cataclysm cost
## only a few seconds of waiting, and potions were pointless.
##
## Now:
## · out of combat ≈ 1 % of max mana per second, in combat ≈ 0.3 %;
## · after a cast regeneration pauses: 3 s, 5 s after a strong spell
##   (≥ 25 % of the bar or tier IV+);
## · all regeneration bonuses (skills, staves, accessories, events, the
##   elixir) ADD up and are capped at +100 %; one effect never stacks with
##   itself (statuses are keyed by id);
## · mana leech is capped per second;
## · mana potions restore a fixed part, share an 8 s cool-down and never go
##   past the maximum.

const REGEN_IDLE := 0.010        # of max mana per second, out of combat
const REGEN_COMBAT := 0.003      # in combat (5 s since the last fight action)
const DELAY_BASE := 3.0          # no regeneration after a cast
const DELAY_STRONG := 5.0        # after a strong spell
const BONUS_CAP := 1.0           # bonuses add up to +100 % at most
const LEECH_CAP := 0.04          # leech: at most 4 % of max mana per second
const POTION_CD := 8.0

## id: [flat, part of max mana, elixir surge bonus, surge seconds]
const POTIONS := {
	"potion_mana_small": [25.0, 0.10, 0.0, 0.0],
	"potion_mana": [45.0, 0.20, 0.0, 0.0],
	"potion_mana_big": [80.0, 0.35, 0.0, 0.0],
	"potion_mana_elixir": [60.0, 0.25, 0.8, 30.0],
}

static var stats := {"spent": 0.0, "regen": 0.0, "potions": 0, "refused_cd": 0, "refused_mana": 0, "leech_capped": 0.0}
static var flash_ms := -100000      # HUD: the mana bar flashes red after a refused cast

## A cast was refused for lack of mana (HUD feedback, statistics).
static func refused(a) -> void:
	stats.refused_mana += 1
	if a != null and a.is_player:
		flash_ms = Time.get_ticks_msec()

## Mana per second this actor regains right now.
static func regen_rate(a) -> float:
	if a.max_mana <= 0.0 or a.statuses.has("exhausted"):
		return 0.0
	if a.mana_delay_t > 0.0:
		return 0.0
	var in_combat: bool = a.combat_t < 5.0
	if a.stats.has("no_mana_regen") and not in_combat:
		return 0.0
	var base: float = a.max_mana * (REGEN_COMBAT if in_combat else REGEN_IDLE)
	return base * (1.0 + regen_bonus(a))

## Sum of every regeneration bonus, capped (no runaway stacking).
static func regen_bonus(a) -> float:
	var bonus := 0.0
	if a.data and a.data.has_node("st_flow"):
		bonus += 0.6
	if a.hook("mana_idle") > 0.0 and Time.get_ticks_msec() - a._last_cast_ms > 3000:
		bonus += a.hook("mana_idle")
	bonus += float(a.stat("mana_regen"))
	if a.statuses.has("mana_surge"):
		bonus += float(a.statuses.mana_surge.get("k", 0.8))
	if Game.world and Game.world.get("director") and Game.world.director != null:
		bonus += float(Game.world.director.mods.get("mana_regen", 1.0)) - 1.0
	return clampf(bonus, -1.0, BONUS_CAP)

## Pay for a cast that really happened and start the regeneration pause.
static func on_spent(a, amount: float, tier := 0) -> void:
	if amount <= 0.0:
		return
	stats.spent += amount
	a._mana_fresh = false
	var strong: bool = tier >= 4 or amount >= a.max_mana * 0.25
	a.mana_delay_t = maxf(a.mana_delay_t, DELAY_STRONG if strong else DELAY_BASE)

static func restore(a, amount: float) -> float:
	var before: float = a.mana
	a.mana = clampf(a.mana + amount, 0.0, a.max_mana)
	return a.mana - before

## Mana from hits («Похищение маны», battle mage): capped per second.
static func leech(a, amount: float) -> void:
	var now := Time.get_ticks_msec()
	var win: Array = a.get_meta("leech_win", [0, 0.0])
	if now - int(win[0]) > 1000:
		win = [now, 0.0]
	var room: float = maxf(0.0, a.max_mana * LEECH_CAP - float(win[1]))
	var got := minf(amount, room)
	if got < amount:
		stats.leech_capped += amount - got
	win[1] = float(win[1]) + got
	a.set_meta("leech_win", win)
	restore(a, got)

# ------------------------------------------------------------------ saves
## Current mana, the regeneration pause, the potion cool-down and an active
## elixir are kept in the character, so a load, a new era scene or a house
## never refills (or empties) the bar.
static func store(a) -> void:
	if a == null or a.data == null or a.max_mana <= 0.0:
		return
	var v := {"mana": a.mana, "max_mana": a.max_mana, "delay": a.mana_delay_t, "potion_cd": a.potion_mana_cd}
	if a.statuses.has("mana_surge"):
		v.surge_t = float(a.statuses.mana_surge.get("t", 0.0))
		v.surge_k = float(a.statuses.mana_surge.get("k", 0.8))
	a.data.vitals = v

static func restore_saved(a) -> void:
	if a == null or a.data == null:
		return
	var v: Dictionary = a.data.vitals
	if v.is_empty() or not v.has("mana"):
		return
	a.mana = clampf(float(v.mana), 0.0, a.max_mana)
	a.mana_delay_t = clampf(float(v.get("delay", 0.0)), 0.0, DELAY_STRONG)
	a.potion_mana_cd = clampf(float(v.get("potion_cd", 0.0)), 0.0, POTION_CD)
	if float(v.get("surge_t", 0.0)) > 0.0:
		a.apply_status("mana_surge", minf(30.0, float(v.surge_t)), {"k": clampf(float(v.get("surge_k", 0.8)), 0.0, BONUS_CAP)})

static func is_mana_potion(base_id: String) -> bool:
	return POTIONS.has(base_id)

## Drink a mana potion. "" or the reason it was refused (nothing is spent then).
static func drink(a, base_id: String) -> String:
	if not POTIONS.has(base_id):
		return "это не зелье маны"
	if a.potion_mana_cd > 0.0:
		stats.refused_cd += 1
		return "зелье ещё действует — подождите %.0f с" % ceilf(a.potion_mana_cd)
	if a.mana >= a.max_mana - 0.5 and float(POTIONS[base_id][2]) <= 0.0:
		return "мана уже полна"
	var p: Array = POTIONS[base_id]
	restore(a, float(p[0]) + a.max_mana * float(p[1]))
	if float(p[2]) > 0.0:
		a.apply_status("mana_surge", float(p[3]), {"k": float(p[2])})
	a.potion_mana_cd = POTION_CD
	stats.potions += 1
	VFX.burst(a.chest(), Color(0.35, 0.55, 1.0), 14, 0.3)
	Audio.play_sfx("heal", a.global_position, -3.0)
	if a.rig and a.act.is_empty():
		a.start_action("skill", 0.45, 0.9, {"anim": "drink"})
	return ""
