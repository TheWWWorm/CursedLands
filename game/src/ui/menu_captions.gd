class_name MenuCaptions
extends RefCounted
## The lettering is original artwork, including its bevel, shadow and stone.
## Reconstruct that atlas once with Lanczos rather than stretching its 256²
## texels with bilinear filtering at desktop resolutions. Never redraw glyphs
## or paint over their backgrounds. Native geometry, UVs and materials stay.

const CACHE := &"menu_caption_enlargement"


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
	var factor := minf(4.0, 1024.0 / maxi(image.get_width(), image.get_height()))
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
