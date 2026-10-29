class_name SurfaceMaterials
extends RefCounted
## Remake surface response from the original assets. Equipment uses the
## database's material type and the exact redress alpha, never albedo brightness.
## The small foliage masks are made from identified regions of the shipped
## atlases: bark, branches and snow must not become translucent leaves.

const SKIN := Vector3(0.08, 0.92, 0.0)
const DULL := Vector3(0.04, 0.96, 0.0)
static var _color_kernel: RefCounted = ClassDB.instantiate("MmpTextureKernel") \
	if ClassDB.class_exists("MmpTextureKernel") and not OS.get_cmdline_user_args().has("--ei-script-textures") else null

## Screen derivatives construct a tangent frame for EI meshes, which have no
## tangent stream. Local texture differences add shallow relief only; distance,
## minification and a hard slope bound suppress painted shadows and shimmer.
const RELIEF_SHADER := """
#ifndef EI_NO_MATERIALS
vec3 ei_relief_normal(sampler2D tex, vec2 uv, vec3 p, vec3 n, float strength) {
	vec2 size = vec2(textureSize(tex, 0));
	vec2 dx = dFdx(uv) * size;
	vec2 dy = dFdy(uv) * size;
	float visible_detail = 1.0 - smoothstep(1.2, 4.0, max(length(dx), length(dy)));
	visible_detail *= 1.0 - smoothstep(14.0, 40.0, length(p));
	// Take derivatives before the distance/minification branch. Explicit
	// gradients retain the same texture footprint at its quad boundary.
	vec3 dpdx = dFdx(p);
	vec3 dpdy = dFdy(p);
	vec2 duvdx = dFdx(uv);
	vec2 duvdy = dFdy(uv);
	if (visible_detail <= 0.0) { return normalize(n); }
	vec2 px = 1.0 / size;
	vec3 lum = vec3(0.2126, 0.7152, 0.0722);
	float left = dot(textureGrad(tex, uv - vec2(px.x, 0.0), duvdx, duvdy).rgb, lum);
	float right = dot(textureGrad(tex, uv + vec2(px.x, 0.0), duvdx, duvdy).rgb, lum);
	float above = dot(textureGrad(tex, uv - vec2(0.0, px.y), duvdx, duvdy).rgb, lum);
	float below = dot(textureGrad(tex, uv + vec2(0.0, px.y), duvdx, duvdy).rgb, lum);
	vec2 slope = clamp(vec2(right - left, below - above) * 2.0, vec2(-0.12), vec2(0.12));
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	vec3 u = r1 * duvdx.x + r2 * duvdy.x;
	vec3 v = r1 * duvdx.y + r2 * duvdy.y;
	float scale = inversesqrt(max(max(dot(u, u), dot(v, v)), 1e-12));
	return normalize(n - (u * slope.x + v * slope.y) * scale * strength * visible_detail);
}
#endif
"""


static func equipment(material: Dictionary) -> Vector3:
	match String(material.get("type", "")).to_lower():
		"metal": return Vector3(0.95, 0.40, 0.85)
		"leather": return Vector3(0.24, 0.76, 0.0)
		"hide": return Vector3(0.22, 0.73, 0.0)
		"bone": return Vector3(0.27, 0.72, 0.0)
		"stone": return Vector3(0.19, 0.84, 0.0)
		"crystal": return Vector3(0.58, 0.32, 0.0)
		"cloth": return Vector3(0.05, 0.96, 0.0)
		"fur": return Vector3(0.03, 0.98, 0.0)
	return DULL


