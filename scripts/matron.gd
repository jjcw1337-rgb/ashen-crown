class_name Matron
extends RefCounted
## The Hollow Matron's heart. She has none: it beats inside one of the veiled Mourners that
## drift around her crypt, and while it does her body is hollow (weapons do a quarter damage).
##
## Each cycle she tears the heart out of her chest and it arcs into one of the Mourners, which
## flares once so you can see where it went. Then the Mourners shuffle like cups in a shell
## game, and the heart stays silent while they move: keep your eyes on it. Once they settle it
## beats again, faintly, every couple of seconds (a red pulse under the veil and a heartbeat
## that's louder the closer you are). Kill the carrier and the heart is crushed: she loses a
## chunk of her life, staggers and stands exposed (double damage) for a few seconds, then
## tears it out again. She can't fall below two thirds, then one third, of her life until her
## heart has been crushed again, so every fight runs at least three cycles. Kill the wrong Mourner and it bursts in a wail that hurts everyone
## near it and raises a zombie. Every cycle brings another Mourner and a faster shuffle;
## area attacks hit the right one and the wrong ones alike.
##
## The host runs all of this. Other players see it through Enemy fx events: "hollow" and
## "exposed" and "rip" on the Matron, "heart_flare" / "heart_on" / "wail" on a Mourner.

const HOLLOW_TAKEN := 0.25
const EXPOSED_TAKEN := 2.0
const EXPOSED_TIME := 8.0
const CRUSH := 0.15          # share of her max life the crushed heart costs her
const RING := 6.0            # Mourners circle this far from the centre of her crypt
const PHASES := [0.66, 0.33] # life she can't fall below in cycles 0 and 1
const FIRST := 3             # Mourners in the first cycle; one more each cycle after
const MOST := 6

var boss: Enemy
var state := "idle"          # idle, rip (tearing it out), fly, shuffle, hidden, exposed
var t := 0.0
var cycle := 0
var mourners: Array = []
var carrier: Enemy = null
var slots: Array = []        # ring angle of each Mourner (index matches mourners)
var spin := 0.0              # the ring turns slowly once the shuffle is over
var swap_t := 0.0
var orb: Node3D = null
var taught := false

func _init(b: Enemy) -> void:
	boss = b

## Damage the Matron takes is multiplied by this (also set on clients from the fx events).
static func taken_for(st: String) -> float:
	match st:
		"exposed": return EXPOSED_TAKEN
		"idle": return 1.0
	return HOLLOW_TAKEN

## The life she can't fall below this cycle.
func floor_life() -> float:
	return boss.max_life * (float(PHASES[cycle]) if cycle < PHASES.size() else 0.0)

## Damage after the phase floor (Enemy.take_damage).
func cap(dmg: float) -> float:
	return clampf(dmg, 0.0, maxf(0.0, boss.life - floor_life()))

func center() -> Vector3:
	return boss.home

## Called every frame on the host while she is fighting.
func update(delta: float) -> void:
	if boss.dead:
		return
	t += delta
	match state:
		"idle":
			_new_cycle()
		"rip":
			# a stun can interrupt the cast: try again, and never stay hollow for good
			if t > 4.0:
				launch()
			elif boss.special != "rip" and boss.stun_t <= 0.0:
				boss._begin_special("rip")
		"shuffle":
			swap_t -= delta
			if swap_t <= 0.0:
				swap_t = _swap_every()
				_swap()
			if t >= _shuffle_time():
				state = "hidden"
				t = 0.0
				carrier._fx("heart_on")
			_herd(delta, 0.0)
		"hidden":
			spin += delta * 0.12
			_herd(delta, spin)
		"exposed":
			if t >= EXPOSED_TIME or boss.life <= floor_life() + 0.5:
				cycle += 1
				_new_cycle()

func _swap_every() -> float:
	return maxf(0.45, 0.95 - cycle * 0.12)

func _shuffle_time() -> float:
	return 4.0 + cycle * 0.8

## Spawns this cycle's Mourners on the ring and has her tear the heart out.
func _new_cycle() -> void:
	_set_state("rip")
	t = 0.0
	spin = 0.0
	for m in mourners:
		if is_instance_valid(m) and not m.dead:
			m.die_visual()
			boss.game.net.enemy_died(m)
	mourners.clear()
	slots.clear()
	carrier = null
	var n := mini(FIRST + cycle, MOST)
	var c := center()
	for i in n:
		var a := TAU * i / n + randf() * 0.3
		var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * RING
		p = boss.game.world.free_spot_near(p, 1.0)
		var m: Enemy = boss.game.spawn_enemy("mourner", p, maxi(1, boss.level - 2), false, "", boss.pack_id)
		if m == null:
			continue
		m.heart_owner = self
		m.aggro = true
		m.goto = p
		mourners.append(m)
		slots.append(a)
		Fx.burst(boss.game.world.fx_root, p + Vector3(0, 0.6, 0), Color(0.75, 0.72, 0.68, 0.7), 18, 2.0, 0.2, 0.9, false, 1.0)
	boss._begin_special("rip")

## The cast's impact (Enemy._impact "rip"): the heart leaves her chest for a Mourner.
func launch() -> void:
	var alive := mourners.filter(func(m): return is_instance_valid(m) and not m.dead)
	if alive.is_empty():
		_new_cycle()
		return
	carrier = alive[randi() % alive.size()]
	_set_state("fly")
	var from := boss.global_position + Vector3(0, boss.height * 1.45, 0)
	orb = heart_orb(boss.game.world.fx_root)
	orb.global_position = from
	var tw := orb.create_tween()
	var target: Enemy = carrier
	tw.tween_method(func(u: float):
		if is_instance_valid(target) and is_instance_valid(orb):
			var to: Vector3 = target.global_position + Vector3(0, target.height * 1.2, 0)
			orb.global_position = from.lerp(to, u) + Vector3(0, sin(u * PI) * 3.0, 0), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_arrived)
	Sfx.play("heartbeat", 2.0, 1.0)

