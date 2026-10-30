# Cuts a Meshy-painted item (drawn on a plain light background) out into an inventory icon:
# the background colour is read from the border, every pixel's alpha comes from how far its colour is
# from it (soft, so glows and mist stay half see-through), the background's tint is taken back out of
# the soft edges, and the item is cropped, centred on a square and scaled.
#   ~/Documents/Game\ Factory\ Audio/venv/bin/python tools/icon_cutout.py in.png out.png [size]
# Needs numpy, scipy and Pillow (the audio venv has them). Turn on mipmaps in the .import.
import sys
import numpy as np
from PIL import Image
from scipy import ndimage


def cutout(src, dst, size=256):
    a = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
    h, w, _ = a.shape
    border = np.concatenate([a[:8].reshape(-1, 3), a[-8:].reshape(-1, 3), a[:, :8].reshape(-1, 3), a[:, -8:].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    # the background may shade a little across the picture: compare with a blurred estimate near the edges
    diff = np.sqrt(((a - bg) ** 2).sum(axis=2))
    alpha = np.clip((diff - 0.045) / 0.16, 0.0, 1.0)
    # anything not connected to the item through solid pixels is background speckle
    solid = alpha > 0.5
    lab, n = ndimage.label(solid)
    if n > 1:
        sizes = ndimage.sum(solid, lab, range(1, n + 1))
        keep = np.isin(lab, 1 + np.where(sizes > sizes.max() * 0.02)[0])
        near = ndimage.binary_dilation(keep, iterations=18)
        alpha = np.where(near, alpha, 0.0)
    # take the background back out of the soft pixels: c = a*fg + (1-a)*bg
    al = alpha[..., None]
    fg = np.where(al > 0.02, (a - (1.0 - al) * bg) / np.maximum(al, 0.02), a)
    fg = np.clip(fg, 0.0, 1.0)
    rgba = np.dstack([fg, alpha])
    ys, xs = np.where(alpha > 0.1)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    s = int(max(x1 - x0, y1 - y0) * 1.06)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    sq = np.zeros((s, s, 4), np.float32)
    sx0, sy0 = cx - s // 2, cy - s // 2
    for yy in range(s):
        sy = sy0 + yy
        if 0 <= sy < h:
            lo, hi = max(0, sx0), min(w, sx0 + s)
            sq[yy, lo - sx0:hi - sx0] = rgba[sy, lo:hi]
    im = Image.fromarray((sq * 255).astype(np.uint8), "RGBA").resize((size, size), Image.LANCZOS)
    im.save(dst)
    print("saved", dst, im.size, "background", np.round(bg, 3))


if __name__ == "__main__":
    cutout(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 256)
