extends "res://tools/tests/terrain_snow_contours.gd"
## Recreate identical cliffs, then alter each family of inputs. Never cache
## mutable field/geometry owners or let one world's edits change another.
func _ready() -> void:
	var factory: RefCounted = Field.new()
	if not factory.has_method("create"):
		check(false, "cliff generation is reusable across world loads")
		finish(); return
	var cache: Script = load("res://src/game/fx/terrain_cliff_cache.gd")
	cache.clear()
	var terrain := fixture(0)
	for y in 33:
		for x in 33: terrain.heights[y*33+x] = 16.0 if x+y >= 32 else 0.0
	var source := source_mesh(terrain)
	var sector := EITerrainSector.new()
	sector.configure(source, StandardMaterial3D.new(), 6, false); terrain.add_child(sector)
	var first: RefCounted = factory.call("create", terrain, rules())
	sector.set_cliff_geometry(first.geometry)
	first.retain()
	var expected: Array = first.geometry.arrays(source)
	var texture: Texture2D = first.tiles
	check(not first.reused and first.geometry.refined_triangles > 0, "first load actually generates curved cliff patches")
	var second: RefCounted = factory.call("create", terrain, rules())
	check(second.reused and second.build_us == 0 and second.tiles == texture, "repeat load restores prepared geometry and immutable textures")
	check(second != first and second.geometry != first.geometry, "worlds have distinct field and geometry owners")
	check(second.geometry.arrays(source) == expected, "restored raster and PT geometry is byte-identical in every channel")
	first.geometry.patches.clear(); first.geometry._prepared.clear(); first.eligible.fill(0)
	first._shaders["test"] = Shader.new()
	check(second.geometry.arrays(source) == expected and second.eligible.count(255) > 0 and second._shaders.is_empty(),
		"mutating one world cannot affect restored geometry or shaders")
	var original_key: String = cache.key(terrain, rules())
	for property in ["heights", "land_xy", "land_n", "land_tile", "tile_types"]:
		var before: Variant = terrain.get(property).duplicate()
		var changed: Variant = before.duplicate()
		match property:
			"heights": changed[544] += 1.0
			"land_xy": changed[544] += Vector2(.125, 0)
			"land_n": changed[544] = Vector3(.6, .8, 0)
			"land_tile": changed[0] = 1
			"tile_types": changed[0] = 9
		terrain.set(property, changed)
		check(cache.key(terrain, rules()) != original_key and not factory.call("create", terrain, rules()).reused,
			"changed " + property + " requires a fresh field")
		terrain.set(property, before)
	for property in ["texture_size", "tile_size", "grid_w"]:
		var before: int = terrain.get(property)
		terrain.set(property, before + 1)
		check(cache.key(terrain, rules()) != original_key, "sampling layout invalidates " + property)
		terrain.set(property, before)
	var saved_colour: Color = source[Mesh.ARRAY_COLOR][0]
	source[Mesh.ARRAY_COLOR][0] = Color(.1, .2, .3, .4)
	check(cache.key(terrain, rules()) != original_key, "underwater source colour invalidates interpolated patch colours")
	source[Mesh.ARRAY_COLOR][0] = saved_colour
	var unknown := rules(); unknown[0].fill(0)
	check(cache.key(terrain, unknown) != original_key and not factory.call("create", terrain, unknown).reused,
		"changed verified artwork cannot reuse known cliffs")
	var weak_field: WeakRef = weakref(first); var weak_world: WeakRef = weakref(terrain)
	first = null; terrain.free()
	check(weak_field.get_ref() == null and weak_world.get_ref() == null, "cache retains no previous field or world")
	var snow := snow_fixture()
	check(snow != null, "original snow artwork supplies the cache case")
	if snow != null:
		var snow_source := source_mesh(snow)
		var snow_sector := EITerrainSector.new()
		snow_sector.configure(snow_source,StandardMaterial3D.new(),6,false); snow.add_child(snow_sector)
		var original_snow: RefCounted = factory.call("create",snow)
		snow_sector.set_cliff_geometry(original_snow.geometry); original_snow.retain()
		var cached_snow: RefCounted = factory.call("create",snow)
		check(cached_snow.reused and cached_snow.geometry != original_snow.geometry,
			"snow rounding is restored into a private geometry owner")
		check(cached_snow.geometry.arrays(snow_source) == original_snow.geometry.arrays(snow_source),
			"cached snow retains exact bevels, edge normals and contour channels")
		snow.free()
	var flat := fixture(0)
	var neutral: RefCounted = factory.call("create",flat,rules()); neutral.retain()
	var neutral_copy: RefCounted = factory.call("create",flat,rules())
	check(neutral_copy.reused and neutral_copy.geometry == null and neutral_copy.tiles == null,
		"unsupported or flat geometry reuses its neutral result without GPU assets")
	flat.free()
	cache.clear()
	for i in 3: cache.store_entry(str(i), {"bytes": 1, "data": var_to_bytes({}), "textures": []})
	check(cache.entries.size() == 2 and not cache.entries.has("0"), "entry limit evicts the oldest map")
	cache.take("1")
	cache.store_entry("3", {"bytes": 1, "data": var_to_bytes({}), "textures": []})
	check(cache.entries.has("1") and not cache.entries.has("2"), "using a retained map refreshes its LRU position")
	cache.clear()
	for i in 3: cache.store_entry(str(i), {"bytes": cache.MAX_BYTES/2 + 1, "data": var_to_bytes({}), "textures": []})
	check(cache.entries.size() == 1 and cache.bytes <= cache.MAX_BYTES, "byte budget bounds retained derived geometry")
	cache.store_entry("oversize", {"bytes": cache.MAX_BYTES + 1, "data": var_to_bytes({}), "textures": []})
	check(not cache.entries.has("oversize"), "oversized maps are not retained")
	check(second.geometry.arrays(source) == expected and texture.get_image() != null, "eviction cannot invalidate a live world")
	cache.clear(); finish()
func finish() -> void:
	print("TERRAIN_CLIFF_REUSE ", checks, " checks ", failures, " failures")
	get_tree().quit(int(failures > 0))
