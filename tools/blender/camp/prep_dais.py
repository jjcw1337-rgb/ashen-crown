# Prepares the raid stash chest's ground (jj's concept A: a round dais of cracked crypt flagstones, ember cracks, candles
# on iron spikes, chains, bones, coins) for the game: joined, centred, scaled to its width, base on the ground,
# decimated, textures shrunk, and two kinds of markers the game reads (empties, exported as nodes):
#   "chest_at"  where the chest stands: the dais's top in its middle
#   "flame_N"   each candle's tip (the tops of the tall thin clusters round the edge), for the game's real flames
#   blender -b --python prep_dais.py -- in.glb out.glb [--w 3.5] [--tris 22000] [--tex 1024] [--debug prefix]
import bpy, bmesh, sys, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
W = float(opt("--w", "3.5"))
TRIS = int(opt("--tris", "22000"))
TEX = int(opt("--tex", "1024"))
DEBUG = opt("--debug", "")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
for o in list(bpy.context.scene.objects):
    if o != ob:
        bpy.data.objects.remove(o, do_unlink=True)
ob.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
ob.name = "dais"

def bounds():
    vs = [v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))

lo, hi = bounds()
k = W / max(hi.x - lo.x, hi.y - lo.y)
ob.data.transform(Matrix.Scale(k, 4))
lo, hi = bounds()
ob.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))))
lo, hi = bounds()

if len(ob.data.polygons) > TRIS:
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = TRIS / len(ob.data.polygons)
    bpy.ops.object.modifier_apply(modifier="dec")

# the chest's spot: the highest surface within a small circle round the middle
vs = [v.co.copy() for v in ob.data.vertices]
mid = [v for v in vs if v.x * v.x + v.y * v.y < (W * 0.08) ** 2]
top = max(v.z for v in mid) if mid else hi.z * 0.5
# the dais's floor level: the typical height of its top (the median of the vertices inside 35% of the radius)
inner = sorted(v.z for v in vs if v.x * v.x + v.y * v.y < (W * 0.35 * 0.5) ** 2)
floor = inner[len(inner) // 2] if inner else top
def empty(name, p):
    e = bpy.data.objects.new(name, None)
    e.location = p
    bpy.context.scene.collection.objects.link(e)
    return e
empty("chest_at", Vector((0, 0, floor)))
# candle tips: the pale wax (the texture's colour under each vertex) well above the floor, out towards the edge,
# clustered by 0.18 m in plan (the iron spikes the candles are impaled on stand higher, but they're dark)
img = None
mat = ob.data.materials[0] if ob.data.materials else None
if mat and mat.use_nodes:
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            img = n.image
            break
px_ = list(img.pixels[:]) if img is not None else None
iw, ih = (img.size[0], img.size[1]) if img is not None else (0, 0)
uvl = ob.data.uv_layers.active
vuv = {}
if uvl is not None:
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            vuv.setdefault(ob.data.loops[li].vertex_index, uvl.data[li].uv.copy())
def pale(i):
    if px_ is None or i not in vuv:
        return True
    u, v = vuv[i]
    x = min(iw - 1, max(0, int((u % 1.0) * iw)))
    y = min(ih - 1, max(0, int((v % 1.0) * ih)))
    j = (y * iw + x) * 4
    r, g, b = px_[j], px_[j + 1], px_[j + 2]
    return (r + g + b) / 3.0 > 0.45 and r >= b
high = [ob.data.vertices[i].co.copy() for i in range(len(ob.data.vertices))
    if ob.data.vertices[i].co.z > floor + 0.3 * (W / 3.5) and math.hypot(ob.data.vertices[i].co.x, ob.data.vertices[i].co.y) > W * 0.28 and pale(i)]
clusters = []
for v in sorted(high, key=lambda v: -v.z):
    for c in clusters:
        if math.hypot(v.x - c[0].x, v.y - c[0].y) < 0.18 * (W / 3.5):
            break
    else:
        clusters.append([v])
flames = 0
for c in clusters:
    t = c[0]
    empty("flame_%d" % flames, t + Vector((0, 0, 0.02)))
    flames += 1
print("DAIS size %s floor %.3f flames %d tris %d" % (tuple(round(v, 2) for v in (hi - lo)), floor, flames, len(ob.data.polygons)))

for im in bpy.data.images:
    if im.size[0] > TEX:
        im.scale(TEX, TEX)

if DEBUG:
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 900
    sc.render.resolution_y = 700
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.12, 0.12, 0.13, 1)
    sc.world = w
    l = bpy.data.lights.new("l", "SUN")
    l.energy = 3
    lo_ = bpy.data.objects.new("l", l)
    lo_.rotation_euler = (0.8, 0.2, 0.6)
    sc.collection.objects.link(lo_)
    for o in sc.objects:
        if o.type == "EMPTY" and o.name.startswith("flame"):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.04, location=o.location)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = Vector((2.6, -3.6, 3.2)) * (W / 3.5)
    cam.rotation_euler = (Vector((0, 0, 0.2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = DEBUG + ".png"
    bpy.ops.render.render(write_still=True)
    for o in list(sc.objects):
        if o.type == "MESH" and o.name.startswith("Sphere"):
            bpy.data.objects.remove(o, do_unlink=True)

for m in bpy.data.materials:
    m.use_backface_culling = False
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.context.scene.objects:
    if o.type in ("MESH", "EMPTY"):
        o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True,
    export_image_format="JPEG", export_jpeg_quality=86)
print("DAIS wrote", OUT)
