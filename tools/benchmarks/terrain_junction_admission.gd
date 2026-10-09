extends "terrain_junction_census.gd"
## Production field construction over the same read-only original map parser.
## Earlier census counts are external prerequisites, not a shader/visual oracle.
const EXPECTED := {"cursed_lands":[38,8374,36],"lost_in_astral":[51,8653,35]}

func admission(terrain: EITerrain) -> Dictionary:
	var field:=Field.new(terrain)
	var atlas_rules: Dictionary={};var used: Dictionary={}
	for code: int in terrain.land_tile:used[code&16383]=true
	for atlas in int(terrain.get_meta("textures_count")):
		atlas_rules[atlas]=Field.Tiles.corners(GameData.load_image("%s%03d" % [terrain.resource_prefix,atlas]))
	var junction_counts: Dictionary={3:0,4:0};var wrong_family:=0;var wrong_donor:=0;var wrong_packing:=0
	for index in field.rows.size():
		if field.rows[index].a>=0:continue
		var families:=field.families_at(index);var count:=families.size()
		junction_counts[count]=int(junction_counts.get(count,0))+1
		var slot:=terrain.land_tile[index]&16383
		var authored: PackedByteArray=atlas_rules[slot>>6].slice((slot&63)*4,((slot&63)+1)*4)
		var expected:=PackedByteArray()
		for family in authored:
			if not expected.has(family):expected.append(family)
		expected.sort()
		wrong_family+=int(families!=expected or count not in [3,4])
		var metadata: Color=field.junction_rows[index]
		for k in count:
			var family: int=families[k];var donor: int=field.donors.get(family,-1)
			var donor_ok:=donor>=0 and used.has(donor)
			if donor_ok:
				var donor_corners: PackedByteArray=atlas_rules[donor>>6].slice((donor&63)*4,((donor&63)+1)*4)
				donor_ok=donor_corners.size()==4 and donor_corners.count(family)==4
			wrong_donor+=int(not donor_ok)
			var encoded:=int(field.rows[index][k]) if k<2 else int(metadata[k])&32767
			wrong_packing+=int(encoded!=donor+1)
	check(wrong_family==0,terrain.map_name+": every admitted junction retains every original family")
	check(wrong_donor==0 and wrong_packing==0,terrain.map_name+": packed donors are exact plain own-family tiles used on this map")
	check(junction_counts[3]==int(field.admitted_families[3]) and junction_counts[4]==int(field.admitted_families[4]),terrain.map_name+": complete production family-count partition")
	var bytes:=0
	if field.tiles:
		var planes:=2 if field.junctions>0 else 1
		bytes=field.tiles.get_image().get_data_size()
		check(field.tiles.get_width()==field.tile_size.x and field.tiles.get_height()==field.tile_size.y*planes and bytes==field.rows.size()*16*planes and bytes<=Field.MAX_TILES*32,terrain.map_name+": exact bounded field allocation")
	else:check(field.admitted==0,terrain.map_name+": no unused texture allocation")
	check(terrain.get_child_count()==0 and terrain._atlases==null and terrain._transitions==null,terrain.map_name+": construction changes no map-owned rendered resources")
	return {"map":terrain.map_name,"tiles":field.rows.size(),"admitted_families":field.admitted_families,"junctions":field.junctions,"bytes":bytes,"build_us":field.build_us,"rejected_support_geometry":field.rejected_support_geometry}

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	var three:=0;var four:=0;var largest:=0
	for name: String in GameData.map_names():
		var terrain:=read_map(name)
		if terrain==null:continue
		var row:=admission(terrain);rows.append(row)
		three+=int(row.admitted_families[3]);four+=int(row.admitted_families[4]);largest=maxi(largest,row.bytes)
		terrain.free()
	var expected: Array=EXPECTED[GameData.campaign_id]
	check(rows.size()==int(expected[0]) and three==int(expected[1]) and four==int(expected[2]),"production admission matches the earlier independent original-map census")
	FileAccess.open("user://terrain-junction-admission.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"campaign":GameData.campaign_id,"maps":rows,"three":three,"four":four,"largest_field_bytes":largest,"scope":"Metadata, provenance and allocation over all mounted maps; not visual, timing or device acceptance."},"\t")+"\n")
	print("TERRAIN_JUNCTION_ADMISSION ",checks," checks ",failures," failures; ",three," three / ",four," four")
	get_tree().quit(1 if failures else 0)
