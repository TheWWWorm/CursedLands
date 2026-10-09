extends RefCounted
## Reconstruct only exact, two-family natural transitions. The source geometry,
## original tile codes and immutable colour cache are never changed.
const Tiles = preload("res://src/game/fx/terrain_transition_tiles.gd")
const TransitionShader = preload("res://src/game/fx/terrain_transition_shader.gd")
const MAX_TILES := 262144
# Authored signature order is NW, NE, SE, SW in the original atlas image.
# Terrain rows run toward negative Godot Z. These are the original tile-turn
# permutations, also asserted by R1 terrain_tile_blend_regression.cpp.
const CORNER_ORDER := [[3,2,0,1], [2,1,3,0], [1,0,2,3], [0,3,1,2]]
const NEIGHBOURS := [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1),
	Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
var tiles: ImageTexture
var tile_size := Vector2i.ZERO
var rows := PackedColorArray()
var donors := {}
var classified := 0
var admitted := 0
var conflicting := 0
var missing_donor := 0
var rejected_geometry := 0
var build_us := 0
var _shaders := {}


func _init(terrain: EITerrain = null, verified: Dictionary = {}) -> void:
	if terrain == null: return
	var start := Time.get_ticks_usec()
	_build(terrain, verified)
	build_us = Time.get_ticks_usec() - start


static func requested() -> bool:
	return DisplayServer.get_name() != "headless" and GameData.option("gfx_terrain") == 2


static func ground_allowed(type_id: int) -> bool:
	# Ground/dirt may be authored paths. Paving, liquids and unknown types
	# stay original, including when an atlas is otherwise recognized.
	return type_id in [0,2,3,9,11,12,15]


static func world_corners(signature: PackedByteArray, rotation: int) -> PackedByteArray:
	var result := PackedByteArray()
	if signature.size() != 4 or rotation < 0 or rotation > 3: return result
	for index: int in CORNER_ORDER[rotation]: result.append(signature[index])
	return result


