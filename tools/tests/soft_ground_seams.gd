extends Node
## Actual production vertex displacement and native footprint meshes, viewed
## against a diagnostic background. Test every four-tile junction occupancy,
## then stamp unchanged authored Ingos terrain through the normal dispatcher.
## --seam-hd mounts the real, already-installed HD Lands package in a test profile.
const SIZE := Vector2i(640,480)
const REGION := Rect2i(80,100,480,280)
var checks := 0
var failures := 0
var rows := []
var isolated_pixels := 0
var view: SubViewport
var camera: Camera3D
var mask_shader: Shader
var hd := OS.get_cmdline_user_args().has("--seam-hd")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func texture(size: Vector2i, colour: Color) -> ImageTexture:
	var image := Image.create(size.x,size.y,false,Image.FORMAT_RGBAF)
	image.fill(colour)
	return ImageTexture.create_from_image(image)

func capture() -> Image:
	for i in 6:
		RenderingServer.force_draw()
		await get_tree().process_frame
	return view.get_texture().get_image()

func hole(colour: Color) -> bool:
	return colour.r > 0.9 and colour.b > 0.9 and colour.g < 0.1

func openings(image: Image, reference: Image = null) -> int:
	var result := 0
	for y in range(REGION.position.y,REGION.end.y):
		for x in range(REGION.position.x,REGION.end.x):
			if not hole(image.get_pixel(x,y)) or (reference != null and hole(reference.get_pixel(x,y))): continue
			# Unaliased T-junction rasterization also leaves isolated pixels
			# when displacement is disabled (flat-control probe). Count those
			# separately; a connected opening must never survive this check.
			if hole(image.get_pixel(x-1,y)) or hole(image.get_pixel(x+1,y)) or hole(image.get_pixel(x,y-1)) or hole(image.get_pixel(x,y+1)):
				result += 1
			else: isolated_pixels += 1
	return result

func frame_point(point: Vector3, angle: int) -> void:
	var direction: Vector3 = [Vector3(3,2.2,4),Vector3(-4,2.2,3),Vector3(-3,2.2,-4),Vector3(4,2.2,-3)][angle]
	camera.position = point+direction
	camera.look_at(point,Vector3.UP)

func synthetic(shift: Vector2) -> EITerrain:
	var terrain := EITerrain.new()
	terrain.sectors_x=2; terrain.sectors_y=2; terrain.grid_w=65
	terrain._land_mat=ShaderMaterial.new(); terrain._land_mat.shader=mask_shader
	terrain._land_mat.set_shader_parameter("terrain_tiles",texture(Vector2i(32,32),Color(0,9,.20,.30)))
	terrain._land_mat.set_shader_parameter("terrain_cells",texture(Vector2i(64,64),Color(-100,9,0,0)))
	terrain._land_mat.set_shader_parameter("soft_vertices",texture(Vector2i(65,65),Color(shift.x,0,shift.y,0)))
	terrain._land_mat.set_shader_parameter("soft_ground",true)
	var levels:=PackedFloat32Array(); levels.resize(64)
	terrain._land_mat.set_shader_parameter("level",levels)
	view.add_child(terrain); terrain.set_process(false)
	for sy in 2:
		for sx in 2:
			var positions:=PackedVector3Array(); var normals:=PackedVector3Array()
			for y in 33:
				for x in 33:
					positions.append(Vector3(sx*32+x+shift.x,0,-sy*32-y-shift.y))
					normals.append(Vector3.UP)
			var codes:=PackedInt32Array(); codes.resize(256)
			# Adjacent tiles can use any of the four authored UV rotations.
			for id in 256: codes[id]=(id%4)<<14
			var tile_data: Image=terrain._land_mat.get_shader_parameter("terrain_tiles").get_image()
			for y in 16:
				for x in 16: tile_data.set_pixel(sx*16+x,sy*16+y,Color(codes[y*16+x],9,.20,.30))
			terrain._land_mat.get_shader_parameter("terrain_tiles").update(tile_data)
			var sector:=EITerrainSector.new(); sector.name="Sector_%d_%d"%[sx,sy]; terrain.add_child(sector)
			sector.configure(terrain._mesh_arrays([positions,normals],codes,PackedInt32Array(),Vector2i(sx,sy)*16),terrain._land_mat,1,false)
	return terrain

