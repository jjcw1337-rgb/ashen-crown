"""Ashen Crown: real fire and smoke for the Archer's Fire Arrow (and any fire effect), simulated with Mantaflow and
rendered with Cycles into flipbook frames (no painting: the colour comes from the sim's own flame and temperature).

    blender -b --python tools/blender/fx/fire_sims.py -- <outdir> <sim> [res] [samples] [px]
      sim: flame | burst | smoke | all

Each sim bakes a gas domain (fire+smoke, vorticity, wavelet noise x2) and renders two kinds of frames, orthographic
from the front:
  fire  : black background, the volume's emission as data: R = flame (how much fire along the ray), G = flame x
          temperature (so G/R is the mean temperature: Godot maps it through a blackbody ramp), B = 0.
          Smoke in front absorbs it (Volume Absorption), so the burst's fire is hidden where smoke covers it.
  smoke : transparent film, a white scattering volume lit by three coloured suns: red from the right, green from
          above, blue from the left (the "RGB lightmap"), alpha = the smoke's opacity. Godot relights it with the
          real scene's lights (ArrowFx SMOKE_SHADER light()).
Frames go to <outdir>/<sim>_<pass>_NNNN.png; tools/fx_flipbook.py packs them into assets/textures/fx/real_*.png.
"""
import bpy, sys, os, math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "/tmp/fire_sims")
SIM = argv[1] if len(argv) > 1 else "all"
RES = int(argv[2]) if len(argv) > 2 else 96
SAMPLES = int(argv[3]) if len(argv) > 3 else 24
PX = int(argv[4]) if len(argv) > 4 else 256
PROBE = len(argv) > 5 and argv[5] == "probe"     # four frames spread over the window, for a look
os.makedirs(OUT, exist_ok=True)

