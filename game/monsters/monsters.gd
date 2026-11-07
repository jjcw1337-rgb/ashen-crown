class_name Monsters
extends RefCounted
## The monster registry. Every monster folder (game/monsters/<monster>/) has a card, its monster.gd, the way every
## hero has its class script: it says which kinds (Data.ENEMIES keys) it is and what of its own it has. Enemy
## (game/monsters/enemy.gd: life, statuses, movement, the shared melee and ranged fighting) asks here, the registry asks
## the kind's card, and when the card has nothing to say the shared way is used. No monster is named in this file:
## a new monster is a folder with its card and one line in CARDS.
##
## A card declares (all but KINDS optional):
##   const KINDS := [...]           the kinds it is
##   const RIGS := {mesh: {glb, height, layout}}   its Meshy models' rigs, by the def's "mesh" (MeshyMonster)
##   const PERSONALITY := "goblin"  its Anim personality (a String, or {kind: String, "*": default}); else "warrior"
##   const MOVES := [...]           the special moves it plays itself (Enemy.special), through begin / during /
##                                  impact / finish below
##   const FALL := "side"           a four-legged body rolls onto its side when it dies (else it falls back)
##   static func build_rig(kind, variant) -> Node3D    a body of its own (null: the shared one)
##   static func pose_rig(rig, st, height) -> bool     poses that body (false: Anim.pose)
##   static func model_paths(kind) -> PackedStringArray  the files its own body loads (a zone loads them ahead)
##   static func brain(e) -> BossBrain                 a boss's brain
##   static func combat(e, delta, hero, to, dist) -> Variant   its own fighting (null: the shared)
##   static func idle(e, delta) -> Variant             its own idle before it notices anyone (null: it wanders)
##   static func on_setup(e) / on_placed(e)            its own start, once its body is built / once it stands home
##   static func begin(e, sp) / during(e, a, hero) / impact(e, hero, dist) / finish(e)   its MOVES
##   static func fx(e, ev) -> bool                     draws its own fx events, every game (true: it was one)
##   static func fall(e, f, delta)                     how its body goes down (f: 0 -> 1 over 0.6 s)
##   static func rest_overlay(e) -> Material, net_lift(e) -> float, heavy_steps(e) -> bool

const CARDS := [
	"res://game/monsters/hrimgar/monster.gd",
	"res://game/monsters/mossbeard/monster.gd",
	"res://game/monsters/king_grubb/monster.gd",
	"res://game/monsters/bear/monster.gd",
	"res://game/monsters/feral/monster.gd",
	"res://game/monsters/hollow_sloth/monster.gd",
	"res://game/monsters/fallen/monster.gd",
	"res://game/monsters/lion/monster.gd",
	"res://game/monsters/zombie/monster.gd",
	"res://game/monsters/treant/monster.gd",
	"res://game/monsters/dark_elf/monster.gd",
	"res://game/monsters/troll_shaman/monster.gd",
	"res://game/monsters/goblin_guard/monster.gd",
	"res://game/monsters/skeleton_archer/monster.gd",
	"res://game/monsters/bandit/monster.gd",
	"res://game/monsters/gladiator/monster.gd",
	"res://game/monsters/champion/monster.gd",
	"res://game/monsters/spider/monster.gd",
]

static var _by_kind: Dictionary = {}     # kind -> its card (Script)
static var _fns: Dictionary = {}         # card -> {function name: true}
static var _consts: Dictionary = {}      # card -> its constants

static func _index() -> void:
	if not _by_kind.is_empty():
		return
	for p in CARDS:
		var c: Script = load(p)
		var fns: Dictionary = {}
		for f in c.get_script_method_list():
			fns[str(f["name"])] = true
		_fns[c] = fns
		_consts[c] = c.get_script_constant_map()
		for k in _consts[c].get("KINDS", []):
			assert(not _by_kind.has(k), "%s is on two cards" % k)
			_by_kind[k] = c

## The card of a kind (null: a kind no card names, so it's all the shared way).
static func card(kind: String) -> Script:
	_index()
	return _by_kind.get(kind, null)

## Every kind with a card.
static func kinds() -> Array:
	_index()
	return _by_kind.keys()

static func _can(c: Script, fn: String) -> bool:
	return c != null and (_fns[c] as Dictionary).has(fn)

static func _const(c: Script, key: String, fallback: Variant) -> Variant:
	return (_consts[c] as Dictionary).get(key, fallback) if c != null else fallback

static func _of(e: Enemy, fn: String) -> Script:
	var c := card(e.kind)
	return c if _can(c, fn) else null

# ---------------------------------------------------------------- its body

## A kind's body, as Enemy.setup gives it: the card's own, else its Meshy model (the card's RIGS by the def's
## "mesh"), else a code-built skeleton (the def's "skin") or the crawler / humanoid. variant: the Feral's model.
static func build_rig(kind: String, variant := 1) -> Node3D:
	var d: Dictionary = Data.ENEMIES[kind]
	var look: Dictionary = d["look"]
	var c := card(kind)
	var r: Node3D = null
	if _can(c, "build_rig"):
		r = c.call("build_rig", kind, variant)
	if r == null:
		var rig: Dictionary = (_const(c, "RIGS", {}) as Dictionary).get(str(d.get("mesh", "")), {})
		if not rig.is_empty() and MeshyMonster.ok(rig):
			r = MeshyMonster.build(str(d["mesh"]), rig, look)
	if r == null and d.has("skin"):
		r = SkeletonModel.build(d["skin"])
		var h: float = look.get("height", look.get("size", 1.0))
		if absf(h - 1.0) > 0.01:
			r.scale = Vector3.ONE * h
	if r == null:
		r = Models.crawler(look) if d["rig"] == "crawler" else Models.humanoid(look)
	r.set_meta("kind", kind)
	return r

