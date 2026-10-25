extends "local_host_campaign.gd"
var out:=""
var rows:=[]
var s:Session
var g:Game
var camera:Camera3D
func status()->Dictionary:
 return RtxGraphics.bridge().call("get_status") if RtxGraphics.bridge() else {}
func phase(label:String,enable:bool,moving:bool)->void:
 GameData.options.rtx_frame_generation=int(enable)
 await get_tree().create_timer(1.0,true,false,true).timeout
 var before:=status()
 var original:=camera.global_transform
 var began:=Time.get_ticks_msec()
 var count:=0
 var active:=0
 while Time.get_ticks_msec()-began<12000:
  var sec:=(Time.get_ticks_msec()-began)/1000.0
  if moving:
   camera.global_transform=original
   camera.global_position+=original.basis.x*sin(sec*0.7)*2.5
   camera.rotate_y(sin(sec*0.9)*0.25)
  await RenderingServer.frame_post_draw
  count+=1
  if status().get("frame_generation_active",false):active+=1
 var after:=status()
 var presented:=int(after.get("presented_frames",0))-int(before.get("presented_frames",0))
 var game_presents:=int(after.get("game_presents",0))-int(before.get("game_presents",0))
 check(after.get("last_error",-1)==0,label+" SDK success")
 check(active>count*0.95 if enable else active==0,label+" actual requested FG state")
 check(presented>game_presents*1.8 and presented<game_presents*2.2 if enable else presented==0,label+" SDK confirms actual generated presentation")
 var rt:=g.get_node("SceneRaytrace")
 check(rt.stats.get("active",false) and rt.device.nrd_active,label+" actual PT and native NRD")
 rows.append({"label":label,"fg":enable,"frames":count,"active_frames":active,"game_presents":game_presents,"sdk_presents":presented,"status":after,"world_time":s.world.time,"window":get_window().size,"actual_window":DisplayServer.window_get_size(),"gate":FsrGraphics.campaign_gate(get_tree(),camera)})
 print("SNOW_PHASE ",JSON.stringify(rows[-1]))
 camera.global_transform=original
func _ready()->void:
 process_mode=Node.PROCESS_MODE_ALWAYS
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--audit-out="):out=arg.trim_prefix("--audit-out=")
 if not RtxGraphics.facts().fg:
  print("SNOW_FRAMEGEN blocked ",RtxGraphics.facts());get_tree().quit(2);return
 GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
 GameData.options.merge({"confine_mouse":0,"show_fps":1,"volume_sfx":0,"volume_stream":0,"volume_voice":0,
  "auto_graphics":0,"display_mode":0,"vsync":0,"fps_limit":0,"q_aa":0,"gfx_soft_ground":0,"gfx_ground_contact":0,
  "gfx_terrain":1,"q_shadows":2,"gfx_depth_of_field":0,"gfx_weather_surfaces":1,"gfx_water_reflections":3,
  "pt_mode":1,"q_rt_lighting":0,"pt_accumulation":0,"rtx_upscaling":1,"rtx_frame_generation":0,
  "fsr_upscaling":0,"fsr_frame_generation":0,"autosave":0,"show_tutorial":0,
  "net_upnp":0,"net_lan":0,"net_directory":0},true)
 GameData.resolution_size="1920x1080"
 GameData.options.resolution=maxi(0,GameData.resolutions().find(Vector2i(1920,1080)))
 GameData._window_state.clear();GameData._apply_window()
 await get_tree().create_timer(0.5,true,false,true).timeout
 GameData._window_gen+=1
 get_window().wrap_controls=false;get_window().min_size=Vector2i.ONE
 get_window().mode=Window.MODE_WINDOWED;get_window().borderless=true
 get_window().size=Vector2i(1920,1080);get_window().position=Vector2i.ZERO
 s=Session.new();get_parent().add_child(s)
 g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
 check(await s.local_host.start(0,1,true)==OK,"solo worker starts")
 await s.new_campaign(false)
 check(await until(func():return s.world!=null and not s._remote_loading,90),"campaign starts")
 s.submit({"t":"console","line":"god on","request":1})
 s.submit({"t":"console","line":"travel gz12k","request":2})
 check(await until(func():return s.zone_id=="gz12k" and not s._remote_loading,120),"recorded snowy zone loads")
 check(await until(func():return LoadingScreen._current==null and ShaderCompilationScreen._current==null,120),"load barriers released")
 g.set_speed(1)
 check(s.local_host._process_alive(),"worker survives cold shader setup")
 print("SNOW_SETUP ",JSON.stringify({"online":s.online,"alive":s.local_host._process_alive(),"loaded":not s.loading_game,"paused":get_tree().paused,"gate":FsrGraphics.campaign_gate(get_tree(),g.rig.camera),"window":get_window().size,"actual_window":DisplayServer.window_get_size()}))
 if not s.local_host._process_alive():
  get_tree().quit(1);return
 s.submit({"t":"console","line":"teleport 177 188","request":3})
 var hero:GameUnit=s.party_heroes()[0]
 check(await until(func():return hero.pos.distance_to(Vector2(177,188))<0.5,10),"recorded village location")
 g.set_speed(1)
 g.rig.set_process(false);g.direct.set_process(false)
 camera=g.rig.camera;camera.fov=55
 camera.global_position=Vector3(178.464981,10.114109,-179.797256)
 camera.rotation=Vector3(-0.087266378,2.812812328,0)
 var rt:=g.get_node("SceneRaytrace")
 check(await until(func():return rt.stats.get("active",false) and rt.device!=null and rt.device.nrd_active and ShaderCompilationScreen._current==null,120),"PT and NRD ready")
 GameData._window_gen+=1
 get_window().wrap_controls=false;get_window().min_size=Vector2i.ONE
 get_window().mode=Window.MODE_WINDOWED;get_window().borderless=true
 get_window().size=Vector2i(1920,1080);get_window().position=Vector2i.ZERO
 Engine.max_fps=30
 await get_tree().create_timer(3.0,true,false,true).timeout
 check(get_window().size==Vector2i(1920,1080) and DisplayServer.window_get_size()==Vector2i(1920,1080),"capture window and swapchain match")
 check(await until(func():return s.world.time>0.5,10),"recording world advances")
 FileAccess.open(out.path_join("record-ready"),FileAccess.WRITE).store_string("1920x1080")
 await get_tree().create_timer(2.0,true,false,true).timeout
 await phase("fg-off-held",false,false)
 await phase("fg-on-held",true,false)
 await phase("fg-on-moving",true,true)
 await phase("fg-off-moving",false,true)
 GameData.options.rtx_frame_generation=0
 FileAccess.open(out.path_join("record-done"),FileAccess.WRITE).store_string("done")
 FileAccess.open(out.path_join("snow-framegen.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"))
 await s.local_host.stop();g.queue_free();s.queue_free()
 for i in 12:await get_tree().process_frame
 print("SNOW_FRAMEGEN ",checks," checks ",failures," failures")
 get_tree().quit(1 if failures else 0)
