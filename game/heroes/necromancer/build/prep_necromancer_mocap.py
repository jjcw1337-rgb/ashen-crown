# Builds the Necromancer's mocap body (game/heroes/necromancer/body/necromancer.glb): the Meshy auto-rigged lich-priest
# (24-bone humanoid, like the knight's, the ranger's, the plague doctor's and Doug's) with Meshy library clips merged onto
# its one armature, decimated to a game budget and exported as one glb whose AnimationPlayer holds every clip by a clean
# name. His scythe-staff is a separate prop (game/heroes/necromancer/weapon/grave_scythe.glb), held in the grip.
#   blender -b --python prep_necromancer_mocap.py -- <rigged.glb> <out.glb> <tris> clips_a.glb clips_b.glb
# Source tasks (Meshy, jj's key, 2026-11-07): concepts (3 takes; jj's pick for the morning, take 2 built), edits to empty
# hands and no mist, image-to-3D 01a1b542-ee7b-7249-8321-6930e65ade97, rig 01a1b545-9366-70e2-b3e1-896c7d568fe1;
# clips 0,12,30,14,16,509,21,178,189,158 / 127,125,129,130,131,132,342.
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
RIG, OUT, TRIS, CLIPS = a[0], a[1], int(a[2]), a[3:]
# Meshy library names (as the glb carries them, lower-cased) -> the game's clip names
NAMES = {
    # locomotion, idles and reactions
    "idle": "idle", "idle_02": "combat_idle", "idle_03": "combat_idle", "casual_walk": "walk", "walk_fight_forward": "walk_fight",
    "run_02": "run", "runfast": "run_fast", "lean_forward_sprint": "sprint",
    "hit_reaction": "hit", "dying_backwards": "death", "roll_dodge": "roll",
    "stand_and_drink": "drink",
    # his spells
    "charged_ground_slam": "slam",                  # Graveyard: the staff driven into the ground
    "charged_spell_cast": "cast_charged",           # spare: a gathered cast
    "mage_soell_cast": "cast",                      # the staff's jab (his plain swing's first blow)
    "mage_soell_cast_1": "cast_quick",              # Bone Bolt: the hand flung forward
    "mage_soell_cast_2": "cast_sweep",              # the swing's second blow
    "mage_soell_cast_3": "cast_hard",               # the swing's third blow
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
