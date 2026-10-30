extends Node3D
## Runtime for the skinned warrior: copies the animation proxies onto the skeleton
## and simulates the cape with damped springs.

var skel: Skeleton3D
var proxy_of := {}          # bone index -> proxy Node3D
var cape_bones: Array = []  # bone indices, top to bottom
var cape_rest: Array = []
var cape_ang: Array = [0.0, 0.0, 0.0]
var cape_vel: Array = [0.0, 0.0, 0.0]
var cape_side: Array = [0.0, 0.0, 0.0]
var cape_side_vel: Array = [0.0, 0.0, 0.0]
var _last_pos := Vector3.ZERO
var _last_t := 0
var _vel := Vector3.ZERO
var fixed_dt := 0.0         # tools set this to step the springs at a fixed rate
var hair_bones: Array = []  # long-hair lock bones (the Meshy knight): chains of three per lock
var hair_rest: Array = []
var hair_key: Array = []    # per bone: [lock index, depth 0..2]
var head_bone := -1
var hair_ang: Array = []
var hair_vel: Array = []
var hair_side: Array = []
var hair_side_vel: Array = []
var _last_yaw := 0.0
## The armoured knight's cloak: its three panels (hA, hB, hC chains) simulated as cloth (_cloth_cloak),
## and his leg bones (leg_l, leg_r), which it can't pass through
var cloak := false

func sync() -> void:
	if skel == null:
		return
	for i in proxy_of.keys():
		var p: Node3D = proxy_of[i]
		skel.set_bone_pose_position(i, p.position)
		skel.set_bone_pose_rotation(i, p.quaternion)
		skel.set_bone_pose_scale(i, p.scale)
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_t) / 1000000.0, 0.0, 0.05)
	if fixed_dt > 0.0:
		dt = fixed_dt
	_last_t = now
	if dt <= 0.0 or (cape_bones.is_empty() and hair_bones.is_empty()) or not is_inside_tree():
		return
	var gp := global_position
	var v := (gp - _last_pos) / dt
	_last_pos = gp
	if v.length() > 30.0:
		v = Vector3.ZERO
	_vel = _vel.lerp(v, clampf(dt * 10.0, 0.0, 1.0))
	var local_v := global_transform.basis.inverse() * _vel
	var fwd_speed := -local_v.z
	var side_speed := local_v.x
	var t := now / 1000000.0
	if cloak:
		_cloth_cloak(t, dt)
	else:
		_sway_hair(fwd_speed, side_speed, t, dt)
	for k in cape_bones.size():
		var target := -clampf(fwd_speed * 0.11, -0.2, 0.75) * (1.0 if k == 0 else 0.45)
		target += sin(t * 1.3 + k * 0.9) * 0.025
		var stiff := 38.0 - k * 8.0
		var damp := 7.0 - k
		var acc: float = (target - cape_ang[k]) * stiff - cape_vel[k] * damp
		cape_vel[k] += acc * dt
		cape_ang[k] += cape_vel[k] * dt
		var st := clampf(side_speed * 0.08, -0.4, 0.4) * (1.0 if k == 0 else 0.5)
		var acc2: float = (st - cape_side[k]) * stiff - cape_side_vel[k] * damp
		cape_side_vel[k] += acc2 * dt
		cape_side[k] += cape_side_vel[k] * dt
		var b: int = cape_bones[k]
		skel.set_bone_pose_position(b, cape_rest[k])
		skel.set_bone_pose_rotation(b, Quaternion.from_euler(Vector3(cape_ang[k], 0.0, cape_side[k])))

