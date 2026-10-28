"""Small numpy DSP kit for Ashen Crown's offline sound renderer (make_sfx.py).

Everything works on float64 numpy arrays at SR. Filtering is done in the frequency domain (whole-signal
FFT for fixed filters, short-time FFT for filters that move), so nothing needs scipy. Runs under any
python3 with numpy; Blender's bundled python works:
    /Applications/Blender.app/Contents/Resources/4.5/python/bin/python3.11 tools/audio/make_sfx.py
"""
import numpy as np
import wave, struct, zlib

SR = 32000


def n_of(dur):
    return max(1, int(round(dur * SR)))


def t_axis(n):
    return np.arange(n) / SR


# ---------------------------------------------------------------- sources
def white(n, rng):
    return rng.uniform(-1.0, 1.0, n)


def pink(n, rng):
    x = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1] if n > 1 else 1.0
    x /= np.sqrt(f)
    y = np.fft.irfft(x, n)
    return y / (np.max(np.abs(y)) + 1e-9)


def brown(n, rng):
    y = np.cumsum(rng.standard_normal(n))
    y = highpass(y - y.mean(), 20.0)
    return y / (np.max(np.abs(y)) + 1e-9)


def phase_of(freq):
    """Phase (radians) of an oscillator whose frequency is a constant or a per-sample array."""
    f = np.asarray(freq, dtype=float)
    return 2.0 * np.pi * np.cumsum(f) / SR


def sine(freq, n=None):
    if np.ndim(freq) == 0:
        return np.sin(2.0 * np.pi * freq * t_axis(n))
    return np.sin(phase_of(freq))


def saw(freq, n=None, harmonics=48):
    """Band-limited sawtooth (additive), frequency constant or per sample."""
    f = np.full(n, float(freq)) if np.ndim(freq) == 0 else np.asarray(freq, dtype=float)
    ph = phase_of(f)
    out = np.zeros(len(f))
    for k in range(1, harmonics + 1):
        mask = (k * f) < (SR * 0.45)
        if not mask.any():
            break
        out += np.sin(k * ph) / k * mask
    return out * (2.0 / np.pi)


def square(freq, n=None, harmonics=31):
    f = np.full(n, float(freq)) if np.ndim(freq) == 0 else np.asarray(freq, dtype=float)
    ph = phase_of(f)
    out = np.zeros(len(f))
    for k in range(1, harmonics + 1, 2):
        mask = (k * f) < (SR * 0.45)
        out += np.sin(k * ph) / k * mask
    return out * (4.0 / np.pi)


def fm(carrier, mod_ratio, index, n):
    """Two-operator FM: index may be a per-sample array (brightness envelope)."""
    t = t_axis(n)
    idx = np.full(n, float(index)) if np.ndim(index) == 0 else index
    car = np.full(n, float(carrier)) if np.ndim(carrier) == 0 else carrier
    mod = np.sin(phase_of(car * mod_ratio))
    return np.sin(phase_of(car) + idx * mod)


def partials(n, freqs, decays, amps=None, rng=None, detune=0.0):
    """Sum of decaying sines: bells, metal, glass. decays in 1/s."""
    t = t_axis(n)
    out = np.zeros(n)
    amps = amps if amps is not None else [1.0 / (i + 1) for i in range(len(freqs))]
    for f, d, a in zip(freqs, decays, amps):
        if rng is not None and detune:
            f = f * (1.0 + rng.uniform(-detune, detune))
        out += a * np.sin(2.0 * np.pi * f * t + (rng.uniform(0, 6.28) if rng is not None else 0.0)) * np.exp(-t * d)
    return out


def crackle(n, rng, density, decay=900.0, bright=4000.0):
    """Sparse random clicks (fire, embers, gravel): density in clicks per second (constant or array)."""
    dens = np.full(n, float(density)) if np.ndim(density) == 0 else density
    hits = rng.uniform(0, 1, n) < dens / SR
    imp = np.zeros(n)
    imp[hits] = rng.uniform(0.3, 1.0, hits.sum()) * rng.choice([-1, 1], hits.sum())
    k = np.exp(-np.arange(int(SR * 0.01)) / SR * decay)
    out = np.convolve(imp, k)[:n]
    return highpass(out, bright * 0.25)


# ---------------------------------------------------------------- envelopes
def env_exp(n, decay, attack=0.002):
    t = t_axis(n)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-t * decay)


def env_ad(n, attack, release, curve=2.0):
    t = t_axis(n)
    dur = n / SR
    up = np.clip(t / max(attack, 1e-5), 0, 1) ** curve
    down = np.clip((dur - t) / max(release, 1e-5), 0, 1) ** curve
    return np.minimum(up, down)


def env_points(n, pts):
    """Piecewise-linear envelope from [(time s, value), ...]."""
    t = t_axis(n)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return np.interp(t, xs, ys)


