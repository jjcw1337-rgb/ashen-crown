#!/usr/bin/env python3
"""Builds the grass texture atlas (assets/textures/grass/atlas.png + atlas.json) from four Meshy botanical sheets.

Each sheet is a row of eight plants laid side by side on a cut-out background (meshy.py draw ... --cutout):
  green.png  fresh grass blades (roots at the bottom)      -> cells 0-7, unrolled
  dry.png    dry / dead straw blades                       -> cells 8-15, unrolled
  heads.png  seed heads and wildflowers on stems           -> cells 16-23, cut-outs
  leaves.png broad leaves (plantain, dock, clover ...)     -> cells 24-31, cut-outs (faded ones are dropped)

The atlas is 2048 x 1024: two rows of sixteen 128 x 512 cells. Blades are *unrolled*: each row of the blade
is stretched across the full cell width, so the texture fits any tapered blade shape the Blender clumps give
it (tools/blender/grass/build_clumps.py) and the blades stay opaque (no cut-out cost). Heads, flowers and
leaves keep their outline (alpha), bottom-aligned and centred in their cell; atlas.json records how much of
the cell each one fills so the clump builder can size its card to the plant. Colour is bled into the clear
pixels so mipmaps don't darken the edges.
  python3 tools/grass_atlas.py <dir with green.png dry.png heads.png leaves.png> [out_dir]
"""
import json, sys, os
import numpy as np
from PIL import Image, ImageFilter

SRC = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else "assets/textures/grass"
CW, CH, COLS = 128, 512, 16
atlas = np.zeros((CH * 2, CW * COLS, 4), np.float32)
meta = {"size": [CW * COLS, CH * 2], "cell": [CW, CH], "cols": COLS, "cells": []}

def items(img: np.ndarray):
    """Split a sheet into its plants: shapes of opaque pixels (a stalk keeps its head attached), small specks
    dropped, and shapes stacked in the same column (the two clover sprigs) merged into one plant."""
    from scipy import ndimage as nd
    a = img[..., 3] > 0.35
    lab, n = nd.label(nd.binary_dilation(a, iterations=1))
    boxes = []
    for i, sl in enumerate(nd.find_objects(lab)):
        if sl is None or nd.sum(a, lab, i + 1) < 1500:
            continue
        boxes.append([sl[1].start, sl[1].stop, sl[0].start, sl[0].stop, [i + 1]])
    boxes.sort(key=lambda b: b[0])
    merged = []
    for b in boxes:
        if merged:
            m = merged[-1]
            ov = min(m[1], b[1]) - max(m[0], b[0])
            if ov > 0.5 * min(m[1] - m[0], b[1] - b[0]):
                merged[-1] = [min(m[0], b[0]), max(m[1], b[1]), min(m[2], b[2]), max(m[3], b[3]), m[4] + b[4]]
                continue
        merged.append(b)
    global OWN
    OWN = [np.isin(lab, b[4]) for b in merged]
    return [tuple(b[:4]) for b in merged]

OWN: list = []

def vivid(img, box) -> float:
    """How solid and coloured a plant is (the faded ghost leaves score low)."""
    x0, x1, y0, y1 = box
    sub = img[y0:y1, x0:x1]
    m = sub[..., 3] > 0.35
    if m.sum() < 50:
        return 0.0
    rgb = sub[..., :3][m]
    sat = (rgb.max(1) - rgb.min(1)).mean()
    return float(sub[..., 3][m].mean() * sat)

