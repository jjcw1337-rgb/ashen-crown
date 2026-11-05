# Gives a Meshy camp keeper fists (jj, 2026-11-04: the smith "holds a piece of material hes working on"): Meshy's
# humanoid rig has no finger bones, so a held hammer or tongs sat in an open, spread hand. This adds two shape keys,
# fist_R and fist_L, that curl each hand's fingers into its palm (a bend from the knuckle line, everything past it
# rolled round a radius on the palm side) and fold the thumb across; Godot sets them (blend_shapes/fist_R) while the
# hand holds something. Animations are kept as they are (exported as NLA tracks like prep_npc.py).
#   blender -b --python tools/blender/npc/fist_keys.py -- <keeper.glb> <out.glb> [--palm -z] [--debug prefix]
import bpy, sys, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
PALM = argv[argv.index("--palm") + 1] if "--palm" in argv else "-z"
DEBUG = argv[argv.index("--debug") + 1] if "--debug" in argv else ""
KNUCKLE = 0.42      # of the hand's length along its bone: where the fingers start
CURL = math.radians(235.0)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
body = max((o for o in bpy.context.scene.objects if o.type == "MESH" and o.vertex_groups), key=lambda o: len(o.data.vertices))
if body.data.shape_keys is None:
    body.shape_key_add(name="Basis", from_mix=False)
pax = {"x": 0, "y": 1, "z": 2}[PALM[-1]]
psg = -1.0 if PALM.startswith("-") else 1.0

def fist(bn, key):
    b = arm.data.bones[bn]
    M = arm.matrix_world @ b.matrix_local
    Mi = M.inverted()
    W = body.matrix_world
    Wi = W.inverted()
    gi = body.vertex_groups[bn].index
    kb = body.shape_key_add(name=key, from_mix=False)
    vs = []
    for v in body.data.vertices:
        w = next((g.weight for g in v.groups if g.group == gi), 0.0)
        if w > 0.0:
            vs.append((v.index, w, Mi @ (W @ v.co)))
    full = [p for i, w, p in vs if w > 0.5]
    ymax = max(p.y for p in full)
    yk = ymax * KNUCKLE
    # the hand's mid-plane across its palm axis, from the part of it past the knuckles (the fingers)
    fing = [p for p in full if p.y > yk]
    z0 = sum(p[pax] for p in fing) / max(1, len(fing))
    L = ymax - yk
    k = CURL / L
    R = 1.0 / k
    # the thumb: the hand's verts below the knuckles that stand out furthest on the palm side
    th = [p for p in full if p.y < yk + L * 0.2 and psg * (p[pax] - z0) > 0.0]
    for i, w, p in vs:
        q = p.copy()
        zz = psg * (p[pax] - z0)
        if p.y > yk:
            s = p.y - yk
            t = min(k * s, CURL)
            extra = max(0.0, s - CURL / k)
            ny = yk + (R - zz) * math.sin(t)
            nz = R - (R - zz) * math.cos(t)
            # past the full curl, on along the tangent
            ny += extra * math.cos(t)
            nz += extra * math.sin(t)
            q.y = ny
            q[pax] = z0 + psg * nz
        elif zz > R * 0.6 and p.y > yk * 0.25:
            # the thumb folds in over the curled fingers
            ang = math.radians(35.0) * min(1.0, (zz - R * 0.6) / (R * 1.5))
            c = mathutils.Vector((0, yk * 0.25, z0))
            rel = q - c
            rot = mathutils.Matrix.Rotation(-ang * psg, 3, "X")
            q = c + rot @ rel
            q.y += (p.y - yk * 0.25) * 0.15 * ang
        d = q - p
        kb.data[i].co = Wi @ (M @ (p + d * w))

fist("RightHand", "fist_R")
fist("LeftHand", "fist_L")
print("FIST keys", [k.name for k in body.data.shape_keys.key_blocks])

if DEBUG:
    sc = bpy.context.scene
    arm.data.pose_position = "REST"
    b = arm.data.bones["RightHand"]
    M = arm.matrix_world @ b.matrix_local
    gi = body.vertex_groups["RightHand"].index
    hv = [body.matrix_world @ v.co for v in body.data.vertices if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
    c = sum(hv, mathutils.Vector()) / len(hv)
    print("FIST hand at", c, "bone says", M @ mathutils.Vector((0, 12, 0)))
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.lens = 45
    out = c - arm.matrix_world @ arm.data.bones["Spine02"].head_local
    out.z = 0
    out.normalize()
    cam.data.clip_end = 0.5
    for nm, off in (("out", out), ("front", mathutils.Vector((0, -1, 0))), ("back", mathutils.Vector((0, 1, 0))), ("under", mathutils.Vector((0, 0, -1)))):
        cam.location = c + off * 0.42
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        for kv in (0.0, 1.0):
            body.data.shape_keys.key_blocks["fist_R"].value = kv
            l = bpy.data.objects.get("l") or bpy.data.objects.new("l", bpy.data.lights.new("l", "SUN"))
            if l.name not in sc.collection.objects:
                sc.collection.objects.link(l)
            l.data.energy = 4
            sc.world = sc.world or bpy.data.worlds.new("w")
            sc.world.color = (0.4, 0.4, 0.4)
            sc.render.engine = "BLENDER_EEVEE_NEXT"
            sc.render.resolution_x = sc.render.resolution_y = 500
            sc.render.filepath = "%s_%s_%d.png" % (DEBUG, nm, int(kv))
            bpy.ops.render.render(write_still=True)
    body.data.shape_keys.key_blocks["fist_R"].value = 0.0
    arm.data.pose_position = "POSE"

if arm.animation_data is None:
    arm.animation_data_create()
for tr in list(arm.animation_data.nla_tracks):
    arm.animation_data.nla_tracks.remove(tr)
for a in bpy.data.actions:
    if a.id_root not in ("OBJECT", None) and a.id_root != "OBJECT":
        continue
    if any(fc.data_path.startswith("key_blocks") for fc in a.fcurves):
        continue
    tr = arm.animation_data.nla_tracks.new()
    tr.name = a.name
    tr.strips.new(a.name, int(a.frame_range[0]), a)
    tr.mute = True
arm.animation_data.action = None
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_skins=True, export_animations=True,
                          export_morph=True, export_animation_mode="NLA_TRACKS", export_image_format="JPEG", export_jpeg_quality=86)
print("FIST", OUT)
