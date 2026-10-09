extends "coop_rename_reconnect.gd"
## Normal menu/ENet import of an independently advanced personal source.
## Original party instructions establish the prepared chapter; the ordinary
## script variable/LeaveToZone path establishes subsequent shared credit.
const Chapters = preload("coop_progress_context.gd")
var advanced_bytes:=PackedByteArray()
var camp:="bz1h"
var field:="gz1h"
var chapter:="FPrison"
var quest_key:=""
var ann_app: Frontend
var fresh_app: Frontend

func clone_state(st: CampaignState) -> CampaignState:
	var helper:=Chapters.new()
	var copy: CampaignState=helper.clone(st)
	helper.free()
	return copy

func chapter_in(s: Session) -> void:
	var helper:=Chapters.new(); helper.s=s; helper.vm=s.world.vm
	helper.transition(camp,chapter)
	check(helper.failures==0,"original party instructions establish "+chapter)
	helper.free()

func advance_solo(st: CampaignState) -> void:
	var s:=Chapters.QuietSession.new(); s.state=st
	s.coop=CoopProgress.new(); s.coop.session=s
	s.world=GameWorld.new(); s.world.session=s
	var vm:=ScriptVM.new(); vm.session=s; vm.world=s.world; s.world.vm=vm
	chapter_in(s)
	s.world.vm=null; vm=null; s.world.free(); s.coop.free(); s.free()

func delivered(label: String) -> CampaignState:
	check(host.save_game(label)==OK,"ordinary host save sends "+label)
	var e:=host.coop.purse_entry(guest.my_index)
	var sequence:=int(e.seq)
	check(await until(func():
		if guest.coop.last_merged.is_empty(): return false
		var saved:=CampaignState.load_from(SaveInfo.path(guest.coop.last_merged))
		return saved!=null and int(saved.coop.get("applied",{}).get(String(e.sid),{}).get("seq",-1))>=sequence
	),label+" arrives through package RPC")
	return CampaignState.load_from(SaveInfo.path(guest.coop.last_merged))

func use_app(app: Frontend) -> void:
	guest_app=app; guest=app.session; get_tree().current_scene=app.get_parent()

func guard_source(source: CampaignState,kind: String) -> void:
	var own:=clone_state(source); own.coop={}
	match kind:
		"ahead": own.set_var(0,quest_key,2.0)
		"behind": own.set_var(0,quest_key,0.0)
		"conflict": own.set_var(0,"bz1h_night",float(host.state.get_var(0,"bz1h_night"))+1.0)
		"zone": own.current_zone="gz1g"
	var slot:="solo_guard_"+kind
	check(own.save(SaveInfo.path(slot))==OK,"prepare personal "+kind+" source")
	if not await join_from_menu("G"+kind,slot): return
	var e: Dictionary=host.coop.joiners["g"+kind]
	check(not e.clean and not e.present,kind+" arrival cannot claim a matching checkpoint")
	var returned:=await delivered("guard_"+kind)
	check(returned.current_zone==own.current_zone and returned.current_party==own.current_party,kind+" arrival retains its own campaign location/chapter")
	check(returned.get_var(0,quest_key)==own.get_var(0,quest_key),kind+" arrival does not adopt host quest history")
	await leave_from_menu("guard "+kind)

