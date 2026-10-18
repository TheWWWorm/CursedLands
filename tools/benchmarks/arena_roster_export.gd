extends Node
## Reproducible native previews and combat inputs for Trials balance/art.
func _ready() -> void:
	var output := "user://roster-export"
	var portraits := "--portraits" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	var data := {"version": ArenaRules.VERSION, "families": [], "native": []}
	for row: Dictionary in GameData.db.table("monster_prototypes"):
		var id := String(row.get("name", ""))
		data.native.append({"id": id, "title": ArenaRules.title(id), "stats": ArenaUnitInfo.values(id), "proto": row,
			"race": GameData.db.find("race_models", str(row.get("base_race","")))})
	var seen := {}
	var preview := WikiPreview.new()
	if portraits:
		preview.fit_slot = true; preview.size = Vector2(384,384)
		add_child(preview)
	for family in ArenaRules.FAMILIES.size():
		var entry: Dictionary = ArenaRules.FAMILIES[family].duplicate(true)
		entry["ranks"] = []
		for rank in 3:
			var id := ArenaRules.prototype(family,rank)
			var row := ArenaRules.recruit_prototype(family,rank,GameData.db.find("monster_prototypes",id))
			var spells := []
			for spell: String in row.get("spells",[]): spells.append({"spec":spell,"parsed":Spells.parse(spell)})
			entry.ranks.append({"id":id,"title":ArenaRules.title(id),"stats":ArenaUnitInfo.values(id,null,family,rank),"spells":spells,"power":ArenaBotPlanner.power(family,rank)})
			if portraits and not seen.has(id):
				seen[id] = true
				preview.show_model({"kind":"creature","value":id},true)
				preview.turn_by(-0.4)
				for frame in 10: await get_tree().process_frame
				await RenderingServer.frame_post_draw
				preview.creature._vp.get_texture().get_image().save_png(output.path_join(id.validate_filename()+".png"))
		data.families.append(entry)
		print("ROSTER_EXPORT ", family, " ", entry.name)
	FileAccess.open(output.path_join("roster.json"),FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	preview.free()
	get_tree().quit()
