# Removes everything below a height (Blender z, metres) from a prepared prop glb and re-exports it.
#   blender -b --python trim_below.py -- in.glb out.glb <z>
import bpy, bmesh, sys
a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, Z = a[0], a[1], float(a[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in [o for o in bpy.context.scene.objects if o.type == "MESH"]:
    bm = bmesh.new(); bm.from_mesh(o.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, Z), plane_no=(0, 0, 1), clear_inner=True)
    bm.to_mesh(o.data); bm.free()
    print("TRIM", o.name, len(o.data.polygons), "faces")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_image_format="JPEG", export_jpeg_quality=84)
