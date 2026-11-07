class_name PhantomAssault
extends WraithSkill
## Phantom Assault ("phantom", G): claw1's wind-up splits phantoms (afterimages of him) off him that streak through
## the foes ahead in a fan, each tearing everything in its path once (Fourth Rider: one more; Legion: harder), and
## the clip's own strike lands in front of him. The phantoms are Missiles its rules fly (made where his hits are
## decided); every game's look flies its own from the "split" event (PhantomAssaultFx). Codex "k": dmg and spirit
## (each phantom's: % of the weapon's blow and of the spirit-light), phantoms (how many), speed (metres a second),
## spread (degrees between them), strike and strike_spirit (his own strike's), strike_r and strike_arc (its reach and
## half-angle in degrees). How far they go is its "range".

const SPLIT_AT := 0.3       # they split off as the wind-up ends
const TEAR := 1.0           # how close to a foe's edge a phantom tears it

var go := false             # cast, not yet split (his own game)
var phantoms: Array = []    # the rules': Missiles in flight

func cast(_aim: Vector3) -> void:
	go = true
	start("phantom")

## The split as the wind-up ends (his own game); the phantoms fly wherever they were made.
func tick(delta: float) -> void:
	_fly(delta)
	var h := hero
	if not go:
		return
	if not playing():
		go = false
		return
	if h.atk_t / h.atk_dur >= SPLIT_AT:
		go = false
		var n := count()
		h.fx(id, "split", {"d": h.aim_dir(), "n": n})
		make("split", {"p": h.global_position, "d": h.aim_dir(), "n": n})

## How many split off (Fourth Rider: one more).
func count() -> int:
	return int(val("phantoms", 3.0)) + int(hero.talent("phantoms"))

## His own strike, after the phantoms have gone.
func impact() -> void:
	var h := hero
	h.fx(id, "strike", {"y": h.rig.global_rotation.y})
	make("strike", {"p": h.global_position, "d": h.aim_dir()})

## Server: from where it has him, no more of them than he has.
func server_ok(kind: String, d: Dictionary) -> bool:
	if not (kind == "split" or kind == "strike") or not near_him(d.get("p"), 4.0):
		return false
	d["d"] = flat(d.get("d"))
	d["n"] = clampi(int(d.get("n", 1)), 1, count())
	return true

func made(kind: String, d: Dictionary) -> void:
	var h := hero
	var at: Vector3 = d["p"]
	var fwd: Vector3 = d["d"]
	match kind:
		"split":
			var n := int(d.get("n", count()))
			var spread := deg_to_rad(val("spread", 22.0))
			for i in n:
				var m := Missile.new(at, fwd.rotated(Vector3.UP, (float(i) - (n - 1) * 0.5) * spread))
				m.speed = val("speed", 15.0)
				m.left = reach_m(8.0)
				m.pierce = true
				m.reach = TEAR
				m.height = 1.0
				phantoms.append(m)
		"strike":
			var arc := cos(deg_to_rad(val("strike_arc", 70.0)))
			for e in h.game.enemies_near(at, val("strike_r", 3.1)):
				if not foe(e):
					continue
				var to: Vector3 = e.global_position - at
				to.y = 0
				if to.length() < 0.5 or fwd.dot(to.normalized()) > arc:
					h._hit_enemy(e, val("strike", 100.0) / 100.0, 0.5, id, spirit(val("strike_spirit", 30.0)))

func _fly(delta: float) -> void:
	for m in phantoms.duplicate():
		m.step(hero.game, delta, func(e) -> bool: return foe(e), func(e) -> void: _tear(m, e))
		if m.done:
			phantoms.erase(m)

## A phantom tears through a foe.
func _tear(m: Missile, e) -> void:
	var h := hero
	h._hit_enemy(e, val("dmg", 120.0) / 100.0, 0.5, id, spirit(val("spirit", 50.0)))
	if is_instance_valid(e):
		h.fx(id, "hit", {"p": e.global_position + Vector3(0, 1.0 * e.height, 0), "d": m.dir})

func clear() -> void:
	super()
	go = false
	phantoms.clear()
