# The Wraith's mocap body (assets/models/wraith_mocap.glb): the Meshy "horned, chained" wraith (concept D),
# auto-rigged by Meshy (24-bone humanoid, like the knight's and the ranger's), with Meshy library clips merged onto
# its armature, decimated, and its robe made into cloth:
#  - the robe below the hips leaves the legs (Meshy's auto-weights stretch it with every stride) for six panels of
#    three bones hung from the hips (hA..hF, round the body) that the game swings like cloth (knight_rig.gd
#    _sway_hair); the panels nearest a leg keep a little of that leg so a stride pushes the cloth instead of
#    poking through it;
#  - a vertex colour for the game's spectral shader (Wraith.MOCAP_SHADER): R = how far down the robe (0 at the
#    hips, 1 at the hem: the hem, shins and feet fray into mist), G = cloth (Meshy's metal map; weak here).
#   blender -b --python prep_wraith_mocap.py -- <rigged.glb> <out.glb> <tris> <clips.glb> [<clips.glb> ...]
import bpy, sys, math
import numpy as np
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
RIG, OUT, TRIS, CLIPS = a[0], a[1], int(a[2]), a[3:]
NAMES = {"idle": "idle", "combat_stance": "combat_idle", "sneaky_walk": "walk", "lean_forward_sprint": "run",
         "punch_combo": "claw1", "punch_combo_1": "claw2", "charged_spell_cast": "cast", "mage_soell_cast": "cast2",
         "zombie_scream": "scream", "hit_reaction": "hit", "strangled_and_fall_forward": "death",
         "quick_step_and_spin_dodge": "dodge", "charged_ground_slam": "slam"}
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
    tr = arm.animation_data.nla_tracks.new()
    tr.name = nm
    tr.strips.new(nm, int(ac.frame_range[0]), ac)
    tr.mute = True
