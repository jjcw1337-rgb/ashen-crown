class_name Consumables
extends RefCounted
## A run's consumables (Data.BASES: potions, elixirs, flasks, a ward scroll, a tome): what a camp chest holds for each
## player, and the thrown flask. Drinking one is Hero.drink (an elixir is a timed buff, RunTalents.buff); a flask is
## thrown at the pointer (throw_flask) and bursts on the game that decides its thrower's hits; its look is FlaskFx.

## What a camp chest gives each player besides the upgrade: the consumables (Data.BASES), weight by tier [1, 2, 3, boss].
const CONSUMABLES := {
	"hp_potion": [40, 30, 22, 14], "mp_potion": [14, 12, 10, 8], "elixir_fury": [8, 10, 12, 14], "draught_iron": [8, 10, 12, 12],
	"tonic_swift": [8, 8, 8, 8], "salve_troll": [6, 8, 10, 12], "elixir_wrath": [2, 5, 8, 12], "flask_fire": [8, 10, 12, 12],
	"flask_frost": [6, 8, 10, 12], "flask_storm": [4, 6, 8, 12], "scroll_ward": [4, 6, 8, 10], "tome_insight": [2, 4, 6, 10],
}
## How many a chest holds for each player, by tier.
const CONSUMABLE_COUNT := {1: [1, 1], 2: [1, 2], 3: [2, 2], 4: [2, 3]}

static func roll(tier: int, rng: RandomNumberGenerator) -> Array:
	tier = clampi(tier, 1, 4)
	var span: Array = CONSUMABLE_COUNT[tier]
	var n := rng.randi_range(int(span[0]), int(span[1]))
	var out := []
	for i in n:
		var total := 0.0
		for k in CONSUMABLES:
			total += float(CONSUMABLES[k][tier - 1])
		var x := rng.randf() * total
		for k in CONSUMABLES:
			x -= float(CONSUMABLES[k][tier - 1])
			if x <= 0.0:
				out.append(k)
				break
	return out

# ---------------------------------------------------------------- the thrown flask

## A flask's flight, from the throw to the burst (FlaskFx's arc takes as long).
const TOSS_T := 0.55
## How far a flask is thrown, and the slack the match server allows on where its thrower stood.
const REACH := 13.0
const SERVER_SLACK := 4.0

## A flask thrown at the pointer (Hero.drink): every peer sees it fly and burst ("toss"); its blow is this game's.
static func throw_flask(h: Hero, base: String, at: Vector3) -> void:
	var b: Dictionary = Data.BASES[base]
	var to := at - h.global_position
	to.y = 0
	to = to.limit_length(REACH)
	var land := h.global_position + to
	land.y = h.game.world.height_at(land.x, land.z)
	var r := float(b["bomb_r"])
	var kind := int(b["bomb"])
	h.fx("run", "toss", {"p": h.global_position + Vector3(0, 1.6, 0), "q": land, "n": kind, "r": r})
	if h.puppet:
		return
	if not h.decides():
		h.game.net.send_skill_make("run", "flask", {"base": base, "at": land})      # (its burst is the server's)
		return
	_burst(h, base, land)

## Match server: a server-run hero's game threw a flask (RunTalents.server_made "flask"), within its reach of where the
## server has them. False when it doesn't add up.
static func server_flask(h: Hero, d: Dictionary) -> bool:
	var base := str(d.get("base", ""))
	if not (Data.BASES.has(base) and Data.BASES[base].has("bomb")) or not d.get("at") is Vector3:
		return false
	if (d["at"] as Vector3).distance_to(h.global_position) > REACH + SERVER_SLACK:
		return false
	_burst(h, base, d["at"])
	return true

## A thrown flask bursts where it lands, on the game that decides its thrower's hits.
static func _burst(h: Hero, base: String, land: Vector3) -> void:
	var b: Dictionary = Data.BASES[base]
	var r := float(b["bomb_r"])
	var kind := int(b["bomb"])
	var amount := ProcHits.weapon(h) * float(b["bomb_pct"]) / 100.0
	h.get_tree().create_timer(TOSS_T).timeout.connect(func():
		if not is_instance_valid(h) or h.game == null or h.game.world == null:
			return
		for e in h.game.enemies_near(land, r):
			if e.dead or ServerRules.friend(h, e):
				continue
			ProcHits.deal(h, e, amount * (1.0 if ProcHits.monster(e) else 0.5), ["fire", "frost", "storm"][kind])
			if e.dead:
				continue
			match kind:
				0: e.ignite(amount * 0.2, 3.0)
				1:
					if ProcHits.monster(e):
						ProcHits.freeze(h, e, 2.0)
					else:
						e.chill(0.4, 2.0)
	)
