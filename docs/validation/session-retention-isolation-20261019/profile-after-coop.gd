extends Node
## Sustained play through the normal game/ENet command paths. Separate owner,
## guest and authority processes; authored mobs, routes, mana and damage remain
## live. No teleports, direct spell spawning, deleted mobs or invulnerability.
var s:Session
var g:Game
var guest:=false
var child:=-1
var began:=0
var next_decision:=0.0
var next_sample:=0.0
var next_shot:=0.0
var frames:Array[float]=[]
var frame_usec:=0
var progress_pos:=Vector2.ZERO
var progress_at:=0.0
var samples:=[]
var start_pos:=Vector2.ZERO
var last_pos:=Vector2.ZERO
var travelled:=0.0
var visited:={}
var target_id:=-1
var attempts:={"lightning":0,"acid_fog":0,"weak":0,"attack":0,"move":0,"heal":0}
var last_spell:=0.0
var attack_target:=-1
var stage:="explore"
var initial_dead:=0
var cast_serials:={}
var target_since:=0.0
var rest_until:=0.0
var target_origin:=Vector2.ZERO
var _running:=false
var route:=[Vector2(345,110),Vector2(345,170),Vector2(350,230),Vector2(300,280),Vector2(230,280),Vector2(200,220),Vector2(200,160),Vector2(280,160),Vector2(340,120)]
var route_index:=0
var move_goal:=Vector2.INF
var progress_hp:=INF
var initial_world_time:=0.0
var current_control:={}
var control_mtime:=0
var run_label:=""
var render_gpu:Array[float]=[]
var render_cpu:Array[float]=[]
var resume_slot:=""
var duration:=900.0
var stationary:=false
var frame_profiler:Script
func frames_wait(n:int)->void:
	for i in n:await get_tree().process_frame
func until(fn:Callable,seconds:=60.0)->bool:
	var end:=Time.get_ticks_msec()+seconds*1000
	while not fn.call() and Time.get_ticks_msec()<end:await get_tree().process_frame
	return fn.call()
func hero()->GameUnit:
	var party:=s.party_units(s.my_index)
	return party[0] if not party.is_empty() else null
