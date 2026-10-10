extends Node
const Field = preload("res://src/game/fx/terrain_cliff.gd")
const Rules = preload("res://src/game/fx/terrain_cliff_tiles.gd")
var checks := 0
var failures := 0
var records := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func fixture(slope := 2.0) -> EITerrain:
	var terrain := EITerrain.new()
	terrain.sectors_x=1; terrain.sectors_y=1; terrain.grid_w=33
	terrain.heights.resize(33*33); terrain.land_xy.resize(33*33); terrain.land_n.resize(33*33)
	terrain.land_tile.resize(16*16); terrain.tile_types.resize(64); terrain.tile_types.fill(2)
	for y in 33:
		for x in 33:
			terrain.heights[y*33+x]=x*slope
			terrain.land_n[y*33+x]=Vector3(-slope,1,0).normalized()
	return terrain

func rules() -> Dictionary:
	var values := PackedByteArray(); values.resize(64); values[0]=1
	return {0:values}

func analytic() -> void:
	for degrees in [0.0,20.0,39.0,40.0]:
		check(Field.side_weight(Vector3(sin(deg_to_rad(degrees)),cos(deg_to_rad(degrees)),0),0)<0.00001,"walkable slope retains top projection "+str(degrees))
	check(is_equal_approx(Field.side_weight(Vector3(1,0,0),0),1.0),"vertical cliff admits full side projection")
	check(Field.side_weight(Vector3(1,0,0),1.0)==0,"flat neighbouring facets protect a tilted ledge normal")
	check(Field.side_weight(Vector3(NAN,1,0),0)==0 and Field.side_weight(Vector3.ZERO,0)==0,"invalid normal is neutral")
	var terrain := fixture()
	var heights := terrain.heights.duplicate(); var xy := terrain.land_xy.duplicate(); var normals := terrain.land_n.duplicate()
	var field := Field.new(terrain,rules())
	check(field.classified==256 and field.admitted==256 and field.eligible.count(255)==256,"verified coherent rock slope is admitted")
	check(field.tiles!=null and field.flatness!=null,"admitted rock owns two bounded field textures")
	check(terrain.heights==heights and terrain.land_xy==xy and terrain.land_n==normals,"classification preserves all original geometry and normals")
	for rotation in 4:
		terrain.land_tile.fill(rotation<<14)
		var rotated := Field.new(terrain,rules())
		check(rotated.admitted==field.admitted and rotated.guards==field.guards,"plain rock eligibility retains authored rotation "+str(rotation))
	terrain.land_tile.fill(1)
	check(Field.new(terrain,rules()).admitted==0,"transition/path/unknown slots stay neutral despite rock ground type")
	terrain.land_tile.fill(0); terrain.tile_types[0]=12
	check(Field.new(terrain,rules()).admitted==0,"snow metadata keeps reused rock art original")
	terrain.tile_types[0]=16
	check(Field.new(terrain,rules()).admitted==0,"unknown ground metadata stays neutral")
	terrain.tile_types[0]=2; terrain.land_tile.fill(65536)
	check(Field.new(terrain,rules()).admitted==0,"unsupported packed tile flags are not interpreted as ordinary rock")
	terrain.land_tile.fill(0)
	terrain.land_xy[16*33+16]=Vector2(3,0)
	var folded := Field.new(terrain,rules())
	check(folded.rejected_geometry>0 and folded.admitted<field.admitted,"folded authored XY triangles stay neutral")
	terrain.land_xy[16*33+16]=Vector2.ZERO; terrain.heights[16*33+16]=NAN
	check(Field.new(terrain,rules()).rejected_geometry>0,"nonfinite source vertices cannot enter projection")
	terrain.heights[16*33+16]=32.0; terrain.land_n[16*33+16]=Vector3(NAN,1,0)
	check(Field.new(terrain,rules()).rejected_geometry>0,"nonfinite authored normals cannot enter projection")
	terrain.free()
	terrain=fixture(0)
	terrain.land_n.fill(Vector3(1,0,0))
	field=Field.new(terrain,rules())
	check(field.admitted==0 and field.tiles==null and field.flatness==null,"flat ledge guard prevents phantom cliff and GPU allocations")
	terrain.free()
	var image := Image.create(512,512,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	check(Rules.masks(image).is_empty(),"unknown atlas is not inferred from its name, colour or ground type")
	check(Rules.masks(Image.create(1024,1024,false,Image.FORMAT_RGBA8)).is_empty(),"nonoriginal dimensions are unclassified")
	var original := EITerrain.TERRAIN_SHADER
	check(Field.new().source(original)==original,"empty feature returns byte-identical source")
	var source: String = Field.CliffShader.source(original)
	check(source.contains("#define EI_TERRAIN_CLIFFS") and source.count("vec3 cliff_albedo(")==1,"one shared projection implementation per enabled land shader")
	check(source.contains("* fade * (1.0-cliff_planes.y)"),"stretched painted normal relief fades with side colour")
	check(source.find("c=cliff_albedo")>source.find("c = clamp(c +") and source.find("c=cliff_albedo")<source.find("float mac ="),"projection follows contrast and shares macro/weather response")
	check(not GroundContactShader.source(EIFigure.OBJECT_SHADER).contains("cliff_albedo"),"default contact source does not compile extra sampling")
	var contact := GroundContactShader.source(EIFigure.OBJECT_SHADER,true)
	check(contact.count("vec3 cliff_albedo(")==1 and contact.count("contact_ground_light(grid,height,camera,projection,result.normal,result.diffuse,result.specular,relief_frame,height_gradient,compression,result.light_inputs);")==1,"contact uses one shared projection and one lighting query")

func maps() -> void:
	var names := ["zone1","zone8","zone11","zone13","zone15"]
	if "--cliff-census" in OS.get_cmdline_user_args():
		names.clear()
		for name: String in GameFiles.files(GameData.root.path_join("maps")):
			if name.to_lower().begins_with("zone") and name.get_extension().to_lower()=="mpr": names.append(name.get_basename())
		names.sort()
	var identity_checked := false
	for map: String in names:
		if not GameFiles.exists(GameData.root.path_join("maps/"+map+".mpr")): continue
		var terrain := EITerrain.load_map(map)
		check(terrain!=null,"real map loaded "+map)
		if terrain==null: continue
		add_child(terrain); terrain.set_process(false)
		check(terrain._cliffs==null,"default-off real map allocates no cliff helper "+map)
		var heights := terrain.heights.duplicate(); var xy := terrain.land_xy.duplicate(); var normals := terrain.land_n.duplicate()
		var field := Field.new(terrain)
		check(terrain.heights==heights and terrain.land_xy==xy and terrain.land_n==normals,"real map geometry remains exact "+map)
		check(field.admitted<=field.classified and (field.tiles!=null)==(field.admitted>0),"bounded admitted data and GPU allocation "+map)
		check(field.guards.size()<=Field.MAX_VERTICES and field.eligible.size()<=Field.MAX_VERTICES/4,"bounded field memory "+map)
		if not identity_checked:
			for atlas in int(terrain.get_meta("textures_count",0)):
				var image := GameData.load_image("%s%03d"%[terrain.resource_prefix,atlas])
				var mask := Rules.masks(image)
				if mask.is_empty(): continue
				check(mask.size()==64 and mask.count(1)>0,"original image fingerprint admits known plain rock")
				var modified := image.duplicate() as Image
				if modified.is_compressed(): modified.decompress()
				modified.clear_mipmaps(); modified.convert(Image.FORMAT_RGBA8)
				var pixel := modified.get_pixel(0,0); pixel.r=0.0 if pixel.r>0.5 else 1.0; modified.set_pixel(0,0,pixel)
				check(Rules.masks(modified).is_empty(),"one modified pixel invalidates original identity")
				identity_checked=true; break
		var row := {"map":map,"prefix":terrain.resource_prefix,"size":str(field.grid_size),"classified":field.classified,"admitted":field.admitted,
			"rejected_geometry":field.rejected_geometry,"build_us":field.build_us,"examples":field.examples}
		records.append(row); print("CLIFF_MAP ",JSON.stringify(row))
		terrain.free(); await get_tree().process_frame

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.merge({"confine_mouse":0,"vsync":0,"auto_graphics":0,"gfx_terrain_cliffs":0},true)
	Gfx.ensure_globals(); analytic(); await maps()
	TexUpscale.shutdown()
	FileAccess.open("user://terrain-cliffs.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"maps":records},"\t"))
	print("TERRAIN_CLIFFS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
