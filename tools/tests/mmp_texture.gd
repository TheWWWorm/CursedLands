extends Node
## Validate authored mip payloads independently of backend support, including
## real MMPs whose chains end before Godot's required 1x1 level.
var checks := 0
var failures := 0
var assets := 0
var compressed_assets := 0
var payload_bytes := 0
var rgba_bytes := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func fixture(width: int, height: int, count: int, dxt3 := false, transparent := false) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(76)
	data.encode_u32(0, EIMmp.MAGIC)
	data.encode_u32(4, width)
	data.encode_u32(8, height)
	data.encode_u32(12, count)
	data.encode_u32(16, 0x33545844 if dxt3 else 0x31545844)
	data.encode_u32(20, 8 if dxt3 else 4)
	var colors := [0xf800, 0x07e0, 0x001f, 0xffff, 0x7bef]
	var w := width
	var h := height
	for level in count:
		var block := PackedByteArray()
		block.resize(16 if dxt3 else 8)
		var offset := 8 if dxt3 else 0
		if dxt3:
			for i in 8:
				block[i] = 0x5a if transparent else 0xff
		block.encode_u16(offset, 0 if transparent and not dxt3 else colors[level % colors.size()])
		block.encode_u16(offset + 2, 0xffff if transparent and not dxt3 else 0)
		block.encode_u32(offset + 4, 0xffffffff if transparent and not dxt3 else 0)
		for i in ((w + 3) >> 2) * ((h + 3) >> 2):
			data.append_array(block)
		w = maxi(1, w >> 1)
		h = maxi(1, h >> 1)
	return data

func authored_bytes(data: PackedByteArray) -> int:
	var width := data.decode_u32(4)
	var height := data.decode_u32(8)
	var size := 0
	var block := 8 if data.decode_u32(16) == 0x31545844 else 16
	for level in data.decode_u32(12):
		size += ((width + 3) >> 2) * ((height + 3) >> 2) * block
		width = maxi(1, width >> 1)
		height = maxi(1, height >> 1)
	return size

func check_pixels(image: Image, data: PackedByteArray, label: String) -> void:
	if image == null:
		return
	var decoded := image.duplicate() as Image
	if decoded.is_compressed():
		check(decoded.decompress() == OK, label + ": decompress output")
	decoded.convert(Image.FORMAT_RGBA8)
	var pixels := decoded.get_data()
	var format := Image.FORMAT_DXT1 if data.decode_u32(16) == 0x31545844 else Image.FORMAT_DXT3
	var block := 8 if format == Image.FORMAT_DXT1 else 16
	var width := data.decode_u32(4)
	var height := data.decode_u32(8)
	var offset := 76
	var levels := 0
	var full_width := width
	var full_height := height
	while full_width > 1 or full_height > 1:
		full_width = maxi(1, full_width >> 1)
		full_height = maxi(1, full_height >> 1)
		levels += 1
	check(image.get_mipmap_count() == levels, label + ": full mip count")
	for level in data.decode_u32(12):
		var bytes := ((width + 3) >> 2) * ((height + 3) >> 2) * block
		var reference := Image.create_from_data(width, height, false, format, data.slice(offset, offset + bytes))
		reference.decompress()
		reference.convert(Image.FORMAT_RGBA8)
		var start := decoded.get_mipmap_offset(level)
		check(pixels.slice(start, start + width * height * 4) == reference.get_data(),
				label + ": authored pixels at level " + str(level))
		offset += bytes
		width = maxi(1, width >> 1)
		height = maxi(1, height >> 1)

func check_fixture(data: PackedByteArray, label: String) -> void:
	var original := data.duplicate()
	for supported in [false, true]:
		var image := EIMmp.decode_texture(data, supported)
		check(image != null, label + ": decoded")
		if image == null:
			continue
		check_pixels(image, data, label)
		if not supported:
			check(image.get_format() == Image.FORMAT_RGBA8, label + ": unsupported S3TC uses RGBA")
		if image.is_compressed():
			check(image.get_data().slice(0, authored_bytes(data)) == data.slice(76, 76 + authored_bytes(data)),
					label + ": exact compressed prefix")
	check(data == original, label + ": immutable input")

