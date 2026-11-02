"""Simulates smoke-type effects with Mantaflow and renders them as flipbook frames (RGBA, lit) for the Demon's
skills: each skill gets its own simulated look instead of sharing Molten Fists' fire.

    SMOKE_KIND=<kind> blender -b --python tools/blender/fx/smoke_flipbook.py -- <outdir> [res] [frames] [px] [samples]

Kinds (each a real simulation, rendered in Cycles; the ground effects from the game camera's own elevation, 44 deg,
so a camera-facing card shows the cloud as the game camera would see it in 3D):
  impact  a boulder or meteor hitting the ground. Debris particles are flung out of the crater on arcs and fall back,
          each trailing dirt and ash (the ejecta curtain); a ring of particles races out along the ground (the base
          surge); a short fireball flashes and rolls up at the heart. One shot, frame 0 = the moment of impact.
  comet   a burning rock's trail: fire and thick smoke torn back by the wind of its flight. Loops (random frames).
  steam   white steam and gas rising off molten rock along a line, drifting. Loops.
  ash     a dark puff of ash and dust kicked up by a hoof: a few small ejecta and a little surge. One shot.
  blast   a ring of fire and smoke blown outward from a body (the Crucible bursting): particles fly out level,
          burning, and their fire turns to rolling smoke. One shot, seen from above-side.
Smoke takes its colour from the flows (brown dirt, grey ash, white steam, soot); it is lit by a warm low key (the
game's dusk) and a cool sky fill, and from inside by its own fire, whose light is a black-body ramp of the flame
field with a crisp edge (as in fire_flipbook.py, so flames have sharp tongues, not cotton). The film is
transparent and the frames are EXR, premultiplied (smoke darkens, fire adds light even where there's no smoke: a PNG's
straight alpha would throw that light away). Writes <outdir>/smk_NNN.exr and <outdir>/book.json (aspect, where the
origin sits, how wide the cloud is); pack with tools/fx_smokebook.py.
"""
import bpy
import bmesh
import sys
import os
import math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp/smoke"
RES = int(argv[1]) if len(argv) > 1 else 96
FRAMES = int(argv[2]) if len(argv) > 2 else 48
PX = int(argv[3]) if len(argv) > 3 else 320
SAMPLES = int(argv[4]) if len(argv) > 4 else 32
KIND = os.environ.get("SMOKE_KIND", "impact")
os.makedirs(OUT, exist_ok=True)
OVERLAP = 12       # loops: frames rendered past the end, cross-faded into the start by the packer (a seamless loop)
#   dom: the domain (x, y, z), dz: its centre's height, warm: warm-up frames (loops), cam: (ortho width, the height
#   its centre looks at, elevation deg), aspect: w/h, span: the cloud's nominal width in metres (what a card's `size`
#   means in the game), mode: how the game holds the card (0 upright, turning round the vertical: seen side on;
#   1 facing the camera: seen from the game's 44 deg; 2 along the way it flies), head: where the source sits along x
SHAPE = {
	"impact": {"dom": (9.6, 9.6, 5.2), "dz": 2.6, "warm": 0, "cam": (8.8, 0.85, 44.0), "aspect": 1.2, "span": 7.0, "mode": 1},
	"comet":  {"dom": (3.8, 1.4, 2.0), "dz": 0.85, "warm": 50, "cam": (3.4, 0.85, 0.0), "aspect": 2.0, "span": 3.4, "mode": 2, "head": (1.3, 0.85)},
	"steam":  {"dom": (2.4, 0.8, 2.6), "dz": 1.3, "warm": 50, "cam": (2.6, 1.25, 0.0), "aspect": 1.0, "span": 2.4, "mode": 0},
	"ash":    {"dom": (2.8, 2.8, 2.0), "dz": 1.0, "warm": 0, "cam": (2.5, 0.45, 44.0), "aspect": 1.25, "span": 1.9, "mode": 1},
	"blast":  {"dom": (10.6, 10.6, 4.4), "dz": 2.2, "warm": 0, "cam": (9.6, 1.3, 44.0), "aspect": 1.25, "span": 7.0, "mode": 1},
}[KIND]
EXTRA = OVERLAP if SHAPE["warm"] > 0 else 0

bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.frame_start = 1
scn.frame_end = SHAPE["warm"] + FRAMES + EXTRA
scn.render.fps = 30
scn.gravity = (0, 0, -9.81)

def link(ob):
	if ob.name not in scn.collection.objects:
		scn.collection.objects.link(ob)

def dome(name, r, z, cut=-0.02):
	"""A half sphere (its normals all point up and out): what ejecta are flung from."""
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=r)
	for v in [v for v in bm.verts if v.co.z < cut * r]:
		bm.verts.remove(v)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	ob = bpy.data.objects.new(name, me)
	ob.location = (0, 0, z)
	link(ob)
	return ob

def ring(name, r, z, minor=0.06):
	bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=minor, major_segments=48, minor_segments=8, location=(0, 0, z))
	ob = bpy.context.object
	ob.name = name
	return ob

def particles(ob, count, f0, f1, life, normal, rand, up=0.0, gravity=1.0, drag=0.0, size=0.05):
	"""A burst of Newtonian particles off ob's faces (normal = speed along the face normal, up = extra upward speed)."""
	ps_mod = ob.modifiers.new("P", "PARTICLE_SYSTEM")
	st = ps_mod.particle_system.settings
	st.count = count
	st.frame_start = f0
	st.frame_end = f1
	st.lifetime = life
	st.lifetime_random = 0.35
	st.emit_from = "FACE"
	st.use_emit_random = True
	st.physics_type = "NEWTON"
	st.normal_factor = normal
	st.factor_random = rand
	st.object_align_factor = (0.0, 0.0, up)
	st.effector_weights.gravity = gravity
	st.drag_factor = drag
	st.particle_size = size
	st.render_type = "NONE"
	ob.hide_render = True
	return ps_mod.particle_system

def flow_from(ob, psys, kind, color, density, temp, cells, fuel=0.0, vel=1.0):
	"""Makes ob a fluid flow emitting along its particles' paths (their speed passed on to the gas). `cells`: how big
	each particle is, in simulation cells (below 1 every particle marks one cell: speckles, not trails)."""
	mod = ob.modifiers.new("Fluid", "FLUID")
	mod.fluid_type = "FLOW"
	fs = mod.flow_settings
	fs.flow_type = kind
	fs.flow_behavior = "INFLOW"
	fs.flow_source = "PARTICLES"
	fs.particle_system = psys
	fs.use_particle_size = True
	fs.particle_size = cells
	fs.subframes = 2           # fast ejecta draw a streak, not a dotted line
	fs.smoke_color = color
	fs.density = density
	fs.temperature = temp
	if kind in ("FIRE", "BOTH"):
		fs.fuel_amount = fuel
	fs.use_initial_velocity = True
	fs.velocity_factor = vel
	ob.hide_render = True
	return fs

def ground():
	"""The ground the particles land on (and roll along)."""
	bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0, 0, 0.0))
	pl = bpy.context.object
	pl.name = "Ground"
	bpy.ops.object.modifier_add(type="COLLISION")
	pl.collision.damping = 0.6
	pl.collision.friction_factor = 0.5
	pl.hide_render = True
	return pl

# --- the domain (made by hand: Quick Smoke needs a selected flow, and particle flows are added after)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, SHAPE["dz"]))
dom = bpy.context.object
dom.name = "Domain"
dom.scale = SHAPE["dom"]
bpy.ops.object.transform_apply(scale=True)
dmod = dom.modifiers.new("Fluid", "FLUID")
dmod.fluid_type = "DOMAIN"
ds = dmod.domain_settings
ds.domain_type = "GAS"
ds.resolution_max = RES
ds.use_adaptive_domain = False
ds.cache_type = "ALL"
ds.cache_directory = os.path.join(OUT, "cache")
ds.cache_frame_start = 1
ds.cache_frame_end = SHAPE["warm"] + FRAMES + EXTRA
for side in ("front", "back", "right", "left", "top"):
	setattr(ds, "use_collision_border_" + side, False)
