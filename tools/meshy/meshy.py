#!/usr/bin/env python3
"""Meshy (meshy.ai) command-line client: generate 3D models for the game. Stdlib only.

The API key is read from $MESHY_API_KEY, or from ~/.config/meshy/key (never put it in the repo).
Needs network access to api.meshy.ai and assets.meshy.ai, and a paid Meshy plan (API keys).

  python3 tools/meshy/meshy.py text  "a rugged knight..." -o out/knight [--pose a-pose] [--polys 30000] [--texture "..."]
  python3 tools/meshy/meshy.py image ref.png           -o out/knight [--pose a-pose] [--polys 30000]
  python3 tools/meshy/meshy.py get   <task id> [--kind image|text]   -o out/knight   # re-download a finished task
  python3 tools/meshy/meshy.py draw  "an old oak tree..." -o out/ref     [--model nano-banana-2]    # 2D image from text
  python3 tools/meshy/meshy.py edit  ref.png "remove the belt" -o out/ref2 [--ref more.png] [--aspect 16:9]   # 2D image edit
  python3 tools/meshy/meshy.py rig   <image/text task id> -o out/npc [--height 1.75]   # skeleton + skin (humanoids)
  python3 tools/meshy/meshy.py animate <rig task id> 0,128 -o out/npc_anims          # library clips, one glb
  python3 tools/meshy/meshy.py library [search]                                     # list animation clips (free)
  python3 tools/meshy/meshy.py check                                                # key + network test

Each finished task saves <out>.glb, <out>_thumb.png and <out>.json (the task record).
Downloads expire after 3 days on Meshy's side, so fetch results promptly. Generations cost credits.
"""
import argparse, base64, json, mimetypes, os, sys, time, urllib.error, urllib.request

API = "https://api.meshy.ai/openapi"


def key() -> str:
    k = os.environ.get("MESHY_API_KEY", "").strip()
    if not k:
        p = os.path.expanduser("~/.config/meshy/key")
        if os.path.exists(p):
            k = open(p).read().strip()
    if not k:
        sys.exit("No Meshy API key: set MESHY_API_KEY or write it to ~/.config/meshy/key")
    return k


