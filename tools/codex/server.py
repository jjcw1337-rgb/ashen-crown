#!/usr/bin/env python3
"""The Hero Codex editor (Blaine, 2026-11-06): a small web app over data/codex/, the files the game loads its
heroes' skills, rites, gems and consumables from (scripts/codex.gd). Saving an entry writes its file and commits
just that file on the checkout's current branch; Publish pushes the branch for a preview build.

    python3 tools/codex/server.py [--port 8765] [--repo .] [--password-file ~/.config/ashen-codex/password]

Every request needs HTTP basic auth (any user name, the password from the file; one is generated on the first run).
Standard library only."""

import argparse, base64, hashlib, hmac, json, os, re, secrets, subprocess, sys, threading
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK = threading.Lock()
ID_RE = re.compile(r"^[a-z0-9_]{2,40}$")
FILE_RE = re.compile(r"^(heroes/[a-z0-9_]+|shared|gems|consumables)\.json$")
# Keep in step with Codex.FX_KEYS (scripts/codex.gd): what a live data-only rite may use.
FX_KEYS = ["dmg", "life_pct", "mana_pct", "armor_pct", "crit", "crit_dmg", "ias", "frw", "regen", "res", "ls",
           "str", "dex", "vit", "ene", "block", "mf", "buff_pow", "buff_dur", "block_dr", "cdr"]
NUM = (int, float)


def fx_ok(fx):
    return isinstance(fx, dict) and fx and all(
        k in FX_KEYS or k.startswith(("dmg:", "cd:", "cost:")) for k in fx)


class Codex:
    def __init__(self, repo: Path):
        self.repo = repo
        self.dir = repo / "data" / "codex"

    def git(self, *args, check=True):
        r = subprocess.run(["git", "-C", str(self.repo), *args], capture_output=True, text=True)
        if check and r.returncode != 0:
            raise RuntimeError((r.stderr or r.stdout).strip()[-400:])
        return r.stdout.strip()

    @staticmethod
    def digest(p):
        return hashlib.sha1(p.read_bytes()).hexdigest()[:12]

    def read(self, rel):
        return json.loads((self.dir / rel).read_text())

    def committed(self, rel):
        """The file as last committed (what 'live' meant before this edit)."""
        try:
            return json.loads(self.git("show", f"HEAD:data/codex/{rel}"))
        except Exception:
            return {}

    def bundle(self):
        heroes = {}
        for p in sorted((self.dir / "heroes").glob("*.json")):
            heroes[p.stem] = json.loads(p.read_text())
        dirty = self.git("status", "--porcelain", "--", "data/codex", check=False)
        ahead = self.git("rev-list", "--count", "@{u}..HEAD", check=False) or "?"
        hashes = {str(p.relative_to(self.dir)): self.digest(p) for p in self.dir.rglob("*.json")}
        return {"heroes": heroes, "shared": self.read("shared.json"), "gems": self.read("gems.json"),
                "consumables": self.read("consumables.json"), "fx_keys": FX_KEYS, "hashes": hashes,
                "git": {"branch": self.git("branch", "--show-current", check=False),
                        "commit": self.git("log", "-1", "--format=%h %s", check=False),
                        "dirty": bool(dirty), "unpushed": ahead}}

    def validate(self, rel, doc):
        if not isinstance(doc, dict):
            raise ValueError("the file must be a JSON object")
        old = self.committed(rel)
        lists = {"skills": doc.get("skills", []), "rites": doc.get("rites", []), "gems": doc.get("gems", []),
                 "entries": doc.get("entries", [])}
        live_before = set()
        for key in ("skills", "rites", "gems", "entries"):
            for e in old.get(key, []) or []:
                if isinstance(e, dict) and e.get("status", "live") == "live":
                    live_before.add((key, e.get("id")))
        for key, lst in lists.items():
            if not isinstance(lst, list):
                raise ValueError(f"{key} must be a list")
            seen = set()
            for e in lst:
                if not isinstance(e, dict):
                    raise ValueError(f"{key}: every entry must be an object")
                i = e.get("id", "")
                if not isinstance(i, str) or not ID_RE.match(i):
                    raise ValueError(f"{key}: id {i!r} must be 2-40 of a-z 0-9 _")
                if i in seen:
                    raise ValueError(f"{key}: id {i} appears twice")
                seen.add(i)
                if not str(e.get("name", "")).strip():
                    raise ValueError(f"{i}: a name is required")
                st = e.get("status", "live")
                if st not in ("live", "design"):
                    raise ValueError(f"{i}: status must be live or design")
                r = e.get("rarity", 0)
                if not isinstance(r, NUM) or int(r) not in (0, 1, 2):
                    raise ValueError(f"{i}: rarity must be 0 common, 1 uncommon or 2 rare")
                for f in ("mana", "cd", "use", "power", "range", "max", "lvl"):
                    if f in e and e[f] is not None and (not isinstance(e[f], NUM) or e[f] < 0):
                        raise ValueError(f"{i}: {f} must be a number of 0 or more")
                if "fx" in e and not (isinstance(e["fx"], dict) and all(isinstance(v, NUM) for v in e["fx"].values())):
                    raise ValueError(f"{i}: every fx value must be a number")
                if st == "live" and (key, i) not in live_before:
                    if key == "rites" and fx_ok(e.get("fx")):
                        continue     # a new rite made of keys the game reads: live straight away
                    raise ValueError(f"{i}: only a rite made of stats the game already reads ({', '.join(FX_KEYS)}, "
                                     f"dmg:/cd:/cost:<skill>) can go live from the codex; this one needs code first, keep it design")
        for key, i in live_before:
            if key in lists and not any(isinstance(e, dict) and e.get("id") == i for e in lists[key]):
                raise ValueError(f"{i} is in the game: it can be edited, not deleted")
        return doc

    def save(self, rel, doc, who, base=None):
        if not FILE_RE.match(rel):
            raise ValueError("unknown codex file")
        path = self.dir / rel
        if not path.exists():
            raise ValueError("unknown codex file")
        self.validate(rel, doc)
        with LOCK:
            if base and self.digest(path) != base:
                raise ValueError("someone else saved this file since you loaded it: reload to see their change, then edit again")
            path.write_text(json.dumps(doc, indent="\t", ensure_ascii=False) + "\n")
            if self.git("status", "--porcelain", "--", f"data/codex/{rel}", check=False):
                self.git("add", "--", f"data/codex/{rel}")
                self.git("commit", "-q", "-m", f"Codex: {rel} edited ({who})\n\nSaved from the Hero Codex editor (tools/codex/server.py).",
                         "--only", "--", f"data/codex/{rel}")
        return self.bundle()["git"]

    def publish(self):
        with LOCK:
            br = self.git("branch", "--show-current")
            if not br.startswith("claude-2/"):
                raise ValueError(f"publishing is only allowed from a claude-2/ task branch (on {br})")
            self.git("fetch", "-q", "origin", br, check=False)
            self.git("push", "-q", "origin", f"HEAD:{br}")
            self.git("push", "-q", "origin", "HEAD:test-codex")
        return {"pushed": [br, "test-codex"], "commit": self.git("log", "-1", "--format=%h %s"),
                "preview": "https://github.com/jjcw1337-rgb/ashen-crown/actions/workflows/preview.yml"}


