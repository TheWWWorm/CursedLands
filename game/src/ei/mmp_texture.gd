class_name EIMmp
extends RefCounted
## Decoder for Evil Islands ".mmp" textures.
## Images are returned in D3D memory order (row 0 = V 0), which matches
## Godot's UV convention, so model UVs from .fig files can be used as-is.

const MAGIC := 0x00504D4D  # "MMP\0"
const DATA_OFFSET := 76
static var _raw_kernel: RefCounted = ClassDB.instantiate("MmpTextureKernel") \
	if ClassDB.class_exists("MmpTextureKernel") and not OS.get_cmdline_user_args().has("--ei-script-textures") else null


static func decode(data: PackedByteArray) -> Image:
	if data.size() < DATA_OFFSET or data.decode_u32(0) != MAGIC:
		return null
	var w := data.decode_u32(4)
	var h := data.decode_u32(8)
	var size_field := data.decode_u32(12)
	var tag := data.slice(16, 20)
	var img: Image
	if tag == "DXT1".to_ascii_buffer():
		img = Image.create_from_data(w, h, false, Image.FORMAT_DXT1,
				data.slice(DATA_OFFSET, DATA_OFFSET + w * h / 2))
		img.decompress()
	elif tag == "DXT3".to_ascii_buffer():
		img = Image.create_from_data(w, h, false, Image.FORMAT_DXT3,
				data.slice(DATA_OFFSET, DATA_OFFSET + w * h))
		img.decompress()
	elif tag == "PNT3".to_ascii_buffer():
		img = _decode_pnt3(data, size_field, w, h)
	else:
		img = _decode_raw(data, w, h)
		# 8888 textures are stored bottom-up, unlike every other format.
		if img and tag == PackedByteArray([0x88, 0x88, 0, 0]):
			img.flip_y()
	if img and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Image for an unchanged world texture. Preserve authored DXT levels, then
## complete only the missing tail for Godot's full-chain Image layout.
## CPU image callers continue to use decode(); HD/redress images need their
## own generated mipmaps after editing.
static func decode_texture(data: PackedByteArray, allow_compressed: bool) -> Image:
	if data.size() < DATA_OFFSET or data.decode_u32(0) != MAGIC:
		return null
	var tag := data.slice(16, 20)
	if tag != "DXT1".to_ascii_buffer() and tag != "DXT3".to_ascii_buffer():
		var image := decode(data)
		if image:
			image.generate_mipmaps()
		return image
	var width := data.decode_u32(4)
	var height := data.decode_u32(8)
	if width <= 0 or height <= 0 or width > 16384 or height > 16384 or width * height > 64 * 1024 * 1024:
		return null
	var format := Image.FORMAT_DXT1 if tag == "DXT1".to_ascii_buffer() else Image.FORMAT_DXT3
	var block_bytes := 8 if format == Image.FORMAT_DXT1 else 16
	if data.decode_u32(20) != (4 if block_bytes == 8 else 8):
		return null
	var complete_levels := 1
	var w := width
	var h := height
	while w > 1 or h > 1:
		w = maxi(1, w >> 1)
		h = maxi(1, h >> 1)
		complete_levels += 1
	var count := data.decode_u32(12)
	if count < 1 or count > complete_levels:
		return null
	var levels: Array[Vector4i] = []
	var offset := DATA_OFFSET
	w = width
	h = height
	for i in count:
		var bytes := ((w + 3) >> 2) * ((h + 3) >> 2) * block_bytes
		if bytes > data.size() - offset:
			return null
		levels.append(Vector4i(offset, bytes, w, h))
		offset += bytes
		w = maxi(1, w >> 1)
		h = maxi(1, h >> 1)
	# Godot uploads FORMAT_DXT1 as RGB on both GL and RenderingDevice.
	# Original MMPs also use BC1's transparent index. Inspect every authored
	# level: a solid final mip does not mean the larger levels are opaque.
	if allow_compressed and format == Image.FORMAT_DXT1:
		for block in range(DATA_OFFSET, offset, 8):
			if data.decode_u16(block) <= data.decode_u16(block + 2):
				var indices := data.decode_u32(block + 4)
				if indices & (indices >> 1) & 0x55555555:
					allow_compressed = false
					break
	var payload := data.slice(DATA_OFFSET, offset)
	var tail: Image
	if count < complete_levels:
		var last := levels[-1]
		var image := Image.create_from_data(last.z, last.w, false, format, data.slice(last.x, last.x + last.y))
		if image.decompress() != OK:
			return null
		image.convert(Image.FORMAT_RGBA8)
		image.generate_mipmaps()
		tail = Image.create_from_data(w, h, complete_levels - count > 1, Image.FORMAT_RGBA8,
				image.get_data().slice(image.get_mipmap_offset(1)))
		# Image.compress(S3TC) needs editor-only modules. Encode just tiny
		# opaque BC1 tails here so exported games get the same result. Bound
		# script work; large missing chains and BC2 tails use RGBA instead.
		if allow_compressed and format == Image.FORMAT_DXT1 and maxi(last.z, last.w) <= 32:
			payload.append_array(_pack_bc1_tail(tail))
			return Image.create_from_data(width, height, true, format, payload)
	elif allow_compressed:
		return Image.create_from_data(width, height, count > 1, format, payload)

	# Unsupported S3TC, BC1 transparency, or an ineligible tail: retain
	# authored mip pixels in RGBA plus the same generated tail.
	var pixels := PackedByteArray()
	for level in levels:
		var image := Image.create_from_data(level.z, level.w, false, format, data.slice(level.x, level.x + level.y))
		if image.decompress() != OK:
			return null
		image.convert(Image.FORMAT_RGBA8)
		pixels.append_array(image.get_data())
	if tail:
		pixels.append_array(tail.get_data())
	return Image.create_from_data(width, height, complete_levels > 1, Image.FORMAT_RGBA8, pixels)


