# The stones and crystals inside the camp waypoint's blue-fire braziers (waypoint overhaul, the rocks pass).
#
# From three Meshy models (a fractured basalt cluster, a second slabby rock cluster, a sapphire crystal cluster) this
# builds a library of unique pieces and four physically settled piles, one per brazier, and exports them in one glb
# that scripts/brazier_coals.gd reads:
#
#   blender -b --python rock_library.py -- <workdir> <out.glb> [--rocks a.glb b.glb ...] [--crystal c.glb]
#          [--stage1] [--stage3] [--tex 1024] [--ctex 512] [--seed 7] [--bowl brazier.glb] [--bowl-scale 1.15] [--sheet out.png]
#
# Stage 3 (--stage3): only the piles and the export, from the library the last stage 2 saved as <workdir>/library.blend.
# Stage 1 (--stage1, or when workdir has no solids yet): each Meshy model (a triangle soup split along its UV seams)
#   becomes a watertight solid: voxel remesh, decimate, smart unwrap, and a Cycles bake of Meshy's colour, normal and
#   roughness onto it (as tools/blender/camp/rebake_prop.py does). Saved as <workdir>/solid_<name>.blend.
# Stage 2: every rock solid is scaled to the bowl and **Voronoi-fractured** (planes between random seeds, every cut
#   capped): each cell is a stone whose outer skin keeps Meshy's weathered texture and whose fracture faces get a
#   procedural fresh-break material (layered dark basalt, mineral strata, speckle, a cellular crack mask), displaced
#   by noise so no break is flat. The crystal solid is cut into chunks between its prisms, and procedural hexagonal
#   prisms (tapered, chipped) join it. Every piece gets two LODs, all LOD0s are unwrapped into one rock atlas and one
#   crystal atlas and baked from the detailed cells (albedo, normal, roughness, AO, and the crack / vein mask into the
#   emissive map). Then four piles are settled with rigid-body physics in the real bowl (the cleaned brazier's dish,
#   at the game's scale): the crystals stand first, the stones fall round them. The glb holds the pieces
#   (`rock_NN_l0/l1`, `frag_NN_l0/l1`, `cry_NN_l0/l1`, children of `lib`) and the piles as Empties (`arr_K` with one
#   child per instance, named `<piece>` + extras {"piece", "cap"}), whose transforms are the instances (metres, the
#   bowl's floor at y = 0 of the brazier node... see BOWL_ORIGIN below).
#
# Blender 4.5, headless. Numbers: metres.
import bpy, bmesh, sys, math, os, random, time
import numpy as np
from mathutils import Vector, Matrix, noise

argv = sys.argv[sys.argv.index("--") + 1:]
WORK, OUT = argv[0], argv[1]
def opts(name, default):
    if name not in argv:
        return default
    i = argv.index(name) + 1
    vals = []
    while i < len(argv) and not argv[i].startswith("--"):
        vals.append(argv[i]); i += 1
    return vals
ROCK_SRC = opts("--rocks", [])
CRY_SRC = opts("--crystal", [])
TEX = int(opts("--tex", ["1024"])[0])
CTEX = int(opts("--ctex", ["512"])[0])
SEED = int(opts("--seed", ["7"])[0])
BOWL = opts("--bowl", [""])[0]
BOWL_SCALE = float(opts("--bowl-scale", ["1.15"])[0])
SHEET = opts("--sheet", [""])[0]
STAGE1 = "--stage1" in argv      # --stage3: piles and export only, from <workdir>/library.blend
os.makedirs(WORK, exist_ok=True)
random.seed(SEED)
T0 = time.time()
def log(*a):
    print("[rocks %5.0fs]" % (time.time() - T0), *a, flush=True)

# the bowl, measured by clean_bowl.py on the brazier model (model units; the game scales the model by BOWL_SCALE):
# the dish's floor, the lip (inner radius at the rim) and the rim height
DISH_FLOOR_Z, DISH_LIP_R, DISH_RIM_Z, DISH_WALL_R0 = 1.0551, 0.325, 1.1537, 0.25
ROCK_CLUSTER_SIZE = 0.36      # a rock cluster scaled to this across before fracturing -> stones of 2..14 cm
CRY_CLUSTER_H = 0.20          # the crystal cluster's height
N_PILES = 4

# ============================================================================ helpers
def select_only(obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    if obs:
        bpy.context.view_layer.objects.active = obs[0]

def verts_np(me):
    P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P)
    return P.reshape(-1, 3)

def set_verts(me, P):
    me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()

def tri_count(me):
    return sum(len(p.vertices) - 2 for p in me.polygons)

def image(name, size, color):
    img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if color else "Non-Color"
    img.generated_color = (0, 0, 0, 1)
    return img

def bake(nt, tex_nodes, target, btype, **kw):
    for n in nt.nodes:
        n.select = False
    tex_nodes[target].select = True
    nt.nodes.active = tex_nodes[target]
    bpy.ops.object.bake(type=btype, **kw)
    log("baked", target)

def save_reload(img, fmt, ext, quality=92):
    import tempfile
    path = os.path.join(WORK, "tex", img.name.replace(" ", "_") + "." + ext)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.file_format = fmt
    img.filepath_raw = path
    img.save(filepath=path, quality=quality)
    img.source = "FILE"
    img.reload()

def mesh_volume(me):
    bm = bmesh.new(); bm.from_mesh(me)
    v = bm.calc_volume(signed=False)
    bm.free()
    return v

def bbox(obj_or_me):
    me = obj_or_me.data if isinstance(obj_or_me, bpy.types.Object) else obj_or_me
    P = verts_np(me)
    return P.min(0), P.max(0)

