extends Node
## Read-only original campaign emitter inventory for lighting qualification.
func _ready() -> void:
	var out:="user://path-light-inventory"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
	DirAccess.make_dir_recursive_absolute(out)
	var campaign:=CampaignMap.load_from(GameData.texts);var entries:=[]
	for zone: Dictionary in campaign.zones.values():
		if zone.get("type","")!="game":continue
		var name:=String(zone.get("mob",zone.get("mpr","")))
		var bytes:=GameData.read_file("maps/"+name+".mob")
		if bytes.is_empty():continue
		var mob:=EIMob.load_bytes(bytes);var torches:=[]
		for record: Dictionary in mob.objects:
			if record.get("kind","")=="TORCH":
				torches.append({"nid":record.get("nid"),"position":str(record.get("position")),
					"strength":record.get("torch_strength"),"offset":str(record.get("torch_offset")),"template":record.get("template")})
		var entry:={"zone":zone.id,"map":name,"sky":zone.get("sky"),"entrances":zone.exits.keys(),"torches":torches}
		entries.append(entry)
		print("LIGHT_INVENTORY ",zone.id," ",zone.get("sky")," ",torches.size())
	FileAccess.open(out.path_join("path-light-inventory.json"),FileAccess.WRITE).store_string(JSON.stringify(entries,"\t"))
	get_tree().quit()