## Bounded encoder for generated opaque tails (at most 16x16 + lower mips).
## Fit each block along its most distant color pair, quantize RGB565, then
## choose the closest palette entry. Never re-encode an authored block.
static func _pack_bc1_tail(image: Image) -> PackedByteArray:
	var pixels := image.get_data()
	var packed := PackedByteArray()
	var width := image.get_width()
	var height := image.get_height()
	for level in image.get_mipmap_count() + 1:
		var start := image.get_mipmap_offset(level)
		for y in range(0, height, 4):
			for x in range(0, width, 4):
				var colors: Array[Vector3] = []
				for row in 4:
					for col in 4:
						var p := start + (mini(y + row, height - 1) * width + mini(x + col, width - 1)) * 4
						colors.append(Vector3(pixels[p], pixels[p + 1], pixels[p + 2]))
				var a := colors[0]
				var b := a
				var distance := 0.0
				for i in 16:
					for j in i:
						var d := colors[i].distance_squared_to(colors[j])
						if d > distance:
							distance = d
							a = colors[i]
							b = colors[j]
				var c0 := _rgb565(a)
				var c1 := _rgb565(b)
				var high := maxi(c0, c1)
				var low := mini(c0, c1)
				a = _rgb565_color(high)
				b = _rgb565_color(low)
				var palette := [a, b, (a * 2.0 + b) / 3.0, (a + b * 2.0) / 3.0]
				var indices := 0
				for i in 16:
					var chosen := 0
					var closest := INF
					for j in 4:
						var d := colors[i].distance_squared_to(palette[j])
						if d < closest:
							closest = d
							chosen = j
					indices |= chosen << (i * 2)
				var offset := packed.size()
				packed.resize(offset + 8)
				packed.encode_u16(offset, high)
				packed.encode_u16(offset + 2, low)
				packed.encode_u32(offset + 4, indices)
		width = maxi(1, width >> 1)
		height = maxi(1, height >> 1)
	return packed


static func _rgb565(color: Vector3) -> int:
	return (roundi(color.x * 31.0 / 255.0) << 11) | (roundi(color.y * 63.0 / 255.0) << 5) | roundi(color.z * 31.0 / 255.0)


static func _rgb565_color(color: int) -> Vector3:
	return Vector3(roundf(((color >> 11) & 31) * 255.0 / 31.0),
			roundf(((color >> 5) & 63) * 255.0 / 63.0), roundf((color & 31) * 255.0 / 31.0))


static func _decode_pnt3(data: PackedByteArray, size: int, w: int, h: int) -> Image:
	# Simple RLE: a dword with non-zero alpha is a BGRA pixel, otherwise it
	# is a count of zero bytes to emit.
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var dst := 0
	var src := DATA_OFFSET
	var end := mini(DATA_OFFSET + size, data.size())
	while src + 4 <= end and dst < out.size():
		if data[src + 3] != 0:
			out[dst] = data[src + 2]
			out[dst + 1] = data[src + 1]
			out[dst + 2] = data[src]
			out[dst + 3] = data[src + 3]
			dst += 4
		else:
			var v := data.decode_u32(src)
			dst += v if v != 0 else 4  # buffer is already zero-filled
		src += 4
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


static func _decode_raw(data: PackedByteArray, w: int, h: int) -> Image:
	if _raw_kernel:
		var rgba: PackedByteArray = _raw_kernel.decode_raw(data, w, h)
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba) if not rgba.is_empty() else null
	return _decode_raw_script(data, w, h)


## Independent reference and fallback on platforms without the extension.
static func _decode_raw_script(data: PackedByteArray, w: int, h: int) -> Image:
	if data.size() < DATA_OFFSET or w <= 0 or h <= 0 or w > 16384 or h > 16384 or w * h > 64 * 1024 * 1024:
		return null
	if not data.decode_u32(20) in [16, 32] or w * h * (data.decode_u32(20) / 8) > data.size() - DATA_OFFSET:
		return null
	var bpp := data.decode_u32(20) / 8
	var masks: Array[PackedInt64Array] = []
	for c in 4:  # a, r, g, b: (mask, shift, bit count)
		var p := 24 + c * 12
		if data.decode_u32(p + 4) >= 64:
			return null
		masks.append(PackedInt64Array([data.decode_u32(p), data.decode_u32(p + 4), data.decode_u32(p + 8)]))
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var src := DATA_OFFSET
	for i in w * h:
		var px: int = data.decode_u16(src) if bpp == 2 else data.decode_u32(src)
		src += bpp
		for c in 4:
			var m := masks[c]
			var v := 255
			if c != 0 or m[2] != 0:
				var full := m[0] >> m[1]
				v = int(0.5 + 255.0 * ((px & m[0]) >> m[1]) / full) if full else 0
			# a,r,g,b -> r,g,b,a
			out[i * 4 + (c + 3) % 4] = v
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
