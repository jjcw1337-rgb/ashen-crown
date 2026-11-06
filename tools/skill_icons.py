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
    # the Warlock's three directions (WarlockHex): Corruption, Fear, Drain; two grids
    "warlock": [
        ("w_corruption", "a withered clawed hand casting a twisting curse of fel green smoke and runes onto a shadowed foe"),
        ("w_malediction", "a crackling fel green bolt with a screaming skull face hurtling forward, rings of curse runes around it"),
        ("w_unending", "an hourglass wrapped in rotting vines with sickly yellow-green sand that never runs out, decay spreading"),
        ("w_festering", "a pulsing violet hex sigil bursting with pus and green sparks over a stunned, staggering silhouette"),
        ("w_leeching", "blood red curse threads pulled out of a writhing figure into an open clawed palm"),
        ("w_reckoning", "a pale white-green skull of judgement with many curse rings converging on it, blinding light in its eyes"),
        ("w_terrify", "a terrified ghostly face screaming as a beautiful violet void spirit with fel green eyes looms out of the dark"),
        ("w_effigy", "a sinister carved jungle idol totem wrapped in black thorned vines, glowing fel green eyes, violet wisps orbiting it"),
        ("w_darkwind", "a bright wisp of violet and green void light bouncing between dark silhouettes, leaving glowing trails"),
    ],
    "warlock2": [
        ("w_crowstorm", "a whirling vortex of glowing violet petals, void wisps and lashing black vines around a hooded spirit, an eclipse above"),
        ("w_leechbolt", "a quick pale green bolt of shadow with motes of stolen life streaming back along its trail"),
        ("w_harvest", "a whip of black thorned jungle vines lashing in a full circle, a ring of pale green life motes rising from its arc"),
        ("w_soulfeast", "many fel green drain beams converging into a raised clawed hand, a glassy green shield forming"),
        ("-", "a black crow feather"),
        ("-", "a cracked green glass orb"),
        ("-", "a purple skull candle"),
        ("-", "a rusted sickle"),
        ("-", "a stitched burlap sack mask"),
    ],
}
# the void re-theme (Blaine 2026-11-06: no crows): the changed icons in one grid
CELLS["warlock_void"] = [c for c in CELLS["warlock"] if c[0] in ("w_terrify", "w_effigy", "w_darkwind")] + \
    [c for c in CELLS["warlock2"] if c[0] in ("w_crowstorm", "w_harvest")]
# the Warlock's rites (WarlockHex.RITE_KEYS, data/codex): cut into assets/textures/talents/<id>.png, where the run's
# window looks for a passive's icon (UI.TALENT_ICON): `cut art.png warlock_rites1 0.05 assets/textures/talents`
CELLS["warlock_rites1"] = [
    ("w_r_lingering", "green rot dripping from a cursed wound, drops falling slowly"),
    ("w_r_decay", "a skeletal hand holding a cracked hourglass oozing green rot"),
    ("w_r_thrift", "a half-empty flask of glowing green curse ink with a quill"),
    ("w_r_vile", "green curse smoke curling into a glowing heart"),
    ("w_r_echo", "concentric green curse rings echoing outward from a skull"),
    ("w_r_haunt", "a ghostly hand reaching out of shadow, violet glow"),
    ("w_r_nightmare", "a screaming face reflected in a black mirror, violet cracks"),
    ("w_r_panic", "a crowd of shadowy silhouettes fleeing in terror from violet void light"),
    ("w_r_dread", "a black thorned vine coiling through a skull, green motes rising"),
]
CELLS["warlock_rites2"] = [
    ("w_r_paralysis", "black thorny roots binding a figure's feet, violet glow"),
    ("w_r_pact", "a clawed hand and a goblet of green blood sealed by a fel rune"),
    ("w_r_bloodward", "a glowing green glass shield forming over a beating heart"),
    ("w_r_gorge", "a gaping maw of shadow drinking a stream of pale green life"),
    ("w_r_hunger", "a green glass shield cracked open with drain beams forking out of it"),
    ("-", "a crow skull"),
    ("-", "a fel green candle"),
    ("-", "a rune stone"),
    ("-", "a cursed coin"),
]
CELLS["warlock_void"] += [c for c in CELLS["warlock_rites1"] if c[0] in ("w_r_panic", "w_r_dread")] + \
    [("-", "a glowing violet orchid"), ("-", "a black thorned vine")]
# her four original skills, in the same hand as the rest (and spares)
CELLS["warlock_core"] = [
    ("drain", "a forked fel green beam of life essence torn out of a screaming silhouette into a raised clawed hand"),
    ("blight", "a howling fel green skull bolt bursting into a bubbling plague pool"),
    ("shackles", "chains of fel green fire snapping out from a glowing sigil to bind shadowy figures"),
    ("covenant", "two clawed hands sealing a pact over a burning fel green sigil, a crown of green flame rising"),
    ("-", "a cracked green glass orb with blood inside"),
    ("-", "a black thorned heart dripping green rot"),
    ("-", "a violet eye in a ring of thorns"),
    ("-", "a glowing green orchid"),
    ("-", "a vine-wrapped jungle idol mask"),
]
for k in ["warlock2", "warlock_rites1", "warlock_rites2", "warlock_void", "warlock_core"]:
    PAL.setdefault(k, PAL["warlock"])

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
        cut(sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 0.05, *sys.argv[5:6])