ds.use_collision_border_bottom = True
ds.use_noise = True
ds.noise_scale = 2
ds.noise_strength = 1.2
ds.use_dissolve_smoke = True

if KIND == "impact":
	ground()
	ds.vorticity = 0.35
	ds.alpha = -0.3             # heavy dust sinks a little as it slows
	ds.beta = 0.9               # the hot heart still lifts a mushroom
	ds.dissolve_speed = 52      # thinning out by the last frame
	ds.burning_rate = 0.9
	ds.flame_smoke = 1.3
	ds.flame_smoke_color = (0.12, 0.09, 0.08)
	ds.flame_vorticity = 0.7
	ds.flame_max_temp = 2.5
	# the ejecta: flung up and out of the crater on arcs, each trailing dirt while it flies (the ejecta curtain)
	ej = dome("Ejecta", 0.32, 0.05)
	pe = particles(ej, 260, 1, 3, 17, 4.6, 2.0, up=2.2, gravity=1.0, drag=0.2, size=0.1)
	flow_from(ej, pe, "SMOKE", (0.72, 0.62, 0.5), 0.55, 0.2, 1.1, vel=0.6)
	# the base surge: a ring racing out along the ground, staying low
	sg = ring("Surge", 0.45, 0.08, 0.05)
	psg = particles(sg, 220, 1, 3, 13, 4.6, 1.2, up=0.4, gravity=0.35, drag=1.4, size=0.1)
	flow_from(sg, psg, "SMOKE", (0.66, 0.57, 0.47), 0.6, 0.0, 1.6, vel=0.6)
	# the fireball at the heart: brief, torn into tongues, rolling up and burning out to soot
	bpy.ops.mesh.primitive_uv_sphere_add(radius=0.4, location=(0, 0, 0.35))
	core = bpy.context.object
	core.name = "Core"
	cm = core.modifiers.new("Fluid", "FLUID")
	cm.fluid_type = "FLOW"
	cf = cm.flow_settings
	cf.flow_type = "BOTH"
	cf.flow_behavior = "INFLOW"
	cf.smoke_color = (0.3, 0.24, 0.2)
	cf.temperature = 2.4
	cf.use_initial_velocity = True
	cf.velocity_normal = 6.0
	cf.velocity_coord = (0, 0, 2.5)
	cf.subframes = 2
	for f, on in [(1, 1.0), (4, 1.0), (5, 0.0)]:
		cf.fuel_amount = 1.5 * on
		cf.density = 0.5 * on
		cf.keyframe_insert("fuel_amount", frame=f)
		cf.keyframe_insert("density", frame=f)
	core.hide_render = True
elif KIND == "comet":
	# a burning rock seen side on, its flight a wind blowing past it: short tongues of fire torn off it, thick smoke
	# churning behind and fading out
	ds.vorticity = 0.6
	ds.alpha = 0.1
	ds.beta = 0.6
	ds.dissolve_speed = 20       # (faster, and the heat goes before the fuel can burn: the fire goes out)
	ds.burning_rate = 1.35
	ds.flame_smoke = 1.0
	ds.flame_vorticity = 1.0
	ds.flame_smoke_color = (0.1, 0.08, 0.07)
	ds.noise_strength = 1.6
	bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=0.24, location=(1.3, 0, 0.85))
	src = bpy.context.object
	sm = src.modifiers.new("Fluid", "FLUID")
	sm.fluid_type = "FLOW"
	fs = sm.flow_settings
	fs.flow_type = "BOTH"
	fs.flow_behavior = "INFLOW"
	fs.fuel_amount = 1.8
	fs.temperature = 2.6
	fs.density = 0.45
	fs.use_initial_velocity = True
	fs.velocity_normal = 1.2
	fs.smoke_color = (0.12, 0.1, 0.09)
	fs.subframes = 2
	src.hide_render = True
	bpy.ops.object.effector_add(type="WIND", location=(2.2, 0, 0.85))
	wind = bpy.context.object
	wind.rotation_euler = (0, -math.pi * 0.5, 0)
	wind.field.strength = 7.0
	wind.field.flow = 1.0
	# eddies only behind the rock: the flame stays on it, the smoke it trails breaks up and churns
	bpy.ops.object.effector_add(type="TURBULENCE", location=(-0.8, 0, 0.85))
	tb = bpy.context.object
	tb.field.strength = 3.0
	tb.field.size = 0.3
	tb.field.flow = 0.0
	tb.field.falloff_type = "SPHERE"
	tb.field.use_max_distance = True
	tb.field.distance_max = 1.5
