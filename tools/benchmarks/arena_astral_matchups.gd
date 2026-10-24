extends "arena_roster_matchups.gd"
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	if not ArenaExpansion.mount(): printerr("LiA data unavailable"); get_tree().quit(1); return
	await super._ready()
