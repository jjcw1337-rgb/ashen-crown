class_name Plague
extends RefCounted
## The Plague Doctor (class "plague"): a plague physician who wins through disease, deception and position.
##
## Body: the Meshy plague doctor (game/heroes/plague/body/plague_doctor.glb; game/heroes/plague/build/prep_plague_mocap.py) on the
## knight's mocap system (Knight.build_mocap, knight_mocap_rig.gd), like the archer's ranger. Every skill and his
## cane attack play their own whole-body library clip (`ACTS`, keyed by attack style), timed so its release lands
## on Anim.impact_at's frame at any attack speed. What his hands hold (a vial, the reliquary, the seed, the censer)
## and his idle fidget are `hands` and `pose` here.
##
## His skills (Data.SKILLS "cls": "plague"; the PvP kit of 2026-11-01) are one object each (docs/content/skills.md),
## made by `_make` and kept in Hero.kit, each in its folder under skills/ with its rules and its look:
##  Q Pestilence Vial (toxic), E Swarmcraft (swarm), R Corpse Bloom (bloom), F Fog of the Forgotten (fog),
##  G Transfusion (transfusion), V The Last Experiment (experiment), and a run's Miasma (p_miasma), Contagion
##  (p_spread) and Leech Jar (p_leech); his cane's blows are PlagueCane ("attack", skills/cane/).
## His poison, Blight and Fever are shared/plague_affliction.gd (Hero.kit["poison"]). His rules run where
## Skill.deals says (his own game, or the match server's copy of him: ServerRules); what is seen goes through
## Hero.fx and is drawn by PlagueFx (plague_fx.gd) and each skill's look, on every game. Numbers: the codex "k".
##
## PvP (PvpObjects): his bloom, his vat while he cranks it and the creature out of it can be broken by other
## players. Their blows are counted on his own game, as before (`obj_hit`: Net.cl_pvp_obj_hit); the server checks
## each against where his rules have the thing (`obj_pos`).

const GLB := "res://game/heroes/plague/body/plague_doctor.glb"
const CANE_GLB := "res://game/heroes/plague/weapon/cane.glb"

const TOXIC := Color(0.45, 0.95, 0.25)       # the poison's green
const MIASMA := Color(0.32, 0.6, 0.18)
const BRASS := Color(0.85, 0.65, 0.3)
const POISON_TINT := Color(0.55, 1.0, 0.35, 1.0)
const FEVER := Color(0.95, 0.85, 0.35)

## Old saves' bindings of the retired skills become the new ones in their keys (Hero.from_save).
const OLD_IDS := {"volatile": "swarm", "trap": "bloom", "epidemic": "experiment"}

