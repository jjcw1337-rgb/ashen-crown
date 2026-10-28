"""SUPERSEDED: the game's sounds now come from real recordings and generated candidates (spec.py, eleven.py,
score.py, build_sfx.py); this synthesizer remains for reference and for anything not yet replaced. Rendering a
name here overwrites that sound's files.

Renders Ashen Crown's sound effects offline (numpy synthesis, see dsp.py) into assets/audio/sfx/ and
writes scripts/sfx_bank.gd (each sound's number of takes and its bus) for Sfx to load.

    python3 tools/audio/make_sfx.py [name ...] [--spectro outdir]
(any python3 with numpy; Blender's bundled python works). With names, only those sounds are rendered
(the bank lists everything already on disk). --spectro also writes a spectrogram PNG per take.

Every sound is a function of a random generator, so each take differs a little (pitch, timing,
grit). Sounds are layered the way game audio usually is: a transient (the crack you hear first), a
body (the thump you feel) and a tail (debris, ring, room). Class identities:
  knight  steel and light: ringing metal, boots, bells, a breath of choir for holy fire
  wraith  cold and hollow: breath, reversed whispers, glass, icy tails
  demon   fire and flesh: sub-bass, roaring flame, crackle, wet tearing, rock
  warlock fel and chains: bubbling siphons, chains, hissing green fire, a low choir
"""
import os, sys, glob, re, zlib
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from dsp import *

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "../.."))
OUT = os.path.join(ROOT, "assets/audio/sfx")
BANK_GD = os.path.join(ROOT, "scripts/sfx_bank.gd")

SOUNDS = {}   # name -> (fn, takes, bus, rms_db)

# The mix (after the first pass was "a little too synthy and too loud"): every sound lands LEVEL dB under
# its own target and never louder than CEIL, so stacked spells don't pile up; rooms are shorter and drier
# than each sound's space() asks for (TAIL scales the size, WET the mix), so sounds end tight.
LEVEL, CEIL = -5.0, -19.0
LOUD = -14.5   # dB: the loudest 100 ms of any sound stays under this (what the ear hears as "loud")
TAIL, WET = 0.6, 0.5
THUMP = 0.5   # the low thud under hits and spells: a felt weight, not a sound of its own
_space = space


def space(x, rng, size=1.2, mix=0.25, damp=6000.0, stereo=False):
    return _space(x, rng, size * TAIL, mix * WET, damp, stereo)


def rms(x):
    return np.sqrt(np.mean(x ** 2)) + 1e-9


def loudest(x, win=0.1):
    p = (x ** 2).mean(axis=0) if x.ndim == 2 else x ** 2
    w = n_of(win)
    if len(p) <= w:
        return 10 * np.log10(p.mean() + 1e-12)
    c = np.concatenate([[0.0], np.cumsum(p)])
    return 10 * np.log10(((c[w:] - c[:-w]) / w).max() + 1e-12)


def sound(takes=3, bus="sfx", rms=-18.0):
    def reg(fn):
        SOUNDS[fn.__name__] = (fn, takes, bus, rms)
        return fn
    return reg


# ---------------------------------------------------------------- building blocks
def whoosh(rng, dur, f0, f1, peak=0.45, width=1.2, kind="pink"):
    n = n_of(dur)
    src = pink(n, rng) if kind == "pink" else white(n, rng)
    return sweep_bp(src, f0, f1, width) * swell(n, peak, 1.6, 2.4)


def thump(rng, f0, f1, dur, decay=14.0, click=0.4):
    # a falling sine for the weight, under a burst of dull noise so it lands like a body, not a kick drum
    n = n_of(dur)
    t = t_axis(n)
    f = f1 + (f0 - f1) * np.exp(-t * 18.0)
    body = sine(f) * env_exp(n, decay * 1.5, 0.001)
    thud = lowpass(brown(n, rng), f0 * 2.0, 3)
    thud = thud / (np.max(np.abs(thud)) + 1e-9) * env_exp(n, decay * 2.2, 0.001)
    clk = highpass(white(n, rng), 1500) * env_exp(n, 220.0, 0.0005) * click
    return (body * 0.7 + thud * 0.55) * THUMP + clk


def crunch(rng, dur, centre, decay=40.0, oct=1.4):
    n = n_of(dur)
    return bandpass(white(n, rng), centre, oct) * env_exp(n, decay, 0.0008)


def ring(rng, dur, base, ratios, decay, amp=1.0, detune=0.01, grit=0.6):
    """A struck thing (metal, glass, bell). Pure decaying sines read as a synth, so each mode is mostly a
    narrow band of noise (it wavers and buzzes like a real resonance) over a quieter sine core."""
    n = n_of(dur)
    t = t_axis(n)
    out = np.zeros(n)
    for i, r in enumerate(ratios):
        f = base * r * (1.0 + rng.uniform(-detune, detune))
        e = np.exp(-t * decay * (1 + 0.35 * i) * rng.uniform(0.85, 1.2))
        band = bandpass(white(n, rng), f, 0.035)
        band *= 0.707 / rms(band)
        core = np.sin(2.0 * np.pi * f * t + rng.uniform(0, 6.28))
        out += amp / (1 + 0.6 * i) * (grit * band + (1 - grit) * core) * e
    return out


