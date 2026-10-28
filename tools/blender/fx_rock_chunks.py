# Rock chunks for the knight's Judgment slam (thrown out of the cracked ground).
#   blender -b --python tools/blender/fx_rock_chunks.py -- <out.glb> [count]
# Each chunk: an icosphere broken up with two layers of noise displacement and flattened or stretched
# at random, then cut with a few random planes (fresh fracture faces), smooth-shaded with sharp
# edges kept, and decimated to ~120-250 triangles. Exported as separate meshes chunk0..N at the
# origin; the game gives them a stone material (Fx.holy_slam).
import bpy, bmesh, sys, random, math
from mathutils import Vector, noise

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
COUNT = int(argv[1]) if len(argv) > 1 else 8
random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
for i in range(COUNT):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=1.0)
    off = Vector((random.uniform(-50, 50), random.uniform(-50, 50), random.uniform(-50, 50)))
    sx, sy, sz = random.uniform(0.7, 1.3), random.uniform(0.6, 1.1), random.uniform(0.35, 0.8)
    for v in bm.verts:
        n = v.co.normalized()
        d = noise.noise(v.co * 1.4 + off) * 0.28 + noise.noise(v.co * 4.0 + off) * 0.08
        v.co = n * (1.0 + d)
        v.co.x *= sx; v.co.y *= sy; v.co.z *= sz
    # fracture faces: slice off caps with random planes
    for _ in range(random.randint(2, 4)):
        nrm = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))).normalized()
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=nrm * random.uniform(0.35, 0.6), plane_no=nrm, clear_outer=True)
        edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
        if edges:
            try:
                bmesh.ops.edgeloop_fill(bm, edges=edges)
            except Exception:
                bmesh.ops.holes_fill(bm, edges=edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(f"chunk{i}")
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(f"chunk{i}", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    dec = ob.modifiers.new("dec", "DECIMATE"); dec.ratio = random.uniform(0.18, 0.3)
    bpy.ops.object.modifier_apply(modifier="dec")
    # size: 8-20 cm across
    s = random.uniform(0.04, 0.1)
    ob.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    for p in me.polygons:
        p.use_smooth = True
    # keep fracture edges crisp
    me.set_sharp_from_angle(angle=math.radians(40))
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60))
    bpy.ops.object.mode_set(mode="OBJECT")
    ob.select_set(False)
    ob.location = (i * 0.3, 0, 0)
    print("chunk", i, "tris", sum(len(p.vertices) - 2 for p in me.polygons))
for ob in bpy.context.scene.objects:
    ob.location = (0, 0, 0)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_materials="NONE")
print("EXPORTED", OUT)
