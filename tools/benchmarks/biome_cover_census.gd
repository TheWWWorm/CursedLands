extends Node
## Read-only authored zone/material/tree census for decorative cover placement.
func _ready() -> void:
	var campaign := CampaignMap.load_from(GameData.texts)
	var rows := []
	for zone: Dictionary in campaign.zones.values():
		if not zone.has("mpr"): continue
		var trees := {}
		var path := "maps/%s.mob" % zone.get("mob",zone.mpr)
		if GameFiles.exists(GameData.root.path_join(path)):
			var mob := EIMob.load_bytes(GameData.read_file(path))
			for object: Dictionary in mob.objects:
				var template := String(object.get("template","")).to_lower()
				if template.begins_with("nafltr"):
					var key := template+":"+str(object.get("parts",[]))
					trees[key] = int(trees.get(key,0))+1
		var row := {"id":zone.id,"map":zone.mpr,"allod":zone.get("allod",""),"sky":zone.get("sky",""),"weather":zone.get("weather",""),"trees":trees}
		rows.append(row)
		print("BIOME_ZONE ",JSON.stringify(row))
	var file := FileAccess.open("user://biome-census.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t")); file.close()
	get_tree().quit()
