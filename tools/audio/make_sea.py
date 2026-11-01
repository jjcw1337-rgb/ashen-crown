"""The sea's sounds, made in code (no recordings or generation service needed): the open sea's swell, surf on
a beach, a splash, gull cries, the hull creaking, water slapping the hull, and Osric's mallet on oak.

    python3 tools/audio/make_sea.py <rawdir>        # writes <rawdir>/<name>_<k>.wav + .json (source, licence)
    python3 tools/audio/build_sfx.py <rawdir>/picks.json   # levels them into assets/audio/sfx and the bank

Everything is filtered noise and modal resonators rather than synth tones: water is noise shaped in time and
spectrum, wood is an impulse ringing through a few damped modes, a gull is a harmonic voice through nasal
formants with a rough edge. Seeds are fixed so a rebuild gives the same files. Replace any of them with a
recording or an ElevenLabs take later under the same name.
"""
import os, sys, json
import numpy as np
from scipy import signal
import soundfile as sf

SR = 32000
OUT = sys.argv[1] if len(sys.argv) > 1 else "sea_raw"
os.makedirs(OUT, exist_ok=True)


def sos_band(lo, hi, order=2):
    if lo <= 0:
        return signal.butter(order, hi, "lowpass", fs=SR, output="sos")
    if hi >= SR / 2:
        return signal.butter(order, lo, "highpass", fs=SR, output="sos")
    return signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos")


def band(x, lo, hi, order=2):
    return signal.sosfilt(sos_band(lo, hi, order), x)


def pink(n, rng):
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    X[1:] /= np.sqrt(f[1:])
    X[0] = 0
    x = np.fft.irfft(X, n)
    return x / (np.abs(x).max() + 1e-9)


def brown(n, rng):
    x = np.cumsum(rng.standard_normal(n))
    x = band(x - x.mean(), 20, 2000)
    return x / (np.abs(x).max() + 1e-9)


def env_ad(n, a, d, at=0, total=None):
    """Attack a seconds then exponential decay d (time constant), starting at sample `at`."""
    total = total or n
    e = np.zeros(total)
    t = np.arange(total - at) / SR
    shape = np.where(t < a, (t / max(a, 1e-4)) ** 2, np.exp(-(t - a) / max(d, 1e-4)))
    e[at:] = shape
    return e


def smooth(x, secs):
    w = max(1, int(secs * SR))
    k = np.hanning(w * 2 + 1)
    return np.convolve(x, k / k.sum(), mode="same")


def resonators(exc, modes):
    """Ring an excitation through damped modes [(freq, decay s, gain)]."""
    y = np.zeros_like(exc)
    for f, d, g in modes:
        r = np.exp(-1.0 / (d * SR))
        w = 2 * np.pi * f / SR
        b = [1 - r]
        a = [1, -2 * r * np.cos(w), r * r]
        y += g * signal.lfilter(b, a, exc)
    return y


def norm(x, peak=0.9):
    return x * peak / (np.abs(x).max() + 1e-9)


def write(name, k, x, what):
    x = np.asarray(x, dtype=np.float32)
    path = os.path.join(OUT, f"{name}_{k}.wav")
    sf.write(path, x.T if x.ndim == 2 else x, SR, subtype="PCM_16")
    json.dump({"source": "Procedural (tools/audio/make_sea.py)", "license": "CC0 1.0 (made for the game)",
               "request": {"text": what}}, open(path[:-4] + ".json", "w"))
    return path


# ------------------------------------------------------------------ beds (stereo loops)
def surf(seed, secs=26.0):
    """Waves breaking on a beach: each one swells, crashes, and hisses back down the sand over the shingle."""
    rng = np.random.default_rng(seed)
    n = int(secs * SR)
    out = np.zeros((2, n))
    # the sea's low roar under everything, slowly breathing
    for c in range(2):
        bed = band(brown(n, rng), 30, 260) * (0.55 + 0.25 * np.sin(2 * np.pi * np.arange(n) / SR / 9.0 + c))
        out[c] += bed * 0.5
    t = rng.uniform(0.3, 1.5)
    while t < secs - 1.0:
        size = rng.uniform(0.6, 1.0)
        pan = rng.uniform(-0.6, 0.6)
        at = int(t * SR)
        L = n - at
        # the swell rising (low, then brighter as it steepens)
        rise = rng.uniform(1.2, 2.0)
        ra = int(rise * SR)
        up = np.zeros(L)
        up[:min(ra, L)] = np.linspace(0, 1, min(ra, L)) ** 2
        tail = np.exp(-np.arange(L) / SR / 0.6)
        swell = np.concatenate([up[:ra], tail[: L - ra]]) if ra < L else up
        lo = band(pink(L, rng), 60, 700) * swell * 0.6
        # the crash: broadband, fast attack, a second or so of thunder
        crash_at = min(ra, L - 1)
        crash = band(pink(L, rng), 120, 7000) * env_ad(L, 0.06, rng.uniform(0.7, 1.1), crash_at) * 1.0
        # the wash: bright hiss running back over the sand, fizzing foam and rattling pebbles
        wash_env = env_ad(L, 0.35, rng.uniform(1.8, 2.8), crash_at + int(0.25 * SR))
        wash = band(rng.standard_normal(L), 1800, 11000) * wash_env * 0.45
        grit = np.zeros(L)
        k = rng.random(L) < (wash_env * 0.004)
        grit[k] = rng.standard_normal(k.sum())
        grit = band(grit, 2500, 9000) * 2.0
        w = (lo + crash + wash + grit) * size
        gl, gr = np.sqrt(0.5 * (1 - pan)), np.sqrt(0.5 * (1 + pan))
        # a touch of width: the right channel a few ms late
        d = int(0.006 * SR)
        out[0, at:] += w * gl
        out[1, at + d:] += w[: L - d] * gr
        t += rng.uniform(6.0, 9.0)
    return norm(out, 0.8)


