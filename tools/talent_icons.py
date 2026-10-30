"""Talent icons (Talents.TREES): painted with Meshy as one 3x3 grid per tree (6 credits a grid), then cut
into 128 px icons. Cells 1-7 are the tree's talents in the order talents.gd lists them, cell 8 the tree's
emblem (the window's header), cell 9 a spare.

  python3 tools/talent_icons.py prompt knight_0                 # the prompt for a tree (class_treeindex)
  python3 tools/meshy/meshy.py draw "$(python3 tools/talent_icons.py prompt knight_0)" -o art/knight_0
  python3 tools/talent_icons.py cut art/knight_0.png knight_0 [inset]   # -> assets/textures/talents/<id>.png
Cutting needs Pillow and numpy (the audio venv has them). Run `godot --headless --editor --quit` after.
"""
import os, re, sys
STYLE = ("A 3x3 grid of nine square fantasy action-RPG talent icons for a dark gothic game like Diablo, "
         "evenly spaced with thin solid black gutters between cells. Each icon is a richly hand-painted, dramatic "
         "illustration with strong rim lighting, deep shadows, a single bold central subject readable at small size, "
         "and a dark vignette background. No text, no letters, no numbers, no borders or frames. Palette: {pal}. "
         "Left to right, top to bottom: {cells}.")
PAL = {
    "knight": "burnished steel, white-gold holy light, crimson accents",
    "wraith": "icy spectral cyan and pale blue on near-black, ghostly mist",
    "demon": "molten ember orange and red on black obsidian, hellfire",
    "warlock": "sickly fel green and deep purple, eerie glow",
    "archer": "dark forest green, worn leather brown and pale spirit-green glow, misty woods",
}
TREES = {
 "knight_0": ("knight", ["a longsword held upright, its blade burning with white-gold holy fire", "an armored gauntlet slamming a sword down onto cracked stone in a burst of white light", "an expanding ring of golden holy fire bursting outward across the ground", "a sword mid-swing leaving three golden motion arcs", "a blessed sword edge with a brilliant star-shaped glint and glowing runes", "a golden hourglass wrapped in holy flame", "a radiant golden heart sigil glowing on consecrated ground with healing light rising", "a white heater shield with a red cross and a golden sunburst behind it", "a holy sun halo above two crossed swords"]),
 "knight_1": ("knight", ["a heavy dented steel breastplate", "a glowing red heart cradled in a steel gauntlet", "a kite shield with arrows shattering against it", "a knight's great helm inside a shimmering blue protective ward", "a raised tower shield taking a huge blow, sparks flying", "a knight's chest plate with golden-green life wisps swirling around it", "a knight roaring a war cry inside a golden aura, ground cracking", "a stone fortress tower behind a shield", "an iron-bound shield on an anvil"]),
 "knight_2": ("knight", ["an armored steel boot striding forward with a dust trail", "a clenched armored fist raised high", "a knight charging shoulder-first with a shockwave in front", "two crossed longswords striking sparks", "a war horn blasting golden sound waves", "a battle banner with a red cross waving on a pole", "a charging knight leaving golden afterimages and lightning", "a lance head with a red pennant", "a galloping warhorse's head in armor"]),
 "wraith_0": ("wraith", ["a spectral scythe blade glinting icy blue", "a single glowing cyan eye inside a dark hood", "blue soul wisps flowing into a skeletal hand", "a ghostly hooded figure blurred by speed trails", "a scythe tip with a bright star glint", "a skull split by a spectral blade", "a scythe sweeping a full glowing circle under a pale full moon", "a hooded reaper silhouette holding a scythe", "a pale full moon behind dead branches"]),
 "wraith_1": ("wraith", ["a screaming ghostly woman's face with rings of sound", "a glowing blue droplet of mana in spectral mist", "a terrified figure cowering under a looming ghost", "a shadow silhouette dissolving and re-forming in streaks", "an open spectral mouth exhaling freezing mist", "a translucent ghostly body inside a pale blue aura", "two overlapping scream shockwaves echoing outward", "a wailing banshee with streaming hair", "a cracked bell ringing with ghostly sound"]),
 "wraith_2": ("wraith", ["a dark heart bound in glowing spectral chains", "frost-covered dark armor plate", "three glowing spirits circling each other", "a ring of floating ghostly runes", "an hourglass filled with drifting souls", "spectral fangs draining a red wisp of life", "four ghostly riders circling a hooded figure", "a gravestone with a spirit rising from it", "a lantern holding a trapped soul"]),
 "demon_0": ("demon", ["three burning claw marks raked across darkness", "a clenched black obsidian clawed fist with lava cracks", "a burning ember flame", "a roaring horned demon face with motion blur", "a black claw tip with a fiery star glint", "a cracked heart of molten lava", "a huge sweeping arc of hellfire claws", "a flaming horned demon skull", "a burning pitchfork"]),
 "demon_1": ("demon", ["a burning contract scroll signed in blood", "a snarling small demon's face", "a horned heart wreathed in fire", "demon minions running on a fiery chain leash", "a chalice overflowing with blood", "a glowing red blood-pact sigil", "four demons climbing out of a burning summoning circle", "a burning summoning circle with runes", "a demon's clawed hand rising from the ground"]),
 "demon_2": ("demon", ["black obsidian armor plate with glowing ember edges", "scaly crimson demon hide", "a demon stepping through a crimson rift portal", "a dark crimson shield of shadow", "fire erupting from a rift in the ground", "a shadowy fanged maw devouring a red wisp", "a furnace burning with captured souls", "a crimson rift tearing between worlds", "a cracked obsidian obelisk"]),
 "warlock_0": ("warlock", ["a green beam of life essence pulled from a victim into a clawed hand", "a goblet of glowing green liquid", "a glowing green orb above an open grimoire", "a purple crystal vial filling with green energy", "a green beam splitting into three forks", "a withered flower crumbling to ash in green light", "an overflowing chalice spilling green and blue essence", "a tall horned wizard hat with green flame", "a floating grimoire wrapped in chains"]),
 "warlock_1": ("warlock", ["a howling green skull bolt", "a bubbling pool of green plague slime", "a rotting green skull with speed trails", "a heart pulsing with sickly green veins", "a widening ring of green plague mist on the ground", "a sinister grinning face in green smoke", "two howling green skulls flying side by side", "a plague skull with green fumes", "a cracked flask of green poison"]),
 "warlock_2": ("warlock", ["purple robes etched with glowing green runes", "a glowing purple mana crystal", "chains of green fel fire", "a circle of glowing green runes", "fel chains shooting outward from a central sigil", "two clawed hands clasped in a pact sealed with green fire", "a burning green pact seal ringed by an endless serpent", "a chained grimoire with a glowing green eye", "a green flame in a dark lantern"]),
 "archer_0": ("archer", ["a hunter's eye glowing pale green under a dark hood", "a black longbow drawn to full with a heavy arrow nocked", "a broad-headed arrow punching through three wooden targets in a row", "a hand nocking an arrow fast with motion blur", "an arrow striking the centre of a target with a bright star glint", "an arrow piercing a beast's skull", "one arrow splitting into three in flight", "a crossed longbow and quiver emblem", "a single black-feathered arrow"]),
 "archer_1": ("archer", ["a hunter's hide-and-leather armour with fur trim", "a glowing heart wrapped in green vines", "a heavy iron jaw trap snapping shut with sparks", "a leather boot running through ferns with a green trail", "three iron traps set in the forest floor", "a ring of glowing green leaf runes", "a wide iron trap catching a whole pack of shadows", "a hooded hunter's silhouette among dark trees", "a coil of rope and a hunting knife"]),
 "archer_2": ("archer", ["a storm of arrows raining down from a dark sky", "arrows falling over a wide glowing circle on the ground", "a spectral glowing green beast's head", "a hunter's horn calling, green sound waves", "a spectral beast and a hunter running side by side", "an hourglass made of arrows", "two spectral beasts leaping together", "a pawprint glowing pale green", "a feathered war arrow"]),
}
def prompt(k):
    cls, cells = TREES[k]
    return STYLE.format(pal=PAL[cls], cells="; ".join(f"({i+1}) {c}" for i, c in enumerate(cells)))


