# Assembles the stash chest from its separately made Meshy pieces (jj: "break it down as small as you can, remake
# it like our concept"): the plinth on the ground, the box on it, the coals inside, the lid on the box's top on two
# iron strap hinges at the back, the padlock's body hanging on the front staple with a real shackle (built here: a
# bent iron bar through the body's two holes), moss tufts at the feet. Every piece is joined, its transforms applied,
# turned by its `yaw`, scaled to its size and placed; textures shrunk. Exported as parts the game moves
# (Game.chest_lid): "body" (box, plinth, moss, the hinges' fixed leaves), "lid" (origin on the hinge line),
# "lock" (origin at the staple, with its "shackle" child, origin at the shackle's hinge leg), "coals".
#   blender -b --python assemble_chest.py -- parts_dir out.glb [spec.json] [--debug prefix]
# parts_dir holds <name>/<name>.glb or <name>.glb for: body lid lock_body plinth coals moss hinge.
import bpy, bmesh, sys, os, json, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
DIR, OUT = argv[0], argv[1]
SPEC = json.load(open(argv[2])) if len(argv) > 2 and argv[2].endswith(".json") else {}
DEBUG = argv[argv.index("--debug") + 1] if "--debug" in argv else ""

# sizes in metres (Blender: x across, -y the front, z up); yaw in degrees turns a piece's front to -y
S = {
    # (jj: "looks fake in game", "the dimensions": bigger than the first pass, sized to the heroes)
    "plinth": {"w": 1.75, "yaw": 0, "h": 0.55},
    "body": {"w": 1.32, "yaw": 0, "h": 0.8},
    "lid": {"w": 1.37, "yaw": 0},
    "lock_body": {"w": 0.22, "yaw": 0},
    "coals": {"w": 1.1, "yaw": 0},
    "moss": {"w": 0.34, "yaw": 0},
    "hinge": {"w": 0.29, "yaw": 0},
    "sigil_b": {"w": 0.2, "yaw": 0},       # (Meshy's seal faces -y, out of the box's front)     # jj's gold wolf seal (optional: only with sigil_b in the parts)
    "tex": 1024,
}
for k, v in SPEC.items():
    if isinstance(v, dict) and k in S:
        S[k].update(v)
    else:
        S[k] = v

bpy.ops.wm.read_factory_settings(use_empty=True)

def find(name):
    for p in [os.path.join(DIR, name, name + ".glb"), os.path.join(DIR, name + ".glb")]:
        if os.path.exists(p):
            return p
    return None

def load(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=find(name))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in new:
        if o != ob and o.name in bpy.data.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.name = name
    # turn, then size it by its width and set its base centre on the origin (glTF imports in quaternion mode, where
    # rotation_euler is ignored)
    ob.rotation_mode = "XYZ"
    ob.rotation_euler = (0, 0, math.radians(float(S[name].get("yaw", 0))))
    bpy.ops.object.transform_apply(rotation=True)
    lo, hi = bounds(ob)
    k = float(S[name]["w"]) / max(hi.x - lo.x, 1e-6)
    ob.scale = (k, k, k * float(S[name].get("h", 1.0)))     # ("h": squash or stretch the height)
    bpy.ops.object.transform_apply(scale=True)
    lo, hi = bounds(ob)
    ob.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))))
    ob.location = (0, 0, 0)
    return ob

def bounds(ob):
    vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
    return (Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
            Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))))

def size(ob):
    lo, hi = bounds(ob)
    return hi - lo

def set_origin(o, p):
    bpy.context.scene.cursor.location = p
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

plinth = load("plinth")
body = load("body")
lid = load("lid")
lock = load("lock_body")
coals = load("coals")
moss = load("moss")
hinge = load("hinge")

ps, bs, ls = size(plinth), size(body), size(lid)
top_p = ps.z * float(S.get("plinth_sink", 0.75))     # the box sits a little into the plinth's stones
body.location = (0, 0, top_p)
bz1 = top_p + bs.z                                    # the box's rim
# the lid's planks rest on the rim (its hasp hangs below them at the front: measured away from the middle)
lw_ = ls.x
lid_floor = min((lid.matrix_world @ v.co).z for v in lid.data.vertices if abs((lid.matrix_world @ v.co).x) > lw_ * 0.22)
lid.location = (0, (bs.y - ls.y) * 0.5 + float(S.get("lid_back", 0.0)), bz1 - lid_floor - float(S.get("lid_overlap", 0.01)))
lid_top = lid.location.z + ls.z
lid_back = lid.location.y + ls.y * 0.5
# the coals on the box's inner floor: the lowest surface inside its walls, above its legs
inner = [body.matrix_world @ v.co for v in body.data.vertices]
inner = [v for v in inner if abs(v.x) < bs.x * 0.3 and abs(v.y) < bs.y * 0.28 and v.z > top_p + bs.z * 0.15]
floor_z = min(v.z for v in inner) if inner else top_p + bs.z * 0.45
coals.location = (0, 0, floor_z - size(coals).z * 0.35)
print("CHEST inner floor %.3f (rim %.3f)" % (floor_z, top_p + bs.z))
# the hinges: strap leaves lying on the lid's top a third in from each side, knuckles over its back edge (they
# turn with the lid, so they're part of it)
hinges = []
for sx in [-1, 1]:
    h = hinge if sx < 0 else hinge.copy()
    if sx > 0:
        h.data = hinge.data.copy()
        bpy.context.scene.collection.objects.link(h)
    hs = size(h)
    h.location = (sx * ls.x * 0.3, lid_back - hs.y * 0.5 + hs.z * 0.6, lid_top - hs.z * 0.45)
    hinges.append(h)
