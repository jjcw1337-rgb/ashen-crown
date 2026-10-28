# Rigs a Meshy monster (A-pose humanoid) on the game's joints and exports a small skinned glb.
#   blender -b --python rig_monster.py -- <in.glb> <out.glb> <layout.json> [texture px, default 1024] [hints json]
# hints override what the measuring gets wrong (a hood or mantle hides the neck): {"sh_z": metres to the
# top of the shoulders, "sh_x": the shoulder joint's distance from the middle}.
# The input is the decimated Meshy model (feet on z = 0; Meshy faces -y, so it is turned to face +y,
# which is Godot's -z). Joints are measured from the mesh: the crotch is the lowest height where the
# legs part, each arm's centre line is traced out to the fingertips, the legs are sliced for knees and
# ankles. Weights are by distance to each bone segment (left and right kept apart), the head is rigid
# and the feet ride the shins. The model stays in its A-pose; Goblin.imported_rig's aim turns each
# arm's rest down the limb, like the gnome Warlock. layout.json gets the joints in Godot axes for
# MeshyMonster.MODELS (python3 tools/blender/act1/layout_to_gd.py <kind> layout.json).
import bpy, sys, json
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, LAYOUT = argv[0], argv[1], argv[2]
TEX = int(argv[3]) if len(argv) > 3 else 1024
HINTS = json.loads(argv[4]) if len(argv) > 4 else {}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
body = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
for o in list(bpy.context.scene.objects):
    if o != body:
        bpy.data.objects.remove(o, do_unlink=True)
