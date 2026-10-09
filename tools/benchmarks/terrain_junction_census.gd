extends Node
## Read-only candidate census for the remaining Natural-mode junction work.
## Loads original headers/vertices/tile codes, but no meshes, GPU textures or
## transition field. Eligibility below is a prerequisite, not visual acceptance.
const Field = preload("res://src/game/fx/terrain_transition.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func read_map(name: String) -> EITerrain:
	var archive := EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr" % name))
	check(archive != null,name+": archive opens")
	if archive == null: return null
	var terrain := EITerrain.new()
	terrain.map_name = name
	terrain.resource_prefix = EITerrain.resolve_map_prefix(archive,name)
	var valid := terrain._parse_header(archive.read(terrain.resource_prefix+".mp"))
	check(valid,name+": original header")
	if not valid: terrain.free(); return null
	for sy in terrain.sectors_y:
		for sx in terrain.sectors_x:
			var data := archive.read("%s%03d%03d.sec" % [terrain.resource_prefix,sx,sy])
			var valid_sector := data.size()>=5 and data.decode_u32(0)==EITerrain.SEC_MAGIC
			check(valid_sector,name+": original sector "+str(Vector2i(sx,sy)))
			if not valid_sector: continue
			var offset := 5+EITerrain.VERTS*EITerrain.VERTS*8*(2 if data[4]!=0 else 1)
			check(data.size()>=offset+512,name+": complete land vertex/tile payload")
			if data.size()<offset+512: continue
			terrain._read_vertices(data,5,sx,sy,true)
			terrain._record_ground(terrain._read_u16s(data,offset),sx,sy)
	return terrain

func census(terrain: EITerrain) -> Dictionary:
	var width := terrain.sectors_x*16
	var height := terrain.sectors_y*16
	var count := terrain.land_tile.size()
	var rules := {}; var identities := {}
	if terrain.texture_size==512 and terrain.tile_size==64:
		for atlas in int(terrain.get_meta("textures_count")):
			var pixels := GameData.load_image("%s%03d" % [terrain.resource_prefix,atlas])
			var corners := Field.Tiles.corners(pixels)
			if not corners.is_empty():
				rules[atlas]=corners
				var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(pixels.get_data())
				identities[atlas]=digest.finish().hex_encode()
	var signatures := PackedByteArray(); signatures.resize(count*4)
	var shared := PackedByteArray(); shared.resize((width+1)*(height+1))
	var uses := {}; var donors := {}; var known := 0
	for i in count:
		var code := terrain.land_tile[i]; var slot := code&16383; var atlas := slot>>6
		if code<0 or code>65535 or slot>=terrain.tile_types.size() or not Field.ground_allowed(terrain.tile_types[slot]) or not rules.has(atlas): continue
		var authored: PackedByteArray = rules[atlas].slice((slot&63)*4,((slot&63)+1)*4)
		if authored.has(0): continue
		var local := Field.world_corners(authored,code>>14)
		known+=1
		for k in 4:
			signatures[i*4+k]=local[k]
			var vertex := (int(i/width)+(k>>1))*(width+1)+i%width+(k&1)
			if shared[vertex]==0: shared[vertex]=local[k]
			elif shared[vertex]!=local[k]: shared[vertex]=255
		if local.count(local[0])==4: uses[slot]=int(uses.get(slot,0))+1
	for slot: int in uses:
		var family: int = rules[slot>>6][(slot&63)*4]
		var old: int = donors.get(family,-1)
		if old<0 or uses[slot]>uses[old] or (uses[slot]==uses[old] and slot<old): donors[family]=slot
	var totals := {"1":0,"2":0,"3":0,"4":0}
	var candidates := {"3":0,"4":0}
	var rejected := {"conflicting_corner":0,"missing_donor":0,"invalid_geometry":0}
	var sites := {"3":[],"4":[]}; var geometry := Field.new()
	for i in count:
		if signatures[i*4]==0: continue
		var local := signatures.slice(i*4,i*4+4); var unique := {}
		for family: int in local: unique[family]=true
		totals[str(unique.size())]+=1
		if unique.size()<3: continue
		var missing := false; var conflict := false
		for family: int in unique:
			if not donors.has(family): missing=true
		for k in 4:
			if shared[(int(i/width)+(k>>1))*(width+1)+i%width+(k&1)]==255: conflict=true
		var valid := geometry._valid_tile(terrain,(i%width)*2,int(i/width)*2)
		if missing: rejected.missing_donor+=1
		if conflict: rejected.conflicting_corner+=1
		if not valid: rejected.invalid_geometry+=1
		if missing or conflict or not valid: continue
		candidates[str(unique.size())]+=1
		var family_count := str(unique.size())
		if sites[family_count].size()<8:
			var x := (i%width)*2+1; var y := int(i/width)*2+1
			var center := Vector2(x,y)+terrain.land_xy[y*terrain.grid_w+x]
			var families := []; var donor_slots := []
			for family: int in unique:
				families.append(Field.Tiles.FAMILIES[family]);donor_slots.append(donors[family])
			sites[family_count].append({"tile":[i%width,int(i/width)],"focus_ei":[center.x,center.y,terrain.heights[y*terrain.grid_w+x]],
				"world_corner_ids":Array(local),"families":families,"donor_slots":donor_slots,"original_code":terrain.land_tile[i]})
	check(known==int(totals["1"])+int(totals["2"])+int(totals["3"])+int(totals["4"]),terrain.map_name+": classified partition")
	check(candidates["3"]<=totals["3"] and candidates["4"]<=totals["4"],terrain.map_name+": candidate bounds")
	check(terrain.get_child_count()==0 and terrain._atlases==null and terrain._transitions==null,terrain.map_name+": no rendered resources")
	return {"map":terrain.map_name,"prefix":terrain.resource_prefix,"tile_count":count,"verified_atlases":identities,
		"classified_families":totals,"junction_candidates":candidates,"rejections_overlap":rejected,"sites":sites}

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	for name: String in GameData.map_names():
		var terrain := read_map(name)
		if terrain==null: continue
		var row := census(terrain); rows.append(row)
		print("JUNCTION_MAP ",JSON.stringify({"map":name,"classified":row.classified_families,"candidates":row.junction_candidates}))
		terrain.free()
	var report := {"checks":checks,"failures":failures,"campaign":GameData.campaign_id,"maps":rows,
		"scope":"Original authored data only; candidate prerequisites, not a rendering or performance claim."}
	FileAccess.open("user://terrain-junction-census.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TERRAIN_JUNCTION_CENSUS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
