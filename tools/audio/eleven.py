"""Generates sound candidates with ElevenLabs Sound Effects for the entries in spec.py (src "eleven").

    python3 eleven.py [name ...] [--out DIR] [--dry]      # default out: ~/Documents/Game Factory Audio/candidates
    python3 eleven.py --credits                           # what the plan has left

Each candidate is <out>/<name>/<k>.mp3 with <k>.json beside it (prompt, settings, credits used). Existing
candidates are skipped, so a run that stops can simply be started again. The key comes from
$ELEVENLABS_API_KEY or ~/.config/elevenlabs/key and is never printed or written anywhere else.
Standard library only (any python3).
"""
import os, sys, json, time, urllib.request, urllib.error
sys.path.insert(0, os.path.dirname(__file__))
from spec import SPEC

API = "https://api.elevenlabs.io/v1"
OUT = os.path.expanduser("~/Documents/Game Factory Audio/candidates")


def key():
    k = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not k:
        p = os.path.expanduser("~/.config/elevenlabs/key")
        if os.path.exists(p):
            k = open(p).read().strip()
    if not k:
        sys.exit("No ElevenLabs key: set ELEVENLABS_API_KEY or write it to ~/.config/elevenlabs/key")
    return k


def call(path, body=None):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"xi-api-key": key(), "Content-Type": "application/json"},
                                 method="POST" if body is not None else "GET")
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read(), dict(r.headers)


def credits():
    d = json.loads(call("/user/subscription")[0])
    return {k: d.get(k) for k in ("tier", "character_count", "character_limit", "next_character_count_reset_unix")}


def generate(s, k, out):
    d = os.path.join(out, s["name"])
    os.makedirs(d, exist_ok=True)
    mp3 = os.path.join(d, f"{k}.mp3")
    if os.path.exists(mp3):
        return None
    text = s["prompt_b"] if str(k).startswith("b") else s["prompt"]
    body = {"text": text, "prompt_influence": 0.6, "model_id": "eleven_text_to_sound_v2"}
    if s.get("dur"):
        body["duration_seconds"] = min(30.0, max(0.5, float(s["dur"])))   # the API's range; build_sfx trims the rest
    if s.get("loop"):
        body["loop"] = True
    for attempt in range(4):
        try:
            audio, hdr = call("/sound-generation?output_format=mp3_44100_128", body)
            break
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode(errors="replace")
            if e.code == 429 or e.code >= 500:
                time.sleep(5 * (attempt + 1))
                continue
            sys.exit(f"{s['name']} {k}: HTTP {e.code} {msg}")
    else:
        sys.exit(f"{s['name']} {k}: gave up after retries")
    open(mp3, "wb").write(audio)
    meta = {"name": s["name"], "take": k, "source": "ElevenLabs Sound Effects", "license": "ElevenLabs paid plan, commercial use",
            "request": body, "credits": hdr.get("character-cost") or hdr.get("Character-Cost"), "bytes": len(audio)}
    json.dump(meta, open(os.path.join(d, f"{k}.json"), "w"), indent=1)
    return meta


if __name__ == "__main__":
    a = sys.argv[1:]
    out = OUT
    if "--out" in a:
        i = a.index("--out"); out = a[i + 1]; del a[i:i + 2]
    if "--credits" in a:
        print(credits()); sys.exit()
    dry = "--dry" in a
    names = [x for x in a if not x.startswith("--")]
    todo = [s for s in SPEC if s["src"] == "eleven" and (not names or s["name"] in names)]
    if dry:
        sec = sum((s["n"] + (4 if s.get("prompt_b") else 0)) * max(0.5, s.get("dur") or 2.0) for s in todo)
        print(f"{len(todo)} sounds, about {sec * 10:.0f} credits at 10/s (what the API charged)"); sys.exit()
    before = credits()
    print("credits before:", before["character_count"], "/", before["character_limit"])
    for s in todo:
        for k in list(range(s["n"])) + ([f"b{i}" for i in range(4)] if s.get("prompt_b") else []):
            m = generate(s, k, out)
            if m:
                print(f"{s['name']} {k}: {m['bytes'] // 1024} KB, cost {m['credits']}", flush=True)
    after = credits()
    print("credits after:", after["character_count"], "/", after["character_limit"], " used", after["character_count"] - before["character_count"])
