class_name HeightGrid
extends RefCounted
## A height field sampled once on a regular grid and read back with bilinear filtering. Zones whose
## ground is an expensive function (the coast, the islands) bake it here so World.height_at, the terrain
## mesh, the sea's depth map, grass and collision all read the same cheap, identical numbers.

var rect := Rect2()
var cell := 1.0
var nx := 0
var nz := 0
var h := PackedFloat32Array()

## Samples f(x, z) at every grid point of `r` (cell metres apart).
func bake(r: Rect2, c: float, f: Callable) -> HeightGrid:
	rect = r
	cell = c
	nx = int(ceil(r.size.x / c)) + 1
	nz = int(ceil(r.size.y / c)) + 1
	h.resize(nx * nz)
	for j in nz:
		var z := r.position.y + j * c
		for i in nx:
			h[j * nx + i] = float(f.call(r.position.x + i * c, z))
	return self

func has(x: float, z: float) -> bool:
	return x >= rect.position.x and z >= rect.position.y and x <= rect.position.x + (nx - 1) * cell and z <= rect.position.y + (nz - 1) * cell

func sample(x: float, z: float) -> float:
	var fx := clampf((x - rect.position.x) / cell, 0.0, nx - 1.001)
	var fz := clampf((z - rect.position.y) / cell, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var k := iz * nx + ix
	return lerpf(lerpf(h[k], h[k + 1], tx), lerpf(h[k + nx], h[k + nx + 1], tx), tz)
