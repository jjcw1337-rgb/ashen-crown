class_name WarlockHex
extends Skill
## The Warlock's three directions (Blaine, 2026-11-06; design in data/codex/heroes/warlock.json, the Hero Codex):
##   Corruption: curses (damage over time) that stack, grow with every curse on a foe and how long it has been cursed,
##     and Reckoning, a curse that deals as much as all the others.
##   Fear: Terrify, the Dread Totem, the Void Wisp and Eclipse Bloom. Feared monsters cower (stunned: the server owns
##     their AI, and the stun is the one message every server already understands); a feared player really runs
##     (PvpStatus "fear", through the server, diminishing returns). Feared or bound foes take more from her spells.
##   Drain: Drain Life, Leech Bolt, Thornlash and Soul Feast; healing past full life can harden into a shield.
## This is what her skills share, one per hero, first in her kit (WarlockSkills.hex) so it beats before them:
##   rules (here, or on the match server's copy of her): her curses on foes and their ticks (`dots`, each curse's
##     own numbers and ways in its skill: WarlockCurse), how long each foe has been cursed, who is frightened;
##   her own game: the shield (on the server's copy, only whether her game says she has one: Undying Hunger).
## It reaches monsters and players through the usual calls (Enemy.take_damage / stun / slow, PvpStatus.send). What is
## seen goes out as fx events (WarlockHarrowFx), never per frame. Her spells' numbers are in their codex "k"; the
## fears' shared ones in Terrify's (feared_more, pvp_k, pvp_max), the shield's in Soul Feast's (shield_fade, shield_melt).
## Rite keys (Hero.talent) her skills read: RITE_KEYS; the codex lets rites made of them (and the shared stats) be offered.

const RITE_KEYS := ["dot_flat", "dot_dur", "dot_heal", "dot_echo", "fear_dur", "dmg_feared", "fear_spread", "fear_kill",
	"fear_root", "overheal_shield", "drain_execute", "shield_fork"]
## The new kit's skills (her three directions; Drain Life and the other first skills are WarlockSkills' too).
const IDS := ["w_corruption", "w_malediction", "w_unending", "w_festering", "w_leeching", "w_reckoning",
	"w_terrify", "w_effigy", "w_darkwind", "w_crowstorm", "w_leechbolt", "w_harvest", "w_soulfeast"]
## The curse's tint on the numbers it deals.
const CURSE_TINT := Color(0.72, 0.95, 0.4)
const SHADOW_TINT := Color(0.78, 0.6, 1.0)

## Rules: her curses on foes, [{e, id, per, t, tick, fester}] (per: a tick's share; t: seconds left).
var dots: Array = []
## Rules: a foe's instance id -> the game time it was first cursed without a break (Unending Rot).
var since := {}
## Rules: a foe's instance id -> {e, until, src, spread}: frightened until.
var feared := {}
## Rules: the foes Contagious Panic has passed to (once each).
var spread := {}
## Her own game: the ward healing past full life hardened into (on the server's copy: >0 while her game has one).
var shield := 0.0
var shield_shown := 0.0
var _ward_on := false

static func has(skill_id: String) -> bool:
	return skill_id in IDS

## Game seconds (GameClock.now: frame deltas added up), so fears and "cursed for N s" follow the game's clock.
static func _now() -> float:
	return GameClock.now()

