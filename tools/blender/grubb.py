# King Grubb the Gilded, built in Blender (4.5) by script and exported to assets/models/grubb.glb.
#
# Run it inside Blender (Text editor, or `blender -b -P tools/blender/grubb.py`). It builds into the
# "Grubb" collection and leaves everything else alone. The .glb goes to the Blender workspace's
# exports/ and is copied into the game's assets/models/; keep the .blend in the workspace's
# sources/, not in this repo (Godot tries to import .blend files it finds by launching Blender).
#
# Coordinates: the game's goblin layout (scripts/goblin.gd, native units before the king's 1.5x
# scale) with Godot (x, y, z) -> Blender (x, -z, y), so the model faces +Y here and -Z in Godot.
# Bone names match the game's joints, so the game's procedural animation drives the skin.
import bpy, bmesh, math, os, shutil
from mathutils import Vector, Matrix, Euler

ROOT = os.environ.get("ASHEN_ROOT", "/Users/blaine/dev/ashen-crown")
WORKSPACE = os.environ.get("GAME_FACTORY", os.path.expanduser("~/Documents/Blender/Game Factory"))
OUT = WORKSPACE + "/exports/grubb.glb"
GAME = ROOT + "/assets/models/grubb.glb"
K = 1.0 / 0.575        # a lone metaball's surface sits at 0.575 of its radius
STAGE = globals().get("STAGE", "all")


def G(x, y, z):
    return Vector((x, -z, y))


def coll():
    c = bpy.data.collections.get("Grubb")
    if c is None:
        c = bpy.data.collections.new("Grubb")
        bpy.context.scene.collection.children.link(c)
    return c


def clear():
    c = coll()
    for o in list(c.objects):
        d = o.data
        bpy.data.objects.remove(o, do_unlink=True)
        if d is not None and d.users == 0:
            if isinstance(d, bpy.types.Mesh):
                bpy.data.meshes.remove(d)
            elif isinstance(d, bpy.types.MetaBall):
                bpy.data.metaballs.remove(d)
            elif isinstance(d, bpy.types.Armature):
                bpy.data.armatures.remove(d)


# ---------------------------------------------------------------- joints (Godot space, native units)
J = {
    "hips": (0, 0.62, 0), "torso": (0, 0.67, 0), "belly": (0, 0.83, -0.05), "head": (0, 1.23, -0.2),
    "jaw": (0, 1.25, -0.25), "crowns": (0, 1.49, -0.18), "medal": (0, 1.22, -0.13),
    "sack0": (0, 1.03, 0.32), "sack1": (-0.2, 1.39, 0.24), "sack2": (0.22, 1.37, 0.26),
}
for s, sn in ((1, "r"), (-1, "l")):
    J["sh_" + sn] = (s * 0.29, 1.15, 0.04)
    J["el_" + sn] = (s * 0.29, 0.79, 0.04)
    J["hand_" + sn] = (s * 0.29, 0.46, 0.04)
    J["leg_" + sn] = (s * 0.15, 0.59, 0.0)
    J["knee_" + sn] = (s * 0.20, 0.32, -0.02)
    J["ear_" + sn] = (s * 0.15, 1.37, -0.19)


def at(j, x=0.0, y=0.0, z=0.0):
    """A point given relative to joint j, in Godot axes; returns Blender coords."""
    b = J[j]
    return G(b[0] + x, b[1] + y, b[2] + z)


# ---------------------------------------------------------------- metaball sculpting
class Meta:
    def __init__(self, name, res=0.007):
        self.mb = bpy.data.metaballs.new(name)
        self.mb.resolution = res
        self.mb.render_resolution = res
        self.mb.threshold = 0.6
        self.ob = bpy.data.objects.new(name, self.mb)
        coll().objects.link(self.ob)

    def ball(self, p, r, stiff=2.0, neg=False):
        e = self.mb.elements.new()
        e.co = p
        e.radius = r * K
        e.stiffness = stiff
        e.use_negative = neg
        return e

    def ell(self, p, rx, ry, rz, stiff=2.0, neg=False, rot=(0, 0, 0)):
        """Ellipsoid with Godot-axis radii."""
        e = self.mb.elements.new(type='ELLIPSOID')
        e.co = p
        e.radius = K
        e.size_x, e.size_y, e.size_z = rx, rz, ry
        e.stiffness = stiff
        e.use_negative = neg
        e.rotation = Euler(rot).to_quaternion()
        return e

    def chain(self, pts, radii, stiff=2.0, step=0.35):
        """Balls along a polyline (Blender points), radius tapering: a limb, a nose."""
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            L = (b - a).length
            n = max(1, int(L / (min(radii[i], radii[i + 1]) * step)))
            for k in range(n):
                t = k / n
                self.ball(a.lerp(b, t), radii[i] + (radii[i + 1] - radii[i]) * t, stiff)
        self.ball(pts[-1], radii[-1], stiff)

    def to_mesh(self, name):
        dg = bpy.context.evaluated_depsgraph_get()
        me = bpy.data.meshes.new_from_object(self.ob.evaluated_get(dg))
        me.name = name
        ob = bpy.data.objects.new(name, me)
        coll().objects.link(ob)
        bpy.data.objects.remove(self.ob)
        return ob


