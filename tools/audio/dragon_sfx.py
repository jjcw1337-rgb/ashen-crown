"""Builds the three dragon classes' sounds (Obsidian Wyrm, Frost Serpent, Storm Wyvern) from the game's own
recordings: each is a layered, pitched and filtered mix of takes already in assets/audio/sfx/ (Kenney CC0 and
ElevenLabs generations, see assets/audio/CREDITS.md), so no new source material is needed.

    python3 tools/audio/dragon_sfx.py          # writes assets/audio/sfx/<name>_0.wav and updates sfx_bank.gd

Every sound is mono 32 kHz 16-bit like the rest of the bank. Loudness is matched to a reference sound of the
same kind (roars to `roar`, footfalls to `slam` lowered, swings to `swing_heavy`, wing beats to `birds_flutter`).
Rerun after changing a recipe; then `godot --headless --editor --quit` to import. Replace any of them with an
ElevenLabs take later through tools/audio/spec.py + build_sfx.py (same names), and drop it from RECIPES here.
"""
import os, re, wave
import numpy as np
from scipy.signal import butter, sosfilt

SR = 32000
ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
BANK = os.path.join(ROOT, "scripts", "sfx_bank.gd")
CREDITS = os.path.join(ROOT, "assets", "audio", "CREDITS.md")


def load(name):
    w = wave.open(os.path.join(SFX, name + ".wav"))
    n, ch = w.getnframes(), w.getnchannels()
    x = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64) / 32768.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return x


def pitch(x, k):
    """Resample: k < 1 lower and longer, k > 1 higher and shorter (like a tape)."""
    n = int(len(x) / k)
    return np.interp(np.arange(n) * k, np.arange(len(x)), x)


def filt(x, kind, f, order=4):
    sos = butter(order, f, btype=kind, fs=SR, output="sos")
    return sosfilt(sos, x)


def fade(x, a=0.005, b=0.08):
    x = x.copy()
    na, nb = int(a * SR), int(b * SR)
    if na:
        x[:na] *= np.linspace(0, 1, na)
    if nb and nb < len(x):
        x[-nb:] *= np.linspace(1, 0, nb) ** 2
    return x


def trim(x, start=0.0, dur=None):
    s = int(start * SR)
    e = len(x) if dur is None else min(len(x), s + int(dur * SR))
    return x[s:e]


def mix(*layers):
    """layers: (signal, offset seconds, gain)"""
    n = max(int(o * SR) + len(s) for s, o, g in layers)
    out = np.zeros(n)
    for s, o, g in layers:
        i = int(o * SR)
        out[i:i + len(s)] += s * g
    return out


def rms(x):
    return float(np.sqrt(np.mean(x ** 2)) + 1e-12)


