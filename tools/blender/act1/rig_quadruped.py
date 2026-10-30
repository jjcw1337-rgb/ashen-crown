# A Meshy quadruped rigged for the game (the bear's rig, rig_bear.py on test-bear, with the size and ground cut as
# options): used for the archer's companion wolf (spirit_beast.gd).
#   blender -b --python tools/blender/act1/rig_quadruped.py -- <raw.glb> <out.glb> [--shoulder m] [--cut raw units] [--tris n]
#     [--blend out.blend] [--debug prefix]
# The rest is the bear's notes:
# The Forsaken Bear (Act I): Meshy's raw image-to-3D (concept 2, "corrupted ancient", standing on all fours on a slab of
# rock and roots) cleaned up, rigged and exported for the game, which poses it in code (scripts/bear.gd).
#   blender -b --python tools/blender/act1/rig_bear.py -- <bear_raw.glb> <out.glb> [--blend out.blend] [--debug prefix]
# The raw model: git show origin/jj-models:exports/forsaken_bear/bear2_meshy_raw.glb > bear_raw.glb
#
# Steps:
#  1. clean: merge Meshy's split vertices (one connected mesh), cut the slab under the paws (every face below the soles),
#     drop the ground bits left lying loose, close the paws' soles, decimate to ~25k triangles, scale to 1.6 m at the
#     shoulder, feet on the ground, origin between the paws, front toward -Y; textures 2k albedo, 1k the rest
#  2. measure the joints on the mesh (the four leg columns, the spine's depth, the skull and the jaw's gape)
#  3. the skeleton, named like the lion's (lion.gd) plus the jaw and the antlers:
#     hips spine chest neck head jaw antler_l antler_r, arm/forearm/paw_l|r, thigh/shin/foot_l|r, tail1
#  4. skin by distance along the surface: Dijkstra over the mesh's edges from each bone, so a leg can't take the belly
#     it touches (they're far apart along the surface) and the roots stay on the part they wrap; antlers all head,
#     the lower jaw only the jaw
#  5. export the skinned glb (no animations; Bear.pose turns the bones) and save the editable .blend (the full-detail
#     mesh kept, hidden, in its own collection)
import bpy, bmesh, sys, heapq, math, os
from mathutils import Vector

def _opt(name, default):
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    return float(a[a.index(name) + 1]) if name in a else default

SHOULDER = _opt("--shoulder", 1.6)   # metres at the shoulder on all fours
TRIS = int(_opt("--tris", 25000))
CUT = _opt("--cut", 0.095)           # the ground's top above the model's bottom (raw units): everything below is cut


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opt = {"in": a[0], "out": a[1], "blend": "", "debug": ""}
    for k in ("--blend", "--debug"):
        if k in a:
            opt[k[2:]] = a[a.index(k) + 1]
    return opt


# ---------------------------------------------------------------- 1. clean
def components(bm):
    bm.verts.ensure_lookup_table()
    seen = set()
    comps = []
    for v in bm.verts:
        if v.index in seen:
            continue
        st = [v]
        seen.add(v.index)
        c = []
        while st:
            a = st.pop()
            c.append(a)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    st.append(b)
        comps.append(c)
    return comps