func authored_departure() -> void:
	var ast:=ScriptParser.parse(EIMob.load_bytes(GameData.read_file("maps/"+camp+".mob")).script_text)
	var call:=[]
	for script: Dictionary in ast.scripts.values():
		for block: Dictionary in script.blocks:
			for stmt: Array in block.body:
				if stmt[0]==ScriptParser.S_CALL and stmt[1]=="LeaveToZone" and stmt[2].size()>=3 \
						and stmt[2][1][0]==ScriptParser.N_STR and String(stmt[2][1][1]).to_lower()==field:
					call=stmt[2]; break
	check(not call.is_empty(),"original chapter contains the tested field transfer")
	if call.is_empty(): return
	host.world.vm._call("LeaveToZone",call,ScriptVM.Instance.new())
	host.world.vm.tick(0.055)
	check(await until(func():return host.zone_id==field and not host.loading_game),"original LeaveToZone reaches the authored field")
	freeze(host)
	for app: Frontend in [ann_app,fresh_app]:
		var s: Session=app.session
		check(await until(func():return s.zone_id==field and not s._remote_loading and not s.loading_game),"independent peer follows original field transfer")
		freeze(s)
	CampaignState.watch=host.coop._on_var

func protected_existing_source() -> void:
	# Fresh has finished; retain Ann as the active participant while another
	# transport attempts the same-name/same-address reconnect with altered data.
	if fresh_app:
		use_app(fresh_app); await leave_from_menu("Fresh after shared progress")
	use_app(ann_app)
	var latest:=CampaignState.load_from(SaveInfo.path(guest.coop.last_merged))
	var active_copy:=clone_state(latest)
	CoopProgress.main_hero(active_copy).str=499.0; active_copy.money=12345
	active_copy.coop.applied[String(host.coop.joiners.ann.sid)].seq=int(host.coop.joiners.ann.seq)
	active_copy.save(SaveInfo.path("solo_active_copy"))
	var uid: int=host.party_units(old_slot)[0].uid
	var displaced:=ann_app
	var old_peer:=guest.multiplayer.get_unique_id()
	var player_events:=[0]
	var on_players_change:=func():player_events[0]+=1
	host.players_changed.connect(on_players_change)
	var replacement:=branch("SoloActiveCopy"); use_app(replacement); open_menu(replacement)
	if not await join_from_menu("Ann","solo_active_copy"): return
	ann_app=replacement
	host.players_changed.disconnect(on_players_change)
	check(guest.my_index==old_slot and host.party_units(old_slot)[0].uid==uid,"active transport handoff retains the reserved live actor")
	check(identity(host.state.heroes[old_slot][0])==fingerprint and host.coop.joiners.ann.purse==purse,"active same-name copy cannot replace the participant's hero or purse")
	check(not old_peer in host.multiplayer.get_peers() and not host.players.has(old_peer) and player_events[0]==2,"active handoff retires peer/path ownership once before the replacement joins")
	# This isolated process holds multiple frontends. The displaced one is
	# now an offline lost-connection screen and no longer needed by the test.
	displaced.session.online=false; displaced.session.multiplayer.multiplayer_peer.close()
	displaced.get_parent().queue_free(); roots.erase(displaced.get_parent())
	for i in 4: await get_tree().process_frame
	await delivered("transport_active_copy")
	var last:=await leave_from_menu("active-copy transport")
	for kind: String in ["stale","uncredited"]:
		var changed:=CampaignState.load_from(SaveInfo.path(last))
		check(changed!=null,kind+" control starts from a received personal save")
		if changed==null: return
		CoopProgress.main_hero(changed).str=299.0; changed.money=23456
		if kind=="stale": changed.coop.applied[String(host.coop.joiners.ann.sid)].seq=maxi(0,int(host.coop.joiners.ann.seq)-1)
		else: changed.coop={}
		var slot:="solo_existing_"+kind
		changed.save(SaveInfo.path(slot))
		if not await join_from_menu("Ann",slot): return
		check(guest.my_index==old_slot and identity(host.state.heroes[old_slot][0])==fingerprint \
			and host.coop.joiners.ann.purse==purse,kind+" source cannot replace the reserved personal baseline")
		await delivered("transport_"+kind)
		last=await leave_from_menu(kind+" source")

