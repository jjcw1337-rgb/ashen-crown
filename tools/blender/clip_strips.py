# Renders a strip of frames for every animation in a rigged glb (Meshy's animate output: one action per clip),
# so the clips can be compared side by side: `n` evenly spaced frames per clip, three-quarter front view, Eevee,
# saved as <prefix>_<clip>.png (frames in a row). Optional props: a box standing in for a chest at the feet.
#   blender -b --python clip_strips.py -- in.glb out_prefix [--n 6] [--size 360] [--chest]
import bpy, sys, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
N = int(opt("--n", "6"))
SIZE = int(opt("--size", "360"))
CHEST = "--chest" in argv

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == "ARMATURE")
meshes = [o for o in sc.objects if o.type == "MESH"]
try:
    sc.render.engine = "BLENDER_EEVEE_NEXT"
except TypeError:
    sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = SIZE
sc.render.resolution_y = int(SIZE * 1.25)
sc.render.film_transparent = False
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.08, 0.08, 0.09, 1)
sc.world = w
for loc, e in [((2.5, -3.0, 3.5), 900), ((-3.0, 1.5, 2.5), 350), ((0, 3, 2), 250)]:
    l = bpy.data.lights.new("l", "AREA")
    l.energy = e
    l.size = 2.5
    lo = bpy.data.objects.new("l", l)
    lo.location = loc
    lo.rotation_euler = (Vector((0, 0, 1)) - lo.location).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(lo)
plane = bpy.data.meshes.new("floor")
plane.from_pydata([(-4, -4, 0), (4, -4, 0), (4, 4, 0), (-4, 4, 0)], [], [(0, 1, 2, 3)])
fl = bpy.data.objects.new("floor", plane)
sc.collection.objects.link(fl)
if CHEST:
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.75, 0.3))
    ch = bpy.context.active_object
    ch.scale = (0.62, 0.42, 0.3)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.location = Vector((2.6, -3.4, 1.9))
cam.rotation_euler = (Vector((0, -0.3, 0.85)) - cam.location).to_track_quat("-Z", "Y").to_euler()
cam.data.lens = 40

actions = list(bpy.data.actions)
print("CLIPS", [a.name for a in actions])
if arm.animation_data is None:
    arm.animation_data_create()
for a in actions:
    arm.animation_data.action = a
    f0, f1 = int(a.frame_range[0]), int(a.frame_range[1])
    tiles = []
    for i in range(N):
        f = round(f0 + (f1 - f0) * i / max(1, N - 1))
        sc.frame_set(f)
        sc.render.filepath = "%s_tmp.png" % OUT
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(sc.render.filepath, check_existing=False)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
        tiles.append(px)
        bpy.data.images.remove(img)
    strip = np.concatenate(tiles, axis=1)
    out = bpy.data.images.new("strip", strip.shape[1], strip.shape[0])
    out.pixels = strip.ravel()
    safe = "".join(c if c.isalnum() else "_" for c in a.name)
    out.filepath_raw = "%s_%s.png" % (OUT, safe)
    out.file_format = "PNG"
    out.save()
    print("STRIP", a.name, f0, f1, out.filepath_raw)
