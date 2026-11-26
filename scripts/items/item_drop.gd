class_name ItemDrop
extends Node3D
## An item lying in the world. Rarity effects: epic purple particles,
## legendary golden beam + flash + sound, mythic crimson distortion + light +
## musical sting. Interactable; consumables/gold can be auto-picked.

var item := {}
var gold := 0
var interact_radius := 2.2
var by_player_t := 0.0
var life := 180.0          # seconds before an unattended drop vanishes
var _t := 0.0
var _vis: Node3D
var _label: Label3D
var _beam: MeshInstance3D
var _beam_base := Vector3.ONE

func setup(it: Dictionary, g: int = 0, by_player: bool = false) -> void:
	item = it
	gold = g
	by_player_t = 4.0 if by_player else 0.0
	var rar: int = it.get("rarity", 0) if g == 0 else 0
	life = [180.0, 240.0, 420.0, 420.0, 900.0, 900.0][clampi(rar, 0, 5)]
	if ItemDB.base(it.get("base", "")).get("relic", false) or it.get("base", "") == "chrono_shard":
		life = 1800.0

func _ready() -> void:
	_vis = Node3D.new()
	add_child(_vis)
	var rar: int = item.get("rarity", 0) if gold == 0 else 1
	var col: Color = ItemDB.RARITY_COLORS[rar] if gold == 0 else Color(1.0, 0.85, 0.3)
	if gold > 0:
		for i in mini(5, 1 + gold / 20):
			MeshLib.part(_vis, MeshLib.cyl(0.09, 0.09, 0.03, 10), MeshLib.mat(Color(1.0, 0.8, 0.25), 0.9, 0.3), Vector3(randf_range(-0.15, 0.15), 0.05 + i * 0.035, randf_range(-0.15, 0.15)))
	else:
		var b := ItemDB.base(item.base)
		var slot: String = b.get("slot", "")
		if slot in ["main", "off"]:
			var w := WeaponModels.build(b.get("model", "sword"), item)
			w.rotation_degrees = Vector3(90, 0, 25)
			w.position.y = 0.25
			_vis.add_child(w)
		elif slot == "use":
			MeshLib.part(_vis, MeshLib.cyl(0.08, 0.1, 0.22, 8), MeshLib.mat(_potion_color(item.base), 0.0, 0.3, 0.6), Vector3(0, 0.15, 0))
			MeshLib.part(_vis, MeshLib.cyl(0.035, 0.035, 0.08, 6), MeshLib.mat(Color(0.5, 0.35, 0.2)), Vector3(0, 0.3, 0))
		elif slot == "mat":
			MeshLib.part(_vis, MeshLib.prism(Vector3(0.25, 0.3, 0.25)), MeshLib.mat(col, 0.3, 0.4, 1.0 if b.get("relic", false) or item.base == "chrono_shard" else 0.0), Vector3(0, 0.2, 0))
		else:
			MeshLib.part(_vis, MeshLib.box(Vector3(0.38, 0.24, 0.3)), MeshLib.mat(Color(0.45, 0.3, 0.18)), Vector3(0, 0.12, 0))
			MeshLib.part(_vis, MeshLib.box(Vector3(0.4, 0.05, 0.32)), MeshLib.mat(col, 0.5, 0.4, 0.6), Vector3(0, 0.25, 0))
	# glow disc under every drop for readability
	var disc := MeshLib.part(self, MeshLib.cyl(0.45, 0.45, 0.02, 12), MeshLib.mat(Color(col.r, col.g, col.b, 0.35), 0.0, 1.0, 1.5, true), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if rar >= 3 and gold == 0:
		# epic: violet motes; legendary: golden beam, sparkle swirl, coin glints;
		# mythic: crimson column, floating runes, distortion ring (MagicFX.loot)
		_beam = MagicFX.loot(self, rar, col)
		if _beam:
			_beam_base = _beam.scale
		if rar >= 5 and VFX.mgr() != null:
			VFX.mgr().attach_light(self, Color(1.0, 0.15, 0.25), 2.0, 5.0, Vector3(0, 1.0, 0))
	_label = Label3D.new()
	_label.text = ("%d %s" % [gold, DBEras.era(Profile.current_era).currency]) if gold > 0 else ItemDB.display_name(item) + ((" ×%d" % item.get("qty", 1)) if item.get("qty", 1) > 1 else "")
	_label.modulate = col
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.005
	_label.outline_size = 10
	_label.position.y = 0.9
	_label.no_depth_test = true
	_label.visible = rar >= 2
	add_child(_label)
	Game.grid.insert_deferred(self, "interact")
	Game.grid.insert_deferred(self, "pickup")

func announce() -> void:
	var rar: int = item.get("rarity", 0)
	if gold > 0:
		return
	if rar == 3:
		Audio.play_sfx("drop_epic", global_position)
	elif rar == 4:
		Audio.play_sfx("drop_legendary", global_position)
		VFX.flash(global_position + Vector3(0, 2, 0), Color(1.0, 0.8, 0.3), 0.4, 6.0)
		VFX.shock(global_position, 3.0, Color(1.0, 0.82, 0.35), 0.6)
		VFX.burst(global_position + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.4), 18, 0.3)
		Audio.play_sting("legendary_sting")
	elif rar == 5:
		Audio.play_sfx("drop_mythic", global_position)
		VFX.flash(global_position + Vector3(0, 2, 0), Color(1.0, 0.1, 0.2), 0.6, 8.0)
		VFX.ring(global_position, 6.0, Color(1.0, 0.1, 0.2), 1.2)
		var mg = VFX.mgr()
		if mg:
			mg.distort(global_position + Vector3(0, 1.0, 0), 5.0, 0.8, Color(1.0, 0.1, 0.2, 0.25), true)
			MagicFX.ground_rune(global_position, "sigil", Color(1.0, 0.15, 0.25), 2.5, 1.5, 1.5, 1.0)
		Audio.play_sting("mythic_sting")

