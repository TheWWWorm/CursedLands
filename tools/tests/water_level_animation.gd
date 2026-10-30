extends Node
## A gradual SetWaterLevel (gz5h's Canyon of Death river, the zone1 sea here)
## moves every 55-ms logic tick, and each host and guest presentation applies
## every step. Each step used to scan every map cell and rebuild grass and the
## reflection plane, about 6 ms per step (13-18 fps in co-op at gz5h). Steps
## now update only the material's cells, and the grass and reflection plane
## follow a moving level at a bounded rate. The final level is applied at once.
const Reflection = preload("res://src/game/fx/water_reflection.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

## The old full-map scan, as reference.
func scan(t: EITerrain, mat: int) -> Array:
	var cells := PackedInt32Array(); var w := t.sectors_x * EITerrain.SECTOR
	var lo := Vector2i(1 << 30, 1 << 30); var hi := Vector2i(-1, -1)
	for i in t.water_mat.size():
		if t.water_mat[i] == mat:
			cells.append(i); var c := Vector2i(i % w, i / w); lo = lo.min(c); hi = hi.max(c)
	return [cells, Rect2i(lo, hi - lo + Vector2i.ONE) if hi.x >= 0 else Rect2i()]

func _ready() -> void:
	var name := "zone1"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--water-map="): name = arg.trim_prefix("--water-map=")
	var t := EITerrain.load_map(name); add_child(t); t.set_process(false)
	var d := t.details
	d.set_process(false)
	var mats := {}
	for m in t.water_mat: if m != 255: mats[m] = true
	check(not mats.is_empty(), name + " has liquid materials")
	# Cached cells and bounds equal the full scan for every material.
	for m: int in mats:
		var expected := scan(t, m)
		check(t.water_cells(m) == expected[0], "material %d cells match the map scan" % m)
		var before := t.water.duplicate()
		var rect := t.set_water_offset(m, 0.5)
		check(rect == expected[1], "material %d changed area matches the map scan" % m)
		var exact := true
		for i in t.water.size():
			var want: float = t.water_base[i] + 0.5 if t.water_mat[i] == m else before[i]
			if not (t.water[i] == want or (is_inf(want) and is_inf(t.water[i]))): exact = false; break
		check(exact, "material %d: only its cells move, by exactly the offset" % m)
		t.set_water_offset(m, 0.0)
	var restored := true
	for i in t.water.size():
		if t.water[i] != t.water_base[i] and not (is_inf(t.water[i]) and is_inf(t.water_base[i])): restored = false; break
	check(restored, "every level back at its base after offset 0")
	check(t.water_cells(254 if not mats.has(254) else 253).is_empty(), "absent material has no cells")
	var mat: int = mats.keys()[0]

	# Grass: a direct change clears at once (as before); animated steps clear
	# at most once per interval and the final level still applies.
	var gen := d._grass_generation
	t.set_water_offset(mat, 0.1)
	check(d._grass_generation == gen + 1 and not d._water_pending, "a direct level change clears grass at once")
	gen = d._grass_generation
	d._water_next_msec = 0
	t.set_water_offset(mat, 0.11, true)
	check(d._grass_generation == gen + 1, "the first animated step clears grass")
	for step in 20:
		t.set_water_offset(mat, 0.12 + step * 0.01, true)
	check(d._grass_generation == gen + 1, "further animated steps within the interval do not rebuild grass")
	check(d._water_pending, "the moved level stays pending")
	d._process(0.0)
	check(d._grass_generation == gen + 1, "pending grass waits for the interval")
	d._water_next_msec = 0
	d._process(0.0)
	check(d._grass_generation == gen + 2 and not d._water_pending, "the pending level clears grass after the interval")
	t.set_water_offset(mat, 0.4)
	check(d._grass_generation == gen + 3, "the final (non-animated) level clears grass immediately")

	# Reflection: animated steps keep the plane index and wait for the scan
	# period; a direct change forces a rescan at once.
	var r: Node = Reflection.new()
	r._plane_key = ["kept"]; r._poll = 0.1
	r.request_refresh(true)
	check(r._plane_key == ["kept"] and r._water_moved and r._poll <= Reflection.ANIMATED_SCAN, "animated step defers the plane scan")
	r._poll = 0.2
	r.request_refresh(true)
	check(is_equal_approx(r._poll, 0.2), "later animated steps do not advance the scan")
	r.request_refresh()
	check(r._plane_key.is_empty() and r._poll == 0.0 and not r._water_moved, "a direct change rescans at once")
	r.free()

	# World: moving entries (ticks left) are animated; a finished one is not.
	var world := GameWorld.new()
	world.terrain = t
	gen = d._grass_generation
	d._water_next_msec = 0
	world.set_water_state({mat: [10, 0.2, 0.01]})
	check(d._grass_generation == gen + 1, "first moving host state clears grass")
	world.set_water_state({mat: [9, 0.21, 0.01]})
	check(d._grass_generation == gen + 1 and d._water_pending, "next moving host state is throttled")
	check(absf(t.water[t.water_cells(mat)[0]] - (t.water_base[t.water_cells(mat)[0]] + 0.21)) < 1e-5, "water heights still follow every step")
	world.set_water_state({mat: [0, 0.3, 0.0]})
	check(d._grass_generation == gen + 2 and not d._water_pending, "the finished host state applies at once")
	world.set_water_state({})
	check(absf(float(t.water_offsets.get(mat, 0.0))) < 1e-6, "a removed entry returns to offset 0")
	world.terrain = null
	world.free()

	# Cost: 18 steps (one second of a rising river) stay well below the old
	# per-step full-map scan.
	var started := Time.get_ticks_usec()
	for step in 18: t.set_water_offset(mat, 0.5 + step * 0.01, true)
	var per_step := (Time.get_ticks_usec() - started) / 18.0
	started = Time.get_ticks_usec()
	for step in 3: scan(t, mat)
	var old_scan := (Time.get_ticks_usec() - started) / 3.0
	print("WATER_LEVEL_ANIMATION_COST ", JSON.stringify({"map":name, "cells":t.water_mat.size(), "material_cells":t.water_cells(mat).size(), "step_us":per_step, "old_scan_us":old_scan}))
	check(per_step < old_scan, "an animated step costs less than the old full-map scan alone")
	print("WATER_LEVEL_ANIMATION ", JSON.stringify({"checks":checks, "failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