func install_pattern(soft: SoftGroundDeform, point: Vector2i, pattern: int, shifted: bool) -> void:
	soft.clear()
	for bit in 4:
		if not (pattern & (1<<bit)): continue
		var tile:=point/2+Vector2i(bit%2-1,bit/2-1)
		var key:=tile/16; var id:=(tile.y%16)*16+tile.x%16
		var rec:=soft._sector(key)
		rec.tiles[id]=null; rec.touched[id]=0.0
		if shifted:
			SoftGroundDeform.paint(rec.image,Vector2(point)+Vector2(.3,.2)-Vector2(key*32),Vector2(.25,.35),.3,1,0)
		else:
			# A retained field can outlive an adjacent dense tile's eviction.
			rec.image.fill(Color(1,0,0,1))
		soft.field.update(key)
	for key: Vector2i in soft.sectors:
		var rec: Dictionary=soft.sectors[key]
		var job: Object=ClassDB.instantiate("SoftGroundMeshJob")
		check(job.configure(rec.arrays,rec.tiles),"native junction mesh accepted")
		job.run()
		var result: Array=job.read_result()
		rec.tiles=result[2]
		soft._apply_mesh(rec,result[0],result[1])

func junctions() -> void:
	for shift: Vector2 in [Vector2.ZERO,Vector2(.375,.25),Vector2(-.375,-.25)]:
		var terrain:=synthetic(shift)
		var soft:=SoftGroundDeform.new(); soft.terrain=terrain; terrain.add_child(soft); soft.set_process(false)
		for point: Vector2i in [Vector2i(16,16),Vector2i(32,32)]:
			for pattern in 16:
				install_pattern(soft,point,pattern,shift!=Vector2.ZERO)
				var pixels:=0
				for angle in 4:
					frame_point(Vector3(point.x,0,-point.y),angle)
					var image:=await capture()
					var count:=openings(image); pixels+=count
					if count>0 or (shift==Vector2(.375,.25) and point.x==32 and pattern==15 and angle==0):
						image.save_png("user://seam-%s-%d-%d-%d.png"%[str(shift),point.x,pattern,angle])
				check(pixels==0,"closed junction shift=%s point=%s pattern=%d pixels=%d"%[shift,point,pattern,pixels])
				rows.append({"kind":"junction","shift":str(shift),"point":str(point),"pattern":pattern,"hole_pixels":pixels})
		terrain.free()

func drain(soft: SoftGroundDeform) -> void:
	for i in 20:
		soft._process(0); soft._finish_mesh_jobs(true)
		if soft._queue.is_empty() and soft._mesh_jobs.is_empty() and not soft.sectors.values().any(func(r): return r.build_pending): break
	check(soft._queue.is_empty() and soft._mesh_jobs.is_empty(),"footprint dispatcher drained")

func authored_points(terrain: EITerrain) -> Array:
	var candidates:=[]
	for y in range(4,terrain.sectors_y*32-4,2):
		for x in range(4,terrain.sectors_x*32-4,2):
			if x%32!=0 and y%32!=0: continue
			var centre:=Vector2i(x,y); var h:=terrain.heights[y*terrain.grid_w+x]
			var slope:=0.0; var dry:=true
			for dy in range(-2,3):
				for dx in range(-2,3):
					var p:=centre+Vector2i(dx,dy)
					slope=maxf(slope,absf(terrain.heights[p.y*terrain.grid_w+p.x]-h))
					if not terrain.details.soft_ground.step_allowed(Vector2(p)): dry=false
			var shift:=terrain.land_xy[y*terrain.grid_w+x]
			if dry and slope<0.45: candidates.append({"point":centre,"score":shift.length()-slope})
	candidates.sort_custom(func(a,b): return a.score>b.score)
	var chosen:=[]
	for candidate: Dictionary in candidates:
		if chosen.any(func(previous): return Vector2(previous.point).distance_to(Vector2(candidate.point))<24.0): continue
		chosen.append(candidate)
		if chosen.size()==3: break
	return chosen

