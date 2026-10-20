extends Node
## Every installed side-quest archive: offer eligibility, accept/complete/reward,
## duplicate dialog completion and persistence. Controlled world; no walking.
class QuietSession extends Session:
	var events: Array = []
	var experience_awards: Array = []
	func broadcast(event: Dictionary) -> void: events.append(event.duplicate(true))
	func sync_state() -> void: pass
	func give_experience(amount: float, source := "quest", player := 0) -> void:
		experience_awards.append([amount,source,player])
		super.give_experience(amount,source,player)

var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)

func _ready() -> void:
	var quests := SideQuests.all()
	check(not quests.is_empty(),"installed campaign contains side-quest archives")
	var exercised := 0
	for q: Dictionary in quests:
		var s := QuietSession.new(); add_child(s); s.set_physics_process(false)
		s.state.ensure_hero(0,"Human Hero")
		s.campaign=CampaignMap.load_from(GameData.texts)
		var w := GameWorld.new(); w.session=s; s.world=w; w.presentation=false
		var vm := ScriptVM.new(); vm.world=w; vm.session=s; w.vm=vm
		vm.ast=ScriptParser.parse("")
		vm.briefings=Briefings.new(vm)
		var zone := SideQuests.zone_of(s,q)
		if zone.is_empty():
			# Multiplayer-only quest maps have no single-player offer route.
			check(SideQuests.active_in(s,"unknown").is_empty(),q.id+" has no invented campaign destination")
			s.world=null; w.free(); s.free(); continue
		exercised+=1
		var allod: String=s.campaign.zone(zone).get("allod","")
		w.zone={"id":"fixture_village","type":"brief","allod":allod}
		var label: String=q.id+": "
		check(not SideQuests.offers(s).has(q),label+"unvisited destination is not offered")
		s.state.visited[zone]=true
		check(SideQuests.offers(s).has(q),label+"visited same-island quest is offered")
		w.zone.type="game"
		check(SideQuests.offers(s).is_empty(),label+"field cannot offer village work")
		w.zone.type="brief"; w.zone.allod="not_this_island"
		check(not SideQuests.offers(s).has(q),label+"another island does not offer this quest")
		w.zone.allod=allod
		s.apply_command({"t":"side_quest","q":q.id},0)
		check(s.state.side_quests.get(q.id)=="active",label+"player acceptance activates quest")
		check(SideQuests.offers(s).is_empty(),label+"active quest blocks additional offers")
		check(SideQuests.active_in(s,zone)==q.id,label+"destination selects active quest overlay")
		var dialogs := s.events.size()
		s.apply_command({"t":"side_quest","q":q.id},0)
		check(s.events.size()==dialogs,label+"double acceptance does not reopen a briefing")
		vm.briefings.staging_tick()
		s.apply_command({"t":"dialog_done","id":"sq."+q.id+".1"},0)
		var before := s.state.vars.duplicate(true)
		s.apply_command({"t":"dialog_done","id":"sq."+q.id+".1"},0)
		check(s.state.vars==before,label+"duplicate offer completion cannot repeat quest initialization")
		SideQuests.finish(s,q.id)
		check(s.state.side_quests.get(q.id)=="done",label+"objective completion waits for reward")
		check(SideQuests.offers(s).is_empty(),label+"unclaimed reward still blocks more offers")
		check(SideQuests.active_in(s,zone).is_empty(),label+"completed quest stops injecting active overlay")
		SideQuests.check_rewards(s); vm.briefings.staging_tick()
		var money := s.state.money
		var awards := s.experience_awards.size()
		s.apply_command({"t":"dialog_done","id":"sq."+q.id+".3"},0)
		check(s.state.side_quests.get(q.id)=="rewarded" and s.state.quests.get(q.id)==2,label+"reward closes both quest records")
		check(s.state.money==money+int(q.money),label+"reward pays exact archive money")
		check(s.experience_awards.size()==awards+1 and s.experience_awards[-1]==[float(q.exp),"side",0],label+"reward dispatches the exact archive experience once")
		var closed := s.events.size()
		for i in 3: s.apply_command({"t":"dialog_done","id":"sq."+q.id+".3"},0)
		SideQuests.finish(s,q.id); SideQuests.check_rewards(s)
		check(s.state.money==money+int(q.money),label+"repeated completion and reward checks never duplicate money")
		check(s.experience_awards.size()==awards+1,label+"repeated completion never repeats experience, including zero-money rewards")
		check(s.events.size()==closed,label+"repeated completion does not emit another dialogue-close event")
		check(not SideQuests.offers(s).has(q),label+"rewarded quest cannot be taken again")
		var file: String = "user://side-quest-"+q.id+".sav"
		check(s.state.save(file)==OK,label+"checkpoint saves")
		var restored := CampaignState.load_from(file)
		check(restored!=null and restored.side_quests==s.state.side_quests and restored.money==s.state.money,label+"reward state and money survive reload")
		await get_tree().process_frame
		s.world=null; w.free(); s.free()
	check(exercised>0,"at least one original side quest exercises the complete campaign lifecycle")
	print("SIDE_QUEST_LIFECYCLE ", JSON.stringify({"checks":checks,"failures":failures,"archives":quests.size(),"campaign_routes":exercised}))
	get_tree().quit(0 if failures.is_empty() else 1)
