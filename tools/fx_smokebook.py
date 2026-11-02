"""Packs a simulated smoke flipbook (tools/blender/fx/smoke_flipbook.py: premultiplied EXR frames and book.json) into
one atlas for the game's smoke cards (DemonKitFx.smoke, SMOKE_SHADER: premultiplied alpha blending).

    python3 tools/fx_smokebook.py <frames dir> <out.png> <cell width px> [columns]

Each frame stays premultiplied: smoke is colour x alpha, and fire is light added on top (colour above alpha, even with
no smoke at all), which a straight-alpha PNG can't hold. The light is rolled off above 0.6 instead of clipped, the
frame is faded to nothing at its edges (no card ever shows a straight edge), scaled to the cell, sRGB-encoded (the
shader reads it as source_color) and laid out left to right, top to bottom. A loop's frames rendered past its end
(book.json "overlap") are cross-faded into its first ones, so the last frame runs on into the first without a jump.
Every pixel with light keeps at least 1/255 of alpha (WebP may rewrite the colour under fully clear pixels).
A book that lies along a flight (mode 2, the comet) is shaped into a tail: narrow at its head (the anchor), widening
behind it and fading out toward its end, so the smoke never fills the card.
Prints the DemonKitFx.BOOKS entry. Import the atlas lossless (compress/mode=0: lossy WebP rewrites the colour under
clear pixels, which premultiplied blending adds as pale boxes), with fix_alpha_border off (it would overwrite the light
under clear pixels) and mipmaps on.
"""
import json
import math
import os
import subprocess
import sys

import cv2
import numpy as np
from PIL import Image

KNEE = 0.6
EDGE = float(os.environ.get("SMOKEBOOK_EDGE", "0.06"))   # how far in from each side a frame fades out


def read_exr(path):
	"""RGBA float32 (linear, premultiplied as Blender wrote it), decoded by ffmpeg (OpenCV here has no EXR)."""
	wh = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
		"-of", "csv=p=0", path], capture_output=True, text=True, check=True).stdout.strip().split(",")
	w, h = int(wh[0]), int(wh[1])
	raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "rawvideo", "-pix_fmt", "gbrapf32le", "-"],
		capture_output=True, check=True).stdout
	g, b, r, a = np.frombuffer(raw, np.float32).reshape(4, h, w)
	return np.dstack([r, g, b, a]).astype(np.float32)


def roll_off(x):
	"""Linear below the knee, then easing toward 1: bright fire keeps its hue instead of clipping flat."""
	y = np.where(x <= KNEE, x, KNEE + (1.0 - KNEE) * (1.0 - np.exp(-(x - KNEE) / (1.0 - KNEE))))
	return np.clip(y, 0.0, 1.0)


def to_srgb(x):
	return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(np.maximum(x, 0.0031308), 1.0 / 2.4) - 0.055)


def edge_mask(h, w):
	def ramp(n):
		t = (np.arange(n, dtype=np.float32) + 0.5) / n
		e = np.minimum(t, 1.0 - t) / EDGE
		e = np.clip(e, 0.0, 1.0)
		return e * e * (3.0 - 2.0 * e)
	return np.outer(ramp(h), ramp(w))


def tail_mask(h, w, head_u, head_v):
	"""A comet's tail: nothing ahead of the head, a cone opening behind it, fading out toward the far end."""
	u = (np.arange(w, dtype=np.float32) + 0.5) / w
	v = 1.0 - (np.arange(h, dtype=np.float32) + 0.5) / h          # (rows run top down; v from the bottom)
	uu, vv = np.meshgrid(u, v)
	behind = np.clip((head_u - uu) / max(head_u, 1e-3), 0.0, 1.0)  # 0 at the head .. 1 at the far end
	half = 0.15 + 0.33 * behind
	d = np.abs(vv - head_v)
	k = 1.0 - np.clip((d - half * 0.25) / (half * 0.75), 0.0, 1.0)     # feathered: no straight edge shows
	k = k * k * (3.0 - 2.0 * k)
	ahead = np.clip(1.0 - (uu - head_u) / 0.1, 0.0, 1.0)
	tail = np.clip(uu / 0.55, 0.0, 1.0)
	tail = tail * tail * (3.0 - 2.0 * tail)
	return (k * ahead * tail).astype(np.float32)


def main():
	if len(sys.argv) < 4:
		raise SystemExit(__doc__)
	src, out, cell_w = sys.argv[1], sys.argv[2], int(sys.argv[3])
	meta = json.load(open(os.path.join(src, "book.json")))
	files = sorted(f for f in os.listdir(src) if f.startswith("smk_") and f.endswith(".exr"))
	ov = int(meta.get("overlap", 0))
	n = int(meta["frames"])
	if len(files) < n + ov:
		raise SystemExit("%s: %d frames, the book wants %d" % (src, len(files), n + ov))
	cols = int(sys.argv[4]) if len(sys.argv) > 4 else (8 if n >= 40 else 6)
	rows = int(math.ceil(n / cols))
	cell_h = int(round(cell_w / meta["aspect"]))
	atlas = np.zeros((rows * cell_h, cols * cell_w, 4), np.float32)
	mask = None
	peak = 0.0
	for i in range(n):
		im = read_exr(os.path.join(src, files[i]))
		if i < ov:
			# the loop's seam: the frames past the end fade into the first ones (premultiplied, so a straight mix)
			w = (i + 1.0) / (ov + 1.0)
			im = im * w + read_exr(os.path.join(src, files[n + i])) * (1.0 - w)
		rgb = np.clip(im[:, :, :3], 0.0, None)
		a = np.clip(im[:, :, 3], 0.0, 1.0)
		peak = max(peak, float(rgb.max()))
		rgb = roll_off(rgb)
		if mask is None:
			mask = edge_mask(*a.shape)
			if int(meta.get("mode", 0)) == 2:
				mask = mask * tail_mask(a.shape[0], a.shape[1], float(meta.get("anchor_u", 0.5)), float(meta["anchor"]))
		rgb *= mask[:, :, None]
		a *= mask
		# scale in linear, premultiplied (the right space to filter in), then encode
		frame = np.dstack([rgb, a])
		frame = cv2.resize(frame, (cell_w, cell_h), interpolation=cv2.INTER_AREA)
		frame = np.clip(frame, 0.0, 1.0)
		lit = frame[:, :, :3].max(axis=2) > 0.5 / 255.0
		frame[:, :, 3] = np.where(lit, np.maximum(frame[:, :, 3], 1.0 / 255.0), frame[:, :, 3])
		frame[:, :, :3] = to_srgb(frame[:, :, :3])
		r, c = divmod(i, cols)
		atlas[r * cell_h:(r + 1) * cell_h, c * cell_w:(c + 1) * cell_w] = frame
	img = Image.fromarray(np.round(atlas * 255.0).astype(np.uint8), "RGBA")
	os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
	img.save(out, optimize=True)
	print("[smokebook] %s: %d frames, %dx%d cells of %dx%d, atlas %dx%d, brightest %.2f" % (
		os.path.basename(out), n, cols, rows, cell_w, cell_h, img.size[0], img.size[1], peak))
	print('\t"%s": ["%s", Vector2(%d, %d), %d, %.3f, Vector2(%.3f, %.3f), %.3f, %d],' % (
		meta["kind"], os.path.basename(out), cols, rows, n, meta["aspect"], meta.get("anchor_u", 0.5), meta["anchor"],
		meta["span"], meta["mode"]))


if __name__ == "__main__":
	main()
