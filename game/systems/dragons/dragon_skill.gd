class_name DragonSkill
extends Skill
## A dragon's skill (game/heroes/<dragon>/skills/<skill>/, docs/content/skills.md): what every dragon's skills share.
## Its rules strike `hits`: a foe alive, no player's thing (PvpObjects) and not on its own side (ServerRules.friend).
## Its crowd control reaches a monster at once and a player through the server (PvpStatus: `stun`, `slow`, `chill`,
## `freeze`). A foe its cast picked goes to its rules by id as well as where it stood (`net_id`; the server finds it
## with ServerRules.foe_of), since the server has everyone a little elsewhere.

## Where its cast was aimed (its impact frame goes there).
var aim := Vector3.ZERO

## Its codex "range" (metres).
func reach() -> float:
	return float(Data.skill_def(id).get("range", 12.0))

## A foe its rules may strike.
func hits(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead and int(e.get("pvp_obj")) == 0 and not ServerRules.friend(hero, e)

## The point aimed at, on the ground and no further than `r` from the hero.
func clamp_aim(at: Vector3, r: float) -> Vector3:
	var h := hero
	var off := at - h.global_position
	off.y = 0
	if off.length() > r:
		at = h.global_position + off.normalized() * r
	at.y = h.game.world.height_at(at.x, at.z)
	return at

## It stops where it stands for the cast.
func halt() -> void:
	hero.moving = false
	hero.path = PackedVector3Array()

## Server: a point the player's game sent, within `slack` metres of where the server has the hero.
func near_me(p, slack: float) -> bool:
	return p is Vector3 and (p as Vector3).distance_to(hero.global_position) <= slack

## Server: a direction the player's game sent, made flat and of length one (false if it isn't one).
static func flat(d: Dictionary, key: String) -> bool:
	if not d.get(key) is Vector3:
		return false
	var v: Vector3 = d[key] * Vector3(1, 0, 1)
	if v.length() < 0.01:
		return false
	d[key] = v.normalized()
	return true

# ---------------------------------------------------------------- crowd control
## Stunned: a monster here, a player through the server (a stagger, with its diminishing returns).
func stun(e, secs: float) -> void:
	Hero.striker = hero
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "stagger", secs)
	else:
		e.stun(secs)

## Slowed by k (0..1) for secs.
func slow(e, secs: float, k: float) -> void:
	Hero.striker = hero
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "slow", secs, {"k": k})
	else:
		e.slow(secs, k)

## Chilled by k for secs (a player: slowed by as much).
func chill(e, k: float, secs: float) -> void:
	Hero.striker = hero
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "slow", secs, {"k": k})
	else:
		e.chill(k, secs)

## Frozen solid for secs (ProcHits.freeze; a player: staggered, and seen frozen).
func freeze(e, secs: float) -> void:
	Hero.striker = hero
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "stagger", secs)
		hero.fx("run", "freeze", {"p": e.global_position, "r": float(e.radius) + 0.4, "x": secs})
	else:
		ProcHits.freeze(hero, e, secs)

# ---------------------------------------------------------------- foes by id

## Rules: the foe an id names, on the match server, if it's still one to strike within `r` of the hero; else null.
func foe_by_id(d: Dictionary, r: float):
	if int(d.get("id", 0)) == 0 or not hero.game.net.server:
		return null
	var e = ServerRules.foe_of(hero.game, int(d["id"]))
	return e if hits(e) and e.global_position.distance_to(hero.global_position) <= r else null
