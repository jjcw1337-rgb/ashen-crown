# The Demon's mocap body (assets/models/demon_mocap.glb): the Meshy "Magma Brute" (concept A: cracked charcoal
# skin with lava glowing through, swept-back horns, bat wings, a spiked tail, a loincloth, hooves), auto-rigged by
# Meshy (the 24-bone humanoid, like the knight's, the ranger's and the Wraith's), with Meshy library clips merged
# onto its armature, trimmed to their useful part, their root motion taken out, and decimated. Meshy bound the
# wings to the arm bones and the tail to the legs, so they tore about with every swing; here each gets its own
# bones the game animates (scripts/demon_mocap_rig.gd):
#  - wings: per side a chain from the back join: wL1 (the wing's root, on the back) -> wL2 (the arm, up to the
#    top joint) -> wL3 (the leading finger, out to the outer tip) and wL4 (the lower finger, down to the bottom
#    tip), parented to Spine01 (wR.. the right). The membrane is skinned to the nearest finger bones, blending
#    into the spine along the flank, so nothing tears where the wing meets the back;
#  - tail: tail1..tail7 along the tail's own centreline (found by geodesic distance from the root, so the curl
#    along the ground is followed), from the hips; the root blends into the hips;
#  - loincloth: the front flap on a cloth panel of three bones from the hips (hA1..hA3; KnightMocapRig's lock
#    naming, swung by the rig), the back flap on hB.. when there is one;
#  - vertex colour: R = along the tail (0 root .. 1 tip), G = wing membrane (the shader may backlight it).
# Clips (Meshy library ids in the commit): idle, walk, run, combat_idle, charge, claw (both fists), slam, smash
# (the axe chop, with the claws), grab_throw, hurl, cast, roar, stomp, hit, death.
#   blender -b --python prep_demon_mocap.py -- <rigged.glb> <out.glb> <tris> <clips.glb> [<clips.glb> ...] [--debug prefix]
import bpy, sys, math, os
import numpy as np
import bmesh
from mathutils import Vector, Quaternion, Matrix
a = sys.argv[sys.argv.index("--") + 1:]
DEBUG = None
if "--debug" in a:
    i_ = a.index("--debug"); DEBUG = a[i_ + 1]; a = a[:i_] + a[i_ + 2:]
RIG, OUT, TRIS, CLIPS = a[0], a[1], int(a[2]), a[3:]
# Meshy library names -> the game's clip names, with the frames kept (24 fps; None = the whole clip)
NAMES = {"idle": ("idle", None), "slow_orc_walk": ("walk", None), "run_02": ("run", None), "run_2": ("run", None),
         "combat_stance": ("combat_idle", None), "male_head_down_charge": ("charge", None),
         "punch_forward_with_both_fists": ("claw", (16, 84)), "charged_ground_slam": ("slam", None),
         "charged_axe_chop": ("smash", (60, 134)), "grip_and_throw_down": ("grab_throw", (12, 108)),
         "crouch_charge_and_throw": ("hurl", (96, 184)), "charged_spell_cast": ("cast", None),
         "zombie_scream": ("roar", None), "angry_ground_stomp": ("stomp", None), "hit_reaction": ("hit", None),
         "falling_down": ("death", None)}
LOOPS = ["idle", "walk", "run", "combat_idle", "charge"]
def key(n):
    return n.split("|")[-1].strip().lower().replace(" ", "_")
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
for ac in list(bpy.data.actions):
    if ac in keep:
        bpy.data.actions.remove(ac)
arm.animation_data_create()
arm.animation_data.action = None
FPS = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base

def bake_copy(src, dst_name, f_from, f_to, step=1):
    """A new action: src's frames f_from..f_to sampled every `step` frames (keys at 0..), every bone channel."""
    dst = bpy.data.actions.new(dst_name)
    dst.use_fake_user = True
    arm.animation_data.action = src
    frames = list(np.arange(f_from, f_to + 1e-6, step))
    if frames[-1] < f_to - 1e-6:
        frames.append(f_to)
    paths = {fc.data_path for fc in src.fcurves}
    for f in frames:
        bpy.context.scene.frame_set(int(round(f)))
        bpy.context.view_layer.update()
        for pb in arm.pose.bones:
            for path, n in (("location", 3), ("rotation_quaternion", 4)):
                dp = 'pose.bones["%s"].%s' % (pb.name, path)
                if dp not in paths:
                    continue
                val = getattr(pb, path)
                for i in range(n):
                    fc = dst.fcurves.find(dp, index=i) or dst.fcurves.new(dp, index=i, action_group=pb.name)
                    fc.keyframe_points.insert(f - f_from, val[i], options={"FAST"})
    for fc in dst.fcurves:
        fc.update()
    arm.animation_data.action = None
    return dst
