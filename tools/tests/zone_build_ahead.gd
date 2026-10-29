extends Node
## A client builds its presentation world when the host announces the zone it
## is about to build (_rpc_zone_ahead), and _rpc_zone then takes that world
## instead of building a second one; a world built for another zone or map,
## a replaced one and the session's teardown free it; a deferred loading
## screen (messages held) keeps the old order.
var checks := 0
var failures: Array[String] = []

class ProbeMain extends "res://src/main.gd":
	func _ready() -> void: pass

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
		var copy := r.duplicate(true)
		copy.nid = 7000 + out.size()
		copy.controller = -1
		out.append(copy)
		if out.size() == n:
			break
	return out

func _run() -> void:
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "auto_graphics": 0, "net_upnp": 0, "net_lan": 0, "net_directory": 0}, true)
	var main := ProbeMain.new()
	get_tree().root.add_child(main)
	var s := Session.new()
	main.session = s
	main.add_child(s)
	var game := Game.new()
	game.session = s
	s.game = game
	main.game = game
	main.add_child(game)
	await get_tree().process_frame
	var z1 := s.campaign.zone("gz1g")
	var z2 := s.campaign.zone("gz2g")
	check(not z1.is_empty() and not z2.is_empty() and s.zone_exists("gz1g") and s.zone_exists("gz2g"), "fixture zones exist")

	# 1. The announcement builds the presentation world without touching the
	# session's world; the host's zone message then takes it.
	var t0 := Time.get_ticks_msec()
	s._rpc_zone_ahead("gz1g", String(z1.mpr))
	var ahead_ms := Time.get_ticks_msec() - t0
	var ahead: GameWorld = s._ahead_world
	check(ahead != null and is_instance_valid(ahead), "the announcement builds a world ahead")
	check(s.world == null, "the world built ahead does not replace the session's world")
	if ahead:
		check(ahead.zone.get("id", "") == "gz1g" and ahead.presentation and not ahead.authority and ahead.units.is_empty() and ahead.terrain != null,
			"the world built ahead is the client's presentation world of the zone, without units")
		check(not ahead.is_inside_tree(), "the world built ahead waits outside the tree")
		check(s._ahead_zone == ["gz1g", String(z1.mpr)], "the zone and map it was built for are remembered")
	var records := records_of(ahead, 3) if ahead else []
	check(records.size() == 3, "three unit records to spawn")
	t0 = Time.get_ticks_msec()
	s._rpc_zone("gz1g", records, PackedInt32Array(), [], "", {})
	var zone_ms := Time.get_ticks_msec() - t0
	check(s.world == ahead and game.world == ahead, "the zone message takes the world built ahead")
	check(s._ahead_world == null and s._ahead_zone.is_empty(), "the taken world is no longer held ahead")
	if ahead and is_instance_valid(ahead):
		check(ahead.is_inside_tree() and ahead.visible and ahead.units.size() == 3, "the taken world is attached with the host's units spawned")
	check(zone_ms < ahead_ms, "the zone message finishes faster than the build it skipped (%d < %d ms)" % [zone_ms, ahead_ms])
	print("AHEAD_TIMING ahead=%d ms zone=%d ms" % [ahead_ms, zone_ms])

	# 2. A world built for another zone is discarded by the zone message,
	# which builds the zone it names.
	s._rpc_zone_ahead("gz1g", String(z1.mpr))
	var stale: GameWorld = s._ahead_world
	check(stale != null and stale != ahead, "a second announcement builds a new world ahead")
	s._rpc_zone("gz2g", [], PackedInt32Array(), [], "", {})
	check(not is_instance_valid(stale), "a world built ahead for another zone is freed")
	check(s.world != null and s.world.zone.get("id", "") == "gz2g" and s._ahead_world == null, "the zone message built the zone it names")
	await get_tree().process_frame   # Game.attach_world queue_frees the old world
	check(not is_instance_valid(ahead), "the previous zone's world was torn down as before")

	# 3. A new announcement replaces a world built ahead; a map name that
	# differs from the announced one is a mismatch too.
	s._rpc_zone_ahead("gz2g", String(z2.mpr))
	var first: GameWorld = s._ahead_world
	var first_id := first.get_instance_id() if first else 0
	s._rpc_zone_ahead("gz1g", String(z1.mpr))
	check(first_id != 0 and instance_from_id(first_id) == null, "an announcement frees the world built ahead before it")
	check(s._ahead_world != null and s._ahead_zone == ["gz1g", String(z1.mpr)], "the latest announcement's world is held")
	var other := z1.duplicate()
	other.mpr = String(z2.mpr)
	check(s._take_ahead_world(other) == null and s._ahead_world == null, "a differing map name takes nothing and frees the world")

	# 4. The take checks the presentation mode and the zone id without
	# building anything.
	var dummy := GameWorld.new()
	s._ahead_world = dummy
	s._ahead_zone = ["gz9g", String(z1.mpr)]
	check(s._take_ahead_world(z1) == null and not is_instance_valid(dummy), "another zone id takes nothing and frees the world")
	dummy = GameWorld.new()
	dummy.presentation = false
	s._ahead_world = dummy
	s._ahead_zone = ["gz1g", String(z1.mpr)]
	check(s._take_ahead_world(z1) == null and not is_instance_valid(dummy), "a world of the other presentation mode is not taken")
	dummy = GameWorld.new()
	s._ahead_world = dummy
	s._ahead_zone = ["gz1g", String(z1.mpr)]
	check(s._take_ahead_world(z1) == dummy and s._ahead_world == null and dummy.zone == z1, "a matching world is taken with the zone record")
	dummy.free()

	# 5. Held messages (deferred loading screen) and the worker ignore it.
	s._zone_holding = true
	s._rpc_zone_ahead("gz1g", String(z1.mpr))
	check(s._ahead_world == null, "no world is built ahead while the host's messages are held")
	s._zone_holding = false
	s.local_host.worker = true
	s._rpc_zone_ahead("gz1g", String(z1.mpr))
	check(s._ahead_world == null, "the simulation worker builds nothing ahead")
	s.local_host.worker = false
	s._rpc_zone_ahead("nowhere", "")
	check(s._ahead_world == null, "an unknown zone builds nothing ahead")

	# 6. Teardown frees a world still held ahead.
	s._rpc_zone_ahead("gz1g", String(z1.mpr))
	var held: GameWorld = s._ahead_world
	var held_id := held.get_instance_id() if held else 0
	check(held != null, "a world is held ahead before the teardown")
	main.queue_free()
	await get_tree().process_frame
	check(held_id != 0 and instance_from_id(held_id) == null, "removing the session frees the world held ahead")
	print("ZONE_BUILD_AHEAD ", checks, " checks ", failures.size(), " failures")
	TexUpscale.shutdown()
	get_tree().quit(0 if failures.is_empty() else 1)
