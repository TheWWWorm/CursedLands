class_name GroundSurfaceData
extends RefCounted
## Static geometry and existing terrain/track textures for one map. Figure
## caches never own this resource; enabled ground-contact and cover consumers
## share it through EITerrain's weak reference.
const LAND_PARAMETERS := [&"atlases", &"terrain_tiles", &"terrain_cells", &"detail",
	&"tiles_per_axis", &"atlas_padding", &"source_texel", &"level", &"soft_ground",
	&"macro_tex", &"rain_cover", &"detail_nm"]
var _terrain: WeakRef
var vertices: ImageTexture
var normals: ImageTexture
var light_inputs: ImageTexture
var metadata: GroundContactData
var _metadata_key := []
var _vertex_snapshot: Image
var _dense_colors: GroundDenseColors
var _empty := SoftGroundField.new()


func _init(terrain: EITerrain, contact := true) -> void:
	_terrain = weakref(terrain)
	_build(terrain,contact)


static func _vertex_image(terrain: EITerrain, contact: bool) -> Image:
	var count := terrain.heights.size()
	var width := terrain.grid_w
	var height := terrain.sectors_y * 32 + 1
	var top_x := PackedFloat32Array()
	if contact:
		top_x.resize(count)
		for y in height:
			for x in width:
				var top := -INF
				for dx in range(-1, 3):
					top = maxf(top, terrain.heights[y * width + clampi(x + dx, 0, width - 1)])
				top_x[y * width + x] = top
	var points := PackedFloat32Array()
	points.resize(count * 4)
	for y in height:
		for x in width:
			var i := y * width + x
			var at := i * 4
			points[at] = terrain.land_xy[i].x
			points[at + 1] = terrain.heights[i]
			points[at + 2] = terrain.land_xy[i].y
			if not contact: continue
			var top := -INF
			for dy in range(-1, 3):
				top = maxf(top, top_x[clampi(y + dy, 0, height - 1) * width + x])
			# Conservative upper bound for any triangle covering this metre.
			# Shader adds the maximum loose/banked displacement before skipping.
			points[at + 3] = top
	return Image.create_from_data(width,height,false,Image.FORMAT_RGBAF,points.to_byte_array())


func _build(terrain: EITerrain, contact: bool) -> void:
	var image := _vertex_image(terrain, contact)
	# A contact consumer may join after cover. Preserve the bound vertex RID
	# when adding its upper bounds; XYZ and the cover's geometry stay identical.
	if vertices: vertices.update(image)
	else: vertices = ImageTexture.create_from_image(image)
	if contact:
		if Portability.compatibility():
			_vertex_snapshot = image
			_refresh_metadata(terrain)
		else:
			normals = ImageTexture.create_from_image(_normal_image(terrain))
			light_inputs = ImageTexture.create_from_image(_light_input_image(terrain))


func _refresh_metadata(terrain: EITerrain) -> void:
	var cliff := terrain._cliffs
	var transition := terrain._transitions
	var key := [cliff.get_instance_id() if cliff else 0, transition.get_instance_id() if transition else 0]
	if metadata == null or key != _metadata_key:
		if metadata == null: metadata = GroundContactData.new()
		metadata.build(_metadata_images(terrain))
		_metadata_key = key


func _metadata_images(terrain: EITerrain) -> Dictionary:
	var images := {"query_vertices":_vertex_snapshot, "query_normals":_normal_image(terrain), "query_light_inputs":_light_input_image(terrain),
		"terrain_tiles":terrain._ground_tile_image(), "terrain_cells":terrain._surface_cell_image()}
	var cliff := terrain._cliffs
	if cliff and cliff.admitted > 0:
		images.cliff_tiles = Image.create_from_data(cliff.tile_size.x, cliff.tile_size.y, false, Image.FORMAT_R8, cliff.eligible)
		images.cliff_flatness = Image.create_from_data(cliff.grid_size.x, cliff.grid_size.y, false, Image.FORMAT_R8, cliff.guards)
	var transition := terrain._transitions
	if transition and transition.admitted > 0:
		var pixels := transition.rows.to_byte_array()
		if transition.junctions > 0: pixels.append_array(transition.junction_rows.to_byte_array())
		images.transition_tiles = Image.create_from_data(transition.tile_size.x, transition.tile_size.y * (2 if transition.junctions > 0 else 1), false, Image.FORMAT_RGBAF, pixels)
	return images



