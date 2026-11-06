# Builds Pestilence Vial's bottle (heroes/plague/skills/pestilence_vial/vial.glb) and its pre-fractured glass
# (heroes/plague/skills/pestilence_vial/vial_shards.glb) from code: a lathed apothecary vial.
#   blender -b --python heroes/plague/build/vial_build.py -- heroes/plague/skills/pestilence_vial [seed]
# vial.glb objects (Plague.Vial assigns the game's materials by name):
#   glass   the bottle's shell (outside and inside walls, rounded lip); thin-glass shader
#   liquid  the volume inside, full height: the shader cuts it at a sloshing fill plane and draws its back
#           faces as the liquid's top surface
#   cork    the stopper, tapered with a crumbled top
#   wax     the seal over the cork with drips down the neck
#   twine   two wraps of cord round the neck
#   collar  the brass band under the lip
# vial_shards.glb: the glass shell cut into SHARDS cells (bmesh bisects round random seeds), each piece its own
# object `shard_N` with its origin at its centre, so the game can fling them.
# Units: metres; the vial is 0.16 m tall standing on the origin, axis Blender +z (= Godot +y).
import bpy, bmesh, sys, math, random
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["/tmp"]
OUT = a[0]
SEED = int(a[1]) if len(a) > 1 else 7
random.seed(SEED)
SEG = 40           # round the axis
SHARDS = 14

bpy.ops.wm.read_factory_settings(use_empty=True)

# the outer profile (radius, height) from the base up: a round-shouldered apothecary vial
OUTER = [
    (0.000, 0.000), (0.026, 0.000), (0.033, 0.004), (0.036, 0.012), (0.037, 0.030), (0.037, 0.062),
    (0.036, 0.076), (0.031, 0.090), (0.022, 0.101), (0.0135, 0.108), (0.0118, 0.114), (0.0118, 0.128),
    (0.0150, 0.132), (0.0158, 0.136), (0.0140, 0.139), (0.0108, 0.139),
]
WALL = 0.0022