func _arrived() -> void:
	if is_instance_valid(orb):
		orb.queue_free()
	orb = null
	if state != "fly":
		return
	if not is_instance_valid(carrier) or carrier.dead:
		_new_cycle()
		return
	# one bright beat so you can see where it went, then silence while they shuffle
	carrier._fx("heart_flare")
	state = "shuffle"
	t = 0.0
	swap_t = 0.5

## Two Mourners trade places on the ring, walking past each other.
func _swap() -> void:
	var idx := []
	for i in mourners.size():
		if is_instance_valid(mourners[i]) and not mourners[i].dead:
			idx.append(i)
	if idx.size() < 2:
		return
	idx.shuffle()
	var a: int = idx[0]
	var b: int = idx[1]
	var sa: float = slots[a]
	slots[a] = slots[b]
	slots[b] = sa

## Walks each Mourner toward its place on the (turning) ring, fast enough to arrive by the
## next swap.
func _herd(_delta: float, turn: float) -> void:
	var c := center()
	for i in mourners.size():
		var m = mourners[i]
		if not is_instance_valid(m) or m.dead:
			continue
		var a: float = float(slots[i]) + turn
		m.goto = c + Vector3(cos(a), 0, sin(a)) * RING
		m.goto_speed = (RING * 2.0) / _swap_every() * 0.75 if state == "shuffle" else 1.2

## A Mourner died (Enemy._die on the host).
func on_mourner_died(m: Enemy) -> void:
	var i := mourners.find(m)
	if i < 0:
		return
	if m == carrier and state in ["shuffle", "hidden", "fly"]:
		_crush(m)
	elif state in ["shuffle", "hidden", "fly"]:
		_wail(m)

func _crush(m: Enemy) -> void:
	carrier = null
	var g = boss.game
	var at: Vector3 = m.global_position + Vector3(0, m.height * 1.2, 0)
	Fx.burst(g.world.fx_root, at, Color(1.0, 0.1, 0.08), 40, 5.0, 0.16, 0.8, true, -4.0)
	Fx.splat(g.world.fx_root, m.global_position, Color(0.5, 0.0, 0.02), 1.4)
	Sfx.play("heartbeat", 4.0, 0.7)
	Sfx.play("boss_die", -6.0, 1.4)
	g.add_shake(0.5)
	# the crushed heart is torn back into her: a chunk of life, a stagger, exposed
	var dmg := cap(boss.max_life * CRUSH)
	boss.life = maxf(1.0, boss.life - dmg)
	Fx.number(g.world.fx_root, boss.global_position + Vector3(0, boss.height * 1.9 + 0.5, 0), str(int(dmg)) + "!", Color(1.0, 0.25, 0.2), true)
	boss.atk_t = -1.0
	boss.stun_t = 2.0
	_set_state("exposed")
	t = 0.0
	g.ui.message("Her heart is crushed. She is exposed!", Color(1.0, 0.4, 0.3))
	for o in mourners:
		if o != m and is_instance_valid(o) and not o.dead:
			Fx.burst(g.world.fx_root, o.global_position + Vector3(0, 0.6, 0), Color(0.6, 0.58, 0.55, 0.7), 14, 2.0, 0.2, 0.8, false, -3.0)
			o.die_visual()
			g.net.enemy_died(o)
	mourners.clear()

func _wail(m: Enemy) -> void:
	var g = boss.game
	m.special_fx("wail")
	g.net.enemy_fx(m, "wail")
	for h in g.all_heroes():
		if not h.dead and h.global_position.distance_to(m.global_position) < 3.5:
			h.take_hit(boss._roll() * 0.7, m.global_position, "nova", "cold")
	g.spawn_enemy("zombie", g.world.free_spot_near(m.global_position, 1.0), maxi(1, boss.level - 2), false, "", boss.pack_id)
	if not taught:
		taught = true
		g.ui.message("Wrong one. Her heart beats in another Mourner.", Color(0.8, 0.8, 1.0))

func _set_state(s: String) -> void:
	var was := taken_for(state)
	state = s
	if taken_for(s) != was or s == "exposed":
		boss._fx("exposed" if s == "exposed" else "hollow")

## The first time a hollow Matron is hit, say why it barely hurt.
func hollow_hit() -> void:
	if not taught:
		taught = true
		boss.game.ui.message("Her body is hollow. Her heart beats in one of the Mourners.", Color(1.0, 0.75, 0.6))

## Which foe a sensible player hits right now (the balance bot uses this).
func priority_target() -> Enemy:
	if state in ["shuffle", "hidden"] and is_instance_valid(carrier) and not carrier.dead:
		return carrier
	return boss

func clear() -> void:
	if is_instance_valid(orb):
		orb.queue_free()
	for m in mourners:
		if is_instance_valid(m) and not m.dead:
			m.die_visual()
			boss.game.net.enemy_died(m)
	mourners.clear()

# ---------------------------------------------------------------- visuals
## The heart in flight: a dark red, beating lump with its own light.
static func heart_orb(root: Node3D) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	Models.P(n, Geo.sph(0.26, 14), Mats.glow(Color(0.9, 0.08, 0.06), 2.4), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.15, 0.9))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.15, 0.1)
	l.light_energy = 4.0
	l.omni_range = 6.0
	n.add_child(l)
	var trail := Fx.burst(n, Vector3.ZERO, Color(0.8, 0.05, 0.05, 0.8), 30, 0.4, 0.09, 0.5, true, -1.0)
	trail.one_shot = false
	trail.local_coords = false
	return n
