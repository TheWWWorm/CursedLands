extends Node
## Sample the production array against independently decoded authored mips.
## Generated tails compare the same BC1 blocks decoded on CPU. The 6/255
## hardware-BC allowance is the established MMP upload contract.
var checks := 0
var failures := 0
var rows := []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",label)

func frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame

func specimen(map_name: String) -> void:
	var archive := EIResArchive.open_path(GameData.root.path_join("maps/%s.mpr" % map_name))
	var prefix := EITerrain.resolve_map_prefix(archive,map_name)
	var header := archive.read(prefix+".mp")
	var terrain := EITerrain.new(); terrain.resource_prefix = prefix
	terrain.texture_size = header.decode_u32(20); terrain.set_meta("textures_count",header.decode_u32(16))
	terrain._load_atlases()
	var original: Array[Image] = []
	var decoded: Array[Image] = []
	var counts := []
	for i in terrain._atlases.get_layers():
		var data := GameData.textures.read("%s%03d.mmp" % [prefix,i])
		counts.append(data.decode_u32(12))
		original.append(EIMmp.decode_texture(data,false))
		# GL's array readback regenerates lower mips from mip zero. Decode
		# the input blocks on CPU for the generated-tail upload control.
		var pixels := EIMmp.decode_texture(data,RenderingServer.has_os_feature("s3tc"))
		if pixels.is_compressed(): pixels.decompress()
		pixels.convert(Image.FORMAT_RGBA8); decoded.append(pixels)
	var authored_texture := Texture2DArray.new(); authored_texture.create_from_images(original)
	var tail_texture := Texture2DArray.new(); tail_texture.create_from_images(decoded)
	var layers := [0]
	if counts.size() > 2: layers.append(counts.size()/2)
	if counts.size() > 1: layers.append(counts.size()-1)
	var view := SubViewport.new(); view.size = Vector2i(384,layers.size()*4*96)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(view)
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2DArray atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform float mip = 0.0;
uniform float layer = 0.0;
void fragment() { COLOR = textureLod(atlas,vec3(UV,layer),mip); }
"""
	var cases := []
	for layer: int in layers:
		for mip: int in [0,1,counts[layer]-1,original[layer].get_mipmap_count()]:
			var textures := [terrain._atlases,authored_texture if mip < counts[layer] else tail_texture]
			for column in 2:
				var rect := ColorRect.new(); rect.position = Vector2(column*192,cases.size()*96); rect.size = Vector2(192,96)
				var material := ShaderMaterial.new(); material.shader = shader
				material.set_shader_parameter("atlas",textures[column]); material.set_shader_parameter("mip",float(mip))
				material.set_shader_parameter("layer",float(layer)); rect.material = material; view.add_child(rect)
			cases.append({"layer":layer,"mip":mip,"authored":mip < counts[layer]})
	await frames(8)
	var shot := view.get_texture().get_image()
	var compressed := terrain._atlases.get_format() in [Image.FORMAT_DXT1,Image.FORMAT_DXT3]
	for i in cases.size():
		var maximum := 0; var bad := 0; var sum_error := 0
		for y in range(i*96,(i+1)*96):
			for x in 192:
				var a := shot.get_pixel(x,y); var b := shot.get_pixel(x+192,y)
				var delta := roundi(255.0*maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
				maximum = maxi(maximum,delta); sum_error += delta
				if delta > (6 if compressed else 0): bad += 1
		check(bad == 0,"array sampling "+map_name+" "+str(cases[i])+" max="+str(maximum)+" bad="+str(bad))
		rows.append({"map":map_name,"format":terrain._atlases.get_format(),"layer":cases[i].layer,"mip":cases[i].mip,
			"authored":cases[i].authored,"max_rgb_bytes":maximum,"mean_max_rgb_bytes":float(sum_error)/(192*96),"bad_pixels":bad})
	check(shot.save_png("user://terrain-compressed-upload-"+map_name+".png") == OK,"save upload capture")
	view.free(); terrain.free(); await frames(4)

func _ready() -> void:
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	GameData.options["gfx_hd_textures"] = 0; GameData.options["confine_mouse"] = 0; Engine.max_fps = 120
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.set_render_loop_enabled(true)
	for name: String in (["zone1","zone3dun1","zonefinal"] if GameData.campaign_id == CampaignProfile.ASTRAL else ["bz2g","bz13h"]):
		await specimen(name)
	await frames(12)
	var report := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"s3tc":RenderingServer.has_os_feature("s3tc"),"rows":rows}
	FileAccess.open("user://terrain-compressed-upload.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("TERRAIN_COMPRESSED_UPLOAD ",JSON.stringify(report))
	get_tree().quit(1 if failures else 0)
