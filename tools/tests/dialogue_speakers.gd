extends "story_coop_traps_net.gd"
## Actual Ingos actors, authored camera directives and both ENet viewpoints.
## Initiating player changes; clicked topic owner and #show order must not
## replace the protagonist's native camera role.

func loaded() -> bool:
	return client.world != null and client.zone_id == "bz8k" and client.my_index == 1 \
		and not client._remote_loading and not client._zone_holding and not client.loading_game

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,
		"auto_graphics":0,"control_mode":1,"scroll_border":0},true)
	host = branch(false)
	check(host.host(29957,2)==OK,"open speaker-camera host")
	host.state = CampaignState.new(); host.state.ensure_hero(0,"Human Hero")
	host.state.set_var(0,"q.gz12k.q49k",2); host.state.set_var(0,"Tr49",2); host.state.set_var(0,"b.Shopper.Tr49_1",1)
	host.set_physics_process(false)
	await host.enter_zone("bz8k",1,false); freeze(host)
	host.set_physics_process(true) # Reliable state/zone transport must keep flushing.
	host.world.vm.instances.clear(); host.world.vm.briefings._check = INF
	client = branch(true); GameData.player_name = "Speaker Guest"
	check(client.join("127.0.0.1",29957)==OK,"connect speaker-camera guest")
	check(await until(loaded),"guest receives original Ingos cast")
	if client.world == null: await finish(); return
	freeze(client)
	client.set_physics_process(true)
	var shots := 0
	for player in [0,1]:
		for id: String in ["Tr49_1","G42","T42"]:
			var b := host.world.vm.briefings
			var owner := {"Tr49_1":"Shopper","G42":"Huber","T42":"Trapper"}[id] as String
			var partner: GameUnit = host.world.vm._by_name(owner)
			check(partner != null,"topic owner exists: "+owner)
			if partner == null: continue
			b.play_named(id,"b."+owner+"."+id,player,partner,true)
			host._send_snapshot_records(host.world.unit_rows().map(func(u):return u.snapshot()),host.world.time)
			check(await until(func():return client.game.hud._dialog._brief==id and client.game.hud._dialog.visible),"authored conversation reaches both peers")
			await frames(4)
			for s: Session in [host,client]:
				var panel := s.game.hud._dialog
				panel.set_process(false)
				check(panel._cast.a==host.party_units(player)[0].uid,"initiating protagonist owns camera slot a on peer %d"%s.my_index)
				for i in panel._phrases.size():
					panel._i=i; panel._show()
					var phrase: Dictionary = panel._phrases[i]
					var u: GameUnit = s.world.units.get(int(panel._cast.names.get(phrase.actor,-1)))
					check(u != null and u.visible,"%s/%d speaking actor stays visible on peer %d"%[id,i,s.my_index])
					var camera := int(phrase.camera)
					if camera not in [2,3,4,6,7,8,10,11,12] or u==null: continue
					var shot := DialogCamera.shot(s.world,panel._cast,phrase,i==0)
					var target: Vector3 = shot[1]
					# These original human scenes have zero forward camera offset.
					# The target must be at the actual speaker, not their listener.
					var authoritative: GameUnit = host.world.units[u.uid]
					check(Vector2(target.x,target.y).distance_to(authoritative.pos)<0.05,"%s/%d frames %s on peer %d"%[id,i,phrase.actor,s.my_index])
					check(s.game.rig._held_target.is_equal_approx(EISpace.vec(target)),"displayed shot advances with the phrase")
					shots+=1
					if id=="Tr49_1" and player==1 and i in [0,1,2] and DisplayServer.get_name()!="headless":
						await frames(3)
						s.game.get_viewport().get_texture().get_image().save_png("user://speaker-%d-peer-%d.png"%[i,s.my_index])
			b.complete(player,b.active,true)
			check(await until(func():return not client.game.hud._dialog.visible),"conversation closes on both peers")
	# Dragon dialogue lists SKD before Hero. Protagonist slot is independent
	# of both the click and the ordering of the first #show directive.
	var doc := Briefings.parse(GameData.text("briefing Dr22"))
	var cast := host.world.vm.briefings.cast(doc.actors,null,1)
	check(cast.a==host.party_units(1)[0].uid,"protagonist remains first even when #show Hero appears second")
	print("DIALOGUE_SPEAKERS shots=",shots," checks=",checks," failures=",failures)
	await finish()
