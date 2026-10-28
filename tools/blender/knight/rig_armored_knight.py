# Rigs the Meshy armoured knight (A-pose crusader: plate over mail, red tabard, short cape, long hair)
# for the game.
#   blender -b --python rig_armored_knight.py -- <in.glb> <out.glb> <layout.json>
# The input is the decimated Meshy model (~70k triangles, facing -y, feet on z = 0, 1.8 m tall).
# Like rig_meshy_knight.py: skin by distance to each bone segment, swing the arms down (a little out
# from the body, for the plate) and straighten the legs into the game's rest pose, turn him to face +y
# (Godot -z) and export a skinned glb; layout.json gets the joints in Godot axes for
# Knight.ARMORED_LAYOUT (python3 layout_to_gd.py layout.json armored).
# Fixed regions: the hair and face ride the head, the tabard rides the hips and torso (the legs never
# take it, so it doesn't tear), the feet ride the shins, and the cape hangs on three panels
# (hA right, hB middle, hC left) of three bones each, which knight_rig.gd swings like hair locks.
import bpy, sys, json
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

# --- per-vertex base colour (average of its loops' texels): finds the red cloth
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
x, y, z = P[:, 0], P[:, 1], P[:, 2]

def sm(v, a, b):
    t = np.clip((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

# (strict: the rust on the plate is reddish brown too)
red = (vc[:, 0] > vc[:, 1] * 1.9) & (vc[:, 0] > vc[:, 2] * 1.6) & (vc[:, 0] > 0.04)
# the cape hangs behind (and wraps the sides behind the arms); the tabard is the front panel
cape = red & (z < 1.5) & (z > 0.3) & ((y > 0.12) | ((y > 0.06) & (z > 0.9)) | ((np.abs(x) > 0.3) & (y > -0.12)))
tabard = red & ~cape & (z < 1.45) & (z > 0.3) & (np.abs(x) < np.where(z < 0.88, 0.13, 0.2)) & (y < -0.05)
# the frayed hems and pale tears aren't red enough: grow both regions into the vertices beside them
# (a few rings), the cape only behind the body and below the shoulders, the tabard only between the legs
from mathutils.kdtree import KDTree
kd = KDTree(N)
for i, p in enumerate(P):
    kd.insert(p, i)
kd.balance()
def grow(mask, allowed, rings=6, r=0.014):
    mask = mask.copy()
    for _ in range(rings):
        add = set()
        for i in np.where(mask)[0]:
            for _, j, _ in kd.find_range(P[i], r):
                if not mask[j] and allowed[j]:
                    add.add(j)
        if not add:
            break
        mask[list(add)] = True
    return mask
cape = grow(cape, (z < 1.45) & (z > 0.3) & ((y > 0.12) | ((np.abs(x) > 0.3) & (y > -0.05))))
tabard = grow(tabard, ~cape & (z < 1.2) & (z > 0.3) & (np.abs(x) < 0.11) & (y < -0.12), rings=3)
print("cape verts", cape.sum(), "tabard", tabard.sum(), "of", N)
# hair: the dark strands round the head (not the beard or the steel collar); the scalp stays on the
# head, the rest hangs on five locks (hD..hH) of three bones that knight_rig.gd swings
lum = vc @ np.array([0.2126, 0.7152, 0.0722])
around = (np.hypot(x, y + 0.02) < 0.2) | (z > 1.62)
dark = (lum < 0.13) & (z > 1.44) & around & ~cape
beard = dark & (y < -0.05) & (np.abs(x) < 0.09) & (z < 1.72)
hair = dark & ~beard
hair = grow(hair, (z > 1.44) & around & ~beard & ~cape & (lum < 0.22), rings=2, r=0.01)
print("hair verts", hair.sum(), "beard", beard.sum())

# --- joints (A-pose, front is -y; s = +1 is his left)
def J(s):
    S = np.array([s * 0.19, -0.03, 1.465]); E = np.array([s * 0.355, -0.065, 1.215])
    Wr = np.array([s * 0.475, -0.15, 1.0]); T = np.array([s * 0.55, -0.2, 0.855])
    Hp = np.array([s * 0.1, -0.03, 0.92]); K = np.array([s * 0.195, -0.06, 0.5]); A = np.array([s * 0.225, -0.035, 0.1])
    return S, E, Wr, T, Hp, K, A
side_name = {-1: "_r", 1: "_l"}
seg = {"hips": ((0, -0.02, 0.84), (0, -0.02, 1.05)), "torso": ((0, -0.02, 1.08), (0, -0.02, 1.5)),
       "head": ((0, -0.03, 1.6), (0, -0.03, 1.78))}
for s in (-1, 1):
    S, E, Wr, T, Hp, K, A = J(s)
    n = side_name[s]
    seg["sh" + n] = (S, E); seg["el" + n] = (E, Wr); seg["hand" + n] = (Wr, T)
    seg["leg" + n] = (Hp, K); seg["knee" + n] = (K, A)
# cape panels: x centre of each (right, middle, left) and the heights of each chain's joints
CAPE = [("hA", -0.2), ("hB", 0.0), ("hC", 0.2)]
CAPE_Z = [1.4, 1.08, 0.76]
cape_names = [f"{c}{k + 1}" for c, _ in CAPE for k in range(3)]
# hair locks: azimuth of each lock's centre round the head (0 = the face, A-pose front is -y)
HAIR_LOCKS = [("hD", 1.25), ("hE", 2.2), ("hF", np.pi), ("hG", -2.2), ("hH", -1.25)]
HAIR_Z = [1.68, 1.6, 1.52]
hair_names = [f"{c}{k + 1}" for c, _ in HAIR_LOCKS for k in range(3)]
cape_names += hair_names
names = ["hips", "torso", "head", "sh_r", "el_r", "hand_r", "sh_l", "el_l", "hand_l", "leg_r", "knee_r", "leg_l", "knee_l"] + cape_names
idx = {n: i for i, n in enumerate(names)}

def seg_dist(a, b):
    a = np.asarray(a, float); ab = np.asarray(b, float) - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)

Wt = np.zeros((N, len(names)))
for n, (a, b) in seg.items():
    Wt[:, idx[n]] = 1.0 / (seg_dist(a, b) + 0.025) ** 6
for s in (-1, 1):
    other = (s * x < -0.02)
    for b in ("sh", "el", "hand", "leg", "knee"):
        Wt[other, idx[b + side_name[s]]] = 0.0
# the pauldrons and chest plate near the body follow the torso, not the upper arm
for s in (-1, 1):
    near = (1.0 - sm(s * x, 0.2, 0.27)) * sm(z, 1.3, 1.4)
    moved = Wt[:, idx["sh" + side_name[s]]] * near
    Wt[:, idx["sh" + side_name[s]]] -= moved
    Wt[:, idx["torso"]] += moved
# above the belt the legs don't move anything (faulds and mail skirt ride the hips)
for leg in ("leg_r", "leg_l", "knee_r", "knee_l"):
    m = sm(z, 0.78, 0.9)
    moved = Wt[:, idx[leg]] * m
    Wt[:, idx[leg]] -= moved
    Wt[:, idx["hips"]] += moved
foot = z < 0.15
for s in (-1, 1):
    m = foot & (s * x > 0)
    Wt[m] = 0; Wt[m, idx["knee" + side_name[s]]] = 1
Wt /= Wt.sum(1, keepdims=True)

def take(mask_w, bone):
    Wt[:] *= (1 - mask_w)[:, None]; Wt[:, idx[bone]] += mask_w
take(sm(z, 1.56, 1.62) * (np.hypot(x, y + 0.02) < 0.2), "head")
# the tabard: hips below the belt, torso above
tb = tabard
Wt[tb] = 0.0
Wt[tb, idx["hips"]] = 1.0 - sm(z[tb], 1.0, 1.12)
Wt[tb, idx["torso"]] = sm(z[tb], 1.0, 1.12)
# the cape: the top band rides the torso, then down each panel's chain by height
cm = cape
memb = np.stack([np.exp(-((x - cx) / 0.16) ** 2) for _, cx in CAPE], 1)
memb /= np.maximum(memb.sum(1, keepdims=True), 1e-9)
def seg_w(zz, top, bot, blend=0.05):
    return sm(zz, bot - blend, bot + blend) * (1 - sm(zz, top - blend, top + blend))
bands = [(9.0, CAPE_Z[0])] + [(CAPE_Z[k], CAPE_Z[k + 1] if k + 1 < 3 else -9.0) for k in range(3)]
hw = np.stack([seg_w(z, t, b_) for t, b_ in bands], 1)
hw /= np.maximum(hw.sum(1, keepdims=True), 1e-9)
Wt[cm] = 0.0
Wt[cm, idx["torso"]] = hw[cm, 0]
for ci, (c, _) in enumerate(CAPE):
    for k in range(3):
        Wt[cm, idx[f"{c}{k + 1}"]] = hw[cm, k + 1] * memb[cm, ci]
Wt[cm] /= np.maximum(Wt[cm].sum(1, keepdims=True), 1e-9)
cape_joints = {}
for ci, (c, cx) in enumerate(CAPE):
    sel = cm & (memb[:, ci] > 0.5)
    pts = []
    for zz in CAPE_Z + [CAPE_Z[-1] - 0.3]:
        band = sel & (np.abs(z - zz) < 0.03)
        pts.append(P[band].mean(0) if band.sum() > 5 else np.array([cx, 0.16, zz]))
    cape_joints[c] = pts
hm = hair
az = np.arctan2(x, -(y + 0.02))
mem = np.stack([np.exp(-((((az - ac) + np.pi) % (2 * np.pi) - np.pi) / 0.45) ** 2) for _, ac in HAIR_LOCKS], 1)
mem /= np.maximum(mem.sum(1, keepdims=True), 1e-9)
hbands = [(9.0, HAIR_Z[0])] + [(HAIR_Z[k], HAIR_Z[k + 1] if k + 1 < 3 else -9.0) for k in range(3)]
hw2 = np.stack([seg_w(z, t, b_, 0.025) for t, b_ in hbands], 1)
hw2 /= np.maximum(hw2.sum(1, keepdims=True), 1e-9)
Wt[hm] = 0.0
Wt[hm, idx["head"]] = hw2[hm, 0]
for ci, (c, _) in enumerate(HAIR_LOCKS):
    for k in range(3):
        Wt[hm, idx[f"{c}{k + 1}"]] = hw2[hm, k + 1] * mem[hm, ci]
Wt[hm] /= np.maximum(Wt[hm].sum(1, keepdims=True), 1e-9)
hair_joints = {}
for ci, (c, ac) in enumerate(HAIR_LOCKS):
    sel = hm & (mem[:, ci] > 0.5)
    pts = []
    for zz in HAIR_Z + [HAIR_Z[-1] - 0.08]:
        band = sel & (np.abs(z - zz) < 0.02)
        if band.sum() > 5:
            pts.append(P[band].mean(0))
        else:
            d = np.array([np.sin(ac), -np.cos(ac), 0.0])
            pts.append(np.array([0, -0.02, zz]) + d * 0.11)
    hair_joints[c] = pts
print("hair locks", {c: int((hm & (mem[:, i] > 0.5)).sum()) for i, (c, _) in enumerate(HAIR_LOCKS)})
print("cape panels", {c: int((cm & (memb[:, i] > 0.5)).sum()) for i, (c, _) in enumerate(CAPE)})

# soften every seam below the chest where neighbours ride different bones (tabard and mail skirt
# against the thighs, the cape's hem against the legs): average the weights over a few cm, a few
# times, so the cloth stretches a little instead of tearing when the legs swing
top0 = np.argmax(Wt, 1)
seam = np.zeros(N, bool)
for i in np.where(z < 1.2)[0]:
    for _, j, _ in kd.find_range(P[i], 0.03):
        if top0[j] != top0[i]:
            seam[i] = True
            break
sidx = np.where(seam)[0]
nbrs = [[j for _, j, _ in kd.find_range(P[i], 0.025)] for i in sidx]
for _ in range(3):
    Wn = Wt.copy()
    for k, i in enumerate(sidx):
        Wn[i] = Wt[nbrs[k]].mean(0)
    Wt = Wn
print("softened seam verts", len(sidx))

# --- repose: arms down (a little out from the plate), legs straight
def rot_to(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); c = a @ b
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))
M = {n: (np.eye(3), np.zeros(3)) for n in names}
def compose(R2, c2, Rt):
    R, t = Rt
    return (R2 @ R, R2 @ (t - c2) + c2)
