# Prepares a Meshy arrow for the archer's shots (archer.gd): joins it, decimates it, lines its shaft up with +Y (the
# head forward: glTF turns Blender's +Y into Godot's -Z, so look_at points it), scales it to its length, shrinks its textures.
#   blender -b --python tools/blender/prep_arrow.py -- <in.glb> <out.glb> [length m, 0.8] [triangles, 2500] [tex px, 512]
# Which end is the head: the fletching's three vanes stand out both ways round the shaft, a broadhead is flat, so the
# end whose thinner spread is wider is the nock.
import bpy, sys
import numpy as np
from mathutils import Matrix, Vector

a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
LENGTH = float(a[2]) if len(a) > 2 else 0.8
TRIS = int(a[3]) if len(a) > 3 else 2500
TEX = int(a[4]) if len(a) > 4 else 512
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    o.select_set(o in ms)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
for x in list(bpy.context.scene.objects):
    if x != o:
        bpy.data.objects.remove(x, do_unlink=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
P = np.array([v.co[:] for v in o.data.vertices])
c = P.mean(0)
Q = P - c
# the shaft's axis: the main direction of the points
w, V = np.linalg.eigh(np.cov(Q.T))
ax = V[:, np.argmax(w)]
t = Q @ ax
L = t.max() - t.min()
def spread(mask):
    q = Q[mask] - np.outer(Q[mask] @ ax, ax)
    w2, _ = np.linalg.eigh(np.cov(q.T))
    w2 = np.sort(w2)
    return np.sqrt(max(w2[1], 0.0))    # the thinner of the two ways round
lo = spread(t < t.min() + 0.25 * L)
hi = spread(t > t.max() - 0.25 * L)
head_dir = -ax if hi > lo else ax      # fletching at the end with the wider thin spread
print("fletch spread lo %.4f hi %.4f" % (lo, hi))
# rotate head_dir onto +Y (Godot -Z)
target = Vector((0, 1, 0))
hd = Vector(head_dir.tolist())
rot = hd.rotation_difference(target).to_matrix().to_4x4()
o.data.transform(Matrix.Translation(-Vector(c.tolist())))
o.data.transform(rot)
s = LENGTH / L
o.data.transform(Matrix.Scale(s, 4))
tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
if tris > TRIS:
    m = o.modifiers.new("dec", "DECIMATE")
    m.ratio = TRIS / tris
    bpy.ops.object.modifier_apply(modifier=m.name)
for img in bpy.data.images:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_image_format="JPEG")
print("exported", OUT, "tris", sum(len(p.vertices) - 2 for p in o.data.polygons), "length", LENGTH)
