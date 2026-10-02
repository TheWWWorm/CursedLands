class_name SurfaceMaterials
extends RefCounted
## Remake surface response from the original assets. Equipment uses the
## database's material type and the exact redress alpha, never albedo brightness.
## The small foliage masks are made from identified regions of the shipped
## atlases: bark, branches and snow must not become translucent leaves.

const SKIN := Vector3(0.08, 0.92, 0.0)
const DULL := Vector3(0.04, 0.96, 0.0)

## Screen derivatives construct a tangent frame for EI meshes, which have no
## tangent stream. Local texture differences add shallow relief only; distance,
## minification and a hard slope bound suppress painted shadows and shimmer.
const RELIEF_SHADER := """
vec3 ei_relief_normal(sampler2D tex, vec2 uv, vec3 p, vec3 n, float strength) {
	vec2 size = vec2(textureSize(tex, 0));
	vec2 dx = dFdx(uv) * size;
	vec2 dy = dFdy(uv) * size;
	float visible_detail = 1.0 - smoothstep(1.2, 4.0, max(length(dx), length(dy)));
	visible_detail *= 1.0 - smoothstep(14.0, 40.0, length(p));
	vec2 px = 1.0 / size;
	vec3 lum = vec3(0.2126, 0.7152, 0.0722);
	float left = dot(texture(tex, uv - vec2(px.x, 0.0)).rgb, lum);
	float right = dot(texture(tex, uv + vec2(px.x, 0.0)).rgb, lum);
	float above = dot(texture(tex, uv - vec2(0.0, px.y)).rgb, lum);
	float below = dot(texture(tex, uv + vec2(0.0, px.y)).rgb, lum);
	vec2 slope = clamp(vec2(right - left, below - above) * 2.0, vec2(-0.12), vec2(0.12));
	vec3 dpdx = dFdx(p);
	vec3 dpdy = dFdy(p);
	vec2 duvdx = dFdx(uv);
	vec2 duvdy = dFdy(uv);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	vec3 u = r1 * duvdx.x + r2 * duvdy.x;
	vec3 v = r1 * duvdx.y + r2 * duvdy.y;
	float scale = inversesqrt(max(max(dot(u, u), dot(v, v)), 1e-12));
	return normalize(n - (u * slope.x + v * slope.y) * scale * strength * visible_detail);
}
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


## Only unambiguous texture families receive relief. Mixed house/chest atlases
## retain a dull nonmetal response until they have an authored material mask.
## xyz = highlight, roughness, metalness; w = shallow relief strength.
static func object_profile(texture: String) -> Vector4:
	var name := texture.to_lower().trim_suffix(".mmp")
	if name.begins_with("stone") or name.begins_with("columnruins") \
			or name in ["ruins00", "kanianruins00", "crypt00", "fence00"]:
		return Vector4(0.20, 0.84, 0.0, 0.70)
	if name in ["bridge00", "orcbridge00", "suspensionbridge00", "ladder00", "barrel00", "box00", "fence02", "stocks00"]:
		return Vector4(0.16, 0.86, 0.0, 0.45)
	return Vector4(DULL.x, DULL.y, DULL.z, 0.0)


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
	for i in range(0, data.size(), 4):
		data[i] = r
		data[i + 1] = g
		data[i + 2] = b
	src = Image.create_from_data(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8, data)
	base.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i.ZERO)


static var _foliage := {}

## R = leaf transmission; G = bark relief. Atlas coordinates are normalized,
## so the mask also lines up with the optional HD albedo without regeneration.
static func foliage_mask(texture: String) -> Texture2D:
	var name := texture.to_lower().trim_suffix(".mmp")
	if name not in ["tree02", "tree03", "tree04", "oak00", "oak01", "bushset01", "bushset02", "bushset03", "bushset04", "bush03", "bush03a", "bush03d"]:
		return null
	if _foliage.has(name):
		return _foliage[name]
	var tex := GameData.get_texture(name)
	var img := tex.get_image() if tex else null
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var width := img.get_width()
	var height := img.get_height()
	for y in height:
		for x in width:
			var uv := Vector2((x + 0.5) / width, (y + 0.5) / height)
			var i := (y * width + x) * 4
			var rgb := Vector3(data[i], data[i + 1], data[i + 2]) / 255.0
			var leaf := leaf_region(name, uv)
			# Foliage pigment rejects brown twigs; low chroma rejects snow on
			# tree03. This is only a refinement of known leaf UV regions.
			var pigment := smoothstep(0.84, 1.03, rgb.y / maxf(rgb.x, 0.02))
			pigment *= smoothstep(0.01, 0.08, maxf(rgb.x, rgb.y) - rgb.z)
			data[i] = int(round(255.0 * leaf * pigment * float(data[i + 3]) / 255.0))
			data[i + 1] = 255 if bark_region(name, uv) and data[i + 3] > 245 else 0
			data[i + 2] = 0
			data[i + 3] = 255
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
