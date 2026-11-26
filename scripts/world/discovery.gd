class_name Discovery
extends Node
## Discovery of places: walking near a settlement or point of interest
## reveals it on the map ("Открыто: …"), grants a reward by category and
## writes the Chronicle. Rumours and road encounters can reveal places
## remotely (reveal()). Undiscovered places stay hidden on the map/minimap.
## Categories: обычное / опасное / редкое / тайное / эпохальное.

const CATEGORY := {"settlement": "normal", "camp": "dangerous", "lair": "dangerous", "cp": "normal", "shrine": "normal",
	"dungeon": "rare", "altar": "rare", "mirror": "rare", "relic_site": "rare", "witness": "secret", "ruins": "secret",
	"rift": "dangerous", "trial": "epochal", "fortress": "epochal", "monument": "epochal", "tourney": "rare",
	"forge": "normal", "lab": "normal", "workshop": "normal", "terminal": "rare"}
const CAT_NAMES := {"normal": "Место", "dangerous": "Опасное место", "rare": "Редкое место", "secret": "Тайное место", "epochal": "Место эпохи"}
const CAT_COL := {"normal": Color(0.85, 0.9, 0.8), "dangerous": Color(1.0, 0.5, 0.4), "rare": Color(0.55, 0.75, 1.0), "secret": Color(0.8, 0.6, 1.0), "epochal": Color(1.0, 0.85, 0.35)}
const CAT_XP := {"normal": 15, "dangerous": 25, "rare": 40, "secret": 60, "epochal": 80}

var world
var _t := 0.0

func setup(w) -> void:
	world = w
	if not Game.world_state.has("discovered"):
		Game.world_state["discovered"] = {}
	# the hero knows the settlements around the place they start
	if world.gen and world.player:
		var pp: Vector3 = world.player.global_position
		for s in world.gen.settlements:
			if Vector2(pp.x, pp.z).distance_to(s.pos) < 220.0:
				_mark(s.id)

func _disc() -> Dictionary:
	return Game.world_state.get("discovered", {})

func is_discovered(id: String) -> bool:
	return _disc().has(id)

func discovered_ids() -> Array:
	return _disc().keys()

func category(p: Dictionary) -> String:
	if p.has("buildings") or p.get("kind", "") == "settlement":
		return "normal"
	return CATEGORY.get(p.get("type", ""), "normal")

func _mark(id: String) -> void:
	if not Game.world_state.has("discovered"):
		Game.world_state["discovered"] = {}
	Game.world_state.discovered[id] = Game.day()

## Remote reveal (rumours, maps, messengers): appears on the map, no reward.
func reveal(id: String) -> void:
	if is_discovered(id):
		return
	_mark(id)
	var nm := _name_of(id)
	if nm != "":
		Events.notify.emit("Отмечено на карте: " + nm, Color(0.8, 0.85, 1.0))

func _name_of(id: String) -> String:
	if world.gen == null:
		return ""
	for s in world.gen.settlements:
		if s.id == id:
			return s.name
	for p in world.gen.pois:
		if p.id == id:
			return p.get("name", "")
	return ""

func _process(delta: float) -> void:
	if world == null or world.gen == null or world.player == null or not is_instance_valid(world.player) or world.dimension != "":
		return
	_t += delta
	if _t < 0.6:
		return
	_t = 0.0
	var pp: Vector3 = world.player.global_position
	var p2 := Vector2(pp.x, pp.z)
	for s in world.gen.settlements:
		if not is_discovered(s.id) and p2.distance_to(s.pos) < 45.0:
			_discover(s.id, s.name, "normal", Vector3(s.pos.x, pp.y, s.pos.y))
	for p in world.gen.pois:
		if is_discovered(p.id):
			continue
		var r := 30.0 if p.type in ["lair", "fortress", "trial", "camp"] else 20.0
		if p2.distance_to(p.pos) < r:
			var nm: String = p.get("name", "")
			if nm == "":
				nm = {"rift": "Временной разлом", "altar": "Алтарь", "shrine": "Святилище", "dungeon": "Подземелье", "witness": "Приют Свидетеля"}.get(p.type, "Неизвестное место")
			_discover(p.id, nm, category(p), Vector3(p.pos.x, pp.y, p.pos.y))

func _discover(id: String, nm: String, cat: String, pos: Vector3) -> void:
	_mark(id)
	var col: Color = CAT_COL.get(cat, Color.WHITE)
	var xp: int = int(CAT_XP.get(cat, 15) * (1.0 + Profile.current_era * 0.25))
	world.player.gain_xp(xp)
	if cat in ["rare", "secret", "epochal"]:
		Events.banner.emit("Открыто: " + nm, CAT_NAMES.get(cat, "") + " · +%d опыта" % xp, col)
	else:
		Events.notify.emit("Открыто: %s (%s, +%d опыта)" % [nm, CAT_NAMES.get(cat, "").to_lower(), xp], col)
	Audio.play_sfx("mastery_up", null, -10.0)
	Chronicle.record("discovery", [world.player], {"pos_v3": pos, "extra": {"place": nm, "category": cat}})
	Profile.add_stat("discoveries")
