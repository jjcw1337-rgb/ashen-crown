class_name DoppelDougFx
extends RefCounted
## What Doppel-Doug looks like (DougFx hands its events here): "start" puffs confetti, fades him (unseen by his
## partners, a ghost to himself, for "x" seconds) and sends off this game's own balloon double of him (his model with a
## balloon's sheen, running, for "r" seconds); "pop" bursts it in confetti. Draws only: the double its rules run is
## DoppelDoug's.

static var _balloon_sh: Shader     # one for every cast (a new Shader per cast compiled again each time)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev.get("e", "")):
		"start":
			DougFx.confetti(root, ev["p"] + Vector3(0, 1.0, 0), 1.0)
			SkillFx.snd(h, "portal", -6.0, 1.6)
			h.fxs["hide_t"] = float(ev.get("x", 1.8))
			var d := _double(h)
			if d != null:
				root.add_child(d)
				d.global_position = ev["p"]
				var dir: Vector3 = ev.get("d", h.facing())
				d.rotation.y = atan2(-dir.x, -dir.z)
				d.set_meta("d", dir)
				d.set_meta("t", float(ev.get("r", 3.0)))
				h.fxs["double"] = d
		"pop":
			var dn = h.fxs.get("double")
			if dn != null and is_instance_valid(dn):
				dn.queue_free()
			h.fxs.erase("double")
			DougFx.confetti(root, ev["p"] + Vector3(0, 1.0, 0), 1.3)
			Fx.ring(root, ev["p"], Skill.num("doppel", "pop_r", 3.0), Color(1.0, 0.85, 0.3), 0.4)
			SkillFx.snd(h, "doug_pop", 0.0)
		_:
			return false
	return true

## His balloon double: his own model, shiny (a balloon sheen over his colours), running.
static func _double(_h: Hero) -> Node3D:
	if not DougBody.model_ok():
		return null
	var d: Node3D = ResCache.inst(DougBody.GLB)
	var root := Node3D.new()
	root.add_child(d)
	if _balloon_sh == null:
		_balloon_sh = Shader.new()
		_balloon_sh.code = """shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
void fragment() {
	vec3 base = texture(tex, UV).rgb;
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = base * 1.1;
	ROUGHNESS = 0.08;
	SPECULAR = 1.0;
	EMISSION = vec3(1.0, 0.95, 0.85) * fr * 0.6;
}"""
	for mi in d.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src := mesh.surface_get_material(si) as BaseMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = _balloon_sh
			if src != null and src.albedo_texture != null:
				sm.set_shader_parameter("tex", src.albedo_texture)
			(mi as MeshInstance3D).set_surface_override_material(si, sm)
	var ap := d.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.has_animation("run"):
		ap.play("run")
	return root

## Every frame: this game's double runs on (ending itself if the pop is lost), and he fades while he's unseen.
static func update(h: Hero, delta: float) -> void:
	if h.fxs.has("double"):
		var d = h.fxs["double"]
		if d == null or not is_instance_valid(d):
			h.fxs.erase("double")
		else:
			d.global_position = h.game.world.move(d.global_position, (d.get_meta("d") as Vector3) * Skill.num("doppel", "speed", 4.2) * delta, 0.4)
			d.set_meta("t", float(d.get_meta("t")) - delta)
			if float(d.get_meta("t")) < -0.5:
				d.queue_free()          # (a partner's copy ends itself if the pop is lost)
				h.fxs.erase("double")
	if h.fxs.has("hide_t"):
		var t := float(h.fxs["hide_t"]) - delta
		h.fxs["hide_t"] = t
		# unseen: his partners see nothing of him, he sees himself as a ghost
		var a := 0.0 if h.puppet else 0.35
		if t <= 0.0:
			a = 1.0
			h.fxs.erase("hide_t")
		_alpha(h, a)

static func _alpha(h: Hero, a: float) -> void:
	h.rig.visible = a > 0.01
	for mi in h.rig.find_children("*", "MeshInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = 1.0 - a

static func clear(h: Hero) -> void:
	var d = h.fxs.get("double")
	if d != null and is_instance_valid(d):
		d.queue_free()
	if h.fxs.has("hide_t"):
		_alpha(h, 1.0)
