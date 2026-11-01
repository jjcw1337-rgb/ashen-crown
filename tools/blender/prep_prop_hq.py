# Prepares a Meshy prop for the game at the best quality it can keep: the high-detail sibling of
# prep_prop.py (same conventions, same PROP line, more care taken with the mesh and the textures).
#
#   blender -b --python prep_prop_hq.py -- in.glb out.glb [size m] [--axis height|width|depth] [--turn deg]
#       [--sink m] [--tris N] [--tex 4096] [--bake] [--lod] [--web-tris N] [--web-tex 4096] [--jpeg] ...
#   blender -b --python prep_prop_hq.py -- props_in/ assets/models/camp/ 2.5 --bake     (every model in a folder)
#   blender -b --python prep_prop_hq.py -- --help                                       (every option)
#
# What it does to each model (.glb / .gltf / .fbx / .obj from Meshy):
#   - drops the cameras, lights and empties the import brings in, joins the mesh parts into one object,
#     applies every transform and modifier;
#   - --turn spins it about the vertical (Meshy's image-to-3D faces the viewer; the game wants the front
#     toward +z in Godot, which is -y in Blender);
#   - merges vertices by a small distance, makes the normals point outward, deletes loose bits;
#   - keeps Meshy's custom (split) normals when they are sound, rebuilds them only when they are broken or
#     after decimation (--normals keep|recalc overrides); smooth shading with edges sharper than
#     --smooth-angle kept hard (sharp-edge flags, which Blender 4.1+ uses instead of auto-smooth);
#   - scales so the --axis dimension (height by default) equals <size> m, or keeps Meshy's size without one;
#   - centres the footprint on the origin, base on the ground, sunk --sink m (0.02) so it never floats;
#   - decimates (Collapse, no symmetry, triangulated) only above --tris (150 000 by default), protecting
#     the vertices on UV seams, sharp edges, open borders and material borders so silhouettes and texture
#     borders survive;
#   - textures: every map becomes lossless PNG, capped at --tex px (4096; 8192 allowed), never upscaled,
#     and embedded in the glb; --jpeg trades that for JPEG at --jpeg-quality;
#   - --bake melts every material into ONE PBR material baked at --tex px from the full-detail copy onto the
#     final mesh (selected-to-active, cage extrusion ~1% of the size): base colour, 16-bit tangent normal,
#     roughness, metallic (if any), emission (if any), alpha (if any); with several materials Meshy's UV
#     islands are repacked into one atlas (Smart UV Project only with --reunwrap or when the UVs are
#     unusable); --bake-margin px of padding (16 at 4k) against seams;
#     the PNGs are also kept in <out>_textures/ unless --no-save-textures;
#   - exports a static glb for Godot (+y up, normals, tangents, UVs, materials, images embedded, no
#     animation, cameras or lights); --lod adds <name>_lod1.glb (50%) and <name>_lod2.glb (20%);
#     --web-tris N adds <name>_web.glb with N triangles and textures capped at --web-tex (4096);
#   - prints a report per model and the line World.add_box reads, exactly as prep_prop.py does:
#       PROP <out> tris N size x W y D z H foot half x X z Z
#     (size in Blender axes: y is depth, z is height; the footprint is the lowest 40 cm as Godot
#     half-extents, z = -y). --report file.json writes all of it as JSON.
# Never writes over its input; a model that fails is reported and the batch goes on. Needs Blender 4.5 LTS
# (`bash tools/blender/setup_blender.sh`); the API guards reach back to 4.1.
#
# Baking notes: the colour, roughness, metallic, emission and alpha passes are baked through an emission
# shader, so they carry no lighting and no noise at any sample count; the normal pass is geometric. Cycles'
# bake has no denoiser and none is needed. Godot reads the 16-bit normal PNG at 8 bits; the 16-bit file is
# the archival copy in <out>_textures/. Alpha-blended materials are baked into the base colour's alpha and
# the baked material keeps blend/clip mode. --bake-device gpu uses the first CUDA/OptiX/HIP/Metal device.
import argparse, json, math, os, shutil, sys, tempfile, time, traceback
import bpy, bmesh, numpy as np
from mathutils import Matrix, Vector

EXTS = {".glb", ".gltf", ".fbx", ".obj"}
VER = tuple(bpy.app.version)
NEW_NORMALS = VER >= (4, 1, 0)        # auto-smooth gone, custom normals are the "custom_normal" attribute


def log(msg, level="INFO"):
    print(f"[prep_prop_hq] {level}: {msg}", flush=True)


def op_kwargs(op, **kw):
    """Keep only the options this Blender's operator really has (names move between versions)."""
    try:
        props = set(op.get_rna_type().properties.keys())
    except Exception:
        return kw
    return {k: v for k, v in kw.items() if k in props}


