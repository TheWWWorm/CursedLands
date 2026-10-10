extends RefCounted
## GLES reserves texture unit 9 for scene depth on 16-unit devices. Keep all
## enhanced-water variants below it, including current, history and clouds.
## Original nearest float tables and all noise mip levels retain their bytes.
static var _tables: ImageTexture
static var _noise: Texture2DArray
static var _sources: Array[Texture2D] = []


static func bind(material: ShaderMaterial, sine: Texture2D, phase: Texture2D, noises: Array[Texture2D]) -> void:
	if not Portability.compatibility(): return
	if _tables == null:
		var data := sine.get_image().get_data()
		data.append_array(phase.get_image().get_data())
		_tables = ImageTexture.create_from_image(Image.create_from_data(512,3,false,Image.FORMAT_RF,data))
	if _noise == null:
		_noise = Texture2DArray.new()
		_sources = noises
		for texture: Texture2D in _sources:
			texture.changed.connect(_refresh_noise)
		_refresh_noise()
	material.set_shader_parameter("water_tables",_tables)
	material.set_shader_parameter("water_noise",_noise)


static func _refresh_noise() -> void:
	var images: Array[Image] = []
	for i in _sources.size():
		var pixels := _sources[i].get_image()
		if pixels == null or pixels.is_empty():
			# NoiseTexture2D finishes asynchronously. Use neutral normals and
			# white foam independently until each layer's pixels arrive.
			pixels = Image.create(256,256,false,Image.FORMAT_RGB8)
			pixels.fill(Color(0.5,0.5,1.0) if i < 2 else Color.WHITE)
			pixels.generate_mipmaps()
		else:
			pixels = pixels.duplicate() as Image
			pixels.convert(Image.FORMAT_RGB8)
		images.append(pixels)
	# Replacing storage preserves the resource/RID held by existing materials.
	var error := _noise.create_from_images(images)
	if error != OK: push_error("Water noise upload failed: " + str(error))


static func source(original: String) -> String:
	if not Portability.compatibility() or not original.contains("#define EI_WATER_FX"):
		return original
	var code := original
	for name: String in ["sine_tex","phase_tex","wave_a","wave_b","foam_tex"]:
		code = RegEx.create_from_string("uniform sampler2D " + name + "[^;]*;").sub(code,"",true)
	code = code.replace("texelFetch(sine_tex, ivec2(index, 0), 0)","texelFetch(water_tables, ivec2(index, 0), 0)")
	code = code.replace("texelFetch(phase_tex, ivec2(cr), 0)","texelFetch(water_tables, ivec2((int(cr.y)*32+int(cr.x))&511,1+(int(cr.y)>>4)), 0)")
	for i in 3:
		var name: String = ["wave_a","wave_b","foam_tex"][i]
		for operation: String in ["texture","textureLod","textureGrad"]:
			code = code.replace(operation+"("+name+",", "water_noise_"+operation+"("+str(i)+".0,")
	return code.replace("shader_type spatial;", """shader_type spatial;
uniform sampler2D water_tables : filter_nearest, repeat_disable;
uniform sampler2DArray water_noise : filter_linear_mipmap, repeat_enable;
vec4 water_noise_texture(float layer,vec2 uv) { return texture(water_noise,vec3(uv,layer)); }
vec4 water_noise_textureLod(float layer,vec2 uv,float lod) { return textureLod(water_noise,vec3(uv,layer),lod); }
vec4 water_noise_textureGrad(float layer,vec2 uv,vec2 dx,vec2 dy) { return textureGrad(water_noise,vec3(uv,layer),dx,dy); }
""")
