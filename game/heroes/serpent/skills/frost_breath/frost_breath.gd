class_name FrostBreath
extends DragonSkill
## Frost Breath ("frost_breath", the serpent's own): it lowers its head and breathes a freezing gale over the cone
## ahead for the whole of its use, a beat of cold every "beat" seconds while its jaws are open (between "open" and
## "close" of the breath). The cone, the cold's damage and its chill are its data entry's (SkillSpec: "area", "base",
## "per_lvl", "dot"). Held like a channel (the Warlock's Drain Life): the serpent's own game holds the breath (its
## attack: a dodge or death breaks it off) and the way it was aimed, and makes the "latch" as the jaws open and the
## "end" as they close; the rules (here, or on the match server's copy of it) strike the cone each beat from where they
## have the serpent. A player in it is slowed through the server (PvpStatus), once a second at most. Its look:
## frost_breath_fx.gd (FrostBreathFx, from the cast's own event). Codex "k": beat (seconds), open and close (of the
## breath's progress).

## Seconds between a player's slows while it stands in the breath (PvpStatus, not every beat).
const PVP_SLOW_EVERY := 1.0

var on := false                  # its own game: the jaws are open (the latch made)
var latched := false             # the rules: breathing
var dir := Vector3.FORWARD       # the rules: the way it breathes
var tick := 0.0                  # the rules: seconds to the next beat
var slowed := {}                 # the rules: a player's stand-in -> when it was last slowed (ms)

func cast(_aim: Vector3) -> void:
	if on:
		on = false
		make("end", {})
	hero._start_attack("breath", id)
	halt()

## Every frame: its own game watches its jaws; the rules beat while it breathes.
func update(delta: float) -> void:
	if not hero.puppet:
		_hold()
	if not latched:
		return
	tick -= delta
	if tick <= 0.0:
		tick = val("beat", 0.2)
		_beat()

## Its own game: the jaws open and close with the breath's progress; a breath broken off closes them.
func _hold() -> void:
	var h := hero
	var a := h.atk_t / maxf(h.atk_dur, 0.001) if h.atk_t >= 0.0 and h.atk_skill == id else -1.0
	var open := a >= val("open", 0.15) and a <= val("close", 0.9)
	if open and not on:
		on = true
		make("latch", {"p": h.global_position, "d": h.aim_dir()})
	elif on and not open:
		on = false
		make("end", {})

func made(kind: String, d: Dictionary) -> void:
	match kind:
		"latch":
			dir = d["d"]
			latched = true
			tick = 0.0
			slowed.clear()
		"end":
			latched = false

## Server: a breath from where it has the serpent, aimed flat; its end.
func server_ok(kind: String, d: Dictionary) -> bool:
	match kind:
		"latch":
			return flat(d, "d") and near_me(d.get("p"), 4.0)
		"end":
			return true
	return false

## A beat: the cone's cold on everything in it (SkillSpec, the way it breathes from where the serpent is now).
func _beat() -> void:
	var h := hero
	for e in SkillSpec.targets(h, id, {"d": dir, "ok": foe}):
		if not PvpStatus.is_player(e):
			SkillSpec.strike(h, id, e)
			continue
		SkillSpec.strike(h, id, e, 0.0, {"dot": false})
		var now := Time.get_ticks_msec()
		if now - int(slowed.get(e, -100000)) >= int(PVP_SLOW_EVERY * 1000.0):
			slowed[e] = now
			var dt: Dictionary = SkillSpec.of(id).get("dot", {})
			chill(e, float(dt.get("k", 0.45)), float(dt.get("secs", 1.5)))

func clear() -> void:
	on = false
	latched = false
	slowed.clear()
