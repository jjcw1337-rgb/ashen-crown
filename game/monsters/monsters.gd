class_name Monsters
extends RefCounted
## The monster registry: what a monster kind (Data.ENEMIES) is made of, from its folder in game/monsters/. Enemy
## (scripts/enemy.gd: life, statuses, movement, the shared melee and ranged fighting) asks here and names no
## monster:
##   build_rig / pose_rig / model_paths   its body: the family's own (Feral, Bear, the lion's skeleton, the Hollow
##                                        Sloth), a Meshy model on MeshyRig, King Grubb's goblins, a skeleton, a prop
##                                        that grows (the Poison Mushroom), or the code-built crawler and humanoid
##   brain_for                            a boss's brain (BossBrain): Hrimgar, Mossbeard, his mushrooms
##   combat                               a monster's own way of fighting (its def's "ai"): the Feral, the Fallen,
##                                        the bear; null for the shared melee and ranged
##   moves_of, begin/during/impact/       a family's own special moves (the Feral's lunge, the Fallen's three, the
##   finish_move                          bear's roar and maul, King Grubb's bomb and scoop), on its brain
##   fx                                   its own fx events ("sloth*", "bb_*"), drawn on every game
##   idle, fall, rest_overlay, net_lift,  its own idle, how it goes down, its body's resting overlay, a client's
##   heavy_steps                          height for it, a boss's ground-shaking walk
## Adding a monster: its folder (game/monsters/README.md), its Data.ENEMIES entry, and a line here for whatever of
## the above it has of its own.

## A monster family's own start, once its body is built (Enemy.setup): a Feral's or the lion's place round the
## hero, a Hollow Sloth's elemental dress and brain.
static func on_setup(e: Enemy) -> void:
	if e.rig.has_meta("feral"):
		e.slot_a = randf_range(-1.6, 1.6)
		e.lunge_cd = randf_range(0.3, 3.0)
	elif e.rig.has_meta("sloth"):
		Sloth.dress(e.rig, str(e.def.get("element", "")))
		e.sloth = Sloth.new(e)
		e.atk_style = "sloth_walk"
		e.add_to_group("sloth")
	elif e.rig.has_meta("lion"):
		e.slot_a = randf_range(-1.6, 1.6)
		e.lunge_cd = randf_range(0.5, 2.5)

## Once it stands where it lives (the end of Enemy.setup): King Grubb's fight (Hoard) begins.
static func on_placed(e: Enemy) -> void:
	if e.def.get("hoard", false):
		e.hoard = Hoard.new(e)
		e.hoard.call_deferred("start")

## How its body carries itself (Anim's personalities: the gait, the idle, the swing).
static func personality(kind: String) -> String:
	match kind:
		"zombie": return "zombie"
		"skel_archer": return "skeleton"
		"fallen", "fallen_skirmisher", "fallen_stalker": return "fallen"
		"grabber", "goblin_guard": return "goblin"
	return "warrior"

## Its own idle while it hasn't noticed anyone (Enemy, out of combat), or null for the shared wander.
static func idle(e: Enemy, delta: float) -> Variant:
	if str(e.def.get("ai", "")) == "bear":
		return BearBrain.idle(e, delta)
	return null

## The overlay its body wears between hit flashes (the Feral's rim light), or null.
static func rest_overlay(e: Enemy) -> Material:
	return Feral.rim_mat() if e.rig.has_meta("feral") else null

## How far above the ground a client draws it (a perched Feral up its tree; Enemy._net_follow).
static func net_lift(e: Enemy) -> float:
	return Feral.perch_pose(e.rig, e.atk_style, e.net_atk) if e.rig.has_meta("feral") else 0.0

## A boss that shakes the ground as it walks (King Grubb's goblin body).
static func heavy_steps(e: Enemy) -> bool:
	return e.boss and e.rig.has_meta("goblin")

