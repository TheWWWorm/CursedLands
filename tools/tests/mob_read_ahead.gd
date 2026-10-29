extends Node
## The map's .mob is parsed on a thread of its own while the terrain is
## built (EIMapScene.load_map) and joined before the objects are placed: the
## parsed objects, diplomacy, script, names, sounds and lights equal a serial
## parse of the same bytes, the placed objects and the unit records left to
## the world are the same, and a map without a .mob still loads.
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func summary(m: EIMapScene) -> Array:
	var names: PackedStringArray = []
	for o: Node3D in m.object_nodes:
		var info: Dictionary = o.get_meta("ei", {})
		names.append("%s:%s@%s" % [info.get("nid", -1), info.get("template", ""), str(o.position)])
	return [names, m.unit_records, m.stats.get("objects", -1), m.stats.get("placed", -1), m.stats.get("missing_models", [])]

func _run() -> void:
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "auto_graphics": 0}, true)
	var zone := CampaignMap.load_from(GameData.texts).zone("gz1g")
	var mpr: String = zone.mpr
	var mob_name: String = zone.get("mob", mpr)
	var t0 := Time.get_ticks_usec()
	var map := EIMapScene.load_map(mpr, mob_name, false, false)
	var load_us := Time.get_ticks_usec() - t0
	check(map != null and map.mob != null, "the map loads with its .mob")
	if map == null or map.mob == null:
		print("MOB_READ_AHEAD %d checks %d failures" % [checks, failures.size()])
		get_tree().quit(1)
		return
	check(map.stats.get("mob_thread", null) == Portability.threads(), "the .mob is parsed on a thread of its own (%s)" % str(map.stats.get("mob_thread")))
	t0 = Time.get_ticks_usec()
	var serial := EIMob.load_bytes(GameData.read_file("maps/%s.mob" % mob_name))
	var parse_us := Time.get_ticks_usec() - t0
	check(map.mob.objects.size() > 100 and map.mob.objects == serial.objects, "the objects equal a serial parse (%d)" % map.mob.objects.size())
	check(map.mob.diplomacy == serial.diplomacy and map.mob.player_names == serial.player_names, "diplomacy and player names equal a serial parse")
	check(map.mob.script_text == serial.script_text and not serial.script_text.is_empty(), "the level script equals a serial parse (%d chars)" % serial.script_text.length())
	check(map.mob.sounds == serial.sounds and map.mob.lights == serial.lights, "sounds and lights equal a serial parse (%d, %d)" % [serial.sounds.size(), serial.lights.size()])
	# The same map a second time: the placement and the records left to the
	# world are the same.
	var again := EIMapScene.load_map(mpr, mob_name, false, false)
	var a := summary(map)
	var b := summary(again) if again else []
	var differs := ""
	for i in a.size():
		if b.size() <= i or a[i] != b[i]:
			differs = "part %d" % i
			if i == 0 and b.size() > i:
				for k in mini(a[0].size(), b[0].size()):
					if a[0][k] != b[0][k]:
						differs += ": %s vs %s" % [a[0][k], b[0][k]]
						break
			break
	check(again != null and differs.is_empty(), "a second load places the same objects and leaves the same unit records (%d placed, %d records%s)" % [map.object_nodes.size(), map.unit_records.size(), "" if differs.is_empty() else "; " + differs])
	check(map.unit_records.size() > 20 and map.unit_records == map._left_unit_records(), "the unit records left to the world are the .mob's units")
	print("mob_read_ahead: %s load %.1f ms, serial .mob parse %.1f ms, %d objects" % [mpr, load_us / 1000.0, parse_us / 1000.0, map.mob.objects.size()])
	map.free()
	again.free()
	# A map whose .mob does not exist: terrain only, no thread, no stat.
	var bare := EIMapScene.load_map(mpr, "no_such_mob_file", false, false)
	check(bare != null and bare.mob == null and bare.object_nodes.is_empty() and not bare.stats.has("mob_thread"), "a map without a .mob loads its terrain only")
	if bare:
		bare.free()
	print("MOB_READ_AHEAD %d checks %d failures" % [checks, failures.size()])
	for f in failures:
		print("  ", f)
	get_tree().quit(1 if failures.size() else 0)
