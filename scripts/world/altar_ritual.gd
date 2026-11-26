class_name AltarRitual
extends Node3D
## The cleansing ritual played out in the world:
##  1 runes ignite on the altar  2 motes spiral around the hero
##  3 the cursed item rises and glows  4 a seal forms in the air
##  5 the curse's energy tears away  6 flash  7 result applied.
## Resources are charged only when it completes. Getting hit, an enemy
## closing in, walking away or dying interrupts it with nothing spent.
## Repeat rituals can be skipped; short version when cinematics are off.

signal finished(ok: bool)

var world
var altar: Node3D
var item_uid := 0
var ritual := {}
var station := "altar"
var stage_reached := 0
var _t := 0.0
var _dur := 3.8
var _hp0 := 0.0
var _over := false
var _col := Color(0.55, 1.0, 0.85)
var _curse_col := Color(0.75, 0.15, 0.35)
var _runes: Node3D
var _motes: CPUParticles3D
var _item_node: Node3D
var _seal: Node3D
var _stream: CPUParticles3D
var _light: OmniLight3D
var _skip_layer: CanvasLayer

static func begin(w, altar_node: Node3D, item: Dictionary, r: Dictionary, st: String = "altar") -> AltarRitual:
	var n := AltarRitual.new()
	n.world = w
	n.altar = altar_node
	n.item_uid = int(item.uid)
	n.ritual = r
	n.station = st
	w.fx_root.add_child(n)
	n.global_position = altar_node.global_position
	return n

func _ready() -> void:
	var pl = world.player
	_hp0 = pl.hp
	var item: Dictionary = Curses.find_item(pl.data, item_uid)
	var rar: int = item.get("rarity", 0)
	var seen: bool = Profile.hints_shown.get("ritual_seen", false)
	_dur = 3.8 if Settings.cinematics > 0 else 1.8
	if rar >= 4 and ritual.get("effect", "") == "cleanse" and Settings.cinematics > 0:
		_dur = 4.6
	if ritual.get("effect", "") == "reveal":
		_dur = minf(_dur, 2.2)
	if station == "tech" or Profile.current_era >= 3:
		_col = Color(0.4, 0.85, 1.0)
	_curse_col = ItemDB.rarity_color(item).lerp(Color(0.6, 0.05, 0.25), 0.6)
	world.active_ritual = self
	world.last_ritual_stages = 0
	if world.cam and Settings.cinematics > 0:
		world.cam.cine_focus = altar.global_position + Vector3(0, 1.2, 0)
	if seen:
		_make_skip_button()
	Profile.hints_shown["ritual_seen"] = true
	_stage(1)

func _make_skip_button() -> void:
	_skip_layer = CanvasLayer.new()
	_skip_layer.layer = 15
	add_child(_skip_layer)
	var b := Button.new()
	b.text = "Пропустить ▸"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(190, 56)
	b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	b.offset_left = -95
	b.offset_right = 95
	b.offset_top = -150
	b.offset_bottom = -94
	b.pressed.connect(func(): _t = maxf(_t, _dur * 0.86))
	_skip_layer.add_child(b)

func _process(delta: float) -> void:
	if _over:
		return
	var why := _interrupt_reason()
	if why != "":
		_end(false, why)
		return
	_t += delta
	var k := _t / _dur
	if k >= 0.15 and stage_reached < 2:
		_stage(2)
	if k >= 0.3 and stage_reached < 3:
		_stage(3)
	if k >= 0.48 and stage_reached < 4:
		_stage(4)
	if k >= 0.65 and stage_reached < 5:
		_stage(5)
	if k >= 0.88 and stage_reached < 6:
		_stage(6)
	# animate
	if _runes:
		_runes.rotation.y += delta * (0.6 + k * 2.5)
	if _seal:
		_seal.rotation.z += delta * 1.6
		_seal.global_position = _item_pos() + Vector3(0, 1.1, 0)
	if _item_node:
		_item_node.global_position = _item_pos() + Vector3(0, sin(_t * 3.0) * 0.08, 0)
		_item_node.rotation.y += delta * 2.0
		var fl := 1.0 + 0.4 * sin(_t * (8.0 + k * 20.0))
		_item_node.scale = Vector3.ONE * (0.9 + 0.1 * fl)
	if _motes:
		_motes.global_position = world.player.global_position
	if _light:
		_light.light_energy = 1.0 + k * 3.0
	if k >= 1.0:
		_end(true, "")

func _item_pos() -> Vector3:
	var pl = world.player
	return pl.global_position.lerp(altar.global_position, 0.5) + Vector3(0, 2.0, 0)

