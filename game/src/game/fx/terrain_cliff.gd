class_name TerrainCliff
extends RefCounted
## Optional wall coordinates and bounded relief. Identity rules use original
## atlases; neither HD art nor a map name can classify unknown artwork.
const Tiles = preload("res://src/game/fx/terrain_cliff_tiles.gd")
const CliffShader = preload("res://src/game/fx/terrain_cliff_shader.gd")
const Blends = preload("res://src/game/fx/terrain_cliff_blends.gd")
const WallMesh = preload("res://src/game/fx/terrain_cliff_mesh.gd")
const Cache = preload("res://src/game/fx/terrain_cliff_cache.gd")
const MAX_VERTICES := 1100000
var tiles: ImageTexture
var flatness: ImageTexture
var blends: ImageTexture
var blend_rows := PackedColorArray()
var mixed := 0
var eligible := PackedByteArray()
var geometry_eligible := PackedByteArray()
var guards := PackedByteArray()
var tile_size := Vector2i.ZERO
var grid_size := Vector2i.ZERO
var classified := 0
var admitted := 0
var rejected_geometry := 0
var build_us := 0
var examples: Array[Dictionary] = []
var _shaders := {}
var geometry: RefCounted
var _snow_tall := false
var _cache_key := ""
var reused := false


static func create(terrain: EITerrain, verified: Dictionary = {}) -> TerrainCliff:
	var identity := Cache.key(terrain, verified)
	var cached := Cache.take(identity)
	var field: TerrainCliff
	if cached.is_empty():
		field = TerrainCliff.new(terrain, verified)
	else:
		field = TerrainCliff.new()
		for property: String in cached.state.field:
			field.set(property, cached.state.field[property])
		field.tiles = cached.textures[0]
		field.flatness = cached.textures[1]
		field.blends = cached.textures[2]
		if not cached.state.geometry.is_empty():
			field.geometry = WallMesh.new()
			for property: String in cached.state.geometry:
				field.geometry.set(property, cached.state.geometry[property])
		field.reused = true
	field._cache_key = identity
	return field


## Called after all authored sectors have prepared their patches. Later snow
## deformation keeps its private bounded cache and cannot mutate this record.
func retain() -> void:
	Cache.remember(_cache_key, self)


func _init(terrain: EITerrain = null, verified: Dictionary = {}) -> void:
	if terrain == null: return
	var start := Time.get_ticks_usec()
	_build(terrain, verified)
	if admitted > 0 or _snow_tall: geometry = WallMesh.new(terrain, self)
	build_us = Time.get_ticks_usec() - start


static func requested() -> bool:
	return DisplayServer.get_name() != "headless" and Gfx.on("gfx_terrain") and Gfx.on("gfx_terrain_cliffs")


