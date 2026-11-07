class_name SoulFeast
extends WarlockSpell
## Soul Feast ("w_soulfeast"; the Drain ultimate): for the length of its cast she drains every foe near her, healing
## a share of it, and while she feasts, healing past full life hardens into a shield (WarlockHex.healed). She is held
## in place while she casts it. Her own game holds the cast (`casting`: it ends with the cast, and tells the rules);
## the rules beat the drain (`feast`). Its look: WarlockHarrowFx ("feast", "end": beams to every foe near, drawn from
## each game's own foes). Codex "k": radius, dps (% of her spell power a second), heal (% of what it drains), shield
## (% of her life the overflow can harden into), first and beat (seconds to the first drain and between them), and
## for every shield of hers: shield_fade (seconds out of combat before it melts), shield_melt (% of her life a second).

var casting := false       # her own game: the feast's cast is on
var feast := {}            # rules: {tick: seconds to the next drain, left: seconds at most (the server's copy)}

func cast(aim: Vector3) -> void:
	super.cast(aim)
	casting = true
	hero.fx(id, "feast", {"x": float(Data.skill_def(id).get("use", 3.0))})
	make("feast", {})

func made(kind: String, _d: Dictionary) -> void:
	if kind == "feast":
		feast = {"tick": val("first", 0.15), "left": float(Data.skill_def(id).get("use", 3.0)) + 1.0}
	elif kind == "end":
		feast = {}

func server_ok(kind: String, _d: Dictionary) -> bool:
	return kind == "feast" or kind == "end"

## Held in place while she casts it.
func rooted() -> bool:
	return hero.atk_t >= 0.0 and hero.atk_skill == id

func update(delta: float) -> void:
	var h := hero
	if casting and (h.atk_skill != id or h.atk_t < 0.0):
		# the cast is over (her own game): the feast ends
		casting = false
		h.fx(id, "end")
		make("end", {})
		return
	if feast.is_empty():
		return
	if h.puppet:
		# (the server's copy: should her game's end never come, it ends with its time)
		feast["left"] -= delta
		if feast["left"] <= 0.0:
			feast = {}
			return
	feast["tick"] -= delta
	if feast["tick"] > 0.0:
		return
	var beat := val("beat", 0.3)
	feast["tick"] = beat
	var hx := hex()
	var total := 0.0
	for e in h.game.enemies_near(h.global_position, val("radius", 7.0)):
		if e.get("pvp_obj") or e.get("pvp_hidden") or not foe(e):
			continue
		total += hx.hit(e, hx.amount(id, val("dps", 80.0) / 100.0 * beat, e), Color(0.6, 1.0, 0.45), true)
	hx.heal(id, total * (val("heal", 25.0) / 100.0))

func clear() -> void:
	super.clear()
	casting = false
	feast = {}
