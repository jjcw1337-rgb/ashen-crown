# Builds the knight's mocap model: the Meshy auto-rigged crusader (24-bone humanoid: spine x3, neck,
# clavicles, wrists, feet, toes) with the Meshy library clips merged onto its one armature, the mesh
# decimated to a game budget, exported as one glb whose AnimationPlayer holds every clip by a clean name.
#   blender -b --python prep_knight_mocap.py -- <rigged.glb> <out.glb> <tris> <clips.glb> [<clips.glb> ...]
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
RIG, OUT, TRIS, CLIPS = a[0], a[1], int(a[2]), a[3:]
NAMES = {"Idle": "idle", "Combat_Stance": "combat_idle", "Casual_Walk": "walk", "Walk_Fight_Forward": "walk_fight",
         "Run_02": "run", "RunFast": "run_fast", "Lean_Forward_Sprint_inplace": "sprint",
         "Walk_Backward_with_Sword_Shield": "walk_back", "ForwardLeft_Run_Fight": "run_fwd_left",
         "ForwardRight_Run_Fight": "run_fwd_right", "Hit_Reaction": "hit", "dying_backwards": "death", "Roll_Dodge": "roll"}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=RIG)
arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
body = [o for o in bpy.context.scene.objects if o.type == "MESH" and len(o.data.polygons) > 1000][0]
for o in list(bpy.context.scene.objects):
    if o.type == "MESH" and o != body:
        bpy.data.objects.remove(o)
keep = set(bpy.data.actions)
for c in CLIPS:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=c)
    for o in set(bpy.data.objects) - before:
        bpy.data.objects.remove(o)
# drop the rig's own one-frame clip; name the library clips and stack them on the armature
for ac in list(bpy.data.actions):
    if ac in keep:
        bpy.data.actions.remove(ac)
arm.animation_data_create()
arm.animation_data.action = None
n = 0
for ac in list(bpy.data.actions):
    nm = NAMES.get(ac.name)
    if nm is None:
        bpy.data.actions.remove(ac)
        continue
    ac.name = nm
    ac.use_fake_user = True
    tr = arm.animation_data.nla_tracks.new()
    tr.name = nm
    tr.strips.new(nm, int(ac.frame_range[0]), ac)
    tr.mute = True
    n += 1
print("clips", n, sorted(a.name for a in bpy.data.actions))
# decimate under the armature modifier
bpy.context.view_layer.objects.active = body
cur = len(body.data.polygons)
if cur > TRIS:
    d = body.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
print("faces", len(body.data.polygons))
# --- the cloak and the scabbard hilt (same detection as rig_crusader_knight.py; the model stands in its
# A-pose here, front toward -y, feet on z = 0, 1.8 m). Meshy's auto-weights tie the cloak to the legs, so
# it stretches with every stride: it moves instead to three panels of three bones (hA right, hB middle,
# hC left) hung from the chest, which the game swings like cloth. The hilt above the scabbard gets its
# own material, "Hilt", so the game can hide it while the sword is in his hand.
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree
me = body.data
N = len(me.vertices)
P = np.array([body.matrix_world @ v.co for v in me.vertices])
x, y, z = P[:, 0], P[:, 1], P[:, 2]
def sm(v, a_, b_):
    t = np.clip((v - a_) / (b_ - a_), 0, 1); return t * t * (3 - 2 * t)