METAL = [1.0, 2.76, 5.40, 8.93, 13.34]
BELL = [0.5, 1.0, 1.19, 1.56, 2.0, 2.51, 3.0]
GLASS = [1.0, 2.32, 4.25, 6.63]


def choir(rng, dur, roots, vowel_path, scale=1.0, breath=0.15, attack=0.3, release=0.6):
    """A breathy pad: mostly air through narrow bands on the chord's harmonics (wind over a bottle, not a
    keyboard), with a faint sung voice underneath for the vowel."""
    n = n_of(dur)
    sung = np.zeros(n)
    air = np.zeros(n)
    src = pink(n, rng)
    for r in roots:
        f0 = r * (1 + 0.004 * sine(5.0 + rng.uniform(-0.5, 0.5), n))
        sung += voice(n, f0, vowel_path, rng, breath + 0.6, scale)
        for h, g in ((1, 1.0), (2, 0.45), (3, 0.2)):
            b = bandpass(src, r * h, 0.04)
            air += g * b / rms(b)
    s = rms(sung)
    out = air * (0.8 * s / rms(air)) + sung * 0.3
    return out * env_ad(n, attack, release, 1.5)


def plus(*xs):
    """Sum of signals of different lengths (zero-padded to the longest)."""
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[:len(x)] += x
    return out


def m(x):
    """Mono helper: average a stereo buffer."""
    return x.mean(axis=0) if x.ndim == 2 else x


# ---------------------------------------------------------------- combat: swings
@sound(4, rms=-20)
def swing_light(rng):
    d = rng.uniform(0.2, 0.26)
    w = whoosh(rng, d, rng.uniform(700, 900), rng.uniform(2200, 3000), 0.42, 1.0)
    edge = highpass(white(n_of(d), rng), 5000) * swell(n_of(d), 0.45, 4, 6) * 0.25
    return space(w + edge, rng, 0.4, 0.12)


@sound(4, rms=-19)
def swing_heavy(rng):
    d = rng.uniform(0.32, 0.4)
    w = whoosh(rng, d, rng.uniform(250, 330), rng.uniform(800, 1100), 0.5, 1.4)
    body = lowpass(brown(n_of(d), rng), 300) * swell(n_of(d), 0.5, 2, 3) * 0.7
    return space(w + body, rng, 0.5, 0.12)


# ---------------------------------------------------------------- combat: impacts
@sound(5, rms=-17)
def impact_flesh(rng):
    th = thump(rng, rng.uniform(150, 190), rng.uniform(48, 60), 0.3, 16, 0.5)
    cr = crunch(rng, 0.12, rng.uniform(1200, 1800), 45, 1.6) * 0.8
    wet = bandpass(white(n_of(0.2), rng), 420, 1.0) * env_exp(n_of(0.2), 22) * 0.6
    wet += crackle(n_of(0.2), rng, 300, 600, 2000) * env_exp(n_of(0.2), 18) * 0.5
    x = place([(th, 0, 1.0), (cr, 0, 1.0), (wet, 0.005, 1.0)])
    return space(saturate(x, 1.6), rng, 0.35, 0.1)


@sound(4, rms=-15)
def impact_bone(rng):
    parts = []
    for k in range(rng.integers(2, 4)):
        clack = plus(ring(rng, 0.09, rng.uniform(900, 1400), [1, 2.4, 3.9], 60) * 0.6, crunch(rng, 0.05, rng.uniform(2500, 4000), 80, 1.0))
        parts.append((clack, k * rng.uniform(0.012, 0.03), 1.0 / (k + 1)))
    parts.append((thump(rng, 160, 70, 0.18, 22, 0.3), 0, 0.6))
    return space(place(parts), rng, 0.3, 0.12)


@sound(3, rms=-15)
def impact_metal(rng):
    n = n_of(0.5)
    r = ring(rng, 0.5, rng.uniform(620, 760), METAL, 9, 0.6)
    clk = crunch(rng, 0.05, 3500, 90, 1.5)
    th = thump(rng, 140, 60, 0.2, 18, 0.2) * 0.7
    return space(place([(r, 0, 0.7), (clk, 0, 1.0), (th, 0, 1.0)]), rng, 0.5, 0.14)


