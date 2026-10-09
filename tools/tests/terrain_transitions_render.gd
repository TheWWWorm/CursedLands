extends Node
const Field = preload("res://src/game/fx/terrain_transition.gd")
const SITES := {"zone1":Vector2i(120,14),"zone11":Vector2i(69,87),"zone15":Vector2i(55,54)}
const PATH_MASK := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D terrain_tiles : filter_nearest, repeat_disable;
void fragment() {
	int width=textureSize(terrain_tiles,0).x; int id=int(UV2.y+0.5);
	int ground=int(texelFetch(terrain_tiles,ivec2(id%width,id/width),0).g+0.5);
	ALBEDO=vec3(ground==1 || ground==4 || ground==7 ? 1.0 : 0.0);
}
"""
var checks := 0
var failures := 0
var records := []

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)

func frames(n := 6) -> void:
	for i in n: await get_tree().process_frame

func capture(view: SubViewport,label: String) -> Image:
	await frames(12); await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
	image.save_png("user://terrain-transitions-"+label+".png")
	return image

func difference(a: Image,b: Image) -> Dictionary:
	var aa:=a.get_data();var bb:=b.get_data();var changed:=0;var peak:=0;var total:=0
	for i in range(0,aa.size(),4):
		var delta:=0
		for k in 3: delta=maxi(delta,absi(int(aa[i+k])-int(bb[i+k])))
		if delta:changed+=1
		peak=maxi(peak,delta);total+=delta
	return {"changed_pixels":changed,"peak_byte_delta":peak,"sum":total}

func scenery(terrain: EITerrain,focus: Vector3) -> MeshInstance3D:
	var root:=Node3D.new();terrain.add_child(root)
	var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=Vector3(1.2,1.4,1.2);node.mesh=mesh;root.add_child(node)
	node.position=focus+Vector3(0,0.55,0)
	var material:=ShaderMaterial.new();material.shader=Gfx.make_shader(EIFigure.OBJECT_SHADER)
	material.set_meta("ground_contact_source",EIFigure.OBJECT_SHADER)
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8);image.fill(Color(0.45,0.23,0.12))
	material.set_shader_parameter("albedo_tex",ImageTexture.create_from_image(image));node.material_override=material
	GroundContact.attach(root,terrain);return node

func path_site(terrain: EITerrain) -> Vector2i:
	var field:=Field.new(terrain);var best:=0;var result:=Vector2i(-1,-1)
	for y in range(7,field.tile_size.y-7):
		for x in range(7,field.tile_size.x-7):
			var code:=terrain.land_tile[y*field.tile_size.x+x]
			if terrain.tile_types[code&16383] not in [1,4,7]:continue
			if terrain.land_n[(y*2+1)*terrain.grid_w+x*2+1].y<0.9:continue
			var close:=0
			for dy in range(-3,4):
				for dx in range(-3,4):
					var row:=field.rows[(y+dy)*field.tile_size.x+x+dx]
					if row.a>0 and row.r!=row.g:close+=1
			if close>best:best=close;result=Vector2i(x,y)
	return result

func case(name: String,path_control := false) -> void:
	var label:=name+"-path" if path_control else name
	GameData.options.gfx_terrain=1
	Gfx.apply_surface_options()
	var view:=SubViewport.new();view.size=Vector2i(640,480);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var terrain:=EITerrain.load_map(name);view.add_child(terrain);terrain.set_process(false);terrain.apply_gfx()
	var tile: Vector2i=path_site(terrain) if path_control else SITES[name]
	check(tile.x>=0,"valid fixed or authored path anchor "+label)
	var x:=tile.x*2+1;var y:=tile.y*2+1
	var focus:=Vector3(x,terrain.heights[y*terrain.grid_w+x],-y)
	var camera:=Camera3D.new();view.add_child(camera);camera.position=focus+Vector3(5,8,7);camera.look_at(focus);camera.current=true
	var env:=WorldEnvironment.new();env.environment=Environment.new();Gfx.setup_original_env(env.environment);view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);view.add_child(sun)
	Gfx.set_light(Color(0.65,0.65,0.65),Color(0.75,0.75,0.75));RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO);RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	var figure: MeshInstance3D
	if "--transition-contact" in OS.get_cmdline_user_args(): figure=scenery(terrain,focus)
	var tracks:=0
	if "--transition-tracks" in OS.get_cmdline_user_args():
		var soft:=terrain.details.soft_ground
		for dx in [-0.4,0.0,0.4]:soft.add_step(Vector2(focus.x+dx,-focus.z),Vector2(0.18,0.30),0.3)
		for i in 5:soft._process(0);soft._finish_mesh_jobs(true)
		for entry: Dictionary in soft.sectors.values():
			var node: MeshInstance3D=entry.node.get_ref()
			if node and node.mesh!=entry.source:tracks+=1
		check(tracks>0,"real footprints have installed dense terrain receivers "+name)
		soft.set_process(false)
	if is_instance_valid(terrain.color_cache): terrain.color_cache.prepare(camera);terrain.color_cache.set_process(false)
	await frames(60)
	check(terrain._transitions==null,"Detailed creates no transition owner "+name)
	var before:=await capture(view,label+"-detailed")
	var height:=terrain.heights.duplicate();var xy:=terrain.land_xy.duplicate();var codes:=terrain.land_tile.duplicate()
	var old_shader:=terrain._land_mat.shader
	GameData.options.gfx_terrain=2;Gfx.apply_surface_options();terrain.apply_gfx();await frames(60)
	check(terrain._transitions!=null and terrain._transitions.admitted>0,"Natural mode admits verified map "+name)
	check(terrain._land_mat.shader!=old_shader,"live 1 to 2 swaps program despite unchanged boolean Gfx mode "+name)
	var field: Field=terrain._transitions
	var row:=field.rows[tile.y*field.tile_size.x+tile.x]
	check(row.a==0 if path_control else row.a>0 and row.r!=row.g,"authored scene anchor has expected admission "+label)
	var after:=await capture(view,label+"-natural")
	var delta:=difference(before,after)
	check(delta.changed_pixels>100 and delta.peak_byte_delta>5,"natural boundary visibly changes "+name)
	check(terrain.heights==height and terrain.land_xy==xy and terrain.land_tile==codes,"visible transition leaves geometry and original rotations exact "+name)
	var path_pixels:=0
	if path_control:
		var saved:=terrain._land_mat.shader
		var mask_shader:=Shader.new();mask_shader.code=PATH_MASK;terrain._land_mat.shader=mask_shader
		var mask:=await capture(view,label+"-mask")
		terrain._land_mat.shader=saved
		var aa:=before.get_data();var bb:=after.get_data();var mm:=mask.get_data();var wrong:=0
		for i in range(0,mm.size(),4):
			if mm[i]<250 or mm[i+1]<250 or mm[i+2]<250:continue
			path_pixels+=1
			if aa[i]!=bb[i] or aa[i+1]!=bb[i+1] or aa[i+2]!=bb[i+2]:wrong+=1
		check(path_pixels>500 and wrong==0,"all original dirt/path/paving pixels retain exact colour and relief "+label+" pixels="+str(path_pixels)+" changed="+str(wrong))
	if figure:
		check(figure.material_override.shader.code.contains("#define EI_TERRAIN_TRANSITIONS"),"contact compiles shared transition source "+name)
		check(figure.material_override.get_shader_parameter("transition_tiles")==field.tiles,"contact shares land field "+name)
	if tracks>0:
		for entry: Dictionary in terrain.details.soft_ground.sectors.values():
			check(entry.material.shader.code.contains("#define EI_TERRAIN_TRANSITIONS") and entry.material.get_shader_parameter("transition_tiles")==field.tiles,"installed footprint receiver shares current transition source and field "+name)
	if "--transition-composed" in OS.get_cmdline_user_args():
		check(terrain._land_mat.shader.code.contains("ei_cloud_sun") and terrain._land_mat.shader.code.contains("caustic_bed") and terrain._land_mat.shader.code.contains("#define EI_TERRAIN_CLIFFS"),"natural sampler composes with cloud caustic and cliff receivers")
		check(terrain._water_mat.shader.code.contains("water_current") and terrain._water_mat.shader.code.contains("water_wave_field"),"neighbouring water current and wave program remains installed")
	var empty:=Image.create(field.tile_size.x,field.tile_size.y,false,Image.FORMAT_RGBAF);empty.fill(Color(0,0,0,0));field.tiles.update(empty)
	check(difference(before,await capture(view,label+"-neutral")).changed_pixels==0,"unclassified field preserves exact original colour and relief "+name)
	field.tiles.update(Image.create_from_data(field.tile_size.x,field.tile_size.y,false,Image.FORMAT_RGBAF,field.rows.to_byte_array()))
	check(difference(after,await capture(view,label+"-restored")).changed_pixels==0,"static field restores exact natural image "+name)
	var cached:=0
	if is_instance_valid(terrain.color_cache):
		cached=terrain.color_cache._resident.size();check(cached>0,"native immutable base cache is active "+name)
		for entry: Dictionary in terrain.color_cache._resident.values():
			check(entry.material.shader.code.contains("#define EI_TERRAIN_TRANSITIONS") and entry.material.get_shader_parameter("transition_tiles")==field.tiles,"cached land applies the same live transition field "+name)
	var weak:=weakref(field);field=null
	GameData.options.gfx_terrain=1;Gfx.apply_surface_options();terrain.apply_gfx();await frames(30)
	check(terrain._transitions==null and weak.get_ref()==null,"1 mode releases transition owner and shaders "+name)
	check(difference(before,await capture(view,label+"-disabled")).changed_pixels==0,"2 to 1 restores exact original image "+name)
	if figure:check(not figure.material_override.shader.code.contains("#define EI_TERRAIN_TRANSITIONS"),"2 to 1 retires contact transition variant "+name)
	if tracks>0:
		for entry: Dictionary in terrain.details.soft_ground.sectors.values():check(entry.material.get_shader_parameter("transition_tiles")==null,"installed footprint receiver releases retired field "+name)
	if is_instance_valid(terrain.color_cache):
		for entry: Dictionary in terrain.color_cache._resident.values():check(entry.material.get_shader_parameter("transition_tiles")==null,"cached materials release retired field "+name)
	GameData.options.gfx_terrain=0;Gfx.apply_surface_options();terrain.apply_gfx();await frames(30)
	check(terrain._transitions==null,"Original mode has no transition allocations "+name)
	await capture(view,label+"-original")
	records.append({"map":name,"label":label,"tile":str(tile),"focus":str(focus),"row":str(row),"difference":delta,"path_pixels":path_pixels,"cached_sectors":cached,"deformed_sectors":tracks,"renderer":RenderingServer.get_current_rendering_method()})
	view.free();await frames()

func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"q_aa":0,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":3},true)
	if "--transition-contact" in OS.get_cmdline_user_args():GameData.options.gfx_ground_contact=1
	if "--transition-soft" in OS.get_cmdline_user_args() or "--transition-tracks" in OS.get_cmdline_user_args():GameData.options.gfx_soft_ground=1
	if "--transition-composed" in OS.get_cmdline_user_args():
		for key in ["gfx_materials","gfx_clouds","gfx_weather_surfaces","gfx_water","gfx_water_caustics","gfx_water_current","gfx_water_interaction","gfx_water_waves","gfx_terrain_cliffs"]:GameData.options[key]=1
	Gfx.ensure_globals();Engine.time_scale=0;Engine.max_fps=120;process_mode=Node.PROCESS_MODE_ALWAYS
	Gfx.apply_surface_options();RenderingServer.set_render_loop_enabled(true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	if "--transition-path" in OS.get_cmdline_user_args():await case("zone1",true)
	elif "--transition-composed" in OS.get_cmdline_user_args():await case("zone11")
	elif "--transition-tracks" in OS.get_cmdline_user_args():await case("zone11");await case("zone15")
	else:
		for name: String in SITES:await case(name)
	TexUpscale.shutdown();await frames(12)
	FileAccess.open("user://terrain-transitions-render.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":records},"\t"))
	print("TERRAIN_TRANSITIONS_RENDER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
