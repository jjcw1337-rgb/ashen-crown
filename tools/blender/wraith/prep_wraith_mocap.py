# The Wraith's mocap body (assets/models/wraith_mocap.glb): the Meshy "horned, chained" wraith (concept D),
# auto-rigged by Meshy (24-bone humanoid, like the knight's and the ranger's), with Meshy library clips merged onto
# its armature, decimated, legless, and its robe made into cloth:
#  - he floats: the skeletal legs and feet are cut out of the mesh (what sat within reach of the leg bones below
#    the hips, plus the loose scraps that leaves), so only the robe hangs below the hips, open and dark inside;
#  - the robe below the hips hangs on six panels of three bones from the hips (hA..hF, round the body) that the game
#    swings like cloth (KnightMocapRig._sway_robe): no leg weights at all;
#  - the clips: Meshy's idle, combat stance, punches, casts, scream, hit and dodge, with their root motion taken out,
#    plus clips made here: "float" / "float_combat" (the idle / the stance with the arms eased back and out, the
#    way they trail when he glides; the game blends idle -> float by speed, the lean, bank and bob are procedural)
#    and "death" (the scream's first throw of the arms, then the head drops and the arms go slack as the game
#    sinks him into the ground dissolving);
#  - a vertex colour for the game's spectral shader (scripts/wraith_mocap.gdshader): R = how far down the robe (0 at
#    the hips, 1 at the hem: the hem frays into mist), G = cloth (Meshy's metal map; weak here).
#   blender -b --python prep_wraith_mocap.py -- <rigged.glb> <out.glb> <tris> <clips.glb> [<clips.glb> ...]
import bpy, sys, math
import numpy as np
import bmesh
from mathutils import Vector, Quaternion, Matrix
a = sys.argv[sys.argv.index("--") + 1:]
RIG, OUT, TRIS, CLIPS = a[0], a[1], int(a[2]), a[3:]
NAMES = {"idle": "idle", "combat_stance": "combat_idle",
         "punch_combo": "claw1", "punch_combo_1": "claw2", "charged_spell_cast": "cast", "mage_soell_cast": "cast2",
         "zombie_scream": "scream", "hit_reaction": "hit", "quick_step_and_spin_dodge": "dodge",
         "charged_ground_slam": "slam"}
# Meshy clips not used any more (he floats): Sneaky_Walk, Lean_Forward_Sprint, Strangled_and_Fall_Forward
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
seen = set()
for ac in list(bpy.data.actions):
    nm = NAMES.get(key(ac.name))
    if nm is None or nm in seen:
        print("dropped clip", ac.name)
        bpy.data.actions.remove(ac)
        continue
    seen.add(nm)
    ac.name = nm
    ac.use_fake_user = True
print("clips", len(seen), sorted(seen))
FPS = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
# Meshy's library clips carry root motion: the game moves the hero itself, so the hips' travel along the ground
# comes out of every clip (its straight-line drift from first frame to last; the sway and the up-and-down stay).
# (the Hips' location keys are in the bone's own rest frame, which Meshy tilts: the drift is taken out along the
# ground in the armature's frame, z up, and turned back)
hb = arm.data.bones["Hips"]
R3 = hb.matrix_local.to_3x3().normalized()
Ri = R3.inverted()
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
    for i_, fc in fcs.items():
        for kp in fc.keyframe_points:
            t = (kp.co.x - f0) / max(f1 - f0, 1e-6)
            drift = Vector(((a1.x - a0.x) * t, (a1.y - a0.y) * t, 0.0))
            d = (Ri @ drift)[i_]
            kp.co.y -= d
            kp.handle_left.y -= d
            kp.handle_right.y -= d
        fc.update()
print("root motion removed")

