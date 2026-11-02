"""The admins' recent requests from the Game Factory Discord channel, for the Codex audit (tools/audit/audit.sh).
    python3 -I fetch_requests.py <hours> > requests.txt
Reads the channel's last messages with the bot's REST API (token from ~/.claude/channels/discord/.env, never printed)
and prints those of the two admins from the last <hours> hours, oldest first: time, who, text (attachments named).
Read only: it never posts."""
import datetime
import json
import os
import sys
import urllib.request

CHANNEL = "1564444926765178890"
ADMINS = {"103232622510997504": "Blaine", "1453436059252687012": "jj"}
ENV = os.path.expanduser("~/.claude/channels/discord/.env")


def token():
    with open(ENV) as f:
        for line in f:
            if line.startswith("DISCORD_BOT_TOKEN="):
                return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("no token")


def main():
    hours = float(sys.argv[1]) if len(sys.argv) > 1 else 24.0
    since = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)
    tok, before, out = token(), None, []
    for _ in range(6):                      # up to 600 messages back
        url = "https://discord.com/api/v10/channels/%s/messages?limit=100" % CHANNEL + ("&before=" + before if before else "")
        req = urllib.request.Request(url, headers={"Authorization": "Bot " + tok, "User-Agent": "GameFactoryAudit (local, 1.0)"})
        page = json.load(urllib.request.urlopen(req, timeout=20))
        if not page:
            break
        stop = False
        for m in page:
            t = datetime.datetime.fromisoformat(m["timestamp"])
            if t < since:
                stop = True
                break
            who = ADMINS.get(m["author"]["id"])
            if who:
                att = " ".join("[attachment %s]" % a["filename"] for a in m.get("attachments", []))
                out.append((t, who, (m.get("content", "") + " " + att).strip()))
        before = page[-1]["id"]
        if stop:
            break
    for t, who, text in sorted(out):
        print("%s %s: %s" % (t.astimezone().strftime("%m-%d %H:%M"), who, text.replace("\n", " / ")))


main()
