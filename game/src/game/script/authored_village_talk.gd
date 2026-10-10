extends RefCounted
## These original village conversations cross disconnected scenery. Native
## topics did not require approaching their display actors. Preserve authored
## staging only for the verified topic, chapter and unchanged display position.
const TOPIC := "b.Haburu.fq15"
const DISPLAY_POSITION := Vector2(41.93026,84.56726)
const NALO_TOPIC := "b.Nalo.Kr61"
const NALO_DISPLAY_POSITION := Vector2(66.54526,55.33020)

static func original_stage(session: Session, hero: GameUnit, target: GameUnit, player: int, topic := "") -> bool:
	if not session.shop_available() or session.world.vm==null \
		or hero==null or target==null or hero.dead or target.dead or hero.controller!=player:
		return false
	var name: String
	var expected_topic: String
	var display_position: Vector2
	if session.state.campaign_id==CampaignProfile.ASTRAL and session.zone_id=="bz23k":
		name="Haburu"; expected_topic=TOPIC; display_position=DISPLAY_POSITION
	elif session.state.campaign_id==CampaignProfile.ORIGINAL and session.zone_id=="bz13h" \
		and session.state.current_party=="HeroAlone" and session.state.get_var(0,"q.gz15h.q61h")==2.0 \
		and bool(session.world.zone.get("cage",false)):
		# Kr61 returns the rescued hero to the main party. The open cell's
		# authored village layout still has no walkable route to Nalo. The
		# topic is already offered while its native door-opening script waits
		# for the first village ticks; that delay must not block conversation.
		name="Nalo"; expected_topic=NALO_TOPIC; display_position=NALO_DISPLAY_POSITION
	else:
		return false
	if (not topic.is_empty() and topic!=expected_topic) \
		or target.uid!=ScriptVM.name_id(name) or String(target.info.get("name","")).to_lower()!=name.to_lower() \
		or target.pos.distance_to(display_position)>0.02 or not target.village_talk_ready() \
		or session.state.get_pvar(player,expected_topic)!=1.0 or hero.pos.distance_to(target.pos)<=Session.TALK_REACH:
		return false
	# Ignore every live actor so a temporary crowd cannot turn a cancelled or
	# failed approach into instant dialogue. Keep authored terrain/scenery.
	var ignored: Array=[hero]
	for unit: GameUnit in session.world.unit_rows():
		if unit!=hero: ignored.append(unit)
	return session.world.nav.find_path(hero.pos,target.pos,ignored,[],0.0,hero.move_class(),true).is_empty()