## Its body going down, f: 0 -> 1 over the first 0.6 s (Enemy's death): a crawler flips, the four-legged roll onto
## their side, a goblin's knees buckle and he topples onto his belly (a boss shakes the ground), the rest fall back.
static func fall(e: Enemy, f: float, delta: float) -> void:
	var rig := e.rig
	if rig.has_meta("crawler"):
		rig.rotation.z = f * PI
		rig.position.y = f * 0.4 * e.height
	elif rig.has_meta("feral") or rig.has_meta("lion") or rig.has_meta("bear") or rig.has_meta("sloth"):
		rig.rotation.x = 0.0
		rig.rotation.z = f * f * 1.35
	elif rig.has_meta("goblin"):
		rig.rotation.x = -Anim.kf(e.dead_t, [[0.0, 0.0], [0.5, 0.08], [1.1, 1.3], [1.25, 1.18], [1.4, 1.28]])
		if e.dead_t > 1.1 and e.dead_t - delta <= 1.1 and e.boss:
			e.game.add_shake(0.5)
			Fx.burst(e.game.world.fx_root, e.global_position - rig.global_transform.basis.z * 1.5, Color(0.4, 0.35, 0.3, 0.8), 40, 4.0, 0.3, 0.9, false, -3.0, 80.0)
	else:
		rig.rotation.x = f * f * 1.45

## A boss's brain, or null.
static func brain_for(e: Enemy) -> BossBrain:
	match e.kind:
		"ice_troll": return Hrimgar.new(e)
		"hermit": return Mossbeard.new(e)
		"spore_shroom": return PoisonMushroom.new(e)
	return null

