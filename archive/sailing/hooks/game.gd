## Not a script: the Game methods and fields sailing had in scripts/game.gd, cut out whole when sailing was archived
## (2026-11-06), so they can be pasted back into Game. REVIVE.md lists where each was called from.

## The boat in this zone (coast.gd / isles.gd zones; BoatRide): moored, or sailing with the hero aboard.
var boat: BoatRide = null
var sail_blend := 0.0          # 0 = the isometric camera, 1 = the sailing camera behind and above her
var sail_cam_yaw := 0.0
var water_pt := Vector3.ZERO   # where the mouse meets the sea's surface (steering by mouse)

## In a sea zone the surf bed follows the shore: full on the beach, fading inland and out at sea (the boat's
## own `sea` bed takes over out there, BoatRide._sounds).
func _sea_sounds() -> void:
	if world == null or not world.sea or Sfx.ambience == null:
		return
	var p := hero.global_position
	var d := 0.0
	var oc: Ocean = world.get_node_or_null("Ocean")
	if oc and oc.depth_at(p.x, p.z) > 0.3:
		d = oc.shore_at(p.x, p.z)                                 # out on the water: how far from land
	elif cur_zone.begins_with("isle_"):
		var isle := Isles.get_isle(Isles.id_of(cur_zone))
		d = maxf(0.0, float(isle.get("r", 100.0)) - Vector2(p.x, p.z).length() - 10.0)   # inland
	else:
		d = maxf(0.0, absf(p.x - Coast.shore_x(p.z)) - 10.0)
	var want := -4.0 - clampf((d - 8.0) / 70.0, 0.0, 1.0) * 18.0
	Sfx.ambience.volume_db = move_toward(Sfx.ambience.volume_db, want, get_process_delta_time() * 6.0)

## The coast and the islands: a long golden evening over the sea. The sun hangs low in the west over
## the open water so the waves catch it in a glittering path, the sky warms to amber at the horizon,
## and the air is clear enough to see the far islands as hazy blue silhouettes.
func _sea_env() -> void:
	sky_mat.sky_top_color = Color(0.22, 0.32, 0.46)
	sky_mat.sky_horizon_color = Color(0.86, 0.66, 0.46)
	# below the horizon the sky is what wave backs reflect at low angles: keep it close to the horizon so
	# the far water doesn't streak dark
	sky_mat.ground_horizon_color = Color(0.8, 0.64, 0.48)
	sky_mat.ground_bottom_color = Color(0.46, 0.5, 0.54)
	sky_mat.sun_angle_max = 22.0
	env.ambient_light_energy = 0.62
	env.tonemap_exposure = 1.1
	env.fog_light_color = Color(0.62, 0.6, 0.56)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.25
	env.fog_height = 0.0
	env.fog_height_density = 0.0
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.07
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.82, 0.72)
	env.volumetric_fog_emission = Color(0.02, 0.016, 0.012)
	env.glow_intensity = 0.8
	env.glow_bloom = 0.07
	sun.rotation_degrees = Vector3(-24, -112, 0)
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 1.15
	hero.light.light_energy = 0.7
	_isle_mood()
	_ocean_light()

## An island with a "mood" in Isles.ISLANDS (the Bleak Isle) has its own water and air in its zone.
func _isle_mood() -> void:
	if not cur_zone.begins_with("isle_"):
		return
	var isle := Isles.get_isle(cur_zone.trim_prefix("isle_"))
	if isle.is_empty() or not isle.has("mood"):
		return
	var m: Dictionary = isle["mood"]
	sky_mat.sky_top_color = m["sky_top"]
	sky_mat.sky_horizon_color = m["horizon"]
	sky_mat.ground_horizon_color = m["horizon"]
	sky_mat.ground_bottom_color = (m["horizon"] as Color).darkened(0.3)
	env.fog_light_color = m["fog"]
	env.fog_density = m["fog_density"]
	env.fog_sky_affect = 0.6
	env.fog_height = m["fog_height"]
	env.fog_height_density = m["fog_height_density"]
	env.volumetric_fog_albedo = m["vol_albedo"]
	env.volumetric_fog_density = m["vol_density"]
	env.volumetric_fog_emission = Color(0.01, 0.014, 0.01)
	env.adjustment_saturation = m["sat"]
	env.adjustment_contrast = m["contrast"]
	env.ambient_light_energy = m["ambient"]
	env.glow_intensity = 0.5
	sun.light_color = m["sun"]
	sun.light_energy = m["sun_energy"]
	if world and world.has_node("Ocean"):
		(world.get_node("Ocean") as Ocean).set_tint(m["shallow"], m["deep"], m["absorb"])

