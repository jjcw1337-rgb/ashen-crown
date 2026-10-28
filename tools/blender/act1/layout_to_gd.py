"""Writes a monster's joint layout (from rig_monster.py) into scripts/meshy_monster.gd MODELS, between
the "# monster models begin/end" markers (replacing that kind's entry).
    python3 layout_to_gd.py <kind> layout.json"""
import json, sys, re, os
kind, src = sys.argv[1], sys.argv[2]
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
line = f'\t"{kind}": {{"glb": "res://assets/models/monsters/{kind}.glb", "height": {d["height"]}, "layout": {{{lay}}}}},'
path = os.path.join(os.path.dirname(__file__), "../../../scripts/meshy_monster.gd")
src_gd = open(path).read()
m = re.search(r"# monster models begin\n(.*?)\t# monster models end", src_gd, re.S)
assert m, "markers missing"
lines = [l for l in m.group(1).split("\n") if l.strip() and not l.strip().startswith(f'"{kind}"')]
lines.append(line)
new = src_gd[:m.start(1)] + "\n".join(lines) + "\n" + src_gd[m.end(1):]
open(path, "w").write(new)
print("wrote", kind, len(order), "joints")
