extends Node
## Read-only census of objective chains authored in the installed quest maps.
func _ready() -> void:
	var report := {"campaign":GameData.campaign_id,"quests":[]}
	for q: Dictionary in SideQuests.all():
		var mob := EIMob.load_bytes(GameData.read_file("maps/" + q.id + ".mob"))
		if mob == null: continue
		var source := mob.script_text
		var lines := []
		for line: String in source.split("\n"):
			if "QStart" in line or "QObj" in line or "QFinish" in line: lines.append(line.strip_edges())
		report.quests.append({"id":q.id,"map":q.mpr,"reg":q.reg,"calls":lines,
			"script":source,"objects":mob.objects})
	FileAccess.open("user://quest-objective-census.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("QUEST_OBJECTIVE_CENSUS ", report.quests.size(), " archives")
	get_tree().quit()