## the whole-body clips, by attack style: [[attack progress, clip fraction], ...] (the release key at
## Anim.impact_at's frame for that style)
const ACTS := {
	# the cane: his own three-blow combo (Hero._swipe: swipe1, swipe2, swipe3; their impacts at 0.4 / 0.42 / 0.47), each
	# with its own clip and its own effect (PlagueCane)
	"swipe1": {"clip": "peck", "frac": true, "keys": [[0.0, 0.12], [0.4, 0.42], [1.0, 0.7]]},
	"swipe2": {"clip": "flick", "frac": true, "keys": [[0.0, 0.15], [0.42, 0.6], [1.0, 0.9]]},
	"swipe3": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.47, 0.85], [1.0, 1.0]]},
	# felling a tree (Harvest): the axe raised in both hands and driven into the trunk, from the censer slam
	"chop": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.55, 0.85], [1.0, 1.0]]},
	"over": {"clip": "peck", "frac": true, "keys": [[0.0, 0.12], [0.5, 0.42], [1.0, 0.7]]},
	"back": {"clip": "flick", "frac": true, "keys": [[0.0, 0.15], [0.48, 0.6], [1.0, 0.9]]},
	"thrust": {"clip": "censer_slam", "frac": true, "keys": [[0.0, 0.3], [0.52, 0.85], [1.0, 1.0]]},
	# Pestilence Vial: a hand to the bandolier, the arm back, the over-shoulder throw, recover
	"pd_flask": {"clip": "throw_flask", "frac": true, "keys": [[0.0, 0.05], [0.3, 0.25], [0.55, 0.42], [1.0, 0.6]]},
	# Swarmcraft: the reliquary held out, the flies pour from it
	"pd_swarm": {"clip": "cast", "frac": true, "keys": [[0.0, 0.08], [0.5, 0.45], [1.0, 0.8]]},
	# Corpse Bloom: down on one knee, the seed driven into the soil
	"pd_bloom": {"clip": "kneel", "frac": true, "keys": [[0.0, 0.05], [0.55, 0.4], [1.0, 0.75]]},
	# Fog of the Forgotten: the censer dashed down at his feet (the hop back is movement)
	"pd_fog": {"clip": "throw_down", "frac": true, "keys": [[0.0, 0.08], [0.45, 0.5], [1.0, 0.85]]},
	# Transfusion: he shudders as the needle goes in
	"pd_transfuse": {"clip": "stagger", "frac": true, "keys": [[0.0, 0.0], [0.45, 0.35], [1.0, 0.8]]},
	# The Last Experiment, stage 1: the vat slammed down; stage 2: cranking it, arms working
	"pd_slam": {"clip": "slam", "frac": true, "keys": [[0.0, 0.05], [0.6, 0.62], [1.0, 0.95]]},
	"pd_crank": {"clip": "cast_charged", "frac": true, "keys": [[0.0, 0.15], [0.25, 0.4], [0.5, 0.55], [0.75, 0.4], [0.97, 0.78], [1.0, 0.85]]},
	# a moment's idle: a vial held up to the light (the class stage's fidget)
	"pd_inspect": {"clip": "inspect", "frac": true, "keys": [[0.0, 0.1], [1.0, 0.75]]},
}
## what his right hand holds while a move plays (from these points until the release; "vial" = Pestilence Vial's glass
## vial with its sloshing liquid, PlagueVialFx.vial, in the next recipe's colour; "reliquary" = Swarmcraft's Meshy
## reliquary, "seed" = Corpse Bloom's Meshy seed-syringe, "censer" = Fog of the Forgotten's Meshy censer until he dashes
## it down), and the moves that need both hands (the cane is put away while they play)
const HELD := {"pd_flask": [0.08, 0.55, "vial"], "pd_inspect": [0.1, 0.9, "vial"], "pd_swarm": [0.05, 0.85, "reliquary"],
	"pd_bloom": [0.1, 0.6, "seed"], "pd_fog": [0.04, 0.45, "censer"]}
const HANDS_FREE := ["pd_flask", "pd_swarm", "pd_bloom", "pd_fog", "pd_transfuse", "pd_slam", "pd_crank", "pd_inspect"]
## Standing about with the cane away for a while, he takes out a vial and peers at it ("pd_inspect", INSPECT_T s),
## every IDLE_EVERY seconds or so.
const IDLE_EVERY := 10.0
const INSPECT_T := 3.2

## His own skills, in bar order, then a run's (the ids his skills script answers for).
const IDS := ["toxic", "swarm", "bloom", "fog", "transfusion", "experiment", "p_miasma", "p_spread", "p_leech"]

# ---------------------------------------------------------------- his kit
## One object per skill (docs/content/skills.md), made the first time it's needed, kept in Hero.kit. "poison" is
## his poison, Blight and Fever (shared/plague_affliction.gd), which his skills' rules share.
static func skill(h: Hero, id: String) -> Skill:
	if not h.kit.has(id):
		var s := _make(h, id)
		if s == null:
			return null
		h.kit[id] = s
	return h.kit[id]

static func _make(h: Hero, id: String) -> Skill:
	match id:
		"attack": return PlagueCane.new(h, id)
		"toxic": return PestilenceVial.new(h, id)
		"swarm": return Swarmcraft.new(h, id)
		"bloom": return CorpseBloom.new(h, id)
		"fog": return FogOfTheForgotten.new(h, id)
		"transfusion": return Transfusion.new(h, id)
		"experiment": return LastExperiment.new(h, id)
		"p_miasma": return Miasma.new(h, id)
		"p_spread": return Contagion.new(h, id)
		"p_leech": return LeechJar.new(h, id)
		"poison": return PlagueAffliction.new(h, "toxic")
	return null