def ellipsoid_mesh(name, p, rx, ry, rz, rot=(0, 0, 0)):
    """A UV-sphere mesh with Godot-axis radii (cutters, eyeballs, teeth)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=16, radius=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    ob.location = p
    ob.scale = (rx, rz, ry)
    ob.rotation_euler = rot
    return ob


def tube_mesh(name, pts, radii, flat=1.0, thin=(0, 1, 0), sides=32, steps=10):
    """A closed tube along Blender points with a radius per point; flat < 1 squashes the
    cross-section along the axis nearest `thin` (ear blades, a narrow nose bridge)."""
    P, R = [], []
    for i in range(len(pts) - 1):
        for k in range(steps):
            t = k / steps
            P.append(pts[i].lerp(pts[i + 1], t))
            R.append(radii[i] + (radii[i + 1] - radii[i]) * t)
    P.append(pts[-1])
    R.append(radii[-1])
    # smooth the polyline a little so joints between segments don't kink
    for _ in range(3):
        P = [P[0]] + [(P[i - 1] + P[i] * 2 + P[i + 1]) / 4 for i in range(1, len(P) - 1)] + [P[-1]]
    bm = bmesh.new()
    rings = []
    thin = Vector(thin)
    for i, p in enumerate(P):
        tan = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        side = tan.cross(thin)
        if side.length < 1e-4:
            side = tan.cross(Vector((1, 0, 0)))
        side.normalize()
        up = side.cross(tan).normalized()
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(bm.verts.new(p + side * math.cos(a) * R[i] + up * math.sin(a) * R[i] * flat))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    return ob


def fuse(base, parts):
    """Join parts into base; the next voxel remesh melts them into one surface."""
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    base.select_set(True)
    bpy.context.view_layer.objects.active = base
    bpy.ops.object.join()
    return base


def carve(ob, cutters):
    """Boolean-subtract each cutter, then delete it."""
    for c in cutters:
        m = ob.modifiers.new("cut", 'BOOLEAN')
        m.operation = 'DIFFERENCE'
        m.solver = 'EXACT'
        m.object = c
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=m.name)
        bpy.data.objects.remove(c, do_unlink=True)


def soften(ob, voxel=0.004, smooth=1.0, repeat=6):
    """Even out the topology and round off boolean edges."""
    r = ob.modifiers.new("remesh", 'REMESH')
    r.mode = 'VOXEL'
    r.voxel_size = voxel
    r.adaptivity = 0.0
    sm = ob.modifiers.new("smooth", 'LAPLACIANSMOOTH')
    sm.lambda_factor = smooth
    sm.iterations = repeat
    sm.use_volume_preserve = True
    bpy.context.view_layer.objects.active = ob
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def head(m):
    """Only the neck stays in the torso metaball; the head is its own sculpted shell."""
    m.chain([at("torso", 0, 0.44, 0.02), at("torso", 0, 0.52, -0.08), at("torso", 0, 0.58, -0.17)], [0.1, 0.095, 0.09])


def head_cuts():
    return [ellipsoid_mesh("cut_navel", at("belly", 0, -0.03, -0.36), 0.016, 0.02, 0.03)]


# ---------------------------------------------------------------- sculpting brushes
import numpy as np


class Sculptor:
    """Sculpt-style brushes on a high-poly mesh, by script: inflate, grab, crease and ridge
    along curves (wrinkles, folds, veins), warts."""

    def __init__(self, ob):
        self.ob = ob
        me = ob.data
        n = len(me.vertices)
        self.co = np.empty(n * 3, dtype=np.float64)
        me.vertices.foreach_get("co", self.co)
        self.co = self.co.reshape(-1, 3)
        self.normals()

    def normals(self):
        me = self.ob.data
        me.vertices.foreach_set("co", self.co.ravel())
        me.update()
        no = np.empty(len(me.vertices) * 3, dtype=np.float64)
        me.vertices.foreach_get("normal", no)
        self.no = no.reshape(-1, 3)

    def commit(self):
        self.ob.data.vertices.foreach_set("co", self.co.ravel())
        self.ob.data.update()

    @staticmethod
    def _fall(d, r):
        t = np.clip(1.0 - d / r, 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    def inflate(self, c, r, amt):
        d = np.linalg.norm(self.co - np.array(c), axis=1)
        self.co += self.no * (amt * self._fall(d, r))[:, None]

    def grab(self, c, r, off):
        d = np.linalg.norm(self.co - np.array(c), axis=1)
        self.co += np.array(off)[None, :] * self._fall(d, r)[:, None]

    def snake(self, pts, radii, sub=4):
        """Snake hook: drag a small region along a path (noses, ears, horns). The path starts
        at the surface point nearest its first point."""
        cur = self.co[int(np.argmin(np.linalg.norm(self.co - np.array(pts[0]), axis=1)))].copy()
        for i in range(1, len(pts)):
            nxt = np.array(pts[i], dtype=np.float64)
            for k in range(sub):
                r = radii[i - 1] + (radii[i] - radii[i - 1]) * (k / sub)
                step = (nxt - cur) / (sub - k)
                d = np.linalg.norm(self.co - cur, axis=1)
                self.co += step[None, :] * self._fall(d, r)[:, None]
                cur = cur + step

    def _line(self, pts):
        """Distance from every vertex to a polyline and the closest point on it."""
        best = np.full(len(self.co), 1e9)
        close = np.zeros_like(self.co)
        for i in range(len(pts) - 1):
            a = np.array(pts[i])
            b = np.array(pts[i + 1])
            ab = b - a
            t = np.clip(((self.co - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
            p = a + t[:, None] * ab
            d = np.linalg.norm(self.co - p, axis=1)
            m = d < best
            best[m] = d[m]
            close[m] = p[m]
        return best, close

    def crease(self, pts, r, depth, pinch=0.4):
        """A groove along a curve: pushed in along the normal and pinched toward the line."""
        d, close = self._line(pts)
        f = self._fall(d, r)
        f2 = f * f
        self.co -= self.no * (depth * f2)[:, None]
        self.co += (close - self.co) * (pinch * f * (1.0 - f2))[:, None]

    def ridge(self, pts, r, height, pinch=0.2):
        d, close = self._line(pts)
        f = self._fall(d, r)
        self.co += self.no * (height * f * f)[:, None]
        self.co += (close - self.co) * (pinch * f)[:, None]

    def warts(self, seed, count, box_c, box_r, r=(0.006, 0.012), h=(0.002, 0.006)):
        rng = np.random.default_rng(seed)
        c = np.array(box_c)
        for _ in range(count):
            p = c + rng.uniform(-1, 1, 3) * np.array(box_r)
            # snap to the nearest surface point
            i = int(np.argmin(np.linalg.norm(self.co - p, axis=1)))
            self.inflate(self.co[i], rng.uniform(*r), rng.uniform(*h))


def curve(j, *pts):
    """Points relative to joint j (Godot axes) -> Blender points."""
    return [at(j, *p) for p in pts]


def sculpt_torso(ob):
    S = Sculptor(ob)
    # neck folds, collarbones, the spine knuckles on the hunch
    for k in range(3):
        S.crease(curve("torso", (-0.09, 0.47 + k * 0.03, -0.12 - k * 0.025), (0, 0.46 + k * 0.03, -0.15 - k * 0.025), (0.09, 0.47 + k * 0.03, -0.12 - k * 0.025)), 0.012, 0.005)
    for s in (1, -1):
        S.ridge(curve("torso", (s * 0.04, 0.47, -0.13), (s * 0.15, 0.49, -0.1), (s * 0.24, 0.5, -0.03)), 0.014, 0.004)
    for k in range(6):
        S.inflate(at("torso", 0, 0.58 - k * 0.07, 0.26 - k * 0.005), 0.025, 0.006)
    # belly: the fold under the chest, the overhang above the belt, the navel crease
    S.crease(curve("belly", (-0.24, 0.12, -0.15), (-0.12, 0.17, -0.28), (0, 0.18, -0.31), (0.12, 0.17, -0.28), (0.24, 0.12, -0.15)), 0.025, 0.01, 0.3)
    S.crease(curve("belly", (-0.26, -0.2, -0.2), (-0.12, -0.24, -0.32), (0, -0.25, -0.35), (0.12, -0.24, -0.32), (0.26, -0.2, -0.2)), 0.025, 0.012, 0.3)
    S.crease(curve("belly", (0, -0.0, -0.355), (0, -0.06, -0.35)), 0.012, 0.008)
    # warts over the scalp, face and shoulders
    S.warts(5, 18, at("torso", 0, 0.45, 0.05), (0.25, 0.1, 0.2))
    S.warts(7, 14, at("belly", 0, 0, -0.1), (0.28, 0.22, 0.25), r=(0.005, 0.009), h=(0.0015, 0.004))
    S.commit()


def sculpt_limb(ob, sn):
    S = Sculptor(ob)
    s = 1 if sn == "r" else -1
    if ob.name.startswith("BodyHi_arm"):
        # elbow and wrist creases, knuckles, a couple of veins down the forearm
        S.crease(curve("el_" + sn, (-s * 0.04, 0.0, -0.045), (0, 0.0, -0.06), (s * 0.04, 0.0, -0.045)), 0.012, 0.006)
        S.crease(curve("hand_" + sn, (-0.04, 0.0, -0.035), (0, 0.0, -0.045), (0.04, 0.0, -0.035)), 0.01, 0.004)
        for k in range(4):
            x = (-0.045 + k * 0.03) * 1.0
            S.inflate(at("hand_" + sn, x, -0.125, -0.03), 0.018, 0.006)
        S.ridge(curve("el_" + sn, (s * 0.01, -0.03, -0.06), (s * 0.02, -0.12, -0.075), (0, -0.2, -0.065), (-s * 0.01, -0.3, -0.05)), 0.006, 0.0035)
        S.ridge(curve("sh_" + sn, (s * 0.05, -0.1, -0.06), (s * 0.06, -0.2, -0.05), (s * 0.04, -0.3, -0.05)), 0.006, 0.003)
        S.inflate(at("sh_" + sn, 0, -0.14, -0.06), 0.06, 0.01)     # bicep
        S.inflate(at("el_" + sn, 0, -0.1, -0.03), 0.06, 0.012)     # forearm
    else:
        S.crease(curve("knee_" + sn, (-0.05, 0.02, -0.04), (0, 0.01, -0.07), (0.05, 0.02, -0.04)), 0.012, 0.005)
        S.inflate(at("knee_" + sn, 0, 0.0, -0.06), 0.035, 0.008)   # kneecap
        for k in range(3):
            S.crease(curve("knee_" + sn, (-s * 0.045 + (k - 1) * 0.035, -0.27, -0.13), (-s * 0.045 + (k - 1) * 0.035, -0.3, -0.2)), 0.008, 0.005, 0.5)
    S.warts(11 + s, 10, ob.location + Vector(np.mean(S.co, axis=0)), (0.12, 0.12, 0.3), r=(0.005, 0.009), h=(0.0015, 0.004))
    S.commit()


def material(name, color, metal=0.0, rough=0.5, emit=None, strength=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs['Base Color'].default_value = (*color, 1.0)
    b.inputs['Metallic'].default_value = metal
    b.inputs['Roughness'].default_value = rough
    if emit is not None:
        b.inputs['Emission Color'].default_value = (*emit, 1.0)
        b.inputs['Emission Strength'].default_value = strength
    return m


def cone_mesh(name, base, tip, r, segs=10):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=0.0, depth=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    d = tip - base
    ob.location = (base + tip) / 2
    ob.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    ob.scale = (1, 1, d.length)
    return ob


def bits():
    """Eyes, slit pupils, a row of crooked teeth (two of gold) and two tusks, each rigidly on its
    bone (a vertex group named after it), joined into one object."""
    H = lambda x, y, z: at("head", x, y, z)
    eye = material("GrubbEye", (0.9, 0.45, 0.03), rough=0.2, emit=(1.0, 0.5, 0.04), strength=2.2)
    dark = material("GrubbDark", (0.01, 0.008, 0.006), rough=0.4)
    tooth = material("GrubbTooth", (0.45, 0.38, 0.25), rough=0.5)
    gold = material("GrubbGold", (1.0, 0.72, 0.28), metal=1.0, rough=0.25)
    parts = []
    def add(ob, bone, mat):
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        ob.data.materials.append(mat)
        vg = ob.vertex_groups.new(name=bone)
        vg.add(range(len(ob.data.vertices)), 1.0, 'REPLACE')
        parts.append(ob)
    for s in (1, -1):
        add(ellipsoid_mesh("eye", H(s * 0.058, 0.11, -0.14), 0.019, 0.014, 0.018), "head", eye)
        add(ellipsoid_mesh("pupil", H(s * 0.058, 0.11, -0.157), 0.0035, 0.012, 0.004), "head", dark)
    for i in range(9):
        a = -0.85 + i * (1.7 / 8)
        x = math.sin(a) * 0.1
        z = -0.13 - math.cos(a) * 0.085
        y = -0.062 + abs(a) * 0.038
        L = 0.022 + 0.012 * abs(math.sin(i * 2.3))
        base = H(x, y + 0.006, z)
        tip = H(x + math.sin(i * 1.7) * 0.004, y - L, z - 0.004)
        add(cone_mesh("tooth", base, tip, 0.009), "head", gold if i in (2, 6) else tooth)
    for s in (1, -1):
        add(cone_mesh("tusk", H(s * 0.06, -0.1, -0.19), H(s * 0.074, -0.04, -0.215), 0.015), "jaw", tooth)
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "Grubb_Bits"
    bpy.ops.object.shade_smooth()
    return ob


def head_shell():
    """Grubb's head, sculpted from a dense sphere: skull sloping back, muzzle, heavy V brow,
    deep sockets, cheekbones, a long hooked nose and long ears pulled out by snake hooks, an
    underbite jaw with jowls. Blocked out, remeshed, then detailed."""
    me = bpy.data.meshes.new("BodyHi_head")
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=6, radius=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("BodyHi_head", me)
    coll().objects.link(ob)
    c = at("head", 0, 0.12, 0.0)
    for v in me.vertices:
        v.co = c + Vector((v.co.x * 0.15, v.co.y * 0.19, v.co.z * 0.16))
    me.update()
    H = lambda x, y, z: at("head", x, y, z)
    V = lambda x, y, z: G(x, y, z) - G(0, 0, 0)
    S = Sculptor(ob)
    # block out: skull back and up, muzzle and jaw forward, jowls out, neck stump down
    S.grab(H(0, 0.18, 0.12), 0.14, V(0, 0.04, 0.09))         # skull swept back
    S.grab(H(0, 0.02, -0.12), 0.12, V(0, -0.02, -0.07))
    S.grab(H(0, -0.06, -0.06), 0.12, V(0, -0.075, -0.04))
    S.grab(H(0, -0.1, -0.15), 0.07, V(0, -0.02, -0.05))          # underbite chin
    for s in (1, -1):
        S.grab(H(s * 0.1, -0.03, -0.09), 0.09, V(s * 0.055, -0.03, -0.01))   # jowls: a wide, heavy face
        S.grab(H(s * 0.09, 0.07, -0.13), 0.05, V(s * 0.01, 0.0, -0.02))  # cheekbones
    S.grab(H(0, -0.02, 0.05), 0.1, V(0, -0.08, 0.02))             # into the neck
    S.normals()
    # brow: forward and down, lowest at the centre (an angry V)
    S.grab(H(0, 0.16, -0.12), 0.1, V(0, -0.01, -0.035))
    S.grab(H(0, 0.15, -0.15), 0.04, V(0, -0.02, -0.01))
    for s in (1, -1):
        S.inflate(H(s * 0.06, 0.155, -0.16), 0.045, 0.02)
        S.inflate(H(s * 0.062, 0.11, -0.17), 0.04, -0.045)         # deep sockets under the brow
    S.normals()
    # the nose: drag out a long hook; the ears: long blades swept back and up
    # a hard brow ridge over the sockets
    for s in (1, -1):
        S.ridge([H(s * 0.125, 0.16, -0.12), H(s * 0.07, 0.15, -0.175), H(s * 0.015, 0.128, -0.195)], 0.032, 0.028, 0.1)
    S.commit()
    # insert the long hooked nose and the ear blades, then melt them in
    # a long, narrow nose hooking down to a sharp point
    parts = [tube_mesh("nose", [H(0, 0.115, -0.17), H(0, 0.095, -0.225), H(0, 0.06, -0.27), H(0, 0.025, -0.29), H(0, -0.005, -0.29)], [0.028, 0.032, 0.026, 0.014, 0.003], flat=1.0, thin=(1, 0, 0))]
    parts[0].scale = (0.62, 1, 1)
    for s in (1, -1):
        e = tube_mesh("ear", [H(s * 0.12, 0.13, 0.0), H(s * 0.2, 0.15, 0.03), H(s * 0.3, 0.19, 0.07), H(s * 0.39, 0.24, 0.1), H(s * 0.46, 0.285, 0.125)], [0.06, 0.075, 0.062, 0.036, 0.004], flat=0.28, thin=tuple(G(0, 0, 1) - G(0, 0, 0)))
        parts.append(e)
    for p in parts:
        bpy.context.view_layer.objects.active = p
        p.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    fuse(ob, parts)
    soften(ob, voxel=0.0028, smooth=0.6, repeat=3)
    # detail on the even remeshed surface
    S = Sculptor(ob)
    for s in (1, -1):
        # flatten the ears into blades
        ec = np.array(H(s * 0.3, 0.19, 0.06))
        d = np.linalg.norm(S.co - ec, axis=1)
        f = Sculptor._fall(d, 0.17)
        flat = np.array(V(0, 0, 1))
        S.co -= flat[None, :] * ((S.co - ec) @ flat)[:, None] * (0.2 * f)[:, None]
    S.normals()
    for s in (1, -1):
        S.crease([H(s * 0.2, 0.16, 0.0), H(s * 0.3, 0.2, 0.04), H(s * 0.38, 0.235, 0.075)], 0.05, 0.01, 0.0)   # ear hollow
        S.crease([H(s * 0.035, 0.03, -0.27), H(s * 0.07, -0.01, -0.225), H(s * 0.085, -0.05, -0.18), H(s * 0.09, -0.08, -0.14)], 0.016, 0.01, 0.5)   # nasolabial
        S.crease([H(s * 0.012, 0.17, -0.19), H(s * 0.02, 0.135, -0.2)], 0.012, 0.008)    # frown furrows
        S.crease([H(s * 0.105, 0.105, -0.155), H(s * 0.135, 0.125, -0.13)], 0.008, 0.004)  # crow's feet
        S.crease([H(s * 0.1, 0.095, -0.16), H(s * 0.135, 0.085, -0.13)], 0.008, 0.004)
        S.crease([H(s * 0.035, 0.075, -0.205), H(s * 0.065, 0.068, -0.195), H(s * 0.095, 0.078, -0.17)], 0.01, 0.005)  # under-eye bags
        S.inflate(H(s * 0.02, -0.015, -0.31), 0.01, -0.012)        # nostrils
        S.inflate(H(s * 0.1, 0.03, -0.15), 0.035, 0.012)           # cheeks bunched up by the grin
    for k in range(3):
        y = 0.21 + k * 0.025
        S.crease([H(-0.09, y - 0.012, -0.12 + k * 0.012), H(0, y + 0.012, -0.16 + k * 0.012), H(0.09, y - 0.012, -0.12 + k * 0.012)], 0.009, 0.005)
    S.crease([H(-0.03, 0.12, -0.215), H(0, 0.126, -0.225), H(0.03, 0.12, -0.215)], 0.007, 0.004)
    # the mouth: a deep line, a fat upper lip, a jutting lower lip, the crease under it
    # a wide, wicked grin: deep at the centre, curling up into the cheeks
    S.crease([H(-0.13, -0.02, -0.13), H(-0.085, -0.06, -0.19), H(0, -0.078, -0.22), H(0.085, -0.06, -0.19), H(0.13, -0.02, -0.13)], 0.02, 0.03, 0.6)
    S.inflate(H(0, -0.05, -0.22), 0.045, 0.008)
    S.inflate(H(0, -0.1, -0.22), 0.045, 0.012)
    S.crease([H(-0.06, -0.125, -0.2), H(0, -0.132, -0.225), H(0.06, -0.125, -0.2)], 0.012, 0.006)
    S.warts(3, 26, H(0, 0.13, -0.02), (0.16, 0.13, 0.17))
    S.inflate(H(0.026, 0.07, -0.278), 0.012, 0.008)
    S.commit()
    return ob


def body():
    """The king's body as fused shells: torso+head, each arm, each leg."""
    shells = []
    m = Meta("GBody")
    m.ell(at("hips", 0, -0.02, 0.01), 0.24, 0.12, 0.19)
    m.ell(at("torso", 0, 0.38, 0.03), 0.25, 0.19, 0.18)
    m.ell(at("torso", 0, 0.47, 0.12), 0.19, 0.15, 0.14)           # the hunch
    for s in (1, -1):
        m.ell(at("torso", s * 0.19, 0.5, 0.05), 0.12, 0.08, 0.1)   # traps
        m.ell(at("torso", s * 0.11, 0.33, -0.13), 0.1, 0.075, 0.05)  # sagging pecs
        m.ball(at("sh_" + ("r" if s > 0 else "l")), 0.085)
    m.chain([at("torso", 0, 0.44, 0.02), at("torso", 0, 0.52, -0.08), at("torso", 0, 0.56, -0.19)], [0.1, 0.095, 0.085])
    m.ell(at("belly", 0, 0.0, -0.04), 0.31, 0.26, 0.29)
    m.ell(at("belly", 0, -0.09, -0.12), 0.25, 0.16, 0.24)          # the sag
    head(m)
    torso = m.to_mesh("BodyHi_torso")
    carve(torso, head_cuts())
    shells.append(torso)
    for s, sn in ((1, "r"), (-1, "l")):
        a = Meta("GArm" + sn)
        a.ball(at("sh_" + sn), 0.085)
        a.chain([at("sh_" + sn), at("sh_" + sn, 0, -0.12, -0.015), at("sh_" + sn, 0, -0.25, 0), at("el_" + sn)], [0.078, 0.085, 0.064, 0.056])
        a.ball(at("el_" + sn), 0.057)
        a.chain([at("el_" + sn), at("el_" + sn, 0, -0.12, -0.025), at("el_" + sn, 0, -0.22, -0.01), at("hand_" + sn)], [0.058, 0.068, 0.056, 0.042])
        hs = 1.35
        a.ell(at("hand_" + sn, 0, -0.05 * hs, 0), 0.05 * hs, 0.06 * hs, 0.03 * hs)
        a.ell(at("hand_" + sn, 0, -0.095 * hs, -0.005), 0.045 * hs, 0.02 * hs, 0.022 * hs)
        shells.append(a.to_mesh("BodyHi_arm_" + sn))
        g = Meta("GLeg" + sn)
        g.ball(at("leg_" + sn), 0.1)
        g.chain([at("leg_" + sn), at("leg_" + sn, s * 0.03, -0.14, -0.02), at("knee_" + sn)], [0.105, 0.095, 0.068])
        g.ball(at("knee_" + sn), 0.068)
        g.chain([at("knee_" + sn), at("knee_" + sn, -s * 0.02, -0.13, 0), at("knee_" + sn, -s * 0.04, -0.25, 0.03)], [0.066, 0.06, 0.043])
        g.ell(at("knee_" + sn, -s * 0.015, -0.08, 0.035), 0.058, 0.08, 0.06)   # calf
        g.ell(at("knee_" + sn, -s * 0.045, -0.29, -0.05), 0.066, 0.042, 0.145)
        g.ell(at("knee_" + sn, -s * 0.045, -0.28, 0.06), 0.045, 0.04, 0.04)    # heel
        shells.append(g.to_mesh("BodyHi_leg_" + sn))
    for sh in shells:
        soften(sh)
    sculpt_torso(shells[0])
    for sh in shells[1:]:
        sculpt_limb(sh, sh.name[-1])
    shells.append(head_shell())
    for sh in shells:
        # fine skin: pores and a little unevenness
        tex = bpy.data.textures.get("grubb_pores") or bpy.data.textures.new("grubb_pores", 'CLOUDS')
        tex.noise_scale = 0.004
        d = sh.modifiers.new("pores", 'DISPLACE')
        d.texture = tex
        d.texture_coords = 'OBJECT'
        d.strength = 0.0007
        d.mid_level = 0.5
        bpy.context.view_layer.objects.active = sh
        bpy.ops.object.modifier_apply(modifier=d.name)
    return shells


