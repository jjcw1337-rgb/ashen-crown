#!/usr/bin/env python3
"""The camp waypoint's rune floor: the glowing rune lettering and ornament laid in rings on the dais's top.

Writes assets/textures/waypoint/rune_rings.png (2048 x 2048 covering +-3.5 m round the dais's centre, 1 px =
3.4 mm) with one mask per channel, so WaypointGrand's floor shader can light, pulse and turn each band on its own:
  R  the outer lettering ring (2.82-3.30 m, on the top tier's rim) AND the inner ring round the socket
     (0.70-1.01 m); the shader tells them apart by the pixel's radius
  G  the great lettering ring (2.02-2.70 m)
  B  the ornate band between the spokes (1.09-1.92 m): an octagram, arcs, small lettering, sigils
The radii match tools/blender/waypoint/build_dais.py: the bands lie on the flagstone rings between the carved
channels (1.01-1.09, 1.92-2.02, 2.70-2.82), whose own glow is the game's torus meshes, and the eight spokes.
The lettering is an Elder-Futhark-like alphabet drawn as strokes (no font), seeded, so a rebuild is identical.

  python3 tools/waypoint_runes.py [out.png] [--seed 7741] [--size 2048]
"""
import math, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

argv = sys.argv[1:]
OUT = argv[0] if argv and not argv[0].startswith("--") else "assets/textures/waypoint/rune_rings.png"
SEED = int(argv[argv.index("--seed") + 1]) if "--seed" in argv else 7741
SIZE = int(argv[argv.index("--size") + 1]) if "--size" in argv else 2048
SS = 2                       # supersampling
N = SIZE * SS
HALF = 3.5                   # metres from the centre to the texture's edge
PX = N / (2 * HALF)          # pixels per metre
rng = random.Random(SEED)

# ---------------------------------------------------------------- the alphabet: strokes in a unit box (x right, y up)
GLYPHS = [
    [[(0.2, 0), (0.2, 1)], [(0.2, 1), (0.8, 0.8)], [(0.2, 0.7), (0.8, 0.5)]],                  # fehu
    [[(0.15, 0), (0.15, 1), (0.85, 0.75), (0.85, 0)]],                                           # uruz
    [[(0.25, 0), (0.25, 1)], [(0.25, 0.8), (0.8, 0.5), (0.25, 0.2)]],                             # thurisaz
    [[(0.2, 0), (0.2, 1)], [(0.2, 1), (0.8, 0.75)], [(0.2, 0.7), (0.8, 0.45)]],                  # ansuz
    [[(0.2, 0), (0.2, 1), (0.8, 0.75), (0.35, 0.5), (0.8, 0)]],                                   # raido
    [[(0.8, 1), (0.2, 0.5), (0.8, 0)]],                                                           # kenaz
    [[(0.1, 0), (0.9, 1)], [(0.1, 1), (0.9, 0)]],                                                 # gebo
    [[(0.2, 0), (0.2, 1), (0.8, 0.8), (0.2, 0.55)]],                                              # wunjo
    [[(0.15, 0), (0.15, 1)], [(0.85, 0), (0.85, 1)], [(0.15, 0.7), (0.85, 0.3)]],                 # hagalaz
    [[(0.5, 0), (0.5, 1)], [(0.15, 0.3), (0.85, 0.7)]],                                           # nauthiz
    [[(0.5, 0), (0.5, 1)]],                                                                       # isa
    [[(0.25, 0.45), (0.5, 1), (0.75, 0.55)], [(0.75, 0.55), (0.5, 0), (0.25, 0.45)]],             # jera
    [[(0.3, 0), (0.3, 1), (0.7, 0.8)], [(0.3, 0.2), (0.7, 0.4)]],                                 # eihwaz
    [[(0.2, 0), (0.2, 1), (0.8, 0.75), (0.45, 0.5), (0.8, 0.25), (0.2, 0)]],                      # perthro
    [[(0.5, 0), (0.5, 1)], [(0.5, 0.6), (0.15, 1)], [(0.5, 0.6), (0.85, 1)]],                     # algiz
    [[(0.8, 1), (0.2, 0.65), (0.8, 0.35), (0.2, 0)]],                                             # sowilo
    [[(0.5, 0), (0.5, 1)], [(0.15, 0.7), (0.5, 1), (0.85, 0.7)]],                                 # tiwaz
    [[(0.2, 0), (0.2, 1), (0.8, 0.8), (0.2, 0.5), (0.8, 0.25), (0.2, 0)]],                        # berkano
    [[(0.15, 0), (0.15, 1), (0.5, 0.6), (0.85, 1), (0.85, 0)]],                                   # ehwaz
    [[(0.15, 0), (0.15, 1), (0.85, 0.4)], [(0.85, 1), (0.85, 0)], [(0.85, 1), (0.15, 0.4)]],      # mannaz
    [[(0.3, 0), (0.3, 1), (0.8, 0.7)]],                                                           # laguz
    [[(0.5, 1), (0.85, 0.5), (0.5, 0), (0.15, 0.5), (0.5, 1)]],                                   # ingwaz
    [[(0.15, 0), (0.15, 1), (0.85, 0), (0.85, 1), (0.15, 0)]],                                    # dagaz
    [[(0.5, 1), (0.85, 0.6), (0.65, 0.4), (0.9, 0)], [(0.85, 0.6), (0.15, 0.6)], [(0.5, 1), (0.15, 0.6), (0.35, 0.4), (0.1, 0)]],  # othala
]

