extends "res://tools/tests/path_trace_camera_routes.gd"
## Actual Suslanger loose sand (zone19) with derived terrain surface maps:
## sand gains its own relief and wind ripples in raster, traced terrain binds
## the same maps, and Surface materials off restores the established path.

func sand_site(session: Session) -> Vector2:
	# The flattest open spot with loose sand all around it, clear of objects.
	var placed: Array[Vector2]=[]
	for object: Variant in session.world.objects.values():
		if object is Node3D:placed.append(Vector2(object.global_position.x,-object.global_position.z))
	var size:=t.size_ei();var best:=-INF;var result:=Vector2(-1,-1)
	for y in range(24,int(size.y)-24,3):
		for x in range(24,int(size.x)-24,3):
			if t.ground_type(x,y)!=3:continue
			var clear:=true
			for p: Vector2 in placed:
				if p.distance_squared_to(Vector2(x,y))<14.0*14.0:clear=false;break
			if not clear:continue
			var sand:=0;var low:=INF;var high:=-INF
			for dy in range(-6,7,2):
				for dx in range(-6,7,2):
					sand+=int(t.ground_type(x+dx,y+dy)==3)
					var h:=t.height_at(x+dx,y+dy);low=minf(low,h);high=maxf(high,h)
			var water:=t.water_at(x,y)
			if is_finite(water) and water>t.height_at(x,y)-1.0:continue
			var score:=sand-(high-low)*2.0
			if score>best:best=score;result=Vector2(x,y)
	return result

func land_materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial]=[]
	for mesh: Node in t.find_children("*","MeshInstance3D",true,false):
		var material:=(mesh as MeshInstance3D).get_active_material(0) as ShaderMaterial
		if material!=null and material.shader!=null and material.shader.code.contains("#define EI_TERRAIN_LIGHT") \
			and material.shader.code.contains("uniform bool surface_maps") and not result.has(material):result.append(material)
	return result

func set_maps(enabled: bool) -> void:
	for material in land_materials():material.set_shader_parameter("surface_maps",enabled)

## The production shading normal, independent of colour and lighting.
func normal_capture(label: String) -> Image:
	var saved:=[];var shaders:={}
	for mesh: Node in t.find_children("*","MeshInstance3D",true,false):
		var original:=(mesh as MeshInstance3D).get_active_material(0) as ShaderMaterial
		if original==null or original.shader==null or not original.shader.code.contains("#define EI_TERRAIN_LIGHT"):continue
		var material:=original.duplicate() as ShaderMaterial
		var key:=original.shader.get_instance_id()
		if not shaders.has(key):
			var shader:=Shader.new()
			shader.code=Gfx._function_tail(original.shader.code.replace("render_mode ","render_mode unshaded, fog_disabled, "),"fragment","""
	ALBEDO=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz)*0.5+0.5;
	EMISSION=vec3(0.0);FOG=vec4(0.0);
""")
			shaders[key]=shader
		material.shader=shaders[key]
		saved.append([mesh,(mesh as MeshInstance3D).get_surface_override_material(0)])
		(mesh as MeshInstance3D).set_surface_override_material(0,material)
	await frames(12);var image:=await capture(label)
	for row: Array in saved:row[0].set_surface_override_material(0,row[1])
	await frames(8)
	return image

## Mean absolute difference between neighbouring pixels: fine normal detail.
func detail(image: Image,rect: Rect2i) -> float:
	var total:=0.0;var count:=0
	for y in range(rect.position.y,rect.end.y,2):
		for x in range(rect.position.x,rect.end.x,2):
			var d:=image.get_pixel(x,y)-image.get_pixel(x+2,y)
			var e:=image.get_pixel(x,y)-image.get_pixel(x,y+2)
			total+=(absf(d.r)+absf(d.b)+absf(e.r)+absf(e.b))*0.25;count+=1
	return total/maxf(count,1)