# the padlock hangs from the staple on the box's front, just under the rim
lsz = size(lock)
lock_at = Vector((0, -bs.y * 0.5 - lsz.y * 0.5 - 0.01, bz1 - float(S.get("lock_drop", 0.06)) - lsz.z))
lock.location = lock_at
# moss at the feet
tufts = []
for i, (x, y, k) in enumerate([(-0.48, -0.36, 1.0), (0.5, -0.3, 0.8), (-0.52, 0.32, 0.9), (0.46, 0.38, 0.7), (0.05, -0.47, 0.6)]):
    t = moss if i == 0 else moss.copy()
    if i > 0:
        t.data = moss.data.copy()
        bpy.context.scene.collection.objects.link(t)
    t.location = (x * bs.x, y * bs.y * 1.2, top_p * 0.6)
    t.scale = (k, k, k)
    t.rotation_euler.z = i * 1.7
    tufts.append(t)

# the shackle: a bent bar (a half torus with two legs) through the lock's holes
lw = lsz.x
r = lw * 0.3
bar = lw * 0.06
bm = bmesh.new()
segs, ring = 16, 8
leg = lsz.z * 0.35
pts = []
for i in range(segs + 1):
    a = math.pi * i / segs
    pts.append(Vector((-r * math.cos(a), 0, leg + r * math.sin(a))))
pts = [Vector((-r, 0, 0))] + pts + [Vector((r, 0, 0))]
rings = []
for i, c in enumerate(pts):
    t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
    n = t.cross(Vector((0, 1, 0))).normalized()
    b = t.cross(n).normalized()
    rings.append([bm.verts.new(c + (n * math.cos(2 * math.pi * j / ring) + b * math.sin(2 * math.pi * j / ring)) * bar) for j in range(ring)])
for i in range(len(rings) - 1):
    for j in range(ring):
        bm.faces.new((rings[i][j], rings[i][(j + 1) % ring], rings[i + 1][(j + 1) % ring], rings[i + 1][j]))
me = bpy.data.meshes.new("shackle")
bm.to_mesh(me)
bm.free()
shackle = bpy.data.objects.new("shackle", me)
bpy.context.scene.collection.objects.link(shackle)
iron = bpy.data.materials.new("shackle_iron")
iron.use_nodes = True
bs_node = next(n for n in iron.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
bs_node.inputs["Base Color"].default_value = (0.16, 0.11, 0.08, 1)
bs_node.inputs["Metallic"].default_value = 0.85
bs_node.inputs["Roughness"].default_value = 0.6
me.materials.append(iron)
shackle.location = lock_at + Vector((0, 0, lsz.z * 0.82))

def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o

# the lid's underside: dark old planks (Meshy left it a flat pale board that glowed like a card in the firelight)
ll, lh = bounds(lid)
under = bpy.data.materials.new("lid_under")
under.use_nodes = True
ub = next(n for n in under.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
ub.inputs["Base Color"].default_value = (0.055, 0.035, 0.022, 1)
ub.inputs["Roughness"].default_value = 0.92
bm = bmesh.new()
i_ = 0.11
zb = lid_floor + lid.location.z + 0.02
vs_ = [bm.verts.new((x, y, zb)) for x, y in [(ll.x + i_, lh.y - i_), (lh.x - i_, lh.y - i_), (lh.x - i_, ll.y + i_), (ll.x + i_, ll.y + i_)]]
bm.faces.new(vs_)
um = bpy.data.meshes.new("lid_under")
bm.to_mesh(um)
bm.free()
um.materials.append(under)
uo = bpy.data.objects.new("lid_under", um)
bpy.context.scene.collection.objects.link(uo)
hinges.append(uo)

# the gold wolf seals (jj): two on the front either side of the padlock, one on each end, one on the back, each its
# own part ("seal_N", origin at its centre) so the game can blow them off as the chest opens (Game.chest_lid)
seals = []
if find("sigil_b"):
    seal = load("sigil_b")
    ss = size(seal)
    zc = top_p + bs.z * float(S.get("seal_at", 0.56))
    spots = [(-bs.x * 0.3, -bs.y * 0.5, 0.0), (bs.x * 0.3, -bs.y * 0.5, 0.0),
             (-bs.x * 0.5, 0.0, -90.0), (bs.x * 0.5, 0.0, 90.0), (0.0, bs.y * 0.5, 180.0)]
    for i, (x, y, yaw) in enumerate(spots):
        o = seal if i == 0 else seal.copy()
        if i > 0:
            o.data = seal.data.copy()
            bpy.context.scene.collection.objects.link(o)
        o.name = "seal_%d" % i
        # its back flat on the wood: out from the face by half its thickness and a hair
        out = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0.0))
        if abs(yaw) == 90.0:
            out = Vector((1.0 if yaw > 0 else -1.0, 0.0, 0.0))
        o.rotation_mode = "XYZ"
        o.rotation_euler = (0, 0, math.radians(yaw))
        o.location = Vector((x, y, zc - ss.z * 0.5)) + out * (ss.y * 0.5 + 0.004)
        seals.append(o)