layers = {k: Image.new("L", (N, N), 0) for k in "RGB"}
draws = {k: ImageDraw.Draw(layers[k]) for k in "RGB"}
C = N / 2.0


def xy(r, a):
    return (C + r * PX * math.cos(a), C - r * PX * math.sin(a))


def polar_line(d, pts, w):
    """Polyline of (radius, angle) points, each segment subdivided so it bends with the ring."""
    out = []
    for i in range(len(pts) - 1):
        (r0, a0), (r1, a1) = pts[i], pts[i + 1]
        n = max(2, int(abs(a1 - a0) * max(r0, r1) * PX / 6) + 1)
        for s in range(n + 1):
            t = s / n
            out.append(xy(r0 + (r1 - r0) * t, a0 + (a1 - a0) * t))
    d.line(out, fill=255, width=max(1, int(round(w * PX))), joint="curve")
    # round the stroke ends
    rad = w * PX * 0.5
    for p in (out[0], out[-1]):
        d.ellipse([p[0] - rad, p[1] - rad, p[0] + rad, p[1] + rad], fill=255)


def ring(d, r, w, a0=0.0, a1=math.tau):
    n = int((a1 - a0) * r * PX / 4) + 2
    pts = [xy(r, a0 + (a1 - a0) * i / n) for i in range(n + 1)]
    d.line(pts, fill=255, width=max(1, int(round(w * PX))), joint="curve")


def glyph(d, g, r_lo, r_hi, a_mid, width_m, w):
    """One glyph of the alphabet laid along the ring: unit y -> radius r_lo..r_hi, unit x -> arc round a_mid
    (reading clockwise from above, i.e. with the angle decreasing)."""
    da = width_m / ((r_lo + r_hi) * 0.5)
    for stroke in GLYPHS[g]:
        pts = [(r_lo + (r_hi - r_lo) * y, a_mid + da * (0.5 - x)) for (x, y) in stroke]
        polar_line(d, pts, w)


