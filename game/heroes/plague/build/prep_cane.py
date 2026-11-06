# Prepares the plague doctor's Meshy cane (game/heroes/plague/weapon/cane.glb) as a weapon in the game's frame:
# the shaft along +y, the crow-skull handle at the top, the grip (just under the brass collar) on the origin,
# so it sits in the hand like the game's procedural maces (Models.weapon: the head toward +y).
#   blender -b --python prep_cane.py -- <in.glb> <out.glb> [length m] [tris] [tex px]
import bpy, sys
import numpy as np
from mathutils import Matrix, Vector
a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
LEN = float(a[2]) if len(a) > 2 else 1.0
TRIS = int(a[3]) if len(a) > 3 else 6000
TEX = int(a[4]) if len(a) > 4 else 1024
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
objs = [o for o in bpy.context.scene.objects]
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
P = np.array([v.co[:] for v in ob.data.vertices])
c = P.mean(axis=0)
# the shaft's axis: the main direction of the vertices
_, _, vt = np.linalg.svd(P - c, full_matrices=False)
ax = vt[0]
t = (P - c) @ ax
# the handle end is the fat one (the crow skull): more spread off the axis near it
off = np.linalg.norm((P - c) - np.outer(t, ax), axis=1)
lo, hi = t.min(), t.max()
top_end = hi if off[t > hi - 0.15 * (hi - lo)].mean() > off[t < lo + 0.15 * (hi - lo)].mean() else lo
if top_end == lo:
    ax = -ax
    t = -t
    lo, hi = -hi, -lo
rot = Vector(ax).rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4()   # Blender z up = Godot y up
grip = c + ax * (hi - 0.2 * (hi - lo))       # a fifth of the way down from the top: under the collar
s = LEN / (hi - lo)
ob.data.transform(Matrix.Scale(s, 4) @ rot @ Matrix.Translation(-Vector(grip)))
ob.data.update()
cur = len(ob.data.polygons)
if cur > TRIS:
    d = ob.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
    bpy.ops.object.modifier_apply(modifier="dec")
for img in bpy.data.images:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88)
print("EXPORTED", OUT, "faces", len(ob.data.polygons), "scale", s)
