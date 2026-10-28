"""The knight's sculpt, as signed distance fields (see sdf.py). Proportions follow the game's
skeleton (scripts/knight.gd BONE_DEF): hips 0.95, shoulders 1.50 at x=+-0.235, head joint
1.66, crown 1.89. Blender axes (face toward -y)."""
import numpy as np
from sdf import *

HC = np.array([0.0, 0.012, 1.765])          # head centre
EYE_R = 0.0122
EYES = {}


def eye_c(s):
    return EYES[s]


def ray(a, e):
    """Direction from the head centre: azimuth a (0 = straight ahead, + = toward +x), elevation e (radians)."""
    return np.array([np.sin(a) * np.cos(e), -np.cos(a) * np.cos(e), np.sin(e)])


def _eyelids(s):
    E = eye_c(s)
    def f(P):
        q = P - E
        ex, ey, ez = q[:, 0] * s, q[:, 1], q[:, 2]
        u = np.clip(ex / 0.0138, -1.2, 1.2)
        bow = np.maximum(1.0 - u * u, 0.0)
        shell = np.abs(length(q) - (EYE_R + 0.0019)) - 0.0015
        shell = np.maximum(shell, ey - 0.002)                 # front of the ball only
        up_edge = 0.0047 * bow - 0.0004 + 0.0008 * u          # outer corner a touch higher
        lo_edge = -0.0034 * bow - 0.0002 + 0.0004 * u
        upper = np.maximum(shell, up_edge - ez)
        lower = np.maximum(shell, ez - lo_edge)
        # a soft crease above the upper lid
        return np.minimum(upper, lower)
    return f


def head_skin():
    cranium = ellipsoid([0, 0.01, 1.768], [0.075, 0.1, 0.1])
    crown = ellipsoid([0, 0.02, 1.8], [0.07, 0.085, 0.085])
    face = ellipsoid([0, -0.025, 1.7], [0.058, 0.07, 0.08])
    mandible = mirror_x(lambda s: roundcone([s * 0.056, 0.002, 1.668], [s * 0.014, -0.072, 1.626], 0.012, 0.012))
    chin = ellipsoid([0, -0.074, 1.63], [0.021, 0.014, 0.018])
    neck = roundcone([0, 0.012, 1.5], [0, 0.012, 1.68], 0.06, 0.053)
    adam = ellipsoid([0, -0.044, 1.6], [0.011, 0.01, 0.014])
    base = blend(cranium, [(crown, 0.03), (face, 0.045), (mandible, 0.03), (chin, 0.022), (neck, 0.035), (adam, 0.015)], 0.03)
    H = HC
    feats = []
    # brow ridge and glabella, cheekbones (zygomatic arch), all a few mm proud of the base
    for s in (1.0, -1.0):
        b0 = anchor(base, H, ray(s * 0.14, 0.07), 0.009)
        b1 = anchor(base, H, ray(s * 0.62, 0.09), 0.009)
        feats.append((roundcone(b0, b1, 0.0125, 0.0105), 0.014))
        z0 = anchor(base, H, ray(s * 0.5, -0.14), 0.009)
        z1 = anchor(base, H, ray(s * 1.15, -0.12), 0.01)
        feats.append((roundcone(z0, z1, 0.012, 0.011), 0.016))
    feats.append((sphere(anchor(base, H, ray(0, 0.06), 0.0085), 0.0105), 0.012))
    # nose: root, bridge, tip anchored on horizontal rays down the midline
    def mid(z, depth, s=0.0, a=0.0):
        return anchor(base, [s, 0.0, z], ray(a, 0.0), depth)
    n0, n1, n2 = mid(1.762, 0.0035), mid(1.738, -0.009), mid(1.714, -0.02)
    feats.append((chain([n0, n1, n2], [0.0068, 0.0072, 0.0098]), 0.01))
    for s in (1.0, -1.0):
        feats.append((ellipsoid(mid(1.707, -0.004, s * 0.0125), [0.0072, 0.0085, 0.0066], rot(0, 0, s * 25)), 0.005))
    feats.append((roundcone(mid(1.704, -0.012), mid(1.693, -0.002), 0.0042, 0.0036), 0.004))
    # lips, philtrum, chin
    feats.append((ellipsoid(mid(1.6665, 0.0045), [0.02, 0.009, 0.0058]), 0.006))
    feats.append((ellipsoid(mid(1.653, 0.005), [0.017, 0.009, 0.0062]), 0.006))
    feats.append((ellipsoid(mid(1.682, 0.004), [0.011, 0.007, 0.011]), 0.006))
    feats.append((ellipsoid(mid(1.628, 0.008), [0.019, 0.012, 0.016]), 0.012))
    # ears on the sides of the skull
    for s in (1.0, -1.0):
        ec = anchor(base, H, ray(s * 1.62, -0.12), -0.002)
        R = rot(-12, 0, s * -18)
        feats.append((carve(ellipsoid(ec, [0.0075, 0.018, 0.028], R),
                            [ellipsoid(ec + [s * 0.004, -0.003, -0.005], [0.0045, 0.0105, 0.016], R)], 0.003), 0.006))
    skull = blend(base, feats, 0.01)
    # eyes: cornea about 2 mm under the skin line between brow and cheek
    for s in (1.0, -1.0):
        sp = surface_point(skull, [s * 0.0315, 0.0, 1.752], [0, -1, 0])
        EYES[s] = sp + np.array([0.0, EYE_R + 0.0015, 0.0])
    skull = carve(skull, [
        (ellipsoid(mid(1.6595, -0.002), [0.021, 0.01, 0.0009]), 0.0012),
        (mirror_x(lambda s: ellipsoid(mid(1.699, -0.008, s * 0.0105), [0.0035, 0.004, 0.0025])), 0.002),
        (mirror_x(lambda s: sphere(eye_c(s), EYE_R + 0.0006)), 0.0015),
        (mirror_x(lambda s: ellipsoid(eye_c(s) + [0, -0.012, 0.0], [0.017, 0.01, 0.011])), 0.006),
    ], 0.004)
    return blend(skull, [(_eyelids(1.0), 0.0018), (_eyelids(-1.0), 0.0018)], 0.002)