## Object surface families. Names cover both the base game and Lost in
## Astral archives (the expansion ships every base atlas unchanged and adds
## its own Jigran, Haburu and autumn artwork). xyz = highlight, roughness,
## metalness; w = shallow relief strength from the colour atlas.
const STONE := Vector4(0.20, 0.84, 0.0, 0.70)      # verified uniform rock/ruin atlases
const MASONRY := Vector4(0.20, 0.84, 0.0, 0.45)    # walls, gates, towers, domes, bridges
const PLASTER := Vector4(0.18, 0.86, 0.0, 0.30)    # houses mixing plaster, wood and windows
const WOOD := Vector4(0.16, 0.86, 0.0, 0.45)       # verified plank/log atlases
const TIMBER := Vector4(0.16, 0.86, 0.0, 0.30)     # mixed wooden houses, fences, furniture
const IRON := Vector4(0.90, 0.42, 0.85, 0.0)       # painted iron braziers and fittings
const GOLD := Vector4(0.95, 0.36, 0.90, 0.0)
const CLAY := Vector4(0.10, 0.80, 0.0, 0.0)
const BONE := Vector4(0.27, 0.72, 0.0, 0.0)
const LEATHER := Vector4(0.24, 0.76, 0.0, 0.0)
const CLOTH := Vector4(0.04, 0.96, 0.0, 0.0)
const OBJECT_FAMILIES := {
	# Verified rock and ruin atlases: full relief (prefixes below).
	"ruins00": STONE, "kanianruins00": STONE, "crypt00": STONE, "fence00": STONE,
	# Verified plank atlases.
	"bridge00": WOOD, "orcbridge00": WOOD, "suspensionbridge00": WOOD, "ladder00": WOOD,
	"barrel00": WOOD, "box00": WOOD, "fence02": WOOD, "stocks00": WOOD,
	# Masonry: Hadagan, Kanian and Dgun stonework, cave doors and mine fittings.
	"hadoganwall00": MASONRY, "hadoganwall01": MASONRY, "hadoganwall02": MASONRY,
	"hadogangates00": MASONRY, "hadoganbridge00": MASONRY, "hadoganstatues00": MASONRY,
	"kaniangate00": MASONRY, "kanianwalls00": MASONRY, "kaniantower00": MASONRY,
	"kanianbridge00": MASONRY, "dome00": MASONRY, "crypt01": MASONRY,
	"dguntorch00": MASONRY, "dguntorchruins01": MASONRY, "dgunbirdruins00": MASONRY,
	"dgunface02": MASONRY, "cavedoor00": MASONRY, "cavedoor01": MASONRY, "kanianwalls01": MASONRY,
	"dgungate00": MASONRY, "dgundragon00": MASONRY, "dgundragon01": MASONRY, "warriorstatue00": MASONRY,
	"podiums00": MASONRY, "teleport00": MASONRY,
	# Houses and workshops mixing plaster or stone with wood.
	"hadoganhouse00": PLASTER, "hadoganveranda00": PLASTER, "hadoganprison00": PLASTER,
	"sortir00": PLASTER, "minedetails00": PLASTER, "minecontrol00": PLASTER,
	"cavelevel00": PLASTER, "kanianarc00": PLASTER, "kanianarc01": PLASTER, "vivary00": PLASTER,
	# Wooden buildings, fences, furniture and carts.
	"kanianhouse00": TIMBER, "kanianhousedetails00": TIMBER, "mine00": TIMBER,
	"driadfence00": TIMBER, "strongfence00": TIMBER, "fence03": TIMBER, "cart00": TIMBER,
	"kanianfurniture00": TIMBER, "torchbase00": TIMBER, "almaz00": TIMBER, "necrotable00": TIMBER,
	# Iron braziers and gold.
	"torch00": IRON, "potfire00": IRON, "goldpile00": GOLD, "goldpile01": GOLD, "goldchest00": GOLD,
	# Clay, bone and cloth props keep a dull dielectric response. Several are
	# marked stone or wood in their figure records.
	"jug00": CLAY, "jug01": CLAY, "jug02": CLAY, "jug03": CLAY,
	"skeleton00": BONE, "jskeleton00": BONE, "deadscientist00": CLOTH,
	"runnerstent00": CLOTH, "runnerstent01": CLOTH, "runnerstent02": CLOTH, "runnerstent03": CLOTH,
	"paneltent00": CLOTH, "tent00": CLOTH, "tent02": CLOTH, "tent04": CLOTH, "tipy00": CLOTH,
	"armytent00": CLOTH, "shoppertent00": CLOTH, "flyerfurniture00": CLOTH,
	"carpet00": CLOTH, "carpet01": CLOTH, "carpet02": CLOTH, "carpet03": CLOTH, "redcarpet00": CLOTH,
	"moneysack00": CLOTH, "squirrelskin00": CLOTH, "basket01": CLOTH, "basket02": CLOTH,
	"campfire00": CLOTH, "ambush00": CLOTH, "ogrhouse00": CLOTH, "goblinhouse00": CLOTH,
	"goblinhouse01": CLOTH, "driadidol00": CLOTH, "fake00": CLOTH,
	# Lost in Astral: Jigran and Haburu stonework, plaster houses and timber.
	"jigranwall00": MASONRY, "jigranwall01": MASONRY, "jigranwall02": MASONRY,
	"jigranwall03": MASONRY, "jigranwall04": MASONRY, "jigrantower00": MASONRY,
	"jigrantower01": MASONRY, "jigrantower02": MASONRY, "jigrantower03": MASONRY,
	"jigrantower04": MASONRY, "jyardwall00": MASONRY, "jcrypt00": MASONRY, "jlion00": MASONRY,
	"jkstatue": MASONRY, "teleport01": MASONRY, "teleport02": MASONRY, "teleport03": MASONRY,
	"golem00": MASONRY, "golem01": MASONRY,
	"jigranhouse00": PLASTER, "jigranhouse00b": PLASTER, "jigranhouse01": PLASTER,
	"jigranhouse01b": PLASTER, "jigranhouse02": PLASTER, "jigranhouse02b": PLASTER,
	"jigranhousebig00": PLASTER, "jigranhousebig01": PLASTER, "jigranbridge00": PLASTER,
	"jigranbridge01": PLASTER, "jigranshipyard00": PLASTER, "jigranshipyard01": PLASTER,
	"jhhouse00": PLASTER, "jdekhouse00": PLASTER, "jvhouse00": PLASTER, "jvhouse01": PLASTER,
	"jhwall00": TIMBER, "jhgates00": TIMBER,
	"jigranprops00": CLOTH, "jigranprops01": CLOTH, "jfield": CLOTH, "jhvivary00": CLOTH,
}
## Figure records (materials.res, read by EIFigureMaterial) classify every
## part the original artists tagged: stone, metal, wood, leather, cloth, skin.
## They refine atlases without a listed family. Relief stays off for them:
## a record does not say whether the painted colour carries usable height.
const RECORD_FAMILIES := {
	17: LEATHER, 18: Vector4(0.16, 0.86, 0.0, 0.0), 19: IRON, 20: CLOTH,
	22: Vector4(0.20, 0.84, 0.0, 0.0), 25: IRON,
}
const METAL_RECORDS := [19, 25]


