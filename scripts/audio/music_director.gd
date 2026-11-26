class_name MusicDirector
extends Node
## Dynamic music: picks the track from what is happening around the hero.
##  ritual (altar ritual) > boss (engaged boss nearby) > combat (enemies
##  hunting the hero) > rift (pocket dimension) > tension (threat nearby,
##  blood moon) > the era's exploration theme.
## Hysteresis keeps combat music for a while after the last foe and
## limits switches so tracks don't flicker.

var world
var state := ""
var _t := 0.0
var _last_switch := -99.0
var _combat_until := 0.0
var _clock := 0.0

func setup(w) -> void:
	world = w

func _process(delta: float) -> void:
	if world == null or world.mode != "world" or world.player == null or not is_instance_valid(world.player):
		return
	_clock += delta
	_t += delta
	if _t < 0.75:
		return
	_t = 0.0
	var want := _evaluate()
	if want != state and (_clock - _last_switch > 3.0 or want in ["boss", "ritual"]):
		state = want
		_last_switch = _clock
		Audio.play_music(_track(want), 2.0 if want in ["explore", "tension"] else 1.0)

func _track(st: String) -> String:
	match st:
		"ritual": return "ritual"
		"boss": return "boss"
		"combat": return "combat"
		"rift": return "rift"
		"tension": return "tension"
	return DBEras.era(world.era).music

func _evaluate() -> String:
	var pl = world.player
	if pl.is_dead:
		return state if state != "" else "explore"
	if world.get("active_ritual") != null and is_instance_valid(world.active_ritual):
		return "ritual"
	var pp: Vector3 = pl.global_position
	var hunting := 0
	var near := 0
	for a in Game.actors_near(pp, 55.0):
		if a == pl or a.is_dead or not Game.is_enemy(pl, a):
			continue
		var d: float = a.global_position.distance_to(pp)
		if a.kind == "boss" and d < 55.0 and (a.aggro.has("player") or d < 30.0):
			return "boss"
		if d < 24.0 and a.aggro.has("player"):
			hunting += 1
		elif d < 32.0:
			near += 1
	if hunting > 0:
		_combat_until = _clock + 6.0
		return "combat"
	if _clock < _combat_until:
		return "combat"
	if world.dimension != "":
		return "rift"
	var blood: bool = world.director != null and world.director.has_method("blood_moon_active") and world.director.blood_moon_active()
	if near >= 2 or blood:
		return "tension"
	return "explore"
