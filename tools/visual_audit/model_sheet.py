"""Renders every .glb in a folder (or a list of files) as a neutral "model sheet" for the visual audit.

    xvfb-run -a blender -b --python tools/visual_audit/model_sheet.py -- out_dir file_or_dir [file_or_dir ...] [--px 512] [--engine eevee|cycles|workbench]

For each model: two views (front three-quarter and back three-quarter) under the same studio lights on a mid-grey
backdrop, plus an untextured clay view that shows the geometry and the normal map alone. Each model is scaled to
fit the frame, so sizes aren't comparable; the stats line (triangles, textures) comes from glb_audit.py.
Saves <out_dir>/<name>.png (the three views side by side). Contact sheets: tools/visual_audit/contact_sheet.py.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
px = 512
engine = "workbench"
if "--px" in argv:
	i = argv.index("--px")
	px = int(argv[i + 1])
	del argv[i:i + 2]
if "--engine" in argv:
	i = argv.index("--engine")
	engine = argv[i + 1]
	del argv[i:i + 2]
out_dir = argv[0]
inputs = argv[1:]
os.makedirs(out_dir, exist_ok=True)
files = []
for p in inputs:
	if os.path.isdir(p):
		for dp, _, fs in os.walk(p):
			for f in sorted(fs):
				if f.lower().endswith(".glb"):
					files.append(os.path.join(dp, f))
	elif p.lower().endswith(".glb"):
		files.append(p)


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	sc = bpy.context.scene
	if engine == "cycles":
		sc.render.engine = "CYCLES"
		sc.cycles.samples = 24
		sc.cycles.use_denoising = True
		sc.cycles.device = "CPU"
	elif engine == "workbench":
		sc.render.engine = "BLENDER_WORKBENCH"
		sc.display.shading.light = "STUDIO"
		sc.display.shading.color_type = "TEXTURE"
		sc.display.shading.show_cavity = True
		sc.display.shading.cavity_type = "BOTH"
		sc.display.shading.show_shadows = True
		sc.display.shading.shadow_intensity = 0.35
		sc.display.shading.show_specular_highlight = True
		sc.render.film_transparent = False
	else:
		sc.render.engine = "BLENDER_EEVEE_NEXT"
		sc.eevee.taa_render_samples = 16
		sc.eevee.use_shadows = True
	sc.render.resolution_x = px
	sc.render.resolution_y = px
	sc.render.film_transparent = False
	sc.view_settings.view_transform = "Standard"
	sc.view_settings.look = "None"
	world = bpy.data.worlds.new("w")
	world.use_nodes = True
	bg = world.node_tree.nodes["Background"]
	bg.inputs[0].default_value = (0.32, 0.33, 0.35, 1.0)
	bg.inputs[1].default_value = 0.55
	sc.world = world
	return sc


def add_light(name, kind, energy, loc, rot, color=(1, 1, 1), size=1.0):
	ld = bpy.data.lights.new(name, kind)
	ld.energy = energy
	ld.color = color
	if kind == "AREA":
		ld.size = size
	ob = bpy.data.objects.new(name, ld)
	bpy.context.scene.collection.objects.link(ob)
	ob.location = loc
	ob.rotation_euler = rot
	return ob


def model_bounds(objs):
	lo = Vector((1e9, 1e9, 1e9))
	hi = Vector((-1e9, -1e9, -1e9))
	for ob in objs:
		if ob.type != "MESH":
			continue
		for c in ob.bound_box:
			w = ob.matrix_world @ Vector(c)
			lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
			hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
	return lo, hi


def clay(objs):
	"""Swap each material's base colour for flat grey (keeps the normal map) for the clay view."""
	for ob in objs:
		if ob.type != "MESH":
			continue
		for slot in ob.material_slots:
			m = slot.material
			if m is None or not m.use_nodes:
				continue
			for n in m.node_tree.nodes:
				if n.type == "BSDF_PRINCIPLED":
					for l in list(n.inputs["Base Color"].links):
						m.node_tree.links.remove(l)
					n.inputs["Base Color"].default_value = (0.55, 0.55, 0.55, 1.0)
					for l in list(n.inputs["Metallic"].links):
						m.node_tree.links.remove(l)
					n.inputs["Metallic"].default_value = 0.0
					for l in list(n.inputs["Roughness"].links):
						m.node_tree.links.remove(l)
					n.inputs["Roughness"].default_value = 0.6


