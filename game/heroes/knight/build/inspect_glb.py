import bpy, sys, numpy as np
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in objs:
    print("MESH", o.name, len(o.data.vertices), "verts", len(o.data.polygons), "faces", "mats", [m.name for m in o.data.materials], "parent", o.parent)
    P = np.array([o.matrix_world @ v.co for v in o.data.vertices])
    print(" bbox min", P.min(0).round(3), "max", P.max(0).round(3))
    for m in o.data.materials:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    print("  tex", n.image.name, n.image.size[:])
print("OTHER", [(o.name, o.type) for o in bpy.context.scene.objects if o.type != "MESH"])