## Hands the sea the sun and the sky's colour (Ocean.set_light).
func _ocean_light() -> void:
	if world == null or not world.has_node("Ocean"):
		return
	(world.get_node("Ocean") as Ocean).set_light(sun.global_basis.z, sun.light_color * sun.light_energy, sky_mat.sky_horizon_color.lerp(sky_mat.sky_top_color, 0.5))

## A sea zone (the coast, an island) gets the ocean: its map covers the whole sea on the coast
## (2 m cells) and the island's waters on an island (1 m).
func _add_ocean(zone: String) -> void:
	sun.rotation_degrees = SUN_DEFAULT
	sky_mat.ground_bottom_color = Color(0.16, 0.18, 0.15)
	sky_mat.sun_angle_max = 30.0
	cam.far = 300.0
	if not world.sea:
		return
	cam.far = 900.0
	var oc := Ocean.new()
	var r: Rect2 = world.get_meta("sea_rect") if zone == "coast" else world.bounds.grow(World.MARGIN + 28.0 + Ocean.MAP_MARGIN)
	world.add_child(oc)
	oc.setup(world, r, 2.0 if zone == "coast" else 1.0, quality, is_forward(), zone)

## The coast's corner map is a sea chart painted from the sea's ground (Coast.ground through the zone's
## height grid): the deep and the shallows, sand, land shaded by height, cliffs and the isles, from the
## pier out past all five, with no fog (a chart is already known). Made once a session (2 m a pixel).
static var _chart_tex: Texture2D
static var _chart_rect: Rect2
func _sea_chart() -> void:
	if _chart_tex == null:
		var r: Rect2 = world.bounds
		for isle in Isles.ISLANDS:
			var ce := Isles.centre(isle)
			var rr := float(isle["r"]) * 1.2
			r = r.merge(Rect2(ce - Vector2(rr, rr), Vector2(rr, rr) * 2.0))
		r = r.grow(20.0)
		var step := 2.0
		var w := int(r.size.x / step)
		var h := int(r.size.y / step)
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		var hs := PackedFloat32Array()
		hs.resize(w * h)
		for y in h:
			for x in w:
				hs[y * w + x] = world.ground_h(r.position.x + (x + 0.5) * step, r.position.y + (y + 0.5) * step)
		for y in h:
			for x in w:
				var g: float = hs[y * w + x]
				var gx: float = hs[y * w + mini(x + 1, w - 1)] - hs[y * w + maxi(x - 1, 0)]
				var gy: float = hs[mini(y + 1, h - 1) * w + x] - hs[maxi(y - 1, 0) * w + x]
				var slope: float = sqrt(gx * gx + gy * gy) / (2.0 * step)
				var c: Color
				if g < 0.0:
					# water: pale turquoise shallows to dark deep, a lighter rim right at the shore
					var dk := clampf(-g / 16.0, 0.0, 1.0)
					c = Color(0.22, 0.46, 0.46).lerp(Color(0.05, 0.12, 0.17), sqrt(dk))
					if g > -0.8:
						c = c.lerp(Color(0.62, 0.7, 0.62), 0.45)
				elif g < 1.3 and slope < 0.5:
					c = Color(0.62, 0.56, 0.42)                              # sand
				else:
					c = Color(0.26, 0.32, 0.17).lerp(Color(0.42, 0.4, 0.28), clampf(g / 24.0, 0.0, 1.0))
					c = c.lerp(Color(0.2, 0.19, 0.18), clampf(slope * 0.9, 0.0, 0.85))    # cliffs
					c = c.darkened(clampf(gx * 0.08, -0.15, 0.25))           # light from the west
				img.set_pixel(x, y, c)
		img.generate_mipmaps()
		_chart_tex = ImageTexture.create_from_image(img)
		_chart_rect = Rect2(r.position, Vector2(w, h) * step)
	ui.minimap.set_map(_chart_tex, _chart_rect, false)
	ui.minimap.chart = true

