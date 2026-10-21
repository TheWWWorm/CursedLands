extends Node
## Read-only authored placement census for the ally-alert investigation.
func _ready() -> void:
	var out:=[]
	for zone: Dictionary in CampaignMap.load_from(GameData.texts).zones.values():
		if zone.get("type","")!="game":continue
		var name:=String(zone.get("mob",zone.get("mpr","")))
		if name.is_empty():continue
		var mob:=EIMob.load_bytes(GameData.read_file("maps/"+name+".mob"))
		if mob==null:continue
		var rats:=mob.objects.filter(func(o):return "rat" in String(o.get("prototype","")).to_lower())
		if not rats.is_empty():out.append({"zone":zone.id,"mob":name,"rats":rats})
	FileAccess.open("user://rat-alert-map-census.json",FileAccess.WRITE).store_string(JSON.stringify(out,"\t"))
	print("RAT_CENSUS ",out.map(func(z):return {"zone":z.zone,"count":z.rats.size()}))
	get_tree().quit()
