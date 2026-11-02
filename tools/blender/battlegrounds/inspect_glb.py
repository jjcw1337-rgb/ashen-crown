# Prints each glb's triangle count, size (Blender axes: z up), lowest point, materials and images, to plan the
# prep of a Meshy prop (which axis is its length, how big it came out of Meshy).
#   blender -b --python tools/blender/battlegrounds/inspect_glb.py -- a.glb b.glb ...
import bpy, sys, mathutils
for src in sys.argv[sys.argv.index("--") + 1:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = mathutils.Vector((1e9,) * 3)
    hi = mathutils.Vector((-1e9,) * 3)
    tris = 0
    for o in objs:
        tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            lo = mathutils.Vector(map(min, lo, w))
            hi = mathutils.Vector(map(max, hi, w))
    mats = set()
    for o in objs:
        for m in o.data.materials:
            if m:
                mats.add(m.name)
    print("INSPECT", src.split("/")[-1], "tris", tris, "size x %.2f y %.2f z %.2f" % tuple(hi - lo),
          "min z %.2f" % lo.z, "mats", len(mats), "imgs", len(bpy.data.images))