static func _alive(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead

# ---------------------------------------------------------------- damage (rules)
## A spell's 100%: grows with level and the weapon, like Blight Bolt's.
func spell() -> float:
	var h := hero
	return (12.0 + h.level * 4.0 + (h.dmg_min + h.dmg_max) * 0.5) * h.buff_mult()

## Feared or bound foes take this much more from her spells (Terrify's "feared_more", Nightmare Fuel's more).
func feared_k() -> float:
	return 1.0 + (Skill.num("w_terrify", "feared_more", 20.0) + hero.talent("dmg_feared")) / 100.0

func is_feared(e) -> bool:
	if not _alive(e):
		return false
	var f = feared.get(e.get_instance_id())
	return f != null and float(f["until"]) > _now()

## Spell damage `k` of skill `skill_id` on `e`: her talents for it, and more on a feared or bound foe.
func amount(skill_id: String, k: float, e = null) -> float:
	var v := spell() * k * hero.dmg_mult(skill_id)
	if e != null and (is_feared(e) or (_alive(e) and e.stun_t > 0.0)):
		v *= feared_k()
	return v

## A spell's blow on e (no crits: her spells deal their own number), in its tint; on the server, the number goes to
## her screen too.
func hit(e, v: float, tint := CURSE_TINT, soft := false) -> float:
	if not _alive(e) or v <= 0.0:
		return 0.0
	e.dmg_tint = tint
	e.soft_hit = soft
	var dealt: float = e.take_damage(0.0, v, hero.global_position, 0.0, false)
	e.dmg_tint = Color(0, 0, 0, 0)
	e.soft_hit = false
	if hero.puppet and hero.game.net.server:
		hero.game.net.tell_dealt(hero, e.global_position, dealt, false)
	return dealt

## A short stun (Festering Hex's burst): a player is staggered through the server, no longer than its PvP cap.
func stun(e, secs: float) -> void:
	if PvpStatus.is_player(e):
		PvpStatus.send(hero.game, e, "stagger", minf(secs, Skill.num("w_festering", "pvp_stun_s", 0.5)))
	elif _alive(e):
		e.stun(secs)

## Life back for her from skill `src`'s rules (a leech, the feast): her own game takes it (`take`).
func heal(src: String, v: float) -> void:
	if v <= 0.0:
		return
	WarlockSkills.skill(hero, src).give("heal", {"v": v})

# ---------------------------------------------------------------- curses (rules)
func curses_on(e) -> int:
	var n := 0
	for d in dots:
		if d["e"] == e:
			n += 1
	# standing in one of her plague pools counts as a curse
	var bb = hero.kit.get("blight")
	if bb != null and bb.in_pool(e):
		n += 1
	return n

func dot(e, skill_id: String) -> Dictionary:
	for d in dots:
		if d["e"] == e and d["id"] == skill_id:
			return d
	return {}

## Put (or refresh) curse `c` on e.
func curse(c: WarlockCurse, e) -> void:
	var h := hero
	var base_dur := c.val("secs", 10.0)
	var tick := c.val("tick", 0.5)
	var dur := base_dur * (1.0 + h.talent("dot_dur") / 100.0)
	var per := amount(c.id, c.val("dmg", 0.0) / 100.0) / (base_dur / tick)
	var key: int = e.get_instance_id()
	if not since.has(key):
		since[key] = _now()
	var d := dot(e, c.id)
	h.fx(c.id, "curse", {"t": [e], "x": dur})
	if not d.is_empty():
		d["t"] = dur
		d["per"] = per
		if h.talent("dot_echo") > 0.0:
			_echo(e)
		return
	dots.append({"e": e, "id": c.id, "per": per, "t": dur, "tick": tick, "fester": c.val("every", 5.0)})

## Echoing Corruption: every curse on e ticks once, now.
func _echo(e) -> void:
	for d in dots.duplicate():
		if d["e"] == e:
			_tick(d)

## How long e has carried at least one of her curses without a break.
func afflicted(e) -> float:
	var s = since.get(e.get_instance_id())
	return 0.0 if s == null else _now() - float(s)

func _curse_of(d: Dictionary) -> WarlockCurse:
	return WarlockSkills.skill(hero, str(d["id"])) as WarlockCurse

## What one tick of curse d deals (its curse's own way: WarlockCurse.tick_amount).
func tick_amount(d: Dictionary) -> float:
	return _curse_of(d).tick_amount(d)

func _tick(d: Dictionary) -> void:
	var h := hero
	var e = d["e"]
	if not _alive(e):
		return
	var v := tick_amount(d)
	if v > 0.0:
		if is_feared(e) or e.stun_t > 0.0:
			v *= feared_k()
		var dealt := hit(e, v, CURSE_TINT, true)
		_curse_of(d).ticked(d, dealt)
	if h.talent("dot_heal") > 0.0 and randf() * 100.0 < h.talent("dot_heal"):
		heal(str(d["id"]), h.max_life * 0.01)

func _update_dots(delta: float) -> void:
	var live := {}
	for d in dots.duplicate():
		var e = d["e"]
		if not _alive(e) or float(d["t"]) <= 0.0:
			dots.erase(d)
			continue
		d["t"] -= delta
		d["tick"] -= delta
		if d["tick"] <= 0.0:
			d["tick"] += _curse_of(d).val("tick", 0.5)
			_tick(d)
		if _alive(e):
			_curse_of(d).beat(d, delta)
		if _alive(e):
			live[e.get_instance_id()] = true
	for k in since.keys():
		if not live.has(k):
			since.erase(k)

# ---------------------------------------------------------------- fear (rules)
## Frighten e for `secs` (the Haunting rite adds to it), by skill `src`.
func fear(src: String, e, secs: float) -> void:
	if not _alive(e) or e.get("pvp_obj"):
		return
	var h := hero
	secs += h.talent("fear_dur")
	if PvpStatus.is_player(e):
		PvpStatus.send(h.game, e, "fear", minf(secs * Skill.num("w_terrify", "pvp_k", 70.0) / 100.0, Skill.num("w_terrify", "pvp_max", 1.2)), {"p": h.global_position})
	else:
		e.stun(secs)
	feared[e.get_instance_id()] = {"e": e, "until": _now() + (secs * (0.3 if e.boss else 1.0)), "src": src}
	h.fx(src, "fear", {"t": [e], "x": secs})

func _update_fears() -> void:
	var h := hero
	var now := _now()
	for k in feared.keys():
		var f: Dictionary = feared[k]
		var e = f["e"]
		if e == null or not is_instance_valid(e):
			feared.erase(k)
			continue
		if e.dead:
			# Dread Harvest: a foe that died afraid gives her mana and Terrify's time back (on her own game)
			if h.talent("fear_kill") > 0.0:
				WarlockSkills.skill(h, str(f["src"])).give("dread", {"k": h.talent("fear_kill")})
			feared.erase(k)
			continue
		if float(f["until"]) <= now:
			feared.erase(k)
			# Paralysing Terror: rooted where the fear ends
			if h.talent("fear_root") > 0.0:
				if PvpStatus.is_player(e):
					PvpStatus.send(h.game, e, "snare", 1.0, 1.0)
				else:
					e.slow(1.0, 1.0)
				h.fx(str(f["src"]), "root", {"t": [e]})
			continue
		# Contagious Panic: running into another frightens it for half a second (once each)
		if h.talent("fear_spread") > 0.0 and not bool(f.get("spread", false)):
			for o in h.game.enemies_near(e.global_position, 1.8):
				if o != e and foe(o) and not feared.has(o.get_instance_id()) and not spread.has(o.get_instance_id()):
					spread[o.get_instance_id()] = true
					fear("w_terrify", o, 0.5)
					if feared.has(o.get_instance_id()):
						feared[o.get_instance_id()]["spread"] = true

# ---------------------------------------------------------------- her own game: life back, the shield
## What her rules gave her (WarlockSpell.given): "heal" {v}; "dread" {k: Dread Harvest's stacks}.
func take(kind: String, data: Dictionary) -> void:
	var h := hero
	match kind:
		"heal":
			healed(float(data.get("v", 0.0)))
		"dread":
			var k := float(data.get("k", 0.0))
			h.mana = minf(h.max_mana, h.mana + 15.0 * k)
			if h.cds.has("w_terrify"):
				h.cds["w_terrify"] = maxf(0.0, float(h.cds["w_terrify"]) - 2.0 * k)

## Heal her; past full life it can harden into a shield (Blood Ward, the Soul Feast, Undying Hunger's).
func healed(v: float) -> void:
	var h := hero
	if v <= 0.0 or h.dead:
		return
	var room := maxf(0.0, h.max_life - h.life)
	h.life = minf(h.max_life, h.life + v)
	var over := v - room
	var sf = h.kit.get("w_soulfeast")
	var pct := h.talent("overheal_shield") + (Skill.num("w_soulfeast", "shield", 30.0) if sf != null and sf.casting else 0.0)
	if over > 0.0 and pct > 0.0:
		shield = minf(h.max_life * pct / 100.0, shield + over)
		_show_shield()
	h.stats_changed.emit()

## Hero.take_hit (ClassSkills.absorb): the shield soaks the blow first.
func absorb(dmg: float) -> float:
	if shield <= 0.0:
		return dmg
	var soak := minf(shield, dmg)
	shield -= soak
	_show_shield()
	return dmg - soak

## The shield's look follows its size in steps (an event only when it changes by a tenth of her life, or breaks).
## When her skills' rules run on the match server, its copy of her is told whether she has one (Undying Hunger).
func _show_shield() -> void:
	var h := hero
	var frac := shield / maxf(1.0, h.max_life)
	var was := shield_shown
	if (frac <= 0.0 and was > 0.0) or absf(frac - was) >= 0.1 or (frac > 0.0 and was <= 0.0):
		shield_shown = frac
		h.fx("drain", "shield", {"x": frac})
	if (shield > 0.0) != _ward_on:
		_ward_on = shield > 0.0
		if not deals():
			WarlockSkills.skill(h, "drain").make("ward", {"on": _ward_on})

# ---------------------------------------------------------------- every frame
func update(delta: float) -> void:
	if not dots.is_empty() or not since.is_empty():
		_update_dots(delta)
	if not feared.is_empty():
		_update_fears()
	var h := hero
	if not h.puppet and shield > 0.0 and h.combat_t > Skill.num("w_soulfeast", "shield_fade", 5.0):
		shield = maxf(0.0, shield - h.max_life * Skill.num("w_soulfeast", "shield_melt", 10.0) / 100.0 * delta)
		_show_shield()

func clear() -> void:
	if shield > 0.0:
		shield = 0.0
		_show_shield()
	dots.clear()
	since.clear()
	feared.clear()
	spread.clear()

func died() -> void:
	clear()
