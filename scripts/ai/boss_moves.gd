class_name BossMoves
## «Beasts of the Ages» boss attack library (used by BossBrain next to its
## classic moves). Every move is announced (telegraph / animation) before it
## hurts, has a cool-down from the boss data, and anything it leaves behind
## (rubble, zones, summons, statuses) is time-limited and capped.
##
## rock_throw, ceiling, armor_up, web, leap, poison_zone, combo,
## parry_stance, bone_wall, roots, decoys, breath, tail, dive, platforms,
## cataclysm_quake, regen, haste, ethereal, burrow, chain, pull,
## echo_strike, ages_wrath.

const MAX_RUBBLE := 10

static func _tpos(br) -> Vector3:
	var b = br.b
	return br.target.global_position if br.target != null and is_instance_valid(br.target) else b.global_position + b.facing * 5.0

static func run(br, typ: String, spec: Dictionary, dir: Vector3) -> bool:
	var b = br.b
	var col: Color = Combat.element_color(str(spec.get("dtype", b.natural_dtype)))
	var tp := _tpos(br)
	match typ:
		"rock_throw":
			var n: int = int(spec.get("count", 2))
			b.start_action("skill", 1.0, 0.55, {"anim": "overhead"})
			br._cast(0.9)
			for i in n:
				var aim: Vector3 = tp + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)) * (0.0 if i == 0 else 1.0)
				br._later(0.5 + 0.25 * i, func():
					var from: Vector3 = b.chest() + Vector3(0, 1.5 * b._scale(), 0)
					var g := MagicFX.ground_point(aim)
					VFX.telegraph(g, 2.2, 0.55, Color(0.9, 0.6, 0.3))
					var vel: Vector3 = (g - from) / 0.6
					vel.y += 0.5 * 18.0 * 0.6
					var info: Dictionary = br._dmg(spec)
					info.knock = 5.0
					var p := Projectile.spawn(b, from, vel, info, "magic", {"range": 40.0, "splash": 2.2, "color": Color(0.5, 0.42, 0.32)})
					if p:
						p.grav = 18.0
						var rock := MeshInstance3D.new()
						rock.mesh = MeshLib.box(Vector3(0.7, 0.6, 0.65))
						rock.material_override = MeshLib.mat(Color(0.45, 0.4, 0.34))
						p.add_child(rock))
			Audio.play_sfx("ground_crack", b.global_position, -2.0)
		"ceiling":
			# the ceiling (or the sky) comes down: telegraphed impacts, some rubble stays as cover
			var n2: int = int(spec.get("count", 6))
			b.start_action("skill", 1.0, 0.7, {"anim": "slam" if not spec.get("sky", false) else "roar"})
			br._cast(0.8)
			VFX.shake(0.4)
			Audio.play_sfx("ground_crack", b.global_position)
			for i in n2:
				var p2: Vector3 = (tp if i == 0 else b.global_position + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)))
				p2 = MagicFX.ground_point(p2)
				var d2 := 0.9 + 0.12 * i
				VFX.telegraph(p2, 2.0, d2, Color(1.0, 0.55, 0.2))
				br._later(d2, func():
					VFX.ground_impact(p2, 2.0)
					VFX.burst(p2 + Vector3(0, 0.5, 0), Color(0.5, 0.45, 0.4), 14, 0.35)
					Combat.aoe(b, p2, 2.0, br._dmg(spec), false)
					if i % 2 == 0 and StoneStructure.count_live() < MAX_RUBBLE:
						StoneStructure.spawn("slab", p2, Vector3.FORWARD, {"life": 18.0, "solid": true, "hp": 140.0, "height": 1.1}))
		"armor_up":
			b.start_action("skill", 0.9, 0.8, {"anim": "roar"})
			br._cast(0.8)
			b.apply_status("stone_armor", float(spec.get("dur", 6.0)), {"mods": {"taken_pct": -0.5}})
			VFX.text(b.chest() + Vector3(0, 1.5, 0), "Броня!", Color(0.8, 0.75, 0.6))
			VFX.burst(b.chest(), Color(0.6, 0.55, 0.45), 16, 0.4)
		"web":
			var r: float = float(spec.get("radius", 4.0))
			b.start_action("skill", 0.8, 0.6, {"anim": "attack"})
			br._cast(0.7)
			VFX.telegraph(tp, r, 0.6, Color(0.9, 0.9, 0.9))
			br._later(0.6, func():
				Zone.create("mud", b, MagicFX.ground_point(tp), r, 6.0, {"amount": 0.0, "status": {"slow": 0.3}}, {"no_res": true})
				for a in Game.actors_near(tp, r):
					if Game.can_damage(b, a):
						a.apply_status("root", 1.2))
		"leap":
			b.start_action("skill", 1.2, 0.8, {"anim": "attack"})
			br._cast(1.1)
			var dest := MagicFX.ground_point(tp)
			VFX.telegraph(dest, 3.5, 0.9, Color(1.0, 0.3, 0.2))
			br._later(0.3, func():
				var tw: Tween = b.create_tween()
				tw.tween_property(b, "global_position", dest + Vector3(0, 0.1, 0), 0.6).set_trans(Tween.TRANS_QUAD))
			br._later(0.95, func():
				VFX.ground_impact(dest, 3.5)
				VFX.shake(0.35)
				Combat.aoe(b, dest, 3.5, br._dmg(spec), false))
		"poison_zone":
			var n3: int = int(spec.get("count", 3))
			b.start_action("skill", 0.8, 0.6, {"anim": "cast"})
			br._cast(0.7)
			for i in n3:
				var pz := MagicFX.ground_point(tp + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)) * (0.0 if i == 0 else 1.0))
				var info3: Dictionary = br._dmg(spec)
				info3.dtype = str(spec.get("dtype", "poison"))
				info3.status = {"decay": 3.0} if info3.dtype == "poison" else ({"burn": 4.0} if info3.dtype == "fire" else {})
				Zone.create("fire" if info3.dtype == "fire" else "dark", b, pz, 2.6, 7.0, info3, {"no_res": true})
		"combo":
			var hits: int = int(spec.get("hits", 3))
			b.start_action("skill", 0.4 + 0.35 * hits, 0.3, {"anim": "slash", "heavy": true})
			br._cast(0.35 * hits + 0.3)
			for i in hits:
				br._later(0.3 + 0.35 * i, func():
					if b.rig:
						b.rig.trigger(["slash", "slash2", "overhead", "thrust"][i % 4])
					var info4: Dictionary = br._dmg(spec)
					info4.melee = true
					Combat.melee(b, b.natural_range + 1.0, 130.0, info4))
		"parry_stance":
			b.apply_status("parry_stance", float(spec.get("dur", 3.0)))
			b.start_action("skill", 0.5, 0.5, {"anim": "block"})
			VFX.text(b.chest() + Vector3(0, 1.4, 0), "Стойка!", Color(0.8, 0.9, 1.0))
		"bone_wall":
			var side: Vector3 = dir.cross(Vector3.UP).normalized()
			var c: Vector3 = b.global_position + dir * 3.0
			b.start_action("skill", 0.8, 0.6, {"anim": "cast"})
			br._cast(0.7)
			for i in 4:
				var wp := MagicFX.ground_point(c + side * (i - 1.5) * 1.6)
				StoneStructure.spawn("stone_wall" if spec.get("stone", false) else "ice_wall", wp, dir, {"life": 9.0, "solid": true, "width": 1.6, "hp": 120.0})
		"roots":
			var n5: int = int(spec.get("count", 4))
			b.start_action("skill", 0.9, 0.6, {"anim": "slam"})
			br._cast(0.8)
			for i in n5:
				var rp := MagicFX.ground_point(tp + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)) * (0.0 if i == 0 else 1.0))
				VFX.telegraph(rp, 1.6, 0.7, Color(0.5, 0.8, 0.3))
				br._later(0.7 + 0.1 * i, func():
					StoneStructure.spawn("stone_spike", rp, Vector3.FORWARD, {"life": 3.0, "solid": false, "scale": 1.2})
					var info5: Dictionary = br._dmg(spec)
					info5.status = {"root": 1.5}
					Combat.aoe(b, rp, 1.6, info5, false))
		"decoys":
			var n6: int = int(spec.get("count", 2))
			b.start_action("skill", 0.7, 0.6, {"anim": "cast"})
			br._cast(0.6)
			var alive := 0
			for a in Game.actors_near(b.global_position, 40.0):
				if a.def_id == "decoy_image" and not a.is_dead:
					alive += 1
			for i in mini(n6, 3 - alive):
				var an := TAU * i / maxf(1.0, n6)
				var arr: Array = Spells.summon(b, "decoy_image", 1, b.global_position + Vector3(cos(an), 0, sin(an)) * 4.0, 10.0)
				for d in arr:
					d.team = "boss"
					d.display_name = b.display_name
					d.max_hp = 1.0
					d.hp = 1.0
			MagicFX.blink_out(b, "dark")
			b.global_position = Spells._safe_dest(b, b.global_position + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)))
		"breath":
			var d3: Vector3 = (tp - b.global_position)
			d3.y = 0
			d3 = d3.normalized()
			b.face_dir(d3)
			b.start_action("skill", 2.0, 0.3, {"anim": "roar"})
			br._cast(1.9)
			VFX.telegraph(b.global_position, 9.0, 0.6, Color(1.0, 0.35, 0.1), "cone", d3, 60.0)
			for k in 5:
				br._later(0.6 + 0.25 * k, func():
					var o: Vector3 = b.chest() + d3 * 1.5 * b._scale()
					if VFX.mgr() != null:
						VFX.mgr().emit(o, {"n": 20, "life": 0.5, "mat": "add", "ramp": "fire", "size": 1.0, "v0": 10.0, "v1": 16.0, "dir": d3, "spread": 28.0, "grav": Vector3.ZERO, "damp": 1.5})
					for a in Game.actors_near(b.global_position, 9.5):
						if a == b or a.is_dead or not Game.can_damage(b, a):
							continue
						var to: Vector3 = a.global_position - b.global_position
						to.y = 0
						if to.length() < 9.5 and d3.angle_to(to.normalized()) < deg_to_rad(32.0):
							var info6: Dictionary = br._dmg(spec)
							info6.dtype = str(spec.get("dtype", "fire"))
							info6.status = {"burn": 5.0}
							Combat.deal(b, a, info6))
		"tail":
			b.start_action("skill", 0.9, 0.6, {"anim": "spin"})
			br._cast(0.8)
			VFX.telegraph(b.global_position, 5.5, 0.55, Color(1.0, 0.3, 0.2), "cone", -b.facing, 200.0)
			br._later(0.55, func():
				var info7: Dictionary = br._dmg(spec)
				info7.knock = 9.0
				for a in Game.actors_near(b.global_position, 6.0):
					if a == b or a.is_dead or not Game.can_damage(b, a):
						continue
					var to2: Vector3 = a.global_position - b.global_position
					to2.y = 0
					if (-b.facing).angle_to(to2.normalized()) < deg_to_rad(100.0):
						Combat.deal(b, a, info7.duplicate()))
		"dive":
			b.start_action("skill", 2.0, 0.85, {"anim": "roar"})
			br._cast(1.9)
			var up: Vector3 = b.global_position + Vector3(0, 10.0, 0)
			var land := MagicFX.ground_point(tp)
			var tw2: Tween = b.create_tween()
			tw2.tween_property(b, "global_position", up, 0.6).set_ease(Tween.EASE_OUT)
			b.apply_status("invuln", 1.4)
			br._later(0.7, func(): VFX.telegraph(land, 4.0, 0.9, Color(1.0, 0.3, 0.15)))
			br._later(1.2, func():
				var tw3: Tween = b.create_tween()
				tw3.tween_property(b, "global_position", land + Vector3(0, 0.1, 0), 0.35).set_ease(Tween.EASE_IN))
			br._later(1.6, func():
				VFX.ground_impact(land, 4.0)
				VFX.shake(0.5)
				Combat.aoe(b, land, 4.0, br._dmg(spec), false))
		"platforms", "cataclysm_quake":
			var big := typ == "cataclysm_quake"
			b.start_action("skill", 1.6 if big else 1.0, 0.85, {"anim": "slam"})
			br._cast(1.5 if big else 0.9)
			var n7: int = int(spec.get("count", 6 if big else 4))
			for i in n7:
				var an2 := TAU * i / n7 + randf() * 0.4
				var pp := MagicFX.ground_point(b.global_position + Vector3(cos(an2), 0, sin(an2)) * randf_range(5.0, 11.0))
				br._later(0.4 + 0.08 * i, func():
					if StoneStructure.count_live() < MAX_RUBBLE + 4:
						StoneStructure.spawn("slab", pp, Vector3.FORWARD, {"life": 12.0, "solid": true, "hp": 200.0}))
			if big:
				MagicFX.ground_rune(b.global_position, "stone", Color(0.7, 0.6, 0.45), 12.0, 4.0, 0.6, 1.3)
				for w in 3:
					br._later(1.4 + 0.8 * w, func():
						VFX.shock(b.global_position, 13.0, Color(0.75, 0.62, 0.45), 0.5)
						VFX.shake(0.5)
						Combat.aoe(b, b.global_position, 13.0, br._dmg(spec), false))
		"regen":
			b.start_action("skill", 1.0, 0.9, {"anim": "cast"})
			br._cast(0.9)
			b.apply_status("boss_regen", float(spec.get("dur", 5.0)), {"hot": b.max_hp * 0.012})
			VFX.text(b.chest() + Vector3(0, 1.5, 0), "Восстановление — прервите!", Color(0.6, 1.0, 0.6))
		"haste":
			b.apply_status("haste", float(spec.get("dur", 5.0)))
			b.apply_status("overclock", float(spec.get("dur", 5.0)), {"mods": {"aspd": 0.4}})
			VFX.burst(b.chest(), Color(1.0, 0.8, 0.4), 12, 0.3)
		"ethereal":
			b.apply_status("ethereal", float(spec.get("dur", 3.0)), {"mods": {"taken_pct": -0.6}})
			VFX.text(b.chest() + Vector3(0, 1.4, 0), "Бесплотен — нужен свет!", Color(0.6, 0.9, 1.0))
		"burrow":
			b.start_action("skill", 2.2, 0.95, {"anim": "slam"})
			br._cast(2.1)
			b.apply_status("invuln", 1.8)
			if b.rig:
				b.rig.visible = false
			VFX.burst(b.global_position, Color(0.5, 0.42, 0.32), 20, 0.4)
			br._later(1.2, func():
				var land2 := MagicFX.ground_point(_tpos(br))
				VFX.telegraph(land2, 3.5, 0.7, Color(0.9, 0.5, 0.25))
				br._later(0.7, func():
					b.global_position = land2
					if b.rig:
						b.rig.visible = true
					VFX.ground_impact(land2, 3.5)
					Combat.aoe(b, land2, 3.5, br._dmg(spec), false)))
		"chain":
			b.start_action("skill", 0.7, 0.6, {"anim": "cast"})
			br._cast(0.6)
			br._later(0.4, func():
				if br.target != null and is_instance_valid(br.target):
					Spells.chain_lightning(b, br.target, b.base_dmg * float(spec.get("dmg", 1.0)), 4, true, b.chest()))
		"pull":
			var r2: float = float(spec.get("radius", 8.0))
			b.start_action("skill", 0.8, 0.6, {"anim": "cast"})
			br._cast(0.7)
			VFX.shock(b.global_position, r2, Color(0.7, 0.5, 1.0), 0.5)
			for a in Game.actors_near(b.global_position, r2):
				if a != b and not a.is_dead and Game.can_damage(b, a) and a.kind != "boss":
					var to3: Vector3 = b.global_position - a.global_position
					to3.y = 0
					a.knockback = to3.normalized() * 9.0
		"echo_strike":
			# repeats a heavy blow a moment later at the same place
			var ep := MagicFX.ground_point(tp)
			for k in 2:
				VFX.telegraph(ep, 3.0, 0.7 + 0.9 * k, Color(0.4, 1.0, 0.85))
				br._later(0.7 + 0.9 * k, func():
					MagicFX.time_snap(ep, 3.0)
					Combat.aoe(b, ep, 3.0, br._dmg(spec), false))
			b.start_action("skill", 0.8, 0.6, {"anim": "slam"})
			br._cast(0.7)
		"ages_wrath":
			# magic of all eras: fire, frost, lightning, earth in sequence — each announced
			var kinds := ["fire", "ice", "lightning", "earth"]
			b.start_action("skill", 2.4, 0.3, {"anim": "roar"})
			br._cast(2.3)
			for k in 4:
				var ap := MagicFX.ground_point(_tpos(br) + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
				var kd: String = kinds[k]
				br._later(0.4 + 0.5 * k, func(): VFX.telegraph(ap, 3.0, 0.6, Combat.element_color(kd)))
				br._later(1.0 + 0.5 * k, func():
					MagicFX.impact(ap + Vector3(0, 0.5, 0), MagicFX.school(kd) if MagicFX.school(kd) != "" else "earth", 3.0)
					var info8: Dictionary = br._dmg(spec)
					info8.dtype = kd
					Combat.aoe(b, ap, 3.0, info8, false))
		_:
			return false
	return true
