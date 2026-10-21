extends Node
## Read-only identity and authored-layout evidence for the mine report.
func _ready() -> void:
	var id := "gz24k" if GameData.campaign_id == CampaignProfile.ASTRAL else "gz14k"
	var campaign := CampaignMap.load_from(GameData.texts)
	var zone := campaign.zone(id)
	var bytes := GameData.read_file("maps/%s.mob"%zone.get("mob",zone.mpr))
	var mob := EIMob.load_bytes(bytes)
	var objects := []
	for o: Dictionary in mob.objects:
		var p: Vector3 = o.get("position",Vector3.ZERO)
		objects.append({"id":o.get("nid",0),"kind":o.kind,"name":o.get("name",""),"template":o.get("template",""),
			"position":[p.x,p.y,p.z],"rotation":str(o.get("rotation",Vector3.ZERO)),"stats":o.get("stats",{}),
			"parts":o.get("parts",[]),"quests":o.get("quests",[]),"items":o.get("items",[])})
	var report := {"campaign":GameData.campaign_id,"zone":zone,"title":GameData.text("zone "+id),"objects":objects}
	report.races=GameData.db.table("race_models").map(func(r):return {"name":r.name,"speeds":r.get("speeds",[])})
	report.npcs=GameData.db.table("npcs").map(func(r):return {"name":r.name,"race":r.get("base_race",""),"tuning_move":r.get("tuning_move",1.0)})
	FileAccess.open("user://mine-scene.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	FileAccess.open("user://mine-script.txt",FileAccess.WRITE).store_string(mob.script_text)
	print("MINE_SCENE ",id," ",objects.size()," objects")
	get_tree().quit()