func _ready() -> void:
	await get_tree().process_frame
	process_mode=Node.PROCESS_MODE_ALWAYS; outer_scene=get_tree().current_scene
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0,"coop_share_loot":0},true)
	for option: String in GameData.options:
		if option.begins_with("gfx_"): GameData.options[option]=0
	check(GameData.campaign_id==CampaignProfile.ASTRAL,"run against actual LiA chapter data")
	if GameData.campaign_id!=CampaignProfile.ASTRAL: await finish(); return
	var origin:=CoopProgress.fresh_state(); origin.heroes[0][0].str=31.0
	origin.money=222; origin.items=["rune:e1"]; origin.visited[origin.current_zone]=true
	check(origin.save(SaveInfo.path("solo_origin"))==OK,"write disposable personal origin")
	original_bytes=FileAccess.get_file_as_bytes(SaveInfo.path("solo_origin"))
	host_app=branch("SoloHost"); host=Session.new(); host_app.add_child(host)
	GameData.player_name="Solo Host"; check(host.host(PORT,4)==OK,"open real ENet authority")
	host_app.start_game(host); host.state=CoopProgress.fresh_state(); host.state.heroes[0][0].str=91.0; host.state.money=9000
	host.set_physics_process(false); await host.enter_zone(origin.current_zone,1,false); freeze(host)
	ann_app=branch("SoloAnn"); use_app(ann_app); open_menu(ann_app)
	if not await join_from_menu("Ann","solo_origin"): await finish(); return
	old_slot=guest.my_index
	await host.enter_zone(origin.current_zone,1,false); freeze(host)
	check(await until(func():return guest.zone_id==host.zone_id and not guest._remote_loading),"shared arrival creates the original checkpoint")
	freeze(guest); CampaignState.watch=host.coop._on_var
	await delivered("solo_original_checkpoint")
	check(host.coop.joiners.ann.has("context_checkpoint"),"original co-op tally holds a resumable older checkpoint")
	var returned_slot:=await leave_from_menu("Ann before solo play")
	var solo:=CampaignState.load_from(SaveInfo.path(returned_slot))
	advance_solo(solo); chapter_in(host)
	await host.enter_zone(camp,1,false); freeze(host)
	var mob:=String(host.campaign.zone(field).get("mob",field))
	var text:=EIMob.load_bytes(GameData.read_file("maps/"+mob+".mob")).script_text
	var found:=RegEx.create_from_string("q\\.[A-Za-z0-9_]+\\.[A-Za-z0-9_]+").search(text)
	check(found!=null,"select a real authored chapter quest variable")
	if found==null: await finish(); return
	quest_key=found.get_string()
	host.state.set_var(0,quest_key,1.0)
	# Prepared matching independently played story checkpoint. Personal hero,
	# equipment and purse stay the solo source's; no production adoption of
	# host vars or chapter is involved in the join under test.
	solo.vars=host.state.vars.duplicate(true); solo.side_quests=host.state.side_quests.duplicate(true)
	solo.quest_items=host.state.quest_items.duplicate(true); solo.current_zone=camp; solo.visited[camp]=true
	CoopProgress.main_hero(solo).str=44.0
	solo.money=777; solo.items=["rune:e1","rune:e2","rune:ic"]
	fingerprint=identity(CoopProgress.main_hero(solo)); purse=CoopProgress.main_bag(solo).duplicate(true)
	check(solo.save(SaveInfo.path("solo_advanced"))==OK,"save the independently advanced acknowledged personal source")
	advanced_bytes=FileAccess.get_file_as_bytes(SaveInfo.path("solo_advanced"))
	if not await join_from_menu("Ann","solo_advanced"): await finish(); return
	check(guest.my_index==old_slot,"acknowledged solo return keeps its reserved player slot")
	check(identity(host.state.heroes[old_slot][0])==fingerprint,"acknowledged solo return imports newly earned hero stats/equipment")
	for s: Session in [host,guest]:
		var unit: GameUnit=s.party_units(old_slot)[0]
		check(String(unit.proto.get("name",""))==String(fingerprint.prototype) and unit.get_meta("hero").str==44.0,"live peer deploys the returned authored protagonist body and stats")
		check(unit.model!=null and unit.model.template==String(unit.race.get("mask","")).to_lower(),"live peer constructs the returned body's original figure model")
	check(host.coop.joiners.ann.purse==purse,"acknowledged solo return imports its new private purse once")
	check(host.coop.joiners.ann.clean and host.coop.joiners.ann.present and host.coop.joiners.ann.in_sync,"matching acknowledged return restores shared checkpoint continuity")
	var resumed:=await delivered("solo_resumed")
	check(resumed.current_party==chapter and resumed.current_zone==camp,"old checkpoint cannot rewind the newer compatible source chapter/location")
	check(identity(CoopProgress.main_hero(resumed))==fingerprint and CoopProgress.main_bag(resumed)==purse,"returned package retains new solo earnings")
	if "--rebase-only" in OS.get_cmdline_user_args():
		await finish(); return # compact before/after proof; full run continues into original field travel
	var probe:=branch("SoloProbe"); use_app(probe); open_menu(probe)
	for kind in ["ahead","behind","conflict","zone"]: await guard_source(solo,kind)
	var fresh:=clone_state(solo); fresh.coop={}; fresh.save(SaveInfo.path("solo_fresh"))
	if not await join_from_menu("Fresh","solo_fresh"): await finish(); return
	fresh_app=guest_app
	check(host.coop.joiners.fresh.clean and host.coop.joiners.fresh.present,"new matching solo import establishes its own compatible checkpoint")
	check(not CoopProgress._reached(host.coop.joiners.ann,field) and not CoopProgress._reached(host.coop.joiners.fresh,field),"neither eligible source has a fabricated field unlock")
	# The same production script variable route that the authored quest uses.
	host.world.vm._call("GSSetVar",[[ScriptParser.N_NUM,0],[ScriptParser.N_STR,quest_key],[ScriptParser.N_NUM,2]],ScriptVM.Instance.new())
	await authored_departure()
	for app: Frontend in [ann_app,fresh_app]:
		use_app(app)
		var e: Dictionary=host.coop.joiners.ann if app==ann_app else host.coop.joiners.fresh
		check(e.in_sync and e.clean and e.present,"matching solo participant retains eligibility through unflagged field travel")
		var saved:=await delivered("solo_final_"+String(e.name).to_lower())
		check(saved.current_party==chapter and saved.current_zone==field,"participant can resume solo at shared chapter/field")
		check(saved.get_var(0,quest_key)==2.0 and saved.quests.get(quest_key.get_slice(".",2))==2,"own aligned quest completes in the returned solo save")
		check(identity(CoopProgress.main_hero(saved))==fingerprint and CoopProgress.main_bag(saved)==purse,"shared progression retains each participant's own solo earnings")
		check(saved.save(SaveInfo.path("solo_resume_"+String(e.name).to_lower()))==OK,"save actual RPC result for independent solo resume")
		rows.append({"player":e.name,"slot":e.idx,"party":saved.current_party,"zone":saved.current_zone,"hero":identity(CoopProgress.main_hero(saved)),"purse":CoopProgress.main_bag(saved),"quest":quest_key,"quest_value":saved.get_var(0,quest_key)})
	check(FileAccess.get_file_as_bytes(SaveInfo.path("solo_origin"))==original_bytes and FileAccess.get_file_as_bytes(SaveInfo.path("solo_advanced"))==advanced_bytes,"both selected personal saves remain byte-identical")
	await finish()

func finish() -> void:
	for view in roots:
		var app: Frontend=view.frontend
		if app and is_instance_valid(app.session):
			app.session.online=false
			if app.session.multiplayer.multiplayer_peer: app.session.multiplayer.multiplayer_peer.close()
	print("COOP_SOLO_RETURN ",checks," checks ",failures," failures")
	await super.finish()
