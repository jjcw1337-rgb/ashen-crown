# Rigs a Hollow Sloth (Meshy, upright A-pose, facing -Y, feet on the ground, about 2.5 m) on the skeleton
# sloth.gd poses (Sloth.BONES: hips, spine, chest, neck, head, arm/forearm/hand, thigh/shin/foot per side,
# tail), and exports it as a glb for the game.
#   blender -b sources/hollow_sloth.blend --python tools/blender/act1/rig_sloth.py -- <object> <out.glb>
# or, in a live Blender, exec this file and call rig("<object>", "<out.glb>").
# The joints are measured on the mesh (the arm's centreline at the elbow and wrist, the legs, the core
# and snout), so all three sloths (and any other model from the same concept) fit. Blender's heat skinning
# fails on Meshy's fur shells (even voxel-remeshed), so each vertex is weighted by its distance to the
# bones (the nearest three, falling off with the 4th power), each limb taking only its own side.
import bpy, sys
from mathutils import Vector


def _mean(vs):
    s = Vector((0, 0, 0))
    for v in vs:
        s += v
    return s / max(len(vs), 1)


def measure(o):
    vs = [o.matrix_world @ v.co - Vector((o.location.x, o.location.y, 0)) for v in o.data.vertices]
    L = {}

    def arm_bin(x0, x1, s):
        b = [v for v in vs if x0 <= v.x * s < x1 and v.z > 0.6]
        return _mean(b)
    for side, s in (("l", 1.0), ("r", -1.0)):
        elbow = arm_bin(0.84, 0.96, s)
        wrist = arm_bin(1.06, 1.18, s)
        shoulder = elbow + (elbow - wrist) * 1.2
        shoulder.x = 0.5 * s
        # the claw tips: furthest along the forearm's line
        fdir = (wrist - elbow).normalized()
        tip = max([v for v in vs if v.x * s > 0.85 and v.z > 0.45], key=lambda v: (v - wrist).dot(fdir))
        L["arm_" + side] = ("chest", shoulder, elbow)
        L["forearm_" + side] = ("arm_" + side, elbow, wrist)
        L["hand_" + side] = ("forearm_" + side, wrist, tip)
        # legs: below the hips, away from the tail behind
        leg = [v for v in vs if 0.15 < v.x * s < 0.75 and v.y < 0.4]
        knee = _mean([v for v in leg if 0.45 <= v.z < 0.58])
        ankle = _mean([v for v in leg if 0.1 <= v.z < 0.2])
        toe = min([v for v in leg if v.z < 0.08] or [ankle + Vector((0, -0.3, -0.1))], key=lambda v: v.y)
        hip = Vector((0.36 * s, knee.y + 0.08, 0.92))
        L["thigh_" + side] = ("hips", hip, knee)
        L["shin_" + side] = ("thigh_" + side, knee, ankle)
        L["foot_" + side] = ("shin_" + side, ankle, Vector((ankle.x, toe.y, max(toe.z, 0.03))))

    def core_y(z0, z1):
        # the middle of the body's depth at this height (front of the chest to the back), tail and snout left out
        b = sorted(v.y for v in vs if abs(v.x) < 0.25 and z0 <= v.z < z1 and -0.6 < v.y < 0.6)
        return (b[len(b) // 10] + b[len(b) * 9 // 10]) / 2.0 if b else 0.0
    yh, ys, yc, yn = core_y(0.9, 1.0), core_y(1.2, 1.3), core_y(1.55, 1.65), core_y(1.85, 1.95)
    snout = min(vs, key=lambda v: v.y)
    L["hips"] = ("", Vector((0, yh, 0.95)), Vector((0, ys, 1.25)))
    L["spine"] = ("hips", Vector((0, ys, 1.25)), Vector((0, yc, 1.6)))
    L["chest"] = ("spine", Vector((0, yc, 1.6)), Vector((0, yn, 1.92)))
    head = Vector((0, yn + (snout.y - yn) * 0.25, 2.05))
    L["neck"] = ("chest", Vector((0, yn, 1.92)), head)
    L["head"] = ("neck", head, Vector((0, snout.y, snout.z)))
    back = max([v for v in vs if v.z < 0.5 and abs(v.x) < 0.3] or [Vector((0, 0.85, 0.15))], key=lambda v: v.y)
    L["tail"] = ("hips", Vector((0, yh + 0.3, 0.75)), Vector((0, back.y, max(back.z, 0.1))))
    return L


def _seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-6)))
    return (a + ab * t - p).length


