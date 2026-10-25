extends "local_host_campaign.gd"
## A blocking driver compile cannot pump ENet. Exercise the real one-minute
## failure window, then require a fresh acknowledged command and world time.
func _ready()->void:
 process_mode=Node.PROCESS_MODE_ALWAYS
 GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
 GameData.options.merge({"auto_graphics":0,"display_mode":0,"fps_limit":2,"net_upnp":0,"net_websocket":0,"net_lan":0,"net_directory":0,"autosave":0,"show_tutorial":0,"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0},true)
 var s:=Session.new();get_parent().add_child(s)
 var g:=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
 check(await s.local_host.start(0,1,true)==OK,"separate local worker starts")
 await s.new_campaign(false)
 check(await until(func():return s.world!=null and not s._remote_loading,40),"campaign loads")
 g.set_speed(1)
 check(await until(func():return s.world.time>0.5),"authority advances before stall")
 var time:=s.world.time
 print("STALL_BEGIN ",Time.get_ticks_msec()," worker=",s.local_host._config)
 OS.delay_msec(90000)
 print("STALL_END ",Time.get_ticks_msec())
 check(await until(func():return s.world.time>time+0.5,5),"simulation resumes after blocking shader compile")
 check(s.local_host._process_alive() and s.online,"local authority remains connected")
 s.submit({"t":"console","line":"god on","request":18})
 check(await until(func():return s._input_out.pending.is_empty(),5),"new player command is acknowledged after compile")
 var resumed:=s.world.time
 check(await until(func():return s.world.time>resumed+0.5,5),"fresh simulation updates continue after recovery")
 await s.local_host.stop();g.queue_free();s.queue_free()
 for i in 8:await get_tree().process_frame
 print("LOCAL_HOST_SHADER_STALL ",checks," checks ",failures," failures")
 get_tree().quit(1 if failures else 0)
