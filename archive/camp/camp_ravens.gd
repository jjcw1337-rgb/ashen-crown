class_name CampRavens
extends Node3D
## The camp's ravens (Raven): a handful sitting about the rooftops (the stalls, tents, the gatehouse, the Gilded Hall,
## the lantern posts) and pecking on the ground by the fire and in the square. Each sits a while doing what ravens
## do, then flies off to another roost; one that a hero (or a passing keeper or guard) comes too close to springs off
## with a clatter of wings, and the others nearby may go up with it. Roosts are found on the roofs themselves: the
## highest surface of each building's mesh under a few points along its ridge (ForestCamp registers them, meta
## "roosts"), worked out a few per frame once the camp is up. Local and cosmetic: each game has its own.

const COUNT := 7
const SPOOK := 3.6            # a hero this close puts a grounded raven up (roof birds sit tighter)
const SPOOK_ROOF := 2.2
const STAY := Vector2(9.0, 30.0)

var world: World
var ravens: Array = []
var roosts: Array = []        # {p: Vector3, yaw, ground, bird}
var _todo: Array = []         # roof nodes still to be measured
var _stay := {}               # raven -> seconds left on its roost
var _ready_done := false

static func add_to(w: World) -> CampRavens:
	if not ResourceLoader.exists(Raven.GLB) or not w.has_meta("roosts"):
		return null
	var cr := CampRavens.new()
	cr.name = "ravens"
	cr.world = w
	w.add_child(cr)
	return cr

func _ready() -> void:
	_todo = (world.get_meta("roosts") as Array).duplicate()
	# ground spots: round the bonfire and the square, in the open
	var c := Vector3(ForestCamp.CENTER.x, 0, ForestCamp.CENTER.y)
	var tries := 0
	var n := 0
	while n < 9 and tries < 200:
		tries += 1
		var a := randf() * TAU
		var r := randf_range(ForestCamp.WP_CLEAR + 0.5, 15.0)
		var p := c + Vector3(cos(a), 0, sin(a)) * r
		if world.solid_at(p.x, p.z, 0.6):
			continue
		p.y = world.height_at(p.x, p.z)
		roosts.append({"p": p, "yaw": randf() * TAU, "ground": true, "bird": null})
		n += 1

func _process(delta: float) -> void:
	# measure a roof or two a frame until they're all known, then let the birds in
	if not _todo.is_empty():
		for i in 2:
			if _todo.is_empty():
				break
			_measure(_todo.pop_back())
		return
	if not _ready_done:
		_ready_done = true
		_spawn()
	var heroes := get_tree().get_nodes_in_group("hero")
	var movers: Array = []
	for h in heroes:
		movers.append((h as Node3D).global_position)
	for it in get_tree().get_nodes_in_group("camp_walker"):
		movers.append((it as Node3D).global_position)
	for r in ravens:
		var rv: Raven = r
		rv.tick(delta)
		if rv.flying():
			continue
		var left: float = float(_stay.get(rv, 10.0)) - delta
		_stay[rv] = left
		var near := 99.0
		for m in movers:
			near = minf(near, Vector2((m as Vector3).x - rv.at.x, (m as Vector3).z - rv.at.z).length())
		var spooked := near < (SPOOK if rv.ground else SPOOK_ROOF)
		if spooked or left <= 0.0:
			_relocate(rv, spooked)
			if spooked:
				# its neighbours on the ground may go up with it
				for o in ravens:
					var ov: Raven = o
					if ov != rv and not ov.flying() and ov.ground and ov.at.distance_to(rv.at) < 4.0 and randf() < 0.6:
						_relocate(ov, true)

func _spawn() -> void:
	var free := roosts.duplicate()
	free.shuffle()
	for i in mini(COUNT, free.size()):
		var rs: Dictionary = free[i]
		var rv := Raven.make()
		add_child(rv)
		rv.on_caw = Callable(self, "_caw")
		rv.perch_at(rs["p"], float(rs["yaw"]), bool(rs["ground"]))
		rs["bird"] = rv
		ravens.append(rv)
		_stay[rv] = randf_range(2.0, STAY.y)

## Off to another free roost: far from what spooked it, now and then out over the wall and back in.
func _relocate(rv: Raven, spooked: bool) -> void:
	var cur: Dictionary = {}
	for rs in roosts:
		if rs["bird"] == rv:
			cur = rs
	var best: Dictionary = {}
	var score := -1e9
	for rs in roosts:
		if rs["bird"] != null:
			continue
		var p: Vector3 = rs["p"]
		var d := p.distance_to(rv.at)
		if d < 3.0 or d > 32.0:
			continue
		var s := randf() * 10.0 - absf(d - 12.0) * 0.3 + (6.0 if spooked and not bool(rs["ground"]) else 0.0)
		if s > score:
			score = s
			best = rs
	if best.is_empty():
		_stay[rv] = 4.0
		return
	if not cur.is_empty():
		cur["bird"] = null
	best["bird"] = rv
	rv.fly_to(best["p"], bool(best["ground"]))
	rv.yaw = float(best["yaw"])
	_stay[rv] = randf_range(STAY.x, STAY.y)
	_sound("raven_wings", rv.global_position, -6.0 if spooked else -12.0)

func _caw(rv: Raven) -> void:
	_sound("raven_caw", rv.global_position + Vector3(0, 0.3, 0), -6.0)

func _sound(nm: String, at: Vector3, db: float) -> void:
	if nm == "":
		return
	var sfx: Node = get_tree().root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call("play_at", nm, at, db, randf_range(0.92, 1.08))

## A building's roosts: the highest surface of its meshes under points along its long axis (the ridge), and the
## corners of its top for the smaller ones.
func _measure(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var tris := PackedVector3Array()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var xf := m.global_transform
		var f := m.mesh.get_faces()
		for v in f:
			var p: Vector3 = xf * v
			tris.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
	if tris.is_empty() or hi.y - lo.y < 1.2:
		return
	var yaw := node.global_rotation.y
	var ax := Vector3(cos(yaw), 0, -sin(yaw))      # the node's own x
	var mid := (lo + hi) * 0.5
	var ext := Vector2(hi.x - lo.x, hi.z - lo.z).length() * 0.3
	for k in [-0.7, 0.0, 0.65]:
		var q: Vector3 = mid + ax * ext * float(k) + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
		var top := _top(tris, q.x, q.z, hi.y + 1.0)
		if top > lo.y + 1.2:
			roosts.append({"p": Vector3(q.x, top + 0.02, q.z), "yaw": yaw + (PI * 0.5 if randf() < 0.5 else -PI * 0.5) + randf_range(-0.4, 0.4),
				"ground": false, "bird": null})

static func _top(tris: PackedVector3Array, x: float, z: float, from_y: float) -> float:
	var best := -INF
	var o := Vector3(x, from_y, z)
	var i := 0
	while i + 2 < tris.size():
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		if x < minf(a.x, minf(b.x, c.x)) or x > maxf(a.x, maxf(b.x, c.x)) or z < minf(a.z, minf(b.z, c.z)) or z > maxf(a.z, maxf(b.z, c.z)):
			continue
		var hit = Geometry3D.ray_intersects_triangle(o, Vector3.DOWN, a, b, c)
		if hit != null and (hit as Vector3).y > best:
			best = (hit as Vector3).y
	return best
