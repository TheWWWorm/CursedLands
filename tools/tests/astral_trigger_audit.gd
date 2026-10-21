extends Node
## Archive-only inventory of torch mechanisms and their original script users.
func _ready() -> void:
	var campaign:=CampaignMap.load_from(GameData.texts)
	var report:={"campaign":GameData.campaign_id,"torches":[],"briefings":[],"texts":{},"references":[],"zones":0}
	for zone:Dictionary in campaign.zones.values():
		report.zones+=1
		var file:=String(zone.get("mob",""));if not file.ends_with(".mob"):file+=".mob"
		var mob:=EIMob.load_bytes(GameData.read_file("maps/"+file))
		var ast:=ScriptParser.parse(mob.script_text)
		for name:String in ast.scripts:
			if range(2,7).any(func(n):return "b.skelet.fq%d"%n in str(ast.scripts[name]).to_lower()):report.references.append({"map":file,"script":name,"body":ast.scripts[name]})
		for obj:Dictionary in mob.objects:
			if obj.get("kind")!="LEVER" or not (String(obj.get("template","")).begins_with("stto") or String(obj.get("name","")).to_lower().contains("torch")):continue
			var scripts:=[]
			for name:String in ast.scripts:
				if str(ast.scripts[name]).contains(str(obj.nid)):scripts.append({"name":name,"body":ast.scripts[name]})
			report.torches.append({"zone":zone.id,"map":file,"object":obj,"scripts":scripts})
	for b:Dictionary in GameData.db.table("briefings"):
		var id:=String(b.get("name","")).to_lower()
		var txt:=GameData.text("briefing "+id)
		if "факел" in txt.to_lower() or "не заж" in txt.to_lower() or "скелет" in txt.to_lower() or id=="fq2":report.briefings.append({"row":b,"text":txt})
	for key:String in GameData.texts.entries:
		var txt:=GameData.text(key)
		if "факел" in txt.to_lower() or "fq2" in key.to_lower():report.texts[key]=txt
	FileAccess.open("user://astral-trigger-audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ASTRAL_TRIGGER_AUDIT ",report.zones," maps ",report.torches.size()," torch levers ",report.briefings.size()," related conversations")
	get_tree().quit()
