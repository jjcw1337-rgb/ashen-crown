# Rigs the Meshy crusader (A-pose: great helm, spiked plate over mail, dark surcoat with a faded red
# cross, sword on the left hip, long tattered cloak) as the knight's armoured body.
#   blender -b --python rig_crusader_knight.py -- <in.glb> <out.glb> <layout.json>
# The input comes from prep_crusader.py (~70k triangles, front toward -y, feet on z = 0, 1.8 m tall).
# Same method as rig_armored_knight.py (skin by distance to each bone segment, arms swung down, legs
# straightened, turned to face +y = Godot -z), with this model's regions: the helm rides the head,
# the surcoat's front panel rides the hips and torso, the sword and scabbard ride the hips, the feet
# ride the shins, and the cloak hangs on three panels (hA right, hB middle, hC left) of three bones each,
# which knight_rig.gd swings. Cloth is found by the metallic map (cloth isn't metal) and where it hangs.
# Then python3 layout_to_gd.py layout.json armored.
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

# --- per-vertex metallic (the glTF metallic-roughness map, blue channel): cloth and leather aren't metal
def tex_for(socket):
    l = socket.links
    while l:
        n = l[0].from_node
        if n.type == "TEX_IMAGE":
            return n.image
        ins = [i for i in n.inputs if i.links]
        if not ins:
            return None
        l = ins[0].links
    return None
