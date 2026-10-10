extends Node
## Actual installed terrain triangles are the independent height oracle. GPU
## probes execute the production cover attachment and mesh attribute format.
const Cover = preload("res://src/game/fx/biome_cover.gd")
const Geometry = preload("res://src/game/fx/biome_cover_mesh.gd")
const N := 32
var checks := 0
var failures := 0
var rows := []
var _triangles := {}
var _height_cache := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count := 8) -> void:
	for i in count:
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		await get_tree().process_frame

func snap(view: SubViewport, label: String) -> Image:
	await frames()
	var image := view.get_texture().get_image()
	image.save_png("user://cover-surface-"+label+".png")
	return image

func difference(a: Image, b: Image) -> Dictionary:
	a.convert(Image.FORMAT_RGBA8); b.convert(Image.FORMAT_RGBA8)
	var aa := a.get_data(); var bb := b.get_data(); var changed := 0; var over := 0; var peak := 0
	for i in range(0,aa.size(),4):
		var d := maxi(absi(aa[i]-bb[i]),maxi(absi(aa[i+1]-bb[i+1]),absi(aa[i+2]-bb[i+2])))
		changed += int(d>0); over += int(d>2); peak = maxi(peak,d)
	return {"changed":changed,"over_2":over,"peak":peak}

func drain(soft: SoftGroundDeform) -> void:
	for i in 16:
		soft._process(0); soft._finish_mesh_jobs(true)
		if soft._mesh_jobs.is_empty() and soft._queue.is_empty() and not soft.sectors.values().any(func(r: Dictionary): return r.build_pending): return
	check(false,"deformation jobs drain")

func anchor_rules() -> void:
	var t := EITerrain.new(); t.sectors_x=1; t.sectors_y=1; t.grid_w=33; t.map_name="anchor-rules"
	t.texture_size=512; t.tile_size=64; t.land_xy.resize(33*33); t.heights.resize(33*33)
	t.land_tile.resize(16*16); t.tile_types=PackedInt32Array([9,0]); t.ground.resize(32*32)
	t.water.resize(32*32); t.surface.resize(32*32); t.water.fill(-INF); t.surface.fill(-INF)
	var field := Cover.new(); field.configure(t,null,{},"ingos")
	var anchor := field.surface_anchor(Vector2(10.25,10.25))
	check(anchor==Vector4(20,10,0.25,0.5),"lower triangle anchor encodes exact cell/side/weights")
	check(field.surface_anchor(Vector2(10.75,10.75))==Vector4(21,10,0.25,0.5),"upper triangle anchor uses its own diagonal")
	check(not field.surface_anchor(Vector2(10.5,10.5)).is_finite(),"shared-edge roots use the conservative ambiguous rule")
	t.land_xy[11*33+11]=Vector2(-1.4,-1.4)
	var folded := Cover.new(); folded.configure(t,null,{},"ingos")
	check(not folded.surface_anchor(Vector2(10.2,10.2)).is_finite(),"folded competing triangles cannot trap a plant below the top surface")
	check(field.surface_anchor(Vector2(10.25,10.25))==anchor,"jitter mutation cannot change a published anchor snapshot")
	t.tile_types.fill(0)
	var hard := Cover.new(); hard.configure(t,null,{},"ingos")
	check(hard.surface_anchor(Vector2(10.25,10.25)).x<0,"hard terrain skips deformation queries")
	check(field.surface_anchor(Vector2(10.25,10.25))==anchor,"material mutation cannot change the copied soft-tile mask")
	var d := TerrainDetails.new(); d.terrain=t; d._cover=true; d._cover_field=hard; d.soft_ground=SoftGroundDeform.new()
	d._ensure_grass_resources()
	check(d._cover_surface==null,"hard-only maps allocate no extra terrain texture for cover")
	d.soft_ground.free(); d.free(); t.free()