## A monster's own way of fighting (Enemy._think_combat), or null for the shared one.
static func combat(e: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Variant:
	match str(e.def.get("ai", "")):
		"feral": return FeralBrain.combat(e, delta, hero, to, dist)
		"skirmisher": return FallenBrain.skirmisher(e, delta, hero, to, dist)
		"reaver": return FallenBrain.reaver(e, delta, hero, to, dist)
		"stalker": return FallenBrain.stalker(e, delta, hero, to, dist)
		"bear": return BearBrain.combat(e, delta, hero, to, dist)
	return null

## The family whose move `sp` is (Enemy.special): its brain script has static begin(e, sp), during(e, a, hero),
## impact(e, hero, dist) and finish(e). Null for the shared moves Enemy plays itself (slam, summon, nova, volley).
static func moves_of(sp: String) -> Script:
	match sp:
		"feral_lunge": return FeralBrain
		"skirm_lunge", "reaver_cleave", "stalk_hook": return FallenBrain
		"bear_roar", "bear_maul": return BearBrain
		"bomb", "scoop", "burst", "cackle": return Hoard
	return null

static func begin_move(e: Enemy, sp: String) -> void:
	var m := moves_of(sp)
	if m != null:
		m.call("begin", e, sp)

static func during_move(e: Enemy, a: float, hero: Node3D) -> void:
	var m := moves_of(e.special)
	if m != null:
		m.call("during", e, a, hero)

## True if the move was a family's (it landed it itself).
static func impact_move(e: Enemy, hero: Node3D, dist: float) -> bool:
	var m := moves_of(e.special)
	if m == null:
		return false
	m.call("impact", e, hero, dist)
	return true

static func finish_move(e: Enemy) -> void:
	var m := moves_of(e.special)
	if m != null:
		m.call("finish", e)

## A monster's own fx event, drawn on every game (Enemy.special_fx): true if it was one.
static func fx(e: Enemy, ev: String) -> bool:
	if ev.begins_with("bear_"):
		BearFx.fx(e, ev)
		return true
	if ev == "reaver_tele":
		FallenFx.fx(e, ev)
		return true
	if ev.begins_with("sloth"):
		Sloth.fx(e, ev)
		return true
	if ev.begins_with("bb_"):
		if e.kind == "ice_troll":
			HrimgarFx.fx(e, ev)
		else:
			MossbeardFx.fx(e, ev)
		return true
	return false

## The model files a monster kind's body loads (build_rig), so a zone can load them on worker threads before it
## spawns its monsters (Game.load_zone: each first load was 23-34 ms on the main thread).
static func model_paths(kind: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not Data.ENEMIES.has(kind):
		return out
	var d: Dictionary = Data.ENEMIES[kind]
	var mesh := str(d.get("mesh", ""))
	match mesh:
		"feral":
			for k in 5:
				out.append(Feral.GLB % (k + 1))
		"lion":
			out.append(Lion.GLB)
		"bear":
			out.append(Bear.GLB)
		"sloth":
			out.append(Sloth.GLB % str(d.get("variant", "")))
		"wolf":
			out.append(SpiritBeast.WOLF_GLB)
		_:
			if MeshyMonster.MODELS.has(mesh):
				out.append(str(MeshyMonster.MODELS[mesh]["glb"]))
	var res := PackedStringArray()
	for p in out:
		if ResourceLoader.exists(p):
			res.append(p)
	return res

## A monster kind's body (its Meshy model, sculpted goblin, skeleton or code-built figure), as setup gives
## it. variant: the Feral's model.
static func build_rig(kind: String, variant := 1) -> Node3D:
	var d: Dictionary = Data.ENEMIES[kind]
	var look: Dictionary = d["look"]
	var h: float = look.get("height", look.get("size", 1.0))
	if d.get("mesh", "") == "feral" and Feral.ok():
		return Feral.build(variant)
	if d.get("mesh", "") == "lion" and Lion.ok():
		return Lion.build()
	if d.get("mesh", "") == "bear" and Bear.ok():
		return Bear.build()
	if d.get("mesh", "") == "sloth":
		return Sloth.build(str(d.get("variant", "")), look.get("skin", Color(0.52, 0.56, 0.47)))
	if d.has("prop"):
		# a thing that grows rather than walks (the hermit's mushrooms): a Meshy prop, pulsing (pose_rig)
		var pr := Node3D.new()
		pr.set_meta("static_prop", true)
		var pp := "res://game/maps/verdant_reach/props/%s.glb" % str(d["prop"])
		var m: Node3D = (load(pp) as PackedScene).instantiate() if ResourceLoader.exists(pp) else null
		if m == null:
			m = Models.crawler(look)
		m.name = "body"
		m.scale = Vector3.ONE * float(look.get("prop_scale", 1.0))
		pr.add_child(m)
		return pr
	if d.get("mesh", "") == "wolf" and ResourceLoader.exists(SpiritBeast.WOLF_GLB):
		return Lion.build(SpiritBeast.WOLF_GLB, 1.0)
	if d.has("mesh") and MeshyMonster.ok(d["mesh"]):
		return MeshyMonster.build(d["mesh"], look)
	if d.has("model"):
		return Goblin.build(d["model"])
	if d.has("skin"):
		var r := SkeletonModel.build(d["skin"])
		if absf(h - 1.0) > 0.01:
			r.scale = Vector3.ONE * h
		return r
	return Models.crawler(look) if d["rig"] == "crawler" else Models.humanoid(look)

## Poses any monster body from the enemy state (see `_pose`).
static func pose_rig(r: Node3D, st: Dictionary, height: float) -> void:
	if r.has_meta("feral"):
		Feral.pose(r, st, height)
	elif r.has_meta("lion"):
		Lion.pose(r, st, height)
	elif r.has_meta("bear"):
		Bear.pose(r, st, height)
	elif r.has_meta("sloth"):
		Sloth.pose(r, st, height)
	elif r.has_meta("static_prop"):
		var b := r.get_node_or_null("body") as Node3D
		if b != null:
			# the breathing pulse round its own size, kept from the first pose: scaling from the current scale every
			# frame compounded (~1% a frame) and grew the hermit's mushrooms past the camera within minutes, one
			# giant cap's shadow over the map (Blaine, 2026-11-06)
			if not b.has_meta("base_scale"):
				b.set_meta("base_scale", b.scale)
			var t := float(st.get("time", 0.0))
			var k := 1.0 + sin(t * 2.6) * 0.04
			b.scale = (b.get_meta("base_scale") as Vector3) * Vector3(k, 2.0 - k, k)
	else:
		Anim.pose(r, st)
