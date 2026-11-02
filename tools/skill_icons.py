"""Skill icons for the action bar and the skill book (SkillGlyph draws a painted icon when there is one, else its
drawn glyph): painted with Meshy as one 3x3 grid per class (6 credits a grid), cut into 128 px icons at
assets/textures/skills/<skill id>.png. Cells follow the class's list in CELLS; "-" cells are spares.

  python3 tools/skill_icons.py prompt plague                    # the grid's prompt
  python3 tools/meshy/meshy.py draw "$(python3 tools/skill_icons.py prompt plague)" -o art/skills_plague
  python3 tools/skill_icons.py cut art/skills_plague.png plague [inset]
Run `godot --headless --editor --quit-after 400` after, to import them.
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from talent_icons import PAL, _cuts

STYLE = ("A 3x3 grid of nine square fantasy action-RPG skill icons for a dark gothic game like Diablo, evenly spaced "
         "with thin solid black gutters between cells. Each icon is a richly hand-painted, dramatic illustration of an "
         "ability in motion, with strong rim lighting, deep shadows, one bold central subject readable at small size, "
         "and a dark vignette background. No text, no letters, no numbers, no borders or frames. Palette: {pal}. "
         "Left to right, top to bottom: {cells}.")
CELLS = {
    "plague": [
        ("toxic", "a corked glass vial of glowing green poison tumbling through the air, about to shatter, droplets flying"),
        ("swarm", "a dense black swarm of plague flies with glowing green eyes pouring out of an open gothic brass reliquary"),
        ("bloom", "a monstrous corpse flower with swollen glowing spore sacs bursting out of cracked earth, black thorned roots spreading"),
        ("fog", "a brass censer on wet cobblestones pouring thick pale lavender fog, a cloaked figure fading into it"),
        ("transfusion", "a gloved arm with a brass needle and hose running to glass tanks of glowing red serum, a glassy shimmer around it"),
        ("experiment", "a brass-bound glass vat bursting open, green bile flooding out and a twisted homunculus clawing free"),
        ("plague_attack", "a crow-skull-handled iron-shod cane striking down, leaving a sickly green arc"),
        ("-", "a plague doctor's beaked mask with glowing green goggles"),
        ("-", "a rat skull on a plague cross"),
    ],
}

def prompt(cls):
    return STYLE.format(pal=PAL[cls], cells="; ".join(f"({i+1}) {c[1]}" for i, c in enumerate(CELLS[cls])))

def cut(png, cls, inset=0.05, outdir="assets/textures/skills"):
    import numpy as np
    from PIL import Image
    im = Image.open(png).convert("RGB")
    a = np.asarray(im).astype(float).mean(2)
    cols, rows = _cuts(a.std(0), a.shape[1]), _cuts(a.std(1), a.shape[0])
    os.makedirs(outdir, exist_ok=True)
    names = []
    for n, (name, _) in enumerate(CELLS[cls]):
        if name == "-":
            continue
        (x0, x1), (y0, y1) = cols[n % 3], rows[n // 3]
        ix, iy = (x1 - x0) * inset, (y1 - y0) * inset
        c = im.crop((int(x0 + ix), int(y0 + iy), int(x1 - ix), int(y1 - iy)))
        c.resize((128, 128), Image.LANCZOS).save(os.path.join(outdir, name + ".png"))
        names.append(name)
    print(cls, "cells", cols, rows, "->", names)

if __name__ == "__main__":
    if sys.argv[1] == "prompt":
        print(prompt(sys.argv[2]))
    elif sys.argv[1] == "cut":
        cut(sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 0.05)