func ingos() -> void:
	for map_name: String in ["zone11","zone12","zone13"]:
		var terrain:=EITerrain.load_map(map_name)
		check(terrain!=null,"authored Ingos map loads: "+map_name)
		if terrain==null: continue
		view.add_child(terrain); terrain.set_process(false); terrain.details.set_process(false)
		var soft:=terrain.details.soft_ground; soft.set_process(false)
		if hd: check(terrain._atlas_source_size>=2048,"real HD Lands atlases loaded: "+map_name)
		var points:=authored_points(terrain)
		check(not points.is_empty(),"dry snow sector witnesses found: "+map_name)
		# Only replace fragment colouring. Vertex displacement and authored
		# geometry, UVs, tile types, water and actual track fields are retained.
		var lit:=terrain._land_mat.shader
		terrain._land_mat.shader=mask_shader
		for witness: Dictionary in points:
			var point: Vector2i=witness.point; var index:=point.y*terrain.grid_w+point.x
			var p:=Vector2(point)+terrain.land_xy[index]
			var centre:=Vector3(p.x,terrain.heights[index]+.2,-p.y)
			soft.clear()
			var before:=[]
			for angle in 4:
				frame_point(centre,angle); before.append(await capture())
			for offset: Vector2 in [Vector2.ZERO,Vector2(.25,-.2),Vector2(-.2,.25)]: soft.add_step(p+offset,Vector2(.25,.35),.3)
			drain(soft)
			check(soft.sectors.size()>1,"authored footfalls cross sector boundary: "+map_name+str(point))
			var pixels:=0
			for angle in 4:
				frame_point(centre,angle); var image:=await capture()
				var count:=openings(image,before[angle]); pixels+=count
				if count>0: image.save_png("user://ingos-%s-%s-%d.png"%[map_name,str(point),angle])
			check(pixels==0,"authored Ingos tracks stay closed: %s %s pixels=%d"%[map_name,point,pixels])
			rows.append({"kind":"authored","map":map_name,"point":str(point),"xy":str(p),"hole_pixels":pixels,"hd":hd})
			# Retire one real installed tile while its neighbouring field is
			# retained, exercising the actual native replacement dispatcher.
			var retired:=point/2-Vector2i.ONE
			var key:=retired/16; var id:=(retired.y%16)*16+retired.x%16
			if soft.sectors.has(key) and soft.sectors[key].tiles.has(id):
				var rec: Dictionary=soft.sectors[key]
				rec.tiles.erase(id); rec.touched.erase(id); rec.revision+=1
				soft._build_meshes({key:true}); drain(soft)
				var retired_pixels:=0
				for angle in 4:
					frame_point(centre,angle); var image:=await capture()
					var count:=openings(image,before[angle]); retired_pixels+=count
					if count>0: image.save_png("user://ingos-retired-%s-%s-%d.png"%[map_name,str(point),angle])
				check(retired_pixels==0,"retired authored tile stays joined: %s %s pixels=%d"%[map_name,point,retired_pixels])
				rows.append({"kind":"authored-retirement","map":map_name,"point":str(point),"hole_pixels":retired_pixels,"hd":hd})
			else: check(false,"retirement witness was present")
			# Verify the original lit HD/native terrain after the diagnostic.
			terrain._land_mat.shader=lit; soft.refresh_materials(); frame_point(centre,0)
			(await capture()).save_png("user://ingos-lit-%s-%s.png"%[map_name,str(point)])
			terrain._land_mat.shader=mask_shader; soft.refresh_materials()
		terrain.free()

func _ready() -> void:
	if DisplayServer.get_name()=="headless": get_tree().quit(2); return
	if hd:
		var key:="community.hd-lands-textures@1.5.0"
		check(ModStore.catalog.has(key),"real HD Lands package installed in disposable profile")
		if failures: get_tree().quit(1); return
		check(ModStore.create_profile("Snow seam validation",false,[key]).is_empty(),"activate isolated HD Lands profile")
		check(GameData.open(GameData.root).is_empty(),"mount HD Lands archives")
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"auto_graphics":0,"gfx_terrain":1,"gfx_soft_ground":1,"confine_mouse":0},true)
	RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals(); Gfx.apply_surface_options()
	var code:=EITerrain.TERRAIN_SHADER
	code=code.substr(0,code.find("void fragment()"))+"void fragment(){ ALBEDO=vec3(0.8); }"
	code=code.replace("render_mode cull_disabled, ambient_light_disabled;","render_mode cull_disabled, unshaded, fog_disabled;")
	mask_shader=Shader.new(); mask_shader.code=code; mask_shader.get_shader_uniform_list()
	view=SubViewport.new(); view.size=SIZE; view.msaa_3d=Viewport.MSAA_DISABLED; view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color.MAGENTA; view.add_child(environment)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-55,-30,0); sun.light_specular=Gfx.SUN_MARK; view.add_child(sun)
	Gfx.set_light(Color(.65,.7,.75),Color(.8,.8,.8)); Gfx.sync_sun_pass(sun)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=4.5; view.add_child(camera); camera.current=true
	await junctions()
	await ingos()
	view.free(); TexUpscale.shutdown()
	FileAccess.open("user://snow-seams.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"hd":hd,"msaa":0,"isolated_raster_pixels":isolated_pixels,"rows":rows},"\t"))
	print("SOFT_GROUND_SEAMS ",checks," checks ",failures," failures"); get_tree().quit(int(failures>0))
