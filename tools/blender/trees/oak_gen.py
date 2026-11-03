# Grows an oak's trunk and boughs in Blender for Flora.oak_model (visual overhaul): a clean replacement for the Meshy
# oaks, whose crowns were crumpled sheets of triangle shards and whose UV atlas (5,000 islands) kept Godot from
# making LODs. The game hangs its own leaf clusters on the crown (Flora.OAK_LEAVES), so this is wood only.
#
#   blender -b --python tools/blender/trees/oak_gen.py -- <out.glb> [--style broad|forked|bent] [--seed N]
#       [--tex 1024] [--height 6.2] [--preview out.png]
#
# The tree: a trunk with buttress roots flaring into the ground, forking into gnarled limbs that split three or four
# times down to twigs, each a tapered tube (8/6/5/4 sides by size) that bends with noise, rises toward the light and
# droops when thin. Each branch has two UV maps: "param" (round it 0..1, along it in metres) drives the procedural
# bark; "UVMap" packs every branch as one island (a hundred or so in all) for the baked textures, so the importer
# can simplify the mesh into LODs. Bark: furrowed ridges running along each branch (seamless round it), lighter
# ridge tops, dark furrows with moss on their upper side, lichen spots; baked to colour, normal and
# roughness/metal maps. Trunk on the origin, base at y = 0, about --height metres tall (prep_tree.py's conventions).
import bpy, bmesh, sys, math, random
import numpy as np
from mathutils import Vector, Matrix, noise

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
STYLE = opt("--style", "broad")
SEED = int(opt("--seed", "1"))
TEX = int(opt("--tex", "1024"))
HEIGHT = float(opt("--height", "6.2"))
PREVIEW = opt("--preview", "")
SHAPE_ONLY = "--shape-only" in argv
rng = random.Random(SEED)

STYLES = {
    # trunk length to the first fork, base radius, limbs at the fork, their spread from vertical (deg), levels,
    # lean of the trunk (deg), how much the limbs rise toward the light, limb length, child angle range (deg)
    "broad": {"trunk": 2.0, "r0": 0.44, "limbs": (4, 5), "spread": (52, 76), "levels": 3, "lean": 4, "rise": 0.1, "len": 3.5, "kid": (35, 65)},
    "forked": {"trunk": 1.7, "r0": 0.43, "limbs": (3, 3), "spread": (20, 38), "levels": 3, "lean": 3, "rise": 0.22, "len": 3.6, "kid": (30, 55)},
    "bent": {"trunk": 2.4, "r0": 0.42, "limbs": (3, 4), "spread": (40, 66), "levels": 3, "lean": 20, "rise": 0.14, "len": 3.1, "kid": (30, 60)},
}
S = STYLES[STYLE]

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------------------------------------------------------------- growing the skeleton
class Branch:
    def __init__(self, pts, radii, level):
        self.pts, self.radii, self.level = pts, radii, level

branches = []

def perp(d):
    a = Vector((1, 0, 0)) if abs(d.x) < 0.9 else Vector((0, 1, 0))
    return d.cross(a).normalized()

def grow(start, direction, length, r_base, level, seed_off):
    """One branch from start: steps of ~0.25 m bending with noise, rising toward the light, drooping when thin."""
    step = max(0.16, min(0.32, length / 9.0))
    n = max(3, int(length / step))
    pts = [start.copy()]
    radii = [r_base]
    d = direction.normalized()
    p = start.copy()
    for i in range(1, n + 1):
        t = i / n
        q = p * 0.9 + Vector((seed_off, seed_off * 0.7, 0.0))
        bend = Vector((noise.noise(q), noise.noise(q + Vector((17.3, 0, 0))), noise.noise(q + Vector((0, 23.1, 0))) * 0.4))
        gnarl = 0.55 if level == 0 else 0.75
        rise = 0.0 if level >= 9 else S["rise"] * step * (1.0 - 0.4 * level / S["levels"])
        d = (d + bend * gnarl * step + Vector((0, 0, rise))).normalized()
        if r_base < 0.06:
            d = (d + Vector((0, 0, -0.18 * step))).normalized()       # thin twigs droop
        p = p + d * step
        pts.append(p.copy())
        taper = 0.3 if level == 0 else 0.5
        radii.append(r_base * (1.0 - taper * t) + 0.004)
    branches.append(Branch(pts, radii, level))
    return pts, radii

