#!/usr/bin/env python3
"""The ranger's colour schemes: recolours the Meshy albedo so the archer stands out in the world.

  python3 tools/archer_colors.py albedo.png regions.json out_dir [scheme ...]

albedo.png: the ranger's base colour (dumped from assets/models/archer_ranger.glb), regions.json: from
tools/blender/archer/region_uv.py. Writes <out_dir>/ranger_<scheme>.jpg for each scheme in SCHEMES.

Each texel is weighed by what it looks like (cloth: dark and grey; leather: warm brown; fur: pale; skin
is left alone) and by where on the body it is (the face is never touched; hood, tunic and legs can each take
their own colour). The cloth keeps its shading and weave, only its colour changes.
"""
import json, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# per scheme: cloth colour on the hood, the tunic/arms, the coat's skirt, the trousers; the leather's tint; the fur's tint
SCHEMES = {
    "crimson": {"head": (0.60, 0.07, 0.06), "torso": (0.52, 0.06, 0.05), "coat": (0.42, 0.05, 0.05), "legs": (0.20, 0.05, 0.05),
                "leather": (0.42, 0.24, 0.12), "fur": (1.0, 0.96, 0.88)},
    "teal":    {"head": (0.05, 0.42, 0.46), "torso": (0.04, 0.36, 0.40), "coat": (0.03, 0.28, 0.32), "legs": (0.04, 0.15, 0.17),
                "leather": (0.36, 0.24, 0.15), "fur": (0.93, 0.96, 1.0)},
    "verdant": {"head": (0.16, 0.45, 0.14), "torso": (0.13, 0.40, 0.12), "coat": (0.10, 0.32, 0.09), "legs": (0.07, 0.16, 0.06),
                "leather": (0.45, 0.30, 0.13), "fur": (1.0, 0.97, 0.86)},
    "royal":   {"head": (0.18, 0.13, 0.55), "torso": (0.15, 0.11, 0.48), "coat": (0.12, 0.09, 0.40), "legs": (0.07, 0.06, 0.19),
                "leather": (0.40, 0.25, 0.14), "fur": (1.0, 0.97, 0.9)},
}
REGIONS = ["face", "head", "torso", "coat", "legs", "hands"]

def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def poly_map(path, size):
    """Each texel's polygon (0 = none), and each polygon's region."""
    im = Image.new("I", (size, size), 0)
    d = ImageDraw.Draw(im)
    polys = json.load(open(path))["polys"]
    reg = np.zeros(len(polys) + 1, np.int32)
    for k, (r, tri) in enumerate(polys, 1):
        d.polygon([(u * size, (1 - v) * size) for u, v in tri], fill=k)
        reg[k] = REGIONS.index(r) + 1
    ids = np.asarray(im).astype(np.int64)
    # grow the islands a little (texels just outside a triangle take its neighbour's id) so seams don't show
    grown = np.asarray(im.filter(ImageFilter.MaxFilter(5))).astype(np.int64)
    ids = np.where(ids == 0, grown, ids)
    return ids, reg

def recolour(a, ids, reg, sc):
    """Each polygon is classed as a whole from its texels' mean (cloth, leather, fur or skin), so a patch never
    comes out speckled; within it the cloth keeps its own shading."""
    n = reg.size
    flat = ids.ravel()
    lum = a @ np.array([0.299, 0.587, 0.114])
    mx, mn = a.max(2), a.min(2)
    sat = (mx - mn) / np.maximum(mx, 1e-4)
    warm = a[..., 0] - a[..., 2]
    cnt = np.maximum(np.bincount(flat, minlength=n), 1)
    m_l = np.bincount(flat, lum.ravel(), n) / cnt
    m_s = np.bincount(flat, sat.ravel(), n) / cnt
    m_w = np.bincount(flat, warm.ravel(), n) / cnt
    fur = smooth(0.22, 0.29, m_l) * (1 - smooth(0.17, 0.25, m_s))
    skin = smooth(0.07, 0.11, m_w) * smooth(0.26, 0.34, m_l)
    # leather kept its own (dyed lightly): the lighter brown straps, belts, bracers and boots; near-black leather
    # pieces on the coat and arms take the cloth's dye so the garment reads as one colour
    leather = smooth(0.13, 0.19, m_s) * smooth(0.035, 0.055, m_w) * smooth(0.11, 0.16, m_l) * (1 - fur) * (1 - skin)
    cloth = (1 - fur) * (1 - skin) * (1 - leather)
    face = reg == REGIONS.index("face") + 1
    # the face region round his head: only the hood's grey cloth there is dyed, never skin or beard
    hood_here = (1 - smooth(0.012, 0.03, m_w)) * (1 - smooth(0.1, 0.16, m_s))
    cloth[face] = (cloth * hood_here)[face]
    leather[face] = 0; fur[face] = 0
    hands = reg == REGIONS.index("hands") + 1
    cloth[hands] = 0; leather[hands] = 0
    reg = np.where(face, REGIONS.index("head") + 1, reg)
    cloth[0] = leather[0] = fur[0] = 0
    out = a.copy()
    # the cloth's own light and dark, lifted so the darkest folds still read as the colour
    ref = np.percentile(lum[(cloth[ids] > 0.5)], 60)
    rel = np.clip(lum / ref, 0.0, 2.2) ** 0.75
    rel = np.maximum(rel, 0.3)
    for name in ("head", "torso", "coat", "legs"):
        w = (cloth * (reg == REGIONS.index(name) + 1))[ids] * 0.93
        tgt = np.array(sc[name], np.float32)[None, None, :] * rel[..., None]
        out = out * (1 - w[..., None]) + tgt * w[..., None]
    lw = leather[ids] * 0.5
    lt = np.array(sc["leather"], np.float32)[None, None, :] * (lum / 0.22)[..., None]
    out = out * (1 - lw[..., None]) + lt * lw[..., None]
    fw = fur[ids]
    out = out * (1 - fw[..., None]) + np.clip(a * np.array(sc["fur"], np.float32) * 1.1, 0, 1) * fw[..., None]
    return np.clip(out, 0, 1)

def main():
    alb, regs, outd = sys.argv[1:4]
    names = sys.argv[4:] or list(SCHEMES)
    a = np.asarray(Image.open(alb).convert("RGB")).astype(np.float32) / 255
    ids, reg = poly_map(regs, a.shape[0])
    for n in names:
        o = recolour(a, ids, reg, SCHEMES[n])
        Image.fromarray((o * 255).astype(np.uint8)).save(f"{outd}/ranger_{n}.jpg", quality=92)
        print("wrote", n)

if __name__ == "__main__":
    main()
