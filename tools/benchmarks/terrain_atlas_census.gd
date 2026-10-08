extends Node
## Read the installed map headers without creating terrain or GPU resources.
func _ready() -> void:
	var rows := []; var counts := {}; var missing := []
	for map_name: String in GameData.map_names():
		var arc := EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr" % map_name))
		if arc == null: missing.append(map_name); continue
		var prefix := EITerrain.resolve_map_prefix(arc,map_name)
		var header := arc.read(prefix+".mp")
		if header.size() < 38 or header.decode_u32(0) != EITerrain.MP_MAGIC:
			missing.append(map_name); continue
		var layers := header.decode_u32(16)
		var size := header.decode_u32(20); var tile := header.decode_u32(28)
		counts[layers] = int(counts.get(layers,0))+1
		rows.append({"map":map_name,"prefix":prefix,"layers":layers,"source_size":size,"tile_size":tile,
			"padded_size":size/tile*(tile+2*EITerrain.TERRAIN_GUTTER) if tile > 0 else 0})
	var report := {"maps":rows,"layer_counts":counts,"invalid_headers":missing}
	FileAccess.open("user://terrain-atlas-census.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TERRAIN_ATLAS_CENSUS ",JSON.stringify({"maps":rows.size(),"layer_counts":counts,"invalid_headers":missing}))
	get_tree().quit(0 if missing.is_empty() else 1)