@sound(3, rms=-15)
def crit_sting(rng):
    # the "that was big" layer, on top of a normal impact: a bright shing, a crack and a low boom
    shing = ring(rng, 0.55, rng.uniform(1700, 2000), [1, 1.5, 2.01, 2.99, 4.1], 8.0, 0.7, 0.003)
    crack = highpass(white(n_of(0.04), rng), 3000) * env_exp(n_of(0.04), 120, 0.0003)
    boom = thump(rng, 90, 38, 0.5, 7, 0.0) * 0.9
    x = place([(shing, 0.0, 0.35), (crack, 0, 1.0), (boom, 0, 1.0)])
    return space(x, rng, 0.9, 0.22, 8000, stereo=True)


@sound(3, rms=-15)
def kill_flesh(rng):
    th = thump(rng, 120, 40, 0.45, 9, 0.6)
    gore = lowpass(white(n_of(0.35), rng), 1400) * env_exp(n_of(0.35), 12) * 0.6
    gore += crackle(n_of(0.35), rng, 420, 500, 1500) * env_exp(n_of(0.35), 9) * 0.7
    fall = thump(rng, 90, 50, 0.3, 12, 0.2) * 0.6
    return space(place([(th, 0, 1.0), (gore, 0.01, 1.0), (fall, rng.uniform(0.18, 0.26), 1.0)]), rng, 0.5, 0.14)


@sound(3, rms=-15)
def kill_bone(rng):
    parts = [(thump(rng, 140, 60, 0.25, 15, 0.3), 0, 0.7)]
    t0 = 0.0
    for k in range(rng.integers(7, 11)):
        t0 += rng.uniform(0.025, 0.07)
        cl = plus(ring(rng, 0.1, rng.uniform(700, 1600), [1, 2.3, 3.7], 55) * 0.5, crunch(rng, 0.04, rng.uniform(2000, 4500), 90))
        parts.append((cl, t0, 1.0 / (1 + k * 0.25)))
    return space(place(parts), rng, 0.4, 0.14)


@sound(3, rms=-15)
def block(rng):
    r = ring(rng, 0.7, rng.uniform(480, 560), METAL, 6, 0.8)
    knock = thump(rng, 220, 110, 0.12, 30, 0.6)
    scrape = crunch(rng, 0.15, 3000, 25, 2.0) * 0.4
    return space(place([(r, 0, 0.6), (knock, 0, 1.0), (scrape, 0.004, 1.0)]), rng, 0.6, 0.15)


# ---------------------------------------------------------------- the heroes' bodies
def grunt(rng, f0, scale, dur, vowels, rough=0.12, drive=1.4, breath=0.9):
    n = n_of(dur)
    t = t_axis(n)
    f = f0 * (1.0 + 0.12 * np.exp(-t * 20)) * (1.0 - 0.15 * t / dur)
    v = voice(n, f, vowels, rng, breath, scale, rough)
    return saturate(v * env_ad(n, 0.015, dur * 0.6, 1.2), drive)


@sound(3, rms=-17)
def hurt_knight(rng):
    return space(grunt(rng, rng.uniform(105, 125), 1.0, rng.uniform(0.2, 0.28), [(0, "aa"), (1, "u")]), rng, 0.3, 0.1)


@sound(3, rms=-17)
def hurt_gnome(rng):
    return space(grunt(rng, rng.uniform(210, 240), 1.35, rng.uniform(0.16, 0.22), [(0, "e"), (1, "o")]), rng, 0.3, 0.1)


@sound(3, rms=-18)
def hurt_wraith(rng):
    n = n_of(0.35)
    hiss = voice(n, 90.0, [(0, "i"), (1, "e")], rng, breath=3.0, scale=1.6) * env_ad(n, 0.01, 0.25)
    glass = ring(rng, 0.35, rng.uniform(2400, 2900), GLASS, 10, 0.3)
    return space(hiss + glass, rng, 0.8, 0.3, 5000)


@sound(3, rms=-16)
def hurt_demon(rng):
    g = grunt(rng, rng.uniform(62, 75), 0.8, rng.uniform(0.28, 0.36), [(0, "aa"), (1, "o")], 0.35, 3.0)
    sizzle = crackle(len(g), rng, 500, 700, 3000) * env_exp(len(g), 8) * 0.25
    return space(g + sizzle, rng, 0.4, 0.12)


def death_voice(rng, f0, scale, vowels, dur, rough, drive):
    n = n_of(dur)
    t = t_axis(n)
    f = f0 * (1.0 - 0.35 * t / dur)
    v = voice(n, f, vowels, rng, 0.8, scale, rough) * env_ad(n, 0.02, dur * 0.7, 1.0)
    return saturate(v, drive)


@sound(1, rms=-15)
def death_knight(rng):
    v = death_voice(rng, 120, 1.0, [(0, "aa"), (0.6, "o"), (1, "u")], 1.0, 0.1, 1.6)
    clank = place([(impact_metal(rng), 0.55, 0.6), (thump(rng, 100, 45, 0.4, 9, 0.4), 0.5, 0.8)])
    return space(place([(v, 0, 1.0), (clank, 0, 1.0)]), rng, 1.2, 0.2)


