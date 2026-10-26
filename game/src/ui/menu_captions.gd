class_name MenuCaptions
extends RefCounted
## The lettering is original artwork, including its bevel, shadow and stone.
## Recover edge contrast in its native samples before reconstructing the atlas.
## Lanczos alone enlarges the painted blur along with the glyphs at 4K. The
## bounded, luminance-only correction retains the original shapes and relief;
## no replacement font, repainted background or extra rendering pass is used.

const CACHE := &"menu_caption_edge_enlargement"


static func _edges(image: Image) -> Image:
	var out := image.duplicate() as Image
	var w := image.get_width()
	var h := image.get_height()
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			if c.a < 0.99: continue
			var n := image.get_pixel(x, maxi(0, y - 1))
			var s := image.get_pixel(x, mini(h - 1, y + 1))
			var e := image.get_pixel(mini(w - 1, x + 1), y)
			var v := image.get_pixel(maxi(0, x - 1), y)
			# Keep alpha silhouettes and their transparent RGB padding untouched.
			if minf(minf(n.a, s.a), minf(e.a, v.a)) < 0.99: continue
			var l := c.get_luminance()
			var ln := n.get_luminance()
			var ls := s.get_luminance()
			var le := e.get_luminance()
			var lv := v.get_luminance()
			var lo := minf(l, minf(minf(ln, ls), minf(le, lv)))
			var hi := maxf(l, maxf(maxf(ln, ls), maxf(le, lv)))
			# Leave quiet stone grain alone. Sharpen the existing bright/dark
			# painted edges, with a cap that protects the palette and bevels.
			var delta := clampf((l - (ln + ls + le + lv) * 0.25) * 0.55
				* smoothstep(0.12, 0.32, hi - lo), -0.12, 0.12)
			out.set_pixel(x, y, Color(clampf(c.r + delta, 0.0, 1.0),
				clampf(c.g + delta, 0.0, 1.0), clampf(c.b + delta, 0.0, 1.0), c.a))
	return out


static func enlarged(source: Texture2D) -> Texture2D:
	if source == null or maxi(source.get_width(), source.get_height()) >= 1024:
		return source
	if source.has_meta(CACHE):
		return source.get_meta(CACHE)
	var image := source.get_image()
	if image == null or image.is_empty(): return source
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps()
	# Keep alpha-tested edges clean without changing any opaque artwork.
	image.fix_alpha_edges()
	image = _edges(image)
	# Eight samples per original texel keep the reconstructed edges resolved
	# when the small original atlas covers a 2160-pixel-tall menu. Existing HD
	# mod textures (1024+) keep their authored pixels and original mip chain.
	var factor := minf(8.0, 2048.0 / maxi(image.get_width(), image.get_height()))
	image.resize(roundi(image.get_width() * factor), roundi(image.get_height() * factor), Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	# Cache on the native texture so campaign/archive changes release both.
	source.set_meta(CACHE, texture)
	return texture


static func apply(figure: Node3D, model: String) -> void:
	if model not in ["unmoco1", "unmoco2"]: return
	var skin := "mainmenu00" if model == "unmoco2" else "escmenu00"
	var textures := {}
	for name: String in [skin, skin + "labels"]:
		var native := GameData.get_texture(name)
		if native == null: continue
		var texture := enlarged(native)
		textures[native] = texture
		# LiA lettering is baked into the primary skin, which uses the
		# world's HD-texture path in the main menu. Base-game label planes
		# and all interface boards use the native UI texture instead.
		if model == "unmoco2":
			textures[Gfx.texture_3d(name)] = texture
	var materials := {}
	for mesh: MeshInstance3D in figure.find_children("*", "MeshInstance3D", true, false):
		var original := mesh.material_override
		if materials.has(original):
			mesh.material_override = materials[original]
			continue
		var source: Texture2D
		if original is StandardMaterial3D: source = original.albedo_texture
		elif original is ShaderMaterial: source = original.get_shader_parameter("albedo_tex")
		if source == null or not textures.has(source): continue
		# Caller-owned copies retain lighting, alpha, hover and contact state.
		var material: Material = original.duplicate()
		if material is StandardMaterial3D: material.albedo_texture = textures[source]
		elif material is ShaderMaterial: material.set_shader_parameter("albedo_tex", textures[source])
		materials[original] = material
		mesh.material_override = material
