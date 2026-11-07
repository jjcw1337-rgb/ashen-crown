"""Breaks a rock model into real pieces for an impact: Voronoi cells cut out of the mesh itself, each closed with
a molten interior (a second material, "Interior", for the game's hot-core shader), its origin at its own centre.

    blender -b --python tools/blender/fx/fracture_rock.py -- <in.glb> <out.glb> [pieces] [seed]

Every cell is the rock clipped by the bisecting planes toward every other seed point (bmesh bisect + fill), so
the pieces fit back together exactly. Seeds are biased toward the middle so a few big chunks come with smaller
shards round them. The game (BrimstoneHurlFx, DemonFx's meteors) swaps the whole rock for its pieces at the moment of
impact and throws them.
"""
import bpy
import bmesh
import sys
import random
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
N = int(argv[2]) if len(argv) > 2 else 11
random.seed(int(argv[3]) if len(argv) > 3 else 7)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
	o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
	bpy.ops.object.join()
rock = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
# centre on its bounds
bb = [Vector(c) for c in rock.bound_box]
mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
centre = (mn + mx) * 0.5
size = mx - mn
rock.data.transform(__import__("mathutils").Matrix.Translation(-centre))
rock.location = (0, 0, 0)

# the interior material (a plain slot; the game puts its own molten shader on it)
inner = bpy.data.materials.new("Interior")
inner.use_nodes = True
inner.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.9, 0.3, 0.05, 1.0)
rock.data.materials.append(inner)
inner_idx = len(rock.data.materials) - 1

# seeds inside the rock's bounds, biased to the middle
seeds = []
while len(seeds) < N:
	p = Vector((random.uniform(-0.5, 0.5) * size.x, random.uniform(-0.5, 0.5) * size.y, random.uniform(-0.5, 0.5) * size.z))
	p *= random.uniform(0.35, 1.0)
	if all((p - q).length > min(size) * 0.18 for q in seeds):
		seeds.append(p)

src_bm = bmesh.new()
src_bm.from_mesh(rock.data)
pieces = []
for i, s in enumerate(seeds):
	bm = src_bm.copy()
	for j, t in enumerate(seeds):
		if i == j:
			continue
		mid = (s + t) * 0.5
		nrm = (t - s).normalized()
		geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
		res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=mid, plane_no=nrm, clear_outer=True)
		cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
		if cut_edges:
			filled = bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
			for f in filled.get("faces", []):
				f.material_index = inner_idx
	if len(bm.faces) < 4:
		bm.free()
		continue
	bmesh.ops.triangulate(bm, faces=bm.faces[:])
	me = bpy.data.meshes.new("chunk_%d" % i)
	bm.to_mesh(me)
	bm.free()
	for m in rock.data.materials:
		me.materials.append(m)
	ob = bpy.data.objects.new("chunk_%d" % i, me)
	bpy.context.scene.collection.objects.link(ob)
	# origin at its own centre (it spins about it when thrown)
	c = sum((v.co for v in me.vertices), Vector()) / max(len(me.vertices), 1)
	me.transform(__import__("mathutils").Matrix.Translation(-c))
	ob.location = c
	pieces.append(ob)
	print("PIECE", ob.name, len(me.polygons), "faces at", tuple(round(x, 3) for x in c))
src_bm.free()
bpy.data.objects.remove(rock, do_unlink=True)
for o in bpy.context.scene.objects:
	o.select_set(o in pieces)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True)
print("FRACTURED", OUT, len(pieces), "pieces, rock size", tuple(round(x, 2) for x in size))
