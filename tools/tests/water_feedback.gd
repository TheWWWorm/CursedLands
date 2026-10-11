extends Node
## GPU sampling of actual LiA tile edges, reflection coverage, and map renders.
var checks := 0
var failures := 0
var out := "user://water-feedback"
var old_source := ""
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func frames(n:=6) -> void:
	for i in n: await get_tree().process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await frames()
	get_viewport().get_texture().get_image().save_png(out.path_join(name+".png"))
func canvas_image(code: String, dimensions: Vector2i, parameters: Dictionary) -> Image:
	var view:=SubViewport.new();view.size=dimensions;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var rect:=ColorRect.new();rect.size=dimensions;view.add_child(rect)
	var shader:=Shader.new();shader.code=code
	var material:=ShaderMaterial.new();material.shader=shader;rect.material=material
	for key in parameters:material.set_shader_parameter(key,parameters[key])
	await frames()
	var result:=view.get_texture().get_image();view.free();return result
func tile_probe(source: String, terrain: EITerrain, points: Image, label: String) -> Dictionary:
	var helpers:=source.substr(source.find("vec2 tile_turn"),source.find("vec3 scene_pos")-source.find("vec2 tile_turn"))
	helpers=helpers.replace("vec3 water_texture(vec3 own, vec2 dx, vec2 dy)","vec3 water_texture(vec3 own, vec2 dx, vec2 dy, vec2 grid_position)").replace("vec2 g = tgrid;","vec2 g = grid_position;")
	var code:="""shader_type canvas_item;
uniform sampler2DArray atlases : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D water_tiles : filter_nearest, repeat_disable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D points : filter_nearest, repeat_disable;
uniform float tiles_per_axis;
uniform float source_texel;
uniform bool blend_tiles = true;
"""+helpers+"""
void fragment() {
 vec4 edge = texelFetch(points, ivec2(0, int(FRAGCOORD.y)), 0);
 vec2 g = edge.xy + edge.zw * (FRAGCOORD.x < 1.0 ? -0.0001 : 0.0001);
 int code = tile_code(ivec2(floor(g)), 0);
 vec2 dx = vec2(0.0001,0.0); vec2 dy = vec2(0.0,0.0001);
 vec3 own = tile_sample(code,fract(g),dx,dy);
 COLOR = vec4(water_texture(own,dx,dy,g),1.0);
}
"""
	var params:={"points":ImageTexture.create_from_image(points)}
	for key in ["atlases","water_tiles","foam_tex","tiles_per_axis","source_texel"]:params[key]=terrain._water_mat.get_shader_parameter(key)
	var img:=await canvas_image(code,Vector2i(2,points.get_height()),params)
	img.save_png(out.path_join(label+"-tile-edges.png"))
	var peak:=0.0;var visible:=0;var sum:=0.0
	for y in img.get_height():
		var a:=img.get_pixel(0,y);var b:=img.get_pixel(1,y)
		var d:=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))*255.0
		peak=maxf(peak,d);sum+=d
		if d>2.1:visible+=1
	return {"samples":img.get_height(),"peak_byte_difference":peak,"visible_seams":visible,"mean_byte_difference":sum/img.get_height()}
func reflection_probe(source: String, label: String) -> Dictionary:
	var helper:=""
	if source.contains("vec4 reflection_over_sky"):
		var start:=source.find("vec4 reflection_over_sky")
		helper=source.substr(start,source.find("\n}",start)+2-start)
	else:
		# Exercise the old production statements as a negative control.
		var start:=source.find("R = mix(R, r.rgb, r.a);")
		var end:=source.find(";",source.find("w = mix(w, max(w, wm), r.a);",start))+1
		helper="vec4 reflection_over_sky(vec3 R, float w, vec4 r, float wm) {"+source.substr(start,end-start)+"return vec4(R,w); }"
	var code:="shader_type canvas_item;\n"+helper+"""
void fragment() {
 vec4 reflection = reflection_over_sky(vec3(0.8),0.01,vec4(vec3(0.03),UV.x),0.35);
 COLOR = vec4(vec3(0.02)*(1.0-reflection.a)+reflection.rgb*reflection.a,1.0);
}
"""
	var img:=await canvas_image(code,Vector2i(256,32),{})
	img.save_png(out.path_join(label+"-reflection-coverage.png"))
	var limit:=maxf(img.get_pixel(0,16).r,img.get_pixel(255,16).r);var peak:=0.0
	for x in 256:peak=maxf(peak,img.get_pixel(x,16).r)
	return {"endpoint_max":limit,"edge_peak":peak,"excess_bytes":(peak-limit)*255.0}
