extends "coop_rename_reconnect.gd"
## Actual New campaign hero joins either before
## Start or after original opening-map startup, without manufactured flags.
var early:=false
var phases:=[]

func freeze(s: Session) -> void:
	s.set_physics_process(false)
	if s.world:
		s.world.set_process(false); s.world.set_physics_process(false)
	if s.game:
		s.game.set_process(false); s.game.rig.set_process(false)
		s.game.hud._tutorial.close(); s.game.hud._dialog.hide()

func story(st: CampaignState) -> Dictionary:
	var out:={}
	for key: String in st.vars:
		if key.begins_with("0:") and not CoopProgress.excluded(key.substr(2)):
			out[key.substr(2)]=st.vars[key]
	return out

func sample(label: String) -> void:
	var e: Dictionary=host.coop.joiners.get("fresh",{})
	var h:=story(host.state)
	var own: Dictionary=e.get("vars",{})
	var diff:={}
	for key: String in h:
		if not is_equal_approx(h[key],float(own.get(key,0.0))): diff[key]={"host":h[key],"guest":own.get(key,0.0)}
	for key: String in own:
		if not CoopProgress.excluded(key) and not is_equal_approx(float(own[key]),float(h.get(key,0.0))):
			diff[key]={"host":h.get(key,0.0),"guest":own[key]}
	var context:=CoopProgress.PartyProgress.read(e.get("party_context"))
	var row:={"label":label,"zone":host.zone_id,"host_party":host.state.current_party,"guest_party":context.current_party if context else "<none>",
		"vars":h,"guest_vars":own.duplicate(true),"differences":diff,"clean":e.get("clean",false),"present":e.get("present",false),"in_sync":e.get("in_sync",false)}
	phases.append(row); print("FRESH_PHASE ",JSON.stringify(row))

func join_lobby() -> bool:
	var menu=menu_of(guest_app)
	var panel: NetworkPanel=menu._net
	panel.open(); panel.show_page(NetworkPanel.JOIN_COOP)
	type_field(panel,"name","Fresh"); type_field(panel,"addr","127.0.0.1:%d"%PORT)
	focus_row(panel,"bring")
	for i in panel._bring_choices().size()+1:
		if CoopProgress.bring_slot==CoopProgress.NEW: break
		key(panel,KEY_RIGHT)
	check(CoopProgress.bring_slot==CoopProgress.NEW,"ordinary keyboard menu selects New campaign hero")
	focus_row(panel,"addr"); key(panel,KEY_ENTER)
	check(await until(func():return host.coop.joiners.has("fresh")),"real bring/hello reaches the lobby before Start")
	guest=menu._session
	CampaignState.watch=host.coop._on_var
	return not host.coop.joiners.is_empty()

func startup() -> void:
	freeze(host); CampaignState.watch=host.coop._on_var
	for i in 100: host.world.vm.tick(0.055)
	await get_tree().process_frame
	freeze(host)

func departure() -> Dictionary:
	# Use the opening map's actual authored first named village exit, with
	# its own target entrance. This is the ordinary Session leave path.
	for id in host.world.zone.exits:
		var ex: Dictionary=host.world.zone.exits[id]
		var dest:=String(ex.get("to","")).to_lower()
		if String(host.campaign.zone(dest).get("type",""))=="brief":
			return {"zone":dest,"entrance":int(ex.get("to_exit",1)),"exit":id}
	var ast=host.world.vm.ast
	for id: String in ast.scripts:
		for block: Dictionary in ast.scripts[id].blocks:
			for statement: Array in block.body:
				if statement.size()>=3 and statement[0]==ScriptParser.S_CALL and statement[1]=="LeaveToZone" \
						and statement[2].size()>=3 and statement[2][1][0]==ScriptParser.N_STR:
					var target:=String(statement[2][1][1]).to_lower()
					if String(host.campaign.zone(target).get("type",""))=="brief":
						return {"zone":target,"script":id,"args":statement[2]}
	return {}