@sound(1, rms=-15)
def death_gnome(rng):
    v = death_voice(rng, 240, 1.35, [(0, "e"), (0.5, "a"), (1, "o")], 0.8, 0.08, 1.5)
    return space(place([(v, 0, 1.0), (thump(rng, 120, 60, 0.3, 12, 0.3), 0.5, 0.7)]), rng, 1.0, 0.2)


@sound(1, rms=-16)
def death_wraith(rng):
    n = n_of(1.6)
    scream = voice(n, 480 * (1 - 0.4 * t_axis(n) / 1.6), [(0, "i"), (1, "u")], rng, 3.5, 1.8, 0.05) * env_ad(n, 0.05, 1.0)
    return space(reverse(space(scream * 0.4, rng, 0.6, 1.0)[:n]) * 0.4 + scream, rng, 2.0, 0.4, 4000)


@sound(1, rms=-15)
def death_demon(rng):
    v = death_voice(rng, 70, 0.8, [(0, "aa"), (1, "o")], 1.3, 0.4, 3.0)
    fire = lowpass(white(len(v), rng), 900) * env_exp(len(v), 2.5) * 0.4 + crackle(len(v), rng, 300, 500, 2500) * env_exp(len(v), 2) * 0.5
    return space(v + fire, rng, 1.2, 0.2)


# ---------------------------------------------------------------- Knight: steel and light
@sound(3, rms=-17)
def cleave_swing(rng):
    d = 0.42
    w = whoosh(rng, d, 380, 1500, 0.55, 1.3) * 1.2
    cut = highpass(white(n_of(0.08), rng), 4000) * env_ad(n_of(0.08), 0.02, 0.05) * 0.5
    sing = ring(rng, 0.5, rng.uniform(1650, 1800), [1, 1.5, 2.02, 3.0], 8, 0.3, 0.002)
    return space(place([(w, 0, 1.0), (cut, 0.2, 1.0), (sing, 0.22, 0.2)]), rng, 0.8, 0.15, 8000, stereo=True)


@sound(2, "sfx", -15)
def holy_nova(rng):
    # an intake of light, a bright crack outward, then holy fire crackling under ringing bells
    build = choir(rng, 0.32, [220.0, 277.2, 329.6], [(0, "o"), (1, "a")], 1.15, 0.1, 0.25, 0.04)
    build *= np.linspace(0.2, 1.0, len(build))
    crack = highpass(white(n_of(0.06), rng), 2500) * env_exp(n_of(0.06), 80, 0.0005)
    out_w = whoosh(rng, 0.6, 5000, 700, 0.12, 1.8) * 1.3
    boom = thump(rng, 110, 40, 0.8, 5, 0.0)
    bells = ring(rng, 1.1, 880, BELL, 3.2, 0.5, 0.004)
    fire = crackle(n_of(1.6), rng, np.linspace(900, 60, n_of(1.6)), 800, 3500) * env_exp(n_of(1.6), 1.8) * 0.6
    roar = bandpass(pink(n_of(1.2), rng), 900, 2.0) * env_exp(n_of(1.2), 3.0) * 0.5
    T = 0.3
    x = place([(build, 0, 1.0), (crack, T, 1.0), (out_w, T, 1.0), (boom, T, 1.0), (bells, T + 0.02, 0.2), (fire, T + 0.03, 1.0), (roar, T + 0.02, 1.0)])
    return space(x, rng, 2.2, 0.3, 7000, stereo=True)


@sound(2, rms=-17)
def charge_dash(rng):
    d = 0.55
    rush = whoosh(rng, d, 300, 2200, 0.7, 1.6) * 1.1
    rattle = bandpass(crackle(n_of(d), rng, 260, 1400, 2500), 3800, 1.2) * swell(n_of(d), 0.5) * 1.2
    steps = place([(thump(rng, 120, 55, 0.18, 20, 0.5), k * 0.13, 0.6 + 0.15 * k) for k in range(4)])
    return space(place([(rush, 0, 1.0), (rattle, 0, 0.7), (steps, 0, 0.8)]), rng, 0.6, 0.12, 6000, stereo=True)


@sound(3, rms=-13)
def charge_impact(rng):
    boom = thump(rng, 100, 34, 0.7, 6, 0.8) * 1.3
    crash = plus(ring(rng, 0.9, rng.uniform(380, 460), METAL, 5, 0.7), crunch(rng, 0.3, 2400, 14, 2.0))
    debris = crackle(n_of(0.6), rng, np.linspace(500, 20, n_of(0.6)), 500, 1500) * 0.6
    return space(saturate(place([(boom, 0, 1.0), (crash, 0, 0.6), (debris, 0.02, 1.0)]), 1.4), rng, 1.0, 0.18, 6000, stereo=True)