## The surface family of an object texture and, optionally, of the figure
## part's original material record. A part the artists marked metal keeps a
## metal response inside a listed wooden or masonry atlas (torch holders,
## armour on fallen warriors). Unlisted names fall back to the record.
static func object_profile(texture: String, material_id := 0) -> Vector4:
	var name := texture.to_lower().trim_suffix(".mmp")
	if name.begins_with("stone") or name.begins_with("columnruins"):
		return STONE
	var family: Variant = OBJECT_FAMILIES.get(name)
	if material_id in METAL_RECORDS and (family == null or family.z < 0.5):
		return IRON
	if family != null:
		return family
	return RECORD_FAMILIES.get(material_id, Vector4(DULL.x, DULL.y, DULL.z, 0.0))


static var _object_surfaces := {}
## The Hadagan atlas is shared with a jug and an oven. These authored pixel
## regions belong to the chest's metal lid and frame; its wood and the other
## objects remain rough dielectrics. Coordinates refer to the original 256²
## atlas, independently of optional albedo upscaling.
static func object_surface(texture: String) -> Texture2D:
	var name := texture.to_lower().trim_suffix(".mmp")
	if name != "hadoganchest00": return null
	if _object_surfaces.has(name): return _object_surfaces[name]
	var image := Image.create(256,256,false,Image.FORMAT_RGB8)
	image.fill(Color(DULL.x,DULL.y,DULL.z))
	var regions := [
		PackedVector2Array([Vector2(67,102),Vector2(77,86),Vector2(133,86),Vector2(144,99),Vector2(141,184),Vector2(67,184)]),
		PackedVector2Array([Vector2(143,101),Vector2(163,101),Vector2(163,162),Vector2(151,180),Vector2(143,180)]),
		PackedVector2Array([Vector2(235,83),Vector2(256,83),Vector2(256,181),Vector2(235,181)]),
		PackedVector2Array([Vector2(162,164),Vector2(235,164),Vector2(235,183),Vector2(162,183)])]
	var metal := equipment({"type":"metal"})
	for y in 256:
		for x in 256:
			var p := Vector2(x+.5,y+.5)
			if regions.any(func(polygon): return Geometry2D.is_point_in_polygon(p,polygon)):
				image.set_pixel(x,y,Color(metal.x,metal.y,metal.z))
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	_object_surfaces[name] = result
	return result


