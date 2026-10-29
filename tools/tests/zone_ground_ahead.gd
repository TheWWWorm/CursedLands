extends Node
## After the zone message a client focuses its camera where the local hero's
## record stands before it spawns the host's units (_prepare_ground_ahead),
## so the ground colour pages of that view can bake meanwhile; the start view
## after the spawn agrees with that early focus, records without a local
## hero leave the rig alone, and headless (no display) no colour cache is made.
var checks := 0
var failures: Array[String] = []

class ProbeMain extends "res://src/main.gd":
	func _ready() -> void: pass

## Records the rig's look-at and camera when the first host unit spawns.
class ProbeSession extends Session:
	var spawned := 0
	var first_look_at: Variant = null
	var first_camera: Variant = null
	var first_units := -1
	func _spawn_record(r: Dictionary) -> GameUnit:
		if spawned == 0 and game and game.rig:
			first_look_at = game.rig.position
			first_camera = game.rig.camera.global_position if game.rig.camera else null
			first_units = world.units.size() if world else -1
		spawned += 1
		return super(r)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func records_of(w: GameWorld, n: int) -> Array:
	var out := []
	for r: Dictionary in w.map.unit_records:
		if not r.get("position") is Vector3:
			continue
		var copy := r.duplicate(true)
		copy.nid = 7000 + out.size()
		copy.controller = -1
		out.append(copy)
		if out.size() == n:
			break
	return out

