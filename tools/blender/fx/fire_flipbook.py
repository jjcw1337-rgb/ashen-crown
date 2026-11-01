"""Simulates a real fire with Mantaflow and renders it as flipbook frames for the game's flames (InfernalFx).

    blender -b --python tools/blender/fx/fire_flipbook.py -- <outdir> [res] [frames] [px] [seed]

A small fuel source at the foot of a tall gas domain burns with vorticity and noise, buffeted by a turbulence
field, so the tongues lick, pinch off and tear away as real flames do. Rendered side-on with an orthographic
camera in Cycles: the flame's light (a black-body ramp of its temperature) on black in RGB, the smoke's density as
alpha, ready to be used premultiplied (light adds, soot darkens). Writes <outdir>/fire_NNN.png for the frames after
the fire has settled; tools/fx_flipbook.sh packs them into an atlas.
"""
import bpy
import sys
import os

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/fire"
RES = int(argv[1]) if len(argv) > 1 else 96
FRAMES = int(argv[2]) if len(argv) > 2 else 64
PX = int(argv[3]) if len(argv) > 3 else 256
SEED = int(argv[4]) if len(argv) > 4 else 3
WARM = 76            # frames for the fire to rise and settle before recording
# FIRE_KIND: body (a full fire: campfires, braziers), tongue (a tall thin flame: torches, weapons, burning foes),
# spread (low and wide: burning ground, buildings), spirit (the waypoint's blue spirit-fire: the body fire a little
# wider and calmer, no soot, rendered violet / electric blue / cyan-white). Each sets the domain, the fuel and the framing.
KIND = os.environ.get("FIRE_KIND", "body")
SHAPE = {
    # domain (x, y, z) m, fuel radius, fuel scale, fuel height, camera (ortho, centre z), frame aspect (w / h)
    "body":   {"dom": (0.9, 0.3, 1.8), "r": 0.095, "fs": (1.7, 0.45, 0.55), "fz": 0.1, "cam": (1.15, 0.56), "aspect": 0.5},
    "tongue": {"dom": (0.5, 0.2, 1.6), "r": 0.05, "fs": (1.0, 1.0, 0.8), "fz": 0.08, "cam": (1.1, 0.53), "aspect": 0.5},
    "spread": {"dom": (1.8, 0.35, 1.0), "r": 0.1, "fs": (7.0, 0.6, 0.35), "fz": 0.06, "cam": (1.6, 0.38), "aspect": 2.0},
    "spirit": {"dom": (0.9, 0.3, 1.8), "r": 0.095, "fs": (1.9, 0.45, 0.5), "fz": 0.1, "cam": (1.15, 0.56), "aspect": 0.5},
}[KIND]
SPIRIT = KIND == "spirit"
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.frame_start = 1
scn.frame_end = WARM + FRAMES
scn.render.fps = 30

# --- the fuel (a lumpy little bed at the foot) and its domain, made by Blender's own Quick Smoke (a domain built
# by hand never took up the flow in a background bake), then reshaped: 0.9 x 0.3 x 1.8 m, open but for the floor
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=SHAPE["r"], location=(0, 0, SHAPE["fz"]))
src = bpy.context.object
src.name = "Fuel"
src.scale = SHAPE["fs"]            # (body: a line of fuel, thin in depth: separate tongues)
bpy.ops.object.transform_apply(scale=True)
src.select_set(True)
bpy.context.view_layer.objects.active = src
bpy.ops.object.quick_smoke(style="BOTH")
dom = [o for o in bpy.data.objects if o != src and o.modifiers][0]
dom.name = "Domain"
dom.location = (0, 0, SHAPE["dom"][2] * 0.5)
dom.dimensions = SHAPE["dom"]      # a thin slab: seen side-on the fire is a sheet with dark gaps, not a solid mass
mod = dom.modifiers[0]
ds = mod.domain_settings
ds.resolution_max = RES
ds.use_adaptive_domain = False
ds.cache_type = "ALL"
ds.cache_directory = os.path.join(OUT, "cache")
ds.cache_frame_start = 1
ds.cache_frame_end = WARM + FRAMES
ds.use_collision_border_front = False
ds.use_collision_border_back = False
ds.use_collision_border_right = False
ds.use_collision_border_left = False
ds.use_collision_border_top = False
ds.use_collision_border_bottom = True
ds.vorticity = 0.12
ds.alpha = 0.6                 # buoyancy from density
ds.beta = 5.0                  # buoyancy from heat: hot gas rises hard
ds.use_dissolve_smoke = True
ds.dissolve_speed = 18
ds.burning_rate = 0.32
ds.flame_smoke = 0.35
ds.flame_vorticity = 0.6
ds.flame_ignition = 1.2
ds.flame_max_temp = 3.0
ds.use_noise = False      # smooth sheets of flame (the upres mottles them); resolution carries the edges
if SPIRIT:
    # the body fire's gas (crisp tongues with dark gaps, as approved), a touch calmer, and no soot
    ds.flame_smoke = 0.0
    ds.vorticity = 0.1
