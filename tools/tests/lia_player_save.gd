extends Node
var checks := 0
var failures := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func frames(n:=3) -> void:
	for i in n: await get_tree().process_frame
func _ready() -> void: _run.call_deferred()
func _run() -> void:
	var fixture := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--save-fixture="): fixture=arg.trim_prefix("--save-fixture=")
	if fixture.is_empty(): printerr("Supply --save-fixture with the repaired save folder");get_tree().quit(1);return
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"control_mode":1,"camera_style":1,"cam_follow":1},true)
	var s:=Session.new();add_child(s);s.set_physics_process(false)
	var g:=Game.new();g.session=s;s.game=g;add_child(g)
	var state:=CampaignState.load_from(fixture.path_join("quick.sav"))
	check(state!=null and s._load_state("feedback_fixture",state),"repaired quicksave loads through Session")
	if s.world==null: get_tree().quit(1);return
	s.set_physics_process(false);s.world.set_process(false);s.world.set_physics_process(false);s.world.vm.instances.clear()
	await frames(4)
	var kel:GameUnit
	for u:GameUnit in s.world.units.values():
		if u.has_meta("hero") and u.get_meta("hero").get("merc",-1)==2:kel=u
	check(kel!=null,"Kel exists as the recruited second-party actor")
	check(kel!=null and kel.get_meta("hero").exp==150 and kel.stats.str==21 and kel.stats.dex==30,"live recruited Kel uses recovered attributes and XP")
	var before:Dictionary=kel.get_meta("hero").duplicate(true)
	s.merc_changed(2,false,0,true,true)
	check(kel.has_meta("npc_character") and s.state.dismissed_mercs.has(2),"script dismissal retains the mutable NPC and a persistent record")
	s.state.store_zone(s.zone_id,s.world)
	check(s.state.zones[s.zone_id].units.has(kel.uid),"dismissed NPC body is saved with the zone")
	s.merc_changed(2,true,0)
	check(kel.get_meta("hero").exp==before.exp and kel.get_meta("hero").dex==before.dex,"live rehire keeps progress without replacing the actor")
	s.merc_changed(2,false,0,true,true)
	kel.set_meta("npc_character",CampaignState.npc_character(kel.info))
	s.merc_changed(2,true,0)
	check(kel.get_meta("hero").exp==before.exp and kel.get_meta("hero").dex==before.dex,"a fresh script character record cannot erase dismissed progress")
	var heroes:=s.party_heroes()
	var own:GameUnit=heroes.filter(func(u):return u!=kel)[0]
	g.selected.assign([own]);kel.controller=1
	var faces:=PartyFaces.new();faces.game=g;g.hud.add_child(faces);faces.hide();faces.set_process(false)
	faces._cells=[[own,null,true],[kel,null,false]]
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.double_click=true
	click.position=faces._r(faces._cell(1)).get_center()
	faces._gui_input(click);g.rig._follow(g,0.0)
	check(g.selected==[own] and g.rig.followed()==kel,"partner portrait double-click follows partner without changing selection")
	for mode in [2,3]:
		GameData.options.control_mode=mode;g.direct._process(0.0)
		faces._gui_input(click);g.direct.apply_camera()
		check(g.direct._portrait_target==kel and g.rig.position.distance_to(kel.global_position)<0.01,"partner portrait focuses remote actor in control mode "+str(mode))
		check(g.rig.presentation_focus().distance_to(kel.global_position+Vector3.UP*clampf(kel.figure_half_z*1.6,0.6,2.8))<0.01,"depth of field follows the inspected partner in mode "+str(mode))
		var key:=InputEventKey.new();key.physical_keycode=KEY_TAB;key.pressed=true
		g.direct.handle_input(key)
		check(g.direct._portrait_target==null,"Tab returns from partner inspection in mode "+str(mode))
	GameData.options.control_mode=1;kel.controller=0;faces.queue_free()
	g.direct._process(0.0)
	var ex:Dictionary=s.world.zone.exits[4]
	check(s.open_exit_at(ex.remove.get_center(),0)==4,"saved party can identify the unlocked LiA exit")
	for i in heroes.size():
		heroes[i].pos=ex.remove.get_center()+Vector2(i*.3,0);heroes[i]._sync_transform(0.0)
	s._leave_armed=4;s._check_exits()
	check(MessageBox.is_up(g.hud._leave_box),"the real exit confirmation opens for the saved party")
	if g.hud._leave_box:g.hud._leave_box.queue_free();g.hud._leave_box=null;g.hud._close_menu()
	s.apply_command({"t":"leave_exit","exit":4},0)
	check(not s.travel_options.is_empty() or s.zone_id!="gz1h","confirming the exit reaches the route selection or next map")
	g.queue_free();s.queue_free();await frames(8)
	print("LIA_PLAYER_SAVE ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
