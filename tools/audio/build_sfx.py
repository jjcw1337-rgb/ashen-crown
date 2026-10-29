"""Turns the chosen recorded/generated candidates into the game's sounds: assets/audio/sfx/<name>_<take>.wav,
scripts/sfx_bank.gd and assets/audio/CREDITS.md (the source and license of every file).

    python build_sfx.py picks.json            # {"impact_flesh": ["/path/cand3.mp3", ...], ...}
    python build_sfx.py --kenney              # just the spec's Kenney sounds (all matching files become takes)
    python build_sfx.py --bank                # only rewrite scripts/sfx_bank.gd from the files on disk

Each take is decoded, trimmed of leading silence, shifted so its loudest moment lands `hit` seconds in (spells
the game starts at the cast and whose payoff belongs on the impact frame), cut where it has died away, faded,
loudness-matched by its loudest 100 ms (per category) and written at 32 kHz (imported as QOA). Positional and
small sounds are mono; big spells, loops and ambience keep their stereo.
Needs librosa + soundfile (the score.py venv); mp3 decoding comes from libsndfile.
"""
import os, sys, json, glob, re
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from spec import SPEC, BY_NAME

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "../.."))
OUT = os.path.join(ROOT, "assets/audio/sfx")
BANK_GD = os.path.join(ROOT, "scripts/sfx_bank.gd")
CREDITS = os.path.join(ROOT, "assets/audio/CREDITS.md")
LIB = os.path.expanduser("~/Documents/Game Factory Audio")
SR = 32000

STEREO = {"music_town", "crowd_roar", "crowd_cheer", "arena_horn", "holy_nova", "wail", "covenant", "host_summon", "summon_demon", "phase_in", "phase_erupt", "blood_pact",
          "battle_cry", "levelup", "portal", "wind", "drip", "drain_loop", "boss_die", "roar"}
UI = {"click", "deny", "gold", "coins", "pickup", "equip", "drop", "potion", "levelup", "portal"}
AMB = {"wind", "drip", "grubb_mutter"}
# dB for the loudest 100 ms: hits and voices sit under the big payoffs, UI and loops well under
LOUD = {"ui": -20.0, "amb": -26.0, "music": -24.0, "loop": -22.0, "small": -17.0, "big": -14.0, "default": -16.0}
SMALL = {"hero_hit", "swing_light", "swing_heavy", "swing", "spirit_dart", "drain_tick", "hurt_knight", "hurt_gnome", "hurt_wraith",
         "hurt_demon", "hurt", "soul_return", "shade_out", "bow"}
BIG = {"arena_horn", "crowd_cheer", "lion_roar", "holy_nova", "phase_erupt", "charge_impact", "boom", "roar", "boss_die", "summon_demon", "covenant", "wail", "crit_sting"}


def category(name):
    if name.startswith("music_"): return "music"
    if name in UI: return "ui"
    if name in AMB: return "amb"
    if BY_NAME.get(name, {}).get("loop"): return "loop"
    if name in SMALL: return "small"
    if name in BIG: return "big"
    return "default"


def load(path, stereo):
    import librosa
    x, _ = librosa.load(path, sr=SR, mono=not stereo)
    return x if x.ndim == 2 else x[None, :]


def loudest(x, win=0.1):
    p = (x ** 2).mean(axis=0)
    w = int(win * SR)
    if p.size <= w:
        return 10 * np.log10(p.mean() + 1e-12), 0
    c = np.concatenate([[0.0], np.cumsum(p)])
    e = (c[w:] - c[:-w]) / w
    i = int(np.argmax(e))
    return 10 * np.log10(e[i] + 1e-12), i


