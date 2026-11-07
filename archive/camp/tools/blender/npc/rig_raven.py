# The camp's ravens (jj, 2026-11-04: "birds land on it with real movement"): the Meshy raven (concept: wings spread,
# standing on a perch stick; image-to-3D) cleaned and rigged for game/maps/camp/raven.gd, which poses it in code (no baked
# animations). The perch stick is cut away, the mesh welded, decimated and scaled to a raven's size (wingspan WINGSPAN
# m), stood with its feet on the origin, facing Godot's +z. Bones (all from the feet): root at the feet; body (belly to
# breast) with neck -> head, tail, and each wing in three (wL1 shoulder to elbow, wL2 elbow to wrist, wL3 wrist to the
# tip; wR*), legs. Skinned by region with soft edges (wings by the distance out along the span, the head and neck by
# height, the tail by how far behind), so the wings fold and beat and the head turns without tearing.
#   blender -b --python tools/blender/npc/rig_raven.py -- <meshy.glb> <out.glb> [tris 9000] [--debug prefix]
import bpy, bmesh, sys, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
TRIS = int(argv[2]) if len(argv) > 2 and not argv[2].startswith("--") else 9000
DEBUG = argv[argv.index("--debug") + 1] if "--debug" in argv else ""
WINGSPAN = 1.05

def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in ms:
    o.select_set(True)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
for o in list(bpy.context.scene.objects):
    if o != ob:
        bpy.data.objects.remove(o, do_unlink=True)
ob.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

bm = bmesh.new()
bm.from_mesh(ob.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0008)
zs = [v.co.z for v in bm.verts]
zmin, zmax = min(zs), max(zs)
H = zmax - zmin
# the perch stick: the bottom slab, under and between the feet
# The stick is pale wood/silver where the bird is near black: faces low on the model whose texture is light go first.
img = None
for mat in ob.data.materials:
    if mat and mat.use_nodes:
        for nd in mat.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image is not None:
                img = img or nd.image
if img is not None:
    W, Hh = img.size
    px = list(img.pixels[:])
    uvl = bm.loops.layers.uv.active
    light = []
    for f in bm.faces:
        if f.calc_center_median().z > zmin + H * 0.25:
            continue
        uv = sum((l[uvl].uv for l in f.loops), mathutils.Vector((0, 0))) / len(f.loops)
        x = min(W - 1, max(0, int(uv.x * W)))
        y = min(Hh - 1, max(0, int(uv.y * Hh)))
        i = (y * W + x) * 4
        lum = 0.3 * px[i] + 0.59 * px[i + 1] + 0.11 * px[i + 2]
        if lum > 0.3:
            light.append(f)
    print("RAVEN stick faces by colour", len(light))
    bmesh.ops.delete(bm, geom=light, context="FACES")
# (the toes wrapped round it go with it: too small to see from the game's camera, and the bird stands on its feet)
cut = zmin + H * 0.12
kill = [f for f in bm.faces if f.calc_center_median().z < cut and abs(f.calc_center_median().x) < 0.3 * H / 0.8]
bmesh.ops.delete(bm, geom=kill, context="FACES")
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(ob.data)
bm.free()

# which way it faces: the beak is the head's furthest point forward or back (Meshy's raven: this finds the back of the
# head's feathers, so the sign is taken the other way round, checked on the debug renders)
vs = ob.data.vertices
zs = [v.co.z for v in vs]
zmin, zmax = min(zs), max(zs)
H = zmax - zmin
head = [v.co for v in vs if v.co.z > zmin + H * 0.72 and abs(v.co.x) < 0.12]
hy = sum(p.y for p in head) / len(head)
tip = max(head, key=lambda p: abs(p.y - hy))
F = 1.0 if tip.y > hy else -1.0
print("RAVEN faces", "+y" if F > 0 else "-y", "H", round(H, 3))