def render_one(path):
	sc = reset()
	bpy.ops.import_scene.gltf(filepath=path)
	objs = list(sc.objects)
	# rest pose: drop any animation so skinned models stand in their bind pose
	for ob in objs:
		if ob.animation_data:
			ob.animation_data_clear()
	lo, hi = model_bounds(objs)
	if lo.x > hi.x:
		return None
	centre = (lo + hi) * 0.5
	size = hi - lo
	radius = max(size.length * 0.5, 0.05)
	# floor under it
	bpy.ops.mesh.primitive_plane_add(size=radius * 12, location=(centre.x, centre.y, lo.z - 0.001))
	floor = sc.objects[-1] if sc.objects[-1].type == "MESH" else bpy.context.active_object
	fm = bpy.data.materials.new("floor")
	fm.use_nodes = True
	fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.12, 0.12, 0.125, 1)
	fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
	floor.data.materials.append(fm)
	r = radius * 3.0
	add_light("key", "AREA", 60.0 * radius * radius, centre + Vector((r * 0.8, -r * 0.9, r * 1.1)), (math.radians(50), 0, math.radians(40)), size=radius * 1.5)
	add_light("fill", "AREA", 18.0 * radius * radius, centre + Vector((-r, -r * 0.4, r * 0.4)), (math.radians(70), 0, math.radians(-60)), (0.85, 0.9, 1.0), size=radius * 2)
	add_light("rim", "AREA", 45.0 * radius * radius, centre + Vector((-r * 0.3, r * 1.1, r * 0.9)), (math.radians(-50), 0, math.radians(170)), size=radius)
	cam_d = bpy.data.cameras.new("cam")
	cam_d.lens = 60
	cam = bpy.data.objects.new("cam", cam_d)
	sc.collection.objects.link(cam)
	sc.camera = cam
	fov = 2 * math.atan(36 / (2 * cam_d.lens))
	horiz = max(size.x, size.y)
	dist = max(size.z, horiz) / (2 * math.tan(fov / 2)) * 1.12
	frames = []
	name = os.path.splitext(os.path.basename(path))[0]
	views = [(145, "front"), (-35, "back"), (145, "clay")]
	for i, (yaw, label) in enumerate(views):
		if label == "clay":
			clay(objs)
			if engine == "workbench":
				sc.display.shading.color_type = "SINGLE"
				sc.display.shading.single_color = (0.6, 0.6, 0.6)
		a = math.radians(yaw - 90)
		el = math.radians(14)
		cam.location = centre + Vector((math.cos(a) * math.cos(el), math.sin(a) * math.cos(el), math.sin(el))) * dist
		d = centre - cam.location
		cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
		fp = os.path.join(out_dir, "_%s_%d.png" % (name, i))
		sc.render.filepath = fp
		bpy.ops.render.render(write_still=True)
		frames.append(fp)
	return frames


def stitch(frames, out):
	imgs = [bpy.data.images.load(f) for f in frames]
	w, h = imgs[0].size
	big = bpy.data.images.new("sheet", w * len(imgs), h)
	px_all = [0.0] * (w * len(imgs) * h * 4)
	for k, im in enumerate(imgs):
		p = list(im.pixels)
		for y in range(h):
			row = p[y * w * 4:(y + 1) * w * 4]
			start = (y * w * len(imgs) + k * w) * 4
			px_all[start:start + w * 4] = row
	big.pixels = px_all
	big.filepath_raw = out
	big.file_format = "PNG"
	big.save()
	for f in frames:
		os.remove(f)


for f in files:
	name = os.path.splitext(os.path.basename(f))[0]
	parent = os.path.basename(os.path.dirname(f))
	out = os.path.join(out_dir, "%s__%s.png" % (parent, name))
	if os.path.exists(out):
		continue
	try:
		fr = render_one(f)
		if fr:
			stitch(fr, out)
			print("[SHEET] ok", out)
	except Exception as e:  # noqa: BLE001
		print("[SHEET] fail", f, e)