## ArrayMesh packs every ordinary normal to two octahedral uint16 values.
## Reproduce that upload and CPU decode from the retained source arrays;
## terrain.land_n is the uncompressed authored value, not the drawn normal.
static func _mesh_normal(value: Vector3) -> Vector3:
	var encoded := value.octahedron_encode()*65535.0
	return Vector3.octahedron_decode(Vector2(
		float(clampi(int(encoded.x),0,65535))/65535.0,
		float(clampi(int(encoded.y),0,65535))/65535.0))


static func _normal_image(terrain: EITerrain) -> Image:
	var pixels := Image.create(terrain.sectors_x*33,terrain.sectors_y*33,false,Image.FORMAT_RGBAF)
	for sector: Node in terrain.get_children():
		if not sector is EITerrainSector: continue
		var name_parts := String(sector.name).split("_")
		var origin := Vector2i(int(name_parts[1]),int(name_parts[2]))*33
		var source_normals: PackedVector3Array=sector._arrays[Mesh.ARRAY_NORMAL]
		for y in 33:
			for x in 33:
				var tx := mini(x/2,15); var ty := mini(y/2,15)
				var source := (ty*16+tx)*9+(y-ty*2)*3+x-tx*2
				var n := _mesh_normal(source_normals[source])
				pixels.set_pixelv(origin+Vector2i(x,y),Color(n.x,n.y,n.z,1.0))
	return pixels


## Original sector COLOR is baked during load. It does not follow scripted
## water offsets. Copy its mesh packing, including sector-local edge identity,
## without creating a second mesh or reading GPU vertex buffers back.
static func _light_input_image(terrain: EITerrain) -> Image:
	var pixels := Image.create(terrain.sectors_x*33,terrain.sectors_y*33,false,Image.FORMAT_RGBA8)
	pixels.fill(Color(0,0,0,0))
	for sector: Node in terrain.get_children():
		if not sector is EITerrainSector: continue
		var name_parts := String(sector.name).split("_")
		var origin := Vector2i(int(name_parts[1]),int(name_parts[2]))*33
		var colours: PackedColorArray=sector._arrays[Mesh.ARRAY_COLOR]
		for y in 33:
			for x in 33:
				var tx := mini(x/2,15); var ty := mini(y/2,15)
				var source := (ty*16+tx)*9+(y-ty*2)*3+x-tx*2
				# FORMAT_RGBA8 truncates each stored Color channel *255,
				# exactly like RenderingServer's initial ARRAY_COLOR packing.
				pixels.set_pixelv(origin+Vector2i(x,y),colours[source])
	return pixels


func bind(material: ShaderMaterial, triangle_only := false) -> void:
	var terrain := _terrain.get_ref() as EITerrain
	if terrain == null:
		return
	if not triangle_only and normals == null and metadata == null: _build(terrain,true)
	for key in LAND_PARAMETERS:
		if triangle_only and key not in [&"terrain_tiles",&"terrain_cells",&"level",&"soft_ground"]: continue
		material.set_shader_parameter(key, terrain._land_mat.get_shader_parameter(key))
	if not triangle_only:
		if terrain._cliffs != null and terrain._cliffs.admitted > 0:
			terrain._cliffs.bind(material)
		if terrain._transitions != null and terrain._transitions.admitted > 0:
			terrain._transitions.bind(material)
		material.set_shader_parameter("blend_edges", Gfx.on("gfx_terrain"))
		material.set_shader_parameter("query_cell_count", 9)
		material.set_shader_parameter("contact_query_passes", 2)
		if Portability.compatibility():
			_refresh_metadata(terrain)
			metadata.bind(material)
		else:
			material.set_shader_parameter("query_normals", normals)
			material.set_shader_parameter("query_light_inputs", light_inputs)
	material.set_shader_parameter("query_vertices", vertices)
	material.set_shader_parameter("query_vertex_count", 3)
	var field := _empty
	if is_instance_valid(terrain.details) and is_instance_valid(terrain.details.soft_ground):
		field = terrain.details.soft_ground.shared_field()
	material.set_shader_parameter("query_tiles", field.tiles)
	material.set_shader_parameter("query_tracks", field.texture)
	material.set_shader_parameter("query_clock", field.clock)
	if not triangle_only:
		_dense_colors = field.contact_colors()
		material.set_shader_parameter("query_dense_light_inputs",_dense_colors.texture)
		material.set_shader_parameter("query_dense_light_tiles",_dense_colors.tiles)
