"""Blender: assemble the knight's parts and render studio shots.
blender -b --python render.py -- <dir with plys/npz> <out prefix> <shots comma list> [save.blend]"""
import bpy, sys, os, math, json
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, SHOTS = argv[0], argv[1], argv[2].split(",")
SAVE = argv[3] if len(argv) > 3 else None
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def node_mat(name, base, rough=0.5, metal=0.0, sss=0.0, spec=0.5):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    b.inputs["Subsurface Weight"].default_value = sss
    b.inputs["Subsurface Radius"].default_value = (0.9, 0.35, 0.2)
    b.inputs["Subsurface Scale"].default_value = 0.004
    return m

def add_noise_color(m, scale, amount, col2):
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    n = nt.nodes.new("ShaderNodeTexNoise"); n.inputs["Scale"].default_value = scale; n.inputs["Detail"].default_value = 6
    nt.links.new(tc.outputs["Object"], n.inputs["Vector"])
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
    mix.inputs["A"].default_value = b.inputs["Base Color"].default_value
    mix.inputs["B"].default_value = (*col2, 1)
    mr = nt.nodes.new("ShaderNodeMapRange"); mr.inputs["From Min"].default_value = 0.35; mr.inputs["From Max"].default_value = 0.75
    mr.inputs["To Max"].default_value = amount
    nt.links.new(n.outputs["Fac"], mr.inputs["Value"]); nt.links.new(mr.outputs["Result"], mix.inputs["Factor"])
    nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.08
    n2 = nt.nodes.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = scale * 30
    nt.links.new(tc.outputs["Object"], n2.inputs["Vector"]); nt.links.new(n2.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])

MATS = {}
skin = node_mat("skin", (0.5, 0.3, 0.21), rough=0.5, sss=0.2); add_noise_color(skin, 60, 0.35, (0.55, 0.3, 0.26)); MATS["skin"] = skin

def eye_mat():
    m = bpy.data.materials.new("eye"); m.use_nodes = True; nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.05
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(tc.outputs["Object"], sep.inputs[0])
    # radial distance from the front axis (-y) in object space
    cx = nt.nodes.new("ShaderNodeMath"); cx.operation = "MULTIPLY"; nt.links.new(sep.outputs[0], cx.inputs[0]); nt.links.new(sep.outputs[0], cx.inputs[1])
    cz = nt.nodes.new("ShaderNodeMath"); cz.operation = "MULTIPLY"; nt.links.new(sep.outputs[2], cz.inputs[0]); nt.links.new(sep.outputs[2], cz.inputs[1])
    s = nt.nodes.new("ShaderNodeMath"); s.operation = "ADD"; nt.links.new(cx.outputs[0], s.inputs[0]); nt.links.new(cz.outputs[0], s.inputs[1])
    r = nt.nodes.new("ShaderNodeMath"); r.operation = "SQRT"; nt.links.new(s.outputs[0], r.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB"); cr = ramp.color_ramp
    cr.interpolation = "EASE"
    cr.elements[0].position = 0.0; cr.elements[0].color = (0.01, 0.01, 0.01, 1)
    e = cr.elements.new(0.0021); e.color = (0.02, 0.015, 0.01, 1)
    e = cr.elements.new(0.0026); e.color = (0.18, 0.11, 0.05, 1)
    e = cr.elements.new(0.0045); e.color = (0.3, 0.2, 0.09, 1)
    e = cr.elements.new(0.0054); e.color = (0.08, 0.05, 0.03, 1)
    cr.elements[1].position = 0.0062; cr.elements[1].color = (0.82, 0.78, 0.74, 1)
    nt.links.new(r.outputs[0], ramp.inputs[0]); nt.links.new(ramp.outputs[0], b.inputs["Base Color"])
    return m
MATS["eye"] = eye_mat()
MATS["hair"] = node_mat("hair", (0.09, 0.055, 0.03), rough=0.42)
MATS["quilt"] = node_mat("quilt", (0.42, 0.36, 0.26), rough=0.9)
MATS["leather"] = node_mat("leather", (0.18, 0.1, 0.055), rough=0.55); add_noise_color(MATS["leather"], 40, 0.4, (0.1, 0.06, 0.035))
MATS["wool"] = node_mat("wool", (0.16, 0.14, 0.12), rough=0.95)
MATS["cloth"] = node_mat("cloth", (0.32, 0.04, 0.035), rough=0.85)
MATS["steel"] = node_mat("steel", (0.6, 0.6, 0.62), rough=0.28, metal=1.0)
MATS["gold"] = node_mat("gold", (0.85, 0.62, 0.28), rough=0.25, metal=1.0)

def import_ply(path, mat):
    bpy.ops.wm.ply_import(filepath=path)
    o = bpy.context.selected_objects[0]
    o.data.materials.clear(); o.data.materials.append(MATS[mat])
    for p in o.data.polygons:
        p.use_smooth = True
    return o

parts = json.load(open(os.path.join(SRC, "parts.json")))
for p in parts.get("meshes", []):
    import_ply(os.path.join(SRC, p["file"]), p["mat"])
for e in parts.get("eyes", []):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=32, radius=e["r"], location=e["c"])
    o = bpy.context.object; bpy.ops.object.shade_smooth(); o.data.materials.append(MATS["eye"])

