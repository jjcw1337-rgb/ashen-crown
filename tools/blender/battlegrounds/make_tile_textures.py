# The Hollow Crypt's wall and floor textures from Meshy's drawn stone (tools/meshy/meshy.py draw, prompts in the
# Battlegrounds plan): makes each image tileable and bakes a tangent-space normal map from it in Cycles (a Bump
# node fed by the colour's luminance, baked onto a flat plane), writing <out>_albedo.png and <out>_normal.png.
#
# Tileable: the image is cropped so its edges run along mortar joints (the darkest rows and columns near each
# edge), where a wrap hardly shows. A wall's courses are offset, so its vertical joints never line up: there the
# half-offset copy is laid over it and the original cross-faded back in over the copy's seam (--mode wall);
# flagstones have joints both ways (--mode floor: the crop alone).
#   blender -b --python tools/blender/battlegrounds/make_tile_textures.py -- <in.png> <outprefix> [--mode wall|floor]
#        [--size 1024] [--feather 110] [--bump 0.55] [--distance 0.08]
import bpy, sys
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
MODE = opt("--mode", "wall")
SIZE = int(opt("--size", "1024"))
FEATHER = int(opt("--feather", "110"))
BUMP = float(opt("--bump", "0.55"))
DIST = float(opt("--distance", "0.08"))

bpy.ops.wm.read_factory_settings(use_empty=True)
img = bpy.data.images.load(SRC)
img.colorspace_settings.name = "sRGB"
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
lum = px[:, :, 0] * 0.3 + px[:, :, 1] * 0.59 + px[:, :, 2] * 0.11

def joint(means, lo, hi):
    """The index of the darkest line (a mortar joint) in [lo, hi)."""
    k = int(np.argmin(means[lo:hi]))
    return lo + k

def crop_rows(a, l):
    rows = l.mean(axis=1)
    t = joint(rows, 0, int(H * 0.14))
    b = joint(rows, int(H * 0.86), H)
    return a[t:b], l[t:b]

def crop_cols(a, l):
    cols = l.mean(axis=0)
    le = joint(cols, 0, int(W * 0.14))
    ri = joint(cols, int(W * 0.86), W)
    return a[:, le:ri], l[:, le:ri]

px, lum = crop_rows(px, lum)
if MODE == "floor":
    px, lum = crop_cols(px, lum)

def resize(a, size):
    """Bilinear resize of an HxWx4 array to size x size."""
    h, w = a.shape[0], a.shape[1]
    ys = (np.arange(size) + 0.5) * h / size - 0.5
    xs = (np.arange(size) + 0.5) * w / size - 0.5
    y0 = np.clip(np.floor(ys).astype(int), 0, h - 1); y1 = np.clip(y0 + 1, 0, h - 1); fy = (ys - y0)[:, None, None]
    x0 = np.clip(np.floor(xs).astype(int), 0, w - 1); x1 = np.clip(x0 + 1, 0, w - 1); fx = (xs - x0)[None, :, None]
    top = a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx
    bot = a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx
    return top * (1 - fy) + bot * fy

tile = resize(px, SIZE)
if MODE == "wall":
    # the half-offset copy wraps across the left/right edge; its own seam (the original's edges meeting at the
    # middle) is hidden under the original, cross-faded over FEATHER px either side
    shifted = np.roll(tile, SIZE // 2, axis=1)
    x = np.arange(SIZE)
    d = np.abs(x - SIZE // 2).astype(np.float32)
    w = np.clip(d / FEATHER, 0.0, 1.0)
    w = w * w * (3.0 - 2.0 * w)
    weight = w[None, :, None]              # the copy's weight: 0 on its seam, 1 away from it
    tile = shifted * weight + tile * (1.0 - weight)
tile[:, :, 3] = 1.0
tile = np.clip(tile, 0.0, 1.0)
alb = bpy.data.images.new("albedo", SIZE, SIZE, alpha=False, float_buffer=False)
alb.colorspace_settings.name = "sRGB"
alb.pixels.foreach_set(tile.reshape(-1).astype(np.float32))
alb.filepath_raw = OUT + "_albedo.png"
alb.file_format = "PNG"
alb.save()
print("WROTE", OUT + "_albedo.png")

# --- the normal map: bake the Bump node's perturbed normal (height = the colour's luminance) onto a flat plane
bpy.ops.mesh.primitive_plane_add(size=2.0)
plane = bpy.context.object
mat = bpy.data.materials.new("tile")
mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = alb
tex.interpolation = "Cubic"
tex.extension = "REPEAT"
bw = nt.nodes.new("ShaderNodeRGBToBW")
bump = nt.nodes.new("ShaderNodeBump")
bump.inputs["Strength"].default_value = BUMP
bump.inputs["Distance"].default_value = DIST
nt.links.new(tex.outputs["Color"], bw.inputs["Color"])
nt.links.new(bw.outputs["Val"], bump.inputs["Height"])
nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
target = nt.nodes.new("ShaderNodeTexImage")
nrm = bpy.data.images.new("normal", SIZE, SIZE, alpha=False, float_buffer=False)
nrm.colorspace_settings.name = "Non-Color"
target.image = nrm
nt.nodes.active = target
plane.data.materials.append(mat)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 1
scene.render.bake.use_selected_to_active = False
scene.render.bake.margin = 0
bpy.ops.object.select_all(action="DESELECT")
plane.select_set(True)
bpy.context.view_layer.objects.active = plane
bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT")
nrm.filepath_raw = OUT + "_normal.png"
nrm.file_format = "PNG"
nrm.save()
print("WROTE", OUT + "_normal.png")