func _ready()->void:run.call_deferred()
func run()->void:
	if OS.get_cmdline_user_args().has("--validate-only"):
		print("PASS traversal tool parses with game autoloads");get_tree().quit();return
	guest=OS.get_cmdline_user_args().has("--guest")
	stationary=OS.get_cmdline_user_args().has("--stationary")
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-slot="):resume_slot=arg.trim_prefix("--resume-slot=")
		if arg.begins_with("--duration="):duration=float(arg.trim_prefix("--duration="))
	GameData.options.merge(GfxPresets.values(GfxPresets.ULTRA),true)
	GameData.options.merge({"autosave":0,"show_tutorial":0,"auto_graphics":0,"net_lan":0,"net_upnp":0,"net_directory":0,"control_mode":1,"display_mode":0,"confine_mouse":0,"vsync":0,"fps_limit":0,"scroll_border":0,"pad_enabled":0,"coop_clock":1,"camera_style":1,"cam_follow":1},true)
	Engine.max_fps=0
	await frames_wait(15);GameData._window_gen+=1;get_window().mode=Window.MODE_WINDOWED;get_window().size=Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	run_label="after-trials-" if OS.get_cmdline_user_args().has("--trials-first") or OS.get_cmdline_user_args().has("--after-trials") else ""
	if not resume_slot.is_empty():run_label="reloaded-"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):run_label=arg.trim_prefix("--label=").validate_filename()+"-"
	if not guest and OS.get_cmdline_user_args().has("--trials-first"):
		for cycle in 3:await trial(cycle)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	s=Session.new();get_parent().add_child(s);g=Game.new();g.session=s;s.game=g;get_parent().add_child(g)
	if guest:
		GameData.player_name="Traversal guest"
		if s.join("127.0.0.1",29916)!=OK:get_tree().quit(2);return
	else:
		var state:=CampaignState.new();state.current_zone="gz17h"
		for player in 2:
			state.ensure_hero(player,"Human Hero","Traversal owner" if player==0 else "Traversal guest")
			var h:Dictionary=state.heroes[player][0]
			h.str=38.0;h.dex=38.0;h.int=38.0;h.level=15;h.exp_total=2000000.0
			h.skills={"melee":100,"archery":40,"sense":60,"science":25,"elemental":100,"astral":100}
			h.spells=["lightning{e2;e2;e2;m2;m2;m2}","acid_fog{ff;e2;e2;m2;m2;r2}","weak{e2;m2}","healing{e2;e2;e2;m2;m2;m2}"]
			h.weapons=["crystal sword.diamond"]
			h.armors=["hadagan highest helm.mithrill","hadagan highest plate.mithrill","hadagan highest leggins.mithrill","hadagan highest shirt.mithrill","hadagan highest pants.mithrill","hadagan highest boots.mithrill","hadagan highest gloves.mithrill"]
			h.quick=["large potion 1","large potion 1","large potion 1","large potion 1"]
			h.perks=["bs1"]
			for family:String in ["sword","mana","health","quickness","vitality","spirit"]:
				for rank in range(1,4):h.perks.append(family+str(rank))
		if resume_slot.is_empty():state.save(SaveInfo.path("traversal-session"))
		if await s.local_host.start(29916,2,false)!=OK:get_tree().quit(2);return
		var args:=PackedStringArray(["--rendering-method","forward_plus","--render-thread","safe"])
		if OS.has_feature("editor"):args.append_array(["--path",ProjectSettings.globalize_path("res://")])
		args.append_array(["--","--ei-path="+GameData.root,"--tool="+get_script().resource_path,"--guest"])
		if not run_label.is_empty():args.append("--label="+run_label.trim_suffix("-"))
		if not resume_slot.is_empty():args.append("--resume-slot="+resume_slot)
		args.append("--duration="+str(duration))
		if stationary:args.append("--stationary")
		child=OS.create_process(OS.get_executable_path(),args)
		if not await until(func():return s.players.size()==2):push_error("Guest did not join");get_tree().quit(2);return
		if not await s.load_game_shown("traversal-session" if resume_slot.is_empty() else resume_slot):get_tree().quit(2);return
	if not await until(func():return s.world!=null and not s._remote_loading and not s.loading_game and hero()!=null):get_tree().quit(2);return
	await frames_wait(60)
	var h:=hero();g.selected.assign([h]);g.rig.follow(h);start_pos=h.pos;last_pos=h.pos
	g.hud.text_window.open=false
	g.rig.focus(h.position);g.rig.follow(h)
	if not guest:g.set_speed(2)
	await until(func():return s.clock_speed==1,10)
	print("TRAVERSE_CLOCK ",s.clock_speed," ",Engine.time_scale)
	print("TRAVERSE_KIT ",JSON.stringify(h.stats))
	progress_pos=h.pos;progress_at=0;frame_usec=Time.get_ticks_usec()
	g.issue({"t":"gait","units":[h.uid],"gait":2})
	g.issue({"t":"aggression","units":[h.uid],"on":false})
	initial_dead=s.world.unit_rows().filter(func(u):return u.dead).size()
	print("TRAVERSE_START ","guest" if guest else "owner"," hero=",h.uid," position=",h.pos," hp=",h.max_hp," mana=",h.max_mana," foes=",s.world.unit_rows().filter(func(u):return s.world.is_enemy(h,u)).size())
	if stationary:g.issue({"t":"stop","units":[h.uid]})
	frame_profiler=load("res://frame_profile.gd");frame_profiler.enabled=true
	initial_world_time=s.world.time;began=Time.get_ticks_msec();next_decision=INF if stationary else 30.0;stage="baseline";_running=true
func trial(cycle:int)->void:
	# Set up a populated late-round roster, then let all nine native battles
	# play out. Leave through normal scene teardown without clearing caches.
	GameData.arena_mode=1;GameData.arena_speed=2
	var screen:=ArenaPveScreen.new();get_parent().add_child(screen);await frames_wait(8)
	screen._seed_input.text=str(7319+cycle);screen._begin();screen.run.auto_save=false
	screen.run.wave=12;screen.run.stage="prepare";screen.run.lives=100
	for player in 9:
		var company:=(screen.run as ArenaTournamentRun).company(player)
		company.army.clear();company.wave=12;company.training=110;company.gold=50;company.auto_save=false;company.lives=company.life_limit()
		for family in [7,9,10,11,17,18,22]:company._recruit(family,1,10)
		company.arrange()
	(screen.run as ArenaTournamentRun)._prepare_round()
	for plan:Dictionary in screen.run.bot_plans:plan.done=true
	screen._refresh();screen._tournament_battles.synchronize();await frames_wait(40)
	screen._tournament_battles.request_start()
	if not await until(func():return screen.run.stage!="prepare"):
		push_error("Trials combat did not start");get_tree().quit(2);return
	await until(func():return screen.run.stage!="fight",65)
	print("TRAVERSE_TRIAL ",JSON.stringify({"cycle":cycle,"stage":screen.run.stage,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"video":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)}))
	screen.queue_free();await frames_wait(120)
	print("TRAVERSE_TRIAL_FREED ",JSON.stringify({"cycle":cycle,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"video":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)}))
