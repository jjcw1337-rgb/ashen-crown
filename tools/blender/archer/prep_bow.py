"""The ranger's bow from Meshy, made ready for the game.

blender -b --python tools/blender/archer/prep_bow.py -- meshy_bow.glb assets/models/ranger_bow.glb spec.json [length] [tris]

- Cuts away Meshy's fixed string (the long thin pieces along the string side): the game draws its own strands from the
  nocks so his fingers can pull it (Archer.pose_bow).
- Stands the bow in the game's frame (Godot axes): the limbs along +Y, the string on the +Z side (the archer's side,
  the way it pulls), the riser at -Z; the origin in the middle of the leather grip, where his fist closes.
- Scales it to `length` metres tip to tip (default 1.45) and decimates to about `tris` triangles (default 9000).
- Writes spec.json: the nocks (where the string ties on), the string's rest point (the nock height on a straight string,
  just above the grip), all in the exported glb's metres and Godot axes; Archer.BOW_SPEC_GLB copies them.
"""
import bpy, bmesh, json, sys, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
src, out, spec_path = argv[0], argv[1], argv[2]
length = float(argv[3]) if len(argv) > 3 else 1.45
tris = int(argv[4]) if len(argv) > 4 else 9000

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obs = [o for o in bpy.data.objects if o.type == "MESH"]
bpy.context.view_layer.objects.active = obs[0]
for o in obs:
    o.select_set(True)
if len(obs) > 1:
    bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
me = ob.data

# --- the long axis of the bow (Meshy stands it up along Z) and the string side (the side the thin pieces are on)
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
seen = set()
parts = []
for v in bm.verts:
    if v.index in seen:
        continue
    st = [v]
    comp = []
    seen.add(v.index)
    while st:
        x = st.pop()
        comp.append(x)
        for e in x.link_edges:
            y = e.other_vert(x)
            if y.index not in seen:
                seen.add(y.index)
                st.append(y)
    parts.append(comp)

def thin(comp):
    """A string piece: long and no thicker than a cord round its own axis."""
    ps = [q.co for q in comp]
    c = sum(ps, Vector()) / len(ps)
    # principal axis by power iteration
    cov = Matrix(((0, 0, 0), (0, 0, 0), (0, 0, 0)))
    for p in ps:
        d = p - c
        for i in range(3):
            for j in range(3):
                cov[i][j] += d[i] * d[j]
    ax = Vector((0.3, 0.2, 1.0))
    for _ in range(30):
        ax = (cov @ ax).normalized()
    rad = max(((p - c) - ax * (p - c).dot(ax)).length for p in ps)
    ln = max((p - c).dot(ax) for p in ps) - min((p - c).dot(ax) for p in ps)
    return rad < 0.011 and ln > 0.03, c

string_vs = []
for comp in parts:
    is_s, c = thin(comp)
    if is_s:
        string_vs += comp
print("string pieces: %d verts" % len(string_vs))
sp = [v.co.copy() for v in string_vs]
s_side = sum(sp, Vector()) / len(sp)
# the nocks: the string's two ends
top = max(sp, key=lambda p: p.z)
bot = min(sp, key=lambda p: p.z)
bmesh.ops.delete(bm, geom=string_vs, context="VERTS")
bm.to_mesh(me)
bm.free()
me.update()

# --- the grip: the middle of the riser at mid height (the wood nearest the middle, opposite the string)
vs = [v.co.copy() for v in me.vertices]
zmid = (max(p.z for p in vs) + min(p.z for p in vs)) / 2
band = [p for p in vs if abs(p.z - zmid) < 0.05]
grip = sum(band, Vector()) / len(band)
# the string side, as a direction across the bow (in the XY plane)
side = Vector((s_side.x - grip.x, s_side.y - grip.y, 0)).normalized()
L = max(p.z for p in vs) - min(p.z for p in vs)
k = length / L
# rotate so the string side faces Blender -Y (Godot +Z), then move the grip to the origin and scale
ang = math.atan2(side.y, side.x)
rot = Matrix.Rotation(-math.pi / 2 - ang, 4, "Z")
xf = Matrix.Scale(k, 4) @ rot @ Matrix.Translation(-grip)
ob.data.transform(xf)
top = xf @ top
bot = xf @ bot
s_mid = xf @ Vector((s_side.x, s_side.y, grip.z))

# --- clean and decimate: weld the UV-split pieces' seams, drop the specks left where the string met the wood,
# then collapse to the budget
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0004)
bpy.ops.object.mode_set(mode="OBJECT")
bm = bmesh.new()
bm.from_mesh(me)
seen = set()
specks = []
for v in bm.verts:
    if v in seen:
        continue
    st = [v]
    comp = []
    seen.add(v)
    while st:
        x = st.pop()
        comp.append(x)
        for e in x.link_edges:
            y = e.other_vert(x)
            if y not in seen:
                seen.add(y)
                st.append(y)
    ext = max((a.co - comp[0].co).length for a in comp)
    if len(comp) < 60 and ext < 0.04 * k:
        specks += comp
bmesh.ops.delete(bm, geom=specks, context="VERTS")
bm.to_mesh(me)
bm.free()
print("specks removed: %d verts" % len(specks))
now = sum(len(p.vertices) - 2 for p in me.polygons)
if now > tris:
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = tris / now
    bpy.ops.object.modifier_apply(modifier="dec")
bpy.ops.object.shade_smooth()
after = sum(len(p.vertices) - 2 for p in me.polygons)
# Meshy's metal map makes the wood glint like metal: keep it, but no fully metallic wood
for mat in me.materials:
    if mat and mat.node_tree:
        for n in mat.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                n.inputs["Metallic"].default_value = 0.0

# 1k textures: plenty for a bow at the game's distance (Meshy's are 2k)
for img in bpy.data.images:
    if img.size[0] > 1024:
        img.scale(1024, 1024)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False, export_apply=True,
                          export_image_format="JPEG", export_jpeg_quality=88)

def godot(v):
    return [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]

spec = {"tips": [godot(top), godot(bot)], "rest": godot(Vector((s_mid.x, s_mid.y, 0.035))),
        "grip": [0.0, 0.0, 0.0], "length": length, "tris": after}
json.dump(spec, open(spec_path, "w"), indent=1)
print("SPEC", json.dumps(spec))