def _ids(tree):
    cls, i = tree.rsplit("_", 1)
    src = open(os.path.join(os.path.dirname(__file__), "..", "scripts", "talents.gd")).read()
    block = src[src.index('"%s": [' % cls):]
    trees = re.split(r'\{"name": "', block)[1:4]
    return re.findall(r'"id": "(\w+)"', trees[int(i)])

def _cuts(prof, n):
    """Cell edges along one axis: gutters are lines of nearly one colour (low spread across the image)."""
    import numpy as np
    k = max(3, n // 200)
    sm = np.convolve(prof, np.ones(k) / k, mode="same")
    thr = 0.3 * np.median(sm[n // 6: 5 * n // 6])
    gut = sm < thr
    def edge(lo, hi, step):
        rng = range(lo, hi, step)
        for x in rng:
            if not gut[x]:
                return x
        return lo
    left, right = edge(0, n // 6, 1), edge(n - 1, 5 * n // 6, -1)
    out = [left]
    for f in (1 / 3, 2 / 3):
        c = int(left + (right - left) * f)
        w = (right - left) // 12
        seg = np.where(gut[c - w: c + w])[0]
        if len(seg):
            out += [c - w + seg[0], c - w + seg[-1]]
        else:
            out += [c, c]
    out.append(right)
    return [(out[0], out[1]), (out[2], out[3]), (out[4], out[5])]

def cut(png, tree, inset=0.035, outdir="assets/textures/talents"):
    import numpy as np
    from PIL import Image
    im = Image.open(png).convert("RGB")
    a = np.asarray(im).astype(float).mean(2)
    cols, rows = _cuts(a.std(0), a.shape[1]), _cuts(a.std(1), a.shape[0])
    names = _ids(tree) + [tree.split("_")[0] + "_tree" + tree.rsplit("_", 1)[1]]
    os.makedirs(outdir, exist_ok=True)
    for n, name in enumerate(names):
        (x0, x1), (y0, y1) = cols[n % 3], rows[n // 3]
        ix, iy = (x1 - x0) * inset, (y1 - y0) * inset    # off the cell's own edge or frame
        c = im.crop((int(x0 + ix), int(y0 + iy), int(x1 - ix), int(y1 - iy)))
        c.resize((128, 128), Image.LANCZOS).save(os.path.join(outdir, name + ".png"))
    print(tree, "cells", cols, rows, "->", names)

if __name__ == "__main__":
    if sys.argv[1] == "prompt":
        print(prompt(sys.argv[2]))
    elif sys.argv[1] == "cut":
        cut(sys.argv[2], sys.argv[3], float(sys.argv[4]) if len(sys.argv) > 4 else 0.035)   # [inset: more for framed cells]