## Long hair, in locks: each lock is a chain of three bones, each bone its own pair of springs
## (swing back/forward about x, side to side about z; positive x swings forward since the rig faces
## -z). Running streams the locks back and flares the side locks out, every footfall bounces them,
## turning swings them, and a gusting wind with per-lock timing keeps them alive when he stands.
## The lower bones are looser, so the ends lag and overlap; back locks can't swing into his neck.
var _hair_head_last := Vector3.ZERO
var _hair_head_vy := 0.0
func _sway_hair(fwd_speed: float, side_speed: float, t: float, dt: float) -> void:
	var n := hair_bones.size()
	if hair_ang.size() != n:
		hair_ang.resize(n); hair_ang.fill(0.0)
		hair_vel.resize(n); hair_vel.fill(0.0)
		hair_side.resize(n); hair_side.fill(0.0)
		hair_side_vel.resize(n); hair_side_vel.fill(0.0)
	var hp: Vector3 = skel.to_global(skel.get_bone_global_pose(head_bone).origin) if head_bone >= 0 else global_position
	var vy := (hp.y - _hair_head_last.y) / dt
	if _hair_head_last == Vector3.ZERO or absf(vy) > 20.0:
		vy = 0.0
	_hair_head_last = hp
	var jolt := clampf(vy - _hair_head_vy, -2.0, 2.0)
	_hair_head_vy = vy
	var yaw := global_rotation.y
	var yaw_v := wrapf(yaw - _last_yaw, -PI, PI) / dt
	_last_yaw = yaw
	if absf(yaw_v) > 30.0:
		yaw_v = 0.0
	var run := clampf(fwd_speed / 4.5, -0.4, 1.2)
	var calm := 1.0 - clampf(run, 0.0, 1.0) * 0.5
	for i in n:
		var lock: int = hair_key[i][0]
		var d: int = hair_key[i][1]
		var rest: Vector3 = hair_rest[i]
		var root_x: float = (hair_rest[i - d] as Vector3).x
		var side_lock := absf(root_x) > 0.09 and (hair_rest[i - d] as Vector3).z < 0.0
		var out_sign := signf(root_x) if absf(root_x) > 0.02 else 0.0
		var ph := float(lock) * 1.9
		var gust := (sin(t * 1.25 + ph) * 0.6 + sin(t * 2.7 + ph * 1.3) * 0.4) * (0.55 + 0.45 * sin(t * 0.29 + 0.7))
		var flutter := sin(t * (3.2 + d * 1.7) + ph * 2.3 + d) * (0.012 + d * 0.012)
		var tx := -run * (0.2 + d * 0.05) - gust * 0.035 * calm - flutter * calm
		var stiff := 34.0 - d * 9.0
		var damp := 4.6 - d * 1.1
		hair_vel[i] += jolt * (0.9 + d * 0.5) * clampf(absf(run) + 0.2, 0.0, 1.0)
		var acc: float = (tx - hair_ang[i]) * stiff - hair_vel[i] * damp
		hair_vel[i] += acc * dt
		var fwd_lim := 0.22 if side_lock else 0.06
		hair_ang[i] = clampf(hair_ang[i] + hair_vel[i] * dt, -0.5, fwd_lim)
		var tz := clampf(side_speed * 0.05 - yaw_v * 0.035, -0.25, 0.25) * (0.6 + d * 0.3)
		tz += out_sign * clampf(run, 0.0, 1.0) * (0.06 + d * 0.03) * (1.0 if side_lock else 0.4)
		tz += sin(t * (2.1 + d) + ph * 1.7) * (0.015 + d * 0.01) * calm
		var acc2: float = (tz - hair_side[i]) * stiff - hair_side_vel[i] * damp
		hair_side_vel[i] += acc2 * dt
		hair_side[i] = clampf(hair_side[i] + hair_side_vel[i] * dt, -0.4, 0.4)
		if out_sign != 0.0 and hair_side[i] * out_sign < -0.08:
			hair_side[i] = -0.08 * out_sign      # never swing a lock in through the head or neck
		var b: int = hair_bones[i]
		skel.set_bone_pose_position(b, rest)
		skel.set_bone_pose_rotation(b, Quaternion.from_euler(Vector3(hair_ang[i], 0.0, hair_side[i])))


# ---------------------------------------------------------------- the cloak as cloth
## The cloak is a small cloth: a grid of points, four down each of its three panels (the panel's three
## bones and the hem), the top row pinned under his shoulders. Each step the free points carry their
## momentum, fall, and are pushed by the air: a gusting wind whose direction wanders, plus the air he
## moves through, so the cloak streams out behind whichever way he goes (WASD, backing off, sidestepping)
## like a flag, harder the faster he runs, with a flutter that grows with the airflow. Lengths down and
## across the panels hold it together; it stays behind his back and out of his legs, above the ground.
## The panel bones are then turned to follow the points. Verlet steps, a few substeps a frame.
const CLOTH_ROWS := 4
const CLOTH_DRAG := 3.4          # how hard the air pushes it (per m/s of airflow)
const CLOTH_KEEP := 0.986        # momentum kept per substep
var _cp := PackedVector3Array()      # points (world), panel * CLOTH_ROWS + row
var _cpp := PackedVector3Array()     # their previous positions
var _crest := PackedVector3Array()   # each point at rest, in the torso's frame (row 0 stays pinned there)
var _cchain: Array = []              # per panel: its three bone indices, top down, and their hair_* slots
var _clen_v := PackedFloat32Array()  # rest length below each point (to the next row)
var _clen_h := PackedFloat32Array()  # rest length to the same row of the next panel
var _ctorso := -1
var _clegs: Array = []               # [hip bone, knee bone] per leg
var _cpanels := 0

