#!/usr/bin/env python3
"""Packs the Mantaflow renders of tools/blender/fx/fire_sims.py into flipbook atlases for ArrowFx, and makes the
procedural scorch decal (no painting anywhere):

    python3 tools/fx_flipbook.py <frames dir> assets/textures/fx

  real_flame.png        8x8 cells, 64 frames of licking flame, looped (the last 16 frames crossfaded into the
                        first 16). R = flame, G = flame x temperature (G/R = the mean temperature along the ray).
  real_burst_fire.png   8x8, the fireball's fire (R, G as above; smoke in front already absorbs it).
  real_burst_smoke.png  8x8, the fireball's smoke: RGB = light from the right / above / the left, A = opacity.
  real_smoke.png        8x8, a puff of smoke rising and rolling open: RGB lightmap, A = opacity.
  real_scorch.png       a burn mark: RGB soot albedo, A = coverage; real_scorch_n.png its normal map;
                        real_scorch_e.png the ember cracks' glow (a blackbody colour, ~1000 K outside to 1600 K
                        in the middle).
Every cell's border is faded to nothing so a domain wall never shows as a square edge.
"""
import sys, os, glob
import numpy as np
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fire_sims"
DST = sys.argv[2] if len(sys.argv) > 2 else "assets/textures/fx"
CELL = int(sys.argv[3]) if len(sys.argv) > 3 else 256
os.makedirs(DST, exist_ok=True)


def load(pattern):
    files = sorted(glob.glob(os.path.join(SRC, pattern)))
    return [np.asarray(Image.open(f).convert("RGBA")).astype(np.float32) / 255.0 for f in files]


def window(n, edge=0.06):
    t = np.linspace(0.0, 1.0, n)
    w = np.clip(np.minimum(t, 1.0 - t) / edge, 0.0, 1.0)
    w = w * w * (3 - 2 * w)
    return np.outer(w, w)[..., None]


def resize(a, n):
    if a.shape[0] == n:
        return a
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA")
    return np.asarray(im.resize((n, n), Image.LANCZOS)).astype(np.float32) / 255.0


def crop_box(frames, src_v, pad=0.04):
    """The square-ish window (over every frame) the sim's light or smoke ever reaches, so no cell is wasted on
    empty domain; prints where the source ends up (the shader's pivot: up from the card's middle)."""
    acc = np.zeros(frames[0].shape[:2], np.float32)
    for f in frames:
        acc = np.maximum(acc, np.max(f[..., :3], -1) * (f[..., 3] if f[..., 3].min() < 1.0 else 1.0))
    ys, xs = np.nonzero(acc > 0.03)
    n = acc.shape[0]
    y0 = max(0, ys.min() / n - pad)
    y1 = min(1.0, max(ys.max() / n + pad, src_v + pad))
    cx = (xs.min() + xs.max()) / 2.0 / n
    w = max(xs.max() - xs.min(), 1) / n + pad * 2
    side = max(w, y1 - y0)
    x0 = min(max(0.0, cx - side / 2), 1.0 - side)
    y0 = max(0.0, y1 - side)
    piv = 0.5 - (src_v - y0) / side
    print("  crop x %.3f..%.3f y %.3f..%.3f: pivot %.3f" % (x0, x0 + side, y0, y0 + side, -piv))
    return (x0, y0, side)


def crop(f, box):
    x0, y0, side = box
    n = f.shape[0]
    a, b = int(round(y0 * n)), int(round((y0 + side) * n))
    c, d = int(round(x0 * n)), int(round((x0 + side) * n))
    return f[a:b, c:d]


def blur(a, sigma):
    """A separable Gaussian blur (numpy only) over the first two axes."""
    r = int(sigma * 3) + 1
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = a
    for ax in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[ax] = (r, r)
        b = np.pad(out, pad, mode="edge")
        acc = np.zeros_like(out)
        for i, w in enumerate(k):
            sl = [slice(None)] * a.ndim
            sl[ax] = slice(i, i + out.shape[ax])
            acc += w * b[tuple(sl)]
        out = acc
    return out


def denoise(f, fire):
    """Cycles leaves grain in thin smoke and stray specks of flame: smooth it (premultiplied, so the thin edges
    don't amplify the noise) and drop the specks."""
    f = f.copy()
    if fire:
        f[..., :2] = blur(f[..., :2], 1.0)
        f[..., :2] *= np.clip((f[..., 0:1] - 0.03) / 0.05, 0.0, 1.0)
        return f
    a = blur(f[..., 3:4], 1.4)
    rgb = blur(f[..., :3] * f[..., 3:4], 1.4)
    f[..., :3] = np.where(a > 0.004, rgb / np.maximum(a, 0.004), 0.0)
    f[..., 3:4] = a
    return f


def pack(frames, name, grid=8, fire=False, src_v=None):
    n = grid * grid
    frames = frames[:n]
    if src_v is not None:
        box = crop_box(frames, src_v)
        frames = [crop(f, box) for f in frames]
    atlas = np.zeros((grid * CELL, grid * CELL, 4), np.float32)
    win = window(CELL)
    for i, f in enumerate(frames):
        f = denoise(resize(f, CELL), fire)
        if fire:
            f = f.copy()
            f[..., 2] = 0.0
            f[..., 3] = 1.0
            f[..., :2] *= win[..., 0:1]
        else:
            f = f.copy()
            f[..., 3:] *= win
        r, c = divmod(i, grid)
        atlas[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL] = f
    Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(DST, name), optimize=True)
    print("wrote", name, len(frames), "frames")


