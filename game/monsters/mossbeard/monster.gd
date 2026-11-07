extends RefCounted
## Old Mossbeard (boss) and his Poison Mushrooms: its card (the monster registry, game/monsters/monsters.gd, reads it; see game/monsters/README.md).

const KINDS := ["hermit", "spore_shroom"]

## Its Meshy models' rigs, by the def's "mesh" (MeshyMonster.build): the joints rig_monster.py measured, written here by
## tools/blender/act1/layout_to_gd.py.
const RIGS := {
	# rigs begin
	"hermit": {"glb": "res://game/monsters/mossbeard/hermit.glb", "height": 1.45, "layout": {"hips": ["", Vector3(0.0, 0.3408, -0.0654)], "torso": ["hips", Vector3(0.0, 0.4278, -0.0654)], "head": ["torso", Vector3(0.0, 1.1165, 0.0575)], "sh_r": ["torso", Vector3(0.1879, 0.986, -0.0165)], "el_r": ["sh_r", Vector3(0.3413, 0.8216, -0.0417)], "hand_r": ["el_r", Vector3(0.4829, 0.6698, -0.065)], "sh_l": ["torso", Vector3(-0.1879, 0.986, -0.0067)], "el_l": ["sh_l", Vector3(-0.3384, 0.8178, -0.0383)], "hand_l": ["el_l", Vector3(-0.4772, 0.6625, -0.0675)], "leg_r": ["hips", Vector3(0.0994, 0.3408, 0.0401)], "knee_r": ["leg_r", Vector3(0.1374, 0.182, 0.0468)], "leg_l": ["hips", Vector3(-0.0923, 0.3408, 0.0454)], "knee_l": ["leg_l", Vector3(-0.1286, 0.1817, 0.0295)]}},
	# rigs end
}

static func brain(e: Enemy) -> BossBrain:
	return Mossbeard.new(e) if e.kind == "hermit" else PoisonMushroom.new(e)

static func fx(e: Enemy, ev: String) -> bool:
	if not ev.begins_with("bb_"):
		return false
	MossbeardFx.fx(e, ev)
	return true

## A mushroom is a thing that grows rather than walks: the Verdant Reach's fungus prop (the def's "prop"), pulsing.
static func build_rig(kind: String, _variant: int) -> Node3D:
	var d: Dictionary = Data.ENEMIES[kind]
	if not d.has("prop"):
		return null
	var look: Dictionary = d["look"]
	var pr := Node3D.new()
	pr.set_meta("static_prop", true)
	var pp := "res://game/maps/verdant_reach/props/%s.glb" % str(d["prop"])
	var m: Node3D = (load(pp) as PackedScene).instantiate() if ResourceLoader.exists(pp) else null
	if m == null:
		m = Models.crawler(look)
	m.name = "body"
	m.scale = Vector3.ONE * float(look.get("prop_scale", 1.0))
	pr.add_child(m)
	return pr

static func pose_rig(r: Node3D, st: Dictionary, _height: float) -> bool:
	if not r.has_meta("static_prop"):
		return false
	var b := r.get_node_or_null("body") as Node3D
	if b != null:
		# the breathing pulse round its own size, kept from the first pose: scaling from the current scale every
		# frame compounded (~1% a frame) and grew the hermit's mushrooms past the camera within minutes, one
		# giant cap's shadow over the map (Blaine, 2026-11-06)
		if not b.has_meta("base_scale"):
			b.set_meta("base_scale", b.scale)
		var t := float(st.get("time", 0.0))
		var k := 1.0 + sin(t * 2.6) * 0.04
		b.scale = (b.get_meta("base_scale") as Vector3) * Vector3(k, 2.0 - k, k)
	return true
