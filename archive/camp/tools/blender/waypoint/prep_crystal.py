# Prepares the waypoint's rune crystal from Meshy (the concept drawn by Meshy, then image-to-3D) for the game.
#
#   blender -b --python tools/blender/waypoint/prep_crystal.py -- <meshy.glb> <out.glb> [--height 3.0] [--tris 2500]
#        [--tex 1024] [--samples 4]
#
# Unlike tools/blender/camp/rebake_prop.py this keeps the crystal's facets sharp: no voxel remesh (it would round
# every edge), a planar decimate instead, so each facet becomes a few flat triangles and the unwrap gives one large
# UV island per facet (Meshy's own atlas is thousands of slivers that bleed into mush in the mipmaps the game
# camera reads). The original's colour, normal, roughness and metal are baked onto it with Cycles. The origin is
# put at the crystal's centre (the game floats and spins it round that point) and it is scaled to --height.
# Prints "CRYSTAL <out> tris N size x y z" and "EXPORTED <out>".
import bpy, bmesh, sys, math, os, tempfile
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
HEIGHT = float(opt("--height", "3.0"))
TRIS = int(opt("--tris", "2500"))
TEX = int(opt("--tex", "1024"))
SAMPLES = int(opt("--samples", "4"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
hi = bpy.context.view_layer.objects.active
hi.name = "hi"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- centre the origin on the bounds' middle and size it
me = hi.data
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
P -= 0.5 * (P.min(axis=0) + P.max(axis=0))
P *= HEIGHT / np.ptp(P[:, 2])
me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()
size = float(np.ptp(P, axis=0).max())

# --- the low copy: planar decimate keeps the facets flat, one UV island per facet
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "crystal"
bpy.context.collection.objects.link(lo)
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True); bpy.context.view_layer.objects.active = lo
m = lo.modifiers.new("planar", "DECIMATE"); m.decimate_type = "DISSOLVE"; m.angle_limit = math.radians(4.0); m.use_dissolve_boundaries = False
bpy.ops.object.modifier_apply(modifier="planar")
# planar dissolve leaves n-gons: triangulate, then collapse down to the budget if still over it
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")
bpy.ops.object.mode_set(mode="OBJECT")
tris = len(lo.data.polygons)
if tris > TRIS:
    m2 = lo.modifiers.new("dec", "DECIMATE"); m2.ratio = TRIS / tris
    bpy.ops.object.modifier_apply(modifier="dec")
while lo.data.uv_layers:
    lo.data.uv_layers.remove(lo.data.uv_layers[0])
lo.data.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(50), island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
bpy.ops.uv.pack_islands(rotate=True, margin=3.0 / TEX)
bpy.ops.object.mode_set(mode="OBJECT")
for p in lo.data.polygons:
    p.use_smooth = False          # a crystal: flat facets
lo.data.materials.clear()

# --- the low copy's material: one image per baked map
def image(name, color):
    img = bpy.data.images.new(name, TEX, TEX, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if color else "Non-Color"
    return img
img_alb, img_nrm, img_rgh, img_met = image("albedo", True), image("normal", False), image("rough", False), image("metal", False)
mat = bpy.data.materials.new("crystal"); mat.use_nodes = True
nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
lo.data.materials.append(mat)
tex_nodes = {}
for nm, img in [("albedo", img_alb), ("normal", img_nrm), ("rough", img_rgh), ("metal", img_met)]:
    n = nt.nodes.new("ShaderNodeTexImage"); n.image = img; n.name = nm; tex_nodes[nm] = n

# --- bake from the original onto the copy
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = SAMPLES
bk = scene.render.bake
bk.use_selected_to_active = True
bk.cage_extrusion = 0.02 * size
bk.max_ray_distance = 0.1 * size
bk.margin = 6
bpy.ops.object.select_all(action="DESELECT")
hi.select_set(True); lo.select_set(True); bpy.context.view_layer.objects.active = lo

def bake(target, btype, **kw):
    for n in nt.nodes:
        n.select = False
    tex_nodes[target].select = True
    nt.nodes.active = tex_nodes[target]
    bpy.ops.object.bake(type=btype, **kw)
    print("BAKED", target)

bake("albedo", "DIFFUSE", pass_filter={"COLOR"})
bake("normal", "NORMAL")
bake("rough", "ROUGHNESS")
saved = []
for mm in hi.data.materials:
    if mm is None or not mm.use_nodes:
        continue
    t = mm.node_tree
    p = next((n for n in t.nodes if n.type == "BSDF_PRINCIPLED"), None)
    out = next((n for n in t.nodes if n.type == "OUTPUT_MATERIAL"), None)
    if p is None or out is None:
        continue
    em = t.nodes.new("ShaderNodeEmission")
    src = p.inputs["Metallic"].links[0].from_socket if p.inputs["Metallic"].is_linked else None
    if src is not None:
        t.links.new(src, em.inputs["Color"])
    else:
        v = p.inputs["Metallic"].default_value
        em.inputs["Color"].default_value = (v, v, v, 1.0)
    old = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].is_linked else None
    t.links.new(em.outputs["Emission"], out.inputs["Surface"])
    saved.append((t, out, old, em))
bake("metal", "EMIT")
for t, out, old, em in saved:
    if old is not None:
        t.links.new(old, out.inputs["Surface"])
    t.nodes.remove(em)

# --- glTF wiring: metallicRoughness = G rough, B metal
r = np.array(img_rgh.pixels[:]).reshape(-1, 4)
mt = np.array(img_met.pixels[:]).reshape(-1, 4)
img_mr = image("metal_rough", False)
mr = np.ones_like(r); mr[:, 1] = r[:, 0]; mr[:, 2] = mt[:, 0]
img_mr.pixels.foreach_set(mr.reshape(-1).astype(np.float32))
for n in list(nt.nodes):
    if n.name in ("rough", "metal"):
        nt.nodes.remove(n)
mrn = nt.nodes.new("ShaderNodeTexImage"); mrn.image = img_mr
sep = nt.nodes.new("ShaderNodeSeparateColor")
nmn = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tex_nodes["albedo"].outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(tex_nodes["normal"].outputs["Color"], nmn.inputs["Color"])
nt.links.new(nmn.outputs["Normal"], bsdf.inputs["Normal"])
nt.links.new(mrn.outputs["Color"], sep.inputs["Color"])
nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
tmp = tempfile.mkdtemp()
for img, fmt, ext in ((img_alb, "JPEG", "jpg"), (img_nrm, "PNG", "png"), (img_mr, "JPEG", "jpg")):
    path = os.path.join(tmp, img.name + "." + ext)
    img.file_format = fmt
    img.filepath_raw = path
    img.save(filepath=path, quality=92)
    img.source = "FILE"
    img.reload()

bpy.data.objects.remove(hi, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_image_format="AUTO", export_jpeg_quality=92)
me = lo.data
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
print("CRYSTAL", OUT, "tris", len(me.polygons), "size x %.2f y %.2f z %.2f" % tuple(np.ptp(P, axis=0)))
print("EXPORTED", OUT)
