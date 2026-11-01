"""Simulates smoke-type effects with Mantaflow and renders them as flipbook frames (RGBA, lit) for the Demon's
skills: each skill gets its own simulated look instead of sharing Molten Fists' fire.

    SMOKE_KIND=<kind> blender -b --python tools/blender/fx/smoke_flipbook.py -- <outdir> [res] [frames] [px]

Kinds (each a real simulation, rendered with Cycles from the game camera's elevation):
  impact  a boulder or meteor hitting the ground: a hot flash at the heart, then a dirt-and-ash cloud thrown out
          and up that rolls and billows, a skirt of dust racing out along the ground. One shot (frame 0 = impact).
  comet   a burning rock's trail: fire and thick smoke torn back by the wind of its flight. Loops (random frames).
  steam   white steam and gas rising off molten rock in a line, drifting. Loops.
  ash     a dark puff of ash and dust kicked up by a hoof: small, quick, one shot.
  blast   a ring of fire and smoke blown outward from a body (the Crucible bursting): one shot, seen from above-side.
Smoke is lit by a key light (warm, low) and a cool sky fill and lit from inside by its own fire where there is
any; the film is transparent, so the frames are premultiplied RGBA (smoke darkens, fire adds). Writes
<outdir>/smk_NNN.png; tools/fx_flipbook.sh-style packing with `smk` frames (tools/fx_smokebook.sh).
"""
import bpy
import sys
import os
import math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/smoke"
RES = int(argv[1]) if len(argv) > 1 else 80
FRAMES = int(argv[2]) if len(argv) > 2 else 48
PX = int(argv[3]) if len(argv) > 3 else 256
KIND = os.environ.get("SMOKE_KIND", "impact")
os.makedirs(OUT, exist_ok=True)
#           domain (x, y, z), domain centre z, warm-up frames, camera (ortho scale, centre z, elevation deg), aspect w/h
SHAPE = {
	"impact": {"dom": (4.4, 4.4, 3.2), "dz": 1.6, "warm": 0, "cam": (4.6, 1.25, 18.0), "aspect": 1.0},
	"comet":  {"dom": (3.2, 1.0, 1.4), "dz": 0.7, "warm": 50, "cam": (3.0, 0.7, 0.0), "aspect": 2.0},
	"steam":  {"dom": (2.4, 0.8, 2.4), "dz": 1.2, "warm": 50, "cam": (2.6, 1.15, 0.0), "aspect": 1.0},
	"ash":    {"dom": (1.6, 1.6, 1.4), "dz": 0.7, "warm": 0, "cam": (1.7, 0.6, 15.0), "aspect": 1.0},
	"blast":  {"dom": (6.0, 6.0, 2.6), "dz": 1.3, "warm": 0, "cam": (6.4, 0.9, 32.0), "aspect": 1.6},
}[KIND]

bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.frame_start = 1
scn.frame_end = SHAPE["warm"] + FRAMES
scn.render.fps = 30

def keyframe(obj, path, pairs):
	for f, v in pairs:
		setattr(obj, path, v) if not isinstance(path, tuple) else None
		obj.keyframe_insert(path, frame=f)

# --- the emitter for each kind
if KIND == "impact":
	bpy.ops.mesh.primitive_uv_sphere_add(radius=0.35, location=(0, 0, 0.25))
elif KIND == "comet":
	bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.16, location=(1.15, 0, 0.7))
elif KIND == "steam":
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.08))
	bpy.context.object.scale = (1.9, 0.18, 0.05)
	bpy.ops.object.transform_apply(scale=True)
elif KIND == "ash":
	bpy.ops.mesh.primitive_uv_sphere_add(radius=0.12, location=(0, 0, 0.1))
elif KIND == "blast":
	bpy.ops.mesh.primitive_torus_add(major_radius=0.55, minor_radius=0.22, location=(0, 0, 0.5))
src = bpy.context.object
src.name = "Source"
src.select_set(True)
bpy.context.view_layer.objects.active = src
bpy.ops.object.quick_smoke(style="BOTH" if KIND in ("impact", "comet", "blast") else "SMOKE")
dom = [o for o in bpy.data.objects if o != src and o.modifiers][0]
dom.name = "Domain"
dom.location = (0, 0, SHAPE["dz"])
dom.dimensions = SHAPE["dom"]
ds = dom.modifiers[0].domain_settings
ds.resolution_max = RES
ds.use_adaptive_domain = False
ds.cache_type = "ALL"
ds.cache_directory = os.path.join(OUT, "cache")
ds.cache_frame_start = 1
ds.cache_frame_end = SHAPE["warm"] + FRAMES
for side in ("front", "back", "right", "left", "top"):
	setattr(ds, "use_collision_border_" + side, False)
ds.use_collision_border_bottom = True
ds.use_noise = True
ds.noise_scale = 2
ds.noise_strength = 1.6
fs = src.modifiers[0].flow_settings
fs.flow_behavior = "INFLOW"
fs.use_initial_velocity = True
fs.surface_distance = 1.0