seen = set()
for ac in list(bpy.data.actions):
    ent = NAMES.get(key(ac.name))
    if ent is None or ent[0] in seen:
        print("dropped clip", ac.name)
        bpy.data.actions.remove(ac)
        continue
    nm, rng = ent
    seen.add(nm)
    if rng is not None:
        # trimmed to its useful part (the long charges and the recoveries Meshy pads them with go)
        f0, f1 = rng
        f1 = min(f1, ac.frame_range[1])
        trimmed = bake_copy(ac, nm, f0, f1, 1)
        bpy.data.actions.remove(ac)
        print("trimmed", nm, f0, f1)
    else:
        ac.name = nm
        ac.use_fake_user = True
print("clips", len(seen), sorted(seen))
# Meshy's library clips carry root motion: the game moves the hero itself, so the hips' travel along the ground
# comes out of every clip (the straight-line drift from first frame to last; sway and bob stay). The Hips' location
# keys are in the bone's own rest frame, which Meshy tilts: the drift is taken out along the ground in the
# armature's frame (z up) and turned back.
hb = arm.data.bones["Hips"]
R3 = hb.matrix_local.to_3x3().normalized()
Ri = R3.inverted()
speeds = {}
for ac in bpy.data.actions:
    fcs = {fc.array_index: fc for fc in ac.fcurves if fc.data_path == 'pose.bones["Hips"].location'}
    if len(fcs) < 3:
        continue
    frames = sorted({round(k.co.x, 4) for fc in fcs.values() for k in fc.keyframe_points})
    if len(frames) < 2:
        continue
    f0, f1 = frames[0], frames[-1]
    def at(f):
        return R3 @ Vector([fcs[i].evaluate(f) for i in range(3)])
    a0, a1 = at(f0), at(f1)
    drift = Vector(((a1.x - a0.x), (a1.y - a0.y), 0.0))
    speeds[ac.name] = drift.length * 0.01 / max((f1 - f0) / FPS, 1e-6)      # the armature is in centimetres
    for i_, fc in fcs.items():
        for kp in fc.keyframe_points:
            t = (kp.co.x - f0) / max(f1 - f0, 1e-6)
            d = (Ri @ (drift * t))[i_]
            kp.co.y -= d
            kp.handle_left.y -= d
            kp.handle_right.y -= d
        fc.update()
print("root motion removed; ground speeds from the drift (m/s):", {k: round(v, 2) for k, v in speeds.items()})
# a clip animated in place has no drift: its pace is the planted foot's speed back under the hips
for nm in ("walk", "run", "charge"):
    if nm not in bpy.data.actions:
        continue
    ac = bpy.data.actions[nm]
    arm.animation_data.action = ac
    f0, f1 = ac.frame_range
    best = 0.0
    prev = None
    for f in range(int(f0), int(f1) + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        hp = arm.matrix_world @ arm.pose.bones["Hips"].head
        feet = [(arm.matrix_world @ arm.pose.bones[s + "Foot"].head) - hp for s in ("Left", "Right")]
        if prev is not None:
            for k in range(2):
                v = (feet[k] - prev[k]).length * FPS
                lowest = min(feet, key=lambda q: q.z)
                if feet[k] is lowest:
                    best = max(best, v)
        prev = feet
    arm.animation_data.action = None
    print("in-place pace of %s: planted foot %.2f m/s (drift %.2f)" % (nm, best, speeds.get(nm, 0.0)))
for ac in bpy.data.actions:
    tr = arm.animation_data.nla_tracks.new()
    tr.name = ac.name
    tr.strips.new(ac.name, max(int(ac.frame_range[0]), 0), ac)
    tr.mute = True
print("actions", sorted(ac.name for ac in bpy.data.actions))

# --- the mesh: welded (Meshy splits every face), decimated
bpy.context.view_layer.objects.active = body
me = body.data
bm = bmesh.new()
bm.from_mesh(me)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)
bm.to_mesh(me)
bm.free()
me.update()
cur = len(me.polygons)
if cur > TRIS:
    d = body.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
print("faces", len(me.polygons), "verts", len(me.vertices))

