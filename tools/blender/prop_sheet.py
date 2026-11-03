# Renders each prepared prop (the .glb prep_prop.py wrote) beside a 1.8 m post, so the wrong object (Meshy's
# text-to-3D made a goblin playing a horn for "bicycle horn" and a ragged figure for "kelp"), a wrong size or a prop
# lying on its side shows before it goes in the game. Prints each one's size (Blender x, y, z; z is up).
#   blender -b --python prop_sheet.py -- outdir a.glb b.glb ...     (outdir/<name>.png, 320 px each)
import bpy, sys, mathutils
a = sys.argv[sys.argv.index("--") + 1:]
OUT, FILES = a[0], a[1:]
for f in FILES:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=f)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    mn = mathutils.Vector((1e9,) * 3); mx = -mn
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
    size = mx - mn; ctr = (mx + mn) / 2; r = max(max(size), 1.8) * 1.6 + 0.5
    bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=1.8, location=(mn.x - 0.4, ctr.y, 0.9))
    bpy.ops.mesh.primitive_plane_add(size=r * 3, location=(ctr.x, ctr.y, 0))
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.scene.collection.objects.link(cam)
    cam.location = (ctr.x + r * 0.8, ctr.y - r * 1.0, ctr.z + r * 0.6)
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc = bpy.context.scene
    sc.camera = cam
    try:
        sc.render.engine = "BLENDER_WORKBENCH"
    except TypeError:
        pass
    sc.display.shading.color_type = "TEXTURE"; sc.display.shading.light = "STUDIO"
    sc.render.resolution_x = 320; sc.render.resolution_y = 320
    name = f.split("/")[-1].replace(".glb", "")
    sc.render.filepath = f"{OUT}/{name}.png"
    bpy.ops.render.render(write_still=True)
    print("SIZE", name, [round(v, 2) for v in size])
