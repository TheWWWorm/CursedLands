extends "coop_progress_travel.gd"
## Re-entry and host reload must not promote a previously rejected incoming
## story checkpoint into a complete zone/party snapshot.
func _ready() -> void:
	s=Session.new(); s.online=true; s.state=CoopProgress.fresh_state()
	s.state.heroes[1]=s.state.heroes[0].duplicate(true)
	s.world=GameWorld.new(); s.world.session=s
	s.campaign=CampaignMap.load_from(GameData.texts)
	s.coop=QuietProgress.new(); s.coop.session=s
	var zone: String=s.state.current_zone
	s.zone_id=zone
	s.state.set_var(0,"q."+zone+".checkpoint",1.0)
	s.state.set_var(0,"story_checkpoint",1.0)
	for kind: String in ["ahead","behind","conflict","party","quest_item","side_quest"]:
		var origin:=CoopProgress.fresh_state()
		var data:={"hero":origin.heroes[0][0],"vars":{"q."+zone+".checkpoint":1.0,"story_checkpoint":1.0},"visited":{zone:true},
			"side_quests":{},"quest_items":{},"seq":{},"purse":{"money":222,"items":[]},"party_context":CoopProgress.PartyProgress.capture(origin),"zone":zone}
		match kind:
			"ahead": data.vars["q."+zone+".checkpoint"]=2.0
			"behind": data.vars["q."+zone+".checkpoint"]=0.0
			"conflict": data.vars.story_checkpoint=2.0
			"party": data.party_context.current_party="DifferentChapter"
			"quest_item": data.quest_items.different=true
			"side_quest": data.side_quests.different="active"
		s.coop.joiners={}; s.coop._pending[72]=data
		s.coop.on_hello(72,1,"Guest")
		var e: Dictionary=s.coop.joiners.guest
		check(not e.clean and not e.present,kind+" is rejected as a whole checkpoint on arrival")
		for loading: bool in [false,true]:
			s.coop._loading=loading; s.coop._zone=zone
			s.coop.zone_entered(zone)
			var pkg:=s.coop.package(e)
			check(not e.clean and pkg.move.is_empty() and pkg.party_context.is_empty(),kind+(" host reload" if loading else " re-entry")+" cannot adopt a full story checkpoint")
	s.world.free(); s.coop.free(); s.free()
	print("COOP_SOLO_RETURN_GUARDS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
