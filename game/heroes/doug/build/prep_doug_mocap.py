# Builds Doug's mocap body (game/heroes/doug/body/doug.glb): the Meshy auto-rigged clown (24-bone
# humanoid, like the knight's, the ranger's and the plague doctor's) with Meshy library clips merged onto its one
# armature, decimated to a game budget and exported as one glb whose AnimationPlayer holds every clip by a clean
# name. The drumstick is a separate prop (game/heroes/doug/weapon/drumstick.glb), held in the grip.
#   blender -b --python prep_doug_mocap.py -- <rigged.glb> <out.glb> <tris> clips_a.glb clips_b.glb clips_c.glb
# Source tasks (Meshy): concept edit of Blaine's reference (doug_edit_1), image-to-3D 01a19a93-25ea-74fb-b108-43f4aa6e6d30,
# rig 01a19aba-b3af-76f3-9a9c-2299e32c2822; clips 0,30,14,16,12,559 / 421,239,516,397,506,384 / 219,97,128,88,42,59,174,184
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
RIG, OUT, TRIS, CLIPS = a[0], a[1], int(a[2]), a[3:]
# Meshy library names (as the glb carries them, lower-cased) -> the game's clip names
NAMES = {
    # locomotion and idles
    "idle": "idle", "idle_02": "combat_idle", "idle_03": "combat_idle", "casual_walk": "walk", "run_02": "run", "runfast": "run_fast",
    "sneaky_walk": "sneak",                          # Doppel-Doug: unseen, he tiptoes away
    # skills
    "over_shoulder_throw": "throw_pie",              # Cream Pie
    "crouch_pull_and_throw": "throw_peels",          # Banana Peels: a low fan toss
    "slide_light": "slide",                          # Pratfall Slide
    "360_power_spin_jump": "bounce",                 # Big Top Bounce: up off the trampoline
    "dive_down_and_land": "belly_flop",              # and down on them
    "quick_step_and_spin_dodge": "doppel",           # Doppel-Doug: the duck behind the confetti
    # the drumstick: his three-blow combo
    "right-hand_sword_slash": "smack", "right_hand_sword_slash": "smack", "left_slash": "backhand", "heavy_hammer_swing": "belly_bump",
    # flair and reactions
    "chest_pound_taunt": "taunt", "gentlemans_bow": "bow", "victory_cheer": "cheer",
    "face_punch_reaction": "hit", "shot_and_fall_forward": "death",
}
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
missing = sorted(set(NAMES.values()) - seen)
if missing:
    print("MISSING clips", missing)
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
