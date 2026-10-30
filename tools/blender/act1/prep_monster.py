# Prepares a raw Meshy monster (A-pose, textured) for rig_monster.py: joins its meshes, cuts away a display base
# under the feet, decimates, scales it to its height and stands it on z = 0, then exports a glb.
#   blender -b --python prep_monster.py -- <in.glb> <out.glb> <height m> [triangles, default 20000] [cut fraction]
# cut: everything below this fraction of the raw height is deleted (a stone base or ground slab: look at the
# model's slices first; 0 keeps it all).
import bpy, bmesh, sys

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, HEIGHT = argv[0], argv[1], float(argv[2])
TRIS = int(argv[3]) if len(argv) > 3 else 20000
CUT = float(argv[4]) if len(argv) > 4 else 0.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
for o in list(bpy.context.scene.objects):
    if o != body:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bm = bmesh.new()
bm.from_mesh(body.data)
z0 = min(v.co.z for v in bm.verts)
z1 = max(v.co.z for v in bm.verts)
if CUT > 0.0:
    cut_z = z0 + CUT * (z1 - z0)
    gone = [v for v in bm.verts if v.co.z < cut_z]
    bmesh.ops.delete(bm, geom=gone, context="VERTS")
    # loose bits of the base left floating (roots, pebbles) go too
    bm.verts.ensure_lookup_table()
    print("cut below %.3f: %d verts removed" % (cut_z, len(gone)))
bm.to_mesh(body.data)
bm.free()
# keep only the biggest connected piece and anything touching it (drops stray base fragments)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="DESELECT")
bpy.ops.object.mode_set(mode="OBJECT")
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
if tris > TRIS:
    m = body.modifiers.new("dec", "DECIMATE")
    m.ratio = TRIS / tris
    bpy.ops.object.modifier_apply(modifier=m.name)
zs = [v.co.z for v in body.data.vertices]
h = max(zs) - min(zs)
s = HEIGHT / h
body.scale = (s, s, s)
bpy.ops.object.transform_apply(scale=True)
zmin = min(v.co.z for v in body.data.vertices)
for v in body.data.vertices:
    v.co.z -= zmin
print("triangles %d -> %d, height %.2f m" % (tris, sum(len(p.vertices) - 2 for p in body.data.polygons), HEIGHT))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False)
