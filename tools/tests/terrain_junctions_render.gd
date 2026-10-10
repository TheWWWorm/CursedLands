extends "terrain_transitions_render.gd"
## Render original verified junctions without replacing the game atlas or mesh.
## The baseline flag records the prior deliberately unclassified junctions.
const BASE_SITES := [
	{"map":"zone15", "tile":Vector2i(69,19), "corners":[40,40,22,17]},
	{"map":"zone12", "tile":Vector2i(67,127), "corners":[11,26,10,34]},
	{"map":"bz11k", "tile":Vector2i(21,56), "corners":[29,13,30,32]},
	{"map":"bz11k", "tile":Vector2i(47,17), "corners":[29,30,23,29]},
]
const ASTRAL_SITES := [
	{"map":"zone26", "tile":Vector2i(19,58), "corners":[29,23,30,29]},
	{"map":"zone2", "tile":Vector2i(158,15), "corners":[17,18,17,21]},
	{"map":"bz22k", "tile":Vector2i(67,127), "corners":[11,26,10,34]},
]
const TARGET_MASK := """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform int target_id;
void fragment() { ALBEDO=vec3(int(UV2.y+0.5)==target_id ? 1.0 : 0.0); }
"""

func land_materials(terrain: EITerrain) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial]=[terrain._land_mat]
	if terrain._pair_land_mat: result.append(terrain._pair_land_mat)
	if is_instance_valid(terrain.color_cache):
		for entry: Dictionary in terrain.color_cache._resident.values():result.append(entry.material)
	if is_instance_valid(terrain.details.soft_ground):
		for entry: Dictionary in terrain.details.soft_ground.sectors.values():result.append(entry.material)
	return result

func target_difference(a: Image,b: Image,mask: Image) -> Dictionary:
	var aa:=a.get_data();var bb:=b.get_data();var mm:=mask.get_data()
	var visible:=0;var changed:=0;var peak:=0
	for i in range(0,aa.size(),4):
		if mm[i]<250 or mm[i+1]<250 or mm[i+2]<250:continue
		visible+=1
		var delta:=0
		for k in 3:delta=maxi(delta,absi(int(aa[i+k])-int(bb[i+k])))
		if delta:changed+=1
		peak=maxi(peak,delta)
	return {"visible_pixels":visible,"changed_pixels":changed,"peak_byte_delta":peak}

