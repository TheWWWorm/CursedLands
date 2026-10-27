extends "biome_cover.gd"
## The additional sand/snow piles are removed; authored terrain stays intact.
func _ready() -> void:
	GameData.options.merge(GfxDetect.original_look_values(true, {}, -1), true)
	GameData.options.gfx_biome_cover = 1
	var field := Cover.new()
	for biome in ["gipat", "ingos", "suslanger", "cave"]:
		field.biome = biome
		for type in [0,1,2,3,4,5,9,11,12]:
			var chance: float = field.weights({"type":type,"colour":Color(0.4,0.3,0.2)},Vector3.ZERO,Vector3.ZERO)[Cover.Kind.STONE]
			var previous := 0.12 if type in [1,2,4,5,11] else 0.025
			check(is_equal_approx(chance, previous*0.5), "half the added stones in %s terrain %d" % [biome,type])
	var campaign := CampaignMap.load_from(GameData.texts)
	var zones := ["bz2h"] if GameData.campaign_id == "lost_in_astral" else ["bz1g", "gz14k"]
	for id: String in zones:
		var zone := campaign.zone(id)
		check(not zone.is_empty(), "authored test zone " + id)
		var world := GameWorld.new(); world.zone = zone
		var map := EIMapScene.new(); world.add_child(map)
		map.terrain = EITerrain.load_map(zone.mpr); map.add_child(map.terrain)
		map.mob = EIMob.load_bytes(GameData.read_file("maps/%s.mob" % zone.get("mob",zone.mpr)))
		var t := map.terrain
		var heights := t.heights.duplicate(); var normals := t.land_n.duplicate()
		var objects := map.mob.objects.duplicate(true)
		var d := t.details; d.prepare_grass()
		field = d._cover_field
		check(not field.mounds.enabled, "no generated sand/snow piles in " + id)
		var count := 0
		for y in ceili(field.size.y/8.0):
			for x in ceili(field.size.x/8.0): count += field.mounds.records(field,Vector2i(x,y),[]).size()
		check(count == 0, "all chunks omit added piles in " + id)
		check(t.heights == heights and t.land_n == normals, "authored terrain shape is unchanged in " + id)
		check(map.mob.objects == objects, "authored objects and rocks are unchanged in " + id)
		print("GROUND_COVER_MAP ",id," mounds=",count)
		world.free()
	print("GROUND_COVER_DENSITY checks=",checks," failures=",failures)
	TexUpscale.shutdown(); get_tree().quit(1 if failures else 0)