def make_handler(codex: Codex, password: str):
    index = (HERE / "index.html").read_bytes()

    class H(BaseHTTPRequestHandler):
        server_version = "HeroCodex/1"

        def log_message(self, fmt, *a):
            sys.stderr.write("[codex] %s %s\n" % (self.address_string(), fmt % a))

        def _authed(self):
            h = self.headers.get("Authorization", "")
            if h.startswith("Basic "):
                try:
                    user, _, pw = base64.b64decode(h[6:]).decode().partition(":")
                    if hmac.compare_digest(pw.encode(), password.encode()):
                        self.who = re.sub(r"[^A-Za-z0-9 _-]", "", user)[:24] or "codex"
                        return True
                except Exception:
                    pass
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="Ashen Crown Hero Codex"')
            self.send_header("Content-Length", "0")
            self.end_headers()
            return False

        def _send(self, code, body, ctype="application/json"):
            if not isinstance(body, bytes):
                body = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Frame-Options", "DENY")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if not self._authed():
                return
            if self.path in ("/", "/index.html") or self.path.startswith("/#"):
                return self._send(200, index, "text/html; charset=utf-8")
            if self.path == "/api/codex":
                return self._send(200, codex.bundle())
            self._send(404, {"error": "not found"})

        def do_PUT(self):
            if not self._authed():
                return
            if not self.path.startswith("/api/file/"):
                return self._send(404, {"error": "not found"})
            try:
                n = int(self.headers.get("Content-Length", "0"))
                if n > 2_000_000:
                    raise ValueError("too large")
                body = json.loads(self.rfile.read(n))
                rel = self.path[len("/api/file/"):]
                git = codex.save(rel, body.get("doc"), self.who, body.get("base"))
                self._send(200, {"ok": True, "git": git, "hash": codex.digest(codex.dir / rel)})
            except (ValueError, RuntimeError, json.JSONDecodeError) as e:
                self._send(400, {"error": str(e)})

        def do_POST(self):
            if not self._authed():
                return
            if self.path != "/api/publish":
                return self._send(404, {"error": "not found"})
            try:
                self._send(200, codex.publish())
            except (ValueError, RuntimeError) as e:
                self._send(400, {"error": str(e)})

    return H


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--repo", default=str(HERE.parent.parent))
    ap.add_argument("--password-file", default=os.path.expanduser("~/.config/ashen-codex/password"))
    a = ap.parse_args()
    pf = Path(a.password_file)
    if not pf.exists():
        pf.parent.mkdir(parents=True, exist_ok=True)
        pf.write_text(secrets.token_urlsafe(9) + "\n")
        pf.chmod(0o600)
        print(f"[codex] a password was generated in {pf}")
    password = pf.read_text().strip()
    codex = Codex(Path(a.repo).resolve())
    codex.bundle()
    srv = ThreadingHTTPServer((a.host, a.port), make_handler(codex, password))
    print(f"[codex] serving {codex.dir} on http://{a.host}:{a.port}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
