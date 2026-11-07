class_name Hoard
extends RefCounted
## King Grubb the Gilded's fight (the Act I boss). One rule to learn: his gold is his life. Every
## pile that reaches him heals him; every pile you take from him hurts him.
##
## He fights with his Hoardkey (swings and a ground slam) and lobs Gilded Bombs at you: a red
## circle marks where one lands, then it blows. At 75%, 50% and 25% of his life one of the three
## sacks on his back rips open. Gold sprays across his vault in glittering piles, Gold Grabbers
## scurry out of their tunnels and everyone scrambles for it: grabbers scoop a pile and haul it
## back to him over their heads, and he waddles from pile to pile scooping it up himself. Each
## pile that reaches him heals him. Step on a pile and the gold is yours, and losing it hurts him
## (he shrieks and staggers); kill a grabber hauling gold and it drops it for you. When the gold is gone the fight goes on, and after the last
## sack he is broke and enraged (faster, three bombs at a time).
##
## The host runs all of it. Other players see it through Enemy fx events (fx() below): the
## piles, bombs, burst sacks, shouts, and "carry_on"/"carry_off" on a grabber.

const SPILLS := [0.75, 0.5, 0.25]   # life shares at which the sacks burst, in order
const PILES := 6                     # piles in the first spill, one more in each after
const HEAL := 0.03                   # share of his max life one pile gives back
const STEAL := 0.045                 # share of his max life he loses when you take a pile
const BOMB_EVERY := 6.5
const BOMB_R := 2.6
const BOMB_FLY := 0.75
const BOMB_FUSE := 1.3
const GUARDS := 3                    # grabbers with him from the start
const TAKE_R := 1.1                  # step this close to a pile to take it
const SCRAMBLE_MAX := 30.0
const GRAB_DELAY := 1.1              # grabbers gawp at the flying gold this long before they scramble

var boss: Enemy
var sacks := 3
var state := "idle"                  # idle (not fighting yet), fight, spill
var t := 0.0
var piles := {}                      # id -> {"pos": Vector3, "amount": int, "node": Node3D, "by": Enemy}
var next_id := 0
var bomb_t := 4.0
var grabbers: Array = []
var carrying := {}                   # grabber -> amount it is hauling
var shout_cd := 0.0
var shout_lbl: Label3D
var told := false
var bombs: Array = []                # where live bombs will blow (host)
var robbed := 0                      # piles heroes have taken (host)
var met := false                     # the fight has begun (every peer, from the "intro" event)
var voice: AudioStreamPlayer3D       # his muttering heard across the fort before the fight
var murmur_t := 2.0

func _init(b: Enemy) -> void:
	boss = b

## Host: his guards, standing about the hoard before the fight.
func start() -> void:
	if boss.remote or boss.game.net.is_client() or not is_instance_valid(boss):
		return
	for i in GUARDS:
		var a := TAU * i / GUARDS + 0.6
		_grabber(boss.game.world.free_spot_near(boss.global_position + Vector3(cos(a), 0, sin(a)) * 2.6, 0.6), false)

func _grabber(p: Vector3, burrow: bool) -> Enemy:
	var g: Enemy = boss.game.spawn_enemy("grabber", p, maxi(1, boss.level - 1), false, "", boss.pack_id)
	if g == null:
		return null
	g.hoard = self
	grabbers.append(g)
	if burrow:
		g.aggro = true
		boss._fx("hole:%.2f:%.2f" % [p.x, p.z])
	return g

# ---------------------------------------------------------------- his voice in the fort
## Before the fight his voice carries through the fort: he mutters and chuckles over his gold, faint
## from the gate and clearer as you close in. Every peer plays it for itself (Enemy._process).
func murmur(delta: float) -> void:
	var g = boss.game
	if met or boss.dead or Sfx.muted or g.hero == null:
		if voice != null and voice.playing and (met or boss.dead):
			voice.stop()
		return
	var d: float = g.hero.global_position.distance_to(boss.global_position)
	if voice == null:
		voice = AudioStreamPlayer3D.new()
		voice.bus = "Ambience"
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED   # the volume follows the distance below
		voice.max_distance = 0.0
		voice.position = Vector3(0, boss.height, 0)
		boss.add_child(voice)
	# from about 75 m (the gate) at a whisper up to clear when he is in sight
	var near := 1.0 - smoothstep(14.0, 75.0, d)
	voice.volume_db = lerpf(-34.0, -4.0, near) + Sfx.volume_db
	if voice.playing:
		return
	murmur_t -= delta
	if murmur_t > 0.0 or d > 80.0:
		return
	murmur_t = randf_range(5.0, 10.0)
	voice.stream = Sfx._pick("grubb_mutter")
	if voice.stream == null:
		return
	voice.pitch_scale = randf_range(0.9, 0.97)
	voice.play()
	Sfx.counts["grubb_mutter"] = int(Sfx.counts.get("grubb_mutter", 0)) + 1