@sound(2, rms=-14)
def battle_cry(rng):
    n = n_of(1.0)
    t = t_axis(n)
    shout = voice(n, 150 * (1 + 0.06 * np.exp(-t * 4)) * (1 - 0.1 * t), [(0, "aa"), (0.7, "aa"), (1, "o")], rng, 0.9, 1.0, 0.25)
    shout = saturate(shout * env_ad(n, 0.04, 0.35, 1.2), 2.2)
    bash = plus(ring(rng, 0.5, rng.uniform(300, 360), METAL, 9, 0.8), crunch(rng, 0.06, 2600, 70))
    drum = plus(thump(rng, 90, 45, 0.9, 5, 0.9), bandpass(white(n_of(0.3), rng), 220, 1.5) * env_exp(n_of(0.3), 18))
    return space(place([(shout, 0, 1.0), (bash, 0, 0.5), (drum, 0, 1.0), (drum * 0.7, 0.35, 1.0)]), rng, 1.6, 0.28, 6000, stereo=True)


# ---------------------------------------------------------------- Wraith: cold and hollow
@sound(3, rms=-18)
def reap_swing(rng):
    d = 0.45
    w = whoosh(rng, d, 1200, 4200, 0.55, 1.0, "white") * 0.9
    breath = voice(n_of(d), 120.0, [(0, "u"), (1, "i")], rng, 4.0, 1.6) * swell(n_of(d), 0.5) * 0.6
    glass = ring(rng, 0.9, rng.uniform(2600, 3100), GLASS, 5, 0.35)
    return space(place([(w, 0, 1.0), (breath, 0, 1.0), (glass, 0.22, 0.6)]), rng, 1.2, 0.3, 5000, stereo=True)


@sound(3, rms=-20)
def soul_return(rng):
    whisper = voice(n_of(0.5), 200.0, [(0, "i"), (1, "u")], rng, 5.0, 1.8) * env_ad(n_of(0.5), 0.3, 0.1)
    chime = ring(rng, 0.8, rng.choice([1568.0, 1760.0, 2093.0]), [1, 2, 3.01], 5, 0.5)
    return space(place([(whisper, 0, 0.8), (chime, 0.42, 0.6)]), rng, 1.0, 0.3, 6000)


@sound(2, rms=-14)
def wail(rng):
    n = n_of(1.4)
    t = t_axis(n)
    f0 = 520 * (1 + 0.05 * np.sin(2 * np.pi * 7 * t)) * (1 + 0.2 * np.minimum(t * 4, 1)) * (1 - 0.25 * np.clip(t - 0.6, 0, 1))
    scream = voice(n, f0, [(0, "u"), (0.15, "i"), (0.7, "e"), (1, "u")], rng, 3.5, 1.9, 0.06) * env_ad(n, 0.08, 0.5, 1.3)
    pre = reverse(space(scream[:n_of(0.3)] * 0.6, rng, 0.3, 1.0)[:n_of(0.3)])
    shatter = plus(ring(rng, 0.7, rng.uniform(3200, 3600), GLASS, 6.0, 0.6), highpass(white(n_of(0.08), rng), 4000) * env_exp(n_of(0.08), 60))
    blast = whoosh(rng, 0.7, 4000, 500, 0.1, 2.0)
    x = place([(pre, 0, 0.5), (scream, 0.28, 1.0), (shatter, 0.31, 0.5), (blast, 0.3, 0.9)])
    return space(x, rng, 2.4, 0.38, 4500, stereo=True)


@sound(2, rms=-17)
def shade_out(rng):
    x = space(whoosh(rng, 0.35, 3000, 600, 0.3, 1.5), rng, 0.6, 0.9)
    sucked = reverse(x)
    return space(place([(sucked, 0, 1.0), (thump(rng, 70, 40, 0.3, 10, 0.0), len(sucked) / SR - 0.05, 0.6)]), rng, 0.5, 0.15, 5000, stereo=True)


@sound(2, rms=-15)
def shade_in(rng):
    burst = whoosh(rng, 0.5, 4500, 700, 0.08, 1.8)
    glass = ring(rng, 1.0, rng.uniform(2200, 2600), GLASS, 4, 0.5)
    th = thump(rng, 130, 45, 0.5, 9, 0.6)
    return space(place([(burst, 0, 1.0), (glass, 0.01, 0.4), (th, 0, 1.0)]), rng, 1.4, 0.32, 5000, stereo=True)


@sound(2, rms=-16)
def shade_implode(rng):
    suck = reverse(space(whoosh(rng, 0.25, 2500, 800, 0.4, 1.2), rng, 0.4, 0.8))
    pop = thump(rng, 160, 50, 0.35, 12, 0.7)
    return space(place([(suck, 0, 1.0), (pop, len(suck) / SR - 0.02, 1.0)]), rng, 1.0, 0.3, 5000, stereo=True)