bsdf = [n for n in body.active_material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"][0]
uv = np.empty(len(me.loops) * 2); me.uv_layers.active.data.foreach_get("uv", uv); uv = uv.reshape(-1, 2)
lv = np.empty(len(me.loops), dtype=np.int64); me.loops.foreach_get("vertex_index", lv)
def per_vertex(img, ch):
    W_, H_ = img.size
    pix = np.array(img.pixels[:], dtype=np.float32).reshape(H_, W_, 4)
    px = np.clip((uv[:, 0] % 1.0) * W_, 0, W_ - 1).astype(int)
    py = np.clip((uv[:, 1] % 1.0) * H_, 0, H_ - 1).astype(int)
    v = np.zeros(N); c = np.zeros(N)
    np.add.at(v, lv, pix[py, px, ch]); np.add.at(c, lv, 1)
    return v / np.maximum(c, 1)
mimg = tex_for(bsdf.inputs["Metallic"])
metal = per_vertex(mimg, 2) if mimg else np.ones(N)
print("metallic map", mimg.name if mimg else None, "mean", metal.mean().round(3))
x, y, z = P[:, 0], P[:, 1], P[:, 2]

def sm(v, a, b):
    t = np.clip((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

soft = metal < 0.35
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
# the arms (A-pose: shoulder, elbow, wrist, fingertips) never take cloak weights, spikes and all
def near_seg(a, b, r):
    a = np.asarray(a, float); ab = np.asarray(b, float) - a
    t = np.clip(((P - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1) < r
arm = np.zeros(N, bool)
for s_ in (-1, 1):
    arm |= near_seg((s_ * 0.24, -0.03, 1.43), (s_ * 0.355, -0.065, 1.215), 0.15)
    arm |= near_seg((s_ * 0.355, -0.065, 1.215), (s_ * 0.475, -0.15, 1.0), 0.14)
    arm |= near_seg((s_ * 0.475, -0.15, 1.0), (s_ * 0.6, -0.22, 0.74), 0.13)    # past the fingertips
# the cloak hangs behind from the shoulders and wraps the sides behind the arms
cape_zone = ~arm & (z < 1.5) & (z > 0.12) & ((y > 0.1) | ((np.abs(x) > 0.24) & (y > 0.0) & (z < 1.0)))
cape = grow(soft & cape_zone, cape_zone, rings=4)
# everything hanging behind or beside the legs that isn't the leg itself is cloak, cloth or not (its hem,
# the metal-flecked edges): it must never take leg weights, or it stretches into a web when he runs
legs = np.zeros(N, bool)
for s_ in (-1, 1):
    legs |= near_seg((s_ * 0.1, -0.02, 0.92), (s_ * 0.13, -0.04, 0.52), 0.1)
    legs |= near_seg((s_ * 0.13, -0.04, 0.52), (s_ * 0.145, 0.0, 0.08), 0.085)
cape |= cape_zone & ~legs & (z < 1.0)
# the surcoat's front panel below the belt, between the legs
tab_zone = ~cape & (z < 1.0) & (z > 0.2) & (np.abs(x) < 0.12) & (y < -0.08)
tabard = grow(soft & tab_zone, tab_zone, rings=3)
# the sword and scabbard on his left hip (+x), in front of the cloak, clear of the hand
# (pommel and crossguard near the hip, the blade angling out and down past the knee; measured on the grid renders)
def near_xz(a, b, r):
    a = np.asarray(a, float); ab = np.asarray(b, float) - a; Q = P[:, [0, 2]]
    t = np.clip(((Q - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(Q - (a + t[:, None] * ab), axis=1) < r
sword = (near_xz((0.16, 1.24), (0.22, 1.02), 0.06) | near_xz((0.22, 1.02), (0.44, 0.22), 0.045)) & (y < 0.08) & ~cape
sword &= (x > 0.12) & ~((z > 0.85) & (np.abs(y + 0.02) < 0.13) & (x < 0.2))   # not the belly
sword &= ~near_seg((0.475, -0.15, 1.0), (0.56, -0.2, 0.8), 0.06)     # not the gauntlet beside it
print("cape verts", cape.sum(), "tabard", tabard.sum(), "sword", sword.sum(), "of", N)
hair = np.zeros(N, bool)

# --- joints (A-pose, front is -y; s = +1 is his left)
def J(s):
    S = np.array([s * 0.19, -0.03, 1.465]); E = np.array([s * 0.355, -0.065, 1.215])
    Wr = np.array([s * 0.475, -0.15, 1.0]); T = np.array([s * 0.55, -0.2, 0.855])
    Hp = np.array([s * 0.1, -0.02, 0.92]); K = np.array([s * 0.13, -0.04, 0.52]); A = np.array([s * 0.145, 0.0, 0.1])
    return S, E, Wr, T, Hp, K, A
side_name = {-1: "_r", 1: "_l"}
seg = {"hips": ((0, -0.02, 0.84), (0, -0.02, 1.05)), "torso": ((0, -0.02, 1.08), (0, -0.02, 1.5)),
       "head": ((0, -0.05, 1.6), (0, -0.05, 1.78))}
for s in (-1, 1):
    S, E, Wr, T, Hp, K, A = J(s)
    n = side_name[s]
    seg["sh" + n] = (S, E); seg["el" + n] = (E, Wr); seg["hand" + n] = (Wr, T)
    seg["leg" + n] = (Hp, K); seg["knee" + n] = (K, A)
# cape panels: x centre of each (right, middle, left) and the heights of each chain's joints
CAPE = [("hA", -0.2), ("hB", 0.0), ("hC", 0.2)]
CAPE_Z = [1.42, 1.02, 0.62]
cape_names = [f"{c}{k + 1}" for c, _ in CAPE for k in range(3)]
# (no hair under the great helm)
HAIR_LOCKS = []
# hair locks: azimuth of each lock's centre round the head (0 = the face, A-pose front is -y)
HAIR_LOCKS = HAIR_LOCKS
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

# --- Blender's heat (automatic) weights on the 13 body bones, A-pose: smooth falloff along each limb,
# plates and mail bending together. The distance weights above stay only where heat weighting leaves a
# piece unweighted (it can on small loose islands).
heat_parents = {"hips": None, "torso": "hips", "head": "torso", "sh_r": "torso", "el_r": "sh_r", "hand_r": "el_r",
                "sh_l": "torso", "el_l": "sh_l", "hand_l": "el_l", "leg_r": "hips", "knee_r": "leg_r", "leg_l": "hips", "knee_l": "leg_l"}
tarm = bpy.data.armatures.new("heat")
trig = bpy.data.objects.new("heat", tarm)
bpy.context.scene.collection.objects.link(trig)
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = trig
bpy.ops.object.mode_set(mode="EDIT")
for n, (a, b) in seg.items():
    eb = tarm.edit_bones.new(n); eb.head = Vector(a); eb.tail = Vector(b)
for n, par in heat_parents.items():
    if par:
        tarm.edit_bones[n].parent = tarm.edit_bones[par]
bpy.ops.object.mode_set(mode="OBJECT")
# heat weighting needs a watertight mesh (Meshy's has loose plates and open seams): weight a voxel-remeshed
# copy, then carry the weights over to the real mesh by nearest surface
proxy = body.copy(); proxy.data = body.data.copy(); proxy.name = "proxy"
bpy.context.scene.collection.objects.link(proxy)
rm = proxy.modifiers.new("vox", "REMESH"); rm.mode = "VOXEL"; rm.voxel_size = 0.012; rm.adaptivity = 0.0
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = proxy; proxy.select_set(True)
bpy.ops.object.modifier_apply(modifier="vox")
dec = proxy.modifiers.new("dec", "DECIMATE"); dec.ratio = min(1.0, 60000 / max(len(proxy.data.polygons), 1))
bpy.ops.object.modifier_apply(modifier="dec")
print("proxy faces", len(proxy.data.polygons))
bpy.ops.object.select_all(action="DESELECT")
proxy.select_set(True); trig.select_set(True)
bpy.context.view_layer.objects.active = trig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
print("proxy weighted groups", len(proxy.vertex_groups))
for vg in proxy.vertex_groups:
    body.vertex_groups.new(name=vg.name)
dt = body.modifiers.new("dt", "DATA_TRANSFER")
dt.object = proxy; dt.use_vert_data = True; dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"; dt.layers_vgroup_select_src = "ALL"; dt.layers_vgroup_select_dst = "NAME"
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = body; body.select_set(True)
bpy.ops.object.modifier_apply(modifier="dt")
H = np.zeros((N, len(names)))
gi = {vg.index: vg.name for vg in body.vertex_groups}
for v in me.vertices:
    for g in v.groups:
        nm = gi.get(g.group)
        if nm in idx:
            H[v.index, idx[nm]] = g.weight
hs = H.sum(1)
ok = hs > 0.05
print("heat-weighted verts", ok.sum(), "of", N)
Wt[ok] = H[ok] / hs[ok][:, None]
body.parent = None
for m in list(body.modifiers):
    body.modifiers.remove(m)
body.vertex_groups.clear()
bpy.data.objects.remove(proxy)
bpy.data.objects.remove(trig)
bpy.context.view_layer.objects.active = body

# the arms (with their spikes) move only with their own arm: outside the chest, nothing else pulls on them
arm_only = {}
for s_ in (-1, 1):
    n_ = side_name[s_]
    m = np.zeros(N, bool)
    m |= near_seg((s_ * 0.24, -0.03, 1.43), (s_ * 0.355, -0.065, 1.215), 0.14)
    m |= near_seg((s_ * 0.355, -0.065, 1.215), (s_ * 0.475, -0.15, 1.0), 0.13)
    m |= near_seg((s_ * 0.475, -0.15, 1.0), (s_ * 0.6, -0.22, 0.74), 0.12)
    m &= (s_ * x > 0.28) & (z < 1.42) & (z > 0.68) & ~cape & ~sword
    keep = [idx["sh" + n_], idx["el" + n_], idx["hand" + n_]]
    w = Wt[m][:, keep]
    w /= np.maximum(w.sum(1, keepdims=True), 1e-9)
    Wt[m] = 0.0
    Wt[np.ix_(np.where(m)[0], keep)] = w
    arm_only[s_] = m
arm_lock = arm_only[-1] | arm_only[1]
print("arm-only verts", arm_lock.sum())

def take(mask_w, bone):
    Wt[:] *= (1 - mask_w)[:, None]; Wt[:, idx[bone]] += mask_w
take(sm(z, 1.55, 1.6) * (np.hypot(x, y + 0.05) < 0.2), "head")
take(sword.astype(float), "hips")
# the cloth hanging between the legs (front and back of the crotch) rides the hips alone: pulled by both
# legs it would stretch into a web when they swing apart
legs_tight = np.zeros(N, bool)
for s_ in (-1, 1):
    legs_tight |= near_seg((s_ * 0.1, -0.02, 0.9), (s_ * 0.13, -0.04, 0.52), 0.09)
    legs_tight |= near_seg((s_ * 0.13, -0.04, 0.52), (s_ * 0.145, 0.0, 0.0), 0.075)
skirt = (z < 0.88) & (z > 0.12) & (np.abs(x) < 0.075) & ~legs_tight & ~cape & ~sword
Wt[skirt] = 0.0
Wt[skirt, idx["hips"]] = 1.0
print("skirt verts", skirt.sum())
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
    for zz in CAPE_Z + [0.22]:
        band = sel & (np.abs(z - zz) < 0.03)
        pts.append(P[band].mean(0) if band.sum() > 5 else np.array([cx, 0.16, zz]))
    cape_joints[c] = pts
hair_joints = {}
print("cape panels", {c: int((cm & (memb[:, i] > 0.5)).sum()) for i, (c, _) in enumerate(CAPE)})

# soften every seam below the chest where neighbours ride different bones (tabard and mail skirt
# against the thighs, the cape's hem against the legs): average the weights over a few cm, a few
# times, so the cloth stretches a little instead of tearing when the legs swing
top0 = np.argmax(Wt, 1)
seam = np.zeros(N, bool)
for i in np.where((z < 1.2) & ~arm_lock & ~cape & ~skirt)[0]:
    for _, j, _ in kd.find_range(P[i], 0.03):
        if top0[j] != top0[i]:
            seam[i] = True
            break
sidx = np.where(seam)[0]
nbrs = [[j for _, j, _ in kd.find_range(P[i], 0.025) if not (arm_lock[j] or cape[j])] or [i] for i in sidx]
for _ in range(3):
    Wn = Wt.copy()
    for k, i in enumerate(sidx):
        Wn[i] = Wt[nbrs[k]].mean(0)
    Wt = Wn
print("softened seam verts", len(sidx))

# --- optional debug: renders of the A-pose coloured by each vertex's main bone (cloak red, legs blue,
# hips green, torso yellow, arms cyan, head white): python ... -- in out layout --debug prefix
# Meshy fuses the cloak to the legs and the gauntlets to the hips where they touch: faces bridging parts
# that move apart (cloak and leg, cloak and arm, arm and hips/leg) would stretch into sheets when he
# runs or swings, so they are cut (at rest they lie inside, unseen)
import bmesh
top1 = np.argmax(Wt, 1)
kind = np.zeros(N, int)       # 0 body, 1 cloak, 2 leg, 3 arm
for j, n_ in enumerate(names):
    k_ = 1 if (n_.startswith("h") and len(n_) == 3) else (2 if n_.startswith(("leg", "knee")) else (3 if n_.startswith(("sh", "el", "hand")) else 0))
    kind[top1 == j] = k_
bm = bmesh.new(); bm.from_mesh(me)
bad = []
for f in bm.faces:
    ks = {int(kind[v.index]) for v in f.verts}
    hipsy = any(top1[v.index] == idx["hips"] for v in f.verts)
    if (1 in ks and 2 in ks) or (1 in ks and 3 in ks) or (3 in ks and 2 in ks) or (3 in ks and hipsy and min(P[v.index][2] for v in f.verts) < 1.2):
        bad.append(f)
bmesh.ops.delete(bm, geom=bad, context="FACES_ONLY")
bm.to_mesh(me); bm.free(); me.update()
print("cut bridging faces", len(bad))
print("NaN weight rows", int(np.isnan(Wt).any(1).sum()), "zero rows", int((Wt.sum(1) < 1e-6).sum()), "head-top rows", int((np.argmax(Wt, 1) == idx["head"]).sum()))
if "--debug" in argv:
    pre = argv[argv.index("--debug") + 1]
    top1 = np.argmax(Wt, 1)
    pal = {"hips": (0.1, 0.8, 0.1), "torso": (0.9, 0.85, 0.1), "head": (1, 1, 1)}
    for n_ in names:
        if n_.startswith("h") and len(n_) == 3:
            pal[n_] = (0.9, 0.1, 0.1)
        elif n_.startswith(("leg", "knee")):
            pal[n_] = (0.15, 0.3, 1.0) if n_.endswith("_l") else (0.5, 0.2, 0.9)
        elif n_.startswith(("sh", "el", "hand")):
            pal[n_] = (0.1, 0.9, 0.9)
    dbg = body.copy(); dbg.data = body.data.copy(); bpy.context.scene.collection.objects.link(dbg)
    ca = dbg.data.color_attributes.new("dbg", "FLOAT_COLOR", "POINT")
    cols = np.array([pal.get(names[t], (0.5, 0.5, 0.5)) + (1.0,) for t in top1], np.float32)
    ca.data.foreach_set("color", cols.reshape(-1))
    mat = bpy.data.materials.new("dbg"); mat.use_nodes = True
    nt = mat.node_tree; bs = nt.nodes["Principled BSDF"]; at = nt.nodes.new("ShaderNodeAttribute"); at.attribute_name = "dbg"
    nt.links.new(at.outputs["Color"], bs.inputs["Base Color"])
    dbg.data.materials.clear(); dbg.data.materials.append(mat)
    body.hide_render = True
    sc = bpy.context.scene
    w_ = bpy.data.worlds.new("w"); sc.world = w_; w_.use_nodes = True
    w_.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.5
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    cd = bpy.data.cameras.new("c"); cd.type = "ORTHO"; cd.ortho_scale = 2.0
    cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam
    sc.render.resolution_x = sc.render.resolution_y = 800
    for v_, loc in (("front", (0, -5, 1.0)), ("side", (5, 0, 1.0)), ("back", (0, 5, 1.0)), ("lside", (-5, 0, 1.0))):
        cam.location = loc
        cam.rotation_euler = (Vector((0, 0, 1.0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = f"{pre}_{v_}.png"
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(dbg)
    body.hide_render = False

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
# crumbs: small loose pieces left hanging in the air after the repose (bits of a fingertip or a spike the
# arm no longer carries) are dropped: islands under 60 faces with nothing else within 4 cm
bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
seen = set(); islands = []
for f in bm.faces:
    if f.index in seen:
        continue
    stack = [f]; isl = []; seen.add(f.index)
    while stack:
        g = stack.pop(); isl.append(g)
        for e in g.edges:
            for h in e.link_faces:
                if h.index not in seen:
                    seen.add(h.index); stack.append(h)
    islands.append(isl)
kd2 = KDTree(N)
for i, p_ in enumerate(P2):
    kd2.insert(p_, i)
kd2.balance()
drop = []
for isl in islands:
    if len(isl) >= 60:
        continue
    vs = {v.index for f in isl for v in f.verts}
    alone = True
    for vi in list(vs)[:12]:
        for _, j, _ in kd2.find_range(P2[vi], 0.04):
            if j not in vs:
                alone = False; break
        if not alone:
            break
    if alone:
        drop += isl
bmesh.ops.delete(bm, geom=drop, context="FACES_ONLY")
bm.to_mesh(me); bm.free(); me.update()
print("dropped crumb faces", len(drop))
# shreds of the cloak's edge that stood out beside the forearms in the A-pose hang in mid-air beside him
# once the arms come down: drop them
shred = cape & (np.abs(P[:, 0]) > 0.355) & (P[:, 2] > 0.88)
bm = bmesh.new(); bm.from_mesh(me)
gone = [f for f in bm.faces if any(shred[v.index] for v in f.verts)]
bmesh.ops.delete(bm, geom=gone, context="FACES_ONLY")
bm.to_mesh(me); bm.free(); me.update()
print("dropped cloak shreds", len(gone))

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
arm = bpy.data.armatures.new("KnightCrusaderRig")
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
