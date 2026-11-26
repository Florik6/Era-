class_name CombatFeel
extends RefCounted
## Combat feel: how movement, weapons and big moments *feel*.
##  - per-class movement style (acceleration, braking, turn rate, lean,
##    dodge kind/distance) — heavy warrior, nimble rogue, mobile archer,
##    composed mage with a blink;
##  - per-weapon weight (hit-stop, knockback, camera kick, lunge, finisher
##    knockback/launch);
##  - spectacle helpers (hit-stop, slow-motion, camera punch/kick, screen
##    flash, speed lines) that all respect Settings.combat_fx:
##    0 Выкл · 1 Минимально · 2 Стандартно · 3 Эпично.
## Danger zones and enemies stay readable: flashes are short and faint,
## slow-motion is a fraction of a second, nothing locks the controls.

const CLASS_MOVE := {
	"warrior": {"accel": 21.0, "decel": 17.0, "turn": 9.5, "lean": 0.1, "skid": true, "dodge": "roll", "dist": 5.2, "dur": 0.5, "step": "heavy"},
	"rogue": {"accel": 58.0, "decel": 44.0, "turn": 21.0, "lean": 0.2, "skid": true, "dodge": "shadow", "dist": 6.9, "dur": 0.3, "step": "light"},
	"archer": {"accel": 40.0, "decel": 32.0, "turn": 15.0, "lean": 0.16, "skid": true, "dodge": "leap", "dist": 6.2, "dur": 0.38, "step": "light"},
	"mage": {"accel": 27.0, "decel": 25.0, "turn": 11.0, "lean": 0.07, "skid": false, "dodge": "blink", "dist": 6.6, "dur": 0.2, "step": "soft"},
}
const DEFAULT_MOVE := {"accel": 42.0, "decel": 42.0, "turn": 12.0, "lean": 0.0, "skid": false, "dodge": "roll", "dist": 5.85, "dur": 0.45, "step": ""}

const WEAPON_FEEL := {
	"dagger": {"stop": 0.035, "knock": 1.6, "kick": 0.05, "lunge": 1.6, "fin_knock": 4.5, "launch": 0.0, "weight": 0.2},
	"sword": {"stop": 0.05, "knock": 2.8, "kick": 0.09, "lunge": 1.3, "fin_knock": 6.5, "launch": 2.5, "weight": 0.5},
	"spear": {"stop": 0.05, "knock": 3.6, "kick": 0.09, "lunge": 2.0, "fin_knock": 7.5, "launch": 2.0, "weight": 0.55},
	"heavy": {"stop": 0.1, "knock": 7.5, "kick": 0.25, "lunge": 0.7, "fin_knock": 12.0, "launch": 5.5, "weight": 1.0},
	"unarmed": {"stop": 0.04, "knock": 2.2, "kick": 0.06, "lunge": 1.2, "fin_knock": 5.0, "launch": 2.0, "weight": 0.3},
	"staff": {"stop": 0.05, "knock": 3.0, "kick": 0.1, "lunge": 0.9, "fin_knock": 6.0, "launch": 2.0, "weight": 0.6},
}

## multipliers per Settings.combat_fx level [off, min, std, epic]
const K := {"stop": [0.0, 0.6, 1.0, 1.25], "shake": [0.0, 0.5, 1.0, 1.3], "slowmo": [0.0, 0.0, 1.0, 1.35],
	"punch": [0.0, 0.5, 1.0, 1.4], "flash": [0.0, 0.0, 0.7, 1.0], "particles": [0.45, 0.7, 1.0, 1.3], "lines": [0.0, 0.0, 1.0, 1.0]}

static func level() -> int:
	return clampi(int(Settings.combat_fx), 0, 3)

static func k(kind: String) -> float:
	return float(K.get(kind, [1, 1, 1, 1])[level()])

