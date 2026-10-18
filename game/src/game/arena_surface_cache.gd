class_name ArenaSurfaceCache
extends RefCounted
## Identical courtyards share immutable surface-query textures. Only packed
## source geometry and static textures are retained; tracks, clocks, materials,
## terrain nodes and combat state remain owned by each board.
const CAPACITY := 4
static var _entries: Array[Dictionary] = []
static var _shaders := {}


static func acquire(terrain: EITerrain) -> Dictionary:
	var key: Array = [terrain.grid_w, terrain.sectors_x, terrain.sectors_y,
		terrain.heights.duplicate(), terrain.land_xy.duplicate(), RenderingServer.get_current_rendering_method()]
	for sector in terrain.get_children():
		if sector is EITerrainSector:
			key.append([sector.name, sector._arrays[Mesh.ARRAY_NORMAL].duplicate(), sector._arrays[Mesh.ARRAY_COLOR].duplicate()])
	for entry in _entries:
		if entry.key == key: return entry.textures
	var textures := {
		"vertices":ImageTexture.create_from_image(GroundSurfaceData._vertex_image(terrain, true)),
		"normals":ImageTexture.create_from_image(GroundSurfaceData._normal_image(terrain)),
		"light_inputs":ImageTexture.create_from_image(GroundSurfaceData._light_input_image(terrain)),
		"candidates":ImageTexture.create_from_image(GroundSurfaceData._candidate_image(terrain)) \
			if RenderingServer.get_current_rendering_method() == "forward_plus" else null,
	}
	if _entries.size() >= CAPACITY: _entries.pop_front()
	_entries.append({"key":key,"textures":textures})
	return textures


static func shader(code: String) -> Shader:
	if not _shaders.has(code):
		if _shaders.size() >= 16: _shaders.clear()
		_shaders[code] = Gfx.make_shader(code)
	return _shaders[code]