# --- where things are (rest pose, world metres; Meshy faces -y, feet on z = 0)
N = len(me.vertices)
P = np.array([body.matrix_world @ v.co for v in me.vertices])
x, y, z = P[:, 0], P[:, 1], P[:, 2]
def bh(n):
    return np.array(arm.matrix_world @ arm.data.bones[n].head_local)
def seg_d(a_, b_, Q=None):
    Q = P if Q is None else Q
    ab = b_ - a_
    if ab @ ab < 1e-9:
        return np.linalg.norm(Q - a_, axis=1)
    t = np.clip(((Q - a_) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(Q - (a_ + t[:, None] * ab), axis=1)
hips = bh("Hips"); neck = bh("neck"); head = bh("Head")
d_torso = seg_d(hips - (0, 0, 0.12), neck)
d_head = seg_d(head, head + (0, 0, 0.3))
d_arm = np.full(N, 9.0); d_leg = np.full(N, 9.0)
for s in ("Left", "Right"):
    for a_, b_ in ((bh(s + "Shoulder"), bh(s + "Arm")), (bh(s + "Arm"), bh(s + "ForeArm")), (bh(s + "ForeArm"), bh(s + "Hand")),
                   (bh(s + "Hand"), bh(s + "Hand") + (bh(s + "Hand") - bh(s + "ForeArm")) * 0.9)):
        d_arm = np.minimum(d_arm, seg_d(a_, b_))
    for a_, b_ in ((bh(s + "UpLeg"), bh(s + "Leg")), (bh(s + "Leg"), bh(s + "Foot")), (bh(s + "Foot"), bh(s + "ToeBase")),
                   (bh(s + "ToeBase"), bh(s + "ToeBase") + (0, -0.12, -0.08))):
        d_leg = np.minimum(d_leg, seg_d(a_, b_))
ed = np.empty(len(me.edges) * 2, dtype=np.int64); me.edges.foreach_get("vertices", ed); ed = ed.reshape(-1, 2)
adj = [[] for _ in range(N)]
for u, v in ed:
    adj[u].append(v); adj[v].append(u)
def components(mask):
    """Connected components (lists of vertex indices) within mask, biggest first."""
    seen_ = np.zeros(N, bool)
    comps = []
    for s0 in np.where(mask)[0]:
        if seen_[s0]:
            continue
        st = [s0]; seen_[s0] = True; comp = []
        while st:
            u = st.pop(); comp.append(u)
            for v in adj[u]:
                if mask[v] and not seen_[v]:
                    seen_[v] = True; st.append(v)
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    return comps
def geodesic(seeds, mask):
    """Edge-length distance from the seeds through mask (inf elsewhere)."""
    import heapq
    dist = np.full(N, np.inf)
    h = []
    for s0 in seeds:
        dist[s0] = 0.0; heapq.heappush(h, (0.0, int(s0)))
    while h:
        d0, u = heapq.heappop(h)
        if d0 > dist[u]:
            continue
        for v in adj[u]:
            if not mask[v]:
                continue
            nd = d0 + float(np.linalg.norm(P[u] - P[v]))
            if nd < dist[v]:
                dist[v] = nd; heapq.heappush(h, (nd, v))
    return dist
def sm(v, a_, b_):
    t = np.clip((v - a_) / (b_ - a_), 0, 1); return t * t * (3 - 2 * t)

# the wings: behind the back, clear of the arms and the torso, above the hips; the two big pieces, by side
cand = (y > 0.1) & (z > 0.55) & (d_arm > 0.2) & (d_torso > 0.24) & (d_head > 0.25)
wing = {"L": np.zeros(N, bool), "R": np.zeros(N, bool)}
for comp in components(cand):
    if len(comp) < 300:
        continue
    cx = x[comp].mean()
    side = "L" if cx > 0 else "R"
    if wing[side].sum() == 0:
        wing[side][comp] = True
print("wings: L %d verts, R %d verts" % (int(wing["L"].sum()), int(wing["R"].sum())))
# the tail: grown from the back of the hips down and along the ground, through what isn't body
tail_ok = (z < 1.12) & (d_leg > 0.16) & (d_torso > 0.2) & ~wing["L"] & ~wing["R"]
seeds = tail_ok & (y > 0.1) & (z > 0.75) & (np.abs(x) < 0.2)
tail = np.zeros(N, bool)
for comp in components(tail_ok):
    if seeds[comp].sum() > 20 and len(comp) > 300:
        tail[comp] = True
        break
print("tail: %d verts, z %.2f..%.2f, x %.2f..%.2f" % (int(tail.sum()), z[tail].min(), z[tail].max(), x[tail].min(), x[tail].max()))
# its centreline: geodesic distance from the root end, binned
root_pts = np.where(tail & (z > np.percentile(z[tail], 97)))[0]
gd = geodesic(root_pts, tail)
gd[~tail] = np.inf
L_tail = float(np.percentile(gd[tail], 99.5))
NB = 24
centre = []
for k in range(NB):
    lo, hi = L_tail * k / NB, L_tail * (k + 1) / NB
    band = tail & (gd >= lo) & (gd < hi)
    if band.sum() > 3:
        centre.append(P[band].mean(0))
centre = np.array(centre)
# smoothed, then resampled by arclength into the bone chain
for _ in range(2):
    c2 = centre.copy()
    c2[1:-1] = (centre[:-2] + centre[1:-1] + centre[2:]) / 3.0
    centre = c2
seglen = np.linalg.norm(np.diff(centre, axis=0), axis=1)
arc = np.concatenate([[0.0], np.cumsum(seglen)])
NT = 7
tail_pts = [np.array([np.interp(arc[-1] * k / NT, arc, centre[:, i]) for i in range(3)]) for k in range(NT + 1)]
print("tail length %.2f m, joints:" % arc[-1], [tuple(round(float(c), 2) for c in p) for p in tail_pts])
# each tail vertex's place along the chain (bone units, from the root)
s_tail = np.interp(gd, [L_tail * k / NB for k in range(NB)] + [L_tail], list(np.concatenate([[0.0], np.cumsum(seglen)])) + [arc[-1]]) / max(arc[-1], 1e-6) * NT
s_tail[~tail] = 0.0
# the loincloth: the flap hanging in front of the thighs (and one behind, if the model has it)
cloth = {}
front = (np.abs(x) < 0.17) & (y < -0.17) & (z > 0.48) & (z < hips[2] - 0.12) & (d_leg > 0.11) & ~tail
back = (np.abs(x) < 0.16) & (y > 0.06) & (z > 0.5) & (z < hips[2] - 0.14) & (d_leg > 0.12) & ~tail & ~wing["L"] & ~wing["R"]
for nm, m in (("hA", front), ("hB", back)):
    comps = [c for c in components(m) if len(c) > 120]
    if not comps:
        print("no %s cloth" % nm)
        continue
    sel = np.zeros(N, bool)
    sel[comps[0]] = True
    cloth[nm] = sel
    print("cloth %s: %d verts, z %.2f..%.2f" % (nm, int(sel.sum()), z[sel].min(), z[sel].max()))

# --- the new bones
inv = arm.matrix_world.inverted()
wing_pts = {}
for side in ("L", "R"):
    w = wing[side]
    if w.sum() == 0:
        continue
    sgn = 1.0 if side == "L" else -1.0
    near = w & (d_torso < np.percentile(d_torso[w], 4))
    J = P[near].mean(0)
    T = P[np.where(w)[0][np.argmax(z[w])]]
    outer = w & (sgn * x > 0.55)
    E = P[np.where(outer)[0][np.argmax(sgn * x[outer])]] if outer.any() else P[np.where(w)[0][np.argmax(sgn * x[w])]]
    low = w & (sgn * x > 0.45)
    B = P[np.where(low)[0][np.argmin(z[low])]] if low.any() else E
    S = J + (T - J) * 0.35
    wing_pts[side] = {"J": J, "S": S, "T": T, "E": E, "B": B}
    print("wing %s: join %s top %s outer %s bottom %s" % (side, *[tuple(round(float(c), 2) for c in p) for p in (J, T, E, B)]))
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
def new_bone(name, h, t, parent):
    b = eb.new(name)
    b.head = inv @ Vector(h); b.tail = inv @ Vector(t)
    if (b.tail - b.head).length < 1e-4:
        b.tail = b.head + Vector((0, 0, 5.0))
    b.parent = parent
    return b
for side, pts in wing_pts.items():
    b1 = new_bone("w%s1" % side, pts["J"], pts["S"], eb["Spine01"])
    b2 = new_bone("w%s2" % side, pts["S"], pts["T"], b1)
    new_bone("w%s3" % side, pts["T"], pts["E"], b2)
    new_bone("w%s4" % side, pts["T"], pts["B"], b2)
par = eb["Hips"]
for k in range(NT):
    par = new_bone("tail%d" % (k + 1), tail_pts[k], tail_pts[k + 1], par)
cloth_joints = {}
for nm, sel in cloth.items():
    zt, zb = float(np.percentile(z[sel], 98)), float(np.percentile(z[sel], 2))
    czs = [zt - (zt - zb) * k / 3.0 for k in range(4)]
    pts = []
    for zz in czs:
        band = sel & (np.abs(z - zz) < 0.04)
        pts.append(P[band].mean(0) if band.sum() > 4 else np.array([0.0, -0.3 if nm == "hA" else 0.2, zz]))
    cloth_joints[nm] = (czs, pts)
    par = eb["Hips"]
    for k in range(3):
        par = new_bone("%s%d" % (nm, k + 1), pts[k], pts[k + 1], par)
bpy.ops.object.mode_set(mode="OBJECT")

# --- the weights
G = {vg.name: vg for vg in body.vertex_groups}
def grp(nm):
    if nm not in G:
        G[nm] = body.vertex_groups.new(name=nm)
    return G[nm]
def set_weights(idx, W):
    """idx: vertex indices; W: {bone: weights over idx}. Replaces every group on those vertices."""
    il = [int(i) for i in idx]
    for vg in body.vertex_groups:
        vg.remove(il)
    for nm, w in W.items():
        g = grp(nm)
        for j, i in enumerate(il):
            if w[j] > 0.003:
                g.add([i], float(w[j]), "REPLACE")
# the spine bone a point on the back belongs to, by height (blended between neighbours)
SPINE = [("Hips", hips[2] - 0.1), ("Spine02", bh("Spine02")[2]), ("Spine01", bh("Spine01")[2]), ("Spine", bh("Spine")[2] + 0.05)]
def spine_w(zz):
    out = {}
    for k, (nm, zk) in enumerate(SPINE):
        lo = SPINE[k - 1][1] if k > 0 else zk - 1.0
        hi = SPINE[k + 1][1] if k + 1 < len(SPINE) else zk + 1.0
        w = np.where(zz < zk, np.clip((zz - lo) / max(zk - lo, 1e-6), 0, 1), np.clip((hi - zz) / max(hi - zk, 1e-6), 0, 1))
        out[nm] = w
    tot = sum(out.values())
    return {k: v / np.maximum(tot, 1e-6) for k, v in out.items()}
for side, pts in wing_pts.items():
    idx = np.where(wing[side])[0]
    Q = P[idx]
    # body share along the flank: what sits against the back stays with the spine
    body_w = 1.0 - sm(d_torso[idx], 0.24, 0.42)
    segs = {"w%s1" % side: (pts["J"], pts["S"]), "w%s2" % side: (pts["S"], pts["T"]),
            "w%s3" % side: (pts["T"], pts["E"]), "w%s4" % side: (pts["T"], pts["B"])}
    inv_d = {}
    for nm, (a_, b_) in segs.items():
        inv_d[nm] = 1.0 / (seg_d(a_, b_, Q) + 0.06) ** 2.5
    tot = sum(inv_d.values())
    W = {nm: v / tot * (1.0 - body_w) for nm, v in inv_d.items()}
    # the root and the arm barely stretch the membrane; the fingers carry it
    for nm, w in spine_w(Q[:, 2]).items():
        W[nm] = W.get(nm, 0.0) + w * body_w
    set_weights(idx, W)
idx = np.where(tail)[0]
s = s_tail[idx]
W = {}
for k in range(NT):
    # a smooth tent over its own bone, half a bone into each neighbour
    W["tail%d" % (k + 1)] = np.clip(1.0 - np.abs(s - (k + 0.5)), 0.0, 1.0)
root_w = 1.0 - sm(s, 0.0, 0.7)
tot = sum(W.values())
W = {nm: w / np.maximum(tot, 1e-6) * (1.0 - root_w) for nm, w in W.items()}
W["Hips"] = root_w
set_weights(idx, W)
for nm, sel in cloth.items():
    idx = np.where(sel)[0]
    czs, pts = cloth_joints[nm]
    zz = z[idx]
    def seg_w(zz, top, bot, blend=0.05):
        return sm(zz, bot - blend, bot + blend) * (1 - sm(zz, top - blend, top + blend))
    bands = [(9.0, czs[0])] + [(czs[k], czs[k + 1] if k + 1 < 3 else -9.0) for k in range(3)]
    hw = np.stack([seg_w(zz, t_, b_) for t_, b_ in bands], 1)
    hw /= np.maximum(hw.sum(1, keepdims=True), 1e-9)
    W = {"Hips": hw[:, 0]}
    for k in range(3):
        W["%s%d" % (nm, k + 1)] = hw[:, k + 1]
    set_weights(idx, W)
# anything else Meshy had hanging off the arms behind the back (wing scraps the components missed) stays as it was

# --- the shader's masks (vertex colour): R = along the tail, G = wing membrane
col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
cd = np.zeros((N, 4), np.float32)
cd[:, 0] = np.clip(s_tail / NT, 0, 1) * tail
cd[:, 1] = (wing["L"] | wing["R"]).astype(np.float32)
cd[:, 3] = 1.0
col.data.foreach_set("color", cd.ravel())
me.color_attributes.active_color = col
for img in bpy.data.images:
    if img.size[0] > 2048:
        img.scale(2048, 2048)
# any scrap of wing below the bottom tips (a vertex of the tip left bound to the arms would stretch into a thread
# whenever the arm moved) is cut
strand = (wing["L"] | wing["R"]) & (z < 0.5)
for side, pts in wing_pts.items():
    B = pts["B"]
    strand |= (np.hypot(x - B[0], y - B[1]) < 0.12) & (z < B[2] - 0.01) & ~tail & (d_leg > 0.15)
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(strand[v.index] for v in f.verts)], context="FACES")
keep_idx = np.array([v.index for v in bm.verts if v.link_faces])
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
bm.to_mesh(me)
bm.free()
me.update()
print("wing strands cut: %d verts; mesh now %d verts %d faces" % (int(strand.sum()), len(me.vertices), len(me.polygons)))
if DEBUG:
    N = len(me.vertices)
    P = np.array([body.matrix_world @ v.co for v in me.vertices])
    wing = {k: v[keep_idx] for k, v in wing.items()}; tail = tail[keep_idx]; s_tail = s_tail[keep_idx]
    cloth = {k: v[keep_idx] for k, v in cloth.items()}
    # a render coloured by the new regions, to check them
    import colorsys
    dbg = me.color_attributes.new("Dbg", "FLOAT_COLOR", "POINT")
    dc = np.full((N, 4), 0.35, np.float32); dc[:, 3] = 1
    dc[wing["L"]] = (0.9, 0.8, 0.1, 1); dc[wing["R"]] = (0.9, 0.5, 0.1, 1)
    tcol = np.stack([np.clip(s_tail / NT, 0, 1), 0.2 + 0 * s_tail, 1.0 - np.clip(s_tail / NT, 0, 1), np.ones(N)], 1)
    dc[tail] = tcol[tail]
    for nm, sel in cloth.items():
        dc[sel] = (0.1, 0.9, 0.3, 1) if nm == "hA" else (0.3, 0.9, 0.9, 1)
    dbg.data.foreach_set("color", dc.ravel())
    me.color_attributes.active_color = dbg
    mat = bpy.data.materials.new("dbg"); mat.use_nodes = True
    nt = mat.node_tree; bs = nt.nodes["Principled BSDF"]
    va = nt.nodes.new("ShaderNodeVertexColor"); va.layer_name = "Dbg"
    nt.links.new(va.outputs[0], bs.inputs["Base Color"])
    saved = list(me.materials)
    me.materials.clear(); me.materials.append(mat)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"; sc.display.shading.light = "FLAT"; sc.display.shading.color_type = "VERTEX"
    sc.render.resolution_x = 700; sc.render.resolution_y = 800
    world = bpy.data.worlds.new("W"); sc.world = world; world.color = (0.1, 0.1, 0.1)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("C")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = 2.6
    for k, (loc, rot) in {"front": ((0, -6, 1.1), (math.pi / 2, 0, 0)), "back": ((0, 6, 1.1), (math.pi / 2, 0, math.pi)),
                          "left": ((6, 0, 1.1), (math.pi / 2, 0, math.pi / 2)), "top": ((0, 0, 7), (0, 0, 0))}.items():
        cam.location = loc; cam.rotation_euler = rot
        sc.render.filepath = "%s_%s.png" % (DEBUG, k)
        bpy.ops.render.render(write_still=True)
    me.materials.clear()
    for m in saved:
        me.materials.append(m)
    me.color_attributes.remove(dbg)
    me.color_attributes.active_color = me.color_attributes["Col"]
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_image_format="JPEG", export_jpeg_quality=88, export_vertex_color="ACTIVE")
print("EXPORTED", OUT)