# --------------------------------------------------------------------------------------------- options
def parse_args(argv):
    p = argparse.ArgumentParser(prog="blender -b --python prep_prop_hq.py --",
                                formatter_class=argparse.ArgumentDefaultsHelpFormatter,
                                description="Meshy prop -> Godot glb, quality first (see the header).")
    p.add_argument("src", help="model file, or a folder of them")
    p.add_argument("out", help="output .glb (file input) or output folder (folder input)")
    p.add_argument("size", nargs="?", type=float, default=None, help="size in metres of the --axis dimension (default: keep Meshy's size)")
    p.add_argument("--axis", choices=["height", "width", "depth"], default="height", help="which dimension <size> sets")
    p.add_argument("--turn", type=float, default=0.0, help="degrees to spin about the vertical before export")
    p.add_argument("--sink", type=float, default=0.02, help="metres the base sinks below the ground")
    p.add_argument("--recursive", action="store_true", help="folder input: also search sub-folders")
    p.add_argument("--overwrite", action="store_true", help="replace existing outputs (never the input)")
    g = p.add_argument_group("mesh")
    g.add_argument("--tris", type=int, default=150000, help="decimate above this many triangles (0 = never)")
    g.add_argument("--merge", type=float, default=0.0001, help="merge-by-distance threshold in metres (0 = off)")
    g.add_argument("--smooth-angle", type=float, default=30.0, help="edges sharper than this (degrees) stay hard")
    g.add_argument("--normals", choices=["auto", "keep", "recalc"], default="auto",
                   help="auto: keep Meshy's custom normals unless broken; keep: always; recalc: rebuild")
    g.add_argument("--keep-loose", action="store_true", help="do not delete loose vertices and edges")
    g.add_argument("--protect", type=float, default=10.0,
                   help="how strongly decimation avoids UV-seam / sharp / border vertices (0 = not at all)")
    t = p.add_argument_group("textures")
    t.add_argument("--tex", type=int, default=4096, choices=[512, 1024, 2048, 4096, 8192], help="texture cap / bake size in px")
    t.add_argument("--jpeg", action="store_true", help="embed JPEG instead of lossless PNG")
    t.add_argument("--jpeg-quality", type=int, default=92)
    b = p.add_argument_group("bake (--bake)")
    b.add_argument("--bake", action="store_true", help="bake all materials into one PBR material at --tex px")
    b.add_argument("--bake-samples", type=int, default=128, help="Cycles samples per pass")
    b.add_argument("--bake-margin", type=int, default=0, help="padding px around UV islands (0 = tex/256, 16 at 4k)")
    b.add_argument("--cage-extrusion", type=float, default=0.0, help="metres (0 = 1%% of the largest dimension)")
    b.add_argument("--reunwrap", action="store_true", help="unwrap afresh (Smart UV Project) instead of repacking Meshy's islands")
    b.add_argument("--bake-device", choices=["cpu", "gpu"], default="cpu")
    b.add_argument("--no-save-textures", dest="save_textures", action="store_false", help="don't keep the baked PNGs on disk")
    v = p.add_argument_group("variants")
    v.add_argument("--lod", action="store_true", help="also export _lod1 (50%%) and _lod2 (20%%)")
    v.add_argument("--lod-ratios", default="0.5,0.2")
    v.add_argument("--web-tris", type=int, default=0, help="also export _web.glb with this many triangles")
    v.add_argument("--web-tex", type=int, default=4096, choices=[512, 1024, 2048, 4096, 8192], help="texture cap of the web variant")
    m = p.add_argument_group("misc")
    m.add_argument("--report", default=None, help="write a JSON report here")
    m.add_argument("-v", "--verbose", action="store_true")
    return p.parse_args(argv)


# --------------------------------------------------------------------------------------- scene helpers
def select_only(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False); o.hide_viewport = False; o.select_set(True)
    bpy.context.view_layer.objects.active = active or (objs[0] if objs else None)


def tri_count(obj):
    n = len(obj.data.polygons)
    if n == 0:
        return 0
    lt = np.empty(n, dtype=np.int32)
    obj.data.polygons.foreach_get("loop_total", lt)
    return int(np.maximum(lt - 2, 0).sum())


def verts(mesh):
    P = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
    mesh.vertices.foreach_get("co", P)
    return P.reshape(-1, 3)


def set_verts(mesh, P):
    mesh.vertices.foreach_set("co", P.reshape(-1).astype(np.float32))
    mesh.update()


# ---------------------------------------------------------------------------------------------- import
def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(**op_kwargs(bpy.ops.import_scene.gltf, filepath=path, import_pack_images=True,
                                              merge_vertices=False, import_shading="NORMALS"))
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(**op_kwargs(bpy.ops.import_scene.fbx, filepath=path, use_image_search=True,
                                             use_custom_normals=True, use_anim=False, ignore_leaf_bones=True))
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        raise ValueError(f"unsupported file type {ext}")
    objs = list(bpy.context.scene.objects)
    if not objs:
        raise RuntimeError("the importer produced nothing")
    return objs


def strip_and_join(objs, name):
    """One mesh object, world transforms baked in, nothing else left in the scene."""
    meshes = [o for o in objs if o.type == "MESH" and len(o.data.polygons) > 0]
    if not meshes:
        raise RuntimeError("no mesh geometry in the file")
    for o in meshes:                                   # detach from empties/armatures, keep the pose
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    for o in meshes:                                   # modifiers become geometry
        select_only([o], o)
        for mod in list(o.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=mod.name)
            except Exception:
                o.modifiers.remove(mod)
    for o in list(bpy.context.scene.objects):
        if o not in meshes:
            bpy.data.objects.remove(o, do_unlink=True)
    meshes.sort(key=lambda o: len(o.data.polygons), reverse=True)
    host = meshes[0]
    if len(meshes) > 1:
        for o in meshes:
            if o.data.users > 1:
                o.data = o.data.copy()
        select_only(meshes, host)
        bpy.ops.object.join()
    host.name = host.data.name = name
    select_only([host], host)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return host


