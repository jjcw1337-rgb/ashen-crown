# A Meshy two-legged dinosaur (theropod: the raptor, the T-Rex) rigged for the game, which poses it in code
# (scripts/theropod.gd), like the quadrupeds (tools/blender/act1/rig_quadruped.py, the lion and the bear).
#   blender -b --python tools/blender/dino/rig_theropod.py -- <raw.glb> <out.glb> --length m [--cut raw units] [--tris n]
#     [--blend out.blend] [--debug prefix]
# The raw model stands side-on, head toward -Y (Meshy's image-to-3D of a side-on concept). Every distance below is a
# fraction of the hip height H (measured after scaling), so one script serves a raptor and a tyrant.
#  1. clean: merge split vertices, cut a base/slab under the feet (--cut), drop loose ground bits, close the soles,
#     decimate (--tris), scale to --length m from snout to tail tip, feet on the ground, origin between them
#  2. measure the joints on the mesh: the two leg columns (thigh, the forward knee... the theropod's hock, the long
#     metatarsus, the toes), the spine through the body's depth, the neck and the skull, the jaw, the tail's centreline
#     to its tip, the little arms
#  3. the skeleton: hips spine chest neck neck2 head jaw, tail1..tail6, thigh/shin/foot/toe_l|r, arm/forearm_l|r
#  4. skin by distance along the surface (Dijkstra over the edges from each bone, as the quadrupeds), so a leg doesn't
#     take the belly it touches; the lower jaw only the jaw
#  5. export the skinned glb (no animations) and save the editable .blend (the full-detail mesh kept, hidden)
import bpy, bmesh, sys, heapq, math, os
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def _opt(name, default):
    return float(ARGS[ARGS.index(name) + 1]) if name in ARGS else default


LENGTH = _opt("--length", 2.6)
HIP = 1.0       # the hip joint's height, measured by clean() on the body's centreline
TRIS = int(_opt("--tris", 30000))
CUT = _opt("--cut", 0.0)


def components(bm):
    bm.verts.ensure_lookup_table()
    seen = set()
    comps = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        seen.add(v.index)
        comp = []
        while stack:
            x = stack.pop()
            comp.append(x)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen:
                    seen.add(y.index)
                    stack.append(y)
        comps.append(comp)
    return comps


def _mean(vs):
    s = Vector((0, 0, 0))
    for v in vs:
        s += v
    return s / max(len(vs), 1)


