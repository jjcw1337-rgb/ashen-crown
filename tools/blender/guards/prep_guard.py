# Builds a camp guard's body (assets/models/guards/<name>.glb + <name>.json): the Meshy auto-rigged guard (the
# 24-bone humanoid the playable mocap bodies use, so a guard can be made playable on Knight.build_mocap later)
# with its Meshy library clips merged onto its one armature, decimated to a game budget and exported as one glb
# whose AnimationPlayer holds every clip by the game's name (CampGuard: idle, walk, run, combat_idle, strafe_l,
# turn_l, strike_1..3 ...). Same steps as tools/blender/plague/prep_plague_mocap.py, plus what CampGuard needs
# to play the clips in place and drive the body itself:
# - turn clips (turn_*, walk_turn_*): the yaw the hips swing through is baked out of the clip (the body turns
#   in place in the game instead, by the measured angle, so the clip never snaps back when it ends);
# - every clip's ground motion (metres per second forward and to the side) and length: off the hips where the clip
#   travels, else (Meshy's in-place walks and runs) off the planted foot, which slides back under the hips at the
#   speed the body would go;
# - strike clips: the moments a hand or foot lands (each time one reaches its farthest out in front), as fractions.
# The numbers go to <out>.json beside the glb.
#   blender -b --python prep_guard.py -- <rigged.glb> <out.glb> <tris> <names.json> clips_a.glb [clips_b.glb ...]
# names.json maps Meshy library names (any case and punctuation: "Left Jab from Guard") to the game's clip names.
# Sources (Meshy task ids, clip ids) are in the git history of docs/guards.md (removed 2026-11-06).
import bpy, json, math, re, sys
from mathutils import Matrix, Vector
a = sys.argv[sys.argv.index("--") + 1:]
RIG, OUT, TRIS, NAMES_JSON, CLIPS = a[0], a[1], int(a[2]), a[3], a[4:]
def norm(n):
    return re.sub(r"[^a-z0-9]", "", n.split("|")[-1].lower())
NAMES = {norm(k): v for k, v in json.load(open(NAMES_JSON)).items()}
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
seen = {}
for ac in list(bpy.data.actions):
    nm = NAMES.get(norm(ac.name))
    if nm is None or nm in seen:
        print("dropped clip", ac.name)
        bpy.data.actions.remove(ac)
        continue
    seen[nm] = ac
    ac.name = nm
    ac.use_fake_user = True
print("clips", len(seen), sorted(seen))
missing = sorted(set(NAMES.values()) - set(seen))
if missing:
    print("MISSING clips", missing)

# --- measure (and for the turns, bake out the hips' yaw), clip by clip
sc = bpy.context.scene
fps = sc.render.fps / sc.render.fps_base
pb = arm.pose.bones
def bone(*names):
    for n in names:
        if n in pb:
            return pb[n]
    raise KeyError(names)
HIPS = bone("Hips", "mixamorig:Hips")
LUP, RUP = bone("LeftUpLeg"), bone("RightUpLeg")
ENDS = [bone(n) for n in ("LeftHand", "RightHand", "LeftFoot", "RightFoot")]
W = arm.matrix_world
def wpos(b):
    return W @ b.head
def yaw_now():
    side = wpos(RUP) - wpos(LUP)           # the hip line: forward is perpendicular to it
    return math.atan2(side.y, side.x)