## Horizontal (EI x/y, Godot x/z) distance between two look-at points: the
## look-at's height is the terrain's / the modern camera's lift by design.
static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _run() -> void:
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "auto_graphics": 0, "net_upnp": 0, "net_lan": 0, "net_directory": 0}, true)
	var main := ProbeMain.new()
	get_tree().root.add_child(main)
	var s := ProbeSession.new()
	main.session = s
	main.add_child(s)
	var game := Game.new()
	game.session = s
	s.game = game
	main.game = game
	main.add_child(game)
	await get_tree().process_frame
	var z1 := s.campaign.zone("gz1g")
	check(not z1.is_empty() and s.zone_exists("gz1g") and game.rig != null and game.rig.camera != null, "fixture zone exists and the game has a camera rig")

	# 1. The world built ahead, three of its unit records; the first one is
	# the local player's hero, standing at its map position.
	s._rpc_zone_ahead("gz1g", String(z1.mpr))
	var ahead: GameWorld = s._ahead_world
	check(ahead != null and is_instance_valid(ahead) and ahead.terrain != null, "the announcement builds the world ahead")
	var records := records_of(ahead, 3) if ahead else []
	check(records.size() == 3, "three unit records with positions to spawn")
	if records.size() < 3 or ahead == null:
		_finish(main)
		return
	var hero_rec: Dictionary = records[0]
	var ei: Vector3 = hero_rec.position
	hero_rec.controller = s.my_index
	hero_rec.position = Vector3(ei.x, ei.y, 0.0)
	var expected := EISpace.pos(ei.x, ei.y, ahead.terrain.height_at(ei.x, ei.y))
	check(s.my_index == 0 and int(records[1].controller) == -1 and int(records[2].controller) == -1, "only the first record belongs to the local player")

	# 2. The zone message: the rig is focused on the hero's record before the
	# first unit spawns.
	var before: Vector3 = game.rig.position
	check(flat_distance(before, expected) > 2.0, "the rig's look-at starts away from the hero's record")
	s._rpc_zone("gz1g", records, PackedInt32Array(), [], "", {})
	check(s.spawned == 3 and s.first_look_at is Vector3 and s.first_units == 0, "the probe saw the first spawn into an empty world")
	if s.first_look_at is Vector3:
		var first: Vector3 = s.first_look_at
		check(flat_distance(first, expected) <= 2.0,
			"the look-at was at the hero's record before any unit spawned (%.2f units away)" % flat_distance(first, expected))
		check(flat_distance(first, before) > 2.0, "the early focus moved the look-at from where it was before the zone message")
		check(s.first_camera is Vector3 and flat_distance(s.first_camera, first) <= CameraRig.MAX_DISTANCE + 2.0
			and (s.first_camera as Vector3).distance_to(first) > 0.5, "the camera stood behind that look-at before the first spawn")

	# 3. After the message: the host's units exist, the start view after the
	# spawn agrees with the early focus, and headless no colour cache was made.
	check(s.world == ahead and game.world == ahead and ahead.units.size() == 3, "the zone message spawned the host's three units")
	var hero: GameUnit = null
	for u: GameUnit in ahead.units.values():
		if u.controller == s.my_index:
			hero = u
	check(hero != null, "the local player's hero unit exists")
	if hero:
		check(flat_distance(game.rig.position, hero.position) <= 2.0 and flat_distance(hero.position, expected) <= 2.0,
			"the final look-at is on the hero, where the early focus went (%.2f / %.2f units)" % [flat_distance(game.rig.position, hero.position), flat_distance(hero.position, expected)])
		check(game.my_units().size() == 1 and game.my_units()[0] == hero, "the hero is the local player's only unit")
	check(not is_instance_valid(ahead.terrain.color_cache), "no terrain colour cache is created without a display")

	# 4. Records without a local-player record leave the rig alone.
	var others := []
	for r: Dictionary in records:
		var copy := r.duplicate(true)
		copy.controller = -1
		others.append(copy)
	var kept: Vector3 = game.rig.position
	s._prepare_ground_ahead(z1, others)
	check(game.rig.position == kept, "records without the local player's unit do not move the rig")
	s._prepare_ground_ahead(z1, [])
	check(game.rig.position == kept, "an empty record list does not move the rig")
	var size: Vector2 = ahead.terrain.size_ei()
	var centre := EISpace.pos(size.x * 0.5, size.y * 0.5, ahead.terrain.height_at(size.x * 0.5, size.y * 0.5))
	game.rig.focus(centre)
	var moved: Vector3 = game.rig.position   # focus(centre) within the zone's look-at limit
	s._prepare_ground_ahead(z1, records)
	check(flat_distance(moved, expected) > 2.0 and flat_distance(game.rig.position, expected) <= 2.0,
		"the hero's record takes the rig from the map centre back to the hero (%.2f units away)" % flat_distance(game.rig.position, expected))

	# 5. _hero_record_position.
	check(s._hero_record_position([]) == null, "no record position for an empty list")
	check(s._hero_record_position([{"controller": 0}, {"controller": 0, "position": "x"}]) == null, "no record position for records without a Vector3 position")
	check(s._hero_record_position([{"controller": -1, "position": Vector3(ei.x, ei.y, 0.0)}, {"controller": 1, "position": Vector3(ei.x, ei.y, 0.0)}]) == null,
		"no record position when none belongs to the local player")
	var got: Variant = s._hero_record_position(others + [hero_rec])
	check(got is Vector3 and (got as Vector3).is_equal_approx(expected), "the hero record's world position is EISpace.pos(x, y, terrain height)")
	var tagged := {"controller": "0", "position": Vector3(ei.x, ei.y, 5.0)}
	got = s._hero_record_position([tagged])
	check(got is Vector3 and (got as Vector3).is_equal_approx(expected), "a controller string and the record's own z are read as the local player's record on the ground")

	# 6. CameraRig.village_start_view(zone, at): a field zone returns false
	# before any focus (_prepare_ground_ahead then focuses itself); a village
	# without a unit of the local player focuses on `at`; with the hero it
	# focuses on the hero, not `at`.
	var field := z1.duplicate()
	field.type = "game"
	var village := z1.duplicate()
	village.type = "brief"
	village.erase("camera")   # no opening view file: only the hero / `at` focus
	var mine := s.my_index
	s.my_index = 7   # no unit of this index: a Game without the local player's units
	check(game.my_units().is_empty(), "a foreign player index has no units in the world")
	game.rig.focus(expected)
	var still: Vector3 = game.rig.position
	check(not game.rig.village_start_view(field, moved) and game.rig.position == still,
		"a field zone returns false and leaves the focus to the caller")
	var applied: bool = game.rig.village_start_view(village, moved)
	check(not applied and flat_distance(game.rig.position, moved) <= 2.0,
		"without local units the village start view focuses on `at` (%.2f units away)" % flat_distance(game.rig.position, moved))
	game.rig.focus(expected)
	still = game.rig.position
	check(not game.rig.village_start_view(village, "nowhere") and game.rig.position == still, "a non-Vector3 `at` leaves the rig alone")
	s.my_index = mine
	applied = game.rig.village_start_view(village, moved)
	check(not applied and flat_distance(game.rig.position, expected) <= 2.0 and flat_distance(game.rig.position, moved) > 2.0,
		"with the hero spawned the village start view focuses on the hero, not `at`")
	_finish(main)

func _finish(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	print("ZONE_GROUND_AHEAD ", checks, " checks ", failures.size(), " failures")
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
