extends Node
## Read-only authored shore eligibility; never infers sea identity or sand from colour.
func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics"]: GameData.options[option] = 0
	GameData.options["gfx_biome_cover"] = 1; Gfx.ensure_globals()
	var t := EITerrain.load_map("zone1"); var d := t.details; d.prepare_grass(); var f := d._cover_field
	GameData.load_image("zone1000").save_png("user://zone1-shore-atlas.png")
	var liquids := {}; var markers := {}; var roots := {}; var samples := []
	for i in t.water_mat.size():
		var key := "%d:%d" % [t.water_mat[i],t.liquid_ground[i]]
		liquids[key] = int(liquids.get(key,0))+1
	for points: PackedVector4Array in f.shores.values():
		for point: Vector4 in points: markers[int(point.w)] = int(markers.get(int(point.w),0))+1
	for key: Vector2i in f.shores:
		for y in 8:
			for x in 8:
				var p := Vector2(key)*8+Vector2(x+0.37,y+0.47); var hit := f.dry_surface(p)
				if hit.is_empty(): continue
				var nearby := f.shore(p)
				if nearby.z!=3 or nearby.x>5: continue
				var category := "%d:%s" % [hit.type,"low" if hit.height-nearby.y<0.8 else "high"]
				roots[category] = int(roots.get(category,0))+1
				if samples.size()<12 and hit.height-nearby.y<0.8: samples.append({"p":str(p),"type":hit.type,"code":hit.code,"above":hit.height-nearby.y,"distance":nearby.x})
	var out := {"liquids":liquids,"markers":markers,"roots":roots,"samples":samples,"prefix":t.resource_prefix}
	FileAccess.open("user://shore-census.json",FileAccess.WRITE).store_string(JSON.stringify(out,"\t")); print("SHORE_CENSUS ",JSON.stringify(out))
	t.free(); TexUpscale.shutdown(); await get_tree().process_frame; get_tree().quit()