# ---------------------------------------------------------------- host logic
## Called every frame on the host while he is fighting.
func update(delta: float) -> void:
	if boss.dead:
		return
	t += delta
	shout_cd -= delta
	match state:
		"idle":
			state = "fight"
			t = 0.0
			boss._begin_special("cackle")
			boss._fx("intro")
			shout("Who's touching my GOLD?!")
		"fight":
			if sacks > 0 and boss.life <= boss.max_life * float(SPILLS[3 - sacks]) and boss.atk_t < 0.0:
				_spill()
				return
			bomb_t -= delta
			if bomb_t <= 0.0 and boss.atk_t < 0.0 and boss.stun_t <= 0.0:
				bomb_t = BOMB_EVERY * (0.8 if boss.enraged else 1.0)
				boss._begin_special("bomb")
		"spill":
			_scramble()

func _spill() -> void:
	sacks -= 1
	state = "spill"
	t = 0.0
	boss._begin_special("burst")
	boss._fx("spill:%d" % sacks)
	shout("NO! MY GOLD!" if sacks == 2 else ("Get it! GET IT ALL!" if sacks == 1 else "MY LAST SACK!"))
	var g = boss.game
	var n := PILES + (2 - sacks)
	var amt := int(6 + boss.level * 2.5)
	for i in n:
		var a := TAU * i / n + randf_range(-0.3, 0.3)
		var p: Vector3 = g.world.free_spot_near(boss.home + Vector3(cos(a), 0, sin(a)) * randf_range(3.5, 8.0), 0.8)
		var id := next_id
		next_id += 1
		boss._fx("pile:%d:%.2f:%.2f:%d" % [id, p.x, p.z, amt])
	var holes: Array = g.world.hoard_holes if not g.world.hoard_holes.is_empty() else [boss.home]
	for i in 2 + (2 - sacks):
		var h: Vector3 = holes[(i + sacks) % holes.size()]
		_grabber(g.world.free_spot_near(h, 0.8), true)

func _scramble() -> void:
	var g = boss.game
	for id in piles.keys():
		var p: Dictionary = piles[id]
		for h in g.all_heroes():
			if not h.dead and _flat(h.global_position, p["pos"]) < TAKE_R:
				_take(id, true)
				_robbed()
				if h == g.hero:
					h.add_to_inventory(Items.gold(int(p["amount"])))
					Sfx.play("gold", 0.0, 0.9)
				else:
					g.net.give_gold(h.peer_id, int(p["amount"]))
				if shout_cd <= 0.0:
					shout("THIEF!" if randf() < 0.5 else "That's MINE!")
				break
	for e in carrying.keys():
		if not is_instance_valid(e) or e.dead:
			carrying.erase(e)
		elif _flat(e.global_position, boss.global_position) < boss.radius + 1.3:
			var amt: int = carrying[e]
			carrying.erase(e)
			e._fx("carry_off")
			_feed(amt)
	if piles.is_empty() and carrying.is_empty():
		_end_spill()
	elif t > SCRAMBLE_MAX:
		for id in piles.keys():
			_take(id, false)

func _end_spill() -> void:
	state = "fight"
	bomb_t = 3.0
	if sacks == 0 and not boss.enraged:
		boss.enraged = true
		boss.speed *= 1.3
		boss.atk_dur *= 0.8
		boss._fx("broke")

## Where a grabber (or the king himself) goes during a scramble; null = fight as usual.
func steer(e: Enemy, delta: float) -> Variant:
	if state != "spill":
		return null
	if e.atk_t >= 0.0:
		return Vector3.ZERO
	if e != boss and t < GRAB_DELAY:
		return Vector3.ZERO
	if carrying.has(e):
		return e.go_to(delta, boss.global_position, e.speed * 0.9)
	var best := -1
	var bd := INF
	for id in piles.keys():
		var by = piles[id]["by"]
		if by != null and by != e and is_instance_valid(by) and not by.dead:
			continue
		var d := _flat(e.global_position, piles[id]["pos"])
		if d < bd:
			bd = d
			best = id
	if best < 0:
		return null
	piles[best]["by"] = e
	if bd < (1.0 if e == boss else 0.6):
		e._begin_special("scoop")
		return Vector3.ZERO
	return e.go_to(delta, piles[best]["pos"], e.speed * (1.15 if e == boss else 1.0))

