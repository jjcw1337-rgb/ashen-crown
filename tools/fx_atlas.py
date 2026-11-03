#!/usr/bin/env python3
"""Packs Meshy-painted VFX sheets (one row of sprites each, meshy.py draw) into particle atlases for the
Archer's arrow effects (assets/textures/fx/phoenix_*.png; scripts/arrow_fx.gd reads them as h-frame strips):
  feathers.png  glowing fire feathers on black  -> phoenix_feathers.png  8 frames of 128x512 (additive)
  flames.png    tongues of flame on black       -> phoenix_flames.png    8 frames of 128x512 (additive)
  smoke.png     dark smoke puffs, cut out       -> phoenix_smoke.png     4 frames of 256x256 (alpha)
  scorch.png    a burn streak, cut out          -> phoenix_scorch.png    1024x256 (alpha, glow in RGB)
Sprites are found by the columns that hold them, centred and bottom-aligned in their frame, the colour bled
into clear pixels (mipmaps don't darken the edges) and, for the black-background sheets, an alpha made from
the brightness so the same strip works alpha-blended too.
  python3 tools/fx_atlas.py concepts/archer_fire/sheets assets/textures/fx
"""
import sys, os
import numpy as np
from PIL import Image

SRC = sys.argv[1]
OUT = sys.argv[2] if len(sys.argv) > 2 else "assets/textures/fx"
os.makedirs(OUT, exist_ok=True)


def load(name):
    im = Image.open(os.path.join(SRC, name)).convert("RGBA")
    return np.asarray(im).astype(np.float32) / 255.0


def alpha_from_black(a):
    """A sprite painted on black: its brightness is its alpha (soft edges stay soft)."""
    lum = a[..., :3].max(axis=2)
    al = np.clip((lum - 0.03) / 0.5, 0.0, 1.0)
    out = a.copy()
    out[..., 3] = al
    # un-premultiply a little: faint pixels keep their hue instead of greying out
    k = np.where(al > 0.02, 1.0 / np.maximum(al, 0.25), 1.0)[..., None]
    out[..., :3] = np.clip(a[..., :3] * k, 0.0, 1.0)
    return out


def split_columns(a, thresh=0.08, min_w=24, min_gap=6):
    """Column spans that hold a sprite (alpha above thresh somewhere in the column)."""
    col = (a[..., 3] > thresh).sum(axis=0)
    on = col > 2
    spans, start, gap = [], None, 0
    for x, v in enumerate(on):
        if v:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                spans.append((start, x - gap))
                start, gap = None, 0
    if start is not None:
        spans.append((start, len(on)))
    return [s for s in spans if s[1] - s[0] >= min_w]


def crop_rows(a, thresh=0.08):
    rows = np.where((a[..., 3] > thresh).any(axis=1))[0]
    return (rows[0], rows[-1] + 1) if len(rows) else (0, a.shape[0])


def bleed(cell, iters=12):
    """Spread the colour of covered pixels into the clear ones around them."""
    rgb, al = cell[..., :3].copy(), cell[..., 3]
    cov = al > 0.02
    for _ in range(iters):
        if cov.all():
            break
        pad = np.pad(rgb, ((1, 1), (1, 1), (0, 0)), mode="edge")
        pc = np.pad(cov, 1, mode="edge")
        acc = np.zeros_like(rgb)
        cnt = np.zeros(rgb.shape[:2], np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                s = pad[1 + dy:1 + dy + rgb.shape[0], 1 + dx:1 + dx + rgb.shape[1]]
                c = pc[1 + dy:1 + dy + rgb.shape[0], 1 + dx:1 + dx + rgb.shape[1]]
                acc += s * c[..., None]
                cnt += c
        newc = (~cov) & (cnt > 0)
        rgb[newc] = (acc[newc] / cnt[newc][..., None])
        cov = cov | newc
    out = cell.copy()
    out[..., :3] = rgb
    return out


def place(frames, cw, ch, fit="bottom"):
    atlas = np.zeros((ch, cw * len(frames), 4), np.float32)
    for i, f in enumerate(frames):
        h, w = f.shape[:2]
        s = min((cw - 4) / w, (ch - 4) / h)
        img = Image.fromarray((np.clip(f, 0, 1) * 255).astype(np.uint8), "RGBA")
        nw, nh = max(1, int(w * s)), max(1, int(h * s))
        if fit == "stretch":
            nw, nh = cw - 4, ch - 4
        img = img.resize((nw, nh), Image.LANCZOS)
        g = np.asarray(img).astype(np.float32) / 255.0
        x0 = i * cw + (cw - nw) // 2
        y0 = ch - nh - 2 if fit == "bottom" else (ch - nh) // 2
        atlas[y0:y0 + nh, x0:x0 + nw] = g
    return atlas


def save(atlas, name):
    img = Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA")
    p = os.path.join(OUT, name)
    img.save(p)
    print("wrote", p, img.size)


def sprites(a, want, by="area"):
    cells = []
    for x0, x1 in split_columns(a):
        sub = a[:, x0:x1]
        y0, y1 = crop_rows(sub)
        cells.append(bleed(sub[y0:y1]))
    if len(cells) > want:
        # keep the most solid ones (the faded ghosts go)
        cells.sort(key=lambda c: -(c[..., 3] > 0.3).sum())
        cells = cells[:want]
    while len(cells) < want:
        cells.append(cells[len(cells) % max(1, len(cells))])
    return cells


feath = alpha_from_black(load("feathers.png"))
save(place(sprites(feath, 8), 128, 512), "phoenix_feathers.png")
flames = alpha_from_black(load("flames.png"))
save(place(sprites(flames, 8), 128, 512), "phoenix_flames.png")
smoke = load("smoke.png")
sm = sprites(smoke, 6)
# the puffs: the four fullest (the thin first and the grey last are dropped)
sm.sort(key=lambda c: -(c[..., 3] > 0.3).sum())
save(place(sm[:4], 256, 256, fit="centre"), "phoenix_smoke.png")
sc = load("scorch.png")
x0, x1 = split_columns(sc, min_w=200)[0]
y0, y1 = crop_rows(sc[:, x0:x1])
streak = bleed(sc[y0:y1, x0:x1])
save(place([streak], 1024, 256, fit="stretch"), "phoenix_scorch.png")
