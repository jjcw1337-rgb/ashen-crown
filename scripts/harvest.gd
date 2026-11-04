class_name Harvest
extends Node3D
## Woodcutting (Act I's moor): a few of the zone's trees can be felled for wood. One Harvest node per zone that
## has them (World child "Harvest", `Harvest.of(world)`); the trees themselves are `Harvest.HTree` interactables
## (Inter kind "tree"), so hovering, clicking and walking up to one is the usual interaction.
##
## - Which trees: `pick` takes them out of the zone's MultiMesh groups before they're drawn (World._build_wild),
##   on its own seed so every co-op peer picks the same ones, never by the road, never a Feral's perch, spaced out,
##   at most CAP; the rest of the forest stays scenery. `build` gives each its own node, its solid footprint (the
##   one World already has for it, `obstacle`), a woodsman's blaze on the bark so it reads as one to chop.
## - Chopping (Hero.start_chop / _chop_*): the hero puts the weapon away and swings the axe (style "chop",
##   Data.CHOP_PROFILES); each blow lands on the clip's impact frame and calls `strike_from(hero)`.
## - Authority: the host owns every tree (life, felling, the logs, respawns). A partner's blow goes to the host
##   (`Net.request_chop`), which checks the partner stands by the trunk, swings no faster than STRIKE_GAP and the
##   tree still stands, applies it and tells everyone what happened (`Net.cl_tree`); the logs are ordinary ground
##   items (Game.drop_item), so a log can only ever be picked up once. Partners never fell or regrow on their own.
## - Respawns run on the host character's played time (Game.played_s, saved), never the wall clock: a felled tree
##   leaves a stump and grows back RESPAWN seconds later, only with no hero within REGROW_CLEAR, so it never pops in
##   on camera. Stumps and their timers are saved with the host's character (`Game.harvest_save`).
## - What is seen (the shudder, chips, the notch deepening, the fall, the dust, the regrowth) plays on every peer
##   from the same events (`play_event`).

const KINDS := {
	"oak": {"name": "Moor Oak", "log": "oak_log", "hp": 7, "yield": [3, 4], "respawn": 480.0, "cut": 0.55, "trunk": 0.42, "leaves": Color(0.24, 0.32, 0.12)},
	"pine": {"name": "Old Pine", "log": "pine_log", "hp": 4, "yield": [2, 3], "respawn": 360.0, "cut": 0.45, "trunk": 0.3, "leaves": Color(0.14, 0.22, 0.12)},
	"heart": {"name": "Ashen Heartwood", "log": "heartwood", "hp": 14, "yield": [1, 2], "respawn": 1500.0, "cut": 0.5, "trunk": 0.36, "leaves": Color(0.3, 0.12, 0.05)},
}
const CAP := 24                 # harvestable trees in one zone
const HEARTWOODS := 3           # of them, Ashen Heartwood (from the moor's dead trees)
const SPACING := 14.0           # metres between harvestable trees
const ROAD_MIN := 8.0           # metres from the road
const ROAD_MAX := 42.0
const STRIKE_GAP := 0.45        # the host refuses blows closer together than this from one hero
const REACH := 3.4              # the host refuses blows from further than this from the trunk
const HEAL_AFTER := 30.0        # a tree left alone this long closes its wound (full life)
const REGROW_CLEAR := 12.0      # no hero this close when it grows back
const REGROW_T := 4.0           # seconds the regrowth takes to play
const FALL_LOGS_AT := 1.7       # seconds after the last blow that the logs spill out (the tree is down)

var world: World = null
var trees: Array = []           # Harvest.HTree, index = the tree's id (the same on every peer)
var _last_strike := {}          # host: peer id -> Time of its last accepted blow

static func of(w: Node) -> Harvest:
	if w == null:
		return null
	return w.get_node_or_null("Harvest") as Harvest

