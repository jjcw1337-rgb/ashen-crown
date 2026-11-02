# Renders the piles of coals.glb in the brazier's bowl (Eevee), one image per pile from a close three-quarter view,
# plus a sheet of the library's pieces, for review before the Godot round trip.
#   xvfb-run -a blender -b --python coals_preview.py -- coals.glb brazier.glb outprefix [bowl_scale]
import bpy, sys, math, mathutils
a = sys.argv[sys.argv.index("--") + 1:]
COALS, BRAZIER, OUT = a[0], a[1], a[2]
SCALE = float(a[3]) if len(a) > 3 else 1.15
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=BRAZIER)
braz = [o for o in bpy.context.selected_objects if o.type == "MESH"]
for o in braz:
    o.scale = (SCALE, SCALE, SCALE)
bpy.ops.import_scene.gltf(filepath=COALS)
lib = {}
piles = {}
for o in bpy.context.scene.objects:
    if o.type == "MESH" and o.name[-3:] in ("_l0", "_l1") and o.name not in [b.name for b in braz]:
        lib[o.name] = o
        o.hide_render = True
    if o.type == "EMPTY" and o.name.startswith("arr_"):
        piles[o.name] = o
print("PIECES", len(lib), "PILES", sorted(piles))
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE_NEXT"
sc.render.resolution_x, sc.render.resolution_y = 900, 700
sc.eevee.taa_render_samples = 32
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.02, 0.02, 0.03)
key = bpy.data.lights.new("key", "POINT"); key.energy = 25; key.color = (0.35, 0.6, 1.0); key.shadow_soft_size = 0.05
ko = bpy.data.objects.new("key", key); sc.collection.objects.link(ko)
fill = bpy.data.lights.new("fill", "SUN"); fill.energy = 0.6; fill.color = (0.7, 0.75, 0.9)
fo = bpy.data.objects.new("fill", fill); sc.collection.objects.link(fo); fo.rotation_euler = (math.radians(50), 0, math.radians(-40))
cam = bpy.data.cameras.new("c"); cam.lens = 45; co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
top = max((o.matrix_world @ mathutils.Vector(c)).z for o in braz for c in o.bound_box)
focus = mathutils.Vector((0, 0, top - 0.02))
ko.location = focus + mathutils.Vector((0, 0, 0.35))
for name in sorted(piles):
    arr = piles[name]
    made = []
    for e in arr.children:
        piece = e.get("piece", e.name.split("_", 1)[1] if "_" in e.name else e.name)
        src = lib.get(piece + "_l0")
        if src is None:
            print("MISSING", piece)
            continue
        inst = src.copy(); inst.data = src.data
        inst.hide_render = False
        inst.matrix_world = e.matrix_world
        sc.collection.objects.link(inst)
        made.append(inst)
    co.location = focus + mathutils.Vector((0.75, -0.75, 0.85))
    co.rotation_euler = (focus - co.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = "%s_%s.png" % (OUT, name)
    bpy.ops.render.render(write_still=True)
    print("SHOT", sc.render.filepath, "instances", len(made))
    for inst in made:
        bpy.data.objects.remove(inst, do_unlink=True)
