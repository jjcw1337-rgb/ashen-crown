# The Warlock, a gnome: rigs the Meshy model (generated from a Meshy concept image) on the hero's
# joints and exports assets/models/gnome_warlock.glb.
#
# Run inside Blender with the decimated model in the scene as "Gnome_Body" (facing +Y, feet on z = 0,
# 1.2 m tall to the hat's tip; ~/Documents/Blender/Game Factory/sources/gnome_warlock.blend). Weights:
# distance to each bone's segment, then fixed regions: the robe rides the hips and torso (the legs only
# move the boots below the hem, so the skirt doesn't tear), the hat and the beard get their own bones
# (the game sways them), the hands take the fingers. The joint heads here must match
# Warlock.GNOME["layout"] (Godot axes: x, z, -y of these).
import bpy, os, shutil
import numpy as np

ROOT = os.environ.get("ASHEN_ROOT", "/Users/blaine/dev/ashen-crown")
WORKSPACE = os.environ.get("GAME_FACTORY", os.path.expanduser("~/Documents/Blender/Game Factory"))
OUT = WORKSPACE + "/exports/gnome_warlock.glb"
GAME = ROOT + "/assets/models/gnome_warlock.glb"

# name, parent, head, tail (Blender space: +Y is his front)
BONES = [
    ("hips", None, (0, 0.0, 0.33), (0, 0.0, 0.4)),
    ("torso", "hips", (0, 0.0, 0.4), (0, 0.0, 0.62)),
    ("head", "torso", (0, 0.03, 0.64), (0, 0.03, 0.78)),
    ("hat", "head", (0, -0.01, 0.8), (0, -0.05, 1.15)),
    ("beard", "head", (0, 0.12, 0.6), (0, 0.15, 0.42)),
    ("sh_r", "torso", (0.19, 0.0, 0.6), (0.31, 0.02, 0.5)),
    ("el_r", "sh_r", (0.31, 0.02, 0.5), (0.41, 0.04, 0.42)),
    ("hand_r", "el_r", (0.41, 0.04, 0.42), (0.46, 0.05, 0.37)),
    ("sh_l", "torso", (-0.19, 0.0, 0.6), (-0.31, 0.02, 0.5)),
    ("el_l", "sh_l", (-0.31, 0.02, 0.5), (-0.41, 0.04, 0.42)),
    ("hand_l", "el_l", (-0.41, 0.04, 0.42), (-0.46, 0.05, 0.37)),
    ("leg_r", "hips", (0.11, 0.0, 0.3), (0.14, 0.01, 0.17)),
    ("knee_r", "leg_r", (0.14, 0.01, 0.17), (0.15, 0.03, 0.03)),
    ("leg_l", "hips", (-0.11, 0.0, 0.3), (-0.14, 0.01, 0.17)),
    ("knee_l", "leg_l", (-0.14, 0.01, 0.17), (-0.15, 0.03, 0.03)),
]
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
        W[:, idx[n]] = 1.0 / (seg_dist(P, h, t) + 0.015) ** 6
    W /= W.sum(axis=1, keepdims=True)
    x, y, z = P[:, 0], P[:, 1], P[:, 2]

    def take(m, bone):
        W[:] *= (1.0 - m)[:, None]
        W[:, idx[bone]] += m

    def give(src, dst, m):
        """Move a share m of src's weight to dst."""
        moved = W[:, idx[src]] * m
        W[:, idx[src]] -= moved
        W[:, idx[dst]] += moved

    # the robe: above the hem the legs don't move it (hips below the belt, torso above)
    robe = smooth(z, 0.17, 0.26)
    for leg in ("leg_r", "knee_r", "leg_l", "knee_l"):
        give(leg, "hips", robe)
    # arms only move the sleeves, not the chest and mantle beside them
    body = 1.0 - smooth(np.abs(x), 0.17, 0.24)
    for arm in ("sh_r", "sh_l"):
        give(arm, "torso", body)
    # the hat (brim and up) and the beard (front, chin to belt)
    take(smooth(z, 0.74, 0.8), "hat")
    beard = smooth(y, 0.06, 0.11) * smooth(z, 0.38, 0.44) * (1.0 - smooth(z, 0.6, 0.66)) * (1.0 - smooth(np.abs(x), 0.1, 0.14))
    take(beard * 0.9, "beard")
    return names, W


def build():
    body = bpy.data.objects["Gnome_Body"]
    old = bpy.data.objects.get("Gnome_Rig")
    if old:
        bpy.data.objects.remove(old)
    body.parent = None
    body.modifiers.clear()
    body.vertex_groups.clear()
    arm = bpy.data.armatures.new("GnomeRig")
    rig = bpy.data.objects.new("Gnome_Rig", arm)
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
    top = np.argsort(-W, axis=1)[:, :4]
    for j, n in enumerate(names):
        vg = body.vertex_groups.new(name=n)
        for r in np.where((top == j).any(axis=1) & (W[:, j] > 0.002))[0]:
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
