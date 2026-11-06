# Contact sheet of the plague doctor's clips: for each clip, frames at fractions of its length, seen from 3/4 front
# (or any yaw), rendered with Workbench (textures, studio light) so deformation problems show.
#   xvfb-run -a blender -b --python clip_sheet.py -- <mocap.glb> <outdir> <clip,clip,...> [fractions] [yaw_deg]
import bpy, sys, os, math
a = sys.argv[sys.argv.index("--") + 1:]
GLB, OUT, CLIPS = a[0], a[1], a[2].split(",")
FRACS = [float(x) for x in a[3].split(",")] if len(a) > 3 else [0.0, 0.25, 0.5, 0.75]
YAW = math.radians(float(a[4])) if len(a) > 4 else math.radians(35)
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.show_shadows = True
RES = int(os.environ.get("SHEET_RES", "384"))
sc.render.resolution_x = RES
sc.render.resolution_y = RES * 4 // 3
sc.view_settings.exposure = 1.6
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w")
sc.world.color = (0.18, 0.18, 0.2)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 50
d = 5.2
cam.location = (math.sin(YAW) * d, -math.cos(YAW) * d, 1.15)
cam.rotation_euler = (math.radians(86), 0, YAW)
arm.animation_data_create()
for tr in arm.animation_data.nla_tracks:
    tr.mute = True
for c in CLIPS:
    ac = bpy.data.actions.get(c)
    if ac is None:
        print("no clip", c)
        continue
    arm.animation_data.action = ac
    f0, f1 = ac.frame_range
    for i, fr in enumerate(FRACS):
        f = f0 + (f1 - f0) * fr
        sc.frame_set(int(f), subframe=f - int(f))
        hp = arm.matrix_world @ arm.pose.bones["Hips"].head   # follow the hips (library clips walk about)
        cam.location = (hp.x + math.sin(YAW) * d, hp.y - math.cos(YAW) * d, 1.15)
        sc.render.filepath = os.path.join(OUT, f"{c}_{i}.png")
        bpy.ops.render.render(write_still=True)
print("DONE")
