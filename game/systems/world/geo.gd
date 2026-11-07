class_name Geo
extends RefCounted
## Procedural geometry helpers: cached primitives, extrusions and lathes.

static var _cache := {}

static func _cached(key: String, maker: Callable) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var m: Mesh = maker.call()
	_cache[key] = m
	return m

static func box(x: float, y: float, z: float) -> Mesh:
	return _cached("box%.3f_%.3f_%.3f" % [x, y, z], func():
		var b := BoxMesh.new()
		b.size = Vector3(x, y, z)
		return b)

static func cyl(top: float, bottom: float, h: float, seg: int = 12) -> Mesh:
	return _cached("cyl%.3f_%.3f_%.3f_%d" % [top, bottom, h, seg], func():
		var c := CylinderMesh.new()
		c.top_radius = top
		c.bottom_radius = bottom
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		return c)

static func sph(r: float, seg: int = 16, hfrac: float = 1.0) -> Mesh:
	return _cached("sph%.3f_%d_%.2f" % [r, seg, hfrac], func():
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = seg
		s.rings = max(4, seg / 2)
		if hfrac < 1.0:
			s.is_hemisphere = true
			s.height = r
		return s)

static func cap(r: float, h: float, seg: int = 12) -> Mesh:
	return _cached("cap%.3f_%.3f_%d" % [r, h, seg], func():
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = max(h, r * 2.0 + 0.001)
		c.radial_segments = seg
		c.rings = 4
		return c)

static func prism(x: float, y: float, z: float, ltr: float = 0.5) -> Mesh:
	return _cached("pri%.3f_%.3f_%.3f_%.2f" % [x, y, z, ltr], func():
		var p := PrismMesh.new()
		p.size = Vector3(x, y, z)
		p.left_to_right = ltr
		return p)

static func torus(inner: float, outer: float, seg: int = 24, rings: int = 10) -> Mesh:
	return _cached("tor%.3f_%.3f_%d_%d" % [inner, outer, seg, rings], func():
		var t := TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = seg
		t.ring_segments = rings
		return t)

static func cone(r: float, h: float, seg: int = 10) -> Mesh:
	return cyl(0.0, r, h, seg)

static func quad(w: float, h: float) -> Mesh:
	return _cached("quad%.3f_%.3f" % [w, h], func():
		var q := QuadMesh.new()
		q.size = Vector2(w, h)
		return q)

## Adds a triangle making sure its winding faces along the supplied normal.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var face := (b - a).cross(c - a)
	var navg := na + nb + nc
	# Godot treats clockwise triangles as front faces.
	if face.dot(navg) > 0.0:
		var t := b; b = c; c = t
		var tn := nb; nb = nc; nc = tn
	st.set_normal(na); st.add_vertex(a)
	st.set_normal(nb); st.add_vertex(b)
	st.set_normal(nc); st.add_vertex(c)

static func _signed_area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		var j := (i + 1) % p.size()
		a += p[i].x * p[j].y - p[j].x * p[i].y
	return a * 0.5

## Extrudes a 2D outline (XY plane) along Z, centred on z = 0.
static func extrude(pts: PackedVector2Array, depth: float, key: String = "") -> Mesh:
	if key != "" and _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := depth * 0.5
	var idx := Geometry2D.triangulate_polygon(pts)
	for i in range(0, idx.size(), 3):
		var p0 := pts[idx[i]]; var p1 := pts[idx[i + 1]]; var p2 := pts[idx[i + 2]]
		var f := Vector3(0, 0, 1); var bk := Vector3(0, 0, -1)
		tri(st, Vector3(p0.x, p0.y, hz), Vector3(p1.x, p1.y, hz), Vector3(p2.x, p2.y, hz), f, f, f)
		tri(st, Vector3(p0.x, p0.y, -hz), Vector3(p1.x, p1.y, -hz), Vector3(p2.x, p2.y, -hz), bk, bk, bk)
	var ccw := _signed_area(pts) > 0.0
	for i in pts.size():
		var a := pts[i]; var b := pts[(i + 1) % pts.size()]
		var d := (b - a).normalized()
		var n2 := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
		var n := Vector3(n2.x, n2.y, 0)
		var a0 := Vector3(a.x, a.y, hz); var a1 := Vector3(a.x, a.y, -hz)
		var b0 := Vector3(b.x, b.y, hz); var b1 := Vector3(b.x, b.y, -hz)
		tri(st, a0, b0, b1, n, n, n)
		tri(st, a0, b1, a1, n, n, n)
	var m := st.commit()
	if key != "":
		_cache[key] = m
	return m

## Revolves a profile of (radius, y) points around the Y axis.
static func lathe(profile: Array, seg: int = 20, key: String = "") -> Mesh:
	if key != "" and _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var pn: Array[Vector2] = []
	for i in n:
		var p0: Vector2 = profile[max(i - 1, 0)]
		var p1: Vector2 = profile[min(i + 1, n - 1)]
		var t := (p1 - p0).normalized()
		pn.append(Vector2(t.y, -t.x))
	for i in n - 1:
		var pa: Vector2 = profile[i]; var pb: Vector2 = profile[i + 1]
		for s in seg:
			var a0 := TAU * s / seg; var a1 := TAU * (s + 1) / seg
			var c0 := cos(a0); var s0 := sin(a0); var c1 := cos(a1); var s1 := sin(a1)
			var v00 := Vector3(pa.x * c0, pa.y, pa.x * s0)
			var v01 := Vector3(pa.x * c1, pa.y, pa.x * s1)
			var v10 := Vector3(pb.x * c0, pb.y, pb.x * s0)
			var v11 := Vector3(pb.x * c1, pb.y, pb.x * s1)
			var n00 := Vector3(pn[i].x * c0, pn[i].y, pn[i].x * s0).normalized()
			var n01 := Vector3(pn[i].x * c1, pn[i].y, pn[i].x * s1).normalized()
			var n10 := Vector3(pn[i + 1].x * c0, pn[i + 1].y, pn[i + 1].x * s0).normalized()
			var n11 := Vector3(pn[i + 1].x * c1, pn[i + 1].y, pn[i + 1].x * s1).normalized()
			if (v10 - v00).length() > 0.00001 or (v11 - v01).length() > 0.00001:
				if (v01 - v00).length() > 0.00001:
					tri(st, v00, v01, v11, n00, n01, n11)
				if (v11 - v10).length() > 0.00001:
					tri(st, v00, v11, v10, n00, n11, n10)
	var m := st.commit()
	if key != "":
		_cache[key] = m
	return m

## A curved horn/tentacle made of shrinking cylinders along a bezier.
static func horn_points(length: float, curve: float, steps: int) -> Array:
	var pts := []
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector3(0, t * length, -curve * t * t * length))
	return pts
