# Cuts the flames Meshy modelled onto a candle prop (the game burns its own, FireFx "candle") and writes where each
# wick stands, so the game can light them. A face is flame when the colour its texture paints at the face's middle
# is a saturated, bright orange-yellow (wax is a paler tan) and it stands above the base slab.
#   blender -b --python tools/blender/battlegrounds/cut_flames.py -- in.glb out.glb wicks.json <size: x=0.6 | h=0.4>
#        [--sat 0.62] [--val 0.72] [--above 0.12]
# The wicks are written in the frame rebake_crypt_prop.py gives the prop at the same size (centred on its
# footprint, base on the ground, scaled), in Godot axes (x, y up, z = -Blender y), metres:
#   {"wicks": [[x, y, z], ...], "size": [x, y, z]}
import bpy, bmesh, sys, json, colorsys
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, WICKS, SIZE = argv[0], argv[1], argv[2], argv[3]
def opt(name, default):
    return float(argv[argv.index(name) + 1]) if name in argv else default
SAT = opt("--sat", 0.62)
VAL = opt("--val", 0.72)
ABOVE = opt("--above", 0.12)      # fraction of the prop's height above its lowest point where flames can be

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
if len(objs) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data

# the base colour image, as an array
img = None
for m in me.materials:
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None:
                links = [l for l in m.node_tree.links if l.from_node == n and l.to_socket.name == "Base Color"]
                if links:
                    img = n.image
if img is None:
    raise SystemExit("no base colour texture")
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, img.channels)[:, :, :3]

bm = bmesh.new(); bm.from_mesh(me)
uvl = bm.loops.layers.uv.active
zs = [v.co.z for v in bm.verts]
zmin, zmax = min(zs), max(zs)
z_floor = zmin + ABOVE * (zmax - zmin)
flame = []
for f in bm.faces:
    c = f.calc_center_median()
    if c.z < z_floor:
        continue
    u = sum(l[uvl].uv.x for l in f.loops) / len(f.loops)
    v = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
    x = int((u % 1.0) * (W - 1)); y = int((v % 1.0) * (H - 1))
    r, g, b = px[y, x]
    h, s, val = colorsys.rgb_to_hsv(float(r), float(g), float(b))
    if s >= SAT and val >= VAL and 0.04 <= h <= 0.17:
        flame.append(f)
print("FLAMES faces", len(flame), "of", len(bm.faces))
cent = np.array([[f.calc_center_median().x, f.calc_center_median().y, f.calc_center_median().z] for f in flame]) if flame else np.zeros((0, 3))
bmesh.ops.delete(bm, geom=flame, context="FACES")
# loose scraps the cut left (a few faces hanging where a flame met its wick)
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context="VERTS")

# the wicks: flame faces gathered by place (each candle's flame), the lowest part of each gathering
wicks = []
if len(cent):
    left = list(range(len(cent)))
    R = 0.06 * (zmax - zmin) / 1.0 + 0.04
    while left:
        seed = left[0]
        grp = [i for i in left if np.linalg.norm(cent[i, :2] - cent[seed, :2]) < R]
        # grow it once, so a tall flame's tip and base end up together
        cx = cent[grp, :2].mean(axis=0)
        grp = [i for i in left if np.linalg.norm(cent[i, :2] - cx) < R]
        left = [i for i in left if i not in grp]
        if len(grp) < 6:
            continue
        g = cent[grp]
        base = np.percentile(g[:, 2], 8)
        wicks.append([float(g[:, 0].mean()), float(g[:, 1].mean()), float(base)])

# specks of flame the colour test missed, floating over the wicks: every connected piece that starts higher than
# the wick under it
if wicks:
    WK = np.array(wicks)
    bm.verts.ensure_lookup_table()
    seen = set()
    drop = []
    for v0 in bm.verts:
        if v0.index in seen:
            continue
        stack = [v0]; comp = []; seen.add(v0.index)
        while stack:
            cur = stack.pop(); comp.append(cur)
            for e in cur.link_edges:
                o = e.other_vert(cur)
                if o.index not in seen:
                    seen.add(o.index); stack.append(o)
        co = np.array([[v.co.x, v.co.y, v.co.z] for v in comp])
        mid = co[:, :2].mean(axis=0)
        near = WK[np.argmin(np.linalg.norm(WK[:, :2] - mid, axis=1))]
        if co[:, 2].min() > near[2] + 0.012 * (zmax - zmin):
            drop.extend(comp)
    print("SPECKS verts", len(drop))
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
bm.to_mesh(me); bm.free(); me.update()

# into the prepared prop's frame (as rebake_crypt_prop.py sizes it)
P = np.empty(len(me.vertices) * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
cx = 0.5 * (P[:, 0].min() + P[:, 0].max()); cy = 0.5 * (P[:, 1].min() + P[:, 1].max()); z0 = P[:, 2].min()
key, val = SIZE.split("=")
ext = {"x": np.ptp(P[:, 0]), "h": np.ptp(P[:, 2]), "w": max(np.ptp(P[:, 0]), np.ptp(P[:, 1]))}[key]
k = float(val) / ext
out_w = [[round((w[0] - cx) * k, 4), round((w[2] - z0) * k, 4), round(-(w[1] - cy) * k, 4)] for w in wicks]
out_w.sort()
size = [round(float(np.ptp(P[:, 0])) * k, 4), round(float(np.ptp(P[:, 2])) * k, 4), round(float(np.ptp(P[:, 1])) * k, 4)]
json.dump({"wicks": out_w, "size": size}, open(WICKS, "w"), indent=1)
print("WICKS", len(out_w), out_w)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB")
print("EXPORTED", OUT)
