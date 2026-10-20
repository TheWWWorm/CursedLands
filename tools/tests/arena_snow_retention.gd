extends Node
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL ",label)
func _ready() -> void:
	for option: Array in GameData.OPTIONS:
		if String(option[0]).begins_with("gfx_"): GameData.options[option[0]] = 0
	var terrain := ArenaTerrain.create(true)
	add_child(terrain)
	var soft := SoftGroundDeform.new(); soft.terrain = terrain
	terrain.add_child(soft); soft.set_process(false)
	for y in range(8,24):
		for x in range(8,24):
			soft._add_mark({"p":Vector2(x*2+1,y*2+1),"extent":Vector2(0.01,0.01),"angle":0.0,"time":soft._age})
	check(soft.tile_count()==256,"full arena clearing retains all 256 footprint tiles")
	check(soft.sectors.size()==4,"all four courtyard sectors survive crossing the old cap")
	check(soft.sectors.values().all(func(rec):return rec.tiles.size()==64 and rec.steps.size()==64),"oldest tracks survive in every sector")
	soft._process(0); soft._finish_mesh_jobs(true)
	check(soft.field._dense_sources.values().reduce(func(sum,tiles):return sum+tiles.size(),0)==256,"all retained tiles install through real mesh workers")
	var palette := soft.field.contact_colors()
	check(palette._slots.size()==256,"contact colour layers cover the complete installed clearing")
	soft._add_mark({"p":Vector2(49,49),"extent":Vector2(1,1),"angle":0.0,"time":soft._age})
	check(soft.tile_count()==256,"oversized edge contacts stay inside the bounded arena allocation")
	check(soft.sectors.values().all(func(rec):return rec.tiles.size()==64),"edge contacts cannot evict a previously walked patch")
	soft.clear(); terrain.queue_free(); await get_tree().process_frame
	print("ARENA_SNOW_RETENTION ",checks," checks; failures=",failures)
	TexUpscale.shutdown(); get_tree().quit(int(failures>0))
