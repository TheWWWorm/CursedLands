extends Node
## Compare byte coloring and full material compositing with the scalar fallback.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func _ready() -> void:
	var kernel := SurfaceMaterials._color_kernel
	check(kernel != null and kernel.has_method("colorize_rgba"), "native coloring available")
	if failures: get_tree().quit(1); return
	var bytes := PackedByteArray()
	for alpha in 256: bytes.append_array(PackedByteArray([alpha, 255-alpha, alpha/2, alpha]))
	var original := bytes.duplicate()
	for color in [Vector3i.ZERO, Vector3i(255,255,255), Vector3i(13,245,0), Vector3i(242,102,217), Vector3i(-1,256,511)]:
		var colored: PackedByteArray = kernel.colorize_rgba(bytes,color.x,color.y,color.z)
		check(bytes == original, "immutable source")
		for pixel in 256:
			check(colored[pixel*4+3] == pixel, "exact alpha")
			for channel in 3: check(colored[pixel*4+channel] == (color[channel]&255), "exact RGB")
	check(kernel.colorize_rgba(PackedByteArray(),0,0,0).is_empty(), "empty input")
	check(kernel.colorize_rgba(PackedByteArray([1,2,3]),0,0,0).is_empty(), "incomplete RGBA rejected")
	for format in [Image.FORMAT_RGBA8, Image.FORMAT_RGB8, Image.FORMAT_DXT3]:
		var layer := Image.create_from_data(16,16,false,Image.FORMAT_RGBA8,bytes)
		if format == Image.FORMAT_DXT3:
			var blocks := PackedByteArray(); blocks.resize(256); blocks.fill(0x5a)
			layer = Image.create_from_data(16,16,false,format,blocks)
		else:
			layer.convert(format); layer.generate_mipmaps()
		var unmodified := layer.get_data()
		for size in [Vector2i(16,16), Vector2i(32,24), Vector2i(8,8)]:
			for material in ["metal","leather","hide","bone","stone","crystal","cloth","fur",""]:
				var profile := SurfaceMaterials.equipment({"type":material})
				var candidate := Image.create_empty(size.x,size.y,false,Image.FORMAT_RGBA8)
				candidate.fill(Color(0.08,0.92,0,1))
				var reference := candidate.duplicate() as Image
				SurfaceMaterials._color_kernel = kernel
				SurfaceMaterials.blend_layer(candidate,layer,profile)
				SurfaceMaterials._color_kernel = null
				SurfaceMaterials.blend_layer(reference,layer,profile)
				check(candidate.get_data() == reference.get_data(), "exact composite "+material+str(size))
				check(layer.get_data() == unmodified, "immutable source image and mips")
	SurfaceMaterials._color_kernel = kernel
	print("SURFACE_MATERIAL_COLOR ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