func choose_target(h:GameUnit)->GameUnit:
	var candidates:=s.world.unit_rows().filter(func(u):return u!=h and not u.dead and not u.hidden and u.visible and u.controller<0 and s.world.is_enemy(h,u) and not visited.has(u.uid) and h.pos.distance_to(u.pos)<18 and s.world.sight_ray(h,u)>0.1)
	candidates.sort_custom(func(a,b):return h.pos.distance_squared_to(a.pos)<h.pos.distance_squared_to(b.pos))
	return candidates[0] if not candidates.is_empty() else null
func move_to(h:GameUnit,point:Vector2)->void:
	if move_goal.distance_to(point)<2 and h.action in ["walk","run"]:return
	g.issue({"t":"move","units":[h.uid],"x":point.x,"y":point.y,"run":false});attempts.move+=1;move_goal=point
func decide(t:float)->void:
	var h:=hero()
	if h==null:return
	if h.dead:
		stage="dead";_running=false;finish.call_deferred();return
	g.selected.assign([h])
	var control_path:String=get_script().resource_path.get_base_dir().path_join("traversal-control.json")
	if FileAccess.file_exists(control_path) and FileAccess.get_modified_time(control_path)!=control_mtime:
		control_mtime=FileAccess.get_modified_time(control_path)
		var control=JSON.parse_string(FileAccess.get_file_as_string(control_path))
		if control is Dictionary:
			current_control=control
			if control.get("skip",false) and target_id>=0:visited[target_id]=true
	if current_control.get("finish",false):_running=false;finish.call_deferred();return
	# Live steering gives normal movement orders, so an obstructed encounter
	# can be left without teleporting or changing authored enemies.
	if current_control.get("move_only",false) or current_control.get("return",false):
		var point:=start_pos if current_control.get("return",false) else Vector2(current_control.point[0],current_control.point[1])
		stage="return" if current_control.get("return",false) else "travel"
		if h.pos.distance_to(point)>1.0:move_to(h,point)
		elif h.action in ["walk","run"]:g.issue({"t":"stop","units":[h.uid]})
		return
	if h.hp<h.max_hp*0.6 and t-last_spell>2 and h.mana>40:
		g.begin_cast(3);g.cast_on(h);g.cancel_touch_target();attempts.heal+=1;last_spell=t;attack_target=-1;return
	if h.hp<h.max_hp*0.4 and t-last_spell>2:
		var belt:Array=h.get_meta("hero").get("quick",[])
		if not belt.is_empty():
			g.issue({"t":"use","unit":h.uid,"item":belt[0]});attempts.heal+=1;last_spell=t;attack_target=-1;return
	if h.action.begins_with("cast") or t-last_spell<1.4:return
	if t>720:
		stage="return"
		if h.pos.distance_to(start_pos)>1:move_to(h,start_pos)
		else:
			stage="settled"
			if h.action in ["walk","run"]:g.issue({"t":"stop","units":[h.uid]})
		return
	if h.mana<60 or t<rest_until:
		if stage!="rest":
			g.issue({"t":"stop","units":[h.uid]});rest_until=t+5;attack_target=-1;move_goal=Vector2.INF
		stage="rest";return
	var target:GameUnit=s.world.units.get(target_id)
	if target and h.pos.distance_to(target.pos)>24:target=null
	if target and (h.pos.distance_to(progress_pos)>3 or target.hp<progress_hp-2):
		progress_pos=h.pos;progress_hp=target.hp;progress_at=t
	if target and (t-progress_at>40 or (t-target_since>75 and h.pos.distance_to(target.pos)>4)):
		visited[target.uid]=true;print("TRAVERSE_SKIP_STALLED ",target.uid);target=null
	if target==null or target.dead or visited.has(target.uid):
		if target and target.dead:visited[target.uid]=true
		target=choose_target(h);target_id=target.uid if target else -1;attack_target=-1;target_since=t;progress_at=t;progress_hp=INF
		if target:print("TRAVERSE_TARGET ","guest" if guest else "owner"," time=",int(t)," ",target.display_name," ",target.pos)
	if target:
		stage="combat";move_goal=Vector2.INF
		if t-last_spell>5 and h.mana>100:
			var slot:=int(attempts.lightning+attempts.acid_fog+attempts.weak)%3
			g.begin_cast(slot)
			if not g.pending_target(target,target.pos).is_empty():
				g.cast_on(target,null,target.pos);attempts[["lightning","acid_fog","weak"][slot]]+=1
				g.cancel_touch_target();last_spell=t;attack_target=-1;return
			g.cancel_touch_target()
		if attack_target!=target_id or h.action=="idle":
			g.forced_on("attack",target,null);attempts.attack+=1;attack_target=target_id
		return
	if t>720 or current_control.get("return",false):
		stage="return";move_to(h,start_pos);return
	var point:Vector2=route[route_index%route.size()]
	if current_control.has("point"):point=Vector2(current_control.point[0],current_control.point[1])
	if h.pos.distance_to(point)<8:
		route_index+=1;point=route[route_index%route.size()];print("TRAVERSE_WAYPOINT ",route_index," at ",h.pos)
	stage="travel";move_to(h,point)
