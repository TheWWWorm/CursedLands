class_name GroundSurfaceData
extends RefCounted
## Static geometry and existing terrain/track textures for one map. Figure
## caches never own this resource; enabled ground-contact and cover consumers
## share it through EITerrain's weak reference.
const LAND_PARAMETERS := [&"atlases", &"terrain_tiles", &"terrain_cells", &"detail",
	&"tiles_per_axis", &"atlas_padding", &"source_texel", &"level", &"soft_ground",
	&"macro_tex", &"rain_cover"]
var _terrain: WeakRef
var vertices: ImageTexture
var normals: ImageTexture
var _empty := SoftGroundField.new()


func _init(terrain: EITerrain, contact := true) -> void:
	_terrain = weakref(terrain)
	_build(terrain,contact)


func _build(terrain: EITerrain, contact: bool) -> void:
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
	var directions := PackedFloat32Array()
	points.resize(count * 4)
	if contact: directions.resize(count * 4)
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
			var normal := terrain.land_n[i]
			directions[at] = normal.x
			directions[at + 1] = normal.y
			directions[at + 2] = normal.z
	var image := Image.create_from_data(width,height,false,Image.FORMAT_RGBAF,points.to_byte_array())
	# A contact consumer may join after cover. Preserve the bound vertex RID
	# when adding its upper bounds; XYZ and the cover's geometry stay identical.
	if vertices: vertices.update(image)
	else: vertices = ImageTexture.create_from_image(image)
	if contact:
		normals = ImageTexture.create_from_image(Image.create_from_data(width, height,
			false, Image.FORMAT_RGBAF, directions.to_byte_array()))


func bind(material: ShaderMaterial, triangle_only := false) -> void:
	var terrain := _terrain.get_ref() as EITerrain
	if terrain == null:
		return
	if not triangle_only and normals == null: _build(terrain,true)
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
		material.set_shader_parameter("query_normals", normals)
	material.set_shader_parameter("query_vertices", vertices)
	material.set_shader_parameter("query_vertex_count", 3)
	var field := _empty
	if is_instance_valid(terrain.details) and is_instance_valid(terrain.details.soft_ground):
		field = terrain.details.soft_ground.shared_field()
	material.set_shader_parameter("query_tiles", field.tiles)
	material.set_shader_parameter("query_tracks", field.texture)
	material.set_shader_parameter("query_clock", field.clock)