func junction(site: Dictionary) -> void:
	var name: String=site.map;var tile: Vector2i=site.tile
	var label: String=name+"-"+str(tile.x)+"-"+str(tile.y)
	var args:=OS.get_cmdline_user_args()
	var baseline:=args.has("--junction-baseline")
	GameData.options.gfx_terrain=0;Gfx.apply_surface_options()
	var view:=SubViewport.new();view.size=Vector2i(640,480);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var terrain:=EITerrain.load_map(name);view.add_child(terrain);terrain.set_process(false);terrain.apply_gfx()
	var x:=tile.x*2+1;var y:=tile.y*2+1;var index:=y*terrain.grid_w+x
	var center:=Vector2(x,y)+terrain.land_xy[index]
	var focus:=Vector3(center.x,terrain.heights[index],-center.y)
	var camera:=Camera3D.new();view.add_child(camera)
	# These authored witnesses include cliff feet. A low oblique camera can
	# sit inside a neighbouring cliff while still producing a target mask.
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=10
	camera.position=focus+Vector3(0,20,0);camera.look_at(focus,Vector3.FORWARD);camera.current=true
	var env:=WorldEnvironment.new();env.environment=Environment.new();Gfx.setup_original_env(env.environment);view.add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);view.add_child(sun)
	Gfx.set_light(Color(0.65,0.65,0.65),Color(0.75,0.75,0.75))
	RenderingServer.global_shader_parameter_set(&"ei_sun_dir",sun.global_basis.z.normalized())
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(100,180,0))
	check(terrain._transitions==null,"Original has no transition owner "+label)
	var original:=await capture(view,label+"-original")
	GameData.options.gfx_terrain=1;Gfx.apply_surface_options();terrain.apply_gfx()
	var figure: MeshInstance3D
	if args.has("--junction-contact"):figure=scenery(terrain,focus+Vector3(1.3,0,0))
	var tracks:=0
	if args.has("--junction-tracks"):
		var soft:=terrain.details.soft_ground
		for dx in [-0.4,0.0,0.4]:soft.add_step(Vector2(focus.x+dx,-focus.z),Vector2(0.18,0.30),0.3)
		for i in 5:soft._process(0);soft._finish_mesh_jobs(true)
		for entry: Dictionary in soft.sectors.values():
			var node: MeshInstance3D=entry.node.get_ref()
			if node and node.mesh!=entry.source:tracks+=1
		check(tracks>0,"real dense footprint receivers installed "+label);soft.set_process(false)
	if is_instance_valid(terrain.color_cache):terrain.color_cache.prepare(camera);terrain.color_cache.set_process(false)
	await frames(60)
	var before:=await capture(view,label+"-detailed")
	check(terrain._transitions==null,"Detailed has no transition owner "+label)
	var height:=terrain.heights.duplicate();var xy:=terrain.land_xy.duplicate();var codes:=terrain.land_tile.duplicate()
	var code:=terrain.land_tile[tile.y*terrain.sectors_x*16+tile.x];var slot:=code&16383
	var atlas:=GameData.load_image("%s%03d" % [terrain.resource_prefix,slot>>6])
	var corners:=Field.Tiles.corners(atlas).slice((slot&63)*4,((slot&63)+1)*4)
	check(Array(Field.world_corners(corners,code>>14))==site.corners,"independent original atlas witness and rotation "+label)
	print("JUNCTION_NATURAL_BEGIN ",label," ",Time.get_ticks_msec())
	GameData.options.gfx_terrain=2;Gfx.apply_surface_options();terrain.apply_gfx()
	print("JUNCTION_NATURAL_INSTALLED ",label," ",Time.get_ticks_msec())
	await frames(60)
	print("JUNCTION_NATURAL_SETTLED ",label," ",Time.get_ticks_msec())
	var field: Field=terrain._transitions
	check(field!=null and field.admitted>0,"Natural field active "+label)
	var row:=field.rows[tile.y*field.tile_size.x+tile.x]
	check(row.a==0 if baseline else row.a<0,"expected baseline rejection or full junction admission "+label)
	var after:=await capture(view,label+"-natural")
	check(terrain.heights==height and terrain.land_xy==xy and terrain.land_tile==codes,"original geometry and tile codes exact "+label)
	var mats:=land_materials(terrain);var saved_shaders: Array[Shader]=[]
	var mask_shader:=Shader.new();mask_shader.code=TARGET_MASK
	for mat: ShaderMaterial in mats:
		saved_shaders.append(mat.shader);mat.shader=mask_shader
		mat.set_shader_parameter("target_id",tile.y*field.tile_size.x+tile.x)
	var mask:=await capture(view,label+"-target-mask")
	for i in mats.size():mats[i].shader=saved_shaders[i]
	var target:=target_difference(before,after,mask)
	check(target.visible_pixels>500,"authored junction is actually visible "+label+" "+str(target))
	if baseline:check(target.changed_pixels==0,"old implementation leaves junction pixels exact "+label)
	else:check(target.changed_pixels>100 and target.peak_byte_delta>5,"new junction itself visibly changes "+label+" "+str(target))
	for mat: ShaderMaterial in mats:
		check(mat.shader.code.contains("#define EI_TERRAIN_TRANSITIONS") and mat.get_shader_parameter("transition_tiles")==field.tiles,"land/footprint/cache shares live sampler "+label)
	if figure:check(figure.material_override.shader.code.contains("#define EI_TERRAIN_TRANSITIONS") and figure.material_override.get_shader_parameter("transition_tiles")==field.tiles,"contact shares live sampler "+label)
	var saved_pixels:=field.tiles.get_image()
	var empty:=Image.create(saved_pixels.get_width(),saved_pixels.get_height(),false,Image.FORMAT_RGBAF);empty.fill(Color(0,0,0,0))
	field.tiles.update(empty)
	check(difference(before,await capture(view,label+"-neutral")).changed_pixels==0,"neutral field restores exact Detailed color and relief "+label)
	field.tiles.update(saved_pixels)
	check(difference(after,await capture(view,label+"-restored")).changed_pixels==0,"restored field reproduces exact Natural output "+label)
	var cached:=terrain.color_cache._resident.size() if is_instance_valid(terrain.color_cache) else 0
	if args.has("--ei-baked-terrain"):check(cached>0,"real cached land installed "+label)
	if args.has("--junction-composed"):
		check(terrain._land_mat.shader.code.contains("ei_cloud_sun") and terrain._land_mat.shader.code.contains("caustic_bed") and terrain._land_mat.shader.code.contains("#define EI_TERRAIN_CLIFFS"),"cloud/caustic/cliff composition "+label)
	var weak:=weakref(field);var texture_bytes:=saved_pixels.get_data().size();field=null
	GameData.options.gfx_terrain=1;Gfx.apply_surface_options();terrain.apply_gfx();await frames(30)
	check(terrain._transitions==null and weak.get_ref()==null,"disable releases current transition owner "+label)
	check(difference(before,await capture(view,label+"-disabled")).changed_pixels==0,"disable restores exact Detailed output "+label)
	for mat: ShaderMaterial in land_materials(terrain):check(mat.get_shader_parameter("transition_tiles")==null,"receiver releases retired field "+label)
	if figure:check(not figure.material_override.shader.code.contains("#define EI_TERRAIN_TRANSITIONS"),"contact retires transition variant "+label)
	if figure:figure.get_parent().free()
	GameData.options.gfx_terrain=0;Gfx.apply_surface_options();terrain.apply_gfx();await frames(30)
	check(terrain._transitions==null,"Original releases transition allocations "+label)
	if tracks==0:check(difference(original,await capture(view,label+"-original-restored")).changed_pixels==0,"Original remains exact after Natural lifecycle "+label)
	records.append({"map":name,"tile":[tile.x,tile.y],"focus":[focus.x,focus.y,focus.z],"code":code,"row":str(row),"corners":site.corners,"target_difference":target,"full_difference":difference(before,after),"texture_bytes":texture_bytes,"cached_sectors":cached,"deformed_sectors":tracks,"renderer":RenderingServer.get_current_rendering_method()})
	view.free();await frames()

