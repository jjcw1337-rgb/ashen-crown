class_name Thunderstep
extends Skill
## Thunderstep (id "snare", kept for old saves' bindings and talents; jj's pick): he backflips away from the pointer,
## driving a thunderstone into a gold storm sigil where he stood, which a moment later detonates: everything on it
## stunned and hurt, lightning leaping on into the nearest others beyond it (Forked Lightning: more of them;
## Aftershock: it strikes again, weaker; Wide Sigil: wider; Long Shock: longer). Players are stunned too, through the
## server (PvpStatus "stagger", with diminishing returns; Blaine, 2026-11-07: three seconds). Its look:
## ThunderstepFx (thunderstep_fx.gd). Codex "k": dmg and chain (% of the weapon's blow on the sigil and down the
## chain), stun_s and chain_stun_s, radius, arm (seconds before it blows), chain_r, arcs, vault (metres) and
## vault_s, again (seconds to Aftershock's second blast) and again_k (its share).

var sigils: Array = []       # DelayedAreas charging
var vault := {}              # the backflip in progress: {from, to, t}

func cast(aim: Vector3) -> void:
	var h := hero
	var from: Vector3 = h.global_position
	var away := (from - aim) * Vector3(1, 0, 1)
	if away.length() < 0.5:
		away = -h.facing()
	away = away.normalized()
	h._face(-away)
	var to: Vector3 = h.game.world.move(from, away * val("vault", 6.5), h.radius)
	to.y = h.game.world.height_at(to.x, to.z)
	h.atk_aim = aim
	h._start_attack("cast", id)
	h.atk_dur = val("vault_s", 0.55)
	vault = {"from": from, "to": to, "t": 0.0}
	var g := Vector3(from.x, h.game.world.height_at(from.x, from.z), from.z)
	h.fx(id, "vault", {"p": g, "q": to})
	make("sigil", {"g": g})

## The sigil its rules charge and blow.
func made(kind: String, d: Dictionary) -> void:
	if kind == "sigil":
		sigils.append(DelayedArea.new(d["g"], val("radius", 3.2), val("arm", 0.9), 1 + int(hero.talent("snare_max")), val("again", 0.8)))

## Server: a sigil where he stood, within a vault of where it has him.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "sigil" and d.get("g") is Vector3 and (d["g"] as Vector3).distance_to(hero.global_position) <= val("vault", 6.5) + 6.0

## Mid-flip his feet are the vault's.
func rooted() -> bool:
	return not vault.is_empty()

func update(delta: float) -> void:
	if not vault.is_empty():
		_carry(delta)
	for s in sigils.duplicate():
		if s.tick(delta):
			_detonate(s)
		if s.over():
			sigils.erase(s)

## The vault carrying him back along the ground (the flip itself is ThunderstepFx's pose).
func _carry(delta: float) -> void:
	var h := hero
	vault["t"] = float(vault["t"]) + delta
	var s := clampf(float(vault["t"]) / val("vault_s", 0.55), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - s, 1.8)
	var want: Vector3 = (vault["from"] as Vector3).lerp(vault["to"], e)
	var np: Vector3 = h.game.world.move(h.global_position, (want - h.global_position) * Vector3(1, 0, 1), h.radius)
	np.y = h.game.world.height_at(np.x, np.z)
	h.global_position = np
	if s >= 1.0 or h.dead:
		vault = {}

## The sigil detonates: everything on it stunned and hurt, the lightning leaping on into the nearest others outside it.
func _detonate(s: DelayedArea) -> void:
	var h := hero
	var pos := s.pos
	var r := s.r * (1.3 if h.talent("snare_wide") > 0.0 else 1.0)
	var first := s.count == 1
	var k := 1.0 if first else val("again_k", 0.6)
	var hold := (val("stun_s", 3.0) + h.talent("snare_dur")) * (1.0 if first else 0.5)
	var caught: Array = []
	for e in h.game.enemies_near(pos, r):
		if foe(e):
			caught.append(e)
	var arcs := int(val("arcs", 3.0)) + int(h.talent("arc_count"))
	var near: Array = h.game.enemies_near(pos, val("chain_r", 8.0)).filter(func(e) -> bool: return foe(e) and not (e in caught))
	near.sort_custom(func(a, b) -> bool: return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	var struck: Array = near.slice(0, arcs)
	# the blast and the chain, seen by everyone (the puppet's sigil detonates on this event)
	h.fx(id, "spring", {"p": pos, "r": r, "t": caught + struck, "n": caught.size(), "x": not s.over()})
	for e in caught:
		_stun(e, hold)
		h._hit_enemy(e, val("dmg", 160.0) / 100.0 * k, 0.0, id)
	for e in struck:
		h._hit_enemy(e, val("chain", 80.0) / 100.0 * k, 0.0, id)
		_stun(e, val("chain_stun_s", 0.5))

## A monster is stunned here; a player through the server, which checks it and applies diminishing returns.
func _stun(e, secs: float) -> void:
	if int(e.get("pvp_pid")) > 0:
		PvpStatus.send(hero.game, e, "stagger", secs)
	else:
		e.stun(secs)

func clear() -> void:
	sigils.clear()
	vault = {}
