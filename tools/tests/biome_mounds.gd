extends Node
## Run with --mound-oracle=.../tests/biome_cover_surface.gd (freeze that file
## beside this tool). Its independent oracle reads the installed terrain mesh.
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Mounds = preload("res://src/game/fx/biome_mounds.gd")
const Sand = preload("res://src/game/fx/biome_sand_tiles.gd")
const N := 32
var checks := 0
var failures := 0
var rows := []
var oracle: Node
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)
func frames(n := 8) -> void:
	for i in n:
		if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
		await get_tree().process_frame
func snap(view: SubViewport,label: String) -> Image:
	await frames()
	var image := view.get_texture().get_image(); image.save_png("user://mounds-"+label+".png"); return image
func delta(a: Image,b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var changed := 0; var over := 0; var peak := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed += int(d>0); over += int(d>2); peak=maxi(peak,d)
	return {"changed":changed,"over_2":over,"peak":peak}
func drain(soft: SoftGroundDeform) -> void:
	for i in 16:
		soft._process(0); soft._finish_mesh_jobs(true)
		if soft._mesh_jobs.is_empty() and soft._queue.is_empty() and not soft.sectors.values().any(func(r: Dictionary): return r.build_pending): return
	check(false,"footprint queue drains")
func metadata() -> void:
	var image := GameData.load_image("zone15000"); var slots := Sand.slots(image)
	check(slots==[5,10,11],"atlas family data admits only three full loose-sand slots on zone15 layer0")
	var altered := image.duplicate() as Image
	if altered.is_compressed(): altered.decompress()
	altered.set_pixel(0,0,Color.MAGENTA)
	check(Sand.slots(altered).is_empty(),"modified atlas cannot inherit shipped identity")
	check(Sand.slots(GameData.load_image("zone1000")).is_empty(),"Gipat sand/beach palette is not soft desert sand")
	check(Sand.slots(null).is_empty(),"missing art never admits sand")
	var ridge := Mounds.rise(Vector2.ZERO,0.9,0.23,1.2)
	check(is_equal_approx(ridge,0.23) and Mounds.rise(Vector2(2,0),0.9,0.23,1.2)==0,"mound centre/rim envelope")
func choose(d: TerrainDetails, hint: Vector2) -> Dictionary:
	var keys: Array[Vector2i] = []
	for y in int(d.terrain.size_ei().y/8):
		for x in int(d.terrain.size_ei().x/8): keys.append(Vector2i(x,y))
	keys.sort_custom(func(a: Vector2i,b: Vector2i): return (Vector2(a)*8-hint).length_squared()<(Vector2(b)*8-hint).length_squared())
	for key in keys:
		var records := d._cover_field.mounds.records(d._cover_field,key,d._mound_boxes(key))
		if records.is_empty(): continue
		var data := d._cover_field.mounds.build(d._cover_field,key,d._mound_boxes(key))
		if not data.records.is_empty(): return {"key":key,"data":data,"record":data.records[0]}
	return {}
func geometry(t: EITerrain,key: Vector2i,data: Dictionary) -> void:
	var a: Array = data.arrays; var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]; var uv: PackedVector2Array=a[Mesh.ARRAY_TEX_UV]
	var anchors: PackedFloat32Array=a[Mesh.ARRAY_CUSTOM0]
	check(data.records.size()<=Mounds.MAX_MOUNDS and v.size()<=Mounds.MAX_VERTICES,"mound budget enforced")
	var worst := 0.0; var height_error := 0.0; var weight_error := 0.0
	for i in v.size():
		var cell := Vector2i(int(anchors[i*4])/2,int(anchors[i*4+1])); var side := int(anchors[i*4])%2
		var grid: Array[Vector2i] = [cell+Vector2i.DOWN,cell+Vector2i.RIGHT,cell]
		if side: grid.assign([cell+Vector2i.RIGHT,cell+Vector2i.DOWN,cell+Vector2i.ONE])
		var weights := Vector3(1-anchors[i*4+2]-anchors[i*4+3],anchors[i*4+2],anchors[i*4+3])
		var expected := Vector2.ZERO; var h := 0.0; var code := t.land_tile[(cell.y/2)*(int(t.size_ei().x)/2)+cell.x/2]
		for j in 3:
			var local := grid[j]-Vector2i(cell.x/2,cell.y/2)*2
			expected += (t._tile_uv(code,local.x,local.y)[0] as Vector2)*weights[j]
			h += t.heights[grid[j].y*t.grid_w+grid[j].x]*weights[j]
			weight_error=maxf(weight_error,absf(weights[j]*16-roundf(weights[j]*16)))
		worst=maxf(worst,expected.distance_to(uv[i])); height_error=maxf(height_error,absf(h-v[i].y))
	check(worst<0.00001,"mound UVs retain original rotated terrain art")
	check(height_error<0.00001 and weight_error<0.00001,"geometry is on original 16-way triangle lattice")
	var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256); digest.update(var_to_bytes(data))
	rows.append({"case":"mesh","key":str(key),"records":data.records.size(),"vertices":v.size(),"triangles":(a[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3,"uv_error":worst,"height_error":height_error,"sha256":digest.finish().hex_encode()})
func cut_at(t: EITerrain,p: Vector2,cell: Vector2i) -> float:
	var soft := t.details.soft_ground; var state := soft.shared_field()._tile_image.get_pixel(cell.x/2,cell.y/2)
	if state.g<0.5 or state.r<0.5: return 0
	var key := Vector2i(cell.x/32,cell.y/32); var img: Image = soft.sectors[key].image
	var q := (p-Vector2(key)*32)*511/32; var lo := Vector2i(q.floor()); var f := q-Vector2(lo); var samples: Array[Color]=[]
	for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]: samples.append(img.get_pixelv((lo+offset).clamp(Vector2i.ZERO,Vector2i.ONE*511)))
	var track := samples[0].lerp(samples[1],f.x).lerp(samples[2].lerp(samples[3],f.x),f.y)
	var age := maxf(soft._age-track.b/maxf(track.a,1e-5),0)
	return clampf(track.r*clampf((240-age)/60,0,1)/0.15,0,1)
func probe(t: EITerrain,key: Vector2i,data: Dictionary,centre: Vector2,label: String,wrong := false) -> void:
	oracle.index_surface(t,centre,12)
	var source: Array = data.arrays; var points: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var aa: PackedFloat32Array = source[Mesh.ARRAY_CUSTOM0]
	var ss: PackedFloat32Array = source[Mesh.ARRAY_CUSTOM1]
	var vertices := PackedVector3Array(); var anchors := PackedFloat32Array(); var shapes := PackedFloat32Array(); var expected := PackedFloat32Array(); var ids := PackedInt32Array()
	var count := mini(N*N,points.size()); var cuts := 0; var invalid := 0
	for i in count:
		var at := mini(points.size()-1,int(float(i)*points.size()/count)); var p := points[at]+Vector3(key.x*8,0,-key.y*8); var xy := Vector2(p.x,-p.z)
		var cell := Vector2i(int(aa[at*4])/2,int(aa[at*4+1])); var cut := cut_at(t,xy,cell)
		cuts += int(cut>0.99 and ss[at*4+2]>0.03)
		var h: float=oracle.raster_height(t,xy); invalid+=int(not is_finite(h))
		var target: float = h+ss[at*4+2]*(1-cut)-0.005+(0.02 if wrong else 0)
		var base := vertices.size()
		for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
			vertices.append(p); anchors.append_array(aa.slice(at*4,at*4+4)); shapes.append_array(ss.slice(at*4,at*4+4))
			var clip := (Vector2(i%N,i/N)+corner)/N*2-Vector2.ONE
			expected.append_array([clip.x,clip.y,target,0])
		ids.append_array([base,base+1,base+2,base,base+2,base+3])
	check(invalid==0,"independent installed mesh covers all mound vertices "+label)
	var vertex := Mounds.VERTEX.replace("\n}\n","\n failed=abs(VERTEX.y-CUSTOM2.z)>0.002 ? 1.0:0.0; POSITION=vec4(CUSTOM2.xy,0.5,1.0);\n}\n")
	var shader := Shader.new(); shader.code="shader_type spatial; render_mode unshaded, fog_disabled, cull_disabled;\nvarying float failed; varying vec3 wpos; varying vec2 soft_profile; varying vec3 ei_e; varying float ei_k;\n"+Cover.Geometry.SURFACE_UNIFORMS+GroundSurfaceShader.SOFT_UNIFORMS+GroundSurfaceShader.SOFT_FUNCTIONS+GroundSurfaceShader.TRIANGLE_QUERY+vertex+"\nvoid fragment() { ALBEDO=vec3(failed,1.0-failed,0.0); }"
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_INDEX]=ids
	arrays[Mesh.ARRAY_CUSTOM0]=anchors; arrays[Mesh.ARRAY_CUSTOM1]=shapes; arrays[Mesh.ARRAY_CUSTOM2]=expected
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mounds.FORMAT|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT))
	var view := SubViewport.new(); view.size=Vector2i(N,N)*4; view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,3,0); camera.look_at(Vector3.ZERO,Vector3.BACK); camera.current=true
	var node := MeshInstance3D.new(); node.mesh=mesh; node.extra_cull_margin=1000; view.add_child(node)
	var material := ShaderMaterial.new(); material.shader=shader; t.ground_surface_data(true).bind(material,true)
	material.set_shader_parameter("view_position",Vector3(centre.x,0,-centre.y)); node.material_override=material
	var image := await snap(view,"probe-"+label); var bad := 0; var rendered := 0
	for y in N:
		for x in N:
			var colour := image.get_pixel(x*4+2,y*4+2); bad+=int(colour.r>0.9); rendered+=int(colour.r>0.9 or colour.g>0.9)
	check(rendered==count,"all GPU samples rendered "+label)
	check(bad==count if wrong else bad==0,"GPU mound height matches actual installed triangles within 2 mm "+label+" bad="+str(bad))
	rows.append({"case":"probe","label":label,"samples":count,"bad":bad,"fully_cut_positive_height_samples":cuts,"negative":wrong})
	view.free(); await frames(2)