def clean(o):
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    z0 = min(v.co.z for v in bm.verts)
    cut = z0 + CUT
    # the slab: every face lying below the soles
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if max(v.co.z for v in f.verts) < cut + 0.004], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # faces straddling the cut: drop the part below by pushing those vertices up to the sole
    for v in bm.verts:
        if v.co.z < cut:
            v.co.z = cut
    # roots trailing along the ground away from the paws: the four paws are the four clusters of sole vertices
    # (one per quadrant); anything low that is far from all four goes
    sole = [v.co.copy() for v in bm.verts if v.co.z < cut + 0.01]
    ymid = (min(p.y for p in sole) + max(p.y for p in sole)) / 2
    paws = []
    for sx in (1, -1):
        for front in (True, False):
            q = [p for p in sole if (p.x > 0) == (sx > 0) and (p.y < ymid) == front]
            if q:
                paws.append(Vector((sum(p.x for p in q) / len(q), sum(p.y for p in q) / len(q), 0)))
    def far(v):
        return min((Vector((v.co.x, v.co.y, 0)) - c).length for c in paws) > 0.17
    trail = [f for f in bm.faces if max(v.co.z for v in f.verts) < cut + 0.07 and all(far(v) for v in f.verts)]
    bmesh.ops.delete(bm, geom=trail, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    print("paws at", [tuple(round(x, 2) for x in c[:2]) for c in paws], "ground roots cut:", len(trail), "faces")
    # roots and stones left lying on the ground, no longer joined to the bear
    for c in components(bm):
        if max(v.co.z for v in c) < cut + 0.18 or len(c) < 30:
            bmesh.ops.delete(bm, geom=c, context="VERTS")
    # close the soles: the open edges on the cut plane
    edges = [e for e in bm.edges if e.is_boundary and all(abs(v.co.z - cut) < 0.002 for v in e.verts)]
    if edges:
        res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        print("soles closed:", len(res["faces"]), "faces")
    bm.to_mesh(me)
    bm.free()
    me.update()
    # decimate
    tri = sum(len(p.vertices) - 2 for p in me.polygons)
    if tri > TRIS:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = TRIS / tri
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
    # place and scale: soles on the ground, origin between the paws, the shoulder at SHOULDER
    vs = [v.co.copy() for v in me.vertices]
    zmin = min(v.z for v in vs)
    feet = [v for v in vs if v.z < zmin + 0.06]
    cx = (min(v.x for v in feet) + max(v.x for v in feet)) / 2
    cy = (min(v.y for v in feet) + max(v.y for v in feet)) / 2
    # the shoulder: the top of the back over the forelegs (the 90th percentile, so spurs and antlers don't count)
    fy = sorted(v.y for v in feet)
    front_y = sum(fy[: max(1, len(fy) // 4)]) / max(1, len(fy) // 4)
    band = sorted(v.z for v in vs if abs(v.y - (front_y + 0.12)) < 0.12 and abs(v.x - cx) < 0.2)
    top = band[int(len(band) * 0.9)] if band else max(v.z for v in vs)
    s = SHOULDER / (top - zmin)
    for v in me.vertices:
        v.co = Vector(((v.co.x - cx) * s, (v.co.y - cy) * s, (v.co.z - zmin) * s))
    me.update()
    print("cleaned: %d verts %d faces, scale %.3f, shoulder %.2f m" % (len(me.vertices), len(me.polygons), s, (top - zmin) * s))
    # textures: 2k albedo, 1k the rest
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
def _mean(vs):
    s = Vector((0, 0, 0))
    for v in vs:
        s += v
    return s / max(len(vs), 1)


def measure(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    H = max(v.z for v in vs)
    L = {}
    feet = [v for v in vs if v.z < 0.08]
    ys = sorted(v.y for v in feet)
    ymid = (ys[0] + ys[-1]) / 2
    # the four leg columns: their centre at each height, from the sole up to the belly
    def col(sx, front, z0, z1):
        b = [v for v in vs if z0 <= v.z < z1 and v.x * sx > 0.04 and ((v.y < ymid) if front else (v.y > ymid))]
        # keep the column near its sole (roots reach outward)
        return _mean(b)
    belly = 0.5 * SHOULDER
    for side, sx in (("l", 1.0), ("r", -1.0)):
        # Blender: the bear faces -Y, so its left is +X
        for front in (True, False):
            sole = col(sx, front, 0.0, 0.07)
            ank = col(sx, front, 0.10, 0.16)
            knee = col(sx, front, 0.36 * SHOULDER - 0.04, 0.36 * SHOULDER + 0.04)
            top = col(sx, front, belly - 0.04, belly + 0.04)
            # the toes: the furthest-forward sole point near this paw (roots on the ground reach further)
            near = [v for v in feet if (Vector((v.x, v.y, 0)) - Vector((sole.x, sole.y, 0))).length < 0.28]
            toe = min(near or [sole + Vector((0, -0.2, 0))], key=lambda v: v.y)
            hip = Vector((top.x * 0.75, top.y, 0.72 * SHOULDER))
            if front:
                L["arm_" + side] = ("chest", hip, knee)
                L["forearm_" + side] = ("arm_" + side, knee, ank)
                L["paw_" + side] = ("forearm_" + side, ank, Vector((ank.x, toe.y, 0.03)))
            else:
                L["thigh_" + side] = ("hips", hip, knee)
                L["shin_" + side] = ("thigh_" + side, knee, ank)
                L["foot_" + side] = ("shin_" + side, ank, Vector((ank.x, toe.y, 0.03)))
    # the spine: through the middle of the body's depth along its length
    def core(y):
        # halfway between the belly (or throat) and the top of the back, spurs and antlers left out
        b = sorted(v.z for v in vs if abs(v.x) < 0.15 and abs(v.y - y) < 0.06 and v.z > 0.3 * SHOULDER)
        return (b[len(b) // 50] + b[len(b) * 85 // 100]) / 2 if b else 0.75 * SHOULDER
    fy = L["arm_l"][1].y
    by = L["thigh_l"][1].y
    tail_y = max(v.y for v in vs if v.z > 0.4 * SHOULDER and abs(v.x) < 0.25)
    hips = Vector((0, by, core(by)))
    mid = Vector((0, (by + fy) / 2, core((by + fy) / 2)))
    chest = Vector((0, fy, core(fy)))
    # the head: the snout is the furthest point forward; the skull behind it
    snout = min(vs, key=lambda v: v.y)
    neck_y = fy - 0.25 * (fy - snout.y)
    neck = Vector((0, neck_y, core(neck_y)))
    skull = Vector((0, snout.y + 0.55 * (neck_y - snout.y), snout.z + 0.06))
    # the jaw: the mouth's lower half, hinged under the skull
    jaw_h = Vector((0, skull.y + 0.02, snout.z - 0.08))
    jaw_t = Vector((0, snout.y + 0.04, snout.z - 0.14))
    L["hips"] = ("", hips, mid)
    L["spine"] = ("hips", mid, chest)
    L["chest"] = ("spine", chest, neck)
    L["neck"] = ("chest", neck, skull)
    L["head"] = ("neck", skull, Vector((0, snout.y, snout.z)))
    L["jaw"] = ("head", jaw_h, jaw_t)
    L["tail1"] = ("hips", Vector((0, tail_y - 0.12, hips.z + 0.05)), Vector((0, tail_y + 0.05, hips.z - 0.05)))
    # antlers: everything rising above the skull, each side
    for side, sx in (("l", 1.0), ("r", -1.0)):
        ant = [v for v in vs if v.z > skull.z + 0.12 and v.y < neck_y and v.x * sx > 0.02]
        if ant:
            tip = max(ant, key=lambda v: v.z)
            L["antler_" + side] = ("head", Vector((0.08 * sx, skull.y, skull.z + 0.1)), tip)
    return L


# ---------------------------------------------------------------- 4. skin by surface distance
def _seg(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def _region(k, p, L):
    """Hard rules on top of the distance: which bones a vertex may take at all."""
    head = L["head"][1]
    if p.z > head.z + 0.1 and p.y < L["neck"][1].y:      # antlers: head only (or their own bone)
        return {"head", "antler_l", "antler_r"}
    return None


def skin(o, L):
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    P = [o.matrix_world @ v.co for v in bm.verts]
    adj = [[(e.other_vert(v).index, e.calc_length()) for e in v.link_edges] for v in bm.verts]
    n = len(P)
    jaw_lo = L["jaw"][1].z + 0.02
    D = {}
    for k, (par, h, t) in L.items():
        # seeds: vertices close to the bone (its own flesh), at their straight distance
        d = [math.inf] * n
        heap = []
        r0 = 0.10 if k not in ("hips", "spine", "chest") else 0.32
        for i, p in enumerate(P):
            s = _seg(p, h, t)
            if s < r0:
                d[i] = s
                heap.append((s, i))
        if not heap:  # the nearest few
            near = sorted(range(n), key=lambda i: _seg(P[i], h, t))[:20]
            for i in near:
                d[i] = _seg(P[i], h, t)
                heap.append((d[i], i))
        heapq.heapify(heap)
        while heap:
            dd, i = heapq.heappop(heap)
            if dd > d[i] or dd > 0.9:
                continue
            for j, w in adj[i]:
                nd = dd + w
                if nd < d[j]:
                    d[j] = nd
                    heapq.heappush(heap, (nd, j))
        D[k] = d
    o.vertex_groups.clear()
    groups = {k: o.vertex_groups.new(name=k) for k in L}
    snout_y = L["head"][2].y
    for i, p in enumerate(P):
        allow = _region(None, p, L)
        cand = []
        for k in L:
            if allow is not None and k not in allow:
                continue
            # the mouth: the lower jaw takes the lower half in front of the hinge, the head the upper
            if k == "jaw" and not (p.z < jaw_lo and p.y < L["jaw"][1].y + 0.02):
                continue
            if k == "head" and p.z < jaw_lo and p.y < L["jaw"][1].y - 0.03 and p.z < L["head"][2].z - 0.02:
                continue
            dk = D[k][i]
            if dk == math.inf:
                dk = _seg(p, L[k][1], L[k][2]) * 3.0 + 0.5   # unreached: far, but not impossible
            # softer than the sloth's 4th power: the bear bends far (rearing), so the skin shares the bend
            cand.append((1.0 / (dk + 0.04) ** 3, k))
        cand.sort(reverse=True)
        cand = cand[:4]
        tot = sum(w for w, k in cand)
        for w, k in cand:
            groups[k].add([i], w / tot, "REPLACE")
    bm.free()


# ---------------------------------------------------------------- 3 + 5. skeleton, export
def build(opt):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=opt["in"])
    o = [x for x in bpy.context.scene.objects if x.type == "MESH"][0]
    o.name = "Bear"
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # the full-detail original, kept hidden in the .blend
    full = o.copy()
    full.data = o.data.copy()
    full.name = "Bear_full_detail"
    col = bpy.data.collections.new("full_detail")
    bpy.context.scene.collection.children.link(col)
    col.objects.link(full)
    col.hide_render = True
    col.hide_viewport = True
    clean(o)
    L = measure(o)
    for k, (p, h, t) in sorted(L.items()):
        print("bone %-10s %-10s head (%.2f %.2f %.2f) tail (%.2f %.2f %.2f)" % (k, p, h.x, h.y, h.z, t.x, t.y, t.z))
    arm = bpy.data.armatures.new("BearRig")
    ar = bpy.data.objects.new("BearRig", arm)
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
    bpy.ops.export_scene.gltf(filepath=opt["out"], use_selection=True, export_format="GLB", export_skins=True,
                              export_animations=False, export_image_format="JPEG", export_jpeg_quality=90, export_yup=True)
    print("exported", opt["out"], len(L), "bones")
    if opt["blend"]:
        os.makedirs(os.path.dirname(os.path.abspath(opt["blend"])), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=opt["blend"])
    if opt["debug"]:
        debug(o, ar, L, opt["debug"])


def debug(o, ar, L, prefix):
    """Renders: the mesh coloured by its main bone, from the side, front, three-quarter and below."""
    import colorsys
    names = list(L.keys())
    col = {k: colorsys.hsv_to_rgb((i * 0.618) % 1.0, 0.75, 0.95) for i, k in enumerate(names)}
    me = o.data
    if not me.color_attributes.get("bone"):
        me.color_attributes.new("bone", "FLOAT_COLOR", "POINT")
    ca = me.color_attributes["bone"]
    gi = {g.index: g.name for g in o.vertex_groups}
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        c = col[gi[best.group]] if best else (0, 0, 0)
        ca.data[v.index].color = (c[0], c[1], c[2], 1.0)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "VERTEX"
    sc.render.resolution_x = 700
    sc.render.resolution_y = 700
    sc.world = bpy.data.worlds.new("w")
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 3.4
    c = Vector((0, 0, 0.9))
    for name, d in [("side", Vector((1, 0, 0.1))), ("front", Vector((0, -1, 0.1))), ("34", Vector((0.8, -0.8, 0.45))), ("under", Vector((0.3, -0.2, -1)))]:
        cam.location = c + d.normalized() * 8
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = "%s_%s.png" % (prefix, name)
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    build(args())