# ---------------------------------------------------------------- the boat (boat_ride.gd)
func sailing() -> bool:
	return boat != null and is_instance_valid(boat) and boat.sailing

## A sea zone's boat. On the coast she lies alongside the pier (for sale until the hero owns her); if he
## arrives sailing from an island ("sail_from_<id>") she's off that island's jetty with him at the tiller.
## On an island she's moored at its jetty: boarding her sails him back out onto the Mournwater.
func _add_boat(zone: String, spawn: String) -> void:
	boat = null
	sail_blend = 0.0
	hero.aboard = false
	ui.set_sail_prompt("")
	if not world.sea:
		return
	var b := BoatRide.new()
	world.add_child(b)
	b.setup(self, hero.best_boat())
	boat = b
	if zone == "coast":
		b.docks.append({"name": "the pier", "kind": "pier", "pos": Vector2(Coast.MOOR.x, Coast.MOOR.z), "yaw": PI * 0.5})
		for isle in Isles.ISLANDS:
			var m := isle_mooring(isle, Vector2.ZERO, true)
			b.docks.append({"name": isle["name"], "kind": "isle", "id": isle["id"], "pos": Vector2(m.x, m.z), "yaw": m.w, "level": int(isle.get("level", 0))})
		if spawn.begins_with("sail_from_") and hero.boats.is_empty():
			# a partner brought along by the party's trip with no boat of his own: he's set down on the pier
			b.moor(Coast.MOOR, PI * 0.5)
			var dp: Vector3 = world.spawns.get("dock", Vector3(2, 0, 0))
			hero.global_position = Vector3(dp.x, world.height_at(dp.x, dp.z), dp.z)
			cam_target = hero.global_position
		elif spawn.begins_with("sail_from_"):
			var isle := Isles.get_isle(spawn.trim_prefix("sail_from_"))
			var m := isle_mooring(isle, Vector2.ZERO, true)
			# the whole party sails out together: each his own boat, the others a few lengths further out ahead
			var r := _party_rank()
			# spaced for the longest boat any of them may sail (each game knows only its own)
			var gap := 9.0
			for bid in Data.BOATS:
				gap = maxf(gap, 9.0 * float(Boat.dims(str(bid))["length"]) / Boat.LENGTH)
			var off := Vector3(-sin(m.w), 0, -cos(m.w)) * gap * float(r)
			b.moor(Vector3(m.x, 0, m.z) + off, m.w)
			b.board(hero)
			sail_blend = 1.0
			sail_cam_yaw = b.yaw
			cam_target = b.global_position
		else:
			b.moor(Coast.MOOR, PI * 0.5)
	else:
		var isle := Isles.get_isle(Isles.id_of(zone))
		var m := isle_mooring(isle, Vector2.ZERO, false)
		b.moor(Vector3(m.x, 0, m.z), m.w)

## This player's place in the party (0 = the lowest peer id), so things placed per player don't overlap.
func _party_rank() -> int:
	if net == null or not net.active or multiplayer.multiplayer_peer == null:
		return 0
	var me := multiplayer.get_unique_id()
	var r := 0
	for pid in net.players.keys():
		if int(pid) < me:
			r += 1
	return r

