# The island's underside from Meshy (prep_prop.py's output) has its grassy top tilted toward the concept's camera:
# this levels it. A plane is fitted to the top's surface (the vertices in the highest TOP_FRAC of the model, by least
# squares), the mesh turned so that plane is level, centred on the top's middle and stood back on the ground (y 0 =
# its lowest point, as prep_prop leaves it), the top's middle cut out (the camp's ground is there), and the top's
# radius printed (CampIsland scales by it).
#   blender -b --python tools/blender/island/level_top.py -- in.glb out.glb
import bpy, sys, math, mathutils
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
TOP_FRAC = 0.18
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ob = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
P = np.array([v.co[:] for v in ob.data.vertices])
z0, z1 = P[:, 2].min(), P[:, 2].max()
for it in range(3):
    top = P[P[:, 2] > z1 - (z1 - z0) * TOP_FRAC]
    A = np.c_[top[:, 0], top[:, 1], np.ones(len(top))]
    (a, b, c), *_ = np.linalg.lstsq(A, top[:, 2], rcond=None)
    n = mathutils.Vector((-a, -b, 1.0)).normalized()
    q = n.rotation_difference(mathutils.Vector((0, 0, 1)))
    R = np.array(q.to_matrix())
    P = P @ R.T
    z0, z1 = P[:, 2].min(), P[:, 2].max()
    print("LEVEL pass", it, "tilt deg", round(math.degrees(math.acos(min(1.0, n.z))), 2))
top = P[P[:, 2] > z1 - (z1 - z0) * 0.08]
cx, cy = top[:, 0].mean(), top[:, 1].mean()
P[:, 0] -= cx
P[:, 1] -= cy
P[:, 2] -= P[:, 2].min()
for v, p in zip(ob.data.vertices, P):
    v.co = p
ob.data.update()
# the top's middle is never seen (the camp's own ground covers it) and its bumps poked up through that ground: cut it
# out, leaving the rim (its bushes over the edge) and the cliff below
import bmesh
bm = bmesh.new()
bm.from_mesh(ob.data)
Hn = P[:, 2].max()
rtop = np.percentile(np.hypot(top[:, 0] - cx, top[:, 1] - cy), 90)
cut = [f for f in bm.faces if f.calc_center_median().z > Hn * 0.72 and math.hypot(f.calc_center_median().x, f.calc_center_median().y) < rtop * 0.84]
# and the bushes standing up off the rim (big flat leaf cards, too coarse seen from the game's camera): anything
# above the grass's level
grass = Hn * 0.935
cut += [f for f in bm.faces if f not in cut and f.calc_center_median().z > grass + Hn * 0.012]
bmesh.ops.delete(bm, geom=cut, context="FACES")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
bm.to_mesh(ob.data)
bm.free()
print("LEVEL cut the top's middle:", len(cut), "faces")
r = np.hypot(top[:, 0] - cx, top[:, 1] - cy)
H = P[:, 2].max()
print("LEVEL top radius r50 %.3f r90 %.3f max %.3f  height %.3f  width %.3f" % (np.percentile(r, 50), np.percentile(r, 90), r.max(), H,
      max(P[:, 0].max() - P[:, 0].min(), P[:, 1].max() - P[:, 1].min())))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_image_format="JPEG", export_jpeg_quality=88)