func _build(terrain: EITerrain, verified: Dictionary) -> void:
	grid_size = Vector2i(terrain.grid_w, terrain.sectors_y * 32 + 1)
	tile_size = Vector2i(terrain.sectors_x * 16, terrain.sectors_y * 16)
	var count := grid_size.x * grid_size.y
	if count <= 0 or count > MAX_VERTICES or tile_size.x <= 0 or tile_size.y <= 0 \
		or grid_size.x != tile_size.x * 2 + 1 \
		or terrain.texture_size != 512 or terrain.tile_size != 64 \
		or terrain.heights.size() != count or terrain.land_xy.size() != count \
		or terrain.land_n.size() != count or terrain.land_tile.size() != tile_size.x * tile_size.y:
		return
	var masks := verified.duplicate()
	var rules := {}
	if masks.is_empty():
		for atlas in clampi(int(terrain.get_meta("textures_count", 0)), 0, 256):
			var image := GameData.load_original_image("%s%03d" % [terrain.resource_prefix, atlas])
			var mask := Tiles.masks(image)
			if not mask.is_empty(): masks[atlas] = mask
			var corners := Tiles.blend_corners(image)
			if not corners.is_empty(): rules[atlas] = corners
	blend_rows = Blends.build(terrain, rules)
	eligible.resize(terrain.land_tile.size())
	geometry_eligible.resize(terrain.land_tile.size())
	var needed := PackedByteArray(); needed.resize(count)
	for ty in tile_size.y:
		for tx in tile_size.x:
			var i := ty * tile_size.x + tx
			var code := terrain.land_tile[i]
			if code < 0 or code > 65535: continue
			var atlas := (code >> 6) & 255
			var slot := code & 63
			var plain: bool = masks.has(atlas) and masks[atlas].size() == 64 and masks[atlas][slot] == 1
			var type_id := atlas * 64 + slot
			if type_id >= terrain.tile_types.size(): continue
			var ground := terrain.tile_types[type_id]
			var projected := (plain or blend_rows[i].a > 0) and Blends.ground_allowed(ground)
			var snowy := snow_geometry(rules.get(atlas, PackedByteArray()), slot, ground)
			if not projected and not snowy: continue
			if projected: classified += 1
			if not _valid_tile(terrain, tx * 2, ty * 2):
				blend_rows[i] = Color(0,0,0,0)
				rejected_geometry += 1
				continue
			geometry_eligible[i] = 255
			if snowy and not _snow_tall:
				for dy in 2:
					for dx in 2:
						var a := (ty * 2 + dy) * grid_size.x + tx * 2 + dx
						for tri: Vector3i in [Vector3i(a,a+1,a+grid_size.x),Vector3i(a+1,a+grid_size.x+1,a+grid_size.x)]:
							var h := Vector3(terrain.heights[tri.x],terrain.heights[tri.y],terrain.heights[tri.z])
							if maxf(h.x,maxf(h.y,h.z))-minf(h.x,minf(h.y,h.z))>WallMesh.MIN_SPAN:_snow_tall=true
			# Known snowy hills need the same contour refinement, but their
			# painted snow/rock boundaries must keep the original projection.
			if not projected: continue
			eligible[i] = 255
			if blend_rows[i].a > 0: mixed += 1
			for y in range(maxi(ty * 2 - 1, 0), mini(ty * 2 + 3, grid_size.y - 1)):
				for x in range(maxi(tx * 2 - 1, 0), mini(tx * 2 + 3, grid_size.x - 1)):
					needed[y * grid_size.x + x] = 1
	if eligible.count(255) == 0: return
	# The maximum and mean neighbouring facet upness protect flat crests and
	# saddle points whose smoothed vertex normal tilts toward a nearby wall.
	var steepest := PackedFloat32Array(); steepest.resize(count); steepest.fill(1.0)
	var best := PackedFloat32Array(); best.resize(count)
	var total := PackedFloat32Array(); total.resize(count)
	var facets := PackedByteArray(); facets.resize(count)
	for y in grid_size.y - 1:
		for x in grid_size.x - 1:
			if needed[y * grid_size.x + x] == 0: continue
			var a := y * grid_size.x + x
			for tri: Vector3i in [Vector3i(a, a + 1, a + grid_size.x), Vector3i(a + 1, a + grid_size.x + 1, a + grid_size.x)]:
				var normal := (_point(terrain, tri.y) - _point(terrain, tri.x)).cross(_point(terrain, tri.z) - _point(terrain, tri.x))
				if not normal.is_finite() or normal.y <= 1e-7: continue
				var up := normal.normalized().y
				for index in [tri.x, tri.y, tri.z]:
					steepest[index] = minf(steepest[index], up)
					best[index] = maxf(best[index], up)
					total[index] += up
					facets[index] += 1
	guards.resize(count); guards.fill(255)
	for i in count:
		if facets[i] > 0: guards[i] = roundi(clampf((best[i] + total[i] / facets[i]) * 0.5, 0.0, 1.0) * 255.0)
	for ty in tile_size.y:
		for tx in tile_size.x:
			if eligible[ty * tile_size.x + tx] == 0: continue
			var strongest := 0.0
			var at := 0
			for y in range(ty * 2, ty * 2 + 3):
				for x in range(tx * 2, tx * 2 + 3):
					var i := y * grid_size.x + x
					# Authored lighting normals can point upward on near-vertical
					# cave walls. Admission follows actual geometry, not lighting.
					var up := steepest[i]
					var weight := side_weight(Vector3(sqrt(maxf(1.0-up*up,0.0)),up,0.0), up)
					if weight > strongest: strongest = weight; at = i
			if strongest <= 0.0: continue
			admitted += 1
			if examples.size() < 20:
				examples.append({"tile": Vector2i(tx, ty), "point": _point(terrain, at), "normal": terrain.land_n[at], "weight": strongest})
	if admitted == 0: return
	tiles = ImageTexture.create_from_image(Image.create_from_data(tile_size.x, tile_size.y, false, Image.FORMAT_R8, eligible))
	flatness = ImageTexture.create_from_image(Image.create_from_data(grid_size.x, grid_size.y, false, Image.FORMAT_R8, guards))
	blends = ImageTexture.create_from_image(Image.create_from_data(tile_size.x, tile_size.y, false, Image.FORMAT_RGBAF, blend_rows.to_byte_array()))