## Where a boat lies at an island's jetty (alongside its end), bow out toward the dock: x, z and her
## yaw in w. `coast`: in the coast's frame; else in the island's own zone (the island at the origin).
func isle_mooring(isle: Dictionary, _o: Vector2, coast: bool) -> Vector4:
	var l := Isles.jetty_end(isle) + Vector2(-3.0, 3.4)
	var p := Isles.to_coast(isle, l)
	if not coast:
		p -= Isles.centre(isle)
	var u: Vector2 = Isles.axes(isle)[0]
	return Vector4(p.x, 0.0, p.y, atan2(-u.x, -u.y))

func _boat_clicked() -> void:
	if boat == null:
		return
	if not hero.owns_boat(boat.id):
		ui.message("That's Osric's boat. Talk to him if you want her.", Color(0.85, 0.75, 0.5))
		return
	if cur_zone.begins_with("isle_"):
		# back out to sea: the coast loads with her off this island's jetty and him at the tiller
		travel(cur_act, "coast", "sail_from_" + Isles.id_of(cur_zone))
		return
	boat.board(hero)
	Sfx.play("click")
	if not hero.sailed:
		hero.sailed = true
		ui.open_dialog("Sailing", "W  sail on; she holds her speed when you let go.\nS  ease off, then back her.\nA / D  steer.   Space  heave to.\nOr hold the left mouse button on the water to sail toward it.\n\nBring her alongside an island's jetty (or back to this pier), slow, and press E to step ashore.", [["Cast off", func(): pass]])
	else:
		ui.message("Cast off: W to sail, A / D to steer", Color(0.75, 0.88, 1.0))

## Keys and mouse to the boat while sailing.
func _sail_input() -> void:
	var thr := 0
	if Input.is_key_pressed(KEY_W): thr += 1
	if Input.is_key_pressed(KEY_S): thr -= 1
	var steer := 0.0
	if Input.is_key_pressed(KEY_A): steer -= 1.0
	if Input.is_key_pressed(KEY_D): steer += 1.0
	var pt: Variant = null
	if lmb_held and not ui.any_panel_open():
		_update_hover()
		pt = water_pt
	boat.drive = {"throttle": thr, "steer": steer, "stop": Input.is_key_pressed(KEY_SPACE), "point": pt}
	var d := boat.dock_near()
	ui.set_sail_prompt(_ashore_prompt(d))

## Steps ashore where she is, if she's at a dock and slow (E, or the prompt's button).
func try_land() -> bool:
	if not sailing():
		return false
	var d := boat.dock_near()
	if d.is_empty():
		ui.message("Bring her alongside a jetty first, and slow", Color(0.75, 0.88, 1.0))
		return false
	var need := int(d.get("level", 0))
	if hero.level < need and not test_allskills:
		ui.message("%s is for heroes of level %d and up (you're %d)" % [d["name"], need, hero.level], Color(1.0, 0.6, 0.35))
		Sfx.play("deny")
		return false
	land_boat(d)
	return true

## The sail prompt at a dock: where, and the level it asks for.
func _ashore_prompt(d: Dictionary) -> String:
	if d.is_empty():
		return ""
	var need := int(d.get("level", 0))
	if need > 0 and hero.level < need and not test_allskills:
		return "%s (level %d: you're %d)" % [d["name"], need, hero.level]
	return "Step ashore at " + str(d["name"])

func land_boat(d: Dictionary) -> void:
	ui.set_sail_prompt("")
	boat.leave(hero)
	if d["kind"] == "pier":
		boat.moor(Coast.MOOR, PI * 0.5)
		var on := Vector3(Coast.DOCK.x + 1.0, 0, -0.6)
		hero.global_position = Vector3(on.x, world.height_at(on.x, on.z), on.z)
		cam_target = hero.global_position
	else:
		travel(cur_act, Isles.zone_of(d["id"]), "jetty")