def loop(frames, n=64, m=16):
    """out[i] = f[i] for i >= m, else a crossfade from f[n + i] into f[i]: out[n-1] -> out[0] runs on."""
    out = []
    for i in range(n):
        if i < m:
            w = i / float(m)
            out.append(frames[n + i] * (1.0 - w) + frames[i] * w)
        else:
            out.append(frames[i])
    return out


def fbm(shape, seed, octaves=6, base=4):
    rng = np.random.default_rng(seed)
    h, w = shape
    acc = np.zeros(shape, np.float32)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        s = base * (2 ** o)
        g = rng.random((s + 1, s + 1)).astype(np.float32)
        g[-1, :] = g[0, :]
        g[:, -1] = g[:, 0]
        im = Image.fromarray(g).resize((w, h), Image.BICUBIC)
        acc += np.asarray(im) * amp
        tot += amp
        amp *= 0.55
    return acc / tot


def scorch(n=512):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32) / (n - 1) * 2.0 - 1.0
    ang = np.arctan2(y, x)
    r = np.sqrt(x * x + y * y)
    warp = fbm((n, n), 3, 5, 3)
    rough = fbm((n, n), 5, 6, 6)
    fine = fbm((n, n), 9, 4, 32)
    # a ragged burn: radius modulated by angle noise, a few uneven splash tongues thrown out of it
    rng = np.random.default_rng(17)
    k = 48
    lobes = rng.random(k) ** 5
    lobes = np.convolve(np.concatenate([lobes, lobes[:3]]), [0.25, 0.5, 0.25], "same")[:k]
    u = (ang / (2 * np.pi) + 0.5) * k + (warp - 0.5) * 3.0
    i0 = np.floor(u).astype(int) % k
    fr = u - np.floor(u)
    streak = lobes[i0] * (1 - fr) + lobes[(i0 + 1) % k] * fr
    edge = 0.58 + (warp - 0.5) * 0.5 + streak * 0.3
    cover = np.clip((edge - r) / 0.22, 0.0, 1.0)
    cover = cover * cover * (3 - 2 * cover)
    cover *= np.clip(0.55 + rough * 0.9 - (r / edge) * 0.35, 0.0, 1.0)
    cover = np.clip(cover * (0.75 + fine * 0.5), 0.0, 1.0)
    # soot: black in the middle, brown-grey ash toward the rim, a few pale ash flecks
    rim = np.clip(1.0 - np.abs(r / np.maximum(edge, 1e-3) - 0.8) / 0.25, 0.0, 1.0) * cover
    soot = np.stack([0.02 + 0.07 * rim + 0.03 * fine, 0.018 + 0.055 * rim + 0.025 * fine, 0.016 + 0.045 * rim + 0.02 * fine], -1)
    flecks = (fine > 0.72) * (rough > 0.5) * cover * 0.35
    soot += flecks[..., None] * np.array([0.5, 0.48, 0.45])
    alb = np.concatenate([soot, cover[..., None]], -1)
    Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(DST, "real_scorch.png"), optimize=True)
    # normal: blistered, cracked char (height = rough + fine, cracks cut in)
    cr = fbm((n, n), 21, 5, 10)
    cracks = np.clip(1.0 - np.abs(cr - 0.5) / 0.035, 0.0, 1.0) * (r < edge * 0.85)
    hgt = rough * 0.6 + fine * 0.4 - cracks * 0.8
    hgt *= cover
    gy, gx = np.gradient(hgt)
    nx, ny = -gx * 18.0, -gy * 18.0
    nz = np.ones_like(nx)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    nm = np.stack([nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5, np.ones_like(nx)], -1)
    Image.fromarray((np.clip(nm, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(DST, "real_scorch_n.png"), optimize=True)
    # embers: the cracks and hot spots in the middle glow (R); G = how hot (centre hotter) for the cooling order
    hot = np.clip(1.0 - r / np.maximum(edge * 0.75, 1e-3), 0.0, 1.0)
    ember = np.clip(cracks * 0.9 + (fine > 0.66) * (rough > 0.55) * 0.7, 0.0, 1.0) * cover * np.clip(hot * 1.6, 0.0, 1.0)
    # coloured by a blackbody: the hot middle ~1600 K, the outer cracks ~1000 K (Decal emission is a colour)
    k = 1000.0 + 600.0 * hot
    t = k / 100.0
    g = np.clip(0.39008158 * np.log(t) - 0.63184144, 0.0, 1.0)
    em = np.stack([ember, ember * g, np.zeros_like(ember), np.ones_like(ember)], -1)
    Image.fromarray((np.clip(em, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(DST, "real_scorch_e.png"), optimize=True)
    print("wrote real_scorch*.png")


if __name__ == "__main__":
    fl = load("flame_fire_*.png")
    # where each sim's source sits in its frame (of the height from the top): the flame's stick at z 0.12 of 1.8,
    # the fireball at 1.0 of 5.6, the smoke's gout at 0.5 of 4.4
    if len(fl) >= 80:
        pack(loop(fl), "real_flame.png", fire=True, src_v=1.0 - 0.12 / 1.8)
    bf = load("burst_fire_*.png")
    bs = load("burst_smoke_*.png")
    if bf and bs:
        # the fire and its smoke share one window, so the two layers line up
        box = crop_box(bs + bf, 1.0 - 1.0 / 5.6)
        pack([crop(f, box) for f in bf], "real_burst_fire.png", fire=True)
        pack([crop(f, box) for f in bs], "real_burst_smoke.png")
    sm = load("smoke_smoke_*.png")
    if sm:
        pack(sm, "real_smoke.png", src_v=1.0 - 0.5 / 4.4)
    scorch()