static func snow_geometry(corners: PackedByteArray, slot: int, ground: int) -> bool:
	if corners.size() != 256 or not (ground in [9,12] or Blends.ground_allowed(ground)): return false
	var snow := false
	for family in corners.slice(slot * 4, slot * 4 + 4):
		if family <= 0 or family >= Tiles.Natural.FAMILIES.size(): return false
		var name: String = Tiles.Natural.FAMILIES[family]
		var snowy := name.begins_with("snow /") or name == "rock / snow"
		if not snowy and not Blends.supported(family): return false
		snow = snow or snowy
	return snow


func _point(terrain: EITerrain, index: int) -> Vector3:
	return Vector3(float(index % grid_size.x) + terrain.land_xy[index].x, terrain.heights[index],
		-float(index / grid_size.x) - terrain.land_xy[index].y)


func _valid_tile(terrain: EITerrain, x: int, y: int) -> bool:
	for dy in 3:
		for dx in 3:
			var normal := terrain.land_n[(y + dy) * grid_size.x + x + dx]
			if not normal.is_finite() or normal.length_squared() < 1e-8: return false
	for dy in 2:
		for dx in 2:
			var a := (y + dy) * grid_size.x + x + dx
			for tri: Vector3i in [Vector3i(a, a + 1, a + grid_size.x), Vector3i(a + 1, a + grid_size.x + 1, a + grid_size.x)]:
				var pa := _point(terrain, tri.x)
				var pb := _point(terrain, tri.y)
				var pc := _point(terrain, tri.z)
				# Folded/degenerate XY cells are deliberately neutral. Original
				# winding and all vertex data stay untouched by this effect.
				if not pa.is_finite() or not pb.is_finite() or not pc.is_finite() or (pb - pa).cross(pc - pa).y <= 1e-7:
					return false
	return true


static func side_weight(normal: Vector3, facet_guard: float) -> float:
	if not normal.is_finite() or normal.length_squared() < 1e-8: return 0.0
	var up := absf(normal.normalized().y)
	return (1.0 - smoothstep(0.57357644, 0.76604444, up)) * (1.0 - smoothstep(0.72, 0.95, facet_guard))


func source(original: String) -> String:
	return CliffShader.source(original) if admitted > 0 else original


func shader(original: String) -> Shader:
	if not _shaders.has(original): _shaders[original] = Gfx.make_shader(source(original), true, true)
	return _shaders[original]


func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("cliff_tiles", tiles)
	material.set_shader_parameter("cliff_flatness", flatness)
	material.set_shader_parameter("cliff_blends", blends)