@sound(2, rms=-16)
def host_summon(rng):
    whispers = np.zeros(n_of(1.5))
    for k in range(3):
        n = n_of(0.9)
        w = voice(n, rng.uniform(140, 260), [(0, "u"), (0.5, "o"), (1, "i")], rng, 5.0, 1.7) * env_ad(n, 0.3, 0.4)
        whispers = place([(whispers, 0, 1.0), (w, k * 0.18, 0.7)])
    pad = choir(rng, 1.6, [330.0, 415.3, 494.0], [(0, "u"), (1, "o")], 1.6, 0.6, 0.5, 0.8)
    chime = ring(rng, 1.5, 1975.0, [1, 1.5, 2.01], 2.5, 0.4)
    return space(place([(whispers, 0, 1.0), (pad, 0.2, 0.4), (chime, 0.7, 0.25)]), rng, 2.4, 0.4, 5000, stereo=True)


@sound(4, rms=-21)
def spirit_dart(rng):
    n = n_of(0.18)
    t = t_axis(n)
    zip_ = sweep_bp(white(n, rng), 1300, 5500, 0.35) * env_ad(n, 0.01, 0.12) * 0.9
    air = highpass(white(n, rng), 2500) * env_ad(n, 0.02, 0.12) * 0.4
    return space(zip_ + air, rng, 0.6, 0.3, 6000)


# ---------------------------------------------------------------- Demon: fire and flesh
def flame(rng, dur, decay=3.0, roar_hz=500):
    n = n_of(dur)
    roar = bandpass(pink(n, rng), roar_hz, 2.4) * env_exp(n, decay, 0.03)
    crk = crackle(n, rng, 500, 600, 2500) * env_exp(n, decay * 0.8)
    return fade(roar + crk * 0.7, 0.003, dur * 0.4)


@sound(3, rms=-16)
def hellclaw(rng):
    rips = [(plus(whoosh(rng, 0.16, 600, 2400, 0.4, 1.0, "white") * 1.3, crunch(rng, 0.05, 1800, 50) * 0.7), k * 0.07, 1.0 - 0.15 * k) for k in range(3)]
    fl = flame(rng, 0.9, 3.0, 700)
    return space(place(rips + [(fl, 0.1, 0.6)]), rng, 0.8, 0.16, 6000, stereo=True)


@sound(2, rms=-14)
def summon_demon(rng):
    n = n_of(1.0)
    rumble = lowpass(brown(n, rng), 140) * swell(n, 0.7, 1.5, 2.0) * 2.0
    rocks = crackle(n_of(0.9), rng, np.linspace(40, 500, n_of(0.9)), 300, 1200) * 0.8
    m_ = n_of(0.9)
    tt = t_axis(m_)
    roar = voice(m_, 68 * (1 + 0.15 * np.exp(-tt * 5)), [(0, "o"), (0.3, "aa"), (1, "o")], rng, 1.3, 0.75, 0.45)
    roar = saturate(roar * env_ad(m_, 0.06, 0.4), 3.0)
    fl = flame(rng, 1.0, 2.5, 400)
    return space(place([(rumble, 0, 1.0), (rocks, 0.1, 1.0), (roar, 0.65, 1.0), (fl, 0.65, 0.8), (thump(rng, 90, 32, 0.7, 6, 0.6), 0.65, 1.0)]), rng, 1.6, 0.2, 5000, stereo=True)


@sound(1, rms=-16)
def phase_in(rng):
    n = n_of(0.9)
    t = t_axis(n)
    drop = (sine(140 * np.exp(-t * 2.2) + 30) * 0.4 + sweep_lp(brown(n, rng), 500, 70) * 1.2) * env_ad(n, 0.01, 0.4)
    dark = reverse(space(bandpass(pink(n_of(0.3), rng), 300, 2.0), rng, 0.9, 1.0))[:n]
    whispers = voice(n, 90.0, [(0, "u"), (1, "o")], rng, 4.0, 1.0) * env_ad(n, 0.2, 0.4) * 0.3
    return space(place([(dark, 0, 0.7), (drop, 0.3, 1.0), (whispers, 0.1, 1.0)]), rng, 1.6, 0.35, 3000, stereo=True)


@sound(2, rms=-13)
def phase_erupt(rng):
    blast = lowpass(white(n_of(1.0), rng), 2500) * env_exp(n_of(1.0), 5, 0.001)
    boom = thump(rng, 90, 28, 1.2, 3.5, 0.9) * 1.4
    fl = flame(rng, 1.6, 2.0, 380)
    debris = crackle(n_of(1.0), rng, np.linspace(900, 20, n_of(1.0)), 400, 1200) * 0.6
    return space(saturate(place([(blast, 0, 1.0), (boom, 0, 1.0), (fl, 0.05, 1.0), (debris, 0.1, 1.0)]), 1.6), rng, 2.2, 0.25, 5000, stereo=True)


