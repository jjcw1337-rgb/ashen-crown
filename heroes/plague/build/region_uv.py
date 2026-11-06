# Writes the plague doctor's texture regions as UV triangles (JSON) for heroes/plague/build/plague_colors.py: which faces are his
# hat and head ("head": above the collar), his gloves ("hands": skinned mostly to a hand bone), his boots ("feet":
# below the coat's hem in the rest pose); everything else is "body" (coat, cape, sleeves). Lets a colour scheme dye
# the coat and keep the hat, gloves and boots their own colour.
#   blender -b --python region_uv.py -- <plague_doctor.glb> <out.json>
import bpy, sys, json
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
body = [o for o in bpy.data.objects if o.type == "MESH" and len(o.data.polygons) > 1000][0]
me = body.data
mw = body.matrix_world
names = {g.index: g.name for g in body.vertex_groups}
HAND = {"LeftHand", "RightHand"}
zs = [(mw @ v.co).z for v in me.vertices]
top, bot = max(zs), min(zs)
H = top - bot
def region(poly) -> str:
    z = sum(zs[i] for i in poly.vertices) / len(poly.vertices) - bot
    hand = 0.0
    for i in poly.vertices:
        for g in me.vertices[i].groups:
            if names.get(g.group) in HAND:
                hand += g.weight
    if hand / len(poly.vertices) > 0.5:
        return "hands"
    if z > H * 0.845:          # the collar's top and up: the head, mask and hat
        return "head"
    if z < H * 0.21:           # below the coat's hem: the boots
        return "feet"
    return "body"
uv = me.uv_layers.active.data
out = {"body": [], "head": [], "hands": [], "feet": []}
for p in me.polygons:
    r = region(p)
    out[r].append([[uv[li].uv[0], uv[li].uv[1]] for li in p.loop_indices])
json.dump(out, open(a[1], "w"))
print("REGIONS", {k: len(v) for k, v in out.items()}, "height", round(H, 3))
