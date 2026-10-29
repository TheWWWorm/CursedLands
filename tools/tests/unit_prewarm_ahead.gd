extends Node
## The client's build ahead of the zone message (Session._rpc_zone_ahead)
## also prepares the unit assets the message's replicas will need: the
## templates' clip libraries (base, parts, height) and the composed atlases
## of the map's own unit records (EIUnitModel.prewarm). Models made after
## it add nothing to those caches, and the gear plan, needed parts and
## root part it derives are what the built model has.
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

func caches() -> Array:
	return [EIAnim._libraries.size(), EIUnitModel._textures.size(), EIUnitModel._surface_textures.size()]

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
	var z := s.campaign.zone("gz1g")
	check(not z.is_empty(), "fixture zone exists")
	var cold := caches()
	var t0 := Time.get_ticks_msec()
	s._rpc_zone_ahead("gz1g", String(z.mpr))
	var ahead_ms := Time.get_ticks_msec() - t0
	var ahead: GameWorld = s._ahead_world
	check(ahead != null and is_instance_valid(ahead) and ahead.map != null, "the announcement builds a world ahead")
	if ahead == null:
		_finish(main)
		return
	var records: Array = ahead.map.unit_records
	check(records.size() > 20, "the map has unit records (%d)" % records.size())
	var warm := caches()
	check(warm[0] > cold[0] and warm[1] > cold[1] and warm[2] > cold[2],
		"the build ahead filled the library and atlas caches (%s -> %s)" % [cold, warm])
	# Prepared again: nothing new to make.
	var again := EIUnitModel.prewarm(records)
	check(again.libraries == 0 and again.textures == 0 and again.records == records.size(),
		"a second preparation makes nothing (%s)" % again)
	check(EIUnitModel.prewarm([]).records == 0 and EIUnitModel.prewarm([{"template": "no_such_figure"}]).records == 0,
		"empty and unknown records prepare nothing")
	# The models the records make find everything prepared and agree with
	# the plan the preparation derived.
	var db := GameData.db
	var made := 0
	var plans_agree := true
	var roots_agree := true
	var holder := Node3D.new()
	add_child(holder)
	t0 = Time.get_ticks_msec()
	for i in records.size():
		var r: Dictionary = records[i]
		var m := EIUnitModel.create(r, false, true, null)
		if m == null:
			continue
		holder.add_child(m)
		made += 1
		var unit := CampaignState.map_unit_record(r)
		var proto := db.find("monster_prototypes", unit.get("prototype", unit.get("parent_template", "")))
		var race := db.find("race_models", unit.get("look_race", proto.get("base_race", "")))
		var model := EIFigure.get_model(m._asset_template)
		var plan := EIUnitModel.gear_plan(model, unit, proto, race, m.template, false)
		var meta: Array = m.get_meta("layers")
		if plan.mask != meta[0] or plan.layers != meta[1]:
			plans_agree = false
			printerr("plan differs for ", m.template, ": ", plan.mask, plan.layers, " vs ", meta)
		var needed := EIUnitModel.needed_parts(model, plan.mesh_for)
		var root := EIUnitModel.root_part_of(model, needed).replace(".", "_")
		if m._animation_roots.is_empty() or m._animation_roots.back().name != root:
			roots_agree = false
			printerr("root differs for ", m.template, ": ", root, " vs ", m._animation_roots.back().name if not m._animation_roots.is_empty() else "none")
		for p: String in needed:
			if m.find_child(p.replace(".", "_"), true, false) == null:
				roots_agree = false
				printerr("needed part missing for ", m.template, ": ", p)
	var create_ms := Time.get_ticks_msec() - t0
	var after := caches()
	check(made > 20, "the records make models (%d)" % made)
	check(after == warm, "models made after the preparation add no library or atlas (%s -> %s)" % [warm, after])
	check(plans_agree, "the gear plan is the built model's atlas layers")
	check(roots_agree, "the needed parts and the root part are the built model's")
	# The zone message takes the world built ahead and spawns its records as
	# before.
	var spawn := []
	for i in 3:
		var copy: Dictionary = records[i].duplicate(true)
		copy.nid = 7000 + i
		copy.controller = -1
		spawn.append(copy)
	s._rpc_zone("gz1g", spawn, PackedInt32Array(), [], String(z.mpr))
	check(s.world == ahead and s.world.units.size() == 3, "the zone message takes the prepared world and spawns its records")
	print("UNIT_PREWARM_TIMING records=%d ahead_ms=%d models_after_ms=%d caches=%s" % [records.size(), ahead_ms, create_ms, after])
	holder.queue_free()
	_finish(main)

func _finish(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	print("UNIT_PREWARM_AHEAD ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
