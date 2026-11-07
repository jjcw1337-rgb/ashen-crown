class_name BearBrain
extends RefCounted
## The bear's brain (host side): it grazes and wanders while nothing is near (idle), then rears, roars and fights
## (combat). Enemy calls it for a bear.

## Ambling about its home ground (wider than most monsters'), stopping every so often to rear up and roar.
static func idle(en: Enemy, delta: float) -> Vector3:
	en.b_idle_t -= delta
	if en.b_idle_t <= 0.0:
		en.b_idle_t = randf_range(14.0, 26.0)
		if en.move_amt < 0.3 and en.global_position.distance_to(en.home) < 12.0:
			en._begin_special("bear_roar")
			return Vector3.ZERO
	en.wander_t -= delta
	if en.wander_t <= 0.0:
		en.wander_t = randf_range(3.0, 7.0)
		en.wander_to = en.game.world.free_spot_near(en.home, 9.0) if randf() < 0.7 else en.global_position
	var d := en.wander_to - en.global_position
	d.y = 0
	if d.length() < 0.4:
		return Vector3.ZERO
	return d.normalized() * en.speed * (0.45 if d.length() > 12.0 else 0.32)

## On noticing a hero it rears and roars once, then charges and mauls, and keeps at it until one of them dies;
## it gives up only when led more than 30 m from home.
static func combat(en: Enemy, delta: float, hero: Node3D, to: Vector3, dist: float) -> Vector3:
	if not en.b_roared:
		en.b_roared = true
		en._face(to)
		en.rig.rotation.y = atan2(-to.x, -to.z)
		en._begin_special("bear_roar")
		return Vector3.ZERO
	if en.global_position.distance_to(en.home) > 30.0:
		en.aggro = false
		en.b_roared = false
		en.f_calm = 6.0
		en.wander_to = en.home
		en.wander_t = 8.0
		return Vector3.ZERO
	if dist <= en.def["range"] + hero.radius * 0.5:
		if en.cooldown <= 0.0:
			en._face(to)
			en._begin_special("bear_maul")
		return Vector3.ZERO
	return en.go_to(delta, hero.global_position, en.speed * 1.5)
