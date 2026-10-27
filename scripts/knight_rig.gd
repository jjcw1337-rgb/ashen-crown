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
var hair_mat: ShaderMaterial    # LongHair material, when the hero has long hair
var hair_node: Node3D
var _hair_last := Vector3.ZERO
var _hair_off := Vector3.ZERO
var _hair_vel := Vector3.ZERO
var _hair_clock := 0.0
var fixed_dt := 0.0      # tools set this to step the springs at a fixed rate

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
	if dt > 0.0 and hair_mat != null and is_instance_valid(hair_node) and hair_node.is_inside_tree():
		_update_hair(dt)
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

## Long hair: a damped spring on where the hair tips hang (below and behind the head), so the
## hair trails behind when the hero runs, turns or swings, then settles; wind comes in head space.
func _update_hair(dt: float) -> void:
	var tip := hair_node.to_global(Vector3(0.0, -0.17, 0.07))
	var v := (tip - _hair_last) / dt
	_hair_last = tip
	if v.length() > 30.0:
		v = Vector3.ZERO
	var target := -v * 0.05
	target.y = minf(target.y, 0.01) + Vector2(v.x, v.z).length() * 0.012
	target = target.limit_length(0.17)
	_hair_vel += ((target - _hair_off) * 45.0 - _hair_vel * 6.0) * dt
	_hair_off += _hair_vel * dt
	_hair_off = _hair_off.limit_length(0.2)
	var inv := hair_node.global_transform.basis.inverse()
	_hair_clock += dt
	hair_mat.set_shader_parameter("clock", _hair_clock)
	hair_mat.set_shader_parameter("sway", inv * _hair_off)
	hair_mat.set_shader_parameter("wind", (inv * LongHair.WIND.normalized()).normalized())