# ---------------------------------------------------------------- 1. clean
def clean(o):
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    z0 = min(v.co.z for v in bm.verts)
    cut = z0 + CUT
    if CUT > 0.0:
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if max(v.co.z for v in f.verts) < cut + 0.004], context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        for v in bm.verts:
            if v.co.z < cut:
                v.co.z = cut
    # loose bits (ground scraps, specks)
    comps = components(bm)
    big = max(len(c) for c in comps)
    for c in comps:
        if len(c) < max(30, big * 0.002) or (CUT > 0.0 and max(v.co.z for v in c) < cut + 0.05):
            bmesh.ops.delete(bm, geom=c, context="VERTS")
    if CUT > 0.0:
        edges = [e for e in bm.edges if e.is_boundary and all(abs(v.co.z - cut) < 0.002 for v in e.verts)]
        if edges:
            bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bm.to_mesh(me)
    bm.free()
    me.update()
    tri = sum(len(p.vertices) - 2 for p in me.polygons)
    if tri > TRIS:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = TRIS / tri
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
    # place and scale: the feet on the ground, origin between them, LENGTH from the snout to the tail's tip
    global HIP
    vs = [v.co.copy() for v in me.vertices]
    zmin = min(v.z for v in vs)
    zmax = max(v.z for v in vs)
    feet = [v for v in vs if v.z < zmin + 0.04 * (zmax - zmin)]
    cx = (min(v.x for v in feet) + max(v.x for v in feet)) / 2
    cy = (min(v.y for v in feet) + max(v.y for v in feet)) / 2
    s = LENGTH / (max(v.y for v in vs) - min(v.y for v in vs))
    for v in me.vertices:
        v.co = Vector(((v.co.x - cx) * s, (v.co.y - cy) * s, (v.co.z - zmin) * s))
    me.update()
    # the hip joint: halfway through the body's depth over the feet, on the centreline (the legs stand out to the sides)
    vs = [v.co for v in me.vertices]
    W = max(v.x for v in vs) - min(v.x for v in vs)
    band = sorted(v.z for v in vs if abs(v.x) < 0.1 * W and abs(v.y) < 0.03 * LENGTH)
    HIP = (band[len(band) // 20] + band[len(band) * 95 // 100]) / 2 if band else 0.35 * LENGTH
    print("cleaned: %d verts %d faces, scale %.3f, hip %.2f m, height %.2f m, length %.2f m" % (len(me.vertices), len(me.polygons), s,
          HIP, (zmax - zmin) * s, LENGTH))
    for mat in me.materials:
        if not mat or not mat.use_nodes:
            continue
        for n in mat.node_tree.nodes:
            if n.type != "TEX_IMAGE" or not n.image:
                continue
            base = any(l.to_socket.name == "Base Color" for l in n.outputs[0].links)
            want = 2048 if base else 1024
            if n.image.size[0] > want:
                n.image.scale(want, want)


# ---------------------------------------------------------------- 2. measure
def measure(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    H = HIP
    L = {}
    W = max(v.x for v in vs) - min(v.x for v in vs)
    feet = [v for v in vs if v.z < 0.06 * H]

    def core(y, wide=0.25):
        b = sorted(v.z for v in vs if abs(v.x) < wide * W and abs(v.y - y) < 0.05 * H)
        return ((b[len(b) // 50] + b[len(b) * 85 // 100]) / 2, b[len(b) // 50], b[len(b) * 85 // 100]) if b else (H, H * 0.8, H * 1.2)

    for side, sx in (("l", 1.0), ("r", -1.0)):
        # Blender: the dinosaur faces -Y, so its left is +X
        f = [v for v in feet if v.x * sx > 0.0]
        sole = _mean(f)
        toe = min(f, key=lambda v: v.y)
        heel = max(f, key=lambda v: v.y)
        near = lambda v: abs(v.y - sole.y) < 0.45 * H and v.x * sx > 0.02 * W
        def col(z0, z1, ny=0.45):
            b = [v for v in vs if z0 <= v.z < z1 and v.x * sx > 0.02 * W and abs(v.y - sole.y) < ny * H]
            return _mean(b) if b else sole + Vector((0, 0, (z0 + z1) / 2))
        ank = col(0.16 * H, 0.24 * H, 0.35)          # the hock (the heel up off the ground)
        knee = col(0.48 * H, 0.58 * H)
        top = col(0.86 * H, 0.98 * H, 0.55)
        ball = Vector((ank.x, (sole.y + toe.y) / 2, 0.03 * H))
        hip = Vector((top.x * 0.7, top.y + 0.04 * H, 0.95 * H))
        knee.y = min(knee.y, hip.y - 0.08 * H)        # the knee forward of the hip, the way they stand
        L["thigh_" + side] = ("hips", hip, knee)
        L["shin_" + side] = ("thigh_" + side, knee, ank)
        L["foot_" + side] = ("shin_" + side, ank, ball)
        L["toe_" + side] = ("foot_" + side, ball, Vector((ball.x, toe.y, 0.02 * H)))
    hy = (L["thigh_l"][1].y + L["thigh_r"][1].y) / 2
    snout = min(vs, key=lambda v: v.y)
    tail_tip = max(vs, key=lambda v: v.y)
    front = hy - snout.y           # hips to the snout's tip
    # the body: the chest a third of the way to the snout, the neck's base beyond it, the skull behind the snout
    cy = hy - 0.36 * front
    ny = hy - 0.6 * front
    n2y = hy - 0.76 * front
    sk_y = snout.y + 0.16 * front
    hips = Vector((0, hy, core(hy)[0]))
    mid = Vector((0, (hy + cy) / 2, core((hy + cy) / 2)[0]))
    chest = Vector((0, cy, core(cy)[0]))
    neck = Vector((0, ny, core(ny)[0]))
    neck2 = Vector((0, n2y, core(n2y)[0]))
    skull = Vector((0, sk_y, core(sk_y)[0] + 0.03 * H))
    L["hips"] = ("", hips, mid)
    L["spine"] = ("hips", mid, chest)
    L["chest"] = ("spine", chest, neck)
    L["neck"] = ("chest", neck, neck2)
    L["neck2"] = ("neck", neck2, skull)
    L["head"] = ("neck2", skull, Vector((0, snout.y, snout.z)))
    # the jaw: the mouth's lower half, hinged under the back of the skull
    lo = core(sk_y)[1]
    jaw_h = Vector((0, skull.y + 0.03 * H, (skull.z + lo) / 2 - 0.02 * H))
    jaw_t = Vector((0, snout.y + 0.03 * H, lo + 0.02 * H))
    L["jaw"] = ("head", jaw_h, jaw_t)
    # the tail: six bones along its centreline from the hips to the tip
    ty0 = hy + 0.06 * H
    prev = "hips"
    pts = []
    for i in range(7):
        y = ty0 + (tail_tip.y - ty0) * (i / 6.0) ** 0.9
        c = core(y, 0.4)[0] if i < 6 else tail_tip.z
        pts.append(Vector((0, y, c)))
    for i in range(6):
        k = "tail%d" % (i + 1)
        L[k] = (prev, pts[i], pts[i + 1])
        prev = k
    # the little arms: what hangs below the chest's core, each side, between the chest and the neck's base
    for side, sx in (("l", 1.0), ("r", -1.0)):
        a = [v for v in vs if v.x * sx > 0.12 * W and ny - 0.05 * H < v.y < cy + 0.25 * H and v.z < chest.z - 0.05 * H and v.z > 0.35 * H]
        if len(a) < 20:
            continue
        sh = Vector((0.18 * W * sx, cy - 0.12 * H, chest.z - 0.04 * H))
        low = min(a, key=lambda v: v.z)
        el = (sh + low) / 2 + Vector((0, 0.04 * H, 0))
        L["arm_" + side] = ("chest", sh, el)
        L["forearm_" + side] = ("arm_" + side, el, low)
    return L


# ---------------------------------------------------------------- 4. skin by surface distance
def _seg(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def skin(o, L):
    H = HIP
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    P = [o.matrix_world @ v.co for v in bm.verts]
    adj = [[(e.other_vert(v).index, e.calc_length()) for e in v.link_edges] for v in bm.verts]
    n = len(P)
    D = {}
    core = ("hips", "spine", "chest")
    for k, (par, h, t) in L.items():
        d = [math.inf] * n
        heap = []
        r0 = (0.28 if k in core else (0.12 if k.startswith(("neck", "head", "tail")) else 0.07)) * H
        for i, p in enumerate(P):
            s = _seg(p, h, t)
            if s < r0:
                d[i] = s
                heap.append((s, i))
        if not heap:
            near = sorted(range(n), key=lambda i: _seg(P[i], h, t))[:20]
            for i in near:
                d[i] = _seg(P[i], h, t)
                heap.append((d[i], i))
        heapq.heapify(heap)
        cap = 0.8 * H
        while heap:
            dd, i = heapq.heappop(heap)
            if dd > d[i] or dd > cap:
                continue
            for j, w in adj[i]:
                nd = dd + w
                if nd < d[j]:
                    d[j] = nd
                    heapq.heappush(heap, (nd, j))
        D[k] = d
    o.vertex_groups.clear()
    groups = {k: o.vertex_groups.new(name=k) for k in L}
    jaw_lo = (L["jaw"][1].z + L["jaw"][2].z) / 2 + 0.02 * H
    hinge_y = L["jaw"][1].y
    for i, p in enumerate(P):
        cand = []
        for k in L:
            # the mouth: the lower jaw takes the lower half in front of the hinge, the head the upper
            if k == "jaw" and not (p.z < jaw_lo and p.y < hinge_y + 0.02 * H):
                continue
            if k == "head" and p.z < jaw_lo - 0.02 * H and p.y < hinge_y - 0.03 * H:
                continue
            dk = D[k][i]
            if dk == math.inf:
                dk = _seg(p, L[k][1], L[k][2]) * 3.0 + 0.6 * H
            cand.append((1.0 / (dk + 0.03 * H) ** 3, k))
        cand.sort(reverse=True)
        cand = cand[:4]
        tot = sum(w for w, k in cand)
        for w, k in cand:
            groups[k].add([i], w / tot, "REPLACE")
    bm.free()


# ---------------------------------------------------------------- 3 + 5. skeleton, export
def build():
    out = ARGS[1]
    blend = ARGS[ARGS.index("--blend") + 1] if "--blend" in ARGS else ""
    dbg = ARGS[ARGS.index("--debug") + 1] if "--debug" in ARGS else ""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=ARGS[0])
    ms = [x for x in bpy.context.scene.objects if x.type == "MESH"]
    bpy.context.view_layer.objects.active = ms[0]
    for x in ms:
        x.select_set(True)
    if len(ms) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = "Dino"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    full = o.copy()
    full.data = o.data.copy()
    full.name = "Dino_full_detail"
    col = bpy.data.collections.new("full_detail")
    bpy.context.scene.collection.children.link(col)
    col.objects.link(full)
    col.hide_render = True
    col.hide_viewport = True
    clean(o)
    L = measure(o)
    for k, (p, h, t) in sorted(L.items()):
        print("bone %-10s %-10s head (%.2f %.2f %.2f) tail (%.2f %.2f %.2f)" % (k, p, h.x, h.y, h.z, t.x, t.y, t.z))
    arm = bpy.data.armatures.new("DinoRig")
    ar = bpy.data.objects.new("DinoRig", arm)
    bpy.context.scene.collection.objects.link(ar)
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = ar
    bpy.ops.object.mode_set(mode="EDIT")
    for k, (p, h, t) in L.items():
        b = arm.edit_bones.new(k)
        b.head, b.tail = h, t
    for k, (p, h, t) in L.items():
        if p:
            arm.edit_bones[k].parent = arm.edit_bones[p]
    bpy.ops.object.mode_set(mode="OBJECT")
    skin(o, L)
    o.parent = ar
    am = o.modifiers.new("arm", "ARMATURE")
    am.object = ar
    for x in bpy.context.selected_objects:
        x.select_set(False)
    o.select_set(True)
    ar.select_set(True)
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format="GLB", export_skins=True,
                              export_animations=False, export_image_format="JPEG", export_jpeg_quality=90, export_yup=True)
    print("exported", out, len(L), "bones")
    if blend:
        os.makedirs(os.path.dirname(os.path.abspath(blend)), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=blend)
    if dbg:
        debug(o, ar, L, dbg)


def debug(o, ar, L, prefix):
    """Renders the mesh coloured by each vertex's strongest bone, from the side, the front and 3/4."""
    import random
    random.seed(4)
    cols = {k: (random.random(), random.random(), random.random(), 1) for k in L}
    me = o.data
    if not me.color_attributes:
        me.color_attributes.new("dbg", "BYTE_COLOR", "POINT")
    ca = me.color_attributes[0]
    names = {g.index: g.name for g in o.vertex_groups}
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        ca.data[v.index].color = cols[names[best.group]] if best else (1, 1, 1, 1)
    mat = bpy.data.materials.new("dbg")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = ca.name
    nt.links.new(vc.outputs[0], bsdf.inputs["Base Color"])
    o.data.materials.clear()
    o.data.materials.append(mat)
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x = sc.render.resolution_y = 800
    w = bpy.data.worlds.new("w")
    w.color = (0.2, 0.2, 0.2)
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sc.collection.objects.link(sun)
    sun.rotation_euler = (0.8, 0.3, 0.6)
    ys = [v.co.y for v in me.vertices]
    span = max(ys) - min(ys)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = span * 1.1
    sc.camera = cam
    mid_y = (max(ys) + min(ys)) / 2
    for nm, loc, rot in (("side", (span * 2, mid_y, HIP), (math.pi / 2, 0, math.pi / 2)),
                         ("front", (0, min(ys) - span * 2, HIP), (math.pi / 2, 0, 0)),
                         ("34", (span * 1.4, mid_y - span * 1.4, HIP * 1.6), (1.2, 0, math.radians(45)))):
        cam.location = loc
        cam.rotation_euler = rot
        sc.render.filepath = "%s_%s.png" % (prefix, nm)
        bpy.ops.render.render(write_still=True)


build()
