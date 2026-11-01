# Prepares a boat or ship model (Meshy, your own Blender model, any glb/fbx/obj) for the game, so every
# boat in Data.BOATS comes in the same way and any of them can be swapped for a better model later.
#
#   blender -b --python prep_boat.py -- in.glb out.glb <length m> --draft <m> [--bow +x|-x|+y|-y]
#                                        [--tris N] [--tex 2048] [--shot preview.png]
#
# What it does:
# - joins the meshes, finds the boat's length (its longest horizontal side) and turns it so the bow points
#   along Godot's -z (Blender +y with export_yup). --bow says which way the bow points in the source
#   (look at the model or its thumbnail once; Meshy side views usually have it at -x or +x).
# - scales it to <length> metres (stem to stern, bowsprit included) and puts the keel <draft> metres
#   under the waterline (y = 0 in Godot), centred on the origin along its length and width.
# - optionally decimates to N triangles, keeps textures as PNG (normal maps stay lossless) at most --tex px.
# - prints BOAT <out> length, beam, height, sheer (deck edge above water) and triangle count: the numbers
#   that go into the boat's Data.BOATS entry.
import bpy, sys, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, LENGTH = argv[0], argv[1], float(argv[2])
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
DRAFT = float(opt("--draft", "0.5"))
BOW = opt("--bow", "+x")
TRIS = int(opt("--tris", "0"))
TEX = int(opt("--tex", "2048"))
SHOT = opt("--shot", "")

bpy.ops.wm.read_factory_settings(use_empty=True)
ext = SRC.lower().rsplit(".", 1)[-1]
if ext in ("glb", "gltf"):
    bpy.ops.import_scene.gltf(filepath=SRC)
elif ext == "fbx":
    bpy.ops.import_scene.fbx(filepath=SRC)
elif ext == "obj":
    bpy.ops.wm.obj_import(filepath=SRC)
elif ext == "blend":
    with bpy.data.libraries.load(SRC) as (src, dst):
        dst.objects = src.objects
    for o in dst.objects:
        if o is not None:
            bpy.context.scene.collection.objects.link(o)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
o.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for e in [x for x in bpy.context.scene.objects if x != o]:
    bpy.data.objects.remove(e, do_unlink=True)
me = o.data

if TRIS:
    cur = sum(len(p.vertices) - 2 for p in me.polygons)
    if cur > TRIS:
        d = o.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
        bpy.ops.object.modifier_apply(modifier="dec")
        me = o.data

P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
# turn so the bow points to Blender +y (= Godot -z after the y-up export)
turn = {"+x": 90.0, "-x": -90.0, "+y": 0.0, "-y": 180.0}[BOW]
a = math.radians(turn); c, s = math.cos(a), math.sin(a)
P[:, 0], P[:, 1] = P[:, 0] * c - P[:, 1] * s, P[:, 0] * s + P[:, 1] * c
lo, hi = P.min(0), P.max(0)
k = LENGTH / (hi[1] - lo[1])
P = (P - [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]) * k
P[:, 2] -= DRAFT
me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()
# normals follow the rotation
for p in me.polygons:
    p.use_smooth = p.use_smooth

for img in bpy.data.images:
    if img.size[0] > TEX or img.size[1] > TEX:
        img.scale(min(TEX, img.size[0]), min(TEX, img.size[1]))

# the sheer: the highest hull point in the middle third of the length below 30% of the mast-free height,
# found as the top of the widest cross-sections there
mid = P[np.abs(P[:, 1]) < LENGTH / 6]
beam = mid[:, 0].max() - mid[:, 0].min() if len(mid) else 0
wide = mid[np.abs(mid[:, 0]) > beam * 0.42] if len(mid) else mid
sheer = wide[:, 2].max() if len(wide) else 0
height = P[:, 2].max()

bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_yup=True,
                          export_image_format="AUTO")
print("BOAT", OUT, "length %.2f beam %.2f height %.2f sheer %.2f draft %.2f tris %d" % (
    LENGTH, beam, height, sheer, DRAFT, sum(len(p.vertices) - 2 for p in me.polygons)), flush=True)

if SHOT:
    # a quick studio check of scale and orientation: the waterline as a thin plane, bow to the right
    sc = bpy.context.scene; sc.render.engine = "CYCLES"; sc.cycles.samples = 24; sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.52, 0.56, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    bpy.ops.mesh.primitive_plane_add(size=LENGTH * 3)
    pl = bpy.context.active_object; m = bpy.data.materials.new("wl"); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]; b.inputs["Base Color"].default_value = (0.05, 0.12, 0.16, 1)
    b.inputs["Alpha"].default_value = 0.55; pl.data.materials.append(m)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3
    sun.rotation_euler = (math.radians(50), 0, math.radians(30)); sc.collection.objects.link(sun)
    cd = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cd); sc.collection.objects.link(cam); sc.camera = cam
    tgt = Vector((0, 0, height * 0.4)); pos = tgt + Vector((-LENGTH * 1.6, -LENGTH * 0.9, LENGTH * 0.45))
    cam.location = pos; cam.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = SHOT; bpy.ops.render.render(write_still=True)
