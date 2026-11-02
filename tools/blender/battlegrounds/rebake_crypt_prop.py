# Prepares a Meshy prop for the Hollow Crypt (Battlegrounds) AND re-bakes its textures onto clean UVs: the camp's
# tools/blender/camp/rebake_prop.py (decimated copy, voxel remesh, large UV islands, Cycles bake of colour, normal,
# roughness and metal; normal as PNG) with what the crypt's pieces needed on top:
#   --xy f           scale the prop horizontally by f after sizing (the hall's pillar: tall but slim enough for its
#                    0.55 m collision circle)
#   --cut-above m    drop everything above that height (metres, after scaling)
#   --keep axis,m    drop everything below m along that axis (x|y, metres, after scaling): the sconce's modelled
#                    flame bulb in front of it (y), which the game's FireFx replaces
#   --tint r,g,b     multiply the baked colour (the ossuary niche came out of Meshy as pale clean stone; the crypt is
#                    dark and mossy)
#
#   blender -b --python rebake_crypt_prop.py -- <in.glb> <out.glb> <size: h=2 | w=1.6 | x=3> <triangles> [--tex 1024]
#        [--yaw deg] [--cut m] [--cut-above m] [--keep axis,m] [--xy f] [--tint r,g,b] [--samples 4] [--voxel 0.006]
# size: h= scales to that height, w= its widest side, x= its length along x (metres, after yaw); "keep" leaves an
# already prepared prop exactly where and as big as it is (only the surface and textures are rebuilt).
# --cut removes everything below that height (metres, after scaling): Meshy's ground patches under a prop.
# Prints "PROP <out> size ... foot half ..." (footprint half-extents in Godot x/z) and "EXPORTED <out>".
import bpy, bmesh, sys, math
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, SIZE, TRIS = argv[0], argv[1], argv[2], int(argv[3])
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
TEX = int(opt("--tex", "1024"))
YAW = float(opt("--yaw", "0"))
CUT = float(opt("--cut", "0"))
SAMPLES = int(opt("--samples", "4"))
CUT_ABOVE = float(opt("--cut-above", "0"))
KEEP = opt("--keep", "")
XY = float(opt("--xy", "1"))
TINT = [float(v) for v in opt("--tint", "1,1,1").split(",")]

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
hi.rotation_euler = (0, 0, math.radians(YAW))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- place and scale the original: footprint centred, base on the ground, sized
me = hi.data
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
P[:, 0] -= 0.5 * (P[:, 0].min() + P[:, 0].max())
P[:, 1] -= 0.5 * (P[:, 1].min() + P[:, 1].max())
P[:, 2] -= P[:, 2].min()
if SIZE == "keep":
    # an already prepared prop (the camp's older glbs): keep its placement and size exactly, so the code that
    # places it needs no change; only its surface and textures are rebuilt
    me.vertices.foreach_get("co", P.reshape(-1))
else:
    key, val = SIZE.split("=")
    ext = {"x": np.ptp(P[:, 0]), "h": np.ptp(P[:, 2]), "w": max(np.ptp(P[:, 0]), np.ptp(P[:, 1]))}[key]
    P *= float(val) / ext
if XY != 1.0:
    P[:, 0] *= XY
    P[:, 1] *= XY
me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()

if CUT_ABOVE > 0:
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, CUT_ABOVE), plane_no=(0, 0, 1), clear_outer=True)
    bm.to_mesh(me); bm.free()
    P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()

if CUT > 0:
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, CUT), plane_no=(0, 0, 1), clear_inner=True)
    bm.to_mesh(me); bm.free()
    P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    P[:, 2] -= P[:, 2].min()   # stand it back on the ground
    me.vertices.foreach_set("co", P.reshape(-1).astype(np.float32)); me.update()
size = float(np.ptp(P, axis=0).max())

