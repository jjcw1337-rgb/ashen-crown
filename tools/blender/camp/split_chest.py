# Splits a prepared stash chest (tools/blender/prep_prop.py output: one mesh, base on the ground, front toward
# Godot +z = Blender -y) into the parts the game opens (Game.chest_lid): "body", "lid" (everything above the lid's
# seam, its origin on the back hinge line) and "lock" (the padlock hanging on the front, its origin at the top of
# its shackle). The cuts leave holes: the body's top and the lid's underside are capped with a dark inside
# (material "inside") so an open chest isn't hollow. Exports one glb with the three as separate nodes.
#   blender -b --python split_chest.py -- in.glb out.glb [--seam 0.74] [--body-bottom 0.16] [--lock x0,x1,z0,z1]
# --seam: the lid's seam as a fraction of the chest's height above --body-bottom (where the plinth ends), measured
# up from the ground; --lock: the padlock's box as fractions of the width (x) and the height (z), on the front.
# Prints SPLIT and the part sizes; --debug <prefix> renders the parts coloured (front, three-quarter).
import bpy, bmesh, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
def opt(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
SEAM = float(opt("--seam", "0.74"))
BODY_BOTTOM = float(opt("--body-bottom", "0.16"))
LOCK = [float(v) for v in opt("--lock", "0.42,0.62,0.30,0.62").split(",")]
DEBUG = opt("--debug", "")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
ob = mesh_objs[0]
if len(mesh_objs) > 1:
    bpy.ops.object.select_all(action="DESELECT")
    for o in mesh_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
bpy.context.view_layer.objects.active = ob
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
ob.name = "body"

vs = [ob.matrix_world @ v.co for v in ob.data.vertices]
lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
size = hi - lo
z_body0 = lo.z + size.z * BODY_BOTTOM
z_seam = z_body0 + (hi.z - z_body0) * SEAM
# the chest itself (not the plinth): its x/y extent from the vertices above the body's bottom
cv = [v for v in vs if v.z > z_body0 + 0.02]
c_lo = Vector((min(v.x for v in cv), min(v.y for v in cv), z_body0))
c_hi = Vector((max(v.x for v in cv), max(v.y for v in cv), hi.z))
cw = c_hi - c_lo
lx0, lx1 = c_lo.x + cw.x * LOCK[0], c_lo.x + cw.x * LOCK[1]
lz0, lz1 = z_body0 + cw.z * LOCK[2], z_body0 + cw.z * LOCK[3]
front_y = c_lo.y + cw.y * 0.12          # Blender -y is the front

inside = bpy.data.materials.new("inside")
inside.use_nodes = True
bsdf = next(n for n in inside.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
bsdf.inputs["Base Color"].default_value = (0.05, 0.035, 0.025, 1.0)
bsdf.inputs["Roughness"].default_value = 0.95

def part_of(c):
    if lx0 <= c.x <= lx1 and lz0 <= c.z <= lz1 and c.y < front_y:
        return "lock"
    if c.z > z_seam:
        return "lid"
    return "body"

bm = bmesh.new()
bm.from_mesh(ob.data)
groups = {"lid": [], "lock": []}
for f in bm.faces:
    k = part_of(f.calc_center_median())
    if k in groups:
        groups[k].append(f.index)
bm.free()

def separate(name, faces_idx):
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for i in faces_idx:
        ob.data.polygons[i].select = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    new = [o for o in bpy.context.selected_objects if o != ob][-1]
    new.name = name
    bpy.context.view_layer.objects.active = ob
    return new

bpy.context.view_layer.objects.active = ob
ob.select_set(True)
lock_ids = groups["lock"]
lock = separate("lock", lock_ids) if lock_ids else None
# (indices shifted after the first separate: find the lid's again)
bm = bmesh.new()
bm.from_mesh(ob.data)
lid_ids = [f.index for f in bm.faces if f.calc_center_median().z > z_seam]
bm.free()
lid = separate("lid", lid_ids)

def cap(o):
    o.data.materials.append(inside)
    mi = len(o.data.materials) - 1
    bm = bmesh.new()
    bm.from_mesh(o.data)
    edges = [e for e in bm.edges if e.is_boundary]
    res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    for f in res.get("faces", []):
        f.material_index = mi
    bm.to_mesh(o.data)
    bm.free()

cap(ob)
cap(lid)

# the holes_fill caps can fail on Meshy's ragged seams: a plain dark board just under the seam in the body (what
# you look down on in an open chest) and just over it under the lid, inset from the walls, always there
def board(o, z, down):
    if "inside" not in [m.name for m in o.data.materials if m]:
        o.data.materials.append(inside)
    mi = [m.name for m in o.data.materials].index("inside")
    bm = bmesh.new()
    bm.from_mesh(o.data)
    i = 0.035
    x0, x1, y0, y1 = c_lo.x + i, c_hi.x - i, c_lo.y + i, c_hi.y - i
    ps = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    if down:
        ps.reverse()
    vs = [bm.verts.new((x, y, z)) for x, y in ps]
    f = bm.faces.new(vs)
    f.material_index = mi
    bm.to_mesh(o.data)
    bm.free()

board(ob, z_seam - 0.03, False)
board(lid, z_seam + 0.004, True)

def set_origin(o, p):
    cur = bpy.context.scene.cursor.location.copy()
    bpy.context.scene.cursor.location = p
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.context.scene.cursor.location = cur

# the hinge: the lid's back edge (Blender +y) at the seam; the lock: the top of its shackle
set_origin(lid, Vector(((c_lo.x + c_hi.x) * 0.5, c_hi.y, z_seam)))
if lock:
    lv = [lock.matrix_world @ v.co for v in lock.data.vertices]
    set_origin(lock, Vector((sum(v.x for v in lv) / len(lv), max(v.y for v in lv), max(v.z for v in lv))))
for o in [ob, lid] + ([lock] if lock else []):
    print("SPLIT %s %d faces" % (o.name, len(o.data.polygons)))
print("SPLIT seam z %.3f, chest %s .. %s" % (z_seam, tuple(round(v, 3) for v in c_lo), tuple(round(v, 3) for v in c_hi)))

if DEBUG:
    cols = {"body": (0.6, 0.6, 0.6, 1), "lid": (0.9, 0.4, 0.1, 1), "lock": (0.1, 0.5, 1.0, 1)}
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "OBJECT"
    sc.render.resolution_x = sc.render.resolution_y = 700
    for o in [ob, lid] + ([lock] if lock else []):
        o.color = cols[o.name]
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    ctr = (lo + hi) * 0.5
    for nm, off in [("front", Vector((0, -2.6, 0.6))), ("34", Vector((1.8, -1.9, 1.2)))]:
        cam.location = ctr + off * max(size.x, size.z)
        cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = DEBUG + "_" + nm + ".png"
        bpy.ops.render.render(write_still=True)
    # and opened: the lid swung back, the lock dropped
    for o in [lid] + ([lock] if lock else []):
        o.rotation_mode = "XYZ"
    lid.rotation_euler.x = 1.75         # (Blender's x; the front (-y) swings up)
    if lock:
        lock.location.z -= 0.06
        lock.rotation_euler.y = 0.6
    sc.render.filepath = DEBUG + "_open.png"
    bpy.ops.render.render(write_still=True)
    lid.rotation_euler.x = 0.0
    if lock:
        lock.rotation_euler.y = 0.0
        lock.location.z += 0.06

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True)
print("SPLIT wrote", OUT)
