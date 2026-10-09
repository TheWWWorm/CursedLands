extends Node
## Can run against the pre-shore pack: guards the established dry random stream.
func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option] = 0
	GameData.options["gfx_biome_cover"] = 1; Gfx.ensure_globals()
	var rows := []
	for name in ["zone1","zone11","zone15"]:
		var t := EITerrain.load_map(name); var d := t.details; d.set_process(false); d.prepare_grass()
		var original: Array[Dictionary] = []
		for y in 8:
			for x in 8:
				var key := Vector2i((x+0.5)*t.size_ei().x/64.0,(y+0.5)*t.size_ei().y/64.0)
				for r: Dictionary in d._cover_field.records(key,[],[]):
					if r.kind<7: original.append(r)
		var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(var_to_bytes(original))
		rows.append({"map":name,"dry_count":original.size(),"dry_hash":h.finish().hex_encode()}); print("DRY_FINGERPRINT ",JSON.stringify(rows[-1]))
		t.free()
	TexUpscale.shutdown(); await get_tree().process_frame
	FileAccess.open("user://biome-cover-dry-fingerprint.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"\t"))
	get_tree().quit()
