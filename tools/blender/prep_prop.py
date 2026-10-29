# Prepares a Meshy prop (stall, wagon, tent, gate, stone...) for the game: joined into one mesh, its
# footprint centred on the origin, its base on the ground, scaled to a size, optionally decimated,
# textures shrunk, exported as a static glb (Godot axes, the model's front toward +z in Godot).
#   blender -b --python prep_prop.py -- in.glb out.glb <size m> [--axis height|width|depth] [--tris N]
#                                        [--tex 1024] [--turn deg] [--sink m]
# --axis says which dimension <size> sets (height by default). --turn spins it about the vertical
# before export (Meshy's image-to-3D faces the viewer; the game wants the front toward +z = south).
# Prints PROP <out> size, triangle count and footprint (half-extents in Godot x/z) for World.add_box.
import bpy, sys, math, numpy as np
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, SIZE = argv[0], argv[1], float(argv[2])
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
AXIS = opt("--axis", "height")
TRIS = int(opt("--tris", "0"))
TEX = int(opt("--tex", "1024"))
TURN = float(opt("--turn", "0"))
SINK = float(opt("--sink", "0.02"))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = o.data
if TRIS:
    cur = sum(len(p.vertices) - 2 for p in me.polygons)
    if cur > TRIS:
        d = o.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
        bpy.ops.object.modifier_apply(modifier="dec")
        me = o.data
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
if TURN:
    a = math.radians(TURN); c, s_ = math.cos(a), math.sin(a)
    P[:, 0], P[:, 1] = P[:, 0] * c - P[:, 1] * s_, P[:, 0] * s_ + P[:, 1] * c
lo, hi = P.min(0), P.max(0)
ext = {"width": hi[0] - lo[0], "depth": hi[1] - lo[1], "height": hi[2] - lo[2]}[AXIS]
k = SIZE / ext
P = (P - [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]) * k
P[:, 2] -= SINK
me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()
for img in bpy.data.images:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=84)
# footprint from the lowest 40 cm (posts, wheels, walls), as Godot half-extents (x, z = -y)
base = P[P[:, 2] < 0.4] if (P[:, 2] < 0.4).sum() > 20 else P
print("PROP", OUT, "tris", sum(len(p.vertices) - 2 for p in me.polygons),
      "size x %.2f y %.2f z %.2f" % tuple(P.max(0) - P.min(0)),
      "foot half x %.2f z %.2f" % (np.abs(base[:, 0]).max(), np.abs(base[:, 1]).max()))
