extends Node
## Read-only census of installed authored clock calls, not a playthrough.
const P := preload("res://src/game/script/script_parser.gd")

func calls(value: Variant, out: Array) -> void:
	if value is Dictionary:
		for child in value.values(): calls(child,out)
	elif value is Array:
		if value.size()>=3 and value[0] is int and value[0] in [P.N_CALL,P.S_CALL] and value[1] is String:
			var args: Array = value[2]
			var clock_key: bool = args.size()>1 and args[1]==[P.N_STR,"gtime"]
			if value[1] in ["GetWorldTime","FixWorldTime","RunWorldTime"] or (value[1] in ["GSGetVar","GSSetVar","GSSetVarMax","GsSetVarMax","GSDelVar"] and clock_key):
				out.append({"command":value[1],"args":value[2]})
		for child in value: calls(child,out)

func _ready() -> void:
	var campaign := CampaignMap.load_from(GameData.texts)
	var rows: Array = []; var errors: Array = []; var scanned := 0
	for zone: Dictionary in campaign.zones.values():
		if not zone.has("mob"): continue
		var file := String(zone.mob)
		if not file.ends_with(".mob"): file+=".mob"
		var mob := EIMob.load_bytes(GameData.read_file("maps/"+file)); scanned+=1
		var ast := ScriptParser.parse(mob.script_text)
		if not ast.errors.is_empty(): errors.append({"zone":zone.id,"errors":ast.errors})
		for name: String in ast.scripts:
			var found: Array = []; calls(ast.scripts[name],found)
			if not found.is_empty(): rows.append({"zone":zone.id,"type":zone.type,"file":file,"script":name,"calls":found,"body":ast.scripts[name]})
	FileAccess.open("user://campaign-clock-inventory.json",FileAccess.WRITE).store_string(JSON.stringify({"campaign":GameData.campaign_id,"maps":scanned,"errors":errors,"scripts":rows},"\t"))
	print("CAMPAIGN_CLOCK_INVENTORY ",scanned," maps ",rows.size()," scripts ",errors.size()," parse errors")
	get_tree().quit(1 if not errors.is_empty() else 0)
