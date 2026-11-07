#!/usr/bin/env python3
"""The Hero Codex editor (Blaine, 2026-11-06): a small web app over data/codex/, the files the game loads its
heroes' skills, rites, gems and consumables from (game/systems/data/codex.gd). Saving an entry writes its file and commits
just that file on the checkout's current branch; Publish pushes the branch for a preview build.

    python3 tools/codex/server.py [--port 8765] [--repo .] [--password-file ~/.config/ashen-codex/password]
    python3 tools/codex/server.py --repo <its own worktree on LIVE_BRANCH> --live staging --godot <godot binary>

--live staging (Blaine 2026-11-06: the editor updates the shared game): the checkout follows origin/staging (its
unpublished edits replayed on top), and Publish runs tools/codex_test.gd on it and pushes it to staging (a
fast-forward, never a force). Give it a worktree of its own: it moves that checkout.

Access (Blaine 2026-11-06: no username and password): the link is the key. Open /?key=<the key in
~/.config/ashen-codex/link_key> once and a cookie remembers it; HTTP basic auth with the password file still works
for tools. Standard library only."""

import argparse, base64, hashlib, hmac, json, os, re, secrets, subprocess, sys, threading, time
from http.cookies import SimpleCookie
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlsplit
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCK = threading.Lock()
ID_RE = re.compile(r"^[a-z0-9_]{2,40}$")
FILE_RE = re.compile(r"^(heroes/[a-z0-9_]+|shared|gems|consumables)\.json$")
NUM = (int, float)
LIVE_BRANCH = "claude-2/codex-live"   # the only branch a --live server publishes from
SYNC_EVERY = 60                       # seconds between looks at the newest staging


def fx_ok(fx, keys):
    """Every effect key one the game reads (data/codex/fx_keys.json, as Codex.data_only)."""
    return isinstance(fx, dict) and fx and all(k in keys or k.startswith(("dmg:", "cd:", "cost:")) for k in fx)