# --- clips made here. A world-axis turn laid on a bone at a frame: the pose is evaluated, the turn (world frame,
# z up, he faces -y) is carried into the bone's own frame and keyed on top of what the clip has there.
Aw = arm.matrix_world.to_3x3().normalized()
def bake_copy(src_name, dst_name, f_from, f_to, step=2):
    """A new action: src's frames f_from..f_to sampled every `step` frames (keys at 0..), for every bone channel."""
    src = bpy.data.actions[src_name]
    dst = bpy.data.actions.new(dst_name)
    dst.use_fake_user = True
    arm.animation_data.action = src
    frames = list(np.arange(f_from, f_to + 1e-6, step))
    if frames[-1] < f_to - 1e-6:
        frames.append(f_to)
    for f in frames:
        bpy.context.scene.frame_set(int(round(f)))
        bpy.context.view_layer.update()
        for pb in arm.pose.bones:
            for path, n in (("location", 3), ("rotation_quaternion", 4)):
                dp = 'pose.bones["%s"].%s' % (pb.name, path)
                if not any(fc.data_path == dp for fc in src.fcurves):
                    continue
                val = getattr(pb, path)
                for i in range(n):
                    fc = dst.fcurves.find(dp, index=i) or dst.fcurves.new(dp, index=i, action_group=pb.name)
                    fc.keyframe_points.insert(f - f_from, val[i], options={"FAST"})
    for fc in dst.fcurves:
        fc.update()
    arm.animation_data.action = None
    return dst
def world_turn(pb, axis, deg):
    """The quaternion to post-multiply pb's rotation by, for a turn of deg about the world axis at its head now."""
    M = (Aw @ pb.matrix.to_3x3()).normalized()      # the bone's frame in world
    Rw = Matrix.Rotation(math.radians(deg), 3, Vector(axis))
    return (M.inverted() @ Rw @ M).to_quaternion()
def ease_arms(ac, turns, weight_at):
    """Lays world turns on the bones of every key of ac: turns = {bone: [(axis, deg), ...]}, weight_at(f) 0..1."""
    arm.animation_data.action = ac
    fr = sorted({round(k.co.x, 3) for fc in ac.fcurves for k in fc.keyframe_points})
    for f in fr:
        bpy.context.scene.frame_set(int(round(f)))
        bpy.context.view_layer.update()
        w = weight_at(f)
        if w <= 0.0:
            continue
        for bn, ts in turns.items():
            pb = arm.pose.bones[bn]
            q = pb.rotation_quaternion.copy()
            for axis, deg in ts:
                q = q @ world_turn(pb, axis, deg * w)
                pb.rotation_quaternion = q
                bpy.context.view_layer.update()
            dp = 'pose.bones["%s"].rotation_quaternion' % bn
            for i in range(4):
                fc = ac.fcurves.find(dp, index=i) or ac.fcurves.new(dp, index=i, action_group=bn)
                fc.keyframe_points.insert(f, q[i], options={"FAST"})
        # the frame's other bones stay as they are
    for fc in ac.fcurves:
        fc.update()
    arm.animation_data.action = None
# the glide: the arms eased back and a little out (world x = his right, y = back, z = up), the elbows loosened,
# the head bowed a touch into the wind, the hands open and trailing
# (world x = his right, y = behind him, z = up; a turn about y by -deg lifts his left arm out, +deg his right)
TRAIL = {"LeftArm": [((1, 0, 0), 26.0), ((0, 1, 0), -8.0)], "RightArm": [((1, 0, 0), 26.0), ((0, 1, 0), 8.0)],
         "LeftForeArm": [((1, 0, 0), 14.0)], "RightForeArm": [((1, 0, 0), 14.0)],
         "LeftHand": [((1, 0, 0), 12.0)], "RightHand": [((1, 0, 0), 12.0)],
         "Head": [((1, 0, 0), 7.0)], "Spine01": [((1, 0, 0), 3.0)]}
ARMS = ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]
def still_arms(ac, amount):
    """The arms' keys pulled toward their first key by amount: the idle's gestures mostly gone (he's gliding)."""
    for bn in ARMS:
        dp = 'pose.bones["%s"].rotation_quaternion' % bn
        fq = {fc.array_index: fc for fc in ac.fcurves if fc.data_path == dp}
        if len(fq) < 4:
            continue
        n_ = len(fq[0].keyframe_points)
        q0 = Quaternion([fq[i].keyframe_points[0].co.y for i in range(4)])
        for k in range(n_):
            q = Quaternion([fq[i].keyframe_points[k].co.y for i in range(4)])
            q2 = q.slerp(q0, amount)
            for i in range(4):
                kp = fq[i].keyframe_points[k]
                kp.handle_left.y += q2[i] - kp.co.y
                kp.handle_right.y += q2[i] - kp.co.y
                kp.co.y = q2[i]
        for i in range(4):
            fq[i].update()