# ---------------------------------------------------------------- choosing and building
## Takes the harvestable trees out of World._build_wild's MultiMesh groups (so they aren't drawn twice) and
## returns their specs: [{kind, xf: Transform3D, mesh}]. `meshes` maps a group key to its Mesh.
static func pick(w: World, groups: Dictionary, meshes: Dictionary) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = int(w.bounds.size.x * 977.0 + w.bounds.size.y * 131.0) + 7031 + w.act * 11
	var cands := {"oak": [], "pine": [], "heart": []}
	for key in groups.keys():
		var kind := ""
		if str(key).begins_with("oak"):
			kind = "oak"
		elif str(key).begins_with("pine"):
			kind = "pine"
		elif str(key).begins_with("dead"):
			kind = "heart"
		if kind == "":
			continue
		var arr: Array = groups[key]
		for i in arr.size():
			var o: Vector3 = (arr[i] as Transform3D).origin
			if not w.bounds.grow(-4.0).has_point(Vector2(o.x, o.z)):
				continue
			var pd := w.path_dist(o.x, o.z)
			if pd < ROAD_MIN or pd > ROAD_MAX:
				continue
			# well clear of where the hero arrives
			if Vector2(o.x, o.z).distance_to(Vector2(0, -6)) < 16.0:
				continue
			(cands[kind] as Array).append([key, i])
	var chosen: Array = []
	var picked_pos: Array = []
	# a few Ashen Heartwoods first (rare, far out), then oaks and pines about two to one
	var quota := {"heart": HEARTWOODS, "oak": int((CAP - HEARTWOODS) * 0.65), "pine": CAP - HEARTWOODS - int((CAP - HEARTWOODS) * 0.65)}
	for kind in ["heart", "oak", "pine"]:
		var pool: Array = cands[kind]
		var want: int = quota[kind]
		var tries := 0
		while want > 0 and not pool.is_empty() and tries < 4000:
			tries += 1
			var j := r.randi() % pool.size()
			var c: Array = pool[j]
			pool.remove_at(j)
			var xf: Transform3D = (groups[c[0]] as Array)[c[1]]
			var o2 := Vector2(xf.origin.x, xf.origin.z)
			if kind == "heart" and w.path_dist(o2.x, o2.y) < 16.0:
				continue
			if picked_pos.any(func(q: Vector2) -> bool: return q.distance_to(o2) < SPACING):
				continue
			picked_pos.append(o2)
			chosen.append({"kind": kind, "key": c[0], "i": c[1], "xf": xf, "mesh": meshes.get(c[0])})
			want -= 1
	# out of the groups (highest index first so the others stay valid)
	chosen.sort_custom(func(a, b): return int(a["i"]) > int(b["i"]))
	for c in chosen:
		(groups[c["key"]] as Array).remove_at(int(c["i"]))
	# a stable order: by position, so ids agree on every peer
	chosen.sort_custom(func(a, b):
		var pa: Vector3 = (a["xf"] as Transform3D).origin
		var pb: Vector3 = (b["xf"] as Transform3D).origin
		return pa.x < pb.x if absf(pa.x - pb.x) > 0.001 else pa.z < pb.z)
	return chosen

## Builds the Harvest node and its trees from `pick`'s specs. Call after the zone's obstacles exist.
static func build(w: World, specs: Array) -> Harvest:
	if specs.is_empty():
		return null
	var h := Harvest.new()
	h.name = "Harvest"
	h.world = w
	w.add_child(h)
	for s in specs:
		var t := HTree.new()
		t.setup(h, h.trees.size(), str(s["kind"]), s["xf"], s["mesh"])
		h.trees.append(t)
		w.interactables.append(t)
		w.tree_pts.append(Vector2((s["xf"] as Transform3D).origin.x, (s["xf"] as Transform3D).origin.z))
	return h

# ---------------------------------------------------------------- the host's rules
func _game() -> Node:
	return world.get_parent() if world != null and is_instance_valid(world) else null

func _now() -> float:
	var g = _game()
	return float(g.played_s) if g != null else Time.get_ticks_msec() / 1000.0

## A blow from `hero` at tree `id` with an axe of `power` (Data.CHOP_POWER). Called on the hero's own game at
## the swing's impact frame: the host applies it, a partner sends it to the host.
static func strike_from(hero: Node3D, id: int, power: float) -> void:
	var w: World = hero.game.world
	var h := Harvest.of(w)
	if h == null or id < 0 or id >= h.trees.size():
		return
	var t: HTree = h.trees[id]
	# what the chopper sees at once (his own blow): the chips, the sound, the shudder; the host's word follows
	t.react(hero.global_position, true)
	if hero.game.net.is_client():
		hero.game.net.request_chop(id, power)
	else:
		h.strike(id, 1, hero.global_position, power)

