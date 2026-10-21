extends Node
## Inventory authored future-position/leader/time queries, including AddMob
## files outside the campaign's initial zone list. No script is executed.
func _ready() -> void:
	var names := ["GetFutureX", "GetFutureY", "GetLeader", "FixWorldTime", "RunWorldTime"]
	var report := {"campaign":GameData.campaign_id,"maps":0,"matches":[]}
	for file: String in GameFiles.files(GameData.root.path_join("maps")):
		if file.get_extension().to_lower()!="mob":continue
		var mob:=EIMob.load_bytes(GameData.read_file("maps/"+file))
		if mob==null:continue
		report.maps+=1
		var ast:=ScriptParser.parse(mob.script_text)
		for name:String in ast.scripts:
			var body:Dictionary=ast.scripts[name]
			var found:=names.filter(func(query):return str(body).contains(query))
			if not found.is_empty():report.matches.append({"file":file,"script":name,"queries":found,"body":body})
	FileAccess.open("user://script-query-census.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SCRIPT_QUERY_CENSUS ",report.maps," maps ",report.matches.size()," matching scripts")
	get_tree().quit()
