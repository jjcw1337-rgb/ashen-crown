# Models the living grass's clumps in Blender and exports one glb per species into assets/models/grass/.
#   blender -b --python tools/blender/grass/build_clumps.py -- assets/textures/grass/atlas.json assets/models/grass
#
# Each species (SPECIES, matching Grass.SPECIES in game/systems/world/grass.gd) is a clump of modelled blades on the Meshy
# texture atlas (game/systems/world/tools/grass_atlas.py): every blade is a folded strip (a raised midrib between two edges, so it
# catches light like a real blade), curved, twisted and tapered to a point (or snapped, for dry straw), with a
# sheath at the root and rounded normals; seed heads, flowers and broad leaves are cut-out cards from the
# atlas, crossed or laid out in rosettes. Two variants and two levels of detail (L1: about half the blades,
# wider, fewer segments, so far grass keeps its cover) per species: objects "<species>_<variant>_<lod>".
#
# The grass shader (Grass.SHADER, textured mode) reads, per vertex:
#   UV  (TEXCOORD_0)  position on the atlas
#   UV2 (TEXCOORD_1)  x = flexibility (0 stiff .. 1 bends fully), y = height along the plant (0 root .. 1 tip)
#   COLOR             r = dryness, g = sway phase, b = lushness, a = 1 tinted blade / 0.5 card in its own colours
# Blender's UVs run bottom-up; the glTF exporter flips every UV map, so both are written as 1 - v here.
import bpy, bmesh, json, math, os, random, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
META = json.load(open(argv[0]))
OUT = argv[1]
os.makedirs(OUT, exist_ok=True)
CW, CH = META["cell"]
AW, AH = META["size"]
COLS = META["cols"]
CELLS = {c["i"]: c for c in META["cells"]}
BY_NAME = {c["name"]: c["i"] for c in META["cells"]}
GREEN = [c["i"] for c in META["cells"] if c["group"] == "green"]
DRY = [c["i"] for c in META["cells"] if c["group"] == "dry"]

def cells(*names):
    return [BY_NAME[n] for n in names if n in BY_NAME]

# h/w/curve/flex are [min, max] (metres for h, w); "dry_chance" = share of blades from the straw cells
SPECIES = {
    "meadow": {"blades": 24, "radius": 0.26, "h": (0.2, 0.4), "w": (0.022, 0.034), "curve": (0.25, 0.6), "segs": 4,
               "flex": (0.7, 1.0), "dry_chance": 0.08, "skirt": 14,
               "flowers": cells("daisy", "buttercup", "yarrow", "dandelion"), "flower_n": 2},
    "tall": {"blades": 13, "radius": 0.2, "h": (0.42, 0.68), "w": (0.018, 0.028), "curve": (0.25, 0.6), "segs": 5,
             "flex": (0.85, 1.0), "dry_chance": 0.3, "skirt": 8, "heads": cells("oat", "timothy", "fescue"), "head_n": 4},
    "tussock": {"blades": 30, "radius": 0.12, "h": (0.26, 0.48), "w": (0.015, 0.024), "curve": (0.5, 0.95), "segs": 4,
                "flex": (0.5, 0.75), "dry_chance": 0.32, "skirt": 10},
    "dry": {"blades": 20, "radius": 0.24, "h": (0.22, 0.44), "w": (0.018, 0.028), "curve": (0.15, 0.45), "segs": 4,
            "flex": (0.35, 0.6), "dry_chance": 1.0, "broken": 0.25, "skirt": 10,
            "heads": cells("heather", "fescue"), "head_n": 1},
    "moss": {"blades": 26, "radius": 0.26, "h": (0.03, 0.07), "w": (0.014, 0.022), "curve": (0.2, 0.5), "segs": 2,
             "flex": (0.1, 0.25), "dry_chance": 0.0, "lush": 1.0, "leaves": cells("clover"), "leaf_n": 5, "leaf_h": (0.06, 0.1)},
    "weed": {"blades": 4, "radius": 0.06, "h": (0.12, 0.22), "w": (0.02, 0.03), "curve": (0.3, 0.6), "segs": 3,
             "flex": (0.4, 0.6), "dry_chance": 0.0, "lush": 0.8,
             "leaves": cells("plantain", "dock", "dandelion_leaf", "sorrel"), "leaf_n": 6, "leaf_h": (0.16, 0.28)},
    "sparse": {"blades": 11, "radius": 0.18, "h": (0.1, 0.22), "w": (0.016, 0.024), "curve": (0.15, 0.5), "segs": 3,
               "flex": (0.5, 0.8), "dry_chance": 0.35, "skirt": 6},
}
VARIANTS = 2

class Builder:
    def __init__(self):
        self.verts = []   # (co, normal, uv, uv2, color)
        self.tris = []
    def v(self, co, n, uv, uv2, col):
        self.verts.append((Vector(co), Vector(n).normalized(), uv, uv2, col))
        return len(self.verts) - 1
    def tri(self, a, b, c):
        self.tris.append((a, b, c))

