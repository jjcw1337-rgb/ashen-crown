"""Turns a Meshy-painted top-down ground painting into a Decal pair for the game: the albedo with its edge faded to
transparent, and a glow mask of its hot part (the molten reds and oranges) for the Decal's emission.

    python3 tools/fx_glow_mask.py <painting.png> <out dir> <name> [radial|strip|keep] [px]

radial: a round mark (fades out toward a ragged circle); strip: a long mark (fades at the long edges and both ends,
any black letterbox bars cropped first); keep: the painting's own alpha (a cut-out). Writes <name>.png and
<name>_glow.png.
"""
import sys
import os
import math
import random
from PIL import Image, ImageFilter, ImageChops

src, outdir, name = sys.argv[1], sys.argv[2], sys.argv[3]
mode = sys.argv[4] if len(sys.argv) > 4 else "radial"
px = int(sys.argv[5]) if len(sys.argv) > 5 else 1024
im = Image.open(src).convert("RGBA")
if mode == "strip":
	# crop black letterbox bars (rows that are nearly black)
	g = im.convert("L")
	w, h = g.size
	rows = [sum(g.getpixel((x, y)) for x in range(0, w, 8)) / (w / 8) for y in range(h)]
	top = next(y for y in range(h) if rows[y] > 18)
	bot = next(y for y in range(h - 1, -1, -1) if rows[y] > 18)
	im = im.crop((0, top + 4, w, bot - 4))
	im = im.resize((px, px // 4), Image.LANCZOS)
else:
	im = im.resize((px, px), Image.LANCZOS)
w, h = im.size
rnd = random.Random(7)
if mode in ("radial", "strip"):
	mask = Image.new("L", (w, h), 0)
	mp = mask.load()
	# a ragged edge: the fade radius wobbles with angle (radial) or along the strip (strip)
	wob = [rnd.uniform(-0.06, 0.06) for _ in range(24)]
	def wobble(t):
		i = t * 24.0
		a, b = wob[int(i) % 24], wob[(int(i) + 1) % 24]
		f = i - int(i)
		return a + (b - a) * (f * f * (3 - 2 * f))
	for y in range(h):
		for x in range(w):
			if mode == "radial":
				dx, dy = (x + 0.5) / w * 2 - 1, (y + 0.5) / h * 2 - 1
				r = math.hypot(dx, dy)
				t = (math.atan2(dy, dx) / math.tau) % 1.0
				edge = 0.92 + wobble(t)
				a = 1.0 - min(1.0, max(0.0, (r - edge * 0.62) / (edge * 0.38)))
			else:
				u, v = (x + 0.5) / w, (y + 0.5) / h * 2 - 1
				edge = 0.86 + wobble(u)
				a = 1.0 - min(1.0, max(0.0, (abs(v) - edge * 0.55) / (edge * 0.45)))
				a *= min(1.0, u / 0.12, (1.0 - u) / 0.12)
			a = a * a * (3 - 2 * a)
			mp[x, y] = int(255 * a)
	mask = mask.filter(ImageFilter.GaussianBlur(2))
	im.putalpha(ImageChops.multiply(im.getchannel("A"), mask))
# the glow: where the painting is hot (red/orange, bright, saturated)
glow = Image.new("RGB", (w, h))
gp = glow.load()
ip = im.load()
for y in range(h):
	for x in range(w):
		r, g, b, a = ip[x, y]
		heat = max(0.0, (r - max(g, b) * 0.9) / 255.0) * min(1.0, r / 200.0)
		heat = min(1.0, heat * 2.2) * (a / 255.0)
		gp[x, y] = (int(255 * heat), int(255 * heat * 0.45), int(255 * heat * 0.08))
glow = glow.filter(ImageFilter.GaussianBlur(1.2))
os.makedirs(outdir, exist_ok=True)
im.save(os.path.join(outdir, name + ".png"))
glow.save(os.path.join(outdir, name + "_glow.png"))
print("wrote", name, im.size)
