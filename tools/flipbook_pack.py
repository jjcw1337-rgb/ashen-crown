# Packs a simulation's rendered frames (f_000.png ...) into a flipbook atlas, cropped to what the effect actually fills:
# a square centred on the frame's centre (so the simulation's origin stays at the middle of every cell, where the game
# puts the card's pivot), as big as the farthest pixel any frame reaches plus a margin. Lanczos-scaled cells, RGBA.
#   python3 tools/flipbook_pack.py <frames dir> <out.png> [--cols 6] [--cell 128] [--first 0] [--count all]
#                                  [--pad 0.04] [--thresh 0.03] [--level L]
# --level brightens the colour so the smoke's average (weighted by its alpha) reaches L: a grey simulation keeps its
# shading but becomes a near-white base the game tints (smoke renders dark under Cycles' absorption).
import sys, os, glob, argparse
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("out")
ap.add_argument("--cols", type=int, default=6)
ap.add_argument("--cell", type=int, default=128)
ap.add_argument("--first", type=int, default=0)
ap.add_argument("--count", type=int, default=0)
ap.add_argument("--pad", type=float, default=0.04)
ap.add_argument("--thresh", type=float, default=0.03)
ap.add_argument("--level", type=float, default=0.0)
a = ap.parse_args()
files = sorted(glob.glob(os.path.join(a.src, "f_*.png")))[a.first:]
if a.count > 0:
	files = files[:a.count]
if not files:
	sys.exit("no frames in " + a.src)
frames = [np.asarray(Image.open(f).convert("RGBA")) for f in files]
if a.level > 0.0:
	wsum = sum(float(fr[..., 3].sum()) for fr in frames) / 255.0
	lsum = sum(float((fr[..., :3].astype(np.float32).mean(axis=2) * fr[..., 3]).sum()) for fr in frames) / (255.0 * 255.0)
	gain = a.level / max(lsum / max(wsum, 1e-6), 1e-3)
	frames = [np.dstack([np.clip(fr[..., :3].astype(np.float32) * gain, 0, 255).astype(np.uint8), fr[..., 3]]) for fr in frames]
	print("gain %.2f" % gain)
h, w = frames[0].shape[:2]
cy, cx = (h - 1) / 2.0, (w - 1) / 2.0
reach = 1.0
for fr in frames:
	ys, xs = np.nonzero(fr[..., 3] > a.thresh * 255)
	if len(xs):
		reach = max(reach, np.abs(xs - cx).max(), np.abs(ys - cy).max())
half = min(int(np.ceil(reach * (1.0 + a.pad))) + 1, int(min(cx, cy)) + 1)
box = (int(round(cx - half)), int(round(cy - half)), int(round(cx + half)), int(round(cy + half)))
rows = (len(frames) + a.cols - 1) // a.cols
sheet = Image.new("RGBA", (a.cols * a.cell, rows * a.cell), (0, 0, 0, 0))
for i, fr in enumerate(frames):
	im = Image.fromarray(fr).crop(box).resize((a.cell, a.cell), Image.LANCZOS)
	sheet.paste(im, ((i % a.cols) * a.cell, (i // a.cols) * a.cell))
os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
sheet.save(a.out, optimize=True)
# the crop as a share of the rendered frame: the game scales its card by this to keep the simulation's true size
print("PACK %s %d frames %dx%d cells %d crop %.3f of the frame" % (a.out, len(frames), a.cols, rows, a.cell, (2 * half) / float(w)))