## Poisons `e` from his poison's `src` (a rite's proc: RunTalents), on the game his rules run on.
static func poison(h: Hero, e, src: String, secs: float) -> void:
	if h != null and h.is_plague():
		(skill(h, "poison") as PlagueAffliction).poison(e, src, secs)

## Is `e` poisoned by him (a rite's condition)?
static func poisoned(h: Hero, e) -> bool:
	var a = h.kit.get("poison") if h != null else null
	return a != null and (a as PlagueAffliction).is_poisoned(e)

# ---------------------------------------------------------------- ClassSkills
static func can_cast(h: Hero, id: String, aim: Vector3) -> bool:
	var s := skill(h, id)
	return s == null or s.can_cast(aim)

static func cast(h: Hero, id: String, aim: Vector3) -> void:
	var t0 := FxTiming.t()
	# any other move takes the needle out early (what was soaked still heals)
	var tr = h.kit.get("transfusion")
	if tr != null:
		(tr as Transfusion).end_early()
	var s := skill(h, id)
	if s != null:
		s.cast(aim)
	FxTiming.done(t0, "plague cast " + id)

## The release (Hero._impact): true when it was the plague doctor's (the vat's crank is The Last Experiment's).
static func impact(h: Hero) -> bool:
	if not h.is_plague():
		return false
	var id := "experiment" if h.atk_skill == "crank" else h.atk_skill
	if not IDS.has(id):
		return false
	var t0 := FxTiming.t()
	skill(h, id).impact()
	FxTiming.done(t0, "plague impact")
	return true

## Every frame on his own game: what his hands hold. (His skills run in ClassSkills.update, his poison last:
## PlagueAffliction.late.)
static func update(h: Hero, _delta: float) -> void:
	if not h.is_plague() or h.game == null or h.game.world == null:
		return
	var t0 := FxTiming.t()
	hands(h)
	FxTiming.done(t0, "plague update")

static func rooted(_h: Hero) -> bool:
	return false

## His skills' state and everything they show go (a class change, a new character).
static func clear(h: Hero) -> void:
	for sk in h.kit.values():
		sk.clear()
	h.kit.clear()
	PlagueFx.clear(h)
	h.fog_hidden = false

## His clouds and poisons outlive him, as before.
static func died(_h: Hero) -> void:
	pass

## The casts' sounds, timed to their release (`at` seconds from now).
static func sound(_h: Hero, skill_id: String, at: float) -> bool:
	match skill_id:
		"toxic": Sfx.play_synced("swing_light", at - 0.05, -4.0, 0.85)
		"swarm": Sfx.play_synced("swing_light", at - 0.05, -6.0, 0.6)
		"bloom": Sfx.play_synced("equip", at, -4.0, 0.7)
		"fog": Sfx.play_synced("swing", at - 0.05, -4.0, 0.9)
		"transfusion": Sfx.play_synced("equip", at, -6.0, 1.3)
		"experiment": Sfx.play_synced("swing_heavy", at - 0.08, -3.0, 0.7)
		_: return false
	return true

## Old saves' bindings of Volatile Mixture, Pestilent Trap and The Last Epidemic become Swarmcraft, Corpse Bloom and
## The Last Experiment (OLD_IDS; Hero.from_save).
static func migrate_binds(binds: Dictionary) -> void:
	for k in binds.keys():
		var id := str(binds[k])
		if OLD_IDS.has(id):
			binds[k] = OLD_IDS[id]

# ---------------------------------------------------------------- his ways (ClassSkills' optional hooks)
## Quicker in his own fog, slower with the needle in his arm.
static func pace(h: Hero) -> float:
	var m := 1.0
	var f = h.kit.get("fog")
	if f != null:
		m *= (f as FogOfTheForgotten).pace()
	var t = h.kit.get("transfusion")
	if t != null:
		m *= (t as Transfusion).pace()
	return m

## His cane's swing (Hero._swipe_impact): its blows are his (PlagueCane), each leaving its own mark.
static func swing(h: Hero, style: String) -> bool:
	(skill(h, "attack") as PlagueCane).swing(style)
	return true

