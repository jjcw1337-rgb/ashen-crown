class_name PoisonMushroom
extends BossBrain
## A Poison Mushroom (kind spore_shroom): stands where it sprang up, breathing its cloud (POISON_R) every 1.5 s. Its
## body is the Verdant Reach's fungus prop (Monsters.build_rig, the def's "prop"). Mossbeard's (his pack) wither
## when he dies; another camp's are just monsters.

const POISON_R := 3.0

var _pulse := 0.0
var _had_maker := false        # a hermit of its pack was seen (see update)

func update(delta: float, _hero: Node3D, _to: Vector3, _dist: float, _gone: bool) -> Vector3:
	_pulse -= delta
	if _pulse <= 0.0:
		_pulse = 1.5
		# its maker gone, it withers. `_had_maker` remembers he was there: once he is dead his body leaves the tree,
		# and "no hermit in the pack" must not read as "never had one"
		var kin: Array = e.game.world.enemies_root.get_children().filter(func(x) -> bool: return x is Enemy and x.kind == "hermit" and x.pack_id == e.pack_id)
		if not kin.is_empty():
			_had_maker = true
		var maker: bool = (not _had_maker) or kin.any(func(x) -> bool: return not x.dead and x.global_position.distance_to(e.global_position) < 40.0)
		if not maker:
			e.take_damage(99999.0, 0.0, e.global_position, 0.0, false)
			return Vector3.ZERO
		e._fx("bb_cloud")
		for h in heroes_in(e.global_position, POISON_R):
			h.take_hit(e.roll(), e.global_position, "burn", "poison")
	return Vector3.ZERO