def sea(seed, secs=24.0):
    """Open water round the boat: the swell's slow heave, wavelets lapping, now and then a whitecap hissing."""
    rng = np.random.default_rng(seed)
    n = int(secs * SR)
    out = np.zeros((2, n))
    tt = np.arange(n) / SR
    for c in range(2):
        heave = 0.6 + 0.4 * np.sin(2 * np.pi * tt / 7.3 + c * 0.7) * np.sin(2 * np.pi * tt / 3.1 + 1.3)
        out[c] += band(brown(n, rng), 40, 420) * heave * 0.55
        out[c] += band(pink(n, rng), 400, 2500) * smooth(np.abs(rng.standard_normal(n)), 0.4) * 0.08
    # wavelets: short, soft laps
    t = 0.1
    while t < secs - 0.8:
        at = int(t * SR)
        L = min(int(1.2 * SR), n - at)
        lap = band(pink(L, rng), rng.uniform(250, 500), rng.uniform(1400, 2600)) * env_ad(L, rng.uniform(0.08, 0.2), rng.uniform(0.15, 0.35))
        pan = rng.uniform(-0.8, 0.8)
        out[0, at:at + L] += lap * 0.35 * np.sqrt(0.5 * (1 - pan))
        out[1, at:at + L] += lap * 0.35 * np.sqrt(0.5 * (1 + pan))
        t += rng.exponential(0.55)
    # whitecaps far off
    t = rng.uniform(1, 4)
    while t < secs - 2.0:
        at = int(t * SR)
        L = min(int(2.5 * SR), n - at)
        cap = band(rng.standard_normal(L), 1500, 6000) * env_ad(L, 0.4, 0.7) * 0.12
        pan = rng.uniform(-0.9, 0.9)
        out[0, at:at + L] += cap * np.sqrt(0.5 * (1 - pan))
        out[1, at:at + L] += cap * np.sqrt(0.5 * (1 + pan))
        t += rng.uniform(3.0, 7.0)
    return norm(out, 0.8)


# ------------------------------------------------------------------ one-shots (mono)
def splash(seed):
    """A fish breaking the surface: a soft plop, a spray of water, droplets falling back."""
    rng = np.random.default_rng(seed)
    n = int(1.1 * SR)
    plop = band(rng.standard_normal(n), 150, 1200) * env_ad(n, 0.004, 0.05) * 0.8
    spray = band(rng.standard_normal(n), 900, 7000) * env_ad(n, 0.01, rng.uniform(0.18, 0.28), int(0.01 * SR)) * 0.9
    drops = np.zeros(n)
    for _ in range(rng.integers(5, 10)):
        at = int(rng.uniform(0.12, 0.75) * SR)
        L = int(0.03 * SR)
        f = rng.uniform(1500, 3800)
        ch = np.sin(2 * np.pi * np.cumsum(np.linspace(f, f * 1.6, L)) / SR) * np.exp(-np.arange(L) / (0.006 * SR))
        drops[at:at + L] += ch * rng.uniform(0.08, 0.2)
    drops = band(drops + band(rng.standard_normal(n), 3000, 9000) * 0.0, 1000, 9000)
    return norm(plop + spray + drops)