# decimate, scale, feet on the origin
dm = ob.modifiers.new("d", "DECIMATE")
dm.ratio = min(1.0, TRIS / max(1, len(ob.data.polygons)))
bpy.ops.object.modifier_apply(modifier="d")
xs = [abs(v.co.x) for v in ob.data.vertices]
k = WINGSPAN / (2.0 * max(xs))
cx = sum(v.co.x for v in ob.data.vertices) / len(ob.data.vertices)
cy = sum(v.co.y for v in ob.data.vertices if abs(v.co.x) < 0.12 / k * k) / max(1, len([1 for v in ob.data.vertices if abs(v.co.x) < 0.12]))
low = min(v.co.z for v in ob.data.vertices)
feet = [v.co for v in ob.data.vertices if v.co.z < low + H * 0.12]
fy = sum(p.y for p in feet) / len(feet)
for v in ob.data.vertices:
    v.co = mathutils.Vector(((v.co.x - cx) * k, (v.co.y - fy) * k * F, (v.co.z - low) * k))
# now it faces Blender -y (glTF export: Godot +z)
ob.data.update()
P = [v.co for v in ob.data.vertices]
H = max(p.z for p in P)
SPAN = WINGSPAN * 0.5
core = [p for p in P if abs(p.x) < SPAN * 0.12]
print("RAVEN height", round(H, 3), "verts", len(P))

def at(cond):
    pts = [p for p in P if cond(p)]
    if not pts:
        return mathutils.Vector()
    return sum(pts, mathutils.Vector()) / len(pts)

SH = SPAN * 0.13                       # the shoulder, out from the middle
belly = at(lambda p: abs(p.x) < SH and H * 0.2 < p.z < H * 0.35)
breast = at(lambda p: abs(p.x) < SH and H * 0.5 < p.z < H * 0.62)
neck = at(lambda p: abs(p.x) < SH and H * 0.62 < p.z < H * 0.72)
headc = at(lambda p: abs(p.x) < SH and p.z > H * 0.8)
beak = min((p for p in P if abs(p.x) < SH and p.z > H * 0.7), key=lambda p: p.y)
tailb = at(lambda p: abs(p.x) < SH and p.y > belly.y + H * 0.08 and p.z < H * 0.45)
tailt = max((p for p in P if abs(p.x) < SH and p.z < H * 0.5), key=lambda p: p.y)

def wing_pt(side, frac):
    x = SPAN * frac
    pts = [p for p in P if abs(side * p.x - x) < SPAN * 0.04]
    return sum(pts, mathutils.Vector()) / len(pts) if pts else mathutils.Vector((side * x, 0, H * 0.7))

