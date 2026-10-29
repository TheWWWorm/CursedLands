extends Node
## NavGrid.build works out the placed objects' footprints on the worker
## threads: a town's footprints took over a second in one thread. Every
## footprint equals the one the same grid computes alone, afterwards, and
## the grid they make (spans, floors, faces, radii) is the same.
var checks := 0
var failures: Array[String] = []

## Which threads rasterize the footprints' boxes (one call per body part).
class Probe extends NavGrid:
	var threads := {}
	var _lock := Mutex.new()
	func _raster_box(lo: Vector3, hi: Vector3, rot: Basis, base: Vector3, kind: int, list: Dictionary) -> void:
		_lock.lock()
		threads[OS.get_thread_caller_id()] = int(threads.get(OS.get_thread_caller_id(), 0)) + 1
		_lock.unlock()
		super(lo, hi, rot, base, kind, list)

## No footprint for one object: the hook's result is what the build keeps.
class Hooked extends NavGrid:
	var skipped := 0
	func _record_footprint(info: Dictionary, t := -1.0) -> Dictionary:
		if int(info.get("nid", 0)) == skipped:
			return {"spans": {}, "floors": {}, "radius": 0.0, "faces": []}
		return super(info, t)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var z := CampaignMap.load_from(GameData.texts).zone("gz1g")
	var mpr := String(z.get("mpr", ""))
	var map := EIMapScene.load_map(mpr, String(z.get("mob", mpr)), false, false)
	check(map != null and map.object_nodes.size() > 500, "fixture zone has placed objects (%d)" % (map.object_nodes.size() if map else 0))
	if map == null:
		_finish()
		return
	add_child(map)
	var objects: Array = map.object_nodes
	var nav := Probe.new()
	var t0 := Time.get_ticks_msec()
	nav.build(map.terrain, map.terrain.water_base, objects)
	var build_ms := Time.get_ticks_msec() - t0
	var boxes := 0
	for id: int in nav.threads:
		boxes += nav.threads[id]
	var built_on := nav.threads.duplicate()
	check(boxes > objects.size() / 2, "the build rasterized the objects' boxes (%d for %d objects)" % [boxes, objects.size()])
	if Portability.threads() and OS.get_processor_count() > 1:
		check(built_on.size() > 1, "footprints are worked out on more than one thread (%d)" % built_on.size())
		check(int(built_on.get(OS.get_main_thread_id(), 0)) < boxes, "the main thread does not rasterize every box")
	else:
		check(built_on.size() == 1, "one thread without worker threads")
	check(nav._fp.size() == objects.size(), "every object registered its footprint (%d)" % nav._fp.size())
	# The same grid, alone, computes the same footprints (the sequential
	# result): spans, floors, faces and radii.
	var spans := 0
	var floors := 0
	var faces := 0
	var mismatches := 0
	t0 = Time.get_ticks_msec()
	for key: int in nav._fp:
		var o: Node3D = nav._fp_nodes[key]
		var again := nav._footprint(o)
		var fp: Dictionary = nav._fp[key]
		if fp != again:
			mismatches += 1
			if mismatches <= 5:
				printerr("footprint differs for ", o.name, ": ", JSON.stringify(fp).left(200), " vs ", JSON.stringify(again).left(200))
		spans += fp.spans.size()
		floors += fp.floors.size()
		faces += fp.faces.size()
	var serial_ms := Time.get_ticks_msec() - t0
	check(mismatches == 0, "every footprint equals its sequential result (%d differ)" % mismatches)
	check(spans > 500 and floors > 0 and faces > 0, "the footprints hold spans, floors and faces (%d, %d, %d)" % [spans, floors, faces])
	# The grid they make: every span cell is registered under its object.
	var registered := 0
	for i: int in nav._spans:
		for s: Array in nav._spans[i]:
			if nav._fp.has(int(s[3])) and nav._fp[int(s[3])].spans.has(i):
				registered += 1
	check(registered == spans, "every footprint span is in the grid (%d of %d)" % [registered, spans])
	var floored := 0
	for i: int in nav._floors:
		floored += nav._floors[i].size()
	check(floored == floors, "every footprint floor is in the grid (%d of %d)" % [floored, floors])
	# A later object goes the sequential way and lands in the same grid.
	var late: Node3D = null
	for o: Node3D in objects:
		var nid := int(o.get_meta("ei", {}).get("nid", 0))
		if nid != 0 and nav._fp.has(nid) and not nav._fp[nid].spans.is_empty():
			late = o
			break
	check(late != null, "an object with spans to re-add")
	if late != null:
		var nid := int(late.get_meta("ei").get("nid", 0))
		var late_fp: Dictionary = nav._fp[nid]
		nav.remove_object(nid)
		check(not nav._fp.has(nid), "a removed object leaves the grid")
		nav.add_object(late)
		check(nav._fp.get(nid, {}) == late_fp, "an object added later has the same footprint")
	# The per-record hook (lever states, the moving-door test) shapes the
	# build's footprints too.
	var hooked := Hooked.new()
	hooked.skipped = int(late.get_meta("ei").get("nid", 0)) if late != null else 0
	hooked.build(map.terrain, map.terrain.water_base, objects)
	check(hooked.skipped != 0 and hooked._fp.has(hooked.skipped) and hooked._fp[hooked.skipped].spans.is_empty() \
		and hooked._fp.size() == nav._fp.size(), "the build's footprints pass through the record hook")
	print("NAV_FOOTPRINTS_TIMING objects=%d build_ms=%d sequential_footprints_ms=%d threads=%d" % [
		objects.size(), build_ms, serial_ms, built_on.size()])
	map.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	print("NAV_FOOTPRINTS_PARALLEL ", checks, " checks ", failures.size(), " failures")
	get_tree().quit(1 if not failures.is_empty() else 0)
