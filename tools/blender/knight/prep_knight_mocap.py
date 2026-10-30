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
for img in bpy.data.images:
    if img.size[0] > 2048:
        img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_image_format="JPEG", export_jpeg_quality=88)
print("EXPORTED", OUT)
