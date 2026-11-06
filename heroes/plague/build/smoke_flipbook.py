# The Plague Doctor's gas flipbooks from Mantaflow smoke simulations (the way tools/blender/fx/fire_flipbook.py makes
# fire: Blender's Quick Smoke domain reshaped, open borders but the floor, a drifting turbulence field), rendered from
# the game camera's angle with alpha, then packed with ffmpeg's tile filter:
#   spore  Corpse Bloom's pulse: a burst of spores thrown up off the bloom's sacs and drifting apart (one shot)
#   fog    one heavy pale puff pushed down onto the floor so it rolls out across the ground and thins (one shot;
#          dust and impact rolls)
#   wisp   Fog of the Forgotten's body: a long, flat, heavy bank of fog torn by turbulence into wisps as it spreads
#          over the floor; recorded late (`skip`), when it is wide and ragged rather than a ball, for fog sprites
#   blender -b --python heroes/plague/build/smoke_flipbook.py -- <kind> <outdir> [res] [frames] [px]
# Pack the frames with tools/flipbook_pack.py (crops to what the smoke fills, then tiles).
import bpy, sys, os, math
a = sys.argv[sys.argv.index("--") + 1:]
KIND = a[0]
OUT = os.path.abspath(a[1])
P = {
	"spore": {"res": 72, "frames": 24, "px": 192, "warm": 0, "dom": (1.8, 1.8, 2.2), "domz": 1.1,
		"src_r": 0.16, "src_z": 0.75, "src_sz": 1.0, "vel": (0.0, 0.0, 2.2), "normal": 1.6, "density": 1.2,
		"alpha": 0.4, "beta": 0.8, "vort": 0.35, "noise": 1.6, "dissolve": 22, "burst": 5,
		"col": (0.86, 0.95, 0.62), "dens_mul": 7.0, "cam_scale": 2.1, "cam_z": 1.0, "turb": 1.4},
	"fog": {"res": 72, "frames": 32, "px": 192, "warm": 0, "dom": (2.4, 2.4, 1.2), "domz": 0.58,
		"src_r": 0.28, "src_z": 0.3, "src_sz": 0.8, "vel": (0.0, 0.0, -0.5), "normal": 1.2, "density": 1.2,
		"alpha": 0.02, "beta": 0.12, "vort": 0.45, "noise": 2.0, "dissolve": 40, "burst": 8,
		"col": (0.86, 0.85, 0.92), "dens_mul": 6.0, "cam_scale": 2.3, "cam_z": 0.35, "turb": 1.6},
	"wisp": {"res": 84, "frames": 32, "px": 224, "warm": 26, "dom": (3.4, 3.4, 1.2), "domz": 0.58,
		"src_r": 0.5, "src_z": 0.22, "src_sz": 0.3, "src_sx": 1.9, "vel": (0.0, 0.0, -0.25), "normal": 1.1, "density": 1.4,
		"alpha": 0.015, "beta": 0.08, "vort": 0.8, "noise": 2.6, "dissolve": 70, "burst": 14,
		"col": (0.86, 0.85, 0.92), "dens_mul": 6.0, "cam_scale": 3.0, "cam_z": 0.3, "turb": 2.4, "turb_size": 0.28},
}[KIND]
RES = int(a[2]) if len(a) > 2 else P["res"]
FRAMES = int(a[3]) if len(a) > 3 else P["frames"]
PX = int(a[4]) if len(a) > 4 else P["px"]
WARM = P["warm"]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=P["src_r"], location=(0, 0, P["src_z"]))
src = bpy.context.active_object
src.scale = (P.get("src_sx", 1.0), 1.0, P["src_sz"])
bpy.ops.object.transform_apply(scale=True)
src.select_set(True)
bpy.context.view_layer.objects.active = src
bpy.ops.object.quick_smoke(style="SMOKE")
dom = [o for o in bpy.data.objects if o != src and o.modifiers][0]
dom.location = (0, 0, P["domz"])
dom.dimensions = P["dom"]
ds = dom.modifiers[0].domain_settings
ds.resolution_max = RES
ds.use_adaptive_domain = False
ds.cache_type = "ALL"
for side in ["front", "back", "right", "left", "top"]:
	setattr(ds, "use_collision_border_" + side, False)
ds.use_collision_border_bottom = True
ds.use_noise = True
ds.noise_scale = 2
ds.noise_strength = P["noise"]
ds.vorticity = P["vort"]
ds.alpha = P["alpha"]
ds.beta = P["beta"]
ds.use_dissolve_smoke = True
ds.dissolve_speed = P["dissolve"]
ds.cache_directory = os.path.join(OUT, "cache")
ds.cache_frame_start = 1
ds.cache_frame_end = WARM + FRAMES + 1
fl = src.modifiers[0].flow_settings
fl.smoke_color = (1, 1, 1)
fl.temperature = 0.6
fl.use_initial_velocity = True
fl.velocity_coord = P["vel"]
fl.velocity_normal = P["normal"]
fl.density = P["density"]
if P["burst"] > 0:
	# one shot: the sacs burst for a few frames, then nothing more comes out
	fl.keyframe_insert("density", frame=1)
	fl.keyframe_insert("density", frame=P["burst"])
	fl.density = 0.0
	fl.keyframe_insert("density", frame=P["burst"] + 1)
src.hide_render = True
bpy.ops.object.effector_add(type="TURBULENCE", location=(0, 0, P["src_z"] + 0.2))
tb = bpy.context.active_object
tb.field.strength = P["turb"]
tb.field.size = P.get("turb_size", 0.35)
tb.field.flow = 0.4
tb.keyframe_insert("location", frame=1)
tb.location = (0.35, 0.25, P["src_z"] + 0.5)
tb.keyframe_insert("location", frame=WARM + FRAMES)
sc.frame_start = 1
sc.frame_end = WARM + FRAMES
bpy.context.view_layer.objects.active = dom
dom.select_set(True)
bpy.ops.fluid.bake_all()
print("SMOKE baked", KIND)
mat = dom.active_material
for n in list(mat.node_tree.nodes):
	if n.type == "PRINCIPLED_VOLUME":
		n.inputs["Color"].default_value = (*P["col"], 1)
		n.inputs["Density"].default_value = P["dens_mul"]
		n.inputs["Absorption Color"].default_value = (0.25, 0.25, 0.25, 1)
# the game camera's angle: from above at ~55 degrees
bpy.ops.object.camera_add(location=(0, -3.2, P["cam_z"] + 2.6))
cam = bpy.context.active_object
cam.data.type = "ORTHO"
cam.data.ortho_scale = P["cam_scale"]
cam.rotation_euler = (math.radians(52), 0, 0)
cam.location = (0, -math.sin(math.radians(52)) * 4.0, P["cam_z"] + math.cos(math.radians(52)) * 4.0)
sc.camera = cam
bpy.ops.object.light_add(type="SUN")
bpy.context.active_object.data.energy = 3.2
bpy.context.active_object.rotation_euler = (math.radians(35), 0.3, 0.7)
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
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
print("SMOKE done", KIND, FRAMES)