func type_profile(t: EITerrain, p: Vector2i) -> Vector2:
	p = p.clamp(Vector2i.ZERO,Vector2i(t.sectors_x,t.sectors_y)*16-Vector2i.ONE)
	var code := t.land_tile[p.y*t.sectors_x*16+p.x]&0x3fff
	var type := t.tile_types[code] if code<t.tile_types.size() else 0
	match type:
		9: return Vector2(0.20,0.30)
		12: return Vector2(0.075,0.12)
		3: return Vector2(0.008,0.025)
	return Vector2.ZERO

func displaced(t: EITerrain, point: Vector3, key: Vector2i, tracks: bool) -> float:
	if not Gfx.on("gfx_soft_ground"): return point.y
	var p := Vector2(point.x,-point.z); var tile := Vector2i((p*0.5).floor())
	if type_profile(t,tile).x==0: return point.y
	var grid := p*0.5-Vector2.ONE*0.5; var base := Vector2i(grid.floor()); var f := grid-Vector2(base)
	f = Vector2(smoothstep(0,1,f.x),smoothstep(0,1,f.y))
	var profile := type_profile(t,base).lerp(type_profile(t,base+Vector2i.RIGHT),f.x).lerp(
		type_profile(t,base+Vector2i.DOWN).lerp(type_profile(t,base+Vector2i.ONE),f.x),f.y)
	var local := p-Vector2(tile)*2; var mask := 1.0
	for side: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if type_profile(t,tile+side).x>0: continue
		var edge := (local.x if side.x<0 else 2-local.x) if side.x!=0 else (local.y if side.y<0 else 2-local.y)
		mask *= smoothstep(0,0.6,edge)
	var cell := Vector2i(p.floor()).clamp(Vector2i.ZERO,Vector2i(t.size_ei())-Vector2i.ONE)
	var at := cell.y*int(t.size_ei().x)+cell.x
	var water := t.water_base[at]+t._level[clampi(t.water_mat[at],0,63)]
	profile *= mask*smoothstep(0.025,0.10,point.y-water)
	var h := point.y+profile.x
	if not tracks: return h
	var soft := t.details.soft_ground; var rec: Dictionary = soft.sectors[key]; var img: Image = rec.image
	var sample := (p-Vector2(key)*32)*511/32; var lo := Vector2i(sample.floor()); var blend := sample-Vector2(lo)
	var values: Array[Color] = []
	for offset: Vector2i in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
		values.append(img.get_pixelv((lo+offset).clamp(Vector2i.ZERO,Vector2i.ONE*511)))
	var value := values[0].lerp(values[1],blend.x).lerp(values[2].lerp(values[3],blend.x),blend.y)
	var age := maxf(soft._age-value.b/maxf(value.a,1e-5),0)
	var fade := clampf((240-age)/60,0,1)
	var compact := value.r*fade; var bank := value.g*fade
	return h+(bank*(1-smoothstep(0.05,0.30,compact))-compact)*profile.y

func index_surface(t: EITerrain, centre: Vector2, span := 10.0) -> void:
	_triangles.clear(); _height_cache.clear()
	var lo := centre-Vector2.ONE*span*0.5; var hi := centre+Vector2.ONE*span*0.5
	for sy in range(maxi(0,int(lo.y/32)-1),mini(t.sectors_y-1,int(hi.y/32)+1)+1):
		for sx in range(maxi(0,int(lo.x/32)-1),mini(t.sectors_x-1,int(hi.x/32)+1)+1):
			var key := Vector2i(sx,sy); var sector := t.get_node("Sector_%d_%d" % [sx,sy])
			var node: MeshInstance3D = sector.deformation_surface() if sector is EITerrainSector else sector
			var arrays := node.mesh.surface_get_arrays(0); var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var tracks := false
			if is_instance_valid(t.details.soft_ground) and t.details.soft_ground.sectors.has(key):
				tracks = node.mesh != t.details.soft_ground.sectors[key].source
			for i in range(0,ids.size(),3):
				var points: Array[Vector3] = [vertices[ids[i]],vertices[ids[i+1]],vertices[ids[i+2]]]
				var a := Vector2(points[0].x,-points[0].z); var b := Vector2(points[1].x,-points[1].z); var c := Vector2(points[2].x,-points[2].z)
				var first := a.min(b).min(c); var last := a.max(b).max(c)
				if first.x>hi.x or first.y>hi.y or last.x<lo.x or last.y<lo.y: continue
				var triangle := {"points":points,"key":key,"tracks":tracks}
				for y in range(floori(first.y),floori(last.y)+1):
					for x in range(floori(first.x),floori(last.x)+1):
						var cell := Vector2i(x,y)
						if not _triangles.has(cell): _triangles[cell] = []
						_triangles[cell].append(triangle)