newJ = {}
down = np.array([0, 0, -1.0])
for s in (-1, 1):
    S, E, Wr, T, Hp, K, A = J(s)
    n = side_name[s]
    arm_down = np.array([s * 0.07, 0.0, -1.0])
    R1 = rot_to(E - S, arm_down)
    M["sh" + n] = compose(R1, S, (np.eye(3), np.zeros(3)))
    E2 = M["sh" + n][0] @ E + M["sh" + n][1]
    W2 = M["sh" + n][0] @ Wr + M["sh" + n][1]
    R2 = rot_to(W2 - E2, np.array([s * 0.03, -0.14, -1.0]))
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
newJ.update({"hips": np.array([0, -0.02, 0.92]), "torso": np.array([0, -0.02, 1.02]), "head": np.array([0, -0.03, 1.6])})
for c, pts in list(cape_joints.items()) + list(hair_joints.items()):
    for k in range(3):
        newJ[f"{c}{k + 1}"] = pts[k]
    newJ[f"{c}tail"] = pts[3]

# --- face +y (Godot -z)
flip = np.array([-1.0, -1.0, 1.0])
P2 *= flip
for k in newJ:
    newJ[k] = newJ[k] * flip
me.vertices.foreach_set("co", P2.reshape(-1).astype(np.float32))
me.update()