## The scoop lands (Enemy._impact "scoop").
func scooped(e: Enemy) -> void:
	for id in piles.keys():
		if piles[id]["by"] == e and _flat(e.global_position, piles[id]["pos"]) < 1.8:
			var amt: int = piles[id]["amount"]
			_take(id, false)
			if e == boss:
				_feed(amt)
			else:
				carrying[e] = amt
				e._fx("carry_on")
			return

## A hero took a pile: it hurts him (never the killing blow; that's yours).
func _robbed() -> void:
	var dmg := minf(boss.max_life * STEAL, boss.life - 1.0)
	if dmg <= 0.0:
		return
	boss.life -= dmg
	boss.hit_t = 0.6
	robbed += 1
	boss._fx("robbed:%d" % int(dmg))

func _take(id: int, by_hero: bool) -> void:
	boss._fx("pile_gone:%d:%d" % [id, 1 if by_hero else 0])

func _feed(_amt: int) -> void:
	var heal := minf(boss.max_life * HEAL, boss.max_life - boss.life)
	boss.life += heal
	boss._fx("feed:%d" % int(heal))
	if shout_cd <= 0.0:
		shout(["Hehehe... mine!", "More! MORE!", "Back where it belongs!"][randi() % 3])

## A grabber died (Enemy._die on the host): any gold it hauled is yours.
func on_grabber_died(e: Enemy) -> void:
	grabbers.erase(e)
	for id in piles.keys():
		if piles[id]["by"] == e:
			piles[id]["by"] = null
	if carrying.has(e):
		var amt: int = carrying[e]
		carrying.erase(e)
		boss.game.drop_item(Items.gold(amt), e.global_position)

## The bomb lands where you stood (Enemy._impact "bomb"); enraged, he throws three.
func throw_bomb(at: Vector3) -> void:
	var spots := [at]
	if boss.enraged:
		var side := (at - boss.global_position).cross(Vector3.UP).normalized()
		spots.append(at + side * 3.0)
		spots.append(at - side * 3.0)
	for s in spots:
		var p: Vector3 = boss.game.world.free_spot_near(s, 0.5)
		boss._fx("bomb:%.2f:%.2f" % [p.x, p.z])
		bombs.append(p)
		boss.get_tree().create_timer(BOMB_FLY + BOMB_FUSE).timeout.connect(_boom.bind(p))

func _boom(p: Vector3) -> void:
	bombs.erase(p)
	if not is_instance_valid(boss) or boss.dead:
		return
	for h in boss.game.all_heroes():
		if not h.dead and _flat(h.global_position, p) < BOMB_R:
			h.take_hit(boss._roll() * 1.3, p, "nova", "fire")
	# his own goblins get caught in it too
	for e in boss.game.enemies_near(p, BOMB_R):
		if e != boss and not e.dead and e.hoard == self:
			e.take_damage(0.0, e.max_life * 0.6, p, 2.0, false)

## Which foe a sensible player hits right now (the balance bot and playtest use this).
func priority_target() -> Enemy:
	var best: Enemy = null
	var bd := INF
	for e in carrying.keys():
		if is_instance_valid(e) and not e.dead:
			var d := _flat(e.global_position, boss.global_position)
			if d < bd:
				bd = d
				best = e
	return best if best != null else boss

## Where a sensible player would step right now, or null: out of a bomb's circle, else onto
## the nearest pile during a scramble (the balance bot uses this).
func move_hint(from: Vector3) -> Variant:
	for b in bombs:
		var away: Vector3 = from - b
		away.y = 0.0
		if away.length() < BOMB_R + 0.6:
			if away.length() < 0.1:
				away = Vector3(1, 0, 0)
			return b + away.normalized() * (BOMB_R + 1.5)
	if state == "spill":
		var best: Variant = null
		var bd := 14.0
		for id in piles.keys():
			var d := _flat(from, piles[id]["pos"])
			if d < bd:
				bd = d
				best = piles[id]["pos"]
		return best
	return null

## He died: his goblins flee down their holes, the piles go, and his hoard bursts open.
func on_death() -> void:
	var g = boss.game
	for id in piles.keys():
		_take(id, false)
	for e in grabbers:
		if is_instance_valid(e) and not e.dead:
			e.die_visual()
			g.net.enemy_died(e)
	grabbers.clear()
	carrying.clear()
	boss._fx("outro")
	shout("My... gold...")
	if not g.net.is_client():
		for i in 8:
			g.drop_item(Items.gold(int(randf_range(10, 20) * (1.0 + boss.level * 0.6))), boss.global_position)

