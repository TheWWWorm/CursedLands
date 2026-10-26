extends "res://tools/tests/terrain_cliff_mesh.gd"
## Snow uses its original artwork; only steep, identified natural surfaces
## may borrow the bounded contour mesh shared by raster, PT and deformation.
func snow_fixture() -> EITerrain:
	var reference := EITerrain.load_map("zone12")
	if reference == null: return null
	var code := -1
	for atlas in int(reference.get_meta("textures_count",0)):
		var corners := Rules.blend_corners(GameData.load_original_image("%s%03d" % [reference.resource_prefix,atlas]))
		if corners.size()!=256: continue
		for slot in 64:
			var type_id:=atlas*64+slot
			if type_id>=reference.tile_types.size():continue
			var ground:=reference.tile_types[type_id]
			if not ground in [9,12] and not Field.Blends.ground_allowed(ground):continue
			var family: int=corners[slot*4]
			if family in [26,27] and corners.slice(slot*4,slot*4+4).count(family)==4:
				code=atlas*64+slot;break
		if code>=0:break
	check(code>=0,"original winter atlas identifies a plain snow surface")
	if code<0:reference.free();return null
	var terrain:=fixture(0)
	terrain.resource_prefix=reference.resource_prefix
	terrain.set_meta("textures_count",reference.get_meta("textures_count"))
	terrain.tile_types=reference.tile_types.duplicate()
	terrain.land_tile.fill(code)
	print("SNOW_SOURCE ",reference.resource_prefix," code=",code," ground=",terrain.tile_types[code])
	for y in 33:
		for x in 33:terrain.heights[y*33+x]=16.0 if x+y>=32 else 0.0
	reference.free()
	return terrain

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	Gfx.ensure_globals()
	var terrain:=snow_fixture()
	if terrain!=null:
		var source:=source_mesh(terrain)
		var original:=source.duplicate(true)
		var collision:=terrain.heights.duplicate()
		var field:=Field.new(terrain)
		check(field.admitted==0 and field.source(EITerrain.TERRAIN_SHADER)==EITerrain.TERRAIN_SHADER,
			"snow keeps its authored material and texture projection")
		check(field.geometry!=null,"identified tall snowy hills receive contour refinement")
		if field.geometry!=null:
			field.geometry.prepare(source)
			# A visible ridge bevel must inset its cosmetic tip. Preserve the
			# original source/collision below and bound only the presentation.
			inspect(source,field.geometry.arrays(source),false,0.30002)
			check(source==original and terrain.heights==collision,"snow collision heights and source mesh stay exact")
			var sector:=EITerrainSector.new();sector.configure(source,StandardMaterial3D.new(),6,false)
			sector.set_cliff_geometry(field.geometry)
			check(sector.visual_arrays()==field.geometry.arrays(source),"raster and PT receive identical snow contours")
			sector.set_cliff_geometry(null)
			check(sector.visual_arrays()==original,"disabling refinement restores original snow geometry")
			sector.free()
		# Art identity alone must never turn ice or water into rounded cliffs.
		terrain.heights.fill(0.0)
		check(Field.new(terrain).geometry==null,"flat snow allocates no contour mesh")
		terrain.heights=collision
		var slot:=terrain.land_tile[0]&16383
		for ground in [10,13,14,16]:
			terrain.tile_types[slot]=ground
			check(Field.new(terrain).geometry==null,"water, ice and unknown metadata stay unchanged: %d"%ground)
		terrain.free()
	TexUpscale.shutdown()
	print("SNOW_CONTOURS ",checks," checks ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
