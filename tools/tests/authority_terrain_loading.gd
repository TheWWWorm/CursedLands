extends Node
## Compare the actual simulation-only world against the same original map
## with presentation, including object floors, water and all movement classes.
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	GameData.options.merge(GfxPresets.values(GfxPresets.HIGH), true)
	for map in ["zone1", "zone7", "zone8", "zone15"]:
		var visible := GameWorld.new()
		var authority := GameWorld.new(); authority.presentation = false
		check(visible.load_map(map, "", false) and authority.load_map(map, "", false), "both world paths load " + map)
		var a := authority.terrain; var b := visible.terrain
		check(a.get_child_count() == 0 and a._atlases == null and a._land_mat == null and a._water_mat == null,
			"authority builds no terrain meshes, atlases or materials " + map)
		check(b.get_child_count() > 0 and b._atlases != null, "presentation still owns terrain graphics " + map)
		check(not a.is_processing() and a.details == null and a.color_cache == null, "authority has no terrain visual work " + map)
		for property in ["materials", "heights", "land_xy", "land_n", "land_tile", "water_tile", "tile_types",
			"water", "water_base", "water_mat", "ground", "liquid_ground", "surface"]:
			check(a.get(property) == b.get(property), "original terrain data matches " + map + ":" + property)
		check(a.height_range() == b.height_range(), "height bounds match " + map)
		for property in ["_h0", "_hq0", "_h", "_hq", "_cost", "_depth", "_liq", "_steep"]:
			check(authority.nav.get(property) == visible.nav.get(property), "navigation input matches " + map + ":" + property)
		for cls in 8:
			var la := authority.nav.layer(cls); var lb := visible.nav.layer(cls)
			check(la.raw == lb.raw and la.land == lb.land and la.cost == lb.cost, "passability and costs match " + map + ":" + str(cls))
		var wet := false
		for mat in a.materials.size():
			if not mat in a.water_mat: continue
			wet = true
			check(a.set_water_offset(mat, 1.25) == b.set_water_offset(mat, 1.25) and a.water == b.water,
				"scripted water raising matches " + map)
			check(a.set_water_offset(mat, 0.0) == b.set_water_offset(mat, 0.0) and a.water == b.water,
				"scripted water restoring matches " + map)
			break
		check(wet, "water parity was exercised " + map)
		a.apply_gfx()
		check(a.get_child_count() == 0 and a._atlases == null, "option refresh cannot allocate authority terrain graphics " + map)
		visible.free(); authority.free()
	print("AUTHORITY_TERRAIN_LOADING ", checks, " checks ", failures, " failures")
	get_tree().quit(int(failures > 0))
