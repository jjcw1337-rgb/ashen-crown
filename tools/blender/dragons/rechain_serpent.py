"""Re-rigs the Frost Serpent with a real spine (jj, 2026-11-04: "fix his movement so it matches actually moving ... a
feeling of life"): its first rig gave the long body two spine bones, four in the neck and six in the tail, so it bent
like a few planks. This one runs a chain of vertebrae down the body's real centreline: TAIL bones from the tip to the
hips, SPINE from the hips to the shoulders, NECK up the S of the neck to the head; the legs, head and jaw keep their
bones (the legs re-parented onto the nearest vertebra) and their weights.

    blender -b --python tools/blender/dragons/rechain_serpent.py -- <serpent.glb> <out.glb> [tail 12] [spine 6] [neck 7]

The centreline: the old chain's polyline, resampled, each sample pulled to the middle of the body's cross-section
there (the centroid of the vertices in a thin slab across it, legs left out by a radius), then smoothed. The weights:
whatever a vertex had on the old body bones (root, spine, neck, tail) is handed to the new chain by where it projects
onto the centreline (the bone it falls in, blended into the next across each joint); head, jaw and leg weights stay.
Prints the new chain and the weight coverage.
"""
import bpy, bmesh, sys, math
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
NT = int(a[2]) if len(a) > 2 else 12
NS = int(a[3]) if len(a) > 3 else 6
NN = int(a[4]) if len(a) > 4 else 7

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.context.scene.objects):
    if o.type in ("LIGHT", "CAMERA") or (o.type == "MESH" and o.parent is None and len(o.data.vertices) < 200):
        bpy.data.objects.remove(o)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
me = next(o for o in bpy.context.scene.objects if o.type == "MESH" and o.parent == arm)
W = arm.matrix_world
bones = {b.name: (W @ b.head_local, W @ b.tail_local) for b in arm.data.bones}

def chain(prefix):
    names = sorted([n for n in bones if n.startswith(prefix)], key=lambda n: int(n.split("_")[-1]))
    return names

# --- the old body path, tail tip -> hips -> shoulders -> head
tail = chain("tail_")
spine = chain("spine_")
neck = chain("neck_")
path = [bones[tail[-1]][1]] + [bones[n][0] for n in reversed(tail)]          # tip .. tail_0 head (= the hips)
hips_i = len(path) - 1
path += [bones[n][1] for n in spine]                                          # .. the shoulders
shoulders_i = len(path) - 1
path += [bones[n][1] for n in neck]                                           # .. the head
head_pt = bones["head_0"][0]
path[-1] = head_pt

def resample(pts, n):
    L = [0.0]
    for i in range(1, len(pts)):
        L.append(L[-1] + (pts[i] - pts[i - 1]).length)
    out = []
    for k in range(n + 1):
        s = L[-1] * k / n
        j = max(1, next((i for i in range(1, len(L)) if L[i] >= s), len(L) - 1))
        f = (s - L[j - 1]) / max(L[j] - L[j - 1], 1e-6)
        out.append(pts[j - 1].lerp(pts[j], f))
    return out

def section(pts, n):
    return resample(pts, n)

# each part resampled densely, pulled to the body's middle, then cut into its bones
verts = [me.matrix_world @ v.co for v in me.data.vertices]
def centre(p, t, r):
    acc = Vector()
    c = 0
    for v in verts:
        d = v - p
        if abs(d.dot(t)) < 0.06 and (d - t * d.dot(t)).length < r:
            acc += v
            c += 1
    return acc / c if c > 8 else p

def refine(pts, r):
    dense = resample(pts, 40)
    out = []
    for i, p in enumerate(dense):
        t = (dense[min(i + 1, len(dense) - 1)] - dense[max(i - 1, 0)]).normalized()
        out.append(centre(p, t, r))
    # smooth (keep the ends)
    for _ in range(3):
        out = [out[0]] + [(out[i - 1] + out[i] * 2 + out[i + 1]) / 4 for i in range(1, len(out) - 1)] + [out[-1]]
    return out

tail_pts = refine(path[:hips_i + 1], 0.75)
spine_pts = refine(path[hips_i:shoulders_i + 1], 0.95)
neck_pts = refine(path[shoulders_i:], 0.7)
tail_pts[-1] = spine_pts[0]
neck_pts[0] = spine_pts[-1]
neck_pts[-1] = head_pt
T = resample(tail_pts, NT)       # tip .. hips
S = resample(spine_pts, NS)      # hips .. shoulders
N = resample(neck_pts, NN)       # shoulders .. head