## A blow on him (Hero.take_hit): Transfusion soaks part of it into his tanks.
static func taken(h: Hero, dmg: float) -> float:
	var t = h.kit.get("transfusion")
	return (t as Transfusion).absorb(dmg) if t != null else dmg

## A monster at `at` can't see him in his fog (Enemy._process).
static func hidden_from_monster(h: Hero, at: Vector3) -> bool:
	return FogOfTheForgotten.hidden_from_monster(h, at)

## A partner's copy of him: what his hands hold.
static func puppet_update(h: Hero, _delta: float) -> void:
	hands(h)

## The cane is put away while a skill needs both his hands (Hero._carry_weapon, the swing's trail).
static func hands_busy(h: Hero) -> bool:
	return bool(PlagueFx.state(h).get("hands_busy", false))

## PvP: where his thing `oid` is in his rules (the server checks a blow's reach against it), or null.
static func obj_pos(h: Hero, oid: int) -> Variant:
	for id in ["bloom", "experiment"]:
		var s = h.kit.get(id)
		if s != null:
			var p = s.obj_pos(oid)
			if p is Vector3:
				return p
	return null

## PvP: another player's blow on one of his things, through the server (on his own game, which counts them).
static func obj_hit(h: Hero, oid: int, attacker: int) -> void:
	for id in ["bloom", "experiment"]:
		var s = h.kit.get(id)
		if s != null and s.obj_hit(oid, attacker):
			return

## The ids of the things of his other players can break (PvpObjects), on his own game.
static func new_oid(h: Hero) -> int:
	var n := int(h.get_meta("plague_oid", 0)) + 1
	h.set_meta("plague_oid", n)
	return n

# ---------------------------------------------------------------- body
static func model_ok() -> bool:
	return ResourceLoader.exists(GLB)

static func build_body() -> Node3D:
	if not model_ok():
		var k := Knight.build(Knight.default_gear())
		k.set_meta("plague", true)
		return k
	var r := Knight.build_mocap(GLB, {
		"relaxed": ["idle", 0.0, "walk", 0.55, "run", 4.25],
		"combat": ["idle", 0.0, "walk", 0.55, "run", 4.25],
		"acts": ACTS, "meta": "plague"})
	r.set_meta("plague", true)
	r.remove_meta("knight")
	dye(r, COLORS)
	_censer_glow(r)
	return r

## His leather's colour (game/heroes/plague/build/plague_colors.py recolours the Meshy texture's dark leather by region): "oxblood2" =
## an oxblood coat with a black hat, gloves and boots (the default), "oxblood", "plague", "plague2", "ash2", "" =
## Meshy's black.
const COLORS := "oxblood2"

static func dye(r: Node3D, scheme: String) -> void:
	var path := "res://game/heroes/plague/body/dyes/coat_%s.jpg" % scheme
	if scheme == "" or not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not (m.mesh is ArrayMesh):
			continue
		for si in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(si) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null and mat.albedo_texture.get_width() >= 1024:
				var dm := mat.duplicate() as StandardMaterial3D
				dm.albedo_texture = tex
				m.set_surface_override_material(si, dm)

## The faint green in his goggles and the censer's leak: a small light at his head, smoke at his hip.
static func _censer_glow(r: Node3D) -> void:
	var J: Dictionary = r.get_meta("j")
	if J.has("at_head"):
		var eye := OmniLight3D.new()
		eye.name = "goggle_glow"
		eye.light_color = TOXIC
		eye.light_energy = 0.35
		eye.omni_range = 0.6
		eye.position = Vector3(0, 0.08, -0.14)
		(J["at_head"] as Node3D).add_child(eye)
	if J.has("at_torso"):
		var smoke := Fx.aura(J["at_torso"], Color(0.4, 0.7, 0.25, 0.5), 10, 0.25, 0.09, 1.6, 0.35, 0.05, 25.0, Vector3(-0.22, -0.55, -0.05), false)
		smoke.name = "censer_smoke"