@sound(2, rms=-15)
def blood_pact(rng):
    beats = []
    for k in range(2):
        beats += [(thump(rng, 70, 40, 0.25, 14, 0.1), k * 0.55, 1.0), (thump(rng, 62, 36, 0.22, 16, 0.1), k * 0.55 + 0.17, 0.7)]
    wet = bandpass(white(n_of(0.5), rng), 380, 1.2) * env_ad(n_of(0.5), 0.05, 0.3) * 0.7
    wet += crackle(n_of(0.5), rng, 300, 300, 800) * env_ad(n_of(0.5), 0.05, 0.3)
    ch = choir(rng, 1.8, [82.4, 98.0, 123.5], [(0, "o"), (1, "u")], 0.85, 0.1, 0.5, 0.9)
    return space(place(beats + [(wet, 0.15, 0.9), (ch, 0.3, 0.45)]), rng, 2.0, 0.3, 3500, stereo=True)


# ---------------------------------------------------------------- Warlock: fel and chains
@sound(2, rms=-17)
def drain_start(rng):
    n = n_of(0.35)
    t = t_axis(n)
    zap = (sweep_bp(white(n, rng), 700, 2600, 0.6) * 0.8 + crackle(n, rng, 500, 500, 2500) * 0.6) * env_ad(n, 0.005, 0.2)
    suck = reverse(space(bandpass(pink(n_of(0.3), rng), 900, 1.2), rng, 0.4, 0.8))
    return space(place([(suck, 0, 0.8), (zap, len(suck) / SR - 0.05, 1.0)]), rng, 0.9, 0.25, 4000, stereo=True)


@sound(1, "sfx", -22)
def drain_loop(rng):
    # 2 s that loops seamlessly: a hollow throat hum moving between vowels, bubbling under it, a thin siphon
    dur, xf = 2.0, 0.4
    n = n_of(dur + xf)
    t = t_axis(n)
    f0 = 82 * (1 + 0.01 * np.sin(2 * np.pi * 0.5 * t))
    hum = voice(n, f0, [(0, "u"), (0.35, "o"), (0.7, "u"), (1, "o")], rng, 1.5, 0.9) * 0.6
    bub = bandpass(crackle(n, rng, 60, 160, 400), 500, 1.2) * 1.5
    siphon = bandpass(white(n, rng), 2600, 0.5) * (0.5 + 0.5 * np.sin(2 * np.pi * 1.0 * t)) * 0.12
    x = hum + bub + siphon
    k = n_of(xf)
    head = x[:k] * np.linspace(0, 1, k) + x[-k:] * np.linspace(1, 0, k)
    return np.concatenate([head, x[k:n - k]])


@sound(4, rms=-20)
def drain_tick(rng):
    n = n_of(0.16)
    t = t_axis(n)
    glug = sine(230 * np.exp(-t * 5)) * env_exp(n, 22, 0.004) * 0.4
    wet = bandpass(white(n, rng), 450, 0.8) * env_exp(n, 30) * 0.7
    return space(glug + wet, rng, 0.4, 0.15, 3000)


@sound(2, rms=-16)
def blight_cast(rng):
    n = n_of(0.7)
    t = t_axis(n)
    howl = voice(n, 280 * (1 + 0.06 * np.sin(2 * np.pi * 9 * t)) * (1 + 0.2 * t), [(0, "u"), (0.5, "o"), (1, "u")], rng, 3.0, 1.3, 0.2) * env_ad(n, 0.05, 0.3)
    w = whoosh(rng, 0.6, 400, 1800, 0.35, 1.2)
    hiss = highpass(white(n, rng), 3500) * env_ad(n, 0.05, 0.4) * 0.12
    return space(place([(howl, 0, 0.8), (w, 0, 1.0), (hiss, 0, 1.0)]), rng, 1.0, 0.25, 4500, stereo=True)


@sound(3, rms=-14)
def blight_burst(rng):
    splash = lowpass(white(n_of(0.5), rng), 1800) * env_exp(n_of(0.5), 9, 0.001)
    splat = crackle(n_of(0.6), rng, np.linspace(1500, 50, n_of(0.6)), 350, 900) * 0.8
    bubbles = place([(sine(rng.uniform(300, 900) * np.exp(t_axis(n_of(0.06)) * 6)) * env_exp(n_of(0.06), 50) * 0.4, rng.uniform(0.05, 0.9), 1.0) for _ in range(14)])
    th = thump(rng, 110, 40, 0.4, 10, 0.3)
    sizzle = highpass(white(n_of(1.0), rng), 4000) * env_exp(n_of(1.0), 3) * 0.1
    return space(place([(splash, 0, 1.0), (splat, 0, 1.0), (bubbles, 0, 0.45), (th, 0, 1.0), (sizzle, 0.05, 1.0)]), rng, 1.0, 0.2, 5000, stereo=True)


