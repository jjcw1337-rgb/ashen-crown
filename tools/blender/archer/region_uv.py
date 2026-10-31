"""Region map of the ranger's texture for recolouring (tools/archer_colors.py).
blender -b --python tools/blender/archer/region_uv.py -- archer_ranger.glb regions.json

For every face of the body (in the rest pose) its UV triangle and the region of the body it's on:
  face  - his face and beard (never recoloured), found as the skin inside the hood round the Head bone
  head  - the hood and the cowl round it
  torso - from the hips to the shoulders, and the arms
  hands - his gloved hands (left as they are)
  coat  - below the hips but hanging clear of the legs (the coat's skirt)
  legs  - the legs themselves
"""
import bpy, bmesh, json, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=argv[0])
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
for o in bpy.data.objects:
    if o.type == "ARMATURE":
        o.data.pose_position = "REST"
bpy.context.view_layer.update()
def bone_head(n):
    return arm.matrix_world @ arm.data.bones[n].head_local
def bone_tail(n):
    return arm.matrix_world @ arm.data.bones[n].tail_local
head_c = bone_head("Head") + Vector((0, 0, 0.09))   # (Meshy's Head bone tail points off into space)
neck_z = bone_head("Neck").z if "Neck" in arm.data.bones else bone_head("Head").z - 0.08
hips_z = bone_head("Hips").z
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.dot(ab), 1e-9)))
    return (p - (a + ab * t)).length
legs = [(bone_head(n), bone_head(m)) for n, m in (("LeftUpLeg", "LeftLeg"), ("LeftLeg", "LeftFoot"), ("RightUpLeg", "RightLeg"), ("RightLeg", "RightFoot"))]
out = []
for ob in bpy.data.objects:
    if ob.type != "MESH":
        continue
    dg = bpy.context.evaluated_depsgraph_get()
    eo = ob.evaluated_get(dg)
    me = eo.to_mesh()
    uvl = me.uv_layers.active.data
    # which way he faces: the nose is the head's frontmost skin; Meshy characters face -Y in Blender
    for p in me.polygons:
        c = ob.matrix_world @ p.center
        n = (ob.matrix_world.to_3x3() @ p.normal).normalized()
        rel = c - head_c
        horiz = Vector((rel.x, rel.y, 0)).length
        if c.z > neck_z - 0.02:
            # in front of the head centre and close to it: face; the hood wraps outside
            region = "face" if (rel.y < -0.02 and horiz < 0.125 and rel.z > -0.13) else "head"
        elif min((c - bone_head(h)).length for h in ("LeftHand", "RightHand")) < 0.13:
            region = "hands"
        elif c.z > hips_z:
            region = "torso"
        else:
            d = min(seg_dist(c, a, b) for a, b in legs)
            region = "coat" if (d > 0.12 and c.z > bone_head("LeftLeg").z - 0.05) else "legs"
        tri = [list(uvl[li].uv) for li in p.loop_indices]
        out.append([region, tri])
    eo.to_mesh_clear()
json.dump({"polys": out}, open(argv[1], "w"))
print("regions", {r: sum(1 for x in out if x[0] == r) for r in ("face", "head", "torso", "hands", "coat", "legs")}, "head", head_c, "neck", neck_z, "hips", hips_z)
