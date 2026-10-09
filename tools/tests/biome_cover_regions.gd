extends "biome_cover.gd"
## Authored habitat/geometry contracts and regional rendering/lifetime checks.
const Regions = preload("res://src/game/fx/biome_cover_regions.gd")


func regional_rules() -> void:
	var boxes:=TerrainDetails.new()
	boxes._index_scenery_box(AABB(Vector3.ZERO,Vector3.ONE),Transform3D.IDENTITY)
	check(not boxes._scenery[Vector2i.ZERO][0].has("solid"),"cover-off grass keeps its original scenery record")
	boxes._scenery.clear(); boxes._cover=true
	boxes._index_scenery_box(AABB(Vector3.ZERO,Vector3.ONE),Transform3D.IDENTITY)
	check(boxes._scenery[Vector2i.ZERO][0].solid==AABB(Vector3.ZERO,Vector3.ONE),"regional walls retain unexpanded authored bounds")
	boxes.free()
	var r := Regions.new(); r.cave=true
	for model in ["unhusk","unhuzm","UNMOSK2","unmozo0","unmocu","unmoba1"]: check(r.undead(model),"authored undead model "+model)
	for model in ["unmogo2","unmoel0","unanwira","unmos","unmosk\ufffdx"]: check(not r.undead(model),"unrelated/malformed model "+model)
	var rock := {"type":2,"colour":Color(0.25,0.23,0.20)}
	var dry := r.weights(rock,Vector4(INF,5,0,0),1)
	var lava := r.weights(rock,Vector4(0.5,5,0,0),1)
	var damp := r.weights(rock,Vector4(INF,-0.5,0.8,0),1)
	check(dry[0]==0 and lava[0]>0 and lava[3]>0,"lava bands supply ash and crust")
	check(dry[4]==0 and damp[4]>0 and damp[6]>0 and damp[8]>0,"damp moss/fern/mushroom habitat")
	check(damp[14]>0 and dry[14]==0,"webs require a corner")
	check(dry[10]>0 and dry[11]>0 and dry[15]>0,"rock supports slabs/rubble/crystals")
	check(dry[12]==0 and r.weights(rock,Vector4(INF,5,0,1),1)[12]>0,"bones require authored undead affinity")
	for type in [6,7,8,9,10,12,13,14,15]:
		check(r.weights({"type":type},Vector4(0,-0.5,1,1),1).count(0.0)==Regions.COUNT,"liquid/road/ice/snow never gets cave clutter "+str(type))
	var d := fixture(); var field := d._cover_field
	field.biome="dead_city"
	var leaf := field.weights({"type":1,"colour":Color(0.3,0.25,0.1)},Vector3(0,0,1),Vector3.ZERO)
	check(leaf[2]>0 and leaf[1]>0 and leaf[6]>0,"Dead City bare wood supplies yellow litter and sparse dry plants")
	check(field.weights({"type":1,"colour":Color(0.3,0.25,0.1)},Vector3(0,1,0),Vector3.ZERO)[2]==0,"conifers do not become yellow leaf sources")
	field.native=null; field.heights.fill(0); field.xy.fill(Vector2.ZERO); field.water.fill(-INF); field.surface.fill(-INF)
	field.ground.fill(2); field.tiles.fill(0); field.regions.cave=true
	var h := field.dry_surface(Vector2(12,12))
	check(r.wall(field,Vector2(12,12),0)==Vector2(5,0),"open floor is not a wall/corner")
	r.walls[Vector2i(1,1)]=[{"inverse":Transform3D.IDENTITY,"box":AABB(Vector3(12.4,0,-16),Vector3(0.2,3,8))},
		{"inverse":Transform3D.IDENTITY,"box":AABB(Vector3(8,0,-12.6),Vector3(8,3,0.2))}]
	check(r.wall(field,Vector2(12,12),0)==Vector2(0.5,1),"perpendicular authored solids form a corner")
	r.liquids[Vector2i(1,1)]=PackedVector4Array([Vector4(13,0,12,2)])
	check(r.habitat(field,Vector2(12,12),h).z==0,"nearby lava suppresses dampness even in a dark corner")
	r.liquids[Vector2i(1,1)]=PackedVector4Array([Vector4(13,0,12,1)])
	check(r.habitat(field,Vector2(12,12),h).z>0.9,"actual water creates a damp band")
	r.liquids.clear(); r.walls.clear(); r.add_site(Vector2(12,12))
	check(r.habitat(field,Vector2(12,12),h).w==1 and r.habitat(field,Vector2(31,31),h).w==0,"undead affinity has a bounded authored radius")
	var shape_rows := []
	for kind in range(14,30):
		var placed: Array[Dictionary]=[{"kind":kind,"p":Vector2(12,12),"height":0.0,"normal":Vector3.UP,
			"colour":Color(0.3,0.4,0.2),"angle":0.7,"scale":Regions.SCALES[kind-14].y,"seed":0.25,
			"anchor":Vector4(-1,0,0,0),"regional_material":Regions.material(kind)}]
		var geometry:=Geometry.new(); var arrays:=geometry.build(placed,Vector2i(1,1),null,field)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		check(vertices.size()>0 and (arrays[Mesh.ARRAY_CUSTOM2] as PackedFloat32Array).size()==vertices.size()*4,"complete regional attributes "+str(kind))
		for i in vertices.size():
			var v:=vertices[i]-Vector3(4,0.008,-4)
			check(v.is_finite() and normals[i].is_finite() and normals[i].length()>0.01,"finite nondegenerate regional triangle "+str(kind))
			check(Vector2(v.x,v.z).length()<=Cover.RADII[kind]*placed[0].scale+0.001 and v.y>=-0.008 and v.y<0.9,"geometry fits the admitted envelope "+str(kind))
		shape_rows.append({"kind":kind,"vertices":vertices.size(),"indices":(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()})
		for n:Vector3 in [Vector3(0.435,0.9004,0).normalized(),Vector3(0,0.9004,-0.435).normalized()]:
			placed[0].normal=n
			var tilted:=Geometry.new().build(placed,Vector2i(1,1),null,field)
			var invalid:=0
			for point:Vector3 in tilted[Mesh.ARRAY_VERTEX]:
				var v:=point-Vector3(4,0.008,-4)
				invalid+=int(Vector2(v.x,v.z).length()>Cover.RADII[kind]*placed[0].scale+0.001 or v.dot(n)<-0.008 or v.dot(n)>0.9)
			check(invalid==0,"tilted geometry stays inside full placement footprint "+str(kind)+" bad="+str(invalid))
	rows.append({"case":"regional-shapes","shapes":shape_rows})
	d.terrain.free(); d.free()


func regional_maps() -> void:
	var campaign:=CampaignMap.load_from(GameData.texts)
	var astral:=OS.get_cmdline_user_args().has("--cover-astral")
	var ids:=["gz5g","bz7g","gz9g","gz14k"] if not astral else ["gz7d1","gz36j","gz9g"]
	for id:String in ids:
		var zone:=campaign.zone(id); var world:=GameWorld.new(); world.zone=zone
		var map:=EIMapScene.new(); world.add_child(map)
		map.terrain=EITerrain.load_map(zone.mpr); map.add_child(map.terrain)
		map.mob=EIMob.load_bytes(GameData.read_file("maps/%s.mob"%zone.get("mob",zone.mpr)))
		var d:=map.terrain.details; d.prepare_grass(); var field:=d._cover_field
		if id=="gz9g": check(field.biome==("gipat2" if astral else "dead_city"),"campaign-aware zone9 identity")
		else: check(field.regions.cave,"authored cave sky "+id)
		var keys: Array[Vector2i]=[]; var extent:=Vector2i(field.size/8)
		for y in 8:
			for x in 8: keys.append(Vector2i((x+0.5)*extent.x/8,(y+0.5)*extent.y/8))
		if id=="bz7g":
			# The crust band is sparse. Include every lava-bearing chunk;
			# a coarse uniform sample missed the only actual flat pocket.
			for key:Vector2i in field.regions.liquids:
				if key.x>=0 and key.y>=0 and key.x<extent.x and key.y<extent.y and not key in keys: keys.append(key)
		if id=="gz14k":
			for i in field.mounds.materials.size():
				if field.mounds.materials[i]!=1: continue
				var key:=Vector2i((i%(field.size.x/2))/4,(i/(field.size.x/2))/4)
				if not key in keys: keys.append(key)
		for record:Dictionary in map.mob.objects:
			if record.kind=="UNIT" and Regions.undead(record.template):
				var key:=Vector2i(Vector2(record.position.x,record.position.y)/8)
				if not key in keys: keys.append(key)
			var tree:=Cover.tree_kind(record)
			if tree: d._index_tree(Vector2(record.position.x,record.position.y),tree)
		var counts:={}; var first:={}; var times:=[]; var native:=field.native; var array_bytes:=0; var jobs:=[]; var mounds:=0
		for key in keys:
			mounds+=field.mounds.records(field,key,[]).size()
			var start:=Time.get_ticks_usec(); var records:=field.records(key,[],d._trees.get(key,[])); times.append(Time.get_ticks_usec()-start)
			for record:Dictionary in records:
				counts[record.kind]=int(counts.get(record.kind,0))+1
				if not first.has(record.kind): first[record.kind]=str(record.p)
				check(not field.dry_surface(record.p).is_empty() if not record.get("underwater",false) else true,"regional root respects fluids/floors "+id)
			if keys.find(key)%16==0:
				var expected:=field.build(key,[],d._trees.get(key,[]));array_bytes+=var_to_bytes(expected.arrays).size()
				field.native=null; check(field.records(key,[],d._trees.get(key,[]))==records,"native/script regional agreement "+id); field.native=native
				var job:=d._chunk_job(key); jobs.append({"job":job,"task":WorkerThreadPool.add_task(Callable(job,"run")),"expected":expected})
		# Frozen jobs must survive mutable source water/unit/site/scenery edits.
		map.terrain.water.fill(100); map.mob.objects.clear();d._scenery.clear()
		for item:Dictionary in jobs:
			WorkerThreadPool.wait_for_task_completion(item.task)
			check(item.job.read_result().cover==item.expected,"regional worker snapshot survives source mutation "+id)
		if field.regions.cave: check(counts.has(24) and counts.has(29),"authored cave rock features "+id)
		if id=="bz7g": check(counts.has(14) and counts.has(17),"authored lava ash/crust")
		if id in ["gz7d1","gz36j"] or id=="gz9g" and not astral: check(counts.has(26),"authored undead sites admit bones "+id)
		if id=="gz9g" and astral: check(not counts.has(26) and not field.regions.dead_city,"LiA zone9 receives no Dead City rules")
		if id=="gz14k": check(mounds>0,"actual authored cave snow admits dense mounds")
		times.sort(); rows.append({"case":"regional-map","id":id,"biome":field.biome,"chunks":keys.size(),"counts":counts,"first":first,
			"record_us_median":times[times.size()/2],"record_us_max":times[-1],"sampled_array_bytes":array_bytes,"sites_buckets":field.regions.sites.size(),"liquid_buckets":field.regions.liquids.size(),"mounds":mounds,"scenery_loaded":false})
		print("REGIONAL_MAP ",JSON.stringify(rows[-1])); world.free()


func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_soft_ground","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option]=0
	GameData.options["gfx_biome_cover"]=1; Engine.max_fps=120; Engine.time_scale=0
	if OS.get_cmdline_user_args().has("--regional-hd"): GameData.options["gfx_hd_textures"]=1; GameData.options["gfx_terrain"]=1
	if OS.get_cmdline_user_args().has("--cover-kind-only"):
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--cover-kind="): only_kind=int(arg.trim_prefix("--cover-kind="))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	if DisplayServer.get_name()=="headless": regional_rules(); regional_maps()
	else: await render_fixture()
	TexUpscale.shutdown(); await frames(12)
	FileAccess.open("user://biome-cover-regions.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("COVER_REGIONS checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
