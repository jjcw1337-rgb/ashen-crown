class_name FallenFx
extends RefCounted
## The Fallen's look (every player's game): the Reaver's arc, the cleave's danger zone. Monsters.fx routes it here.

static func fx(en: Enemy, ev: String) -> void:
	match ev:
		"reaver_tele":
			Fx.arc_telegraph(en.game.world.fx_root, en.global_position, -en.rig.global_transform.basis.z, 2.6 + en.radius * 0.5, 60.0, en.atk_dur * (Anim.impact_at("reaver_cleave") - 0.15))
