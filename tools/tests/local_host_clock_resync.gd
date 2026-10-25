extends "local_host_campaign.gd"
## A load/travel can restore the authority's clock between owner callbacks.
## An explicit Normal click must reassert the clock even if the cached owner
## value is already Normal, and movement must then advance on the authority.
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,
		"autosave":0,"show_tutorial":0,"confine_mouse":0,"show_fps":1,
		"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
	var s:=Session.new();get_parent().add_child(s)
	var g:=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"separate solo authority starts")
	await s.new_campaign(false)
	check(await until(func():return s.world!=null and not s._remote_loading,40),"campaign ready")
	s.submit({"t":"console","line":"god on","request":1})
	s.submit({"t":"console","line":"travel gz12k","request":2})
	check(await until(func():return s.zone_id=="gz12k" and not s._remote_loading,60),"reported snowy zone loads through the worker")
	s.submit({"t":"console","line":"teleport 177 188","request":3})
	var hero:GameUnit=s.party_heroes()[0]
	check(await until(func():return hero.pos.distance_to(Vector2(177,188))<0.5,5),"player reaches the reported snowy location")
	g.set_speed(1)
	check(await until(func():return s.world.time>0.5),"initial authority clock advances")
	check(await until(func():return not hero.blocked,30),"opening script releases player controls")
	# Reproduce a late authority pause with a still-current last-sent cache.
	s.local_host._rpc_single_clock.rpc_id(1,true,1.0,false,0)
	await get_tree().create_timer(0.3,true,false,true).timeout
	var stopped:=s.world.time
	await get_tree().create_timer(0.3,true,false,true).timeout
	check(s.world.time==stopped and not get_tree().paused,"authority paused while owner remains interactive")
	check(s.local_host._single_clock==[false,1.0,false,0],"last-sent cache matches the visible Normal choice")
	# Drive held movement explicitly rather than reading the test keyboard.
	g.direct.set_process(false)
	var start:=hero.pos
	var dial:=g.hud._clock_dial
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	var angle:=1.5*PI/6.0
	event.position=dial.size-Vector2(cos(angle),sin(angle))*72.0*dial._scale()
	dial._gui_input(event)
	check(await until(func():return s.world.time>stopped+0.3,3),"Normal click resumes actual authority despite unchanged cached choice")
	s.submit({"t":"direct_control","leader":hero.uid})
	for i in 60:
		s.submit({"t":"direct_move","units":[hero.uid],"direction":Vector2(1,0),"run":true})
		await get_tree().create_timer(0.033,true,false,true).timeout
	check(hero.pos.distance_to(start)>0.25,"held movement advances the player after resync")
	s.submit({"t":"direct_move","units":[hero.uid],"direction":Vector2.ZERO})
	check(await until(func():return s._input_out.pending.is_empty(),3),"movement is acknowledged")
	get_tree().paused=true
	await get_tree().create_timer(0.3,true,false,true).timeout
	stopped=s.world.time
	await get_tree().create_timer(0.3,true,false,true).timeout
	check(s.world.time==stopped,"ordinary owner pause still stops the authority")
	g.set_speed(2)
	check(await until(func():return s.world.time>stopped+0.5,3),"Fast click resumes from an ordinary pause")
	await s.local_host.stop();g.queue_free();s.queue_free()
	for i in 8:await get_tree().process_frame
	print("LOCAL_HOST_CLOCK_RESYNC ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
