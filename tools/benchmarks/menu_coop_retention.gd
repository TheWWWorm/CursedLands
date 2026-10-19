extends "saved_coop_traversal.gd"
## Sustained play with real menu ownership. The driver is a root sibling so
## Main can destroy/recreate every menu, lobby, game and session normally.
## Menu operations use pointer/key events against visible controls; they never
## call lifecycle handlers, emit button signals, or instantiate game screens.
var main: Node
var menu_cycles := 3
var smoke_rounds := 0
var menu_actions := []
var menu_busy := false
var finishing := false

func require(value: bool, label: String) -> bool:
	if value: return true
	printerr("MENU_PLAY_FAILED ", label)
	get_tree().quit(2)
	return false

func note(action: String) -> void:
	var row := {"seconds":Time.get_ticks_msec()/1000.0,"peer":"guest" if guest else "owner","action":action}
	menu_actions.append(row)
	FileAccess.open("user://menu-actions-"+("guest" if guest else "owner")+".json",FileAccess.WRITE).store_string(JSON.stringify(menu_actions,"\t"))
	print("MENU_PLAY ",JSON.stringify(row))

func pointer(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	if not require(get_viewport().get_visible_rect().has_point(at),"click inside window: "+str(at)): return
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var motion:=InputEventMouseMotion.new();motion.position=at
	Input.parse_input_event(motion)
	await frames_wait(2)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.button_index=button;event.pressed=pressed
		Input.parse_input_event(event);await frames_wait(2)

func key(code: Key, unicode := 0) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.unicode=unicode;event.pressed=pressed
		get_viewport().push_input(event);await frames_wait(2)

func click_control(control: Control, label: String) -> void:
	if not require(is_instance_valid(control) and control.is_visible_in_tree(),"visible "+label):return
	if control is BaseButton and not require(not control.disabled,"enabled "+label):return
	var at:=control.get_global_transform_with_canvas()*(control.size/2)
	print("MENU_POINTER ",JSON.stringify({"action":label,"peer":"guest" if guest else "owner","position":[at.x,at.y]}))
	note(label);await pointer(at);await frames_wait(5)

func scout_click(control: Control, label: String) -> void:
	# Scouting is optional. Round transitions rebuild/hide these controls;
	# a stale button is not a failed lobby/save/exit lifecycle assertion.
	if not is_instance_valid(control) or control.is_queued_for_deletion() or not control.is_visible_in_tree():return
	if control is BaseButton and control.disabled:return
	await click_control(control,label)

func find_button(root: Node, title: String) -> Button:
	for node in root.find_children("*","Button",true,false):
		if node.is_visible_in_tree() and not node.disabled and node.text==RemakeText.t(title):return node
	return null

func click_text(root: Node, title: String) -> void:
	await click_control(find_button(root,title),title)

func target(control: Node, id: String) -> void:
	await frames_wait(4)
	var at:=Vector2(-1,-1)
	for item:Dictionary in control.pad_targets():
		if str(item.id)==id:at=(item.rect as Rect2).get_center();break
	if not require(at.x>=0,"visible target "+id):return
	note(id);await pointer(at);await frames_wait(8)

func row_text(panel: NetworkPanel, id: String, text: String) -> void:
	await pointer(panel.target_point("row:"+id))
	# These native text rows append at the end; Backspace is their normal edit.
	for i in 40:await key(KEY_BACKSPACE)
	for c in text:await key(KEY_NONE,c.unicode_at(0))
	note("typed "+id+": "+text)

func choose_save(panel: NetworkPanel, slot: String) -> void:
	var choice:OptionButton=panel._save_choice
	var index:=-1
	for i in choice.item_count:
		if str(choice.get_item_metadata(i))==slot:index=i;break
	if not require(index>=0,"save offered "+slot):return
	await click_control(choice,"open saved-game choices")
	await until(func():return choice.get_popup().visible,5)
	var popup:=choice.get_popup()
	for step in choice.item_count+2:
		if popup.get_focused_item()==index:break
		for pressed in [true,false]:
			var event:=InputEventKey.new();event.keycode=KEY_DOWN;event.physical_keycode=KEY_DOWN;event.pressed=pressed;event.window_id=popup.get_window_id();Input.parse_input_event(event);await frames_wait(2)
	print("MENU_SAVE_FOCUS ",index," ",popup.get_focused_item()," ",popup.get_window_id()," ",popup.visible)
	await shot_menu("save-choices")
	var enter:=InputEventKey.new();enter.keycode=KEY_ENTER;enter.physical_keycode=KEY_ENTER;enter.pressed=true;enter.window_id=popup.get_window_id();Input.parse_input_event(enter)
	await frames_wait(8)
	print("MENU_SAVE_SELECTION ",panel.start_slot," ",CoopProgress.bring_slot)
	require((panel.start_slot if panel.page==NetworkPanel.HOST_COOP else CoopProgress.bring_slot)==slot,"selected save "+slot)
	note("selected save "+slot)

func current_menu() -> Control:
	for node in main.get_children():
		if node.get_script()==load("res://src/ui/main_menu.gd") and not node.is_queued_for_deletion():return node
	return null

func current_lobby() -> ArenaOnlineLobby:
	for node in main.get_children():
		if node is ArenaOnlineLobby and not node.is_queued_for_deletion():return node
	return null

func shot_menu(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://menu-"+("guest" if guest else "owner")+"-"+label+".png")

func before_campaign() -> void:
	main=get_parent();reparent(get_tree().root)
	process_mode=Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-cycles="):menu_cycles=int(arg.trim_prefix("--menu-cycles="))
		if arg.begins_with("--menu-smoke-rounds="):smoke_rounds=int(arg.trim_prefix("--menu-smoke-rounds="))
	GameData.player_name="Save test caster" if guest else "Save test fighter"
	GameData.arena_mode=1
	for pair in [["supplied-host",host_source],["supplied-guest",guest_source]]:
		var state:=CampaignState.load_from(pair[1])
		SaveInfo.write(pair[0],state.world_time,"suslanger",state.current_zone,"Supplied friend" if pair[0]=="supplied-guest" else "Supplied host")
	# Bootstrap only: subsequent transitions must come from the menu itself.
	await main.open_menu();await frames_wait(40);apply_window_size()
	await shot_menu("initial")
	if not guest:child=launch_guest(guest_arguments())
	for cycle in menu_cycles:await full_tournament(cycle)

func guest_arguments() -> PackedStringArray:
	var args:=super.guest_arguments()
	args.append("--menu-cycles="+str(menu_cycles))
	if smoke_rounds>0:args.append("--menu-smoke-rounds="+str(smoke_rounds))
	return args

func online_lobby(cycle: int) -> ArenaOnlineLobby:
	var menu:=current_menu()
	await click_control(menu._arena_pve_button,"Trials of the Allods")
	if not require(await until(func():return main.get_children().any(func(n):return n is ArenaPveScreen),20),"Trials landing"):return null
	var landing:Node=main.get_children().filter(func(n):return n is ArenaPveScreen)[0]
	await click_text(landing,"Play online")
	if not require(await until(func():return current_lobby()!=null,15),"online lobby"):return null
	var lobby:=current_lobby();var panel:=lobby.panel
	await pointer(panel.target_point("mode:join_coop" if guest else "mode:host_coop"));await frames_wait(10)
	if guest:
		await row_text(panel,"addr","127.0.0.1:27016")
		if not require(await until(func():return FileAccess.file_exists("user://menu-hosted-%d"%cycle),90),"host opened room"):return null
	await shot_menu("lobby-%d"%cycle)
	await pointer(panel.target_point("ok"));note("join room" if guest else "host room")
	if guest:
		if not require(await until(func():return lobby.connection!=null and lobby.connection.my_seat>=0,90),"joined room"):return null
		await pointer(panel.target_point("ok"));note("ready in lobby")
	else:
		if not require(await until(func():return lobby.connection!=null and lobby.connection.owns_game(),90),"host listening"):return null
		FileAccess.open("user://menu-hosted-%d"%cycle,FileAccess.WRITE).store_string("ready")
		if not require(await until(func():return lobby.connection.members.size()==2 and lobby.connection.members.values().all(func(m):return m.ready),90),"friend ready"):return null
		await pointer(panel.target_point("ok"));note("start tournament")
	if not require(await until(func():return lobby.screen!=null,90),"match screen"):return null
	return lobby

func arrange_ui() -> void:
	await click_control(tournament_screen._menu,"Menu")
	await click_text(tournament_screen._modal_box,"Auto arrange")

func shop_action(intent: Dictionary) -> void:
	if not intent.has("action"):return
	match str(intent.action):
		"buy":
			var i:=int(intent.args[0]);var card:Control=tournament_screen._shop.get_child(i).get_child(0)
			if card is ArenaCreatureCard and not card.disabled:
				await click_control(card,"recruit %d"%i);await frames_wait(15);await arrange_ui()
		"train":await click_control(tournament_screen._train_button,"buy experience")
		"refresh":await click_control(tournament_screen._refresh_button,"reroll shop")
		"sell":
			var uid:=int(intent.args[0]);var selected:=false
			for button in tournament_screen._army_row.get_children():
				if int(button.get_meta("arena_creature",{}).get("uid",-1))==uid:
					await click_control(button,"select reserve for sale");selected=true;break
			if not selected:
				for unit in tournament_screen.battle.world.unit_rows():
					if int(unit.get_meta("arena_placement",{}).get("run_uid",-1))==uid:
						await pointer(tournament_screen.field.camera.unproject_position(unit.global_position+Vector3.UP*.5));break
			if tournament_screen.selected_uid==uid and tournament_screen._sell_target.visible:
				await click_control(tournament_screen._sell_target,"sell unit")

func full_tournament(cycle: int) -> void:
	census("menu-before-tournament-%d"%cycle)
	var lobby:=await online_lobby(cycle)
	if lobby==null:return
	tournament=lobby.connection;tournament_screen=lobby.screen
	await frames_wait(15);apply_window_size()
	var round_number:=-1;var plan:={};var ready_sent:=false
	var next_action:=0;var next_watch:=0;var next_measure:=0;var watching:=0
	var frame_count:=0;var measured_at:=Time.get_ticks_msec();var start:=measured_at
	while tournament.view.global_stage!="won":
		var now:=Time.get_ticks_msec();var view:=tournament.view
		if not require(now-start<3600000,"tournament within one hour"):return
		if smoke_rounds>0 and view.wave>smoke_rounds:break
		if view.lives<=0:
			var eliminated:="user://menu-eliminated-%d-"%cycle
			FileAccess.open(eliminated+("guest" if guest else "owner"),FileAccess.WRITE).store_string(str(view.wave))
			if FileAccess.file_exists(eliminated+"owner") and FileAccess.file_exists(eliminated+"guest"):break
		if view.wave!=round_number:
			round_number=view.wave;plan={"done":false,"actions":0,"rerolls":0};ready_sent=false
		if not guest and view.battle_speed!=2 and tournament_screen._speed.visible:
			await click_control(tournament_screen._speed,"2x battle speed")
		if now>=next_action and view.global_stage=="prepare" and not view.preparing_battle and view.lives>0:
			next_action=now+1200
			if tournament_screen.field.showing_boards():
				await scout_click(find_button(tournament_screen._overview_bar,"Your board"),"Your board")
				if tournament_screen.field.showing_boards():continue
			if not plan.done:
				var copy:=ShopPlan.new();copy.auto_save=false;var snap:=view.snapshot()
				for property in ["gold","army","shop","lives","training","stage","wave","history","free_refresh","next_uid","boons"]:copy.set(property,snap[property])
				ArenaBotPlanner.step(copy,2 if guest else 3,view.wave,view.lives,plan)
				await shop_action(copy.intent)
			elif not ready_sent:
				if not view.ready_seats.has(tournament.my_seat):await click_control(tournament_screen._start,"ready for battle")
				ready_sent=true
		if now>=next_watch and view.global_stage=="fight":
			next_watch=now+15000;watching+=1
			# ArenaTooltips moves native tooltip text into its own registry.
			# The overview button is the second visible toolbar control.
			if watching%3==0 and not tournament_screen.field.showing_boards():
				if tournament_screen._standing_rows.get_child_count()>0 and tournament_screen._standing_rows.get_child(0).get_child_count()>1:
					await scout_click(tournament_screen._standing_rows.get_child(0).get_child(1),"nine-board overview")
			if watching%3!=0 and tournament_screen.field.showing_boards():
				await scout_click(find_button(tournament_screen._overview_bar,"Your board"),"Your board")
			for button in tournament_screen._standing_rows.find_children("*","Button",true,false):
				if watching%3!=0 and button.is_visible_in_tree() and not button.is_queued_for_deletion() and button.has_meta("board_player") and int(button.get_meta("board_player"))==(0 if view.lives>0 else view.alive_players()[watching%view.alive_players().size()]) and not button.disabled:
					await scout_click(button,"watch board");break
		if now>=next_measure:
			next_measure=now+30000
			census("menu-tournament-%d-round-%d-%s"%[cycle,view.wave,view.global_stage],float(frame_count)*1000/maxi(1,now-measured_at))
			print("MENU_MATCH ",JSON.stringify({"cycle":cycle,"round":view.wave,"health":view.lives,"alive":view.alive_players().size(),"seconds":(now-start)/1000.0,"peer":"guest" if guest else "owner"}))
			frame_count=0;measured_at=now;await shot_menu("tournament-%d-%04d"%[cycle,int((now-start)/1000)])
		frame_count+=1;await get_tree().process_frame
	census("menu-tournament-%d-complete-round-%d-place-%d"%[cycle,tournament.view.wave,tournament.view.placements[0]])
	old_worlds.append(weakref(tournament_screen.battle.world))
	for board in tournament_screen._tournament_battles.boards.values():old_worlds.append(weakref(board.world))
	# The guest leaves first through the actual confirmation. The host then
	# leaves through its confirmation, exercising both teardown paths.
	if not guest:await until(func():return FileAccess.file_exists("user://menu-left-%d-guest"%cycle),60)
	await click_control(tournament_screen._menu,"Menu")
	await click_text(tournament_screen._modal_box,"Main menu")
	await shot_menu("leave-confirm-%d"%cycle)
	await click_text(tournament_screen._modal_box,"Leave game")
	if not require(await until(func():return current_menu()!=null,90),"returned to main menu"):return
	tournament=null;tournament_screen=null
	await frames_wait(120);census("menu-tournament-%d-returned"%cycle);await shot_menu("returned-%d"%cycle)
	FileAccess.open("user://menu-left-%d-"%cycle+("guest" if guest else "owner"),FileAccess.WRITE).store_string("ready")
	await until(func():return FileAccess.file_exists("user://menu-left-%d-owner"%cycle) and FileAccess.file_exists("user://menu-left-%d-guest"%cycle),60)

func open_campaign() -> void:
	var menu:=current_menu()
	await target(menu._scene,"multiplayer")
	var panel:NetworkPanel=menu._net
	await pointer(panel.target_point("mode:join_coop" if guest else "mode:host_coop"));await frames_wait(8)
	await choose_save(panel,("" if checkpoint else "supplied-guest") if guest else "supplied-host")
	if guest:
		await row_text(panel,"addr","127.0.0.1:27015")
		if not require(await until(func():return FileAccess.file_exists("user://menu-campaign-hosted"),90),"campaign room ready"):return
	await shot_menu("campaign-lobby")
	await pointer(panel.target_point("ok"));note("join campaign" if guest else "host campaign")
	if not guest:
		if not require(await until(func():return menu._session!=null and panel.hosting,90),"campaign host listening"):return
		FileAccess.open("user://menu-campaign-hosted",FileAccess.WRITE).store_string("ready")
		if not require(await until(func():return menu._session.players.size()==2,90),"friend in campaign lobby"):return
		await pointer(panel.target_point("ok"));note("load selected campaign save")
	if not require(await until(func():return main.game!=null and main.session!=null,90),"menu created campaign"):return
	s=main.session;g=main.game;observe_game()
	s.message.connect(func(message:String):print("SAVED_COOP_MESSAGE ",message))
	note("campaign entered from lobby")

func leave_for_next_zone(h: GameUnit,t: float) -> bool:
	if MessageBox.is_up(g.hud._leave_box):
		if not menu_busy:accept_map_exit.call_deferred()
		return true
	if g.hud._travel.visible:
		if not menu_busy:pick_next_map.call_deferred()
		return true
	var choices:=[]
	for number in s.world.zone.get("exits",{}):
		var ex:Dictionary=s.world.zone.exits[number]
		if ex.has("remove") and s.campaign.zone(String(ex.get("to","none"))).get("type","")=="edge" and s._exit_is_open(int(number),s.my_index):
			choices.append({"number":int(number),"rect":ex.remove,"point":(ex.remove as Rect2).get_center()})
	if choices.is_empty():return false
	choices.sort_custom(func(a,b):return h.pos.distance_squared_to(a.point)<h.pos.distance_squared_to(b.point))
	var choice:Dictionary=choices[0];changing_location=true;stage="walking to map exit"
	write_group({"target":-1,"point":[h.pos.x,h.pos.y]})
	# Ground activation carries the ordinary exit-click tag. A raw movement
	# command deliberately does not arm an exit when auto-exit is disabled.
	if t-exit_requested_at>3 and (move_goal.distance_to(choice.point)>=2 or h.action not in ["walk","run"]):
		g.order_on(null,false,null,-1,choice.point)
		move_goal=choice.point;attempts.move+=1;exit_requested_at=t
	return true

func accept_map_exit() -> void:
	menu_busy=true
	await shot_menu("map-exit-"+s.zone_id)
	await target(g.hud._leave_box,"ok")
	menu_busy=false

func pick_next_map() -> void:
	menu_busy=true
	var map:TravelMap=g.hud._travel.get_child(0)
	var candidates:=[]
	for target_info:Dictionary in map.pad_targets():
		if not str(target_info.id).begins_with("piece"):continue
		var i:=int(str(target_info.id).trim_prefix("piece"));var piece:Dictionary=map._pieces[i]
		var id:=str(piece.get("id",piece.get("zone","")))
		if id!=s.zone_id and map.options.any(func(o):return str(o.zone)==id):candidates.append({"id":id,"point":target_info.rect.get_center()})
	candidates.sort_custom(func(a,b):return int(zone_visits.get(a.id,0))<int(zone_visits.get(b.id,0)))
	if candidates.is_empty():
		print("MENU_TRAVEL_TARGETS ",map._pieces," ",map.options)
		require(false,"clickable next map")
	else:
		await shot_menu("travel-map-"+s.zone_id);note("click map "+str(candidates[0].id));await pointer(candidates[0].point)
		await frames_wait(10)
		# Enter confirms the original zone objectives / entrance screen.
		await shot_menu("travel-objectives-"+s.zone_id);await key(KEY_ENTER)
	menu_busy=false

func decide(t: float) -> void:
	if menu_busy or (not guest and s.map_open):
		if not guest and s.map_open and not menu_busy:pick_next_map.call_deferred()
		return
	super.decide(t)

func finish() -> void:
	if finishing:return
	finishing=true;_running=false
	census("menu-campaign-complete")
	if guest:await until(func():return FileAccess.file_exists("user://menu-campaign-saved"),45)
	else:
		await key(KEY_ESCAPE);await frames_wait(45);await target(g.hud._menu,"save")
		if require(await until(func():return g.hud._save_load.visible,10),"save screen"):
			await shot_menu("campaign-save");await key(KEY_ENTER);await frames_wait(120)
		FileAccess.open("user://menu-campaign-saved",FileAccess.WRITE).store_string("ready")
	old_worlds.append(weakref(s.world))
	if not guest:await until(func():return FileAccess.file_exists("user://menu-campaign-guest-left"),45)
	await key(KEY_ESCAPE);await frames_wait(45);await target(g.hud._menu,"exit");await frames_wait(8)
	await shot_menu("campaign-exit-confirm");await key(KEY_ENTER)
	if not require(await until(func():return current_menu()!=null,90),"campaign returned to menu"):return
	g=null;s=null;observed.game=null
	await frames_wait(120);census("menu-campaign-returned");await shot_menu("campaign-returned")
	if guest:FileAccess.open("user://menu-campaign-guest-left",FileAccess.WRITE).store_string("ready")
	note("normal main-menu exit")
	await target(current_menu()._scene,"exit")