# frame windows: (first frame rendered, count); the flame renders N + 16 frames for the loop crossfade
SIMS = {
    "flame": {"frames": (40, 80), "end": 125, "size": (0.9, 0.9, 1.8), "res": RES},
    "burst": {"frames": (2, 64), "end": 70, "size": (5.0, 5.0, 5.6), "res": RES},
    "smoke": {"frames": (2, 64), "end": 70, "size": (3.2, 3.2, 4.4), "res": RES},
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.cycles.volume_step_rate = 1.0
    sc.cycles.volume_max_steps = 256
    sc.cycles.max_bounces = 4
    sc.cycles.volume_bounces = 1
    sc.render.resolution_x = PX
    sc.render.resolution_y = PX
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.render.threads_mode = "AUTO"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.0
    sc.world = w
    return sc


def cube(name, size, loc):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def build(kind):
    sc = reset()
    cfg = SIMS[kind]
    sx, sy, sz = cfg["size"]
    dom = cube("Domain", (sx, sy, sz), (0, 0, sz * 0.5))
    m = dom.modifiers.new("Fluid", "FLUID")
    m.fluid_type = "DOMAIN"
    d = m.domain_settings
    d.domain_type = "GAS"
    d.resolution_max = cfg["res"]
    d.cache_directory = os.path.join(OUT, "cache_" + kind)
    d.cache_type = "ALL"
    d.cache_frame_start = 1
    d.cache_frame_end = cfg["end"]
    d.use_adaptive_domain = False
    d.time_scale = 1.0
    d.use_noise = True
    d.noise_scale = 2
    d.noise_strength = 1.2
    d.noise_pos_scale = 2.0
    d.use_dissolve_smoke = True
    d.dissolve_speed = 40
    d.use_dissolve_smoke_log = True
    d.vorticity = 0.25
    d.alpha = 1.0     # density buoyancy
    d.beta = 1.0      # heat buoyancy
    d.burning_rate = 0.75
    d.flame_smoke = 1.0
    d.flame_vorticity = 0.6
    d.flame_ignition = 1.25
    d.flame_max_temp = 1.75
    d.flame_smoke_color = (0.25, 0.25, 0.25)
    d.use_collision_border_top = False
    if kind == "flame":
        # licking flames off a burning stick: little smoke, a lot of vorticity so the tongues break up
        d.flame_smoke = 0.1
        d.flame_vorticity = 1.6
        d.vorticity = 0.45
        d.burning_rate = 0.92
        d.flame_ignition = 1.1
        d.noise_strength = 1.6
        d.dissolve_speed = 10
        bpy.ops.mesh.primitive_cylinder_add(radius=0.045, depth=0.26, location=(0, 0, 0.12), rotation=(0, math.pi / 2, 0))
        em = bpy.context.active_object
        fm = em.modifiers.new("Fluid", "FLUID")
        fm.fluid_type = "FLOW"
        f = fm.flow_settings
        f.flow_type = "FIRE"
        f.flow_behavior = "INFLOW"
        f.flow_source = "MESH"
        f.surface_distance = 1.2
        f.fuel_amount = 1.2
        f.temperature = 1.0
        f.use_initial_velocity = False
        # flicker the fuel so the tongues come in pulses, not one steady column
        for fr in range(1, cfg["end"] + 1, 3):
            f.fuel_amount = 0.9 + 0.5 * (0.5 + 0.5 * math.sin(fr * 0.9) * math.sin(fr * 0.37 + 1.0))
            f.keyframe_insert("fuel_amount", frame=fr)
    elif kind == "burst":
        # a fireball: fuel thrown out of a small sphere for a few frames, then it burns open and rolls up into smoke
        d.flame_smoke = 2.2
        d.flame_vorticity = 1.7
        d.vorticity = 0.6
        d.burning_rate = 0.8
        d.dissolve_speed = 60
        d.flame_smoke_color = (0.12, 0.11, 0.1)
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.3, subdivisions=5, location=(0, 0, 1.0))
        em = bpy.context.active_object
        # a lumpy gout, not a ball: the emitter displaced by noise
        tx = bpy.data.textures.new("lumps", "CLOUDS")
        tx.noise_scale = 0.18
        dm = em.modifiers.new("Lumps", "DISPLACE")
        dm.texture = tx
        dm.strength = 0.35
        fm = em.modifiers.new("Fluid", "FLUID")
        fm.fluid_type = "FLOW"
        f = fm.flow_settings
        f.flow_type = "BOTH"
        f.flow_behavior = "INFLOW"
        f.flow_source = "MESH"
        f.surface_distance = 1.5
        f.fuel_amount = 1.4
        f.density = 0.9
        f.smoke_color = (0.12, 0.11, 0.1)
        f.temperature = 2.4
        f.use_initial_velocity = True
        f.velocity_normal = 6.0
        f.velocity_coord = (0.0, 0.0, 1.5)
        # the fuel comes out in clots, not an even shell: a noise texture drives how much each spot emits
        tx2 = bpy.data.textures.new("clots", "CLOUDS")
        tx2.noise_scale = 0.12
        tx2.contrast = 2.2
        f.use_texture = True
        f.noise_texture = tx2
        f.texture_map_type = "AUTO"
        f.texture_size = 0.5
        # the gout bursts open: the emitting shell swells over five frames, then it is spent
        for fr, k in ((1, 0.6), (2, 1.3), (3, 2.0), (4, 2.6), (5, 3.0), (6, 0.001)):
            em.scale = (k, k, k * 0.85)
            em.keyframe_insert("scale", frame=fr)
    else:
        # a puff of smoke: a short gout that rises, rolls and spreads (no fire)
        d.dissolve_speed = 45
        d.vorticity = 0.6
        d.beta = 0.6
        bpy.ops.mesh.primitive_ico_sphere_add(radius=0.34, subdivisions=3, location=(0, 0, 0.5))
        em = bpy.context.active_object
        fm = em.modifiers.new("Fluid", "FLUID")
        fm.fluid_type = "FLOW"
        f = fm.flow_settings
        f.flow_type = "SMOKE"
        f.flow_behavior = "INFLOW"
        f.flow_source = "MESH"
        f.surface_distance = 1.5
        f.density = 1.0
        f.temperature = 0.9
        f.use_initial_velocity = True
        f.velocity_normal = 2.2
        f.velocity_coord = (0.0, 0.0, 1.0)
        em.keyframe_insert("scale", frame=1)
        em.keyframe_insert("scale", frame=5)
        em.scale = (0.001, 0.001, 0.001)
        em.keyframe_insert("scale", frame=7)
    em.hide_render = True
    sc.frame_start = 1
    sc.frame_end = cfg["end"]
    # the camera: orthographic from the front, framing the domain
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(sx, sz)
    cam.location = (0, -10, sz * 0.5)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    cam.data.clip_end = 30
    sc.camera = cam
    return sc, dom


def bake(sc, dom):
    bpy.context.view_layer.objects.active = dom
    dom.select_set(True)
    with bpy.context.temp_override(object=dom, active_object=dom):
        bpy.ops.fluid.bake_all()


def attr(nt, name):
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = name
    a.attribute_type = "GEOMETRY"
    return a.outputs["Fac"]