elif KIND == "steam":
	ds.vorticity = 0.25
	ds.alpha = 0.6
	ds.beta = 2.0
	ds.dissolve_speed = 45
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.1))
	src = bpy.context.object
	src.scale = (1.9, 0.2, 0.1)
	bpy.ops.object.transform_apply(scale=True)
	sm = src.modifiers.new("Fluid", "FLUID")
	sm.fluid_type = "FLOW"
	fs = sm.flow_settings
	fs.flow_type = "SMOKE"
	fs.flow_behavior = "INFLOW"
	fs.density = 0.9
	fs.temperature = 2.0
	fs.use_initial_velocity = True
	fs.velocity_normal = 1.1
	fs.smoke_color = (0.85, 0.83, 0.8)
	# vents along the crack that come and go: the emission broken up by drifting cloud noise
	nt_tex = bpy.data.textures.new("Vents", "CLOUDS")
	nt_tex.noise_scale = 0.22
	nt_tex.contrast = 1.8
	fs.use_texture = True
	fs.noise_texture = nt_tex
	fs.texture_map_type = "AUTO"
	fs.texture_size = 1.0
	fs.texture_offset = 0.0
	fs.keyframe_insert("texture_offset", frame=1)
	fs.texture_offset = 2.5
	fs.keyframe_insert("texture_offset", frame=SHAPE["warm"] + FRAMES + EXTRA)
	src.hide_render = True
	bpy.ops.object.effector_add(type="TURBULENCE", location=(0, 0, 1.2))
	tb = bpy.context.object
	tb.field.strength = 2.4
	tb.field.size = 0.45
	tb.field.flow = 0.5
	tb.keyframe_insert("location", frame=1)
	tb.location = (0.3, 0.1, 1.8)
	tb.keyframe_insert("location", frame=SHAPE["warm"] + FRAMES + EXTRA)
elif KIND == "ash":
	ground()
	ds.vorticity = 0.5          # it billows as it rolls
	ds.alpha = -0.15
	ds.beta = 0.25
	ds.dissolve_speed = 28
	# a few clods' worth of dust kicked up on short arcs
	ej = dome("Kick", 0.1, 0.03)
	pe = particles(ej, 40, 1, 2, 7, 1.6, 0.8, up=1.2, gravity=1.0, drag=0.6, size=0.05)
	flow_from(ej, pe, "SMOKE", (0.5, 0.45, 0.4), 0.8, 0.1, 2.0, vel=0.5)
	# the low roll of dust spreading over the ground
	sg = ring("Surge", 0.15, 0.04, 0.03)
	psg = particles(sg, 60, 1, 2, 8, 2.2, 0.6, up=0.2, gravity=0.3, drag=1.6, size=0.05)
	flow_from(sg, psg, "SMOKE", (0.45, 0.41, 0.37), 0.8, 0.0, 2.4, vel=0.6)
	# the soft puff that rises from the strike itself
	bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(0, 0, 0.12))
	pf = bpy.context.object
	pf.name = "Puff"
	pm = pf.modifiers.new("Fluid", "FLUID")
	pm.fluid_type = "FLOW"
	pfs = pm.flow_settings
	pfs.flow_type = "SMOKE"
	pfs.flow_behavior = "INFLOW"
	pfs.smoke_color = (0.5, 0.45, 0.4)
	pfs.temperature = 0.4
	pfs.use_initial_velocity = True
	pfs.velocity_normal = 0.9
	pfs.velocity_coord = (0, 0, 0.9)
	for f, on in [(1, 1.0), (3, 1.0), (4, 0.0)]:
		pfs.density = 0.9 * on
		pfs.keyframe_insert("density", frame=f)
	pf.hide_render = True