def gull(seed):
    """A herring gull's call, two to four cries: a rising 'kee' falling to 'ow', nasal and rough."""
    rng = np.random.default_rng(seed)
    calls = rng.integers(2, 5)
    parts = []
    base = rng.uniform(0.9, 1.1)
    for i in range(calls):
        dur = rng.uniform(0.28, 0.42) * (1.0 if i == 0 else rng.uniform(0.75, 1.0))
        L = int(dur * SR)
        x = np.linspace(0, 1, L)
        # pitch: up quickly, hold, slide down
        f0 = base * (780 + 650 * np.clip(x / 0.25, 0, 1) - 520 * np.clip((x - 0.45) / 0.55, 0, 1) ** 1.4)
        # a real throat: the pitch wanders (jitter), each cycle's strength wavers (shimmer), and the cry
        # breaks into roughness (period doubling) as it falls
        f0 *= 1 + 0.012 * np.sin(2 * np.pi * 22 * np.arange(L) / SR) + 0.02 * smooth(rng.standard_normal(L), 0.004) * 6
        ph = 2 * np.pi * np.cumsum(f0) / SR
        v = np.zeros(L)
        tilt = 0.7 + 0.5 * x
        for h in range(1, 16):
            wob = 1 + 0.35 * smooth(rng.standard_normal(L), 0.01) * 5
            v += np.sin(h * ph + rng.uniform(0, 6.3)) * wob / h ** tilt
        v *= 1 + 0.45 * np.sin(ph / 2) * np.clip((x - 0.35) / 0.4, 0, 1)
        v *= 1 + 0.25 * smooth(rng.standard_normal(L), 0.003) * 6
        nasal = band(v, 1400, 2700, 2) * 1.0 + band(v, 2900, 4300, 2) * 0.55 + band(v, 600, 1100, 1) * 0.25
        e = np.minimum(1, x / 0.05) * np.minimum(1, (1 - x) / 0.25) ** 1.5
        breath = band(rng.standard_normal(L), 1500, 6500) * 0.22 * e
        parts.append((nasal + breath) * e * (1.0 if i == 0 else rng.uniform(0.6, 0.9)))
        parts.append(np.zeros(int(rng.uniform(0.09, 0.22) * SR)))
    y = np.concatenate(parts)
    # heard from a little way off: soften the top, a short airy tail
    y = band(y, 300, 7000, 2)
    tail = np.convolve(y, np.exp(-np.arange(int(0.12 * SR)) / (0.04 * SR)) * 0.25, mode="full")[: y.size]
    return norm(y + tail)


def hull_creak(seed):
    """Planks and the mast step working against each other in a seaway: a slow stick-slip creak."""
    rng = np.random.default_rng(seed)
    dur = rng.uniform(0.7, 1.3)
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    rate = 35 + 140 * np.sin(np.pi * x) ** 1.5 * rng.uniform(0.7, 1.2)
    rate *= 1 + 0.15 * smooth(rng.standard_normal(n), 0.03) * 8
    ph = np.cumsum(rate / SR)
    exc = np.zeros(n)
    ticks = np.where(np.diff(np.floor(ph)) > 0)[0]
    exc[ticks] = rng.uniform(0.6, 1.0, ticks.size)
    exc += rng.standard_normal(n) * 0.02
    k = rng.uniform(0.92, 1.08)
    # short-lived modes: each slip is a dry tick, the rate of ticks is the creak's pitch
    y = resonators(exc, [(240 * k, 0.018, 1.0), (530 * k, 0.014, 0.8), (1010 * k, 0.01, 0.55), (1720 * k, 0.007, 0.35)])
    y += band(exc, 600, 4000) * 0.15
    y *= np.sin(np.pi * x) ** 0.7
    return norm(band(y, 120, 5000))


def hull_slap(seed):
    """The bow dropping into a wave: a hollow thump on the planks and the water thrown off it."""
    rng = np.random.default_rng(seed)
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * rng.uniform(70, 95) * t) * np.exp(-t / 0.09) * 0.7
    body = resonators(env_ad(n, 0.003, 0.01) * rng.standard_normal(n), [(180, 0.08, 1.0), (410, 0.05, 0.5)]) * 0.5
    water = band(pink(n, rng), 200, 2400) * env_ad(n, 0.01, 0.16) * 0.8
    spray = band(rng.standard_normal(n), 1500, 7000) * env_ad(n, 0.05, 0.22, int(0.05 * SR)) * 0.35
    return norm(thump + body + water + spray)


def mallet(seed):
    """A wooden mallet driving a trenail into an oak plank: a short, dry knock with a bit of ring."""
    rng = np.random.default_rng(seed)
    n = int(0.45 * SR)
    exc = np.zeros(n)
    L = int(0.003 * SR)
    exc[:L] = rng.standard_normal(L) * np.hanning(L)
    k = rng.uniform(0.93, 1.07)
    y = resonators(exc, [(185 * k, 0.07, 0.9), (420 * k, 0.06, 1.0), (930 * k, 0.04, 0.7), (1620 * k, 0.025, 0.45),
                         (2550 * k, 0.015, 0.3)])
    click = band(exc, 2000, 9000) * 0.6
    return norm(y + click)


SOUNDS = [
    ("surf", surf, 2, "surf breaking on a beach: swell, crash, wash back over sand and shingle (loop)"),
    ("sea", sea, 1, "open water round a small boat: the swell's heave, lapping wavelets, far whitecaps (loop)"),
    ("splash", splash, 3, "a fish breaking the surface: plop, spray, droplets"),
    ("gull", gull, 4, "herring gull cries, two to four calls"),
    ("hull_creak", hull_creak, 4, "a small wooden boat's planks creaking in a seaway"),
    ("hull_slap", hull_slap, 3, "the bow dropping into a wave: a hollow thump and spray"),
    ("mallet", mallet, 4, "a wooden mallet knocking into an oak plank"),
]

if __name__ == "__main__":
    picks = {}
    for name, fn, takes, what in SOUNDS:
        picks[name] = [write(name, k, fn(1000 + 37 * k + sum(map(ord, name))), what)
                       for k in range(takes)]
        print(name, takes)
    json.dump(picks, open(os.path.join(OUT, "picks.json"), "w"), indent=1)
    print("picks:", os.path.join(OUT, "picks.json"))
