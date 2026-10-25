extends "res://tools/tests/terrain_cave_wall.gd"
## Measure the broad bands in the actual lit photograph, independently of
## fine texture/normal detail (which alone did not remove these stripes).
func band_contrast(image: Image) -> float:
	if image.get_size() != Vector2i(1920,1080): return INF
	var columns := PackedFloat64Array()
	for x in range(660,1180):
		var value := 0.0
		for y in range(80,240):
			var c := image.get_pixel(x,y)
			value += (c.r+c.g+c.b)/3.0
		columns.append(value/160.0)
	var sum := 0.0; var squared := 0.0
	for x in columns.size():
		var local := 0.0
		for dx in range(-64,65): local += columns[clampi(x+dx,0,columns.size()-1)]
		# Normalize out exposure and the broad lamp falloff. A darker image
		# cannot pass by merely reducing every pixel's absolute contrast.
		var high := columns[x]/maxf(local/129.0,1.0/255.0)
		sum += high; squared += high*high
	return sqrt(maxf(squared/columns.size()-pow(sum/columns.size(),2),0.0))


func run() -> void:
	cave=true
	var context := await setup_sharc()
	if context.is_empty(): get_tree().quit(1); return
	var game: Game=context[1]; var rt: Node=game.get_node("SceneRaytrace")
	var heights := t.heights.duplicate(); var xy := t.land_xy.duplicate(); var normals := t.land_n.duplicate()
	check(await ready_scene(rt),"PT prepares the refined cave wall")
	await frames(90)
	var pt := await capture("contours-pt")
	var pt_bands := band_contrast(pt)
	check(pt_bands<0.22,"lit PT wall has no strong metre-grid columns: %.6f"%pt_bands)
	check(await select_sharc(rt,true),"SHaRC accepts the same refined wall geometry")
	await frames(90)
	var cached := await capture("contours-sharc")
	var cached_bands := band_contrast(cached)
	check(cached_bands<0.23,"cached PT retains the contour correction: %.6f"%cached_bands)
	check(rt.device!=null and rt.device.nrd_active and rt.device.sharc.active,"refined walls retain NRD and SHaRC")
	var terrain_triangles := 0; var tile_ids_valid := true
	if rt._scene!=null:
		for geometry: Dictionary in rt._scene.geometries:
			if not geometry.has("land_tiles"): continue
			terrain_triangles += geometry.land_tiles.size()
			for tile: int in geometry.land_tiles:
				tile_ids_valid = tile_ids_valid and tile>0 and tile<=t.land_tile.size()
	check(terrain_triangles>0 and tile_ids_valid,"PT retains valid authored material identities for refined triangles")
	GameData.options.pt_mode=0;Gfx.apply_env(game._env);await frames(30)
	if t.color_cache!=null: t.color_cache.clear();t.color_cache.set_process(false)
	await frames(12)
	var corrected := await capture("contours-raster")
	var corrected_bands := band_contrast(corrected)
	check(corrected_bands<0.22,"lit raster wall has no strong metre-grid columns: %.6f"%corrected_bands)
	# Retain all materials, lighting and settings while removing only the new
	# geometry. This negative control must reproduce the reported bands.
	var wall_geometry: Variant=t._cliffs.get("geometry") if t._cliffs!=null else null
	for sector in t.get_children():
		if sector is EITerrainSector and sector.has_method("set_cliff_geometry"): sector.call("set_cliff_geometry",null)
	await frames(12)
	var original := await capture("contours-straight-control")
	var original_bands := band_contrast(original)
	check(original_bands>0.30,"straight-face negative control reproduces the vertical bands: %.6f"%original_bands)
	check(corrected_bands<original_bands*0.65,"wall contour correction removes at least 35 percent of band contrast")
	var floor_error := region_difference(corrected,original,Rect2i(1050,640,120,80))
	check(floor_error<0.002,"walkable floor pixels remain unchanged: %.6f"%floor_error)
	check(vertical_detail(corrected,Rect2i(760,60,260,200))>0.008,"wall keeps visible rock detail")
	for sector in t.get_children():
		if sector is EITerrainSector and sector.has_method("set_cliff_geometry"): sector.call("set_cliff_geometry",wall_geometry)
	await frames(12)
	check(region_difference(corrected,await capture("contours-restored"),Rect2i(660,80,520,160))<0.002,
		"restoring the wall geometry restores identical lit pixels")
	check(t.heights==heights and t.land_xy==xy and t.land_n==normals,"original terrain anchors, collision heights and lighting records remain unchanged")
	FileAccess.open(out.path_join("wall-contours.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"checks":checks,"failures":failures,"pt_bands":pt_bands,"cached_bands":cached_bands,
		"raster_bands":corrected_bands,"control_bands":original_bands,"floor_error":floor_error,
		"terrain_triangles":terrain_triangles},"\t"))
	context[1].queue_free();context[0].queue_free();await frames(16);TexUpscale.shutdown()
	print("WALL_CONTOURS ",checks," checks ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
