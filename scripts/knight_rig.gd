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
	_last_t = now
	if dt <= 0.0 or cape_bones.is_empty() or not is_inside_tree():
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
