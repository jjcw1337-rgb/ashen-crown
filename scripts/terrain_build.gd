extends RefCounted
## Main-thread terrain rows. Both synchronous builders and scheduled worlds use this exact algorithm.
## A mesh upload remains one atomic step and is included in World's max_step_ms measurement.
var world
var target: MeshInstance3D
var tcol: Dictionary
var x0: float
var z0: float
var step_size: float
var nx: int
var nz: int
var floor_y: float
var own: Callable
var drop: float
var clip: Callable
var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()
var hs := PackedFloat32Array()
var phase := 0
var j := 0

func _init(w, node: MeshInstance3D, r: Rect2, spacing: float, palette: Dictionary, floor_height: float, ownership: Callable, offset: float, clipping: Callable) -> void:
	world = w
	target = node
	x0 = r.position.x
	z0 = r.position.y
	step_size = spacing
	nx = int(r.size.x / spacing)
	nz = int(r.size.y / spacing)
	tcol = palette.duplicate()
	floor_y = floor_height
	own = ownership
	drop = offset
	clip = clipping

func step() -> bool:
	if not is_instance_valid(world) or not is_instance_valid(target): return true
	match phase:
		0:
			verts.resize((nx + 1) * (nz + 1))
			norms.resize(verts.size())
			cols.resize(verts.size())
			hs.resize((nx + 3) * (nz + 3))
			phase = 1
		1:
			_heights()
			j += 1
			if j == nz + 3: phase = 2; j = 0
		2:
			_vertices()
			j += 1
			if j == nz + 1: phase = 3; j = 0
		3:
			if j < nz: _indices()
			j += 1
			if j >= nz: phase = 4
		4:
			if idx.is_empty():
				target.free()
			else:
				_commit()
			verts.clear(); norms.clear(); cols.clear(); idx.clear(); hs.clear()
			phase = 5
			return true
	return phase == 5

func _heights() -> void:
	for i in nx + 3:
		hs[j * (nx + 3) + i] = world.ground_h(x0 + (i - 1) * step_size, z0 + (j - 1) * step_size)

func _vertices() -> void:
	for i in nx + 1:
		var x := x0 + i * step_size
		var z := z0 + j * step_size
		var k := j * (nx + 1) + i
		var hc := hs[(j + 1) * (nx + 3) + (i + 1)]
		var hl := hs[(j + 1) * (nx + 3) + i]
		var hr := hs[(j + 1) * (nx + 3) + (i + 2)]
		var hd := hs[j * (nx + 3) + (i + 1)]
		var hu := hs[(j + 2) * (nx + 3) + (i + 1)]
		verts[k] = Vector3(x, hc - drop, z)
		if clip.is_valid():
			# (the island camp: a vertex past the edge is drawn in onto it, so the ground ends in a smooth line)
			var q: Vector3 = clip.call(x, z, hc - drop)
			verts[k] = q
		norms[k] = Vector3(hl - hr, 2.0 * step_size, hd - hu).normalized()
		var cliff := clampf((1.0 - norms[k].y) * 3.0, 0.0, 1.0)
		cols[k] = Color(world.dirt_at(x, z), cliff, world.cobble_at(x, z), 1.0)

func _indices() -> void:
	for i in nx:
		var a := j * (nx + 1) + i
		var b := a + 1
		var c := a + (nx + 1)
		var d := c + 1
		if verts[a].y < floor_y and verts[b].y < floor_y and verts[c].y < floor_y and verts[d].y < floor_y:
			continue
		if own.is_valid() and not bool(own.call(x0 + (i + 0.5) * step_size, z0 + (j + 0.5) * step_size)):
			continue
		idx.append_array([a, b, d, a, d, c])

func _commit() -> void:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = Mats.shader("terrain")
	for k in tcol.keys():
		mat.set_shader_parameter(k, tcol[k])
	# the ground's small detail: pebbles and grit in the dirt from Medium up, fallen leaves in Act I's oak woods
	mat.set_shader_parameter("ground_detail", 1.0 if world.detail >= 1 else 0.0)
	mat.set_shader_parameter("litter", 1.0 if world.oak_forest and world.detail >= 1 else 0.0)
	mesh.surface_set_material(0, mat)
	target.mesh = mesh