# the battle stance (Meshy's Combat Stance is a boxer's guard, one fist out: not his): the idle with the claws
# raised, out and forward, the elbows bent, leaning in a little
STANCE = {"LeftArm": [((0, 1, 0), 26.0), ((1, 0, 0), -14.0)], "RightArm": [((0, 1, 0), -26.0), ((1, 0, 0), -14.0)],
          "LeftForeArm": [((1, 0, 0), -46.0), ((0, 0, 1), 16.0)], "RightForeArm": [((1, 0, 0), -46.0), ((0, 0, 1), -16.0)],
          "LeftHand": [((1, 0, 0), 22.0), ((0, 0, 1), 12.0)], "RightHand": [((1, 0, 0), 22.0), ((0, 0, 1), -12.0)],
          "Spine01": [((1, 0, 0), 7.0)], "Head": [((1, 0, 0), 9.0)]}
bpy.data.actions.remove(bpy.data.actions["combat_idle"])
idle_a = bpy.data.actions["idle"]
ci = bake_copy("idle", "combat_idle", idle_a.frame_range[0], idle_a.frame_range[1], 2)
still_arms(ci, 0.6)
ease_arms(ci, STANCE, lambda f: 1.0)
for src, dst in (("idle", "float"), ("combat_idle", "float_combat")):
    sa = bpy.data.actions[src]
    fl = bake_copy(src, dst, sa.frame_range[0], sa.frame_range[1], 2)
    if dst == "float":
        still_arms(fl, 0.8)
    ease_arms(fl, TRAIL, lambda f: 1.0 if dst == "float" else 0.45)
    print("made", dst, fl.frame_range)
# the death (3 s, made from the idle's first pose): he rears up, the arms flung out wide and the head thrown back
# (0.4 s), hangs there shuddering (1.2 s), then the head drops and the arms sag as the game sinks him into the
# ground dissolving (3 s, held)
de = bake_copy("idle", "death", 0, 1, 1)
def add_keys_from(ac, f_src, f_dst, turns):
    """Keys at f_dst: ac's pose at f_src with world turns laid on (every bone keyed, so the hold is clean)."""
    arm.animation_data.action = ac
    bpy.context.scene.frame_set(int(round(f_src)))
    bpy.context.view_layer.update()
    vals = {}
    for pb in arm.pose.bones:
        vals[pb.name] = (pb.location.copy(), pb.rotation_quaternion.copy())
    for bn, ts in turns.items():
        pb = arm.pose.bones[bn]
        q = vals[bn][1].copy()
        for axis, deg in ts:
            q = q @ world_turn(pb, axis, deg)
            pb.rotation_quaternion = q
            bpy.context.view_layer.update()
        vals[bn] = (vals[bn][0], q)
    for pb in arm.pose.bones:
        for path, n in (("location", 3), ("rotation_quaternion", 4)):
            dp = 'pose.bones["%s"].%s' % (pb.name, path)
            if not any(fc.data_path == dp for fc in ac.fcurves):
                continue
            v = vals[pb.name][0 if path == "location" else 1]
            for i in range(n):
                fc = ac.fcurves.find(dp, index=i)
                fc.keyframe_points.insert(f_dst, v[i], options={"FAST"})
    for fc in ac.fcurves:
        fc.update()
    arm.animation_data.action = None
REAR = {"Head": [((1, 0, 0), -32.0)], "neck": [((1, 0, 0), -12.0)], "Spine01": [((1, 0, 0), -9.0)], "Spine": [((1, 0, 0), -8.0)],
        "LeftArm": [((0, 1, 0), -42.0), ((1, 0, 0), 12.0)], "RightArm": [((0, 1, 0), 42.0), ((1, 0, 0), 12.0)],
        "LeftForeArm": [((0, 1, 0), -20.0)], "RightForeArm": [((0, 1, 0), 20.0)],
        "LeftHand": [((0, 1, 0), -25.0)], "RightHand": [((0, 1, 0), 25.0)]}