class Codex:
    def __init__(self, repo: Path, live=None, godot=None):
        self.repo = repo
        self.dir = repo / "data" / "codex"
        self.live = live          # "staging": Publish puts the edits into the shared game
        self.godot = godot        # runs tools/codex_test.gd before a live publish
        self.synced = 0.0
        self.sync_error = ""

    def git(self, *args, check=True):
        r = subprocess.run(["git", "-C", str(self.repo), *args], capture_output=True, text=True)
        if check and r.returncode != 0:
            raise RuntimeError((r.stderr or r.stdout).strip()[-400:])
        return r.stdout.strip()

    def fx_keys(self, cls=None):
        f = self.read("fx_keys.json")
        if cls is None:
            return f
        return list(f.get("any", [])) + list(f.get(cls, []))

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
        upstream = f"origin/{self.live}" if self.live else "@{u}"
        ahead = self.git("rev-list", "--count", f"{upstream}..HEAD", check=False) or "?"
        hashes = {str(p.relative_to(self.dir)): self.digest(p) for p in self.dir.rglob("*.json")}
        return {"heroes": heroes, "shared": self.read("shared.json"), "gems": self.read("gems.json"),
                "consumables": self.read("consumables.json"), "fx_keys": self.fx_keys(), "hashes": hashes,
                "git": {"branch": self.git("branch", "--show-current", check=False),
                        "commit": self.git("log", "-1", "--format=%h %s", check=False),
                        "dirty": bool(dirty), "unpushed": ahead, "live": self.live or "",
                        "sync_error": self.sync_error}}

    def validate(self, rel, doc):
        if not isinstance(doc, dict):
            raise ValueError("the file must be a JSON object")
        old = self.committed(rel)
        keys = self.fx_keys(rel[len("heroes/"):-5] if rel.startswith("heroes/") else "any")
        lists = {"skills": doc.get("skills", []), "rites": doc.get("rites", []), "gems": doc.get("gems", []),
                 "entries": doc.get("entries", [])}
        live_before = set()
        old_k = {}
        for key in ("skills", "rites", "gems", "entries"):
            for e in old.get(key, []) or []:
                if isinstance(e, dict) and e.get("status", "live") == "live":
                    live_before.add((key, e.get("id")))
                if isinstance(e, dict) and isinstance(e.get("k"), dict):
                    old_k[(key, e.get("id"))] = e["k"]
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
                top = 3 if rel == "gems.json" or key == "gems" else 2      # (a gem can be legendary)
                if not isinstance(r, NUM) or int(r) not in range(top + 1):
                    raise ValueError(f"{i}: rarity must be 0 common, 1 uncommon, 2 rare" + (" or 3 legendary" if top == 3 else ""))
                for f in ("mana", "cd", "use", "power", "range", "max", "lvl"):
                    if f in e and e[f] is not None and (not isinstance(e[f], NUM) or e[f] < 0):
                        raise ValueError(f"{i}: {f} must be a number of 0 or more")
                if "fx" in e and not (isinstance(e["fx"], dict) and all(isinstance(v, NUM) for v in e["fx"].values())):
                    raise ValueError(f"{i}: every fx value must be a number")
                if "k" in e:
                    # a run talent's settings: numbers, and words some procs read (e.g. "src": "attack")
                    if not (isinstance(e["k"], dict) and all(isinstance(v, (int, float, str)) for v in e["k"].values())):
                        raise ValueError(f"{i}: every k value must be a number or a word")
                    was = old_k.get((key, i), {})
                    for kk, v in e["k"].items():
                        if kk in was and isinstance(was[kk], str) != isinstance(v, str):
                            raise ValueError(f"{i}: k {kk} must stay a {'word' if isinstance(was[kk], str) else 'number'}")
                if st == "live" and (key, i) not in live_before:
                    if key == "rites" and fx_ok(e.get("fx"), keys):
                        continue     # a new rite made of keys the game reads: live straight away
                    raise ValueError(f"{i}: only a rite made of effects the game already reads ({', '.join(keys)}, "
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

    def sync(self, force=False):
        """Live mode: bring the checkout up to the newest origin/<live>, replaying the editor's unpublished commits on
        top. Called under LOCK. Never touches a checkout with uncommitted changes; a conflict is aborted and reported."""
        if not self.live or (not force and time.time() - self.synced < SYNC_EVERY):
            return
        self.synced = time.time()
        if self.git("status", "--porcelain", "--untracked-files=no", check=False):
            self.sync_error = "the checkout has uncommitted changes: not following staging until they're committed"
            if force:
                raise ValueError(self.sync_error)
            return
        try:
            self.git("fetch", "-q", "origin", self.live)
            if self.git("rev-list", "--count", f"HEAD..origin/{self.live}") != "0":
                if self.git("rev-list", "--count", f"origin/{self.live}..HEAD") == "0":
                    self.git("merge", "-q", "--ff-only", f"origin/{self.live}")
                else:
                    r = subprocess.run(["git", "-C", str(self.repo), "rebase", "-q", f"origin/{self.live}"],
                                       capture_output=True, text=True)
                    if r.returncode != 0:
                        self.git("rebase", "--abort", check=False)
                        raise RuntimeError("the unpublished edits conflict with a newer " + self.live
                                           + ": someone changed the same entries in the game; ask Claude-2 to merge them")
            self.sync_error = ""
        except RuntimeError as e:
            self.sync_error = str(e)
            if force:
                raise

    def _godot(self, script, what):
        if not self.godot:
            raise ValueError("publishing to the game needs --godot (the codex export and test run first)")
        try:
            r = subprocess.run([self.godot, "--headless", "--path", str(self.repo), "-s", "tools/_late.gd", "--",
                                f"res://tools/{script}.gd"], capture_output=True, text=True, timeout=600)
        except subprocess.TimeoutExpired:
            raise RuntimeError(f"the {what} timed out: nothing was published")
        return r, r.stdout + r.stderr

    def export(self):
        """Live mode: fold what the code changed since the last export into the codex (Codex's three-way merge keeps
        the editor's own edits), and commit it on its own."""
        r, out = self._godot("codex_export", "codex export")
        if r.returncode != 0 or "[codex_export]" not in out:
            raise RuntimeError("the codex export failed, nothing was published: " + out[-300:])
        if self.git("status", "--porcelain", "--", "data/codex", check=False):
            self.git("add", "--", "data/codex")
            self.git("commit", "-q", "-m", "Codex: brought up to date with the code (tools/codex_export.gd)\n\n"
                     "Run by the Hero Codex editor before publishing.", "--", "data/codex")

    def check(self):
        """Live mode: tools/codex_test.gd on the checkout (the game and the codex agree, every file loads)."""
        r, out = self._godot("codex_test", "codex test")
        if r.returncode != 0 or "SCRIPT ERROR" in out or "[codex_test] PASS" not in out:
            fails = [ln for ln in out.splitlines() if "[FAIL]" in ln or "SCRIPT ERROR" in ln][:6]
            raise RuntimeError("the codex test failed, nothing was published: " + ("; ".join(fails) or out[-300:]))

    def publish(self):
        if self.live:
            return self.publish_live()
        with LOCK:
            br = self.git("branch", "--show-current")
            if not br.startswith("claude-2/"):
                raise ValueError(f"publishing is only allowed from a claude-2/ task branch (on {br})")
            self.git("fetch", "-q", "origin", br, check=False)
            self.git("push", "-q", "origin", f"HEAD:{br}")
            self.git("push", "-q", "origin", "HEAD:test-codex")
        return {"pushed": [br, "test-codex"], "commit": self.git("log", "-1", "--format=%h %s"),
                "preview": "https://github.com/jjcw1337-rgb/ashen-crown/actions/workflows/preview.yml"}

    def publish_live(self):
        with LOCK:
            br = self.git("branch", "--show-current")
            if br != LIVE_BRANCH:
                raise ValueError(f"publishing to {self.live} is only allowed from {LIVE_BRANCH} (on {br})")
            for attempt in range(2):
                self.sync(force=True)
                if self.git("rev-list", "--count", f"origin/{self.live}..HEAD") == "0":
                    return {"pushed": [], "commit": self.git("log", "-1", "--format=%h %s"),
                            "note": f"nothing new: the game ({self.live}) already has every saved edit"}
                self.export()
                self.check()
                r = subprocess.run(["git", "-C", str(self.repo), "push", "-q", "origin", f"HEAD:{self.live}"],
                                   capture_output=True, text=True)
                if r.returncode == 0:
                    self.git("fetch", "-q", "origin", self.live, check=False)
                    return {"pushed": [self.live], "commit": self.git("log", "-1", "--format=%h %s"),
                            "note": f"in the game: pushed to {self.live}"}
                if "rejected" not in (r.stderr + r.stdout) and "non-fast-forward" not in (r.stderr + r.stdout):
                    raise RuntimeError((r.stderr or r.stdout).strip()[-400:])
            raise RuntimeError(f"{self.live} kept moving while publishing: try again in a minute")


NO_KEY = (b"<!doctype html><meta charset=utf-8><title>Hero Codex</title><body style='font:16px system-ui;"
          b"background:#15120f;color:#e8dcc4;padding:40px'><h2>Hero Codex</h2><p>Open the Codex with its link "
          b"(the one with <code>?key=</code>). Ask Claude-2 for it.</p>")


def _secret(path: Path, n: int) -> str:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(secrets.token_urlsafe(n) + "\n")
        path.chmod(0o600)
        print(f"[codex] a new secret was generated in {path}", flush=True)
    return path.read_text().strip()


def make_handler(codex: Codex, password: str, link_key: str):
    index = (HERE / "index.html").read_bytes()

    class H(BaseHTTPRequestHandler):
        server_version = "HeroCodex/1"

        def log_message(self, fmt, *a):
            line = re.sub(r"key=[^& ]+", "key=***", fmt % a)          # the key never lands in the log
            sys.stderr.write("[codex] %s %s\n" % (self.address_string(), line))

        def _authed(self):
            url = urlsplit(self.path)
            self.route = url.path
            self.who = re.sub(r"[^A-Za-z0-9 _-]", "", self.headers.get("X-Codex-Who", ""))[:24] or "codex"
            q = parse_qs(url.query).get("key", [""])[0]
            if q and hmac.compare_digest(q.encode(), link_key.encode()):
                # the link is the key: a cookie remembers it, and the address bar loses it
                self.send_response(303)
                self.send_header("Set-Cookie", f"codex_key={link_key}; Max-Age=31536000; Path=/; HttpOnly; Secure; SameSite=Lax")
                self.send_header("Location", url.path or "/")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return False
            jar = SimpleCookie()
            try:
                jar.load(self.headers.get("Cookie", ""))
            except Exception:
                pass
            if "codex_key" in jar and hmac.compare_digest(jar["codex_key"].value.encode(), link_key.encode()):
                return True
            h = self.headers.get("Authorization", "")
            if h.startswith("Basic "):
                try:
                    user, _, pw = base64.b64decode(h[6:]).decode().partition(":")
                    if hmac.compare_digest(pw.encode(), password.encode()):
                        self.who = re.sub(r"[^A-Za-z0-9 _-]", "", user)[:24] or "codex"
                        return True
                except Exception:
                    pass
            self.send_response(401)                 # no WWW-Authenticate: no login prompt, just how to get in
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(NO_KEY)))
            self.end_headers()
            self.wfile.write(NO_KEY)
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
            if self.route in ("/", "/index.html"):
                return self._send(200, index, "text/html; charset=utf-8")
            if self.route == "/api/codex":
                with LOCK:
                    codex.sync()       # live: follow the newest staging (at most once a minute)
                return self._send(200, codex.bundle())
            m = re.match(r"^/icon/(skills|talents)/([a-z0-9_]{1,40})\.png$", self.route)
            if m:
                f = codex.repo / "assets" / "textures" / m.group(1) / (m.group(2) + ".png")
                if f.is_file():
                    return self._send(200, f.read_bytes(), "image/png")
                return self._send(404, {"error": "no icon"})
            self._send(404, {"error": "not found"})

        def do_PUT(self):
            if not self._authed():
                return
            if not self.route.startswith("/api/file/"):
                return self._send(404, {"error": "not found"})
            try:
                n = int(self.headers.get("Content-Length", "0"))
                if n > 2_000_000:
                    raise ValueError("too large")
                body = json.loads(self.rfile.read(n))
                rel = self.route[len("/api/file/"):]
                git = codex.save(rel, body.get("doc"), self.who, body.get("base"))
                self._send(200, {"ok": True, "git": git, "hash": codex.digest(codex.dir / rel)})
            except (ValueError, RuntimeError, json.JSONDecodeError) as e:
                self._send(400, {"error": str(e)})

        def do_POST(self):
            if not self._authed():
                return
            if self.route != "/api/publish":
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
    ap.add_argument("--live", default=None, help="a branch (staging): Publish tests and pushes the edits into it")
    ap.add_argument("--godot", default=os.environ.get("GODOT"), help="the Godot binary for the codex test (--live)")
    a = ap.parse_args()
    pf = Path(a.password_file)
    if not pf.exists():
        pf.parent.mkdir(parents=True, exist_ok=True)
        pf.write_text(secrets.token_urlsafe(9) + "\n")
        pf.chmod(0o600)
        print(f"[codex] a password was generated in {pf}")
    password = pf.read_text().strip()
    link_key = _secret(pf.parent / "link_key", 18)
    codex = Codex(Path(a.repo).resolve(), a.live, a.godot)
    if a.live:
        br = codex.git("branch", "--show-current", check=False)
        if br != LIVE_BRANCH:
            sys.exit(f"[codex] --live needs a checkout of its own on {LIVE_BRANCH} (this one is on {br or 'no branch'})")
        with LOCK:
            codex.sync(force=False)
    codex.bundle()
    srv = ThreadingHTTPServer((a.host, a.port), make_handler(codex, password, link_key))
    print(f"[codex] serving {codex.dir} on http://{a.host}:{a.port}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