def limb(start, direction, length, r, level, seed_off):
    pts, radii = grow(start, direction, length, r, level, seed_off)
    if level >= S["levels"] or r < 0.022:
        return
    # children along the outer part of the branch, plus the tip carrying on
    kids = rng.randint(2, 3) if level < 2 else rng.randint(2, 4)
    for k in range(kids):
        at = rng.uniform(0.45, 0.92) if k < kids - 1 else 0.98
        i = min(len(pts) - 2, max(1, int(at * (len(pts) - 1))))
        base_d = (pts[i + 1] - pts[i]).normalized()
        side = perp(base_d)
        rot = Matrix.Rotation(rng.uniform(0, math.tau), 4, base_d)
        side = (rot @ side.to_4d()).to_3d().normalized()
        ang = math.radians(rng.uniform(*S["kid"]))
        nd = (base_d * math.cos(ang) + side * math.sin(ang)).normalized()
        cr = radii[i] * rng.uniform(0.6, 0.78)
        limb(pts[i], nd, length * rng.uniform(0.55, 0.75), cr, level + 1, seed_off + 3.7 * (k + 1) + level * 11.1)

# the trunk: leaning, then forking
lean_dir = Vector((math.cos(rng.uniform(0, math.tau)), math.sin(rng.uniform(0, math.tau)), 0)).normalized()
lean = math.radians(S["lean"])
trunk_dir = (Vector((0, 0, 1)) * math.cos(lean) + lean_dir * math.sin(lean)).normalized()
tpts, trad = grow(Vector((0, 0, -0.4)), trunk_dir, S["trunk"] + 0.4, S["r0"], 0, SEED * 1.37)
top = tpts[-1]
nl = rng.randint(*S["limbs"])
a0 = rng.uniform(0, math.tau)
for k in range(nl):
    az = a0 + math.tau * k / nl + rng.uniform(-0.35, 0.35)
    sp = math.radians(rng.uniform(*S["spread"]))
    horiz = Vector((math.cos(az), math.sin(az), 0))
    if STYLE == "bent":
        horiz = (horiz - lean_dir * 0.6).normalized()                     # limbs reach back over the lean
    d = (Vector((0, 0, 1)) * math.cos(sp) + horiz * math.sin(sp)).normalized()
    # each limb starts a little inside the trunk's top, so the fork reads as one piece of wood
    start = top - trunk_dir * trad[-1] * 1.6
    limb(start, d, S["len"] * rng.uniform(0.85, 1.15), trad[-1] * rng.uniform(0.82, 0.95), 1, SEED * 2.1 + k * 5.3)

# no separate roots: the trunk's foot flares into buttresses instead (see the mesh), sunk below the ground

# scale so the crown tops out at HEIGHT
zmax = max(p.z for b in branches for p in b.pts)
sc = HEIGHT / max(zmax, 1e-3)
for b in branches:
    b.pts = [p * sc for p in b.pts]
    b.radii = [r * sc for r in b.radii]

