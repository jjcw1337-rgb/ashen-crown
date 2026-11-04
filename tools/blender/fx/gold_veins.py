"""Turns a model's blue glow gold (jj: Thunderstep's thunderstone "should be yellow or gold"): every texture's
saturated blue texels get the hue of gold, keeping how bright and how white they are; the dark rock is untouched.

    blender -b --python tools/blender/fx/gold_veins.py -- <in.glb> <out.glb>
"""
import bpy, sys, colorsys
import numpy as np

a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
GOLD_H = 0.11          # hue of gold (0..1)
for im in bpy.data.images:
    if im.size[0] == 0 or "normal" in im.name.lower():
        continue
    px = np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)
    rgb = px[:, :3]
    mx = rgb.max(1)
    mn = rgb.min(1)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    blue = (rgb[:, 2] >= rgb[:, 0]) & (rgb[:, 2] >= rgb[:, 1] * 0.95) & (sat > 0.18)
    # gold at the same value and saturation (a touch richer), white cores stay white
    v = mx[blue]
    s = np.clip(sat[blue] * 1.15, 0, 1)
    h6 = GOLD_H * 6.0
    c = v * s
    x = c * (1 - abs(h6 % 2 - 1))
    m = v - c
    out = np.stack([c + m, x + m, m], 1)     # hue in [0, 60 deg): r = c, g = x, b = 0
    rgb[blue] = out
    px[:, :3] = rgb
    im.pixels[:] = px.ravel()
    im.pack()
    print("GOLD", im.name, int(blue.sum()), "texels of", len(px))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=88)
