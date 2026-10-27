extends "terrain_cliffs.gd"
const Ground = preload("res://src/game/fx/terrain_cliff_ground_tiles.gd")

func authored(image: Image) -> PackedByteArray:
	var copy := image.duplicate() as Image
	if copy.is_compressed(): copy.decompress()
	copy.clear_mipmaps(); copy.convert(Image.FORMAT_RGBA8)
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(copy.get_data())
	var digest := hash.finish().hex_encode()
	return String(Ground.IDENTITIES[digest]).hex_decode() if Ground.IDENTITIES.has(digest) else Rules.Natural.corners(image)

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	for map in ["zone17","zone18","zone19","bz14h"]:
		var t := EITerrain.load_map(map); add_child(t); t.set_process(false)
		var field := Field.new(t)
		var identities := {}; var plain := 0; var missing := 0; var forbidden := 0
		for atlas in int(t.get_meta("textures_count",0)):
			var image := GameData.load_original_image("%s%03d" % [t.resource_prefix,atlas])
			identities[atlas]=authored(image)
		for tile in t.land_tile.size():
			var code := t.land_tile[tile]&16383
			var corners: PackedByteArray=identities.get(code>>6,PackedByteArray())
			if corners.size()!=256: continue
			var family := corners[(code&63)*4]
			if corners.slice((code&63)*4,((code&63)+1)*4).count(family)!=4:continue
			var dry := family>=200 and family<200+Ground.FAMILIES.size()
			var sand := family>=16 and family<=25
			if not dry and not sand:continue
			var x := (tile%field.tile_size.x)*2; var y := (tile/field.tile_size.x)*2
			if not field._valid_tile(t,x,y):continue
			if not TerrainCliff.Blends.ground_allowed(t.tile_types[code]):
				if field.eligible[tile]>0:forbidden+=1
				continue
			var steep := false
			for dy in 2:
				for dx in 2:
					var a := (y+dy)*t.grid_w+x+dx
					var n := (field._point(t,a+1)-field._point(t,a)).cross(field._point(t,a+t.grid_w)-field._point(t,a)).normalized()
					if n.y<0.4:steep=true
			if not steep:continue
			plain+=1
			if field.eligible[tile]==0:missing+=1
		check(plain>0,"original desert map has steep dry natural tiles: "+map)
		check(missing==0,"steep sand, soil and rubble receive wall coordinates: %s %d/%d"%[map,plain-missing,plain])
		check(forbidden==0,"liquid/snow/unknown ground remains outside desert projection: "+map)
		print("DESERT_MAP ",JSON.stringify({"map":map,"expected":plain,"missing":missing,"admitted":field.admitted}))
		t.free();await get_tree().process_frame
	var image := GameData.load_original_image("zone17000")
	check(not Rules.blend_corners(image).is_empty(),"original desert atlas has verified material corners")
	if image.is_compressed():image.decompress()
	image.set_pixel(0,0,Color.MAGENTA)
	check(Rules.blend_corners(image).is_empty(),"modified artwork does not inherit desert identity")
	TexUpscale.shutdown()
	print("DESERT_CLIFFS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
