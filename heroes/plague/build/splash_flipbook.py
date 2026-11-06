# Pestilence Vial's splash: a real FLIP liquid simulation of a burst vial's contents hitting the ground (a crown,
# fingers, droplets flung out), rendered side-on into frames for a flipbook (heroes/plague/skills/pestilence_vial/vial_splash.png,
# packed by tools/fx_flipbook.sh). The liquid renders as glossy green with alpha (film transparent), so the game
# blends it normally.
#   blender -b --python heroes/plague/build/splash_flipbook.py -- <outdir> [res 64] [frames 36] [px 192] [seed 3]
# RENDER_ONLY=1 reuses the bake in <outdir>/cache. KIND=wave makes The Last Experiment's burst instead: the vat's
# whole column of fluid (0.42 m across, 1 m tall) let go at once with a ring of gobbets thrown out by the glass,
# collapsing into a wave that rolls out across the ground (heroes/plague/skills/last_experiment/vat_wave.png).
import bpy, sys, os, math, random
KIND = os.environ.get("KIND", "splash")
WAVE = KIND == "wave"
K = 2.4 if WAVE else 1.0      # the wave's scene is this much bigger
a = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(a[0])
RES = int(a[1]) if len(a) > 1 else 64
FRAMES = int(a[2]) if len(a) > 2 else 36
PX = int(a[3]) if len(a) > 3 else 192
SEED = int(a[4]) if len(a) > 4 else 3
random.seed(SEED)
os.makedirs(OUT, exist_ok=True)
START = 1
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# the domain: 1.6 x 1.6 x 0.8 m over the floor
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0.45 * K))
dom = bpy.context.active_object
dom.name = "domain"
dom.scale = (1.8 * K, 1.8 * K, 0.9 * K)
bpy.ops.object.transform_apply(scale=True)
m = dom.modifiers.new("fluid", "FLUID")
m.fluid_type = "DOMAIN"
ds = m.domain_settings
ds.domain_type = "LIQUID"
ds.resolution_max = RES
ds.cache_directory = os.path.join(OUT, "cache")
ds.cache_frame_start = START
ds.cache_frame_end = START + FRAMES + 2
ds.cache_type = "ALL"
ds.use_mesh = True
ds.mesh_scale = 2
ds.mesh_particle_radius = 2.2
ds.mesh_smoothen_pos = 3
ds.mesh_smoothen_neg = 1
ds.use_spray_particles = False
ds.use_collision_border_front = False
ds.use_collision_border_back = False
ds.use_collision_border_left = False
ds.use_collision_border_right = False
ds.use_collision_border_bottom = True
ds.use_collision_border_top = False
ds.surface_tension = 0.02
ds.timesteps_max = 12
ds.cfl_condition = 2.0
ds.time_scale = 0.45 if not WAVE else 0.6     # slow motion: more frames of the crown in the flipbook

# the liquid: the vial's contents at the moment the glass bursts on the ground: a core falling onto the spot and
# a ring of gobbets thrown out and up (each its own flow object with its own velocity; per-normal initial velocity
# is ignored for geometry flows in a background bake)
def gob(name, loc, r, vel):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=16, ring_count=8)
    o = bpy.context.active_object
    o.name = name
    fm = o.modifiers.new("fluid", "FLUID")
    fm.fluid_type = "FLOW"
    fs = fm.flow_settings
    fs.flow_type = "LIQUID"
    fs.flow_behavior = "GEOMETRY"
    fs.use_initial_velocity = True
    fs.velocity_coord = vel
    o.hide_render = True
    return o
