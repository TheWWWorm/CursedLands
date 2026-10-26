extends "../benchmarks/arena_roster_audit.gd"
## Same-price mirrored teams: preserve counters and reject near-universal wins.
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); printerr("FAIL ",label)
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL]=arg.trim_prefix("--astral-path=")
	check(ArenaExpansion.mount(), "installed opponents available")
	if not ArenaExpansion.mounted(): finish(); return
	var native := hash(GameData.db.tables)
	var outcomes := []
	for star in 3:
		rank=star
		for family in [19,35,38]:
			var points:=0.0; var count:=0
			for opponent: int in ArenaRules.active_families(true):
				if opponent==family or ArenaRules.FAMILIES[opponent].cost != ArenaRules.FAMILIES[family].cost: continue
				# Bow units need a frontline; a caster should also be answerable
				# when both players invest in ranged allies.
				for context in (["line"] if family==38 else ["line","screen"]):
					var allies := supports(family,opponent) if context=="line" else backline(family,opponent)
					for seed_value in [8519,16729]:
						for side in 2:
							var result:=await fight(family,opponent,allies,seed_value,side)
							check(result.winner in [-1,family,opponent], "native mirrored battle settles")
							points+=1.0 if result.winner==family else 0.5 if result.winner==-1 else 0.0;count+=1
			var rate:=points/count
			check(rate>=(0.25 if family==35 else 0.30) and rate<=0.80, "viable but counterable team contribution %s star %s: %s" % [family,star+1,rate])
			outcomes.append({"family":family,"rank":star,"points":points,"fights":count,"rate":rate})
	check(hash(GameData.db.tables)==native,"balance is isolated from campaign records")
	FileAccess.open("user://arena-horde-balance.json",FileAccess.WRITE).store_string(JSON.stringify(outcomes))
	finish()
func finish() -> void:
	print("ARENA_HORDE_BALANCE ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
