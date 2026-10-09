extends RefCounted
## Haburu's display placement is on a disconnected village island. Native
## village topics did not require approaching it; selecting fq15 placed the
## conversation partner beside the hero. Preserve that one authored case.
const TOPIC := "b.Haburu.fq15"
const DISPLAY_POSITION := Vector2(41.93026,84.56726)

static func original_stage(session: Session, hero: GameUnit, target: GameUnit, player: int) -> bool:
	if session.state.campaign_id!=CampaignProfile.ASTRAL or session.zone_id!="bz23k" \
		or not session.shop_available() or session.world.vm==null \
		or hero==null or target==null or hero.dead or target.dead or hero.controller!=player \
		or target.uid!=ScriptVM.name_id("Haburu") or String(target.info.get("name","")).to_lower()!="haburu" \
		or target.pos.distance_to(DISPLAY_POSITION)>0.02 or not target.village_talk_ready() \
		or session.state.get_pvar(player,TOPIC)!=1.0 or hero.pos.distance_to(target.pos)<=Session.TALK_REACH:
		return false
	# Ignore every live actor so a temporary crowd cannot turn a cancelled or
	# failed approach into instant dialogue. Keep authored terrain/scenery.
	var ignored: Array=[hero]
	for unit: GameUnit in session.world.unit_rows():
		if unit!=hero: ignored.append(unit)
	return session.world.nav.find_path(hero.pos,target.pos,ignored,[],0.0,hero.move_class(),true).is_empty()
