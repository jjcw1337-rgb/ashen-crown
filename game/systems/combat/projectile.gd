class_name Projectile
extends Node3D
## Enemy projectiles: arrows, darts, fireballs and poison orbs. Blockable with a shield.

var game: Node
var kind := "arrow"
var vel := Vector3.ZERO
var dmg := 5.0
var life := 3.0
var element := "phys"
var visual_only := false  # co-op: the host decides hits; this copy only shows the flight

func launch(g: Node, k: String, from: Vector3, to: Vector3, damage: float) -> void:
	game = g
	kind = k
	dmg = damage
	global_position = from
	var d := (to - from)
	var sp := 16.0
	match k:
		"arrow":
			sp = 17.0
			var shaft := Models.seg(self, Vector3(0, 0, 0.35), Vector3(0, 0, -0.35), 0.012, 0.012, Mats.mat(Color(0.4, 0.3, 0.2), 0.8), 4)
			var tip := Models.P(self, Geo.cone(0.03, 0.08, 4), Mats.mat(Color(0.5, 0.5, 0.5), 0.4, 0.8), Vector3(0, 0, -0.38), Vector3(-90, 0, 0))
			Models.P(self, Geo.box(0.06, 0.005, 0.1), Mats.mat(Color(0.8, 0.8, 0.75), 0.9), Vector3(0, 0, 0.3))
		"dart":
			sp = 19.0
			Models.seg(self, Vector3(0, 0, 0.12), Vector3(0, 0, -0.12), 0.008, 0.004, Mats.mat(Color(0.3, 0.5, 0.2), 0.8), 4)
			Models.P(self, Geo.sph(0.03, 6), Mats.glow(Color(0.5, 1.0, 0.3), 2.0), Vector3(0, 0, 0.12))
		"fireball", "poison":
			sp = 10.0
			element = "fire"
			var col := Color(1.0, 0.45, 0.1) if k == "fireball" else Color(0.4, 1.0, 0.3)
			Models.P(self, Geo.sph(0.18, 10), Mats.glow(col, 4.0))
			Models.P(self, Geo.sph(0.3, 10), Mats.glow(col, 1.0, 0.0, 1.0))
			var tr := GPUParticles3D.new()
			tr.amount = 30
			tr.lifetime = 0.5
			tr.local_coords = false
			var pm := ParticleProcessMaterial.new()
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.12
			pm.gravity = Vector3(0, 1.5, 0)
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.4
			var g2 := Gradient.new()
			g2.set_color(0, Color(col.r, col.g, col.b, 0.9))
			g2.set_color(1, Color(col.r * 0.5, col.g * 0.3, 0.0, 0.0))
			var gt := GradientTexture1D.new()
			gt.gradient = g2
			pm.color_ramp = gt
			tr.process_material = pm
			var q := QuadMesh.new()
			q.size = Vector2(0.3, 0.3)
			q.material = Mats.particle_mat(true, Color(2, 2, 2))
			tr.draw_pass_1 = q
			add_child(tr)
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 1.5
			l.omni_range = 4.0
			add_child(l)
	vel = d.normalized() * sp
	if vel.length() > 0.01:
		look_at(global_position + vel, Vector3.UP)

func _process(delta: float) -> void:
	if game == null or game.world == null:
		return
	life -= delta
	global_position += vel * delta
	var p := global_position
	if life <= 0.0 or game.world.solid_at(p.x, p.z) and p.y < 2.5:
		_explode(false)
		return
	for hero in game.all_heroes():
		if hero.dead or not hero.visible:
			continue
		var hp: Vector3 = hero.global_position + Vector3(0, 1.1, 0)
		if p.distance_to(hp) < 0.65:
			if not visual_only:
				hero.take_hit(dmg, p - vel.normalized(), "proj", element)
			_explode(true)
			return

func _explode(hit: bool) -> void:
	if kind in ["fireball", "poison"]:
		var col := Color(1.0, 0.5, 0.1) if kind == "fireball" else Color(0.4, 1.0, 0.3)
		Fx.burst(game.world.fx_root, global_position, col, 24, 4.0, 0.2, 0.5, true, 0.0)
		Fx.flash(game.world.fx_root, global_position, col, 2.0, 0.25)
	elif not hit:
		Fx.burst(game.world.fx_root, global_position, Color(0.6, 0.55, 0.45, 0.8), 6, 1.5, 0.08, 0.3, false, -6.0)
	queue_free()