def shape(x, name):
    s = BY_NAME.get(name, {})
    loop = bool(s.get("loop"))
    if loop and x.shape[1] > 8 * SR:
        # a long loop (music, beds) wraps seamlessly: its last 3 s fade into its first 3 s
        n = int(3.0 * SR)
        ramp = np.sin(np.linspace(0, np.pi / 2, n)) ** 2
        head = x[:, :n] * ramp + x[:, -n:] * ramp[::-1]
        x = np.concatenate([head, x[:, n:-n]], axis=1)
    if not loop:
        env = np.abs(x).max(axis=0)
        on = np.where(env > env.max() * 10 ** (-45 / 20))[0]
        x = x[:, max(0, on[0] - int(0.004 * SR)):]
        # the payoff (loudest moment) lands `hit` s in
        hit = float(s.get("hit", 0.0))
        if hit > 0:
            _, i = loudest(x, 0.03)
            shift = int(hit * SR) - i
            if shift > 0:
                x = np.concatenate([np.zeros((x.shape[0], shift)), x], axis=1)
            elif shift < 0:
                x = x[:, -shift:]
        # cut where it has died away (-50 dB under its peak, held for 50 ms), then fade
        env = np.abs(x).max(axis=0)
        above = np.where(env > env.max() * 10 ** (-50 / 20))[0]
        x = x[:, :min(x.shape[1], above[-1] + int(0.05 * SR))]
        n_in, n_out = int(0.002 * SR), min(int(0.06 * SR), x.shape[1] // 3)
        x[:, :n_in] *= np.linspace(0, 1, n_in)
        x[:, -n_out:] *= np.linspace(1, 0, n_out) ** 2
    # rumble under 35 Hz is wasted headroom
    X = np.fft.rfft(x, axis=1)
    f = np.fft.rfftfreq(x.shape[1], 1 / SR)
    X *= 1 / np.sqrt(1 + (35.0 / np.maximum(f, 1e-3)) ** 4)
    x = np.fft.irfft(X, x.shape[1], axis=1)
    db, _ = loudest(x)
    x = x * 10 ** ((LOUD[category(name)] - db) / 20)
    pk = np.abs(x).max()
    if pk > 0.95:
        x = x * 0.95 / pk
    return x


def write_wav(path, x):
    import soundfile as sf
    sf.write(path, (x.T if x.shape[0] == 2 else x[0]).astype(np.float32), SR, subtype="PCM_16")


def kenney_files(s):
    out = []
    for g in s["files"]:
        out += sorted(glob.glob(os.path.join(LIB, "sources/kenney", g), recursive=True))
    return out


def source_of(path):
    meta = os.path.splitext(path)[0] + ".json"
    if os.path.exists(meta):
        m = json.load(open(meta))
        return m.get("source", "?"), m.get("license", "?"), m.get("request", {}).get("text", "")
    if "/kenney/" in path:
        pack = path.split("/kenney/")[1].split("/")[0]
        return f"Kenney {pack} (kenney.nl)", "CC0 1.0", os.path.basename(path)
    return "?", "?", ""


def build(picks):
    credits = json.load(open(CREDITS + ".json")) if os.path.exists(CREDITS + ".json") else {}
    for name, files in picks.items():
        # only this sound's own takes: "hurt_*.wav" would also catch hurt_knight_0.wav
        for old in glob.glob(os.path.join(OUT, f"{name}_*.wav")):
            if re.fullmatch(re.escape(name) + r"_\d+\.wav", os.path.basename(old)):
                os.remove(old)
        for k, f in enumerate(files):
            x = shape(load(f, name in STEREO), name)
            write_wav(os.path.join(OUT, f"{name}_{k}.wav"), x)
        credits[name] = [dict(zip(("source", "license", "detail"), source_of(f))) for f in files]
        print(f"{name}: {len(files)} take(s), {x.shape[1] / SR:.2f} s, {category(name)}")
    json.dump(credits, open(CREDITS + ".json", "w"), indent=1, sort_keys=True)
    write_credits(credits)
    write_bank()


def write_credits(credits):
    lines = ["# Sound credits", "",
             "Every sound in `assets/audio/sfx/`, where it came from and its license (generated by `tools/audio/build_sfx.py`).",
             "Kenney sounds are CC0 (kenney.nl). ElevenLabs sounds were generated on a paid ElevenLabs plan (commercial use).", "",
             "| Sound | Takes | Source | License | Prompt / file |", "|---|---|---|---|---|"]
    for name in sorted(credits):
        c = credits[name]
        srcs = sorted({x["source"] for x in c})
        lic = sorted({x["license"] for x in c})
        det = c[0]["detail"].replace("|", "/")
        lines.append(f"| {name} | {len(c)} | {', '.join(srcs)} | {', '.join(lic)} | {det} |")
    open(CREDITS, "w").write("\n".join(lines) + "\n")


def write_bank():
    found = {}
    for path in glob.glob(os.path.join(OUT, "*.wav")):
        m = re.match(r"(.+)_(\d+)\.wav$", os.path.basename(path))
        if m:
            found[m.group(1)] = max(found.get(m.group(1), 0), int(m.group(2)) + 1)
    lines = ["## Generated by tools/audio/build_sfx.py: each sound's number of takes and its bus.",
             "## Files are assets/audio/sfx/<name>_<take>.wav (sources in assets/audio/CREDITS.md). Don't edit by hand.",
             "## [takes, bus, seconds to the payoff (Sfx.play_synced lands it on an attack's impact frame)]",
             "const BANK := {"]
    for name in sorted(found):
        bus = "ui" if name in UI else ("ambience" if name in AMB else "sfx")
        hit = float(BY_NAME.get(name, {}).get("hit", 0.0))
        lines.append(f'\t"{name}": [{found[name]}, "{bus}", {hit}],')
    lines.append("}")
    open(BANK_GD, "w").write("\n".join(lines) + "\n")
    print("bank:", len(found), "sounds")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--bank":
        write_bank()
    elif a and a[0] == "--kenney":
        build({s["name"]: kenney_files(s) for s in SPEC if s["src"] == "kenney"})
    else:
        build(json.load(open(a[0])))
