class_name Doug
extends RefCounted
## Doug (Blaine's tier-1 character and the pilot of the character workflow): the stubby circus brawler, a roast
## drumstick and a bag of tricks. Every one of his skills (Data.SKILLS "cls": "doug") is an object in Hero.kit
## (skills/<skill>/), holding its own state and reading its numbers from his codex (data/codex/heroes/doug.json "k"):
##   attack     Drumstick Smack: his drumstick blows (Hero's swing; its hits are his skill's)
##   pie        Cream Pie: a lobbed pie; the first foe near where it lands takes the hit and is Pied
##   peels      Banana Peels: three on the ground ahead, each a slip for the first to step on it
##   slide      Pratfall Slide: a belly-slide, striking and shoving the foes in the way
##   doppel     Doppel-Doug: he is unseen for a moment while a balloon double runs off; a foe that reaches it pops it
##   juggle     Pin Juggle: five flaming pins, each bouncing on to two more foes
##   bounce     Big Top Bounce: a leap to the cursor and a belly-flop that launches
##   car        Clown Car: a few seconds of driving and ramming, then mini clowns pie the nearest foes
##   u_barrage, u_bonanza, u_cannon: a run's Pie Barrage, Banana Bonanza and Human Cannonball
## What only his skills share is in shared/ (the pies in flight, the belly-flop). What is seen is an fx event (Hero.fx
## -> DougFx, on every game). In a Battlegrounds, Arena or Sandbox match his skills run on the server (ServerRules):
## his game moves him and shows the throw, and the server's copy of him deals the hits (Skill.make). Crowd control
## on another player goes through the server (`cc`: Net.send_pvp_effect).
## His body and drumstick: body/doug_body.gd (DougBody).

const ACCENT := Color(1.0, 0.82, 0.2)          # his colour: the suit's mustard yellow
## His skills' attack styles (no weapon trail on a throw or a trick; partners see the style, not the skill)
const SKILL_STYLES := ["pie", "peels", "slide", "doppel", "juggle", "bounce", "car"]
## The drumstick's blows (Hero's right-click combo and its free swing): his Drumstick Smack lands them.
const SWING_STYLES := ["swipe1", "swipe2", "swipe3", "over", "back", "thrust"]

# ---------------------------------------------------------------- his kit
## His skill objects (docs/content/skills.md): one per skill id, made the first time it's needed, kept in Hero.kit.
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"attack": return DrumstickSmack.new(h, id)
		"pie": return CreamPie.new(h, id)
		"peels": return BananaPeels.new(h, id)
		"slide": return PratfallSlide.new(h, id)
		"doppel": return DoppelDoug.new(h, id)
		"juggle": return PinJuggle.new(h, id)
		"bounce": return BigTopBounce.new(h, id)
		"car": return ClownCar.new(h, id)
		"u_barrage": return PieBarrage.new(h, id)
		"u_bonanza": return BananaBonanza.new(h, id)
		"u_cannon": return HumanCannonball.new(h, id)
	return null

# ---------------------------------------------------------------- his ways (ClassSkills' optional hooks)
## In his clown car he drives at its speed.
static func pace(h: Hero) -> float:
	var car = h.kit.get("car")
	return car.speed() if car != null else 1.0

## In his clown car nothing stops him: blows land, their stuns and slows don't (Hero.take_hit).
static func unstoppable(h: Hero) -> bool:
	var car = h.kit.get("car")
	return car != null and car.driving()

## The match server's copy of him (ServerRules.update): fallen, what ends with him ends there too (his own game:
## `died`).
static func server_update(h: Hero, _delta: float) -> void:
	if h.dead:
		for sk in h.kit.values():
			sk.died()

# ---------------------------------------------------------------- ClassSkills
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var s := skill(h, id)
	return s == null or s.can_cast(aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var s := skill(h, id)
	if s != null:
		s.cast(aim)

## The impact frame (Hero._impact): a skill of his, or a blow of his drumstick. True when it was his.
static func impact(h: Hero) -> bool:
	if not h.is_doug():
		return false
	var id := h.atk_skill
	if id == "":
		if not SWING_STYLES.has(h.atk_style):
			return false
		id = "attack"
	var s := skill(h, id)
	if s == null:
		return false
	s.impact()
	return true

## Every frame on his own game: his skills' pies, peels, slides, doubles, pins and rides.
static func update(h: Hero, delta: float) -> void:
	if h.puppet or not h.is_doug():
		return
	for sk in h.kit.values():
		sk.update(delta)

## Mid-slide and mid-bounce his feet are the skill's.
static func rooted(h: Hero) -> bool:
	if not h.is_doug():
		return false
	for sk in h.kit.values():
		if sk.rooted():
			return true
	return false

static func clear(h: Hero) -> void:
	for sk in h.kit.values():
		sk.clear()
	h.kit.clear()
	h.hidden_t = 0.0

## His ride, his slide, his leap and the pins still to come end with him (the pies, peels and the double stay).
static func died(h: Hero) -> void:
	if h.is_doug():
		for sk in h.kit.values():
			sk.died()
	h.hidden_t = 0.0

static func sound(_h: Hero, skill_id: String, at: float) -> bool:
	match skill_id:
		"pie": Sfx.play_synced("swing_light", at, -2.0)
		"peels": Sfx.play_synced("swing_light", at, -4.0)
		"slide": Sfx.play("swing_heavy" if Sfx.bank.has("swing_heavy") else "swing_light", -4.0, 0.8)
		"juggle": Sfx.play_synced("swing_light", at, -3.0)
		"bounce": Sfx.play_synced("doug_flop", at, 0.0)
		"doppel", "car": return true
		_: return false
	return true

# ---------------------------------------------------------------- shared by his skills
## Crowd control on a foe: a monster stunned or slowed here; another player through the server, which checks it and
## hands it to them as a blow of that kind (Net.send_pvp_effect -> Hero.take_hit "slip", "pied", "quake"). `k` is a
## slow's share (0..1).
static func cc(h: Hero, e, kind: String, secs: float, k := 0.0) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	if int(e.get("pvp_pid")) > 0:
		h.game.net.send_pvp_effect(int(e.pvp_pid), kind, h.global_position)
		return
	match kind:
		"slip", "quake":
			e.stun(secs)
		"pied":
			e.stun(Skill.num("pie", "stun_s", 0.4))
			e.slow(secs, k)
		"slow":
			e.slow(secs, k)