elif KIND == "blast":
	ground()
	ds.vorticity = 0.4
	ds.alpha = 0.0
	ds.beta = 1.4
	ds.dissolve_speed = 20
	ds.burning_rate = 1.7       # the fire flashes out and is gone, the smoke rolls on
	ds.flame_smoke = 0.6
	ds.flame_smoke_color = (0.1, 0.07, 0.07)
	ds.flame_max_temp = 3.0
	ds.flame_vorticity = 0.7
	# a ring of burning particles thrown out level from round his body, each burning only while it flies
	rg = ring("Ring", 0.55, 0.7, 0.22)
	pr = particles(rg, 200, 1, 3, 12, 5.2, 1.6, up=0.6, gravity=0.25, drag=1.4, size=0.1)
	flow_from(rg, pr, "BOTH", (0.12, 0.08, 0.08), 0.45, 2.5, 2.0, fuel=1.2, vel=0.4)

# --- bake
bpy.context.view_layer.objects.active = dom
for o in scn.objects:
	o.select_set(o == dom)
with bpy.context.temp_override(active_object=dom, object=dom, selected_objects=[dom]):
	bpy.ops.fluid.bake_all()
print("[smoke] baked", KIND, flush=True)

# --- the look: lit smoke in its own colour; flames as a crisp black-body ramp of the flame field
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
# (the node multiplies Density by the smoke's own density grid itself: its "Density Attribute"; wiring the grid in
# as well squares it and thin dust all but vanishes)
vol.inputs["Density"].default_value = {"impact": 4.5, "comet": 5.0, "steam": 3.5, "ash": 7.0, "blast": 6.0}[KIND]
# the smoke's colour: one per kind (the colour grid comes through weighted by density, so thin dust read black)
vol.inputs["Color"].default_value = {"impact": (0.52, 0.43, 0.33, 1.0), "comet": (0.24, 0.2, 0.18, 1.0),
	"steam": (0.92, 0.91, 0.9, 1.0), "ash": (0.5, 0.45, 0.4, 1.0), "blast": (0.22, 0.18, 0.17, 1.0)}[KIND]
vol.inputs["Anisotropy"].default_value = 0.25
# dust and steam scatter light (a dull grey absorption, so the colour shows); soot stays dark through its colour
vol.inputs["Absorption Color"].default_value = (0.55, 0.52, 0.5, 1.0)
ramp = nt.nodes.new("ShaderNodeValToRGB")
cr = ramp.color_ramp
cr.elements[0].position = 0.0
cr.elements[0].color = (0.32, 0.02, 0.0, 1.0)
cr.elements[1].position = 1.0
cr.elements[1].color = (1.0, 0.55, 0.12, 1.0) if KIND == "blast" else (1.0, 0.7, 0.2, 1.0)
for pos, col in [(0.35, (0.9, 0.16, 0.0, 1.0)), (0.7, (1.0, 0.42, 0.04, 1.0))]:
	e = cr.elements.new(pos)
	e.color = col
heat = nt.nodes.new("ShaderNodeMapRange")
heat.inputs["From Min"].default_value = 0.15 if KIND == "comet" else 0.3
heat.inputs["From Max"].default_value = 1.0
nt.links.new(flame.outputs["Fac"], heat.inputs["Value"])
nt.links.new(heat.outputs["Result"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], vol.inputs["Emission Color"])
edge = nt.nodes.new("ShaderNodeMapRange")
edge.interpolation_type = "SMOOTHERSTEP"
# (the comet's flame is torn thin by its wind: a lower threshold keeps it alight in every frame)
edge.inputs["From Min"].default_value = 0.18 if KIND == "comet" else 0.32
edge.inputs["From Max"].default_value = 0.55 if KIND == "comet" else 0.7
nt.links.new(flame.outputs["Fac"], edge.inputs["Value"])
emul = nt.nodes.new("ShaderNodeMath")
emul.operation = "MULTIPLY"
emul.inputs[1].default_value = {"impact": 9.0, "comet": 5.0, "blast": 3.6}.get(KIND, 8.0)
nt.links.new(edge.outputs["Result"], emul.inputs[0])
nt.links.new(emul.outputs[0], vol.inputs["Emission Strength"])
nt.links.new(vol.outputs["Volume"], outn.inputs["Volume"])
mat.cycles.volume_interpolation = "CUBIC"
dom.data.materials.clear()
dom.data.materials.append(mat)
for o in scn.objects:
	if o.type == "MESH" and o != dom:
		o.hide_render = True

