# Gives a camp keeper (a Meshy rigged character, assets/models/npc/<name>.glb) more Meshy library clips (jj, 2026-11-04:
# "30 different movements and gestures for each merchant"): the clips are animated once on any Meshy rig (meshy.py
# animate) and moved onto the keeper here. Every Meshy humanoid rig has the same 24 bones with the same rest frames, so
# a clip's rotations go across bone for bone; the hips' travel is scaled by the two rigs' hip heights. The keeper's
# own clips are kept. Each clip is exported as its own glTF animation, like prep_npc.py.
#   blender -b --python tools/blender/npc_add_clips.py -- <keeper.glb> <out.glb> <names,...|all> <clips.glb> [<clips.glb> ...] [--keep]
# names: the clip names to take (as the clips glb carries them, e.g. Idle_3,Shrug); "all" takes every one.
import bpy, sys

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, NAMES = argv[0], argv[1], argv[2]
KEEP = "--keep" in argv            # keep every mesh and the textures' full size (the guards' armour)
CLIPS = [a for a in argv[3:] if a != "--keep"]
want = None if NAMES == "all" else set(NAMES.split(","))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.context.scene.objects):
    if not KEEP and o.type == "MESH" and (len(o.vertex_groups) == 0 or len(o.data.polygons) < 500):
        bpy.data.objects.remove(o, do_unlink=True)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
own = set(a.name for a in bpy.data.actions)
hips_h = arm.data.bones["Hips"].head_local.z

added = []
for path in CLIPS:
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    src_arm = next((o for o in bpy.data.objects if o not in before and o.type == "ARMATURE"), None)
    k = 1.0
    if src_arm is not None and "Hips" in src_arm.data.bones:
        k = hips_h / max(src_arm.data.bones["Hips"].head_local.z, 1e-6)
    for a in list(bpy.data.actions):
        if a in acts_before:
            continue
        nm = a.name
        # (the glTF importer names actions "<clip>" or "<clip>_<armature>")
        base = nm.split("_Armature")[0]
        if len(base) > 4 and base[-4] == "." and base[-3:].isdigit():
            base = base[:-4]           # (a name the keeper already has: Blender made it "<clip>.001")
        if want is not None and base not in want:
            bpy.data.actions.remove(a)
            continue
        if base in own:
            bpy.data.actions.remove(a)
            continue
        a.name = base
        for fc in a.fcurves:
            if fc.data_path == 'pose.bones["Hips"].location':
                for kp in fc.keyframe_points:
                    kp.co.y *= k
                    kp.handle_left.y *= k
                    kp.handle_right.y *= k
        own.add(base)
        added.append(base)
    for o in list(bpy.data.objects):
        if o not in before:
            bpy.data.objects.remove(o, do_unlink=True)

for img in bpy.data.images:
    if not KEEP and img.size[0] > 1024:
        img.scale(1024, 1024)
if arm.animation_data is None:
    arm.animation_data_create()
for tr in list(arm.animation_data.nla_tracks):
    arm.animation_data.nla_tracks.remove(tr)
for a in bpy.data.actions:
    tr = arm.animation_data.nla_tracks.new()
    tr.name = a.name
    tr.strips.new(a.name, int(a.frame_range[0]), a)
    tr.mute = True
arm.animation_data.action = None
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_skins=True, export_animations=True,
                          export_animation_mode="NLA_TRACKS", export_image_format="JPEG", export_jpeg_quality=86)
print("CLIPS", OUT, len(bpy.data.actions), "added", len(added), sorted(added))