if KIND == "impact":
	ds.vorticity = 0.35
	ds.alpha = -0.25            # heavy dust: it sinks a little as it cools
	ds.beta = 1.6               # the hot core still rises into a mushroom
	ds.use_dissolve_smoke = True
	ds.dissolve_speed = 60
	ds.burning_rate = 1.4
	ds.flame_smoke = 1.6
	ds.flame_max_temp = 2.5
	fs.flow_type = "BOTH"
	fs.fuel_amount = 1.6
	fs.temperature = 3.0
	fs.density = 1.0
	fs.velocity_normal = 6.0     # thrown outward
	fs.velocity_coord = (0, 0, 3.5)
	fs.use_plane_init = False
	# only the first few frames emit: the cloud is thrown once and then rolls on its own
	fs.flow_behavior = "INFLOW"
	src.modifiers[0].flow_settings.subframes = 2
	for f, on in [(1, 1.0), (5, 1.0), (6, 0.0)]:
		fs.density = 1.0 * on
		fs.fuel_amount = 1.6 * on
		fs.keyframe_insert("density", frame=f)
		fs.keyframe_insert("fuel_amount", frame=f)
	# a flat ring at the floor sends the skirt of dust racing out along the ground
	bpy.ops.mesh.primitive_torus_add(major_radius=0.55, minor_radius=0.1, location=(0, 0, 0.08))
	skirt = bpy.context.object
	skirt.name = "Skirt"
	bpy.ops.object.modifier_add(type="FLUID")
	skirt.modifiers[0].fluid_type = "FLOW"
	sf = skirt.modifiers[0].flow_settings
	sf.flow_type = "SMOKE"
	sf.flow_behavior = "INFLOW"
	sf.use_initial_velocity = True
	sf.velocity_normal = 7.5
	sf.smoke_color = (0.32, 0.27, 0.22)
	for f, on in [(1, 1.0), (4, 1.0), (5, 0.0)]:
		sf.density = 1.2 * on
		sf.keyframe_insert("density", frame=f)
	skirt.hide_render = True
	fs.smoke_color = (0.24, 0.2, 0.17)
elif KIND == "comet":
	ds.vorticity = 0.25
	ds.alpha = 0.2
	ds.beta = 1.0
	ds.use_dissolve_smoke = True
	ds.dissolve_speed = 40
	ds.burning_rate = 0.6
	ds.flame_smoke = 1.2
	ds.flame_vorticity = 0.8
	fs.flow_type = "BOTH"
	fs.fuel_amount = 2.0
	fs.temperature = 3.0
	fs.density = 0.8
	fs.velocity_normal = 0.6
	fs.smoke_color = (0.14, 0.11, 0.1)
	# the wind of its flight tears it back (toward -x)
	bpy.ops.object.effector_add(type="WIND", location=(2.0, 0, 0.7))
	wind = bpy.context.object
	wind.rotation_euler = (0, -math.pi * 0.5, 0)
	wind.field.strength = 9.0
	wind.field.flow = 1.0
	bpy.ops.object.effector_add(type="TURBULENCE", location=(0, 0, 0.7))
	tb = bpy.context.object
	tb.field.strength = 2.5
	tb.field.size = 0.3
	tb.field.flow = 0.6
elif KIND == "steam":
	ds.vorticity = 0.2
	ds.alpha = 0.6
	ds.beta = 1.4
	ds.use_dissolve_smoke = True
	ds.dissolve_speed = 45
	fs.flow_type = "SMOKE"
	fs.density = 0.55
	fs.temperature = 1.4
	fs.velocity_normal = 0.8
	fs.smoke_color = (0.82, 0.8, 0.78)
	bpy.ops.object.effector_add(type="TURBULENCE", location=(0, 0, 1.2))
	tb = bpy.context.object
	tb.field.strength = 2.0
	tb.field.size = 0.45
	tb.field.flow = 0.5
	tb.keyframe_insert("location", frame=1)
	tb.location = (0.3, 0.1, 1.8)
	tb.keyframe_insert("location", frame=SHAPE["warm"] + FRAMES)
elif KIND == "ash":
	ds.vorticity = 0.4
	ds.alpha = -0.1
	ds.beta = 0.6
	ds.use_dissolve_smoke = True
	ds.dissolve_speed = 30
	fs.flow_type = "SMOKE"
	fs.temperature = 1.0
	fs.velocity_normal = 3.0
	fs.velocity_coord = (0, 0, 1.2)
	fs.smoke_color = (0.16, 0.14, 0.13)
	for f, on in [(1, 1.0), (3, 1.0), (4, 0.0)]:
		fs.density = 1.0 * on
		fs.keyframe_insert("density", frame=f)
elif KIND == "blast":
	ds.vorticity = 0.4
	ds.alpha = 0.0
	ds.beta = 2.2
	ds.use_dissolve_smoke = True
	ds.dissolve_speed = 45
	ds.burning_rate = 1.2
	ds.flame_smoke = 1.0
	ds.flame_max_temp = 3.0
	fs.flow_type = "BOTH"
	fs.temperature = 3.0
	fs.velocity_normal = 9.0      # blown outward from the ring
	fs.smoke_color = (0.12, 0.08, 0.08)
	for f, on in [(1, 1.0), (4, 1.0), (5, 0.0)]:
		fs.density = 0.9 * on
		fs.fuel_amount = 2.0 * on
		fs.keyframe_insert("density", frame=f)
		fs.keyframe_insert("fuel_amount", frame=f)