## Host: applies a blow (from peer `pid`, the striker standing at `from`). Returns true if it counted.
func strike(id: int, pid: int, from: Vector3, power: float) -> bool:
	if id < 0 or id >= trees.size():
		return false
	var t: HTree = trees[id]
	if t.state != "stand":
		return false
	var flat := Vector2(from.x - t.global_position.x, from.z - t.global_position.z).length()
	if flat > REACH + t.trunk_r:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_strike.get(pid, -99.0)) < STRIKE_GAP:
		return false
	_last_strike[pid] = now
	t.hp = maxf(0.0, t.hp - clampf(power, 0.5, 2.0))
	t.last_hit = _now()
	var dir := Vector3(t.global_position.x - from.x, 0, t.global_position.z - from.z).normalized()
	if t.hp <= 0.0:
		t.state = "falling"
		t.respawn_at = _now() + float(t.def["respawn"])
		_broadcast(id, "fell", {"d": dir, "pid": pid})
		_drop_logs_later(t, dir)
		var g = _game()
		if g != null and g.has_method("on_tree_felled"):
			g.on_tree_felled(t)
	else:
		_broadcast(id, "hit", {"d": dir, "hp": t.hp / t.max_hp, "pid": pid})
	return true

## Host: tells everyone (itself first) what happened to tree `id`.
func _broadcast(id: int, ev: String, data: Dictionary) -> void:
	play_event(id, ev, data)
	var g = _game()
	if g != null and g.net.active and g.net.is_host:
		g.net.send_tree(id, ev, data)

## Every peer: shows an event (`hit`, `fell`, `heal`, `regrow`, `stump`).
func play_event(id: int, ev: String, data: Dictionary) -> void:
	if id < 0 or id >= trees.size():
		return
	var t: HTree = trees[id]
	var g = _game()
	var mine: bool = g != null and int(data.get("pid", -1)) == (g.multiplayer.get_unique_id() if g.net.active else 1)
	match ev:
		"hit":
			t.hp = float(data.get("hp", 1.0)) * t.max_hp
			if not mine:
				t.react(t.global_position - (data.get("d", Vector3.FORWARD) as Vector3) * 1.2, false)
			t.set_wound(1.0 - t.hp / t.max_hp, data.get("d", Vector3.FORWARD))
		"fell":
			t.hp = 0.0
			t.fell(data.get("d", Vector3.FORWARD))
		"heal":
			t.hp = t.max_hp
			t.set_wound(0.0, Vector3.FORWARD)
		"regrow":
			t.regrow()
		"stump":
			t.to_stump()

func _drop_logs_later(t: HTree, dir: Vector3) -> void:
	var g = _game()
	if g == null:
		return
	var y: Array = t.def["yield"]
	var r := RandomNumberGenerator.new()
	r.randomize()
	var n := r.randi_range(int(y[0]), int(y[1]))
	var log_id: String = t.def["log"]
	var base := t.global_position
	var length := t.height * 0.75
	await get_tree().create_timer(FALL_LOGS_AT).timeout
	if not is_instance_valid(t) or g.world != world:
		return
	for k in n:
		# along the trunk where it lies, from near the stump to most of its length
		var f := 0.25 + 0.6 * (k + 0.5) / float(n)
		var at := base + dir * length * f + dir.cross(Vector3.UP) * r.randf_range(-0.5, 0.5)
		at.y = world.height_at(at.x, at.z) + 0.2
		g.drop_item(Items.resource(log_id, 1), at)

## Host, every frame: wounds close, stumps grow back.
func _process(delta: float) -> void:
	for t in trees:
		(t as HTree).animate(delta)
	var g = _game()
	if g == null or (g.net.active and not g.net.is_host):
		return
	var now := _now()
	for i in trees.size():
		var t: HTree = trees[i]
		if t.state == "stand" and t.hp < t.max_hp and now - t.last_hit > HEAL_AFTER:
			_broadcast(i, "heal", {})
		elif t.state == "stump" and now >= t.respawn_at and not _hero_near(g, t.global_position, REGROW_CLEAR):
			t.state = "stand"
			t.hp = t.max_hp
			_broadcast(i, "regrow", {})