func _build(terrain: EITerrain, verified: Dictionary) -> void:
	tile_size = Vector2i(terrain.sectors_x * 16, terrain.sectors_y * 16)
	var count := tile_size.x * tile_size.y
	var vertex_count := (tile_size.x * 2 + 1) * (tile_size.y * 2 + 1)
	if count <= 0 or count > MAX_TILES or tile_size.x <= 0 or tile_size.y <= 0 \
		or terrain.texture_size != 512 or terrain.tile_size != 64 \
		or terrain.grid_w != tile_size.x * 2 + 1 or terrain.heights.size() != vertex_count \
		or terrain.land_xy.size() != vertex_count or terrain.land_n.size() != vertex_count \
		or terrain.land_tile.size() != count: return
	var rules := verified.duplicate()
	if rules.is_empty():
		for atlas in clampi(int(terrain.get_meta("textures_count", 0)), 0, 256):
			var corners := Tiles.corners(GameData.load_image("%s%03d" % [terrain.resource_prefix, atlas]))
			if not corners.is_empty(): rules[atlas] = corners
	var corners := PackedByteArray(); corners.resize(count * 4)
	var shared := PackedByteArray(); shared.resize((tile_size.x + 1) * (tile_size.y + 1))
	var uses := {}
	for i in count:
		var code := terrain.land_tile[i]
		if code < 0 or code > 65535: continue
		var slot := code & 16383
		var atlas := slot >> 6
		if slot >= terrain.tile_types.size() or not ground_allowed(terrain.tile_types[slot]) \
			or not rules.has(atlas) or rules[atlas].size() != 256: continue
		var authored: PackedByteArray = rules[atlas].slice((slot & 63) * 4, ((slot & 63) + 1) * 4)
		if authored.has(0): continue
		var local := world_corners(authored, code >> 14)
		var tx := i % tile_size.x; var ty := int(i / tile_size.x)
		for k in 4:
			corners[i * 4 + k] = local[k]
			var vertex := (ty + (k >> 1)) * (tile_size.x + 1) + tx + (k & 1)
			if shared[vertex] == 0: shared[vertex] = local[k]
			elif shared[vertex] != local[k]: shared[vertex] = 255
		if local.count(local[0]) == 4:
			uses[slot] = int(uses.get(slot, 0)) + 1
	# Own-family donors must actually appear as plain tiles on this map.
	# Equal use counts choose the lower original atlas slot deterministically.
	for slot: int in uses:
		var family: int = rules[slot >> 6][(slot & 63) * 4]
		var previous: int = donors.get(family, -1)
		if previous < 0 or uses[slot] > uses[previous] or (uses[slot] == uses[previous] and slot < previous): donors[family] = slot
	rows.resize(count); rows.fill(Color(0,0,0,0))
	for i in count:
		if corners[i * 4] == 0: continue
		var local := corners.slice(i * 4, i * 4 + 4)
		var a := int(local[0]); var b := a
		for value in local: a = mini(a, value); b = maxi(b, value)
		if local.count(a) + (local.count(b) if a != b else 0) != 4: continue
		if a != b: classified += 1
		if not donors.has(a) or not donors.has(b):
			if a != b: missing_donor += 1
			continue
		var tx := i % tile_size.x; var ty := int(i / tile_size.x)
		var consistent := true
		for k in 4:
			if shared[(ty + (k >> 1)) * (tile_size.x + 1) + tx + (k & 1)] == 255: consistent = false
		if not consistent:
			if a != b: conflicting += 1
			continue
		if a != b and not _valid_tile(terrain, tx * 2, ty * 2):
			rejected_geometry += 1
			continue
		var mask := 0
		for k in 4:
			if local[k] == b: mask |= 1 << k
		var donor_a: int = donors[a]; var donor_b: int = donors[b]
		var packed := mask | (terrain.tile_types[donor_a] << 12) | (terrain.tile_types[donor_b] << 16)
		rows[i] = Color(donor_a + 1, donor_b + 1, packed, a + b * 64)
		if a != b: admitted += 1
	if admitted == 0: return
	for i in count:
		var row := rows[i]
		if row.a == 0 or row.r == row.g: continue
		var cell := Vector2i(i % tile_size.x, int(i / tile_size.x))
		var packed := int(row.b)
		for k in NEIGHBOURS.size():
			if not _compatible(cell + NEIGHBOURS[k], int(row.a)): packed |= 1 << (k + 4)
		row.b = packed; rows[i] = row
	tiles = ImageTexture.create_from_image(Image.create_from_data(tile_size.x, tile_size.y, false, Image.FORMAT_RGBAF, rows.to_byte_array()))


func _compatible(cell: Vector2i, pair: int) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= tile_size.x or cell.y >= tile_size.y: return false
	var other := int(rows[cell.y * tile_size.x + cell.x].a)
	if other == pair: return true
	var family := other & 63
	return family > 0 and family == (other >> 6) and family in [pair & 63, pair >> 6]


func _valid_tile(terrain: EITerrain, x: int, y: int) -> bool:
	for dy in 3:
		for dx in 3:
			var i := (y + dy) * terrain.grid_w + x + dx
			if not terrain.land_n[i].is_finite() or terrain.land_n[i].length_squared() < 1e-8: return false
	for dy in 2:
		for dx in 2:
			var i := (y + dy) * terrain.grid_w + x + dx
			for tri: Vector3i in [Vector3i(i, i+1, i+terrain.grid_w), Vector3i(i+1, i+terrain.grid_w+1, i+terrain.grid_w)]:
				var points := PackedVector3Array()
				for j in [tri.x, tri.y, tri.z]:
					points.append(Vector3(float(j % terrain.grid_w) + terrain.land_xy[j].x, terrain.heights[j], -float(j / terrain.grid_w) - terrain.land_xy[j].y))
				if not points[0].is_finite() or not points[1].is_finite() or not points[2].is_finite() \
					or (points[1]-points[0]).cross(points[2]-points[0]).y <= 1e-7: return false
	return true


func source(original: String) -> String:
	return TransitionShader.source(original) if admitted > 0 else original


func shader(original: String) -> Shader:
	if not _shaders.has(original): _shaders[original] = Gfx.make_shader(source(original), true, true)
	return _shaders[original]


func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("transition_tiles", tiles)
