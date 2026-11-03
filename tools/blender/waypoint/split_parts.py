# Post-process a re-baked waypoint prop (after tools/blender/camp/rebake_prop.py), waypoint overhaul stage 2.
#
#   blender -b --python split_parts.py -- <in.glb> <out.glb> crystal [r_crystal] | flame <top_fraction>
#
# crystal: Meshy's crystal comes as one model (socket, crystal, orbiting shards). Splits it by loose parts into
#   objects "socket" (below the empty band over it, stays put), "crystal" (faces within [r_crystal] 0.42 m of the
#   axis above it; origin at its centre so the game can float and spin it) and "shards" (the rest above, origin on
#   the crystal's centre so they orbit it). Prints CRYSTAL_CENTER x y z (Godot axes, metres).
# flame: Meshy models fire as solid blobs. Finds the widest slice in the top <top_fraction> of the model (a
#   brazier's bowl rim, a torch's cup) and deletes everything above it; the game's particles are the fire.
#   Prints RIM y (Godot axes).
import bpy, bmesh, sys
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, MODE = a[0], a[1], a[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def bbox(o):
    ws = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = Vector((min(w.x for w in ws), min(w.y for w in ws), min(w.z for w in ws)))
    hi = Vector((max(w.x for w in ws), max(w.y for w in ws), max(w.z for w in ws)))
    return lo, hi

if MODE == "flame":
    frac = float(a[3]) if len(a) > 3 else 0.4
    lo, hi = bbox(ob)
    h = hi.z - lo.z
    z0 = hi.z - h * frac
    bins = 60
    width = [0.0] * bins
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    for v in ob.data.vertices:
        if v.co.z >= z0:
            i = min(bins - 1, int((v.co.z - z0) / (hi.z - z0) * bins))
            width[i] = max(width[i], ((v.co.x - cx) ** 2 + (v.co.y - cy) ** 2) ** 0.5)
    wmax = max(width)
    # the rim: the highest slice still nearly as wide as the widest (flames taper above it)
    rim_i = max(i for i in range(bins) if width[i] > wmax * 0.9)
    rim = z0 + (rim_i + 1) / bins * (hi.z - z0) + 0.01
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    kill = [f for f in bm.faces if f.calc_center_median().z > rim]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    print("RIM %.3f (cut %d faces)" % (rim, len(kill)))
elif MODE == "crystal":
    # By shape, not loose parts (the re-baked mesh is split along its UV seams): the socket is everything below
    # the empty band over it; above it, faces near the axis are the crystal and the ones further out the shards.
    import math
    lo, hi = bbox(ob)
    B = 60
    filled = [False] * B
    for v in ob.data.vertices:
        filled[min(B - 1, int((v.co.z - lo.z) / (hi.z - lo.z) * B))] = True
    gap = next(i for i in range(1, B) if filled[i - 1] and not filled[i])     # first empty band above the socket
    z_sock = lo.z + (hi.z - lo.z) * gap / B
    r_cry = float(a[3]) if len(a) > 3 else 0.42
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    groups = {"socket": [], "crystal": [], "shards": []}
    for f in bm.faces:
        c = f.calc_center_median()
        k = "socket" if c.z < z_sock else ("crystal" if math.hypot(c.x, c.y) < r_cry else "shards")
        groups[k].append(f.index)
    bm.free()
    out = {}
    for k, idx in groups.items():
        o = ob.copy()
        o.data = ob.data.copy()
        o.name = k
        bpy.context.scene.collection.objects.link(o)
        keep = set(idx)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
        bm.to_mesh(o.data)
        bm.free()
        out[k] = o
    bpy.data.objects.remove(ob, do_unlink=True)
    clo, chi = bbox(out["crystal"])
    c = (clo + chi) / 2
    c.x = 0.0; c.y = 0.0
    bpy.context.scene.cursor.location = c
    for k in ("crystal", "shards"):
        bpy.ops.object.select_all(action="DESELECT")
        out[k].select_set(True)
        bpy.context.view_layer.objects.active = out[k]
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    # Blender (x, y, z) -> Godot (x, z, -y)
    print("CRYSTAL_CENTER %.3f %.3f %.3f  socket below %.2f  faces: %s" % (c.x, c.z, -c.y, z_sock,
          {k: len(v) for k, v in groups.items()}))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=False)
print("EXPORTED", OUT)
