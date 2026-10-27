# King Grubb's gear, hard-surface: pauldrons, collar, belt and buckle, keys and purse, loincloth,
# bracers, greaves, the crown stack, the gold sacks, the Hoardkey, fingers and toes.
# Exec'd by tools/blender/grubb.py after its helpers (G, at, coll, material, ...).
# Materials are Poly Haven textures (CC0) projected in object space, baked later into atlases.

def pmat(name):
    """A Poly Haven material made ready for box projection (no UVs needed)."""
    m = bpy.data.materials.get(name)
    if m is None:
        raise RuntimeError("missing Poly Haven material " + name + " (import it first)")
    m.use_fake_user = True
    nt = m.node_tree
    tc = next((n for n in nt.nodes if n.type == 'TEX_COORD'), None)
    mp = next((n for n in nt.nodes if n.type == 'MAPPING'), None)
    if tc is not None and mp is not None:
        for l in list(mp.inputs['Vector'].links):
            nt.links.remove(l)
        nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    for n in nt.nodes:
        if n.type == 'TEX_IMAGE':
            n.projection = 'BOX'
            n.projection_blend = 0.3
    # displacement nodes would make the bake (and the export) noisy: keep it to the normal map
    out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
    for l in list(out.inputs['Displacement'].links):
        nt.links.remove(l)
    return m


def tinted(src, name, tint, metal=None, rough_mul=1.0, scale=None):
    """A copy of a Poly Haven material with its colour multiplied by tint (gold from iron)."""
    old = bpy.data.materials.get(name)
    if old is not None:
        bpy.data.materials.remove(old)
    m = None
    if m is None:
        m = pmat(src).copy()
        m.name = name
        nt = m.node_tree
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        col_link = b.inputs['Base Color'].links[0] if b.inputs['Base Color'].links else None
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.blend_type = 'MULTIPLY'
        mix.inputs['Factor'].default_value = 1.0
        mix.inputs[7].default_value = (*tint, 1.0)
        if col_link is not None:
            nt.links.new(col_link.from_socket, mix.inputs[6])
        nt.links.new(mix.outputs[2], b.inputs['Base Color'])
        if metal is not None:
            for l in list(b.inputs['Metallic'].links):
                nt.links.remove(l)
            b.inputs['Metallic'].default_value = metal
        if rough_mul != 1.0 and b.inputs['Roughness'].links:
            src_sock = b.inputs['Roughness'].links[0].from_socket
            mul = nt.nodes.new('ShaderNodeMath')
            mul.operation = 'MULTIPLY'
            mul.inputs[1].default_value = rough_mul
            nt.links.new(src_sock, mul.inputs[0])
            nt.links.new(mul.outputs[0], b.inputs['Roughness'])
        m.use_fake_user = True
    if scale is not None:
        mp = next((n for n in m.node_tree.nodes if n.type == 'MAPPING'), None)
        if mp is not None:
            mp.inputs['Scale'].default_value = (scale, scale, scale)
    return m


def gear_mats():
    return {
        "iron": tinted("metal_plate_02", "GrubbIron", (0.55, 0.52, 0.5), metal=0.85, scale=4.0),
        "gold": tinted("metal_plate_02", "GrubbGoldWorn", (1.6, 1.05, 0.38), metal=1.0, rough_mul=0.55, scale=5.0),
        "leather": tinted("fabric_leather_02", "GrubbLeather", (0.7, 0.55, 0.45), scale=6.0),
        "burlap": tinted("hessian_380", "GrubbBurlap", (0.42, 0.33, 0.22), scale=10.0),
        "royal": tinted("quatrefoil_jacquard_fabric", "GrubbRoyal", (0.5, 0.18, 0.6), scale=9.0),
        "gem_r": material("GrubbGemRed", (0.6, 0.02, 0.02), rough=0.08, emit=(1.0, 0.08, 0.05), strength=1.5),
        "gem_b": material("GrubbGemBlue", (0.05, 0.15, 0.7), rough=0.08, emit=(0.2, 0.4, 1.0), strength=1.2),
        "gem_g": material("GrubbGemGreen", (0.05, 0.5, 0.1), rough=0.08, emit=(0.2, 1.0, 0.3), strength=1.2),
        "claw": material("GrubbClaw", (0.1, 0.08, 0.06), rough=0.35),
        "skin": bpy.data.materials.get("GrubbSkinHi") or skin_material(),
    }


GEAR = []   # [object, bone]


