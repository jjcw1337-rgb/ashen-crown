# Prepares Meshy-painted cut-outs (grass clumps, flowers) for the game's camera-facing cards:
# crops to the plant, pads it to a square with its base on the bottom edge, scales to 512 px and
# pushes the plant's colour out into the clear pixels (alpha kept as is), so the mipmaps don't mix in
# the black behind the blades and far clumps don't go dark and blobby.
#   python3 tools/grass_prep.py meshy.png assets/textures/grass/topN.png
#   python3 tools/grass_prep.py --bleed assets/textures/grass/gN.png ...     # only the colour bleed, in place
# Needs numpy, scipy and Pillow. Turn on mipmaps in the new file's .import (mipmaps/generate=true).
import sys
import numpy as np
from PIL import Image
from scipy import ndimage


def bleed(im):
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3]
    solid = al >= 128
    # each pixel that isn't solid takes the colour of the nearest solid one
    idx = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    out = np.where(solid[..., None], rgb, rgb[idx[0], idx[1]])
    return Image.fromarray(np.dstack([out, al]).clip(0, 255).astype(np.uint8), "RGBA")


def prep(src, dst, size=512):
    im = Image.open(src).convert("RGBA")
    ys, xs = np.where(np.asarray(im)[..., 3] > 20)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    w, h = x1 - x0, y1 - y0
    s = max(w, h) + 8
    sq = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sq.paste(im.crop((x0, y0, x1, y1)), ((s - w) // 2, s - h - 2))
    bleed(sq.resize((size, size), Image.LANCZOS)).save(dst)
    print(dst, f"plant {w}x{h} px")


if __name__ == "__main__":
    if sys.argv[1] == "--bleed":
        for p in sys.argv[2:]:
            bleed(Image.open(p)).save(p)
            print("bled", p)
    else:
        prep(sys.argv[1], sys.argv[2])
