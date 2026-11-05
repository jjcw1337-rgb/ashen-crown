"""The camp island's sky textures (jj, 2026-11-04: the World-Tree Island in space, "use real space images"):
    python3 tools/space_textures.py <real dir> <meshy island dir> assets/textures/space
<real dir> holds the downloads (sources and licences in assets/textures/space/CREDITS.md):
  eso0932a_large.jpg       ESO's 360-degree panorama of the Milky Way (ESO/S. Brunier, CC BY 4.0), equirectangular in
                           galactic coordinates: the whole sky (milkyway_eso.jpg, 4096 x 2048)
  2k_saturn.jpg            Saturn's surface, and 8k_saturn_ring_alpha.png its rings' radial profile with their alpha
                           (Solar System Scope, CC BY 4.0): the ringed giant (saturn.jpg, saturn_rings.png 2048 x 8)
<meshy island dir>/comet.png is Meshy's painted comet: black lifted out into alpha (comet.png).
"""
import sys, os
import numpy as np
from PIL import Image

real, meshy, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
Image.open(os.path.join(real, "eso0932a_large.jpg")).convert("RGB").resize((4096, 2048), Image.LANCZOS).save(
    os.path.join(out, "milkyway_eso.jpg"), quality=90)
Image.open(os.path.join(real, "2k_saturn.jpg")).convert("RGB").save(os.path.join(out, "saturn.jpg"), quality=92)
Image.open(os.path.join(real, "8k_saturn_ring_alpha.png")).convert("RGBA").resize((2048, 8), Image.LANCZOS).save(
    os.path.join(out, "saturn_rings.png"))
c = np.asarray(Image.open(os.path.join(meshy, "comet.png")).convert("RGB")).astype(np.float32) / 255.0
al = np.clip(c.max(2) * 1.4 - 0.04, 0, 1)
col = c / np.maximum(c.max(2, keepdims=True), 1e-3)
rgba = np.concatenate([np.clip(col, 0, 1), al[..., None]], 2)
Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").resize((1024, 576), Image.LANCZOS).save(os.path.join(out, "comet.png"))
print("wrote", sorted(os.listdir(out)))