# ---------------------------------------------------------------- the game mesh, baked
BAKE_RES = 2048


def game_mesh(shells):
    """Lower-poly copies of the shells, joined into one object and unwrapped."""
    los = []
    for sh in shells:
        me = sh.data.copy()
        lo = bpy.data.objects.new(sh.name.replace("Hi", "Lo"), me)
        coll().objects.link(lo)
        r = lo.modifiers.new("remesh", 'REMESH')
        r.mode = 'VOXEL'
        r.voxel_size = 0.006 if sh.name.endswith("head") else 0.011
        d = lo.modifiers.new("smooth", 'LAPLACIANSMOOTH')
        d.lambda_factor = 0.5
        d.iterations = 2
        dc = lo.modifiers.new("decimate", 'DECIMATE')
        dc.ratio = 0.3
        sm2 = lo.modifiers.new("smooth2", 'LAPLACIANSMOOTH')
        sm2.lambda_factor = 0.3
        sm2.iterations = 2
        bpy.context.view_layer.objects.active = lo
        for m in list(lo.modifiers):
            bpy.ops.object.modifier_apply(modifier=m.name)
        los.append(lo)
    bpy.ops.object.select_all(action='DESELECT')
    for lo in los:
        lo.select_set(True)
    bpy.context.view_layer.objects.active = los[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Grubb_Body"
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004)
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.shade_smooth()
    return body


