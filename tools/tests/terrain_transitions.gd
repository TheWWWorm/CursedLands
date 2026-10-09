extends Node
const Field = preload("res://src/game/fx/terrain_transition.gd")
var checks := 0
var failures := 0
var records := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func fixture() -> EITerrain:
	var terrain := EITerrain.new()
	terrain.sectors_x=1; terrain.sectors_y=1; terrain.grid_w=33
	terrain.heights.resize(1089); terrain.land_xy.resize(1089); terrain.land_n.resize(1089); terrain.land_n.fill(Vector3.UP)
	terrain.land_tile.resize(256); terrain.tile_types.resize(64); terrain.tile_types.fill(0); terrain.tile_types[1]=2
	for y in 16:
		for x in 16: terrain.land_tile[y*16+x]=0 if x<7 else (2 if x==7 else 1)
	return terrain

func rules() -> Dictionary:
	var data := PackedByteArray(); data.resize(256)
	for k in 4: data[k]=1; data[4+k]=2
	data[8]=1; data[9]=2; data[10]=2; data[11]=1
	return {0:data}

func analytical() -> void:
	var terrain := fixture()
	# Derive corner correspondence from the renderer's original UV builder,
	# independently of the new helper's explicit R1 rotation table.
	for turn in 4:
		var expected := PackedByteArray()
		for p: Vector2i in [Vector2i(0,0),Vector2i(2,0),Vector2i(0,2),Vector2i(2,2)]:
			var uv: Vector2=terrain._tile_uv(turn<<14,p.x,p.y)[0]
			var right := uv.x>0.0625; var bottom := uv.y>0.9375
			expected.append((3 if right else 4) if bottom else (2 if right else 1))
		check(Field.world_corners(PackedByteArray([1,2,3,4]),turn)==expected,"authored original UV corner rotation "+str(turn))
	var heights := terrain.heights.duplicate(); var xy := terrain.land_xy.duplicate(); var normals := terrain.land_n.duplicate(); var codes := terrain.land_tile.duplicate()
	var field := Field.new(terrain,rules())
	check(field.admitted==16 and field.classified==16 and field.conflicting==0,"coherent two-family boundary admitted without votes")
	check(field.donors=={1:0,2:1},"each exact family uses its own present plain fill")
	check(field.tiles!=null and field.tiles.get_width()==16 and field.rows.size()==256,"one bounded RGBAF field per map")
	check((int(field.rows[8*16+7].b)&15)==10,"runtime field follows original rotated corner ownership")
	check(terrain.heights==heights and terrain.land_xy==xy and terrain.land_n==normals and terrain.land_tile==codes,"classification changes no source geometry or tile codes")
	for type_id in [1,4,5,6,7,8,10,13,14,16,-1]:
		terrain.tile_types[2]=type_id
		check(Field.new(terrain,rules()).admitted==0,"path liquid or unknown ground remains exact "+str(type_id))
	terrain.tile_types[2]=0
	for y in 16:
		for x in range(8,16): terrain.land_tile[y*16+x]=63
	field=Field.new(terrain,rules())
	check(field.admitted==0 and field.missing_donor==16 and field.tiles==null,"missing own-family donor cannot borrow related material")
	terrain.free(); terrain=fixture()
	terrain.land_tile[8*16+6]=1
	field=Field.new(terrain,rules())
	check(field.conflicting>0 and field.admitted<16,"conflicting authored shared vertices are rejected instead of voted")
	terrain.land_tile[8*16+6]=63
	field=Field.new(terrain,rules())
	check((int(field.rows[8*16+7].b)&16)!=0,"unknown neighbour guards the original-art edge")
	terrain.free(); terrain=fixture()
	var three := rules(); three[0][11]=3
	check(Field.new(terrain,three).admitted==0,"junction without its own third-family donor remains original")
	terrain.land_xy[16*33+15]=Vector2(4,0)
	field=Field.new(terrain,rules())
	check(field.rejected_geometry>0 and field.admitted<16,"folded authored XY geometry is not reconstructed")
	terrain.land_xy[16*33+15]=Vector2.ZERO; terrain.heights[16*33+15]=NAN
	check(Field.new(terrain,rules()).rejected_geometry>0,"nonfinite geometry is neutral")
	terrain.free()
	var image := Image.create(512,512,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	check(Field.Tiles.corners(image).is_empty(),"unknown artwork is never guessed from its map or ground name")
	check(Field.Tiles.corners(Image.create(512,1024,false,Image.FORMAT_RGBA8)).is_empty(),"animated strip or nonoriginal atlas dimensions are neutral")
	check(Field.new().source(EITerrain.TERRAIN_SHADER)==EITerrain.TERRAIN_SHADER,"empty helper preserves exact shader source")
	var source := Field.TransitionShader.source(EITerrain.TERRAIN_SHADER)
	check(source.count("vec3 ground_sample(")==1 and source.count("vec3 transition_original_sample(")==2,"one shared wrapper preserves live and baked original samplers")
	check(source.count("uniform sampler2D transition_tiles")==1,"one shared optional texture sampler")
	var contact := Field.TransitionShader.source(GroundContactShader.source(EIFigure.OBJECT_SHADER,true))
	check(contact.contains(Field.TransitionShader.FUNCTIONS),"contact uses byte-identical natural transition implementation")
	check(contact.contains("cliff_albedo"),"natural transitions compose with existing cliff source")
	var base := GfxDetect.base_values()
	check(int(base.gfx_terrain)==1,"existing Detailed default remains unchanged")
	for tier in range(GfxDetect.LAST+1): check(int(GfxDetect.tier_values(tier,base).gfx_terrain)<=1,"automatic tier never opts into reconstruction "+str(tier))
	for lang in ["en","ru","de"]:
		RemakeText.lang=lang
		var choices := GameData.option_choices("gfx_terrain")
		check(choices.size()==3 and (lang=="en" or choices[2]!="Natural transitions"),"three localized values "+lang)
		var panel := OptionsPanel.new(); add_child(panel)
		for label: String in choices: check(panel.text_width(label)<=160.0,"localized choice fits value column: "+lang+" "+label)
		panel.free()
	RemakeText.lang="en"
	check(GfxDetect.original_look_values(true,{},-1,base).gfx_terrain==0,"Original look clears Natural mode through the existing key")
	check(GfxDetect.original_look_values(false,{},-1,base).gfx_terrain==1,"leaving Original look restores existing Detailed default")
	GameData.options.gfx_terrain=2;GameData.save_settings()
	var saved:=ConfigFile.new()
	check(saved.load(GameData.CONFIG_PATH)==OK and saved.get_value("options","gfx_terrain",-1)==2,"Natural value persists under the existing terrain key")
	GameData.options.gfx_terrain=1;GameData.save_settings()

func maps() -> void:
	var names := ["zone1","zone11","zone15"]
	if "--transition-astral" in OS.get_cmdline_user_args(): names=["zone26","zone6"]
	for name: String in names:
		var terrain := EITerrain.load_map(name); add_child(terrain); terrain.set_process(false)
		check(terrain._transitions==null,"Detailed allocates no transition field "+name)
		var height := terrain.heights.duplicate(); var xy := terrain.land_xy.duplicate(); var codes := terrain.land_tile.duplicate()
		var field := Field.new(terrain)
		check(field.admitted<=field.classified and field.tiles!=null if field.admitted>0 else field.tiles==null,"real-map bounded allocation "+name)
		check(field.rows.size()<=Field.MAX_TILES,"real-map field memory cap "+name)
		check(terrain.heights==height and terrain.land_xy==xy and terrain.land_tile==codes,"original map geometry and rotations remain exact "+name)
		var positive := name!="zone6"
		check((field.admitted>0)==positive,"verified real-map admission "+name)
		var slots := PackedInt32Array()
		for i in field.rows.size():
			var row := field.rows[i]
			if row.a!=0 and row.r!=row.g: slots.append(i)
		var bad := 0
		for i in slots:
			var code := terrain.land_tile[i]; var row := field.rows[i]
			if not Field.ground_allowed(terrain.tile_types[code&16383]): bad+=1
			for family in field.families_at(i):
				if not field.donors.has(family): bad+=1
		check(bad==0,"every admitted transition has allowed authored ground and all own donors "+name)
		var record := {"map":name,"classified":field.classified,"admitted":field.admitted,"conflicting":field.conflicting,
			"missing_donor":field.missing_donor,"rejected_geometry":field.rejected_geometry,"junctions":field.junctions,
			"build_us":field.build_us,"bytes":(field.rows.size()+field.junction_rows.size())*16,"donors":field.donors}
		records.append(record); print("TRANSITION_MAP ",JSON.stringify(record))
		terrain.free(); await get_tree().process_frame

func _ready() -> void:
	get_window().size=Vector2i(800,600)
	for i in 3: await get_tree().process_frame
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	GameData.options.gfx_terrain=1
	Gfx.ensure_globals(); analytical(); await maps()
	TexUpscale.shutdown()
	FileAccess.open("user://terrain-transitions.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"maps":records},"\t"))
	print("TERRAIN_TRANSITIONS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