## Poses any monster body from the enemy state (Enemy._pose): its card's own, else the shared animation.
static func pose_rig(r: Node3D, st: Dictionary, height: float) -> void:
	var c := card(str(r.get_meta("kind", "")))
	if _can(c, "pose_rig") and bool(c.call("pose_rig", r, st, height)):
		return
	Anim.pose(r, st)

## The model files a kind's body loads, so a zone can load them on worker threads before it spawns its monsters
## (Game.load_zone: each first load was 23-34 ms on the main thread).
static func model_paths(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not Data.ENEMIES.has(kind):
		return out
	var c := card(kind)
	var paths := PackedStringArray()
	if _can(c, "model_paths"):
		paths = c.call("model_paths", kind)
	else:
		var rig: Dictionary = (_const(c, "RIGS", {}) as Dictionary).get(str(Data.ENEMIES[kind].get("mesh", "")), {})
		if rig.has("glb"):
			paths.append(str(rig["glb"]))
	for p in paths:
		if ResourceLoader.exists(p):
			out.append(p)
	return out

## How its body carries itself (Anim's personalities: the gait, the idle, the swing).
static func personality(kind: String) -> String:
	var p: Variant = _const(card(kind), "PERSONALITY", "warrior")
	if p is Dictionary:
		return str((p as Dictionary).get(kind, (p as Dictionary).get("*", "warrior")))
	return str(p)

## Its body going down, f: 0 -> 1 over the first 0.6 s (Enemy's death): its card's own, a four-legged roll onto the
## side, a crawler's flip, or falling back.
static func fall(e: Enemy, f: float, delta: float) -> void:
	var c := card(e.kind)
	if _can(c, "fall"):
		c.call("fall", e, f, delta)
	elif e.rig.has_meta("crawler"):
		e.rig.rotation.z = f * PI
		e.rig.position.y = f * 0.4 * e.height
	elif _const(c, "FALL", "") == "side":
		e.rig.rotation.x = 0.0
		e.rig.rotation.z = f * f * 1.35
	else:
		e.rig.rotation.x = f * f * 1.45

## The overlay its body wears between hit flashes (null: none).
static func rest_overlay(e: Enemy) -> Material:
	var c := _of(e, "rest_overlay")
	return c.call("rest_overlay", e) if c != null else null

## How far above the ground a client draws it (Enemy's network follow).
static func net_lift(e: Enemy) -> float:
	var c := _of(e, "net_lift")
	return float(c.call("net_lift", e)) if c != null else 0.0

## A body that shakes the ground as it walks.
static func heavy_steps(e: Enemy) -> bool:
	var c := _of(e, "heavy_steps")
	return c != null and bool(c.call("heavy_steps", e))

# ---------------------------------------------------------------- its rules

## Its own start, once its body is built (Enemy.setup).
static func on_setup(e: Enemy) -> void:
	var c := _of(e, "on_setup")
	if c != null:
		c.call("on_setup", e)

## Once it stands where it lives (the end of Enemy.setup).
static func on_placed(e: Enemy) -> void:
	var c := _of(e, "on_placed")
	if c != null:
		c.call("on_placed", e)

## A boss's brain, or null.
static func brain_for(e: Enemy) -> BossBrain:
	var c := _of(e, "brain")
	return c.call("brain", e) if c != null else null

## Its own way of fighting (Enemy._think_combat), or null for the shared one.
static func combat(e: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Variant:
	var c := _of(e, "combat")
	return c.call("combat", e, delta, hero, to, dist) if c != null else null

## Its own idle before it notices anyone, or null for the shared wander.
static func idle(e: Enemy, delta: float) -> Variant:
	var c := _of(e, "idle")
	return c.call("idle", e, delta) if c != null else null

## The card that plays move `sp` for this monster (its MOVES), or null for the shared moves Enemy plays itself
## (slam, summon, nova, volley).
static func _mover(e: Enemy, sp: String) -> Script:
	var c := card(e.kind)
	return c if sp in _const(c, "MOVES", []) else null

static func begin_move(e: Enemy, sp: String) -> void:
	var c := _mover(e, sp)
	if c != null:
		c.call("begin", e, sp)

static func during_move(e: Enemy, a: float, hero: Node3D) -> void:
	var c := _mover(e, e.special)
	if c != null:
		c.call("during", e, a, hero)

## True if the move was its card's (the card landed it).
static func impact_move(e: Enemy, hero: Node3D, dist: float) -> bool:
	var c := _mover(e, e.special)
	if c == null:
		return false
	c.call("impact", e, hero, dist)
	return true

static func finish_move(e: Enemy) -> void:
	var c := _mover(e, e.special)
	if c != null:
		c.call("finish", e)

## Its own fx event, drawn on every game (Enemy.special_fx): true if it was one.
static func fx(e: Enemy, ev: String) -> bool:
	var c := _of(e, "fx")
	return c != null and bool(c.call("fx", e, ev))
