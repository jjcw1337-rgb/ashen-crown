# Renders a prepared prop glb from the game's camera angle (Eevee) next to a close three-quarter view, for review.
#   xvfb-run -a blender -b --python prop_shot.py -- <prop.glb> <out.png>
import bpy, sys, math, mathutils
a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
lo = mathutils.Vector((1e9,) * 3); hi = mathutils.Vector((-1e9,) * 3)
for o in objs:
    for c in o.bound_box:
        w = o.matrix_world @ mathutils.Vector(c)
        lo = mathutils.Vector(map(min, lo, w)); hi = mathutils.Vector(map(max, hi, w))
for o in objs:
    o.location.z -= lo.z     # stand it on the floor (raw Meshy models are centred on the origin)
hi.z -= lo.z; lo.z = 0.0
ctr = (lo + hi) / 2; size = max(hi - lo)
sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE_NEXT"
sc.render.resolution_x, sc.render.resolution_y = 900, 600
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.05, 0.06, 0.07)
bpy.ops.mesh.primitive_plane_add(size=size * 6, location=(ctr.x, ctr.y, 0))
g = bpy.context.object; gm = bpy.data.materials.new("g"); gm.diffuse_color = (0.12, 0.11, 0.09, 1); g.data.materials.append(gm)
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.0; so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so)
so.rotation_euler = (math.radians(50), 0, math.radians(35))
fill = bpy.data.lights.new("fill", "AREA"); fill.energy = 60 * size * size; fill.size = size * 2; fo = bpy.data.objects.new("fill", fill)
sc.collection.objects.link(fo); fo.location = ctr + mathutils.Vector((-size * 1.5, -size * 1.5, size * 1.5)); fo.rotation_euler = (math.radians(55), 0, math.radians(-45))
cam = bpy.data.cameras.new("c"); cam.lens = 50; co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
d = size * 2.6
co.location = ctr + mathutils.Vector((d * 0.55, -d * 0.75, d * 0.55))
co.rotation_euler = (ctr - co.location).to_track_quat("-Z", "Y").to_euler()
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("SHOT", OUT)