def chains(rng, dur, density=320):
    n = n_of(dur)
    imp = crackle(n, rng, density, 300, 1500)
    links = np.zeros(n)
    for base in (2300, 3100, 4200):
        links += bandpass(imp, base * rng.uniform(0.95, 1.05), 0.25)
    return links * 1.5


@sound(2, rms=-14)
def shackles(rng):
    rattle = chains(rng, 0.7) * swell(n_of(0.7), 0.3, 1.5, 2.0)
    snaps = [(highpass(white(n_of(0.03), rng), 2500) * env_exp(n_of(0.03), 140, 0.0003), 0.12 + k * rng.uniform(0.05, 0.09), 1.0) for k in range(3)]
    clank = plus(ring(rng, 0.7, rng.uniform(380, 450), METAL, 7, 0.8), thump(rng, 140, 60, 0.2, 18, 0.5))
    hiss = bandpass(white(n_of(0.9), rng), 3200, 1.5) * env_ad(n_of(0.9), 0.05, 0.6) * 0.25
    return space(place([(rattle, 0, 0.8)] + snaps + [(clank, 0.42, 0.8), (hiss, 0.1, 1.0)]), rng, 1.2, 0.2, 5000, stereo=True)


@sound(2, rms=-15)
def covenant(rng):
    ch = choir(rng, 1.8, [65.4, 98.0, 130.8], [(0, "u"), (0.4, "o"), (1, "a")], 0.85, 0.08, 0.5, 0.7)
    fel = bandpass(pink(n_of(1.8), rng), 380, 2.2) * swell(n_of(1.8), 0.35, 1.5, 2) * 0.7
    fel += crackle(n_of(1.8), rng, 200, 700, 3000) * swell(n_of(1.8), 0.35) * 0.4
    bell = ring(rng, 1.6, 196.0, [1, 2.0, 2.4, 3.0, 4.2, 5.4], 2.4, 0.9, 0.003)
    return space(place([(ch, 0, 1.0), (fel, 0.2, 1.0), (bell, 0.45, 0.4)]), rng, 2.8, 0.35, 3500, stereo=True)


# ---------------------------------------------------------------- reward
@sound(1, "ui", -15)
def levelup(rng):
    pad = choir(rng, 2.0, [261.6, 329.6, 392.0], [(0, "o"), (1, "a")], 1.15, 0.1, 0.25, 0.9)
    notes = [523.3, 659.3, 784.0, 1046.5, 1318.5]
    arp = place([(ring(rng, 0.8, f, [1, 2.0, 3.01], 4.5, 0.5, 0.004, 0.4), 0.08 + k * 0.07, 0.6) for k, f in enumerate(notes)])
    shimmer = highpass(white(n_of(1.5), rng), 6000) * env_ad(n_of(1.5), 0.3, 1.0) * 0.06
    return space(place([(pad, 0, 0.4), (arp, 0, 1.0), (shimmer, 0.2, 1.0)]), rng, 2.0, 0.3, 8000, stereo=True)


# ---------------------------------------------------------------- render
def render(names=None, spectro=None):
    os.makedirs(OUT, exist_ok=True)
    todo = names or list(SOUNDS)
    for name in todo:
        fn, takes, bus, rms = SOUNDS[name]
        for old in glob.glob(os.path.join(OUT, f"{name}_*.wav")):
            os.remove(old)
        for k in range(takes):
            rng = np.random.default_rng(zlib.crc32(name.encode()) + k * 7919)
            x = fn(rng)
            x = trim_silence(fade(x) if x.ndim == 1 else np.stack([fade(c) for c in x]))
            x = normalize(x, 0.92, min(rms + LEVEL, CEIL))
            x = x * 10 ** (min(0.0, LOUD - loudest(x)) / 20)
            path = os.path.join(OUT, f"{name}_{k}.wav")
            write_wav(path, x)
            if spectro:
                os.makedirs(spectro, exist_ok=True)
                spectrogram_png(os.path.join(spectro, f"{name}_{k}.png"), x)
        print(f"{name}: {takes} take(s), {x.shape[-1] / SR:.2f} s, {'stereo' if x.ndim == 2 else 'mono'}")
    write_bank()


def write_bank():
    # the bank (with each sound's payoff time) is build_sfx.py's now
    from build_sfx import write_bank as wb
    wb()


if __name__ == "__main__":
    args = sys.argv[1:]
    spectro = None
    if "--spectro" in args:
        i = args.index("--spectro")
        spectro = args[i + 1]
        del args[i:i + 2]
    render(args or None, spectro)
