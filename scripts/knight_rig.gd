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
var hair_bones: Array = []  # long-hair sway bones (the Meshy knight), top to bottom
var hair_rest: Array = []
var hair_ang: Array = [0.0, 0.0]
var hair_vel: Array = [0.0, 0.0]
var hair_side: Array = [0.0, 0.0]
var hair_side_vel: Array = [0.0, 0.0]

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

## Long hair: two springs per bone (swing back/forward and side to side). Running streams it back
## behind him, every footfall bounces it, turning and strafing swing it sideways, and a slow gusting
## wind keeps it alive while he stands. Positive x rotation swings the hair forward (the rig faces -z).
var _hair_head_last := Vector3.ZERO
var _hair_head_vy := 0.0
func _sway_hair(fwd_speed: float, side_speed: float, t: float, dt: float) -> void:
	# the head's vertical speed: a drop then a sudden stop (a footfall) kicks the hair
	var hp: Vector3 = (proxy_of[2] as Node3D).global_position if proxy_of.has(2) else global_position
	var vy := (hp.y - _hair_head_last.y) / dt
	if _hair_head_last == Vector3.ZERO or absf(vy) > 20.0:
		vy = 0.0
	_hair_head_last = hp
	var jolt := clampf(vy - _hair_head_vy, -2.0, 2.0)
	_hair_head_vy = vy
	var run := clampf(fwd_speed / 4.5, -0.4, 1.2)
	for k in hair_bones.size():
		var gust := (sin(t * 1.3 + k * 0.7) * 0.6 + sin(t * 2.9 + 1.7) * 0.4) * (0.5 + 0.5 * sin(t * 0.31))
		var target := -run * (0.42 if k == 0 else 0.3) - gust * 0.06 * (1.0 - clampf(run, 0.0, 1.0) * 0.5)
		var stiff := 26.0 - k * 7.0
		var damp := 4.2 - k * 1.0
		hair_vel[k] += jolt * (1.2 if k == 0 else 1.6) * clampf(absf(run) + 0.2, 0.0, 1.0)
		var acc: float = (target - hair_ang[k]) * stiff - hair_vel[k] * damp
		hair_vel[k] += acc * dt
		hair_ang[k] = clampf(hair_ang[k] + hair_vel[k] * dt, -0.62 if k == 0 else -0.45, 0.3)
		var st := clampf(side_speed * 0.09, -0.35, 0.35) + sin(t * 1.7 + k * 1.3) * 0.035 + sin(t * 5.6 + k) * 0.03 * clampf(run, 0.0, 1.0)
		var acc2: float = (st - hair_side[k]) * stiff - hair_side_vel[k] * damp
		hair_side_vel[k] += acc2 * dt
		hair_side[k] += hair_side_vel[k] * dt
		var b: int = hair_bones[k]
		skel.set_bone_pose_position(b, hair_rest[k])
		skel.set_bone_pose_rotation(b, Quaternion.from_euler(Vector3(hair_ang[k], 0.0, hair_side[k])))