def lathe(name, prof, closed_bottom=True, cap_top=False):
    bm = bmesh.new()
    rings = []
    for (r, z) in prof:
        ring = []
        if r < 1e-6:
            ring = [bm.verts.new((0, 0, z))]
        else:
            for i in range(SEG):
                t = 2 * math.pi * i / SEG
                ring.append(bm.verts.new((r * math.cos(t), r * math.sin(t), z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        A, B = rings[k], rings[k + 1]
        for i in range(SEG):
            j = (i + 1) % SEG
            if len(A) == 1:
                bm.faces.new((A[0], B[i], B[j]))
            elif len(B) == 1:
                bm.faces.new((A[i], B[0], A[j]))
            else:
                bm.faces.new((A[i], B[i], B[j], A[j]))
    if cap_top and len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob

# glass: the outer profile up and over the lip, then the inner wall back down
inner = [(max(r - WALL, 0.0), z) for (r, z) in OUTER[1:-1]]
inner[0] = (inner[0][0], WALL * 1.6)
glass_prof = OUTER[:-1] + [(OUTER[-1][0], OUTER[-1][1])] + list(reversed([(r, z) for (r, z) in inner if z > WALL])) + [(0.0, WALL * 1.6)]
glass = lathe("glass", glass_prof)

# liquid: the inside, slightly smaller, full height to the neck (the shader cuts it at the level)
liq_prof = [(0.0, WALL * 1.8)] + [(max(r - WALL * 1.35, 0.001), z) for (r, z) in OUTER[2:11]] + [(0.0, OUTER[10][1])]
liquid = lathe("liquid", liq_prof)

# cork: tapered, pushed into the neck, a crumbled top
cork_prof = [(0.0, 0.120), (0.0095, 0.120), (0.0102, 0.130), (0.0112, 0.141), (0.0128, 0.146), (0.0128, 0.151),
             (0.0110, 0.154), (0.0, 0.155)]
cork = lathe("cork", cork_prof)
for v in cork.data.vertices:
    if v.co.z > 0.143:
        n = random.uniform(-1, 1)
        v.co.x *= 1.0 + 0.06 * n
        v.co.y *= 1.0 + 0.06 * n
        v.co.z += 0.0012 * random.uniform(-1, 1)

# wax seal: a blob over the cork top, with drips running down the neck
wax_prof = [(0.0, 0.1585), (0.0090, 0.1580), (0.0138, 0.1545), (0.0158, 0.1500), (0.0166, 0.1440),
            (0.0168, 0.1385), (0.0150, 0.1360), (0.0, 0.1355)]
wax = lathe("wax", wax_prof)
bm = bmesh.new()
bm.from_mesh(wax.data)
for k in range(5):
    ang = random.uniform(0, 2 * math.pi)
    length = random.uniform(0.006, 0.016)
    w = random.uniform(0.0022, 0.0034)
    res = bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=8, radius=1.0)
    for v in res["verts"]:
        x, y, z = v.co
        z01 = (z + 1.0) * 0.5            # 0 bottom .. 1 top
        rr = w * (0.6 + 0.4 * z01) if z < 0 else w
        v.co = Vector((x * rr * 0.6, y * rr, z * length * 0.5))
        v.co.z += 0.1395 - length * 0.5
        rad = 0.0162 - 0.0004 * (1 - z01)
        c, s = math.cos(ang), math.sin(ang)
        px, py = v.co.x + rad, v.co.y
        v.co.x, v.co.y = px * c - py * s, px * s + py * c
bm.to_mesh(wax.data)
bm.free()
for p in wax.data.polygons:
    p.use_smooth = True

# twine: two wraps round the neck (a bent torus with a slight helix and wobble)
def ring(name, z, r_major, r_minor, wobble):
    bm = bmesh.new()
    res = bmesh.ops.create_circle(bm, cap_ends=False, segments=48, radius=r_major)
    bm.free()
    bpy.ops.mesh.primitive_torus_add(major_radius=r_major, minor_radius=r_minor, major_segments=56, minor_segments=8,
                                     location=(0, 0, z))
    ob = bpy.context.active_object
    ob.name = name
    for v in ob.data.vertices:
        t = math.atan2(v.co.y, v.co.x)
        v.co.z += wobble * math.sin(t * 3.0 + z * 400.0) + 0.0006 * t / math.pi
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob
t1 = ring("twine", 0.1165, 0.0129, 0.0011, 0.0003)
t2 = ring("twine2", 0.1192, 0.0129, 0.0011, 0.0003)
t2.select_set(True); t1.select_set(True)
bpy.context.view_layer.objects.active = t1
bpy.ops.object.join()
twine = t1
twine.name = "twine"

# brass collar under the lip
col_prof = [(0.0122, 0.1240), (0.0134, 0.1243), (0.0137, 0.1265), (0.0134, 0.1288), (0.0122, 0.1290), (0.0122, 0.1240)]
collar = lathe("collar", col_prof)

def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format="GLB", export_apply=True,
                              export_yup=True, export_normals=True, export_materials="NONE")

export(OUT + "/vial.glb", [glass, liquid, cork, wax, twine, collar])

# ---------------------------------------------------------------- the shards
seeds = []
while len(seeds) < SHARDS:
    t = random.uniform(0, 2 * math.pi)
    z = random.uniform(0.004, 0.13)
    r = 0.04
    seeds.append(Vector((r * math.cos(t), r * math.sin(t), z)))
shards = []
for i, s in enumerate(seeds):
    bm = bmesh.new()
    bm.from_mesh(glass.data)
    for j, o in enumerate(seeds):
        if j == i:
            continue
        mid = (s + o) * 0.5
        nrm = (o - s).normalized()
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=mid, plane_no=nrm, clear_outer=True)
    if len(bm.faces) == 0:
        bm.free()
        continue
    me = bpy.data.meshes.new("shard_%d" % i)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("shard_%d" % i, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    # origin at the piece's centre
    c = sum((v.co for v in me.vertices), Vector()) / max(len(me.vertices), 1)
    me.transform(__import__("mathutils").Matrix.Translation(-c))
    ob.location = c
    shards.append(ob)
export(OUT + "/vial_shards.glb", shards)
print("vial: %d tris glass, %d shards" % (sum(len(p.vertices) - 2 for p in glass.data.polygons), len(shards)))
