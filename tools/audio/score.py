"""Scores candidate sounds so the weak ones can be thrown out before anyone listens:

  clap  how well the sound matches its description (LAION-CLAP text-audio similarity, about -0.1..0.7)
  pq    production quality, 1..10 (Meta audiobox-aesthetics; also ce, cu, pc: enjoyment, usefulness, complexity)

    python score.py "a sword cutting into flesh" a.wav b.ogg ...     # one description, many files
    python score.py --jobs jobs.json out.json                         # [{"prompt": ..., "files": [...]}, ...]
    python score.py --rank <candidates dir> out.json [name ...]       # every spec sound's candidates, best first

Needs torch, laion-clap, torchvision, audiobox_aesthetics, librosa (a separate venv; see tools/audio/README.md).
The first run downloads the models (about 2 GB).
"""
import sys, json
import numpy as np

_clap = None
_aes = None


def clap():
    global _clap
    if _clap is None:
        import laion_clap
        _clap = laion_clap.CLAP_Module(enable_fusion=False)
        _clap.load_ckpt()   # 630k-audioset-best: clips under 10 s
    return _clap


def aes():
    global _aes
    if _aes is None:
        from audiobox_aesthetics.infer import initialize_predictor
        _aes = initialize_predictor()
    return _aes


def load48(path):
    import librosa
    x, _ = librosa.load(path, sr=48000, mono=True)
    return x[:48000 * 10]


def score(prompt, files):
    m = clap()
    t = m.get_text_embedding([prompt, ""], use_tensor=False)[0]
    out = []
    for f in files:
        import torch
        x = load48(f)
        a = m.get_audio_embedding_from_data(x=x[None, :], use_tensor=False)[0]
        sim = float(np.dot(a, t) / (np.linalg.norm(a) * np.linalg.norm(t) + 1e-9))
        q = aes().forward([{"path": torch.tensor(x[None, :]), "sample_rate": 48000}])[0]
        out.append({"file": f, "clap": round(sim, 3), **{k.lower(): round(float(v), 2) for k, v in q.items()}})
    return out


# ---------------------------------------------------------------- ranking a spec's candidates
DISTRACTORS = ["a synthesizer sound effect", "an electronic beep", "a video game arcade sound", "silence", "music"]


def rank(cand_dir, names=None):
    """For each spec sound with candidates in cand_dir/<name>/*.mp3 (plus its Kenney `alt`), the chance CLAP hears
    each as its label (against every other spec label and some synthetic-sounding distractors) and its
    production quality. Returns {name: [{file, p, pq, ce}, ...]} best first."""
    import glob, os, torch
    from spec import SPEC
    m = clap()
    labels = sorted({s["label"] for s in SPEC}) + DISTRACTORS
    T = m.get_text_embedding(labels, use_tensor=False)
    T = T / np.linalg.norm(T, axis=1, keepdims=True)
    lib = os.path.expanduser("~/Documents/Game Factory Audio/sources/kenney")
    out = {}
    for s in SPEC:
        if names and s["name"] not in names:
            continue
        files = sorted(glob.glob(os.path.join(cand_dir, s["name"], "*.mp3")))
        for g in s.get("alt", []) + (s.get("files", []) if s["src"] == "kenney" else []):
            files += sorted(glob.glob(os.path.join(lib, g), recursive=True))
        rows = []
        for f in files:
            x = load48(f)
            x = (np.clip(x, -1, 1) * 32767).astype(np.int16).astype(np.float32) / 32767
            if len(x) < 48000:
                x = np.concatenate([x, np.zeros(48000 - len(x), np.float32)])
            a = m.get_audio_embedding_from_data(x=x[None, :], use_tensor=False)[0]
            a = a / np.linalg.norm(a)
            sims = T @ a
            top = labels[int(np.argmax(sims))]
            # real, not synthetic: its own label against the synthetic-sounding distractors only
            # (near-synonyms among the other labels, "a magic implosion" for a nova, aren't failures)
            own = [labels.index(s["label"])] + [labels.index(d) for d in DISTRACTORS]
            p = np.exp(sims[own] * 100)
            p = p / p.sum()
            q = aes().forward([{"path": torch.tensor(x[None, :]), "sample_rate": 48000}])[0]
            rows.append({"file": f, "p": round(float(p[0]), 3), "heard": top,
                         "pq": round(float(q["PQ"]), 2), "ce": round(float(q["CE"]), 2)})
        rows.sort(key=lambda r: -(r["p"] * 0.6 + r["pq"] / 10 * 0.4))
        out[s["name"]] = rows
        print(s["name"], [(round(r["p"], 2), r["pq"]) for r in rows[:4]], flush=True)
    return out


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "--rank":
        # python score.py --rank <candidates dir> <out.json> [name ...]
        import os
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        json.dump(rank(a[1], a[3:] or None), open(a[2], "w"), indent=1)
    elif a and a[0] == "--jobs":
        jobs = json.load(open(a[1]))
        res = [{"prompt": j["prompt"], "scores": score(j["prompt"], j["files"])} for j in jobs]
        json.dump(res, open(a[2], "w"), indent=1)
    else:
        for r in score(a[0], a[1:]):
            print(f"clap {r['clap']:6.3f}  pq {r['pq']:5.2f}  ce {r['ce']:5.2f}  {r['file']}")