# --- armature
parents = {"hips": None, "torso": "hips", "head": "torso", "sh_r": "torso", "el_r": "sh_r", "hand_r": "el_r",
           "sh_l": "torso", "el_l": "sh_l", "hand_l": "el_l", "leg_r": "hips", "knee_r": "leg_r", "leg_l": "hips", "knee_l": "leg_l"}
tails = {"hips": newJ["torso"], "torso": newJ["head"], "head": newJ["head"] + [0, 0, 0.2]}
for c, _ in HAIR_LOCKS:
    parents[f"{c}1"] = "head"; parents[f"{c}2"] = f"{c}1"; parents[f"{c}3"] = f"{c}2"
    tails[f"{c}1"] = newJ[f"{c}2"]; tails[f"{c}2"] = newJ[f"{c}3"]; tails[f"{c}3"] = newJ[f"{c}tail"]
for c, _ in CAPE:
    parents[f"{c}1"] = "torso"; parents[f"{c}2"] = f"{c}1"; parents[f"{c}3"] = f"{c}2"
    tails[f"{c}1"] = newJ[f"{c}2"]; tails[f"{c}2"] = newJ[f"{c}3"]; tails[f"{c}3"] = newJ[f"{c}tail"]
for n in ("_r", "_l"):
    tails["sh" + n] = newJ["el" + n]; tails["el" + n] = newJ["hand" + n]; tails["hand" + n] = newJ["tip" + n]
    tails["leg" + n] = newJ["knee" + n]; tails["knee" + n] = newJ["ankle" + n]
arm = bpy.data.armatures.new("KnightArmoredRig")
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