# --- the new armature: edit the old one in place (keeps the object, the mesh's modifier and the leg/head bones)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
inv = W.inverted()
old_body = [n for n in list(eb.keys()) if n.startswith(("spine_", "neck_", "tail_"))]
for n in old_body:
    eb[n].name = "old_" + n          # (out of the way of the new bones' names)
old_body = ["old_" + n for n in old_body]
keep_parent = {}
for b in eb:
    if b.name in ("head_0",) or b.name.startswith("leg_") and b.name.endswith("_0"):
        keep_parent[b.name] = b.parent.name if b.parent else None
root = eb["root"]
new = {}
def add(name, h, t, parent):
    b = eb.new(name)
    b.head = inv @ h
    b.tail = inv @ t
    b.roll = 0.0
    b.parent = parent
    b.use_connect = False
    new[name] = b
    return b
prev = root
for i in range(NS):
    prev = add("spine_%d" % i, S[i], S[i + 1], prev)
spine_last = prev
prev = new["spine_0"]
for i in range(NT):
    # tail_0 at the hips running back toward the tip
    h = T[NT - i]
    t = T[NT - i - 1]
    prev = add("tail_%d" % i, h, t, prev if i > 0 else new["spine_0"])
prev = spine_last
for i in range(NN):
    prev = add("neck_%d" % i, N[i], N[i + 1], prev)
neck_last = prev
for n in old_body:
    eb.remove(eb[n])
eb["head_0"].parent = neck_last
# the legs onto the vertebra nearest their root
for n in [b.name for b in eb if b.name.startswith("leg_") and b.name.endswith("_0")]:
    hb = W @ eb[n].head
    best = min((nb for nb in eb if nb.name.startswith("spine_")), key=lambda nb: ((W @ nb.head) - hb).length)
    eb[n].parent = best
bpy.ops.object.mode_set(mode="OBJECT")

# --- weights: the old body weights onto the new chain by where each vertex projects onto the centreline
# the old body groups share names with new bones (spine_0, neck_0 ...): set them aside first
body_old = set()
for g in me.vertex_groups:
    # (renaming the bones renamed their groups already; any not yet renamed are renamed here)
    if g.name in old_body:
        body_old.add(g.name)
    elif "old_" + g.name in old_body or g.name == "root":
        g.name = "old_" + g.name
        body_old.add(g.name)
groups = {g.index: g.name for g in me.vertex_groups}
CH = [("tail_%d" % (NT - 1 - i), T[i], T[i + 1]) for i in range(NT)]       # tip .. hips (tail_NT-1 first)
CH += [("spine_%d" % i, S[i], S[i + 1]) for i in range(NS)]
CH += [("neck_%d" % i, N[i], N[i + 1]) for i in range(NN)]
for nm, _, _ in CH:
    if nm not in me.vertex_groups:
        me.vertex_groups.new(name=nm)
covered = 0
for v in me.data.vertices:
    body = 0.0
    for g in v.groups:
        if groups.get(g.group) in body_old:
            body += g.weight
    if body <= 1e-4:
        continue
    p = me.matrix_world @ v.co
    best = None
    bd = 1e9
    for k, (nm, h, t) in enumerate(CH):
        seg = t - h
        f = max(0.0, min(1.0, (p - h).dot(seg) / max(seg.length_squared, 1e-9)))
        d = (p - (h + seg * f)).length
        if d < bd:
            bd = d
            best = (k, f)
    k, f = best
    # blend across the joints: the half nearest a neighbour shares with it
    w_self, w_n, kn = 1.0, 0.0, k
    if f > 0.5 and k + 1 < len(CH):
        w_n = (f - 0.5) * 0.9
        kn = k + 1
    elif f < 0.5 and k > 0:
        w_n = (0.5 - f) * 0.9
        kn = k - 1
    w_self = 1.0 - w_n
    me.vertex_groups[CH[k][0]].add([v.index], body * w_self, "ADD")
    if w_n > 0.0:
        me.vertex_groups[CH[kn][0]].add([v.index], body * w_n, "ADD")
    covered += 1
for n in body_old:
    if n != "old_root" and n in me.vertex_groups:
        me.vertex_groups.remove(me.vertex_groups[n])
if "old_root" in me.vertex_groups:
    me.vertex_groups["old_root"].name = "root"
print("RECHAIN", "tail", NT, "spine", NS, "neck", NN, "vertices re-weighted", covered, "of", len(me.data.vertices))
for nm, h, t in CH:
    print("  ", nm, tuple(round(x, 2) for x in h))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_skins=True, export_animations=False,
    export_image_format="AUTO")
print("EXPORTED", OUT)
