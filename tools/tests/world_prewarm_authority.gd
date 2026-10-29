extends Node
## A world that spawns the map's units itself (the authority: the solo
## campaign's simulation worker, a co-op host) decodes their templates' clip
## libraries on a thread from the moment the .mob is read, while it places
## the objects and builds the navigation grid, and joins it before the first
## unit is made (GameWorld.load_map, EIUnitModel.prewarm_start/finish): the
## units' players share the prepared libraries, which equal a serial
## preparation's clip for clip; a world that presents nothing prepares no
## atlases while a presenting one prepares them all; a caller's own on_mob
## and a world without units prepare nothing; a warm load starts no thread.
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

## A content signature of every cached library (unit_prewarm_background).
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

## The units whose player's "ei" library is one of the shared cache's.
func shared_players(w: GameWorld) -> int:
	var cached: Array = EIAnim._libraries.values()
	var n := 0
	for u: GameUnit in w.unit_rows():
		if u.model and u.model.player and u.model.player.get_animation_library("ei") in cached:
			n += 1
	return n

func world(presenting: bool) -> GameWorld:
	var w := GameWorld.new()
	w.zone = {"type": "game"}
	w.presentation = presenting
	add_child(w)
	return w

func _run() -> void:
	GameData.options.merge({"autosave": 0, "show_tutorial": 0, "auto_graphics": 0}, true)
	var zone := CampaignMap.load_from(GameData.texts).zone("gz1g")
	var mpr: String = zone.mpr
	var mob: String = zone.get("mob", mpr)
	var map := EIMapScene.load_map(mpr, mob, false, false)
	var records: Array = Array(map.unit_records) if map else []
	check(records.size() > 20, "the map leaves unit records to the world (%d)" % records.size())
	if map: map.free()

	# The serial references, from cold caches: libraries only, and with the atlases.
	clear_caches()
	var bare := EIUnitModel.prewarm(records, false)
	var reference := signature()
	check(bare.libraries > 0 and reference.size() == bare.libraries, "the serial preparation makes the libraries (%d)" % bare.libraries)
	check(bare.textures == 0 and EIUnitModel._textures.is_empty() and EIUnitModel._surface_textures.is_empty(),
		"a preparation without textures composes no atlas (%d)" % bare.textures)
	clear_caches()
	var dressed := EIUnitModel.prewarm(records, true)
	check(dressed.libraries == bare.libraries and dressed.textures > 0, "the serial preparation with textures makes the libraries and the atlases (%d, %d)" % [dressed.libraries, dressed.textures])
	var atlas_count := [EIUnitModel._textures.size(), EIUnitModel._surface_textures.size()]

	# 1. The headless authority (the simulation worker): the libraries are
	# prepared on the thread and joined before the units are made; no atlas.
	clear_caches()
	var w := world(false)
	var t0 := Time.get_ticks_usec()
	check(w.load_map(mpr, mob, true), "the authority world loads %s with its units" % mpr)
	var load_us := Time.get_ticks_usec() - t0
	var units := w.unit_rows().size()
	check(units == records.size(), "the authority spawns every record (%d of %d)" % [units, records.size()])
	var stats: Dictionary = w.map.stats if w.map else {}
	check(stats.has("prewarm"), "the authority world prepares its units' libraries (map.stats.prewarm)")
	var made: Dictionary = stats.get("prewarm", {})
	check(int(made.get("libraries", -1)) == bare.libraries, "every library comes from the preparation, none from a unit's own build (%s of %d)" % [str(made.get("libraries")), bare.libraries])
	check(bool(made.get("threaded", false)) == Portability.threads(), "the libraries are decoded on a thread of their own (%s)" % str(made.get("threaded")))
	check(int(made.get("textures", -1)) == 0 and EIUnitModel._textures.is_empty() and EIUnitModel._surface_textures.is_empty(),
		"a world that presents nothing prepares no atlas (%s)" % str(made.get("textures")))
	check(signature() == reference, "the prepared libraries equal the serial preparation's, clip for clip")
	check(EIAnim._libraries.size() == reference.size(), "the cache holds the preparation's keys and no other (%d of %d)" % [EIAnim._libraries.size(), reference.size()])
	check(shared_players(w) == units, "every unit's player uses a prepared library (%d of %d)" % [shared_players(w), units])
	print("world_prewarm_authority: authority load %.1f ms, %d units, %d libraries" % [load_us / 1000.0, units, bare.libraries])

	# 2. A warm authority load: nothing to prepare, no thread.
	var again := world(false)
	check(again.load_map(mpr, mob, true), "a second authority load succeeds")
	var warm: Dictionary = again.map.stats.get("prewarm", {}) if again.map else {}
	check(not warm.is_empty() and int(warm.get("libraries", -1)) == 0 and not bool(warm.get("threaded", true)),
		"a warm load prepares nothing and starts no thread (%s)" % JSON.stringify(warm))
	check(signature() == reference and shared_players(again) == again.unit_rows().size(), "the warm load keeps the cache and shares it")

	# 3. A presenting authority (a co-op host, headless here) prepares the
	# atlases too, the serial preparation's count.
	clear_caches()
	var host := world(true)
	check(host.load_map(mpr, mob, true), "the presenting authority loads with its units")
	var shown: Dictionary = host.map.stats.get("prewarm", {}) if host.map else {}
	check(int(shown.get("libraries", -1)) == dressed.libraries and int(shown.get("textures", -1)) == dressed.textures,
		"a presenting world prepares the libraries and the atlases (%s; serial %d, %d)" % [JSON.stringify(shown), dressed.libraries, dressed.textures])
	check([EIUnitModel._textures.size(), EIUnitModel._surface_textures.size()] == atlas_count, "the atlas caches hold the serial preparation's count %s" % str(atlas_count))
	check(signature() == reference and shared_players(host) == host.unit_rows().size(), "the presenting world's units share the prepared libraries")

	# 4. A caller's own on_mob (the client's build ahead) and a world without
	# units: the world prepares nothing itself.
	clear_caches()
	var seen := {"calls": 0, "records": 0}
	var client := world(true)
	check(client.load_map(mpr, mob, false, func(rows: Array) -> void:
		seen.calls += 1
		seen.records = rows.size()), "a world with a caller's on_mob loads")
	check(seen.calls == 1 and seen.records == records.size(), "the caller's on_mob gets the records once (%d calls, %d records)" % [seen.calls, seen.records])
	check(not client.map.stats.has("prewarm") and EIAnim._libraries.is_empty(), "the world prepares nothing of its own behind a caller's on_mob")
	var empty := world(false)
	check(empty.load_map(mpr, mob, false), "a world without units loads")
	check(not empty.map.stats.has("prewarm") and EIAnim._libraries.is_empty() and empty.unit_rows().is_empty(), "a world without units prepares nothing")

	print("WORLD_PREWARM_AUTHORITY %d checks %d failures" % [checks, failures.size()])
	for f in failures:
		print("  ", f)
	get_tree().quit(1 if failures.size() else 0)
