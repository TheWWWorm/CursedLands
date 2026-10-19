extends "arena_expansion_ui.gd"
## Native village offers, touch acceptance/reopen and browser-sized safe areas.
class QuestGame extends Game:
	var accepted := ""
	func issue(command: Dictionary) -> void:
		accepted = command.get("q", "")
		session.state.side_quests[accepted] = "active"

func tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position=point; event.index=0; event.pressed=pressed
		Input.parse_input_event(event); await frames(3)

func _ready() -> void:
	OS.add_logger(errors); await frames(8)
	GameData._window_gen+=1
	GameData.options.merge({"confine_mouse":0,"auto_graphics":0,"show_tutorial":0},true)
	get_window().mode=Window.MODE_WINDOWED
	get_window().position=Vector2i.ZERO
	TouchInput.enabled=true; TouchInput.pinned=true
	var session:=Session.new()
	session.campaign=CampaignMap.load_from(GameData.texts)
	session.state=CampaignState.new()
	for id in session.campaign.zones: session.state.visited[id]=true
	var world:=GameWorld.new(); session.world=world
	var chosen: Dictionary={}; var most:=0
	for zone: Dictionary in session.campaign.zones.values():
		if zone.get("type","")!="brief": continue
		world.zone=zone
		var count:=SideQuests.offers(session).size()
		if count>most: most=count; chosen=zone
	world.zone=chosen
	check(most>=3,"multiple original quest offers are available")
	var game:=QuestGame.new(); game.session=session
	var hud:=GameHUD.new(); hud.game=game
	var safe:=Control.new(); add_child(safe)
	for language in ["en","ru","de"]:
		RemakeText.lang=language
		var panel:=SideQuestPanel.new(); panel.hud=hud; safe.add_child(panel)
		for dimensions in [Vector2i(360,800),Vector2i(800,360),Vector2i(1280,800)]:
			get_window().size=dimensions; await frames(4)
			safe.position=Vector2(12,12); safe.size=Vector2(dimensions)-Vector2(24,24)
			session.state.side_quests.clear(); game.accepted=""; panel.open(); await frames(15)
			var bounds:=safe.get_global_rect()
			check(bounds.encloses(panel.get_global_rect()),"offer panel fits safe area %s %s"%[language,dimensions])
			check(panel._scroll.get_v_scroll_bar().max_value>panel._scroll.size.y,"long native list scrolls")
			check(bounds.encloses(panel._close.get_global_rect()),"Close stays accessible")
			check(panel._close.size.y>=TouchInput.target_pixels(),"Close meets touch target size")
			if dimensions.x==360:
				await shot("quest-offers-"+language)
				get_window().size=Vector2i(800,360); await frames(4)
				safe.size=Vector2(776,336); await frames(10)
				check(safe.get_global_rect().encloses(panel.get_global_rect()),"open offers recenter after rotation")
				get_window().size=dimensions; await frames(4)
				safe.size=Vector2(dimensions)-Vector2(24,24); await frames(10)
			# A touch drag scrolls the list without accepting the button it starts on.
			var start:=panel._scroll.get_global_rect().get_center()
			var press:=InputEventScreenTouch.new(); press.position=start; press.pressed=true
			Input.parse_input_event(press); await frames(2)
			for i in 5:
				var drag:=InputEventScreenDrag.new(); drag.position=start-Vector2(0,(i+1)*12); drag.relative=Vector2(0,-12)
				Input.parse_input_event(drag); await frames(2)
			press=InputEventScreenTouch.new(); press.position=start-Vector2(0,60)
			Input.parse_input_event(press); await frames(3)
			check(game.accepted.is_empty() and panel.visible and panel._scroll.scroll_vertical>0,"touch scroll never accepts an offer")
			panel._scroll.ensure_control_visible(panel._list.get_child(1)); await frames(6)
			await tap(panel._list.get_child(1).get_global_rect().get_center())
			check(not game.accepted.is_empty() and not panel.visible,"touch accepts native quest and closes offers")
			panel.open(); await frames(12)
			check(panel._list.get_child_count()==1 and panel._list.get_child(0).text==RemakeText.t("Finish your current task first."),"accepted task has a compact localized panel")
			check(bounds.encloses(panel.get_global_rect()) and panel.position.y>0,"reopened active quest remains centered and accessible")
			await shot("quest-"+language+"-"+str(dimensions.x))
			await tap(panel._close.get_global_rect().get_center())
			check(not panel.visible,"touch closes reopened active quest panel")
		panel.queue_free(); await frames(3)
	safe.queue_free(); hud.free(); game.free(); session.world=null; world.free(); session.free()
	TouchInput.pinned=false; TouchInput.enabled=false
	await frames(6); OS.remove_logger(errors)
	check(errors.messages.is_empty(),"no runtime errors: "+str(errors.messages))
	print("SIDE_QUEST_PANEL_UI ",checks," checks; failures=",JSON.stringify(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