func _potion_color(b: String) -> Color:
	match b:
		"potion_hp", "potion_big": return Color(0.9, 0.15, 0.2)
		"potion_mana": return Color(0.2, 0.4, 1.0)
		"elixir_mutation": return Color(0.4, 1.0, 0.3)
		"bomb_flask", "grenade": return Color(0.3, 0.3, 0.3)
	if b.begins_with("tome") or b.begins_with("scroll"):
		return Color(0.9, 0.85, 0.65)
	return Color(0.7, 0.6, 0.9)

func _exit_tree() -> void:
	Game.grid.remove(self, "interact")
	Game.grid.remove(self, "pickup")

func interact_label() -> String:
	if gold > 0:
		return "Подобрать золото"
	return "Подобрать: " + ItemDB.display_name(item)

func interact(a) -> void:
	if Game.world and Game.world.get("loot"):
		Game.world.loot.pickup(a, self)

func _process(delta: float) -> void:
	_t += delta
	life -= delta
	by_player_t = maxf(0.0, by_player_t - delta)
	if life <= 0.0:
		queue_free()
		return
	_vis.rotation.y += delta * 1.2
	_vis.position.y = 0.1 + sin(_t * 2.5) * 0.06
	if _beam:
		var pk := 1.0 + sin(_t * 4.0) * 0.15
		_beam.scale = _beam_base * Vector3(pk, 1.0, pk)
	var pl = Game.player
	if pl == null or not is_instance_valid(pl) or pl.is_dead:
		return
	var d: float = pl.global_position.distance_to(global_position)
	if d > 260.0 and life < 1700.0:
		queue_free()
		return
	if _label:
		_label.visible = d < 9.0 or item.get("rarity", 0) >= 2
	if by_player_t <= 0.0 and d < 1.3 and Settings.auto_pickup:
		var b := ItemDB.base(item.get("base", ""))
		if gold > 0 or b.get("slot", "") in ["use", "mat"] or not pl.data.inv.is_full():
			interact(pl)