func exposed_trough(t: EITerrain,key: Vector2i,data: Dictionary,camera: Camera3D,on: Image,off: Image) -> void:
	var arrays: Array=data.arrays; var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var anchors: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM0]; var shapes: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM1]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]; var pixels := {}
	for i in range(0,indices.size(),3):
		var points: Array[Vector3]=[]; var eligible := true
		for j in 3:
			var at := indices[i+j]; var p := vertices[at]+Vector3(key.x*8,0,-key.y*8)
			if shapes[at*4+2]<0.03 or cut_at(t,Vector2(p.x,-p.z),Vector2i(int(anchors[at*4])/2,int(anchors[at*4+1])))<0.999: eligible=false; break
			p.y=oracle.raster_height(t,Vector2(p.x,-p.z)); points.append(p)
		if not eligible: continue
		var screen := camera.unproject_position((points[0]+points[1]+points[2])/3)
		var pixel := Vector2i(screen.floor())
		if pixel.x>=0 and pixel.y>=0 and pixel.x<on.get_width() and pixel.y<on.get_height(): pixels[pixel]=true
	var bad := 0
	for pixel: Vector2i in pixels: bad+=int(on.get_pixelv(pixel)!=off.get_pixelv(pixel))
	check(pixels.size()>10 and bad==0,"fully compacted mound exposes exact underlying trench pixels")
	rows.append({"case":"exposed-trough","pixels":pixels.size(),"changed":bad})
