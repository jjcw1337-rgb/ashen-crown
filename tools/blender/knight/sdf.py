"""Tiny signed-distance-field sculpting kit (numpy). Shapes are functions P(N,3) -> d(N).
Blender axes: x right, -y forward (the face looks toward -y), z up. Units: metres."""
import numpy as np


def length(v):
    return np.sqrt(np.einsum("...i,...i->...", v, v))


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Rotation matrix (degrees), applied as local = (P - c) @ R."""
    rx, ry, rz = np.radians([rx, ry, rz])
    X = np.array([[1, 0, 0], [0, np.cos(rx), -np.sin(rx)], [0, np.sin(rx), np.cos(rx)]])
    Y = np.array([[np.cos(ry), 0, np.sin(ry)], [0, 1, 0], [-np.sin(ry), 0, np.cos(ry)]])
    Z = np.array([[np.cos(rz), -np.sin(rz), 0], [np.sin(rz), np.cos(rz), 0], [0, 0, 1]])
    return X @ Y @ Z


def ellipsoid(c, r, R=None):
    c = np.asarray(c, float); r = np.asarray(r, float)
    def f(P):
        q = P - c
        if R is not None:
            q = q @ R
        k0 = length(q / r)
        k1 = length(q / (r * r))
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    return f


def sphere(c, r):
    c = np.asarray(c, float)
    return lambda P: length(P - c) - r


def roundcone(a, b, r1, r2):
    """Capsule from a (radius r1) to b (radius r2), exact (Inigo Quilez)."""
    a = np.asarray(a, float); b = np.asarray(b, float)
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    def f(P):
        pa = P - a
        y = pa @ ba
        z = y - l2
        w = pa * l2 - np.outer(y, ba)
        x2 = np.einsum("ij,ij->i", w, w)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0)) + y * rr) * il2 - r1
        d1 = np.sqrt(x2 + z2) * il2 - r2
        d2 = np.sqrt(x2 + y2) * il2 - r1
        return np.where(np.sign(z) * a2 * z2 > k, d1, np.where(np.sign(y) * a2 * y2 < k, d2, d3))
    return f


def chain(points, radii):
    """Smoothly joined capsules through a list of points."""
    parts = [roundcone(points[i], points[i + 1], radii[i], radii[i + 1]) for i in range(len(points) - 1)]
    return union(*parts)


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def union(*fs, k=0.0):
    def f(P):
        d = fs[0](P)
        for g in fs[1:]:
            d = smin(d, g(P), k) if k > 0 else np.minimum(d, g(P))
        return d
    return f


def blend(base, adds, k):
    """base smoothly unioned with each (shape, k_i) or shape (uses k)."""
    def f(P):
        d = base(P)
        for a in adds:
            g, kk = a if isinstance(a, tuple) else (a, k)
            d = smin(d, g(P), kk)
        return d
    return f


def carve(base, cuts, k):
    def f(P):
        d = base(P)
        for c in cuts:
            g, kk = c if isinstance(c, tuple) else (c, k)
            d = smax(d, -g(P), kk)
        return d
    return f


def mirror_x(make):
    """make(side) -> shape for side +1/-1; returns union of both."""
    return union(make(1.0), make(-1.0))


def grad(f, P, e=0.0005):
    dx = np.array([e, 0, 0]); dy = np.array([0, e, 0]); dz = np.array([0, 0, e])
    g = np.stack([f(P + dx) - f(P - dx), f(P + dy) - f(P - dy), f(P + dz) - f(P - dz)], -1)
    return g / np.maximum(length(g)[:, None], 1e-12)


def mesh(f, lo, hi, step, chunk=1_500_000):
    """Marching cubes of f over the box [lo, hi]. Returns verts (N,3), faces (M,3)."""
    from skimage.measure import marching_cubes
    lo = np.asarray(lo, float); hi = np.asarray(hi, float)
    n = np.ceil((hi - lo) / step).astype(int) + 1
    xs = lo[0] + np.arange(n[0]) * step
    ys = lo[1] + np.arange(n[1]) * step
    zs = lo[2] + np.arange(n[2]) * step
    vol = np.empty((n[0], n[1], n[2]), np.float32)
    per = max(1, chunk // (n[0] * n[1]))
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    for z0 in range(0, n[2], per):
        zz = zs[z0:z0 + per]
        P = np.stack([np.repeat(X[..., None], len(zz), 2), np.repeat(Y[..., None], len(zz), 2),
                      np.broadcast_to(zz, X.shape + (len(zz),))], -1).reshape(-1, 3)
        vol[:, :, z0:z0 + per] = f(P).reshape(n[0], n[1], len(zz))
    v, faces, _, _ = marching_cubes(vol, 0.0, spacing=(step, step, step))
    return v + lo, faces[:, ::-1]


def write_ply(path, v, faces, colors=None):
    with open(path, "wb") as fh:
        hdr = ["ply", "format binary_little_endian 1.0", f"element vertex {len(v)}",
               "property float x", "property float y", "property float z"]
        if colors is not None:
            hdr += ["property uchar red", "property uchar green", "property uchar blue"]
        hdr += [f"element face {len(faces)}", "property list uchar int vertex_indices", "end_header"]
        fh.write(("\n".join(hdr) + "\n").encode())
        if colors is None:
            fh.write(np.asarray(v, "<f4").tobytes())
        else:
            dt = np.dtype([("p", "<f4", 3), ("c", "u1", 3)])
            arr = np.empty(len(v), dt); arr["p"] = v; arr["c"] = colors
            fh.write(arr.tobytes())
        dtf = np.dtype([("n", "u1"), ("i", "<i4", 3)])
        fa = np.empty(len(faces), dtf); fa["n"] = 3; fa["i"] = faces
        fh.write(fa.tobytes())


def surface_point(f, o, d, tmax=0.3):
    """First zero crossing of f along the ray o + t d (o inside: f(o) < 0). Bisection."""
    o = np.asarray(o, float); d = np.asarray(d, float); d = d / np.linalg.norm(d)
    lo, hi = 0.0, tmax
    for _ in range(40):
        mid = 0.5 * (lo + hi)
        if f((o + d * mid)[None])[0] < 0:
            lo = mid
        else:
            hi = mid
    return o + d * lo


def anchor(f, o, d, depth):
    """Point at `depth` below the surface hit by the ray (inward along the surface normal)."""
    s = surface_point(f, o, d)
    n = grad(f, s[None])[0]
    return s - n * depth