def math_node(nt, op, a, b):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    for i, v in enumerate((a, b)):
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def fire_material(dom, gain, smoke_abs):
    mat = bpy.data.materials.new("fire")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    flame = math_node(nt, "MULTIPLY", attr(nt, "flame"), gain)
    temp = attr(nt, "temperature")
    ft = math_node(nt, "MULTIPLY", flame, math_node(nt, "MINIMUM", math_node(nt, "MULTIPLY", temp, 0.55), 1.0))
    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(flame, comb.inputs[0])
    nt.links.new(ft, comb.inputs[1])
    emi = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(comb.outputs[0], emi.inputs["Color"])
    emi.inputs["Strength"].default_value = 1.0
    shader = emi.outputs[0]
    if smoke_abs > 0.0:
        ab = nt.nodes.new("ShaderNodeVolumeAbsorption")
        ab.inputs["Color"].default_value = (0, 0, 0, 1)
        nt.links.new(math_node(nt, "MULTIPLY", attr(nt, "density"), smoke_abs), ab.inputs["Density"])
        add = nt.nodes.new("ShaderNodeAddShader")
        nt.links.new(emi.outputs[0], add.inputs[0])
        nt.links.new(ab.outputs[0], add.inputs[1])
        shader = add.outputs[0]
    nt.links.new(shader, out.inputs["Volume"])
    dom.data.materials.clear()
    dom.data.materials.append(mat)


def smoke_material(dom, dens):
    mat = bpy.data.materials.new("smoke")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    pv = nt.nodes.new("ShaderNodeVolumePrincipled")
    pv.inputs["Color"].default_value = (1, 1, 1, 1)
    pv.inputs["Absorption Color"].default_value = (0, 0, 0, 1)
    pv.inputs["Anisotropy"].default_value = 0.2
    pv.inputs["Emission Strength"].default_value = 0.0
    pv.inputs["Blackbody Intensity"].default_value = 0.0
    pv.inputs["Density Attribute"].default_value = ""
    nt.links.new(math_node(nt, "MULTIPLY", attr(nt, "density"), dens), pv.inputs["Density"])
    nt.links.new(pv.outputs[0], out.inputs["Volume"])
    dom.data.materials.clear()
    dom.data.materials.append(mat)


def lights(sc, on):
    for o in list(sc.collection.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o)
    if not on:
        return
    # red from the right, green from above, blue from the left (Blender: x right, z up, the camera looks along +y)
    for name, col, rot in (("R", (1, 0, 0), (0, math.radians(90), 0)), ("G", (0, 1, 0), (0, 0, 0)),
                           ("B", (0, 0, 1), (0, math.radians(-90), 0))):
        ld = bpy.data.lights.new(name, "SUN")
        ld.color = col
        ld.energy = 3.2
        ld.angle = math.radians(8)
        lo = bpy.data.objects.new(name, ld)
        sc.collection.objects.link(lo)
        # a sun shines along its local -z: rotate so it comes FROM the named side
        lo.rotation_euler = rot


def render(sc, kind, pas):
    f0, n = SIMS[kind]["frames"]
    idx = range(n) if not PROBE else range(0, n, max(1, n // 4))
    for i in idx:
        sc.frame_set(f0 + i)
        sc.render.filepath = os.path.join(OUT, "%s_%s_%04d.png" % (kind, pas, i))
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(sc.render.filepath)
        px = im.pixels[:]
        mx = max(px[0::4]); bpy.data.images.remove(im)
        print("[fx] %s %s %d/%d max %.3f" % (kind, pas, i + 1, n, mx), flush=True)


def run(kind):
    sc, dom = build(kind)
    import time
    t0 = time.time()
    bake(sc, dom)
    print("[fx] baked %s in %.0f s" % (kind, time.time() - t0), flush=True)
    t0 = time.time()
    if kind in ("flame", "burst"):
        sc.render.film_transparent = False
        lights(sc, False)
        fire_material(dom, 4.0 if kind == "flame" else 2.4, 0.0 if kind == "flame" else 5.0)
        render(sc, kind, "fire")
    if kind in ("burst", "smoke"):
        sc.render.film_transparent = True
        lights(sc, True)
        smoke_material(dom, 26.0 if kind == "burst" else 18.0)
        render(sc, kind, "smoke")
    print("[fx] rendered %s in %.0f s" % (kind, time.time() - t0), flush=True)


for k in (["flame", "burst", "smoke"] if SIM == "all" else [SIM]):
    run(k)
