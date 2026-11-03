# Packs a simulation's rendered frames (f_000.png ...) into a flipbook atlas, cropped to what the effect actually fills:
# a square centred on the frame's centre (so the simulation's origin stays at the middle of every cell, where the game
# puts the card's pivot), as big as the farthest pixel any frame reaches plus a margin. Lanczos-scaled cells, RGBA.
#   python3 tools/flipbook_pack.py <frames dir> <out.png> [--cols 6] [--cell 128] [--first 0] [--count all]
#                                  [--pad 0.04] [--thresh 0.03] [--level L] [--alpha-gamma G]
# --level brightens the colour so the smoke's average (weighted by its alpha) reaches L: a grey simulation keeps its
# shading but becomes a near-white base the game tints (smoke renders dark under Cycles' absorption).
# --alpha-gamma G < 1 fills out the smoke's thin edges (alpha ** G), so overlapping puffs merge into one body of fog
# instead of reading as separate dense cores. --vignette V fades every cell's alpha out from V of its half-width to
# its edge, so smoke that reaches the frame's border never shows a hard square edge on a sprite.
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
ap.add_argument("--alpha-gamma", type=float, default=1.0)
ap.add_argument("--vignette", type=float, default=0.0)
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
if a.alpha_gamma != 1.0:
	frames = [np.dstack([fr[..., :3], (np.power(fr[..., 3].astype(np.float32) / 255.0, a.alpha_gamma) * 255.0).astype(np.uint8)]) for fr in frames]
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
fade = None
if a.vignette > 0.0:
	yy, xx = np.mgrid[0:a.cell, 0:a.cell]
	rr = np.hypot(xx - (a.cell - 1) / 2.0, yy - (a.cell - 1) / 2.0) / (a.cell / 2.0)
	t = np.clip((1.0 - rr) / max(1.0 - a.vignette, 1e-3), 0.0, 1.0)
	fade = t * t * (3.0 - 2.0 * t)
for i, fr in enumerate(frames):
	im = Image.fromarray(fr).crop(box).resize((a.cell, a.cell), Image.LANCZOS)
	if fade is not None:
		arr = np.asarray(im).astype(np.float32)
		arr[..., 3] *= fade
		im = Image.fromarray(arr.astype(np.uint8), "RGBA")
	sheet.paste(im, ((i % a.cols) * a.cell, (i // a.cols) * a.cell))
os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
sheet.save(a.out, optimize=True)
# the crop as a share of the rendered frame: the game scales its card by this to keep the simulation's true size
print("PACK %s %d frames %dx%d cells %d crop %.3f of the frame" % (a.out, len(frames), a.cols, rows, a.cell, (2 * half) / float(w)))
