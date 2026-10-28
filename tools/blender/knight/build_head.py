import sys, numpy as np
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from sdf import mesh, write_ply
from model import head_skin
out = sys.argv[1]
step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0012
import time; t = time.time()
v, f = mesh(head_skin(), [-0.11, -0.13, 1.53], [0.11, 0.13, 1.93], step)
write_ply(out, v, f)
print("head", len(v), "verts", len(f), "tris", round(time.time() - t, 1), "s")
