extends Node
## Private, read-only authoring audit. Never package original dialogue or maps.
func _ready() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lore-evidence="): output = arg.trim_prefix("--lore-evidence=")
	assert(not output.is_empty())
	var campaign := CampaignMap.load_from(GameData.texts)
	var evidence := {"campaign":GameData.campaign_id,"language":RemakeText.lang,"zones":campaign.zones,"allods":campaign.allods,"objects":{},"scripts":{},"briefings":GameData.db.table("briefings"),"prototypes":GameData.db.table("monster_prototypes"),"texts":{}}
	for key: String in GameData.texts.entries:
		if key.get_slice(" ",0) in ["pers","briefing","zone","allod","quest","unit"]: evidence.texts[key] = GameData.text(key)
	for zone: Dictionary in campaign.zones.values():
		var name := String(zone.get("mob",""))
		if name.is_empty() or evidence.objects.has(name): continue
		var mob := EIMob.load_bytes(GameData.read_file("maps/"+name+".mob"))
		evidence.objects[name] = []
		for object: Dictionary in mob.objects:
			if object.kind == "UNIT": evidence.objects[name].append(object)
		evidence.scripts[name] = mob.script_text
	var file := FileAccess.open(output,FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(evidence,"\t"))
	file.close()
	print("LORE_EVIDENCE ",output)
	get_tree().quit()
