# Cleans the camp waypoint's brazier (waypoint overhaul, the rocks pass): split_parts.py's `flame` mode cut Meshy's
# modelled flame at the bowl's rim, which left the bottom of that flame blob inside the bowl as a fused lump that
# read as "blobby blue rocks". This removes it and closes the bowl with a smooth dished floor, so the game can fill
# the bowl with real stones (scripts/brazier_coals.gd). Everything else (size, placement, textures) stays as it was.
#
#   blender -b --python clean_bowl.py -- <in.glb> <out.glb> [--hole 0.27] [--margin 0.02]
#
# --hole: radius (model units) inside which everything above the bowl's underside is removed (the blob and the
#   floor under it); the inner wall outside it is kept. --margin: how far above the underside the removal starts.
# Prints DISH <floor z> <junction r> <junction z> <lip r> <rim z> (model units, Blender z up) and EXPORTED <out>.
import bpy, bmesh, sys, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
HOLE = float(opt("--hole", "0.27"))
MARGIN = float(opt("--margin", "0.02"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data
dg = bpy.context.evaluated_depsgraph_get()
bvh = BVHTree.FromObject(ob, dg)

# --- measure: the bowl's top surface (downward rays) by radius: the inner wall outside the hole, and under the
# hole's radius the bowl's underside (the outer shell seen from outside, rays cast up from far below)
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
top = P[:, 2].max()
def ring_hits(r, up):
    zs = []
    for k in range(36):
        a = 2 * math.pi * k / 36
        if up:
            o = Vector((r * math.cos(a), r * math.sin(a), -1.0)); d = Vector((0, 0, 1))
        else:
            o = Vector((r * math.cos(a), r * math.sin(a), top + 0.5)); d = Vector((0, 0, -1))
        h = bvh.ray_cast(o, d, 4.0)
        if h[0] is not None:
            zs.append(h[0].z)
    return zs
# the inner wall just outside the hole: where the new floor must meet it
wall = {}
for r in np.arange(HOLE - 0.02, HOLE + 0.07, 0.005):
    zs = ring_hits(r, False)
    wall[round(r, 3)] = (float(np.median(zs)) if zs else top)
rim = max(wall.values())
lip_r = min(r for r, z in wall.items() if z > rim - 0.01)
wall_at_hole = wall[min(wall, key=lambda r: abs(r - HOLE))]
# the cut height: just under the inner floor at the hole's edge; the outer shell must lie below it there (the
# bowl's underside, found from far below: the first upward hit at that radius is the base or the stem, the last
# surface before the cavity is what matters, so check the underside at the hole's radius with a downward ray from
# inside the cavity's level instead)
z_cut = wall_at_hole - MARGIN - 0.01
under_hits = []
for k in range(36):
    a = 2 * math.pi * k / 36
    o = Vector((HOLE * math.cos(a), HOLE * math.sin(a), z_cut)); d = Vector((0, 0, -1))
    h = bvh.ray_cast(o, d, 2.0)
    if h[0] is not None:
        under_hits.append(h[0].z)
underside = max(under_hits) if under_hits else -1.0
print("WALL", {k: round(v, 3) for k, v in wall.items()})
print("CUT z %.4f (inner floor at the hole %.4f, the shell below it reaches %.4f)" % (z_cut, wall_at_hole, underside))
assert underside < z_cut, "the bowl's shell reaches above the cut: lower --hole or --margin"

# --- remove the blob and the floor under it: every face with a vertex inside the hole and above the cut
bm = bmesh.new()
bm.from_mesh(me)
uv_lay = bm.loops.layers.uv.active
kill = []
for f in bm.faces:
    inside = False
    for v in f.verts:
        if math.hypot(v.co.x, v.co.y) < HOLE and v.co.z > z_cut:
            inside = True
            break
    if inside:
        kill.append(f)
bmesh.ops.delete(bm, geom=kill, context="FACES")
print("REMOVED %d faces" % len(kill))

# the boundary left in the wall: its vertices give the UV spot (dark iron) and the exact junction height
junction_z = wall_at_hole
junction_r = HOLE
bound = [v for v in bm.verts if v.is_boundary and abs(v.co.z - wall_at_hole) < 0.05 and HOLE - 0.03 < math.hypot(v.co.x, v.co.y) < HOLE + 0.06]
if bound:
    junction_z = float(np.median([v.co.z for v in bound]))
    junction_r = float(np.median([math.hypot(v.co.x, v.co.y) for v in bound]))
# the texel for the new floor: among the boundary's own UVs, the one whose baked colour is the darkest matte
# iron (a median over islands would land anywhere in the atlas)
def img_named(part):
    for im in bpy.data.images:
        if part in im.name.lower():
            return im
    return None
alb, mr = img_named("albedo"), img_named("metal_rough")
def sample(img, uv):
    if img is None:
        return (0.5, 0.5, 0.5)
    w, h = img.size
    x = int(min(max(uv.x, 0.0), 0.9999) * w); y = int(min(max(uv.y, 0.0), 0.9999) * h)
    i = (y * w + x) * 4
    return tuple(img.pixels[i:i + 3])
best, best_uv = 1e9, Vector((0.5, 0.5))
for v in bound:
    for l in v.link_loops:
        uv = l[uv_lay].uv.copy()
        c = sample(alb, uv); m = sample(mr, uv)
        lum = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
        sat = max(c) - min(c)
        score = abs(lum - 0.16) + sat * 2.0 + max(0.0, 0.55 - m[1]) * 2.0 + m[2] * 1.5   # dark, grey, rough, not metal
        if score < best:
            best, best_uv = score, uv
uv0 = best_uv
print("FLOOR_TEXEL uv (%.3f, %.3f) albedo %s rough %.2f metal %.2f" % (uv0.x, uv0.y, tuple(round(c, 2) for c in sample(alb, uv0)), sample(mr, uv0)[1], sample(mr, uv0)[2]))

# --- the new floor: a shallow dish in the middle, and from the hole's edge outward it hugs the inner wall as it
# stands at each vertex's own spot, 2 mm above it (the removal left a ragged edge up to a triangle's width
# outside the hole: the dish covers it)
bm.to_mesh(me); me.update()
bvh2 = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
R_OUT = (max(math.hypot(v.co.x, v.co.y) for v in bound) if bound else HOLE) + 0.012
R0 = HOLE - 0.02
wall_r = sorted(wall)
def wall_z(r):
    return float(np.interp(r, wall_r, [wall[k] for k in wall_r]))
def wall_here(x, y, r):
    h = bvh2.ray_cast(Vector((x, y, top + 0.5)), Vector((0, 0, -1)), 2.0)
    if h[0] is not None and h[0].z > z_cut:
        return h[0].z
    return wall_z(r)
floor_z = wall_z(R0) - 0.02                     # the dish's centre sits a little below the wall's foot
def dish_z(x, y):
    r = math.hypot(x, y)
    if r <= R0:
        return floor_z + (wall_z(R0) + 0.002 - floor_z) * ((r / R0) ** 2.2)
    return max(wall_here(x, y, r), wall_z(R0)) + 0.002
RINGS, SEGS = 12, 60
verts = [bm.verts.new(Vector((0.0, 0.0, dish_z(0.0, 0.0))))]
for i in range(1, RINGS + 1):
    r = R_OUT * (i / RINGS) ** 1.25
    for s in range(SEGS):
        a = 2 * math.pi * s / SEGS
        x, y = r * math.cos(a), r * math.sin(a)
        verts.append(bm.verts.new(Vector((x, y, dish_z(x, y)))))
faces = []
for s in range(SEGS):
    faces.append(bm.faces.new((verts[0], verts[1 + s], verts[1 + (s + 1) % SEGS])))
for i in range(1, RINGS):
    for s in range(SEGS):
        a0 = 1 + (i - 1) * SEGS + s
        a1 = 1 + (i - 1) * SEGS + (s + 1) % SEGS
        b0 = 1 + i * SEGS + s
        b1 = 1 + i * SEGS + (s + 1) % SEGS
        faces.append(bm.faces.new((verts[a0], verts[b0], verts[b1], verts[a1])))
# UVs: a tiny patch round the wall's own texel, so the floor stays the bowl's dark iron with a little variation
for f in faces:
    f.smooth = True
    for l in f.loops:
        co = l.vert.co
        l[uv_lay].uv = uv0 + Vector((co.x, co.y)) * 0.004
bmesh.ops.recalc_face_normals(bm, faces=faces)
# make sure the dish faces up (recalc on an open patch can flip them)
if sum(f.normal.z for f in faces) < 0:
    bmesh.ops.reverse_faces(bm, faces=faces)
bm.to_mesh(me)
bm.free()
me.update()

print("DISH floor_z %.4f junction_r %.4f junction_z %.4f lip_r %.4f rim_z %.4f top_before %.4f" % (floor_z, junction_r, junction_z, lip_r, rim, top))
bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_image_format="AUTO", export_jpeg_quality=90)
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
print("PROP", OUT, "tris", sum(len(p.vertices) - 2 for p in me.polygons), "size x %.2f y %.2f h %.2f" % tuple(np.ptp(P, axis=0)))
print("EXPORTED", OUT)