func _hero_near(g: Node, p: Vector3, r: float) -> bool:
	var heroes: Array = [g.hero]
	if g.net.active:
		for pid in g.net.players.keys():
			var ph = g.net.players[pid].get("hero")
			if is_instance_valid(ph):
				heroes.append(ph)
	for hh in heroes:
		if is_instance_valid(hh) and Vector2(hh.global_position.x - p.x, hh.global_position.z - p.z).length() < r:
			return true
	return false

# ---------------------------------------------------------------- saves and joins
## The felled trees and when they grow back (played seconds), for the host's save.
func to_save() -> Dictionary:
	var d := {}
	for i in trees.size():
		var t: HTree = trees[i]
		if t.state != "stand":
			d[str(i)] = t.respawn_at
	return d

## Puts back what a save says: stumps whose time hasn't come, the rest standing.
func from_save(d: Dictionary, now: float) -> void:
	for k in d.keys():
		var i := int(k)
		if i < 0 or i >= trees.size():
			continue
		var at := float(d[k])
		if at > now:
			var t: HTree = trees[i]
			t.respawn_at = at
			t.to_stump()

## Host -> a joining partner: which trees are stumps and how hurt the rest are.
func snapshot() -> Dictionary:
	var d := {}
	for i in trees.size():
		var t: HTree = trees[i]
		if t.state != "stand":
			d[str(i)] = -1.0
		elif t.hp < t.max_hp:
			d[str(i)] = t.hp / t.max_hp
	return d

func apply_snapshot(d: Dictionary) -> void:
	for k in d.keys():
		var i := int(k)
		if i < 0 or i >= trees.size():
			continue
		var t: HTree = trees[i]
		var v := float(d[k])
		if v < 0.0:
			t.to_stump()
		else:
			t.hp = v * t.max_hp
			t.set_wound(1.0 - v, Vector3.FORWARD)

# ---------------------------------------------------------------- sounds
## The woodcutting sounds, by name; until the recorded ones are in the bank (tools/audio/spec.py), the nearest
## existing sound stands in, pitched to fit.
const SOUND_STAND_IN := {
	"axe_chop": ["impact_bone", 0.62, -2.0],
	"bark_crack": ["block", 0.7, -6.0],
	"tree_creak": ["portcullis", 0.55, -8.0],
	"tree_fall": ["slam", 0.62, 0.0],
	"tree_thud": ["boom", 0.7, -8.0],
	"leaves_rustle": ["birds_flutter", 0.8, -14.0],
	"log_pickup": ["drop", 0.75, -2.0],
}

## The Sfx autoload, looked up at run time (so tool scripts that name these classes compile before it exists).
static func sfx() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Sfx")

static func snd(nm: String, at: Vector3, vol := 0.0, pitch := 1.0) -> void:
	if Harvest.sfx().bank.has(nm):
		Harvest.sfx().play_at(nm, at, vol, pitch * randf_range(0.94, 1.06))
		return
	var s: Array = SOUND_STAND_IN.get(nm, [])
	if s.is_empty():
		return
	Harvest.sfx().play_at(str(s[0]), at, vol + float(s[2]), float(s[1]) * pitch * randf_range(0.94, 1.06))