def lettering(d, r_lo, r_hi, pitch_m, w, a0=0.0, a1=math.tau, margin=0.0, sep_every=0, sep_r=0.0):
    """A row of glyphs between the radii from angle a0 to a1 (margin metres kept clear at each end)."""
    r_mid = (r_lo + r_hi) * 0.5
    arc = (a1 - a0) * r_mid - 2 * margin
    n = int(arc / pitch_m)
    if n < 1:
        return
    start = a0 + (margin + (arc - n * pitch_m) * 0.5 + pitch_m * 0.5) / r_mid
    for i in range(n):
        a = start + i * pitch_m / r_mid
        g = rng.randrange(len(GLYPHS))
        glyph(d, g, r_lo, r_hi, a, pitch_m * 0.62, w)
        if sep_every and i % sep_every == sep_every - 1 and i < n - 1:
            # a small diamond between words
            sa = a + 0.5 * pitch_m / r_mid
            s = sep_r
            poly = [xy(r_mid + s, sa), xy(r_mid, sa + s / r_mid), xy(r_mid - s, sa), xy(r_mid, sa - s / r_mid)]
            d.polygon(poly, fill=255)


def dot(d, r, a, s):
    p = xy(r, a)
    d.ellipse([p[0] - s * PX, p[1] - s * PX, p[0] + s * PX, p[1] + s * PX], fill=255)


# ---------------------------------------------------------------- R: the outer rim ring and the inner ring
dR = draws["R"]
ring(dR, 2.87, 0.018)
ring(dR, 3.25, 0.018)
ring(dR, 3.405, 0.022)       # the top tier's lit edge
lettering(dR, 2.93, 3.19, 0.30, 0.034, sep_every=7, sep_r=0.05)
ring(dR, 0.975, 0.012)
lettering(dR, 0.785, 0.945, 0.145, 0.022)

# ---------------------------------------------------------------- G: the great lettering ring
dG = draws["G"]
ring(dG, 2.065, 0.022)
ring(dG, 2.655, 0.022)
lettering(dG, 2.15, 2.57, 0.46, 0.046, sep_every=5, sep_r=0.07)

# ---------------------------------------------------------------- B: the ornate band between the spokes
dB = draws["B"]
SPOKE_HALF = 0.055 * 0.5 + 0.045       # the carved spoke and a clear margin beside it
sectors = [(math.tau * k / 8, math.tau * (k + 1) / 8) for k in range(8)]
# the octagram: two squares whose corners stand between the spokes
for off in (math.tau / 16, math.tau / 16 + math.tau / 8):
    corners = [(1.87, off + k * math.tau / 4) for k in range(4)]
    for k in range(4):
        (r0, a0), (r1, a1) = corners[k], corners[(k + 1) % 4]
        p0, p1 = xy(r0, a0), xy(r1, a1)
        # a straight chord: it dips to 1.32 m at its middle, over the arc below the lettering
        dB.line([p0, p1], fill=255, width=max(1, int(round(0.016 * PX))))
for k in range(8):
    a = math.tau / 16 + k * math.tau / 8
    dot(dB, 1.87, a, 0.035)           # a bead at each corner
    ring(dB, 1.87, 0.012, a - 0.11 / 1.87, a + 0.11 / 1.87)
for (a0, a1) in sectors:
    m = SPOKE_HALF
    ring(dB, 1.305, 0.014, a0 + m / 1.305, a1 - m / 1.305)
    lettering(dB, 1.135, 1.275, 0.135, 0.02, a0, a1, margin=m + 0.02)
    # a sigil in the middle of the sector, under the octagram's chord
    am = (a0 + a1) * 0.5
    dot(dB, 1.4, am, 0.02)
    for s in (-1, 1):
        dot(dB, 1.4, am + s * 0.09 / 1.4, 0.012)
    ring(dB, 1.56, 0.012, am - 0.13 / 1.56, am + 0.13 / 1.56)
    polar_line(dB, [(1.49, am), (1.63, am)], 0.012)

# ---------------------------------------------------------------- downsample and pack
img = Image.merge("RGB", [layers[k].resize((SIZE, SIZE), Image.LANCZOS) for k in "RGB"])
import os
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
img.save(OUT, optimize=True)
arr = np.asarray(img)
print("WROTE", OUT, img.size, "coverage R %.3f G %.3f B %.3f" % tuple((arr[..., i] > 64).mean() for i in range(3)))