if WAVE:
    # the vat's column of fluid, standing where the glass was, and the glass bursting outward throws gobbets
    bpy.ops.mesh.primitive_cylinder_add(radius=0.42, depth=1.0, location=(0, 0, 0.52), vertices=32)
    col = bpy.context.active_object
    col.name = "column"
    cf = col.modifiers.new("fluid", "FLUID")
    cf.fluid_type = "FLOW"
    cf.flow_settings.flow_type = "LIQUID"
    cf.flow_settings.flow_behavior = "GEOMETRY"
    cf.flow_settings.use_initial_velocity = True
    cf.flow_settings.velocity_coord = (0.0, 0.0, -0.3)
    col.hide_render = True
    for i in range(18):
        t = 2 * math.pi * i / 18 + random.uniform(-0.12, 0.12)
        z = random.uniform(0.2, 0.95)
        out = random.uniform(2.5, 4.5)
        gob("burst%d" % i, (math.cos(t) * 0.44, math.sin(t) * 0.44, z), random.uniform(0.06, 0.1),
            (math.cos(t) * out, math.sin(t) * out, random.uniform(0.8, 2.6)))
gob("core", (0, 0, 0.14), 0.1, (0.0, 0.0, -2.5))
N = 14 if not WAVE else 0
for i in range(N):
    t = 2 * math.pi * i / N + random.uniform(-0.15, 0.15)
    rr = random.uniform(0.07, 0.11)
    out = random.uniform(2.2, 3.6)
    up = random.uniform(1.4, 3.0)
    gob("gob%d" % i, (math.cos(t) * 0.12, math.sin(t) * 0.12, 0.12), random.uniform(0.035, 0.055),
        (math.cos(t) * out, math.sin(t) * out, up))
for i in range(8 if not WAVE else 0):
    t = random.uniform(0, 2 * math.pi)
    gob("spit%d" % i, (math.cos(t) * 0.06, math.sin(t) * 0.06, 0.2), random.uniform(0.02, 0.03),
        (math.cos(t) * random.uniform(0.8, 1.6), math.sin(t) * random.uniform(0.8, 1.6), random.uniform(3.0, 4.2)))
# (a thin film on the ground was tried: at a game-sized grid it breaks into noise)

sc.frame_start = START
sc.frame_end = START + FRAMES
if not os.environ.get("RENDER_ONLY"):
    bpy.context.view_layer.objects.active = dom
    dom.select_set(True)
    bpy.ops.fluid.bake_all()
    print("SPLASH baked")

# the look: glossy, thick, sickly green with a little glow; the domain mesh is the liquid surface
mat = bpy.data.materials.new("liquid")
mat.use_nodes = True
nt = mat.node_tree
b = nt.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.035, 0.085, 0.012, 1)
b.inputs["Roughness"].default_value = 0.05
b.inputs["Transmission Weight"].default_value = 0.25
b.inputs["IOR"].default_value = 1.4
b.inputs["Subsurface Weight"].default_value = 0.4
b.inputs["Subsurface Radius"].default_value = (0.4, 1.0, 0.2)
b.inputs["Emission Color"].default_value = (0.3, 0.85, 0.1, 1)
b.inputs["Emission Strength"].default_value = 0.18
dom.data.materials.append(mat)

# camera: orthographic, side-on, a little from above (as the game camera sees the splash)
bpy.ops.object.camera_add(location=(0, -2.6 * K, 1.9 * K))
cam = bpy.context.active_object
cam.data.type = "ORTHO"
cam.data.ortho_scale = 2.0 * K
cam.rotation_euler = (math.radians(55), 0, 0)
sc.camera = cam
bpy.ops.object.light_add(type="AREA", location=(1.0 * K, -1.2 * K, 2.0 * K))
bpy.context.active_object.data.energy = 120 * K * K
bpy.context.active_object.data.size = 1.5 * K
bpy.ops.object.light_add(type="POINT", location=(-1.0 * K, 1.0 * K, 0.6 * K))
bpy.context.active_object.data.energy = 40 * K * K
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.04, 0.05, 0.04, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.25
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 32
sc.cycles.use_denoising = True
sc.render.film_transparent = True
sc.render.resolution_x = PX
sc.render.resolution_y = PX
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
for f in range(START, START + FRAMES):
    sc.frame_set(f)
    sc.render.filepath = os.path.join(OUT, "f_%03d.png" % (f - START))
    bpy.ops.render.render(write_still=True)
print("SPLASH done", FRAMES, "frames")
