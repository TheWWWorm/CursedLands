extends "arena_commander_events_ui.gd"
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--astral-path="): GameData.campaign_roots[CampaignProfile.ASTRAL] = arg.trim_prefix("--astral-path=")
	assert(ArenaExpansion.mount())
	expansion = true; host_commander = "lia_hero:wrapped"; guest_commander = "hero:jun"
	await super._ready()
