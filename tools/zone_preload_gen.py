#!/usr/bin/env python3
"""Turn the game's recorded zone file lists (user://zone_preload_record.json, ZonePreload.record) into
game/systems/loading/zone_preload_data.gd.  python3 tools/zone_preload_gen.py [record.json]"""
import json, os, sys
src = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/Library/Application Support/Godot/app_userdata/Ashen Crown/zone_preload_record.json")
d = json.load(open(src))
out = ["class_name ZonePreloadData",
       "## Recorded by ZonePreload.record (see zone_preload.gd); regenerate with tools/zone_preload_gen.py.",
       "const PATHS := {"]
for k in sorted(d):
    out.append('\t"%s": [' % k)
    for p in d[k]:
        out.append('\t\t"%s",' % p)
    out.append("\t],")
out.append("}")
open(os.path.join(os.path.dirname(__file__), "..", "scripts", "zone_preload_data.gd"), "w").write("\n".join(out) + "\n")
print({k: len(v) for k, v in d.items()})