# ------------------------------------------------------------------------------------- mesh clean-up
def has_custom_normals(mesh):
    return "custom_normal" in mesh.attributes if NEW_NORMALS else bool(getattr(mesh, "has_custom_normals", False))


def clear_custom_normals(obj):
    mesh = obj.data
    try:
        if NEW_NORMALS and "custom_normal" in mesh.attributes:
            mesh.attributes.remove(mesh.attributes["custom_normal"])
        else:
            select_only([obj], obj)
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception as e:
        log(f"could not clear custom normals: {e}", "WARN")


def custom_normals_broken(mesh, limit=0.05):
    """True when custom normals are NaN/zero or more than `limit` of them face against their own polygon."""
    if not has_custom_normals(mesh) or len(mesh.loops) == 0:
        return False
    try:
        cn = np.empty(len(mesh.loops) * 3, dtype=np.float32)
        if NEW_NORMALS:
            mesh.corner_normals.foreach_get("vector", cn)
        else:
            mesh.calc_normals_split(); mesh.loops.foreach_get("normal", cn)
        cn = cn.reshape(-1, 3)
        pn = np.empty(len(mesh.polygons) * 3, dtype=np.float32)
        mesh.polygon_normals.foreach_get("vector", pn)
        lt = np.empty(len(mesh.polygons), dtype=np.int32)
        mesh.polygons.foreach_get("loop_total", lt)
        pn = np.repeat(pn.reshape(-1, 3), lt, axis=0)
        if not np.isfinite(cn).all() or (np.linalg.norm(cn, axis=1) < 1e-4).mean() > 0.001:
            return True
        return float((np.einsum("ij,ij->i", cn, pn) < 0).mean()) > limit
    except Exception as e:
        log(f"could not validate custom normals ({e}); rebuilding them", "WARN")
        return True


def cleanup(obj, merge, remove_loose):
    select_only([obj], obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    if merge > 0:
        bpy.ops.mesh.remove_doubles(**op_kwargs(bpy.ops.mesh.remove_doubles, threshold=merge, use_sharp_edge_from_normals=True))
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    if remove_loose:
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=False)
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.data.update()


def edge_classes(mesh, angle_deg):
    """Per edge: sharp (face angle above the threshold) and border (fewer than two faces)."""
    bm = bmesh.new(); bm.from_mesh(mesh)
    bm.edges.ensure_lookup_table()
    limit = math.radians(angle_deg)
    sharp = np.zeros(len(bm.edges), dtype=bool); border = np.zeros(len(bm.edges), dtype=bool)
    for e in bm.edges:
        n = len(e.link_faces)
        if n == 2:
            sharp[e.index] = e.calc_face_angle(0.0) > limit
        else:
            border[e.index] = True
    bm.free()
    return sharp, border


def smooth_by_angle(obj, angle_deg):
    """Smooth faces, hard edges above the angle: the sharp-edge flags (4.1+) or auto-smooth (older)."""
    mesh = obj.data
    mesh.polygons.foreach_set("use_smooth", np.ones(len(mesh.polygons), dtype=bool))
    sharp, _ = edge_classes(mesh, angle_deg)
    mesh.edges.foreach_set("use_edge_sharp", sharp)
    if not NEW_NORMALS and hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True; mesh.auto_smooth_angle = math.radians(angle_deg)
    mesh.update()
    return int(sharp.sum())


def protect_group(obj, angle_deg):
    """Vertex group of the vertices decimation must leave alone: UV seams, sharp edges, borders, material borders."""
    mesh = obj.data
    nv = len(mesh.vertices)
    keep = np.zeros(nv, dtype=bool)
    ne = len(mesh.edges)
    if ne:
        ev = np.empty(ne * 2, dtype=np.int32); mesh.edges.foreach_get("vertices", ev)
        sharp, border = edge_classes(mesh, angle_deg)
        flagged = ev.reshape(-1, 2)[sharp | border]
        keep[flagged.reshape(-1)] = True
    nl = len(mesh.loops)
    if nl:
        lv = np.empty(nl, dtype=np.int32); mesh.loops.foreach_get("vertex_index", lv)
        # material borders: a vertex whose corners belong to polygons of different materials
        npoly = len(mesh.polygons)
        mi = np.empty(npoly, dtype=np.int32); mesh.polygons.foreach_get("material_index", mi)
        lt = np.empty(npoly, dtype=np.int32); mesh.polygons.foreach_get("loop_total", lt)
        lm = np.repeat(mi, lt)
        if mi.max() != mi.min():
            lo = np.full(nv, 1 << 30, dtype=np.int64); hi = np.full(nv, -1, dtype=np.int64)
            np.minimum.at(lo, lv, lm); np.maximum.at(hi, lv, lm)
            keep |= hi > lo
        # UV seams: a vertex whose corners carry different UVs
        for layer in mesh.uv_layers:
            uv = np.empty(nl * 2, dtype=np.float32); layer.data.foreach_get("uv", uv)
            uv = uv.reshape(-1, 2)
            for c in range(2):
                lo = np.full(nv, np.inf, dtype=np.float32); hi = np.full(nv, -np.inf, dtype=np.float32)
                np.minimum.at(lo, lv, uv[:, c]); np.maximum.at(hi, lv, uv[:, c])
                keep |= (hi - lo) > 1e-5
    vg = obj.vertex_groups.get("keep_edges") or obj.vertex_groups.new(name="keep_edges")
    idx = np.nonzero(keep)[0].tolist()
    if idx:
        vg.add(idx, 0.9, "REPLACE")   # 0.9, not 1.0: a weight of 1 locks the vertices and the budget is never met
    return vg, len(idx)