# hair strands (npz: points (N,P,3), radius root/tip)
for h in parts.get("hair", []):
    d = np.load(os.path.join(SRC, h["file"]))
    pts = d["points"]; n, k, _ = pts.shape
    cv = bpy.data.hair_curves.new(h["name"]) if hasattr(bpy.data, "hair_curves") else None
    cv.add_curves([k] * n)
    cv.position_data.foreach_set("vector", pts.reshape(-1).astype(np.float32))
    rad = np.linspace(h["r0"], h["r1"], k)[None, :].repeat(n, 0).reshape(-1).astype(np.float32)
    cv.attributes["radius"].data.foreach_set("value", rad) if "radius" in cv.attributes else None
    if "radius" not in cv.attributes:
        a = cv.attributes.new("radius", "FLOAT", "POINT"); a.data.foreach_set("value", rad)
    ob = bpy.data.objects.new(h["name"], cv); sc.collection.objects.link(ob)
    hm = MATS["hair"].copy() if "color" in h else MATS["hair"]
    if "color" in h:
        hm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*h["color"], 1)
    cv.materials.append(hm)

# studio: grey backdrop, key / fill / rim
world = bpy.data.worlds.new("w"); sc.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.05, 0.055, 0.06, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
def light(name, kind, loc, energy, size, color=(1, 1, 1)):
    ld = bpy.data.lights.new(name, kind); ld.energy = energy; ld.color = color
    if kind == "AREA": ld.size = size
    o = bpy.data.objects.new(name, ld); sc.collection.objects.link(o); o.location = loc
    d = Vector((0, 0, 1.2)) - Vector(loc); o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return o
light("key", "AREA", (-1.6, -2.2, 2.6), 300, 1.6, (1.0, 0.93, 0.85))
light("fill", "AREA", (2.2, -1.8, 1.6), 70, 2.0, (0.8, 0.88, 1.0))
light("rim", "AREA", (0.6, 2.4, 2.4), 300, 1.2, (1.0, 0.9, 0.8))
bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
floor = bpy.context.object; floor.data.materials.append(node_mat("floor", (0.12, 0.12, 0.13), rough=0.8))

sc.render.engine = "BLENDER_EEVEE_NEXT"
FAST = os.environ.get("FAST", "1") == "1"
sc.eevee.taa_render_samples = 16 if FAST else 64
try:
    sc.eevee.use_shadows = True; sc.eevee.use_raytracing = not FAST
except Exception:
    pass
sc.view_settings.view_transform = "AgX"
SHOT = {
    "face": ((0.0, -0.62, 1.76), (0, 0, 1.745), 32, (900, 1000)),
    "face34": ((-0.38, -0.5, 1.78), (0, 0, 1.745), 32, (900, 1000)),
    "side": ((-0.62, -0.02, 1.76), (0, 0, 1.745), 32, (900, 1000)),
    "back": ((0.3, 0.75, 1.75), (0, 0, 1.68), 40, (900, 1000)),
    "bust": ((-0.45, -1.35, 1.6), (0, 0, 1.5), 40, (900, 1000)),
    "full": ((-1.4, -3.6, 1.35), (0, 0, 0.95), 38, (800, 1100)),
    "fullback": ((1.2, 3.6, 1.4), (0, 0, 0.95), 38, (800, 1100)),
}
cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
for s in SHOTS:
    loc, tgt, lens, res = SHOT[s]
    cam.location = loc
    cam.rotation_euler = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cam_d.lens = lens * 2.2 if s in ("face", "face34", "side") else lens * 1.4
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = f"{OUT}_{s}.png"
    bpy.ops.render.render(write_still=True)
    print("SHOT", s)
if SAVE:
    bpy.ops.wm.save_as_mainfile(filepath=SAVE)
