class_name ChronoBrain
extends BotBrain
## Brain of the chrono double: replays the player's recorded habits —
## attack rhythm, dodge frequency and the skills/spells the player used.

var buffer: Array = []
var p_dodge := 0.1
var fav_skills: Array = []
var _replay_t := 0.0

func _init(npc, recorded: Array) -> void:
	super._init(npc)
	buffer = recorded
	var total := maxf(1.0, buffer.size())
	var dodges := 0
	for e in buffer:
		if e.type == "dodge":
			dodges += 1
		elif e.type == "skill" and e.id != "" and not e.id in fav_skills:
			fav_skills.append(e.id)
	p_dodge = clampf(dodges / total, 0.05, 0.5)
	p = DBActors.ARCHETYPES.aggressive

func tick(delta: float) -> void:
	if Game.player and is_instance_valid(Game.player) and not Game.player.is_dead:
		target = Game.player
		goal = "fight"
	super.tick(delta)
	_replay_t -= delta
	if _replay_t <= 0.0 and target and is_instance_valid(target):
		_replay_t = 0.6
		var d: float = n.global_position.distance_to(target.global_position)
		var dir: Vector3 = (target.global_position - n.global_position).normalized()
		if randf() < p_dodge * 0.6 and d < 6.0:
			n.dodge(dir.cross(Vector3.UP) * (1.0 if randf() < 0.5 else -1.0))
		for id in fav_skills:
			if not n.skill_cd.has(id) and randf() < 0.35:
				n.use_ability(id, dir)
				break

func _think() -> void:
	if Game.player and is_instance_valid(Game.player):
		_set_goal("fight", Game.player)