HANG = {"Head": [((1, 0, 0), -42.0)], "neck": [((1, 0, 0), -14.0)], "Spine01": [((1, 0, 0), -12.0)], "Spine": [((1, 0, 0), -10.0)],
        "LeftArm": [((0, 1, 0), -58.0), ((1, 0, 0), 18.0)], "RightArm": [((0, 1, 0), 58.0), ((1, 0, 0), 18.0)],
        "LeftForeArm": [((0, 1, 0), -25.0)], "RightForeArm": [((0, 1, 0), 25.0)],
        "LeftHand": [((0, 1, 0), -40.0), ((1, 0, 0), 20.0)], "RightHand": [((0, 1, 0), 40.0), ((1, 0, 0), 20.0)]}
SAG = {"Head": [((1, 0, 0), 38.0)], "neck": [((1, 0, 0), 14.0)], "Spine01": [((1, 0, 0), 16.0)], "Spine": [((1, 0, 0), 10.0)],
       "LeftArm": [((0, 1, 0), -18.0), ((1, 0, 0), 30.0)], "RightArm": [((0, 1, 0), 18.0), ((1, 0, 0), 30.0)],
       "LeftForeArm": [((1, 0, 0), 20.0)], "RightForeArm": [((1, 0, 0), 20.0)],
       "LeftHand": [((1, 0, 0), 40.0)], "RightHand": [((1, 0, 0), 40.0)]}
add_keys_from(de, 0, 0.4 * FPS, REAR)
add_keys_from(de, 0, 1.2 * FPS, HANG)
add_keys_from(de, 0, 3.0 * FPS, SAG)
de.frame_range = (0.0, 3.0 * FPS)
de.use_frame_range = True
print("made death", de.frame_range)
for ac in bpy.data.actions:
    tr = arm.animation_data.nla_tracks.new()
    tr.name = ac.name
    tr.strips.new(ac.name, max(int(ac.frame_range[0]), 0), ac)
    tr.mute = True
print("actions", sorted(ac.name for ac in bpy.data.actions))

# --- the mesh: the legs out, the fragments swept, decimated
bpy.context.view_layer.objects.active = body
me = body.data
P = np.array([body.matrix_world @ v.co for v in me.vertices])
x, y, z = P[:, 0], P[:, 1], P[:, 2]
def bh(n):
    return np.array(arm.matrix_world @ arm.data.bones[n].head_local)
hips = bh("Hips")
hip_z = float(hips[2])
def seg_d(a_, b_, Q=None):
    Q = P if Q is None else Q
    ab = b_ - a_
    t = np.clip(((Q - a_) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(Q - (a_ + t[:, None] * ab), axis=1)
leg_segs = []
for s in ("Left", "Right"):
    u, k, f, t_ = bh(s + "UpLeg"), bh(s + "Leg"), bh(s + "Foot"), bh(s + "ToeBase")
    leg_segs += [(u, k, 0.085), (k, f, 0.095), (f, t_, 0.13), (f + (0, 0, -0.1), t_ + (0, 0, -0.1), 0.13)]
def leg_mask(Q):
    zz = Q[:, 2]
    m = np.zeros(len(Q), bool)
    for a_, b_, r in leg_segs:
        m |= seg_d(a_, b_, Q) < r
    return m & (zz < hip_z - 0.06)
gname = {vg.index: vg.name for vg in body.vertex_groups}
on_arm = np.zeros(len(me.vertices), bool)
for v in me.vertices:
    if v.groups:
        g = max(v.groups, key=lambda e: e.weight)
        nm = gname.get(g.group, "")
        on_arm[v.index] = ("Arm" in nm or "Hand" in nm or "Shoulder" in nm) and g.weight > 0.3
legs = leg_mask(P) & ~on_arm
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(legs[v.index] for v in f.verts)], context="FACES")
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0004)   # Meshy splits every face: welded, so the scraps show as islands
bm.verts.ensure_lookup_table()
# the scraps the cut leaves (bits of ankle, toe and shin that reached outside the cut): small islands below the hips
# near the leg bones go too; the chains and the robe's rags are big or far from the legs
seen = set()
scrap = []
for v in bm.verts:
    if v.index in seen:
        continue
    st = [v]
    seen.add(v.index)
    isl = []
    while st:
        w_ = st.pop()
        isl.append(w_)
        for e in w_.link_edges:
            o = e.other_vert(w_)
            if o.index not in seen:
                seen.add(o.index)
                st.append(o)
    if len(isl) > 400:
        continue
    Q = np.array([body.matrix_world @ w_.co for w_ in isl])
    near = min(seg_d(a_, b_, Q).min() for a_, b_, r in leg_segs)
    if Q[:, 2].max() < hip_z - 0.06 and near < 0.16:
        scrap += isl
