extends Node
## Read-only installed-map inventory for the native lever-use contract.
func _ready() -> void:
	var report := {'campaign':GameData.campaign_id,'maps':0,'levers':[]}
	var campaign := CampaignMap.load_from(GameData.texts)
	for zone: Dictionary in campaign.zones.values():
		var file := String(zone.get('mob',''))
		if not file.ends_with('.mob'): file += '.mob'
		var raw := GameData.read_file('maps/'+file)
		if raw.is_empty(): continue
		var mob := EIMob.load_bytes(raw)
		if mob==null: continue
		report.maps += 1
		var ast := ScriptParser.parse(mob.script_text)
		for o: Dictionary in mob.objects:
			if o.kind!='LEVER': continue
			var scripts := {}
			for name: String in ast.scripts:
				var body := str(ast.scripts[name])
				if str(int(o.nid)) in body and ('EnableLever' in body or 'SwitchLeverState' in body or 'GetLeverState' in body): scripts[name]=ast.scripts[name]
			report.levers.append({'zone':zone.id,'map':file,'id':int(o.nid),'template':o.get('template',''),'name':o.get('name',''),
				'states':int(o.get('lever_states',2)),'state':int(o.get('lever_state',0)),'cycled':int(o.get('lever_cycled',0)),
				'science':Array(o.get('lever_science',PackedInt32Array([1,0,0]))),'scripts':scripts})
	FileAccess.open('user://lever-interaction-census.json',FileAccess.WRITE).store_string(JSON.stringify(report,'\t'))
	print('LEVER_INTERACTION_CENSUS ',report.maps,' maps ',report.levers.size(),' mechanisms')
	get_tree().quit()
