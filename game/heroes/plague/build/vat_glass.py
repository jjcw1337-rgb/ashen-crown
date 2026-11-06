# The Last Experiment's vat glass, fractured for the burst (game/heroes/plague/skills/last_experiment/vat_shards.glb): the vat's glass
# cylinder (0.42 m radius, 1 m tall, a slight wall thickness) cut into curved panes round random seeds on its surface
# (bmesh bisects, as game/heroes/plague/build/vial_build.py fractures the vial). Each pane is its own object `pane_N`
# with its origin at its centre, so the game can fling them.
#   blender -b --python game/heroes/plague/build/vat_glass.py -- <out.glb> [panes 24] [seed 5]
import bpy, bmesh, sys, math, random
from mathutils import Vector, Matrix
a = sys.argv[sys.argv.index("--") + 1:]
OUT = a[0]
N = int(a[1]) if len(a) > 1 else 24
random.seed(int(a[2]) if len(a) > 2 else 5)
bpy.ops.wm.read_factory_settings(use_empty=True)
R, H, WALL, SEG, RINGS = 0.42, 1.0, 0.012, 64, 16
bm = bmesh.new()
outer, inner = [], []
for k in range(RINGS + 1):
    z = 0.12 + (H - 0.2) * k / RINGS
    ro, ri = [], []
    for i in range(SEG):
        t = 2 * math.pi * i / SEG
        ro.append(bm.verts.new((R * math.cos(t), R * math.sin(t), z)))
        ri.append(bm.verts.new(((R - WALL) * math.cos(t), (R - WALL) * math.sin(t), z)))
    outer.append(ro)
    inner.append(ri)
for k in range(RINGS):
    for i in range(SEG):
        j = (i + 1) % SEG
        bm.faces.new((outer[k][i], outer[k][j], outer[k + 1][j], outer[k + 1][i]))
        bm.faces.new((inner[k][j], inner[k][i], inner[k + 1][i], inner[k + 1][j]))
me = bpy.data.meshes.new("glass")
bm.to_mesh(me)
bm.free()
glass = bpy.data.objects.new("glass", me)
bpy.context.scene.collection.objects.link(glass)
seeds = []
for i in range(N):
    t = random.uniform(0, 2 * math.pi)
    seeds.append(Vector((R * math.cos(t), R * math.sin(t), random.uniform(0.15, H - 0.1))))
panes = []
for i, s in enumerate(seeds):
    b = bmesh.new()
    b.from_mesh(glass.data)
    for j, o in enumerate(seeds):
        if j == i:
            continue
        mid = (s + o) * 0.5
        bmesh.ops.bisect_plane(b, geom=b.verts[:] + b.edges[:] + b.faces[:], plane_co=mid, plane_no=(o - s).normalized(), clear_outer=True)
    if len(b.faces) == 0:
        b.free()
        continue
    pm = bpy.data.meshes.new("pane_%d" % i)
    b.to_mesh(pm)
    b.free()
    ob = bpy.data.objects.new("pane_%d" % i, pm)
    bpy.context.scene.collection.objects.link(ob)
    for p in pm.polygons:
        p.use_smooth = True
    c = sum((v.co for v in pm.vertices), Vector()) / max(len(pm.vertices), 1)
    pm.transform(Matrix.Translation(-c))
    ob.location = c
    panes.append(ob)
bpy.ops.object.select_all(action="DESELECT")
for o in panes:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format="GLB", export_yup=True, export_materials="NONE")
print("VAT GLASS", len(panes), "panes")
