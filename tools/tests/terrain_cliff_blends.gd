extends "res://tools/tests/terrain_cliffs.gd"
const Blends = preload("res://src/game/fx/terrain_cliff_blends.gd")
func _ready() -> void:
	analytic()
	var upright:=fixture(10.0);upright.land_n.fill(Vector3.UP)
	check(Field.new(upright,rules()).admitted>0,"geometrically steep faces remain admitted with upward authored lighting normals")
	upright.free()
	var terrain:=fixture()
	var corners:=PackedByteArray();corners.resize(256)
	for k in 4:corners[k]=31;corners[4+k]=36;corners[8+k]=31
	corners[8]=36
	var metadata:={0:corners}
	terrain.land_tile.fill(63);terrain.land_tile[0]=0;terrain.land_tile[255]=1
	var at:=8*16+8
	for rotation in 4:
		terrain.land_tile[at]=2|(rotation<<14)
		var rows:=Blends.build(terrain,metadata)
		check(rows[at]==[Color(1,1,2,1),Color(1,1,1,2),Color(1,2,1,1),Color(2,1,1,1)][rotation],"rock donors and authored world corners retain rotation %d"%rotation)
		check(rows[0].a==0 and rows[255].a==0 and rows[1].a==0,"plain and unknown tiles keep their original sampling")
	terrain.land_tile[255]=63
	check(Blends.build(terrain,metadata)[at].a==0,"missing on-map donor leaves the painted transition untouched")
	terrain.land_tile[255]=1;terrain.land_tile[at-1]=0
	check(Blends.build(terrain,metadata)[at].a==0,"conflicting shared material corner cannot enter projection")
	terrain.land_tile[at-1]=63
	for ground in [9,10,12,13,14,16,-1]:
		terrain.tile_types[2]=ground
		check(Blends.build(terrain,metadata)[at].a==0,"snow, ice, liquid and unknown ground stay authored: %d"%ground)
	terrain.tile_types[2]=2
	corners[8]=0
	check(Blends.build(terrain,{0:corners})[at].a==0,"unknown family cannot be inferred from adjacent rock")
	check(Blends.build(terrain,{})[at].a==0,"unverified original atlas remains neutral")
	check(not Blends.supported(0) and not Blends.supported(255),"out-of-range families remain neutral")
	check(Blends.supported(31) and Blends.supported(36),"both original cave stone families are supported")
	corners[8]=36
	for k in 4:corners[12+k]=253;corners[16+k]=254
	corners[20]=31;corners[21]=36;corners[22]=253;corners[23]=254
	terrain.land_tile[253]=3;terrain.land_tile[254]=4;terrain.land_tile[at]=5
	check(Blends.build(terrain,{0:corners})[at]==Color(5,4,1,2),"three/four-material cliff corners keep their own on-map donors")
	var image:=GameData.load_original_image("zone5_1000")
	var cave:=Field.Tiles.blend_corners(image)
	check(cave.size()==256 and cave.slice(16*4,17*4).has(254) and cave.slice(32*4,33*4).has(254),"reported striped tiles have fingerprinted dirt/stone identities")
	if image!=null:
		var altered:=image.duplicate() as Image
		if altered.is_compressed():altered.decompress()
		altered.set_pixel(0,0,Color.MAGENTA)
		check(Field.Tiles.blend_corners(altered).is_empty(),"modified cave artwork cannot inherit the original identity")
	terrain.free()
	await maps()
	TexUpscale.shutdown()
	print("CLIFF_BLENDS ",checks," checks ",failures," failures")
	get_tree().quit(0 if failures==0 else 1)
