# Prepares a Meshy tree for the game: trunk centred on the origin, roots on the ground, scaled to a
# height, textures shrunk, exported as a static glb (Godot axes).
#   blender -b --python prep_tree.py -- in.glb out.glb <height m> [texture px]
import bpy, sys, numpy as np
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, H = argv[0], argv[1], float(argv[2])
TEX = int(argv[3]) if len(argv) > 3 else 1024
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
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
z0, z1 = P[:, 2].min(), P[:, 2].max()
s = H / (z1 - z0)
P = (P - [0, 0, z0]) * s
# the trunk: centroid of a slice a little above the root flare
band = (P[:, 2] > 0.55) & (P[:, 2] < 0.9)
cx, cy = P[band, 0].mean(), P[band, 1].mean()
P[:, 0] -= cx; P[:, 1] -= cy
P[:, 2] -= 0.04                         # roots sink a few cm into the ground
me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()
for img in bpy.data.images:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=82)
r = np.hypot(P[:, 0], P[:, 1])
print("TREE", OUT, "tris", sum(len(p.vertices) - 2 for p in me.polygons), "height", round(P[:, 2].max(), 2),
      "trunk r at 1m", round(float(np.percentile(r[(P[:, 2] > 0.9) & (P[:, 2] < 1.1)], 60)), 2), "crown r", round(float(np.percentile(r, 97)), 2))
