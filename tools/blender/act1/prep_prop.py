# Prepares a Meshy prop (a static model) for the game: decimated, standing on the ground, centred,
# turned and scaled, textures shrunk, exported as a static glb (Godot axes: it faces -z).
#   blender -b --python prep_prop.py -- <in.glb> <out.glb> <size: "x=5" | "h=8" | "w=11"> <triangles> [yaw deg] [texture px]
# x=  scales so its length along x is that many metres (a wall section), h= its height, w= its widest side.
# yaw turns it about the vertical before scaling (to bring its front or its long side round).
import bpy, sys, math
import numpy as np
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, SIZE, TRIS = argv[0], argv[1], argv[2], int(argv[3])
YAW = float(argv[4]) if len(argv) > 4 else 0.0
TEX = int(argv[5]) if len(argv) > 5 else 1024
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
o.rotation_euler = (0, 0, math.radians(YAW))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
if tris > TRIS:
    m = o.modifiers.new("dec", "DECIMATE"); m.ratio = TRIS / tris
    bpy.ops.object.modifier_apply(modifier="dec")
me = o.data
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
P[:, 0] -= 0.5 * (P[:, 0].min() + P[:, 0].max())
P[:, 1] -= 0.5 * (P[:, 1].min() + P[:, 1].max())
P[:, 2] -= P[:, 2].min()
key, val = SIZE.split("=")
ext = {"x": P[:, 0].ptp(), "h": P[:, 2].ptp(), "w": max(P[:, 0].ptp(), P[:, 1].ptp())}[key]
P *= float(val) / ext
me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32))
me.update()
for img in bpy.data.images:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
print("size x %.2f y %.2f h %.2f, %d triangles" % (P[:, 0].ptp(), P[:, 1].ptp(), P[:, 2].ptp(), sum(len(p.vertices) - 2 for p in me.polygons)))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=85)
print("EXPORTED", OUT)
