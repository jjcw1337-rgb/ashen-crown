class_name SoulSiphonFx
extends RefCounted
## Soul Siphon's look on every game (SoulSiphon is its rules). Draws only:
##  "latch" {t: [the victim], x: the hold}: the tether hooks in (h.fxs["tether"], drawn from his hand into the
##    victim's chest every frame by `update`) until "end" {x: its hold ran out, n: the life it drained back}, or
##    x + SLACK seconds if that is lost;
##  "tick": a drain (the victim flashes, the hum ticks); "soul" {p}: a victim it killed gives up its soul to him.

const SPIRIT := SpiritFx.SPIRIT
const VIOLET := SpiritFx.VIOLET
const PALE := SpiritFx.PALE
const SLACK := 2.0          # a tether outlives its hold by this much at most if the "end" is lost

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"cast":
			pass
		"latch":
			_end(h, false)
			var vs: Array = ev.get("t", [])
			if vs.is_empty():
				return true
			var v = vs[0]
			latch(root, _chest(v))
			h.fxs["tether"] = {"victim": v, "node": tether(root), "hum": Sfx.start_loop("drain_loop", -16.0, 0.72, h),
				"until": float(ev.get("x", 2.5)) + SLACK}
			if v is Enemy:
				v.set_drained(true, SPIRIT)
			SkillFx.snd(h, "spirit_dart", -4.0, 0.8)
			SkillFx.shake(h, 0.08)
		"tick":
			if h.fxs.has("tether"):
				var v = h.fxs["tether"]["victim"]
				if is_instance_valid(v) and v is Enemy and not v.dead:
					v.drain_flash(SPIRIT)
				h.fxs["tether"]["until"] = maxf(float(h.fxs["tether"]["until"]), SLACK)
			if h.puppet:
				Sfx.play_at("drain_tick", h.global_position, -16.0, 1.3)
			else:
				Sfx.play("drain_tick", -12.0, 1.3)
		"soul":
			var p: Vector3 = ev["p"]
			SpiritFx.pulse(root, p, PALE, 1.6, 0.35)
			SpiritFx.soul_wisp(root, p, h, WraithSkill.wisp_time(0), -6.0)
		"end":
			_end(h, bool(ev.get("x", false)))
			var n := int(ev.get("n", 0))
			if n >= 1 and h._mine():
				Fx.number(root, h.global_position + Vector3(0, 2.3, 0), "+%d" % n, Color(0.55, 0.95, 1.0))
		_:
			return false
	return true

## A victim's chest: a monster's by its height, a player's (on another game a player is their hero) by a man's.
static func _chest(v) -> Vector3:
	return SkillFx.chest_of(v) if v is Enemy else (v as Node3D).global_position + Vector3(0, 1.2, 0)

## The tether lets go: it thins and is gone, the victim's rim and the hum with it (a violet pulse if its hold ran out).
static func _end(h: Hero, spent: bool) -> void:
	if not h.fxs.has("tether"):
		return
	var t: Dictionary = h.fxs["tether"]
	h.fxs.erase("tether")
	var v = t["victim"]
	if v != null and is_instance_valid(v):
		if v is Enemy:
			v.set_drained(false)
		if spent and not v.dead and h.game.world != null:
			SpiritFx.pulse(h.game.world.fx_root, _chest(v), VIOLET, 1.2, 0.3)
	var n = t["node"]
	if n != null and is_instance_valid(n):
		var tw: Tween = n.create_tween()
		tw.tween_property(n, "fade", 0.0, 0.25)
		tw.tween_callback(n.queue_free)
	var hum = t["hum"]
	if hum != null and is_instance_valid(hum):
		hum.stop()
		hum.queue_free()

