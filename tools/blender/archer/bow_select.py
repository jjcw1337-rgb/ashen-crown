def bow_verts(body, arm):
    """The bow Meshy fused into his right hand: everything on his right side, out of reach of the body's own
    bones (each bone a tube of its own radius), except the hand itself; the quiver on his back is kept."""
    from mathutils import Vector
    R = {"Hips": 0.3, "Spine": 0.3, "Spine01": 0.3, "Spine02": 0.32, "neck": 0.16, "Head": 0.2, "LeftShoulder": 0.2,
         "RightShoulder": 0.2, "LeftArm": 0.14, "RightArm": 0.14, "LeftForeArm": 0.11, "RightForeArm": 0.1, "LeftHand": 0.12,
         "RightHand": 0.075, "LeftUpLeg": 0.2, "RightUpLeg": 0.2, "LeftLeg": 0.15, "RightLeg": 0.15, "LeftFoot": 0.14,
         "RightFoot": 0.14, "LeftToeBase": 0.1, "RightToeBase": 0.1}
    mw = arm.matrix_world
    segs = []
    for b in arm.data.bones:
        if b.name not in R:
            continue
        h, t = mw @ b.head_local, mw @ b.tail_local
        if b.name == "RightHand":
            t = h + (h - (mw @ arm.data.bones["RightForeArm"].head_local)).normalized() * 0.1
        segs.append((h, t, R[b.name]))
    def inside(p, k_=1.0):
        for a, b, r in segs:
            ab = b - a
            k = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
            if (a + ab * k - p).length < r * k_:
                return True
        return False
    out = []
    bw = body.matrix_world
    for v in body.data.vertices:
        p = bw @ v.co
        quiver = p.y > 0.1 and p.z > 1.0
        out.append(p.x < -0.12 and 0.45 < p.z < 1.5 and not quiver and not inside(p))
    # grow along the mesh from what's clearly bow, into the thin parts that pass close to the coat (the string, the
    # lower limb's tip behind him), stopping deep inside the body and at the hand
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    P = [bw @ v.co for v in body.data.vertices]
    hand = [s_ for s_ in segs if s_[2] == 0.075][0]
    def near_hand(p):
        a, b, r = hand
        ab = b - a
        k = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        return (a + ab * k - p).length < 0.065
    # Meshy splits vertices along UV seams: vertices on the same spot count as joined
    twins = {}
    for i, p in enumerate(P):
        twins.setdefault((round(p.x, 4), round(p.y, 4), round(p.z, 4)), []).append(i)
    def neighbours(i):
        for e in bm.verts[i].link_edges:
            yield e.other_vert(bm.verts[i]).index
        p = P[i]
        for j in twins[(round(p.x, 4), round(p.y, 4), round(p.z, 4))]:
            if j != i:
                yield j
    front = [i for i, o in enumerate(out) if o]
    while front:
        nxt = []
        for i in front:
            for j in neighbours(i):
                if out[j]:
                    continue
                p = P[j]
                if p.x < 0.08 and 0.4 < p.z < 1.55 and not (p.y > 0.1 and p.z > 1.0) and not near_hand(p) and not inside(p, 0.62):
                    out[j] = True
                    nxt.append(j)
        front = nxt
    bm.free()
    # what's left of the grip in his fist: anything round the hand that Meshy tied to another bone (the legs, the
    # hips) would stretch into a long sliver when he raises the arm, so it goes too
    gi = {g.index: g.name for g in body.vertex_groups}
    a, b, r = hand
    for i, v in enumerate(body.data.vertices):
        if out[i]:
            continue
        p = P[i]
        ab = b - a
        k = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
        if (a + ab * k - p).length > 0.16:
            continue
        g = max(v.groups, key=lambda g: g.weight, default=None)
        if g is None or gi[g.group] not in ("RightHand", "RightForeArm"):
            out[i] = True
    # the rest of the grip sticking out of his fist: anything near the hand but off its axis (the fingers stay
    # within about 7 cm of it), and not the forearm
    fa = [s_ for s_ in segs if s_[2] == 0.1][0]
    def dom(i):
        g_ = max(body.data.vertices[i].groups, key=lambda g: g.weight, default=None)
        return gi[g_.group] if g_ else ""
    def in_body(p):
        for a_, b_, r_ in segs:
            if r_ in (0.075, 0.1):
                continue
            ab_ = b_ - a_
            k_ = max(0.0, min(1.0, (p - a_).dot(ab_) / max(ab_.length_squared, 1e-9)))
            if (a_ + ab_ * k_ - p).length < r_:
                return True
        return False
    n_ = 0
    for i, p in enumerate(P):
        if out[i]:
            continue
        if (p - a).length > 0.26:
            continue
        ab = b - a
        k = (p - a).dot(ab) / max(ab.length_squared, 1e-9)
        off = (a + ab * max(0.0, min(1.2, k)) - p).length
        fk = max(0.0, min(1.0, (p - fa[0]).dot(fa[1] - fa[0]) / max((fa[1] - fa[0]).length_squared, 1e-9)))
        if off > 0.07 and (fa[0] + (fa[1] - fa[0]) * fk - p).length > 0.09 and p.z < 1.25 and dom(i) == "RightHand":
            out[i] = True
            n_ += 1
    print("grip remains:", n_)
    return out