func restoration(a: Image,b: Image,camera: Camera3D,chosen: Dictionary,label: String) -> void:
	var lo := Vector2.INF; var hi := -Vector2.INF
	for v: Vector3 in chosen.data.arrays[Mesh.ARRAY_VERTEX]:
		for height in [-0.4,0.65]:
			var p := camera.unproject_position(v+Vector3(chosen.key.x*8,height,-chosen.key.y*8))
			lo=lo.min(p); hi=hi.max(p)
	var start := Vector2i(lo.floor())-Vector2i.ONE*4
	var area := Rect2i(start,Vector2i(hi.ceil())+Vector2i.ONE*4-start).intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	var whole := delta(a,b); var patch := delta(a.get_region(area),b.get_region(area))
	# Explicit narrower diagnostic only after an unchanged-pack control.
	# Retain all full-frame differences; this flag cannot bless a changed
	# mound, and does not claim a whole-scene restoration pass.
	var regional := OS.get_cmdline_user_args().has("--mound-region-restoration")
	check(patch.changed==0 and (regional or whole.changed==0),label+(" (mound area only)" if regional else " (whole scene)"))
	rows.append({"case":"restoration","label":label,"region_only":regional,"area":str(area),"patch":patch,"whole_scene":whole})
func install(d: TerrainDetails,chosen: Dictionary) -> void:
	if not d._chunks.has(chosen.key): d._install_chunk(chosen.key,d.instances(chosen.key))
	var p: Vector2=chosen.record.p
	d._material.set_shader_parameter("view_position",Vector3(p.x,0,-p.y))
	d._cover_material.set_shader_parameter("view_position",Vector3(p.x,0,-p.y)); d._mound_material.set_shader_parameter("view_position",Vector3(p.x,0,-p.y))
	for chunk: Node in d._chunks.values():
		var cover := chunk.get_node_or_null("BiomeCover")
		if cover: cover.hide()
