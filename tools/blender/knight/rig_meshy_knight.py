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