def atlas_uv(cell: int, u: float, t: float) -> tuple:
    """Cell-local (u across 0..1, t up 0..1) -> atlas UV in Blender's bottom-up convention (exported as top-down)."""
    r, c = divmod(cell, COLS)
    inset = 1.5 / CW
    x = (c + inset + u * (1 - 2 * inset)) * CW / AW
    y_top = (r * CH + (1.0 - t) * CH * 0.995 + 1) / AH     # 0 = the atlas's top edge
    return (x, 1.0 - y_top)

def blade(B: Builder, rng, root, face, lean, h, w, curve, segs, flex, cell, dry, lush, twist, pointed=True):
    phase = rng.random()
    col = (dry, phase, lush, 1.0)
    rows = []
    for s in range(segs + 1):
        t = s / segs
        p = Vector(root) + lean * (curve * h * t * t) + Vector((0, 0, 1)) * (h * t * (1 - 0.3 * curve * curve * t * t))
        tw = face + twist * t
        side = Vector((math.cos(tw), math.sin(tw), 0))
        # a sheath at the root, widest a little above it, then tapering to the tip (or a ragged break)
        if t < 0.12:
            wt = w * (0.75 + 0.25 * t / 0.12)
        else:
            wt = w * (1 - ((t - 0.12) / 0.88) ** 1.5 * (0.97 if pointed else 0.55))
        tan = (lean * (curve * 2 * t) + Vector((0, 0, 1 - 0.9 * curve * curve * t * t))).normalized()
        nrm = side.cross(tan).normalized()
        if nrm.z < 0:
            nrm = -nrm
        fold = wt * 0.35   # the midrib stands out of the blade's plane, so its two halves face apart
        rows.append((p, side, wt, nrm, t, fold))
    idx = []
    for s, (p, side, wt, nrm, t, fold) in enumerate(rows):
        u2 = (flex, 1.0 - t)
        if s == segs and pointed:
            idx.append((B.v(p, nrm, atlas_uv(cell, 0.5, t), u2, col),) * 3)
            continue
        l = B.v(p - side * wt * 0.5, nrm * 0.8 - side * 0.6, atlas_uv(cell, 0.0, t), u2, col)
        m = B.v(p + nrm * fold, nrm, atlas_uv(cell, 0.5, t), u2, col)
        r = B.v(p + side * wt * 0.5, nrm * 0.8 + side * 0.6, atlas_uv(cell, 1.0, t), u2, col)
        idx.append((l, m, r))
    for s in range(segs):
        l0, m0, r0 = idx[s]
        l1, m1, r1 = idx[s + 1]
        if l1 == m1 == r1:
            B.tri(l0, m0, m1); B.tri(m0, r0, m1)
        else:
            B.tri(l0, m0, m1); B.tri(l0, m1, l1)
            B.tri(m0, r0, r1); B.tri(m0, r1, m1)

def card(B: Builder, rng, root, yaw, tilt, h, cell, flex, lush, rows=3):
    """A cut-out plant from the atlas, standing at `root` facing `yaw`, leaning `tilt` radians out."""
    meta = CELLS[cell]
    wf, hf = meta["wf"], meta["hf"]
    w = h * (wf * CW) / (hf * CH)
    phase = rng.random()
    col = (0.0, phase, lush, 0.5)
    side = Vector((math.cos(yaw), math.sin(yaw), 0))
    out = Vector((-math.sin(yaw), math.cos(yaw), 0))
    up = (Vector((0, 0, 1)) * math.cos(tilt) + out * math.sin(tilt)).normalized()
    n = side.cross(up).normalized()
    if n.z < 0:
        n = -n
    nn = (n + Vector((0, 0, 0.6))).normalized()
    idx = []
    for s in range(rows):
        t = s / (rows - 1)
        p = Vector(root) + up * (h * t)
        u0, u1 = 0.5 - wf / 2, 0.5 + wf / 2
        a = B.v(p - side * w * 0.5, nn, atlas_uv(cell, u0, t * hf), (flex, 1.0 - t), col)
        b = B.v(p + side * w * 0.5, nn, atlas_uv(cell, u1, t * hf), (flex, 1.0 - t), col)
        idx.append((a, b))
    for s in range(rows - 1):
        a0, b0 = idx[s]
        a1, b1 = idx[s + 1]
        B.tri(a0, b0, b1); B.tri(a0, b1, a1)