def swell(n, peak_at, rise=2.0, fall=3.0):
    """Rises to 1 at peak_at (fraction), then falls: a whoosh's loudness."""
    u = np.linspace(0, 1, n)
    up = np.clip(u / peak_at, 0, 1) ** rise
    down = np.clip((1 - u) / (1 - peak_at), 0, 1) ** fall
    return np.where(u < peak_at, up, down)


def fade(x, a=0.003, b=0.02):
    n = len(x)
    na, nb = min(n, n_of(a)), min(n, n_of(b))
    y = x.copy()
    if na > 0:
        y[:na] *= np.linspace(0, 1, na)
    if nb > 0:
        y[-nb:] *= np.linspace(1, 0, nb)
    return y


# ---------------------------------------------------------------- filters
def _resp(x, H):
    X = np.fft.rfft(x)
    return np.fft.irfft(X * H, len(x))


def _freqs(n):
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = 1e-3
    return f


def lowpass(x, fc, order=2):
    f = _freqs(len(x))
    return _resp(x, 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    f = _freqs(len(x))
    return _resp(x, 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order)))


def bandpass(x, fc, octaves=1.0):
    f = _freqs(len(x))
    H = np.exp(-((np.log2(f / fc)) / (octaves * 0.6)) ** 2)
    return _resp(x, H)


def peaks(x, centres, widths, gains):
    """Several resonances at once (formants, body resonance)."""
    f = _freqs(len(x))
    H = np.zeros_like(f)
    for c, w, g in zip(centres, widths, gains):
        H += g * np.exp(-((np.log2(f / c)) / (w * 0.6)) ** 2)
    return _resp(x, H)


def stft_filter(x, gain_fn, frame=1024, hop=256):
    """Time-varying filter: gain_fn(freqs, t_seconds) -> gains per bin for each frame (overlap-add)."""
    n = len(x)
    pad = np.concatenate([np.zeros(frame), x, np.zeros(frame)])
    win = np.hanning(frame)
    out = np.zeros(len(pad))
    norm = np.zeros(len(pad))
    f = np.fft.rfftfreq(frame, 1.0 / SR)
    f[0] = 1e-3
    for s in range(0, len(pad) - frame, hop):
        seg = pad[s:s + frame] * win
        tc = (s + frame / 2 - frame) / SR
        G = gain_fn(f, tc)
        out[s:s + frame] += np.fft.irfft(np.fft.rfft(seg) * G, frame) * win
        norm[s:s + frame] += win ** 2
    out /= np.maximum(norm, 1e-6)
    return out[frame:frame + n]


def sweep_lp(x, fc_start, fc_end, order=2, curve=1.0):
    dur = len(x) / SR
    def g(f, t):
        u = np.clip(t / max(dur, 1e-6), 0, 1) ** curve
        fc = fc_start * (fc_end / fc_start) ** u
        return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))
    return stft_filter(x, g)


def sweep_bp(x, fc_start, fc_end, octaves=1.0, curve=1.0):
    dur = len(x) / SR
    def g(f, t):
        u = np.clip(t / max(dur, 1e-6), 0, 1) ** curve
        fc = fc_start * (fc_end / fc_start) ** u
        return np.exp(-((np.log2(f / fc)) / (octaves * 0.6)) ** 2)
    return stft_filter(x, g)


# vowel formants (F1, F2, F3) for a gruff male voice; a higher voice scales them
VOWELS = {"a": (730, 1090, 2440), "o": (570, 840, 2410), "u": (300, 870, 2240), "e": (530, 1840, 2480),
          "i": (270, 2290, 3010), "aa": (850, 1220, 2810)}


def voice(n, f0, vowel_path, rng, breath=0.25, scale=1.0, rough=0.0):
    """A sung/shouted vowel: band-limited buzz through moving formants. f0 constant or array;
    vowel_path [(time fraction, vowel), ...]."""
    f0a = np.full(n, float(f0)) if np.ndim(f0) == 0 else f0
    if rough:
        f0a = f0a * (1.0 + rough * lowpass(rng.standard_normal(n), 30.0) * 0.5)
    src = saw(f0a, harmonics=60) + breath * white(n, rng)
    dur = n / SR
    keys = sorted(vowel_path)
    def g(f, t):
        u = t / dur
        a, b = keys[0], keys[-1]
        for i in range(len(keys) - 1):
            if keys[i][0] <= u <= keys[i + 1][0]:
                a, b = keys[i], keys[i + 1]
                break
        w = 0.0 if b[0] == a[0] else np.clip((u - a[0]) / (b[0] - a[0]), 0, 1)
        fa, fb = VOWELS[a[1]], VOWELS[b[1]]
        G = np.zeros_like(f)
        for k, (ga) in enumerate((1.0, 0.7, 0.35)):
            c = (fa[k] * (1 - w) + fb[k] * w) * scale
            G += ga * np.exp(-((np.log2(f / c)) / 0.18) ** 2)
        return G + 0.02
    return stft_filter(src, g)


