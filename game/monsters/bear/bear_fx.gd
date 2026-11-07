class_name BearFx
extends RefCounted
## The bear's look (every player's game): the ring where its paws will land, its roar, the maul's quake. Its brain
## (bear_brain.gd) sends these as fx events; Monsters.fx routes "bear_*" here.

static func fx(en: Enemy, ev: String) -> void:
	var fwd := -en.rig.global_transform.basis.z
	match ev:
		"bear_tele":
			# the danger zone: a ring where the paws will land (scaled by its body: the bear is radius 1)
			Fx.telegraph(en.game.world.fx_root, en.global_position + fwd * 1.6 * en.radius, 1.9 * en.radius, en.atk_dur * Anim.impact_at("bear_maul"), Color(0.6, 1.0, 0.4))
		"bear_roar":
			Bear.sound("bear_roar", en.global_position + Vector3(0, 2.0, 0))
			Fx.burst(en.game.world.fx_root, en.global_position + Vector3(0, 2.4, 0) + fwd * 0.9, Color(0.75, 0.8, 0.75, 0.35), 18, 1.6, 0.35, 0.9, false, 0.4, 35.0, fwd)
			if en.game.hero.global_position.distance_to(en.global_position) < 16.0:
				en.game.add_shake(0.25)
		"bear_maul":
			Bear.sound("bear_maul", en.global_position)
			ElementalFx.ground_slam(en.game, en.game.world.fx_root, en.global_position + fwd * 1.6 * en.radius, 1.3 + en.radius)
			if en.game.hero.global_position.distance_to(en.global_position) < 10.0:
				en.game.add_shake(0.45)
