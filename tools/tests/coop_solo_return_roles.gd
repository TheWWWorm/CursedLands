extends "coop_progress_context.gd"
## Reimport must not replace independently earned Nalo/Shaina progression
## with freshly seeded role statistics. Original instructions define the role.
func _ready() -> void:
	s=QuietSession.new(); s.online=true; s.state=CoopProgress.fresh_state()
	s.state.ensure_hero(1,"Human Hero","Guest"); s.state.heroes[1][0].str=31.0
	s.coop=CoopProgress.new(); s.coop.session=s
	s.world=GameWorld.new(); s.world.session=s
	vm=ScriptVM.new(); vm.session=s; vm.world=s.world
	origin=CoopProgress.fresh_state(); origin.heroes[0][0].str=31.0; origin.money=222; origin.items=["rune:e1"]
	entry={"idx":1,"pid":2,"active":true,"in_sync":true,"clean":true,"present":true,
		"hero_in":s.state.heroes[1][0].duplicate(true),"orig_name":"Solo Guest","seq":4,"sid":"role-return",
		"vars":{},"visited":{},"side_quests":{},"quest_items":{},
		"credits":{"vars":{},"visited":{},"side_quests":{},"quest_items":{},"zones":{}},
		"purse":{"money":222,"items":["rune:e1"]},"party_context":capture(origin)}
	s.coop.joiners.guest=entry
	if GameData.campaign_id==CampaignProfile.ASTRAL:
		transition("bz1h","FPrison"); transition("bz2h","FSusel"); transition("bz5h","Shaina")
		s.zone_id="gz2h"
	else:
		transition("bz7g","HeroAlone"); transition("bz13h","Pretty")
		s.zone_id="gz15h"
	var returned:=clone(origin); CoopProgress.merge(returned,s.coop.package(entry))
	returned.heroes[0][0].str=49.0; returned.money=888; returned.items=["rune:e2"]
	CoopProgress.main_hero(returned).str=44.0
	var main:=CoopProgress.main_party(returned)
	returned.party_bags[main]={"money":777,"items":["rune:ic"]}
	var expected_proto: String=returned.heroes[0][0].prototype
	entry.active=false
	var view:={}
	for key: String in s.state.vars:
		if key.begins_with("0:") and not CoopProgress.excluded(key.substr(2)): view[key.substr(2)]=s.state.vars[key]
	s.coop._pending[72]={"hero":CoopProgress.sanitize_hero(CoopProgress.main_hero(returned)),"vars":view,"visited":{s.zone_id:true},
		"side_quests":s.state.side_quests.duplicate(true),"quest_items":s.state.quest_items.duplicate(true),
		"seq":{"role-return":4},"purse":CoopProgress.main_bag(returned),"party_context":capture(returned),"zone":s.zone_id}
	s.coop.on_hello(72,1,"Guest")
	CoopProgress.GuestRoles.ensure(s,1) # ordinary late-join deployment preparation
	check(entry.clean and entry.present,"matching acknowledged temporary chapter restores continuity")
	check(s.state.heroes[1][0].prototype==expected_proto and s.state.heroes[1][0].str==49.0,"returned temporary body keeps its independently earned statistics")
	check(entry.purse=={"money":888,"items":["rune:e2"]},"returned temporary role keeps its own earned purse")
	check(String(s.state.heroes[1][0].get("guest_unit_name","")).begins_with("RemakeGuest1_"),"restored role retains generated co-op deployment identity")
	var result:=clone(returned); CoopProgress.merge(result,s.coop.package(entry))
	check(result.heroes[0][0].str==49.0 and result.money==888,"next progress package cannot reset imported temporary-role earnings")
	check(CoopProgress.main_hero(result).str==44.0 and CoopProgress.main_bag(result)=={"money":777,"items":["rune:ic"]},"normal protagonist and bag remain separately parked")
	vm=null; s.world.free(); s.coop.free(); s.free()
	print("COOP_SOLO_RETURN_ROLES ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
