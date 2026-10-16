extends Node

func _ready() -> void:
	var campaign := CampaignMap.load_from(GameData.texts)
	var rows := []
	for z: Dictionary in campaign.zones.values():
		if not z.has("mpr"): continue
		rows.append({"id":z.id,"allod":z.allod,"map":z.mpr,"type":z.type,"entrances":z.exits.keys()})
	print("TRAILER_CATALOG ",JSON.stringify({"campaign":GameData.campaign_id,"zones":rows,"music":EIAudio.music_table()}))
	print("TRAILER_ENEMIES ",JSON.stringify(GameData.db.table("monster_prototypes").filter(func(r):return String(r.name).to_lower().begins_with("wolf") or String(r.name).to_lower().begins_with("orc") or String(r.name).to_lower().begins_with("boar")).map(func(r):return r.name)))
	for table in ["weapons","armors"]:
		print("TRAILER_ITEMS ",table," ",JSON.stringify(GameData.db.table(table).slice(0,15)))
	for table in ["human_prototypes","monster_prototypes"]:
		print("TRAILER_HEROES ",table," ",JSON.stringify(GameData.db.table(table).filter(func(r):return String(r.name) in ["Human Hero","Human Mercenary Warrior","Human Mercenary Mage"])))
	get_tree().quit()