# ---------------------------------------------------------------- the mesh: one tube per branch
bm = bmesh.new()
uv_param = bm.loops.layers.uv.new("param")
uv_atlas = bm.loops.layers.uv.new("UVMap")
islands = []      # per branch: list of faces, for packing
for bi, b in enumerate(branches):
    r_max = max(b.radii)
    sides = 8 if r_max > 0.2 else (6 if r_max > 0.08 else (5 if r_max > 0.035 else 4))
    pts = b.pts
    # parallel-transported frames along the path
    t0 = (pts[1] - pts[0]).normalized()
    nrm = perp(t0)
    rings = []
    vlen = 0.0
    vs = []
    for i, p in enumerate(pts):
        if i > 0:
            vlen += (pts[i] - pts[i - 1]).length
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        nrm = (nrm - t * nrm.dot(t)).normalized()
        bin_ = t.cross(nrm)
        r = b.radii[i]
        ring = []
        for s in range(sides + 1):
            th = math.tau * s / sides
            rr = r
            if b.level == 0 and bi == 0:
                # buttress flare at the foot of the trunk
                zf = max(0.0, p.z)
                lobes = max(0.0, math.cos(5 * th + SEED)) ** 2
                rr = r * (1.0 + math.exp(-zf / 0.55) * (0.35 + 0.95 * lobes))
            off = (nrm * math.cos(th) + bin_ * math.sin(th)) * rr
            if s < sides:
                ring.append(bm.verts.new(p + off))
            else:
                ring.append(ring[0])
        rings.append(ring)
        vs.append(vlen)
    faces = []
    circ = math.tau * r_max
    for i in range(len(rings) - 1):
        for s in range(sides):
            a, bb, c, d = rings[i][s], rings[i][s + 1], rings[i + 1][s + 1], rings[i + 1][s]
            try:
                f = bm.faces.new((a, bb, c, d))
            except ValueError:
                continue
            u0, u1 = s / sides, (s + 1) / sides
            for loop, (u, v) in zip(f.loops, ((u0, vs[i]), (u1, vs[i]), (u1, vs[i + 1]), (u0, vs[i + 1]))):
                loop[uv_param].uv = (u, v)
                # atlas: unrolled, round = circumference, along = length (metres), packed later
                loop[uv_atlas].uv = (u * circ, v)
            faces.append(f)
    # a cap on the tip
    tip = bm.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * b.radii[-1] * 0.8)
    for s in range(sides):
        try:
            f = bm.faces.new((rings[-1][s], rings[-1][s + 1], tip))
        except ValueError:
            continue
        for loop in f.loops:
            loop[uv_param].uv = (0.5, vs[-1])
            loop[uv_atlas].uv = (0.5 * circ, vs[-1])
        faces.append(f)
    islands.append(faces)

me = bpy.data.meshes.new("oak")
bm.to_mesh(me)
bm.free()
ob = bpy.data.objects.new("oak", me)
bpy.context.scene.collection.objects.link(ob)
bpy.context.view_layer.objects.active = ob
ob.select_set(True)
for p in me.polygons:
    p.use_smooth = True
tris = sum(len(p.vertices) - 2 for p in me.polygons)
print("OAK %s seed %d: %d branches, %d tris, %.2f m tall" % (STYLE, SEED, len(branches), tris, HEIGHT))

# pack the atlas islands (one per branch) into 0..1
me.uv_layers.active = me.uv_layers["UVMap"]
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.select_all(action="SELECT")
bpy.ops.uv.pack_islands(rotate=True, margin=3.0 / TEX)
bpy.ops.object.mode_set(mode="OBJECT")

