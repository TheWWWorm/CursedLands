extends RefCounted
## Reconstruct only exact, authored natural transitions. The source geometry,
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
## Present only on maps with admitted junctions; appended below the legacy
## rows in the same texture. Each integer occupies at most 24 exact float bits.
var junction_rows := PackedColorArray()
var donors := {}
var classified := 0
var admitted := 0
var conflicting := 0
var missing_donor := 0
var rejected_geometry := 0
var junctions := 0
var rejected_support_geometry := 0
var admitted_families := {2:0, 3:0, 4:0}
var build_us := 0
var _shaders := {}
var _pair_sectors := {}


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
		var supported := true
		for family in authored:
			if family == 0 or family >= 64: supported = false
		if not supported: continue
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
		var families := _families(local)
		var mixed := families.size() > 1
		var a := int(families[0]); var b := int(families[mini(1, families.size() - 1)])
		if mixed: classified += 1
		var missing := false
		for family in families:
			if not donors.has(family): missing = true
		if missing:
			if mixed: missing_donor += 1
			continue
		var tx := i % tile_size.x; var ty := int(i / tile_size.x)
		var consistent := true
		for k in 4:
			if shared[(ty + (k >> 1)) * (tile_size.x + 1) + tx + (k & 1)] == 255: consistent = false
		if not consistent:
			if mixed: conflicting += 1
			continue
		if mixed and not _valid_tile(terrain, tx * 2, ty * 2):
			rejected_geometry += 1
			continue
		var mask := 0
		for k in 4:
			if local[k] == b: mask |= 1 << k
		var donor_a: int = donors[a]; var donor_b: int = donors[b]
		var packed := mask | (terrain.tile_types[donor_a] << 12) | (terrain.tile_types[donor_b] << 16)
		rows[i] = Color(donor_a + 1, donor_b + 1, packed, a + b * 64 if families.size() <= 2 else -families.size())
		if mixed:
			admitted += 1
			admitted_families[families.size()] += 1
			if families.size() > 2: junctions += 1
	if admitted == 0: return
	for i in count:
		var row := rows[i]
		if row.a <= 0 or row.r == row.g: continue
		var cell := Vector2i(i % tile_size.x, int(i / tile_size.x))
		var packed := int(row.b)
		for k in NEIGHBOURS.size():
			if not _compatible(cell + NEIGHBOURS[k], int(row.a)): packed |= 1 << (k + 4)
		row.b = packed; rows[i] = row
	if junctions > 0: _build_junction_rows(terrain, corners)
	var pixels := rows.to_byte_array()
	if junctions > 0: pixels.append_array(junction_rows.to_byte_array())
	tiles = ImageTexture.create_from_image(Image.create_from_data(tile_size.x, tile_size.y * (2 if junctions > 0 else 1), false, Image.FORMAT_RGBAF, pixels))


