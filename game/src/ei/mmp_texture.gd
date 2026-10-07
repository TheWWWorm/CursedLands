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
