"""Posts the nightly lab's morning report to the Game Factory Discord channel (run by tools/nightly/run.sh).
    python post_discord.py <out dir> <report.md> [failed steps] [--dry]
Uses the bot's REST API with the token from ~/.claude/channels/discord/.env (never printed or logged); no gateway
connection, so it doesn't disturb the Game Factory session's own bot connection. Messages are split under Discord's
2000 characters; images (the mode GIF, then the best PNGs, resized to JPEG) go in a follow-up message, at most 10.
--dry prints what would be sent (lengths and file names) instead.
"""
import glob
import io
import json
import os
import sys
import urllib.request
import uuid

CHANNEL = "1564444926765178890"
ENV = os.path.expanduser("~/.claude/channels/discord/.env")
ITCH = "https://jbhatab.itch.io/ashen-crown-staging"


def token():
    with open(ENV) as f:
        for line in f:
            if line.startswith("DISCORD_BOT_TOKEN="):
                return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("no DISCORD_BOT_TOKEN in the .env")


def chunks(text, n=1900):
    out, cur = [], ""
    for para in text.split("\n"):
        # (a section starts a new message rather than being cut, once the message has some length)
        if len(cur) + len(para) + 1 > n or (para.startswith("## ") and len(cur) > n * 0.6):
            out.append(cur)
            cur = ""
        cur += para + "\n"
    if cur.strip():
        out.append(cur)
    return out


def send(tok, content, files=()):
    boundary = uuid.uuid4().hex
    body = io.BytesIO()
    def part(headers, data):
        body.write(("--%s\r\n" % boundary).encode())
        body.write(headers.encode() + b"\r\n\r\n")
        body.write(data)
        body.write(b"\r\n")
    part('Content-Disposition: form-data; name="payload_json"\r\nContent-Type: application/json',
         json.dumps({"content": content, "allowed_mentions": {"users": ["103232622510997504", "1453436059252687012"]}}).encode())
    for i, (name, data) in enumerate(files):
        part('Content-Disposition: form-data; name="files[%d]"; filename="%s"' % (i, name), data)
    body.write(("--%s--\r\n" % boundary).encode())
    req = urllib.request.Request("https://discord.com/api/v10/channels/%s/messages" % CHANNEL, data=body.getvalue(),
        headers={"Authorization": "Bot " + tok, "Content-Type": "multipart/form-data; boundary=" + boundary,
                 "User-Agent": "AshenCrownNightly (github.com/jjcw1337-rgb/ashen-crown, 1.0)"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status


def images(out):
    files = []
    gif = os.path.join(out, "mode.gif")
    if os.path.exists(gif) and os.path.getsize(gif) < 9_000_000:
        files.append(("new_mode.gif", open(gif, "rb").read()))
    pngs = [p for p in sorted(glob.glob(os.path.join(out, "*.png"))) if "mode_frame_" not in os.path.basename(p)]
    try:
        from PIL import Image
        for p in pngs[: 10 - len(files)]:
            im = Image.open(p).convert("RGB")
            im.thumbnail((1600, 1600))
            b = io.BytesIO()
            im.save(b, "JPEG", quality=85)
            files.append((os.path.splitext(os.path.basename(p))[0] + ".jpg", b.getvalue()))
    except Exception as e:
        print("images:", e)
    return files


def main():
    out, report = sys.argv[1], sys.argv[2]
    args = [a for a in sys.argv[3:] if a != "--dry"]
    failed = (args[0] if args else "").strip()
    dry = "--dry" in sys.argv
    text = open(report).read()
    target = open(os.path.join(out, "target.txt")).read().strip() if os.path.exists(os.path.join(out, "target.txt")) else "?"
    itch = open(os.path.join(out, "itch.txt")).read().strip() if os.path.exists(os.path.join(out, "itch.txt")) else ""
    base = os.path.basename(report)
    job = {"mode": "game mode", "triage": "triage", "hotfix": "hotfix"}.get(base.rsplit("-", 1)[-1][:-3], "performance")
    head = "<@103232622510997504> <@1453436059252687012> 🌙 **Nightly %s report**\n" % job
    if target == "staging":
        head += "It passed every test and is on `staging`: " + (
            "the itch app has it now → " + ITCH if itch == "itch-ok" else "it's still building for itch (" + ITCH + ")") + "\n"
    else:
        head += "⚠️ It did NOT pass (tests, or the benchmark found it slower), so it's parked on `%s` (staging unchanged).\n" % target
    if failed:
        head += "⚠️ Steps that failed: %s (log: ~/Library/Logs/ashen-nightly/)\n" % failed
    msgs = chunks(head + "\n" + text)
    files = images(out)
    if dry:
        for m in msgs:
            print("message", len(m))
        print("files", [(n, len(d)) for n, d in files])
        return
    tok = token()
    for m in msgs:
        send(tok, m)
    if files:
        send(tok, "📸 Tonight in pictures", files)
    print("posted", len(msgs), "messages and", len(files), "files")


main()