func shout(text: String) -> void:
	shout_cd = 5.0
	boss._fx("shout:" + text)

static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ---------------------------------------------------------------- what every player sees
## Enemy.special_fx hands the boss's events here. Returns true if it was one of ours.
func fx(ev: String) -> bool:
	var g = boss.game
	var root: Node3D = g.world.fx_root
	var a := ev.split(":")
	match a[0]:
		"pile":
			var id := int(a[1])
			var p := Vector3(float(a[2]), 0, float(a[3]))
			p.y = g.world.height_at(p.x, p.z)
			var node := Goblin.pile(int(a[4]))
			root.add_child(node)
			node.global_position = p
			node.scale = Vector3.ONE * 0.05
			piles[id] = {"pos": p, "amount": int(a[4]), "node": node, "by": null}
			# a stream of coins arcs from the burst sack to where the pile lands
			var from := boss.global_position + Vector3(0, boss.height * 1.5, 0)
			var coin := Models.P(root, Geo.cyl(0.07, 0.07, 0.02, 10), Goblin.gold_m(), from)
			var trail := Goblin.sparkle(coin, Vector3.ZERO, Color(1.0, 0.8, 0.3), 14, Vector3(0.05, 0.05, 0.05), 0.3, 0.5, -1.0)
			trail.local_coords = false
			var dur := randf_range(0.5, 0.8)
			var tw := coin.create_tween()
			tw.tween_method(func(u: float):
				if is_instance_valid(coin):
					coin.global_position = from.lerp(p, u) + Vector3(0, sin(u * PI) * 3.5, 0)
					coin.rotation = Vector3(u * 20.0, u * 7.0, 0), 0.0, 1.0, dur)
			tw.tween_callback(coin.queue_free)
			var tw2 := node.create_tween()
			tw2.tween_interval(dur)
			tw2.tween_property(node, "scale", Vector3.ONE * 1.15, 0.12)
			tw2.tween_property(node, "scale", Vector3.ONE, 0.1)
			tw2.tween_callback(func(): Sfx.play("gold", -8.0, randf_range(0.8, 1.1)))
			return true
		"pile_gone":
			var id := int(a[1])
			if piles.has(id):
				var node: Node3D = piles[id]["node"]
				if is_instance_valid(node):
					Fx.burst(root, node.global_position + Vector3(0, 0.3, 0), Color(1.0, 0.8, 0.3), 22, 3.0, 0.07, 0.6, true, -6.0)
					if a[2] == "1":
						Fx.number(root, node.global_position + Vector3(0, 1.2, 0), "+%d gold" % int(piles[id]["amount"]), Color(1.0, 0.85, 0.3))
					node.queue_free()
				piles.erase(id)
			return true
		"spill":
			sacks = int(a[1])
			boss.rig.set_meta("sacks", sacks)
			var at := boss.global_position + Vector3(0, boss.height * 1.4, 0) + boss.rig.global_transform.basis.z * 0.5
			Fx.burst(root, at, Color(1.0, 0.78, 0.25), 70, 7.0, 0.09, 1.3, true, -9.0, 50.0)
			Fx.burst(root, at, Color(0.45, 0.32, 0.18, 0.9), 24, 3.0, 0.14, 0.8, false, -5.0)
			Fx.flash(root, at, Color(1.0, 0.75, 0.3), 5.0, 0.5, 8.0)
			Sfx.play("coins", 0.0)
			g.add_shake(0.5)
			if not told:
				told = true
				g.ui.message("His sack bursts! His gold is his life: every pile you grab hurts him, every pile that reaches him heals him.", Color(1.0, 0.82, 0.35), 6.5)
			else:
				g.ui.message("Another sack bursts! Grab the gold!", Color(1.0, 0.82, 0.35), 3.0)
			return true
		"robbed":
			var top := boss.global_position + Vector3(0, boss.height * 2.0 + 0.4, 0)
			Fx.number(root, top, a[1] + "!", Color(1.0, 0.75, 0.2), true)
			Sfx.play("hurt", -2.0, 1.6)
			return true
		"feed":
			var top := boss.global_position + Vector3(0, boss.height * 2.0 + 0.4, 0)
			Fx.number(root, top, "+" + a[1], Color(0.55, 1.0, 0.4), true)
			Fx.burst(root, boss.global_position + Vector3(0, boss.height * 1.1, 0), Color(1.0, 0.8, 0.3), 30, 2.5, 0.08, 0.7, true, 1.0)
			Fx.ring(root, boss.global_position, 2.0, Color(1.0, 0.8, 0.3), 0.5)
			Sfx.play("gold", -2.0, 0.8)
			return true
		"bomb":
			_bomb_fx(Vector3(float(a[1]), 0, float(a[2])))
			return true
		"hole":
			var p := Vector3(float(a[1]), 0, float(a[2]))
			Fx.burst(root, p + Vector3(0, 0.3, 0), Color(0.3, 0.22, 0.14, 0.9), 26, 4.0, 0.14, 0.8, false, -8.0)
			Sfx.play("cackle", -8.0, randf_range(0.92, 1.02))
			return true
		"intro":
			met = true
			g.focus_on(boss, 2.6, 0.5)
			return true
		"outro":
			g.focus_on(boss, 3.0, 0.6)
			return true
		"shout":
			_shout_fx(ev.substr(6))
			return true
		"broke":
			g.ui.message("King Grubb is out of gold, and furious!", Color(1.0, 0.35, 0.2), 3.5)
			Sfx.play("roar", 0.0, 0.88)
			Fx.ring(root, boss.global_position, 4.0, Color(1.0, 0.3, 0.1), 0.6)
			_shout_fx("You'll pay for that. In BLOOD!")
			return true
	return false

