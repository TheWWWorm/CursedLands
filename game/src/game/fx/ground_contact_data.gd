class_name GroundContactData
extends RefCounted
## Fit contact and native shadows within the tested Android GLES sampler
## budget. Static fields share one array; dynamic tracks and roof maps retain
## their existing resources. Forward+ and Mobile keep their original shaders.
const FIELDS := ["query_vertices", "query_normals", "query_light_inputs",
	"terrain_tiles", "terrain_cells", "cliff_tiles", "cliff_flatness", "transition_tiles"]
var texture := Texture2DArray.new()
var sizes := {}
var layers := {}
var size := Vector2i.ONE
var page_shift := Vector2i.ZERO
var bytes := 0


func build(images: Dictionary) -> void:
	sizes.clear(); layers.clear()
	# Keep the normalized water-cell lookup at its original dimensions.
	# floor(uv*size) disagrees with hardware nearest filtering at some edges
	# on NVIDIA GLES. All other packed fields already use integer texelFetch.
	size = images.terrain_cells.get_size()
	page_shift = Vector2i.ZERO
	while (1 << page_shift.x) < size.x: page_shift.x += 1
	while (1 << page_shift.y) < size.x * size.y: page_shift.y += 1
	var upload: Array[Image] = []
	for name: String in FIELDS:
		if not images.has(name): continue
		layers[name] = upload.size()
		sizes[name] = images[name].get_size()
		var pixels := images[name].duplicate() as Image
		pixels.convert(Image.FORMAT_RGBAF)
		var data := pixels.get_data()
		var stride := size.x * size.y * 16
		for start in range(0, data.size(), stride):
			var page := data.slice(start, mini(start + stride, data.size()))
			page.resize(stride)
			upload.append(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBAF, page))
	# Storage changes preserve the shared resource/RID used by fade copies.
	var error := texture.create_from_images(upload)
	if error != OK: push_error("Ground-contact metadata upload failed: " + str(error))
	bytes = size.x * size.y * 16 * upload.size()


func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("contact_data", texture)
	material.set_shader_parameter("contact_page_shift", page_shift)
	for name: String in layers:
		material.set_shader_parameter("contact_" + name + "_size", sizes[name])
		material.set_shader_parameter("contact_" + name + "_layer", layers[name])


static func _power_of_two(value: int) -> bool:
	return value > 0 and (value & (value - 1)) == 0


static func specialize(original: String, terrain: EITerrain) -> String:
	# Cells are sectors*32. These maps need no integer division per query tap;
	# other dimensions retain the general page layout and address calculation.
	if Portability.compatibility() and _power_of_two(terrain.sectors_x) and _power_of_two(terrain.sectors_y):
		return original.replace("shader_type spatial;", "shader_type spatial;\n#define EI_CONTACT_POWER_OF_TWO_PAGES")
	return original


static func source(original: String) -> String:
	if not Portability.compatibility() or not original.contains("#define EI_GROUND_CONTACT"):
		return original
	var code := original
	var helpers := """
uniform sampler2DArray contact_data : filter_nearest, repeat_disable;
vec4 contact_data_fetch(ivec2 p,ivec2 extent,int first_layer,int lod) {
	ivec2 page=textureSize(contact_data,0).xy;
	int index=p.y*extent.x+p.x;
	return texelFetch(contact_data,ivec3(index%page.x,(index/page.x)%page.y,first_layer+index/(page.x*page.y)),lod);
}
"""
	if original.contains("#define EI_CONTACT_POWER_OF_TWO_PAGES"):
		helpers = helpers.replace("uniform sampler2DArray contact_data", "uniform ivec2 contact_page_shift;\nuniform sampler2DArray contact_data")
		helpers = helpers.replace("index%page.x,(index/page.x)%page.y,first_layer+index/(page.x*page.y)",
			"index&(page.x-1),(index>>contact_page_shift.x)&(page.y-1),first_layer+(index>>contact_page_shift.y)")
	for name: String in FIELDS:
		var declaration := RegEx.create_from_string("uniform sampler2D " + name + "[^;]*;")
		code = declaration.sub(code, "", true)
		var dimensions := RegEx.create_from_string("textureSize\\(\\s*" + name + "\\s*,\\s*0\\s*\\)")
		code = dimensions.sub(code, "contact_" + name + "_size", true)
		var fetch := RegEx.create_from_string("texelFetch\\(\\s*" + name + "\\s*,\\s*")
		code = fetch.sub(code, "contact_" + name + "_texelFetch(", true)
		helpers += "uniform ivec2 contact_%s_size;\nuniform int contact_%s_layer;\n" % [name, name]
		helpers += "vec4 contact_%s_texelFetch(ivec2 p,int lod) { return contact_data_fetch(p,contact_%s_size,contact_%s_layer,lod); }\n" % [name, name, name]
	var lookup := RegEx.create_from_string("textureLod\\(\\s*terrain_cells\\s*,\\s*")
	code = lookup.sub(code, "contact_terrain_cells_textureLod(", true)
	helpers += "vec4 contact_terrain_cells_textureLod(vec2 uv,float lod) { return textureLod(contact_data,vec3(uv,float(contact_terrain_cells_layer)),lod); }\n"
	# Contact uses query_tracks; the terrain's sector-only sampler is unused.
	# GLES still assigns a unit to its declaration. Leave that unit available
	# for the native shadow texture, including rain and cloud-shadow variants.
	var begin := code.find("vec2 soft_sample(vec2 uv) {")
	var end := code.find("\n}", begin)
	assert(begin >= 0 and end > begin)
	code = code.erase(begin, end + 2 - begin)
	code = code.replace("uniform sampler2DArray soft_track_texture : filter_linear, repeat_disable;", "")
	return code.replace("shader_type spatial;", "shader_type spatial;\n" + helpers)