# --- lights: a warm low key from the side and a little behind (the game's dusk; shadowed faces show the volume), a
# cool fill from the sky in front
key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
key.data.energy = 8.0
key.data.color = (1.0, 0.86, 0.72)
key.rotation_euler = (math.radians(60), 0, math.radians(-110))
link(key)
fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
fill.data.energy = 1.8
fill.data.color = (0.62, 0.72, 0.92)
fill.rotation_euler = (math.radians(60), 0, math.radians(54.5))
link(fill)
world = bpy.data.worlds.new("W")
world.color = (0.06, 0.06, 0.07)
scn.world = world

# --- camera: orthographic, at about the game camera's elevation for kinds seen from above
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = SHAPE["cam"][0]
cam = bpy.data.objects.new("Cam", cam_data)
link(cam)
el = math.radians(SHAPE["cam"][2])
cam.location = (0, -12.0 * math.cos(el), SHAPE["cam"][1] + 12.0 * math.sin(el))
cam.rotation_euler = (math.radians(90) - el, 0, 0)
scn.camera = cam
scn.render.engine = "CYCLES"
scn.cycles.device = "CPU"
scn.cycles.samples = SAMPLES
scn.cycles.use_denoising = True
scn.cycles.volume_step_rate = 0.7
scn.cycles.volume_max_steps = 192
scn.render.film_transparent = True
scn.render.resolution_x = PX if SHAPE["aspect"] >= 1.0 else int(PX * SHAPE["aspect"])
scn.render.resolution_y = int(PX / SHAPE["aspect"]) if SHAPE["aspect"] >= 1.0 else PX
scn.render.resolution_percentage = 100
scn.render.image_settings.file_format = "OPEN_EXR"
scn.render.image_settings.color_mode = "RGBA"
scn.render.image_settings.color_depth = "16"
scn.render.image_settings.exr_codec = "ZIP"
scn.view_settings.view_transform = "Standard"
# where the sim's origin lands in the frame (fractions from the bottom left): the card's anchor in the game. The origin
# is the ground point under the effect, or for the comet the rock itself ("head": its x, z)
img_h = SHAPE["cam"][0] / SHAPE["aspect"]
head = SHAPE.get("head", (0.0, 0.0))
anchor = 0.5 + (head[1] - SHAPE["cam"][1]) * math.cos(el) / img_h
import json
with open(os.path.join(OUT, "book.json"), "w") as fh:
	json.dump({"kind": KIND, "frames": FRAMES, "aspect": SHAPE["aspect"], "anchor": round(anchor, 4),
		"anchor_u": round(0.5 + head[0] / SHAPE["cam"][0], 4),
		"span": round(SHAPE["span"] / SHAPE["cam"][0], 4), "mode": SHAPE["mode"], "loop": SHAPE["warm"] > 0,
		"overlap": EXTRA,
		"res": [scn.render.resolution_x, scn.render.resolution_y]}, fh)
only = os.environ.get("ONLY_FRAMES")      # tests: render just these frames ("0,8,16")
todo = [int(x) for x in only.split(",")] if only else range(FRAMES + EXTRA)
for i in todo:
	scn.frame_set(SHAPE["warm"] + 1 + i)
	scn.render.filepath = os.path.join(OUT, "smk_%03d.exr" % i)
	bpy.ops.render.render(write_still=True)
	print("[smoke] frame", i, flush=True)
print("[smoke] done", KIND, flush=True)
