"""Writes a Meshy model's joint layout (from rig_monster.py) onto its monster's card,
game/monsters/<folder>/monster.gd RIGS, between the "# rigs begin/end" markers (replacing that model's entry).
The model is game/monsters/<folder>/<mesh>.glb, and the kind's Data.ENEMIES entry names it with "mesh".
    python3 layout_to_gd.py <folder> <mesh> layout.json"""
import json, sys, re, os
folder, kind, src = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src))
L, P = d["layout"], d["parents"]
order = []
def visit(n):
    if n in order:
        return
    if P.get(n):
        visit(P[n])
    order.append(n)
for n in L:
    visit(n)
f = lambda v: repr(round(float(v), 4) + 0.0)
lay = ", ".join(f'"{n}": ["{P.get(n) or ""}", Vector3({f(L[n][0])}, {f(L[n][1])}, {f(L[n][2])})]' for n in order)
line = f'\t"{kind}": {{"glb": "res://game/monsters/{folder}/{kind}.glb", "height": {d["height"]}, "layout": {{{lay}}}}},'
path = os.path.join(os.path.dirname(__file__), "../../../game/monsters", folder, "monster.gd")
src_gd = open(path).read()
m = re.search(r"# rigs begin\n(.*?)\t# rigs end", src_gd, re.S)
assert m, "no RIGS markers on the card: add const RIGS := {\n\t# rigs begin\n\t# rigs end\n} to it"
lines = [l for l in m.group(1).split("\n") if l.strip() and not l.strip().startswith(f'"{kind}"')]
lines.append(line)
new = src_gd[:m.start(1)] + "\n".join(lines) + "\n" + src_gd[m.end(1):]
open(path, "w").write(new)
print("wrote", kind, len(order), "joints")
