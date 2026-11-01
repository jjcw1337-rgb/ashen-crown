"""The nightly lab's morning report and cost record (run by tools/nightly/run.sh after both phases).
    python report.py <date> <out dir> <base commit> <failed steps or "none">
Reads the phases' own outputs in <out dir>: perf_result.json / mode_result.json (Claude's --output-format json: cost,
turns, time), perf_summary.md, mode_summary.md, mode_costs.json (assets the mode phase bought), mode_frame_*.png.
Writes docs/nightly/nights/<date>.md (the report as posted), appends docs/nightly/costs.jsonl, adds the Claude cost
to the new mode's README "Cost" section, and builds <out dir>/mode.gif from the frames.
"""
import glob
import json
import os
import sys

DATE, OUT, BASE, FAILED = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
SERVER_PER_NIGHT = 24.0 / 30.0      # the staging droplet, $24/month


def load(name, default):
    try:
        with open(os.path.join(OUT, name)) as f:
            return json.load(f) if name.endswith(".json") else f.read()
    except Exception:
        return default


def claude_cost(r):
    if not isinstance(r, dict):
        return {"usd": None, "turns": None, "minutes": None, "ok": False}
    return {"usd": r.get("total_cost_usd"), "turns": r.get("num_turns"),
            "minutes": round((r.get("duration_ms") or 0) / 60000.0, 1), "ok": not r.get("is_error", False)}


perf = claude_cost(load("perf_result.json", None))
mode = claude_cost(load("mode_result.json", None))
assets = load("mode_costs.json", {}) or {}
costs = {
    "date": DATE, "base": BASE,
    "claude_perf_usd": perf["usd"], "claude_mode_usd": mode["usd"],
    "claude_perf_turns": perf["turns"], "claude_mode_turns": mode["turns"],
    "perf_minutes": perf["minutes"], "mode_minutes": mode["minutes"],
    "meshy_credits": assets.get("meshy_credits", 0), "elevenlabs_credits": assets.get("elevenlabs_credits", 0),
    "server_usd": round(SERVER_PER_NIGHT, 2), "failed": FAILED,
}
os.makedirs("docs/nightly/nights", exist_ok=True)
with open("docs/nightly/costs.jsonl", "a") as f:
    f.write(json.dumps(costs) + "\n")


def usd(x):
    return "n/a" if x is None else "$%.2f" % x


# the new mode's README gets the Claude cost
modes = sorted(d for d in glob.glob("docs/nightly/modes/%s-*" % DATE) if os.path.isdir(d))
mode_dir = modes[-1] if modes else ""
if mode_dir and os.path.exists(os.path.join(mode_dir, "README.md")):
    with open(os.path.join(mode_dir, "README.md"), "a") as f:
        f.write("\n### Build cost (filled in by the nightly script)\n\n| Tool | Cost |\n|---|---|\n")
        f.write("| Claude (this mode, %s turns, %s min) | %s |\n" % (mode["turns"], mode["minutes"], usd(mode["usd"])))
        f.write("| Meshy | %s credits |\n| ElevenLabs | %s credits |\n" % (costs["meshy_credits"], costs["elevenlabs_credits"]))
        f.write("| Staging server (share of the night) | %s |\n" % usd(costs["server_usd"]))

# a GIF from the mode's frames
frames = sorted(glob.glob(os.path.join(OUT, "mode_frame_*.png")))
if frames:
    try:
        from PIL import Image
        ims = []
        for p in frames[:80]:
            im = Image.open(p).convert("RGB")
            im.thumbnail((720, 720))
            ims.append(im.convert("P", palette=Image.ADAPTIVE))
        ims[0].save(os.path.join(OUT, "mode.gif"), save_all=True, append_images=ims[1:], duration=80, loop=0, optimize=True)
    except Exception as e:
        print("gif failed:", e)

total = sum(x for x in [perf["usd"], mode["usd"], costs["server_usd"]] if x is not None)
lines = ["# Nightly lab: %s" % DATE, ""]
lines += ["## ⚡ Performance", "", (load("perf_summary.md", "") or "_The performance phase left no summary._").strip(), ""]
lines += ["## 🚀 New tonight", "", (load("mode_summary.md", "") or "_The mode phase left no summary._").strip(), ""]
if mode_dir:
    lines += ["Details: `%s/README.md`. Feedback goes in `%s/feedback.md` (just reply in Discord)." % (mode_dir, mode_dir), ""]
# (a list, not a table: Discord doesn't draw Markdown tables)
lines += ["## 💸 What tonight cost", "",
          "- Claude, performance: %s (%s turns, %s min)" % (usd(perf["usd"]), perf["turns"], perf["minutes"]),
          "- Claude, new mode: %s (%s turns, %s min)" % (usd(mode["usd"]), mode["turns"], mode["minutes"]),
          "- Meshy: %s credits · ElevenLabs: %s credits" % (costs["meshy_credits"], costs["elevenlabs_credits"]),
          "- Staging server: %s" % usd(costs["server_usd"]),
          "- **Total: %s** (plus the credits above)" % usd(total), ""]
if FAILED != "none":
    lines += ["⚠️ Steps that failed tonight: %s (logs: ~/Library/Logs/ashen-nightly/%s.log)" % (FAILED, DATE), ""]
with open("docs/nightly/nights/%s.md" % DATE, "w") as f:
    f.write("\n".join(lines))
print("report written", "docs/nightly/nights/%s.md" % DATE)
