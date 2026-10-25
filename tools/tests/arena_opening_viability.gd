extends "../benchmarks/arena_roster_audit.gd"
## Broad opening guardrails over whole price cohorts, both orientations and
## two seeds. Ranged recruits are judged behind a frontline; tanks/hunters
## also screen ranged allies. This does not prescribe equal player win rates.
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("FAIL ",label)

func _ready()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="):GameData.campaign_roots[CampaignProfile.ASTRAL]=arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(),"full installed roster mounted")
	if not ArenaExpansion.mounted():get_tree().quit(1);return
	rank=0;seeds=[8519,16729]
	var native:=hash(GameData.db.tables)
	var roster:Array=Array(ArenaRules.ACTIVE_FAMILIES).duplicate();roster.append_array(ArenaExpansion.FAMILIES)
	var outcomes:=[]
	for family in [4,22,34,35]:
		var points:=0.0;var count:=0
		for opponent:int in roster:
			if opponent==family or ArenaRules.FAMILIES[opponent].cost!=ArenaRules.FAMILIES[family].cost:continue
			for context:String in (["line"] if family==4 else ["line","screen"]):
				var allies:=supports(family,opponent) if context=="line" else backline(family,opponent)
				for seed_value:int in seeds:
					for side in 2:
						var result:=await fight(family,opponent,allies,seed_value,side)
						check(result.winner in [-1,family,opponent] and result.time>0.0,"native mirrored fight completes")
						points+=1.0 if result.winner==family else 0.5 if result.winner==-1 else 0.0
						count+=1
		var rate:=points/count
		# A sling attacker needs a useful protected opening. Melee families
		# retain hard matchups; reject a return to near-universal team losses.
		check(rate>=(0.4 if family==4 else 0.25),"opening contribution across the entire price cohort: "+str(family))
		outcomes.append({"family":family,"points":points,"fights":count,"rate":rate})
	check(hash(GameData.db.tables)==native,"opening balance leaves campaign records intact")
	FileAccess.open("user://arena-opening-viability.json",FileAccess.WRITE).store_string(JSON.stringify(outcomes,"\t"))
	print("ARENA_OPENING_VIABILITY ",JSON.stringify({"checks":checks,"failures":failures,"cohorts":outcomes}))
	get_tree().quit(0 if failures.is_empty() else 1)
