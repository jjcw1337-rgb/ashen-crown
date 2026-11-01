# Saves every image in a glb (albedo, metal/roughness, normal) as PNGs, for tools/plague_colors.py.
#   blender -b --python dump_textures.py -- <in.glb> <outdir>
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
for img in bpy.data.images:
    print("IMG", img.name, img.size[:])
    img.filepath_raw = a[1] + "/" + img.name.replace(" ", "_").replace(".", "_") + ".png"
    img.file_format = "PNG"
    img.save()