func difference(a: Image,b: Image,rect: Rect2i) -> float:
	var total:=0.0;var count:=0
	for y in range(rect.position.y,rect.end.y,2):
		for x in range(rect.position.x,rect.end.x,2):
			var d:=a.get_pixel(x,y)-b.get_pixel(x,y)
			total+=(absf(d.r)+absf(d.g)+absf(d.b))/3.0;count+=1
	return total/maxf(count,1)

func run() -> void:
	map_name="zone19";resolution=Vector2i(1920,1080);out="user://terrain-surface"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--surface-res="):
			var parts:=arg.trim_prefix("--surface-res=").split("x");resolution=Vector2i(int(parts[0]),int(parts[1]))
	var context:=await setup_route()
	if context.is_empty():get_tree().quit(1);return
	var session: Session=context[0];var game: Game=context[1]
	GameData.options.merge({"pt_mode":0,"gfx_soft_ground":0,"gfx_terrain_cliffs":1},true)
	t.apply_gfx();Gfx.apply_env(game._env);await frames(20)
	for unit: GameUnit in session.world.units.values():unit.hide()
	var site:=sand_site(session)
	check(site.x>=0,"Suslanger contains an open loose-sand site")
	if site.x<0:get_tree().quit(1);return
	var focus:=Vector3(site.x,t.height_at(site.x,site.y),-site.y)
	camera.global_position=focus+Vector3(2.5,5.0,4.0);camera.look_at(focus)
	if t.color_cache!=null:t.color_cache.clear();t.color_cache.set_process(false)
	check(t._surface_maps!=null,"surface maps are derived for the installed Suslanger atlases")
	if t._surface_maps==null:get_tree().quit(1);return
	check(t._surface_maps.get_layers()==t._detail_atlases.get_layers() and t._surface_maps.get_width()==t._detail_atlases.get_width(),
		"surface maps match the padded atlas layout")
	var materials:=land_materials()
	check(not materials.is_empty() and materials.all(func(m:ShaderMaterial)->bool:return m.get_shader_parameter("surface_maps")==true \
		and m.get_shader_parameter("surface_atlases")==t._surface_maps),"every land material binds the derived maps")
	check(materials.all(func(m:ShaderMaterial)->bool:return m.get_shader_parameter("surface_tuning")==TerrainSurfaceMaps.tuning),
		"every land material uses the derived-map strength")
	var view:=Rect2i(Vector2i(resolution.x*3/10,resolution.y*3/10),Vector2i(resolution.x*4/10,resolution.y*4/10))
	await frames(30)
	var lit_on:=await capture("sand-raster-maps")
	var normals_on:=await normal_capture("sand-normals-maps")
	set_maps(false);await frames(12)
	var lit_off:=await capture("sand-raster-established")
	var normals_off:=await normal_capture("sand-normals-established")
	set_maps(true);await frames(12)
	var before:=detail(normals_off,view);var after:=detail(normals_on,view)
	print("TERRAIN_SURFACE_SAND_DETAIL ",before," -> ",after)
	check(after>before*1.3,"loose sand gains visible fine relief: %.5f -> %.5f"%[before,after])
	check(difference(lit_on,lit_off,view)>0.004,"derived relief changes the lit sand: %.5f"%difference(lit_on,lit_off,view))
	check(difference(lit_on,await capture("sand-raster-restored"),view)<0.002,"re-enabling maps restores the same image")
	# The selected strength is visibly stronger than the first, unit-gain pass.
	var selected:=TerrainSurfaceMaps.tuning
	TerrainSurfaceMaps.tuning=Vector4(1.0,1.0,0.11,1.0);t.apply_gfx();await frames(12)
	check(land_materials().all(func(m:ShaderMaterial)->bool:return m.get_shader_parameter("surface_tuning")==TerrainSurfaceMaps.tuning),
		"a strength change reaches every land material")
	var normals_unit:=await normal_capture("sand-normals-unit-strength")
	var unit:=detail(normals_unit,view)
	print("TERRAIN_SURFACE_STRENGTH ",unit," -> ",after)
	check(after>unit*1.15,"selected strength adds relief over unit gain: %.5f -> %.5f"%[unit,after])
	TerrainSurfaceMaps.tuning=selected;t.apply_gfx();await frames(12)
	check(difference(lit_on,await capture("sand-raster-selected-again"),view)<0.002,"restoring the strength restores the same image")
	# Path tracing: the same maps through the traced terrain header.
	GameData.options.merge({"pt_mode":2,"pt_accumulation":1},true);Gfx.apply_env(game._env)
	var rt: Node=game.get_node("SceneRaytrace")
	check(await ready_scene(rt),"traced sand prepares")
	if rt.device!=null:
		check(rt.device.terrain.surface==t._surface_maps,"PT retains the derived surface maps")
		check((rt.device.terrain.data.decode_u32(44)&2)!=0,"PT terrain header enables the derived maps")
		var header:=func()->Vector4:
			var d: PackedByteArray=rt.device.terrain.data
			return Vector4(d.decode_float(64),d.decode_float(68),d.decode_float(72),d.decode_float(76))
		check(header.call().is_equal_approx(TerrainSurfaceMaps.tuning),"PT terrain header carries the derived-map strength")
		var selected_pt:=TerrainSurfaceMaps.tuning
		TerrainSurfaceMaps.tuning=Vector4(1.0,1.0,0.11,1.0);await frames(4)
		check(await ready_scene(rt) and header.call().is_equal_approx(TerrainSurfaceMaps.tuning),"a strength change rebuilds the traced terrain header")
		TerrainSurfaceMaps.tuning=selected_pt;await frames(4);await ready_scene(rt)
		await frames(120);var traced:=await capture("sand-pt-maps")
		var output: Image=rt.device.output.get_image();var finite:=true
		for y in range(0,output.get_height(),7):
			for x in range(0,output.get_width(),7):
				var c:=output.get_pixel(x,y)
				if not (is_finite(c.r) and is_finite(c.g) and is_finite(c.b)):finite=false
		check(finite,"traced terrain output stays finite with derived maps")
		check(difference(traced,lit_on,view)>0.0,"traced capture is distinct from raster")
	# Option off: no derived maps in raster or PT.
	GameData.options.gfx_materials=0;t.apply_gfx();Gfx.apply_env(game._env)
	check(t._surface_maps==null and land_materials().all(func(m:ShaderMaterial)->bool:return m.get_shader_parameter("surface_maps")==false),
		"Surface materials off releases the derived maps")
	if rt.device!=null:
		await frames(4);check(await ready_scene(rt),"traced terrain rebuilds without derived maps")
		check(rt.device.terrain.surface==null and (rt.device.terrain.data.decode_u32(44)&2)==0,"PT header clears the derived maps")
		await frames(90);await capture("sand-pt-established")
	GameData.options.gfx_materials=1;GameData.options.pt_mode=0;t.apply_gfx();Gfx.apply_env(game._env);await frames(20)
	check(t._surface_maps!=null,"Surface materials on derives the maps again")
	# Localized option help mentions the new ground relief.
	var help:String=GameData.REMAKE_OPTIONS["gfx_materials"][1]
	for language: String in ["en","ru","de"]:
		RemakeText.lang=language
		var text:=RemakeText.t(help)
		check(not text.is_empty() and (language=="en" or text!=help),"Surface materials help is translated: "+language)
		check(text.contains(["sand","песке","Sand"][["en","ru","de"].find(language)]),"help mentions loose sand: "+language)
	RemakeText.lang="en"
	FileAccess.open(out.path_join("terrain-surface-live.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,
		"map":map_name,"resolution":[resolution.x,resolution.y],"site":[site.x,site.y],"camera":str(camera.global_transform),
		"normal_detail_established":before,"normal_detail_maps":after},"\t"))
	game.queue_free();session.queue_free();await frames(16);TexUpscale.shutdown()
	print("TERRAIN_SURFACE_LIVE ",checks," checks ",failures.size()," failures");get_tree().quit(0 if failures.is_empty() else 1)
