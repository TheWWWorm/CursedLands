extends "local_host_campaign.gd"
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge({"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"show_tutorial":0},true)
	var s:=Session.new();get_parent().add_child(s)
	var g:=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	check(await s.local_host.start(0,1,true)==OK,"solo authority starts")
	await s.new_campaign(false)
	check(await until(func():return s.world!=null and not s._remote_loading,30),"solo world arrives")
	for speed in [0,1]:
		for paused in [false,true]:
			s.restore_play_clock({"paused":paused,"speed":speed})
			var slot:="clock-worker-%s-%s"%[speed,paused]
			var answer:=await s.local_host.request("save",{"slot":slot,"camera":s.local_host.view()})
			check(answer.get("ok",false),"save via solo worker")
			var state:=CampaignState.load_from(SaveInfo.path(slot))
			check(state!=null and state.play_clock=={"paused":paused,"speed":speed},"worker save keeps gameplay clock")
			s.restore_play_clock({"paused":not paused,"speed":1-speed})
			answer=await s.local_host.request("load",{"slot":slot})
			check(answer.get("ok",false),"load via solo worker")
			check(await until(func():return not s._remote_loading and g.speed==speed and get_tree().paused==paused,30),"owner restores speed and pause after worker load")
			check(is_equal_approx(Engine.time_scale,55.0/27.0 if speed else 1.0),"owner simulation rate restored")
	s.restore_play_clock({})
	await s.local_host.stop()
	print("LOCAL_HOST_PLAY_CLOCK ",checks," checks ",failures," failures")
	get_tree().quit(1 if failures else 0)