print("clips", len(seen), sorted(seen))
# Meshy's library clips carry root motion (the walk travels 1.1 m a loop): the game moves the hero itself, so the
# hips' travel along the ground comes out of every clip (its straight-line drift from first frame to last; the
# sway and the up-and-down stay). The death keeps its fall.
# (the Hips' location keys are in the bone's own rest frame, which Meshy tilts: the drift is taken out along the
# ground in the armature's frame, z up, and turned back)
hb = arm.data.bones["Hips"]
R3 = hb.matrix_local.to_3x3().normalized()
Ri = R3.inverted()
for ac in bpy.data.actions:
    if ac.name == "death":
        continue
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
# a glide, not a stride: in the walk and the glide the legs keep only some of their swing under the robe (the knees
# came up through the cloth), turned back toward their rest by GLIDE_LEGS of the way
GLIDE_LEGS = 0.62
LEG_BONES = ["LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "LeftToeBase", "RightToeBase"]
for ac in bpy.data.actions:
    if ac.name not in ("walk", "run"):
        continue
    for bn in LEG_BONES:
        fq = {fc.array_index: fc for fc in ac.fcurves if fc.data_path == 'pose.bones["%s"].rotation_quaternion' % bn}
        if len(fq) < 4:
            continue
        n_ = len(fq[0].keyframe_points)
        if any(len(fq[i].keyframe_points) != n_ for i in range(4)):
            continue
        from mathutils import Quaternion
        for k in range(n_):
            q = Quaternion([fq[i].keyframe_points[k].co.y for i in range(4)])
            q2 = Quaternion((1, 0, 0, 0)).slerp(q, 1.0 - GLIDE_LEGS)
            for i in range(4):
                kp = fq[i].keyframe_points[k]
                d = q2[i] - kp.co.y
                kp.co.y += d
                kp.handle_left.y += d
                kp.handle_right.y += d
        for i in range(4):
            fq[i].update()
print("legs eased in walk/run")
bpy.context.view_layer.objects.active = body
cur = len(body.data.polygons)
if cur > TRIS:
    d = body.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
print("faces", len(body.data.polygons))

# --- where things are (rest pose, world metres; Meshy faces -y, feet on z = 0)
me = body.data
N = len(me.vertices)
P = np.array([body.matrix_world @ v.co for v in me.vertices])
x, y, z = P[:, 0], P[:, 1], P[:, 2]
def bh(n):
    return np.array(arm.matrix_world @ arm.data.bones[n].head_local)
hips = bh("Hips")
legs = {s: [bh(s + "UpLeg"), bh(s + "Leg"), bh(s + "Foot")] for s in ("Left", "Right")}
def seg_d(a_, b_):
    ab = b_ - a_
    t = np.clip(((P - a_) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(P - (a_ + t[:, None] * ab), axis=1)
leg_d = {}
for s, (u, k, f) in legs.items():
    leg_d[s + "UpLeg"] = seg_d(u, k)
    leg_d[s + "Leg"] = seg_d(k, f)
near_leg = np.minimum.reduce(list(leg_d.values()))
hip_z = float(hips[2])
knee_z = float((legs["Left"][1][2] + legs["Right"][1][2]) / 2)
# the robe: below the hips and clear of the bony legs and feet (which stay on their bones)
foot_z = float(max(legs["Left"][2][2], legs["Right"][2][2])) + 0.02
skirt = (z < hip_z + 0.02) & ((near_leg > 0.075) | (z > knee_z + 0.05)) & ~((z < foot_z + 0.04) & (near_leg < 0.11))
# ...but not what hangs from his arms in the A-pose (the shackle chains and torn sleeves reach below the hips): a
# vertex Meshy bound mostly to an arm, or out beyond the robe's sides, stays on the arm
gname = {vg.index: vg.name for vg in body.vertex_groups}
on_arm = np.zeros(N, bool)
for v in me.vertices:
    if v.groups:
        g = max(v.groups, key=lambda e: e.weight)
        nm = gname.get(g.group, "")
        on_arm[v.index] = ("Arm" in nm or "Hand" in nm or "Shoulder" in nm) and g.weight > 0.3
radial = np.hypot(x - hips[0], y - hips[1])
skirt &= ~on_arm & (radial < 0.42)
print("hip_z %.3f knee_z %.3f, robe verts %d of %d" % (hip_z, knee_z, int(skirt.sum()), N))
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
        band = sel & (np.abs(z - zz) < 0.04)
        if band.sum() > 5:
            pts.append(P[band].mean(0))
        else:
            r = 0.2
            pts.append(np.array([hips[0] + math.sin(ca) * r, hips[1] - math.cos(ca) * r, zz]))
    joints[c] = pts
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
bpy.ops.object.mode_set(mode="OBJECT")
def sm(v, a_, b_):
    t = np.clip((v - a_) / (b_ - a_), 0, 1); return t * t * (3 - 2 * t)
def seg_w(zz, top, bot, blend=0.06):
    return sm(zz, bot - blend, bot + blend) * (1 - sm(zz, top - blend, top + blend))
bands = [(9.0, CZ[0])] + [(CZ[k], CZ[k + 1] if k + 1 < 3 else -9.0) for k in range(3)]
hw = np.stack([seg_w(z, t_, b_) for t_, b_ in bands], 1)
hw /= np.maximum(hw.sum(1, keepdims=True), 1e-9)
# a stride still carries the cloth just over the leg a little (the rest is the panels')
legname = np.array(list(leg_d.keys()))
legidx = np.argmin(np.stack(list(leg_d.values()), 1), 1)
leg_share = 0.4 * np.exp(-(near_leg / 0.16) ** 2) * sm(-z, -hip_z, -hip_z + 0.12)
ri = np.where(skirt)[0].tolist()
for vg in body.vertex_groups:
    vg.remove(ri)
groups = {vg.name: vg for vg in body.vertex_groups}
def grp(nm):
    return groups[nm] if nm in groups else body.vertex_groups.new(name=nm)
top = grp("Hips")
for i in ri:
    rest = 1.0 - leg_share[i]
    if hw[i, 0] * rest > 0.003:
        top.add([i], float(hw[i, 0] * rest), "REPLACE")
    if leg_share[i] > 0.003:
        grp(str(legname[legidx[i]])).add([i], float(leg_share[i]), "ADD")
for pi_, (c, _) in enumerate(PANELS):
    for k in range(3):
        g_ = grp(f"{c}{k + 1}")
        for i in ri:
            w_ = float(hw[i, k + 1] * memb[i, pi_] * (1.0 - leg_share[i]))
            if w_ > 0.003:
                g_.add([i], w_, "REPLACE")

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
# everything below the hips but what hangs from the arms: the legs and feet fade into the mist with the robe
down = np.clip((hip_z - z) / max(hip_z - hem_z, 0.1), 0, 1) * (~on_arm & (radial < 0.42))
cloth = (metal < 0.4).astype(float)
col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
cd = np.zeros((N, 4), np.float32)
cd[:, 0] = down; cd[:, 1] = cloth; cd[:, 3] = 1.0
col.data.foreach_set("color", cd.ravel())
me.color_attributes.active_color = col
print("hem mask: %d robe verts, cloth %d" % (int((down > 0).sum()), int(cloth.sum())))
for img in bpy.data.images:
    if img.size[0] > 2048:
        img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_image_format="JPEG", export_jpeg_quality=88, export_vertex_color="ACTIVE")
print("EXPORTED", OUT)
