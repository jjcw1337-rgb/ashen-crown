"""A nightly job's report and cost record (run by tools/nightly/run.sh after the job and the benchmark).
    python report.py <job: perf|mode|triage> <date> <out dir> <base commit> <failed steps or "none">
Reads the job's outputs in <out dir>: <job>_result.json (Claude's --output-format json: cost, turns, time),
<job>_summary.md, <job>_skipped.txt (run.sh's note that the job was skipped tonight, and why), bench.md (the runner's
benchmark verdict), and for the mode job mode_costs.json (assets it bought) and mode_frame_*.png.
Writes docs/nightly/nights/<date>-<job>.md (the report as posted), appends docs/nightly/costs.jsonl, adds the Claude
cost to the new mode's README "Cost" section, and builds <out dir>/mode.gif from the frames.
"""
import glob
import json
import os
import sys

JOB, DATE, OUT, BASE, FAILED = sys.argv[1:6]
SERVER_PER_NIGHT = 24.0 / 30.0 / 3      # the staging droplet, $24/month, shared by the three jobs
TITLE = {"perf": "performance", "mode": "new mode", "triage": "triage", "hotfix": "hotfix"}[JOB]
HEAD = {"perf": "## ⚡ Performance", "mode": "## 🚀 New tonight", "triage": "## 🩺 What players hit, and what's fixed", "hotfix": "## 🛠️ The issue, and the fix"}[JOB]
LOGS = {"perf": "docs/nightly/perf/LOG.md", "mode": "docs/nightly/modes/LOG.md", "triage": "docs/nightly/triage/LOG.md", "hotfix": "docs/nightly/triage/LOG.md"}[JOB]


def load(name, default):
    try:
        with open(os.path.join(OUT, name)) as f:
            return json.load(f) if name.endswith(".json") else f.read()
    except Exception:
        return default


def claude_cost(r):
    if not isinstance(r, dict):
        return {"usd": None, "turns": None, "minutes": None, "ok": False, "ran": False, "result": ""}
    return {"usd": r.get("total_cost_usd"), "turns": r.get("num_turns"),
            "minutes": round((r.get("duration_ms") or 0) / 60000.0, 1), "ok": not r.get("is_error", False),
            "ran": True, "result": str(r.get("result") or "")}


def usd(x):
    return "n/a" if x is None else "$%.2f" % x


r = claude_cost(load("%s_result.json" % JOB, None))
skipped = load("%s_skipped.txt" % JOB, None)
if skipped is not None:
    skipped = skipped.strip() or "set by hand for tonight"
assets = (load("mode_costs.json", {}) or {}) if JOB == "mode" else {}
costs = {
    "date": DATE, "job": JOB, "base": BASE, "claude_usd": r["usd"], "claude_turns": r["turns"], "minutes": r["minutes"],
    "meshy_credits": assets.get("meshy_credits", 0), "elevenlabs_credits": assets.get("elevenlabs_credits", 0),
    "server_usd": round(SERVER_PER_NIGHT, 2), "failed": FAILED, "skipped": skipped is not None,
}
os.makedirs("docs/nightly/nights", exist_ok=True)
with open("docs/nightly/costs.jsonl", "a") as f:
    f.write(json.dumps(costs) + "\n")

mode_dir = ""
if JOB == "mode":
    # the new mode's README gets the Claude cost
    modes = sorted(d for d in glob.glob("docs/nightly/modes/%s-*" % DATE) if os.path.isdir(d))
    mode_dir = modes[-1] if modes else ""
    if mode_dir and os.path.exists(os.path.join(mode_dir, "README.md")):
        with open(os.path.join(mode_dir, "README.md"), "a") as f:
            f.write("\n### Build cost (filled in by the nightly script)\n\n| Tool | Cost |\n|---|---|\n")
            f.write("| Claude (this mode, %s turns, %s min) | %s |\n" % (r["turns"], r["minutes"], usd(r["usd"])))
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


def section():
    """The job's summary, or a plain account of why there is none: skipped on purpose, never ran, or ran and ended
    without writing one (then its exit state and the last thing it said)."""
    text = (load("%s_summary.md" % JOB, "") or (load("triage_summary.md", "") if JOB == "hotfix" else "") or "").strip()
    if text:
        return text
    if skipped is not None:
        return "**Skipped tonight on purpose**: %s. It runs again tomorrow night." % skipped
    if not r["ran"]:
        return "**The %s job didn't run** (no result from its Claude session; log: ~/Library/Logs/ashen-nightly/%s-%s.log)." % (TITLE, DATE, JOB)
    said = r["result"].strip().replace("\n\n", "\n")
    if len(said) > 700:
        said = said[:700].rsplit(" ", 1)[0] + " …"
    head = "**The %s job %s without writing its summary** (%s turns, %s min)." % (
        TITLE, "ended" if r["ok"] else "failed", r["turns"], r["minutes"])
    return head + ("\nIts last words:\n> " + said.replace("\n", "\n> ") if said else "")


if skipped is not None:
    claude = "- Claude: $0 (skipped tonight)"
elif not r["ran"]:
    claude = "- Claude: $0 (didn't run)"
else:
    claude = "- Claude: %s (%s turns, %s min)" % (usd(r["usd"]), r["turns"], r["minutes"])
total = sum(x for x in [r["usd"], costs["server_usd"]] if x is not None)

lines = ["# Nightly %s: %s" % (TITLE, DATE), "", HEAD, "", section(), ""]
bench = (load("bench.md", "") or "").strip()
if bench:
    lines += [bench, ""]
if mode_dir:
    lines += ["Details: `%s/README.md`. Feedback goes in `%s/feedback.md` (just reply in Discord)." % (mode_dir, mode_dir), ""]
lines += ["Log of every attempt: `%s`" % LOGS, ""]
# (a list, not a table: Discord doesn't draw Markdown tables)
lines += ["## 💸 What it cost", "", claude]
if JOB == "mode":
    lines += ["- Meshy: %s credits · ElevenLabs: %s credits" % (costs["meshy_credits"], costs["elevenlabs_credits"])]
lines += ["- Staging server (a third of the day): %s" % usd(costs["server_usd"]),
          "- **Total: %s**%s" % (usd(total), " (plus the credits above)" if JOB == "mode" else ""), ""]
with open("docs/nightly/nights/%s-%s.md" % (DATE, JOB), "w") as f:
    f.write("\n".join(lines))
print("report written", "docs/nightly/nights/%s-%s.md" % (DATE, JOB))
