class_name ArenaTerrainColor
extends RefCounted
## Derived tile colour shared by the identical 64 m courtyards. This does not
## bake normals, light, snow compaction or marks. Those remain live in the
## ordinary terrain material, including its copies on deformed meshes.
const DENSITY := 128
const BUDGET_BYTES := 128 * 1024 * 1024
static var _shared := {} # asset/layout identity -> weak Texture2DArray


static func available(terrain: EITerrain) -> bool:
	if DisplayServer.get_name() == "headless" or terrain.texture_size <= 0: return false
	# Other renderers retain their tested sampler and memory budgets. Large
	# replacement atlases must keep their authored detail rather than being
	# downsampled to this cache's fixed, validated density.
	var density := (terrain.tile_size - 16) * (terrain._atlas_source_size / terrain.texture_size) \
		* (2 if terrain._atlas_hd else 1)
	return ClassDB.class_exists("TerrainColorField") \
		and RenderingServer.get_current_rendering_method() == "forward_plus" \
		and Gfx.on("gfx_terrain") and density <= DENSITY \
		and terrain.sectors_x == 2 and terrain.sectors_y == 2 \
		and (terrain._cliffs == null or terrain._cliffs.admitted == 0) \
		and (terrain._transitions == null or terrain._transitions.admitted == 0)


static func acquire(terrain: EITerrain) -> Texture2DArray:
	if not available(terrain) or terrain._detail_atlases == null: return null
	# Asset roots are immutable for a loaded game. Include the complete tile
	# layout so different courtyards cannot alias through a layout hash.
	var key := str([GameData.root, terrain.resource_prefix, terrain.texture_size,
		terrain.tile_size, terrain._atlas_source_size, terrain._atlas_hd, terrain.land_tile])
	for old_key: String in _shared.keys():
		if _shared[old_key].get_ref() == null: _shared.erase(old_key)
	if _shared.has(key): return _shared[key].get_ref() as Texture2DArray
	var images: Array[Image] = []
	for layer in terrain._detail_atlases.get_layers():
		var pixels := terrain._detail_atlases.get_layer_data(layer)
		if pixels == null: return null
		if pixels.is_compressed() and pixels.decompress() != OK: return null
		images.append(pixels)
	var field: RefCounted = ClassDB.instantiate("TerrainColorField")
	if not field.configure(images, terrain.land_tile, Vector2i(32, 32),
			terrain.texture_size, terrain.tile_size, EITerrain.TERRAIN_GUTTER, true): return null
	images.clear()
	var bytes := 0
	for y in 2:
		for x in 2:
			var pixels: Image = field.bake(Vector2i(x, y), DENSITY)
			if pixels == null: return null
			bytes += pixels.get_data().size()
			if bytes > BUDGET_BYTES: return null
			images.append(pixels)
			NetStatus.keep_alive()
	var texture := Texture2DArray.new()
	if texture.create_from_images(images) != OK: return null
	texture.set_meta("bytes", bytes)
	_shared[key] = weakref(texture)
	return texture


static func source(code: String) -> String:
	# A single array binding works on both ordinary and live footprint
	# materials. Selecting by authored tile ID also works when scouting moves
	# a board away from the origin; no world-space cache offset is needed.
	code = code.replace("shader_type spatial;", "shader_type spatial;\n#define EI_BAKED_TERRAIN")
	code = code.replace("uniform sampler2D baked_ground", "uniform sampler2DArray baked_ground")
	return code.replace(
		"return textureGrad(baked_ground,(vec2(cell)+p-bake_origin)/bake_span,dx/bake_span,dy/bake_span).rgb;",
		"""ivec2 sector = clamp(cell / 16, ivec2(0), ivec2(1));
 return textureGrad(baked_ground,
  vec3((vec2(cell) + p - vec2(sector * 16 - ivec2(1))) / 18.0, float(sector.y * 2 + sector.x)),
  dx / 18.0, dy / 18.0).rgb;""")
