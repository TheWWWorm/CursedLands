extends "coop_progress_context.gd"
## Focused package-level ownership regression. Mutable dependent snapshots
## stand in for the same records changed by independent solo play.
func actor(uid: int, owner: int, record: Dictionary, pet: bool) -> GameUnit:
	var u:=GameUnit.new(); u.uid=uid; u.world=s.world; u.controller=-1
	u.set_meta("orphan_of",owner); u.info={"name":record.get("unit_name","")}
	if pet: u.set_meta("tame_stage",3)
	else: u.set_meta("hero",record)
	s.world.add_child(u); s.world.set_unit(uid,u)
	return u

func _ready() -> void:
	s=QuietSession.new(); s.online=true; s.state=CoopProgress.fresh_state()
	s.state.ensure_hero(1,"Human Hero","Guest")
	s.world=GameWorld.new(); s.world.session=s; s.zone_id=s.state.current_zone
	s.coop=CoopProgress.new(); s.coop.session=s
	origin=CoopProgress.fresh_state(); origin.heroes[0][0].str=31.0
	var pet:={"rec":{"prototype":"Human Hero","name":"Personal dependent"},"controller":1,"party":"","hp":17.0,"pos":Vector2(6,7)}
	s.state.pets=[pet,{"rec":{"prototype":"Human Hero","name":"Host dependent"},"controller":0,"hp":99.0}]
	var hired: Dictionary=origin.heroes[0][0].duplicate(true)
	hired.merge({"merc":6,"controller":1,"unit_name":"merc6","str":31.0},true)
	s.state.mercs[6]=hired
	var others:=hired.duplicate(true); others.controller=2; others.merc=7
	s.state.mercs[7]=others
	s.state.set_var(0,"apartyn6",1.0); s.state.set_var(0,"adeadn6",0.0)
	actor(1,1,{},true); actor(2,1,hired,false)
	actor(3,2,{},true); actor(4,2,others,false)
	entry={"idx":1,"pid":2,"active":true,"in_sync":true,"clean":true,"present":true,
		"hero_in":origin.heroes[0][0].duplicate(true),"orig_name":"Guest","seq":1,"sid":"dependents-source",
		"vars":{},"visited":{},"side_quests":{},"quest_items":{},
		"credits":{"vars":{},"visited":{},"side_quests":{},"quest_items":{},"zones":{}},
		"purse":{"money":222,"items":[]},"party_context":capture(origin)}
	s.coop.joiners.guest=entry
	var returned:=clone(origin); CoopProgress.merge(returned,s.coop.package(entry))
	check(returned.pets.size()==1 and returned.pets[0].hp==17.0,"original package credits the guest's dependent once")
	check(returned.mercs[6].str==31.0,"original package credits the owned companion")
	returned.pets[0].hp=11.0; returned.pets[0].body={"wounds":[1,2]}
	returned.mercs[6].str=44.0; returned.mercs[6].hp=22.0
	entry.active=false
	s.coop._pending[72]={"hero":CoopProgress.main_hero(returned),"vars":{},"visited":{s.zone_id:true},"side_quests":{},"quest_items":{},
		"seq":{"dependents-source":1},"purse":entry.purse,"party_context":capture(returned),"zone":s.zone_id}
	s.coop.on_hello(72,1,"Guest")
	check(entry.clean and entry.present,"acknowledged matching source is eligible for continuation")
	check(not s.world.units.has(1) and s.world.units.has(3),"reimport removes only the inactive owner's old live animal")
	check(s.state.pets.size()==1 and s.state.pets[0].controller==0,"only the superseded personal animal leaves the host snapshot")
	check(s.world.units.has(4) and s.state.mercs.has(7),"another player's hired actor and record remain intact")
	var rebased:=clone(returned); CoopProgress.merge(rebased,s.coop.package(entry))
	check(rebased.pets.size()==1 and rebased.pets[0].hp==11.0 and rebased.pets[0].body=={"wounds":[1,2]},"changed solo dependent retains its mutable state without a stale host duplicate")
	if GameData.campaign_id==CampaignProfile.ORIGINAL:
		check(rebased.mercs[6].str==44.0 and rebased.mercs[6].hp==22.0,"independently trained personal hire is not replaced by its stale host record")
		check(not s.world.units.has(2) and not s.state.mercs.has(6) and s.state.get_var(0,"apartyn6")==0.0 \
			and s.state.get_var(0,"adeadn6")==0.0,"old optional hire is dismissed without inventing a death")
	else:
		check(rebased.mercs[6].str==31.0,"LiA shared story companion remains authority-owned")
		check(s.world.units.has(2) and s.state.mercs.has(6) and s.state.get_var(0,"apartyn6")==1.0,"LiA authored companion keeps its live role and hiring state")
	var once:=capture(rebased); CoopProgress.merge(rebased,s.coop.package(entry))
	check(capture(rebased)==once,"repeated acknowledged package does not multiply dependents")
	s.world.free(); s.coop.free(); s.free()
	print("COOP_SOLO_RETURN_DEPENDENTS ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
