# Builds the Plague Doctor's mocap body (assets/models/plague_doctor.glb): the Meshy auto-rigged plague doctor
# (24-bone humanoid, like the knight's and the ranger's) with Meshy library clips merged onto its one armature,
# decimated to a game budget and exported as one glb whose AnimationPlayer holds every clip by a clean name.
# Same steps as heroes/archer/build/prep_ranger_mocap.py (no weapon to cut: the concept had empty hands).
#   blender -b --python prep_plague_mocap.py -- <rigged.glb> <out.glb> <tris> clips_a.glb clips_b.glb clips_c.glb clips_d.glb
# Source tasks (Meshy): image-to-3D 01a191d9-dfec-77ab-90e2-4853b2c02bc4 (concept 1), rig 01a191dc-4fd3-7584-82b8-dd7321ff498c,
# clips 0,30,14,16,509,12,342,178,189,158 / 421,398,274,365,127,125,572,571,113,21 / 219,240,97,389,239,131
# (219, 240, 97: the first cane combo, replaced) / cane 221, 242, 128 (with 4, 237, 99, 102, 92 tried and left out).
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
RIG, OUT, TRIS, CLIPS = a[0], a[1], int(a[2]), a[3:]
# Meshy library names (as the glb carries them, lower-cased) -> the game's clip names
NAMES = {
    # locomotion and idles
    "idle": "idle", "idle_03": "combat_idle", "casual_walk": "walk", "walk_fight_forward": "walk_fight",
    "run_02": "run", "runfast": "run_fast", "lean_forward_sprint": "sprint",
    "walk_turn_left": "turn_walk", "run_turn_left": "turn_run",
    "stand_and_drink": "inspect",                   # the idle fidget: a vial held up to the light
    # reactions
    "hit_reaction": "hit", "mummy_stagger": "stagger", "roll_dodge": "roll", "dying_backwards": "death",
    # the cane: his own three-blow combo (clips_d: 221, 242, 128)
    "charged_upward_slash": "peck",                 # 1 Crow's Peck: low, hooked, rising with the crow-skull handle
    "charged_slash": "flick",                       # 2 Vial Flick: the wide side-arm swing that flings the drops
    "heavy_hammer_swing": "censer_slam",            # 3 Censer Slam: overhead, both hands, driven into the ground
    # skills
    "over_shoulder_throw": "throw_flask",           # Toxic Flask
    "crouch_charge_and_throw": "throw_volatile",    # Volatile Mixture
    "female_crouch_pick_up_place_side": "place_trap",  # Pestilent Trap
    "kneel_on_one_knee_and_stand": "kneel",         # The Last Epidemic: stage 1
    "charged_ground_slam": "slam",                  # stage 2: the censer smashed
    "charged_spell_cast": "cast_charged",           # stage 3: the dome raised
    "mage_soell_cast_2": "cast",                    # spare cast
    "grip_and_throw_down": "throw_down", "crouch_pull_and_throw": "throw_crouch",  # spare throws
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