func run() -> void:
	print("MOUND_STAGE run")
	var id := "gz11k"; var hint := Vector2(396,171)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mound-zone="): id=arg.trim_prefix("--mound-zone=")
	if id=="gz15h": hint=Vector2(151,191)
	var view := SubViewport.new(); view.size=Vector2i(800,600); view.own_world_3d=true; view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var world := GameWorld.new(); world.process_mode=Node.PROCESS_MODE_PAUSABLE; view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.zone=CampaignMap.load_from(GameData.texts).zone(id)
	print("MOUND_STAGE load ",id)
	var map := EIMapScene.load_map(world.zone.mpr,world.zone.get("mob",""),false); world.add_child(map); world.map=map; world.terrain=map.terrain
	var t := map.terrain; t.set_process(false); var d := t.details; d.set_process(false); d.soft_ground.set_process(false)
	var started := Time.get_ticks_usec(); d.prepare_grass(); rows.append({"case":"prepare","us":Time.get_ticks_usec()-started})
	print("MOUND_STAGE prepared")
	var chosen := choose(d,hint); check(not chosen.is_empty(),"authored mound survives scenery and material exclusions")
	if chosen.is_empty(): view.free(); return
	var p: Vector2=chosen.record.p; geometry(t,chosen.key,chosen.data); install(d,chosen)
	rows.append({"case":"chosen","zone":id,"record":str(chosen.record),"key":str(chosen.key)})
	check(d._mound_material.get_shader_parameter("query_tracks")==d.soft_ground.shared_field().texture,"mounds share the existing track texture")
	check(d._cover_surface.normals==null,"mounds do not allocate contact normals")
	var blocked := [{"box":AABB(Vector3(p.x-0.01,0,-p.y-0.01),Vector3(0.02,200,0.02)),"inverse":Transform3D.IDENTITY}]
	var rejected := d._cover_field.mounds.build(d._cover_field,chosen.key,blocked)
	check(rejected.records.all(func(r: Dictionary): return r.p!=p),"full mound footprint excludes a thin prop")
	check(d._cover_field.build(chosen.key,blocked,[]).mounds==rejected,"direct cover builder preserves its supplied scenery exclusions")
	var original_normals := t.land_n.duplicate()
	var job := d._chunk_job(chosen.key); var task := WorkerThreadPool.add_task(Callable(job,"run"))
	t.land_n.fill(Vector3.ZERO)
	WorkerThreadPool.wait_for_task_completion(task); t.land_n=original_normals
	check(job.read_result().cover.mounds==chosen.data,"worker and script publish identical mound meshes")
	job=null
	var costs := []; var active_costs := []; var vertex_total := 0; var mound_total := 0
	for y in range(chosen.key.y-2,chosen.key.y+3):
		for x in range(chosen.key.x-2,chosen.key.x+3):
			var key := Vector2i(x,y); started=Time.get_ticks_usec()
			var data := d._cover_field.mounds.build(d._cover_field,key,d._mound_boxes(key)); costs.append(Time.get_ticks_usec()-started)
			if not data.records.is_empty(): active_costs.append(costs.back())
			vertex_total+=(data.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(); mound_total+=data.records.size()
	costs.sort(); active_costs.sort()
	rows.append({"case":"build-cost","chunks":costs.size(),"median_us":costs[costs.size()/2],"max_us":costs.back(),"active_chunks":active_costs.size(),"active_median_us":active_costs[active_costs.size()/2],"mounds":mound_total,"vertices":vertex_total})
	if DisplayServer.get_name()=="headless": view.free(); return
	var focus := Vector3(p.x,t.height_at(p.x,p.y)+0.1,-p.y)
	var camera := Camera3D.new(); view.add_child(camera); camera.position=focus+Vector3(2.7,2.6,3.5); camera.look_at(focus); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment); env.environment.background_mode=Environment.BG_COLOR; view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); sun.shadow_enabled=true; view.add_child(sun)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75)); Gfx.set_foliage_wind(false)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized()); RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO); RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var mound_node := d._chunks[chosen.key].get_node("BiomeMounds") as MeshInstance3D
	check(mound_node.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"piles receive but do not cast shadows")
	await frames(120); mound_node.hide(); var off := await snap(view,"off"); mound_node.show(); var base := await snap(view,"loose")
	check(delta(base,await snap(view,"stable")).changed==0,"mound image settled")
	var diff := delta(off,base); check(diff.over_2>30,"authored mound visibly changes ground"); rows.append({"case":"visible","difference":diff})
	if OS.get_cmdline_user_args().has("--mound-submissions"):
		await submissions(view,d,focus)
	await probe(t,chosen.key,chosen.data,p,"loose"); await probe(t,chosen.key,chosen.data,p,"negative",true)
	var soft := d.soft_ground; soft.add_step(p,Vector2(0.30,0.46),0.4)
	check(not soft.sectors.is_empty(),"authored footstep admitted")
	await probe(t,chosen.key,chosen.data,p,"pending")
	check(delta(base,await snap(view,"pending")).changed==0,"pending mesh does not prematurely compact mound")
	drain(soft); await probe(t,chosen.key,chosen.data,p,"installed")
	var pressed := await snap(view,"pressed"); diff=delta(base,pressed); check(diff.over_2>15,"tracks visibly cut mound"); rows.append({"case":"footprint","difference":diff})
	mound_node.hide(); await snap(view,"pressed-ground-control"); mound_node.show()
	# From an oblique camera, an uncut side wall legitimately occludes part
	# of a deep trench. The overhead comparison isolates the exposed floor.
	var camera_pose := camera.transform
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=3.0
	camera.position=focus+Vector3.UP*4; camera.look_at(focus,Vector3.BACK)
	var overhead := await snap(view,"trough-overhead")
	mound_node.hide(); var underlying := await snap(view,"trough-overhead-ground"); mound_node.show()
	exposed_trough(t,chosen.key,chosen.data,camera,overhead,underlying)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE; camera.transform=camera_pose
	process_mode=Node.PROCESS_MODE_ALWAYS; get_tree().paused=true; Engine.time_scale=1; soft.set_process(true)
	var age := soft._age; var held := await snap(view,"paused")
	check(soft._age==age and delta(held,await snap(view,"paused-later")).changed==0,"tree pause holds mound compaction and ground together")
	soft.set_process(false); get_tree().paused=false; Engine.time_scale=0; process_mode=Node.PROCESS_MODE_INHERIT
	var rid := soft.field.texture.get_rid(); soft._process(210); drain(soft); await probe(t,chosen.key,chosen.data,p,"fading")
	soft._process(31); drain(soft); await probe(t,chosen.key,chosen.data,p,"expired")
	check(delta(base,await snap(view,"expired")).changed==0,"track expiry restores mound exactly")
	soft.add_step(p,Vector2(0.30,0.46),0.4); drain(soft); soft.clear()
	check(soft.field.texture.get_rid()==rid and delta(base,await snap(view,"clear")).changed==0,"shared field clear restores mound without new texture RID")
	var holder: WeakRef = weakref(d._cover_surface); GameData.options["gfx_soft_ground"]=0; t.apply_gfx()
	check(d._cover_surface==null and holder.get_ref()==null,"soft-off drops optional ground geometry")
	var hard := await snap(view,"soft-off")
	GameData.options["gfx_soft_ground"]=1; t.apply_gfx(); d.soft_ground.set_process(false)
	restoration(base,await snap(view,"soft-restored"),camera,chosen,"soft-ground round trip restores mound")
	GameData.options["gfx_soft_ground"]=0; t.apply_gfx()
	restoration(hard,await snap(view,"soft-off-restored"),camera,chosen,"soft-off static shader restores exact pixels")
	GameData.options["gfx_soft_ground"]=1; t.apply_gfx(); d.soft_ground.set_process(false)
	d.water_changed(); d.prepare_grass(); install(d,chosen)
	check(d.instances(chosen.key).cover.mounds==chosen.data,"water invalidation rebuilds identical mound geometry")
	restoration(base,await snap(view,"rebuilt"),camera,chosen,"rebuild restores original mound scene")
	var snapshot: WeakRef = weakref(d._cover_field); var material: WeakRef = weakref(d._mound_material)
	GameData.options["gfx_biome_cover"]=0; d.apply_options(); await frames()
	check(d._mound_material==null and snapshot.get_ref()==null and material.get_ref()==null,"cover off releases mound material and immutable snapshot")
	restoration(off,await snap(view,"off-restored"),camera,chosen,"cover off restores original scene")
	view.free(); await frames()
