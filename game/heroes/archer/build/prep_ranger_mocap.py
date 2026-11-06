# Builds the archer's mocap body (game/heroes/archer/body/archer_ranger.glb): the Meshy auto-rigged northern ranger
# (24-bone humanoid, like the knight's) with Meshy library clips merged onto its one armature (bow clips
# included: the aimed walk, the archery shot, a hit reaction with the bow), decimated to a game budget and
# exported as one glb whose AnimationPlayer holds every clip by a clean name. Same steps as the knight's
# tools/blender/knight/prep_knight_mocap.py, without the knight's cloak and scabbard.
#   blender -b --python prep_ranger_mocap.py -- <rigged.glb> <out.glb> <tris> <clips.glb> [<clips.glb> ...]
# Meshy: rig task 01a18daf-9298-7071-8ac4-201a57eb6b99; clips_a 0,30,14,16,509,228,231,224,222,150; clips_b
# 189,158,98,230; clips_c 223,229,225,226,227,234,690 (task 01a1987d-29e6-717e-bb8b-cc284635ef0a, 21 credits)
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
RIG, OUT, TRIS, CLIPS = a[0], a[1], int(a[2]), a[3:]
# Meshy library names (with spaces or underscores, as the glb carries them) -> the game's clip names
NAMES = {"idle": "idle", "casual_walk": "walk", "run_02": "run", "run_2": "run", "runfast": "run_fast", "run_fast": "run_fast",
         "lean_forward_sprint": "sprint", "lean_forward_sprint_inplace": "sprint",
         "walk_forward_with_bow_aimed": "walk_aim", "archery_aim_with_lateral_scan": "combat_idle",
         "archery_shot": "shoot", "draw_and_shoot_from_back": "shoot_back", "hit_reaction_with_bow": "hit",
         "dying_backwards": "death", "roll_dodge": "roll", "run_and_shoot": "run_shoot",
         "walk_backward_with_bow_aimed": "walk_back",
         # the quick shot (Meshy 225 "Archery Shot 1": reach over the shoulder, nock, draw to the cheek, 1 s; and 227
         # "Archery Shot 3": the loose, the string hand flung back, back to the ready stance, 0.67 s), joined below
         # into "shoot_quick". (Compared and left out: 223/229 are near copies of 222/224, 226 only holds the aim, and
         # 234/690 "Walk Forward While Shooting" hold a half draw the whole way and never loose.)
         "archery_shot_1": "shoot1", "archery_shot_3": "shoot3"}
def key(n):
    n = n.split("|")[-1].strip().lower().replace(" ", "_")
    return n
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
n = 0
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
    n += 1
# Archery Shot 3 starts on Archery Shot 1's last pose: one action, the draw then the loose
if "shoot1" in seen and "shoot3" in seen:
    a1, a3 = bpy.data.actions["shoot1"], bpy.data.actions["shoot3"]
    off = a1.frame_range[1] - a3.frame_range[0]
    q = a1.copy()
    q.name = "shoot_quick"
    for fc in q.fcurves:
        src = a3.fcurves.find(fc.data_path, index=fc.array_index)
        if src is None:
            continue
        for kp in src.keyframe_points:
            if kp.co[0] <= a3.frame_range[0]:
                continue
            fc.keyframe_points.insert(kp.co[0] + off, kp.co[1], options={"FAST"})
        fc.update()
    for nm_ in ("shoot1", "shoot3"):
        for tr in list(arm.animation_data.nla_tracks):
            if tr.name == nm_:
                arm.animation_data.nla_tracks.remove(tr)
        bpy.data.actions.remove(bpy.data.actions[nm_])
        seen.discard(nm_)
    q.use_fake_user = True
    tr = arm.animation_data.nla_tracks.new()
    tr.name = "shoot_quick"
    tr.strips.new("shoot_quick", int(q.frame_range[0]), q)
    tr.mute = True
    seen.add("shoot_quick")
    print("shoot_quick", q.frame_range[:])
print("clips", len(seen), sorted(seen))
# the bow Meshy fused into his right hand goes (he holds the game's own bows, in his left hand, as the bow clips do)
import os
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "bow_select.py")).read())
sel = bow_verts(body, arm)
import bmesh
bm = bmesh.new()
bm.from_mesh(body.data)
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.verts[i] for i, s_ in enumerate(sel) if s_], context="VERTS")
# and any small scrap left floating (vertices on the same spot count as joined: Meshy splits along UV seams)
bm.verts.ensure_lookup_table()
twins = {}
for v in bm.verts:
    twins.setdefault(tuple(round(c, 4) for c in v.co), []).append(v.index)
seen = set()
scraps = []
for v in bm.verts:
    if v.index in seen:
        continue
    comp = [v.index]
    seen.add(v.index)
    k = 0
    while k < len(comp):
        u = bm.verts[comp[k]]
        k += 1
        nb = [e.other_vert(u).index for e in u.link_edges] + twins[tuple(round(c, 4) for c in u.co)]
        for j in nb:
            if j not in seen:
                seen.add(j)
                comp.append(j)
    if len(comp) < 400:
        scraps += comp
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in scraps], context="VERTS")
bm.to_mesh(body.data)
bm.free()
print("bow removed:", sum(sel), "vertices; scraps:", len(scraps))
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
print("EXPORTED", OUT)