func _ready() -> void:_run.call_deferred()
func _run() -> void:
	var save_path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before-terrain="):
			old_source=FileAccess.get_file_as_string(arg.trim_prefix("--before-terrain=")).get_slice("const WATER_FX_SHADER := \"\"\"",1).get_slice("\"\"\"",0)
		if arg.begins_with("--route-save="):save_path=arg.trim_prefix("--route-save=")
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	check(not old_source.is_empty(),"old water shader supplied for rendered negative controls")
	if old_source.is_empty():get_tree().quit(1);return
	for option:Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"):GameData.options[option[0]]=0
	GameData.options.merge({"display_mode":0,"auto_graphics":0,"confine_mouse":0,"control_mode":1,"vsync":0,"q_shadows":0,"q_aa":0,"gfx_water":1,"gfx_weather_surfaces":1,"autosave":0,"show_tutorial":0,"unit_fog":0,"net_upnp":0,"net_lan":0,"net_directory":0},true)
	GameData.resolution_size="1280x720";GameData.options.resolution=GameData.resolutions().find(Vector2i(1280,720));GameData._apply_window()
	Engine.max_fps=60;RenderingServer.set_render_loop_enabled(true);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var s:=Session.new();add_child(s)
	var game:=Game.new();game.session=s;s.game=game;add_child(game)
	check(s._load_state("water_feedback",CampaignState.load_from(save_path)),"supplied LiA save loads for water captures")
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	game.rig.set_process(false);game.direct.set_process(false);game.hud.process_mode=Node.PROCESS_MODE_DISABLED;game.hud.hide();game.set_process(false)
	game.process_mode=Node.PROCESS_MODE_DISABLED;s.world.process_mode=Node.PROCESS_MODE_DISABLED
	for u:GameUnit in s.world.units.values():u.hide();u.set_process(false)
	var terrain:=s.world.terrain;terrain.set_process(false)
	var width:=terrain.sectors_x*EITerrain.TILES
	var points:Array[Vector4]=[];var seen:={}
	for y in range(1,terrain.sectors_y*EITerrain.TILES-1):
		for x in range(1,width-1):
			var code:=terrain.water_tile[y*width+x]
			if code<0:continue
			for axis in [Vector2i(1,0),Vector2i(0,1)]:
				var prev:=terrain.water_tile[(y-axis.y)*width+x-axis.x]
				var key:=[prev,code,axis]
				if prev<0 or seen.has(key):continue
				seen[key]=true
				for f in [0.13,0.37,0.61,0.89]:points.append(Vector4(x+(f if axis.y else 0.0),y+(f if axis.x else 0.0),axis.x,axis.y))
	var point_image:=Image.create(1,points.size(),false,Image.FORMAT_RGBAF)
	for i in points.size():point_image.set_pixel(0,i,Color(points[i].x,points[i].y,points[i].z,points[i].w))
	await frames(40)
	var old_tiles:=await tile_probe(old_source,terrain,point_image,"before")
	var new_tiles:=await tile_probe(EITerrain.WATER_FX_SHADER,terrain,point_image,"after")
	check(old_tiles.visible_seams>0,"old shader reproduces discontinuities at actual LiA water-tile borders")
	check(new_tiles.visible_seams==0,"enhanced water is continuous across sampled LiA tile borders")
	var old_reflection:=await reflection_probe(old_source,"before")
	var new_reflection:=await reflection_probe(EITerrain.WATER_FX_SHADER,"after")
	check(old_reflection.excess_bytes>2.0,"old reflection blend reproduces a bright silhouette outline")
	check(new_reflection.excess_bytes<=1.0,"partial reflection coverage cannot create a bright outline")
	var focus:=Vector3.ZERO;var best:=-INF
	for y in range(10,terrain.sectors_y*EITerrain.SECTOR-10,4):
		for x in range(10,terrain.sectors_x*EITerrain.SECTOR-10,4):
			var level:=terrain.water_at(x,y)
			if not is_finite(level):continue
			var score:=10.0
			for offset:Vector2 in [Vector2.ZERO,Vector2(6,6),Vector2(-6,6),Vector2(6,-6),Vector2(-6,-6)]:
				var p:=Vector2(x,y)+offset;var water:=terrain.water_at(p.x,p.y)
				if not is_finite(water) or absf(water-level)>0.2:score=-INF;break
				score=minf(score,water-terrain.height_at(p.x,p.y))
			if score>best:best=score;focus=Vector3(x,level,-y)
	check(best>0.5,"visual fixture contains a continuous patch of actual LiA water")
	var camera:=Camera3D.new();game.add_child(camera);camera.current=true;camera.position=focus+Vector3(2,5,5);camera.look_at(focus)
	RenderingServer.global_shader_parameter_set(&"ei_border",Vector4.ZERO)
	RenderingServer.global_shader_parameter_set(&"ei_fog",Vector3(200,300,0))
	Gfx.set_surface_weather(1.0,1.0)
	for variant in ["before","after"]:
		terrain._water_mat.shader=Gfx.make_shader(old_source if variant=="before" else EITerrain.WATER_FX_SHADER,true,true)
		terrain._water_mat.set_shader_parameter("waves",0.0)
		await capture(variant+"-lia-rain-water")
	GameData.options.gfx_water_reflections=2;terrain.apply_gfx()
	var reflection:=terrain._reflection;reflection.set_process(false)
	Gfx.set_surface_weather(0.0,0.0)
	var actor:GameUnit=s.party_heroes()[0]
	var mannequin:=EIUnitModel.create(actor.figure_info());game.add_child(mannequin)
	mannequin.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	mannequin.position=focus+Vector3(0,0.2,0)
	camera.position=focus+Vector3(4,3,7);camera.look_at(focus+Vector3.UP)
	for variant in ["before","after"]:
		terrain._water_mat.shader=Gfx.make_shader(old_source if variant=="before" else EITerrain.WATER_FX_SHADER,true,true)
		terrain._water_mat.set_shader_parameter("waves",0.0)
		reflection._process(0.2);await capture(variant+"-lia-mirror")
	check(terrain._water_mat.get_shader_parameter("planar_enabled")==true,"actual LiA mirror viewport is active")
	var visible_character:=reflection.viewport.get_texture().get_image().get_data()
	mannequin.hide();await frames()
	check(visible_character!=reflection.viewport.get_texture().get_image().get_data(),"actual LiA character contributes reflected pixels")
	FileAccess.open(out.path_join("verification.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"focus":str(focus),"before_tiles":old_tiles,"after_tiles":new_tiles,"before_reflection":old_reflection,"after_reflection":new_reflection},"\t"))
	game.queue_free();s.queue_free();await frames(10);TexUpscale.shutdown()
	print("WATER_FEEDBACK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