func test_fixtures() -> void:
	check_fixture(fixture(8, 8, 2), "partial BC1")
	check_fixture(fixture(8, 8, 4), "complete BC1")
	check_fixture(fixture(8, 4, 2), "rectangular BC1")
	check_fixture(fixture(4, 4, 1), "one authored level")
	check_fixture(fixture(1, 1, 1), "one texel")
	check_fixture(fixture(8, 8, 2, false, true), "BC1 transparent tail")
	check_fixture(fixture(8, 8, 4, false, true), "complete transparent BC1")
	check_fixture(fixture(8, 8, 2, true, true), "BC2 transparent tail")
	check_fixture(fixture(8, 8, 4, true, true), "complete BC2")
	var alpha_base := fixture(8, 8, 2, false, true)
	var opaque := fixture(8, 8, 2)
	for i in 8:
		alpha_base[alpha_base.size() - 8 + i] = opaque[opaque.size() - 8 + i]
	check_fixture(alpha_base, "BC1 transparency only above opaque tail")
	check(EIMmp.decode_texture(alpha_base, true).get_format() == Image.FORMAT_RGBA8,
			"BC1 transparency anywhere in the chain requires RGBA")
	check(EIMmp.decode_texture(fixture(8, 8, 4, false, true), true).get_format() == Image.FORMAT_RGBA8,
			"complete BC1 chain cannot lose transparency on upload")
	check(EIMmp.decode_texture(fixture(128, 128, 1), true).get_format() == Image.FORMAT_RGBA8,
			"large missing mip chain bounds script encoding work with RGBA fallback")
	var partial := fixture(8, 8, 2)
	for size in [0, 75, 76, partial.size() - 1]:
		check(EIMmp.decode_texture(partial.slice(0, size), true) == null, "truncated " + str(size))
	for entry in [[4, 0], [8, 0], [4, 16385], [12, 0], [12, 5], [20, 32]]:
		var malformed := partial.duplicate()
		malformed.encode_u32(entry[0], entry[1])
		check(EIMmp.decode_texture(malformed, true) == null, "invalid header " + str(entry))

func test_generated_tail() -> void:
	# Four collinear colors in separate authored 4x4 blocks. Their lower
	# mips fit BC1's palette; check texel placement, quantization and alpha,
	# including padded 2x2/1x1 blocks, without an editor-only compressor.
	var data := fixture(8, 8, 1)
	var colors := [0, 0x528a, 0xad55, 0xffff]
	for i in 4:
		data.encode_u16(76 + i * 8, colors[i])
	var candidate := EIMmp.decode_texture(data, true)
	check(candidate != null and candidate.get_format() == Image.FORMAT_DXT1,
			"generated tail remains compressed in runtime builds")
	if candidate == null:
		return
	check(candidate.get_data().slice(0, 32) == data.slice(76, 108), "tail encoder never changes authored blocks")
	var reference := EIMmp.decode_texture(data, false)
	candidate.decompress()
	var actual := candidate.get_data()
	var expected := reference.get_data()
	for level in range(1, candidate.get_mipmap_count() + 1):
		var start := candidate.get_mipmap_offset(level)
		var end := candidate.get_mipmap_offset(level + 1) if level < candidate.get_mipmap_count() else actual.size()
		var max_error := 0
		var opaque := true
		for p in range(start, end, 4):
			for c in 3:
				max_error = maxi(max_error, absi(actual[p + c] - expected[p + c]))
			opaque = opaque and actual[p + 3] == 255
		check(max_error <= 4, "generated gray tail within RGB565 quantization: " + str(level))
		check(opaque, "generated tail stays opaque: " + str(level))

func test_assets() -> void:
	for file: String in GameData.textures.names_with_suffix(".mmp"):
		var data := GameData.textures.read(file)
		if data.size() < 76 or data.decode_u32(16) not in [0x31545844, 0x33545844]:
			continue
		var image := EIMmp.decode_texture(data, true)
		check(image != null, "asset decoded: " + file)
		if image == null:
			continue
		check_pixels(image, data, file)
		if image.is_compressed():
			compressed_assets += 1
			check(image.get_data().slice(0, authored_bytes(data)) == data.slice(76, 76 + authored_bytes(data)),
					"authored blocks preserved: " + file)
		payload_bytes += image.get_data_size()
		var width := image.get_width()
		var height := image.get_height()
		while true:
			rgba_bytes += width * height * 4
			if width == 1 and height == 1:
				break
			width = maxi(1, width >> 1)
			height = maxi(1, height >> 1)
		assets += 1
	check(assets > 100, "shipped compressed texture corpus exercised")

func test_production_entry() -> void:
	var previous := GameData.option("gfx_hd_textures")
	GameData.options["gfx_hd_textures"] = 0
	var texture := Gfx.texture_3d("govenorhouse00") as ImageTexture
	var ui := GameData.get_texture("govenorhouse00") as ImageTexture
	check(texture != null and ui != null, "world and existing UI path both load")
	if texture and ui:
		check(texture != ui, "authored and generated mip caches are distinct")
		check(ui.get_format() == Image.FORMAT_RGBA8, "UI/CPU path unchanged")
		check(texture.get_format() == (Image.FORMAT_DXT1 if RenderingServer.has_os_feature("s3tc") else Image.FORMAT_RGBA8),
				"world path obeys actual backend capability")
		check(Gfx.texture_3d("GOVENORHOUSE00") == texture, "world cache remains case-insensitive")
	GameData.options["gfx_hd_textures"] = previous

func _ready() -> void:
	test_fixtures()
	test_generated_tail()
	test_assets()
	test_production_entry()
	print("MMP_TEXTURE ", JSON.stringify({"checks": checks, "failures": failures, "assets": assets,
			"compressed_assets": compressed_assets, "payload_bytes": payload_bytes, "rgba_bytes": rgba_bytes,
			"s3tc": RenderingServer.has_os_feature("s3tc"), "editor": OS.has_feature("editor")}))
	get_tree().quit(1 if failures else 0)