fm = src.modifiers[0]
fs = fm.flow_settings
fs.flow_type = "BOTH"
fs.flow_behavior = "INFLOW"
fs.surface_distance = 1.2
fs.fuel_amount = 2.2
fs.temperature = 3.0
fs.density = 0.25
fs.use_initial_velocity = True
fs.velocity_normal = 1.4

# --- turbulence keeps the silhouette from ever repeating
bpy.ops.object.effector_add(type="TURBULENCE", location=(0, 0, 0.8))
tb = bpy.context.object
tb.field.strength = 3.0 if not SPIRIT else 2.6
tb.field.size = 0.35
tb.field.flow = 0.5
tb.field.noise = 0.6
tb.field.seed = SEED
tb.field.use_max_distance = False
# drift the turbulence and the noise texture through time so the fire evolves
tb.location = (0, 0, 0.6)
tb.keyframe_insert("location", frame=1)
tb.location = (0.12, -0.08, 1.1)
tb.keyframe_insert("location", frame=WARM + FRAMES)

# --- bake (skipped with RENDER_ONLY=1 when the cache is already there: only the look is re-rendered)
bpy.context.view_layer.objects.active = dom
dom.select_set(True)
if os.environ.get("RENDER_ONLY") == "1" and os.path.isdir(os.path.join(OUT, "cache", "data")):
    ds.cache_type = "MODULAR"
    ds.has_cache_baked_data = True if hasattr(ds, "has_cache_baked_data") else None
    print("[fire] using the baked cache", flush=True)
else:
    with bpy.context.temp_override(active_object=dom, object=dom, selected_objects=[dom]):
        bpy.ops.fluid.bake_all()
    print("[fire] baked", flush=True)

# --- the look: black-body light from the flame's temperature, the smoke as faint density
mat = bpy.data.materials.new("Fire")
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
outn = nt.nodes.new("ShaderNodeOutputMaterial")
vol = nt.nodes.new("ShaderNodeVolumePrincipled")
flame = nt.nodes.new("ShaderNodeAttribute")
flame.attribute_name = "flame"
dens = nt.nodes.new("ShaderNodeAttribute")
dens.attribute_name = "density"
ramp = nt.nodes.new("ShaderNodeValToRGB")
cr = ramp.color_ramp
cr.elements[0].position = 0.0
if SPIRIT:
    # blue spirit-fire (target: the Meshy concept, wp_concepts/bluefire): violet at the cooling edges and tips,
    # electric blue through the body, a near-white cyan heart
    cr.elements[0].color = (0.16, 0.02, 0.42, 1.0)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (0.82, 0.95, 1.0, 1.0)
    for pos, col in [(0.25, (0.22, 0.08, 0.9, 1.0)), (0.5, (0.08, 0.3, 1.0, 1.0)), (0.75, (0.25, 0.62, 1.0, 1.0)), (0.9, (0.55, 0.85, 1.0, 1.0))]:
        e = cr.elements.new(pos)
        e.color = col
else:
    cr.elements[0].color = (0.32, 0.02, 0.0, 1.0)
    cr.elements[1].position = 1.0
    cr.elements[1].color = (1.0, 0.66, 0.14, 1.0)
    for pos, col in [(0.35, (0.9, 0.16, 0.0, 1.0)), (0.7, (1.0, 0.4, 0.03, 1.0))]:
        e = cr.elements.new(pos)
        e.color = col
