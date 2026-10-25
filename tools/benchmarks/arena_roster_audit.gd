extends "arena_context_balance.gd"
## Full same-price roster scan, including optional Astral recruits. Mirror each
## pairing and retain actual fights; these are diagnostic policies, not win-rate
## guarantees. Set --rank=0/1/2, --seeds=... and --contexts=duel,line,screen.
func backline(a:int,b:int)->Array:
	var candidates:=ArenaRules.ACTIVE_FAMILIES.filter(func(f):
		return f!=a and f!=b and ArenaRules.recruit_role(f,rank)!="Melee")
	var price:int=ArenaRules.FAMILIES[a].cost
	candidates.sort_custom(func(x,y):
		var dx:=absi(int(ArenaRules.FAMILIES[x].cost)-price)
		var dy:=absi(int(ArenaRules.FAMILIES[y].cost)-price)
		return dx<dy if dx!=dy else x<y)
	return candidates.slice(0,2)

func army(company:ArenaRun,family:int,allies:Array)->void:
	super.army(company,family,allies)
	for entry:Dictionary in company.army:
		if entry.family!=family and ArenaRules.recruit_role(entry.family,rank)!="Melee":entry.point[0]=22.0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="):
			GameData.campaign_roots[CampaignProfile.ASTRAL]=arg.trim_prefix("--astral-path=")
		elif arg.begins_with("--rank="):rank=int(arg.get_slice("=",1))
		elif arg.begins_with("--seeds="):seeds=Array(arg.get_slice("=",1).split(",")).map(func(s):return int(s))
		elif arg.begins_with("--contexts="):contexts=Array(arg.get_slice("=",1).split(","))
		elif arg.begins_with("--families="):families=Array(arg.get_slice("=",1).split(",")).map(func(s):return int(s))
	var roster:Array=Array(ArenaRules.ACTIVE_FAMILIES).duplicate()
	if GameData.campaign_roots.has(CampaignProfile.ASTRAL):
		if not ArenaExpansion.mount():printerr("FAIL Astral roster unavailable");get_tree().quit(1);return
		roster.append_array(ArenaExpansion.FAMILIES)
	var native:=hash(GameData.db.tables)
	for a:int in roster:
		for b:int in roster:
			if b<=a or ArenaRules.FAMILIES[a].cost!=ArenaRules.FAMILIES[b].cost:continue
			if not families.is_empty() and a not in families and b not in families:continue
			for context:String in contexts:
				var allies:=supports(a,b) if context=="line" else backline(a,b) if context=="screen" else []
				var row:={"a":a,"b":b,"rank":rank,"cost":ArenaRules.FAMILIES[a].cost,"context":context,"supports":allies,"trials":[]}
				for seed_value:int in seeds:
					for side in 2:row.trials.append(await fight(a,b,allies,seed_value,side))
				rows.append(row)
				FileAccess.open("user://arena-roster-audit.json",FileAccess.WRITE).store_string(JSON.stringify(rows))
				print("ROSTER_AUDIT ",a," ",b," ",context," ",row.trials.map(func(t):return t.winner))
	print("ROSTER_AUDIT_COMPLETE rows=",rows.size()," fights=",rows.size()*seeds.size()*2," native_unchanged=",hash(GameData.db.tables)==native)
	get_tree().quit(0 if not rows.is_empty() and hash(GameData.db.tables)==native else 1)
