extends "story_coop_traps_net.gd"
## Actual Dead City actor and original Dr20 phrases on two ENet peers.
## Unrelated simulation is paused; ordinary idle/snapshot calls remain part
## of the checks. This does not change dragon movement or quest conditions.
const DRAGON := 1000002518

func loaded() -> bool:
	return client.world != null and client.zone_id == "bz3g" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game

func bottom(u: GameUnit) -> float:
	var y := INF
	for m: MeshInstance3D in u.model.find_children("*","MeshInstance3D",true,false):
		if m.mesh == null: continue
		for p: Vector3 in m.mesh.get_faces(): y = minf(y,(m.global_transform*p).y-u.global_position.y)
	return y

func pose(s: Session, index: int) -> void:
	var panel := s.game.hud._dialog
	panel._i = index; panel._show()
	var u: GameUnit = s.world.units[DRAGON]
	u._set_action("idle"); u._update_pose()
	if s == client: u.apply_snapshot(host.world.units[DRAGON].snapshot(),true)
	# Evaluate a real authored pose after blend completion.
	u.model.player.advance(0.4)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,
		"net_directory":0,"auto_graphics":0,"scroll_border":0},true)
	host = branch(false); check(host.host(29944,2)==OK,"open dialogue host")
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.set_physics_process(false)
	await host.enter_zone("bz3g",1,false); freeze(host)
	var dragon: GameUnit = host.world.units.get(DRAGON)
	check(dragon != null and dragon.model.template == "unmodg","original Dead City SKD uses dragon model")
	if dragon == null: await finish(); return
	dragon.model.player.advance(0.4)
	var flying_bottom := bottom(dragon)
	print("DRAGON_IDLE clip=",dragon.model._current," bottom=",flying_bottom," altitude=",dragon.proto.altitude)
	check(dragon.model._current=="cidle" and dragon.race.locomotion==2,"ordinary flying idle and movement class remain authored")
	client = branch(true); GameData.player_name = "Dragon Guest"
	check(client.join("127.0.0.1",29944)==OK,"connect dialogue guest")
	check(await until(loaded),"guest receives original Dead City actor")
	if client.world == null: await finish(); return
	freeze(client)
	host.world.vm.briefings.play_named("Dr20","b.bz3g.Dr20",0,null,true)
	check(await until(func():return client.game.hud._dialog.visible),"original briefing event reaches both peers")
	var hp := host.game.hud._dialog; var cp := client.game.hud._dialog
	hp.set_process(false); cp.set_process(false)
	check(hp._phrases==cp._phrases and hp._cast==cp._cast,"both peers share original phrases and actor identities")
	var ground_bottom := INF
	var captured := false
	for i in hp._phrases.size():
		var phrase: Dictionary = hp._phrases[i]
		var speaking := String(phrase.actor)=="skd"
		var special := int(phrase.get("anim",0)) if speaking else 0
		if special<1: special = 1 if speaking else 2
		var expected := "ubriefing%02d"%special
		for s: Session in [host,client]:
			pose(s,i)
			var u: GameUnit = s.world.units[DRAGON]
			check(u.model._current==expected,"peer %d phrase %d keeps original %s through idle/snapshot"%[s.my_index,i+1,expected])
			var hero: GameUnit = s.world.units.get(int(hp._cast.names.get("hero",-1)))
			if i==0 and hero:
				var record: Array = hero.model.adb.filter(func(r):return r.name==hero.model._current)
				var allowed := [int(phrase.anim)] if int(phrase.anim)>0 else [1,6,7,8]
				if String(phrase.actor)!="hero": allowed = [2,10,12,13]
				check(not record.is_empty() and int(record[0].code)&0x3c0000==0x40000 \
					and (int(record[0].code)>>22)&255 in allowed,"peer %d human uses original dialogue special table"%s.my_index)
			if s==host and ground_bottom==INF:
				ground_bottom = bottom(u)
				print("DRAGON_DIALOGUE clip=",u.model._current," bottom=",ground_bottom)
				u.model.player.advance(20.0); u.model._process(0.0)
				check(u.model._current=="ubriefing02" and u.model.player.is_playing(),"finished speaking special resumes original listening pose")
		var view := DialogCamera.shot(host.world,hp._cast,phrase,i==0)
		if not captured and DisplayServer.get_name()!="headless" and view.size()>1 \
				and i==2:
			await frames(8)
			var file := "user://dragon-dialogue.png"
			check(get_viewport().get_texture().get_image().save_png(file)==OK,"capture original dragon dialogue view")
			print("DRAGON_IMAGE ",ProjectSettings.globalize_path(file))
			captured = true
	if DisplayServer.get_name()!="headless": check(captured,"captured an authored dragon-facing shot")
	check(ground_bottom < flying_bottom-2.0,"authored dialogue pose brings dragon down to the ground")
	# Explicit #animation and skip are presentation directives, tested without
	# applying or inventing any campaign reward or completion flag.
	hp._phrases = [{"actor":"skd","speaker":"Old Dragon","text":"Animation probe","anim":5}]
	hp._i=0; hp._show(); dragon._set_action("idle")
	check(dragon.model._current=="ubriefing05","explicit phrase animation selects special modifier five")
	hp._skipping=true; hp._show(); hp._skipping=false
	check(dragon.model._current=="ubriefing02","skip leaves the dragon listening")
	# A dialogue pose must not prevent a real movement/death action.
	dragon.model.act("walk")
	check(dragon.model._current.begins_with("cflight"),"ordinary flying movement can replace dialogue presentation")
	dragon._set_action("idle")
	check(dragon.model._current=="ubriefing02","idle returns to listening while dialogue remains open")
	host.broadcast({"t":"dialog_close","id":"b.bz3g.Dr20"})
	check(await until(func():return not cp.visible),"remote close reaches guest")
	for s: Session in [host,client]:
		var u: GameUnit = s.world.units[DRAGON]
		u._set_action("idle"); u.model.player.advance(0.4)
		check(u.model._current=="cidle","peer %d releases dialogue pose on close"%s.my_index)
	check(dragon.race.locomotion==2 and dragon.proto.altitude==7.0,"dialogue never rewrites flying physics or prototype altitude")
	print("DIALOGUE_POSES ",checks," checks ",failures," failures")
	await finish()
