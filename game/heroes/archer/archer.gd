class_name Archer
extends RefCounted
## The archer (the bow class, Jace's; its name is still his to choose). With a bow in his hands his attack
## shoots: Hero.swipe_attack and free_attack come here (`shoot`), he stops at RANGE from a clicked foe
## (Hero.reach) and keeps shooting while the button is held. His skills (Data.SKILLS "cls": "archer"):
##   Piercing Shot: a heavy arrow through every enemy in a line;
##   Volley: arrows into the sky that rain on the cursor, hitting all within reach again and again;
##   Thunderstep (id "snare", kept for old saves' bindings and talents; jj's pick, in place of Storm Snare): he
##     backflips away from the pointer, driving a thunderstone into a gold storm sigil where he stood, which a moment
##     later detonates: everything on it stunned and hurt, lightning chaining on into the nearest others;
##   Spirit Beast: a spectral beast (the lion's body, ghostly) that hunts with him for 30 s, and the
##     class's 12 s battle buff (+40% damage).
## His skills that are objects (Hero.kit, skills/) keep their own state: arrows in flight, the rains, the sigils.
## What is still here lives on the hero (his beasts, the mark), updated
## by `update` and cleared by `clear`. What is seen is raised by fx events (Hero.fx -> ArcherFx), so a
## partner's copy of him (Hero.puppet) shoots, rains, sets traps and runs his wolf too; only his own game
## deals the damage (Enemy.take_damage routes to the host in co-op).
## His body and the bow in his hands: body/archer_body.gd (ArcherBody). His arrows' models: weapon/arrow_model.gd.

const RANGE := 13.0
const ARROW_SPEED := 34.0
const FLIGHT := RANGE + 5.0     # how far an arrow flies before it falls
const HUNTER := Color(0.62, 0.85, 0.75)     # the class's colour: pale spirit-green

## how fast he steps while he looses arrows (of his normal pace): slowed to a careful, aimed walk
const SHOOT_MOVE := 0.36

# ---------------------------------------------------------------- his kit
## The skills that have their own object (docs/content/skills.md): one per hero, made the first time it's needed,
## kept in Hero.kit. The rest are still the functions below, until each moves to its folder.
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"attack": return ArcherShot.new(h, id)
		"pierce": return FireArrow.new(h, id)
		"a_multishot": return ScatterShot.new(h, id)
		"a_explosive": return BlastArrow.new(h, id)
		"a_glacial": return GlacialShard.new(h, id)
		"a_stormshot": return StormShot.new(h, id)
		"volley": return FrostVolley.new(h, id)
		"a_barrage": return ArrowStorm.new(h, id)
		"snare": return Thunderstep.new(h, id)
		"beast": return BeastCommand.new(h, id)
		"a_mark": return HuntersMark.new(h, id)
	return null

# ---------------------------------------------------------------- his ways (ClassSkills' optional hooks)
## His basic attack is the bow shot, when he has a bow.
static func attack(h: Hero, aim: Vector3, keep_target: bool) -> bool:
	if not h.has_bow():
		return false
	shoot(h, aim, keep_target)
	return true

static func reach(h: Hero) -> float:
	return RANGE if h.has_bow() else -1.0

## He runs 10% faster while his Spirit Beast is at his side.
static func pace(h: Hero) -> float:
	return 1.1 if h.beasts.any(func(b) -> bool: return is_instance_valid(b) and not b.dead) else 1.0

## Loosing arrows, he steps slowly with the bow drawn.
static func attack_pace(h: Hero) -> float:
	return SHOOT_MOVE if (h.has_bow() and h.atk_style == "bow") else -1.0

static func posed(h: Hero, st: Dictionary) -> void:
	ArcherBody.pose_bow(h, st)

## A partner's copy of him runs his wolf too (and its commands come as fx events).
static func puppet_update(h: Hero, delta: float) -> void:
	update(h, delta)

## The match server's copy of him (ServerRules.update) runs the wolf that bites.
static func server_update(h: Hero, delta: float) -> void:
	SpiritBeast.keep(h, delta)

static func weapon_hand(h: Hero, J: Dictionary) -> Node3D:
	return ArcherBody.weapon_hand(h, J)

# ---------------------------------------------------------------- the bow
## Loose an arrow toward aim (an attack: the draw, the release on the pose's impact frame).
static func shoot(h: Hero, aim: Vector3, keep_target: bool) -> void:
	if h.atk_t >= 0.0:
		return
	if not keep_target:
		h.target = null
	else:
		# a shot at the foe he walked up to: he stands his ground
		h.moving = false
		h.path = PackedVector3Array()
	h.atk_aim = assist(h, aim)
	h.atk_target = null
	h._face(h.atk_aim - h.global_position)
	h._start_attack("bow")

## Aim help: an enemy near the point aimed at is the one aimed at.
static func assist(h: Hero, aim: Vector3) -> Vector3:
	var best = null
	var bd := 2.6
	for e in h.game.enemies_near(aim, 2.6):
		var d: float = Vector2(e.global_position.x - aim.x, e.global_position.z - aim.z).length()
		if not e.dead and d < bd:
			bd = d
			best = e
	return best.global_position if best != null else aim

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## ClassSkills: nothing to check before a shot.
static func can_cast(_h: Hero, _id: String, _aim: Vector3) -> bool:
	return true

## One of his skills holds him in place (mid-Thunderstep his feet are the vault's).
static func rooted(h: Hero) -> bool:
	for sk in h.kit.values():
		if sk.rooted():
			return true
	return false

## His wolf and arrows stay through death (the wolf rises again on its own, SpiritBeast.keep).
static func died(_h: Hero) -> void:
	pass

## The string's twang on the release (Volley's flight a little lower); `at` = seconds to the impact frame.
static func sound(h: Hero, skill: String, at: float) -> bool:
	if h.atk_style != "bow":
		return false
	# (the Fire Arrow's whoosh of flame goes with it: ArrowFx "release" layers land with the arrow's "loose" event)
	Sfx.play_synced("bow", at, -3.0, 0.85 if skill == "volley" else (0.92 if skill == "pierce" else 1.0))
	return true

## The release (Hero._impact): true when it was the archer's.
static func impact(h: Hero) -> bool:
	if not h.is_archer():
		return false
	if h.atk_skill == "" and h.atk_style != "bow":
		return false
	var s := skill(h, h.atk_skill if h.atk_skill != "" else "attack")
	if s == null:
		return false
	s.impact()
	return true

## Shatter (Frost): the chilled take 20% more from his arrows.
static func shatter(h: Hero, e) -> float:
	return 1.2 if h.talent("frost_shatter") > 0.0 and e.chill_t > 0.0 else 1.0

# ---------------------------------------------------------------- every frame
static func update(h: Hero, delta: float) -> void:
	SpiritBeast.keep(h, delta)
	# his skills that are objects (Hero.kit): arrows in flight, the rains, the sigils; on his own game only, since a partner's
	# copy of him only shows them
	if not h.puppet:
		for sk in h.kit.values():
			sk.update(delta)

static func clear(h: Hero) -> void:
	for sk in h.kit.values():
		sk.clear()
	h.kit.clear()
	ArcherArrowFx.clear(h)
	ArrowFx.end_draw(h)
	FrostVolleyRainFx.clear(h)
	FrostVolleyFx.clear(h)
	ThunderstepFx.clear(h)
	for b in h.beasts:
		if is_instance_valid(b):
			b.dismiss()
	h.beasts.clear()
