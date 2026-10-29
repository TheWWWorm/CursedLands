extends Node
## The build ahead's clip libraries are decoded on a thread of their own from
## the moment the map's .mob is read (EIMapScene.load_map's on_mob,
## EIUnitModel.prewarm_start) while the main thread places the objects, and
## joined afterwards (prewarm_finish): the libraries equal the ones the serial
## preparation makes, clip for clip; a model made meanwhile on the main thread
## builds what it needs itself and the finish keeps it; the shared caches end
## with the same keys; a second preparation makes nothing.
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

## A content signature of every cached library: clip names, lengths, loops,
## tracks (path, type, key count, first and last key value).
static func signature() -> Dictionary:
	var out := {}
	for key: String in EIAnim._libraries:
		var lib: AnimationLibrary = EIAnim._libraries[key]
		var clips := []
		for name: StringName in lib.get_animation_list():
			var a := lib.get_animation(name)
			var tracks := []
			for t in a.get_track_count():
				var n := a.track_get_key_count(t)
				tracks.append([String(a.track_get_path(t)), a.track_get_type(t), n,
					var_to_str(a.track_get_key_value(t, 0)) if n > 0 else "",
					var_to_str(a.track_get_key_value(t, n - 1)) if n > 0 else ""])
			clips.append([String(name), a.length, a.loop_mode, tracks])
		out[key] = hash(clips)
	return out

func clear_caches() -> void:
	EIAnim._libraries.clear()
	EIUnitModel._textures.clear()
	EIUnitModel._surface_textures.clear()

func _run() -> void:
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "auto_graphics": 0}, true)
	var zone := CampaignMap.load_from(GameData.texts).zone("gz1g")
	var mpr: String = zone.mpr
	# The hook: the records the map leaves to the world, before any object
	# is placed; the same records the map reports afterwards.
	var seen := {"calls": 0, "records": [], "when": 0}
	var t0 := Time.get_ticks_usec()
	var map := EIMapScene.load_map(mpr, zone.get("mob", mpr), false, false, func(records: Array) -> void:
		seen.calls += 1
		seen.records = records
		seen.when = Time.get_ticks_usec() - t0)
	check(map != null and map.unit_records.size() > 20, "the map loads with unit records (%d)" % (map.unit_records.size() if map else -1))
	check(seen.calls == 1, "on_mob is called once (%d)" % seen.calls)
	check(seen.records == Array(map.unit_records), "on_mob gets the records the map leaves to the world (%d)" % seen.records.size())
	var records: Array = Array(map.unit_records)
	var placed := Time.get_ticks_usec() - t0
	check(seen.when < placed, "on_mob is called before the objects are placed (%d of %d us)" % [seen.when, placed])
	map.free()

	# The serial reference.
	clear_caches()
	var serial := EIUnitModel.prewarm(records)
	var reference := signature()
	check(serial.libraries > 0 and reference.size() == serial.libraries, "the serial preparation makes the libraries (%d)" % serial.libraries)

	# The same on the thread, with a model made meanwhile on the main thread.
	clear_caches()
	var job := EIUnitModel.prewarm_start(records)
	var started := job.get("thread") is Thread and (job.thread as Thread).is_started()
	check(started, "prewarm_start returns with the libraries' thread running")
	check(EIAnim._libraries.is_empty(), "the thread does not write the shared cache")
	var model := EIUnitModel.create(records[0])
	check(model != null and model.player != null and model.player.has_animation_library("ei"), "a model made meanwhile builds its library on the main thread")
	var meanwhile := EIAnim._libraries.size()
	var meanwhile_atlases := EIUnitModel._textures.size() + EIUnitModel._surface_textures.size()
	check(meanwhile > 0, "the model's keys are in the shared cache (%d)" % meanwhile)
	var made := EIUnitModel.prewarm_finish(job)
	var threaded := signature()
	check(not (job.thread as Thread).is_alive(), "prewarm_finish joins the thread")
	check(threaded.keys() == reference.keys() or (threaded.size() == reference.size() and threaded.keys().all(func(k): return reference.has(k))),
		"the caches end with the same keys (%d)" % threaded.size())
	var same := 0
	for key: String in reference:
		if threaded.get(key) == reference[key]:
			same += 1
	check(same == reference.size(), "every library equals the serial one clip for clip (%d of %d)" % [same, reference.size()])
	check(made.libraries + meanwhile == serial.libraries, "the finish keeps the main thread's libraries and adds the rest (%d + %d = %d)" % [made.libraries, meanwhile, serial.libraries])
	check(made.records == serial.records and made.textures + meanwhile_atlases == serial.textures,
		"records as the serial preparation, atlases as it less the model's own (%s + %d / %s)" % [made, meanwhile_atlases, serial])
	model.free()

	# Warm: nothing to make, no thread.
	var again := EIUnitModel.prewarm_start(records)
	check(again.get("thread") == null, "a warm preparation starts no thread")
	var again_made := EIUnitModel.prewarm_finish(again)
	check(again_made.libraries == 0 and again_made.textures == 0 and again_made.records == records.size(), "a warm preparation makes nothing (%s)" % again_made)
	check(EIUnitModel.prewarm([]).records == 0 and EIUnitModel.prewarm_finish({}).libraries == 0, "no records: nothing")
	print("UNIT_PREWARM_BACKGROUND ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if failures.size() else 0)