def decimate(obj, target, smooth_angle, protect):
    """Collapse to `target` triangles (if above it). Returns the number of protected vertices or -1."""
    cur = tri_count(obj)
    if target <= 0 or cur <= target:
        return -1
    select_only([obj], obj)
    kept = 0
    if protect > 0:
        vg, kept = protect_group(obj, smooth_angle)
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = max(min(target / float(cur), 1.0), 0.001)
    mod.use_collapse_triangulate = True
    mod.use_symmetry = False
    if protect > 0 and kept:
        mod.vertex_group = vg.name
        mod.invert_vertex_group = True           # weight 1 = keep (the group marks what to protect)
        mod.vertex_group_factor = protect
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)
    if has_custom_normals(obj.data):             # interpolated custom normals after a collapse are not trustworthy
        clear_custom_normals(obj)
    smooth_by_angle(obj, smooth_angle)
    return kept


# --------------------------------------------------------------------------------------- placement
def place(obj, args):
    """Turn, scale to size, footprint centred, base on the ground sunk --sink. Returns the scale factor."""
    me = obj.data
    if args.turn:
        obj.rotation_euler = (0.0, 0.0, math.radians(args.turn))
        select_only([obj], obj)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    P = verts(me)
    lo, hi = P.min(0), P.max(0)
    ext = {"width": hi[0] - lo[0], "depth": hi[1] - lo[1], "height": hi[2] - lo[2]}[args.axis]
    k = args.size / ext if (args.size and ext > 1e-9) else 1.0
    P = (P - [(lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2]]) * k
    P[:, 2] -= args.sink
    set_verts(me, P)
    obj.location = (0, 0, 0)
    return k


def footprint(obj):
    """prep_prop.py's numbers: size (Blender axes) and the lowest 40 cm as Godot half-extents (x, z = -y)."""
    P = verts(obj.data)
    base = P[P[:, 2] < 0.4] if (P[:, 2] < 0.4).sum() > 20 else P
    size = P.max(0) - P.min(0)
    return [float(v) for v in size], float(np.abs(base[:, 0]).max()), float(np.abs(base[:, 1]).max())


# ----------------------------------------------------------------------------------------- textures
def principled(mat):
    if not mat or not mat.use_nodes:
        return None
    return next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)


def sock(node, *names):
    for n in names:
        if n in node.inputs:
            return node.inputs[n]
    return None


def images_of(obj):
    """(image, is_normal_map) for every image the object's materials use."""
    out, seen = [], set()
    for slot in obj.material_slots:
        mat = slot.material
        if not mat or not mat.use_nodes:
            continue
        for node in mat.node_tree.nodes:
            img = getattr(node, "image", None)
            if not img or img.name in seen:
                continue
            seen.add(img.name)
            normal = any(l.to_node.type == "NORMAL_MAP" for o in node.outputs for l in o.links)
            out.append((img, normal))
    return out


def touch(img):
    """Mark the pixel buffer dirty so a save writes the buffer (a scale alone leaves the file bytes in use)."""
    px = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(px); img.pixels.foreach_set(px)


def normalize_textures(obj, cap, workdir, fmt="PNG"):
    """Every texture becomes a packed PNG (lossless) no larger than `cap` px; smaller ones are never upscaled."""
    for img, is_normal in images_of(obj):
        if img.size[0] == 0:
            log(f"texture '{img.name}' has no pixels (missing file?) and will be absent", "WARN"); continue
        if is_normal and img.colorspace_settings.name != "Non-Color":
            img.colorspace_settings.name = "Non-Color"   # (changing the colour space reloads the file: do it first)
        cs = img.colorspace_settings.name
        w, h = img.size
        if max(w, h) > cap:
            s = cap / max(w, h)
            img.scale(max(1, round(w * s)), max(1, round(h * s)))
            touch(img)
        safe = "".join(c if c.isalnum() or c in "-_" else "_" for c in img.name)
        path = os.path.join(workdir, f"{safe}.png")
        img.filepath_raw = path; img.file_format = fmt
        img.save()
        new = bpy.data.images.load(path)
        new.colorspace_settings.name = cs
        new.pack()
        new.name = img.name + "_png"
        img.user_remap(new)
        bpy.data.images.remove(img)
        new.name = new.name[:-4]


def texture_report(obj):
    return [{"name": i.name, "size": [int(i.size[0]), int(i.size[1])], "packed": i.packed_file is not None,
             "normal": n, "depth": int(i.depth)} for i, n in images_of(obj)]