func sample(t:float)->void:
	var h:=hero()
	var n:=frames.size();var total:float=frames.reduce(func(a,b):return a+b,0.0);frames.sort()
	var fx:=ParticleFx.of(s.world)
	var row:={"peer":"guest" if guest else "owner","seconds":t,"clock":s.clock_speed,"time_scale":Engine.time_scale,"fps":1000.0*n/total if total>0 else 0,"p95_ms":frames[int(n*0.95)] if n else 0,"position":[h.pos.x,h.pos.y] if h else [],"travelled":travelled,"hp":h.hp if h else 0,"mana":h.mana if h else 0,"phase":stage,"visited":visited.size(),"deaths":s.world.unit_rows().filter(func(u):return u.dead).size()-initial_dead,"attempts":attempts.duplicate(),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"video":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED),"effects":fx.effects.size(),"bolts":fx.bolts.size(),"lights":fx.lights.size(),"virtual_sounds":g.sound.mixer._virtual.size(),"real_casts":cast_serials.size(),"action":h.action if h else "", "target_hp":s.world.units[target_id].hp if s.world.units.has(target_id) else -1, "target_distance":h.pos.distance_to(s.world.units[target_id].pos) if s.world.units.has(target_id) else -1, "camera":str(g.rig.position), "model_visible":h.model.visible,"route_index":route_index,"world_seconds":s.world.time-initial_world_time,"depth":h.pos.distance_to(start_pos)}
	row.gpu_ms=render_gpu.reduce(func(a,b):return a+b,0.0)/maxi(1,render_gpu.size())
	row.input={"serial":s._input_out.serial,"pending":s._input_out.pending.size(),"epoch":s._pool_epoch,"blocked":h.blocked if h else false,"loading":s.loading_game,"movie":s.movie_active()}
	row.render_cpu_ms=render_cpu.reduce(func(a,b):return a+b,0.0)/maxi(1,render_cpu.size())
	row.particles=0
	for effect:ParticleFx.Effect in fx.effects:row.particles+=effect.e.parts.size()
	row.npc_actions={}
	for unit:GameUnit in s.world.unit_rows():
		if unit.controller<0:row.npc_actions[unit.action]=int(row.npc_actions.get(unit.action,0))+1
	var marks:=s.world.ground_marks
	row.ground_marks={"foot":marks.foot_marks.size(),"blood":marks.blood_marks.size(),"fire":marks.fire_marks.size()}
	row.script_profile=frame_profiler.take()
	samples.append(row);print("TRAVERSE_SAMPLE ",JSON.stringify(row));frames.clear();render_gpu.clear();render_cpu.clear()
	FileAccess.open("user://traversal-"+run_label+("guest" if guest else "owner")+".json",FileAccess.WRITE).store_string(JSON.stringify(samples,"\t"))
func _process(dt:float)->void:
	if not _running:return
	g.rig._window_focused=true # Both rendered peers keep following as on two PCs.
	var now_usec:=Time.get_ticks_usec()
	frames.append((now_usec-frame_usec)/1000.0);frame_usec=now_usec
	render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
	render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
	var t:=(Time.get_ticks_msec()-began)/1000.0
	var h:=hero()
	if h:
		travelled+=h.pos.distance_to(last_pos);last_pos=h.pos
		if h.action.begins_with("cast"):cast_serials[str(h.uid)+":"+str(h._remote_action_serial)]=true
	if t>=next_decision:next_decision=t+1.5;decide(t)
	if t>=next_sample:next_sample=t+30;sample(t)
	if t>=next_shot:
		next_shot=t+60
		capture.call_deferred(int(t))
	if t>=duration:
		if not samples.is_empty() and t-float(samples[-1].seconds)>1.0:sample(t)
		_running=false;finish.call_deferred()
func capture(second:int)->void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://traversal-%s%s-%03d.png"%[run_label,"guest" if guest else "owner",second])
func finish()->void:
	if guest:
		s.online=false;s.multiplayer.multiplayer_peer.close()
	else:
		await s.local_host.stop()
		if child>0 and OS.is_process_running(child):OS.kill(child)
	g.queue_free();s.queue_free();await frames_wait(8);TexUpscale.shutdown();get_tree().quit()