func _ready() -> void:
	var args:=OS.get_cmdline_user_args()
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"q_aa":0,"auto_graphics":0,"confine_mouse":0,"vsync":0,"fps_limit":3},true)
	if args.has("--junction-contact"):GameData.options.gfx_ground_contact=1
	if args.has("--junction-tracks"):GameData.options.gfx_soft_ground=1
	if args.has("--junction-composed"):
		for key in ["gfx_materials","gfx_clouds","gfx_weather_surfaces","gfx_water","gfx_water_caustics","gfx_water_current","gfx_water_interaction","gfx_water_waves","gfx_terrain_cliffs"]:GameData.options[key]=1
	Gfx.ensure_globals();Engine.time_scale=0;Engine.max_fps=120;process_mode=Node.PROCESS_MODE_ALWAYS
	Gfx.apply_surface_options();RenderingServer.set_render_loop_enabled(true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	var sites: Array=ASTRAL_SITES if GameData.campaign_id=="lost_in_astral" else BASE_SITES
	if args.has("--junction-one"):sites=[sites[0]]
	if args.has("--junction-snow"):sites=[sites[sites.size()-1] if GameData.campaign_id=="lost_in_astral" else sites[1]]
	for site: Dictionary in sites:await junction(site)
	TexUpscale.shutdown();await frames(12)
	FileAccess.open("user://terrain-junctions-render.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"baseline":args.has("--junction-baseline"),"rows":records},"\t")+"\n")
	print("TERRAIN_JUNCTIONS_RENDER ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