bpy.context.view_layer.objects.active = body
body.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = body.data
N = len(me.vertices)
P = np.empty(N * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
P[:, 2] -= P[:, 2].min()
# face +y (Godot -z): the toes reach out in front of the ankles
Hh = P[:, 2].max()
toes = P[P[:, 2] < 0.025 * Hh, 1].mean()
ankles = P[np.abs(P[:, 2] - 0.09 * Hh) < 0.015 * Hh, 1].mean()
if toes < ankles:
    P[:, :2] *= -1.0
print("turned to face +y" if toes < ankles else "already faces +y")
P[:, 0] -= np.median(P[:, 0])
x, y, z = P.T
H = z.max()

def sm(v, a, b):
    t = np.clip((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

# --- crotch: scanning up from the knees, the first height where nothing crosses the middle
crotch = 0.3 * H
for zz in np.arange(0.2 * H, 0.7 * H, 0.005 * H):
    band = np.abs(z - zz) < 0.004 * H
    mid = band & (np.abs(x) < 0.025 * H)
    if mid.sum() > 3:
        crotch = zz
        break
hip_z = crotch + 0.035 * H
# --- arms: fingertips are the outermost points; the arm's centre line from slices across x
xmax = np.abs(x).max()
# shoulders: the neck is the narrowest point under the head; the shoulders are the first height below it where the body is much wider
def width(zz, q=95):
    band = np.abs(z - zz) < 0.006 * H
    return np.percentile(np.abs(x[band]), q) if band.sum() > 10 else 0.0
zs = np.arange(0.92 * H, 0.6 * H, -0.005 * H)
neck_z = zs[int(np.argmin([width(zz) or 9.0 for zz in zs]))]
neck_w = max(width(neck_z), 0.02 * H)
sh_top = neck_z - 0.04 * H
for zz in np.arange(neck_z, 0.45 * H, -0.005 * H):
    if width(zz) > 1.8 * neck_w:
        sh_top = zz
        break
head_w = neck_w
sh_top = HINTS.get("sh_z", sh_top)
torso_w = np.percentile(np.abs(x[np.abs(z - (sh_top - 0.03 * H)) < 0.006 * H]), 85)
print("head_w %.3f shoulder top %.3f torso_w %.3f" % (head_w, sh_top, torso_w))
J = {}
for s, sn in ((1, "_r"), (-1, "_l")):         # facing +y, his right is +x... (Godot x stays x)
    side = s * x > 0
    tipm = side & (s * x > 0.93 * xmax)
    T = P[tipm].mean(0) if tipm.sum() > 3 else np.array([s * xmax, 0, 0.5 * H])
    pts = []
    for f in np.linspace(0.45, 0.9, 10):
        sl = side & (np.abs(s * x - f * xmax) < 0.012 * H) & (z > crotch)
        if sl.sum() < 5:
            continue
        # keep the cluster nearest the line toward the fingertips (not the hanging cloth)
        zc = np.median(z[sl])
        sel = sl & (np.abs(z - zc) < 0.08 * H)
        pts.append(P[sel].mean(0))
    pts = np.array(pts) if len(pts) >= 2 else np.array([T * 0.6, T])
    # shoulder: just under the top of the shoulders, a little in from the body's edge there
    S = np.array([s * HINTS.get("sh_x", torso_w * 0.8), 0.0, sh_top - 0.05 * H])
    S[1] = np.median(y[(np.abs(x - S[0]) < 0.03 * H) & (np.abs(z - S[2]) < 0.05 * H)]) if ((np.abs(x - S[0]) < 0.03 * H) & (np.abs(z - S[2]) < 0.05 * H)).sum() > 3 else S[1]
    L = np.linalg.norm(T - S)
    W = S + (T - S) * 0.78
    E = S + (W - S) * 0.52
    J["sh" + sn], J["el" + sn], J["hand" + sn], J["tip" + sn] = S, E, W, T
    # legs: slices below the crotch on this side
    def leg_at(zz):
        sl = side & (np.abs(z - zz) < 0.01 * H) & (s * x < torso_w * 1.4)
        return P[sl].mean(0) if sl.sum() > 3 else np.array([s * 0.1 * H, 0.0, zz])
    Hp = leg_at(crotch - 0.02 * H); Hp[2] = hip_z; Hp[0] = s * max(abs(Hp[0]) * 0.8, 0.05 * H)
    K = leg_at(hip_z * 0.53)
    A = leg_at(hip_z * 0.12)
    J["leg" + sn], J["knee" + sn], J["ankle" + sn] = Hp, K, A
sh_z = 0.5 * (J["sh_r"][2] + J["sh_l"][2])
J["hips"] = np.array([0.0, np.median(y[np.abs(z - hip_z) < 0.02 * H]), hip_z])
J["torso"] = J["hips"] + np.array([0, 0, 0.06 * H])
neck = (np.abs(x) < 0.06 * H) & (z > sh_z) & (z < sh_z + 0.08 * H)
J["head"] = np.array([0.0, np.median(y[neck]) if neck.sum() > 3 else 0.0, sh_top + 0.04 * H])
print("H %.2f crotch %.2f hips %.2f shoulders %.2f" % (H, crotch, hip_z, sh_z))
for k, v in J.items():
    print(k, np.round(v, 3))

names = ["hips", "torso", "head", "sh_r", "el_r", "hand_r", "sh_l", "el_l", "hand_l", "leg_r", "knee_r", "leg_l", "knee_l"]
seg = {"hips": (J["hips"], J["torso"]), "torso": (J["torso"], np.array([0, J["head"][1], sh_z])),
       "head": (J["head"], J["head"] + [0, 0, 0.12 * H])}
for sn in ("_r", "_l"):
    seg["sh" + sn] = (J["sh" + sn], J["el" + sn]); seg["el" + sn] = (J["el" + sn], J["hand" + sn])
    seg["hand" + sn] = (J["hand" + sn], J["tip" + sn])
    seg["leg" + sn] = (J["leg" + sn], J["knee" + sn]); seg["knee" + sn] = (J["knee" + sn], J["ankle" + sn])
idx = {n: i for i, n in enumerate(names)}

def seg_dist(a, b):
    a = np.asarray(a, float); ab = np.asarray(b, float) - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)

Wt = np.zeros((N, len(names)))
for n, (a, b) in seg.items():
    Wt[:, idx[n]] = 1.0 / (seg_dist(a, b) + 0.015 * H) ** 6
for s, sn in ((1, "_r"), (-1, "_l")):
    other = s * x < -0.01 * H
    for b in ("sh", "el", "hand", "leg", "knee"):
        Wt[other, idx[b + sn]] = 0.0
# arms only move the arm, not the chest beside them
for s, sn in ((1, "_r"), (-1, "_l")):
    near = 1.0 - sm(s * x, abs(J["sh" + sn][0]) * 0.8, abs(J["sh" + sn][0]) * 1.15)
    moved = Wt[:, idx["sh" + sn]] * near
    Wt[:, idx["sh" + sn]] -= moved; Wt[:, idx["torso"]] += moved
# above the crotch the legs don't pull the belly or loincloth
for b in ("leg_r", "leg_l", "knee_r", "knee_l"):
    m = sm(z, crotch, hip_z + 0.03 * H)
    moved = Wt[:, idx[b]] * m
    Wt[:, idx[b]] -= moved; Wt[:, idx["hips"]] += moved
foot = z < J["ankle_r"][2] + 0.01 * H
for s, sn in ((1, "_r"), (-1, "_l")):
    m = foot & (s * x > 0)
    Wt[m] = 0; Wt[m, idx["knee" + sn]] = 1
Wt /= Wt.sum(1, keepdims=True)
head_m = sm(z, J["head"][2] + 0.02 * H, J["head"][2] + 0.05 * H) * (np.abs(x) < 0.2 * H)
Wt[:] *= (1 - head_m)[:, None]; Wt[:, idx["head"]] += head_m

me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32))
me.update()
# textures down to game size
for img in bpy.data.images:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)

parents = {"hips": None, "torso": "hips", "head": "torso", "sh_r": "torso", "el_r": "sh_r", "hand_r": "el_r",
           "sh_l": "torso", "el_l": "sh_l", "hand_l": "el_l", "leg_r": "hips", "knee_r": "leg_r", "leg_l": "hips", "knee_l": "leg_l"}
tails = {"hips": J["torso"], "torso": J["head"], "head": J["head"] + [0, 0, 0.12 * H]}
for sn in ("_r", "_l"):
    tails["sh" + sn] = J["el" + sn]; tails["el" + sn] = J["hand" + sn]; tails["hand" + sn] = J["tip" + sn]
    tails["leg" + sn] = J["knee" + sn]; tails["knee" + sn] = J["ankle" + sn]
arm = bpy.data.armatures.new("MonsterRig")
rig = bpy.data.objects.new("Monster_Rig", arm)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for n in names:
    b = arm.edit_bones.new(n)
    b.head = Vector(J[n]); b.tail = Vector(tails[n])
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
                          export_animations=False, export_image_format="JPEG", export_jpeg_quality=85)
lay = {n: [round(float(J[n][0]), 4), round(float(J[n][2]), 4), round(float(-J[n][1]), 4)] for n in names}
json.dump({"layout": lay, "parents": parents, "height": round(float(H), 3)}, open(LAYOUT, "w"), indent=1)
print("EXPORTED", OUT)