func _interrupt_reason() -> String:
	var pl = world.player
	if pl == null or not is_instance_valid(pl) or pl.is_dead:
		return "герой пал"
	if not is_instance_valid(altar):
		return "алтарь исчез"
	if Vector2(pl.global_position.x - altar.global_position.x, pl.global_position.z - altar.global_position.z).length() > 6.5:
		return "вы отошли от алтаря"
	if pl.hp < _hp0 - maxf(1.0, pl.max_hp * 0.01):
		return "вас ранили"
	for a in Game.actors_near(pl.global_position, 8.0):
		if a != pl and not a.is_dead and Game.is_enemy(pl, a) and a.aggro.has("player"):
			return "рядом враг"
	if Curses.find_item(pl.data, item_uid).is_empty():
		return "предмет пропал"
	return ""

func _stage(n: int) -> void:
	stage_reached = n
	world.last_ritual_stages = n
	var top := altar.global_position + Vector3(0, 1.05, 0)
	match n:
		1:   # runes ignite on the altar surface
			_runes = Node3D.new()
			add_child(_runes)
			_runes.global_position = top
			MeshLib.part(_runes, MeshLib.torus(0.75, 0.82), MeshLib.glow(_col, 2.8), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			MeshLib.part(_runes, MeshLib.torus(0.42, 0.46), MeshLib.glow(_col, 2.2), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			for i in 8:
				var a := TAU * i / 8.0
				MeshLib.part(_runes, MeshLib.box(Vector3(0.1, 0.02, 0.22)), MeshLib.glow(_col.lightened(0.2), 3.2), Vector3(cos(a) * 0.62, 0.02, sin(a) * 0.62), Vector3(0, rad_to_deg(-a), 0), Vector3.ONE, false)
			_light = OmniLight3D.new()
			_light.light_color = _col
			_light.omni_range = 7.0
			_light.shadow_enabled = false
			_runes.add_child(_light)
			_light.position.y = 0.8
			Audio.play_sfx("dark_cast", top)
			VFX.ring(altar.global_position, 2.5, _col, 0.6)
		2:   # motes spiral around the hero
			_motes = CPUParticles3D.new()
			_motes.amount = int(28 * maxf(0.4, Settings.profile().get("particles", 1.0)))
			_motes.lifetime = 1.6
			_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			_motes.emission_ring_axis = Vector3.UP
			_motes.emission_ring_radius = 1.3
			_motes.emission_ring_inner_radius = 1.0
			_motes.emission_ring_height = 0.2
			_motes.direction = Vector3.UP
			_motes.spread = 15.0
			_motes.gravity = Vector3(0, 0.6, 0)
			_motes.initial_velocity_min = 0.6
			_motes.initial_velocity_max = 1.4
			_motes.orbit_velocity_min = 0.3
			_motes.orbit_velocity_max = 0.6
			_motes.mesh = MeshLib.box(Vector3(0.06, 0.06, 0.06))
			_motes.material_override = MeshLib.glow(_col, 3.0)
			_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_motes)
			_motes.global_position = world.player.global_position
		3:   # the cursed item rises and glows
			var item: Dictionary = Curses.find_item(world.player.data, item_uid)
			var rc: Color = ItemDB.rarity_color(item)
			_item_node = Node3D.new()
			add_child(_item_node)
			var slot: String = ItemDB.base(item.get("base", "")).get("slot", "main")
			if slot == "main" or slot == "off":
				MeshLib.part(_item_node, MeshLib.box(Vector3(0.09, 1.1, 0.03)), MeshLib.glow(rc.lightened(0.2), 2.4), Vector3(0, 0.15, 0))
				MeshLib.part(_item_node, MeshLib.box(Vector3(0.36, 0.06, 0.08)), MeshLib.glow(rc, 1.8), Vector3(0, -0.42, 0))
				MeshLib.part(_item_node, MeshLib.box(Vector3(0.06, 0.26, 0.06)), MeshLib.mat(Color(0.25, 0.18, 0.12)), Vector3(0, -0.6, 0))
			else:
				MeshLib.part(_item_node, MeshLib.box(Vector3(0.6, 0.7, 0.3)), MeshLib.glow(rc, 1.8), Vector3.ZERO)
				MeshLib.part(_item_node, MeshLib.box(Vector3(0.75, 0.18, 0.34)), MeshLib.glow(rc.lightened(0.2), 2.2), Vector3(0, 0.3, 0))
			_item_node.global_position = _item_pos()
			VFX.burst(_item_pos(), rc, 14, 0.3)
		4:   # a seal forms in the air
			_seal = Node3D.new()
			add_child(_seal)
			MeshLib.part(_seal, MeshLib.torus(0.9, 1.0), MeshLib.glow(_col, 3.0), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
			MeshLib.part(_seal, MeshLib.torus(0.55, 0.6), MeshLib.glow(_col.lightened(0.25), 3.0), Vector3.ZERO, Vector3(90, 0, 0), Vector3.ONE, false)
			for i in 6:
				var a := TAU * i / 6.0
				MeshLib.part(_seal, MeshLib.box(Vector3(0.12, 0.3, 0.03)), MeshLib.glow(_col, 3.4), Vector3(cos(a) * 0.75, sin(a) * 0.75, 0), Vector3(0, 0, rad_to_deg(a)), Vector3.ONE, false)
			_seal.global_position = _item_pos() + Vector3(0, 1.1, 0)
			_seal.scale = Vector3.ONE * 0.1
			var tw := _seal.create_tween()
			tw.tween_property(_seal, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			Audio.play_sfx("portal_open", top, -6.0)
		5:   # the curse's energy tears away into the seal
			_stream = CPUParticles3D.new()
			_stream.amount = int(36 * maxf(0.4, Settings.profile().get("particles", 1.0)))
			_stream.lifetime = 0.8
			_stream.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			_stream.emission_sphere_radius = 0.35
			_stream.direction = Vector3.UP
			_stream.spread = 12.0
			_stream.gravity = Vector3.ZERO
			_stream.initial_velocity_min = 1.4
			_stream.initial_velocity_max = 2.2
			_stream.scale_amount_min = 0.6
			_stream.scale_amount_max = 1.4
			_stream.mesh = MeshLib.box(Vector3(0.08, 0.08, 0.08))
			_stream.material_override = MeshLib.glow(_curse_col, 2.6)
			_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_stream)
			_stream.global_position = _item_pos()
			Audio.play_sfx("curse_bind", top, -4.0)
			if world.cam:
				world.cam.shake(0.12)
		6:   # flash
			VFX.flash(_item_pos(), _col.lightened(0.3), 0.35, 9.0)
			VFX.ring(altar.global_position, 5.0, _col, 0.7)
			VFX.burst(_item_pos(), Color(1, 1, 1), 24, 0.4)
			if world.cam:
				world.cam.shake(0.3)
			Audio.play_sfx("heal", top)
			if _stream:
				_stream.emitting = false

func _end(ok: bool, why: String) -> void:
	_over = true
	if world.cam:
		world.cam.cine_focus = null
	if world.active_ritual == self:
		world.active_ritual = null
	var pl = world.player
	var item: Dictionary = Curses.find_item(pl.data, item_uid) if pl and is_instance_valid(pl) else {}
	if ok and not item.is_empty():
		if not Curses.pay(pl, ritual.get("costs", {})):
			ok = false
			why = "не хватило ресурсов"
	if not ok:
		Events.notify.emit("Ритуал прерван: %s. Ресурсы не потрачены." % why, Color(1.0, 0.6, 0.4))
		Audio.play_sfx("error")
	else:
		var was_bound: bool = Curses.is_bound(item)
		var summary := Curses.apply(item, ritual.get("effect", ""), ritual.get("name", ""))
		match ritual.get("effect", ""):
			"reveal":
				Events.banner.emit("Проклятие распознано", summary, Color(0.85, 0.7, 1.0))
			"unbind":
				Events.banner.emit("Связь разорвана", ItemDB.display_name(item) + " — теперь его можно снять", Color(0.6, 1.0, 0.9))
				Chronicle.record("curse_broken", [pl], {"pos_v3": pl.global_position, "extra": {"item": ItemDB.display_name(item)}})
				Profile.unlock("curse_broken")
			"cleanse":
				Events.banner.emit("Проклятие снято", ItemDB.display_name(item) + (" — снятие свободно" if was_bound else ""), Color(0.6, 1.0, 0.9))
				Chronicle.record("curse_broken", [pl], {"pos_v3": pl.global_position, "extra": {"item": ItemDB.display_name(item)}})
				Profile.unlock("curse_broken")
		if ritual.get("id", "") == "night_ritual":
			var ed: Dictionary = DBEras.era(Profile.current_era)
			for i in 3:
				var nid: String = ed.night_enemies[randi() % ed.night_enemies.size()]
				world.spawner.spawn_enemy(nid, altar.global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)))
			Events.notify.emit("Ритуал пробудил стражей тьмы!", Color(0.7, 1.0, 0.8))
		pl.refresh_gear()
		SaveSys.save_game()
	finished.emit(ok)
	# fade out the visuals
	for n in [_runes, _item_node, _seal]:
		if n and is_instance_valid(n):
			var tw: Tween = n.create_tween()
			tw.tween_property(n, "scale", Vector3.ONE * 0.05, 0.35)
	if _motes:
		_motes.emitting = false
	if _skip_layer:
		_skip_layer.queue_free()
	get_tree().create_timer(0.6, false).timeout.connect(queue_free)
