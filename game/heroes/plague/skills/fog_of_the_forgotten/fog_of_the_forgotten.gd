class_name FogOfTheForgotten
extends PlagueSkill
## F Fog of the Forgotten ("fog"): the censer dashed at his feet and a hop back from the pointer; pale fog hangs there.
## Players outside can't see anyone inside; inside, everyone within `see` is seen. He moves faster in it; using a
## skill or striking from it reveals him for a moment; Feverish or swarm-marked players show through it (PvpStatus
## "reveal"). Monsters beyond `see` lose track of him in it (bosses and the Hollow Sloths see through it: Enemy).
## It makes nothing his rules act on (it hurts no one): his speed and the reveal are his own game's (`fogs`), and who
## is hidden from whom is answered on each game from the fog that game shows (PlagueFogFx keeps where it is: `zones`),
## so a co-op host's monsters and a match server's both lose him.
## Its look: PlagueFogFx ("fog" {p, r, x: seconds}, "reveal"). Codex "k": cast_s, radius, secs (Lingering Fog adds to
## it), see, hop (metres), speed (% faster in it), reveal_s.

var fogs: Array = []      # his game: {pos, r, t}

func cast(aim: Vector3) -> void:
	var h := hero
	var to := (aim - h.global_position) * Vector3(1, 0, 1)
	h.atk_aim = h.global_position + (to.normalized() if to.length() > 0.1 else -h.facing())
	h._start_attack("pd_fog", id)
	h.atk_dur = cast_secs(0.6)

func impact() -> void:
	var h := hero
	var g := ground(h.global_position)
	var r := val("radius", 6.0)
	var secs := val("secs", 6.0) + h.talent("fog_dur")
	h.fx(id, "fog", {"p": g, "r": r, "x": secs})
	fogs.append({"pos": g, "r": r, "t": secs})
	# the hop back: away from the pointer
	var dir := ((h.global_position - h.atk_aim) * Vector3(1, 0, 1)).normalized()
	if dir.length() < 0.1:
		dir = -h.aim_dir()
	h.shove = dir * val("hop", 4.0) * 6.0

func update(delta: float) -> void:
	for f in fogs.duplicate():
		f["t"] = float(f["t"]) - delta
		if float(f["t"]) <= 0.0:
			fogs.erase(f)

func in_fog(p: Vector3) -> bool:
	for f in fogs:
		var c: Vector3 = f["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(f["r"]) * 0.92:
			return true
	return false

## Walking in his own fog he's quicker (ClassSkills.pace).
func pace() -> float:
	return 1.0 + val("speed", 25.0) / 100.0 if not fogs.is_empty() and in_fog(hero.global_position) else 1.0

## A skill used from inside his fog shows him for a moment, on every game.
func reveal_if_in() -> void:
	if not fogs.is_empty() and in_fog(hero.global_position):
		hero.fx(id, "reveal")

func clear() -> void:
	fogs.clear()

# ---------------------------------------------------------------- who sees him (on each game, from the fog it shows)
## Is he hidden from the player watching (`viewer`)? Only in the Battlegrounds (in co-op his partners always see him,
## faded). Hidden while inside his fog, unless the watcher is within `see` of him, he struck from it a moment ago, or
## he carries Fever or the swarm's mark.
static func hidden_from(h: Hero, viewer: Hero) -> bool:
	if viewer == null or not PlagueFogFx.covers(h, h.global_position):
		return false
	if PvpStatus.has(h, "reveal"):
		return false
	return viewer.global_position.distance_to(h.global_position) > Skill.num("fog", "see", 3.5)

## For a monster at `at` (Enemy._process, on the game running the monsters): it can't see him in his fog and loses
## track of him, as of a Demon in the Underworld, unless it's within `see`, he struck from the fog a moment ago or
## he's marked (reveal).
static func hidden_from_monster(h: Hero, at: Vector3) -> bool:
	if not PlagueFogFx.covers(h, h.global_position):
		return false
	if PvpStatus.has(h, "reveal"):
		return false
	return Vector2(at.x - h.global_position.x, at.z - h.global_position.z).length() > Skill.num("fog", "see", 3.5)
