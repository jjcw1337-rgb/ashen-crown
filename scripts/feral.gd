class_name Feral
## The Feral (Act I forest): a man gone wholly animal, on all fours. A Meshy model rigged and animated in
## Blender (sources/feral.blend: a 17-bone skeleton skinned by distance along the body, IK on the four
## limbs) with three baked, in-place animations: "crawl" (diagonal pairs, one hand at a time, head level),
## "lunge" (gather, launch one limb after another, leap, land the same way) and "swipe" (a rake with the
## right claw, then the left). Unlike the other monsters (Anim.pose on the shared skeleton) he plays those,
## timed by the enemy code: the crawl follows his movement, the attacks follow their progress.
##
## They wait in packs, clinging head-down to oak trunks deep in the forest (World._feral_packs); come close
## and they skitter down and come at you from all sides, one lunging at a time (Enemy._feral_combat).

const GLB := "res://assets/models/monsters/feral.glb"
## the Meshy model is 1.7 m tall crouched; this makes him a man-sized crouch (~1.3 m)
const SCALE := 0.75
## metres of ground the crawl covers per cycle at this scale (1.5 m in the source)
const STRIDE := 1.5 * SCALE
## how high up the trunk they cling, and how long they take to come down
const PERCH_H := 3.0
const DESCEND_T := 1.3

static func ok() -> bool:
	return ResourceLoader.exists(GLB)

static func build() -> Node3D:
	var root := Node3D.new()
	var body: Node3D = (load(GLB) as PackedScene).instantiate()
	body.name = "Body"
	# Blender's front (-Y) arrives facing +z; the game's monsters face -z
	body.rotation.y = PI
	body.scale = Vector3.ONE * SCALE
	root.add_child(body)
	# a crisp dark outline and a cool rim, so his pale silhouette reads against the forest floor
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = rim_mat()
		var shell := MeshInstance3D.new()
		shell.mesh = (mi as MeshInstance3D).mesh
		shell.skin = (mi as MeshInstance3D).skin
		shell.material_override = outline_mat()
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.get_parent().add_child(shell)
		shell.skeleton = shell.get_path_to(mi.get_node((mi as MeshInstance3D).skeleton))
		shell.transform = (mi as MeshInstance3D).transform
	var aps := body.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var ap: AnimationPlayer = aps[0]
		ap.speed_scale = 0.0   # timed by pose(), not by the clock
		root.set_meta("feral", ap)
	return root

static var _outline: ShaderMaterial
static var _rim: ShaderMaterial

## The back faces pushed out along their normals and drawn flat and dark: an outline that follows him.
static func outline_mat() -> ShaderMaterial:
	if _outline == null:
		_outline = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
void vertex(){ VERTEX += NORMAL * 0.012; }
void fragment(){ ALBEDO = vec3(0.025, 0.02, 0.018); }
"""
		_outline.shader = sh
	return _outline

## A thin cool light along his edges (added over the model's own material).
static func rim_mat() -> ShaderMaterial:
	if _rim == null:
		_rim = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode blend_add, unshaded, shadows_disabled;
void fragment(){
	float r = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = vec3(0.55, 0.62, 0.7) * r * 0.35;
}
"""
		_rim.shader = sh
	return _rim

## Shows the right moment of the right animation. st is the same state Anim.pose gets (phase, move,
## atk, style); height is the monster's look height.
static func pose(rig: Node3D, st: Dictionary, height: float) -> void:
	if not rig.has_meta("feral"):
		return
	var ap: AnimationPlayer = rig.get_meta("feral")
	var style: String = st.get("style", "")
	var atk: float = st.get("atk", -1.0)
	var anim := "crawl"
	var t := 0.0
	if atk >= 0.0 and style == "feral_lunge":
		anim = "lunge"
		t = atk
	elif atk >= 0.0 and style == "feral_swipe":
		anim = "swipe"
		t = atk
	elif style == "descend":
		t = fmod(maxf(atk, 0.0) * 3.0, 1.0)            # three quick steps down the trunk
	elif style == "perch":
		t = 0.08 + 0.02 * sin(float(st.get("time", 0.0)) * 1.3)   # gripping, barely breathing
	else:
		# the crawl keeps pace with the ground he covers (phase grows 1.6 / height per metre)
		var per_cycle := STRIDE * 1.6 / maxf(height, 0.3)
		t = fposmod(float(st.get("phase", 0.0)) / per_cycle, 1.0)
	if ap.current_animation != anim:
		ap.play(anim)
	ap.seek(t * ap.get_animation(anim).length, true)

## Clinging to a trunk (style "perch"), or part way down it ("descend", atk = progress): how far above
## the ground he is, and his body tipped head-down against the bark.
static func perch_pose(rig: Node3D, style: String, atk: float) -> float:
	if style == "perch":
		rig.rotation.x = -PI * 0.5
		return PERCH_H
	if style == "descend":
		var p := clampf(atk, 0.0, 1.0)
		rig.rotation.x = -PI * 0.5 * (1.0 - smoothstep(0.78, 1.0, p))
		return PERCH_H * (1.0 - smoothstep(0.0, 0.9, p))
	rig.rotation.x = 0.0
	return 0.0
