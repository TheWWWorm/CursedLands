extends RefCounted
## Immutable terrain inputs for traced material evaluation. The padded atlas
## is shared with raster rendering; retaining its resource owns that lifetime.
## Only tile identity/traits, cliff guards and transition metadata are copied.
const HEADER := 64
var data := PackedByteArray()
var atlas: TextureLayered
var build_us := 0
var terrain_triangles := 0

static func version(terrain: EITerrain) -> Array:
	var material := terrain._land_mat
	var normal: Texture2D = material.get_shader_parameter("detail_nm") if material else null
	var macro: Texture2D = material.get_shader_parameter("macro_tex") if material else null
	# Readiness alone cannot distinguish two already generated textures. Keep
	# their identities and the sampled edge mode in the immutable snapshot.
	return [terrain._detail_atlases,terrain._cliffs,terrain._transitions,
		normal,normal != null and normal.get_image() != null,
		macro,macro != null and macro.get_image() != null,
		material == null or material.get_shader_parameter("blend_edges") != false]

func collect(scene: RefCounted, terrain: EITerrain) -> void:
	var start := Time.get_ticks_usec()
	data.resize(HEADER)
	if not Gfx.on("gfx_terrain") or terrain._detail_atlases == null: return
	var size := Vector2i(terrain.sectors_x*16,terrain.sectors_y*16)
	if size.x<=0 or size.y<=0 or size.x*size.y!=terrain.land_tile.size(): return
	var normal: Texture2D = terrain._land_mat.get_shader_parameter("detail_nm")
	var macro: Texture2D = terrain._land_mat.get_shader_parameter("macro_tex")
	# NoiseTexture2D is generated asynchronously. A completed texture changes
	# version(), rebuilding this snapshot instead of binding a transient RID.
	var normal_layer: int = scene._layer(normal) if normal != null and normal.get_image()!=null else -1
	var macro_layer: int = scene._layer(macro) if macro != null and macro.get_image()!=null else -1
	var tiles := PackedInt32Array(); tiles.resize(terrain.land_tile.size())
	var cliff := terrain._cliffs
	for i in tiles.size():
		var code := terrain.land_tile[i]
		var type := terrain.tile_types[code&16383] if (code&16383)<terrain.tile_types.size() else 0
		tiles[i] = (code&65535) | (clampi(type,0,255)<<16)
		if cliff != null and cliff.admitted>0 and cliff.eligible[i]>0:
			tiles[i] |= 1<<24
			if cliff.blend_rows[i].a>0: tiles[i] |= 1<<25
	data.encode_u32(0,size.x);data.encode_u32(4,size.y);data.encode_u32(8,data.size())
	data.append_array(tiles.to_byte_array())
	data.encode_u32(12,data.size())
	var primitives := PackedInt32Array();primitives.resize(scene.vertices.size()/48)
	for geometry: Dictionary in scene.geometries:
		if not geometry.has("land_tiles"): continue
		var ids: PackedInt32Array = geometry.land_tiles
		for i in ids.size(): primitives[geometry.offset/3+i]=ids[i]
		terrain_triangles+=ids.size()
	data.append_array(primitives.to_byte_array())
	data.encode_float(16,float(terrain.texture_size)/terrain.tile_size)
	data.encode_float(20,float(EITerrain.TERRAIN_GUTTER)/terrain.tile_size)
	data.encode_float(24,1.0/terrain.texture_size)
	data.encode_float(28,1.0 if terrain._land_mat.get_shader_parameter("blend_edges")!=false else 0.0)
	data.encode_u32(32,normal_layer+1);data.encode_u32(36,macro_layer+1)
	data.encode_u32(44,1 if Gfx.on("gfx_materials") else 0)
	if cliff != null and cliff.admitted>0:
		data.encode_u32(40,data.size());data.encode_u32(48,cliff.grid_size.x);data.encode_u32(52,cliff.grid_size.y)
		data.append_array(cliff.guards);data.resize((data.size()+3)&~3)
		if cliff.mixed>0: data.append_array(cliff.blend_rows.to_byte_array())
	var transition := terrain._transitions
	if transition != null and transition.admitted>0:
		data.encode_u32(56,data.size());data.append_array(transition.rows.to_byte_array())
		if transition.junctions>0:
			data.encode_u32(60,data.size());data.append_array(transition.junction_rows.to_byte_array())
	atlas=terrain._detail_atlases
	build_us=Time.get_ticks_usec()-start