# --------------------------------------------------------------------------------------------- baking
class EmitOverride:
    """Temporarily feeds a Principled input (colour or value) straight into an Emission shader on the output,
    so an EMIT bake captures it as-is: no lighting, no noise."""

    def __init__(self, mats, names):
        self.mats, self.names, self.undo = mats, names, []

    def __enter__(self):
        for m in self.mats:
            p = principled(m)
            if not p:
                continue
            src = sock(p, *self.names)
            nt = m.node_tree
            out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None) \
                or next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
            if src is None or out is None:
                continue
            surf = out.inputs["Surface"]
            old = surf.links[0].from_socket if surf.is_linked else None
            emit = nt.nodes.new("ShaderNodeEmission")
            if src.is_linked:
                nt.links.new(src.links[0].from_socket, emit.inputs["Color"])
            else:
                v = src.default_value
                emit.inputs["Color"].default_value = (v, v, v, 1.0) if isinstance(v, float) else (v[0], v[1], v[2], 1.0)
            nt.links.new(emit.outputs["Emission"], surf)
            self.undo.append((nt, emit, surf, old))
        return self

    def __exit__(self, *_):
        for nt, emit, surf, old in self.undo:
            for l in list(surf.links):
                nt.links.remove(l)
            if old is not None:
                nt.links.new(old, surf)
            nt.nodes.remove(emit)


def uses(mats, names, linked_only=False):
    for m in mats:
        p = principled(m)
        s = sock(p, *names) if p else None
        if s is None:
            continue
        if s.is_linked:
            return True
        if not linked_only:
            v = s.default_value
            if (v > 0.001) if isinstance(v, float) else (max(v[:3]) > 0.001):
                return True
    return False


def uses_emission(mats):
    for m in mats:
        p = principled(m)
        if not p:
            continue
        col, st = sock(p, "Emission Color", "Emission"), sock(p, "Emission Strength")
        if col is None:
            continue
        if (col.is_linked or max(col.default_value[:3]) > 0.001) and (st is None or st.is_linked or st.default_value > 0):
            return True
    return False


def uses_alpha(mats):
    for m in mats:
        p = principled(m)
        s = sock(p, "Alpha") if p else None
        if s is not None and (s.is_linked or s.default_value < 0.999):
            return True
        if getattr(m, "blend_method", "OPAQUE") in ("BLEND", "CLIP"):   # HASHED is 4.2+'s plain dithered default
            return True
    return False


def uv_valid(mesh):
    layer = mesh.uv_layers.active
    if layer is None or len(mesh.loops) == 0:
        return False
    uv = np.empty(len(mesh.loops) * 2, dtype=np.float32); layer.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    return bool(np.isfinite(uv).all() and ((uv.max(0) - uv.min(0)) > 1e-5).all())


def unwrap_for_bake(obj, margin_px, size, fresh):
    """One UV atlas for the bake. Meshy's own islands are good (and the texture detail follows them), so they
    are repacked together (materials share UV space, so their islands overlap until then); a fresh Smart UV
    Project only when asked or when the UVs are unusable. Returns which was done."""
    mesh = obj.data
    frac = margin_px / size
    select_only([obj], obj)
    if not fresh and uv_valid(mesh):
        for i in range(len(mesh.uv_layers) - 1, 0, -1):      # one layer, the active one
            if mesh.uv_layers[i] != mesh.uv_layers.active:
                mesh.uv_layers.remove(mesh.uv_layers[i])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_all(action="SELECT")
        try:
            bpy.ops.uv.pack_islands(**op_kwargs(bpy.ops.uv.pack_islands, rotate=True, margin_method="FRACTION",
                                                margin=frac, shape_method="CONCAVE", merge_overlap=False, udim_source="CLOSEST_UDIM"))
            bpy.ops.object.mode_set(mode="OBJECT")
            return "repacked"
        except Exception as e:
            log(f"packing the islands failed ({e}); unwrapping afresh", "WARN")
            bpy.ops.object.mode_set(mode="OBJECT")
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    mesh.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(**op_kwargs(bpy.ops.uv.smart_project, angle_limit=math.radians(66.0), island_margin=frac,
                                         area_weight=0.0, correct_aspect=True, scale_to_bounds=False,
                                         margin_method="ADD", rotate_method="AXIS_ALIGNED"))
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    return "smart uv project"


def setup_cycles(args, extrusion, margin):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    cy = sc.cycles
    cy.samples = max(1, args.bake_samples); cy.use_adaptive_sampling = False
    if hasattr(cy, "use_denoising"):
        cy.use_denoising = False                  # bakes are not denoised by Cycles; our passes carry no noise
    cy.device = "CPU"
    if args.bake_device == "gpu":
        try:
            prefs = bpy.context.preferences.addons["cycles"].preferences
            for kind in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
                try:
                    prefs.compute_device_type = kind; prefs.get_devices()
                    if any(d.type != "CPU" for d in prefs.devices):
                        for d in prefs.devices:
                            d.use = True
                        cy.device = "GPU"; log(f"baking on {kind}"); break
                except Exception:
                    continue
        except Exception as e:
            log(f"no GPU for Cycles ({e}); baking on the CPU", "WARN")
    bk = sc.render.bake
    bk.use_selected_to_active = True; bk.use_cage = False
    bk.cage_extrusion = extrusion; bk.max_ray_distance = extrusion * 2.0
    bk.margin = margin
    if hasattr(bk, "margin_type"):
        bk.margin_type = "EXTEND"
    bk.use_clear = True
    if hasattr(bk, "target"):
        bk.target = "IMAGE_TEXTURES"
    try:
        sc.view_settings.view_transform = "Standard"; sc.view_settings.look = "None"
    except Exception:
        pass
    sc.render.image_settings.file_format = "PNG"; sc.render.image_settings.color_depth = "16"


