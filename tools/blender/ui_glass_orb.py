# Glass for the life and mana globes: only the reflections of a glass sphere (a soft window highlight,
# a rim light and a broad top sheen) rendered against black, so the game adds it over the liquid
# (additive blending: black adds nothing). blender -b --python tools/blender/ui_glass_orb.py -- <out.png> [size]
import bpy, sys, math
argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]
SIZE = int(argv[1]) if len(argv) > 1 else 512
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 256
sc.cycles.use_denoising = True
sc.cycles.device = "CPU"
sc.render.film_transparent = False
sc.render.resolution_x = SIZE
sc.render.resolution_y = SIZE
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.02, 0.02, 0.025, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
bpy.ops.mesh.primitive_uv_sphere_add(segments=96, ring_count=48, radius=1.0)
sp = bpy.context.object
bpy.ops.object.shade_smooth()
m = bpy.data.materials.new("glass"); m.use_nodes = True
nt = m.node_tree; nt.nodes.clear()
out = nt.nodes.new("ShaderNodeOutputMaterial")
mix = nt.nodes.new("ShaderNodeMixShader")
gl = nt.nodes.new("ShaderNodeBsdfGlossy"); gl.inputs["Roughness"].default_value = 0.16
tr = nt.nodes.new("ShaderNodeBsdfTransparent")
lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.42
nt.links.new(lw.outputs["Fresnel"], mix.inputs["Fac"])
nt.links.new(tr.outputs[0], mix.inputs[1])
nt.links.new(gl.outputs[0], mix.inputs[2])
# add a little emission-free sheen everywhere so reflections show across the face
add = nt.nodes.new("ShaderNodeAddShader")
gl2 = nt.nodes.new("ShaderNodeBsdfGlossy"); gl2.inputs["Roughness"].default_value = 0.1
nt.links.new(mix.outputs[0], add.inputs[0]); nt.links.new(gl2.outputs[0], add.inputs[1])
nt.links.new(add.outputs[0], out.inputs[0])
sp.data.materials.append(m)
def area(name, loc, size, energy, rot):
    ld = bpy.data.lights.new(name, "AREA"); ld.size = size; ld.energy = energy; ld.shape = "ELLIPSE"; ld.size_y = size * 0.6
    o = bpy.data.objects.new(name, ld); sc.collection.objects.link(o); o.location = loc; o.rotation_euler = rot
    return o
area("window", (-2.2, -3.0, 2.6), 1.2, 140, (math.radians(55), 0, math.radians(-35)))
area("rim", (2.5, -1.5, -2.0), 1.8, 60, (math.radians(120), 0, math.radians(55)))
area("top", (0, -1.0, 4.0), 3.0, 25, (math.radians(10), 0, 0))
cd = bpy.data.cameras.new("cam"); cd.type = "ORTHO"; cd.ortho_scale = 2.02
cam = bpy.data.objects.new("cam", cd); sc.collection.objects.link(cam)
cam.location = (0, -6, 0); cam.rotation_euler = (math.radians(90), 0, 0)
sc.camera = cam
sc.render.filepath = OUT
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGB"
bpy.ops.render.render(write_still=True)
print("RENDERED", OUT)
