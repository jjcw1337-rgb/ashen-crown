# Quick studio renders of a glb: blender -b --python preview_glb.py -- in.glb out_prefix [views]
import bpy, sys, os
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
VIEWS = argv[2].split(",") if len(argv) > 2 else ["front", "side", "back"]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
world = bpy.data.worlds.new("w"); sc.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.34, 0.37, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
def light(name, loc, energy, size):
    ld = bpy.data.lights.new(name, "AREA"); ld.energy = energy; ld.size = size
    o = bpy.data.objects.new(name, ld); sc.collection.objects.link(o); o.location = loc
    o.rotation_euler = (Vector((0, 0, 1.1)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
light("key", (-1.8, 2.6, 2.8), 500, 2.0); light("fill", (2.2, 2.0, 1.6), 150, 2.5); light("rim", (0.5, -2.6, 2.6), 350, 1.5)
sc.render.engine = "BLENDER_EEVEE_NEXT"; sc.eevee.taa_render_samples = 16
sc.view_settings.view_transform = "AgX"
cd = bpy.data.cameras.new("c"); cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam
cd.lens = 50
# the model faces +y
V = {"front": (0, 4.2, 1.0), "side": (4.2, 0.3, 1.0), "back": (0, -4.2, 1.1), "face": (0.15, 1.1, 1.72), "34": (2.6, 3.3, 1.2)}
for v in VIEWS:
    cam.location = V[v]
    tgt = Vector((0, 0, 1.72 if v == "face" else 0.95))
    cam.rotation_euler = (tgt - Vector(V[v])).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x, sc.render.resolution_y = (700, 1000) if v != "face" else (700, 700)
    sc.render.filepath = f"{OUT}_{v}.png"
    bpy.ops.render.render(write_still=True)