func _cloth_setup() -> void:
	_ctorso = skel.find_bone("torso")
	var tinv := skel.get_bone_global_rest(_ctorso).affine_inverse()
	var locks := {}
	for i in hair_bones.size():
		var lk: int = hair_key[i][0]
		if not locks.has(lk):
			locks[lk] = [-1, -1, -1]
		locks[lk][hair_key[i][1]] = i
	var keys := locks.keys()
	keys.sort()
	_cchain = []
	var pts := []
	for lk in keys:
		var slots: Array = locks[lk]
		_cchain.append(slots)
		var p := []
		for k in 3:
			p.append(skel.get_bone_global_rest(hair_bones[slots[k]]).origin)
		p.append(p[2] + (p[2] - p[1]) * 0.9)          # the hem, below the last bone
		pts.append(p)
	_cpanels = _cchain.size()
	_crest.resize(_cpanels * CLOTH_ROWS)
	_clen_v.resize(_cpanels * CLOTH_ROWS)
	_clen_h.resize(_cpanels * CLOTH_ROWS)
	var sc: float = skel.global_transform.basis.get_scale().x
	for pi in _cpanels:
		for r in CLOTH_ROWS:
			var i := pi * CLOTH_ROWS + r
			_crest[i] = tinv * (pts[pi][r] as Vector3)
			_clen_v[i] = ((pts[pi][r + 1] as Vector3) - pts[pi][r]).length() * sc if r < CLOTH_ROWS - 1 else 0.0
			_clen_h[i] = ((pts[pi + 1][r] as Vector3) - pts[pi][r]).length() * sc if pi < _cpanels - 1 else 0.0
	_clegs = []
	for s in ["l", "r"]:
		var a := skel.find_bone("leg_" + s)
		var b := skel.find_bone("knee_" + s)
		if a >= 0 and b >= 0:
			_clegs.append([a, b])
	_cp.resize(0)

