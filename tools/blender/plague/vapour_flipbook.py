# A low, rolling vapour (Pestilence Vial's pool, the plague's fumes): a Mantaflow smoke simulation rendered side-on
# into frames for a flipbook (assets/textures/fx/vapour.png via tools/fx_flipbook.sh). Grey-white density with alpha;
# the game tints it per mixture. Made the way tools/blender/fx/fire_flipbook.py makes fire (Quick Smoke's domain, a
# warm-up before recording, the turbulence drifting so it never repeats).
#   blender -b --python tools/blender/plague/vapour_flipbook.py -- <outdir> [res 64] [frames 36] [px 160]
import bpy, sys, os, math
a = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(a[0])
RES = int(a[1]) if len(a) > 1 else 64
FRAMES = int(a[2]) if len(a) > 2 else 36
PX = int(a[3]) if len(a) > 3 else 160
WARM = 40
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
# the source: a flat disc on the ground, as a pool breathes off its surface
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.3, location=(0, 0, 0.06))
src = bpy.context.active_object
src.scale = (1.0, 1.0, 0.18)
bpy.ops.object.transform_apply(scale=True)
src.select_set(True)
bpy.context.view_layer.objects.active = src
bpy.ops.object.quick_smoke(style="SMOKE")
dom = [o for o in bpy.data.objects if o != src and o.modifiers][0]
dom.location = (0, 0, 0.5)
dom.dimensions = (1.4, 1.4, 1.0)
ds = dom.modifiers[0].domain_settings
ds.resolution_max = RES
ds.use_adaptive_domain = False
ds.cache_type = "ALL"
for side in ["front", "back", "right", "left", "top"]:
    setattr(ds, "use_collision_border_" + side, False)
ds.use_collision_border_bottom = True
ds.use_noise = True
ds.noise_scale = 2
ds.noise_strength = 1.4
ds.vorticity = 0.25
ds.alpha = 0.2              # heavy: it barely rises
ds.beta = 0.6
ds.use_dissolve_smoke = True
ds.dissolve_speed = 30
ds.cache_directory = os.path.join(OUT, "cache")
ds.cache_frame_start = 1
ds.cache_frame_end = WARM + FRAMES + 1
fl = src.modifiers[0].flow_settings
fl.smoke_color = (1, 1, 1)
fl.density = 0.7
fl.temperature = 0.4
fl.use_initial_velocity = True
fl.velocity_normal = 0.35
src.hide_render = True
# a slow drift of turbulence so the curls never repeat
bpy.ops.object.effector_add(type="TURBULENCE", location=(0, 0, 0.3))
tb = bpy.context.active_object
tb.field.strength = 1.2
tb.field.size = 0.3
tb.field.flow = 0.4
tb.keyframe_insert("location", frame=1)
tb.location = (0.3, 0.2, 0.5)
tb.keyframe_insert("location", frame=WARM + FRAMES)
sc.frame_start = 1
sc.frame_end = WARM + FRAMES
bpy.context.view_layer.objects.active = dom
dom.select_set(True)
bpy.ops.fluid.bake_all()
print("VAPOUR baked")
# the look: pale density, lit softly, with alpha
mat = dom.active_material
nt = mat.node_tree
for n in list(nt.nodes):
    if n.type == "PRINCIPLED_VOLUME":
        n.inputs["Color"].default_value = (0.92, 0.92, 0.92, 1)
        n.inputs["Density"].default_value = 6.0
        n.inputs["Absorption Color"].default_value = (0.2, 0.2, 0.2, 1)
bpy.ops.object.camera_add(location=(0, -3.0, 1.2))
cam = bpy.context.active_object
cam.data.type = "ORTHO"
cam.data.ortho_scale = 1.25
cam.rotation_euler = (math.radians(70), 0, 0)
sc.camera = cam
bpy.ops.object.light_add(type="SUN")
bpy.context.active_object.data.energy = 3.5
bpy.context.active_object.rotation_euler = (math.radians(40), 0.3, 0.6)
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 24
sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.render.resolution_x = PX
sc.render.resolution_y = PX
sc.render.image_settings.color_mode = "RGBA"
for f in range(FRAMES):
    sc.frame_set(WARM + 1 + f)
    sc.render.filepath = os.path.join(OUT, "f_%03d.png" % f)
    bpy.ops.render.render(write_still=True)
print("VAPOUR done", FRAMES)