print("scraps swept: %d verts" % len(scrap))
bmesh.ops.delete(bm, geom=scrap, context="VERTS")
bm.to_mesh(me)
bm.free()
me.update()
print("legs cut: %d verts left" % len(me.vertices))
cur = len(me.polygons)
if cur > TRIS:
    d = body.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
print("faces", len(me.polygons))

# --- where things are (rest pose, world metres; Meshy faces -y, feet were on z = 0)
N = len(me.vertices)
P = np.array([body.matrix_world @ v.co for v in me.vertices])
x, y, z = P[:, 0], P[:, 1], P[:, 2]
gname = {vg.index: vg.name for vg in body.vertex_groups}
on_arm = np.zeros(N, bool)
for v in me.vertices:
    if v.groups:
        g = max(v.groups, key=lambda e: e.weight)
        nm = gname.get(g.group, "")
        on_arm[v.index] = ("Arm" in nm or "Hand" in nm or "Shoulder" in nm) and g.weight > 0.3
def sm(v, a_, b_):
    t = np.clip((v - a_) / (b_ - a_), 0, 1); return t * t * (3 - 2 * t)
def seg_w(zz, top, bot, blend=0.07):
    return sm(zz, bot - blend, bot + blend) * (1 - sm(zz, top - blend, top + blend))
