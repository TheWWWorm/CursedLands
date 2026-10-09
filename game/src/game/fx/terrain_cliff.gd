class_name TerrainCliff
extends RefCounted
## Optional albedo coordinates only. Identity rules refer to untouched original
## atlases; neither HD art nor a map name can turn unknown tiles into rock.
const Tiles = preload("res://src/game/fx/terrain_cliff_tiles.gd")
const CliffShader = preload("res://src/game/fx/terrain_cliff_shader.gd")
const MAX_VERTICES := 1100000
var tiles: ImageTexture
var flatness: ImageTexture
var eligible := PackedByteArray()
var guards := PackedByteArray()
var tile_size := Vector2i.ZERO
var grid_size := Vector2i.ZERO
var classified := 0
var admitted := 0
var rejected_geometry := 0
var build_us := 0
var examples: Array[Dictionary] = []
var _shaders := {}


func _init(terrain: EITerrain = null, verified: Dictionary = {}) -> void:
	if terrain == null: return
	var start := Time.get_ticks_usec()
	_build(terrain, verified)
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
	if masks.is_empty():
		for atlas in clampi(int(terrain.get_meta("textures_count", 0)), 0, 256):
			var mask := Tiles.masks(GameData.load_image("%s%03d" % [terrain.resource_prefix, atlas]))
			if not mask.is_empty(): masks[atlas] = mask
	eligible.resize(terrain.land_tile.size())
	var needed := PackedByteArray(); needed.resize(count)
	for ty in tile_size.y:
		for tx in tile_size.x:
			var i := ty * tile_size.x + tx
			var code := terrain.land_tile[i]
			if code < 0 or code > 65535: continue
			var atlas := (code >> 6) & 255
			var slot := code & 63
			if not masks.has(atlas) or masks[atlas].size() != 64 or masks[atlas][slot] != 1: continue
			var type_id := atlas * 64 + slot
			if type_id >= terrain.tile_types.size(): continue
			# Snow/ice/liquid metadata may reuse original rock artwork. Retain
			# its authored surface even when that atlas is otherwise recognised.
			var ground := terrain.tile_types[type_id]
			if ground < 0 or ground > 15 or ground in [9, 10, 12, 13, 14]: continue
			classified += 1
			if not _valid_tile(terrain, tx * 2, ty * 2):
				rejected_geometry += 1
				continue
			eligible[i] = 255
			for y in range(maxi(ty * 2 - 1, 0), mini(ty * 2 + 3, grid_size.y - 1)):
				for x in range(maxi(tx * 2 - 1, 0), mini(tx * 2 + 3, grid_size.x - 1)):
					needed[y * grid_size.x + x] = 1
	if eligible.count(255) == 0: return
	# The maximum and mean neighbouring facet upness protect flat crests and
	# saddle points whose smoothed vertex normal tilts toward a nearby wall.
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
					var weight := side_weight(terrain.land_n[i], guards[i] / 255.0)
					if weight > strongest: strongest = weight; at = i
			if strongest <= 0.0: continue
			admitted += 1
			if examples.size() < 20:
				examples.append({"tile": Vector2i(tx, ty), "point": _point(terrain, at), "normal": terrain.land_n[at], "weight": strongest})
	if admitted == 0: return
	tiles = ImageTexture.create_from_image(Image.create_from_data(tile_size.x, tile_size.y, false, Image.FORMAT_R8, eligible))
	flatness = ImageTexture.create_from_image(Image.create_from_data(grid_size.x, grid_size.y, false, Image.FORMAT_R8, guards))


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
