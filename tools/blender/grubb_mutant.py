# King Grubb, the mutant: rigs the Meshy model (generated from a Meshy concept image) to the game's
# goblin joints and exports assets/models/grubb_mutant.glb.
#
# Run inside Blender with the decimated model in the scene as "Mutant_Body" (facing +Y, feet on
# z = 0, 2.2 m tall; it lives in ~/Documents/Blender/Game Factory/sources/grubb.blend). Weights come
# from distance to each bone's segment, with fixed regions for the crowns, the three gold sacks
# (so each can burst on its own) and the Hoardkey in his right hand. The joint layout here must
# match Goblin.KINDS["mutant"]["layout"] (Godot axes: x, z, -y of these).
import bpy, math, os, shutil
import numpy as np
from mathutils import Vector

ROOT = os.environ.get("ASHEN_ROOT", "/Users/blaine/dev/ashen-crown")
WORKSPACE = os.environ.get("GAME_FACTORY", os.path.expanduser("~/Documents/Blender/Game Factory"))
OUT = WORKSPACE + "/exports/grubb_mutant.glb"
GAME = ROOT + "/assets/models/grubb_mutant.glb"

# joint heads in Blender space (front is +Y), parent, tail
BONES = [
    ("hips", None, (0, 0.0, 0.62), (0, 0.0, 0.8)),
    ("torso", "hips", (0, 0.0, 0.8), (0, 0.02, 1.35)),
    ("belly", "torso", (0, 0.3, 0.8), (0, 0.55, 0.8)),
    ("head", "torso", (-0.08, 0.16, 1.48), (-0.1, 0.22, 1.82)),
    ("crowns", "head", (-0.13, 0.23, 1.84), (-0.13, 0.23, 2.1)),
    ("sh_r", "torso", (0.4, 0.08, 1.42), (0.58, 0.12, 0.98)),
    ("el_r", "sh_r", (0.58, 0.12, 0.98), (0.69, 0.17, 0.62)),
    ("hand_r", "el_r", (0.69, 0.17, 0.62), (0.72, 0.22, 0.42)),
    ("sh_l", "torso", (-0.4, 0.08, 1.42), (-0.58, 0.12, 0.98)),
    ("el_l", "sh_l", (-0.58, 0.12, 0.98), (-0.69, 0.17, 0.62)),
    ("hand_l", "el_l", (-0.69, 0.17, 0.62), (-0.72, 0.22, 0.42)),
    ("leg_r", "hips", (0.22, 0.12, 0.6), (0.3, 0.15, 0.32)),
    ("knee_r", "leg_r", (0.3, 0.15, 0.32), (0.32, 0.25, 0.03)),
    ("leg_l", "hips", (-0.22, 0.12, 0.6), (-0.3, 0.15, 0.32)),
    ("knee_l", "leg_l", (-0.3, 0.15, 0.32), (-0.32, 0.25, 0.03)),
    ("sack0", "torso", (0.32, -0.3, 1.45), (0.32, -0.3, 1.6)),
    ("sack1", "torso", (0.18, -0.32, 1.66), (0.18, -0.32, 1.8)),
    ("sack2", "torso", (0.42, -0.28, 1.66), (0.42, -0.28, 1.8)),
]
# bones that skin by distance (the rest are region-only)
SKIN = ["hips", "torso", "head", "sh_r", "el_r", "hand_r", "sh_l", "el_l", "hand_l", "leg_r", "knee_r", "leg_l", "knee_l"]


def seg_dist(P, a, b):
    a = np.array(a)
    ab = np.array(b) - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def weights(P):
    names = [b[0] for b in BONES]
    idx = {n: i for i, n in enumerate(names)}
    W = np.zeros((len(P), len(names)))
    for n in SKIN:
        _, _, h, t = BONES[idx[n]]
        d = seg_dist(P, h, t)
        W[:, idx[n]] = 1.0 / (d + 0.03) ** 6
    W /= W.sum(axis=1, keepdims=True)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    def take(mask_w, bone):
        """Blend vertices toward one bone by mask weight (0..1)."""
        W[:] *= (1.0 - mask_w)[:, None]
        W[:, idx[bone]] += mask_w
    # the cape (behind, below the shoulders) rides the torso and hips only: never an arm or a leg
    cape = smooth(-y, 0.1, 0.22) * (1.0 - smooth(z, 1.3, 1.45))
    lowc = 1.0 - smooth(z, 0.5, 0.9)
    take(cape * (1.0 - lowc), "torso")
    take(cape * lowc, "hips")
    # the belly (front, middle) gets its own bone so it can jiggle
    belly = smooth(y, 0.22, 0.38) * smooth(z, 0.45, 0.6) * (1.0 - smooth(z, 1.0, 1.15)) * (1.0 - smooth(np.abs(x), 0.35, 0.5))
    take(belly * 0.85, "belly")
    # the Hoardkey: a diagonal from the right hand down to the front
    key = seg_dist(P, (0.76, 0.2, 0.64), (0.0, 0.8, 0.18))
    out_front = np.maximum(smooth(y, 0.62, 0.7), smooth(x, 0.62, 0.68))
    take((1.0 - smooth(key, 0.05, 0.08)) * out_front, "hand_r")
    # the crown stack
    crown = smooth(z, 1.82, 1.88) * (1.0 - smooth(np.abs(x + 0.12), 0.28, 0.34))
    take(crown, "crowns")
    # the three gold sacks behind his right shoulder
    sacks = smooth(-y, 0.1, 0.18) * smooth(z, 1.33, 1.4) * smooth(x, 0.06, 0.12) * (1.0 - smooth(x, 0.58, 0.64))
    upper = smooth(z, 1.58, 1.64)
    outer = smooth(x, 0.27, 0.33)
    take(sacks * (1.0 - upper), "sack0")
    take(sacks * upper * (1.0 - outer), "sack1")
    take(sacks * upper * outer, "sack2")
    return names, W


def build():
    body = bpy.data.objects["Mutant_Body"]
    old = bpy.data.objects.get("Mutant_Rig")
    if old:
        bpy.data.objects.remove(old)
    body.parent = None
    body.modifiers.clear()
    body.vertex_groups.clear()
    arm = bpy.data.armatures.new("MutantRig")
    rig = bpy.data.objects.new("Mutant_Rig", arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    for n, par, h, t in BONES:
        b = arm.edit_bones.new(n)
        b.head = h
        b.tail = t
        if par:
            b.parent = arm.edit_bones[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    P = np.empty(len(body.data.vertices) * 3)
    body.data.vertices.foreach_get("co", P)
    P = P.reshape(-1, 3)
    names, W = weights(P)
    # keep the four strongest influences per vertex
    top = np.argsort(-W, axis=1)[:, :4]
    for j, n in enumerate(names):
        vg = body.vertex_groups.new(name=n)
        rows = np.where((top == j).any(axis=1) & (W[:, j] > 0.002))[0]
        for r in rows:
            vg.add([int(r)], float(W[r, j]), 'REPLACE')
    body.parent = rig
    m = body.modifiers.new("Armature", 'ARMATURE')
    m.object = rig
    print("weights done", len(P), "verts")
    return rig, body


def export(rig, body):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    body.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
        export_skins=True, export_animations=False, export_image_format='JPEG')
    os.makedirs(os.path.dirname(GAME), exist_ok=True)
    shutil.copyfile(OUT, GAME)
    print("exported", GAME, os.path.getsize(GAME) // 1024, "KB")


if __name__ == "__main__" or True:
    r, b = build()
    if globals().get("EXPORT", True):
        export(r, b)