def bleed(cell: np.ndarray) -> np.ndarray:
    """Spread the colour of opaque pixels into the clear ones (repeated dilation)."""
    rgb, a = cell[..., :3].copy(), cell[..., 3]
    known = a > 0.05
    for _ in range(48):
        if known.all():
            break
        acc = np.zeros_like(rgb); n = np.zeros(a.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            s = np.roll(np.roll(rgb, dy, 0), dx, 1); k = np.roll(np.roll(known, dy, 0), dx, 1)
            acc += s * k[..., None]; n += k
        new = (~known) & (n > 0)
        rgb[new] = acc[new] / n[new][:, None]
        known = known | new
    rgb[~known] = rgb[known].mean(0)
    return np.dstack([rgb, a])

def unroll(img, box, crop_bottom=0.0) -> np.ndarray:
    """A blade stretched row by row to the full cell width, root at the bottom, tip at the top."""
    x0, x1, y0, y1 = box
    y1c = int(y1 - (y1 - y0) * crop_bottom)
    rows = []
    last = None
    for y in range(y0, y1c):
        line = img[y, x0:x1]
        idx = np.where(line[:, 3] > 0.5)[0]
        if len(idx) < 2:
            if last is not None:
                rows.append(last)
            continue
        seg = line[idx.min():idx.max() + 1, :3]
        xs = np.linspace(0, len(seg) - 1, CW)
        r = np.stack([np.interp(xs, np.arange(len(seg)), seg[:, c]) for c in range(3)], 1)
        last = r
        rows.append(r)
    strip = np.array(rows, np.float32)  # (h, CW, 3)
    im = Image.fromarray((strip * 255).astype(np.uint8)).resize((CW, CH), Image.LANCZOS)
    rgb = np.asarray(im).astype(np.float32) / 255
    from scipy import ndimage as nd
    soft = nd.gaussian_filter(rgb, (6, 1.5, 0))
    k = np.clip(1.0 - np.arange(CH) / (CH * 0.45), 0, 1)[:, None, None]   # 1 at the tip (top) .. 0 lower down
    rgb = rgb * (1 - k) + soft * k
    return np.dstack([rgb, np.ones((CH, CW), np.float32)])

def cutout(img, box, own=None):
    """A plant kept whole: scaled to fit the cell, bottom-aligned and centred; returns (cell, wf, hf)."""
    x0, x1, y0, y1 = box
    sub = img[y0:y1, x0:x1].copy()
    if own is not None:
        sub[..., 3] *= own[y0:y1, x0:x1]
    h, w = sub.shape[:2]
    s = min(CH / h, CW / w) * 0.98
    nw, nh = max(1, int(w * s)), max(1, int(h * s))
    im = Image.fromarray((sub * 255).astype(np.uint8), "RGBA").resize((nw, nh), Image.LANCZOS)
    cell = np.zeros((CH, CW, 4), np.float32)
    ox = (CW - nw) // 2
    cell[CH - nh:, ox:ox + nw] = np.asarray(im).astype(np.float32) / 255
    return bleed(cell), nw / CW, nh / CH

def put(i: int, cell: np.ndarray) -> None:
    r, c = divmod(i, COLS)
    atlas[r * CH:(r + 1) * CH, c * CW:(c + 1) * CW] = cell

NAMES = {
    "heads": ["oat", "timothy", "fescue", "daisy", "buttercup", "heather", "yarrow", "dandelion"],
    "leaves": ["plantain", "dock", "dandelion_leaf", "clover", "nettle", "moss", "sorrel", "weed"],
}
for g, base, kind in (("green", 0, "blade"), ("dry", 8, "blade"), ("heads", 16, "card"), ("leaves", 24, "card")):
    img = np.asarray(Image.open(os.path.join(SRC, g + ".png")).convert("RGBA")).astype(np.float32) / 255
    found = items(img)
    print(f"{g}: {len(found)} plants")
    k = 0
    for j, box in enumerate(found[:8]):
        # a plant must be clearly drawn: cut-outs that came out faded or ghostly are dropped
        x0, x1, y0, y1 = box
        al = img[y0:y1, x0:x1, 3]
        solid = float(al[al > 0.05].mean())
        if kind == "card" and (x1 - x0 < 40 or solid < 0.6):
            # Meshy sometimes draws a plant faded almost to nothing: only its stem survives the cut-out
            print(f"  skip {g}[{j}] (faded: {x1 - x0} px wide, opacity {solid:.2f})")
            continue
        i = base + k
        name = NAMES.get(g, [])[j] if j < len(NAMES.get(g, [])) else f"{g}{j}"
        if kind == "blade":
            # the green blades were drawn with their roots: those stay below ground, so crop them off
            put(i, unroll(img, box, 0.15 if g == "green" else 0.06))
            meta["cells"].append({"i": i, "group": g, "kind": "blade", "name": f"{g}{j}", "wf": 1.0, "hf": 1.0})
        else:
            cell, wf, hf = cutout(img, box, OWN[j])
            put(i, cell)
            meta["cells"].append({"i": i, "group": g, "kind": "card", "name": name, "wf": round(wf, 3), "hf": round(hf, 3)})
        k += 1
os.makedirs(OUT, exist_ok=True)
Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "atlas.png"), optimize=True)
json.dump(meta, open(os.path.join(OUT, "atlas.json"), "w"), indent=1)
print("cells:", [(c["i"], c["name"]) for c in meta["cells"]])
