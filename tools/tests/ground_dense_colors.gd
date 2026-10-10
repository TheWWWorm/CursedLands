extends Node
## Real authored terrain + actual native/script dispatcher. Packed ArrayMesh
## COLOR and primitive addresses, rather than the palette packer, are the oracle.
var checks := 0
var failures := 0
var rows := []
var compared_vertices := 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
	return ok

func packed_colors(mesh: ArrayMesh) -> PackedByteArray:
	var surface: Dictionary = mesh.call("_get_surfaces")[0]
	var stride := RenderingServer.mesh_surface_get_format_attribute_stride(surface.format, surface.vertex_count)
	var offset := RenderingServer.mesh_surface_get_format_offset(surface.format, surface.vertex_count, Mesh.ARRAY_COLOR)
	var data: PackedByteArray = surface.attribute_data
	var result := PackedByteArray()
	for i in int(surface.vertex_count): result.append_array(data.slice(i * stride + offset, i * stride + offset + 4))
	return result

func verify(soft: SoftGroundDeform, palette: GroundDenseColors, label: String) -> void:
	var drawn := {}
	var bad_bytes := 0
	var bad_addresses := 0
	var bad_visibility := 0
	var vertices := 0
	for key: Vector2i in soft.sectors:
		var rec: Dictionary = soft.sectors[key]
		var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
		var mesh := node.mesh as ArrayMesh
		var arrays := mesh.surface_get_arrays(0)
		var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var colors := packed_colors(mesh)
		var source_count := (rec.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var at := 0
		for tile in 256:
			var global_tile := key * 16 + Vector2i(tile % 16, tile / 16)
			var dense := ids[at] >= source_count
			var visibility := soft.field._tile_image.get_pixelv(global_tile)
			var layer := int(palette._tile_image.get_pixelv(global_tile).r) - 1
			if dense:
				drawn[global_tile] = true
				var start := ids[at]
				vertices += 1224
				if layer < 0 or not palette._slots.has(global_tile) or layer != int(palette._slots[global_tile]):
					bad_addresses += 1
				else:
					var expected := colors.slice(start * 4, (start + 1224) * 4)
					if palette._images[layer].get_data() != expected: bad_bytes += 1
				if visibility.g != 1.0 or visibility.r <= 0.0: bad_visibility += 1
				at += 8 * 256 * 3
			else:
				if layer >= 0: bad_addresses += 1
				if visibility.g != 0.0: bad_visibility += 1
				at += 24
		check(at == ids.size(), label + " complete primitive stream " + str(key))
	check(palette._slots.size() == drawn.size(), label + " no absent or extra drawn tile slots")
	check(bad_addresses == 0, label + " all drawn tile addresses exact")
	check(bad_visibility == 0, label + " shared dense visibility matches installed geometry")
	check(bad_bytes == 0, label + " every installed native COLOR byte exact")
	check(palette._slots.size() <= SoftGroundDeform.MAX_TILES, label + " palette stays within capacity")
	compared_vertices += vertices
	rows.append({"label": label, "drawn_tiles": drawn.size(), "logical_tiles": soft.tile_count(),
		"palette_slots": palette._slots.size(), "compared_vertices": vertices,
		"bad_addresses": bad_addresses, "bad_visibility": bad_visibility, "bad_color_tiles": bad_bytes,
		"pending_jobs": soft._mesh_jobs.size(), "queued_tiles": soft._queue.size()})

func drain(soft: SoftGroundDeform) -> void:
	for i in 64:
		soft._process(0.0)
		soft._finish_mesh_jobs(true)
		if soft._mesh_jobs.is_empty() and soft._queue.is_empty() and not soft.sectors.values().any(func(rec: Dictionary) -> bool: return rec.build_pending):
			check(true, "dispatcher finished accepted work")
			return
	check(false, "dispatcher finished accepted work")

func points(soft: SoftGroundDeform) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var selected_key := Vector2i(-1, -1)
	var size := soft.terrain.size_ei()
	for y in range(1, int(size.y) - 1, 2):
		for x in range(1, int(size.x) - 1, 2):
			var p := Vector2(x, y)
			var key := Vector2i(p / 32.0)
			if selected_key.x >= 0 and key != selected_key: continue
			if not soft.step_allowed(p) or soft.terrain.ground_type(x, y) != 9: continue
			selected_key = key
			found.append(p)
			if found.size() == 4: return found
	return found

func step(soft: SoftGroundDeform, p: Vector2) -> void:
	soft.add_step(p, Vector2(0.12, 0.2), 0.3)

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	GameData.options.gfx_soft_ground = 1
	Gfx.ensure_globals(); Gfx.apply_surface_options()
	var terrain := EITerrain.load_map("zone11")
	if not check(terrain != null, "authored snow map loads"):
		finish(); return
	add_child(terrain); terrain.set_process(false); terrain.hide()
	terrain.details.set_process(false)
	var soft := terrain.details.soft_ground
	soft.set_process(false); soft._age = 123.0
	var native := not OS.get_cmdline_user_args().has("--ei-script-soft-ground")
	check(soft._native_mesh == native, "requested native/script dispatcher is active")
	var p := points(soft)
	if not check(p.size() == 4, "four dry authored snow contact points in one sector"):
		terrain.free(); finish(); return
	var key := Vector2i(p[0] / 32.0)
	step(soft, p[0])
	check(not soft._queue.is_empty(), "public foot contact queues geometry")
	soft._process(0.0)
	if native: check(soft._mesh_jobs.size() == 1, "real worker has a pending snapshot")
	step(soft, p[1])
	drain(soft)
	check(soft.field._dense_colors == null, "ordinary footsteps retain no contact palette before demand")
	var palette := soft.field.contact_colors()
	verify(soft, palette, "late contact binding after coalesced jobs")
	check(palette._slots.size() == 2, "both separate contacts are installed")
	var rec: Dictionary = soft.sectors[key]
	var node := (rec.node as WeakRef).get_ref() as MeshInstance3D
	var original := rec.source as ArrayMesh
	check(node.mesh != original and (rec.shadow as WeakRef).get_ref().mesh != null, "actual surface and shadow are installed")
	step(soft, p[2])
	verify(soft, palette, "queued contact retains last installed bytes")
	soft._process(0.0)
	verify(soft, palette, "dispatched contact retains accepted bytes")
	drain(soft)
	verify(soft, palette, "later snapshot installed")
	var retained := weakref(palette)
	palette = null
	check(retained.get_ref() == null, "last consumer release drops the contact palette")
	palette = soft.field.contact_colors()
	verify(soft, palette, "rejoining consumer reconstructs installed state")
	step(soft, p[3]); soft._process(0.0)
	var generation: int = rec.generation
	soft._restore(key)
	check(node.mesh == original and palette._slots.is_empty(), "retiring sector immediately restores source and removes palette")
	step(soft, p[0])
	check(int(soft.sectors[key].generation) != generation, "recreated sector has a fresh generation")
	drain(soft)
	verify(soft, palette, "obsolete worker cannot revive retired contacts")
	check(palette._slots.size() == 1, "only recreated contact is installed")
	rec = soft.sectors[key]
	step(soft, p[1]); soft._process(0.0)
	for id: int in rec.touched: rec.touched[id] = -SoftGroundDeform.LIFE
	soft._process(1.1)
	verify(soft, palette, "expiry pending replacement")
	drain(soft)
	verify(soft, palette, "expired geometry removed")
	check(rec.tiles.is_empty() and palette._slots.is_empty(), "expiry removes all accepted dense colors")
	step(soft, p[0]); drain(soft)
	step(soft, p[1]); soft._process(0.0)
	soft._make_room(key, SoftGroundDeform.MAX_TILES)
	check(node.mesh == original and palette._slots.is_empty(), "capacity reset removes old geometry and colors together")
	step(soft, p[2]); drain(soft)
	verify(soft, palette, "capacity reset accepts only new contacts")
	check(palette._slots.size() == 1, "capacity reset leaves one new contact")
	step(soft, p[3]); soft._process(0.0)
	soft.clear()
	check(soft._mesh_jobs.is_empty() and soft.sectors.is_empty() and node.mesh == original, "clear joins workers and restores authored mesh")
	check(palette._slots.is_empty() and palette._images.is_empty(), "clear releases the peak color allocation")
	step(soft, p[0]); drain(soft)
	verify(soft, palette, "new contacts after clear")
	step(soft, p[1]); soft._process(0.0)
	soft.free()
	check(node.mesh == original and palette._slots.is_empty(), "node removal joins work and restores mesh and palette")
	terrain.details.soft_ground = null
	terrain.free()
	finish()

func finish() -> void:
	var result := {"checks": checks, "failures": failures, "rows": rows, "compared_vertices": compared_vertices,
		"script_dispatch": OS.get_cmdline_user_args().has("--ei-script-soft-ground"),
		"scope": "Controlled public add_step calls on real authored zone11 snow, actual native/script dispatcher and installed packed ArrayMesh COLOR oracle. Pending/coalesced work, late consumer, stale generation, expiry, capacity reset, clear and removal. No physical walking, rendered lighting or performance claim."}
	FileAccess.open("user://dense-dispatcher.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("DENSE_DISPATCHER checks=", checks, " failures=", failures, " vertices=", compared_vertices)
	TexUpscale.shutdown(); UnitWounds.shutdown(); get_tree().quit(int(failures > 0))
