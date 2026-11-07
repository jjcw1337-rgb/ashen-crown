class_name RimeLanceFx
extends RefCounted
## Rime Lance's look (RimeLance, "spikes"): a line of the Meshy ice crystals bursting up one after another along it,
## then shattering. Draws only.

static func play(h: Hero, ev: Dictionary) -> bool:
	if str(ev["e"]) != "spikes":
		return false
	var root: Node3D = h.game.world.fx_root
	var game = h.game
	var p: Vector3 = ev["p"]
	var d: Vector3 = ev["d"]
	var ln: float = float(ev.get("x", 10.0))
	var tr := InfernalFx.tier(game)
	var step: float = [1.6, 1.3, 1.1, 1.0][tr]
	var k := 0
	var along := 1.2
	while along <= ln:
		var side := Vector3(d.z, 0, -d.x) * randf_range(-0.35, 0.35)
		var at: Vector3 = p + d * along + side
		at.y = game.world.height_at(at.x, at.z)
		_spike(h, root, at, randf_range(0.55, 0.85) + along / ln * 0.25, k * 0.045, tr)
		along += step
		k += 1
	SkillFx.snd(h, "ice_burst", -2.0, 1.1)
	SkillFx.shake(h, 0.18)
	return true

## One of its crystals: up after `delay`, shattered a moment later.
static func _spike(h: Hero, root: Node3D, at: Vector3, s: float, delay: float, tr: int) -> void:
	var tw := root.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if not is_instance_valid(root):
			return
		var c := FrostFx.crystal(root, at, s, tr)
		if c == null:
			return
		var t2 := c.create_tween()
		t2.tween_interval(0.9 + randf() * 0.3)
		t2.tween_callback(func():
			if is_instance_valid(c) and is_instance_valid(h):
				FrostFx.smash(root, h.game.world, c, tr)))
