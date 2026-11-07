class_name ThunderDive
extends DragonSkill
## Thunder Dive ("v_dive", a run skill): the wyvern climbs on its wings and dives onto the pointer in a strike of
## lightning: everything where it lands is struck and stunned (Plummet: wider, harder, sooner; Eye of the Storm: a kill
## makes it ready again). Its own game flies it there (its position is that game's) and, landing on the dive's impact
## frame (Anim.impact_at "dive"), makes the "land" where it came down; the rules (here, or on the match server's copy
## of it) strike and stun there and show it ("land"). A player is stunned through the server (PvpStatus). Its look:
## thunder_dive_fx.gd (ThunderDiveFx: "start" from the cast, "land"). Codex "k": r (metres it strikes round where it
## lands), dmg (% of the weapon's blow), stun_s; its reach is its codex range.

## Of the dive's progress: when it leaves the ground (it lands on the style's impact frame).
const TAKEOFF := 0.12
const KNOCK := 2.5

var dive := {}          # its own game: the flight in progress {from, to}

func cast(at: Vector3) -> void:
	var h := hero
	h._start_attack("dive", id)
	halt()
	var to := clamp_aim(at, reach())
	if h.game.world.is_blocked(to.x, to.z):
		to = h.game.world.free_spot_near(to, 1.5)
	dive = {"from": h.global_position, "to": to}
	h.fx(id, "start", {"p": h.global_position, "q": to, "x": h.atk_dur})

## Its own game: carried through the air from where it took off to where it aimed, while the dive lasts.
func update(_delta: float) -> void:
	if hero.puppet or dive.is_empty():
		return
	var h := hero
	if h.atk_skill != id or h.atk_t < 0.0:
		dive = {}
		return
	var a := clampf((h.atk_t / maxf(h.atk_dur, 0.01) - TAKEOFF) / (Anim.impact_at("dive") - TAKEOFF), 0.0, 1.0)
	var p: Vector3 = (dive["from"] as Vector3).lerp(dive["to"], smoothstep(0.0, 1.0, a))
	var step := p - h.global_position
	step.y = 0
	h.global_position = h.game.world.move(h.global_position, step, h.radius * 0.5)

## It comes down where it aimed, and the blow lands there.
func impact() -> void:
	var h := hero
	if not dive.is_empty():
		h.global_position = h.game.world.move(h.global_position, dive["to"] - h.global_position, h.radius)
	dive = {}
	make("land", {"p": h.global_position})

func made(kind: String, d: Dictionary) -> void:
	if kind != "land":
		return
	var h := hero
	var p: Vector3 = d["p"]
	var r := val("r", 4.0) * (1.0 + h.talent("dive_r") / 100.0)
	var hit: Array = []
	for e in h.game.enemies_near(p, r):
		if not hits(e):
			continue
		h._hit_enemy(e, val("dmg", 240.0) / 100.0, KNOCK, id)
		if not e.dead:
			stun(e, val("stun_s", 0.8))
		hit.append(e)
	h.fx(id, "land", {"p": p, "r": r, "t": hit})
	if h.talent("dive_reset") > 0.0 and hit.any(func(e) -> bool: return e.dead):
		give("ready", {})      # (Eye of the Storm)

## Server: a landing within a dive of where it has the wyvern (it flies fast; the server hears late).
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "land" and near_me(d.get("p"), reach() + 6.0)

## Its own game: a kill made it ready again.
func given(kind: String, _data: Dictionary) -> void:
	if kind == "ready":
		hero.cds[id] = 0.0

func clear() -> void:
	dive = {}
