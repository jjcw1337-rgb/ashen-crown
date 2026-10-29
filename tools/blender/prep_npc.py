# Cleans up a Meshy rigged + animated character (meshy.py rig / animate) for the game: drops stray
# helper meshes (Meshy's files carry an icosphere), shrinks textures, and re-exports the armature,
# skinned mesh and every animation clip as one glb. Clip names are kept (Idle, Heavy_Hammer_Swing...).
#   blender -b --python prep_npc.py -- in.glb out.glb [texture px]
import bpy, sys
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
TEX = int(argv[2]) if len(argv) > 2 else 1024
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.context.scene.objects):
    if o.type == "MESH" and (len(o.vertex_groups) == 0 or len(o.data.polygons) < 500):
        bpy.data.objects.remove(o, do_unlink=True)
for img in bpy.data.images:
    if img.size[0] > TEX:
        img.scale(TEX, TEX)
arm = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
# every clip as its own glTF animation
if arm.animation_data is None:
    arm.animation_data_create()
for a in bpy.data.actions:
    tr = arm.animation_data.nla_tracks.new(); tr.name = a.name
    st = tr.strips.new(a.name, int(a.frame_range[0]), a)
    tr.mute = True
arm.animation_data.action = None
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_skins=True, export_animations=True,
                          export_animation_mode="NLA_TRACKS", export_image_format="JPEG", export_jpeg_quality=86)
print("NPC", OUT, [a.name for a in bpy.data.actions], [o.name for o in bpy.context.scene.objects])