def call(method: str, path: str, body=None) -> dict:
    req = urllib.request.Request(API + path, method=method, headers={"Authorization": "Bearer " + key(), "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"Meshy {method} {path}: HTTP {e.code} {e.read().decode(errors='replace')[:500]}")


def wait(path: str) -> dict:
    last = -1
    while True:
        t = call("GET", path)
        st, pr = t.get("status"), t.get("progress", 0)
        if pr != last:
            print(f"  {st} {pr}%", flush=True)
            last = pr
        if st == "SUCCEEDED":
            return t
        if st in ("FAILED", "CANCELED"):
            sys.exit(f"task {st}: {t.get('task_error')}")
        time.sleep(6)


def fetch(url: str, dest: str) -> None:
    with urllib.request.urlopen(url, timeout=300) as r, open(dest, "wb") as fh:
        fh.write(r.read())
    print("  saved", dest)


def save(task: dict, out: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    json.dump(task, open(out + ".json", "w"), indent=2)
    urls = task.get("model_urls") or {}
    if "glb" in urls:
        fetch(urls["glb"], out + ".glb")
    if task.get("thumbnail_url"):
        fetch(task["thumbnail_url"], out + "_thumb.png")
    for side, u in (task.get("thumbnail_urls") or {}).items():
        if u:
            fetch(u, f"{out}_{side}.png")
    print(f"  credits used: {task.get('consumed_credits')}")


def image_ref(src: str) -> str:
    if src.startswith(("http://", "https://", "data:")):
        return src
    mime = mimetypes.guess_type(src)[0] or "image/png"
    return f"data:{mime};base64," + base64.b64encode(open(src, "rb").read()).decode()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["text", "image", "edit", "draw", "get", "check", "rig", "animate", "library"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("arg2", nargs="?")
    ap.add_argument("-o", "--out", default="meshy_out/model")
    ap.add_argument("--pose", default="a-pose", help="a-pose, t-pose or '' (rigging wants a-pose)")
    ap.add_argument("--polys", type=int, default=30000)
    ap.add_argument("--texture", default="", help="texture prompt for the refine pass")
    ap.add_argument("--model", default="latest")
    ap.add_argument("--kind", default="image")
    ap.add_argument("--cutout", action="store_true", help="draw: transparent background")
    ap.add_argument("--aspect", default="", help="draw/edit: aspect ratio, e.g. 16:9")
    ap.add_argument("--ref", action="append", default=[], help="edit: another reference image (repeatable)")
    ap.add_argument("--height", type=float, default=1.75, help="rig: character height in metres")
    a = ap.parse_args()
    if a.cmd == "check":
        req = urllib.request.Request(API + "/v1/balance", headers={"Authorization": "Bearer " + key()})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                print("Meshy OK:", r.read().decode()[:200])
        except urllib.error.HTTPError as e:
            print("Meshy reachable, HTTP", e.code, e.read().decode(errors="replace")[:200])
        return
    if a.cmd == "library":
        lib = call("GET", "/v1/animations/library?page_size=1000")
        items = lib if isinstance(lib, list) else lib.get("result", [])
        for it in items:
            if not a.arg or a.arg.lower() in json.dumps(it).lower():
                print(it.get("action_id"), it.get("name"), "-", it.get("category"), "/", it.get("sub_category"))
        return
    if a.cmd == "rig":
        tid = call("POST", "/v1/rigging", {"input_task_id": a.arg, "height_meters": a.height})["result"]
        print("rig task", tid)
        t = wait(f"/v1/rigging/{tid}")
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        json.dump(t, open(a.out + ".json", "w"), indent=2)
        r = t.get("result") or {}
        if r.get("rigged_character_glb_url"):
            fetch(r["rigged_character_glb_url"], a.out + ".glb")
        print(f"  rig task id {tid}   credits used: {t.get('consumed_credits')}")
        return
    if a.cmd == "animate":
        ids = [int(x) for x in a.arg2.split(",")]
        body = {"rig_task_id": a.arg, ("action_id" if len(ids) == 1 else "action_ids"): ids[0] if len(ids) == 1 else ids}
        tid = call("POST", "/v1/animations", body)["result"]
        print("animation task", tid)
        t = wait(f"/v1/animations/{tid}")
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        json.dump(t, open(a.out + ".json", "w"), indent=2)
        r = t.get("result") or {}
        if r.get("animation_glb_url"):
            fetch(r["animation_glb_url"], a.out + ".glb")
        print(f"  credits used: {t.get('consumed_credits')}")
        return
    common = {"ai_model": a.model, "pose_mode": a.pose, "should_remesh": True, "topology": "triangle",
              "target_polycount": a.polys, "target_formats": ["glb"]}
    if a.cmd == "text":
        print("preview (shape)...")
        pid = call("POST", "/v2/text-to-3d", {"mode": "preview", "prompt": a.arg, **common})["result"]
        wait(f"/v2/text-to-3d/{pid}")
        print("refine (textures)...")
        body = {"mode": "refine", "preview_task_id": pid, "enable_pbr": True, "target_formats": ["glb"]}
        if a.texture:
            body["texture_prompt"] = a.texture
        rid = call("POST", "/v2/text-to-3d", body)["result"]
        save(wait(f"/v2/text-to-3d/{rid}"), a.out)
    elif a.cmd == "draw":
        model = a.model if a.model != "latest" else "nano-banana-2"
        body = {"ai_model": model, "prompt": a.arg}
        if a.cutout:
            body["remove_background"] = True
        if a.aspect:
            body["aspect_ratio"] = a.aspect
        tid = call("POST", "/v1/text-to-image", body)["result"]
        print("task", tid)
        t = wait(f"/v1/text-to-image/{tid}")
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        json.dump(t, open(a.out + ".json", "w"), indent=2)
        for i, u in enumerate(t.get("image_urls") or []):
            fetch(u, a.out + (f"_{i}" if i else "") + ".png")
        print(f"  credits used: {t.get('consumed_credits')}")
    elif a.cmd == "edit":
        model = a.model if a.model != "latest" else "nano-banana-2"
        body = {"ai_model": model, "prompt": a.arg2, "reference_image_urls": [image_ref(a.arg)] + [image_ref(r) for r in a.ref]}
        if a.aspect:
            body["aspect_ratio"] = a.aspect
        tid = call("POST", "/v1/image-to-image", body)["result"]
        print("task", tid)
        t = wait(f"/v1/image-to-image/{tid}")
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        json.dump(t, open(a.out + ".json", "w"), indent=2)
        for i, u in enumerate(t.get("image_urls") or []):
            fetch(u, a.out + (f"_{i}" if i else "") + ".png")
        print(f"  credits used: {t.get('consumed_credits')}")
    elif a.cmd == "image":
        body = {"image_url": image_ref(a.arg), "should_texture": True, "enable_pbr": True, "multi_view_thumbnails": True, **common}
        if a.texture:
            body["texture_prompt"] = a.texture
        tid = call("POST", "/v1/image-to-3d", body)["result"]
        print("task", tid)
        save(wait(f"/v1/image-to-3d/{tid}"), a.out)
    else:
        path = f"/v2/text-to-3d/{a.arg}" if a.kind == "text" else f"/v1/image-to-3d/{a.arg}"
        save(call("GET", path), a.out)


if __name__ == "__main__":
    main()