static func _families(corners: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	for family in corners:
		if not result.has(family): result.append(family)
	result.sort()
	return result


func families_at(index: int) -> PackedByteArray:
	if index < 0 or index >= rows.size() or rows[index].a == 0: return PackedByteArray()
	if rows[index].a > 0:
		var pair := int(rows[index].a)
		return PackedByteArray([pair & 63]) if (pair & 63) == (pair >> 6) else PackedByteArray([pair & 63, pair >> 6])
	var packed := int(junction_rows[index].r)
	var result := PackedByteArray()
	for k in -int(rows[index].a): result.append((packed >> (k * 6)) & 63)
	return result


func _build_junction_rows(terrain: EITerrain, corners: PackedByteArray) -> void:
	var count := rows.size()
	var vertices := PackedByteArray(); vertices.resize((tile_size.x + 1) * (tile_size.y + 1))
	for i in count:
		if rows[i].a >= 0: continue
		for k in 4:
			vertices[(int(i / tile_size.x) + (k >> 1)) * (tile_size.x + 1) + i % tile_size.x + (k & 1)] = 1
	var support := PackedByteArray(); support.resize(count)
	var valid := PackedByteArray(); valid.resize(count)
	for i in count:
		if rows[i].a == 0: continue
		valid[i] = 1
		var influence := 0
		for k in 4:
			influence |= int(vertices[(int(i / tile_size.x) + (k >> 1)) * (tile_size.x + 1) + i % tile_size.x + (k & 1)]) << k
		var row := rows[i]; row.b = int(row.b) | (influence << 20); rows[i] = row
		if influence == 0 or row.r == row.g: continue
		# The bounded warp can read the next tile past the one-tile halo.
		# Plain receivers remain original, but folded/nonfinite support must
		# not feed a new field across a mixed receiver's edge.
		var cell := Vector2i(i % tile_size.x, int(i / tile_size.x))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var other := cell + Vector2i(dx, dy)
				if _inside(other): support[other.y * tile_size.x + other.x] = 1
	for i in count:
		if valid[i] == 1 and support[i] == 1 and rows[i].r == rows[i].g \
			and not _valid_tile(terrain, (i % tile_size.x) * 2, int(i / tile_size.x) * 2):
			valid[i] = 0
			rejected_support_geometry += 1
	junction_rows.resize(count); junction_rows.fill(Color(0,0,0,0))
	for i in count:
		if valid[i] == 0: continue
		var local := corners.slice(i * 4, i * 4 + 4)
		var families := _families(local)
		var packed_families := 0; var packed_corners := 0
		for k in families.size(): packed_families |= int(families[k]) << (k * 6)
		for k in 4: packed_corners |= families.find(local[k]) << (k * 2)
		var cell := Vector2i(i % tile_size.x, int(i / tile_size.x))
		for k in NEIGHBOURS.size():
			var other: Vector2i = cell + NEIGHBOURS[k]
			if not _inside(other) or valid[other.y * tile_size.x + other.x] == 0:
				packed_corners |= 1 << (k + 8)
		var extra := [0, 0]
		for k in range(2, families.size()):
			var donor: int = donors[families[k]]
			extra[k - 2] = (donor + 1) | (terrain.tile_types[donor] << 15)
		# R: four exact six-bit family IDs; G: four two-bit corner indices
		# and eight art-edge guards; B/A: third/fourth donor + 1 and type.
		junction_rows[i] = Color(packed_families, packed_corners, extra[0], extra[1])


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < tile_size.x and cell.y < tile_size.y


func _compatible(cell: Vector2i, pair: int) -> bool:
	if not _inside(cell): return false
	var other := int(rows[cell.y * tile_size.x + cell.x].a)
	if other <= 0: return false
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


## Classification is immutable map metadata, cached once per requested
## sector. The extra tile covers all four painted-relief offsets, including
## fragments at sector edges. Unsupported/unknown fields keep the full path.
func pair_sector_allowed(origin: Vector2i) -> bool:
	if admitted == 0 or junctions == 0 or rows.size() != tile_size.x * tile_size.y \
		or origin.x < 0 or origin.y < 0 or origin.x % 16 != 0 or origin.y % 16 != 0 \
		or origin.x + 16 > tile_size.x or origin.y + 16 > tile_size.y:
		return false
	if _pair_sectors.has(origin): return _pair_sectors[origin]
	for y in range(maxi(0, origin.y - 1), mini(tile_size.y, origin.y + 17)):
		for x in range(maxi(0, origin.x - 1), mini(tile_size.x, origin.x + 17)):
			if ((int(rows[y * tile_size.x + x].b) >> 20) & 15) != 0:
				_pair_sectors[origin] = false
				return false
	_pair_sectors[origin] = true
	return true


func source(original: String, pair_only := false) -> String:
	return TransitionShader.source(original, junctions > 0, pair_only) if admitted > 0 else original


func shader(original: String, pair_only := false) -> Shader:
	var key := str(int(pair_only)) + original
	if not _shaders.has(key): _shaders[key] = Gfx.make_shader(source(original, pair_only), true, true)
	return _shaders[key]


func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("transition_tiles", tiles)