arm_data = bpy.data.armatures.new("RavenRig")
arm = bpy.data.objects.new("Raven", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones

def bone(name, h, t, parent=None):
    b = eb.new(name)
    b.head = h
    b.tail = t if (t - h).length > 1e-4 else h + mathutils.Vector((0, 0, 0.02))
    if parent:
        b.parent = eb[parent]
    return b

bone("root", mathutils.Vector((0, 0, 0)), mathutils.Vector((0, 0, H * 0.15)))
bone("legs", mathutils.Vector((0, 0, 0)), mathutils.Vector((0, belly.y, H * 0.2)), "root")
bone("body", mathutils.Vector((0, belly.y, H * 0.22)), breast, "root")
bone("neck", breast, neck + (headc - neck) * 0.4, "body")
bone("head", neck + (headc - neck) * 0.4, beak, "neck")
bone("tail", mathutils.Vector((0, tailb.y - H * 0.05, tailb.z + H * 0.05)), tailt, "body")
for side, s in (("L", 1.0), ("R", -1.0)):
    sh = wing_pt(s, 0.13)
    el = wing_pt(s, 0.4)
    wr = wing_pt(s, 0.66)
    tp = wing_pt(s, 0.97)
    bone("w%s1" % side, sh, el, "body")
    bone("w%s2" % side, el, wr, "w%s1" % side)
    bone("w%s3" % side, wr, tp, "w%s2" % side)
bpy.ops.object.mode_set(mode="OBJECT")

# weights by region
for n in ["root", "legs", "body", "neck", "head", "tail", "wL1", "wL2", "wL3", "wR1", "wR2", "wR3"]:
    ob.vertex_groups.new(name=n)
G = {g.name: g for g in ob.vertex_groups}
neck_z = H * 0.66
for v in ob.data.vertices:
    p = v.co
    ax = abs(p.x) / SPAN
    side = "L" if p.x > 0 else "R"
    ws = {}
    wing = smooth(0.1, 0.17, ax)
    if wing > 0:
        w3 = smooth(0.6, 0.72, ax)
        w2 = smooth(0.34, 0.46, ax) * (1 - w3)
        w1 = 1 - w2 - w3
        ws["w%s1" % side] = wing * w1
        ws["w%s2" % side] = wing * w2
        ws["w%s3" % side] = wing * w3
    rest = 1 - wing
    if rest > 0:
        hd = smooth(neck_z - H * 0.04, neck_z + H * 0.1, p.z)
        hh = smooth(neck_z + H * 0.06, neck_z + H * 0.14, p.z)
        # the tail: behind the feet (the feet are on y = 0; it droops nearly to the ground), below the back
        tl = smooth(0.02, 0.07, p.y) * (1 - smooth(H * 0.4, H * 0.5, p.z))
        lg = (1 - smooth(H * 0.12, H * 0.2, p.z)) * (1 - smooth(0.04, 0.08, p.y))
        ws["head"] = rest * hh
        ws["neck"] = rest * (hd - hh)
        r2 = rest * (1 - hd)
        ws["legs"] = r2 * lg
        ws["tail"] = r2 * (1 - lg) * tl
        ws["body"] = r2 * (1 - lg) * (1 - tl)
    for n, w in ws.items():
        if w > 0.001:
            G[n].add([v.index], w, "REPLACE")
mod = ob.modifiers.new("arm", "ARMATURE")
mod.object = arm
ob.parent = arm
for b in arm.data.bones:
    print("BONE", b.name, [round(c, 3) for c in b.head_local], [round(c, 3) for c in b.tail_local])

if DEBUG:
    sc = bpy.context.scene
    cols = {"root": (0.5, 0.5, 0.5), "legs": (1, 1, 0), "body": (0.2, 0.2, 1), "neck": (0, 1, 1), "head": (1, 0, 0), "tail": (1, 0, 1),
            "wL1": (0, 1, 0), "wL2": (0, 0.6, 0), "wL3": (0, 0.3, 0), "wR1": (1, 0.6, 0), "wR2": (0.7, 0.4, 0), "wR3": (0.4, 0.2, 0)}
    ca = ob.data.color_attributes.new("dbg", "FLOAT_COLOR", "POINT")
    for v in ob.data.vertices:
        best = max(v.groups, key=lambda g: g.weight) if v.groups else None
        c = cols[ob.vertex_groups[best.group].name] if best else (0, 0, 0)
        ca.data[v.index].color = (*c, 1)
    m = bpy.data.materials.new("dbg"); m.use_nodes = True
    nt = m.node_tree
    at_ = nt.nodes.new("ShaderNodeVertexColor"); at_.layer_name = "dbg"
    nt.links.new(at_.outputs[0], nt.nodes["Principled BSDF"].inputs[0])
    keep = list(ob.data.materials)
    ob.data.materials.clear(); ob.data.materials.append(m)
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam); sc.camera = cam
    l = bpy.data.objects.new("l", bpy.data.lights.new("l", "SUN")); l.data.energy = 3; sc.collection.objects.link(l)
    sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.5, 0.5, 0.5)
    sc.render.engine = "BLENDER_EEVEE_NEXT"; sc.render.resolution_x = 700; sc.render.resolution_y = 500
    c = mathutils.Vector((0, 0, H * 0.5))
    for nm, d in (("front", (0, -1, 0.15)), ("side", (1, 0, 0.1)), ("top", (0, 0.01, 1))):
        cam.location = c + mathutils.Vector(d).normalized() * 1.6
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = "%s_%s.png" % (DEBUG, nm)
        bpy.ops.render.render(write_still=True)
    # a test pose: wings half folded, head turned
    pb = arm.pose.bones
    pb["wL1"].rotation_mode = pb["wR1"].rotation_mode = "XYZ"
    ob.data.materials.clear()
    for mm in keep:
        ob.data.materials.append(mm)
    ob.data.color_attributes.remove(ob.data.color_attributes["dbg"])

for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, 1024)
bpy.ops.object.select_all(action="DESELECT")
ob.select_set(True)
arm.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_skins=True, export_animations=False,
                          export_image_format="JPEG", export_jpeg_quality=88, use_selection=True)
print("RAVEN", OUT, len(ob.data.polygons), "tris-ish")