def skin_material():
    """The procedural skin used for baking: mottled olive, paler belly, dark warts and creases."""
    m = bpy.data.materials.get("GrubbSkinHi") or bpy.data.materials.new("GrubbSkinHi")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tc = nt.nodes.new('ShaderNodeTexCoord')
    def noise(scale, detail=4.0):
        n = nt.nodes.new('ShaderNodeTexNoise')
        n.inputs['Scale'].default_value = scale
        n.inputs['Detail'].default_value = detail
        nt.links.new(tc.outputs['Object'], n.inputs['Vector'])
        return n
    def ramp(inp, stops):
        r = nt.nodes.new('ShaderNodeValToRGB')
        cr = r.color_ramp
        cr.elements[0].position, cr.elements[0].color = stops[0]
        cr.elements[1].position, cr.elements[1].color = stops[1]
        for pos, col in stops[2:]:
            e = cr.elements.new(pos)
            e.color = col
        nt.links.new(inp, r.inputs[0])
        return r
    big = ramp(noise(3.0).outputs['Fac'], [(0.35, (0.02, 0.026, 0.012, 1)), (0.65, (0.055, 0.065, 0.03, 1))])
    mot = noise(14.0, 6.0)
    mix = nt.nodes.new('ShaderNodeMix')
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs['Factor'].default_value = 0.6
    nt.links.new(big.outputs[0], mix.inputs[6])
    nt.links.new(ramp(mot.outputs['Fac'], [(0.3, (0.55, 0.55, 0.45, 1)), (0.7, (1.1, 1.05, 0.9, 1))]).outputs[0], mix.inputs[7])
    # warts: dark spots
    vor = nt.nodes.new('ShaderNodeTexVoronoi')
    vor.inputs['Scale'].default_value = 60.0
    nt.links.new(tc.outputs['Object'], vor.inputs['Vector'])
    wart = ramp(vor.outputs['Distance'], [(0.05, (0.45, 0.4, 0.3, 1)), (0.18, (1, 1, 1, 1))])
    m2 = nt.nodes.new('ShaderNodeMix')
    m2.data_type = 'RGBA'
    m2.blend_type = 'MULTIPLY'
    m2.inputs['Factor'].default_value = 1.0
    nt.links.new(mix.outputs[2], m2.inputs[6])
    nt.links.new(wart.outputs[0], m2.inputs[7])
    # cavities darker, ridges catch a little sallow yellow
    ao = nt.nodes.new('ShaderNodeAmbientOcclusion')
    ao.inputs['Distance'].default_value = 0.08
    nt.links.new(m2.outputs[2], ao.inputs['Color'])
    cav = ramp(ao.outputs['AO'], [(0.25, (0.18, 0.1, 0.07, 1)), (0.9, (1, 1, 1, 1))])
    m3 = nt.nodes.new('ShaderNodeMix')
    m3.data_type = 'RGBA'
    m3.blend_type = 'MULTIPLY'
    m3.inputs['Factor'].default_value = 1.0
    nt.links.new(m2.outputs[2], m3.inputs[6])
    nt.links.new(cav.outputs[0], m3.inputs[7])
    # age spots and a sallow belly
    spots = ramp(noise(28.0, 3.0).outputs['Fac'], [(0.62, (1, 1, 1, 1)), (0.7, (0.55, 0.42, 0.3, 1))])
    m4 = nt.nodes.new('ShaderNodeMix')
    m4.data_type = 'RGBA'
    m4.blend_type = 'MULTIPLY'
    m4.inputs['Factor'].default_value = 1.0
    nt.links.new(m3.outputs[2], m4.inputs[6])
    nt.links.new(spots.outputs[0], m4.inputs[7])
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(geo.outputs['Normal'], sep.inputs[0])
    front = ramp(sep.outputs['Y'], [(0.3, (0, 0, 0, 1)), (0.85, (1, 1, 1, 1))])
    m5 = nt.nodes.new('ShaderNodeMix')
    m5.data_type = 'RGBA'
    nt.links.new(front.outputs[0], m5.inputs['Factor'])
    nt.links.new(m4.outputs[2], m5.inputs[6])
    m5.inputs[7].default_value = (0.085, 0.08, 0.04, 1)
    belly = nt.nodes.new('ShaderNodeMix')
    belly.data_type = 'RGBA'
    sepp = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(tc.outputs['Object'], sepp.inputs[0])
    low = ramp(sepp.outputs['Z'], [(0.55, (1, 1, 1, 1)), (1.05, (0, 0, 0, 1))])
    nt.links.new(low.outputs[0], belly.inputs['Factor'])
    nt.links.new(m4.outputs[2], belly.inputs[6])
    nt.links.new(m5.outputs[2], belly.inputs[7])
    nt.links.new(belly.outputs[2], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.55
    # fine surface baked into the normal map: pores, crawling wrinkles, wart bumps
    pores = nt.nodes.new('ShaderNodeTexVoronoi')
    pores.inputs['Scale'].default_value = 420.0
    nt.links.new(tc.outputs['Object'], pores.inputs['Vector'])
    wr = nt.nodes.new('ShaderNodeTexNoise')
    wr.inputs['Scale'].default_value = 70.0
    wr.inputs['Detail'].default_value = 6.0
    wr.inputs['Distortion'].default_value = 2.5
    nt.links.new(tc.outputs['Object'], wr.inputs['Vector'])
    h1 = nt.nodes.new('ShaderNodeMath')
    h1.operation = 'MULTIPLY_ADD'
    h1.inputs[1].default_value = 0.5
    nt.links.new(pores.outputs['Distance'], h1.inputs[0])
    nt.links.new(wr.outputs['Fac'], h1.inputs[2])
    h2 = nt.nodes.new('ShaderNodeMath')
    h2.operation = 'ADD'
    nt.links.new(h1.outputs[0], h2.inputs[0])
    inv = nt.nodes.new('ShaderNodeMath')
    inv.operation = 'SUBTRACT'
    inv.inputs[0].default_value = 1.0
    nt.links.new(wart.outputs[0], inv.inputs[1])
    nt.links.new(inv.outputs[0], h2.inputs[1])
    bump = nt.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = 0.45
    bump.inputs['Distance'].default_value = 0.0015
    nt.links.new(h2.outputs[0], bump.inputs['Height'])
    nt.links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    return m


def bake(body, shells):
    """Bake the high shells' surface onto the game mesh: normal map and colour (with AO in it)."""
    sc = bpy.context.scene
    try:
        sc.render.engine = 'CYCLES'
    except TypeError as e:
        print("engine", e)
    sc.cycles.device = 'GPU' if bpy.context.preferences.addons['cycles'].preferences.has_active_device() else 'CPU'
    sc.cycles.samples = 32
    hi = skin_material()
    for sh in shells:
        sh.data.materials.clear()
        sh.data.materials.append(hi)
    imgs = {}
    for kind in ("color", "normal"):
        old = bpy.data.images.get("grubb_" + kind)
        if old is not None:
            bpy.data.images.remove(old)
        img = bpy.data.images.new("grubb_" + kind, BAKE_RES, BAKE_RES, alpha=False)
        if kind == "normal":
            img.colorspace_settings.name = 'Non-Color'
        imgs[kind] = img
    lo = bpy.data.materials.get("GrubbSkin") or bpy.data.materials.new("GrubbSkin")
    lo.use_nodes = True
    nt = lo.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bsdf = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    tcol = nt.nodes.new('ShaderNodeTexImage')
    tcol.image = imgs["color"]
    tnor = nt.nodes.new('ShaderNodeTexImage')
    tnor.image = imgs["normal"]
    nmap = nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(tcol.outputs[0], bsdf.inputs['Base Color'])
    nt.links.new(tnor.outputs[0], nmap.inputs['Color'])
    nt.links.new(nmap.outputs[0], bsdf.inputs['Normal'])
    bsdf.inputs['Roughness'].default_value = 0.55
    body.data.materials.clear()
    body.data.materials.append(lo)
    bpy.ops.object.select_all(action='DESELECT')
    for sh in shells:
        sh.hide_set(False)
        sh.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.02
    sc.render.bake.max_ray_distance = 0.05
    sc.render.bake.margin = 8
    for kind, typ in (("normal", 'NORMAL'), ("color", 'DIFFUSE')):
        for n in nt.nodes:
            n.select = False
        node = tnor if kind == "normal" else tcol
        node.select = True
        nt.nodes.active = node
        if typ == 'DIFFUSE':
            sc.render.bake.use_pass_direct = False
            sc.render.bake.use_pass_indirect = False
            sc.render.bake.use_pass_color = True
        bpy.ops.object.bake(type=typ)
        # colour as JPEG (small), the normal map as PNG (JPEG artefacts show up in the shading)
        ext = "jpg" if kind == "color" else "png"
        imgs[kind].filepath_raw = WORKSPACE + "/exports/grubb_%s.%s" % (kind, ext)
        imgs[kind].file_format = 'JPEG' if kind == "color" else 'PNG'
        os.makedirs(WORKSPACE + "/exports", exist_ok=True)
        imgs[kind].save()
    for sh in shells:
        sh.hide_set(True)
    print("baked", [i.name for i in imgs.values()])


# ---------------------------------------------------------------- rig and export
# [bone, parent, tail offset (Godot axes) from the joint]; the body deforms with these
BONES = [
    ("hips", None, (0, 0.05, 0)), ("torso", "hips", (0, 0.48, 0.02)), ("belly", "torso", (0, -0.05, -0.3)),
    ("head", "torso", (0, 0.25, 0)), ("jaw", "head", (0, -0.07, -0.15)),
    ("sh_r", "torso", None), ("el_r", "sh_r", None), ("hand_r", "el_r", (0, -0.16, 0)),
    ("sh_l", "torso", None), ("el_l", "sh_l", None), ("hand_l", "el_l", (0, -0.16, 0)),
    ("leg_r", "hips", None), ("knee_r", "leg_r", (-0.04, -0.26, 0.03)),
    ("leg_l", "hips", None), ("knee_l", "leg_l", (0.04, -0.26, 0.03)),
    ("ear_r", "head", (0.3, 0.14, 0.31)), ("ear_l", "head", (-0.3, 0.14, 0.31)),
    ("crowns", "head", (0, 0.2, 0)), ("sack0", "torso", (0, 0.3, 0)), ("sack1", "torso", (0, 0.25, 0)),
    ("sack2", "torso", (0, 0.25, 0)),
]
# bones that only carry rigid gear: kept out of the body's automatic weights
GEAR_BONES = ("crowns", "sack0", "sack1", "sack2")
CHILD = {"sh_r": "el_r", "el_r": "hand_r", "sh_l": "el_l", "el_l": "hand_l", "leg_r": "knee_r", "leg_l": "knee_l"}


def rig(body):
    arm = bpy.data.armatures.new("GrubbRig")
    ob = bpy.data.objects.new("Grubb_Rig", arm)
    coll().objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    for name, parent, tail in BONES:
        b = arm.edit_bones.new(name)
        b.head = at(name)
        b.tail = at(CHILD[name]) if tail is None else at(name, *tail)
        if parent:
            b.parent = arm.edit_bones[parent]
    for n in GEAR_BONES:
        arm.edit_bones[n].use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')
    # automatic (heat) weights; the hard limb/torso shells keep their weights apart
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    bpy.ops.object.mode_set(mode='OBJECT')
    for n in GEAR_BONES:
        arm.bones[n].use_deform = True
    return ob


def export(rig_ob, body):
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    rig_ob.select_set(True)
    body.select_set(True)
    for b in [o for o in coll().objects if o.name == "Grubb_Bits" or o.name.startswith("Grubb_Gear_")]:
        b.hide_set(False)
        b.parent = rig_ob
        if not b.modifiers.get("Armature"):
            m = b.modifiers.new("Armature", 'ARMATURE')
            m.object = rig_ob
        b.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True,
        export_skins=True, export_animations=False, export_apply=True, export_texcoords=True,
        export_normals=True, export_materials='EXPORT', export_image_format='AUTO')
    os.makedirs(os.path.dirname(GAME), exist_ok=True)
    shutil.copyfile(OUT, GAME)
    print("exported", OUT, "->", GAME, os.path.getsize(GAME) // 1024, "KB")


if __name__ == "__main__" or True:
    if STAGE == "head":
        for n in ("BodyHi_head", "Grubb_Bits"):
            old = bpy.data.objects.get(n)
            if old:
                bpy.data.objects.remove(old)
        head_shell()
        bits()
    if STAGE in ("all", "body"):
        clear()
        parts = body()
        bits()
        exec(open(ROOT + "/tools/blender/grubb_gear.py").read(), globals())
        build_gear()
        print("shells", [(p.name, len(p.data.vertices)) for p in parts])
    if STAGE in ("all", "game"):
        parts = [o for o in coll().objects if o.name.startswith("BodyHi_")]
        old = bpy.data.objects.get("Grubb_Body")
        if old:
            bpy.data.objects.remove(old)
        body_lo = game_mesh(parts)
        print("game mesh", len(body_lo.data.polygons), "faces")
        bake(body_lo, parts)
    if STAGE in ("all", "rig"):
        old = bpy.data.objects.get("Grubb_Rig")
        if old:
            bpy.data.objects.remove(old)
        body_lo = bpy.data.objects["Grubb_Body"]
        body_lo.parent = None
        body_lo.modifiers.clear()
        body_lo.vertex_groups.clear()
        r = rig(body_lo)
        export(r, body_lo)
