#!/usr/bin/env python3
"""Packs the Blender lightning (tools/blender/fx/lightning_bolts.py: bolt_NN.png, white light on black, each running
from the left edge's middle to the right edge's middle) into one 4x4 atlas for ArcFx's BOLT_SHADER:

    python3 tools/fx_bolt_atlas.py <frames dir> assets/textures/fx/storm/bolts.png [cell width 512]

Each frame is kept as its light (greyscale), faded to nothing toward its top and bottom edges so a fork that reached
the frame's edge never ends in a straight cut; the bolt's two ends stay at full strength (they meet the points).
"""
import sys, glob, os
import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
cw = int(sys.argv[3]) if len(sys.argv) > 3 else 512
ch = cw // 4
fs = sorted(glob.glob(os.path.join(src, "bolt_*.png")))[:16]
atlas = np.zeros((ch * 4, cw * 4), np.float32)
t = np.linspace(0, 1, ch)
fade = np.clip(np.minimum(t, 1 - t) / 0.1, 0, 1)
fade = (fade * fade * (3 - 2 * fade))[:, None]
for i, f in enumerate(fs):
    im = Image.open(f).convert("L").resize((cw, ch), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0 * fade
    x, y = (i % 4) * cw, (i // 4) * ch
    atlas[y:y + ch, x:x + cw] = a
os.makedirs(os.path.dirname(dst), exist_ok=True)
Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "L").convert("RGB").save(dst)
print("bolts:", len(fs), "frames ->", dst, atlas.shape[::-1])
