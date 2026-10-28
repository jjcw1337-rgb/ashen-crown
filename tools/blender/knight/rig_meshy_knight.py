# Rigs the Meshy knight (A-pose, white shirt and shorts, long hair) for the game.
#   blender -b --python rig_meshy_knight.py -- <in.glb> <out.glb> <layout.json>
# The model faces -y in Blender after import. Steps: colour-classify hair/beard from the base-colour
# texture, skin by distance to each bone segment (hair rides the head + two sway bones), swing the
# arms down and straighten the legs into the game's rest pose (linear blend skinning in numpy),
# turn him to face +y (Godot -z after export) and export a skinned glb. layout.json gets the joint
# positions in Godot axes (x, z, -y) for Knight.MESHY_LAYOUT.
import bpy, sys, json, math
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, LAYOUT = argv[0], argv[1], argv[2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
body = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = body.data
N = len(me.vertices)
P = np.empty(N * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
P[:, 2] -= P[:, 2].min()

# --- per-vertex base colour (average of its loops' texels)
img = None
for n in body.active_material.node_tree.nodes:
    if n.type == "BSDF_PRINCIPLED":
        l = n.inputs["Base Color"].links
        if l and l[0].from_node.type == "TEX_IMAGE":
            img = l[0].from_node.image
W_, H_ = img.size
pix = np.array(img.pixels[:], dtype=np.float32).reshape(H_, W_, 4)
uv = np.empty(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
lv = np.empty(len(me.loops), dtype=np.int64); me.loops.foreach_get("vertex_index", lv)
px = np.clip((uv[:, 0] % 1.0) * W_, 0, W_ - 1).astype(int)
py = np.clip((uv[:, 1] % 1.0) * H_, 0, H_ - 1).astype(int)
col = pix[py, px, :3]
vc = np.zeros((N, 3)); cnt = np.zeros(N)
np.add.at(vc, lv, col); np.add.at(cnt, lv, 1)
vc /= np.maximum(cnt, 1)[:, None]
lum = vc @ np.array([0.2126, 0.7152, 0.0722])
x, y, z = P[:, 0], P[:, 1], P[:, 2]

def sm(v, a, b):
    t = np.clip((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

dark = (lum < 0.16) & (z > 1.3) & ((np.hypot(x, y) < 0.19) | (z > 1.6))
beard = dark & (y < -0.035) & (np.abs(x) < 0.085) & (z > 1.55)
hair = dark & ~beard
print("hair verts", hair.sum(), "beard", beard.sum(), "of", N)

# --- a red crusader cross dyed into the shirt front (keeps the cloth's folds and shading)
def paint_cross():
    cx, cz = 0.0, 1.34                      # centre of the cross on the chest (A-pose, front is -y)
    half_v, half_h, w = 0.15, 0.105, 0.028  # half lengths of the bars and half bar width
    cross_z = cz + 0.045                    # the crossbar sits above the middle
    red = np.array([0.36, 0.012, 0.012])
    def inside(px, pz):
        dv = np.maximum(np.abs(px - cx) - w, np.abs(pz - cz) - half_v)
        dh = np.maximum(np.abs(px - cx) - half_h, np.abs(pz - cross_z) - w)
        return np.minimum(dv, dh)            # < 0 inside the cross (signed, metres)
    nlp = len(me.polygons)
    ls = np.empty(nlp, dtype=np.int64); me.polygons.foreach_get("loop_start", ls)
    lt = np.empty(nlp, dtype=np.int64); me.polygons.foreach_get("loop_total", lt)
    K = np.zeros((H_, W_), np.float32)   # coverage of the cross per texel (max over faces)
    painted = 0
    for f in range(nlp):
        if lt[f] != 3:
            continue
        L = np.arange(ls[f], ls[f] + 3)
        vi = lv[L]
        V = P[vi]
        if not (V[:, 1].max() < 0.0 and V[:, 2].min() > 1.15 and V[:, 2].max() < 1.56 and np.abs(V[:, 0]).max() < 0.17):
            continue
        if hair[vi].all() or beard[vi].any():
            continue
        if inside(V[:, 0], V[:, 2]).min() > 0.004:
            continue
        T = uv[L] * np.array([W_, H_])
        x0, y0 = np.floor(T.min(0)).astype(int); x1, y1 = np.ceil(T.max(0)).astype(int)
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        Q = np.stack([gx.ravel() + 0.5, gy.ravel() + 0.5], 1)
        a, b, c = T
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-9:
            continue
        l1 = ((b[1] - c[1]) * (Q[:, 0] - c[0]) + (c[0] - b[0]) * (Q[:, 1] - c[1])) / den
        l2 = ((c[1] - a[1]) * (Q[:, 0] - c[0]) + (a[0] - c[0]) * (Q[:, 1] - c[1])) / den
        l3 = 1 - l1 - l2
        m = (l1 >= -0.25) & (l2 >= -0.25) & (l3 >= -0.25)   # bleed past the triangle so UV seams don't show
        if not m.any():
            continue
        B = np.stack([l1[m], l2[m], l3[m]], 1)
        X = B @ V
        d = inside(X[:, 0], X[:, 2])
        k = np.clip(0.5 - d / 0.0025, 0, 1)    # soft 2.5 mm edge
        sel = k > 0
        if not sel.any():
            continue
        qx = np.clip(gx.ravel()[m][sel], 0, W_ - 1); qy = np.clip(gy.ravel()[m][sel], 0, H_ - 1)
        np.maximum.at(K, (qy, qx), k[sel].astype(np.float32))
        painted += int(sel.sum())
    out = pix.copy()
    lumo = pix[..., :3] @ np.array([0.2126, 0.7152, 0.0722])
    shade = np.clip(lumo / 0.85, 0.45, 1.12)[..., None]
    out[..., :3] = pix[..., :3] * (1 - K[..., None]) + (red * shade) * K[..., None]
    print("cross texels", painted)
    path = OUT.rsplit(".", 1)[0] + "_basecolor.png"
    im2 = bpy.data.images.new("KnightBase", W_, H_, alpha=True)
    im2.pixels.foreach_set(out.reshape(-1).astype(np.float32))
    im2.filepath_raw = path; im2.file_format = "PNG"; im2.save()
    for n in body.active_material.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image == img:
            n.image = im2
if "--cross" in argv:
    paint_cross()

# --- joints in the A-pose (front is -y; the character's right side is -x)
def J(s):
    S = np.array([s * 0.18, 0.0, 1.53]); E = np.array([s * 0.366, 0.0, 1.27]); Wr = np.array([s * 0.516, -0.05, 1.05])
    T = np.array([s * 0.618, -0.095, 0.894])
    Hp = np.array([s * 0.09, 0.0, 0.9]); K = np.array([s * 0.135, -0.01, 0.47]); A = np.array([s * 0.165, 0.0, 0.085])
    return S, E, Wr, T, Hp, K, A
side_name = {-1: "_r", 1: "_l"}
seg = {"hips": ((0, 0, 0.78), (0, 0, 1.0)), "torso": ((0, 0, 1.05), (0, 0, 1.5)), "head": ((0, -0.01, 1.64), (0, -0.01, 1.85))}
for s in (-1, 1):
    S, E, Wr, T, Hp, K, A = J(s)
    n = side_name[s]
    seg["sh" + n] = (S, E); seg["el" + n] = (E, Wr); seg["hand" + n] = (Wr, T)
    seg["leg" + n] = (Hp, K); seg["knee" + n] = (K, A)
names = ["hips", "torso", "head", "sh_r", "el_r", "hand_r", "sh_l", "el_l", "hand_l", "leg_r", "knee_r", "leg_l", "knee_l", "hair1", "hair2"]
idx = {n: i for i, n in enumerate(names)}

def seg_dist(a, b):
    a = np.asarray(a, float); ab = np.asarray(b, float) - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)

Wt = np.zeros((N, len(names)))
for n, (a, b) in seg.items():
    Wt[:, idx[n]] = 1.0 / (seg_dist(a, b) + 0.025) ** 6
# keep left and right limbs apart (a leg never takes the other side's verts, likewise arms)
for s in (-1, 1):
    other = (s * x < -0.02)
    for b in ("sh", "el", "hand", "leg", "knee"):
        Wt[other, idx[b + side_name[s]]] = 0.0
# the feet ride the shins
foot = z < 0.13
for s in (-1, 1):
    m = foot & (s * x > 0)
    Wt[m] = 0; Wt[m, idx["knee" + side_name[s]]] = 1
Wt /= Wt.sum(1, keepdims=True)

def take(mask_w, bone):
    Wt[:] *= (1 - mask_w)[:, None]; Wt[:, idx[bone]] += mask_w
# head and beard are rigid on the head; hair hangs on head -> hair1 -> hair2 by height
headzone = (sm(z, 1.6, 1.66)) * (1 - (hair | beard))
take(headzone, "head")
take(beard.astype(float), "head")
h = hair.astype(float)
take(h, "head")
lower = sm(1.7 - z, 0.0, 0.08)
take(h * lower * (1 - sm(1.5 - z, 0.0, 0.08)), "hair1")
take(h * sm(1.5 - z, 0.0, 0.08), "hair2")

# --- repose: arms straight down, legs straight (rotations about the joints)
def rot_to(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = a @ b
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))
M = {n: (np.eye(3), np.zeros(3)) for n in names}   # x' = R x + t
def compose(R2, c2, Rt):
    R, t = Rt
    return (R2 @ R, R2 @ (t - c2) + c2)
newJ = {}
down = np.array([0, 0, -1.0])
for s in (-1, 1):
    S, E, Wr, T, Hp, K, A = J(s)
    n = side_name[s]
    R1 = rot_to(E - S, down)
    M["sh" + n] = compose(R1, S, (np.eye(3), np.zeros(3)))
    E2 = M["sh" + n][0] @ E + M["sh" + n][1]
    W2 = M["sh" + n][0] @ Wr + M["sh" + n][1]
    R2 = rot_to(W2 - E2, down)
    M["el" + n] = compose(R2, E2, M["sh" + n])
    M["hand" + n] = M["el" + n]
    W3 = M["el" + n][0] @ Wr + M["el" + n][1]
    T3 = M["el" + n][0] @ T + M["el" + n][1]
    R3 = rot_to(K - Hp, down)
    M["leg" + n] = compose(R3, Hp, (np.eye(3), np.zeros(3)))
    K2 = M["leg" + n][0] @ K + M["leg" + n][1]
    A2 = M["leg" + n][0] @ A + M["leg" + n][1]
    R4 = rot_to(A2 - K2, down)
    M["knee" + n] = compose(R4, K2, M["leg" + n])
    newJ.update({"sh" + n: S, "el" + n: E2, "hand" + n: W3, "tip" + n: T3, "leg" + n: Hp, "knee" + n: K2,
                 "ankle" + n: M["knee" + n][0] @ A + M["knee" + n][1]})
P2 = np.zeros_like(P)
for n in names:
    R, t = M[n]
    P2 += Wt[:, idx[n]][:, None] * (P @ R.T + t)
newJ.update({"hips": np.array([0, 0, 0.95]), "torso": np.array([0, 0, 1.03]), "head": np.array([0, -0.005, 1.64]),
             "hair1": np.array([0, 0.085, 1.68]), "hair2": np.array([0, 0.12, 1.5])})

# --- face +y (Godot -z): rotate 180 degrees about z
flip = np.array([-1.0, -1.0, 1.0])
P2 *= flip
for k in newJ:
    newJ[k] = newJ[k] * flip
me.vertices.foreach_set("co", P2.reshape(-1).astype(np.float32))
me.update()

# --- leather sandals, built as separate pieces fitted to each foot (final pose, front is +y):
# a 1 cm sole traced from the footprint, and leather bands cut from slices of the foot's shape
# (across the forefoot, over the instep, round the ankle, behind the heel). Skinned to the shin.
def add_sandals():
    global Wt, N
    import bmesh
    def ConvexHull(pts):
        class H: pass
        P_ = np.asarray(pts); order = np.lexsort((P_[:, 1], P_[:, 0]))
        def cross(o, a, b): return (P_[a][0] - P_[o][0]) * (P_[b][1] - P_[o][1]) - (P_[a][1] - P_[o][1]) * (P_[b][0] - P_[o][0])
        lower, upper = [], []
        for i in order:
            while len(lower) >= 2 and cross(lower[-2], lower[-1], i) <= 0: lower.pop()
            lower.append(i)
        for i in order[::-1]:
            while len(upper) >= 2 and cross(upper[-2], upper[-1], i) <= 0: upper.pop()
            upper.append(i)
        h = H(); h.vertices = np.array(lower[:-1] + upper[:-1]); return h
    Q = P2
    bm = bmesh.new(); bm.from_mesh(me)
    if len(me.materials) < 2:
        m = bpy.data.materials.new("Sandal"); m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (0.075, 0.04, 0.02, 1)
        bsdf.inputs["Roughness"].default_value = 0.65
        me.materials.append(m)
    new_w = []
    def emit(rings, closed, bone):
        """rings: list of point loops (same length); faces between consecutive rings."""
        vs = [[bm.verts.new(tuple(p)) for p in r] for r in rings]
        n = len(rings[0])
        for a, b in zip(vs[:-1], vs[1:]):
            for k in range(n if closed else n - 1):
                k2 = (k + 1) % n
                try:
                    f = bm.faces.new([a[k], a[k2], b[k2], b[k]]); f.material_index = 1; f.smooth = True
                except ValueError:
                    pass
        row = np.zeros(len(names)); row[idx[bone]] = 1.0
        new_w.extend([row] * (len(rings) * n))
        return vs
    def resample(loop, n, closed=True):
        pts = np.vstack([loop, loop[:1]]) if closed else loop
        d = np.r_[0, np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))]
        t = np.linspace(0, d[-1], n + (0 if closed else 0), endpoint=not closed)
        return np.stack([np.interp(t, d, pts[:, c]) for c in range(pts.shape[1])], 1)
    for s_ in (1, -1):
        bone = "knee_r" if s_ > 0 else "knee_l"      # after the flip the right foot is at +x
        fm = (Q[:, 2] < 0.13) & (s_ * Q[:, 0] > 0.02)
        F = Q[fm]
        toe_y, heel_y = F[:, 1].max(), F[:, 1].min()
        L = toe_y - heel_y
        # sole: footprint hull, pushed out 7 mm, 1.1 cm thick
        low = F[F[:, 2] < 0.035][:, :2]
        hull = low[ConvexHull(low).vertices]
        c = hull.mean(0)
        ring = resample(hull, 48)
        ring = ring + (ring - c) / np.linalg.norm(ring - c, axis=1)[:, None] * 0.007
        top = np.c_[ring, np.full(len(ring), 0.007)]
        bot = np.c_[ring, np.full(len(ring), -0.004)]
        emit([bot, top], True, bone)
        # cap the sole (top and bottom fans)
        for z0, flip_ in ((0.007, False), (-0.004, True)):
            cv = bm.verts.new((c[0], c[1], z0)); new_w.append(np.eye(len(names))[idx[bone]])
            rv = [bm.verts.new((p[0], p[1], z0)) for p in ring]; new_w.extend([np.eye(len(names))[idx[bone]]] * len(rv))
            for k in range(len(rv)):
                vv = [cv, rv[k], rv[(k + 1) % len(rv)]]
                if flip_:
                    vv.reverse()
                try:
                    f = bm.faces.new(vv); f.material_index = 1
                except ValueError:
                    pass
        # a band: around a centre in a slicing plane, the foot's outer radius at each angle (smoothed),
        # pushed out a few mm, swept across the strap's width with some thickness
        def band(axis, val, width, center, a0, a1, closed, nseg=40):
            near = F[np.abs(F[:, axis] - val) < 0.008]
            other = [a for a in (0, 1, 2) if a != axis]
            uv2 = near[:, other] - center
            ang = np.arctan2(uv2[:, 1], uv2[:, 0]); rad = np.linalg.norm(uv2, axis=1)
            angs = np.linspace(a0, a1, nseg, endpoint=not closed)
            rr = np.full(nseg, np.nan)
            for k, a in enumerate(angs):
                d = np.abs((ang - a + np.pi) % (2 * np.pi) - np.pi)
                m = d < (a1 - a0) / nseg * 1.2
                if m.any():
                    rr[k] = rad[m].max()
            ok = ~np.isnan(rr)
            if ok.sum() < 4:
                return
            rr = np.interp(np.arange(nseg), np.arange(nseg)[ok], rr[ok])
            for _ in range(3):
                rr = np.convolve(np.r_[rr[-1:] if closed else rr[:1], rr, rr[:1] if closed else rr[-1:]], [0.25, 0.5, 0.25], "valid")
            rings = []
            for dv, ex in ((-width / 2, 0.0), (-width / 2, 0.0035), (width / 2, 0.0035), (width / 2, 0.0), (-width / 2, 0.0)):
                q = np.zeros((nseg, 3))
                r2 = rr + 0.003 + ex
                q[:, other[0]] = center[0] + np.cos(angs) * r2
                q[:, other[1]] = center[1] + np.sin(angs) * r2
                q[:, axis] = val + dv
                rings.append(q)
            emit(rings, closed, bone)
        for tt in (0.66, 0.44):
            yv = heel_y + tt * L
            sl = F[np.abs(F[:, 1] - yv) < 0.008]
            band(1, yv, 0.024, np.array([sl[:, 0].mean(), 0.006]), 0.0, np.pi, False)   # over the foot, sole to sole
        ak = F[np.abs(F[:, 2] - 0.085) < 0.008]
        band(2, 0.085, 0.02, ak[:, :2].mean(0), -np.pi, np.pi, True, 48)                 # round the ankle
    bm.to_mesh(me); bm.free(); me.update()
    Wt = np.vstack([Wt, np.array(new_w)])
    N = len(me.vertices)
    print("sandal verts", len(new_w))
add_sandals()

# --- armature
parents = {"hips": None, "torso": "hips", "head": "torso", "sh_r": "torso", "el_r": "sh_r", "hand_r": "el_r",
           "sh_l": "torso", "el_l": "sh_l", "hand_l": "el_l", "leg_r": "hips", "knee_r": "leg_r", "leg_l": "hips", "knee_l": "leg_l",
           "hair1": "head", "hair2": "hair1"}
tails = {"hips": newJ["torso"], "torso": newJ["head"], "head": newJ["head"] + [0, 0, 0.2], "hair1": newJ["hair2"],
         "hair2": newJ["hair2"] + [0, 0.02, -0.14]}
for n in ("_r", "_l"):
    tails["sh" + n] = newJ["el" + n]; tails["el" + n] = newJ["hand" + n]; tails["hand" + n] = newJ["tip" + n]
    tails["leg" + n] = newJ["knee" + n]; tails["knee" + n] = newJ["ankle" + n]
arm = bpy.data.armatures.new("KnightRig")
rig = bpy.data.objects.new("Knight_Rig", arm)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for n in names:
    b = arm.edit_bones.new(n)
    b.head = Vector(newJ[n]); b.tail = Vector(tails[n])
for n in names:
    if parents[n]:
        arm.edit_bones[n].parent = arm.edit_bones[parents[n]]
bpy.ops.object.mode_set(mode="OBJECT")
top = np.argsort(-Wt, axis=1)[:, :4]
body.vertex_groups.clear()
for j, n in enumerate(names):
    vg = body.vertex_groups.new(name=n)
    rows = np.where((top == j).any(1) & (Wt[:, j] > 0.003))[0]
    for r in rows:
        vg.add([int(r)], float(Wt[r, j]), "REPLACE")
body.parent = rig
mod = body.modifiers.new("Armature", "ARMATURE"); mod.object = rig
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True); body.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_skins=True,
                          export_animations=False, export_image_format="JPEG", export_jpeg_quality=88)
lay = {n: [round(float(v[0]), 4), round(float(v[2]), 4), round(float(-v[1]), 4)] for n, v in newJ.items() if n in names}
json.dump({"layout": lay, "parents": parents}, open(LAYOUT, "w"), indent=1)
print("EXPORTED", OUT)
print(json.dumps(lay))