def clump(sp: str, v: int, lod: int) -> Builder:
    S = SPECIES[sp]
    rng = random.Random(hash(sp) % 100000 + v * 7919)
    B = Builder()
    segs = S["segs"] if lod == 0 else max(1, S["segs"] - 1)
    for i in range(S["blades"]):
        a = rng.random() * math.tau
        rr = math.sqrt(rng.random()) * S["radius"]
        root = Vector((math.cos(a) * rr, math.sin(a) * rr, -0.01))
        h = rng.uniform(*S["h"]); w = rng.uniform(*S["w"]); curve = rng.uniform(*S["curve"]); flex = rng.uniform(*S["flex"])
        face = rng.random() * math.tau
        outv = Vector((root.x, root.y, 0)).normalized() if rr > 0.01 else Vector((math.cos(face), math.sin(face), 0))
        lean = (outv + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0))).normalized()
        dry = rng.random() < S.get("dry_chance", 0)
        cell = rng.choice(DRY if dry else GREEN)
        twist = rng.uniform(-0.8, 0.8)
        broken = rng.random() < S.get("broken", 0)
        keep = rng.random()
        if lod == 1 and keep >= 0.55:
            continue
        if broken:
            h *= 0.65
        blade(B, rng, root, face, lean, h, w * (1.6 if lod == 1 else 1.0), curve, segs, flex, cell,
              0.8 if dry else 0.0, S.get("lush", 0.0), twist, not broken)
    # a low skirt of short blades lying out round the clump, covering the soil between clumps
    for i in range(S.get("skirt", 0)):
        a = rng.random() * math.tau
        rr = (0.4 + 1.3 * math.sqrt(rng.random())) * S["radius"]
        root = Vector((math.cos(a) * rr, math.sin(a) * rr, -0.005))
        lean = (Vector((math.cos(a), math.sin(a), 0)) + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0))).normalized()
        cell = rng.choice(GREEN if rng.random() > S.get("dry_chance", 0) * 0.5 else DRY)
        keep = rng.random()
        if lod == 1 and keep >= 0.5:
            continue
        blade(B, rng, root, rng.random() * math.tau, lean, rng.uniform(0.05, 0.12), rng.uniform(0.03, 0.045),
              rng.uniform(0.9, 1.3), 1, rng.uniform(0.2, 0.4), cell, 0.0, 0.3, 0.0, True)
    # seed heads on tall stalks (two crossed cards each)
    for i in range(S.get("head_n", 0)):
        if lod == 1 and i % 2 == 1:
            continue
        a = rng.random() * math.tau
        root = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0, S["radius"] * 0.6)
        h = S["h"][1] * rng.uniform(1.0, 1.25)
        cell = rng.choice(S["heads"])
        yaw = rng.random() * math.pi
        tilt = rng.uniform(0.0, 0.25)
        flex = rng.uniform(0.85, 1.0)
        card(B, rng, root, yaw, tilt, h, cell, flex, 0.0, 4)
        if lod == 0:
            card(B, rng, root, yaw + math.pi / 2, tilt, h, cell, flex, 0.0, 4)
    # moorland flowers rising a little above the grass (variant 0 only, so not every clump flowers)
    if v == 0 and lod == 0:
        for i in range(S.get("flower_n", 0)):
            a = rng.random() * math.tau
            root = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.03, 0.14)
            cell = rng.choice(S["flowers"])
            h = S["h"][1] * rng.uniform(1.0, 1.3)
            yaw = rng.random() * math.pi
            card(B, rng, root, yaw, rng.uniform(0, 0.2), h, cell, 0.9, 0.0, 3)
            card(B, rng, root, yaw + math.pi / 2, rng.uniform(0, 0.2), h, cell, 0.9, 0.0, 3)
    # broad leaves in a rosette, lying out from the heart
    for i in range(S.get("leaf_n", 0)):
        if lod == 1 and i % 2 == 1:
            continue
        a = i / max(1, S["leaf_n"]) * math.tau + rng.uniform(-0.3, 0.3)
        root = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.0, 0.04)
        yaw = a - math.pi / 2           # the card's "out" direction points away from the heart
        cell = rng.choice(S["leaves"])
        card(B, rng, root, yaw, rng.uniform(0.6, 1.05), rng.uniform(*S["leaf_h"]), cell, rng.uniform(0.3, 0.5), S.get("lush", 0.5), 3)
    return B

def to_object(name: str, B: Builder):
    me = bpy.data.meshes.new(name)
    me.from_pydata([v[0] for v in B.verts], [], B.tris)
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    uv2 = me.uv_layers.new(name="UV2")
    colattr = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    for i, vv in enumerate(B.verts):
        colattr.data[i].color = vv[4]
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            uv.data[li].uv = B.verts[vi][2]
            uv2.data[li].uv = B.verts[vi][3]
    me.color_attributes.active_color = colattr
    me.normals_split_custom_set_from_vertices([v[1] for v in B.verts])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob

stats = []
for sp in SPECIES:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for v in range(VARIANTS):
        for lod in range(2):
            B = clump(sp, v, lod)
            to_object(f"{sp}_{v}_{lod}", B)
            stats.append(f"{sp}_{v}_{lod}: {len(B.verts)} verts, {len(B.tris)} tris")
    path = os.path.join(OUT, sp + ".glb")
    kw = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=False, export_normals=True,
              export_texcoords=True, export_materials="NONE", export_animations=False, export_skins=False)
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color="ACTIVE")
    except TypeError:
        bpy.ops.export_scene.gltf(**kw, export_colors=True)
    print("wrote", path)
print("\n".join(stats))