if S.get("no_plinth"):
    # (the raid's chest stands on its dais, which has its own stone: no plinth or moss)
    bpy.data.objects.remove(plinth, do_unlink=True)
    for t_ in tufts:
        bpy.data.objects.remove(t_, do_unlink=True)
    body = join([body], "body")
else:
    body = join([body, plinth] + tufts, "body")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
lid = join([lid] + hinges, "lid")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in [lid, lock, coals, shackle] + seals:
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
lo, hi = bounds(lid)
set_origin(lid, Vector((0, hi.y, lo.z)))                       # the hinge line: the lid's back, underside
set_origin(lock, lock_at + Vector((0, 0, lsz.z)))              # it hangs from its top
for o in seals:
    lo_s, hi_s = bounds(o)
    set_origin(o, (lo_s + hi_s) * 0.5)
sl, sh = bounds(shackle)
set_origin(shackle, Vector((sh.x, (sl.y + sh.y) * 0.5, sl.z))) # it swings open on its right leg
shackle.parent = lock
shackle.matrix_parent_inverse = lock.matrix_world.inverted()

# smaller textures (the small pieces' at half)
px = int(S.get("tex", 1024))
small = {"lock_body", "hinge", "moss"}
for im in bpy.data.images:
    lim = px // 2 if any(n in im.name for n in small) else px
    if im.size[0] > lim:
        im.scale(lim, lim)

for o in [body, lid, lock, shackle, coals]:
    print("CHEST %s %d faces size %s" % (o.name, len(o.data.polygons), tuple(round(v, 3) for v in size(o))))

if DEBUG:
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 900
    sc.render.resolution_y = 760
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.1, 0.1, 0.11, 1)
    sc.world = w
    for loc, e in [((2.0, -2.4, 2.6), 400), ((-2.4, 1.4, 2.0), 150)]:
        l = bpy.data.lights.new("l", "AREA")
        l.energy = e
        l.size = 2
        lo_ = bpy.data.objects.new("l", l)
        lo_.location = loc
        lo_.rotation_euler = (Vector((0, 0, 0.4)) - lo_.location).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(lo_)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    def shot(nm, eye):
        cam.location = Vector(eye)
        cam.rotation_euler = (Vector((0, 0, 0.42)) - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = DEBUG + "_" + nm + ".png"
        bpy.ops.render.render(write_still=True)
    shot("front34", (1.5, -2.2, 1.6))
    shot("back34", (-1.6, 2.0, 1.5))
    shot("top_closed", (0.4, -1.3, 2.6))      # (about the game camera's angle)
    shot("back", (0.0, 2.6, 0.9))
    shot("left", (-2.6, 0.0, 0.9))
    for o in [lid, lock, shackle]:
        o.rotation_mode = "XYZ"
    lid.rotation_euler.x = math.radians(-105)      # (the game's Game.LID_OPEN, the same direction in Godot)
    shackle.rotation_euler.y = math.radians(-60)
    lock.rotation_euler.x = math.radians(-12)
    shot("open34", (1.5, -2.2, 1.6))
    shot("open_top", (0.6, -1.4, 2.2))
    lid.rotation_euler.x = 0
    shackle.rotation_euler.y = 0
    lock.rotation_euler.x = 0

bpy.ops.object.select_all(action="SELECT")
for o in list(bpy.context.selected_objects):
    if o.type not in ("MESH",):
        o.select_set(False)
# every material double-sided: Meshy's thin walls (the open box's) are single faces, and from outside the box's
# front was see-through in the game
for m in bpy.data.materials:
    m.use_backface_culling = False
# (JPEG textures: seven pieces each with their own maps came to 19 MB as PNG)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True,
    export_image_format="JPEG", export_jpeg_quality=86)
print("CHEST wrote", OUT)