# --- the low-poly copy: decimated, unwrapped into large islands
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "lo"
bpy.context.collection.objects.link(lo)
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True); bpy.context.view_layer.objects.active = lo
# Meshy's surface is a noisy triangle soup, so an unwrap of it (even decimated) shatters into slivers. A voxel
# remesh gives a smooth closed skin that unwraps into large islands; the bake puts the detail back.
# --voxel is the voxel size as a fraction of the prop's size (0 = skip; thin parts thinner than a voxel are lost)
VOX = float(opt("--voxel", "0.006"))
if VOX > 0:
    rm = lo.modifiers.new("remesh", "REMESH"); rm.mode = "VOXEL"; rm.voxel_size = VOX * size; rm.adaptivity = 0.0
    bpy.ops.object.modifier_apply(modifier="remesh")
    sm = lo.modifiers.new("smooth", "SMOOTH"); sm.iterations = 2; sm.factor = 0.5
    bpy.ops.object.modifier_apply(modifier="smooth")
tris = sum(len(p.vertices) - 2 for p in lo.data.polygons)
if tris > TRIS:
    m = lo.modifiers.new("dec", "DECIMATE"); m.ratio = TRIS / tris
    bpy.ops.object.modifier_apply(modifier="dec")
if KEEP != "":
    # cut on the remeshed copy (a cut through Meshy's triangle soup breaks the voxel remesh), the hole closed
    kax, kmin = KEEP.split(",")
    kco = (float(kmin), 0, 0) if kax == "x" else (0, float(kmin), 0)
    kno = (1, 0, 0) if kax == "x" else (0, 1, 0)
    bm = bmesh.new(); bm.from_mesh(lo.data)
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=kco, plane_no=kno, clear_inner=True)
    bmesh.ops.holes_fill(bm, edges=bm.edges, sides=0)
    bm.to_mesh(lo.data); bm.free()
    lo.data.update()
while lo.data.uv_layers:
    lo.data.uv_layers.remove(lo.data.uv_layers[0])
lo.data.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0, area_weight=0.0, scale_to_bounds=False)
bpy.ops.uv.pack_islands(rotate=True, margin=2.5 / TEX)
bpy.ops.object.mode_set(mode="OBJECT")
lo.data.materials.clear()

# --- the low copy's material: one image per baked map
def image(name, color):
    img = bpy.data.images.new(name, TEX, TEX, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "sRGB" if color else "Non-Color"
    return img
img_alb, img_nrm, img_rgh, img_met = image("albedo", True), image("normal", False), image("rough", False), image("metal", False)
mat = bpy.data.materials.new("prop"); mat.use_nodes = True
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
# metal: wire whatever feeds each original material's Metallic into an emission and bake that
saved = []
for m in hi.data.materials:
    if m is None or not m.use_nodes:
        continue
    t = m.node_tree
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

# --- wire the baked maps for glTF: metallicRoughness = G rough, B metal (packed into one image)
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
nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tex_nodes["albedo"].outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(tex_nodes["normal"].outputs["Color"], nm.inputs["Color"])
nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
nt.links.new(mrn.outputs["Color"], sep.inputs["Color"])
nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
if TINT != [1.0, 1.0, 1.0]:
    px = np.array(img_alb.pixels[:]).reshape(-1, 4)
    px[:, 0] *= TINT[0]; px[:, 1] *= TINT[1]; px[:, 2] *= TINT[2]
    img_alb.pixels.foreach_set(np.clip(px, 0.0, 1.0).reshape(-1).astype(np.float32))
# Save each map as a file in its format and reload it, so the glTF exporter's AUTO keeps that format: colour and
# metal/roughness as JPEG (small), the normal map as PNG (JPEG's blocks would read as bumps)
import tempfile, os
tmp = tempfile.mkdtemp()
for img, fmt, ext in ((img_alb, "JPEG", "jpg"), (img_nrm, "PNG", "png"), (img_mr, "JPEG", "jpg")):
    path = os.path.join(tmp, img.name + "." + ext)
    img.file_format = fmt
    img.filepath_raw = path
    img.save(filepath=path, quality=90)     # the raw pixels, no view transform
    img.source = "FILE"
    img.reload()

# --- export only the low copy
bpy.data.objects.remove(hi, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_image_format="AUTO", export_jpeg_quality=90)
me = lo.data
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
base = P[P[:, 2] < 0.4] if (P[:, 2] < 0.4).sum() > 20 else P
print("PROP", OUT, "tris", sum(len(p.vertices) - 2 for p in me.polygons),
      "size x %.2f y %.2f h %.2f" % tuple(np.ptp(P, axis=0)),
      "foot half x %.2f z %.2f" % (np.abs(base[:, 0]).max(), np.abs(base[:, 1]).max()))
print("EXPORTED", OUT)