func submissions(view:SubViewport,d:TerrainDetails,focus:Vector3) -> void:
	var cover_visibility:= {}
	for chunk:Node in d._chunks.values():
		var cover:=chunk.get_node_or_null("BiomeCover") as MeshInstance3D
		if cover:cover_visibility[cover]=cover.visible
	for offset:Vector3 in [Vector3(32,0,0),Vector3(42,0,-7),Vector3(1000,0,1000),Vector3.ZERO]:
		var at:=focus+offset
		for material:ShaderMaterial in [d._material,d._cover_material,d._mound_material]:
			if material:material.set_shader_parameter("view_position",at)
		d._submission_culling=false;d._cull_focus=Vector2.INF;d._update_submissions(Vector2(at.x,at.z))
		var before:=await snap(view,"cull-"+str(offset)+"-off")
		var primitives:=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		d._submission_culling=true;d._cull_focus=Vector2.INF;d._update_submissions(Vector2(at.x,at.z))
		var after:=await snap(view,"cull-"+str(offset)+"-on");var diff:=delta(before,after)
		check(diff.changed==0,"faded mound culling preserves actual ground pixels")
		var visible:=d._chunks.values().filter(func(n:MultiMeshInstance3D):return n.get_node_or_null("BiomeMounds")!=null and n.get_node("BiomeMounds").is_visible_in_tree()).size()
		if offset.length()>500:check(visible==0,"distant mounds stop submitting")
		elif offset==Vector3.ZERO:check(visible>0,"near mound submissions return")
		rows.append({"case":"mound-submissions","offset":str(offset),"difference":diff,"visible_mound_chunks":visible,"before_primitives":primitives,"after_primitives":view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	# This fixture isolates mounds by manually hiding litter. Returning the
	# stream to the near view also restores litter; reapply the fixture mask.
	for cover:MeshInstance3D in cover_visibility:cover.visible=cover_visibility[cover]
	await frames()

func _ready() -> void:
	print("MOUND_STAGE ready")
	for option in ["gfx_hd_textures","gfx_terrain","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option]=0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mound-oracle="): oracle=load(arg.trim_prefix("--mound-oracle=")).new()
	GameData.options["gfx_biome_cover"]=1; GameData.options["gfx_soft_ground"]=1
	if OS.get_cmdline_user_args().has("--mound-detail"): GameData.options["gfx_terrain"]=1
	if OS.get_cmdline_user_args().has("--mound-hd"): GameData.options["gfx_hd_textures"]=1
	check(oracle!=null,"independent surface oracle supplied")
	print("MOUND_STAGE oracle")
	Engine.max_fps=120; Engine.time_scale=0; DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals(); metadata()
	print("MOUND_STAGE metadata")
	if oracle: await run(); oracle.free()
	TexUpscale.shutdown(); await frames(10)
	FileAccess.open("user://biome-mounds.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("BIOME_MOUNDS checks=",checks," failures=",failures); get_tree().quit(1 if failures else 0)
