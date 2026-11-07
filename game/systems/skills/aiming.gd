class_name Aiming
extends Node
## Click to cast for area skills (League of Legends' "normal cast"; Blaine and JJ). An area skill (one whose data has
## "aoe": its area lands centred on the aimed spot) is armed by its key instead of cast: nothing is spent, he keeps
## moving, and AimIndicator shows its range round him and where it would land. The left click casts it there through
## Hero.use_skill, the same as a quick cast (mana and cooldown are spent then). Esc or its key again lets it go;
## another skill's key lets it go and does that key's own thing. The setting ("Quick cast") casts every skill on its
## key, as before. Every other skill casts on its key either way. Only the local player's game aims; this decides,
## AimIndicator draws.
##
## A skill's "aoe": {"r": <the number its area's radius is>, "grow": <a rite key that widens it, in %>}. "r" names the
## number its rules hit with, never a copy: a key of its codex "k" (Skill.val), or Class.CONSTANT while the number is
## still in its code.

const SECTION := "controls"
const KEY := "aoe_click_cast"

var game: Node
var click_cast := true          # the setting: false = quick cast (every skill on its key)
var skill := ""                 # the armed skill ("" = not aiming)

func _init(g: Node) -> void:
	game = g
	name = "Aiming"
	click_cast = bool(g._load_setting(SECTION, KEY, true))

func set_click_cast(on: bool) -> void:
	click_cast = on
	game._save_setting(SECTION, KEY, on)
	if not on:
		cancel()

func armed() -> bool:
	return skill != ""

func cancel() -> void:
	skill = ""

## Is this an area skill that click to cast arms?
static func is_area(id: String) -> bool:
	return Data.skill_def(id).get("aoe") is Dictionary

## How far off the skill can land (its "range": the ring round him, and Hero.skill_aim's clamp).
static func reach(id: String) -> float:
	return float(Data.skill_def(id).get("range", 0.0))

## Its area's radius for this hero: the number its rules hit with, widened by his rites ("grow").
static func radius(h: Hero, id: String) -> float:
	var a = Data.skill_def(id).get("aoe")
	if not a is Dictionary:
		return 0.0
	var r := base_radius(id)
	var grow := str(a.get("grow", ""))
	if grow != "" and h != null:
		r *= 1.0 + h.talent(grow) / 100.0
	return r

## The radius its "aoe" "r" names, before rites (0 when it names nothing).
static func base_radius(id: String) -> float:
	var a = Data.skill_def(id).get("aoe")
	if not a is Dictionary:
		return 0.0
	var where := str(a.get("r", ""))
	if where.contains("."):
		return _constant(where)
	return Skill.num(id, where, 0.0)

static var _consts := {}

## A constant of a named script class ("Plague.CLOUD_R"), as a number (0 when there is none).
static func _constant(path: String) -> float:
	if _consts.has(path):
		return _consts[path]
	var v := 0.0
	var cls := path.get_slice(".", 0)
	var cname := path.get_slice(".", 1)
	for c in ProjectSettings.get_global_class_list():
		if str(c["class"]) == cls:
			var s: Script = load(str(c["path"]))
			var got = s.get_script_constant_map().get(cname) if s != null else null
			if got is float or got is int:
				v = float(got)
	_consts[path] = v
	return v

## A skill's button went down (`first`) or is still held: a key (Q E R F G V), or a mouse button (`key` false: a skill
## there is cast by its own click, at the pointer). True when click to cast took it: it armed the skill, let the aim
## go, or refused it with the cast's own message. False: the caller does what it always did.
func press(id: String, first: bool, key := true) -> bool:
	var area := click_cast and key and is_area(id)
	if not first:
		return area      # (held: an area skill neither re-arms nor casts on its own)
	if armed():
		var was := skill
		cancel()
		if was == id:
			return true      # its key again: let it go
	if not area:
		return false
	var h: Hero = game.hero
	if h == null or h.dead or h.arena_waiting() or h.skill_denied(id):
		return true
	skill = id
	return true

## Where the armed skill would land with the pointer at `cursor` (the cast's own clamp, Hero.skill_aim).
func landing(cursor: Vector3) -> Vector3:
	return game.hero.skill_aim(skill, cursor)

## Is the pointer within the armed skill's range?
func in_reach(cursor: Vector3) -> bool:
	var to: Vector3 = (cursor - game.hero.global_position) * Vector3(1, 0, 1)
	return to.length() <= reach(skill) + 0.01

## The left click: casts the armed skill at the pointer, the same as a quick cast. Still armed when he was in the
## middle of another skill (click again once it is done); let go otherwise. True when it was cast.
func confirm(cursor: Vector3) -> bool:
	if not armed():
		return false
	var h: Hero = game.hero
	var id := skill
	var ok := h.use_skill(id, h.skill_aim(id, cursor))
	if ok or not (h.atk_t >= 0.0 and h.atk_skill != "" and not h.dead):
		cancel()
	return ok

## Lets the aim go when it can't hold: he died or changed class, the game paused, a panel or a loading screen came up.
func _process(_delta: float) -> void:
	if not armed():
		return
	var h: Hero = game.hero
	if h == null or h.dead or not game.playing or game.paused or game.loading.visible or game.ui.any_panel_open() \
			or not _his(h, skill):
		cancel()

static func _his(h: Hero, id: String) -> bool:
	for s in h.skill_list() + Data.shared_skills():
		if s["id"] == id:
			return true
	return false