radial = np.hypot(x - hips[0], y - hips[1])
# what hangs from his arms in the A-pose (the shackle chains with their hooks, the torn sleeves) reaches below the
# hips; Meshy bound the lower links to the legs. Those (below the hips, under a hand or a forearm, clear of the
# robe) take their weights from the arm they hang from: diffused edge by edge down from the arm-bound vertices
hand_d = np.minimum.reduce([np.hypot(x - bh(s + "Hand")[0], y - bh(s + "Hand")[1]) for s in ("Left", "Right")])
def seg_d2(a_, b_):
    ab = (b_ - a_)[:2]
    t = np.clip(((P[:, :2] - a_[:2]) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(P[:, :2] - (a_[:2] + t[:, None] * ab), axis=1)
fore_d = np.minimum.reduce([seg_d2(bh(s + "ForeArm"), bh(s + "Hand")) for s in ("Left", "Right")])
hang = (z < hip_z + 0.02) & ~on_arm & (((hand_d < 0.2) & (radial > 0.33) & (z > 0.4)) | ((hand_d < 0.15) & (z <= 0.4))
                                        | ((fore_d < 0.12) & (z > 0.42) & (radial > 0.3)))
print("hanging from the arms: %d verts, %d of them below z 0.4" % (int(hang.sum()), int((hang & (z <= 0.4)).sum())))
G = list(body.vertex_groups)
gi = {g.index: k for k, g in enumerate(G)}
Wm = np.zeros((N, len(G)), np.float32)
for v in me.vertices:
    for e in v.groups:
        Wm[v.index, gi[e.group]] = e.weight
legcol = np.array([("Leg" in g.name or "Foot" in g.name or "Toe" in g.name) for g in G])
good = on_arm.copy()
Wm[good][:, legcol] = 0.0
Wg = Wm.copy()
Wg[:, legcol] = 0.0
Wg /= np.maximum(Wg.sum(1, keepdims=True), 1e-6)
ed = np.empty(len(me.edges) * 2, dtype=np.int64); me.edges.foreach_get("vertices", ed); ed = ed.reshape(-1, 2)
ed = np.concatenate([ed, ed[:, ::-1]])
todo = hang.copy()
for it in range(3000):
    src_ok = good[ed[:, 0]] & todo[ed[:, 1]]
    if not src_ok.any():
        break
    e2 = ed[src_ok]
    acc = np.zeros_like(Wm); cnt = np.zeros(N)
    np.add.at(acc, e2[:, 1], Wg[e2[:, 0]]); np.add.at(cnt, e2[:, 1], 1)
    got = cnt > 0
    Wg[got] = acc[got] / cnt[got][:, None]
    good |= got
    todo &= ~got
print("hanging bits: %d verts rebound to the arms, %d unreached" % (int(hang.sum() - todo.sum()), int(todo.sum())))
# what the diffusion never reached isn't joined to an arm: it's the robe's side after all
hang &= ~todo
rebind = np.where(hang | on_arm)[0]
for k, g in enumerate(G):
    g.remove(rebind.tolist())
    wk = Wg[rebind, k]
    for j in np.where(wk > 0.002)[0]:
        g.add([int(rebind[j])], float(wk[j]), "REPLACE")
# the shackle chains hanging from his wrists (the hanging bits under a hand, below the wrist) swing on their own
# chains of three bones from each hand (hG.. the left, hH.. the right; KnightMocapRig swings them as pendulums)
chain_joints = {}
chain_w = {}
for side, cn in (("Left", "hG"), ("Right", "hH")):
    hh = bh(side + "Hand")
    cv = hang & (np.hypot(x - hh[0], y - hh[1]) < 0.2) & (z < hh[2] - 0.06)
    if cv.sum() < 30:
        continue
    zt, zb = float(hh[2]) - 0.05, float(np.percentile(z[cv], 1))
    czs = [zt - (zt - zb) * k / 3.0 for k in range(4)]
    pts = []
    for zz in czs:
        band = cv & (np.abs(z - zz) < 0.05)
        pts.append(P[band].mean(0) if band.sum() > 4 else np.array([hh[0], hh[1], zz]))
    pts[0] = np.array([pts[0][0], pts[0][1], zt])
    chain_joints[cn] = (side + "Hand", pts)
    bands_c = [(9.0, czs[0])] + [(czs[k], czs[k + 1] if k + 1 < 3 else -9.0) for k in range(3)]
    cw = np.stack([seg_w(z, t_, b_, 0.04) for t_, b_ in bands_c], 1)
    cw /= np.maximum(cw.sum(1, keepdims=True), 1e-9)
    chain_w[cn] = (cv, cw)
    print("wrist chain %s: %d verts, %.2f..%.2f" % (cn, int(cv.sum()), zt, zb))
# the robe: everything else below the hips
skirt = (z < hip_z + 0.02) & ~on_arm & ~hang
print("hip_z %.3f, robe verts %d of %d" % (hip_z, int(skirt.sum()), N))
# six panels round the body by angle about the hips (front is -y)
ang = np.arctan2(x - hips[0], -(y - hips[1]))          # 0 = front, + = his left
PANELS = [("hA", 0.5), ("hB", -0.5), ("hC", 1.55), ("hD", -1.55), ("hE", 2.6), ("hF", -2.6)]
def adiff(a1, a2):
    return np.abs((a1 - a2 + math.pi) % (2 * math.pi) - math.pi)
memb = np.stack([np.exp(-(adiff(ang, c) / 0.62) ** 2) for _, c in PANELS], 1)
memb /= np.maximum(memb.sum(1, keepdims=True), 1e-9)
hem_z = max(float(np.percentile(z[skirt], 2)), 0.02) if skirt.any() else 0.05
CZ = [hip_z - 0.02, hip_z - (hip_z - hem_z) * 0.36, hip_z - (hip_z - hem_z) * 0.7, hem_z]
joints = {}
for pi_, (c, ca) in enumerate(PANELS):
    sel = skirt & (memb[:, pi_] > 0.45)
    pts = []
    for zz in CZ:
        band = sel & (np.abs(z - zz) < 0.05)
        if band.sum() > 5:
            pts.append(P[band].mean(0))
        else:
            r = 0.2
            pts.append(np.array([hips[0] + math.sin(ca) * r, hips[1] - math.cos(ca) * r, zz]))
    # the chain follows the bell of the robe only half-way: a chain slanted far out turns like a board
    top = pts[0]
    joints[c] = [np.array([top[0] + (p[0] - top[0]) * 0.5, top[1] + (p[1] - top[1]) * 0.5, p[2]]) for p in pts]
inv = arm.matrix_world.inverted()
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
for c, _ in PANELS:
    par = eb["Hips"]
    for k in range(3):
        b = eb.new(f"{c}{k + 1}")
        b.head = inv @ Vector(joints[c][k]); b.tail = inv @ Vector(joints[c][k + 1])
        if (b.tail - b.head).length < 1e-4:
            b.tail = b.head + Vector((0, 0, -0.05))
        b.parent = par
        par = b
for cn, (pname, pts) in chain_joints.items():
    par = eb[pname]
    for k in range(3):
        b = eb.new(f"{cn}{k + 1}")
        b.head = inv @ Vector(pts[k]); b.tail = inv @ Vector(pts[k + 1])
        if (b.tail - b.head).length < 1e-4:
            b.tail = b.head + Vector((0, 0, -0.05))
        b.parent = par
        par = b
bpy.ops.object.mode_set(mode="OBJECT")
bands = [(9.0, CZ[0])] + [(CZ[k], CZ[k + 1] if k + 1 < 3 else -9.0) for k in range(3)]
hw = np.stack([seg_w(z, t_, b_) for t_, b_ in bands], 1)
hw /= np.maximum(hw.sum(1, keepdims=True), 1e-9)
ri = np.where(skirt)[0].tolist()
for vg in body.vertex_groups:
    vg.remove(ri)
groups = {vg.name: vg for vg in body.vertex_groups}
def grp(nm):
    return groups[nm] if nm in groups else body.vertex_groups.new(name=nm)
top = grp("Hips")
for i in ri:
    if hw[i, 0] > 0.003:
        top.add([i], float(hw[i, 0]), "REPLACE")
for pi_, (c, _) in enumerate(PANELS):
    for k in range(3):
        g_ = grp(f"{c}{k + 1}")
        for i in ri:
            w_ = float(hw[i, k + 1] * memb[i, pi_])
            if w_ > 0.003:
                g_.add([i], w_, "REPLACE")
for cn, (cv, cw) in chain_w.items():
    hand_g = grp(chain_joints[cn][0])
    ci = np.where(cv)[0].tolist()
    for vg in body.vertex_groups:
        vg.remove(ci)
    for i in ci:
        if cw[i, 0] > 0.003:
            hand_g.add([i], float(cw[i, 0]), "REPLACE")
    for k in range(3):
        g_ = grp(f"{cn}{k + 1}")
        for i in ci:
            if cw[i, k + 1] > 0.003:
                g_.add([i], float(cw[i, k + 1]), "REPLACE")
# the leg groups are empty now (and the rig never animates them): dropped
for vg in list(body.vertex_groups):
    if "Leg" in vg.name or "Foot" in vg.name or "Toe" in vg.name:
        body.vertex_groups.remove(vg)

# --- the shader's masks (vertex colour): R = down the robe to the hem, G = cloth
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
metal = np.zeros(N)
if mimg:
    W_, H_ = mimg.size
    pix = np.array(mimg.pixels[:], dtype=np.float32).reshape(H_, W_, 4)
    px = np.clip((uv[:, 0] % 1.0) * W_, 0, W_ - 1).astype(int); py = np.clip((uv[:, 1] % 1.0) * H_, 0, H_ - 1).astype(int)
    v_ = np.zeros(N); c_ = np.zeros(N)
    np.add.at(v_, lv, pix[py, px, 2]); np.add.at(c_, lv, 1)
    metal = v_ / np.maximum(c_, 1)
down = np.clip((hip_z - z) / max(hip_z - hem_z, 0.1), 0, 1) * skirt
cloth = (metal < 0.4).astype(float)
col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
cd = np.zeros((N, 4), np.float32)
cd[:, 0] = down; cd[:, 1] = cloth; cd[:, 3] = 1.0
col.data.foreach_set("color", cd.ravel())
me.color_attributes.active_color = col
print("hem mask: %d robe verts, cloth %d, hem_z %.3f" % (int((down > 0).sum()), int(cloth.sum()), hem_z))
for img in bpy.data.images:
    if img.size[0] > 2048:
        img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_image_format="JPEG", export_jpeg_quality=88, export_vertex_color="ACTIVE")
print("EXPORTED", OUT)