def _finish(ob, mat, bone, bevel=0.0, solid=0.0, smooth=True):
    """Give a piece its material, thickness, bevelled edges and its bone."""
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    if solid:
        s = ob.modifiers.new("solid", 'SOLIDIFY')
        s.thickness = solid
        s.offset = 0.0
    if bevel:
        b = ob.modifiers.new("bevel", 'BEVEL')
        b.width = bevel
        b.segments = 2
        b.limit_method = 'ANGLE'
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
        w = ob.modifiers.new("wn", 'WEIGHTED_NORMAL') if bevel else None
    GEAR.append((ob, bone))
    return ob


def _new(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll().objects.link(ob)
    return ob


def place(ob, p, rot=(0, 0, 0), scl=(1, 1, 1)):
    ob.location = p
    ob.rotation_euler = rot
    ob.scale = scl
    return ob


def basis_from(z_axis, x_hint):
    """A rotation whose local Z points along z_axis (Blender vectors)."""
    z = Vector(z_axis).normalized()
    x = Vector(x_hint)
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed().to_euler()


def ring(name, r_out, r_in, h, segs=48, arc=1.0, flare=0.0):
    """A band (crowns, cuffs, belts, pauldron lames): local Z up, arc < 1 leaves a gap at -Y."""
    bm = bmesh.new()
    rows = []
    n = segs if arc >= 1.0 else segs + 1
    for zi, (z, f) in enumerate(((0.0, 0.0), (h, flare))):
        for ri, r in enumerate((r_out + f, r_in + f)):
            row = []
            for i in range(n):
                a = (i / segs) * 2 * math.pi * arc - math.pi * arc + math.pi / 2
                row.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
            rows.append(row)
    o0, i0, o1, i1 = rows
    def quads(a, b, flip=False):
        for i in range(n - 1 if arc < 1.0 else n):
            j = (i + 1) % n
            f = (a[i], a[j], b[j], b[i])
            bm.faces.new(f[::-1] if flip else f)
    quads(o0, o1, True)
    quads(i0, i1)
    quads(o1, i1, True)
    quads(o0, i0)
    if arc < 1.0:
        for k in (0, n - 1):
            bm.faces.new((o0[k], i0[k], i1[k], o1[k]) if k == 0 else (o0[k], o1[k], i1[k], i0[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new(name, bm)


def dome(name, r, cap_deg, segs=40, rings=12):
    """A spherical cap around local +Z (pauldron domes, helm tops)."""
    bm = bmesh.new()
    rows = []
    for j in range(rings + 1):
        th = math.radians(cap_deg) * j / rings
        row = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            row.append(bm.verts.new((math.sin(th) * math.cos(a) * r, math.sin(th) * math.sin(a) * r, math.cos(th) * r)))
        rows.append(row)
    for j in range(rings):
        for i in range(segs):
            k = (i + 1) % segs
            if j == 0:
                continue
            bm.faces.new((rows[j][i], rows[j][k], rows[j + 1][k], rows[j + 1][i]))
    top = bm.verts.new((0, 0, r))
    for i in range(segs):
        bm.faces.new((top, rows[1][i], rows[1][(i + 1) % segs]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new(name, bm)


def cone(name, r, h, segs=12):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=0.0, depth=h)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, h / 2))
    return _new(name, bm)


def sphere(name, r, segs=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(6, segs // 2), radius=r)
    return _new(name, bm)


def box(name, x, y, z):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(x, y, z), verts=bm.verts)
    return _new(name, bm)


def torus(name, R, r, segs=24, rsegs=8):
    bm = bmesh.new()
    rows = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        row = []
        for j in range(rsegs):
            b = 2 * math.pi * j / rsegs
            row.append(bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b))))
        rows.append(row)
    for i in range(segs):
        for j in range(rsegs):
            bm.faces.new((rows[i][j], rows[(i + 1) % segs][j], rows[(i + 1) % segs][(j + 1) % rsegs], rows[i][(j + 1) % rsegs]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _new(name, bm)


def V(x, y, z):
    """A direction in Godot axes -> Blender."""
    return G(x, y, z) - G(0, 0, 0)


def rivets(pts, r, mat, bone):
    for p in pts:
        _finish(place(sphere("rivet", r, 10), p, scl=(1, 1, 0.6)), mat, bone)


def chain(pts, link, mat, bone):
    """Torus links along a polyline (Blender points), alternating 90 degrees."""
    out = []
    path = []
    for i in range(len(pts) - 1):
        L = (pts[i + 1] - pts[i]).length
        n = max(1, int(L / (link * 1.6)))
        for k in range(n):
            path.append((pts[i].lerp(pts[i + 1], k / n), (pts[i + 1] - pts[i]).normalized()))
    for k, (p, d) in enumerate(path):
        t = torus("link", link * 0.55, link * 0.18, 12, 6)
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = d.cross(Vector((1, 0, 0)))
        if k % 2:
            side = d.cross(side)
        place(t, p, basis_from(side, d), (1.5, 1.0, 1.0))
        out.append(_finish(t, mat, bone))
    return out


def gear():
    global GEAR
    GEAR = []
    M = gear_mats()
    # ------------------------------------------------ pauldrons: a dome and three lames, trimmed in gold
    for s, sn in ((1, "r"), (-1, "l")):
        sh = J["sh_" + sn]
        big = 1.18 if s > 0 else 1.0
        up = V(s * 0.55, 1.0, 0.0)
        c = at("sh_" + sn, s * 0.035, 0.035, 0.0)
        d = place(dome("pauldron", 0.16 * big, 62), c, basis_from(up, V(0, 0, 1)))
        _finish(d, M["iron"], "sh_" + sn, bevel=0.004, solid=0.012)
        tr = place(torus("trim", 0.16 * big * math.sin(math.radians(62)) + 0.002, 0.011 * big, 40, 8),
                   c + up.normalized() * 0.16 * big * math.cos(math.radians(62)), basis_from(up, V(0, 0, 1)))
        _finish(tr, M["gold"], "sh_" + sn)
        for k in range(3):
            lr = 0.125 * big - k * 0.01
            lm = place(ring("lame", lr, lr - 0.01, 0.05, 40, arc=0.55, flare=0.01),
                       at("sh_" + sn, s * 0.01, -0.06 - k * 0.045, 0.0), basis_from(V(0, 1, 0), V(-s, 0, 0)))
            lm.rotation_euler.rotate_axis('Z', math.radians(-90 * s))
            _finish(lm, M["iron"] if k % 2 == 0 else M["gold"], "sh_" + sn, bevel=0.003)
        # rivets round the dome's rim, spikes on the big one
        for k in range(9):
            a = 2 * math.pi * k / 9
            loc = Vector((math.cos(a), math.sin(a), 0)) * 0.16 * big * math.sin(math.radians(58))
            loc.z = 0.16 * big * math.cos(math.radians(58))
            p = c + Matrix.Rotation(0, 3, 'Z') @ (basis_from(up, V(0, 0, 1)).to_matrix() @ loc)
            rivets([p], 0.009, M["gold"], "sh_" + sn)
        if s > 0:
            for k, (ax, ay) in enumerate(((0.0, 0.0), (-0.35, 0.25), (0.35, 0.25))):
                dirv = (up.normalized() + V(0, ax * 0.0, ay) + V(s * 0.0, 0.0, ax)).normalized()
                sp = place(cone("spike", 0.026, 0.16 - k * 0.03, 10), c + dirv * 0.17 * big, basis_from(dirv, V(0, 0, 1)))
                _finish(sp, M["iron"], "sh_" + sn)
    # ------------------------------------------------ collar: thick leather ring, gold studs, iron spikes
    nc = at("torso", 0, 0.5, -0.03)
    col = place(ring("collar", 0.2, 0.15, 0.07, 48, flare=0.03), nc, basis_from(V(0, 1, -0.25), V(1, 0, 0)))
    _finish(col, M["leather"], "torso", bevel=0.006)
    for k in range(10):
        a = 2 * math.pi * k / 10
        dirv = (V(math.cos(a), 0.15, math.sin(a))).normalized()
        p = nc + V(math.cos(a) * 0.21, 0.04, math.sin(a) * 0.21)
        if k % 2:
            _finish(place(cone("collar_spike", 0.018, 0.08, 8), p, basis_from(dirv, V(0, 1, 0))), M["iron"], "torso")
        else:
            rivets([p], 0.014, M["gold"], "torso")
    # ------------------------------------------------ belt: wide leather band under the belly, gold buckle
    bc = at("hips", 0, -0.01, -0.02)
    belt = place(ring("belt", 0.285, 0.265, 0.1, 64), bc, basis_from(V(0, 1, 0.1), V(1, 0, 0)), (1.0, 0.92, 1.0))
    _finish(belt, M["leather"], "hips", bevel=0.005)
    bk = at("hips", 0, 0.035, -0.29)
    plate = place(box("buckle", 0.17, 0.035, 0.14), bk, basis_from(V(0, 0.12, -1), V(1, 0, 0)))
    _finish(plate, M["gold"], "hips", bevel=0.008)
    disc = place(ring("buckle_ring", 0.06, 0.045, 0.02, 32), bk + V(0, 0, -0.022), basis_from(V(0, 0.12, -1), V(1, 0, 0)))
    _finish(disc, M["gold"], "hips", bevel=0.003)
    _finish(place(sphere("buckle_gem", 0.032, 16), bk + V(0, 0, -0.03), scl=(1, 0.6, 1)), M["gem_r"], "hips")
    for k in range(14):
        a = 2 * math.pi * k / 14
        if abs(math.sin(a)) > 0.92 and math.sin(a) < 0:
            continue
        rivets([bc + V(math.cos(a) * 0.29, 0.05, math.sin(a) * 0.27)], 0.011, M["gold"], "hips")
    # keys on a chain at the right hip, a fat coin purse at the left
    hip = at("hips", 0.27, 0.0, -0.1)
    chain([hip, hip + V(0.01, -0.08, -0.01), hip + V(0.0, -0.15, 0.01)], 0.022, M["iron"], "hips")
    for k in range(3):
        kp = hip + V(-0.02 + k * 0.025, -0.2, 0.01)
        _finish(place(torus("keyring", 0.018, 0.005, 16, 6), kp, (math.radians(90), 0, 0)), M["gold"], "hips")
        _finish(place(box("keyshaft", 0.008, 0.008, 0.08), kp + V(0, -0.055, 0)), M["gold"], "hips", bevel=0.002)
        _finish(place(box("keybit", 0.022, 0.008, 0.016), kp + V(0.012, -0.085, 0)), M["gold"], "hips", bevel=0.002)
    purse = place(sphere("purse", 0.07, 20), at("hips", -0.28, -0.1, -0.1), scl=(1.0, 1.0, 1.25))
    _finish(purse, M["leather"], "hips")
    _finish(place(torus("purse_tie", 0.035, 0.009, 16, 6), at("hips", -0.28, -0.02, -0.1), (0, 0, 0)), M["gold"], "hips")
    # ------------------------------------------------ loincloth: royal brocade panels with gold hems
    for front, z, rot in ((True, -0.3, 0.0), (False, 0.24, math.pi)):
        pnl = cloth_panel("loin", 0.3 if front else 0.36, 0.4, 9 if front else 13)
        place(pnl, at("hips", 0, 0.06, z), (math.radians(-5 if front else 5), 0, rot))
        _finish(pnl, M["royal"], "hips", solid=0.008)
        hem = place(box("hem", 0.3 if front else 0.36, 0.01, 0.03), at("hips", 0, -0.33, z + (-0.03 if front else 0.03)), (0, 0, rot))
        _finish(hem, M["gold"], "hips", bevel=0.003)
    # ------------------------------------------------ bracers and greaves
    for s, sn in ((1, "r"), (-1, "l")):
        br = place(ring("bracer", 0.075, 0.062, 0.15, 32, flare=0.01), at("el_" + sn, 0, -0.3, 0.0), basis_from(V(0, 1, 0), V(1, 0, 0)))
        _finish(br, M["leather"], "el_" + sn, bevel=0.004)
        for k in range(2):
            st = place(ring("bracer_strip", 0.079, 0.07, 0.018, 32), at("el_" + sn, 0, -0.285 + k * 0.1, 0.0), basis_from(V(0, 1, 0), V(1, 0, 0)))
            _finish(st, M["iron"], "el_" + sn, bevel=0.002)
        for k in range(4):
            a = math.pi / 2 + (k - 1.5) * 0.45
            sp = place(cone("bracer_spike", 0.013, 0.05, 8), at("el_" + sn, math.cos(a) * 0.075 * s * 0 + 0.0, -0.23, 0.0) + V(s * 0.075 * math.sin(a - math.pi / 2) * 0, 0, 0), basis_from(V(s, 0.2, 0), V(0, 1, 0)))
            sp.location = at("el_" + sn, s * 0.074, -0.27 + k * 0.03, -0.01)
            _finish(sp, M["iron"], "el_" + sn)
        gr = place(ring("greave", 0.07, 0.058, 0.17, 32, arc=0.55, flare=0.008), at("knee_" + sn, -s * 0.03, -0.24, 0.0), basis_from(V(0, 1, 0), V(1, 0, 0)))
        gr.rotation_euler.rotate_axis('Z', math.radians(180))
        _finish(gr, M["iron"], "knee_" + sn, bevel=0.003)
        _finish(place(dome("kneecop", 0.055, 70), at("knee_" + sn, 0, 0.0, -0.06), basis_from(V(0, 0.2, -1), V(1, 0, 0))), M["iron"], "knee_" + sn, bevel=0.003, solid=0.008)
    # ------------------------------------------------ fingers, thumbs, claws; toes
    for s, sn in ((1, "r"), (-1, "l")):
        hs = 1.35
        for i in range(4):
            x = (-0.036 + i * 0.024) * hs
            L = (1.0 - abs(i - 1.5) * 0.12) * hs
            pts = [at("hand_" + sn, x, -0.09 * hs, -0.005), at("hand_" + sn, x, -0.135 * L, -0.03), at("hand_" + sn, x, -0.168 * L, -0.012), at("hand_" + sn, x, -0.18 * L, 0.02)]
            f = tube_mesh("finger", pts, [0.016 * hs, 0.015 * hs, 0.012 * hs, 0.009 * hs], sides=10, steps=4)
            _finish(f, M["skin"], "hand_" + sn)
            _finish(place(cone("claw", 0.009 * hs, 0.035 * hs, 8), pts[3] + V(0, 0, 0.004), basis_from(V(0, -0.3, 1), V(1, 0, 0))), M["claw"], "hand_" + sn)
            if i in (1, 3):
                _finish(place(torus("ring", 0.017 * hs, 0.0045 * hs, 16, 6), pts[1], basis_from(V(0, 1, -0.5), V(1, 0, 0))), M["gold"], "hand_" + sn)
        tp = [at("hand_" + sn, -s * 0.045, -0.04, -0.02), at("hand_" + sn, -s * 0.068, -0.09, -0.055), at("hand_" + sn, -s * 0.064, -0.13, -0.06)]
        _finish(tube_mesh("thumb", tp, [0.02, 0.017, 0.012], sides=10, steps=4), M["skin"], "hand_" + sn)
        for i in range(3):
            x = -s * 0.045 + (i - 1) * 0.04
            pts = [at("knee_" + sn, x, -0.3, -0.15), at("knee_" + sn, x + (i - 1) * 0.01, -0.305, -0.21), at("knee_" + sn, x + (i - 1) * 0.015, -0.315, -0.25)]
            _finish(tube_mesh("toe", pts, [0.022, 0.018, 0.012], sides=10, steps=4), M["skin"], "knee_" + sn)
            _finish(place(cone("toeclaw", 0.011, 0.04, 8), pts[2], basis_from(V(0, -0.2, -1), V(1, 0, 0))), M["claw"], "knee_" + sn)
    # ------------------------------------------------ the crown stack
    crown_specs = [(0.165, 0.065, 0.0, (-6, 0, 7), 6, 0.1, "gem_r"), (0.125, 0.05, 0.075, (9, 35, -13), 5, 0.08, "gem_b"), (0.085, 0.04, 0.145, (16, 70, 24), 4, 0.08, "gem_g")]
    base = J["crowns"]
    off = 0.0
    for i, (r, h, y, rot, n, sh, gem) in enumerate(crown_specs):
        rb = Euler((math.radians(rot[0]), math.radians(rot[2]), math.radians(rot[1])))
        cc = G(base[0] + off, base[1] + y, base[2])
        band = place(ring("crown", r + 0.012, r - 0.004, h, 48, flare=0.012), cc, rb)
        _finish(band, M["gold"], "crowns", bevel=0.003)
        for k in range(n):
            a = 2 * math.pi * k / n
            local = Vector((math.cos(a) * (r + 0.012), math.sin(a) * (r + 0.012), h))
            p = cc + rb.to_matrix() @ local
            pt = place(cone("point", 0.03 * r / 0.165 + 0.01, sh, 4), p, rb)
            _finish(pt, M["gold"], "crowns", bevel=0.002)
            _finish(place(sphere("pearl", 0.012, 10), p + rb.to_matrix() @ Vector((0, 0, sh))), M["gold"], "crowns")
            g_local = Vector((math.cos(a + math.pi / n) * (r + 0.016), math.sin(a + math.pi / n) * (r + 0.016), h * 0.5))
            _finish(place(sphere("gem", 0.017, 12), cc + rb.to_matrix() @ g_local, scl=(1, 1, 1)), M[gem], "crowns")
        if i == 2:
            _finish(place(sphere("topgem", 0.034, 16), cc + rb.to_matrix() @ Vector((0, 0, h + 0.04))), M[gem], "crowns")
        off += 0.012 if i % 2 == 0 else -0.012
    # ------------------------------------------------ the gold sacks, rope ties and spilling coins
    sizes = [1.15, 0.85, 0.78]
    for i in range(3):
        sz = sizes[i]
        c = G(*J["sack%d" % i])
        sk = place(sphere("sack", 0.22 * sz, 28), c, scl=(1.05, 0.9, 1.15))
        tex = bpy.data.textures.get("sack_lumps") or bpy.data.textures.new("sack_lumps", 'VORONOI')
        tex.noise_scale = 0.06
        d = sk.modifiers.new("lumps", 'DISPLACE')
        d.texture = tex
        d.texture_coords = 'OBJECT'
        d.strength = 0.02 * sz
        _finish(sk, M["burlap"], "sack%d" % i)
        neck = place(cone("sack_neck", 0.09 * sz, 0.12 * sz, 16), c + Vector((0, 0, 0.2 * sz)), (math.pi, 0, 0))
        neck.location = c + Vector((0, 0, 0.3 * sz))
        _finish(neck, M["burlap"], "sack%d" % i)
        _finish(place(torus("rope", 0.06 * sz, 0.012 * sz, 20, 6), c + Vector((0, 0, 0.21 * sz))), M["leather"], "sack%d" % i)
        for k in range(6):
            a = k * 2.4
            cp = c + Vector((math.cos(a) * 0.04 * sz, math.sin(a) * 0.04 * sz, 0.31 * sz + (k % 3) * 0.012))
            coin = place(ring("coin", 0.03, 0.0, 0.006, 16), cp, (math.radians(30 + k * 25), math.radians(k * 40), 0))
            _finish(coin, M["gold"], "sack%d" % i, bevel=0.001)
    # ------------------------------------------------ the Hoardkey, held in the right hand
    hand = Vector(J["hand_r"])
    grip = G(hand.x, hand.y - 0.08, hand.z - 0.01)
    kd = V(0, -0.469, -0.883).normalized()
    ks = 1.3
    rot = basis_from(kd, V(1, 0, 0))
    def kp(t):
        return grip + kd * t * ks
    _finish(place(cone("kgrip", 0.04, 0.001, 12), kp(0.0), rot), M["leather"], "hand_r")
    shaft = tube_mesh("kshaft", [kp(-0.12), kp(1.02)], [0.045 * ks, 0.04 * ks], sides=16, steps=2)
    _finish(shaft, M["iron"], "hand_r", bevel=0.0)
    for t in (-0.1, 0.18, 0.55, 0.98):
        _finish(place(torus("kcollar", 0.05 * ks, 0.013 * ks, 24, 8), kp(t), rot), M["gold"], "hand_r")
    bow = place(torus("kbow", 0.1 * ks, 0.024 * ks, 32, 10), kp(-0.24), basis_from(V(1, 0, 0), kd))
    _finish(bow, M["gold"], "hand_r")
    for k in range(3):
        a = 2 * math.pi * k / 3 + math.pi / 2
        inner = kp(-0.24) + (Vector((0, 0, 1)).cross(kd).normalized() * math.cos(a) + kd * math.sin(a)) * 0.035 * ks
        _finish(place(torus("kfil", 0.03 * ks, 0.008 * ks, 20, 6), inner, basis_from(V(1, 0, 0), kd)), M["gold"], "hand_r")
    _finish(place(sphere("kgem", 0.035 * ks, 16), kp(-0.24)), M["gem_r"], "hand_r")
    side = kd.cross(V(1, 0, 0)).normalized()
    for (t, w, h) in ((0.9, 0.24, 0.07), (1.0, 0.18, 0.06)):
        b = place(box("kbit", 0.07 * ks, h * ks, w * ks), kp(t) + side * w * 0.5 * ks, rot)
        _finish(b, M["iron"], "hand_r", bevel=0.006)
    b = place(box("kward", 0.075 * ks, 0.2 * ks, 0.06 * ks), kp(0.95) + side * 0.21 * ks, rot)
    _finish(b, M["gold"], "hand_r", bevel=0.006)
    _finish(place(cone("ktip", 0.05 * ks, 0.1 * ks, 12), kp(1.05), rot), M["gold"], "hand_r")
    for k in range(5):
        np_ = kp(0.86 + k * 0.035) + side * 0.25 * ks
        _finish(place(cone("knail", 0.013 * ks, 0.08 * ks, 6), np_, basis_from(side, kd)), M["iron"], "hand_r")
    return GEAR


def cloth_panel(name, w, h, folds):
    """A hanging cloth panel with folds and a ragged hem, hanging down from its top edge."""
    bm = bmesh.new()
    cols, rows = 16, 12
    grid = []
    rng = __import__("random").Random(len(name) * 7 + folds)
    for j in range(rows + 1):
        v = j / rows
        row = []
        for i in range(cols + 1):
            u = i / cols
            x = (u - 0.5) * w * (1 + v * 0.25)
            z = -v * h * (0.85 + 0.15 * (0.5 + 0.5 * math.sin(i * 1.3 + folds)) if j == rows else 1.0)
            y = -math.sin(u * folds * math.pi) * 0.02 * (0.3 + v) - v * v * 0.03
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(rows):
        for i in range(cols):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    return _new(name, bm)


def finish_gear():
    """Apply each piece's modifiers and transforms, give it its bone, join into Grubb_Gear
    (split by material later when baking)."""
    objs = []
    for ob, bone in GEAR:
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        for m in list(ob.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=m.name)
            except RuntimeError:
                ob.modifiers.remove(m)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        vg = ob.vertex_groups.new(name=bone)
        vg.add(range(len(ob.data.vertices)), 1.0, 'REPLACE')
        objs.append(ob)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    g = bpy.context.view_layer.objects.active
    g.name = "Grubb_Gear"
    return g


# ---------------------------------------------------------------- weathering and baking the gear
def weather(m, edge=1.5, grime=(0.18, 0.12, 0.08)):
    """Grime in the crevices (AO) and bright worn edges (pointiness) on a gear material."""
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    if not b.inputs['Base Color'].links or m.get("weathered"):
        return
    src = b.inputs['Base Color'].links[0].from_socket
    ao = nt.nodes.new('ShaderNodeAmbientOcclusion')
    ao.inputs['Distance'].default_value = 0.05
    nt.links.new(src, ao.inputs['Color'])
    dirt = nt.nodes.new('ShaderNodeMix')
    dirt.data_type = 'RGBA'
    dirt.inputs[7].default_value = (*grime, 1.0)
    inv = nt.nodes.new('ShaderNodeMath')
    inv.operation = 'POWER'
    inv.inputs[1].default_value = 2.0
    nt.links.new(ao.outputs['AO'], inv.inputs[0])
    one = nt.nodes.new('ShaderNodeMath')
    one.operation = 'SUBTRACT'
    one.inputs[0].default_value = 1.0
    nt.links.new(inv.outputs[0], one.inputs[1])
    nt.links.new(one.outputs[0], dirt.inputs['Factor'])
    nt.links.new(src, dirt.inputs[6])
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    wear_r = nt.nodes.new('ShaderNodeMapRange')
    wear_r.inputs['From Min'].default_value = 0.52
    wear_r.inputs['From Max'].default_value = 0.6
    nt.links.new(geo.outputs['Pointiness'], wear_r.inputs['Value'])
    # worn edges brighten the material itself (polished gold, bare iron), not toward grey
    bright = nt.nodes.new('ShaderNodeMix')
    bright.data_type = 'RGBA'
    bright.blend_type = 'MULTIPLY'
    bright.inputs['Factor'].default_value = 1.0
    nt.links.new(src, bright.inputs[6])
    bright.inputs[7].default_value = (edge, edge, edge, 1)
    wear = nt.nodes.new('ShaderNodeMix')
    wear.data_type = 'RGBA'
    nt.links.new(wear_r.outputs['Result'], wear.inputs['Factor'])
    nt.links.new(dirt.outputs[2], wear.inputs[6])
    nt.links.new(bright.outputs[2], wear.inputs[7])
    nt.links.new(wear.outputs[2], b.inputs['Base Color'])
    m["weathered"] = True


GEAR_RES = 1024
METAL = ("GrubbIron", "GrubbGoldWorn")
PLAIN = ("GrubbGemRed", "GrubbGemBlue", "GrubbGemGreen", "GrubbClaw")


def split_gear(g):
    """Split the joined gear by kind: metal and soft get baked atlases, gems and claws stay plain."""
    groups = {"metal": [], "soft": [], "plain": []}
    for i, slot in enumerate(g.material_slots):
        n = slot.material.name if slot.material else ""
        groups["metal" if n in METAL else ("plain" if n in PLAIN else "soft")].append(i)
    out = {}
    for kind, idxs in groups.items():
        if not idxs:
            continue
        ob = g.copy()
        ob.data = g.data.copy()
        ob.name = "Grubb_Gear_" + kind
        coll().objects.link(ob)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in idxs], context='FACES')
        bm.to_mesh(ob.data)
        bm.free()
        out[kind] = ob
    bpy.data.objects.remove(g)
    return out


def bake_atlas(ob, kind, metallic):
    sc = bpy.context.scene
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006)
    bpy.ops.object.mode_set(mode='OBJECT')
    imgs = {}
    for pas in ("color", "rough", "normal"):
        nm = "gear_%s_%s" % (kind, pas)
        old = bpy.data.images.get(nm)
        if old:
            bpy.data.images.remove(old)
        img = bpy.data.images.new(nm, GEAR_RES, GEAR_RES, alpha=False)
        if pas != "color":
            img.colorspace_settings.name = 'Non-Color'
        imgs[pas] = img
    mats = [s.material for s in ob.material_slots if s.material]
    for m in mats:
        weather(m)
    sc.render.bake.use_selected_to_active = False
    sc.render.bake.margin = 6
    for pas, typ in (("color", 'EMIT'), ("rough", 'ROUGHNESS'), ("normal", 'NORMAL')):
        # colour goes out through a temporary emission shader: a metal's diffuse colour bakes black
        swaps = []
        if typ == 'EMIT':
            for m in mats:
                nt = m.node_tree
                b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
                out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
                old = out.inputs['Surface'].links[0].from_socket if out.inputs['Surface'].links else None
                em = nt.nodes.new('ShaderNodeEmission')
                if b.inputs['Base Color'].links:
                    nt.links.new(b.inputs['Base Color'].links[0].from_socket, em.inputs['Color'])
                else:
                    em.inputs['Color'].default_value = b.inputs['Base Color'].default_value
                nt.links.new(em.outputs[0], out.inputs['Surface'])
                swaps.append((m, em, old, out))
        for m in mats:
            nt = m.node_tree
            node = nt.nodes.get("bake_target") or nt.nodes.new('ShaderNodeTexImage')
            node.name = "bake_target"
            node.image = imgs[pas]
            for n in nt.nodes:
                n.select = False
            node.select = True
            nt.nodes.active = node
        bpy.ops.object.bake(type=typ)
        for m, em, old, out in swaps:
            if old is not None:
                m.node_tree.links.new(old, out.inputs['Surface'])
            m.node_tree.nodes.remove(em)
        ext = "jpg" if pas == "color" else "png"
        imgs[pas].filepath_raw = WORKSPACE + "/exports/gear_%s_%s.%s" % (kind, pas, ext)
        imgs[pas].file_format = 'JPEG' if pas == "color" else 'PNG'
        imgs[pas].save()
    for m in mats:
        n = m.node_tree.nodes.get("bake_target")
        if n:
            m.node_tree.nodes.remove(n)
    # the export material: the three atlases on one Principled BSDF
    em = bpy.data.materials.get("Gear_" + kind) or bpy.data.materials.new("Gear_" + kind)
    em.use_nodes = True
    nt = em.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    b = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(b.outputs[0], out.inputs[0])
    tcol = nt.nodes.new('ShaderNodeTexImage'); tcol.image = imgs["color"]
    trou = nt.nodes.new('ShaderNodeTexImage'); trou.image = imgs["rough"]
    tnor = nt.nodes.new('ShaderNodeTexImage'); tnor.image = imgs["normal"]
    nm = nt.nodes.new('ShaderNodeNormalMap')
    nt.links.new(tcol.outputs[0], b.inputs['Base Color'])
    nt.links.new(trou.outputs[0], b.inputs['Roughness'])
    nt.links.new(tnor.outputs[0], nm.inputs['Color'])
    nt.links.new(nm.outputs[0], b.inputs['Normal'])
    b.inputs['Metallic'].default_value = metallic
    ob.data.materials.clear()
    ob.data.materials.append(em)
    return ob


def build_gear():
    """Model, weather, bake and return the gear objects ready to rig and export."""
    for o in list(coll().objects):
        if o.name.startswith("Grubb_Gear"):
            bpy.data.objects.remove(o)
    gear()
    g = finish_gear()
    parts = split_gear(g)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 16
    if "metal" in parts:
        bake_atlas(parts["metal"], "metal", 1.0)
    if "soft" in parts:
        bake_atlas(parts["soft"], "soft", 0.0)
    return list(parts.values())
