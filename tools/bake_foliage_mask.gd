extends SceneTree
## Bakes the foliage cards' procedural alpha (Flora.FOLIAGE_SHADER's needles / leaves / fern) into
## assets/textures/fx/foliage_mask_<kind>.png (one 8-bit grey image per kind, Flora.NEEDLES / LEAVES / FERN = 0 / 1 / 2;
## 0..1 = the alpha before its 0.5 cut: one byte a texel, since the shadow passes are bound by its bandwidth), which
## the leaves' shadow casters sample instead of working it out per shadow texel (Flora.FOLIAGE_SHADOW_SHADER).
##   godot --headless --path . -s tools/bake_foliage_mask.gd [-- size]
## A straight port of the shader's functions; float precision differs from the GPU by ~1e-4 in the hashes.
const N := 256

func h21(p: Vector2) -> float:
	p = Vector2(fposmod(p.x * 123.34, 1.0), fposmod(p.y * 456.21, 1.0))
	var d := p.dot(p + Vector2(45.32, 45.32))
	p += Vector2(d, d)
	return fposmod(p.x * p.y, 1.0)

func vn(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	return lerpf(lerpf(h21(i), h21(i + Vector2(1, 0)), u.x), lerpf(h21(i + Vector2(0, 1)), h21(i + Vector2(1, 1)), u.x), u.y)

func ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)

func needles(uv: Vector2) -> float:
	var x := uv.x
	var y := uv.y - 0.5
	var env := 1.0 - ss(0.42 * (1.0 - x * 0.55), 0.48 * (1.0 - x * 0.5), absf(y))
	env *= ss(0.0, 0.06, x) * (1.0 - ss(0.92, 1.0, x))
	var t := x * 24.0 - absf(y) * 9.0 + h21(Vector2(floorf(x * 24.0), signf(y))) * 0.4
	var nd := 1.0 - ss(0.12, 0.3, absf(fposmod(t, 1.0) - 0.5))
	var twig := 1.0 - ss(0.015, 0.03, absf(y))
	return maxf(nd * env, twig * (1.0 if x <= 0.95 else 0.0))

func leaves(uv: Vector2) -> float:
	var p := uv * 3.4
	var a := 0.0
	for j in range(-1, 2):
		for i in range(-1, 2):
			var cell := p.floor() + Vector2(i, j)
			var c := cell + Vector2(h21(cell), h21(cell + Vector2(7.1, 7.1))) * 0.8 + Vector2(0.1, 0.1)
			var ang := h21(cell + Vector2(3.3, 3.3)) * 6.2831
			var d := p - c
			d = Vector2(d.x * cos(ang) - d.y * sin(ang), d.x * sin(ang) + d.y * cos(ang))
			var e := (d * Vector2(1.0, 2.1)).length()
			a = maxf(a, 1.0 - ss(0.42, 0.5, e))
	var r := (uv - Vector2(0.5, 0.5)).length()
	return a * (1.0 - ss(0.38, 0.5, r + vn(uv * 6.0) * 0.12))

func fern(uv: Vector2) -> float:
	var x := uv.x
	var y := uv.y - 0.5
	var width := 0.46 * sin(clampf(x, 0.0, 1.0) * 3.14159) * (1.0 - x * 0.35)
	var rib := 1.0 - ss(0.01, 0.025, absf(y))
	var pinna := fposmod(x * 16.0 - absf(y) * 2.5, 1.0)
	var leaflet := (1.0 - ss(0.32, 0.46, absf(pinna - 0.5))) * (1.0 - ss(width * 0.85, width, absf(y)))
	return maxf(rib * (1.0 if x <= 0.98 else 0.0), leaflet)

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n := int(a[0]) if a.size() > 0 else N
	for k in 3:
		var img := Image.create(n, n, false, Image.FORMAT_L8)
		for y in n:
			for x in n:
				# texel centres, the way the GPU samples them (UV (0,0) is the image's top left)
				var uv := Vector2((x + 0.5) / n, (y + 0.5) / n)
				var v := needles(uv) if k == 0 else (leaves(uv) if k == 1 else fern(uv))
				img.set_pixel(x, y, Color(v, v, v))
		img.save_png("res://assets/textures/fx/foliage_mask_%d.png" % k)
	print("[MASK] ", n, "x", n, " written")
	quit()