def bake_one_material(lo, hi, stem, out_dir, args, rep):
    """All of `hi`'s materials baked onto one new material on `lo` (which is the final, decimated mesh)."""
    size = args.tex
    P = verts(lo.data)
    max_dim = float((P.max(0) - P.min(0)).max())
    extrusion = args.cage_extrusion or max(max_dim * 0.01, 1e-4)
    margin = args.bake_margin or max(4, size // 256)
    setup_cycles(args, extrusion, margin)
    mats = [s.material for s in hi.material_slots if s.material]
    if not mats:
        raise RuntimeError("--bake needs materials and the model has none")

    if args.reunwrap or len(mats) > 1 or not uv_valid(lo.data):
        rep["uv"] = unwrap_for_bake(lo, margin, size, args.reunwrap)
        log(f"UV atlas: {rep['uv']} ({len(mats)} source material(s))")
    else:
        rep["uv"] = "kept"
    uv_name = lo.data.uv_layers.active.name

    mat = bpy.data.materials.new(f"{stem}_baked"); mat.use_nodes = True
    nt = mat.node_tree; p = principled(mat)
    lo.data.materials.clear(); lo.data.materials.append(mat)
    tex_dir = os.path.join(out_dir, f"{stem}_textures")
    os.makedirs(tex_dir, exist_ok=True)

    do_metal, do_emit, do_alpha = uses(mats, ("Metallic",)), uses_emission(mats), uses_alpha(mats)
    passes = [("basecolor", "sRGB", False, dict(type="EMIT"), ("Base Color",)),
              ("normal", "Non-Color", True, dict(type="NORMAL", normal_space="TANGENT"), None),
              ("roughness", "Non-Color", False, dict(type="EMIT"), ("Roughness",))]
    if do_metal:
        passes.append(("metallic", "Non-Color", False, dict(type="EMIT"), ("Metallic",)))
    if do_emit:
        passes.append(("emission", "sRGB", False, dict(type="EMIT"), None))
    if do_alpha:
        passes.append(("alpha", "Non-Color", False, dict(type="EMIT"), ("Alpha",)))

    nodes, y = {}, 400
    for key, cs, deep, kw, override in passes:
        t0 = time.time()
        img = bpy.data.images.new(f"{stem}_{key}", size, size, alpha=False, float_buffer=deep)
        img.colorspace_settings.name = cs
        node = nt.nodes.new("ShaderNodeTexImage"); node.image = img; node.label = key; node.location = (-700, y); y -= 300
        for n in nt.nodes:
            n.select = False
        node.select = True; nt.nodes.active = node
        select_only([hi, lo], lo)
        call = op_kwargs(bpy.ops.object.bake, use_selected_to_active=True, cage_extrusion=extrusion,
                         max_ray_distance=extrusion * 2.0, margin=margin, use_clear=True, target="IMAGE_TEXTURES", **kw)
        log(f"baking {key} {size}x{size} ...")
        if override:
            with EmitOverride(mats, override):
                bpy.ops.object.bake(**call)
        else:
            bpy.ops.object.bake(**call)
        log(f"  {key} in {time.time() - t0:.0f} s")
        nodes[key] = node

    # alpha goes into the base colour's alpha channel (one less texture, and that is how glTF carries it)
    if "alpha" in nodes:
        base, a = nodes["basecolor"].image, nodes["alpha"].image
        bp = np.empty(size * size * 4, dtype=np.float32); base.pixels.foreach_get(bp)
        ap = np.empty(size * size * 4, dtype=np.float32); a.pixels.foreach_get(ap)
        bp[3::4] = ap[0::4]
        base.pixels.foreach_set(bp)
        nt.nodes.remove(nodes.pop("alpha")); bpy.data.images.remove(a)

    # save (PNG, 16-bit where the image is float), reload packed, so the exporter embeds the file bytes verbatim
    for key, node in nodes.items():
        img = node.image
        path = os.path.join(tex_dir, f"{stem}_{key}.png")
        img.filepath_raw = path; img.file_format = "PNG"; img.save()
        cs = img.colorspace_settings.name
        new = bpy.data.images.load(path); new.colorspace_settings.name = cs; new.pack()
        node.image = new
        bpy.data.images.remove(img)
        new.name = f"{stem}_{key}"

    L = nt.links
    L.new(nodes["basecolor"].outputs["Color"], sock(p, "Base Color"))
    L.new(nodes["roughness"].outputs["Color"], sock(p, "Roughness"))
    nm = nt.nodes.new("ShaderNodeNormalMap"); nm.space = "TANGENT"; nm.uv_map = uv_name; nm.location = (-350, -200)
    L.new(nodes["normal"].outputs["Color"], nm.inputs["Color"]); L.new(nm.outputs["Normal"], sock(p, "Normal"))
    if "metallic" in nodes:
        L.new(nodes["metallic"].outputs["Color"], sock(p, "Metallic"))
    else:
        sock(p, "Metallic").default_value = 0.0
    if "emission" in nodes:
        L.new(nodes["emission"].outputs["Color"], sock(p, "Emission Color", "Emission"))
        if sock(p, "Emission Strength"):
            sock(p, "Emission Strength").default_value = 1.0
    elif sock(p, "Emission Strength"):
        sock(p, "Emission Strength").default_value = 0.0
    if do_alpha:
        L.new(nodes["basecolor"].outputs["Alpha"], sock(p, "Alpha"))
        clip = any(getattr(m, "blend_method", "") == "CLIP" for m in mats)
        for attr, val in (("blend_method", "CLIP" if clip else "BLEND"), ("surface_render_method", "DITHERED" if clip else "BLENDED")):
            if hasattr(mat, attr):
                try:
                    setattr(mat, attr, val)
                except Exception:
                    pass
    rep.update(baked=True, bake_passes=list(nodes), bake_textures=tex_dir, source_materials=len(mats))
    if not args.save_textures:
        rep["bake_textures"] = None
        shutil.rmtree(tex_dir, ignore_errors=True)


# --------------------------------------------------------------------------------------------- export
def export_glb(obj, path, args):
    select_only([obj], obj)
    kw = op_kwargs(bpy.ops.export_scene.gltf, filepath=path, export_format="GLB", use_selection=True, use_visible=False,
                   use_active_collection=False, export_apply=True, export_yup=True, export_normals=True,
                   export_tangents=len(obj.data.uv_layers) > 0, export_texcoords=True, export_materials="EXPORT",
                   export_image_format="JPEG" if args.jpeg else "AUTO",   # AUTO keeps our PNGs as PNG
                   export_image_quality=args.jpeg_quality, export_jpeg_quality=args.jpeg_quality,
                   export_unused_images=False, export_unused_textures=False, export_vertex_color="MATERIAL",
                   export_animations=False, export_skins=False, export_morph=False, export_cameras=False,
                   export_lights=False, export_extras=False, export_draco_mesh_compression_enable=False,
                   export_hierarchy_full_collections=False, export_gn_mesh=False, export_attributes=False)
    bpy.ops.export_scene.gltf(**kw)


def variant(obj, name, target, args):
    dup = obj.copy(); dup.data = obj.data.copy(); dup.name = dup.data.name = name
    bpy.context.scene.collection.objects.link(dup)
    decimate(dup, target, args.smooth_angle, args.protect)
    return dup


def drop(obj):
    me = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if me.users == 0:
        bpy.data.meshes.remove(me)


# --------------------------------------------------------------------------------------- one model
def out_path(src, base, suffix, args):
    path = os.path.abspath(f"{base}{suffix}.glb")
    if path == os.path.abspath(src):
        path = os.path.abspath(f"{base}_hq{suffix}.glb")
        log(f"output is the input; writing {os.path.basename(path)} instead", "WARN")
    if os.path.exists(path) and not args.overwrite:
        raise FileExistsError(f"{path} exists (--overwrite to replace)")
    return path


def process(src, out_glb, args, workdir):
    t0 = time.time()
    stem = os.path.splitext(os.path.basename(out_glb))[0]
    base = os.path.splitext(out_glb)[0]
    out_dir = os.path.dirname(os.path.abspath(out_glb))
    rep = {"input": src, "name": stem, "outputs": []}
    log(f"=== {os.path.basename(src)} -> {os.path.basename(out_glb)}")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = "METRIC"; sc.unit_settings.scale_length = 1.0

    obj = strip_and_join(import_model(src), stem)
    rep["input_tris"] = tri_count(obj)
    rep["input_materials"] = len([s for s in obj.material_slots if s.material])
    P = verts(obj.data); rep["input_size"] = [float(v) for v in P.max(0) - P.min(0)]

    had = has_custom_normals(obj.data)
    cleanup(obj, args.merge, not args.keep_loose)
    keep = had and args.normals != "recalc"
    if keep and args.normals == "auto" and custom_normals_broken(obj.data):
        log("Meshy's custom normals are broken; rebuilding the shading", "WARN"); keep = False
    if had and not keep:
        clear_custom_normals(obj)
    rep["hard_edges"] = smooth_by_angle(obj, args.smooth_angle)
    rep["normals"] = "kept" if keep and has_custom_normals(obj.data) else "rebuilt"

    rep["scale"] = place(obj, args)
    if args.merge > 0 and abs(rep["scale"] - 1.0) > 1e-6:
        cleanup(obj, args.merge, False)          # the merge threshold is in final metres

    hi = None
    if args.bake:
        hi = obj.copy(); hi.data = obj.data.copy(); hi.name = hi.data.name = f"{stem}_hi"
        bpy.context.scene.collection.objects.link(hi)

    before = tri_count(obj)
    kept = decimate(obj, args.tris, args.smooth_angle, args.protect)
    if kept >= 0:
        log(f"decimated {before:,} -> {tri_count(obj):,} tris ({kept:,} edge vertices protected)")
        rep["normals"] = "rebuilt (decimated)"
    else:
        log(f"{before:,} tris, under the {args.tris:,} budget: not decimated")
    rep["protected_vertices"] = max(kept, 0)

    if args.bake:
        bake_one_material(obj, hi, stem, out_dir, args, rep)
        drop(hi)
    else:
        rep["baked"] = False
        normalize_textures(obj, args.tex, workdir)
    rep["materials"] = len([s for s in obj.material_slots if s.material])
    rep["textures"] = texture_report(obj)

    rep["tris"] = tri_count(obj)
    rep["size"], fx, fz = footprint(obj)
    rep["foot_half"] = [fx, fz]
    main = out_path(src, base, "", args)
    export_glb(obj, main, args)
    rep["outputs"].append({"variant": "main", "path": main, "tris": rep["tris"]})

    jobs = []
    if args.lod:
        for i, r in enumerate([float(x) for x in args.lod_ratios.split(",") if x.strip()], 1):
            jobs.append((f"_lod{i}", int(rep["tris"] * r), None))
    if args.web_tris > 0:
        jobs.append(("_web", args.web_tris, args.web_tex))
    for suffix, target, cap in jobs:
        path = out_path(src, base, suffix, args)
        if cap is not None and cap < args.tex:
            normalize_textures(obj, cap, workdir)   # last variant: shrinking in place is fine
        v = variant(obj, f"{stem}{suffix}", target, args)
        export_glb(v, path, args)
        rep["outputs"].append({"variant": suffix[1:], "path": path, "tris": tri_count(v)})
        drop(v)

    rep["seconds"] = round(time.time() - t0, 1)
    report(rep)
    return rep


def report(r):
    s = r["size"]
    print("-" * 78)
    print(f"  {r['name']}")
    print(f"  tris       : {r['input_tris']:,} -> {r['tris']:,}    normals {r['normals']}, {r['hard_edges']:,} hard edges")
    print(f"  size (m)   : x {s[0]:.3f}  y(depth) {s[1]:.3f}  z(height) {s[2]:.3f}   scale x{r['scale']:.4f}")
    print(f"  materials  : {r['input_materials']} -> {r['materials']}" + (f"   [baked: {', '.join(r['bake_passes'])}; uv {r['uv']}]" if r.get("baked") else ""))
    for t in r["textures"]:
        print(f"    {t['name']}: {t['size'][0]}x{t['size'][1]} {t['depth']}-bit" + ("  normal map" if t["normal"] else "") + ("" if t["packed"] else "  NOT PACKED"))
    for o in r["outputs"]:
        print(f"  {o['variant']:<5} {o['tris']:>9,} tris  {o['path']}")
    print(f"  {r['seconds']} s")
    print("-" * 78)
    for o in r["outputs"]:
        print("PROP", o["path"], "tris", o["tris"], "size x %.2f y %.2f z %.2f" % tuple(s),
              "foot half x %.2f z %.2f" % tuple(r["foot_half"]), flush=True)


# ------------------------------------------------------------------------------------------------ main
def gather(src, recursive):
    src = os.path.abspath(src)
    if os.path.isfile(src):
        return [src]
    if not os.path.isdir(src):
        raise FileNotFoundError(src)
    files = []
    for root, dirs, names in os.walk(src):
        files += [os.path.join(root, n) for n in names if os.path.splitext(n)[1].lower() in EXTS]
        if not recursive:
            break
    files = sorted(files)
    glbs = {os.path.splitext(f)[0] for f in files if f.lower().endswith(".glb")}
    # a .gltf beside a .glb of the same name is the same model: take the .glb
    return [f for f in files if not (f.lower().endswith(".gltf") and os.path.splitext(f)[0] in glbs)]


def main():
    args = parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    log(f"Blender {bpy.app.version_string}")
    files = gather(args.src, args.recursive)
    if not files:
        log(f"nothing to do in {args.src}", "ERROR"); sys.exit(1)
    single = os.path.isfile(os.path.abspath(args.src))
    if single and not args.out.lower().endswith(".glb"):
        args.out = os.path.join(args.out, os.path.splitext(os.path.basename(files[0]))[0] + ".glb")
    os.makedirs(os.path.dirname(os.path.abspath(args.out)) if single else os.path.abspath(args.out), exist_ok=True)
    reports, failed = [], []
    workdir = tempfile.mkdtemp(prefix="prep_prop_hq_")
    try:
        for f in files:
            out = args.out if single else os.path.join(args.out, os.path.splitext(os.path.basename(f))[0] + ".glb")
            try:
                reports.append(process(f, out, args, workdir))
            except Exception as e:
                failed.append((f, str(e)))
                log(f"FAILED {os.path.basename(f)}: {e}", "ERROR")
                if args.verbose:
                    traceback.print_exc()
                reports.append({"input": f, "error": str(e)})
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as fh:
            json.dump({"blender": bpy.app.version_string, "args": vars(args), "models": reports}, fh, indent=2)
    log(f"{len(files) - len(failed)} done, {len(failed)} failed")
    for f, e in failed:
        log(f"  {os.path.basename(f)}: {e}", "ERROR")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