# --- bake
bpy.context.view_layer.objects.active = dom
dom.select_set(True)
with bpy.context.temp_override(active_object=dom, object=dom, selected_objects=[dom]):
	bpy.ops.fluid.bake_all()
print("[smoke] baked", KIND, flush=True)

# --- the look: lit smoke (its own colour), fire inside lighting it
mat = bpy.data.materials.new("Smoke")
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
	nt.nodes.remove(n)
outn = nt.nodes.new("ShaderNodeOutputMaterial")
vol = nt.nodes.new("ShaderNodeVolumePrincipled")
dens = nt.nodes.new("ShaderNodeAttribute")
dens.attribute_name = "density"
colr = nt.nodes.new("ShaderNodeAttribute")
colr.attribute_name = "color"
flame = nt.nodes.new("ShaderNodeAttribute")
flame.attribute_name = "flame"
dmul = nt.nodes.new("ShaderNodeMath")
dmul.operation = "MULTIPLY"
dmul.inputs[1].default_value = {"impact": 9.0, "comet": 7.0, "steam": 4.0, "ash": 10.0, "blast": 8.0}[KIND]
nt.links.new(dens.outputs["Fac"], dmul.inputs[0])
nt.links.new(dmul.outputs[0], vol.inputs["Density"])
nt.links.new(colr.outputs["Color"], vol.inputs["Color"])
vol.inputs["Anisotropy"].default_value = 0.3
ramp = nt.nodes.new("ShaderNodeValToRGB")
cr = ramp.color_ramp
cr.elements[0].position = 0.0
cr.elements[0].color = (0.0, 0.0, 0.0, 1.0)
cr.elements[1].position = 1.0
cr.elements[1].color = (1.0, 0.72, 0.3, 1.0)
for pos, col in [(0.3, (0.55, 0.06, 0.0, 1.0)), (0.62, (1.0, 0.32, 0.03, 1.0))]:
	e = cr.elements.new(pos)
	e.color = col
nt.links.new(flame.outputs["Fac"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], vol.inputs["Emission Color"])
emul = nt.nodes.new("ShaderNodeMath")
emul.operation = "MULTIPLY"
emul.inputs[1].default_value = 14.0
nt.links.new(flame.outputs["Fac"], emul.inputs[0])
nt.links.new(emul.outputs[0], vol.inputs["Emission Strength"])
nt.links.new(vol.outputs["Volume"], outn.inputs["Volume"])
mat.cycles.volume_interpolation = "CUBIC"
dom.data.materials.clear()
dom.data.materials.append(mat)
for o in bpy.data.objects:
	if o.type == "MESH" and o != dom:
		o.hide_render = True

# --- lights: a warm low key (the game's dusk), a cool fill from the sky
key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
key.data.energy = 4.5
key.data.color = (1.0, 0.85, 0.7)
key.rotation_euler = (math.radians(55), 0, math.radians(35))
scn.collection.objects.link(key)
fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
fill.data.energy = 1.2
fill.data.color = (0.6, 0.7, 0.9)
fill.rotation_euler = (math.radians(-40), 0, math.radians(-150))
scn.collection.objects.link(fill)
world = bpy.data.worlds.new("W")
world.color = (0.05, 0.05, 0.06)
scn.world = world

# --- camera: orthographic, at the game camera's elevation for kinds seen from above
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = SHAPE["cam"][0]
cam = bpy.data.objects.new("Cam", cam_data)
scn.collection.objects.link(cam)
el = math.radians(SHAPE["cam"][2])
cam.location = (0, -10.0 * math.cos(el), SHAPE["cam"][1] + 10.0 * math.sin(el))
cam.rotation_euler = (math.radians(90) - el, 0, 0)
scn.camera = cam
scn.render.engine = "CYCLES"
scn.cycles.device = "CPU"
scn.cycles.samples = 40
scn.cycles.use_denoising = True
scn.cycles.volume_step_rate = 0.6
scn.cycles.volume_max_steps = 256
scn.render.film_transparent = True
scn.render.resolution_x = PX if SHAPE["aspect"] >= 1.0 else int(PX * SHAPE["aspect"])
scn.render.resolution_y = int(PX / SHAPE["aspect"]) if SHAPE["aspect"] >= 1.0 else PX
scn.render.resolution_percentage = 100
scn.render.image_settings.file_format = "PNG"
scn.render.image_settings.color_mode = "RGBA"
scn.view_settings.view_transform = "Standard"
for i in range(FRAMES):
	scn.frame_set(SHAPE["warm"] + 1 + i)
	scn.render.filepath = os.path.join(OUT, "smk_%03d.png" % i)
	bpy.ops.render.render(write_still=True)
	print("[smoke] frame", i, flush=True)
print("[smoke] done", KIND, flush=True)
