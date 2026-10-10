extends RefCounted
## These original village conversations cross disconnected scenery. Native
## topics did not require approaching their display actors. Preserve authored
## staging only for the verified topic, chapter and unchanged display position.
const TOPIC := "b.Haburu.fq15"
const DISPLAY_POSITION := Vector2(41.93026,84.56726)
const NALO_ENTRY_TOPIC := "b.Nalo.Kr60"
const NALO_TOPIC := "b.Nalo.Kr61"
const NALO_DISPLAY_POSITION := Vector2(66.54526,55.33020)
const CAPTIVE_LEADER_TOPIC := "b.HWLeader.Ha29_1"
const CAPTIVE_LIZARD_TOPIC := "b.OLiz.Ha29_2"
const CAPTIVE_ESCAPE_TOPIC := "b.OLiz.Ha29_3"
const CAPTIVE_LEADER_POSITION := Vector2(70.68,62.84)
const CAPTIVE_LIZARD_POSITION := Vector2(77.64449,75.97987)

static func original_stage(session: Session, hero: GameUnit, target: GameUnit, player: int, topic := "") -> bool:
	if not session.shop_available() or session.world.vm==null \
		or hero==null or target==null or hero.dead or target.dead or hero.controller!=player:
		return false
	var name: String
	var expected_topic: String
	var display_position: Vector2
	var captive_route := false
	if session.state.campaign_id==CampaignProfile.ASTRAL and session.zone_id=="bz23k":
		name="Haburu"; expected_topic=TOPIC; display_position=DISPLAY_POSITION
	elif session.state.campaign_id==CampaignProfile.ORIGINAL and session.zone_id=="bz13h" \
		and session.state.current_party=="HeroAlone" \
		and bool(session.world.zone.get("cage",false)):
		# Both the Kr60 rescue handoff and the Kr61 return cross this cage.
		# The offered return also precedes the native door-opening tick.
		# Only the topic belonging to the current authored quest phase may
		# use staging; completing the rescue cannot grant entry-topic staging.
		if session.state.get_var(0,"q.gz15h.q61h")==2.0:
			expected_topic=NALO_TOPIC
		elif session.state.get_var(0,"q.gz15h.q60h")==2.0:
			expected_topic=NALO_ENTRY_TOPIC
		else:
			return false
		name="Nalo"; display_position=NALO_DISPLAY_POSITION
	elif session.state.campaign_id==CampaignProfile.ORIGINAL and session.zone_id=="bz4g" \
		and session.state.current_party.is_empty() and bool(session.world.zone.get("cage",false)) \
		and session.state.get_var(0,"b.bz4g.Ha29")==2.0:
		# Zak remains inside the original pen while the commander and Hermit
		# speak from outside. No walking route reaches either display actor.
		if target.uid==ScriptVM.name_id("HWLeader"):
			name="HWLeader"; expected_topic=CAPTIVE_LEADER_TOPIC; display_position=CAPTIVE_LEADER_POSITION
		elif target.uid==ScriptVM.name_id("OLiz"):
			name="OLiz"; display_position=CAPTIVE_LIZARD_POSITION
			expected_topic=CAPTIVE_ESCAPE_TOPIC if session.state.get_pvar(player,CAPTIVE_LIZARD_TOPIC)==2.0 else CAPTIVE_LIZARD_TOPIC
		else:
			return false
		captive_route=true
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
	var route := session.world.nav.find_path(hero.pos,target.pos,ignored,[],0.0,hero.move_class(),true)
	# The original search can return a partial route to the pen wall rather
	# than an empty path. It must still fail to reach conversation distance.
	return route.is_empty() or (captive_route and route[-1].distance_to(target.pos)>Session.TALK_REACH)
