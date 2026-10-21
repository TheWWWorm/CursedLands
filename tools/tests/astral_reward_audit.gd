extends Node
## Inspect authored campaign placements and effective imported stats without spawning enemies.
func _ready():
	var campaign:=CampaignMap.load_from(GameData.texts)
	var report:={"campaign":GameData.campaign_id,"zones":[]}
	var add:=RegEx.new();add.compile('(?i)AddMob\\s*\\(\\s*"([^"\\n]+)"')
	for zone:Dictionary in campaign.zones.values():
		if zone.get("type")!="game":continue
		var pending:Array=[String(zone.get("mob",""))];var seen:={};var actors:=[]
		while not pending.is_empty():
			var file:String=pending.pop_back();file=file.to_lower()
			if not file.ends_with(".mob"):file+=".mob"
			if file.is_empty() or seen.has(file):continue
			seen[file]=true
			var mob:=EIMob.load_bytes(GameData.read_file("maps/"+file))
			for m:RegExMatch in add.search_all(mob.script_text):pending.append(m.get_string(1))
			for raw:Dictionary in mob.objects:
				if raw.get("kind")!="UNIT":continue
				var record:=CampaignState.map_unit_record(raw)
				var proto:=GameData.db.find("monster_prototypes",record.get("prototype",""))
				var race:=GameData.db.find("race_models",proto.get("base_race",""))
				var imported:Variant=Combat.mob_import(record,proto,race)
				if imported!=null:proto=imported[0]
				if proto.is_empty():continue
				var row:={"mob":file,"uid":record.get("nid"),"name":record.get("name",""),"prototype":proto.name,"title":GameUnit.unit_title(proto.name),"player":record.get("player",1),"position":str(record.get("position")),"imported":imported!=null}
				for key:String in ["hp","mana","absorption","to_hit","parry","damage_min","damage_max","tuning_actions","base_level","experience","loot","rare_loot","items","spells","weapon"]:row[key]=proto.get(key)
				row.quick_items=record.get("quick_items",[]);row.quest_items=record.get("quest_items",[])
				actors.append(row)
		report.zones.append({"id":zone.id,"mob":zone.get("mob"),"actors":actors})
	FileAccess.open("user://astral_reward_audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ASTRAL_REWARD_AUDIT ",report.zones.size()," zones")
	get_tree().quit()