func raster_height(t: EITerrain, p: Vector2) -> float:
	var highest := -INF
	for triangle: Dictionary in _triangles.get(Vector2i(p.floor()),[]):
		var v: Array[Vector3] = triangle.points
		var a := Vector2(v[0].x,-v[0].z); var b := Vector2(v[1].x,-v[1].z); var c := Vector2(v[2].x,-v[2].z)
		var determinant := (b-a).cross(c-a)
		if absf(determinant)<1e-10: continue
		var u := (p-a).cross(c-a)/determinant; var w := (b-a).cross(p-a)/determinant
		if u< -1e-5 or w< -1e-5 or u+w>1.00001: continue
		var h := 0.0
		for i in 3:
			var cache_key := Vector4(v[i].x,v[i].y,v[i].z,float(triangle.tracks))
			if not _height_cache.has(cache_key): _height_cache[cache_key] = displaced(t,v[i],triangle.key,triangle.tracks)
			h += float(_height_cache[cache_key])*[1-u-w,u,w][i]
		highest = maxf(highest,h)
	return highest

func probe_shader() -> Shader:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, fog_disabled, cull_disabled;\n"+Geometry.SURFACE_UNIFORMS+GroundSurfaceShader.SOFT_UNIFORMS+GroundSurfaceShader.SOFT_FUNCTIONS+GroundSurfaceShader.TRIANGLE_QUERY+"""
varying float failed;
void vertex() {
	float fade=1.0;
	vec2 clip=VERTEX.xz;
	VERTEX.y=UV.x;
"""+Geometry.ATTACH+"""
	failed=abs(VERTEX.y-CUSTOM1.x)>0.002 ? 1.0 : 0.0;
	POSITION=vec4(clip,0.5,1.0);
}
void fragment() { ALBEDO=vec3(failed,1.0-failed,0.0); }
"""
	return shader

func probe(t: EITerrain, centre: Vector2, label: String, wrong := false) -> void:
	index_surface(t,centre)
	var verts := PackedVector3Array(); var uv := PackedVector2Array(); var anchors := PackedFloat32Array(); var expected := PackedFloat32Array(); var ids := PackedInt32Array()
	var field := t.details._cover_field; var admitted: Array[Vector2i] = []; var omitted := 0; var inactive := 0
	var peak_delta := 0.0
	for y in N:
		for x in N:
			var p := centre+Vector2((x+0.37)/N-0.5,(y+0.63)/N-0.5)*8
			var anchor := field.surface_anchor(p); var original := field.sample(p)
			if not anchor.is_finite() or original.is_empty(): omitted += 1; continue
			var h := raster_height(t,p)
			check(is_finite(h),"oracle has an actual drawn triangle "+label+" "+str(p))
			if not is_finite(h): continue
			inactive += int(anchor.x<0); admitted.append(Vector2i(x,y))
			peak_delta = maxf(peak_delta,absf(h-float(original.height)))
			var base := verts.size()
			for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var clip := (Vector2(x,y)+corner)/N*2-Vector2.ONE
				verts.append(Vector3(clip.x,0,-clip.y)); uv.append(Vector2(float(original.height)+0.008,0))
				anchors.append_array([anchor.x,anchor.y,anchor.z,anchor.w]); expected.append_array([h+0.008+(0.02 if wrong else 0),0,0,0])
			ids.append_array([base,base+1,base+2,base,base+2,base+3])
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=ids
	arrays[Mesh.ARRAY_CUSTOM0]=anchors; arrays[Mesh.ARRAY_CUSTOM1]=expected
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Geometry.FORMAT | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	var view := SubViewport.new(); view.size = Vector2i(N,N)*4; view.own_world_3d = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var camera := Camera3D.new(); view.add_child(camera); camera.position = Vector3(0,3,0); camera.look_at(Vector3.ZERO,Vector3.BACK); camera.current = true
	var node := MeshInstance3D.new(); node.mesh = mesh; node.extra_cull_margin = 100; view.add_child(node)
	var material := ShaderMaterial.new(); material.shader = probe_shader(); t.ground_surface_data(true).bind(material,true); node.material_override = material
	var image := await snap(view,"probe-"+label)
	var bad := 0; var rendered := 0
	# POSITION probes can have the renderer's render-target Y flip. Count
	# every rasterized cell; each quad carries its own expected height.
	for y in N:
		for x in N:
			var c := image.get_pixel(x*4+2,y*4+2)
			bad += int(c.r>0.9); rendered += int(c.r>0.9 or c.g>0.9)
	var missing := admitted.size()-rendered
	check(missing==0,"all probe vertices actually rendered "+label+" missing="+str(missing))
	check(bad==admitted.size() if wrong else bad==0,"GPU root height within 2 mm of installed triangles "+label+" bad="+str(bad))
	rows.append({"case":"probe","label":label,"samples":admitted.size(),"omitted_ambiguous":omitted,"inactive":inactive,"bad":bad,"missing":missing,"largest_ground_motion_m":peak_delta,"negative_control":wrong})
	print("COVER_SURFACE_PROBE ",JSON.stringify(rows.back()))
	view.free(); await frames(2)

func camera_clear(d: TerrainDetails, focus: Vector3) -> bool:
	var from := focus+Vector3(0,0.4,0); var to := focus+Vector3(2.7,2.8,3.5)
	for i in 16:
		var point := from.lerp(to,float(i)/15); var p := Vector2(point.x,-point.z); var hit := d.surface_sample(p)
		if hit.is_empty() or float(hit.height)>point.y-0.15: return false
		for record: Dictionary in d._scenery.get(Vector2i((p/8).floor()),[]):
			var inverse: Transform3D = record.inverse
			if (record.box as AABB).intersects_segment(inverse*from,inverse*to)!=null: return false
	return true

func choose(d: TerrainDetails, type: int, hint: Vector2) -> Dictionary:
	var keys: Array[Vector2i] = []
	for y in int(d.terrain.size_ei().y/8):
		for x in int(d.terrain.size_ei().x/8): keys.append(Vector2i(x,y))
	keys.sort_custom(func(a: Vector2i,b: Vector2i): return (Vector2(a)*8-hint).length_squared()<(Vector2(b)*8-hint).length_squared())
	for key in keys:
		for record: Dictionary in d._cover_field.records(key,d._scenery.get(key,[]),d._trees.get(key,[])):
			if record.kind!=Cover.Kind.DRY or d.terrain.ground_type(record.p.x,record.p.y)!=type or record.anchor.x<0: continue
			if camera_clear(d,Vector3(record.p.x,record.height,-record.p.y)): return record
	return {}

func build(d: TerrainDetails, centre: Vector2) -> void:
	d.prepare_grass(); var focus := Vector2i((centre/8).floor())
	for y in range(focus.y-1,focus.y+2):
		for x in range(focus.x-1,focus.x+2):
			var key := Vector2i(x,y)
			if not d._chunks.has(key): d._install_chunk(key,d.instances(key))
	d._cover_material.set_shader_parameter("view_position",Vector3(centre.x,0,-centre.y))

func boundary(t: EITerrain, hint: Vector2) -> Vector2:
	var best := Vector2.INF; var distance := INF
	for axis in 2:
		for line in range(32,int(t.size_ei()[axis])-1,32):
			for value in range(4,int(t.size_ei()[1-axis])-4,2):
				var p := Vector2(line,value+0.37) if axis==0 else Vector2(value+0.37,line)
				var valid := true
				for offset: Vector2 in [Vector2.ZERO,Vector2(-0.4,0),Vector2(0.4,0),Vector2(0,-0.4),Vector2(0,0.4)]:
					if not t.details.soft_ground.step_allowed(p+offset): valid=false; break
				if valid and p.distance_squared_to(hint)<distance: best=p; distance=p.distance_squared_to(hint)
	return best

func timing(view: SubViewport, label: String) -> void:
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	await frames(40); var cpu := []; var gpu := []
	for i in 80:
		await frames(1)
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
	cpu.sort(); gpu.sort(); rows.append({"case":"timing","label":label,"cpu_median_ms":cpu[40],"gpu_median_ms":gpu[40],"cpu_p95_ms":cpu[76],"gpu_p95_ms":gpu[76]})

func run() -> void:
	var id := "gz11k"; var type := 9; var hint := Vector2(396.1418,171.3711)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--surface-zone="): id = arg.trim_prefix("--surface-zone=")
	if id=="gz15h": type=3; hint=Vector2(151.5,191.5)
	var view := SubViewport.new(); view.size=Vector2i(800,600); view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF; add_child(view)
	var world := GameWorld.new(); world.process_mode=Node.PROCESS_MODE_PAUSABLE; view.add_child(world); world.set_process(false); world.set_physics_process(false)
	world.zone=CampaignMap.load_from(GameData.texts).zone(id)
	var map := EIMapScene.load_map(world.zone.mpr,world.zone.get("mob",""),false); world.add_child(map); world.map=map; world.terrain=map.terrain
	var t := map.terrain; t.set_process(false); var d := t.details; d.set_process(false); d.soft_ground.set_process(false)
	var started := Time.get_ticks_usec(); d.prepare_grass()
	rows.append({"case":"prepare","us":Time.get_ticks_usec()-started,"vertices_texture_bytes":t.grid_w*(t.sectors_y*32+1)*16})
	var chosen := choose(d,type,hint); check(not chosen.is_empty(),"full-scene dry cover on authored soft ground")
	if chosen.is_empty(): view.free(); return
	var p: Vector2=chosen.p; var focus := Vector3(p.x,chosen.height,-p.y); build(d,p)
	rows.append({"case":"scene","zone":id,"type":type,"point":str(p),"record":str(chosen)})
	var soft := d.soft_ground
	if OS.get_cmdline_user_args().has("--surface-script-mesh"): soft._native_mesh=false
	check(d._cover_surface==t.ground_surface_data(),"cover shares the map geometry resource")
	check(d._cover_surface.normals==null and d._cover_surface.metadata==null,"cover alone does not build contact-light normals or metadata")
	check(d._cover_material.get_shader_parameter("query_tracks")==soft.shared_field().texture,"cover uses the existing deformation field")
	var field_id := soft.field.texture.get_rid()
	var camera := Camera3D.new(); view.add_child(camera); camera.position=focus+Vector3(2.7,2.8,3.5); camera.look_at(focus); camera.current=true
	var env := WorldEnvironment.new(); env.environment=Environment.new(); Gfx.setup_original_env(env.environment)
	env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.13,0.20,0.28); view.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-40,-35,0); sun.shadow_enabled=true; view.add_child(sun)
	var lamp := OmniLight3D.new(); lamp.position=focus+Vector3(1,2,1); lamp.omni_range=8; lamp.shadow_enabled=true; view.add_child(lamp)
	Gfx.set_light(Color(0.5,0.5,0.5),Color(0.75,0.75,0.75)); Gfx.set_foliage_wind(false)
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO); RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	for chunk: MultiMeshInstance3D in d._chunks.values(): chunk.visible=false
	await frames(160)
	var original := await snap(view,"original-before-probe")
	await probe(t,p,"startup-control")
	rows.append({"case":"original-probe-control","difference":difference(original,await snap(view,"original-after-probe"))})
	for chunk: MultiMeshInstance3D in d._chunks.values(): chunk.visible=true
	await frames(160)
	await probe(t,p,"loose"); await probe(t,p,"negative-control",true)
	var base := await snap(view,"loose")
	check(difference(base,await snap(view,"loose-stable")).changed==0,"unchanged scene has settled before the footprint comparisons")
	d._cover_material.shader=Geometry.shader(false,false)
	var detached := await snap(view,"detached-control"); var diff := difference(base,detached)
	check(diff.over_2>5,"attachment visibly changes loose-ground roots")
	rows.append({"case":"detached-control","difference":diff})
	if OS.get_cmdline_user_args().has("--surface-timing"): await timing(view,"detached")
	d._apply_grass_material()
	if OS.get_cmdline_user_args().has("--surface-timing"): await timing(view,"attached")
	soft.add_step(p,Vector2(0.30,0.46),0.4)
	check(not soft.sectors.is_empty(),"real footprint admitted")
	await probe(t,p,"pending")
	check(difference(base,await snap(view,"pending")).changed==0,"queued footprint leaves cover and ground at the old height")
	drain(soft); await probe(t,p,"installed")
	var pressed := await snap(view,"installed"); diff=difference(base,pressed)
	check(diff.over_2>10,"installed footprint visibly changes the surface")
	rows.append({"case":"footprint","difference":diff})
	for chunk: MultiMeshInstance3D in d._chunks.values(): d.remove_child(chunk); d.add_child(chunk)
	check(difference(pressed,await snap(view,"shadow-refresh")).changed==0,"moving cover and its cached shadows agree after refresh")
	GameData.options["gfx_vegetation_interaction"]=1; GameData.options["gfx_wind"]=1; d.apply_options(); build(d,p)
	var wave_clock := [t._waves.ticks,t._waves.acc,t._waves.phase]
	t._waves.advance(0.3); d._apply_grass_material()
	var pressure := d.interaction; pressure.focus=Vector2(p.x,-p.y)
	d._cover_material.set_shader_parameter("vegetation_focus",pressure.focus)
	var contacts: Array[Dictionary]=[{"id":1,"p":pressure.focus,"extent":Vector2(0.8,0.8),"angle":0.0}]
	for i in 10: pressure.advance(contacts,pressure.focus,0.05)
	var combined := await snap(view,"wind-pressure-tracks")
	check(difference(pressed,combined).over_2>5,"wind and pressure remain visible over a real footprint")
	process_mode=Node.PROCESS_MODE_ALWAYS; get_tree().paused=true; Engine.time_scale=1; soft.set_process(true)
	var age := soft._age; var held := await snap(view,"paused")
	check(difference(held,await snap(view,"paused-later")).changed==0 and soft._age==age,"tree pause holds tracks and cover together")
	soft.set_process(false); get_tree().paused=false; Engine.time_scale=0; process_mode=Node.PROCESS_MODE_INHERIT
	# Restore the clock used to pose the wind. Otherwise a later apply_gfx()
	# also advances the map's original distant water, invalidating the image
	# round-trip control even though the cover itself has returned correctly.
	t._waves.ticks=wave_clock[0]; t._waves.acc=wave_clock[1]; t._waves.phase=wave_clock[2]; t._update_wave_parameters()
	GameData.options["gfx_vegetation_interaction"]=0; GameData.options["gfx_wind"]=0; d.apply_options(); build(d,p)
	check(difference(pressed,await snap(view,"interaction-restored")).changed==0,"disabling interaction restores the deformed cover image")
	pressure=null
	soft._process(210); drain(soft); await probe(t,p,"fading")
	soft._process(31); drain(soft); await probe(t,p,"expired")
	check(soft.sectors.is_empty(),"last expired footprint releases sectors")
	check(difference(base,await snap(view,"expired")).changed==0,"expiry returns both ground and cover to loose layer")
	soft.add_step(p,Vector2(0.30,0.46),0.4); drain(soft); await probe(t,p,"reallocated")
	check(soft.field.texture.get_rid()==field_id,"track growth/clear keeps bound texture RID")
	soft.clear(); await probe(t,p,"clear")
	check(difference(base,await snap(view,"cleared")).changed==0,"explicit track clear restores root heights")
	var edge := boundary(t,p); check(edge.is_finite(),"authored soft ground crosses a sector boundary")
	if edge.is_finite():
		soft.add_step(edge,Vector2(0.30,0.46),0.4); drain(soft)
		check(soft.sectors.size()>=2,"boundary footstep installs adjacent sectors")
		await probe(t,edge,"sector-border")
		soft._restore(soft.sectors.keys()[0]); await probe(t,edge,"sector-eviction")
		soft.clear()
		rows.append({"case":"sector-boundary","point":str(edge)})
	# A later contact consumer adds its lighting normals and bounds in-place.
	# Existing cover materials must keep the same resource and rendered result.
	var data := t.ground_surface_data(); var vertex_id := data.vertices.get_rid()
	var full := ShaderMaterial.new(); full.shader=Shader.new(); full.shader.code="shader_type spatial;"
	data.bind(full)
	check((data.normals!=null or data.metadata!=null) and data.vertices.get_rid()==vertex_id,"contact upgrade preserves the cover vertex texture RID")
	check(difference(base,await snap(view,"contact-upgrade")).changed==0,"contact data upgrade leaves attached cover identical")
	full=null; data=null
	# Real water-level changes rebuild placement and rebind the surviving track
	# field. No gameplay/save state is changed by this isolated map fixture.
	var water_material := -1
	for material: int in t.water_mat:
		if material<64: water_material=material; break
	if water_material>=0:
		t.set_water_offset(water_material,0.3); build(d,p)
		check(d._cover_material.get_shader_parameter("level")==t._level,"water level reaches the rebuilt cover material")
		await probe(t,p,"water-raised")
		t.set_water_offset(water_material,0); build(d,p)
		check(difference(base,await snap(view,"water-restored")).changed==0,"water round trip restores cover and original geometry")
	rows.append({"case":"water-level","material":water_material,"applicable":water_material>=0})
	var surface_ref := weakref(d._cover_surface)
	GameData.options["gfx_soft_ground"]=0; t.apply_gfx(); await frames()
	check(d._cover_surface==null and surface_ref.get_ref()==null,"soft-ground off releases cover's geometry snapshot")
	check(d._cover_material.get_shader_parameter("query_vertices")==null and d._cover_material.get_shader_parameter("query_tracks")==null,"unused material drops field textures")
	var off := await snap(view,"soft-off")
	GameData.options["gfx_soft_ground"]=1; t.apply_gfx(); d.soft_ground.set_process(false)
	check(difference(base,await snap(view,"soft-restored")).changed==0,"soft option round trip restores the original image")
	check(d._cover_surface!=null and d._cover_material.get_shader_parameter("query_tracks")==d.soft_ground.shared_field().texture,"new deformation owner rebound after option toggle")
	GameData.options["gfx_soft_ground"]=0; t.apply_gfx()
	check(difference(off,await snap(view,"soft-off-restored")).changed==0,"disabled soft ground retains its own exact image")
	surface_ref=weakref(t.ground_surface_data()); check(surface_ref.get_ref()==null,"terrain's weak cache does not retain unused optional resources")
	view.free(); await frames()

func _ready() -> void:
	for option in ["gfx_hd_textures","gfx_terrain","gfx_ground_contact","gfx_grass","gfx_vegetation_interaction","gfx_wind","gfx_water","gfx_water_interaction","gfx_water_caustics","gfx_volumetric","gfx_ssao","gfx_bloom","confine_mouse","vsync"]: GameData.options[option]=0
	GameData.options["gfx_biome_cover"]=1; GameData.options["gfx_soft_ground"]=1
	Engine.max_fps=120; Engine.time_scale=0; DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE; RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	anchor_rules()
	if DisplayServer.get_name()=="headless": check(false,"this fixture requires a real renderer")
	else: await run()
	TexUpscale.shutdown(); await frames(12)
	FileAccess.open("user://biome-cover-surface.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("BIOME_COVER_SURFACE checks=",checks," failures=",failures)
	get_tree().quit(1 if failures else 0)
