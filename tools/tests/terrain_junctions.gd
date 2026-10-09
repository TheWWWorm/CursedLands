extends Node
## Authoritative synthetic corner topology and binary metadata ownership.
## Actual production-shader seams/appearance have separate rendered fixtures.
const Field = preload("res://src/game/fx/terrain_transition.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func fixture(family_count := 4, rotation := 0, changes := {}) -> Dictionary:
	var terrain := EITerrain.new()
	terrain.sectors_x = 1; terrain.sectors_y = 1; terrain.grid_w = 33
	terrain.heights.resize(1089); terrain.land_xy.resize(1089)
	terrain.land_n.resize(1089); terrain.land_n.fill(Vector3.UP)
	terrain.land_tile.resize(256); terrain.tile_types.resize(64)
	var signatures := PackedByteArray(); signatures.resize(256)
	var vertices := PackedByteArray(); vertices.resize(17 * 17)
	for y in 17:
		for x in 17:
			vertices[y * 17 + x] = 1 if x < 8 else 2
			if y >= 8 and family_count > 2:
				vertices[y * 17 + x] = 3 if x < 8 else (43 if family_count == 4 else 1)
	for point: Vector2i in changes: vertices[point.y * 17 + point.x] = changes[point]
	var slots := {}
	var types := {1:0, 2:2, 3:3, 42:15, 43:9}
	for y in 16:
		for x in 16:
			var world := PackedByteArray()
			for k in 4: world.append(vertices[(y + (k >> 1)) * 17 + x + (k & 1)])
			var authored := PackedByteArray(); authored.resize(4)
			for k in 4: authored[Field.CORNER_ORDER[rotation][k]] = world[k]
			var key := authored.hex_encode()
			if not slots.has(key):
				var slot := slots.size(); slots[key] = slot
				check(slot < 64, "synthetic metadata fits one original atlas")
				for k in 4: signatures[slot * 4 + k] = authored[k]
				terrain.tile_types[slot] = types[world[0]] if world.count(world[0]) == 4 else 0
			terrain.land_tile[y * 16 + x] = int(slots[key]) | (rotation << 14)
	return {"terrain":terrain, "rules":{0:signatures}, "vertices":vertices}

func ids(row: Color) -> PackedByteArray:
	var result := PackedByteArray()
	for k in 4:
		var family := (int(row.r) >> (k * 6)) & 63
		if family > 0: result.append(family)
	return result

func corner_ids(row: Color) -> PackedByteArray:
	var families := ids(row)
	var result := PackedByteArray()
	for k in 4: result.append(families[(int(row.g) >> (k * 2)) & 3])
	return result

func influence(row: Color, p: Vector2) -> float:
	var bits := int(row.b) >> 20
	return lerpf(lerpf(float(bits & 1), float((bits >> 1) & 1), p.x),
		lerpf(float((bits >> 2) & 1), float((bits >> 3) & 1), p.x), p.y)

func field_weights(row: Color, p: Vector2) -> Dictionary:
	var corners := corner_ids(row)
	var result := {}
	var weights := [(1-p.x)*(1-p.y), p.x*(1-p.y), (1-p.x)*p.y, p.x*p.y]
	for k in 4: result[corners[k]] = float(result.get(corners[k], 0.0)) + weights[k]
	return result

func packing() -> void:
	var saw_old_rounding_loss := false
	for packed in [1, 8388607, 8388609, 11284609, 15728641, 16777215]:
		var exact: float = PackedFloat32Array([packed])[0]
		check(int(exact) == packed, "all 24 integer bits survive float32 upload " + str(packed))
		var old: float = PackedFloat32Array([exact + 0.5])[0]
		if int(old) != packed: saw_old_rounding_loss = true
	check(saw_old_rounding_loss, "regression control exposes old +0.5 packed-integer loss")
	var source := Field.TransitionShader.source(EITerrain.TERRAIN_SHADER, true)
	check(not source.contains("int(row.b+0.5)"), "junction-capable source decodes exact packed flags")
	check(source.count("uniform sampler2D transition_tiles") == 1, "junctions add no sampler")
	check(source.contains("textureSize(transition_tiles,0).y/2") and source.contains("size.y/=2"),
		"both metadata fetches bound logical land rows, excluding the appended plane")
	check(source.count("vec3 ground_sample(") == 1 and source.count("vec3 transition_pair_sample(") == 1,
		"one shared entry retains the accepted pair implementation")
	check(source.contains("float depth=mix(0.28,0.42,smoothstep(0.0,0.5,soft))"),
		"width follows continuous soft-family weight rather than top-two identity")
	check(source.contains("vec2 q=grid+0.28*guard*"), "generalized warp respects the shared support guard")
	check(Field.TransitionShader.JUNCTION_FUNCTIONS.contains("float transition_junction_noise(vec2 p)")
		and not Field.TransitionShader.JUNCTION_FUNCTIONS.contains("transition_noise("),
		"generalized warp and scores use stable integer lattice noise")
	check(Field.TransitionShader.FUNCTIONS.contains("vec4 h=fract(sin(q)*43758.5453)"),
		"accepted remote-pair noise stays unchanged")
	check(Field.TransitionShader.JUNCTION_FUNCTIONS.contains("uniform int transition_junction_materials = 4;")
		and Field.TransitionShader.JUNCTION_FUNCTIONS.contains("int material_count=transition_junction_materials;"),
		"internal default-four material loop uses its runtime bound")
	check(Field.TransitionShader.JUNCTION_FUNCTIONS.count("transition_pair_sample(") == 1
		and Field.TransitionShader.JUNCTION_FUNCTIONS.contains("if (blend<=0.0) { traits=legacy_traits; return legacy; }"),
		"one shared fallback call preserves exact zero-influence pair output")
	var bounded := true
	for i in 401:
		var distance := i * 0.001
		if 0.28 * smoothstep(0.15,0.40,distance) > distance + 1e-9: bounded = false
	check(bounded, "maximum guarded warp cannot cross an unsupported cardinal/diagonal neighbour")
	var contact := Field.TransitionShader.source(GroundContactShader.source(EIFigure.OBJECT_SHADER,true), true)
	check(contact.contains(Field.TransitionShader.JUNCTION_FUNCTIONS), "contact receives the identical junction implementation")
	check(EITerrain.TERRAIN_SHADER.count(Field.TransitionShader.TERRAIN_RELIEF) == 1,
		"exact terrain relief block matches once")
	check(GroundContactShader.source(EIFigure.OBJECT_SHADER,true).count(Field.TransitionShader.CONTACT_RELIEF) == 1,
		"exact contact relief block matches once")
	for code: String in [source, contact]:
		check(code.count("transition_relief_samples(tile,local,step_uv,dx,dy,left,right,down,up)") == 1
			and not code.contains(Field.TransitionShader.TERRAIN_RELIEF) and not code.contains(Field.TransitionShader.CONTACT_RELIEF),
			"junction source shares exactly one complete four-tap relief loop")
	var pair_source := Field.TransitionShader.source(EITerrain.TERRAIN_SHADER)
	check(not pair_source.contains("transition_relief_samples") and pair_source.contains(Field.TransitionShader.TERRAIN_RELIEF),
		"pair-only relief source remains exact without helper")

func coherent_fields() -> void:
	for count in [3, 4]:
		for turn in 4:
			var setup := fixture(count, turn)
			var terrain: EITerrain = setup.terrain
			var codes := terrain.land_tile.duplicate()
			var field := Field.new(terrain, setup.rules)
			check(field.junctions == 1 and field.admitted_families[count] == 1,
				"all families admitted at the authored junction %d turn %d" % [count, turn])
			check(field.rows[7 * 16 + 7].a == -count and field.families_at(7 * 16 + 7).size() == count,
				"junction retains every distinct family rather than its min/max pair")
			check(field.tiles.get_size() == Vector2(16,32) and field.junction_rows.size() == 256,
				"one bounded two-plane texture contains complete metadata")
			check(field.tiles.get_image().get_data_size() == 256 * 32, "exact 32-byte-per-tile storage")
			var image := field.tiles.get_image()
			for i in 256:
				var cell := Vector2i(i % 16, int(i / 16))
				var local := corner_ids(field.junction_rows[i])
				var expected := PackedByteArray()
				for k in 4: expected.append(setup.vertices[(cell.y + (k >> 1)) * 17 + cell.x + (k & 1)])
				check(local == expected, "metadata preserves original rotated corner ownership")
				check(image.get_pixel(cell.x, cell.y) == field.rows[i]
					and image.get_pixel(cell.x, cell.y + 16) == field.junction_rows[i], "RGBAF round-trip preserves every packed bit")
				var families := ids(field.junction_rows[i])
				for k in families.size():
					var encoded := int(field.rows[i].r) if k == 0 else int(field.rows[i].g)
					if k > 1: encoded = int(field.junction_rows[i][k]) & 32767
					check(encoded == int(field.donors[families[k]]) + 1, "every donor belongs to its exact authored family")
			check(terrain.land_tile == codes and terrain.heights.count(0.0) == 1089
				and terrain.land_xy.count(Vector2.ZERO) == 1089, "classification changes no geometry or rotations")
			# The influence field is shared at every edge, including diagonally
			# touched halo tiles, and is exactly zero beyond that halo.
			for y in range(5, 10):
				for x in range(5, 9):
					for t in [0.0, 0.2, 0.5, 0.9, 1.0]:
						check(is_equal_approx(influence(field.rows[y*16+x], Vector2(1,t)),
							influence(field.rows[y*16+x+1], Vector2(0,t))), "shared vertical influence edge")
			check(influence(field.rows[6*16+6], Vector2(1,1)) == 1.0
				and influence(field.rows[6*16+6], Vector2.ZERO) == 0.0, "diagonal one-vertex halo joins continuously")
			check(influence(field.rows[7], Vector2(0.5,0.5)) == 0.0, "remote two-family field has no junction influence")
			terrain.free()
	var pair_setup := fixture(2)
	var pair := Field.new(pair_setup.terrain, pair_setup.rules)
	check(pair.junctions == 0 and pair.junction_rows.is_empty() and pair.tiles.get_height() == 16,
		"pair-only map retains its original allocation")
	check(pair.source(EITerrain.TERRAIN_SHADER) == Field.TransitionShader.source(EITerrain.TERRAIN_SHADER),
		"pair-only map retains the exact accepted shader source")
	var mixed_setup := fixture()
	var mixed := Field.new(mixed_setup.terrain, mixed_setup.rules)
	for y in 5: check(mixed.rows[y*16+7] == pair.rows[y*16+7], "remote pair metadata unchanged")
	pair_setup.terrain.free(); mixed_setup.terrain.free()

func different_family_sets() -> void:
	for fourth in [false, true]:
		var changes := {Vector2i(7,7):1, Vector2i(8,7):2, Vector2i(9,7):42 if fourth else 43,
			Vector2i(7,8):3, Vector2i(8,8):43 if fourth else 3, Vector2i(9,8):1 if fourth else 43}
		if fourth:
			for y in range(11,14):
				for x in range(11,14): changes[Vector2i(x,y)] = 42
		var setup := fixture(4, 0, changes)
		var field := Field.new(setup.terrain, setup.rules)
		var left := 7*16+7; var right := left+1
		check(field.families_at(left).size() == (4 if fourth else 3)
			and field.families_at(right).size() == (4 if fourth else 3), "adjacent different family sets are both admitted")
		for t in [0.0,0.2,0.5,0.9,1.0]:
			var a := field_weights(field.junction_rows[left], Vector2(1,t))
			var b := field_weights(field.junction_rows[right], Vector2(0,t))
			for family in field.donors:
				check(is_equal_approx(float(a.get(family,0)), float(b.get(family,0))),
					"shared authored weights agree across ABC/BCD and ABCD/ABCE")
		var entering := field_weights(field.junction_rows[right], Vector2(0.000001,0.5))
		check(float(entering.get(42 if fourth else 43,0)) < 0.000002,
			"a new family enters the warped neighbour field continuously from zero")
		setup.terrain.free()

func guards() -> void:
	var center := 7*16+7
	for path in [false,true]:
		var setup := fixture()
		var terrain: EITerrain = setup.terrain
		if path: terrain.tile_types[terrain.land_tile[center-1] & 16383] = 1
		else: terrain.land_tile[center-1] = 63
		var field := Field.new(terrain,setup.rules)
		check(field.rows[center].a == -4 and field.rows[center-1].a == 0,
			"unsupported/path neighbour remains authored beside admitted junction")
		check((int(field.junction_rows[center].g) & (1<<8)) != 0,
			"general sampler guards unsupported/path shared edge")
		terrain.free()
	for nonfinite in [false,true]:
		var setup := fixture()
		var terrain: EITerrain = setup.terrain
		var vertex := 13*33+13 # interior of the pure NW neighbour, not shared
		if nonfinite: terrain.heights[vertex] = NAN
		else: terrain.land_xy[vertex] = Vector2(4,0)
		var field := Field.new(terrain,setup.rules)
		check(field.junctions == 1 and field.rejected_support_geometry > 0,
			"invalid plain geometry cannot support the junction warp")
		check(field.rows[6*16+6].a > 0 and field.junction_rows[6*16+6].r == 0,
			"invalid plain art retains legacy ownership but no generalized metadata")
		check((int(field.junction_rows[center].g) & (1<<12)) != 0,
			"invalid diagonal support retains original-art corner guard")
		terrain.free()
	var setup := fixture()
	var terrain: EITerrain = setup.terrain
	var base := Field.new(terrain,setup.rules)
	var donor := int(base.donors[43])
	for i in 256:
		if (terrain.land_tile[i] & 16383) == donor: terrain.land_tile[i] = 63
	var missing := Field.new(terrain,setup.rules)
	check(missing.rows[center].a == 0 and missing.missing_donor > 0,
		"missing fourth-family fill is never replaced with a related donor")
	terrain.free()

func _ready() -> void:
	packing()
	coherent_fields()
	different_family_sets()
	guards()
	print("TERRAIN_JUNCTIONS ", JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(1 if failures else 0)
