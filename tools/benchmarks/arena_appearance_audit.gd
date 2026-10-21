extends Node
## Read the original map appearances, prototype strength and localized names.
func _ready() -> void:
	var output := "user://arena-appearance-audit.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	var placed := {}
	var maps := GameData.root.path_join("maps")
	var files := DirAccess.get_files_at(maps)
	files.sort()
	for file: String in files:
		if not file.ends_with(".mob"): continue
		var mob := EIMob.load_bytes(FileAccess.get_file_as_bytes(maps.path_join(file)))
		for object: Dictionary in mob.objects:
			var id := String(object.get("prototype", object.get("parent_template", ""))).to_lower()
			if id.is_empty() or String(object.get("texture", "")).is_empty(): continue
			if not placed.has(id): placed[id] = {}
			var key := String(object.texture)
			if not placed[id].has(key): placed[id][key] = {"count":0,"sample_map":file,"sample_nid":object.get("nid",0),"template":object.get("template", "")}
			placed[id][key].count += 1
	var families := []
	for family: int in ArenaAppearance.RANK_PALETTES:
		var ranks := []
		for rank in 3:
			var id := ArenaRules.prototype(family,rank)
			var donor := ArenaAppearance.name_prototype(id,family,rank)
			var proto := GameData.db.find("monster_prototypes",donor)
			var names := {}
			for language: String in ["en","ru","de"]:
				RemakeText.lang = language
				names[language] = ArenaRules.title(id,family,rank)
			ranks.append({"rank":rank+1,"combat_prototype":id,"name_prototype":donor,"texture":ArenaAppearance.info(id,family,rank).texture,"native_level":proto.base_level,"native_hp":proto.hp,"native_damage_max":proto.damage_max,"native_appearances":placed.get(donor,{}),"names":names})
		families.append({"family":family,"name":ArenaRules.FAMILIES[family].name,"ranks":ranks})
	RemakeText.lang = "en"
	var result := {"families":families,"all_native_appearances":placed}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ARENA_APPEARANCE_AUDIT ", families.size(), " families; ", placed.size(), " original placed prototypes")
	get_tree().quit()
