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
