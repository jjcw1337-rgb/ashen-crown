class_name DemonSkill
extends Skill
## A skill of the Demon's (demon.gd keeps one per skill id in Hero.kit). What his skills share:
##  - his magma: a part by level on top of the weapon in every blow (`magma`);
##  - the PvP share: against a player (a Battlegrounds stand-in) a blow deals its "pvp" share of what it deals
##    monsters (Data.SKILLS "pvp"), with no knockback, and its crowd control goes through the server (`cc`);
##  - his stages: a skill of several clips chains them (`start`, `next_now`; the queued one starts when this one's
##    clip ends, `stages`), each stage its own attack style (DemonBody.SHOTS);
##  - a foe his game picked (the chain's hook) goes to the match server as its id (`make_at`, `foe_in`).
## Every number is its codex "k" (val). Its rules run where his hits are decided (Skill.deals): here, or on the match
## server's copy of him, which makes what his game sends (make / made / server_ok).

## The stage queued after this one (it starts when this one's clip has ended).
var next := ""

## The magma in his blows: a part by level on top of the weapon (the same curve as the other classes' spells), so his
## skills keep their weight while the weapon is still small. k is the blow's share of it.
static func magma(h: Hero, k: float) -> float:
	return (16.0 + h.level * 4.5 + (h.dmg_min + h.dmg_max) * 0.35) * k

## Its number against players (Data.SKILLS "pvp": the share of what it deals monsters, a status's seconds).
static func pvp_of(skill_id: String, key: String, def: float) -> float:
	return float((Data.skill_def(skill_id).get("pvp", {}) as Dictionary).get(key, def))

func pvp(key: String, def: float) -> float:
	return pvp_of(id, key, def)

## Is this one too big to be stopped or dragged (bosses, the Sloths)?
static func immovable(e) -> bool:
	return bool(e.boss) or e.get("sloth") != null

## A blow of his: against a player its PvP share applies (and Pit-born's PvP bonus in place of the battle buff).
func hit(e, mult: float, knock: float, flat: float, src := "") -> void:
	var h := hero
	var by := src if src != "" else id
	if PvpStatus.is_player(e):
		var share := pvp_of(by, "dmg", 1.0)
		if h.buff_t > 0.0 and Demon.pit_born(h):
			share *= (1.0 + pvp_of("wrath", "bonus", 0.2)) / h.buff_mult()
		mult *= share
		flat *= share
		knock = 0.0
	h._hit_enemy(e, mult, knock, by, flat)

## A status on a foe: a monster takes it here (stun, slow), a player through the server (PvpStatus).
func cc(e, kind: String, pve_secs: float, pvp_secs: float, data := {}) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	if PvpStatus.is_player(e):
		if pvp_secs > 0.0:
			PvpStatus.send(hero.game, e, kind, pvp_secs, data)
		return
	match kind:
		"slow":
			e.slow(pve_secs, float(data.get("k", 0.35)))
		_:
			if pve_secs > 0.0:
				e.stun(pve_secs)

## A foe's burn: a monster's here, a player's through the server.
func burn(e, dps: float, secs: float, pvp_secs := -1.0) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "burn", pvp_secs if pvp_secs > 0.0 else secs, {"dps": dps})
	else:
		e.ignite(dps, secs)

## The foes within r of `at` (alive, not his side), measured to their edge.
func foes_round(at: Vector3, r: float, edge := 1.0) -> Array:
	var out := []
	for e in hero.game.enemies_near(at, r + 0.8):
		var to: Vector3 = e.global_position - at
		to.y = 0
		if to.length() - e.radius * edge <= r and foe(e):
			out.append(e)
	return out

## A meteor lands at `at` (Wrath of the Pit's rain, the Volcano's): its blow on everything within r (`mult` of the
## weapon's, `magma_k` of his magma), and monsters set alight (`burn_k` of his magma a second, for 3 s).
func land_meteor(at: Vector3, r: float, mult: float, magma_k: float, burn_k: float) -> void:
	var h := hero
	for e in foes_round(at, r):
		hit(e, mult, 1.2, magma(h, magma_k))
		if is_instance_valid(e) and not e.dead and not PvpStatus.is_player(e):
			e.ignite(magma(h, burn_k) * h.dmg_mult(id), 3.0)

# ---------------------------------------------------------------- stages
## Starts one of its clips: `secs` before the class's pace (else the stage's own length, Demon.DUR).
func start(style: String, secs := 0.0) -> void:
	var h := hero
	h._start_attack(style, id)
	# (the same timing everywhere, the Battlegrounds included; a skill with a "use" in its data is retimed by
	# SkillSpec.apply_timing once its cast is done)
	var d: float = (secs if secs > 0.0 else float(Demon.DUR[style])) * Data.attack_pace(h.cls)
	if id == "fists":
		d /= h.aspd
	h.atk_dur = d
	h.moving = false
	h.path = PackedVector3Array()

## Queue the stage after this one and end this one at once.
func next_now(style: String) -> void:
	next = style
	hero.atk_t = hero.atk_dur

## Hero._update_attack ended one of its stages (Demon.stage_done): what follows it.
func stage_done(_style: String) -> void:
	pass

## A queued stage starts.
func begin_stage(_style: String) -> void:
	pass

## Every frame, first: the queued stage starts once the clip before it has ended.
func stages() -> void:
	if next == "" or hero.atk_t >= 0.0:
		return
	var s := next
	next = ""
	if not hero.dead:
		begin_stage(s)

## Mid-skill: it, or a stage still to come, holds him.
func busy() -> bool:
	return next != "" or (hero.atk_t >= 0.0 and hero.atk_skill == id)

# ---------------------------------------------------------------- a foe his game picked
## Makes `kind` about foe `e`: here with the foe itself, or on the match server as its id (SkillFx.encode).
func make_at(kind: String, e, data: Dictionary) -> void:
	if deals():
		data["e"] = e
		made(kind, data)
	else:
		data["t"] = SkillFx.encode(hero.game.net, {"t": [e]})["t"]
		hero.game.net.send_skill_make(id, kind, data)

## The foe a `make_at` named (on the server, its id resolved: ServerRules.foe_of), or null.
func foe_in(d: Dictionary):
	var e = null
	if d.has("t"):
		var ids = d["t"]
		if (ids is PackedInt64Array or ids is Array) and ids.size() > 0:
			e = ServerRules.foe_of(hero.game, int(ids[0]))
	elif not hero.game.net.server:
		e = d.get("e")
	return e if e != null and is_instance_valid(e) and foe(e) else null

## What its rules give him (Skill.give): "refund", a share of its cooldown back.
func given(kind: String, d: Dictionary) -> void:
	if kind == "refund":
		hero.cds[id] = hero.cds.get(id, 0.0) * (1.0 - clampf(float(d.get("k", 0.0)), 0.0, 1.0))
