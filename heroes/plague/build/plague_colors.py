"""The plague doctor's colour schemes (Plague.COLORS / Plague.dye): recolours the dark leather of his coat, cape, hat,
gloves and boots in the Meshy albedo, keeping the brown straps and pouches, the silver mask, the brass (goggles, censer,
buckles: found by the metallic map) and the coloured vials as they are. Like heroes/archer/build/archer_colors.py for the ranger.

  # the albedo and the metal/roughness map out of the glb (Blender):
  blender -b --python heroes/plague/build/dump_textures.py -- heroes/plague/body/plague_doctor.glb outdir
  blender -b --python heroes/plague/build/region_uv.py -- heroes/plague/body/plague_doctor.glb outdir/regions.json
  python3 heroes/plague/build/plague_colors.py outdir/Image_0.png outdir/Image_1.png outdir/regions.json [scheme ...]   # -> assets/textures/plague/coat_<scheme>.jpg

The dye keeps each pixel's lightness (folds, scuffs, stitching survive) and lays the scheme's colour over it, weighted by
how dark and grey the pixel is, so the edges between leather and straps blend instead of cutting.
"""
import os, sys
import numpy as np
from PIL import Image

# Each scheme gives, per region of his leather, the colour a typical dark-leather pixel (lightness 0.18) becomes, or
# None to keep Meshy's black there. Regions (heroes/plague/build/region_uv.py): body = coat, cape, sleeves;
# head = hat (and the mask's leather hood); hands = gloves; feet = boots.
GREEN = (0.13, 0.198, 0.109)
OXBLOOD = (0.25, 0.075, 0.065)
ASH = (0.33, 0.31, 0.27)
SCHEMES = {
    "plague": {"body": GREEN, "head": GREEN, "hands": GREEN, "feet": GREEN},       # deep plague green all over
    "plague2": {"body": GREEN, "head": None, "hands": None, "feet": None},         # green coat, black hat, gloves, boots
    "oxblood": {"body": OXBLOOD, "head": OXBLOOD, "hands": OXBLOOD, "feet": OXBLOOD},
    "oxblood2": {"body": OXBLOOD, "head": None, "hands": None, "feet": None},
    "ash2": {"body": ASH, "head": None, "hands": None, "feet": None},              # weathered ash-grey coat, black the rest
}
OUT = "heroes/plague/body/dyes"


def masks(regions_json: str, size: int) -> dict:
    """One soft mask per region, drawn from the UV triangles and grown a few pixels over the seams."""
    import json
    from PIL import ImageDraw, ImageFilter
    reg = json.load(open(regions_json))
    out = {}
    for name, polys in reg.items():
        im = Image.new("L", (size, size), 0)
        d = ImageDraw.Draw(im)
        for poly in polys:
            d.polygon([(u * size, (1.0 - v) * size) for u, v in poly], fill=255)
        im = im.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
        out[name] = np.asarray(im, np.float32) / 255.0
    return out


def dye(albedo: np.ndarray, mr: np.ndarray, scheme: dict, region_masks: dict) -> np.ndarray:
    rgb = albedo[..., :3].astype(np.float32) / 255.0
    mx = rgb.max(axis=2)
    mn = rgb.min(axis=2)
    sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0.0)
    val = mx
    metal = mr[..., 2].astype(np.float32) / 255.0 if mr is not None else np.zeros_like(val)
    # how much of a pixel is the dark leather: dark, grey, not metal
    leather = np.clip((0.33 - val) / 0.09, 0.0, 1.0) * np.clip((0.32 - sat) / 0.12, 0.0, 1.0) * np.clip((0.45 - metal) / 0.2, 0.0, 1.0)
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    out = rgb.copy()
    for region, mid in scheme.items():
        if mid is None:
            continue
        m = region_masks[region] if region_masks else np.ones_like(val)
        w = (leather * m)[..., None]
        dyed = np.clip(lum[..., None] / 0.18 * np.array(mid, np.float32), 0.0, 1.0)
        out = out * (1.0 - w) + dyed * w
    return (out * 255.0 + 0.5).astype(np.uint8)


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    albedo = np.array(Image.open(sys.argv[1]).convert("RGB"))
    mr = np.array(Image.open(sys.argv[2]).convert("RGB"))
    regions = sys.argv[3]
    names = sys.argv[4:] or list(SCHEMES)
    rm = masks(regions, albedo.shape[0])
    os.makedirs(OUT, exist_ok=True)
    for n in names:
        img = Image.fromarray(dye(albedo, mr, SCHEMES[n], rm))
        path = os.path.join(OUT, "coat_%s.jpg" % n)
        img.save(path, quality=90)
        print("wrote", path)


if __name__ == "__main__":
    main()
