# Prepares the Meshy crusader (A-pose, great helm, long cloak) for rig_crusader_knight.py: one mesh,
# decimated to a triangle budget, scaled to a height, feet on z = 0, centred on x/y, front toward -y.
# Also writes orthographic front/side renders with a 5 cm grid (for placing the joints) when given a prefix.
#   blender -b --python prep_crusader.py -- in.glb out.glb [--tris 70000] [--height 1.8] [--grid prefix]
import bpy, sys, numpy as np
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
def opt(n, d):
    return argv[argv.index(n) + 1] if n in argv else d
TRIS = int(opt("--tris", "70000")); HEIGHT = float(opt("--height", "1.8")); GRID = opt("--grid", "")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = body.data
cur = sum(len(p.vertices) - 2 for p in me.polygons)
if cur > TRIS:
    d = body.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
    bpy.ops.object.modifier_apply(modifier="dec")
    me = body.data
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
lo, hi = P.min(0), P.max(0)
k = HEIGHT / (hi[2] - lo[2])
# centre on the torso (feet and cloak can be lopsided): the median of the verts above the hips
mid = P[P[:, 2] > lo[2] + 0.55 * (hi[2] - lo[2])]
P = (P - [np.median(mid[:, 0]), np.median(mid[:, 1]), lo[2]]) * k
me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()
print("PREP tris", sum(len(p.vertices) - 2 for p in me.polygons), "bbox", P.min(0).round(3), P.max(0).round(3))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=90)
if GRID:
    sc = bpy.context.scene
    world = bpy.data.worlds.new("w"); sc.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = 2.0
    cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam
    sc.render.resolution_x = sc.render.resolution_y = 1000
    for v, loc in (("front", (0, -5, 1.0)), ("side", (5, 0, 1.0))):
        cam.location = loc
        cam.rotation_euler = (Vector((0, 0, 1.0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{GRID}_{v}.png"
        bpy.ops.render.render(write_still=True)
    print("GRID: 1000 px = 2.0 m, image centre = (0, 1.0 m)")
