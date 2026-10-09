extends Node
## Verified atlas identities, rotated corner placement and authored deltas.
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Families = preload("res://src/game/fx/biome_cover_tiles.gd")
var checks := 0
var failures := 0
var rows := []

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures+=1; printerr("FAIL ",label)

func stamp(value: Variant) -> String:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(var_to_bytes(value)); return hash.finish().hex_encode()

func rules() -> void:
	var t := EITerrain.new(); t.texture_size=512; t.tile_size=64
	var field := Cover.new(); var masks := PackedByteArray(); masks.resize(64); masks[0]=1
	field.families[0]=masks
	# One bare NW signature corner appears at these world corners after each
	# original rotation. Explicit oracle also catches the decoded-image V flip.
	var expected := [[1.0,0.0,0.0,0.0],[0.0,0.0,1.0,0.0],[0.0,0.0,0.0,1.0],[0.0,1.0,0.0,0.0]]
	for rotation in 4:
		var code := rotation<<14
		for y in 3:
			for x in 3:
				var uv: Vector2=t._tile_uv(code,x,y)[0]
				var e: Array=expected[rotation]
				var want:=lerpf(lerpf(e[0],e[1],x/2.0),lerpf(e[2],e[3],x/2.0),y/2.0)
				check(absf(field.bare_share({"code":code,"uv":uv})-want)<0.00001,"rotated atlas corner including edge/centre "+str(rotation))
	masks[0]=15; field.families[0]=masks; field.biome="gipat"
	var hit := {"code":0,"uv":t._tile_uv(0,1,1)[0],"type":0,"colour":Color(0.12,0.4,0.08),"height":0.3,"normal":Vector3.UP}
	check(field.weights(hit,Vector3.ZERO,Vector3(1,0,0))[Cover.Kind.FLOWER]==0,"green-looking fully bare art has no meadow flowers")
	hit.type=11; hit.colour=Color(0.43,0.32,0.20)
	check(field.weights(hit,Vector3.ZERO,Vector3(1,0,0))[Cover.Kind.DRY]==0,"fully bare dry-grass tag does not grow dry tufts")
	hit.type=3
	check(field.weights(hit,Vector3.ZERO,Vector3(1,0,0))[Cover.Kind.DRY]>0,"sand tufts retain original rule")
	hit.type=1; masks[0]=128; field.families[0]=masks
	check(field.beach_sand(hit),"a known sand-family corner qualifies a soil-tagged beach")
	check(field.bank_weights(Vector2.ONE,hit,Vector3(0.3,0,3)).w>0,"known sand art admits near-sea shells")
	hit.type=7
	check(field.bank_weights(Vector2.ONE,hit,Vector3(0.3,0,3))==Vector4.ZERO,"atlas labels do not override excluded road terrain types")
	hit.type=1; field.families.clear()
	check(not field.beach_sand(hit) and field.bare_share(hit)==0,"unknown atlas retains existing ground-type rules")
	check(Families.masks(Image.create(128,128,false,Image.FORMAT_RGBA8)).is_empty(),"unsupported atlas size adds no classification")
	for conflict in [["bz3g004",19],["bz3g005",7],["bz3g007",8],["bz3g007",28]]:
		var image := GameData.load_image(conflict[0]); var known := Families.masks(image)
		check(known.size()==64 and known[conflict[1]]==0,"ambiguous identical-art slot stays neutral "+str(conflict))
	var image := GameData.load_image("zone1000"); var known := Families.masks(image)
	check(known.size()==64,"original atlas has verified metadata")
	image.set_pixel(0,0,Color(0.01,0.02,0.03,0.04))
	check(Families.masks(image).is_empty(),"modified original art does not inherit old semantic labels")
	check(known.size()==64,"published masks survive changes to source image")
	t.free()

func indexed(records: Array) -> Dictionary:
	var result := {}
	for r: Dictionary in records: result[str(r.kind)+":"+str(r.p)]=r
	return result

func authored() -> void:
	var removed_total := 0; var added_total := 0
	for name in ["zone1","zone7","zone8","zone9","zone11","zone15"]:
		var started := Time.get_ticks_usec(); var t:=EITerrain.load_map(name); var d:=t.details
		d.set_process(false); d.prepare_grass(); var field: Variant=d._cover_field
		var prepared := Time.get_ticks_usec()-started
		var metadata: Dictionary=field.families; var payload := 0
		for data: PackedByteArray in metadata.values(): payload+=data.size()
		var removed := {}; var added := {}; var kept := 0; var examples := []; var unchanged := []; var keys := {}
		var removed_examples := 0; var added_examples := 0
		for y in 8:
			for x in 8: keys[Vector2i((x+0.5)*t.size_ei().x/64.0,(y+0.5)*t.size_ei().y/64.0)]=true
		# Include all actual coastal banks, not only a sparse grid in the sea.
		if name in ["zone7","zone8"]:
			for key: Vector2i in field.shores:
				if key.x>=0 and key.y>=0 and key.x*8<t.size_ei().x and key.y*8<t.size_ei().y: keys[key]=true
		for key: Vector2i in keys:
			field.families={}; var before:=indexed(field.records(key,[],[]))
			field.families=metadata; var after:=indexed(field.records(key,[],[]))
			for id: String in before:
				var r: Dictionary=before[id]
				if after.has(id):
					check(after[id]==r,"surviving record remains byte-for-byte equivalent "+name)
					kept+=1; unchanged.append(r)
				else:
					check(r.kind in [Cover.Kind.FLOWER,Cover.Kind.DRY],"only meadow/dry tufts are suppressed "+name)
					removed[r.kind]=int(removed.get(r.kind,0))+1; removed_total+=1
					if removed_examples<4:
						examples.append({"change":"removed","record":r,"bare_share":field.bare_share(field.dry_surface(r.p))}); removed_examples+=1
			for id: String in after:
				if before.has(id): continue
				var r: Dictionary=after[id]; var hit: Dictionary=field.dry_surface(r.p)
				check(r.kind in [Cover.Kind.WRACK,Cover.Kind.SHELL],"only verified beach debris is added "+name)
				check(not hit.is_empty() and field.beach_sand(hit),"new beach root has original sand tag or verified family "+name)
				check(field.footprint(r.p,hit,r.kind,Cover.RADII[r.kind]*r.scale),"new beach footprint retains dry/slope/material admission "+name)
				added[r.kind]=int(added.get(r.kind,0))+1; added_total+=1
				if added_examples<4:
					examples.append({"change":"added","record":r,"type":hit.type,"family_mask":field.family_mask(hit)}); added_examples+=1
		rows.append({"case":"authored","map":name,"load_prepare_us":prepared,"native_sampler":field.native!=null,"chunks":keys.size(),"metadata_payload_bytes":payload,"removed":removed,"added":added,"kept":kept,"kept_hash":stamp(unchanged),"examples":examples})
		print("COVER_FAMILIES ",JSON.stringify(rows[-1]));t.free()
	check(removed_total>0,"authored transition rules suppress existing misplaced tufts")
	check(added_total>0,"authored sand-family shore rule adds eligible beach debris")

func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option]=0
	GameData.options["gfx_biome_cover"]=1; Gfx.ensure_globals()
	rules();authored();TexUpscale.shutdown();await get_tree().process_frame
	FileAccess.open("user://biome-cover-families.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("COVER_FAMILIES checks=",checks," failures=",failures);get_tree().quit(1 if failures else 0)
