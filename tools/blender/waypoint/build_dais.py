# The camp's grand waypoint dais, modelled in code (waypoint overhaul, stage 2).
#
# A three-tier stepped platform of dressed stone blocks (each block its own bevelled, chipped, slightly
# tilted piece with a small joint between), and a top floor of flagstones laid in rings. The gaps between the
# floor's rings and the eight spokes ARE the rune channels: their bottom (object "groove") sits a few
# centimetres below the floor, and WaypointGrand lays the glowing rune meshes in them, so the light comes out of
# carved grooves instead of sitting on the stone. The octagonal socket in the middle holds the crystal.
# Meshy is poor at a flat 10 m disc with fine grooves (it melts them), so this one is built here. Textures come
# from the game (Mats.world, the camp's stone), so the glb has geometry only and four objects:
#   steps (the tiers), floor (the flagstones), groove (the channel floor), socket.
# The radii must match WaypointGrand (RINGS, SPOKE_R, TIERS).
#
#   blender -b --python tools/blender/waypoint/build_dais.py -- assets/models/waypoint/dais.glb [--seed 7741]
import bpy, bmesh, sys, math, random
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
SEED = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 7741
rng = random.Random(SEED)

TIERS = [(4.85, 0.12), (4.15, 0.24), (3.45, 0.36)]     # outer radius, top height (m); top tier = the floor's rim
FLOOR_Y = 0.36
GROOVE_Y = 0.325                                      # channel bottom
# floor rings between the channels (inner, outer): the channels are the gaps 1.01-1.09, 1.92-2.02, 2.70-2.82
FLOOR_RINGS = [(0.70, 1.01), (1.09, 1.92), (2.02, 2.70), (2.82, 3.30)]
SPOKE_RING = 1          # the ring the eight spokes cut across
SPOKE_W = 0.055
JOINT = 0.012           # gap between blocks
BEVEL = 0.022

bpy.ops.wm.read_factory_settings(use_empty=True)

def segment(bm, r0, r1, a0, a1, y0, y1, segs, tilt=(0.0, 0.0), sink=0.0):
    """A curved block (annular sector) from angle a0 to a1, radius r0..r1, height y0..y1 (Blender z up)."""
    rows = []
    for s in range(segs + 1):
        a = a0 + (a1 - a0) * s / segs
        ca, sa = math.cos(a), math.sin(a)
        ring = []
        for (r, z) in ((r0, y0), (r1, y0), (r1, y1), (r0, y1)):
            zt = z
            if z == y1:
                zt = y1 - sink + tilt[0] * (r - (r0 + r1) * 0.5) + tilt[1] * ((s / segs) - 0.5) * (a1 - a0) * r
            ring.append(bm.verts.new((r * ca, r * sa, zt)))
        rows.append(ring)
    faces = []
    for s in range(segs):
        a, b = rows[s], rows[s + 1]
        for k in range(4):
            faces.append(bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k])))
    faces.append(bm.faces.new(tuple(reversed(rows[0]))))
    faces.append(bm.faces.new(tuple(rows[-1])))
    return [v for r in rows for v in r]

_tmp_me = None

def block(bm, make, chip=0.012):
    """Build one block with `make(b)` in a fresh bmesh, bevel and weather it, append it to `bm`."""
    global _tmp_me
    b = bmesh.new()
    make(b)
    bmesh.ops.bevel(b, geom=list(b.edges), offset=BEVEL, segments=2, affect="EDGES", profile=0.6)
    b.normal_update()
    off = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
    ztop = max(v.co.z for v in b.verts)
    for v in b.verts:
        n = noise.noise(v.co * 4.0 + off)
        edge = 1.0 if v.co.z > ztop - 0.03 else 0.35
        v.co += v.normal * (n * chip * edge)
    if rng.random() < 0.3:      # a chipped corner now and then
        c = max(b.verts, key=lambda v: v.co.z + rng.uniform(0, 0.02))
        cc = c.co.copy()
        for v in b.verts:
            d = (v.co - cc).length
            if d < 0.09:
                v.co.z -= (0.09 - d) * 0.5
    if _tmp_me is None:
        _tmp_me = bpy.data.meshes.new("_tmp")
    b.to_mesh(_tmp_me)
    b.free()
    bm.from_mesh(_tmp_me)

