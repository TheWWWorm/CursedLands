extends "mod_profiles.gd"
## Texture packs can replace MMP entries with PNG images, and high-resolution
## clothing/armour keeps its resolution over an original-size skin.
## Run only with --mod-tests and a disposable profile.

func png(size: int, color: Color, transparent_top := false) -> PackedByteArray:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	if transparent_top:
		img.fill_rect(Rect2i(0, 0, size, size / 2), Color(0, 0, 0, 0))
	return img.save_png_to_buffer()

func finish() -> void:
	print("MOD_TEXTURE_PNG ", checks, " checks ", failures, " failures")
	TexUpscale.shutdown(); get_tree().quit(int(failures > 0))

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--mod-tests"): get_tree().quit(2); return
	var red := Color8(210, 25, 45, 255)
	var blue := Color8(20, 45, 220, 255)
	var green := Color8(30, 200, 60, 255)
	# Decoder and header probe, independent of the overlay.
	var sample := png(64, green)
	check(EIMmp.is_png(sample) and EIMmp.image_size(sample) == Vector2i(64, 64), "PNG header size is read")
	var decoded := EIMmp.decode(sample)
	check(decoded != null and decoded.get_size() == Vector2i(64, 64) and decoded.get_format() == Image.FORMAT_RGBA8 \
		and decoded.get_pixel(5, 5).is_equal_approx(green), "PNG bytes decode as an RGBA texture")
	var mipped := EIMmp.decode_texture(sample, true)
	check(mipped != null and mipped.has_mipmaps() and mipped.get_pixel(0, 0).is_equal_approx(green), "PNG texture path generates mipmaps")
	check(EIMmp.decode(sample.slice(0, 40)) == null, "truncated PNG is rejected without a texture")
	var huge := sample.duplicate()
	huge.encode_u32(16, 0x00000140)   # IHDR width 0x40010000 (big-endian), beyond the MMP bound
	check(EIMmp.decode(huge) == null, "oversized PNG header is rejected before decoding")
	var mmp := GameData.redress.read_original(GameData.redress.names_with_suffix(".mmp")[0])
	check(EIMmp.image_size(mmp) == Vector2i(mmp.decode_u32(4), mmp.decode_u32(8)) and not EIMmp.is_png(mmp), "original MMP headers keep their size")

	var proto := GameData.db.find("monster_prototypes", "Human Hero")
	var race := GameData.db.find("race_models", proto.base_race)
	var mask := String(race.mask).to_lower()
	var skin := "skin_%02d" % int(proto.get("skin", 0))
	var original_skin := EIMmp.decode(GameData.redress.read_original(mask + skin + ".mmp"))
	check(original_skin != null, "original hero skin decodes")
	if original_skin == null: return finish()
	var skin_size := original_skin.get_size()
	var big := skin_size.x * 4
	var world := GameData.textures.names_with_suffix(".mmp")[0].trim_suffix(".mmp")
	var m := manifest("png.fixture")
	m.api = 2; m.options = []
	m.overrides = [
		{"archive":"redress.res","entry":mask+"png-armour.mmp","file":"redress.res/png-armour.png"},
		{"archive":"redress.res","entry":mask+"png-skin.mmp","file":"redress.res/png-skin.png"},
		{"archive":"textures.res","entry":world+".mmp","file":"textures.res/world.png"}]
	check(ModSchema.manifest_error(m).is_empty(), "PNG replacement files are accepted for MMP entries")
	var assets := {"redress.res/png-armour.png":png(big, blue, true), "redress.res/png-skin.png":png(skin_size.x, red),
		"textures.res/world.png":png(128, green)}
	check(ModStore.import_package(pack(m, assets)).is_empty(), "PNG texture package imports")
	check(ModStore.create_profile("PNG texture test").is_empty(), "create isolated texture profile")
	check(ModStore.set_packages(["png.fixture@1.0"]).is_empty(), "select PNG package")
	DataSwitch.clear_caches()
	check(GameData.open(GameData.root).is_empty() and ModStore.startup_error.is_empty(), "normal loading mounts the PNG package")
	check(GameData.textures.read(world + ".mmp") == assets["textures.res/world.png"], "world texture reader returns the PNG replacement")
	var world_image := GameData.load_image(world)
	check(world_image != null and world_image.get_size() == Vector2i(128, 128) and world_image.get_pixel(3, 3).is_equal_approx(green), "world texture loads from PNG")
	var world_tex := GameData.get_texture(world, true)
	check(world_tex != null and world_tex.get_width() == 128, "authored-mip texture path accepts PNG")
	# High-resolution armour over the original skin: compose at the armour's size.
	var armoured := EIUnitModel._compose(mask, [skin, "png-armour"] as Array[String])
	check(armoured != null and armoured.get_size() == Vector2(big, big), "armour layer keeps its %dpx resolution over a %dpx skin" % [big, skin_size.x])
	if armoured:
		var img := armoured.get_image()
		check(img.get_pixel(big / 2, big - 2).is_equal_approx(blue), "opaque armour pixels are drawn at full resolution")
		var expected := original_skin.duplicate() as Image
		expected.resize(big, big, Image.INTERPOLATE_BILINEAR)
		check(img.get_pixel(big / 2, 8).is_equal_approx(expected.get_pixel(big / 2, 8)), "the original skin is enlarged under transparent armour")
	var surface := EIUnitModel._compose_surface(mask, [skin, "png-armour"] as Array[String], [SurfaceMaterials.DULL, SurfaceMaterials.DULL])
	check(surface != null and surface.get_size() == Vector2(big, big), "surface response map matches the armour resolution")
	# A smaller overlay is enlarged to the skin, as before.
	var small := EIUnitModel._compose(mask, ["png-skin", "png-armour"] as Array[String])
	check(small != null and small.get_size() == Vector2(big, big) and small.get_image().get_pixel(4, 4).is_equal_approx(red), "PNG skin composes under PNG armour")
	var plain := EIUnitModel._compose(mask, [skin] as Array[String])
	check(plain != null and plain.get_size() == Vector2(skin_size), "an unmodded skin keeps its original size")
	check(ModStore.select_profile("default").is_empty(), "disable PNG package")
	DataSwitch.clear_caches()
	check(GameData.open(GameData.root).is_empty(), "reload unmodded data")
	check(not GameData.redress.has(mask + "png-armour.mmp") and GameData.textures.read(world + ".mmp") == GameData.textures.read_original(world + ".mmp"), "disabling restores original textures")
	finish()