static func move_style(a) -> Dictionary:
	if a == null or not is_instance_valid(a):
		return DEFAULT_MOVE
	if a.get("data") != null and a.data != null and (a.is_player or a.kind == "humanoid"):
		return CLASS_MOVE.get(String(a.data.class_id), DEFAULT_MOVE)
	return DEFAULT_MOVE

static func weapon_feel(cat: String) -> Dictionary:
	return WEAPON_FEEL.get(cat, WEAPON_FEEL.unarmed)

# ------------------------------------------------------------------ spectacle
static func hitstop(dur: float) -> void:
	var m := k("stop")
	if m > 0.0 and dur > 0.0:
		Game.hit_stop(dur * m)

static func slowmo(scale: float, real_dur: float) -> void:
	var m := k("slowmo")
	if m > 0.0:
		Game.slow_motion(scale, real_dur * m)

static func cam():
	return Game.world.cam if Game.world and Game.world.get("cam") != null else null

static func shake(a: float) -> void:
	var c = cam()
	if c and k("shake") > 0.0:
		c.shake(a * k("shake"))

static func punch(amount: float, dur: float = 0.25) -> void:
	var c = cam()
	if c and c.has_method("punch") and k("punch") > 0.0:
		c.punch(amount * k("punch"), dur)

static func kick(dir: Vector3, amount: float) -> void:
	var c = cam()
	if c and c.has_method("kick") and k("shake") > 0.0:
		c.kick(dir, amount * k("shake"))

static func overlay():
	return Game.world.sys("combat_overlay") if Game.world and Game.world.has_method("sys") else null

static func flash(c: Color, strength: float = 0.25) -> void:
	var o = overlay()
	if o and k("flash") > 0.0:
		o.flash(c, strength * k("flash"))

static func speed_lines(dur: float = 0.3, strength: float = 1.0) -> void:
	var o = overlay()
	if o and k("lines") > 0.0:
		o.speed_lines(dur, strength)

static func particles(n: int) -> int:
	var dq: float = [1.0, 0.75, 0.7, 0.6, 0.55, 0.5][clampi(DynamicQuality.level, 0, 5)]
	return maxi(1, int(round(n * k("particles") * float(Settings.profile().get("particles", 1.0)) * dq)))

# ------------------------------------------------------------------ moments
## The player's melee/ranged hit landed: weight-dependent hit-stop and camera kick.
static func on_player_hit(att, tgt, dealt: float, info: Dictionary) -> void:
	var wf := weapon_feel(String(info.get("cat", "unarmed")))
	var big: bool = info.get("crit", false) or tgt.is_dead or dealt > tgt.max_hp * 0.2
	var fin: bool = info.get("finisher", false)
	var stop: float = wf.stop * (1.8 if fin else 1.0) * (1.35 if big else 1.0)
	if info.get("melee", false) and not info.get("proc", false):
		hitstop(stop)
	var dir: Vector3 = tgt.global_position - att.global_position
	dir.y = 0
	kick(dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD, wf.kick * (1.6 if fin or big else 1.0))
	if fin or (tgt.is_dead and big):
		shake(0.12 + wf.weight * 0.22)
	if fin and wf.weight >= 0.9:
		flash(Color(1.0, 0.92, 0.75), 0.12)

## Successful parry: brief slow-motion, punch-in, bright spark, counter window.
static func parry_moment(def, src) -> void:
	slowmo(0.3, 0.22)
	punch(0.12, 0.3)
	flash(Color(1.0, 0.95, 0.7), 0.18)
	shake(0.15)
	Audio.play_sfx("parry_ring", def.global_position, 2.0)
	def.counter_t = 1.4
	def.counter_target = src if (src != null and is_instance_valid(src)) else null

## Ultimate spell: charge focus, release slow-mo + flash + shake.
static func ultimate_release(pos: Vector3, c: Color) -> void:
	Audio.play_sfx("ultimate_boom", pos, 1.0)
	slowmo(0.35, 0.18)
	punch(-0.12, 0.45)
	flash(c.lightened(0.3), 0.22)
	shake(0.45)