## Blend a material value using the same alpha and layer order as redress.
## The result is RGB data (linear, not source_color); a fully transparent
## overlay cannot turn the exposed skin or another item into metal.
static func blend_layer(base: Image, layer: Image, profile: Vector3) -> void:
	var src := layer.duplicate() as Image
	if src.is_compressed():
		src.decompress()
	src.clear_mipmaps()
	src.convert(Image.FORMAT_RGBA8)
	if src.get_size() != base.get_size():
		src.resize(base.get_width(), base.get_height(), Image.INTERPOLATE_BILINEAR)
	var data := src.get_data()
	var r := int(round(profile.x * 255.0))
	var g := int(round(profile.y * 255.0))
	var b := int(round(profile.z * 255.0))
	if _color_kernel and _color_kernel.has_method("colorize_rgba"):
		data = _color_kernel.colorize_rgba(data, r, g, b)
	else:
		for i in range(0, data.size(), 4):
			data[i] = r
			data[i + 1] = g
			data[i + 2] = b
	src = Image.create_from_data(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8, data)
	base.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)


static var _foliage := {}
const FOLIAGE_CACHE := "user://cache/foliage-v1"
const FOLIAGE_MAGIC := "EIFOL001"


static func _foliage_hash(data: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish()


## Hash the decoded source as well as its dimensions: edited/modded assets
## never inherit a mask from another installation. Bump the directory version
## whenever the mask algorithm or identified atlas regions change.
static func _foliage_path(name: String, size: Vector2i, source: PackedByteArray) -> String:
	return FOLIAGE_CACHE.path_join("%s-%dx%d-%s.bin" % [name,size.x,size.y,_foliage_hash(source).hex_encode()])


static func _foliage_read(path: String, size: Vector2i) -> PackedByteArray:
	if not FileAccess.file_exists(path): return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	var bytes := size.x * size.y * 4
	if f == null or f.get_length() != 48 + bytes: return PackedByteArray()
	if f.get_buffer(8).get_string_from_ascii() != FOLIAGE_MAGIC or f.get_32() != size.x or f.get_32() != size.y:
		return PackedByteArray()
	var checksum := f.get_buffer(32)
	var data := f.get_buffer(bytes)
	return data if data.size() == bytes and _foliage_hash(data) == checksum else PackedByteArray()


static func _foliage_write(path: String, size: Vector2i, data: PackedByteArray) -> void:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK: return
	# Rename a complete file into place; simultaneous game processes never read
	# a half-written entry. Cache failures leave ordinary generation available.
	var temporary := path + ".%d.tmp" % OS.get_process_id()
	var f := FileAccess.open(temporary, FileAccess.WRITE)
	if f == null: return
	f.store_buffer(FOLIAGE_MAGIC.to_ascii_buffer())
	f.store_32(size.x)
	f.store_32(size.y)
	f.store_buffer(_foliage_hash(data))
	f.store_buffer(data)
	var ok := f.get_error() == OK
	f.close()
	if not ok or DirAccess.rename_absolute(temporary,path) != OK:
		DirAccess.remove_absolute(temporary)

## Lost in Astral's autumn trees are recolours of the base tree02 atlas with
## identical cutouts. Their leaf pigment is read from the green original at
## the same texel, since orange and yellow foliage cannot be told from twigs
## by hue. The donor must have exactly the same coverage; otherwise the warm
## pigment rule below classifies the recolour on its own.
const FOLIAGE_RECOLOURS := {"tree01": "tree02", "tree05": "tree02", "tree06": "tree02"}
const FOLIAGE_MASKED := ["tree02", "tree03", "tree04", "oak00", "oak01", "bushset01", "bushset02",
	"bushset03", "bushset04", "bush03", "bush03a", "bush03d"]


static func _foliage_image(name: String) -> Image:
	var tex := GameData.get_texture(name)
	var img := tex.get_image() if tex else null
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _same_coverage(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	for i in range(3, a.size(), 4):
		if (a[i] > 127) != (b[i] > 127):
			return false
	return true


## R = leaf transmission; G = bark relief. Atlas coordinates are normalized,
## so the mask also lines up with the optional HD albedo without regeneration.
static func foliage_mask(texture: String) -> Texture2D:
	var name := texture.to_lower().trim_suffix(".mmp")
	if name not in FOLIAGE_MASKED and not FOLIAGE_RECOLOURS.has(name):
		return null
	if _foliage.has(name):
		return _foliage[name]
	var img := _foliage_image(name)
	if img == null:
		return null
	var data := img.get_data()
	var width := img.get_width()
	var height := img.get_height()
	var layout: String = FOLIAGE_RECOLOURS.get(name, name)
	var pigment_source := data
	var fingerprint := data
	if layout != name:
		var donor := _foliage_image(layout)
		if donor != null and donor.get_size() == img.get_size() and _same_coverage(data, donor.get_data()):
			pigment_source = donor.get_data()
			fingerprint = data.duplicate()
			fingerprint.append_array(pigment_source)
	var cache_path := _foliage_path(name, img.get_size(), fingerprint)
	var cached := _foliage_read(cache_path, img.get_size())
	if not cached.is_empty():
		var mask := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, cached)
		mask.generate_mipmaps()
		var result := ImageTexture.create_from_image(mask)
		_foliage[name] = result
		return result
	var warm := pigment_source == data and layout != name
	for y in height:
		for x in width:
			var uv := Vector2((x + 0.5) / width, (y + 0.5) / height)
			var i := (y * width + x) * 4
			var rgb := Vector3(pigment_source[i], pigment_source[i + 1], pigment_source[i + 2]) / 255.0
			var leaf := leaf_region(layout, uv)
			# Foliage pigment rejects brown twigs; low chroma rejects snow on
			# tree03. This is only a refinement of known leaf UV regions.
			var pigment := smoothstep(0.84, 1.03, rgb.y / maxf(rgb.x, 0.02))
			if warm:
				# Autumn recolour without its donor: bright, saturated warm
				# pixels are leaves; dark low-chroma pixels are twigs.
				pigment = smoothstep(0.30, 0.42, maxf(rgb.x, rgb.y))
			pigment *= smoothstep(0.01 if not warm else 0.10, 0.08 if not warm else 0.22, maxf(rgb.x, rgb.y) - rgb.z)
			data[i] = int(round(255.0 * leaf * pigment * float(data[i + 3]) / 255.0))
			data[i + 1] = 255 if bark_region(layout, uv) and data[i + 3] > 245 else 0
			data[i + 2] = 0
			data[i + 3] = 255
	_foliage_write(cache_path, img.get_size(), data)
	var mask := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	mask.generate_mipmaps()
	var result := ImageTexture.create_from_image(mask)
	_foliage[name] = result
	return result


static func leaf_region(name: String, uv: Vector2) -> float:
	if name in ["tree02", "tree03"]:
		if _rect(uv, 0.00, 0.26, 0.26, 0.54) or _rect(uv, 0.00, 0.54, 0.275, 0.80) \
				or _rect(uv, 0.24, 0.40, 0.35, 0.54) or _rect(uv, 0.32, 0.31, 0.63, 0.555) \
				or _rect(uv, 0.32, 0.54, 0.525, 0.72) or _rect(uv, 0.425, 0.17, 0.515, 0.38) \
				or _rect(uv, 0.63, 0.405, 0.86, 0.49) or _rect(uv, 0.00, 0.81, 0.395, 1.00) \
				or _rect(uv, 0.395, 0.73, 0.60, 1.00):
			return 1.0
	elif name == "tree04":
		if _rect(uv, 0.00, 0.00, 0.32, 0.365) or _rect(uv, 0.325, 0.00, 0.50, 0.54) \
				or _rect(uv, 0.00, 0.38, 0.465, 1.00) or _rect(uv, 0.75, 0.00, 0.94, 0.195) \
				or _rect(uv, 0.93, 0.325, 1.00, 0.55):
			return 1.0
	elif name in ["oak00", "oak01"]:
		return 1.0 if _rect(uv, 0.0, 0.50, 0.50, 1.0) else 0.0
	elif name.begins_with("bushset"):
		return 1.0
	elif name in ["bush03", "bush03a", "bush03d"]:
		return 1.0 if _rect(uv, 0.0, 0.50, 0.495, 1.0) else 0.0
	return 0.0


static func bark_region(name: String, uv: Vector2) -> bool:
	if name in ["tree02", "tree03"]:
		return _rect(uv, 0.285, 0.095, 0.335, 0.31) or _rect(uv, 0.60, 0.02, 0.85, 0.15) \
			or _rect(uv, 0.86, 0.02, 1.00, 0.15) or _rect(uv, 0.88, 0.25, 1.00, 0.715) \
			or _rect(uv, 0.615, 0.815, 1.00, 1.00)
	if name == "tree04":
		return _rect(uv, 0.535, 0.045, 0.65, 0.30) or _rect(uv, 0.545, 0.30, 0.635, 0.84) \
			or _rect(uv, 0.895, 0.625, 1.00, 1.00)
	if name in ["oak00", "oak01"]:
		return uv.y < 0.48
	return false


static func _rect(uv: Vector2, x0: float, y0: float, x1: float, y1: float) -> bool:
	return uv.x >= x0 and uv.x <= x1 and uv.y >= y0 and uv.y <= y1


static func clear_cache() -> void:
	_foliage.clear()
