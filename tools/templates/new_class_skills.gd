extends RefCounted
## TEMPLATE for a new class's skills. Copy it to `scripts/<class>_skills.gd`, uncomment and rename the
## class_name, replace "newclass" and the skill ids, then follow the checklist in docs/content/heroes.md ("Making a hero").
##
## ClassSkills (scripts/class_skills.gd) calls these static functions; every class's script has all of them.
## Keep gameplay here and drawing in `<Class>Fx.play`: wherever something should be seen, call
## h.fx(skill_id, event, data) (co-op partners see it too). Tuning (names, mana, cooldowns, levels, aim) lives in
## Data.SKILLS entries with "cls": "newclass".
##
## Example skills below: a melee strike (Q), a ring around him (E), a self buff (F).

# class_name NewclassSkills

static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	# return false (after h.game.ui.message(...)) when a skill can't start, e.g. no target in reach
	return true

static func cast(h: Hero, id: String, _aim: Vector3) -> void:
	match id:
		"nc_strike":
			h._start_attack("side", "nc_strike", 0.7)      # style (Anim), skill id, seconds (before attack speed)
		"nc_ring":
			h._start_attack("cast", "nc_ring")
			h.atk_dur = 0.55 * Data.attack_pace(h.cls)       # fixed length, not scaled by attack speed
		"nc_buff":
			h._start_attack("cast", "nc_buff")
			h.atk_dur = 0.6 * Data.attack_pace(h.cls)

## The impact frame (Anim.impact_at of the attack style). Return false for ids that aren't this class's.
static func impact(h: Hero) -> bool:
	var fwd := h.aim_dir()      # "ahead" is the pointer's line when he cast (never the body's facing)
	match h.atk_skill:
		"nc_strike":
			var hit := []
			for e in h.game.enemies_near(h.global_position, 3.0):
				var to: Vector3 = e.global_position - h.global_position
				to.y = 0
				if to.length() < 0.5 or fwd.dot(to.normalized()) > cos(deg_to_rad(70.0)):
					h._hit_enemy(e, 1.3, 0.5, "nc_strike")    # weapon damage x1.3, a little knockback
					hit.append(e)
			h.fx("nc_strike", "impact", {"y": h.rig.global_rotation.y, "t": hit})
		"nc_ring":
			var dmg := (16.0 + h.level * 4.0 + (h.dmg_min + h.dmg_max) * 0.4) * h.buff_mult() * h.dmg_mult("nc_ring")
			h.fx("nc_ring", "impact")
			for e in h.game.enemies_near(h.global_position, 6.0):
				e.take_damage(dmg, 0.0, h.global_position, 1.0, false)
		"nc_buff":
			h.buff_t = 12.0 + h.talent("buff_dur")
			h.fx("nc_buff", "impact", {"x": h.buff_t})
		_:
			return false
	return true

## Every frame on the local hero, whatever his class: run down this class's own timers and lingering effects
## (state lives on the hero; check it's set before doing work).
static func update(_h: Hero, _delta: float) -> void:
	pass

## True while one of his skills should hold him in place (he can't be walked mid-slam, say).
static func rooted(_h: Hero) -> bool:
	return false

## A class change or a new character: drop everything of this class's.
static func clear(_h: Hero) -> void:
	pass

## Death: end what shouldn't outlive him.
static func died(_h: Hero) -> void:
	pass

## The cast's sound, timed so its payoff lands on the impact frame (`at` seconds from now).
static func sound(_h: Hero, skill: String, at: float) -> bool:
	match skill:
		"nc_strike": Sfx.play_synced("hellclaw", at, -2.0)
		_: return false
	return true