# ============================================================================ stage 1: Meshy soup -> textured solid
def make_solid(src, name, tris=60000, voxel=0.0045, tex=2048):
    """Imports a Meshy glb and returns a watertight, smartly unwrapped solid carrying Meshy's colour, normal and
    roughness baked onto it (2048), with a material 'skin_<name>'. Centred on the ground."""
    log("stage 1:", name, "from", src)
    bpy.ops.import_scene.gltf(filepath=src)
    objs = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    for o in list(bpy.context.selected_objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    select_only(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    hi = bpy.context.view_layer.objects.active
    hi.name = "hi_" + name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    P = verts_np(hi.data)
    P[:, 0] -= 0.5 * (P[:, 0].min() + P[:, 0].max()); P[:, 1] -= 0.5 * (P[:, 1].min() + P[:, 1].max()); P[:, 2] -= P[:, 2].min()
    set_verts(hi.data, P)
    size = float(np.ptp(P, axis=0).max())
    lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "solid_" + name
    bpy.context.collection.objects.link(lo)
    select_only([lo])
    rm = lo.modifiers.new("remesh", "REMESH"); rm.mode = "VOXEL"; rm.voxel_size = voxel * size; rm.adaptivity = 0.0
    bpy.ops.object.modifier_apply(modifier="remesh")
    sm = lo.modifiers.new("smooth", "SMOOTH"); sm.iterations = 1; sm.factor = 0.5
    bpy.ops.object.modifier_apply(modifier="smooth")
    n = tri_count(lo.data)
    if n > tris:
        d = lo.modifiers.new("dec", "DECIMATE"); d.ratio = tris / n
        bpy.ops.object.modifier_apply(modifier="dec")
    for p in lo.data.polygons:
        p.use_smooth = True
    while lo.data.uv_layers:
        lo.data.uv_layers.remove(lo.data.uv_layers[0])
    lo.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(rotate=True, margin=2.5 / tex)
    bpy.ops.object.mode_set(mode="OBJECT")
    lo.data.materials.clear()
    img_alb, img_nrm, img_rgh = image(name + "_albedo", tex, True), image(name + "_normal", tex, False), image(name + "_rough", tex, False)
    mat = bpy.data.materials.new("skin_" + name); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
    lo.data.materials.append(mat)
    tn = {}
    for nm, img in (("albedo", img_alb), ("normal", img_nrm), ("rough", img_rgh)):
        tnode = nt.nodes.new("ShaderNodeTexImage"); tnode.image = img; tnode.name = nm; tn[nm] = tnode
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"; scene.cycles.samples = 4
    bk = scene.render.bake
    bk.use_selected_to_active = True; bk.cage_extrusion = 0.02 * size; bk.max_ray_distance = 0.1 * size; bk.margin = 8
    select_only([lo]); hi.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bake(nt, tn, "albedo", "DIFFUSE", pass_filter={"COLOR"})
    bake(nt, tn, "normal", "NORMAL")
    bake(nt, tn, "rough", "ROUGHNESS")
    nm_node = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(tn["albedo"].outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tn["normal"].outputs["Color"], nm_node.inputs["Color"])
    nt.links.new(nm_node.outputs["Normal"], bsdf.inputs["Normal"])
    nt.links.new(tn["rough"].outputs["Color"], bsdf.inputs["Roughness"])
    for img in (img_alb, img_nrm, img_rgh):
        img.pack()
    bpy.data.objects.remove(hi, do_unlink=True)
    log("solid", name, "tris", tri_count(lo.data), "size %.2f" % size)
    return lo

def stage1():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    names = []
    for i, src in enumerate(ROCK_SRC):
        names.append(("rock%d" % i, src))
    for i, src in enumerate(CRY_SRC):
        names.append(("cry%d" % i, src))
    for name, src in names:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        make_solid(src, name)
        path = os.path.join(WORK, "solid_%s.blend" % name)
        bpy.ops.wm.save_as_mainfile(filepath=path)
        log("saved", path)

# ============================================================================ stage 2 pieces
def load_solid(name):
    path = os.path.join(WORK, "solid_%s.blend" % name)
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = [o for o in src.objects if o.startswith("solid_")]
    obs = [o for o in dst.objects if o is not None]
    for o in obs:
        bpy.context.collection.objects.link(o)
    return obs[0]

def scale_to(ob, size=None, height=None):
    P = verts_np(ob.data)
    ext = np.ptp(P, axis=0)
    k = (size / ext.max()) if size else (height / ext[2])
    P *= k
    P[:, 0] -= 0.5 * (P[:, 0].min() + P[:, 0].max()); P[:, 1] -= 0.5 * (P[:, 1].min() + P[:, 1].max()); P[:, 2] -= P[:, 2].min()
    set_verts(ob.data, P)
    return k

# --- the fresh-break material: layered dark basalt by object coordinates, a cellular crack mask in the emission
def break_material(name, seed, strata_dir):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]; out = nt.nodes["Material Output"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping"); mp.vector_type = "POINT"
    mp.inputs["Location"].default_value = (seed * 0.37 % 7.0, seed * 0.61 % 5.0, seed * 0.13 % 3.0)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    # base: two dark greys mixed by a broad noise
    n1 = nt.nodes.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = 38.0; n1.inputs["Detail"].default_value = 6.0; n1.inputs["Roughness"].default_value = 0.62
    nt.links.new(mp.outputs["Vector"], n1.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.35; ramp.color_ramp.elements[0].color = (0.030, 0.030, 0.034, 1)
    ramp.color_ramp.elements[1].position = 0.72; ramp.color_ramp.elements[1].color = (0.085, 0.085, 0.092, 1)
    nt.links.new(n1.outputs["Fac"], ramp.inputs["Fac"])
    # mineral strata: bands along one direction, distorted
    mp2 = nt.nodes.new("ShaderNodeMapping"); mp2.vector_type = "POINT"
    d = Vector(strata_dir).normalized()
    rot = d.to_track_quat("Z", "Y").to_euler()
    mp2.inputs["Rotation"].default_value = (rot.x, rot.y, rot.z)
    nt.links.new(tc.outputs["Object"], mp2.inputs["Vector"])
    wave = nt.nodes.new("ShaderNodeTexWave"); wave.wave_type = "BANDS"; wave.bands_direction = "Z"
    wave.inputs["Scale"].default_value = 34.0; wave.inputs["Distortion"].default_value = 9.0; wave.inputs["Detail"].default_value = 4.0; wave.inputs["Detail Scale"].default_value = 3.0
    nt.links.new(mp2.outputs["Vector"], wave.inputs["Vector"])
    sramp = nt.nodes.new("ShaderNodeValToRGB")
    sramp.color_ramp.elements[0].position = 0.55; sramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    sramp.color_ramp.elements[1].position = 0.78; sramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(wave.outputs["Fac"], sramp.inputs["Fac"])
    mix1 = nt.nodes.new("ShaderNodeMix"); mix1.data_type = "RGBA"; mix1.blend_type = "MIX"
    mix1.inputs[7].default_value = (0.19, 0.185, 0.175, 1)       # the lighter mineral layer
    nt.links.new(ramp.outputs["Color"], mix1.inputs[6])
    sfac = nt.nodes.new("ShaderNodeMath"); sfac.operation = "MULTIPLY"; sfac.inputs[1].default_value = 0.22
    nt.links.new(sramp.outputs["Color"], sfac.inputs[0])
    nt.links.new(sfac.outputs["Value"], mix1.inputs[0])
    # speckle: fine high-frequency noise thresholded both ways (light grains, dark pits)
    n2 = nt.nodes.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = 420.0; n2.inputs["Detail"].default_value = 2.0; n2.inputs["Roughness"].default_value = 0.5
    nt.links.new(mp.outputs["Vector"], n2.inputs["Vector"])
    light = nt.nodes.new("ShaderNodeMath"); light.operation = "GREATER_THAN"; light.inputs[1].default_value = 0.66
    nt.links.new(n2.outputs["Fac"], light.inputs[0])
    dark = nt.nodes.new("ShaderNodeMath"); dark.operation = "LESS_THAN"; dark.inputs[1].default_value = 0.34
    nt.links.new(n2.outputs["Fac"], dark.inputs[0])
    mix2 = nt.nodes.new("ShaderNodeMix"); mix2.data_type = "RGBA"; mix2.inputs[7].default_value = (0.30, 0.30, 0.31, 1)
    nt.links.new(mix1.outputs[2], mix2.inputs[6])
    lf = nt.nodes.new("ShaderNodeMath"); lf.operation = "MULTIPLY"; lf.inputs[1].default_value = 0.6
    nt.links.new(light.outputs["Value"], lf.inputs[0]); nt.links.new(lf.outputs["Value"], mix2.inputs[0])
    mix3 = nt.nodes.new("ShaderNodeMix"); mix3.data_type = "RGBA"; mix3.inputs[7].default_value = (0.012, 0.012, 0.014, 1)
    nt.links.new(mix2.outputs[2], mix3.inputs[6])
    df = nt.nodes.new("ShaderNodeMath"); df.operation = "MULTIPLY"; df.inputs[1].default_value = 0.7
    nt.links.new(dark.outputs["Value"], df.inputs[0]); nt.links.new(df.outputs["Value"], mix3.inputs[0])
    # cracks: cellular edges, thin; they darken the stone and are the glow mask
    vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.feature = "DISTANCE_TO_EDGE"; vor.inputs["Scale"].default_value = 26.0; vor.inputs["Randomness"].default_value = 1.0
    nt.links.new(mp.outputs["Vector"], vor.inputs["Vector"])
    crack = nt.nodes.new("ShaderNodeMapRange"); crack.inputs["From Min"].default_value = 0.004; crack.inputs["From Max"].default_value = 0.03
    crack.inputs["To Min"].default_value = 1.0; crack.inputs["To Max"].default_value = 0.0
    nt.links.new(vor.outputs["Distance"], crack.inputs["Value"])
    # only some of the cells crack: a broad noise gate
    n3 = nt.nodes.new("ShaderNodeTexNoise"); n3.inputs["Scale"].default_value = 9.0; n3.inputs["Detail"].default_value = 1.0
    nt.links.new(mp.outputs["Vector"], n3.inputs["Vector"])
    gate = nt.nodes.new("ShaderNodeMapRange"); gate.inputs["From Min"].default_value = 0.42; gate.inputs["From Max"].default_value = 0.6
    nt.links.new(n3.outputs["Fac"], gate.inputs["Value"])
    cm = nt.nodes.new("ShaderNodeMath"); cm.operation = "MULTIPLY"
    nt.links.new(crack.outputs["Result"], cm.inputs[0]); nt.links.new(gate.outputs["Result"], cm.inputs[1])
    mix4 = nt.nodes.new("ShaderNodeMix"); mix4.data_type = "RGBA"; mix4.inputs[7].default_value = (0.006, 0.006, 0.008, 1)
    nt.links.new(mix3.outputs[2], mix4.inputs[6])
    cf = nt.nodes.new("ShaderNodeMath"); cf.operation = "MULTIPLY"; cf.inputs[1].default_value = 0.85
    nt.links.new(cm.outputs["Value"], cf.inputs[0]); nt.links.new(cf.outputs["Value"], mix4.inputs[0])
    nt.links.new(mix4.outputs[2], bsdf.inputs["Base Color"])
    # roughness: matte stone, the grains a little glassier
    rg = nt.nodes.new("ShaderNodeMapRange"); rg.inputs["From Min"].default_value = 0.0; rg.inputs["From Max"].default_value = 1.0
    rg.inputs["To Min"].default_value = 0.9; rg.inputs["To Max"].default_value = 0.55
    nt.links.new(light.outputs["Value"], rg.inputs["Value"])
    nt.links.new(rg.outputs["Result"], bsdf.inputs["Roughness"])
    # micro relief into the normal
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35; bump.inputs["Distance"].default_value = 0.002
    n4 = nt.nodes.new("ShaderNodeTexNoise"); n4.inputs["Scale"].default_value = 160.0; n4.inputs["Detail"].default_value = 5.0
    nt.links.new(mp.outputs["Vector"], n4.inputs["Vector"])
    nt.links.new(n4.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    # the mask: R = cracks (glow candidates) with a soft halo round them so the glow reads from afar, G = 0 (veins
    # are the crystals'), B = 0
    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(crack_halo(nt, vor.outputs["Distance"], gate.outputs["Result"], cm.outputs["Value"]), comb.inputs["Red"])
    nt.links.new(comb.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat

def crack_halo(nt, dist_socket, gate_socket, crack_socket):
    """max(crack, 0.35 * halo) * gate: the halo is a wide soft falloff from the same cellular edges."""
    halo = nt.nodes.new("ShaderNodeMapRange"); halo.inputs["From Min"].default_value = 0.0; halo.inputs["From Max"].default_value = 0.1
    halo.inputs["To Min"].default_value = 1.0; halo.inputs["To Max"].default_value = 0.0
    nt.links.new(dist_socket, halo.inputs["Value"])
    sq = nt.nodes.new("ShaderNodeMath"); sq.operation = "POWER"; sq.inputs[1].default_value = 2.2
    nt.links.new(halo.outputs["Result"], sq.inputs[0])
    hf = nt.nodes.new("ShaderNodeMath"); hf.operation = "MULTIPLY"; hf.inputs[1].default_value = 0.35
    nt.links.new(sq.outputs["Value"], hf.inputs[0])
    hg = nt.nodes.new("ShaderNodeMath"); hg.operation = "MULTIPLY"
    nt.links.new(hf.outputs["Value"], hg.inputs[0]); nt.links.new(gate_socket, hg.inputs[1])
    mx = nt.nodes.new("ShaderNodeMath"); mx.operation = "MAXIMUM"
    nt.links.new(crack_socket, mx.inputs[0]); nt.links.new(hg.outputs["Value"], mx.inputs[1])
    return mx.outputs["Value"]

def add_skin_cracks(mat, seed):
    """Gives a stage-1 skin material the same crack mask: dark lines on the colour, R of the emission."""
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
    alb_link = bsdf.inputs["Base Color"].links[0].from_socket
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Location"].default_value = (seed * 0.41 % 5.0, seed * 0.29 % 7.0, seed * 0.71 % 3.0)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.feature = "DISTANCE_TO_EDGE"; vor.inputs["Scale"].default_value = 20.0
    nt.links.new(mp.outputs["Vector"], vor.inputs["Vector"])
    crack = nt.nodes.new("ShaderNodeMapRange"); crack.inputs["From Min"].default_value = 0.004; crack.inputs["From Max"].default_value = 0.028
    crack.inputs["To Min"].default_value = 1.0; crack.inputs["To Max"].default_value = 0.0
    nt.links.new(vor.outputs["Distance"], crack.inputs["Value"])
    n3 = nt.nodes.new("ShaderNodeTexNoise"); n3.inputs["Scale"].default_value = 7.0; n3.inputs["Detail"].default_value = 1.0
    nt.links.new(mp.outputs["Vector"], n3.inputs["Vector"])
    gate = nt.nodes.new("ShaderNodeMapRange"); gate.inputs["From Min"].default_value = 0.5; gate.inputs["From Max"].default_value = 0.64
    nt.links.new(n3.outputs["Fac"], gate.inputs["Value"])
    cm = nt.nodes.new("ShaderNodeMath"); cm.operation = "MULTIPLY"
    nt.links.new(crack.outputs["Result"], cm.inputs[0]); nt.links.new(gate.outputs["Result"], cm.inputs[1])
    # the stone itself a little darker and colder than Meshy's mid grey, cracks darker still
    tint = nt.nodes.new("ShaderNodeMix"); tint.data_type = "RGBA"; tint.blend_type = "MULTIPLY"; tint.inputs[0].default_value = 1.0
    tint.inputs[7].default_value = (0.5, 0.51, 0.56, 1)
    nt.links.new(alb_link, tint.inputs[6])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.inputs[7].default_value = (0.006, 0.006, 0.008, 1)
    nt.links.new(tint.outputs[2], mix.inputs[6])
    cf = nt.nodes.new("ShaderNodeMath"); cf.operation = "MULTIPLY"; cf.inputs[1].default_value = 0.85
    nt.links.new(cm.outputs["Value"], cf.inputs[0]); nt.links.new(cf.outputs["Value"], mix.inputs[0])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(crack_halo(nt, vor.outputs["Distance"], gate.outputs["Result"], cm.outputs["Value"]), comb.inputs["Red"])
    nt.links.new(comb.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0

def crystal_material(name, seed):
    """Procedural sapphire for the modelled prisms: deep blue with cloudy inclusions, G of the emission = veins."""
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Location"].default_value = (seed * 0.53 % 5.0, seed * 0.17 % 7.0, seed * 0.83 % 3.0)
    mp.inputs["Scale"].default_value = (1.0, 1.0, 0.35)      # stretched along the prism
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    n1 = nt.nodes.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = 30.0; n1.inputs["Detail"].default_value = 5.0
    nt.links.new(mp.outputs["Vector"], n1.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3; ramp.color_ramp.elements[0].color = (0.008, 0.03, 0.16, 1)
    ramp.color_ramp.elements[1].position = 0.75; ramp.color_ramp.elements[1].color = (0.04, 0.16, 0.5, 1)
    nt.links.new(n1.outputs["Fac"], ramp.inputs["Fac"])
    # veins: stretched cellular edges
    vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.feature = "DISTANCE_TO_EDGE"; vor.inputs["Scale"].default_value = 18.0
    nt.links.new(mp.outputs["Vector"], vor.inputs["Vector"])
    vein = nt.nodes.new("ShaderNodeMapRange"); vein.inputs["From Min"].default_value = 0.003; vein.inputs["From Max"].default_value = 0.03
    vein.inputs["To Min"].default_value = 1.0; vein.inputs["To Max"].default_value = 0.0
    nt.links.new(vor.outputs["Distance"], vein.inputs["Value"])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.inputs[7].default_value = (0.25, 0.7, 1.0, 1)
    nt.links.new(ramp.outputs["Color"], mix.inputs[6])
    vf = nt.nodes.new("ShaderNodeMath"); vf.operation = "MULTIPLY"; vf.inputs[1].default_value = 0.6
    nt.links.new(vein.outputs["Result"], vf.inputs[0]); nt.links.new(vf.outputs["Value"], mix.inputs[0])
    nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.14
    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(vein.outputs["Result"], comb.inputs["Green"])
    nt.links.new(comb.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    return mat

def add_crystal_veins(mat):
    """The Meshy crystal's skin: its painted cyan veins become G of the emission (the vein mask)."""
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
    alb = bsdf.inputs["Base Color"].links[0].from_socket
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(alb, sep.inputs["Color"])
    # cyan veins: green well above red
    diff = nt.nodes.new("ShaderNodeMath"); diff.operation = "SUBTRACT"
    nt.links.new(sep.outputs["Green"], diff.inputs[0]); nt.links.new(sep.outputs["Red"], diff.inputs[1])
    vein = nt.nodes.new("ShaderNodeMapRange"); vein.inputs["From Min"].default_value = 0.12; vein.inputs["From Max"].default_value = 0.4
    nt.links.new(diff.outputs["Value"], vein.inputs["Value"])
    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(vein.outputs["Result"], comb.inputs["Green"])
    nt.links.new(comb.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.2
    if bsdf.inputs["Roughness"].is_linked:
        nt.links.remove(bsdf.inputs["Roughness"].links[0])

# --- Voronoi fracture
def fracture(ob, seeds, break_mat):
    """Cuts the closed mesh of `ob` into one closed cell per seed (planes halfway between seed pairs), capping every
    cut with faces of `break_mat` (material slot 1). Returns the cell objects (not yet displaced)."""
    me = ob.data
    if len(me.materials) < 2:
        me.materials.append(break_mat)
    base = bmesh.new(); base.from_mesh(me)
    cells = []
    for i, si in enumerate(seeds):
        bm = base.copy()
        for j, sj in enumerate(seeds):
            if i == j or len(bm.faces) == 0:
                continue
            n = sj - si
            if n.length < 1e-6:
                continue
            co = (si + sj) * 0.5
            n.normalize()
            # skip planes that miss the piece entirely (all vertices on the seed's side)
            ds = [(v.co - co).dot(n) for v in bm.verts]
            if max(ds) <= 0.0:
                continue
            if min(ds) >= 0.0:
                bm.free(); bm = None
                break
            bm.verts.ensure_lookup_table(); bm.edges.ensure_lookup_table(); bm.faces.ensure_lookup_table()
            res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=co, plane_no=n, clear_outer=True, clear_inner=False)
            cut = [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMEdge)]
            if cut:
                fill = bmesh.ops.edgenet_fill(bm, edges=cut)
                for f in fill["faces"]:
                    f.material_index = 1
                    f.smooth = True
        if bm is None or len(bm.faces) < 4:
            if bm is not None:
                bm.free()
            continue
        cme = bpy.data.meshes.new("cell")
        bm.to_mesh(cme); bm.free()
        cme.materials.append(me.materials[0]); cme.materials.append(break_mat)
        co = bpy.data.objects.new("cell", cme)
        bpy.context.collection.objects.link(co)
        cells.append(co)
    base.free()
    return cells

def roughen_caps(ob, amp, seed):
    """Subdivides the fracture faces to a few mm and heaves them with layered noise (interior cap vertices only, so
    the skin keeps its silhouette): no fracture is a flat plane."""
    me = ob.data
    bm = bmesh.new(); bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    caps = [f for f in bm.faces if f.material_index == 1]
    if not caps:
        bm.free(); return
    # triangulate the n-gon caps, then split their edges until they are short
    bmesh.ops.triangulate(bm, faces=caps)
    target = max(0.0035, amp * 1.6)
    for _ in range(4):
        caps = [f for f in bm.faces if f.material_index == 1]
        long_edges = set()
        for f in caps:
            for e in f.edges:
                if e.calc_length() > target:
                    long_edges.add(e)
        if not long_edges:
            break
        bmesh.ops.subdivide_edges(bm, edges=list(long_edges), cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if f.material_index == 1])
    # displace interior cap vertices along the cap normal
    caps = [f for f in bm.faces if f.material_index == 1]
    off = Vector((seed * 1.7, seed * 0.3, seed * 2.1))
    for v in set(v for f in caps for v in f.verts):
        if any(f.material_index != 1 for f in v.link_faces):
            continue        # on the skin's edge: fixed
        nrm = Vector((0, 0, 0))
        for f in v.link_faces:
            nrm += f.normal
        if nrm.length < 1e-9:
            continue
        nrm.normalize()
        p = v.co + off
        h = noise.noise(p * (6.0 / max(amp, 1e-4)) * 0.12) * 0.55 + noise.noise(p * (6.0 / max(amp, 1e-4)) * 0.5) * 0.3 + noise.noise(p * (6.0 / max(amp, 1e-4)) * 1.8) * 0.15
        # conchoidal ripples: a few broad shallow steps
        step = noise.noise(p * (2.0 / max(amp, 1e-4)) * 0.08)
        h += 0.35 * (abs(step) ** 0.6) * (1.0 if step > 0 else -1.0)
        v.co += nrm * (h * amp)
    for f in bm.faces:
        f.smooth = True
    bm.normal_update()
    bm.to_mesh(me); bm.free()
    me.update()

def decimate_copy(src, name, tris):
    ob = src.copy(); ob.data = src.data.copy(); ob.name = name
    bpy.context.collection.objects.link(ob)
    n = tri_count(ob.data)
    if n > tris:
        select_only([ob])
        d = ob.modifiers.new("dec", "DECIMATE"); d.ratio = max(0.01, tris / n); d.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="dec")
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob

def recentre(ob):
    """Moves the mesh so its bounding box centre is the origin; returns (radius, height, min_z_offset)."""
    P = verts_np(ob.data)
    c = 0.5 * (P.min(0) + P.max(0))
    P -= c
    set_verts(ob.data, P)
    ext = np.ptp(P, axis=0)
    return float(np.hypot(ext[0], ext[1]) * 0.5), float(ext[2]), float(-P[:, 2].min())

def unwrap(ob, tex, margin_px=3.0):
    select_only([ob])
    while ob.data.uv_layers:
        ob.data.uv_layers.remove(ob.data.uv_layers[0])
    ob.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")

def pack_joined(obs, tex):
    """Joins copies of `obs` into one object whose islands are packed together (one atlas); returns it. Each face
    carries the integer attribute `piece` = its index in `obs`, to split the joined mesh back into pieces."""
    copies = []
    for i, o in enumerate(obs):
        c = o.copy(); c.data = o.data.copy(); c.name = "pack_%d" % i
        bpy.context.collection.objects.link(c)
        attr = c.data.attributes.new("piece", "INT", "FACE")
        attr.data.foreach_set("value", [i] * len(c.data.polygons))
        copies.append(c)
    select_only(copies)
    bpy.ops.object.join()
    j = bpy.context.view_layer.objects.active
    j.name = "joined"
    bpy.context.scene.tool_settings.use_uv_select_sync = True     # the mesh selection is the UV selection
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin=3.0 / tex, margin_method="ADD")
    bpy.ops.object.mode_set(mode="OBJECT")
    return j

def split_joined(j, names):
    """Separates the packed object back into one object per piece (by the `piece` attribute), named by `names`."""
    out = {}
    attr = j.data.attributes["piece"]
    ids = np.empty(len(j.data.polygons), dtype=np.int32); attr.data.foreach_get("value", ids)
    bm = bmesh.new(); bm.from_mesh(j.data)
    bm.faces.ensure_lookup_table()
    lay = bm.faces.layers.int.get("piece")
    for pid in np.unique(ids):
        sub = bm.copy()
        sub.faces.ensure_lookup_table()
        kill = [f for f in sub.faces if f[sub.faces.layers.int.get("piece")] != pid]
        bmesh.ops.delete(sub, geom=kill, context="FACES")
        me = bpy.data.meshes.new(names[pid])
        sub.to_mesh(me); sub.free()
        for m in j.data.materials:
            me.materials.append(m)
        o = bpy.data.objects.new(names[pid], me)
        bpy.context.collection.objects.link(o)
        out[int(pid)] = o
    bm.free()
    return out

# --- procedural crystals
def make_prism(name, length, radius, seed, mat):
    rnd = random.Random(seed)
    sides = 6
    bm = bmesh.new()
    # an irregular hexagon, a slight twist and taper, a pointed tip of unequal facets, a chipped tip corner
    base_r = [radius * rnd.uniform(0.75, 1.15) for _ in range(sides)]
    ring0 = [bm.verts.new(Vector((math.cos(2 * math.pi * k / sides) * base_r[k], math.sin(2 * math.pi * k / sides) * base_r[k], 0.0))) for k in range(sides)]
    taper = rnd.uniform(0.8, 0.98)
    shoulder = length * rnd.uniform(0.72, 0.86)
    tw = rnd.uniform(-0.12, 0.12)
    ring1 = [bm.verts.new(Vector((math.cos(2 * math.pi * k / sides + tw) * base_r[k] * taper, math.sin(2 * math.pi * k / sides + tw) * base_r[k] * taper, shoulder))) for k in range(sides)]
    tip = bm.verts.new(Vector((rnd.uniform(-0.25, 0.25) * radius, rnd.uniform(-0.25, 0.25) * radius, length)))
    for k in range(sides):
        bm.faces.new((ring0[k], ring0[(k + 1) % sides], ring1[(k + 1) % sides], ring1[k]))
        bm.faces.new((ring1[k], ring1[(k + 1) % sides], tip))
    bm.faces.new(tuple(reversed(ring0)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    # a chip or two off the tip and an edge: planar cuts capped (the same break look as the stones, in crystal)
    select_only([ob])
    bm = bmesh.new(); bm.from_mesh(me)
    for c in range(rnd.randint(1, 3)):
        a = rnd.uniform(0, 2 * math.pi)
        at = Vector((math.cos(a) * radius * taper * 0.9, math.sin(a) * radius * taper * 0.9, shoulder + rnd.uniform(0.2, 0.7) * (length - shoulder)))
        n = (at - Vector((0, 0, shoulder * 0.9))).normalized()
        n = (n + Vector((rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(0.0, 0.4)))).normalized()
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=at - n * radius * 0.12, plane_no=n, clear_outer=True)
        cut = [g for g in res["geom_cut"] if isinstance(g, bmesh.types.BMEdge)]
        if cut:
            fill = bmesh.ops.edgenet_fill(bm, edges=cut)
            for f in fill["faces"]:
                f.smooth = False
    for f in bm.faces:
        f.smooth = False      # crystals are faceted: flat shading, the bake keeps it
    bm.to_mesh(me); bm.free()
    return ob

def make_cluster(name, seed, mat):
    """2-3 prisms grown from one spot, leaning apart, fused into one piece (a boolean union is not needed: the
    overlapping prisms are exported as they are; the shader is opaque)."""
    rnd = random.Random(seed)
    n = rnd.randint(2, 3)
    parts = []
    for k in range(n):
        L = rnd.uniform(0.07, 0.15) if k == 0 else rnd.uniform(0.045, 0.1)
        r = L * rnd.uniform(0.13, 0.2)
        p = make_prism("%s_p%d" % (name, k), L, r, seed * 10 + k, mat)
        a = rnd.uniform(0, 2 * math.pi)
        tilt = rnd.uniform(0.1, 0.45) if k else rnd.uniform(0.0, 0.2)
        p.rotation_euler = (tilt * math.cos(a), tilt * math.sin(a), rnd.uniform(0, 2 * math.pi))
        p.location = Vector((math.cos(a) * r * 0.9, math.sin(a) * r * 0.9, -L * 0.1)) if k else Vector((0, 0, -L * 0.08))
        parts.append(p)
    select_only(parts)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob

# --- the bowl for the physics settle (the cleaned brazier's dish at the game's scale)
def bowl_collider():
    if not BOWL or not os.path.exists(BOWL):
        # a lathe stand-in from the measured profile
        bm = bmesh.new()
        prof = [(0.0, DISH_FLOOR_Z), (0.1, DISH_FLOOR_Z + 0.003), (0.2, DISH_FLOOR_Z + 0.012), (DISH_WALL_R0, DISH_FLOOR_Z + 0.02), (0.29, 1.092), (0.31, 1.121), (DISH_LIP_R, DISH_RIM_Z), (0.36, DISH_RIM_Z), (0.36, DISH_RIM_Z - 0.3)]
        rings = []
        for r, z in prof:
            rings.append([bm.verts.new(Vector((math.cos(2 * math.pi * k / 48) * max(r, 1e-4), math.sin(2 * math.pi * k / 48) * max(r, 1e-4), z))) for k in range(48)])
        for i in range(len(rings) - 1):
            for k in range(48):
                bm.faces.new((rings[i][k], rings[i][(k + 1) % 48], rings[i + 1][(k + 1) % 48], rings[i + 1][k]))
        me = bpy.data.meshes.new("bowl"); bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.new("bowl", me); bpy.context.collection.objects.link(ob)
    else:
        bpy.ops.import_scene.gltf(filepath=BOWL)
        objs = [o for o in bpy.context.selected_objects if o.type == "MESH"]
        for o in list(bpy.context.selected_objects):
            if o.type != "MESH":
                bpy.data.objects.remove(o, do_unlink=True)
        select_only(objs)
        if len(objs) > 1:
            bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        ob.name = "bowl"
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        # keep the bowl only (the dish, its wall and rim), the stem is irrelevant
        bm = bmesh.new(); bm.from_mesh(ob.data)
        kill = [f for f in bm.faces if f.calc_center_median().z < DISH_FLOOR_Z - 0.08]
        bmesh.ops.delete(bm, geom=kill, context="FACES")
        bm.to_mesh(ob.data); bm.free()
    P = verts_np(ob.data) * BOWL_SCALE
    set_verts(ob.data, P)
    return ob

def settle(pile_i, stones, crystals, bowl, rnd):
    """Rigid-body settle of `stones` (active, convex hulls) round `crystals` (passive, placed standing) in the bowl.
    Returns [(object, Matrix)] for everything that came to rest inside the bowl."""
    scene = bpy.context.scene
    floor = DISH_FLOOR_Z * BOWL_SCALE
    lip = DISH_LIP_R * BOWL_SCALE
    if scene.rigidbody_world is None:
        bpy.ops.rigidbody.world_add()
    rbw = scene.rigidbody_world
    rbw.substeps_per_frame = 40
    rbw.solver_iterations = 30
    scene.frame_start = 1; scene.frame_end = 240
    rbw.point_cache.frame_start = 1; rbw.point_cache.frame_end = 240
    def add_rb(o, kind, shape):
        with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o], selected_editable_objects=[o]):
            bpy.ops.rigidbody.object_add(type=kind)
        rb = o.rigid_body
        rb.collision_shape = shape
        rb.use_margin = True
        rb.collision_margin = 0.001
        rb.friction = 0.85
        rb.restitution = 0.02
        rb.linear_damping = 0.2
        rb.angular_damping = 0.4
        return rb
    add_rb(bowl, "PASSIVE", "MESH")
    bowl.rigid_body.collision_margin = 0.004
    bowl.rigid_body.friction = 0.9
    # crystals: a cluster near the middle, singles further out, leaning away from the centre, their bases sunk into
    # the stones to come
    placed = []
    for k, c in enumerate(crystals):
        if k == 0:
            r = rnd.uniform(0.0, 0.07); a = rnd.uniform(0, 2 * math.pi)
            tilt = rnd.uniform(0.05, 0.22)
        else:
            r = rnd.uniform(0.11, 0.2); a = rnd.uniform(0, 2 * math.pi)
            # keep singles apart from each other and the cluster
            for _ in range(20):
                ok = all(math.hypot(r * math.cos(a) - p[0], r * math.sin(a) - p[1]) > 0.1 for p in placed)
                if ok:
                    break
                r = rnd.uniform(0.1, 0.21); a = rnd.uniform(0, 2 * math.pi)
            tilt = rnd.uniform(0.25, 0.55)
        placed.append((r * math.cos(a), r * math.sin(a)))
        # the base of a crystal sits in the stone layer: the centrepiece low (its own rock shows), the singles higher
        c.location = Vector((r * math.cos(a), r * math.sin(a), floor + (0.03 if k == 0 else 0.055) + float(c["base"])))
        # lean outward: rotate about the horizontal axis perpendicular to the radial direction
        lean_axis = Vector((-math.sin(a), math.cos(a), 0.0))
        c.rotation_euler = (Matrix.Rotation(tilt, 4, lean_axis) @ Matrix.Rotation(rnd.uniform(0, 2 * math.pi), 4, "Z")).to_euler()
        add_rb(c, "PASSIVE", "CONVEX_HULL")
    # an invisible tube over the rim while they settle (the real bowl is only 11 cm deep): nothing bounces out;
    # whatever still rests outside the lip afterwards is dropped
    bm = bmesh.new()
    rings = [[bm.verts.new(Vector((math.cos(2 * math.pi * k / 40) * (lip + 0.012), math.sin(2 * math.pi * k / 40) * (lip + 0.012), z))) for k in range(40)]
             for z in (DISH_RIM_Z * BOWL_SCALE - 0.03, DISH_RIM_Z * BOWL_SCALE + 0.4)]
    for k in range(40):
        bm.faces.new((rings[0][k], rings[0][(k + 1) % 40], rings[1][(k + 1) % 40], rings[1][k]))
    tube_me = bpy.data.meshes.new("tube"); bm.to_mesh(tube_me); bm.free()
    tube = bpy.data.objects.new("tube", tube_me); bpy.context.collection.objects.link(tube)
    add_rb(tube, "PASSIVE", "MESH")
    tube.rigid_body.collision_margin = 0.004
    # stones: big ones first, in loose layers above the rim (nothing starts inside the dish's sloping wall or
    # another stone: a crash would fling them), spaced by their radii, clear of the crystals
    stones = sorted(stones, key=lambda o: -o["radius"])
    layers = []
    cry_xy = placed[:]
    for i, s in enumerate(stones):
        rs = float(s["radius"])
        spot = None
        for li in range(12):
            while len(layers) <= li:
                layers.append([])
            for _ in range(80):
                rr = rnd.uniform(0.0, max(0.02, lip - 0.02 - rs)) * (0.5 + 0.5 * rnd.random())
                a = rnd.uniform(0, 2 * math.pi)
                x, y = rr * math.cos(a), rr * math.sin(a)
                if all(math.hypot(x - q[0], y - q[1]) > rs + q[2] + 0.006 for q in layers[li]) and \
                        all(math.hypot(x - c[0], y - c[1]) > rs + 0.025 for c in cry_xy):
                    spot = (x, y, li)
                    break
            if spot:
                break
        if spot is None:
            spot = (0.0, 0.0, len(layers))
            layers.append([])
        x, y, li = spot
        layers[li].append((x, y, rs))
        s.location = Vector((x, y, DISH_RIM_Z * BOWL_SCALE + 0.015 + rs + 0.085 * li))
        s.rotation_euler = (rnd.uniform(0, 2 * math.pi), rnd.uniform(0, 2 * math.pi), rnd.uniform(0, 2 * math.pi))
        rb = add_rb(s, "ACTIVE", "CONVEX_HULL")
        rb.mass = max(0.01, 2600.0 * s["volume"])
        rb.angular_damping = 0.6
    # run
    rbw.point_cache.frame_end = scene.frame_end
    for f in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(f)
    bpy.context.view_layer.update()
    out = []
    for c in crystals:
        out.append((c, c.matrix_world.copy()))
    lost = 0
    for s in stones:
        m = s.matrix_world.copy()
        p = m.translation
        if math.hypot(p.x, p.y) > lip + 0.02 or p.z < floor - 0.004 or p.z > floor + 0.45:
            lost += 1
            log("  lost", s.name, "at %.2f %.2f %.2f" % (p.x, p.y, p.z))
            continue
        out.append((s, m))
    log("pile", pile_i, "settled", len(out), "pieces, lost", lost)
    # tear the rigid bodies down for the next pile
    for o in stones + crystals + [bowl, tube]:
        with bpy.context.temp_override(object=o, active_object=o, selected_objects=[o], selected_editable_objects=[o]):
            bpy.ops.rigidbody.object_remove()
        o.location = (0, 0, 0); o.rotation_euler = (0, 0, 0)
    bpy.data.objects.remove(tube, do_unlink=True)
    rbw.point_cache.frame_end = 1
    scene.frame_set(1)
    return out

# ============================================================================ stage 2
def stage2():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"; scene.cycles.device = "CPU"
    rnd = random.Random(SEED)
    rock_names = ["rock%d" % i for i in range(len(ROCK_SRC))]
    cry_names = ["cry%d" % i for i in range(len(CRY_SRC))]
    # --- hi pieces: fractured rock cells
    hi_rocks = []
    for ri, name in enumerate(rock_names):
        solid = load_solid(name)
        scale_to(solid, size=ROCK_CLUSTER_SIZE * (1.0 if ri == 0 else 0.86))
        add_skin_cracks(solid.data.materials[0], SEED + ri)
        lo_b, hi_b = bbox(solid)
        # seeds: a sparse set for the big stones and two clustered bunches for medium ones
        seeds = []
        n_big = 11 if ri == 0 else 10
        for _ in range(n_big):
            seeds.append(Vector((rnd.uniform(lo_b[0], hi_b[0]), rnd.uniform(lo_b[1], hi_b[1]), rnd.uniform(lo_b[2], hi_b[2]))))
        for _ in range(2):
            cx = Vector((rnd.uniform(lo_b[0], hi_b[0]), rnd.uniform(lo_b[1], hi_b[1]), rnd.uniform(lo_b[2], hi_b[2])))
            for _ in range(rnd.randint(4, 6)):
                seeds.append(cx + Vector((rnd.gauss(0, 0.05), rnd.gauss(0, 0.05), rnd.gauss(0, 0.05))))
        bmat = break_material("break_%s" % name, SEED * 3 + ri, (rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.3, 1.0)))
        cells = fracture(solid, seeds, bmat)
        bpy.data.objects.remove(solid, do_unlink=True)
        log("fractured", name, "into", len(cells), "cells")
        def keep(c):
            vol = mesh_volume(c.data)
            lo_c, hi_c = bbox(c)
            ext = hi_c - lo_c
            if vol < 1.0e-6 or ext.max() < 0.012 or ext.min() < 0.004:   # slivers and dust: gone
                bpy.data.objects.remove(c, do_unlink=True)
                return False
            c["volume"] = vol
            return True
        cells = [c for c in cells if keep(c)]
        # a second break: some medium cells shatter further into the fragments and gravel that lie between the
        # stones (their new faces are breaks too)
        cells.sort(key=lambda o: -o["volume"])
        again = [c for c in cells if 0.04 < float((bbox(c)[1] - bbox(c)[0]).max()) < 0.12]
        rnd.shuffle(again)
        for c in again[:6 if ri == 0 else 5]:
            lo_c, hi_c = bbox(c)
            sub_seeds = [Vector((rnd.uniform(lo_c[0], hi_c[0]), rnd.uniform(lo_c[1], hi_c[1]), rnd.uniform(lo_c[2], hi_c[2]))) for _ in range(rnd.randint(7, 11))]
            subs = fracture(c, sub_seeds, bmat)
            cells.remove(c)
            bpy.data.objects.remove(c, do_unlink=True)
            cells += [s for s in subs if keep(s)]
        hi_rocks += cells
    # --- hi pieces: the crystal cluster cut into chunks between its prisms, plus procedural prisms and clusters
    hi_crys = []
    cmat = crystal_material("crystal_proc", SEED)
    for ci, name in enumerate(cry_names):
        solid = load_solid(name)
        scale_to(solid, height=CRY_CLUSTER_H)
        add_crystal_veins(solid.data.materials[0])
        lo_b, hi_b = bbox(solid)
        bmat = break_material("break_%s" % name, SEED * 5 + ci, (0.2, 0.3, 1.0))
        cx = 0.5 * (lo_b[0] + hi_b[0]); cy = 0.5 * (lo_b[1] + hi_b[1])
        seeds = []
        for k in range(3):
            a = 2 * math.pi * k / 3 + rnd.uniform(-0.3, 0.3)
            seeds.append(Vector((cx + math.cos(a) * 0.05, cy + math.sin(a) * 0.05, 0.04)))
        chunks = fracture(solid, seeds, bmat)
        bpy.data.objects.remove(solid, do_unlink=True)
        for c in chunks:
            c["volume"] = mesh_volume(c.data)
            c["sub"] = "chunk"
            hi_crys.append(c)
        log("crystal cluster cut into", len(chunks), "chunks")
    for k in range(6):
        p = make_prism("cryp_%d" % k, rnd.uniform(0.06, 0.15), rnd.uniform(0.011, 0.022), SEED * 7 + k, cmat)
        p["volume"] = mesh_volume(p.data); p["sub"] = "prism"
        hi_crys.append(p)
    for k in range(3):
        c = make_cluster("cryc_%d" % k, SEED * 11 + k, cmat)
        c["volume"] = mesh_volume(c.data); c["sub"] = "cluster"
        hi_crys.append(c)
    # --- roughen the fracture faces of every stone (the chunks' too), then classify and name
    pieces = []       # dicts: hi, lo0, lo1, name, kind, sub, radius, height, volume, cap
    for i, c in enumerate(sorted(hi_rocks, key=lambda o: -o["volume"])):
        lo_c, hi_c = bbox(c)
        size = float((hi_c - lo_c).max())
        if size > 0.12:       # a cell bigger than a fist: scaled down to the biggest stone the bowl takes
            P = verts_np(c.data) * (0.12 / size); set_verts(c.data, P)
            c["volume"] = float(c["volume"]) * (0.12 / size) ** 3
            size = 0.12
        roughen_caps(c, amp=max(0.0025, size * 0.03), seed=SEED + i)
        kind = "rock" if size >= 0.055 else "frag"
        pieces.append({"hi": c, "kind": kind, "sub": kind, "size": size, "volume": float(c["volume"])})
    for i, c in enumerate(hi_crys):
        if c.name.startswith("cell"):
            lo_c, hi_c = bbox(c)
            roughen_caps(c, amp=max(0.002, float((hi_c - lo_c).max()) * 0.02), seed=SEED + 100 + i)
        lo_c, hi_c = bbox(c)
        pieces.append({"hi": c, "kind": "cry", "sub": str(c["sub"]), "size": float((hi_c - lo_c).max()), "volume": float(c["volume"])})
    counts = {"rock": 0, "frag": 0, "cry": 0}
    for p in pieces:
        p["name"] = "%s_%02d" % (p["kind"], counts[p["kind"]])
        counts[p["kind"]] += 1
        p["hi"].name = "hi_" + p["name"]
    log("pieces:", counts, "sizes (cm):", sorted(int(round(p["size"] * 100)) for p in pieces if p["kind"] != "cry"))
    if "--dry" in argv:          # only the fracture statistics
        sys.exit(0)
    # --- lo pieces: two LODs per piece; the hi and the lo are centred together so the bake lines up
    for p in pieces:
        hi = p["hi"]
        P = verts_np(hi.data); c = 0.5 * (P.min(0) + P.max(0)); set_verts(hi.data, P - c)
        t0 = {"rock": 700, "frag": 160, "cry": 260}[p["kind"]]
        if p["kind"] == "rock":
            t0 = int(260 + 440 * min(1.0, (p["size"] - 0.045) / 0.1))
        if p["kind"] == "cry" and p["sub"] == "chunk":
            t0 = 420
        lo0 = decimate_copy(hi, p["name"] + "_l0", t0)
        P = verts_np(lo0.data)
        ext = np.ptp(P, axis=0)
        r, h, base = float(np.hypot(ext[0], ext[1]) * 0.5), float(ext[2]), float(-P[:, 2].min())
        p["lo0"] = lo0; p["radius"] = r; p["height"] = h; p["base"] = base
        caps = sum(1 for f in lo0.data.polygons if f.material_index == 1)
        p["cap"] = caps / max(1, len(lo0.data.polygons))
        unwrap(lo0, TEX if p["kind"] != "cry" else CTEX)
    # --- the atlases: join, pack, bake from the hi pieces, split back
    final = {}
    for group, tex in (("rock", TEX), ("cry", CTEX)):
        members = [p for p in pieces if (p["kind"] == "cry") == (group == "cry")]
        if not members:
            continue
        # spread the hi and lo pieces out on a grid so no piece's rays reach a neighbour
        cols = int(math.ceil(math.sqrt(len(members))))
        for i, p in enumerate(members):
            off = Vector(((i % cols) * 0.5, (i // cols) * 0.5, 0.0))
            p["hi"].location = off; p["lo0"].location = off
        bpy.context.view_layer.update()
        joined = pack_joined([p["lo0"] for p in members], tex)
        # the joined object has the pieces at their offsets baked into the mesh (join applies transforms)
        joined.data.materials.clear()
        img_alb, img_nrm, img_rgh, img_ao, img_msk = (image(group + "_albedo", tex, True), image(group + "_normal", tex, False),
                                                     image(group + "_rough", tex, False), image(group + "_ao", tex, False), image(group + "_glow", tex, False))
        mat = bpy.data.materials.new("coals_" + group); mat.use_nodes = True
        nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
        joined.data.materials.append(mat)
        tn = {}
        for nm, img in (("albedo", img_alb), ("normal", img_nrm), ("rough", img_rgh), ("ao", img_ao), ("glow", img_msk)):
            tnode = nt.nodes.new("ShaderNodeTexImage"); tnode.image = img; tnode.name = nm; tn[nm] = tnode
        bk = scene.render.bake
        bk.use_selected_to_active = True; bk.cage_extrusion = 0.0035; bk.max_ray_distance = 0.014; bk.margin = 6
        bk.use_clear = True
        # one high-poly source object (Cycles re-syncs the scene once per selected source: with ~90 pieces that
        # cost more than the rays did), so the hi pieces are joined for the bake
        hi_all = []
        for p in members:
            c = p["hi"].copy(); c.data = p["hi"].data.copy()
            bpy.context.collection.objects.link(c)
            hi_all.append(c)
        select_only(hi_all)
        if len(hi_all) > 1:
            bpy.ops.object.join()
        hi_joined = bpy.context.view_layer.objects.active
        hi_joined.name = "hi_joined"
        select_only([joined])
        hi_joined.select_set(True)
        bpy.context.view_layer.objects.active = joined
        scene.cycles.samples = 2
        bake(nt, tn, "albedo", "DIFFUSE", pass_filter={"COLOR"})
        bake(nt, tn, "normal", "NORMAL")
        bake(nt, tn, "rough", "ROUGHNESS")
        bake(nt, tn, "glow", "EMIT")
        scene.cycles.samples = 8
        bake(nt, tn, "ao", "AO")
        # pack: ORM = (AO, rough, 0); save every map in its format
        r = np.array(img_rgh.pixels[:]).reshape(-1, 4); ao = np.array(img_ao.pixels[:]).reshape(-1, 4)
        img_orm = image(group + "_metal_rough", tex, False)
        orm = np.ones_like(r); orm[:, 0] = ao[:, 0]; orm[:, 1] = r[:, 0]; orm[:, 2] = 0.0
        img_orm.pixels.foreach_set(orm.reshape(-1).astype(np.float32))
        for n in list(nt.nodes):
            if n.name in ("rough", "ao"):
                nt.nodes.remove(n)
        on = nt.nodes.new("ShaderNodeTexImage"); on.image = img_orm
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nm_node = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(tn["albedo"].outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(tn["normal"].outputs["Color"], nm_node.inputs["Color"])
        nt.links.new(nm_node.outputs["Normal"], bsdf.inputs["Normal"])
        nt.links.new(on.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        nt.links.new(tn["glow"].outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
        # occlusion for glTF: the exporter reads it from the "glTF Material Output" group
        grp = bpy.data.node_groups.get("glTF Material Output")
        if grp is None:
            grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
            grp.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
        gn = nt.nodes.new("ShaderNodeGroup"); gn.node_tree = grp
        nt.links.new(sep.outputs["Red"], gn.inputs["Occlusion"])
        save_reload(img_alb, "JPEG", "jpg"); save_reload(img_nrm, "PNG", "png"); save_reload(img_orm, "PNG", "png"); save_reload(img_msk, "PNG", "png")
        bpy.data.objects.remove(hi_joined, do_unlink=True)
        # split back into pieces and make the LOD1s (the old lo0 objects give their names up first)
        for p in members:
            p["lo0"].name = "tmp_" + p["name"]
        objs = split_joined(joined, [p["name"] + "_l0" for p in members])
        bpy.data.objects.remove(joined, do_unlink=True)
        for i, p in enumerate(members):
            bpy.data.objects.remove(p["lo0"], do_unlink=True)
            o = objs[i]
            P = verts_np(o.data); P -= np.array([(i % cols) * 0.5, (i // cols) * 0.5, 0.0]); set_verts(o.data, P)
            p["lo0"] = o
            t1 = max(40, tri_count(o.data) // 4)
            p["lo1"] = decimate_copy(o, p["name"] + "_l1", t1)
            bpy.data.objects.remove(p["hi"], do_unlink=True)
            p["hi"] = None
            final[p["name"]] = p
    log("library: %d pieces, LOD0 tris %d, LOD1 tris %d" % (len(final), sum(tri_count(p["lo0"].data) for p in final.values()), sum(tri_count(p["lo1"].data) for p in final.values())))
    # the library is saved (images packed) so the piles and the export can be redone without the bakes (--stage3)
    for p in final.values():
        for o in (p["lo0"], p["lo1"]):
            for key in ("radius", "height", "base", "cap", "volume", "size"):
                o[key] = float(p[key])
            o["kind"] = p["kind"]; o["sub"] = p["sub"]; o["piece"] = p["name"]
    for img in bpy.data.images:
        if img.source == "FILE" and not img.packed_file:
            img.pack()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(WORK, "library.blend"))
    log("saved", os.path.join(WORK, "library.blend"))
    return final

def load_library():
    """Rebuilds the `final` piece table from a saved library.blend (--stage3)."""
    bpy.ops.wm.open_mainfile(filepath=os.path.join(WORK, "library.blend"))
    final = {}
    for o in bpy.context.scene.objects:
        if o.type != "MESH" or "piece" not in o:
            continue
        nm = str(o["piece"])
        p = final.setdefault(nm, {"name": nm, "hi": None})
        p["l" + o.name[-1]] = o
        for key in ("radius", "height", "base", "cap", "volume", "size"):
            p[key] = float(o[key])
        p["kind"] = str(o["kind"]); p["sub"] = str(o["sub"])
    for p in final.values():
        p["lo0"] = p.pop("l0"); p["lo1"] = p.pop("l1")
    log("loaded library: %d pieces" % len(final))
    return final

def stage3(final):
    """The four piles, settled in the bowl, and the export."""
    bowl = bowl_collider()
    rocks = [p for p in final.values() if p["kind"] == "rock"]
    frags = [p for p in final.values() if p["kind"] == "frag"]
    crys = [p for p in final.values() if p["kind"] == "cry"]
    for p in final.values():
        o = p["lo0"]
        o["radius"] = p["radius"]; o["volume"] = p["volume"]; o["base"] = p["base"]
        o["piece"] = p["name"]; o["cap"] = p["cap"]
    chunks = [c for c in crys if c["sub"] == "chunk"]
    clusters = [c for c in crys if c["sub"] == "cluster"]
    prisms = [c for c in crys if c["sub"] == "prism"]
    piles = []
    for k in range(N_PILES):
        prnd = random.Random(SEED * 100 + k)
        n_rock = min(len(rocks), prnd.randint(8, 10)); n_frag = min(len(frags), prnd.randint(14, 18))
        chosen = prnd.sample(rocks, n_rock) + prnd.sample(frags, n_frag)
        # crystals: the centrepiece is a chunk of the Meshy cluster (one per pile while they last, then a
        # procedural cluster) with 1-2 single prisms round it; no two piles share a centrepiece
        centres = chunks + clusters
        pick = [centres[k % len(centres)]] if centres else []
        pick += prnd.sample(prisms, min(len(prisms), prnd.randint(1, 2)))
        res = settle(k, [p["lo0"] for p in chosen], [p["lo0"] for p in pick], bowl, prnd)
        piles.append(res)
    bpy.data.objects.remove(bowl, do_unlink=True)
    # --- export: the library under `lib` at the origin, the piles as Empties
    lib = bpy.data.objects.new("lib", None); bpy.context.collection.objects.link(lib)
    for p in final.values():
        for o in (p["lo0"], p["lo1"]):
            o.parent = lib
            o.location = (0, 0, 0); o.rotation_euler = (0, 0, 0); o.scale = (1, 1, 1)
            o["radius"] = p["radius"]; o["height"] = p["height"]; o["base"] = p["base"]; o["cap"] = p["cap"]; o["kind"] = p["kind"]
            for key in ("volume", "sink", "piece", "size", "sub"):
                if key in o:
                    del o[key]
    for k, res in enumerate(piles):
        arr = bpy.data.objects.new("arr_%d" % k, None); bpy.context.collection.objects.link(arr)
        for i, (o, m) in enumerate(res):
            e = bpy.data.objects.new("i%02d_%s" % (i, o.name[:-3]), None)
            bpy.context.collection.objects.link(e)
            e.parent = arr
            e.matrix_world = m
            e["piece"] = o.name[:-3]
            e["cap"] = float(o["cap"]) if "cap" in o else 0.0
            e.empty_display_size = 0.02
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_extras=True,
                              export_image_format="AUTO", export_jpeg_quality=92, export_apply=True)
    log("EXPORTED", OUT)
    if SHEET:
        contact_sheet(final, SHEET)

def contact_sheet(final, path):
    """Every LOD0 piece laid out on a grid, lit, rendered with Eevee (for review)."""
    import mathutils
    scene = bpy.context.scene
    for o in list(bpy.context.scene.objects):
        if o.type == "EMPTY" and o.name.startswith("arr_"):
            for c in o.children:
                bpy.data.objects.remove(c, do_unlink=True)
            bpy.data.objects.remove(o, do_unlink=True)
    names = sorted(final)
    cols = int(math.ceil(math.sqrt(len(names))))
    cell = 0.2
    for i, nm in enumerate(names):
        p = final[nm]
        p["lo1"].hide_render = True
        o = p["lo0"]
        o.parent = None
        o.location = ((i % cols) * cell, -(i // cols) * cell, p["base"])
    n_rows = int(math.ceil(len(names) / cols))
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x, scene.render.resolution_y = 1600, int(1600 * n_rows / cols)
    scene.world = bpy.data.worlds.new("w"); scene.world.color = (0.06, 0.06, 0.07)
    bpy.ops.mesh.primitive_plane_add(size=cols * cell * 2, location=((cols - 1) * cell * 0.5, -(n_rows - 1) * cell * 0.5, 0))
    g = bpy.context.object; gm = bpy.data.materials.new("g"); gm.diffuse_color = (0.14, 0.13, 0.12, 1); g.data.materials.append(gm)
    sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.5; so = bpy.data.objects.new("sun", sun); scene.collection.objects.link(so)
    so.rotation_euler = (math.radians(45), 0, math.radians(30))
    blue = bpy.data.lights.new("blue", "POINT"); blue.energy = 40; blue.color = (0.3, 0.55, 1.0)
    bo = bpy.data.objects.new("blue", blue); scene.collection.objects.link(bo); bo.location = ((cols - 1) * cell * 0.5, -(n_rows - 1) * cell * 0.5, 0.5)
    cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"; cam.ortho_scale = cols * cell * 1.05
    co = bpy.data.objects.new("c", cam); scene.collection.objects.link(co); scene.camera = co
    co.location = ((cols - 1) * cell * 0.5, -(n_rows - 1) * cell * 0.5 - 1.0, 2.0)
    co.rotation_euler = (math.radians(27), 0, 0)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    log("SHEET", path)

if "--stage3" in argv:
    stage3(load_library())
else:
    if STAGE1 or not all(os.path.exists(os.path.join(WORK, "solid_%s.blend" % n)) for n in ["rock%d" % i for i in range(len(ROCK_SRC))] + ["cry%d" % i for i in range(len(CRY_SRC))]):
        stage1()
    stage3(stage2())