if SHAPE_ONLY:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_shadows = True
    cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam); scene.camera = cam
    cam.location = (HEIGHT * 1.5, -HEIGHT * 1.5, HEIGHT * 0.75)
    cam.rotation_euler = (Vector((0, 0, HEIGHT * 0.42)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 520; scene.render.resolution_y = 520
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    sys.exit(0)

# ---------------------------------------------------------------- the bark (procedural, then baked)
mat = bpy.data.materials.new("bark")
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
out = nt.nodes.new("ShaderNodeOutputMaterial")
bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "param"
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(uvn.outputs["UV"], sep.inputs["Vector"])
# seamless round each branch: (cos 2piu, sin 2piu) * R, along = v
def math_node(op, a=None, b=None, v1=None):
    m = nt.nodes.new("ShaderNodeMath"); m.operation = op
    if a is not None: nt.links.new(a, m.inputs[0])
    if b is not None: nt.links.new(b, m.inputs[1])
    if v1 is not None: m.inputs[1].default_value = v1
    return m
ang = math_node("MULTIPLY", sep.outputs["X"], v1=math.tau)
cx = math_node("COSINE", ang.outputs[0]); cy = math_node("SINE", ang.outputs[0])
comb = nt.nodes.new("ShaderNodeCombineXYZ")
nt.links.new(math_node("MULTIPLY", cx.outputs[0], v1=0.9).outputs[0], comb.inputs["X"])
nt.links.new(math_node("MULTIPLY", cy.outputs[0], v1=0.9).outputs[0], comb.inputs["Y"])
nt.links.new(math_node("MULTIPLY", sep.outputs["Y"], v1=0.55).outputs[0], comb.inputs["Z"])
# furrows: Voronoi edges stretched along the branch, warped by noise
warp = nt.nodes.new("ShaderNodeTexNoise"); warp.inputs["Scale"].default_value = 2.2; warp.inputs["Detail"].default_value = 3.0
nt.links.new(comb.outputs["Vector"], warp.inputs["Vector"])
mix = nt.nodes.new("ShaderNodeVectorMath"); mix.operation = "MULTIPLY_ADD"
nt.links.new(warp.outputs["Color"], mix.inputs[0]); mix.inputs[1].default_value = (0.35, 0.35, 0.12)
nt.links.new(comb.outputs["Vector"], mix.inputs[2])
st = nt.nodes.new("ShaderNodeVectorMath"); st.operation = "MULTIPLY"
nt.links.new(mix.outputs["Vector"], st.inputs[0]); st.inputs[1].default_value = (3.2, 3.2, 0.9)
vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.feature = "DISTANCE_TO_EDGE"; vor.inputs["Scale"].default_value = 1.6
nt.links.new(st.outputs["Vector"], vor.inputs["Vector"])
ridge = nt.nodes.new("ShaderNodeMapRange"); ridge.inputs["From Min"].default_value = 0.0; ridge.inputs["From Max"].default_value = 0.22
nt.links.new(vor.outputs["Distance"], ridge.inputs["Value"])
fine = nt.nodes.new("ShaderNodeTexNoise"); fine.inputs["Scale"].default_value = 26.0; fine.inputs["Detail"].default_value = 6.0
nt.links.new(comb.outputs["Vector"], fine.inputs["Vector"])
height = math_node("ADD", ridge.outputs["Result"], math_node("MULTIPLY", fine.outputs["Fac"], v1=0.25).outputs[0])
# colour: dark furrows, grey-brown bark, pale ridge tops; moss in the furrows on the upper side; lichen spots
geo = nt.nodes.new("ShaderNodeNewGeometry")
upz = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(geo.outputs["Normal"], upz.inputs["Vector"])
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.12; ramp.color_ramp.elements[0].color = (0.016, 0.013, 0.011, 1)
ramp.color_ramp.elements[1].position = 0.95; ramp.color_ramp.elements[1].color = (0.13, 0.112, 0.094, 1)
e = ramp.color_ramp.elements.new(0.55); e.color = (0.065, 0.054, 0.044, 1)
nt.links.new(height.outputs[0], ramp.inputs["Fac"])
mossn = nt.nodes.new("ShaderNodeTexNoise"); mossn.inputs["Scale"].default_value = 3.0
nt.links.new(comb.outputs["Vector"], mossn.inputs["Vector"])
mossm = math_node("MULTIPLY", math_node("SUBTRACT", math_node("MULTIPLY", upz.outputs["Z"], v1=1.0).outputs[0], v1=-0.25).outputs[0],
                  math_node("SUBTRACT", mossn.outputs["Fac"], v1=0.42).outputs[0])
mossm2 = math_node("MULTIPLY", mossm.outputs[0], math_node("SUBTRACT", math_node("MULTIPLY", height.outputs[0], v1=-1.0).outputs[0], v1=-0.75).outputs[0])
mossf = nt.nodes.new("ShaderNodeClamp"); nt.links.new(math_node("MULTIPLY", mossm2.outputs[0], v1=3.5).outputs[0], mossf.inputs["Value"])
mixc = nt.nodes.new("ShaderNodeMix"); mixc.data_type = "RGBA"
nt.links.new(mossf.outputs["Result"], mixc.inputs["Factor"])
nt.links.new(ramp.outputs["Color"], mixc.inputs["A"]); mixc.inputs["B"].default_value = (0.05, 0.07, 0.022, 1)
lich = nt.nodes.new("ShaderNodeTexVoronoi"); lich.inputs["Scale"].default_value = 9.0
nt.links.new(comb.outputs["Vector"], lich.inputs["Vector"])
lichm = nt.nodes.new("ShaderNodeMapRange"); lichm.inputs["From Min"].default_value = 0.06; lichm.inputs["From Max"].default_value = 0.0
nt.links.new(lich.outputs["Distance"], lichm.inputs["Value"])
mixl = nt.nodes.new("ShaderNodeMix"); mixl.data_type = "RGBA"
nt.links.new(math_node("MULTIPLY", lichm.outputs["Result"], v1=0.55).outputs[0], mixl.inputs["Factor"])
nt.links.new(mixc.outputs["Result"], mixl.inputs["A"]); mixl.inputs["B"].default_value = (0.2, 0.21, 0.17, 1)
nt.links.new(mixl.outputs["Result"], bsdf.inputs["Base Color"])
bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.9; bump.inputs["Distance"].default_value = 0.03
nt.links.new(height.outputs[0], bump.inputs["Height"])
nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
rough = nt.nodes.new("ShaderNodeMapRange"); rough.inputs["To Min"].default_value = 0.95; rough.inputs["To Max"].default_value = 0.78
nt.links.new(height.outputs[0], rough.inputs["Value"])
nt.links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
bsdf.inputs["Metallic"].default_value = 0.0
me.materials.append(mat)

# ---------------------------------------------------------------- bake into the atlas
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 4
scene.render.bake.margin = 6
def image(name, color):
    img = bpy.data.images.new(name, TEX, TEX, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if color else "Non-Color"
    return img
img_c, img_n, img_r = image("bark_color", True), image("bark_normal", False), image("bark_rough", False)
target = nt.nodes.new("ShaderNodeTexImage")
atlas_uv = nt.nodes.new("ShaderNodeUVMap"); atlas_uv.uv_map = "UVMap"
nt.links.new(atlas_uv.outputs["UV"], target.inputs["Vector"])
def bake(img, btype, **kw):
    target.image = img
    for n in nt.nodes:
        n.select = False
    target.select = True
    nt.nodes.active = target
    bpy.ops.object.bake(type=btype, **kw)
    print("BAKED", img.name)
me.uv_layers.active = me.uv_layers["UVMap"]
bake(img_c, "DIFFUSE", pass_filter={"COLOR"})
bake(img_n, "NORMAL")
bake(img_r, "ROUGHNESS")

# ---------------------------------------------------------------- the game's material: baked maps, packed metal/roughness
r = np.array(img_r.pixels[:]).reshape(-1, 4)
img_mr = image("bark_mr", False)
mr = np.ones_like(r); mr[:, 1] = r[:, 0]; mr[:, 2] = 0.0
img_mr.pixels.foreach_set(mr.reshape(-1).astype(np.float32))
for n in list(nt.nodes):
    if n not in (out, bsdf):
        nt.nodes.remove(n)
tc = nt.nodes.new("ShaderNodeTexImage"); tc.image = img_c
tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = img_n
tm = nt.nodes.new("ShaderNodeTexImage"); tm.image = img_mr
nm = nt.nodes.new("ShaderNodeNormalMap")
sp = nt.nodes.new("ShaderNodeSeparateColor")
nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
nt.links.new(tm.outputs["Color"], sp.inputs["Color"])
nt.links.new(sp.outputs["Green"], bsdf.inputs["Roughness"])
nt.links.new(sp.outputs["Blue"], bsdf.inputs["Metallic"])
import tempfile, os
tmp = tempfile.mkdtemp()
for img, fmt, ext in ((img_c, "JPEG", "jpg"), (img_n, "PNG", "png"), (img_mr, "JPEG", "jpg")):
    path = os.path.join(tmp, img.name + "." + ext)
    img.file_format = fmt
    img.filepath_raw = path
    img.save(filepath=path, quality=92)
    img.source = "FILE"
    img.reload()
me.uv_layers.remove(me.uv_layers["param"])

if PREVIEW:
    cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam); scene.camera = cam
    cam.location = (HEIGHT * 1.35, -HEIGHT * 1.35, HEIGHT * 0.7)
    cam.rotation_euler = (Vector((0, 0, HEIGHT * 0.45)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(50), 0, math.radians(30)); sun.data.energy = 3.0
    w = bpy.data.worlds.new("w"); w.use_nodes = True; w.node_tree.nodes["Background"].inputs[1].default_value = 0.6; scene.world = w
    scene.render.resolution_x = 640; scene.render.resolution_y = 640
    scene.cycles.samples = 24
    scene.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)

bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_image_format="AUTO", export_jpeg_quality=92)
print("EXPORTED", OUT, "tris", tris)
