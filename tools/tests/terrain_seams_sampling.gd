extends Node
## Render the production sampling functions. The authored zone11 vertices
## expose nonlinear coarse/dense gaps without any HD texture replacement.
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func capture(view:SubViewport)->Image:
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<800:
		RenderingServer.force_draw()
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func program(code:String)->Shader:
	var shader:=Shader.new();shader.code=code;shader.get_shader_uniform_list();return shader
func _ready()->void:
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"gfx_terrain":1,"gfx_soft_ground":1,"auto_graphics":0,"confine_mouse":0},true)
	RenderingServer.set_render_loop_enabled(true);Gfx.ensure_globals();Gfx.apply_surface_options()
	var view:=SubViewport.new();view.size=Vector2i(96,32);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.own_world_3d=true;add_child(view)
	var rect:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(6,2);rect.mesh=quad;view.add_child(rect)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2;view.add_child(camera);camera.position.z=2;camera.current=true
	var mat:=ShaderMaterial.new();rect.material_override=mat
	# Padded white tile surrounded by deliberately unrelated magenta tiles.
	var atlas:=Image.create(512,512,false,Image.FORMAT_RGBA8);atlas.fill(Color.MAGENTA);atlas.fill_rect(Rect2i(192,256,64,64),Color.WHITE)
	atlas=EITerrain.padded_atlas(atlas,64,8);atlas.generate_mipmaps()
	var textures:=Texture2DArray.new();textures.create_from_images([atlas])
	var code:="shader_type spatial;\nrender_mode unshaded, fog_disabled;\n"+GroundSurfaceShader.LAND_UNIFORMS+GroundSurfaceShader.TILE_FUNCTIONS+"""
void fragment() {
 float gradient=UV.x<0.333 ? 0.005 : (UV.x<0.666 ? 2.0 : 8.0);
 float position=UV.y<0.333 ? 0.0 : (UV.y<0.666 ? 0.5 : 1.0);
 ALBEDO=tile_sample(27.0,vec2(position),vec2(gradient,0),vec2(0,gradient));
}
"""
	mat.shader=program(code)
	mat.set_shader_parameter("atlases",textures);mat.set_shader_parameter("atlas_padding",.125)
	print("PROBE shader uniforms ",mat.shader.get_shader_uniform_list().size())
	var fixed:=await capture(view)
	fixed.save_png("user://atlas-fixed.png")
	for y in [5,16,27]:
		for x in [16,48,80]:check(fixed.get_pixel(x,y).g>.98,"tile stays white at border/centre and near/far footprint %d,%d"%[x,y])
	var begin:=code.find("// BEGIN_ATLAS_FOOTPRINT");var end:=code.find("// END_ATLAS_FOOTPRINT")
	mat.shader=program(code.erase(begin,end-begin))
	var before:=await capture(view)
	before.save_png("user://atlas-before.png")
	# Forward+ reproduces the coarse-mip leak; this GL driver clamps the
	# former sampler too. Both renderers must keep every fixed tile white.
	if RenderingServer.get_current_rendering_method()=="forward_plus":
		check(before.get_pixel(80,16).g<.8,"former coarse atlas sampling reproduces unrelated bright colour leakage")
	check(before.get_pixel(16,16)==fixed.get_pixel(16,16),"ordinary close sampling remains unchanged")
	# The first Ingos map, original geometry and original texture profiles.
	var map:=EIMapScene.load_map("zone11","",false);add_child(map)
	var terrain:=map.terrain
	view.size=Vector2i(terrain.grid_w-1,terrain.sectors_y*32);quad.size=Vector2(float(view.size.x)/view.size.y*2,2)
	mat.shader=program("shader_type spatial;\nrender_mode unshaded, fog_disabled;\n"+GroundSurfaceShader.LAND_UNIFORMS+GroundSurfaceShader.SOFT_UNIFORMS+GroundSurfaceShader.SOFT_FUNCTIONS+"""
vec3 point_at(ivec2 cell) {
 vec3 p=texelFetch(soft_vertices,cell,0).rgb;
 return vec3(vec2(cell)+p.xz,p.y);
}
void fragment() {
 ivec2 cell=ivec2(UV*vec2(textureSize(soft_vertices,0)-1));
 // Shared tile edges in both directions; sample a dense-only midpoint.
 ivec2 axis=(cell.x%2==0) ? ivec2(0,1) : ivec2(1,0);
 vec3 a=point_at(cell), b=point_at(cell+axis), p=(a+b)*0.5;
 float coarse=(soft_surface(a.xy,a.z).x+soft_surface(b.xy,b.z).x)*0.5;
 float previous=soft_surface(p.xy,p.z).x;
 float fixed=soft_profile_grid(vec2(cell)+vec2(axis)*0.5).x;
 ALBEDO=vec3(min(abs(previous-coarse)*10.0,1.0),min(abs(fixed-coarse)*1000.0,1.0),0);
}
""")
	for key:StringName in [&"terrain_tiles",&"terrain_cells",&"soft_vertices",&"level"]:mat.set_shader_parameter(key,terrain._land_mat.get_shader_parameter(key))
	var seam:=await capture(view);seam.save_png("user://snow-edge-displacement.png")
	var old_max:=0.0;var new_max:=0.0;var cracked:=0
	for y in seam.get_height():
		for x in seam.get_width():
			var pixel:=seam.get_pixel(x,y);old_max=maxf(old_max,pixel.r);new_max=maxf(new_max,pixel.g);cracked+=int(pixel.r>.05)
	check(cracked>10,"original Ingos edges reproduce dense/coarse snow cracks without HD Lands")
	check(new_max<.01,"all sampled shared edges retain the coarse triangle's height")
	print("TERRAIN_SEAMS_SAMPLING old_gap_at_least=",old_max/10," new_gap_upper_bound=",(new_max+1.0/255.0)/1000," old_cracked_edges=",cracked)
	map.free();view.free();TexUpscale.shutdown()
	print("TERRAIN_SEAMS_SAMPLING ",checks," checks ",failures," failures");get_tree().quit(int(failures>0))
