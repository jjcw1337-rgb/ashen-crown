class_name MeshyRig
extends RefCounted
## A Meshy model on a skeleton made from a joint layout (Godot axes, model space; each joint names its parent): the
## model's skinned meshes re-bound to the layout's bones by name, a rim of light on its materials. Every Meshy monster
## (MeshyMonster) and the Warlock's gnome body stand on it; King Grubb's goblins have their own (Goblin).

## A rig for an imported, skinned model (a .glb rigged in Blender with bones named like our joints):
## joint nodes from a layout {joint: [parent, model-space position (Godot axes)]}, a Skeleton3D that
## mirrors them (knight_rig.gd copies the joints onto the bones each frame) and the glb's mesh re-bound
## to it by bone name. aim {joint: other joint}: the joint's rest turns its -Y toward the other (an
## A-pose arm), so Anim's zero pose hangs that limb straight down; "=joint" copies that joint's rest
## orientation (a hand lined up with its forearm). key caches the mesh and skin.
static func build(layout: Dictionary, glb: String, key: String, aim := {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Rig"
	root.set_script(load("res://game/systems/bodies/knight_rig.gd"))
	var J := {}
	var G := {}
	for n in layout.keys():
		var at: Vector3 = layout[n][1]
		var b := Basis()
		if aim.has(n) and String(aim[n]).begins_with("="):
			b = (G[String(aim[n]).substr(1)] as Transform3D).basis
		elif aim.has(n):
			var y := -((layout[aim[n]][1] as Vector3) - at).normalized()
			var x := (Vector3.RIGHT - y * Vector3.RIGHT.dot(y)).normalized()
			b = Basis(x, y, x.cross(y))
		G[n] = Transform3D(b, at)
	for n in layout.keys():
		var par: String = layout[n][0]
		var nd := Node3D.new()
		nd.name = n
		nd.transform = G[n] if par == "" else (G[par] as Transform3D).affine_inverse() * (G[n] as Transform3D)
		(J[par] if par != "" else root).add_child(nd)
		J[n] = nd
	J["hips_y"] = (layout["hips"][1] as Vector3).y
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	root.add_child(skel)
	var bones: Array = layout.keys()
	var bi := {}
	for i in bones.size():
		skel.add_bone(bones[i])
		bi[bones[i]] = i
	var proxies := {}
	for i in bones.size():
		var n: Node3D = J[bones[i]]
		var par := n.get_parent()
		if par != root:
			skel.set_bone_parent(i, bi[String(par.name)])
		skel.set_bone_rest(i, n.transform)
		skel.set_bone_pose_position(i, n.position)
		skel.set_bone_pose_rotation(i, n.quaternion)
		proxies[i] = n
	if not _bodies.has(key):
		_bodies[key] = mesh_of(glb, bi)
		_skins[key] = skel.create_skin_from_rest_transforms()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = _bodies[key]
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = _skins[key]
	root.set("skel", skel)
	root.set("proxy_of", proxies)
	root.set_meta("j", J)
	return root

static var _bodies := {}
static var _skins := {}

## A model's skinned meshes as one ArrayMesh, its bones renumbered to the skeleton's (`bi`: bone name -> index).
static func mesh_of(path: String, bi: Dictionary) -> ArrayMesh:
	var scene: Node = ResCache.inst(path)
	var out := ArrayMesh.new()
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var src: MeshInstance3D = n
		var skin: Skin = src.skin
		var skel := src.get_node_or_null(src.skeleton) as Skeleton3D
		var remap := {}
		if skin != null:
			for b in skin.get_bind_count():
				var nm := String(skin.get_bind_name(b))
				if nm == "" and skel != null:
					nm = skel.get_bone_name(skin.get_bind_bone(b))
				remap[b] = bi.get(nm, 0)
		for si in src.mesh.get_surface_count():
			var arr: Array = src.mesh.surface_get_arrays(si)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			if arr[Mesh.ARRAY_BONES] != null:
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				for i in bones.size():
					bones[i] = remap.get(bones[i], 0)
				arr[Mesh.ARRAY_BONES] = bones
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mat: Material = src.mesh.surface_get_material(si)
			if mat is StandardMaterial3D:
				# a touch of rim light so his silhouette reads against the dark
				mat = mat.duplicate()
				(mat as StandardMaterial3D).rim_enabled = true
				(mat as StandardMaterial3D).rim = 0.35
				(mat as StandardMaterial3D).rim_tint = 0.6
			out.surface_set_material(out.get_surface_count() - 1, mat)
	scene.free()
	out.set_meta("imported", true)
	return out