def mesh_obj(name, build):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    build(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    return ob

def blocks_ring(bm, r0, r1, y0, y1, arc, segs, cut_angles=(), cut_w=0.0, sink=(0.0, 0.0), chip=0.012):
    n = max(6, int(round(math.tau * (r0 + r1) * 0.5 / arc)))
    bounds = [math.tau * (i + rng.uniform(-0.12, 0.12)) / n for i in range(n)]
    bounds.append(bounds[0] + math.tau)
    for i in range(n):
        a0, a1 = bounds[i], bounds[i + 1]
        pieces = [(a0, a1)]
        for ca in cut_angles:           # spokes: split the block where a spoke crosses it
            for k in range(-1, 2):
                c = ca + k * math.tau
                np_ = []
                for (p0, p1) in pieces:
                    if p0 < c < p1:
                        hw = cut_w * 0.5 / ((r0 + r1) * 0.5)
                        np_ += [(p0, c - hw), (c + hw, p1)]
                    else:
                        np_.append((p0, p1))
                pieces = np_
        for (p0, p1) in pieces:
            if p1 - p0 < 0.01:
                continue
            j = JOINT * 0.5 / ((r0 + r1) * 0.5)
            tl = (rng.uniform(-0.012, 0.012), rng.uniform(-0.01, 0.01))
            sk = rng.uniform(*sink)
            block(bm, lambda b, p0=p0, p1=p1, j=j, tl=tl, sk=sk: segment(b, r0 + JOINT * 0.5, r1 - JOINT * 0.5,
                  p0 + j, p1 - j, y0, y1, segs, tilt=tl, sink=sk), chip)

def build_steps(bm):
    for t, (r_out, top) in enumerate(TIERS):
        r_in = TIERS[t + 1][0] - 0.15 if t + 1 < len(TIERS) else FLOOR_RINGS[-1][1]
        # outer course: tall dressed blocks; the tier's top is these blocks' top
        blocks_ring(bm, r_in, r_out, 0.0, top, arc=0.95 - t * 0.08, segs=3, sink=(0.0, 0.025))

def build_floor(bm):
    spokes = [math.tau * i / 8 for i in range(8)]
    for i, (r0, r1) in enumerate(FLOOR_RINGS):
        cut = spokes if i == SPOKE_RING else ()
        # flagstones: radial joints every ~0.7 m, and a second course in the wide rings
        if r1 - r0 > 0.6:
            mid = (r0 + r1) * 0.5 + rng.uniform(-0.05, 0.05)
            blocks_ring(bm, r0, mid, FLOOR_Y - 0.12, FLOOR_Y, 0.7, 2, cut, SPOKE_W, sink=(0.0, 0.012), chip=0.008)
            blocks_ring(bm, mid, r1, FLOOR_Y - 0.12, FLOOR_Y, 0.75, 2, cut, SPOKE_W, sink=(0.0, 0.012), chip=0.008)
        else:
            blocks_ring(bm, r0, r1, FLOOR_Y - 0.12, FLOOR_Y, 0.7, 2, cut, SPOKE_W, sink=(0.0, 0.012), chip=0.008)

def build_groove(bm):
    # one flat disc under the whole floor: what shows through the channels
    n = 64
    c = bm.verts.new((0, 0, GROOVE_Y))
    ring = [bm.verts.new((3.32 * math.cos(math.tau * i / n), 3.32 * math.sin(math.tau * i / n), GROOVE_Y)) for i in range(n)]
    for i in range(n):
        bm.faces.new((c, ring[i], ring[(i + 1) % n]))

def build_socket(bm):
    # octagonal carved socket: a plinth course and a raised rim with a channel round its top
    for (r0, r1, y0, y1, a_off) in ((0.0, 0.70, FLOOR_Y - 0.1, FLOOR_Y + 0.08, 0.0),
                                    (0.50, 0.66, FLOOR_Y + 0.08, FLOOR_Y + 0.24, math.pi / 8)):
        for i in range(8):
            a0 = math.tau * i / 8 + a_off
            a1 = math.tau * (i + 1) / 8 + a_off
            block(bm, lambda b, a0=a0, a1=a1, r0=r0, r1=r1, y0=y0, y1=y1: segment(b, max(r0, 0.001), r1,
                  a0 + 0.004, a1 - 0.004, y0, y1, 1), 0.006)

objs = [mesh_obj("steps", build_steps), mesh_obj("floor", build_floor),
        mesh_obj("groove", build_groove), mesh_obj("socket", build_socket)]
tris = sum(len(o.data.polygons) for o in objs)
for o in objs:
    o.data.calc_loop_triangles()
print("TRIS", sum(len(o.data.loop_triangles) for o in objs))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True,
                          export_normals=True, export_materials="NONE")
print("EXPORTED", OUT)
