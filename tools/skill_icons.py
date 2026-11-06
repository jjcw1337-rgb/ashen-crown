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
    # the run's skills (Blaine's roguelike pass, 2026-11-06): the archer's whole kit
    "archer": [
        ("pierce", "a flaming arrow tearing through the air trailing fire and smoke, embers flying"),
        ("volley", "a fan of icy blue glacier arrows climbing into a frosty night sky"),
        ("snare", "a hooded ranger backflipping away from a golden storm sigil on the ground crackling with lightning"),
        ("beast", "a huge ghostly spirit-green dire wolf lunging forward, fangs bared, mist trailing"),
        ("a_multishot", "five arrows fanning out from a drawn recurve bow, motion streaks behind each"),
        ("a_explosive", "an arrow bursting into a fireball on impact, shockwave and flying debris"),
        ("a_glacial", "a jagged arrow of pure blue ice piercing through three frozen silhouettes in a line"),
        ("a_stormshot", "an arrow wreathed in crackling white-blue lightning that forks into chains of lightning"),
        ("a_mark", "a glowing green hunter's crosshair rune hovering over a snarling beast's head"),
    ],
    # the run's other new skills and its consumables
    "run_mix": [
        ("a_barrage", "a dark sky raining hundreds of arrows down onto a ring on the ground"),
        ("p_miasma", "a brass censer smashing on cobblestones in an explosion of thick toxic green gas"),
        ("p_spread", "a sickly green plague sigil leaping between three hunched figures like a chain"),
        ("p_leech", "a cracked glass jar spilling writhing black blood leeches onto the ground, red glow"),
        ("flask_fire", "a corked round flask of roiling orange fire with flames licking out of the neck"),
        ("flask_frost", "a corked round flask of swirling icy blue frost, ice crystals growing on the glass"),
        ("flask_storm", "a corked round flask with a crackling violet-white lightning storm trapped inside"),
        ("scroll_ward", "an unrolled glowing parchment scroll with a shimmering blue protective rune shield above it"),
        ("tome_insight", "an ancient open tome radiating golden light with runes floating up out of its pages"),
    ],
    "potions": [
        ("elixir_fury", "a tall crystal potion bottle of glowing blood-red elixir with a skull stopper, fiery aura"),
        ("draught_iron", "a heavy iron-banded clay jug of thick brown draught with bark growing over it"),
        ("tonic_swift", "a slender teal glass tonic bottle with a feather tied to it, swirling wind"),
        ("salve_troll", "an open wooden pot of thick glowing green troll salve with a wooden spatula"),
        ("elixir_wrath", "a golden potion bottle crackling with gold sparks and a lion-head stopper"),
        ("phoenix", "a blazing orange phoenix ember gemstone cradled in feathers of fire"),
        ("tempest", "a faceted storm-blue gemstone with a tiny lightning storm swirling inside, an eye at its heart"),
        ("hunger", "a dark blood-red gemstone shaped like a fanged heart, oozing shadow"),
        ("seer", "a cyan crystal eye-shaped gemstone glowing with arcane sight"),
    ],
    "gems": [
        ("ruby", "a single cut ruby gemstone glowing with inner fire"),
        ("sapphire", "a single cut sapphire gemstone rimed with frost"),
        ("emerald", "a single cut emerald gemstone dripping green venom"),
        ("topaz", "a single cut golden topaz gemstone sparking with static"),
        ("amethyst", "a single cut violet amethyst gemstone with dusk mist inside"),
        ("onyx", "a single cut black onyx gemstone with a sharp white glint"),
        ("bloodstone", "a single dark green bloodstone speckled with glowing red"),
        ("jade", "a single carved green jade stone with a leaf pattern"),
        ("moonstone", "a single milky moonstone with a pale blue moon glow"),
    ],
    "warlock": [
        ("w_corruption", "a circle of cursed ground erupting in sickly fel-green flame, rotting skeletal hands reaching up"),
        ("w_soulrend", "ghostly green souls being torn out of shadowy figures and pulled toward a gnome warlock's raised claw"),
        ("w_hellfire", "fel-green meteors of hellfire streaking down from a dark purple sky onto burning ground"),
        ("-", "a warlock's floating grimoire with glowing fel runes"),
        ("covenant", "a fel-green flame in a pact circle"),
        ("-", "a horned gnome warlock's hat glowing green"),
        ("shackles", "green chains of fel fire"),
        ("blight", "a skull of blight howling green smoke"),
        ("-", "a dark purple pact scroll sealed with green wax"),
    ],
    "gems2": [
        ("heartstone", "a heart-shaped rose-red crystal gemstone pulsing with warm light"),
        ("prism", "a clear crystal prism splitting light into a rainbow"),
        ("warstone", "a jagged orange war gemstone set in black iron spikes"),
        ("crownshard", "a glowing golden shard broken from an ancient crown, jewels embedded"),
        ("-", "a pile of cut gemstones in a leather pouch"),
        ("-", "a dark velvet cushion with an empty gem setting"),
        ("-", "a jeweler's loupe over a glowing gem"),
        ("-", "a gem embedded in a sword hilt"),
        ("-", "a gem embedded in a dark ring"),
    ],
}
PAL.setdefault("run_mix", "dark fantasy: deep shadow, warm firelight and cold arcane glows, worn brass and glass")
PAL.setdefault("potions", "dark fantasy alchemy: rich glowing liquids in glass, worn brass and leather, deep shadow")
PAL.setdefault("gems", "dark velvet black background, each gem brilliantly lit, rich saturated jewel colours")
PAL.setdefault("gems2", "dark velvet black background, each gem brilliantly lit, rich saturated jewel colours")

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
