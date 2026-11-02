# Cuts away the faces above a height (Blender z, metres, the raw Meshy model's own frame) and re-exports: for a rider
# Meshy fused onto a prop (Doug's clown car came with a jester sitting on its roof; cut at the window line it is an open
# tourer he can drive). Optional boxes cut lower in one region: "x>0.40:z>-0.24" (the jester's collar over the boot).
# Faces left open are drawn from both sides (the glTF material's doubleSided), so the inside isn't see-through.
#   blender -b --python cut_above.py -- in.glb out.glb <z> [region ...] [--blend sources/x.blend]
import bpy, bmesh, sys
a = sys.argv[sys.argv.index("--") + 1:]
blend = ""
if "--blend" in a:
    blend = a[a.index("--blend") + 1]
    a = a[:a.index("--blend")]
SRC, OUT, Z = a[0], a[1], float(a[2])
REGIONS = []
for r in a[3:]:
    conds = []
    for c in r.split(":"):
        ax, op, v = c[0], c[1], float(c[2:])
        conds.append(("xyz".index(ax), op, v))
    REGIONS.append(conds)

def cut(p) -> bool:
    if p.z > Z:
        return True
    for conds in REGIONS:
        if all((p[i] > v) if op == ">" else (p[i] < v) for i, op, v in conds):
            return True
    return False

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
n = 0
for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
    bm = bmesh.new(); bm.from_mesh(o.data)
    kill = [f for f in bm.faces if cut(o.matrix_world @ f.calc_center_median())]
    n += len(kill)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(o.data); bm.free()
    for m in o.data.materials:
        if m:
            m.use_backface_culling = False
print("CUT", n, "faces")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB")
if blend:
    bpy.ops.wm.save_as_mainfile(filepath=blend)
