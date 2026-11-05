"""Real branching lightning for Arc (jj, 2026-11-04: "redo the lightning coming off of it to look better"): bolts grown
in Blender (a jagged main channel by midpoint displacement in 3D, forks branching off it and forking again, every
channel a curve tube thinning toward its tip), lit only by their own emission and rendered in Cycles with the
compositor's glare, orthographic from the side, so each frame is a photograph-like bolt with its glow. Each bolt runs
from the left edge's middle to the right edge's middle; the game stretches a frame between two points.

    blender -b --python tools/blender/fx/lightning_bolts.py -- <outdir> [count=16] [px=512]

Writes <outdir>/bolt_NN.png (greyscale light on black); tools/fx_bolt_atlas.py packs them.
"""
import bpy, sys, os, math, random
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "/tmp/bolts")
N = int(argv[1]) if len(argv) > 1 else 16
PX = int(argv[2]) if len(argv) > 2 else 512
os.makedirs(OUT, exist_ok=True)
L = 4.0          # the bolt's length (scene units): the frame is L wide, L / 4 tall


def jag(a, b, levels, rough, rng, keep=None):
    """Midpoint displacement: every level halves each segment and kicks its middle sideways by `rough` of its span,
    so the channel is jagged at every scale (lightning's look). `keep` holds it inside the frame."""
    pts = [a, b]
    for lv in range(levels):
        out = [pts[0]]
        for i in range(len(pts) - 1):
            p, q = pts[i], pts[i + 1]
            m = (p + q) * 0.5
            span = (q - p).length
            off = Vector((0, rng.uniform(-1, 1), rng.uniform(-1, 1))) * span * rough
            if rng.random() < 0.12:
                off *= 2.2          # now and then a sharp kink
            n = m + off
            if keep is not None:
                n.z = max(-keep, min(keep, n.z))
            out += [n, q]
        pts = out
    return pts


def tube(name, pts, r0, r1, strength):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = 2
    sp = cu.splines.new("POLY")
    sp.points.add(len(pts) - 1)
    for i, p in enumerate(pts):
        t = i / max(1, len(pts) - 1)
        sp.points[i].co = (p.x, p.y, p.z, 1.0)
        sp.points[i].radius = r0 + (r1 - r0) * t
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = strength
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], o.inputs["Surface"])
    cu.materials.append(m)
    return ob


def bolt(seed):
    rng = random.Random(seed)
    a = Vector((-L / 2, 0, 0))
    b = Vector((L / 2, 0, 0))
    main = jag(a, b, 8, 0.2, rng, keep=L * 0.1)
    tube("main", main, 0.0075, 0.005, 14.0)
    # forks: off the main channel, angled on toward the end, thinner, some forking again
    for k in range(rng.randint(3, 6)):
        i = rng.randint(4, len(main) - 12)
        s = main[i]
        d = (b - s).normalized() + Vector((0, rng.uniform(-1.2, 1.2), rng.uniform(-0.9, 0.9)))
        f_end = s + d.normalized() * L * rng.uniform(0.12, 0.3)
        f_end.z = max(-L * 0.11, min(L * 0.11, f_end.z))
        fork = jag(s, f_end, 6, 0.24, rng, keep=L * 0.115)
        tube("fork%d" % k, fork, 0.004, 0.001, 10.0)
        if rng.random() < 0.6:
            j = rng.randint(2, len(fork) - 3)
            s2 = fork[j]
            d2 = (f_end - s2).normalized() + Vector((0, rng.uniform(-1, 1), 0))
            e2 = s2 + d2.normalized() * L * rng.uniform(0.05, 0.12)
            e2.z = max(-L * 0.115, min(L * 0.115, e2.z))
            sub = jag(s2, e2, 5, 0.25, rng, keep=L * 0.118)
            tube("sub%d" % k, sub, 0.0025, 0.0007, 7.0)


def scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16
    sc.cycles.use_denoising = False
    sc.render.resolution_x = PX
    sc.render.resolution_y = PX // 4
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
    sc.world = w
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = L
    cam.location = (0, -10, 0)
    cam.rotation_euler = (math.pi / 2, 0, 0)
    sc.camera = cam
    # the glow: the compositor's glare (fog glow) over the bolt's own light
    sc.use_nodes = True
    nt = sc.node_tree
    nt.nodes.clear()
    rl = nt.nodes.new("CompositorNodeRLayers")
    gl = nt.nodes.new("CompositorNodeGlare")
    gl.glare_type = "FOG_GLOW"
    gl.quality = "HIGH"
    gl.threshold = 0.7
    gl.size = 7
    gl.mix = -0.35
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(rl.outputs["Image"], gl.inputs["Image"])
    nt.links.new(gl.outputs["Image"], comp.inputs["Image"])
    return sc


for n in range(N):
    sc = scene()
    bolt(1000 + n * 7)
    sc.render.filepath = os.path.join(OUT, "bolt_%02d.png" % n)
    bpy.ops.render.render(write_still=True)
    print("[bolt]", n, flush=True)
