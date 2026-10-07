extends Node
## Byte-exact comparison against the independent script decoder, including
## every 16-bit input, random masks, shipped assets and malformed lengths.
var checks := 0
var failures := 0
var kernel: RefCounted

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func same(data: PackedByteArray, w: int, h: int, label: String) -> void:
	var native: PackedByteArray = kernel.decode_raw(data, w, h)
	var reference := EIMmp._decode_raw_script(data, w, h)
	check(native.is_empty() if reference == null else native == reference.get_data(), label)

func header(w: int, h: int, bits: int, masks: Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(76 + w * h * (bits / 8))
	data.encode_u32(0, EIMmp.MAGIC)
	data.encode_u32(4, w); data.encode_u32(8, h); data.encode_u32(20, bits)
	for c in 4:
		for k in 3: data.encode_u32(24 + c * 12 + k * 4, masks[c][k])
	return data

func _ready() -> void:
	kernel = ClassDB.instantiate("MmpTextureKernel")
	var rng := RandomNumberGenerator.new()
	rng.seed = 941763
	for masks in [
		[[0,0,0],[0xf800,11,5],[0x7e0,5,6],[0x1f,0,5]],
		[[0x8000,15,1],[0x7c00,10,5],[0x3e0,5,5],[0x1f,0,5]],
		[[0xf000,12,4],[0xf00,8,4],[0xf0,4,4],[0xf,0,4]],
	]:
		var data := header(256, 256, 16, masks)
		for i in 65536: data.encode_u16(76 + i * 2, i)
		same(data, 256, 256, "all 16-bit pixels: %s" % str(masks))
	for trial in 200:
		var masks := []
		for c in 4:
			masks.append([rng.randi(), rng.randi_range(0,63), 0 if c == 0 and trial % 2 else 32])
		var data := header(19, 13, 32, masks)
		for i in 19 * 13: data.encode_u32(76 + i * 4, rng.randi())
		same(data, 19, 13, "random 32-bit masks %d" % trial)
	var good := header(2, 2, 32, [[0xff000000,24,8],[0xff0000,16,8],[0xff00,8,8],[0xff,0,8]])
	for size in [0, 20, 75, 76, good.size() - 1]:
		same(good.slice(0,size), 2, 2, "truncated data %d" % size)
	for dims in [Vector2i.ZERO,Vector2i(-1,2),Vector2i(2,-1),Vector2i(16385,1),Vector2i(16384,16384)]:
		same(good, dims.x, dims.y, "invalid dimensions %s" % dims)
	var malformed := good.duplicate()
	malformed.encode_u32(28,64)
	same(malformed,2,2,"invalid channel shift")
	malformed = good.duplicate(); malformed.encode_u32(20,24)
	same(malformed,2,2,"unsupported raw pixel width")
	# All shipped raw assets, including the spell atlases and HUD images that
	# first appeared during combat. No pixel or mipmap changes are permitted.
	var assets := 0
	var native_us := 0
	var script_us := 0
	for archive: EIResArchive in [GameData.textures, GameData.menus]:
		if archive == null: continue
		for name in archive.names_with_suffix(".mmp"):
			var data := archive.read(name)
			if data.size() < 76 or not data.decode_u32(20) in [16,32]: continue
			var tag := data.slice(16,20).get_string_from_ascii()
			if tag in ["DXT1","DXT3","PNT3"]: continue
			var w := data.decode_u32(4); var h := data.decode_u32(8)
			var started := Time.get_ticks_usec()
			var pixels: PackedByteArray = kernel.decode_raw(data,w,h)
			native_us += Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			var reference := EIMmp._decode_raw_script(data,w,h)
			script_us += Time.get_ticks_usec() - started
			check(reference != null and pixels == reference.get_data(), "asset " + name)
			assets += 1
	print("MMP_NATIVE ", JSON.stringify({"checks":checks,"failures":failures,"assets":assets,"native_us":native_us,"script_us":script_us}))
	get_tree().quit(1 if failures else 0)