# ================================================================ one tree
class HTree extends Inter:
	var harvest: Harvest
	var id := 0
	var tkind := "oak"
	var def: Dictionary = {}
	var hp := 1.0
	var max_hp := 1.0
	var state := "stand"           # stand | falling | stump | regrow
	var respawn_at := 0.0
	var last_hit := -999.0
	var trunk_r := 0.4             # the trunk's radius at the cut (world metres)
	var height := 6.0
	var cut_y := 0.5               # world metres up the trunk
	var obstacle := -1             # World.obstacles index of its footprint
	var obstacle_r := 0.7
	var base_scale := 1.0
	var yaw := 0.0
	# nodes
	var body: Node3D               # the standing tree (rocks when struck)
	var full: MeshInstance3D
	var stump: Node3D
	var fall: Node3D               # pivot at the cut; the trunk and crown above it
	var top: Node3D
	var wound: Node3D              # the axe's notch
	var blaze: Node3D
	var glow: OmniLight3D
	# motion
	var rock := 0.0                # the shudder: angle (rad), its speed, its axis
	var rock_v := 0.0
	var rock_axis := Vector3.RIGHT
	var fall_a := 0.0
	var fall_v := 0.0
	var fall_dir := Vector3.FORWARD
	var fall_t := 0.0
	var landed := 0
	var regrow_t := 0.0
	var wound_amt := 0.0

	func setup(h: Harvest, i: int, k: String, xf: Transform3D, mesh: Mesh) -> void:
		harvest = h
		id = i
		tkind = k
		def = Harvest.KINDS[k]
		kind = "tree"
		label = str(def["name"])
		max_hp = float(def["hp"])
		hp = max_hp
		base_scale = xf.basis.get_scale().x
		yaw = xf.basis.get_euler().y
		cut_y = float(def["cut"]) * base_scale
		h.world.add_child(self)
		global_position = xf.origin
		body = Node3D.new()
		body.name = "Body"
		add_child(body)
		var holder := Node3D.new()
		holder.basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * base_scale)
		body.add_child(holder)
		full = MeshInstance3D.new()
		full.mesh = mesh
		holder.add_child(full)
		# its shadow from the forest's shadows-only twin (welded trunk, baked leaf mask: Flora.shadow_twin), as the
		# MultiMesh oaks around it do; a child of `full`, so it goes when the tree is felled (nightly perf 2026-11-04)
		if mesh != null and mesh.has_meta("shadow_mesh") and not OS.get_cmdline_user_args().has("--notwins") and not OS.get_cmdline_user_args().has("--noharvesttwin"):
			var tw := MeshInstance3D.new()
			tw.name = "ShadowTwin"
			tw.mesh = mesh.get_meta("shadow_mesh")
			tw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			tw.visibility_range_end = 90.0
			full.add_child(tw)
			full.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var parts := Harvest.split_mesh(mesh, float(def["cut"]))
		height = float(parts[2]) * base_scale
		trunk_r = maxf(0.18, float(parts[3]) * base_scale)
		radius = trunk_r + Data.DEFAULT_CHOP["stand"] + 0.25
		# the stump (shown once felled) and the falling trunk with its crown
		stump = Node3D.new()
		stump.name = "Stump"
		add_child(stump)
		var sh := Node3D.new()
		sh.basis = holder.basis
		stump.add_child(sh)
		var lo := MeshInstance3D.new()
		lo.mesh = parts[0]
		sh.add_child(lo)
		var cap := Wood.cut_disc(str(def["log"]), trunk_r * 0.97)
		cap.position = Vector3(0, cut_y + 0.005, 0)
		stump.add_child(cap)
		stump.visible = false
		fall = Node3D.new()
		fall.name = "Fall"
		fall.position = Vector3(0, cut_y, 0)
		add_child(fall)
		top = Node3D.new()
		top.basis = holder.basis
		top.position = Vector3(0, -cut_y, 0)
		fall.add_child(top)
		var up := MeshInstance3D.new()
		up.mesh = parts[1]
		top.add_child(up)
		var bottom := Wood.cut_disc(str(def["log"]), trunk_r * 0.97)
		bottom.rotation_degrees = Vector3(180, 0, 0)
		bottom.position = Vector3(0, -0.005, 0)
		fall.add_child(bottom)
		fall.visible = false
		# like the forest's MultiMesh chunks: past ~90 m it's off any screen
		for mi in [full, lo, up]:
			(mi as MeshInstance3D).visibility_range_end = 90.0
		if tkind == "heart":
			# a dead tree still smouldering inside: ember-lit cracks, a glow at its foot, embers drifting up
			var em := Wood.bark("heartwood")
			for mi in [full, lo, up]:
				(mi as MeshInstance3D).material_override = em
			glow = OmniLight3D.new()
			glow.light_color = Color(1.0, 0.42, 0.1)
			glow.light_energy = 1.1
			glow.omni_range = 4.0
			glow.position = Vector3(0, 1.0, 0)
			add_child(glow)
			Fx.aura(body, Color(1.0, 0.5, 0.15, 0.85), 16, 0.35, 0.04, 2.2, 0.5, trunk_r * 1.2, 25.0, Vector3(0, 1.4, 0))
		_make_wound()
		_make_blaze()
		# its footprint is the one World registered for it when the forest was laid out
		obstacle = h.world.obstacle_at(Vector2(xf.origin.x, xf.origin.z))
		if obstacle >= 0:
			obstacle_r = float(h.world.obstacles[obstacle][1])

	## The woodsman's blaze: a hand-sized patch of bark slashed away at chest height, facing the road, so a
	## harvestable tree reads as one without a marker floating over it.
	func _make_blaze() -> void:
		blaze = Node3D.new()
		var w := harvest.world
		var p := global_position
		var best := Vector3.FORWARD
		var bd := 1e9
		for k in 12:
			var a := TAU * k / 12.0
			var q := p + Vector3(cos(a), 0, sin(a)) * 6.0
			var dd := w.path_dist(q.x, q.z)
			if dd < bd:
				bd = dd
				best = Vector3(cos(a), 0, sin(a))
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(trunk_r * 0.75, 0.32)
		mi.mesh = qm
		mi.material_override = Wood.end_grain(str(def["log"]), true)
		blaze.add_child(mi)
		blaze.position = best * (trunk_r * 0.9) + Vector3(0, 1.25, 0)
		blaze.basis = Basis.looking_at(-best, Vector3.UP)
		body.add_child(blaze)

	func _make_wound() -> void:
		wound = Wood.notch(str(def["log"]), trunk_r)
		wound.visible = false
		body.add_child(wound)

	## How deep the axe has bitten (0..1), on the side it was struck from.
	func set_wound(k: float, from_dir: Vector3) -> void:
		wound_amt = clampf(k, 0.0, 1.0)
		if wound_amt <= 0.01:
			wound.visible = false
			return
		if not wound.visible and from_dir.length() > 0.1:
			var side := -Vector3(from_dir.x, 0, from_dir.z).normalized()
			wound.basis = Basis.looking_at(-side, Vector3.UP)
		wound.visible = true
		var s := lerpf(0.35, 1.0, wound_amt)
		wound.scale = Vector3(s, lerpf(0.6, 1.15, wound_amt), 1.0)
		# the notch's +z faces the striker (looking_at turned its -z away from him)
		var side2 := wound.basis.z
		wound.position = Vector3(0, cut_y + 0.04, 0) + side2 * trunk_r * lerpf(0.95, 0.35, wound_amt)

	## A blow lands: the tree shudders away from it, chips and splinters fly back toward the striker, leaves
	## fall, and the axe bites (its sound). `from` is where the striker stands.
	func react(from: Vector3, own: bool) -> void:
		if state != "stand":
			return
		var d := Vector3(global_position.x - from.x, 0, global_position.z - from.z)
		d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
		rock_axis = Vector3.UP.cross(d).normalized()
		rock_v += 0.11 if own else 0.08
		var at := global_position + Vector3(0, cut_y + 0.05, 0) - d * trunk_r
		var deb := Wood.Debris.of(harvest.world)
		deb.spray(at, -d, str(def["log"]), 9, 4)
		Fx.burst(harvest.world.fx_root, at, Color(0.55, 0.45, 0.32, 0.55), 10, 1.4, 0.18, 0.7, false, -1.5, 60.0, -d)
		var lc: Color = def["leaves"]
		Fx.burst(harvest.world.fx_root, global_position + Vector3(0, height * 0.7, 0), Color(lc.r, lc.g, lc.b, 0.9), 8, 0.6, 0.14, 2.6, false, -1.2, 180.0)
		Harvest.snd("axe_chop", at, 0.0 if own else -3.0)
		if wound_amt > 0.5:
			Harvest.snd("bark_crack", at, -4.0)
		var g = harvest._game()
		if own and g != null:
			g.add_shake(0.06)
			g.hitstop(0.035)

	## The last blow: the tree tips away from the striker, slowly at first, faster, crashes down and bounces.
	func fell(dir: Vector3) -> void:
		if state == "stump":
			return
		state = "falling"
		fall_dir = Vector3(dir.x, 0, dir.z).normalized() if Vector3(dir.x, 0, dir.z).length() > 0.01 else Vector3.FORWARD
		fall_a = 0.0
		fall_v = 0.05
		fall_t = 0.0
		landed = 0
		body.visible = false
		stump.visible = true
		fall.visible = true
		fall.basis = Basis.IDENTITY
		wound.visible = false
		if glow:
			glow.light_energy = 0.5
		_set_footprint(false)
		Harvest.snd("tree_creak", global_position + Vector3(0, 2.0, 0))
		var deb := Wood.Debris.of(harvest.world)
		deb.spray(global_position + Vector3(0, cut_y, 0), -fall_dir, str(def["log"]), 14, 8, 1.2)

	## Straight to a stump (a save or a join that finds it felled).
	func to_stump() -> void:
		state = "stump"
		body.visible = false
		fall.visible = false
		stump.visible = true
		wound.visible = false
		hp = 0.0
		if glow:
			glow.light_energy = 0.3
		_set_footprint(false)

	## Grows back where the stump was: up out of the ground over REGROW_T, with a rustle of leaves.
	func regrow() -> void:
		state = "regrow"
		regrow_t = 0.0
		hp = max_hp
		body.visible = true
		body.scale = Vector3.ONE * 0.05
		stump.visible = false
		fall.visible = false
		set_wound(0.0, Vector3.FORWARD)
		if glow:
			glow.light_energy = 1.1
		_set_footprint(true)
		Harvest.snd("leaves_rustle", global_position + Vector3(0, 2.0, 0))

	func _set_footprint(standing: bool) -> void:
		if obstacle < 0:
			return
		# a stump is still solid, but small; the full tree back is its old size
		harvest.world.obstacles[obstacle][1] = obstacle_r if standing else clampf(trunk_r * 0.85, 0.22, obstacle_r * 0.7)

	func animate(delta: float) -> void:
		# the shudder: a damped spring about the axis across the blow
		if state == "stand" and (absf(rock) > 0.0001 or absf(rock_v) > 0.0001):
			rock_v += (-rock * 160.0 - rock_v * 9.0) * delta
			rock += rock_v * delta * 6.0
			body.basis = Basis(rock_axis, rock * 0.25)
		match state:
			"falling":
				_animate_fall(delta)
			"regrow":
				regrow_t += delta
				var k := clampf(regrow_t / REGROW_T, 0.0, 1.0)
				# ease out with a little overshoot, as if it straightened up into its place
				var e := 1.0 + 2.7 * pow(k - 1.0, 3.0) + 1.7 * pow(k - 1.0, 2.0)
				body.scale = Vector3.ONE * maxf(0.05, e)
				if k >= 1.0:
					body.scale = Vector3.ONE
					state = "stand"

	func _animate_fall(delta: float) -> void:
		fall_t += delta
		var axis := Vector3.UP.cross(fall_dir).normalized()
		# lands where the ground meets it: about horizontal, a little less downhill
		var land := deg_to_rad(86.0)
		if landed == 0:
			# an inverted pendulum: slow to tip, then it goes
			var gl := 9.8 / maxf(1.5, height * 0.55)
			fall_v += gl * sin(fall_a + 0.04) * delta
			fall_a += fall_v * delta
			if fall_a >= land:
				fall_a = land
				fall_v = -fall_v * 0.22
				landed = 1
				_impact_ground()
		elif landed < 4:
			fall_v += 9.8 / maxf(1.5, height * 0.55) * delta * 2.0
			fall_a += fall_v * delta
			if fall_a >= land:
				fall_a = land
				fall_v = -fall_v * 0.3
				landed += 1
				if absf(fall_v) < 0.05:
					landed = 4
		fall.basis = Basis(axis, fall_a)
		# lying there a moment, then it settles into the moss and is gone
		if landed >= 1 and fall_t > 4.5:
			var s := clampf((fall_t - 4.5) / 3.0, 0.0, 1.0)
			fall.position = Vector3(0, cut_y - s * (trunk_r * 2.2 + 0.2), 0)
			if s >= 1.0:
				fall.visible = false
				fall.position = Vector3(0, cut_y, 0)
				state = "stump"

	func _impact_ground() -> void:
		var mid := global_position + fall_dir * height * 0.55
		mid.y = harvest.world.height_at(mid.x, mid.z)
		Harvest.snd("tree_fall", mid)
		Harvest.snd("tree_thud", mid)
		var g = harvest._game()
		if g != null:
			var dh := Vector2(g.hero.global_position.x - mid.x, g.hero.global_position.z - mid.z).length()
			g.add_shake(clampf(0.5 - dh * 0.02, 0.05, 0.4))
			if g.grass_field != null and g.grass_field.has_method("impulse"):
				g.grass_field.impulse(mid, height * 0.5, 1.0)
		var lc: Color = def["leaves"]
		for k in 4:
			var p := global_position + fall_dir * height * (0.3 + 0.18 * k)
			p.y = harvest.world.height_at(p.x, p.z) + 0.3
			Fx.burst(harvest.world.fx_root, p, Color(0.5, 0.42, 0.3, 0.5), 14, 2.2, 0.5, 1.4, false, -0.6, 70.0, Vector3.UP)
			if tkind != "heart":
				Fx.burst(harvest.world.fx_root, p + Vector3(0, 0.8, 0), Color(lc.r, lc.g, lc.b, 0.95), 18, 2.5, 0.16, 2.4, false, -1.6, 160.0, Vector3.UP)
			else:
				Fx.burst(harvest.world.fx_root, p, Color(1.0, 0.45, 0.1, 0.9), 16, 3.0, 0.07, 1.2, true, -2.0, 120.0, Vector3.UP)
		var deb := Wood.Debris.of(harvest.world)
		deb.spray(global_position + fall_dir * height * 0.4 + Vector3(0, 0.3, 0), fall_dir, str(def["log"]), 12, 10, 0.9)

	func _process(_delta: float) -> void:
		pass