## The sailing camera: behind her and high, looking past the bow to the horizon so the isles show
## ahead; it eases in when he takes the tiller and back to the isometric view when he steps ashore.
func _sail_camera(dt: float, sh: Vector3) -> void:
	var want := 1.0 if sailing() else 0.0
	sail_blend = move_toward(sail_blend, want, dt / 1.3)
	if sail_blend <= 0.0:
		cam.basis = Basis.looking_at(Vector3(0, 1.0, 0) - cam.position, Vector3.UP)    # (turned by the orbit, if any)
		return
	if boat == null or not is_instance_valid(boat):
		return
	sail_cam_yaw = lerp_angle(sail_cam_yaw, boat.yaw, clampf(dt * 1.6, 0.0, 1.0))
	var f := Vector3(-sin(sail_cam_yaw), 0, -cos(sail_cam_yaw))
	var bp := Vector3(boat.global_position.x, 0, boat.global_position.z)
	cam_target = bp
	cam_pivot.position = bp
	var k := smoothstep(0.0, 1.0, sail_blend)
	var iso_pos := cam_pivot.global_position + CAM_OFFSET * zoom
	var iso_look := cam_pivot.global_position + Vector3(0, 1.0, 0)
	# over her port quarter, so the sail doesn't hide the way ahead and he's in view at the tiller
	var sd := Vector3(cos(sail_cam_yaw), 0, -sin(sail_cam_yaw))
	# framed for the Gull; a bigger boat (BoatRide.kl, her length against the Gull's) pulls the camera back with her
	var bk: float = boat.kl
	var sail_pos := bp + (-f * 16.0 * zoom - sd * 5.5 * zoom + Vector3(0, 7.0 * zoom, 0)) * bk
	var sail_look := bp + (f * 11.0 + sd * 1.0 + Vector3(0, 0.3, 0)) * bk
	cam.global_position = iso_pos.lerp(sail_pos, k) + sh
	cam.look_at(iso_look.lerp(sail_look, k), Vector3.UP)

## Osric Saltmarrow, the shipwright on the Mournwater Coast: a word about the isles, then his boat
## (BoatShop). Once you own her, he tells you where she's moored.
func _shipwright_talk(t: Inter) -> void:
	var owned := not hero.boats.is_empty()
	var txt := "The Mournwater, they call it. Five isles out there, each a fair sail: the Verdant Isle with its great oak, the old ruins on their terraces, the Lost Isle with its black stone, the Bleak Isle where the fog never lifts, and the Merchant's Reach, empty since the night its people left. No bridge, no ferry. A boat, or nothing. I've built a good one."
	if owned:
		txt = "She's lying alongside the pier, ready when you are. Mind the rocks off the Bleak Isle, and bring her back in one piece."
	# one button per boat in Data.BOATS, cheapest first
	var ids: Array = Data.BOATS.keys()
	ids.sort_custom(func(a, b): return int(Data.BOATS[a]["price"]) < int(Data.BOATS[b]["price"]))
	var btns: Array = []
	for id in ids:
		var bid := str(id)
		var nm := str(Data.BOATS[bid]["name"])
		btns.append([("Look over " if hero.owns_boat(bid) else "See ") + nm, func(): ui.boat_shop.open(t, bid)])
	btns.append(["Leave", func(): pass])
	ui.open_dialog(t.label, txt, btns)

## Buys a boat (Data.BOATS) from the shipwright: pays, owns it from now on (saved with the character).
func buy_boat(id: String) -> bool:
	var spec: Dictionary = Data.BOATS[id]
	var price := int(spec["price"])
	if hero.owns_boat(id) or hero.gold < price:
		return false
	hero.gold -= price
	hero.boats.append(id)
	hero.stats_changed.emit()
	Sfx.play("gold")
	ui.big_message("%s is yours" % spec["name"])
	ui.message("She's moored at the end of the pier. Click her to go aboard.", Color(0.75, 0.88, 1.0), 4.0)
	save_game()
	# a better boat takes the old one's place at the dock (not while he's out sailing)
	if boat != null and is_instance_valid(boat) and not hero.aboard and boat.id != hero.best_boat():
		boat.queue_free()
		if boat.inter != null and is_instance_valid(boat.inter):
			boat.inter.queue_free()
		_add_boat(cur_zone, "")
	return true