def near_seg(a_, b_, r):
    a_ = np.asarray(a_, float); ab = np.asarray(b_, float) - a_
    t = np.clip(((P - a_) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(P - (a_ + t[:, None] * ab), axis=1) < r
def near_xz(a_, b_, r):
    a_ = np.asarray(a_, float); ab = np.asarray(b_, float) - a_; Q = P[:, [0, 2]]
    t = np.clip(((Q - a_) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(Q - (a_ + t[:, None] * ab), axis=1) < r
# metallic per vertex (cloth isn't metal)
mat = body.active_material
bsdf = [nd for nd in mat.node_tree.nodes if nd.type == "BSDF_PRINCIPLED"][0]
def tex_for(sock):
    l = sock.links
    while l:
        nd = l[0].from_node
        if nd.type == "TEX_IMAGE":
            return nd.image
        ins = [i for i in nd.inputs if i.links]
        if not ins:
            return None
        l = ins[0].links
    return None
uv = np.empty(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
lv = np.empty(len(me.loops), dtype=np.int64); me.loops.foreach_get("vertex_index", lv)
mimg = tex_for(bsdf.inputs["Metallic"])
metal = np.ones(N)
if mimg:
    W_, H_ = mimg.size
    pix = np.array(mimg.pixels[:], dtype=np.float32).reshape(H_, W_, 4)
    px = np.clip((uv[:, 0] % 1.0) * W_, 0, W_ - 1).astype(int); py = np.clip((uv[:, 1] % 1.0) * H_, 0, H_ - 1).astype(int)
    v_ = np.zeros(N); c_ = np.zeros(N)
    np.add.at(v_, lv, pix[py, px, 2]); np.add.at(c_, lv, 1)
    metal = v_ / np.maximum(c_, 1)
soft = metal < 0.35
arm_m = np.zeros(N, bool)
legs = np.zeros(N, bool)
for s_ in (-1, 1):
    arm_m |= near_seg((s_ * 0.24, -0.03, 1.43), (s_ * 0.355, -0.065, 1.215), 0.15)
    arm_m |= near_seg((s_ * 0.355, -0.065, 1.215), (s_ * 0.475, -0.15, 1.0), 0.14)
    arm_m |= near_seg((s_ * 0.475, -0.15, 1.0), (s_ * 0.6, -0.22, 0.74), 0.13)
    legs |= near_seg((s_ * 0.1, -0.02, 0.92), (s_ * 0.13, -0.04, 0.52), 0.1)
    legs |= near_seg((s_ * 0.13, -0.04, 0.52), (s_ * 0.145, 0.0, 0.08), 0.085)
cape_zone = ~arm_m & (z < 1.5) & (z > 0.12) & ((y > 0.1) | ((np.abs(x) > 0.24) & (y > 0.0) & (z < 1.0)))
kd = KDTree(N)
for i, p_ in enumerate(P):
    kd.insert(p_, i)
kd.balance()
cape = soft & cape_zone
for _ in range(4):
    add = set()
    for i in np.where(cape)[0]:
        for _, j, _ in kd.find_range(P[i], 0.014):
            if not cape[j] and cape_zone[j]:
                add.add(j)
    if not add:
        break
    cape[list(add)] = True
cape |= cape_zone & ~legs & (z < 1.0)
print("cloak verts", int(cape.sum()), "of", N)
# the cloak's bones: three panels, joints at three heights, hung from the upper spine
CAPE = [("hA", -0.2), ("hB", 0.0), ("hC", 0.2)]
CZ = [1.42, 1.02, 0.62, 0.22]
memb = np.stack([np.exp(-((x - cx) / 0.16) ** 2) for _, cx in CAPE], 1)
memb /= np.maximum(memb.sum(1, keepdims=True), 1e-9)
joints = {}
for ci, (c, cx) in enumerate(CAPE):
    sel = cape & (memb[:, ci] > 0.5)
    pts = []
    for zz in CZ:
        band = sel & (np.abs(z - zz) < 0.03)
        pts.append(P[band].mean(0) if band.sum() > 5 else np.array([cx, 0.16, zz]))
    joints[c] = pts
inv = arm.matrix_world.inverted()
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
for c, _ in CAPE:
    par = eb["Spine02"]
    for k in range(3):
        b = eb.new(f"{c}{k + 1}")
        b.head = inv @ Vector(joints[c][k]); b.tail = inv @ Vector(joints[c][k + 1])
        b.parent = par
        par = b
bpy.ops.object.mode_set(mode="OBJECT")
def seg_w(zz, top, bot, blend=0.05):
    return sm(zz, bot - blend, bot + blend) * (1 - sm(zz, top - blend, top + blend))
bands = [(9.0, CZ[0])] + [(CZ[k], CZ[k + 1] if k + 1 < 3 else -9.0) for k in range(3)]
hw = np.stack([seg_w(z, t_, b_) for t_, b_ in bands], 1)
hw /= np.maximum(hw.sum(1, keepdims=True), 1e-9)
ci_ = np.where(cape)[0].tolist()
for vg in body.vertex_groups:
    vg.remove(ci_)
groups = {vg.name: vg for vg in body.vertex_groups}
def grp(nm):
    return groups[nm] if nm in groups else body.vertex_groups.new(name=nm)
top = grp("Spine02")
for i in ci_:
    if hw[i, 0] > 0.003:
        top.add([i], float(hw[i, 0]), "REPLACE")
for ci, (c, _) in enumerate(CAPE):
    for k in range(3):
        g_ = grp(f"{c}{k + 1}")
        for i in ci_:
            w_ = float(hw[i, k + 1] * memb[i, ci])
            if w_ > 0.003:
                g_.add([i], w_, "REPLACE")
# the hilt standing out of the scabbard on his left hip
sword = (near_xz((0.16, 1.24), (0.22, 1.02), 0.06) | near_xz((0.22, 1.02), (0.44, 0.22), 0.045)) & (y < 0.08) & ~cape
sword &= (x > 0.12) & ~((z > 0.85) & (np.abs(y + 0.02) < 0.13) & (x < 0.2)) & ~near_seg((0.475, -0.15, 1.0), (0.56, -0.2, 0.8), 0.06)
hilt = sword & (z > 1.0)
hm = mat.copy(); hm.name = "Hilt"
me.materials.append(hm)
hidx = len(me.materials) - 1
nh = 0
for poly in me.polygons:
    if all(hilt[v] for v in poly.vertices):
        poly.material_index = hidx; nh += 1
print("hilt faces", nh)
for img in bpy.data.images:
    if img.size[0] > 2048:
        img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_image_format="JPEG", export_jpeg_quality=88)
print("EXPORTED", OUT)
