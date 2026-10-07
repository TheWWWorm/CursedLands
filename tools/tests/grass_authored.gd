extends "grass_chunks.gd"
## Real terrain triangles, authored atlas pixels and water/floor state.
func _ready() -> void:
	var campaign := CampaignMap.load_from(GameData.texts)
	var maps := ["gz16g", "gz7g", "gz21k"]
	var chunks := 0; var tufts := 0
	for id in maps:
		var zone: Dictionary = campaign.zone(id)
		if zone.is_empty(): continue
		var terrain := EITerrain.load_map(zone.mpr)
		check(terrain != null, "authored map " + id)
		if terrain == null: continue
		var details := terrain.details
		if details == null:
			details = TerrainDetails.new(); details.terrain = terrain; terrain.add_child(details)
		details._grass = true
		details.prepare_grass()
		check(details._grass_field != null, "authored field " + id)
		var size := Vector2i(terrain.size_ei() / TerrainDetails.CHUNK)
		var keys: Array[Vector2i] = [Vector2i.ZERO, size - Vector2i.ONE, size / 2]
		for exit: Dictionary in zone.exits.values():
			if exit.get("deploy") is Rect2:
				keys.append(Vector2i((exit.deploy as Rect2).get_center() / TerrainDetails.CHUNK))
		var rng := RandomNumberGenerator.new(); rng.seed = id.hash()
		for i in 12: keys.append(Vector2i(rng.randi_range(0, size.x - 1), rng.randi_range(0, size.y - 1)))
		for key in keys:
			var native := details.instances(key)
			var scalar := details.instances_script(key)
			equal(native, scalar, id + " " + str(key))
			chunks += 1; tufts += scalar.transforms.size()
		terrain.free()
	check(chunks >= 30 and tufts > 500, "authored coverage includes growing terrain")
	print("GRASS_AUTHORED checks=",checks," failures=",failures," chunks=",chunks," tufts=",tufts)
	get_tree().quit(1 if failures else 0)