# ---------------------------------------------------------------- the mesh cut in two
static var _splits := {}

## Splits a tree mesh at height `cut` (model units): [below, above, top height, trunk radius at the cut].
## Each triangle goes to the side its middle is on (the seam is hidden by the cut discs). Cached per mesh.
static func split_mesh(mesh: Mesh, cut: float) -> Array:
	var key := "%d_%.3f" % [mesh.get_instance_id(), cut]
	if _splits.has(key):
		return _splits[key]
	var lo := ArrayMesh.new()
	var hi := ArrayMesh.new()
	var top := 0.0
	var rads: Array = []
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		else:
			idx = PackedInt32Array()
			idx.resize(vs.size())
			for i in vs.size():
				idx[i] = i
		var il := PackedInt32Array()
		var ih := PackedInt32Array()
		for t in range(0, idx.size() - 2, 3):
			var a: Vector3 = vs[idx[t]]
			var b: Vector3 = vs[idx[t + 1]]
			var c: Vector3 = vs[idx[t + 2]]
			var cy := (a.y + b.y + c.y) / 3.0
			top = maxf(top, maxf(a.y, maxf(b.y, c.y)))
			if cy < cut:
				il.append_array([idx[t], idx[t + 1], idx[t + 2]])
			else:
				ih.append_array([idx[t], idx[t + 1], idx[t + 2]])
			# the trunk's girth just under the cut (bark near the axis only, not roots or low branches)
			for v in [a, b, c]:
				if v.y > cut - 0.12 and v.y < cut + 0.12:
					var rr := Vector2(v.x, v.z).length()
					if rr < 0.9:
						rads.append(rr)
		var mat := mesh.surface_get_material(si)
		for pair in [[lo, il], [hi, ih]]:
			if (pair[1] as PackedInt32Array).size() < 3:
				continue
			var a2 := arr.duplicate()
			a2[Mesh.ARRAY_INDEX] = pair[1]
			(pair[0] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
			(pair[0] as ArrayMesh).surface_set_material((pair[0] as ArrayMesh).get_surface_count() - 1, mat)
	# the trunk's girth: most of the bark there, not the odd root or branch stub
	var r_cut := 0.35
	if rads.size() > 6:
		rads.sort()
		r_cut = float(rads[int(rads.size() * 0.75)])
	var out := [lo, hi, top, r_cut]
	_splits[key] = out
	return out
