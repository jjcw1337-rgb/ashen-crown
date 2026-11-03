# Turns a Meshy top-down ground painting (a puddle, a mould patch, a ring of growth, on black) into a game decal:
#   <out>_albedo.png  colour with alpha keyed from the black background (soft edge)
#   <out>_normal.png  a tangent-space normal map baked in Blender from the painting's relief: a densely subdivided
#                     plane displaced by the painting's brightness, baked (selected to active) onto a flat plane
#   blender -b --python tools/blender/plague/ground_decal.py -- <painting.png> <out prefix> [px 1024] [relief 0.04]
#                                                               [key black|chroma]
# key chroma keys by colourfulness instead of brightness, for paintings whose background is a grey floor rather than
# black (the bile spray): grey goes, the coloured liquid and its bright highlights stay.
import bpy, sys, os
import numpy as np
a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
PX = int(a[2]) if len(a) > 2 else 1024
RELIEF = float(a[3]) if len(a) > 3 else 0.04
KEY = a[4] if len(a) > 4 else "black"
bpy.ops.wm.read_factory_settings(use_empty=True)
img = bpy.data.images.load(os.path.abspath(SRC))
img.scale(PX, PX)
px = np.array(img.pixels[:], dtype=np.float32).reshape(PX, PX, 4)
rgb = px[..., :3]
lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
mx = rgb.max(axis=2)
# alpha: the black background keyed out, with a soft shoulder so splatter edges stay crisp but not jagged
alpha = np.clip((mx - 0.035) / 0.12, 0.0, 1.0)
if KEY == "chroma":
	chroma = mx - rgb.min(axis=2)
	alpha = np.maximum(np.clip((chroma - 0.04) / 0.1, 0.0, 1.0), np.clip((lum - 0.45) / 0.2, 0.0, 1.0))
alpha = alpha * alpha * (3.0 - 2.0 * alpha)
out = np.dstack([rgb, alpha]).astype(np.float32)
al = bpy.data.images.new("albedo", PX, PX, alpha=True)
al.pixels[:] = out.ravel()
al.filepath_raw = os.path.abspath(OUT + "_albedo.png")
al.file_format = "PNG"
al.save()
# the relief: brightness as height, softened (a painting's highlights are not all height)
hgt = bpy.data.images.new("height", PX, PX, alpha=False)
h = np.clip(lum * 1.4, 0.0, 1.0) * alpha
hgt.pixels[:] = np.dstack([h, h, h, np.ones_like(h)]).astype(np.float32).ravel()
# the high-poly: a plane subdivided and displaced by it
bpy.ops.mesh.primitive_plane_add(size=2, location=(0, 0, 0))
hi = bpy.context.active_object
hi.name = "hi"
sub = hi.modifiers.new("sub", "SUBSURF")
sub.subdivision_type = "SIMPLE"
sub.levels = 8
sub.render_levels = 8
tex = bpy.data.textures.new("h", "IMAGE")
tex.image = hgt
tex.extension = "CLIP"
dp = hi.modifiers.new("disp", "DISPLACE")
dp.texture = tex
dp.texture_coords = "UV"
dp.strength = RELIEF
dp.mid_level = 0.0
# the low-poly target: a flat plane with an image to bake into
bpy.ops.mesh.primitive_plane_add(size=2, location=(0, 0, 0))
lo = bpy.context.active_object
lo.name = "lo"
nm = bpy.data.images.new("normal", PX, PX, alpha=False, float_buffer=False)
mat = bpy.data.materials.new("bake")
mat.use_nodes = True
node = mat.node_tree.nodes.new("ShaderNodeTexImage")
node.image = nm
mat.node_tree.nodes.active = node
lo.data.materials.append(mat)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 4
bpy.ops.object.select_all(action="DESELECT")
hi.select_set(True)
lo.select_set(True)
bpy.context.view_layer.objects.active = lo
bpy.ops.object.bake(type="NORMAL", use_selected_to_active=True, cage_extrusion=RELIEF * 1.5, normal_space="TANGENT")
nm.filepath_raw = os.path.abspath(OUT + "_normal.png")
nm.file_format = "PNG"
nm.save()
print("DECAL", OUT, PX)
