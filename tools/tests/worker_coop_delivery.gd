extends Node
## Actual co-op simulation service + host presentation + ENet guest.
## Measures delivery cadence, not rendered FPS or CPU benchmark throughput.
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)
func until(predicate: Callable,seconds:=90.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await get_tree().process_frame
	return bool(predicate.call())
func wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds,true,false,true).timeout
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"net_websocket":0,"auto_graphics":0,"control_mode":1,"coop_clock":1},true)
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	var host:=Session.new();get_parent().add_child(host)
	var game:=Game.new();game.session=host;host.game=game;get_parent().add_child(game)
	check(await host.local_host.start(29931,2,false)==OK,"start real co-op simulation service")
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.own_world_3d=true;add_child(viewport)
	var api:=SceneMultiplayer.new();api.root_path=viewport.get_path();get_tree().set_multiplayer(api,viewport.get_path())
	var main:=Node.new();main.name="Main";viewport.add_child(main)
	var client:=Session.new();main.add_child(client)
	var cg:=Game.new();cg.session=client;client.game=cg;main.add_child(cg)
	GameData.player_name="Cadence Guest"
	check(client.join("127.0.0.1",29931)==OK,"guest joins service over ENet")
	check(await until(func():return client.my_index==1 and host.players.size()>=2),"separate host and guest identities")
	var source:="/home/llm2x/Documents/EI/local/lost-in-astral/checks/story-route6-profile/godot/app_userdata/Evil Islands Remake (PoC)/saves/lost_in_astral/lia_story_02_catacombs.sav"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):source=arg.trim_prefix("--save=")
	DirAccess.make_dir_recursive_absolute(SaveInfo.directory())
	var file:=FileAccess.open(SaveInfo.path("delivery"),FileAccess.WRITE)
	file.store_buffer(FileAccess.get_file_as_bytes(source));file.close()
	check(await host.load_game_shown("delivery"),"load existing Portal route checkpoint in service")
	check(await until(func():return client.zone_id==host.zone_id and not client._remote_loading and not client.loading_game and not client.party_units(1).is_empty()),"guest reaches loaded Portal")
	if failures:
		await host.local_host.stop();get_tree().quit(1);return
	Engine.max_fps=60
	var results:=[]
	for sector in [1,2]:
		await host.local_host.request("clock",{"sector":sector})
		await wait_real(1.0)
		var unit: GameUnit=client.party_units(1)[0]
		var pad:=cg.get_node("PadField") as PadField
		cg.selected.assign([unit])
		var times: Array[int]=[]
		var last: int=unit.net_view._last_ms
		var next_command:=0
		var start:=Time.get_ticks_msec()
		var sim_start:=client.world.time
		var initial:=unit.pos
		var distance:=0.0
		var previous:=unit.pos
		while Time.get_ticks_msec()<start+8000:
			var now:=Time.get_ticks_msec()
			if now>=next_command:
				next_command=now+400
				var direction:=Vector2.RIGHT if (now-start)<4000 else Vector2.LEFT
				var at:=pad._walk_goal(unit,direction)
				client.submit({"t":"move","units":[unit.uid],"x":at.x,"y":at.y,"line":true})
			if int(unit.net_view._last_ms)!=last:
				times.append(int(unit.net_view._last_ms)-last);last=unit.net_view._last_ms
			distance+=unit.pos.distance_to(previous);previous=unit.pos
			await get_tree().process_frame
		times.sort()
		var row:={"speed":sector,"packets":times.size(),"p95_gap_ms":times[int(times.size()*.95)] if not times.is_empty() else -1,"max_gap_ms":times[-1] if not times.is_empty() else -1,"distance":distance,"simulation_seconds":client.world.time-sim_start,"wall_seconds":(Time.get_ticks_msec()-start)/1000.0,"units":client.world.units.size()}
		results.append(row)
		check(times.size()>20 and row.max_gap_ms<1000,"service guest receives continuous updates at %dx" % sector)
		check(distance>1.0,"guest walk command advances through busy Portal at %dx" % sector)
	print("WORKER_COOP_DELIVERY ",JSON.stringify({"checks":checks,"failures":failures,"results":results}))
	client.online=false;client.multiplayer.multiplayer_peer.close()
	await host.local_host.stop()
	check(not host.local_host._process_alive(),"simulation service shuts down")
	viewport.queue_free();game.queue_free();host.queue_free()
	await wait_real(.2)
	get_tree().quit(1 if failures else 0)
