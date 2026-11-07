class_name PlagueSkill
extends Skill
## One of the Plague Doctor's skills (docs/content/skills.md): what all of his share. His damage is poison's kind
## (green numbers, no blood or flinch, armour doesn't stop it: `damage`), worked out from his level and weapon
## (`base`); his poison, Blight and Fever are the hero's one PlagueAffliction (`aff`, shared/plague_affliction.gd);
## and what he lays down that ticks (a pool, a cloud) is a `PlagueCloud` the skill keeps and `tick_cloud` beats.

const POISON_TINT := Color(0.55, 1.0, 0.35, 1.0)

## His poison, Blight and Fever (one per hero, in Hero.kit: wherever his rules run).
func aff() -> PlagueAffliction:
	return Plague.skill(hero, "poison") as PlagueAffliction

## Damage by his level and weapon (the same shape as the warlock's Blight Bolt): flat + level x per level + the
## weapon's roll x per weapon, with his buffs and the skill's own talents.
func base(k_flat: float, k_lvl: float, k_wpn: float, src: String) -> float:
	var h := hero
	return (k_flat + h.level * k_lvl + (h.dmg_min + h.dmg_max) * k_wpn) * h.buff_mult() * h.dmg_mult(src)

## The same from the skill's codex numbers `<pre>_flat`, `<pre>_lvl`, `<pre>_wpn`.
func base_k(pre: String, flat: float, lvl: float, wpn: float, src := "") -> float:
	return base(val(pre + "_flat", flat), val(pre + "_lvl", lvl), val(pre + "_wpn", wpn), src if src != "" else id)

## The foes his rules may touch round a point (monsters and, in a match, other players' stand-ins).
func foes(at: Vector3, r: float) -> Array:
	if hero.game == null:
		return []
	return hero.game.enemies_near(at, r).filter(func(e) -> bool: return foe(e))

## Poison and its kin hurt in green numbers, with no blood; armour doesn't stop them (the game's elemental channel).
func damage(e, amount: float, from: Vector3, knock: bool) -> void:
	if e == null or not is_instance_valid(e) or e.dead or amount <= 0.0:
		return
	var h := hero
	Hero.striker = h
	e.dmg_tint = POISON_TINT
	e.soft_hit = not knock
	if h.run != null:
		RunTalents.mark(h, e)
	var dealt: float = e.take_damage(0.0, amount, from, 0.3 if knock else 0.0, false)
	e.soft_hit = false
	e.dmg_tint = Color(0, 0, 0, 0)
	if h.puppet and h.game.net.server:
		h.game.net.tell_dealt(h, e.global_position, dealt, false)      # (the number on his screen)

## Heals him from his own skill (from the match server's copy of him it goes to his game: Hero.gain_life).
func heal(amount: float) -> void:
	hero.gain_life(amount)

## His right hand (where a vial or the reliquary leaves it), else a point at his chest.
func hand(up := 1.6) -> Vector3:
	var J: Dictionary = hero.rig.get_meta("j") if hero.rig != null and hero.rig.has_meta("j") else {}
	return (J["at_hand_r"] as Node3D).global_position if J.has("at_hand_r") else hero.global_position + Vector3(0, up, 0)

## The ground under a point.
func ground(at: Vector3) -> Vector3:
	return Vector3(at.x, hero.game.world.height_at(at.x, at.z), at.z)

## Using a skill from inside his fog shows him for a moment (on his own game, as he casts).
func reveal_if_fogged() -> void:
	var f := Plague.skill(hero, "fog") as FogOfTheForgotten
	if f != null:
		f.reveal_if_in()

## Where he aims it, no further than the skill's range (its codex "range").
func within_range(aim: Vector3, fallback: float) -> Vector3:
	var to := (aim - hero.global_position) * Vector3(1, 0, 1)
	return hero.global_position + to.limit_length(float(Data.skill_def(id).get("range", fallback)))

## The cast's length at his pace (its codex "cast_s"), slower when harried.
func cast_secs(fallback: float) -> float:
	var h := hero
	return val("cast_s", fallback) * Data.attack_pace(h.cls) * (PvpStatus.act_mult(h) if not h.pvs.is_empty() else 1.0)

## Server: `p` (a Vector3) is within `reach` metres of where it has him.
func near_him(p, reach: float) -> bool:
	return p is Vector3 and (p as Vector3).distance_to(hero.global_position) <= reach

# ---------------------------------------------------------------- what ticks on the ground
## A pool or cloud of his: everything in it is poisoned from `src` every tick (and Blighted, for the vial's kind);
## a leech pool heals him for each foe in it; a choking one slows.
class PlagueCloud extends GroundZone:
	var src := "toxic"
	var linger := 2.0       # seconds the poison stays after a foe steps out
	var blight := ""        # the Blight it adds ("" none)
	var leech := 0.0        # % of his life a second, for each foe in it
	var leech_max := 3
	var slow := 0.0

## A cloud at `at`, `r` wide, for `secs`, ticking at the poison's beat.
func cloud(at: Vector3, r: float, secs: float, src: String, linger: float) -> PlagueCloud:
	var c := PlagueCloud.new(at, r, secs, 0.0, aff().tick())
	c.src = src
	c.linger = linger
	return c

## One frame of a cloud: true when it is over.
func tick_cloud(c: PlagueCloud, delta: float) -> bool:
	c.left -= delta
	if c.left <= 0.0:
		return true
	c.next -= delta
	if c.next > 0.0:
		return false
	c.next = c.every
	var a := aff()
	var fed := 0
	for e in foes(c.pos, c.r):
		a.poison(e, c.src, c.linger)
		if c.blight != "":
			a.blight(e, c.blight)
		fed += 1
	if c.leech > 0.0 and fed > 0:
		heal(hero.max_life * c.leech / 100.0 * c.every * mini(fed, c.leech_max))
	if c.slow > 0.0:
		for e in foes(c.pos, c.r):
			e.chill(c.slow, 1.0)
	return false
