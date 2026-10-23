extends RefCounted
## The original server removal detaches the unit from its player as well
## as the scene (LiA 4eb3b0 -> 4ae350(0) -> 58f850). The remake's generic
## scene removal cannot stand in for that named-party handoff: otherwise
## Kel is deployed alive again on the scene's return to Jigran.
## Keep this correction limited to the shipped death scene and its saved
## resurrection record; other actor/party removal contracts are separate.
const DEATH_SCENE := "a0dcc8c2fc96a5382604dd67fd93a7e361abf8fdf04435f91da51d8880b5c6da"

static func before_remove(vm: ScriptVM, thread: String, u: GameUnit) -> void:
	var s := vm.session
	if s.state.campaign_id != CampaignProfile.ASTRAL or not s.lmp.is_empty() \
			or s.state.current_party != "Jigran2" or s.zone_id != "cz3j" \
			or thread != "VMovie#0#3" or not u.dead or not u.has_meta("hero") \
			or vm.world.mob == null or vm.world.mob.script_text.sha256_text() != DEATH_SCENE:
		return
	# party_member falls back to the unnamed party for an unknown party name.
	# An unrelated merc2 there is not the authored resurrection archive.
	if not s.state.parties.has("Jigran5"): return
	var record := s.state.party_member("Jigran2::merc2")
	if record.is_empty() or not is_same(record,u.get_meta("hero")) \
			or s.state.party_member("Jigran5::merc2").is_empty(): return
	s.state.remove_party_unit("Jigran2::merc2")