func _cloth_cloak(t: float, dt: float) -> void:
	if _cchain.is_empty() or _ctorso < 0:
		_cloth_setup()
		if _cchain.is_empty():
			return
	var tg: Transform3D = skel.global_transform * skel.get_bone_global_pose(_ctorso)
	var n := _cpanels * CLOTH_ROWS
	# a fresh start, or after a teleport (a new zone, a respawn): hang at rest
	if _cp.size() != n or (tg * _crest[0]).distance_to(_cp[0]) > 1.5:
		_cp.resize(n)
		_cpp.resize(n)
		for i in n:
			_cp[i] = tg * _crest[i]
			_cpp[i] = _cp[i]
	# the wind: gusts that rise and fall from a direction that wanders about the south-east
	var gust := clampf(0.5 + 0.35 * sin(t * 0.41) + 0.25 * sin(t * 1.07 + 1.3), 0.05, 1.0)
	var wa := 0.7 + sin(t * 0.13) * 0.8 + sin(t * 0.37 + 2.0) * 0.35
	var wind := Vector3(sin(wa), 0.0, cos(wa)) * (0.7 + 1.3 * gust)
	wind += Vector3(sin(t * 1.7), sin(t * 2.3) * 0.25, cos(t * 1.3 + 0.5)) * 0.35 * gust
	var inv := global_transform.affine_inverse()
	var ground := global_position.y + 0.04
	var legs := []
	for lg in _clegs:
		var hip: Vector3 = skel.global_transform * skel.get_bone_global_pose(lg[0]).origin
		var knee: Vector3 = skel.global_transform * skel.get_bone_global_pose(lg[1]).origin
		var ankle: Vector3 = knee + (knee - hip).normalized() * (knee - hip).length() * 1.0
		legs.append([hip, knee, ankle])
	var subs := 2 if dt > 0.02 else 1
	var h := dt / subs
	for sub in subs:
		var tt := t - dt + h * (sub + 1)
		# pinned row: under the shoulders, as the body moves
		for pi in _cpanels:
			var i := pi * CLOTH_ROWS
			_cpp[i] = _cp[i]
			_cp[i] = tg * _crest[i]
		for pi in _cpanels:
			for r in range(1, CLOTH_ROWS):
				var i := pi * CLOTH_ROWS + r
				var p := _cp[i]
				var v := (p - _cpp[i]) / maxf(h, 0.0001)
				var rel := wind - v
				var free := float(r) / float(CLOTH_ROWS - 1)
				var ph := float(pi) * 1.9 + float(r) * 1.3
				# the flutter: across the airflow, quicker and stronger as it streams
				var flap := Vector3(sin(tt * 8.3 + ph), sin(tt * 6.1 + ph * 1.7) * 0.6, cos(tt * 7.4 + ph * 0.8))
				var acc := Vector3(0, -9.8, 0) + rel * CLOTH_DRAG * (0.6 + 0.4 * free) + flap * (0.6 + rel.length() * 0.9) * free
				# a faint memory of how it hangs, so the panels keep their folds
				acc += ((tg * _crest[i]) - p) * 1.5
				var np := p + (p - _cpp[i]) * CLOTH_KEEP + acc * h * h
				_cpp[i] = p
				_cp[i] = np
		# hold it together: down each panel exactly, across the panels a little looser
		for it in 5:
			for pi in _cpanels:
				for r in CLOTH_ROWS - 1:
					var a := pi * CLOTH_ROWS + r
					_keep(a, a + 1, _clen_v[a], 1.0, r == 0)
			for pi in _cpanels - 1:
				for r in range(1, CLOTH_ROWS):
					var a := pi * CLOTH_ROWS + r
					_keep(a, a + CLOTH_ROWS, _clen_h[a], 0.6, false)
			# behind his back, out of his legs, above the ground
			for i in n:
				if i % CLOTH_ROWS == 0:
					continue
				var p := _cp[i]
				var lp := inv * p
				var zmin := 0.13 if lp.y > 0.95 else 0.08
				if lp.z < zmin:
					lp.z = zmin
					p = global_transform * lp
				for lg in legs:
					p = _out_of(p, lg[0], lg[1], 0.13)
					p = _out_of(p, lg[1], lg[2], 0.11)
				p.y = maxf(p.y, ground)
				_cp[i] = p
	# the bones follow the points: each turned from its parent so it points at the next row
	var gb := (skel.global_transform.basis * skel.get_bone_global_pose(_ctorso).basis).orthonormalized()
	for pi in _cpanels:
		var par := gb
		for k in 3:
			var slot: int = _cchain[pi][k]
			var b: int = hair_bones[slot]
			var child_off: Vector3 = skel.get_bone_rest(hair_bones[_cchain[pi][k + 1]]).origin if k < 2 else skel.get_bone_rest(b).origin
			var want := (_cp[pi * CLOTH_ROWS + k + 1] - _cp[pi * CLOTH_ROWS + k])
			if want.length() < 0.001 or child_off.length() < 0.001:
				continue
			var lw := (par.inverse() * want).normalized()
			var q := Quaternion(child_off.normalized(), lw)
			skel.set_bone_pose_position(b, hair_rest[slot])
			skel.set_bone_pose_rotation(b, q)
			par = par * Basis(q)

## Moves points a and b to rest length apart (a stays put if pinned).
func _keep(a: int, b: int, rest: float, k: float, a_pinned: bool) -> void:
	var d := _cp[b] - _cp[a]
	var l := d.length()
	if l < 0.0001:
		return
	var diff := (l - rest) / l * k
	if a_pinned:
		_cp[b] -= d * diff
	else:
		_cp[a] += d * diff * 0.5
		_cp[b] -= d * diff * 0.5

## p pushed out of the capsule from a to b of radius r.
static func _out_of(p: Vector3, a: Vector3, b: Vector3, r: float) -> Vector3:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var c := a + ab * u
	var d := p - c
	var l := d.length()
	if l >= r or l < 0.0001:
		return p
	return c + d / l * r