func _bomb_fx(p: Vector3) -> void:
	var g = boss.game
	var root: Node3D = g.world.fx_root
	p.y = g.world.height_at(p.x, p.z)
	var J: Dictionary = boss.rig.get_meta("j")
	var from: Vector3 = (J["hand_l"] as Node3D).global_position if J.has("hand_l") else boss.global_position + Vector3(0, 2, 0)
	var b := Goblin.bomb()
	root.add_child(b)
	b.global_position = from
	Sfx.play("swing", -4.0, 0.7)
	var tw := b.create_tween()
	tw.tween_method(func(u: float):
		if is_instance_valid(b):
			b.global_position = from.lerp(p + Vector3(0, 0.2, 0), u) + Vector3(0, sin(u * PI) * 3.0, 0)
			b.rotation = Vector3(u * 9.0, 0, u * 4.0), 0.0, 1.0, BOMB_FLY)
	tw.tween_callback(func():
		Fx.telegraph(root, p, BOMB_R, BOMB_FUSE)
		Sfx.play("fuse", -6.0))
	tw.tween_interval(BOMB_FUSE)
	tw.tween_callback(func():
		Fx.ring(root, p, BOMB_R, Color(1.0, 0.55, 0.15), 0.45)
		Fx.burst(root, p + Vector3(0, 0.4, 0), Color(1.0, 0.5, 0.12), 50, 7.0, 0.22, 0.6, true, -2.0)
		Fx.burst(root, p + Vector3(0, 0.3, 0), Color(0.3, 0.27, 0.24, 0.85), 24, 3.5, 0.4, 1.0, false, 1.0)
		Fx.burst(root, p + Vector3(0, 0.3, 0), Color(1.0, 0.82, 0.3), 24, 6.0, 0.06, 0.8, true, -9.0)
		Fx.flash(root, p + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.2), 8.0, 0.35, 9.0)
		Fx.splat(root, p, Color(0.05, 0.04, 0.03), 1.6)
		Sfx.play("boom")
		g.add_shake(0.45)
		b.queue_free())

func _shout_fx(text: String) -> void:
	if shout_lbl == null or not is_instance_valid(shout_lbl):
		shout_lbl = Label3D.new()
		shout_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		shout_lbl.no_depth_test = true
		shout_lbl.font_size = 44
		shout_lbl.outline_size = 12
		shout_lbl.pixel_size = 0.006
		shout_lbl.modulate = Color(1.0, 0.82, 0.3)
		shout_lbl.outline_modulate = Color(0.12, 0.05, 0.0, 0.95)
		boss.add_child(shout_lbl)
	shout_lbl.position = Vector3(0, boss.height * 1.75 + 0.5, 0)
	shout_lbl.text = text
	shout_lbl.scale = Vector3.ONE * 0.4
	shout_lbl.modulate.a = 1.0
	var tw := shout_lbl.create_tween()
	tw.tween_property(shout_lbl, "scale", Vector3.ONE * 1.1, 0.12)
	tw.tween_property(shout_lbl, "scale", Vector3.ONE, 0.08)
	tw.tween_interval(1.8)
	tw.tween_property(shout_lbl, "modulate:a", 0.0, 0.5)
	Sfx.play("cackle", -3.0, randf_range(0.86, 0.94))
