class_name DragonKit
extends RefCounted
## What every dragon's skills script shares (the Obsidian Wyrm's game/heroes/wyrm/wyrm.gd, the Frost Serpent's
## serpent/serpent.gd, the Storm Wyvern's wyvern/wyvern.gd: each keeps its own kit table and answers ClassSkills, and
## hands these on here). A dragon's basic attack is the common three-swipe combo (Hero._swipe_impact), which its body
## (Dragon.pose) shows as a raking foreclaw, a lunging bite and a tail spin: this plays their sounds, and its roars.
## What its skills share is DragonSkill (dragon_skill.gd); its body, Dragon (dragon.gd); off the ground, DragonFlight.

## How far its basic attack reaches (ClassSkills.reach).
static func reach(h: Hero) -> float:
	return Dragon.reach(h.cls)

## Its roar, under a skill's own sound.
static func roar(h: Hero, db: float, pitch: float) -> void:
	Sfx.play(h.cls + "_roar", db, pitch)

## The basic attack's sounds, each landing on its impact frame: claw, bite, tail spin. True when it was one.
static func attack_sound(h: Hero, skill: String, at: float) -> bool:
	if skill != "":
		return false
	match h.atk_style:
		"swipe1":
			Sfx.play_synced(h.cls + "_claw", at, -2.0)
		"swipe2":
			Sfx.play_synced(h.cls + "_bite", at, -2.0)
		"swipe3":
			Sfx.play_synced(h.cls + "_tail", at, -1.0)
			Sfx.play(h.cls + "_roar", -12.0, 1.1)
		_:
			return false
	return true

## A last roar under the death cry.
static func died(h: Hero) -> void:
	if h.rig != null and h.rig.is_inside_tree():
		Sfx.play_at(h.cls + "_roar", h.global_position, -6.0, 0.8)

## Where a dragon's breath leaves it: in front of its head.
static func jaws(h: Hero) -> Vector3:
	var J: Dictionary = h.rig.get_meta("j") if h.rig != null and h.rig.has_meta("j") else {}
	var hd = J.get("at_head", J.get("head"))
	if hd is Node3D and is_instance_valid(hd):
		return (hd as Node3D).global_position + h.facing() * 0.5
	return h.global_position + Vector3(0, 2.0, 0) + h.facing() * 1.2