## His cane (the class's weapon kind "cane"): the Meshy crow-skull cane, else a plain dark staff.
static func cane_model() -> Node3D:
	if ResourceLoader.exists(CANE_GLB):
		var root := Node3D.new()
		root.add_child(ResCache.inst(CANE_GLB))
		return root
	var w := Node3D.new()
	var m := MeshInstance3D.new()
	m.mesh = Geo.cyl(0.014, 0.018, 1.0, 8)
	m.position = Vector3(0, -0.3, 0)
	m.material_override = Mats.mat(Color(0.08, 0.07, 0.07), 0.6, 0.0)
	w.add_child(m)
	return w

## Before the body's pose, on his own game (ClassSkills.pose): now and then, standing about, he peers at a vial. Only
## the pose: any step, attack or cast ends it at once.
static func pose(h: Hero, st: Dictionary, delta: float) -> void:
	var b := PlagueFx.state(h)
	var still: bool = float(st.get("move", 0.0)) < 0.05 and float(st.get("atk", -1.0)) < 0.0 and float(st.get("draw", 0.0)) < 0.05 \
		and not h.dead and not h.moving and float(st.get("hit", 0.0)) < 0.1
	if not still:
		b["idle_t"] = 0.0
		b["fid_a"] = -1.0
		return
	b["idle_t"] = float(b.get("idle_t", 0.0)) + delta
	if float(b["idle_t"]) < IDLE_EVERY:
		b["fid_a"] = -1.0
		return
	b["fid_a"] = (float(b["idle_t"]) - IDLE_EVERY) / INSPECT_T
	if float(b["fid_a"]) >= 1.0:
		b["idle_t"] = randf_range(-4.0, 2.0)
		b["fid_a"] = -1.0
		return
	st["style"] = "pd_inspect"
	st["atk"] = b["fid_a"]

## What his hands hold this frame: the vial, reliquary or seed he's about to use, and the cane only when no skill
## needs his hands (his own game from the attack, a partner's copy from the pose it was sent).
static func hands(h: Hero) -> void:
	if h.rig == null or not h.rig.has_meta("j"):
		return
	var b := PlagueFx.state(h)
	var style: String = h.atk_style if not h.puppet else str(h.net_st.get("style", ""))
	var a: float = (h.atk_t / h.atk_dur if h.atk_t >= 0.0 else -1.0) if not h.puppet else float(h.net_st.get("atk", -1.0))
	if not h.puppet and float(b.get("fid_a", -1.0)) >= 0.0:
		style = "pd_inspect"
		a = float(b["fid_a"])
	var want := ""
	if a >= 0.0 and HELD.has(style):
		var spec: Array = HELD[style]
		if a >= float(spec[0]) and a < float(spec[1]):
			want = spec[2]
	var held = b.get("held")
	if want != str(b.get("held_path", "")) or (held != null and not is_instance_valid(held)):
		if held != null and is_instance_valid(held):
			(held as Node).queue_free()
		held = null
		b["held_slosh"] = null
		b["held_path"] = want
		var J: Dictionary = h.rig.get_meta("j")
		if want != "" and J.has("at_hand_r"):
			match want:
				"vial":
					held = PlagueVialFx.vial(PlagueVialFx.next_recipe(h))
					held.scale = Vector3.ONE * PlagueVialFx.HAND_SCALE
					held.position = Vector3(0, -0.06, -0.03)
					b["held_slosh"] = PlagueVialFx.Slosh.new()
				"reliquary":
					held = PlagueSwarmFx.reliquary()
					held.position = Vector3(0, -0.07, -0.02)
				"seed":
					held = PlagueBloomFx.seed_syringe()
					held.position = Vector3(0, -0.05, -0.02)
				"censer":
					held = PlagueFogFx.censer_in_hand()
					held.position = Vector3(0, -0.05, -0.02)
			if held != null:
				(J["at_hand_r"] as Node3D).add_child(held)
		b["held"] = held
	var slosh = b.get("held_slosh")
	if slosh != null and held != null and is_instance_valid(held):
		(slosh as PlagueVialFx.Slosh).step(held, h.get_process_delta_time())
	b["hands_busy"] = a >= 0.0 and HANDS_FREE.has(style)    # Hero._carry_weapon hides the cane meanwhile
	if h.puppet and h.weapon_node != null and is_instance_valid(h.weapon_node):
		h.weapon_node.visible = not bool(b["hands_busy"])
