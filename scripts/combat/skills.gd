class_name Skills
## Active weapon techniques from the mastery trees.

static func use(a: Actor, id: String, aim: Vector3) -> bool:
	var n := DBSkills.find_skill(id)
	if n.is_empty() or a.data == null or not a.data.has_node(id):
		return false
	var st: float = n.get("stamina", 0.0)
	var mn: float = n.get("mana", 0.0)
	if a.stamina < st or a.mana < mn:
		if a.is_player:
			Events.notify.emit("Недостаточно выносливости" if a.stamina < st else "Недостаточно маны", Color(0.9, 0.8, 0.4))
		return false
	a.stamina -= st
	a.mana -= mn
	a.skill_cd[id] = n.get("cd", 5.0)
	if aim.length() < 0.01:
		aim = a.facing
	aim.y = 0
	aim = aim.normalized()
	a.face_dir(aim)
	var tree := a.get_tree()
	var r := a.weapon_range()
	match id:
		"sw_quick":
			_act(a, "slash", 0.4, 0.35, func():
				Combat.melee(a, r, 120.0, Combat.weapon_info(a, 1.0))
				tree.create_timer(0.15, false).timeout.connect(func():
					if is_instance_valid(a) and not a.is_dead:
						a.rig.trigger("slash2")
						Combat.melee(a, r, 120.0, Combat.weapon_info(a, 1.1))))
		"sw_heavy":
			_act(a, "overhead", 0.7, 0.55, func():
				var info := Combat.weapon_info(a, 2.6)
				info.knock = 7.0
				Combat.melee(a, r + 0.4, 100.0, info)
				VFX.ring(a.global_position + a.facing * 1.5, 1.8, Color(1, 0.9, 0.7), 0.25)
				Audio.play_sfx("swing_heavy", a.global_position))
		"sw_whirl", "hv_quake":
			if id == "sw_whirl":
				_act(a, "spin", 0.9, 0.2, func():
					for i in 3:
						tree.create_timer(0.22 * i, false).timeout.connect(func():
							if is_instance_valid(a) and not a.is_dead:
								Combat.melee(a, r + 0.5, 360.0, Combat.weapon_info(a, 0.9))
								VFX.ring(a.global_position, r + 0.5, Color(0.9, 0.9, 1.0), 0.2)
								Audio.play_sfx("swing", a.global_position)))
			else:
				_act(a, "slam", 0.7, 0.5, func():
					for i in 3:
						tree.create_timer(0.2 * i, false).timeout.connect(func():
							if not is_instance_valid(a):
								return
							var p: Vector3 = a.global_position + aim * (3.0 + 3.0 * i)
							VFX.explosion(p, 2.4, Color(0.7, 0.6, 0.45))
							var inf := Combat.weapon_info(a, 1.4)
							inf.status = {"stun": 0.5}
							Combat.aoe(a, p, 2.4, inf)))
		"dg_flurry":
			_act(a, "stab", 0.55, 0.2, func():
				for i in 5:
					tree.create_timer(0.08 * i, false).timeout.connect(func():
						if is_instance_valid(a) and not a.is_dead:
							a.rig.trigger("stab" if i % 2 == 0 else "slash")
							Combat.melee(a, r + 0.2, 70.0, Combat.weapon_info(a, 0.6 + (0.09 * i if a.data.has_node("dg_combo") else 0.0)), 1)))
		"dg_stealth":
			a.apply_status("stealth", 6.0)
			if a.rig:
				a.rig.crouch = true
			VFX.burst(a.chest(), Color(0.3, 0.3, 0.4), 16, 0.4)
			Audio.play_sfx("dark_cast", a.global_position, -6.0)
		"dg_shadowstep":
			var t := Spells._target(a, aim, 11.0, 70.0)
			if t == null:
				a.skill_cd.erase(id)
				a.stamina += st
				return false
			var behind: Vector3 = t.global_position + t.facing * -1.3
			VFX.burst(a.chest(), Color(0.2, 0.1, 0.3), 14, 0.35)
			a.global_position = Spells._safe_dest(a, behind)
			a.reset_physics_interpolation()
			a.face_dir(t.global_position - a.global_position)
			_act(a, "stab", 0.35, 0.3, func():
				Combat.melee(a, r + 0.4, 80.0, Combat.weapon_info(a, 2.0), 1))
		"sp_lunge":
			a.dodge_dir = aim
			a.knockback = aim * 14.0
			_act(a, "thrust", 0.45, 0.4, func():
				var info := Combat.weapon_info(a, 1.8)
				Combat.melee(a, r + 0.5, 50.0, info, 2))
		"sp_sweep":
			_act(a, "slash", 0.55, 0.45, func():
				var info2 := Combat.weapon_info(a, 1.3)
				info2.status = {"stun": 0.8}
				info2.knock = 4.0
				Combat.melee(a, r, 220.0, info2))
		"sp_wall":
			_act(a, "thrust", 0.8, 0.2, func():
				for i in 3:
					tree.create_timer(0.18 * i, false).timeout.connect(func():
						if is_instance_valid(a) and not a.is_dead:
							a.rig.trigger("thrust")
							var inf3 := Combat.weapon_info(a, 1.2)
							inf3.status = {"slow": 0.5}
							Combat.melee(a, r + 0.6, 60.0, inf3, 3)))
		"hv_slam":
			_act(a, "slam", 0.7, 0.55, func():
				var inf4 := Combat.weapon_info(a, 2.0)
				inf4.status = {"stun": 0.6}
				VFX.explosion(a.global_position + aim * 1.2, 4.0, Color(0.75, 0.65, 0.5))
				Combat.aoe(a, a.global_position + aim * 1.2, 4.0, inf4))
		"hv_unstoppable":
			a.apply_status("unstoppable", 8.0)
			VFX.ring(a.global_position, 2.0, Color(1.0, 0.6, 0.2), 0.5)
			Audio.play_sfx("boss_roar", a.global_position, -6.0)
		"bw_aimed":
			_act(a, "shoot", 0.7, 0.75, func():
				var inf5 := Combat.weapon_info(a, 3.0)
				inf5.melee = false
				Projectile.spawn(a, a.chest() + aim * 0.7, aim * 62.0, inf5, "arrow", {"pierce": 2, "range": r * 1.4})
				Audio.play_sfx("bow_release", a.global_position))
		"bw_rapid":
			_act(a, "shoot", 0.5, 0.2, func():
				for i in 3:
					tree.create_timer(0.12 * i, false).timeout.connect(func():
						if is_instance_valid(a) and not a.is_dead:
							var inf6 := Combat.weapon_info(a, 0.9)
							inf6.melee = false
							Projectile.spawn(a, a.chest() + a.facing * 0.7, a.facing.rotated(Vector3.UP, randf_range(-0.04, 0.04)) * 40.0, inf6, "arrow", {"range": r})
							Audio.play_sfx("bow_release", a.global_position, -3.0)))
		"bw_special":
			_act(a, "shoot", 0.6, 0.5, func():
				var school := a.data.best_school()
				if school == "":
					school = "fire"
				for i in 5:
					var inf7 := Combat.weapon_info(a, 1.1)
					inf7.melee = false
					inf7.dtype = DBSkills.SCHOOLS[school].dtype
					inf7.status = Combat.school_status(school, inf7.amount * 0.3)
					Projectile.spawn(a, a.chest() + aim * 0.7, aim.rotated(Vector3.UP, deg_to_rad(-20 + 10 * i)) * 40.0, inf7, "arrow", {"range": r, "color": Combat.element_color(inf7.dtype)})
				Audio.play_sfx("bow_release", a.global_position))
		"fa_burst":
			_act(a, "shoot", 0.3, 0.1, func():
				for i in 5:
					var inf8 := Combat.weapon_info(a, 0.8)
					inf8.melee = false
					Projectile.spawn(a, a.chest() + aim * 0.8, aim.rotated(Vector3.UP, deg_to_rad(-16 + 8 * i)) * 80.0, inf8, "bullet", {"range": r})
				Audio.play_sfx("gun_shotgun", a.global_position))
		"fa_special":
			_act(a, "shoot", 0.4, 0.2, func():
				var inf9 := Combat.weapon_info(a, 2.5)
				inf9.melee = false
				inf9.dtype = "fire"
				Projectile.spawn(a, a.chest() + aim * 0.8, aim * 55.0, inf9, "plasma", {"range": r, "splash": 3.5, "color": Color(1.0, 0.5, 0.2)})
				Audio.play_sfx("explosion", a.global_position, -6.0))
		"st_shield":
			a.shield_hp = 40.0 + 2.0 * a.data.mastery_level("staff") + a.level * 3.0
			a.apply_status("magic_shield", 12.0)
			VFX.ring(a.global_position, 1.5, Color(0.5, 0.7, 1.0), 0.5)
			Audio.play_sfx("heal", a.global_position)
		"st_overload":
			_act(a, "cast", 0.5, 0.5, func():
				var school2 := a.data.best_school()
				for i in 6:
					var info10 := Combat.weapon_info(a, 0.9)
					info10.melee = false
					if school2 != "":
						info10.dtype = DBSkills.SCHOOLS[school2].dtype
						info10.school = school2
					Projectile.spawn(a, a.chest() + aim * 0.8, aim.rotated(Vector3.UP, deg_to_rad(-30 + 12 * i)) * 24.0, info10, "magic", {"range": r, "color": Combat.element_color(info10.dtype)}))
		"ua_kick":
			_act(a, "kick", 0.45, 0.45, func():
				var inf11 := Combat.weapon_info(a, 1.2)
				inf11.knock = 9.0
				Combat.melee(a, 2.0, 80.0, inf11, 1))
		_:
			return false
	return true

static func _act(a: Actor, anim: String, dur: float, impact: float, cb: Callable) -> void:
	a.start_action("skill", dur, impact, {"anim": anim, "cb": cb})