func _ready() -> void:
	await get_tree().process_frame
	process_mode=Node.PROCESS_MODE_ALWAYS; outer_scene=get_tree().current_scene
	early="--before-start" in OS.get_cmdline_user_args()
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0,"coop_share_loot":0},true)
	for opt: String in GameData.options:
		if opt.begins_with("gfx_"):GameData.options[opt]=0
	host_app=branch("FreshHost"); host=Session.new(); host_app.add_child(host)
	GameData.player_name="Fresh Host"; check(host.host(PORT,4)==OK,"open actual ENet authority")
	if failures:await finish();return
	host_app.start_game(host); host.set_physics_process(false)
	if early:
		guest_app=branch("FreshGuest"); get_tree().current_scene=guest_app.get_parent(); open_menu(guest_app)
		if not await join_lobby(): await finish(); return
	# The normal New Campaign implementation, skipping only intro playback.
	await host.new_campaign(false)
	check(host.zone_id=="gz1g" and host.state.current_party=="","ordinary New Campaign builds the untouched opening chapter")
	await startup()
	print("FRESH_EXITS ",JSON.stringify(host.world.zone.exits))
	var script_file:=FileAccess.open("user://opening-script.txt",FileAccess.WRITE)
	script_file.store_string(host.world.mob.script_text); script_file.close()
	print("FRESH_VM ",JSON.stringify({"time":host.world.vm.time,"instances":host.world.vm.instances.size(),"players":host.players,"joiners":host.coop.joiners.keys()}))
	if not early:
		sample("host-startup-before-hello")
		guest_app=branch("FreshGuest"); get_tree().current_scene=guest_app.get_parent(); open_menu(guest_app)
		if not await join_from_menu("Fresh",CoopProgress.NEW):await finish(); return
	else:
		check(await until(func():return guest_app.game!=null and guest_app.session!=null and guest_app.session.zone_id==host.zone_id and not guest._remote_loading and not guest.loading_game),"lobby guest receives the actual opening world")
		freeze(guest)
	CampaignState.watch=host.coop._on_var
	check(guest.coop._origin_new,"client uses ordinary new-origin merge path")
	sample("opening-after-hello")
	check(phases.back().differences.is_empty(),"New hero has the exact opening old-value baseline for later credits")
	var entry: Dictionary=host.coop.joiners.fresh
	var own:=CoopProgress.fresh_state()
	check(identity(entry.hero_in)==identity(CoopProgress.sanitize_hero(CoopProgress.main_hero(own))) and entry.purse==CoopProgress.main_bag(own),"opening admission retains the new guest's own hero and purse")
	var exit:=departure()
	check(not exit.is_empty(),"opening data defines an ordinary village departure")
	if exit.is_empty():await finish();return
	print("FRESH_DEPARTURE ",JSON.stringify(exit))
	if exit.has("args"):
		host.world.vm._call("LeaveToZone",exit.args,ScriptVM.Instance.new())
		host.world.vm.tick(0.055)
	else:host.leave_zone(exit.zone,exit.entrance)
	check(await until(func():return host.zone_id==exit.zone and not host.loading_game),"normal leave enters original first village")
	freeze(host)
	check(await until(func():return guest.zone_id==host.zone_id and not guest._remote_loading and not guest.loading_game),"guest receives ordinary first village")
	freeze(guest); CampaignState.watch=host.coop._on_var
	sample("village-before-startup")
	await startup()
	sample("village-after-startup")
	var before:=guest.coop.merged_count
	check(host.save_game("fresh_checkpoint")==OK,"ordinary host save emits the first-village checkpoint")
	check(await until(func():return guest.coop.merged_count>before and not guest.coop.last_merged.is_empty()),"New hero receives actual progress package")
	var got:=CampaignState.load_from(SaveInfo.path(guest.coop.last_merged))
	check(got!=null and got.current_zone==host.zone_id and got.current_party==host.state.current_party,"starting-together guest can resume at the first shared village")
	var e: Dictionary=host.coop.joiners["fresh"]
	check(e.clean and e.present and e.in_sync,"fresh shared progression remains eligible after ordinary departure")
	if got: phases.append({"label":"received-save","zone":got.current_zone,"party":got.current_party,"vars":story(got)})
	await finish()

func finish() -> void:
	var file:=FileAccess.open("user://fresh-start-review.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"before_start":early,"campaign":GameData.campaign_id,"checks":checks,"failures":failures,"phases":phases},"  ")); file.close()
	print("COOP_FRESH_START ",checks," checks ",failures," failures")
	await super.finish()
