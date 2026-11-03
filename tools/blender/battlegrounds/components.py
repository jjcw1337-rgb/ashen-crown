# Lists a glb's connected mesh components (size and centre), to decide what to cut from a Meshy prop.
#   blender -b --python tools/blender/battlegrounds/components.py -- in.glb
import bpy, bmesh, sys
import numpy as np
src = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bm = bmesh.new()
bm.from_mesh(o.data)
bm.verts.ensure_lookup_table()
seen = set()
comps = []
for v in bm.verts:
    if v.index in seen:
        continue
    stack = [v]
    comp = []
    seen.add(v.index)
    while stack:
        cur = stack.pop()
        comp.append(cur)
        for e in cur.link_edges:
            w = e.other_vert(cur)
            if w.index not in seen:
                seen.add(w.index)
                stack.append(w)
    P = np.array([c.co[:] for c in comp])
    comps.append((len(comp), P.min(axis=0), P.max(axis=0), P.mean(axis=0)))
comps.sort(key=lambda c: -c[0])
print("COMPONENTS", len(comps))
for n, lo, hi, c in comps[:30]:
    print("  verts %6d  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f  centre (%.2f %.2f %.2f)" % (n, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], c[0], c[1], c[2]))
