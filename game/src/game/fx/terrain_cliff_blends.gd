extends RefCounted
## Side-project plain donors, never the painted transition itself. All
## materials retain their original, rotated world-corner assignments.
## Rows contain four donor codes + 1 (NW, NE, SW, SE); zero is unsupported.
const Natural = preload("res://src/game/fx/terrain_transition_tiles.gd")
const Transition = preload("res://src/game/fx/terrain_transition.gd")
const Tiles = preload("res://src/game/fx/terrain_cliff_tiles.gd")

static func supported(family: int) -> bool:
	return Tiles.supported(family)

static func ground_allowed(ground: int) -> bool:
	return ground >= 0 and ground <= 15 and not ground in [9,10,12,13,14]

static func build(terrain: EITerrain, rules: Dictionary) -> PackedColorArray:
	var width := terrain.sectors_x * 16
	var height := terrain.sectors_y * 16
	var rows := PackedColorArray(); rows.resize(width * height); rows.fill(Color(0,0,0,0))
	var corners := PackedByteArray(); corners.resize(rows.size() * 4)
	var shared := PackedByteArray(); shared.resize((width + 1) * (height + 1))
	var uses := {}; var donors := {}
	for i in rows.size():
		var code := terrain.land_tile[i]
		if code < 0 or code > 65535: continue
		var slot := code & 16383
		if slot >= terrain.tile_types.size() or not ground_allowed(terrain.tile_types[slot]) \
			or not rules.has(slot >> 6) or rules[slot >> 6].size() != 256: continue
		var authored: PackedByteArray = rules[slot >> 6].slice((slot & 63) * 4, ((slot & 63) + 1) * 4)
		var local := Transition.world_corners(authored, code >> 14)
		# Include known corners of neighbouring unsupported tiles in the agreement
		# check, but never turn those neighbours into eligible cliff artwork.
		for k in 4:
			if local[k] == 0: continue
			var at := (int(i / width) + (k >> 1)) * (width + 1) + i % width + (k & 1)
			if shared[at] == 0: shared[at] = local[k]
			elif shared[at] != local[k]: shared[at] = 255
		if not supported(local[0]) or not supported(local[1]) or not supported(local[2]) or not supported(local[3]): continue
		for k in 4: corners[i * 4 + k] = local[k]
		if local.count(local[0]) == 4: uses[slot] = int(uses.get(slot, 0)) + 1
	# Only plain donors actually used by this map are allowed. Use the most
	# common variant; a tie selects the lower original atlas slot.
	for slot: int in uses:
		var family: int = rules[slot >> 6][(slot & 63) * 4]
		var previous: int = donors.get(family, -1)
		if previous < 0 or uses[slot] > uses[previous] or (uses[slot] == uses[previous] and slot < previous): donors[family] = slot
	for i in rows.size():
		var local := corners.slice(i * 4, i * 4 + 4)
		if local[0] == 0: continue
		var families := Transition._families(local)
		var missing := false
		for family in families:
			if not donors.has(family): missing = true
		if missing: continue
		# Existing plain natural tiles retain their exact variant/rotation.
		if families.size() == 1 and not families[0] in [253,254]: continue
		var consistent := true
		for k in 4:
			var at := (int(i / width) + (k >> 1)) * (width + 1) + i % width + (k & 1)
			if shared[at] == 255: consistent = false
		if consistent: rows[i] = Color(donors[local[0]] + 1, donors[local[1]] + 1, donors[local[2]] + 1, donors[local[3]] + 1)
	return rows
