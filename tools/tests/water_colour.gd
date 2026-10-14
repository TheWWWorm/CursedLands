extends Node
## GPU checks for liquid palettes without painted lines and continuous seams.
var checks := 0
var failures := 0
var rows := []
var previous := ""
var atlas: Texture2DArray

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func frames(n := 8) -> void:
	for i in n:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func pixels(source: String, codes: Array, rect: Vector4, blend := false, size := Vector2i(256,128)) -> Image:
	var helpers := source.substr(source.find("vec2 tile_turn"),source.find("vec3 scene_pos")-source.find("vec2 tile_turn"))
	helpers=helpers.replace("vec3 water_texture(vec3 own, vec2 dx, vec2 dy)","vec3 water_texture(vec3 own, vec2 dx, vec2 dy, vec2 grid_position)").replace("vec2 g = tgrid;","vec2 g = grid_position;")
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2DArray atlases : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D water_tiles : filter_nearest, repeat_disable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform float tiles_per_axis = 8.0;
uniform float source_texel = 0.001953125;
uniform bool blend_tiles = false;
uniform vec4 grid_rect;
""" + helpers + """
void fragment() {
	vec2 g = grid_rect.xy + UV * grid_rect.zw;
	vec2 dx = dFdx(g); vec2 dy = dFdy(g);
	int code = tile_code(ivec2(floor(g)), 0);
	vec3 own = tile_sample(code, fract(g), dx, dy);
	COLOR = vec4(water_texture(own, dx, dy, g), 1.0);
}
"""
	var view := SubViewport.new(); view.size=size; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(view)
	var canvas := ColorRect.new(); canvas.size=size; view.add_child(canvas)
	var mat := ShaderMaterial.new(); mat.shader=shader; canvas.material=mat
	var tiles := Image.create(codes.size(),1,false,Image.FORMAT_RF)
	for i in codes.size(): tiles.set_pixel(i,0,Color(codes[i],0,0))
	mat.set_shader_parameter("atlases",atlas)
	mat.set_shader_parameter("water_tiles",ImageTexture.create_from_image(tiles))
	mat.set_shader_parameter("foam_tex",Gfx.noise("foam",256,0.03,4))
	mat.set_shader_parameter("grid_rect",rect); mat.set_shader_parameter("blend_tiles",blend)
	await frames()
	var image := view.get_texture().get_image(); view.free(); return image

func spread(image: Image) -> float:
	var lo := 1.0; var hi := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x,y)
			lo=minf(lo,c.b); hi=maxf(hi,c.b)
	return (hi-lo)*255.0

func mean(image: Image) -> Vector3:
	var sum := Vector3.ZERO
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x,y); sum+=Vector3(c.r,c.g,c.b)
	return sum/(image.get_width()*image.get_height())

func metadata_codes(texture: Texture2D) -> PackedInt32Array:
	# GLES ImageTexture.get_image() reads through RGBA8, clamping float
	# metadata to 0..1. Encode the shader's sampled integers into three
	# byte channels before readback so this checks the actual GPU data.
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
render_mode unshaded;
uniform sampler2D codes : filter_nearest, repeat_disable;
void fragment() {
	ivec2 cell = ivec2(UV * vec2(textureSize(codes, 0)));
	int code = int(texelFetch(codes, cell, 0).r) + 1;
	COLOR = vec4(float(code & 255), float((code >> 8) & 255), float((code >> 16) & 255), 255.0) / 255.0;
}
"""
	var view := SubViewport.new()
	view.size = Vector2i(texture.get_width(), texture.get_height())
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var canvas := ColorRect.new(); canvas.size = view.size; view.add_child(canvas)
	var mat := ShaderMaterial.new(); mat.shader = shader; canvas.material = mat
	mat.set_shader_parameter("codes", texture)
	await frames()
	var image := view.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	var result := PackedInt32Array(); result.resize(view.size.x * view.size.y)
	for i in result.size():
		result[i] = (int(bytes[i * 4]) | (int(bytes[i * 4 + 1]) << 8) | (int(bytes[i * 4 + 2]) << 16)) - 1
	view.free()
	return result

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before-terrain="):
			var text := FileAccess.get_file_as_string(arg.trim_prefix("--before-terrain="))
			previous=text.get_slice("const WATER_FX_SHADER := \"\"\"",1).get_slice("\"\"\"",0)
	check(not previous.is_empty(),"previous production shader supplied")
	if previous.is_empty(): get_tree().quit(1); return
	Engine.time_scale=0; Engine.max_fps=120; RenderingServer.set_render_loop_enabled(true); Gfx.ensure_globals()
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var image := Image.create(512,512,false,Image.FORMAT_RGB8); image.fill(Color.MAGENTA)
	var colours := [Color(0.10,0.24,0.34),Color(0.08,0.19,0.04),Color(0.65,0.12,0.02),Color(0.12,0.32,0.27)]
	for tile in 4:
		for y in 64:
			for x in 64:
				var c: Color=colours[tile]
				if x%16<2 or y%16<2: c=c.lightened(0.2)
				image.set_pixel(tile*64+x,448+y,c)
	image.generate_mipmaps(); atlas=Texture2DArray.new(); atlas.create_from_images([image])
	await frames(40)
	for tile in 3:
		var code := tile | EITerrain.WATER_TILE_COLOUR
		var before := await pixels(previous,[code],Vector4(0.0,0.0,1.0,1.0))
		var after := await pixels(EITerrain.WATER_FX_SHADER,[code],Vector4(0.0,0.0,1.0,1.0))
		before.save_png("user://water-colour-%d-before.png"%tile); after.save_png("user://water-colour-%d-after.png"%tile)
		var label: String = ["clear water","swamp","lava"][tile]
		check(spread(before)>15,label+": baseline contains painted lines")
		check(spread(after)<=1,label+": palette sampling removes painted lines throughout a tile")
		var drift := (mean(before)-mean(after)).abs()*255.0
		check(maxf(drift.x,maxf(drift.y,drift.z))<12,label+": retains its authored colour")
		rows.append({"case":label,"before_spread":spread(before),"after_spread":spread(after),"mean_drift_bytes":str(drift)})
	var codes := [EITerrain.WATER_TILE_COLOUR,EITerrain.WATER_TILE_COLOUR|1,EITerrain.WATER_TILE_COLOUR|2,EITerrain.WATER_TILE_COLOUR|3]
	var peak := 0.0
	for boundary in [1.0,2.0,3.0]:
		var edge := await pixels(EITerrain.WATER_FX_SHADER,codes,Vector4(boundary-0.0002,0.1,0.0004,0.8),true,Vector2i(2,256))
		for y in edge.get_height():
			var a := edge.get_pixel(0,y); var b := edge.get_pixel(1,y)
			peak=maxf(peak,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))*255.0)
	check(peak<=2,"clear water, bog and lava tile boundaries remain continuous")
	rows.append({"case":"mixed-liquid-seams","peak_delta_bytes":peak})
	# Exercise the production metadata builder on authored water, preserving
	# all original codes while marking every liquid atlas entry.
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]]=0
	var terrain := EITerrain.load_map("zone1")
	var packed := await metadata_codes(terrain._water_tile_tex)
	var plain := 0; var bog := 0; var valid := true
	var per_tex := (terrain.texture_size/terrain.tile_size)*(terrain.texture_size/terrain.tile_size)
	for i in terrain.water_tile.size():
		var source := terrain.water_tile[i]
		var code := packed[i]
		if source<0: valid=valid and code==source; continue
		valid=valid and (code&65535)==source
		var index := ((source>>6)&255)*per_tex+(source&63)
		if index>=terrain.tile_types.size(): continue
		valid=valid and (code&EITerrain.WATER_TILE_COLOUR)!=0
		if terrain.tile_types[index]==14: bog+=1
		else: plain+=1
	check(valid and plain>0 and bog>0,"authored map keeps tile identities and smooths clear water and swamp palettes")
	rows.append({"case":"authored-zone1","clear_tiles":plain,"swamp_tiles":bog})
	terrain.free(); TexUpscale.shutdown(); await frames()
	FileAccess.open("user://water-colour.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
	print("WATER_COLOUR ",checks," checks ",failures," failures"); get_tree().quit(1 if failures else 0)