LOCO = {"walk", "run", "walk_fight", "walk_fight_back", "strafe_l", "strafe_r", "walk_look", "walk_back"}
meta = {}
for nm, ac in sorted(seen.items()):
    arm.animation_data.action = ac
    f0, f1 = int(ac.frame_range[0]), int(ac.frame_range[1])
    sc.frame_set(f0)
    y0 = yaw_now()
    p0 = wpos(HIPS).copy()
    fwd0 = Vector((0.0, -1.0, 0.0))        # the model's forward (glTF's +z, Meshy's front, imports as Blender's -y):
    # motion is measured in the model's frame, the one the game moves him in (a diagonal run's hips face its way)
    yaws, ps, ends = [], [], []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        yaws.append(yaw_now())
        ps.append(wpos(HIPS).copy())
        ends.append([wpos(b).copy() for b in ENDS])
    # unwrap the yaw and see how far the body turned
    tot = [0.0]
    for i in range(1, len(yaws)):
        d = (yaws[i] - yaws[i - 1] + math.pi) % (2 * math.pi) - math.pi
        tot.append(tot[-1] + d)
    turn = tot[-1]
    length = (f1 - f0) / fps
    m = {"len": round(length, 3)}
    disp = ps[-1] - ps[0]
    m["fwd"] = round(disp.dot(fwd0) / max(length, 1e-3), 3)
    m["side"] = round(disp.dot(Vector((-fwd0.y, fwd0.x, 0.0)).normalized()) / max(length, 1e-3), 3)
    if nm in LOCO and abs(m["fwd"]) < 0.15 and abs(m["side"]) < 0.15:
        # in place: the foot on the ground slides back under the hips at the body's speed
        lf = [] ; left0 = Vector((-fwd0.y, fwd0.x, 0.0)).normalized()
        for i in range(1, len(ends)):
            k = 2 if ends[i][2].z < ends[i][3].z else 3
            v = ((ends[i][k] - ps[i]) - (ends[i - 1][k] - ps[i - 1])) * fps
            lf.append((-v.dot(fwd0), -v.dot(left0)))
        lf.sort(key=lambda x: x[0]); mf = lf[len(lf) // 2][0]
        lf.sort(key=lambda x: x[1]); ms = lf[len(lf) // 2][1]
        m["fwd"], m["side"], m["inplace"] = round(mf, 3), round(ms, 3), True
    if nm.startswith("turn") or nm.startswith("walk_turn"):
        m["turn"] = round(math.degrees(turn), 1)
        # take the yaw out: each frame the hips are turned back about their own vertical by the yaw so far
        HIPS.rotation_mode = "QUATERNION"
        for i, f in enumerate(range(f0, f1 + 1)):
            sc.frame_set(f)
            p = HIPS.head.copy()                       # armature space
            up = (W.inverted().to_3x3() @ Vector((0, 0, 1))).normalized()
            R = Matrix.Translation(p) @ Matrix.Rotation(-tot[i], 4, up) @ Matrix.Translation(-p)
            HIPS.matrix = R @ HIPS.matrix
            HIPS.keyframe_insert("rotation_quaternion", frame=f)
            HIPS.keyframe_insert("location", frame=f)
    if nm.startswith("strike"):
        # a blow lands when a hand or foot is at its farthest out in front of the hips
        reach = [max((ends[i][k] - ps[i]).dot(fwd0) for k in range(4)) for i in range(len(ends))]
        top = max(reach) if reach else 0.0
        low = min(reach) if reach else 0.0
        hits, last = [], -1e9
        for i in range(1, len(reach) - 1):
            back = reach[max(0, i - int(fps * 0.3)):i]
            thrust = reach[i] - min(back) if back else 0.0      # it came out fast, not a hand drifting about
            if reach[i] >= reach[i - 1] and reach[i] > reach[i + 1] and reach[i] > low + (top - low) * 0.72 \
                    and thrust > (top - low) * 0.35 and (i - last) / fps > 0.3:
                hits.append(round(i / max(1, len(reach) - 1), 3))
                last = i
        m["hits"] = hits or [0.45]
    meta[nm] = m
    print("clip %-16s %5.2fs fwd %5.2f side %5.2f%s%s" % (nm, length, m["fwd"], m["side"],
          (" turn %.0f" % m["turn"]) if "turn" in m else "", (" hits %s" % m["hits"]) if "hits" in m else ""))
arm.animation_data.action = None
for nm, ac in seen.items():
    tr = arm.animation_data.nla_tracks.new()
    tr.name = nm
    tr.strips.new(nm, int(ac.frame_range[0]), ac)
    tr.mute = True

bpy.context.view_layer.objects.active = body
cur = len(body.data.polygons)
if cur > TRIS:
    d = body.modifiers.new("dec", "DECIMATE"); d.ratio = TRIS / cur
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
print("faces", len(body.data.polygons))
for img in bpy.data.images:
    if img.size[0] > 2048:
        img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_image_format="JPEG", export_jpeg_quality=88)
json.dump(meta, open(OUT.rsplit(".", 1)[0] + ".json", "w"), indent=1, sort_keys=True)
print("EXPORTED", OUT)