## Every frame (his own game and his puppet's): the tether from his hand to the victim's chest, until it is let go,
## its victim is lost, or its time is up.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("tether"):
		return
	var t: Dictionary = h.fxs["tether"]
	var v = t["victim"]
	var n = t["node"]
	t["until"] = float(t["until"]) - delta
	if v == null or not is_instance_valid(v) or n == null or not is_instance_valid(n) or float(t["until"]) <= 0.0:
		_end(h, false)
	else:
		(n as Tether).draw(SkillFx.hand(h, true), _chest(v), h.anim_time)

static func clear(h: Hero) -> void:
	_end(h, false)

# ---------------------------------------------------------------- Soul Siphon: the tether
## The tether from the Wraith's hand into a victim: two strands of spirit-light twisted round a dark core, pulled
## taut, with the stolen soul-stuff flowing back along it as pale motes, and the soul being torn loose at the far
## end (a writhing pale knot). Redrawn each frame (an ImmediateMesh ribbon facing the camera).
class Tether extends MeshInstance3D:
	var born := -1.0
	var jitter := 0.0
	var _from := Vector3.ZERO
	var _span := Vector3.ZERO
	var _len := 1.0
	var _side := Vector3.RIGHT
	var _up := Vector3.UP
	var _vup := Vector3.UP
	var _t := 0.0
	var fade := 1.0      # 1 holding, eased to 0 as it lets go

	func _init() -> void:
		jitter = randf() * 10.0
		mesh = ImmediateMesh.new()
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		top_level = true
		material_override = SpiritFx.ribbon_mat()

	func _at(u: float, wob: float, rate: float, ph: float) -> Vector3:
		var env := sin(u * PI)
		var a := u * rate * TAU * _len / 5.0 + _t * 6.0 + ph + jitter
		var sag := Vector3.DOWN * 0.18 * env * _len * 0.12
		return _from + _span * u + (_side * sin(a) + _up * cos(a * 1.3) * 0.7) * wob * env + sag

	func _blob(im: ImmediateMesh, p: Vector3, r: float, c0: Color, c1: Color, seg := 10, star := 0.0) -> void:
		for i in seg:
			var a0 := TAU * i / seg + _t * 2.0
			var a1 := TAU * (i + 1) / seg + _t * 2.0
			var r0 := r * (1.0 + star * sin(a0 * 3.0 + _t * 11.0))
			var r1 := r * (1.0 + star * sin(a1 * 3.0 + _t * 11.0))
			im.surface_set_color(c0)
			im.surface_add_vertex(p)
			im.surface_set_color(c1)
			im.surface_add_vertex(p + (_side * cos(a0) + _vup * sin(a0)) * r0)
			im.surface_add_vertex(p + (_side * cos(a1) + _vup * sin(a1)) * r1)

	func _strip(im: ImmediateMesh, pts: Array, ws: Array, cols: Array, across: Vector3) -> void:
		for i in range(1, pts.size()):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var wa: float = ws[i - 1]
			var wb: float = ws[i]
			var ca: Color = cols[i - 1]
			var cb: Color = cols[i]
			var la := a - across * wa * 0.5
			var ra := a + across * wa * 0.5
			var lb := b - across * wb * 0.5
			var rb := b + across * wb * 0.5
			for v in [[la, ca], [ra, ca], [rb, cb], [la, ca], [rb, cb], [lb, cb]]:
				im.surface_set_color(v[1])
				im.surface_add_vertex(v[0])

	## from: the Wraith's hand; to: the victim's chest.
	func draw(from: Vector3, to: Vector3, t: float) -> void:
		global_transform = Transform3D.IDENTITY
		var im: ImmediateMesh = mesh
		im.clear_surfaces()
		if born < 0.0:
			born = t
		var grow := 1.0 - pow(1.0 - clampf((t - born) / 0.14, 0.0, 1.0), 3.0)
		to = from.lerp(to, grow)
		_t = t
		_from = from
		_span = to - from
		_len = _span.length()
		if _len < 0.05 or fade <= 0.01:
			return
		var dir := _span / _len
		var cam := get_viewport().get_camera_3d()
		var view := Vector3.UP
		if cam != null:
			view = (cam.global_position - (from + to) * 0.5).normalized()
		_side = dir.cross(view)
		if _side.length() < 0.01:
			_side = dir.cross(Vector3.RIGHT)
		_side = _side.normalized()
		_up = _side.cross(dir).normalized()
		_vup = view.cross(_side).normalized()
		var n := clampi(int(_len * 6.0), 12, 64)
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var strands := [
			[0.3, 0.02, 1.5, 0.0, SpiritFx.NIGHT.lightened(0.2), 0.5],
			[0.11, 0.1, 3.2, 0.0, SpiritFx.SPIRIT, 0.8],
			[0.08, 0.1, 3.2, PI, SpiritFx.VIOLET, 0.7],
			[0.04, 0.01, 2.0, 1.0, SpiritFx.PALE, 0.85],
		]
		for s in strands:
			var pts := []
			var ws := []
			var cols := []
			for i in n + 1:
				var u := float(i) / n
				pts.append(_at(u, float(s[1]), float(s[2]), float(s[3])))
				ws.append(float(s[0]) * (0.6 + 0.4 * sin(u * PI)) * grow * fade)
				var pulse := pow(0.5 + 0.5 * sin(u * _len * 2.5 - t * 12.0 + jitter), 5.0)
				var c: Color = s[4]
				cols.append(Color(c.r, c.g, c.b, clampf(float(s[5]) * (0.5 + 0.8 * pulse) * fade, 0.0, 1.0)))
			_strip(im, pts, ws, cols, _side)
		# motes of the stolen soul drifting down the tether into the hand
		for k in 10:
			var h := fposmod(sin(k * 12.9898 + jitter) * 43758.5453, 1.0)
			var u := fposmod(k / 10.0 + h * 0.1 - t * (0.6 + h * 0.5), 1.0)
			var e := sin(u * PI)
			var mp := _at(u, 0.08 + h * 0.12, 3.2, k * 1.7)
			_blob(im, mp, (0.05 + 0.05 * h) * (0.4 + 0.6 * e) * fade, Color(0.95, 1.0, 1.0, 0.9 * e * fade), Color(SpiritFx.SPIRIT.r, SpiritFx.SPIRIT.g, SpiritFx.SPIRIT.b, 0.0), 6)
		# the soul being torn loose: a pale knot writhing at the victim
		var throb := 1.0 + 0.25 * sin(t * 16.0)
		_blob(im, to, 0.5 * throb * fade, Color(SpiritFx.VIOLET.r, SpiritFx.VIOLET.g, SpiritFx.VIOLET.b, 0.3 * fade), Color(0.1, 0.0, 0.2, 0.0), 14)
		_blob(im, to, 0.22 * throb * fade, Color(1.0, 1.0, 1.0, 0.8 * fade), Color(SpiritFx.SPIRIT.r, SpiritFx.SPIRIT.g, SpiritFx.SPIRIT.b, 0.0), 10, 0.4)
		# the grip: a small vortex at the hand
		_blob(im, from, 0.16 * fade, Color(SpiritFx.PALE.r, SpiritFx.PALE.g, SpiritFx.PALE.b, 0.7 * fade), Color(SpiritFx.VIOLET.r, SpiritFx.VIOLET.g, SpiritFx.VIOLET.b, 0.0), 8, 0.3)
		im.surface_end()

static func tether(root: Node3D) -> Tether:
	var t := Tether.new()
	root.add_child(t)
	return t

## The tether's bite: a flash of violet where it sinks in.
static func latch(root: Node3D, pos: Vector3) -> void:
	SpiritFx.burst(root, pos, VIOLET, 14, 2.5, 0.09, 0.4, true, 0.0)
	Fx.flash(root, pos, VIOLET, 1.6, 0.25, 3.0)