# a sharp edge: the flame's light is a steep ramp of its field, so the tongues have crisp outlines like real fire
edge = nt.nodes.new("ShaderNodeMapRange")
edge.interpolation_type = "SMOOTHERSTEP"
edge.inputs["From Min"].default_value = 0.42
edge.inputs["From Max"].default_value = 0.78
edge.inputs["To Min"].default_value = 0.0
edge.inputs["To Max"].default_value = 1.0
heat = nt.nodes.new("ShaderNodeMapRange")
heat.inputs["From Min"].default_value = 0.42
heat.inputs["From Max"].default_value = 1.0
strength = nt.nodes.new("ShaderNodeMath")
strength.operation = "MULTIPLY"
strength.inputs[1].default_value = 9.0
dmul = nt.nodes.new("ShaderNodeMath")
dmul.operation = "MULTIPLY"
dmul.inputs[1].default_value = 0.0
nt.links.new(flame.outputs["Fac"], edge.inputs["Value"])
nt.links.new(flame.outputs["Fac"], heat.inputs["Value"])
nt.links.new(heat.outputs["Result"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], vol.inputs["Emission Color"])
nt.links.new(edge.outputs["Result"], strength.inputs[0])
gen = nt.nodes.new("ShaderNodeNewGeometry")     # world position: the floor is z = 0
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
foot = nt.nodes.new("ShaderNodeMapRange")
foot.interpolation_type = "SMOOTHSTEP"
foot.inputs["From Min"].default_value = 0.06
foot.inputs["From Max"].default_value = 0.36
footmul = nt.nodes.new("ShaderNodeMath")
footmul.operation = "MULTIPLY"
nt.links.new(gen.outputs["Position"], sep.inputs["Vector"])
nt.links.new(sep.outputs["Z"], foot.inputs["Value"])
nt.links.new(strength.outputs[0], footmul.inputs[0])
nt.links.new(foot.outputs["Result"], footmul.inputs[1])
nt.links.new(footmul.outputs[0], vol.inputs["Emission Strength"])
nt.links.new(dens.outputs["Fac"], dmul.inputs[0])
nt.links.new(dmul.outputs[0], vol.inputs["Density"])
vol.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
vol.inputs["Absorption Color"].default_value = (0.0, 0.0, 0.0, 1.0)
nt.links.new(vol.outputs["Volume"], outn.inputs["Volume"])
mat.cycles.volume_interpolation = "CUBIC"     # smooth between voxels
dom.data.materials.clear()
dom.data.materials.append(mat)
src.hide_render = True

# --- camera and render
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = SHAPE["cam"][0]
cam = bpy.data.objects.new("Cam", cam_data)
scn.collection.objects.link(cam)
cam.location = (0, -4.0, SHAPE["cam"][1])
cam.rotation_euler = (1.5708, 0, 0)
scn.camera = cam
scn.render.engine = "CYCLES"
scn.cycles.device = "CPU"
scn.cycles.samples = 48
scn.cycles.use_denoising = True
scn.cycles.volume_step_rate = 0.5
scn.cycles.volume_max_steps = 256
scn.render.film_transparent = False      # RGB is the fire's light on black (it adds); no alpha
scn.render.resolution_x = int(PX * SHAPE["aspect"]) if SHAPE["aspect"] <= 1.0 else PX
scn.render.resolution_y = PX if SHAPE["aspect"] <= 1.0 else int(PX / SHAPE["aspect"])
scn.render.resolution_percentage = 100
scn.render.image_settings.file_format = "PNG"
scn.render.image_settings.color_mode = "RGB"
scn.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("W")
world.color = (0, 0, 0)
scn.world = world
for i in range(FRAMES):
    scn.frame_set(WARM + 1 + i)
    scn.render.filepath = os.path.join(OUT, "fire_%03d.png" % i)
    bpy.ops.render.render(write_still=True)
    print("[fire] frame", i, flush=True)
print("[fire] done", flush=True)