def _allowed(bone, v):
    side = 1.0 if bone.endswith("_l") else (-1.0 if bone.endswith("_r") else 0.0)
    if bone[:3] in ("arm", "for", "han"):
        return v.x * side > 0.3
    if bone[:3] in ("thi", "shi", "foo"):
        return v.x * side > -0.05 and v.z < 1.05
    if bone == "tail":
        return v.y > 0.15 and v.z < 1.0
    if bone == "head":
        return v.z > 1.8
    if bone == "neck":
        return v.z > 1.6
    return True


def skin_by_distance(o, L, off, top=3, power=4.0):
    o.vertex_groups.clear()
    groups = {k: o.vertex_groups.new(name=k) for k in L}
    segs = [(k, h, t) for k, (p, h, t) in L.items()]
    mw = o.matrix_world
    for v in o.data.vertices:
        p = mw @ v.co - off
        ws = []
        for k, h, t in segs:
            if not _allowed(k, p):
                continue
            d = _seg_dist(p, h, t)
            ws.append((1.0 / (d + 0.03) ** power, k))
        ws.sort(reverse=True)
        ws = ws[:top]
        tot = sum(w for w, k in ws)
        for w, k in ws:
            groups[k].add([v.index], w / tot, "REPLACE")


def rig(name, out):
    o = bpy.data.objects[name]
    off = Vector((o.location.x, o.location.y, 0))
    L = measure(o)
    an = name + "Rig"
    if an in bpy.data.objects:
        bpy.data.objects.remove(bpy.data.objects[an], do_unlink=True)
    arm = bpy.data.armatures.new(an)
    ar = bpy.data.objects.new(an, arm)
    bpy.context.collection.objects.link(ar)
    ar.location = off
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = ar
    bpy.ops.object.mode_set(mode="EDIT")
    for k, (p, h, t) in L.items():
        b = arm.edit_bones.new(k)
        b.head, b.tail = h, t
    for k, (p, h, t) in L.items():
        if p:
            arm.edit_bones[k].parent = arm.edit_bones[p]
    bpy.ops.object.mode_set(mode="OBJECT")
    # skin by distance to each bone (Blender's heat skinning fails on Meshy's fur shells, even remeshed):
    # each limb only takes the vertices on its own side, the head and tail their own region
    skin_by_distance(o, L, off)
    o.parent = ar
    o.matrix_parent_inverse = ar.matrix_world.inverted()
    am = o.modifiers.new("arm", "ARMATURE")
    am.object = ar
    # export the rigged sloth at the origin, textures as jpeg at 1k (it's seen from far up)
    keep = (ar.location.copy(),)
    ar.location = (0, 0, 0)
    for x in bpy.context.selected_objects:
        x.select_set(False)
    o.select_set(True)
    ar.select_set(True)
    imgs = {n.image for m in o.data.materials if m and m.use_nodes for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}
    for im in imgs:
        if im.size[0] > 1024:
            im.scale(1024, 1024)
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format="GLB", export_skins=True, export_animations=False,
                              export_image_format="JPEG", export_jpeg_quality=88, export_yup=True)
    ar.location = keep[0]
    print("rigged", name, "->", out, len(L), "bones")
    return L


if __name__ == "__main__" and "--" in sys.argv:
    a = sys.argv[sys.argv.index("--") + 1:]
    rig(a[0], a[1])