# ---------------------------------------------------------------- shaping, space
def saturate(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def pitch_down_resample(x, ratio):
    """Plays x at a different speed (ratio < 1 slows and lowers it)."""
    n_out = int(len(x) / ratio)
    src = np.arange(n_out) * ratio
    return np.interp(src, np.arange(len(x)), x)


def reverse(x):
    return x[::-1].copy()


def reverb_ir(dur, rng, damp=6000.0, decay=3.0, stereo=False, predelay=0.01):
    n = n_of(dur)
    t = t_axis(n)
    chans = []
    for c in range(2 if stereo else 1):
        e = rng.standard_normal(n) * np.exp(-t * decay)
        # high frequencies die faster: a lowpass that closes over the tail
        e = stft_filter(e, lambda f, tt: 1.0 / np.sqrt(1.0 + (f / (damp * np.exp(-tt * 1.5) + 300.0)) ** 4), 512, 128)
        e = np.concatenate([np.zeros(n_of(predelay)), e])
        chans.append(e / np.sqrt(np.sum(e ** 2) + 1e-9))
    return chans


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    m = 1 << int(np.ceil(np.log2(n)))
    y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:n]
    return y


def space(x, rng, size=1.2, mix=0.25, damp=6000.0, stereo=False):
    """Dry plus a convolution tail of `size` seconds."""
    irs = reverb_ir(size, rng, damp, 4.0 / size, stereo)
    tails = [convolve(x, ir) for ir in irs]
    n = len(tails[0])
    dry = np.concatenate([x, np.zeros(n - len(x))])
    if stereo:
        return np.stack([dry * (1 - mix * 0.5) + tails[0] * mix, dry * (1 - mix * 0.5) + tails[1] * mix])
    return dry * (1 - mix * 0.5) + tails[0] * mix


def place(parts, n=None):
    """Mix [(signal, start seconds, gain), ...] into one buffer."""
    end = max(n_of(s) + len(x) for x, s, g in parts)
    out = np.zeros(max(end, n or 0))
    for x, s, g in parts:
        i = n_of(s) if s > 0 else 0
        out[i:i + len(x)] += x * g
    return out


def trim_silence(x, thresh=0.0008):
    a = np.abs(x) if x.ndim == 1 else np.max(np.abs(x), axis=0)
    idx = np.where(a > thresh)[0]
    if len(idx) == 0:
        return x
    end = min(len(a), idx[-1] + n_of(0.02))
    return x[..., :end]


def normalize(x, peak=0.9, rms_db=None):
    a = np.max(np.abs(x)) + 1e-9
    y = x / a * peak
    if rms_db is not None:
        r = np.sqrt(np.mean(y ** 2)) + 1e-9
        want = 10 ** (rms_db / 20.0)
        y = y * min(want / r, peak / (np.max(np.abs(y)) + 1e-9))
    return y


# ---------------------------------------------------------------- files
def write_wav(path, x):
    x = np.clip(x, -1.0, 1.0)
    stereo = x.ndim == 2
    data = (x.T if stereo else x)
    pcm = (data * 32000.0).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)


def write_png(path, rgb):
    """rgb: HxWx3 uint8."""
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def spectrogram_png(path, x, width=420, height=200, top_hz=16000):
    """A log-frequency spectrogram (top) over the waveform (bottom strip), 1 second = width px if shorter."""
    if x.ndim == 2:
        x = x.mean(axis=0)
    frame, hop = 1024, max(32, len(x) // width)
    cols = []
    for s in range(0, max(1, len(x) - frame), hop):
        seg = x[s:s + frame]
        if len(seg) < frame:
            seg = np.pad(seg, (0, frame - len(seg)))
        cols.append(np.abs(np.fft.rfft(seg * np.hanning(frame))))
    S = np.array(cols).T if cols else np.zeros((frame // 2 + 1, 1))
    f = np.fft.rfftfreq(frame, 1.0 / SR)
    rows = np.geomspace(40, top_hz, height)
    idx = np.clip(np.searchsorted(f, rows), 0, len(f) - 1)
    img = 20 * np.log10(S[idx][::-1] + 1e-6)
    img = np.clip((img + 30) / 70.0, 0, 1)
    # stretch to width
    xs = np.linspace(0, img.shape[1] - 1, width).astype(int)
    img = img[:, xs]
    rgb = np.stack([img ** 0.7, img ** 1.4, img ** 3.0 * 0.6 + img * 0.2], -1)
    wave_h = 60
    wv = np.zeros((wave_h, width, 3))
    env = np.array([np.max(np.abs(x[int(i * len(x) / width):int((i + 1) * len(x) / width) + 1])) for i in range(width)])
    for i, e in enumerate(env):
        h = int(e * (wave_h / 2 - 1))
        wv[wave_h // 2 - h:wave_h // 2 + h + 1, i] = (0.9, 0.6, 0.3)
    out = (np.concatenate([rgb, wv], 0) * 255).astype(np.uint8)
    write_png(path, out)