def loud_rms(x):
    """RMS over the loudest 40% of 20 ms windows (ignores silent tails)."""
    w = int(0.02 * SR)
    if len(x) < w * 2:
        return rms(x)
    frames = x[: len(x) // w * w].reshape(-1, w)
    r = np.sqrt((frames ** 2).mean(axis=1))
    r = np.sort(r)[::-1]
    return float(np.sqrt(np.mean(r[: max(1, int(len(r) * 0.4))] ** 2)) + 1e-12)


def match(x, ref, db=0.0):
    y = x * (loud_rms(load(ref + "_0")) / loud_rms(x)) * 10 ** (db / 20.0)
    peak = np.max(np.abs(y))
    if peak > 0.97:          # soft ceiling, then a hard limit
        y = y / peak * 0.97
    return y


def hit_of(x):
    """Seconds to the loudest 10 ms (the payoff Sfx.play_synced lands on the impact frame)."""
    w = int(0.01 * SR)
    frames = np.abs(x[: len(x) // w * w]).reshape(-1, w).max(axis=1)
    return round(float(np.argmax(frames)) * 0.01, 2)


def save(name, x):
    y = np.clip(x, -1.0, 1.0)
    path = os.path.join(SFX, name + "_0.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y * 32767.0).astype(np.int16).tobytes())
    return path


# ---------------------------------------------------------------- recipes
def wyrm():
    roar = mix((filt(pitch(load("lion_roar_1"), 0.62), "lowpass", 2600), 0.0, 1.0),
               (filt(pitch(load("roar_0"), 0.7), "lowpass", 1800), 0.05, 0.7),
               (filt(pitch(load("fire_erupt_0"), 0.75), "lowpass", 3000), 0.18, 0.45))
    step = mix((filt(pitch(trim(load("slam_0"), 0, 0.45), 0.7), "lowpass", 380), 0.0, 1.0),
               (filt(pitch(trim(load("charge_impact_0"), 0, 0.35), 0.6), "lowpass", 300), 0.0, 0.5))
    claw = mix((pitch(load("hellclaw_0"), 0.8), 0.0, 1.0), (pitch(load("swing_heavy_0"), 0.78), 0.0, 0.7),
               (filt(pitch(load("fire_erupt_0"), 1.1), "highpass", 900), 0.12, 0.18))
    bite = mix((pitch(trim(load("growl_0"), 0, 0.6), 0.72), 0.0, 0.8), (pitch(load("impact_bone_0"), 0.7), 0.28, 1.0),
               (pitch(load("swing_light_0"), 0.75), 0.12, 0.5))
    tail = mix((pitch(load("cleave_swing_0"), 0.62), 0.0, 1.0), (pitch(load("swing_heavy_0"), 0.55), 0.18, 0.8),
               (filt(pitch(trim(load("slam_0"), 0, 0.5), 0.8), "lowpass", 600), 0.5, 0.35))
    death = mix((pitch(load("death_demon_0"), 0.74), 0.0, 1.0), (filt(pitch(load("boss_die_0"), 0.85), "lowpass", 2400), 0.15, 0.5))
    return {
        "wyrm_roar": (match(fade(roar, 0.005, 0.5), "roar", -1.0), "sfx"),
        "wyrm_step": (match(fade(step, 0.002, 0.15), "slam", -14.0), "sfx"),
        "wyrm_claw": (match(fade(claw), "hellclaw", -1.0), "sfx"),
        "wyrm_bite": (match(fade(bite), "hellclaw", -1.0), "sfx"),
        "wyrm_tail": (match(fade(tail, 0.005, 0.25), "swing_heavy", 0.0), "sfx"),
        "death_wyrm": (match(fade(death, 0.005, 0.6), "death_demon", 0.0), "sfx"),
    }


def serpent():
    roar = mix((filt(pitch(load("lion_roar_0"), 0.82), "lowpass", 3800), 0.0, 1.0),
               (filt(pitch(load("wail_0"), 0.7), "bandpass", [300, 2500]), 0.1, 0.55),
               (filt(load("ice_shatter_0"), "highpass", 2500), 0.45, 0.25),
               (filt(trim(load("wind_0"), 1.0, 1.6), "bandpass", [600, 3000]), 0.0, 0.35))
    rng = np.random.default_rng(7)
    sl = filt(rng.uniform(-1, 1, int(0.42 * SR)), "bandpass", [1200, 5200])           # scales hissing over the ground
    sl *= np.sin(np.linspace(0, np.pi, len(sl))) ** 1.5
    step = mix((sl, 0.0, 0.5), (filt(pitch(trim(load("slam_0"), 0, 0.35), 0.95), "lowpass", 500), 0.02, 0.6))
    claw = mix((pitch(load("reap_swing_0"), 0.92), 0.0, 1.0), (filt(pitch(load("ice_shatter_0"), 1.15), "highpass", 1800), 0.16, 0.45))
    bite = mix((pitch(trim(load("growl_0"), 0, 0.5), 1.05), 0.0, 0.6), (pitch(load("impact_bone_0"), 0.95), 0.22, 1.0),
               (filt(pitch(load("ice_shatter_0"), 1.3), "highpass", 2500), 0.22, 0.35))
    tail = mix((pitch(load("cleave_swing_0"), 0.78), 0.0, 1.0), (filt(trim(load("wind_0"), 3.0, 0.9), "bandpass", [500, 4000]), 0.05, 0.6),
               (filt(load("ice_shatter_1"), "highpass", 1500), 0.5, 0.35))
    death = mix((pitch(load("death_wraith_0"), 0.8), 0.0, 1.0), (pitch(load("lion_roar_1"), 0.8), 0.0, 0.35),
                (filt(load("ice_shatter_0"), "highpass", 1200), 0.9, 0.5))
    return {
        "serpent_roar": (match(fade(roar, 0.005, 0.5), "roar", -2.0), "sfx"),
        "serpent_step": (match(fade(step, 0.01, 0.12), "slam", -18.0), "sfx"),
        "serpent_claw": (match(fade(claw), "hellclaw", -1.0), "sfx"),
        "serpent_bite": (match(fade(bite), "hellclaw", -1.0), "sfx"),
        "serpent_tail": (match(fade(tail, 0.005, 0.25), "swing_heavy", 0.0), "sfx"),
        "death_serpent": (match(fade(death, 0.005, 0.6), "death_demon", 0.0), "sfx"),
    }


def wyvern():
    roar = mix((filt(pitch(load("lion_roar_1"), 1.05), "lowpass", 4500), 0.0, 1.0),
               (filt(pitch(load("roar_0"), 0.9), "lowpass", 2500), 0.0, 0.45),
               (filt(pitch(load("thunder_strike_0"), 0.85), "lowpass", 1500), 0.35, 0.5))
    step = mix((filt(pitch(trim(load("slam_0"), 0, 0.4), 0.85), "lowpass", 450), 0.0, 1.0),
               (pitch(trim(load("impact_bone_0"), 0, 0.2), 0.6), 0.0, 0.25))
    flap = mix((filt(pitch(trim(load("birds_flutter_1"), 0.2, 0.9), 0.45), "lowpass", 1400), 0.0, 1.0),
               (filt(pitch(trim(load("swing_heavy_0"), 0, 0.5), 0.5), "lowpass", 900), 0.0, 0.55))
    claw = mix((pitch(load("swing_heavy_0"), 0.9), 0.0, 1.0), (pitch(load("hellclaw_0"), 1.0), 0.05, 0.6),
               (filt(pitch(trim(load("thunder_strike_1"), 0, 0.5), 1.4), "highpass", 1500), 0.14, 0.3))
    bite = mix((pitch(trim(load("growl_0"), 0, 0.55), 0.9), 0.0, 0.7), (pitch(load("impact_bone_0"), 0.85), 0.25, 1.0),
               (pitch(load("swing_light_0"), 0.9), 0.1, 0.45))
    tail = mix((pitch(load("cleave_swing_0"), 0.72), 0.0, 1.0), (filt(pitch(load("thunder_strike_0"), 1.2), "highpass", 1200), 0.42, 0.3),
               (pitch(load("swing_heavy_0"), 0.65), 0.2, 0.6))
    death = mix((pitch(load("death_demon_0"), 0.95), 0.0, 1.0), (pitch(load("lion_roar_0"), 0.95), 0.0, 0.4),
                (filt(pitch(load("thunder_strike_1"), 0.7), "lowpass", 1200), 0.6, 0.45))
    return {
        "wyvern_roar": (match(fade(roar, 0.005, 0.5), "roar", -1.0), "sfx"),
        "wyvern_step": (match(fade(step, 0.002, 0.12), "slam", -15.0), "sfx"),
        "wyvern_flap": (match(fade(flap, 0.01, 0.2), "birds_flutter", 1.0), "sfx"),
        "wyvern_claw": (match(fade(claw), "hellclaw", -1.0), "sfx"),
        "wyvern_bite": (match(fade(bite), "hellclaw", -1.0), "sfx"),
        "wyvern_tail": (match(fade(tail, 0.005, 0.25), "swing_heavy", 0.0), "sfx"),
        "death_wyvern": (match(fade(death, 0.005, 0.6), "death_demon", 0.0), "sfx"),
    }


SYNCED = ("_claw", "_bite", "_tail")


def main():
    made = {}
    for f in (wyrm, serpent, wyvern):
        for name, (x, bus) in f().items():
            save(name, x)
            hit = hit_of(x) if name.endswith(SYNCED) else 0.0
            made[name] = (bus, hit, len(x) / SR)
    # sfx_bank.gd: replace or add each entry, keep the rest as build_sfx.py wrote it
    src = open(BANK).read()
    for name, (bus, hit, _) in sorted(made.items()):
        line = f'\t"{name}": [1, "{bus}", {hit}],'
        pat = re.compile(r'^\t"' + re.escape(name) + r'": \[.*\],$', re.M)
        if pat.search(src):
            src = pat.sub(line, src)
        else:
            src = src.replace("\n}", "\n" + line + "\n}", 1) if src.rstrip().endswith("}") else src + line + "\n"
    open(BANK, "w").write(src)
    # CREDITS.md: one note for the derived set
    note = "\n## Dragon sounds (tools/audio/dragon_sfx.py)\n\nDerived from recordings already listed above (lion_roar, roar, fire_erupt, slam, charge_impact, hellclaw, swing_heavy, swing_light, growl, impact_bone, cleave_swing, death_demon, death_wraith, boss_die, wail, wind, ice_shatter, thunder_strike, birds_flutter, reap_swing) by pitching, filtering and layering; same licences as their sources. Files: " + ", ".join(f"`{n}_0.wav`" for n in sorted(made)) + ".\n"
    cr = open(CREDITS).read() if os.path.exists(CREDITS) else ""
    cr = re.sub(r"\n## Dragon sounds \(tools/audio/dragon_sfx.py\)\n.*?(?=\n## |\Z)", "", cr, flags=re.S)
    open(CREDITS, "w").write(cr.rstrip() + "\n" + note)
    for n, (bus, hit, d) in sorted(made.items()):
        print(f"{n:16s} {d:5.2f}s  hit {hit}")


if __name__ == "__main__":
    main()
