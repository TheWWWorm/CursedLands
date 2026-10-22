extends "coop_trade.gd"
## Original LiA torch gates and actual rendered picking / two-peer use commands.
## The paid conversation itself is covered by astral_fortune.gd.
const TORCH := 2261640
const P := preload("res://src/game/script/script_parser.gd")
const Fortunes := preload("res://src/game/script/story_astral_fortunes.gd")
var observations := []

func peer(label:String, main:bool) -> Session:
	# Separate viewports give both peers actual local mouse coordinates.
	# A desktop Window reads the physical pointer instead of push_input's
	# position, so it is not an isolated input fixture when focus is elsewhere.
	var view:=SubViewport.new();view.name=label;view.size=Vector2i(1280,720)
	view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(view);roots.append(view)
	var api:=SceneMultiplayer.new();api.root_path=view.get_path();get_tree().set_multiplayer(api,view.get_path())
	var s:=Session.new();view.add_child(s)
	var g:=ObservedGame.new();g.session=s;s.game=g;view.add_child(g)
	if main:
		var display:=TextureRect.new();display.texture=view.get_texture();display.mouse_filter=Control.MOUSE_FILTER_IGNORE
		display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(display)
	return s
func call_enable(enabled:bool) -> void:
	host.world.vm._call("EnableLever",[[P.N_CALL,"GetObject",[[P.N_NUM,TORCH]]],[P.N_NUM,int(enabled)]],ScriptVM.Instance.new())
func run_script(name:String) -> void:
	var vm:=host.world.vm
	vm.spawn(name,[]);vm._run(vm.instances.back())
func frames(count:=6) -> void:
	for i in count:await get_tree().process_frame
func point_for(s:Session) -> Vector2:
	var obj:Node3D=s.world.objects[TORCH]
	var cam:=s.game.rig.camera
	s.game.rig.set_process(false);s.game.rig.edge=Vector2i.ZERO
	cam.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam.position=Vector3.ZERO;cam.global_position=obj.global_position+Vector3(-6,6,-10)
	cam.look_at(obj.global_position+Vector3.UP*1.5)
	var context:=GameUnit.MeshScreenRect.camera_context(cam)
	for mi:MeshInstance3D in s.world.lever_sys._morph[TORCH].meshes:
		var rect:=GameUnit.MeshScreenRect.of_context(mi,cam,context)
		if rect.has_area():
			observations.append({"host":s.is_host,"mesh":String(mi.name),"rect":str(rect),"hit":s.game.pick_lever(rect.get_center())})
			return rect.get_center()
	return Vector2(-100,-100)
func hover(s:Session,p:Vector2) -> String:
	s.game.selected.assign([s.party_units(s.my_index)[0]])
	var motion:=InputEventMouseMotion.new();motion.position=p;motion.global_position=p
	s.game.get_viewport().push_input(motion,true)
	s.game._update_cursor()
	print("TORCH_HOVER ",s.my_index," ",p," mouse=",s.game.get_viewport().get_mouse_position()," kind=",s.game.cursor.kind," unit=",s.game.pick_unit(p))
	return s.game.cursor.kind
func capture(label:String) -> void:
	if DisplayServer.get_name()=="headless":return
	await frames();await RenderingServer.frame_post_draw
	host.game.get_viewport().get_texture().get_image().save_png("user://torch-"+label+"-host.png")
	client.game.get_viewport().get_texture().get_image().save_png("user://torch-"+label+"-guest.png")
func _ready() -> void:
	var actor_index:=0
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--torch-player="):actor_index=int(arg.get_slice("=",1))
	process_mode=Node.PROCESS_MODE_ALWAYS
	GameData.options.merge(GfxDetect.original_look_values(true,{},-1),true)
	GameData.options.control_mode=1
	GameData.options.merge({"autosave":0,"show_tutorial":0,"net_upnp":0,"net_lan":0,"net_directory":0,"auto_graphics":0,"unit_fog":0,"resolution":1},true)
	host=peer("TorchHost",true);client=peer("TorchGuest",false)
	(client.get_parent() as SubViewport).render_target_update_mode=SubViewport.UPDATE_ALWAYS
	check(host.host(29981+actor_index,2)==OK and client.join("127.0.0.1",29981+actor_index)==OK,"torch peers connect")
	check(await until(func():return host.players.size()==2),"two torch players")
	host.state=CampaignState.new();host.state.ensure_hero(0,"Human Hero");host.state.ensure_hero(1,"Human Hero","Guest")
	host.state.set_var(0,"q.gz1h.q01h",2);host.state.set_var(0,"q.gz1h.q02h",2)
	host.set_physics_process(false)
	await host.enter_zone("gz1h",1,false)
	host.set_physics_process(false);host.world.set_process(false);host.world.set_physics_process(false)
	check(await until(func():return client.world!=null and not client._remote_loading and not client.loading_game),"both peers enter original Portal map")
	host.world.vm.instances.clear();host.world.vm.globals["Heroes"]=host.party_units(0)
	var obj:Node3D=host.world.objects[TORCH]
	var position:Vector3=obj.get_meta("ei").position
	check(obj.get_meta("ei").name=="TorchBase00-1497","fixture is the original unlit torch beside the Portal house")
	for owner in [0,1]:
		var u:GameUnit=host.party_units(owner)[0]
		u.pos=host.world.nav.nearest_walkable_for(u,Vector2(position.x,position.y)+Vector2(-3-owner,2))
		u._sync_transform()
	call_enable(false);await frames(12)
	var hp:=point_for(host);var cp:=point_for(client)
	hover(host,hp);hover(client,cp)
	check(not host.world.lever_sys.usable(TORCH) and not client.world.lever_sys.usable(TORCH),"original startup hides hand before the torch quest")
	check(host.game.pick_lever(hp)!=TORCH and client.game.pick_lever(cp)!=TORCH,"both peers refuse disabled torch picking")
	host.state.set_var(0,"b.skelet.fq2",0);host.state.set_var(0,"q.gz1h.fq2",0);host.state.set_var(0,"z.gz1d1",1)
	run_script("Raja#0")
	check(not host.world.lever_sys.usable(TORCH),"original quest watcher waits for the fortune-teller conversation")
	await capture("locked")
	# State produced by completing the actual paid skelet_fq2 dialogue,
	# carried across a map change before the original market watcher polled.
	host.state.set_var(0,"b.skelet.skelet_fq2",2)
	Fortunes.recover(host.world.vm)
	host.world.vm._forget_conditions()   # a new pass, as ScriptVM._tick starts one
	for inst:ScriptVM.Instance in host.world.vm.instances:
		inst.poll=0;host.world.vm._run(inst)
	await frames()
	check(host.world.lever_sys.usable(TORCH) and client.world.lever_sys.usable(TORCH),"original Raja watcher enables torch on host and guest after completed fortune")
	check(host.state.get_var(0,"z.gz1d1")==1,"accepting the fortune alone does not open the entrance")
	var host_cursor:=hover(host,hp);var guest_cursor:=hover(client,cp)
	check(host.game.pick_lever(hp)==TORCH and client.game.pick_lever(cp)==TORCH,"actual torch mesh is clickable on both peers")
	check(host_cursor=="cursor_use" and guest_cursor=="cursor_use","one selected hero sees the hand icon on both peers")
	await capture("available")
	# The real snapshot payload used by saves and late joiners retains the gate.
	host.state.store_zone("gz1h",host.world)
	var row:Array=host.state.zones.gz1h.levers[TORCH]
	client.world.lever_sys.restore_row(TORCH,row)
	check(client.world.lever_sys.usable(TORCH),"enabled torch survives the campaign snapshot importer")
	# One fresh world per operator: this mechanism is authored as one-shot.
	for s:Session in [client if actor_index==1 else host]:
		var owner:=s.my_index
		# Each actor gets an independent route; the previous operator must
		# leave the narrow approach before checking the other player.
		var other:GameUnit=host.party_units(1-owner)[0]
		other.command({"type":"wait","t":0.0})
		other.pos=host.world.nav.nearest_walkable_for(other,Vector2(position.x,position.y)+Vector2(-6,5))
		other._sync_transform()
		var operator:GameUnit=host.party_units(owner)[0]
		operator.blocked=false
		operator.command({"type":"wait","t":0.0})
		operator.pos=host.world.nav.nearest_walkable_for(operator,Vector2(position.x,position.y)+Vector2(-4,2))
		operator._sync_transform()
		host.world.vm.instances.clear();host.world.lever_sys.restore_row(TORCH,[0,0.0,true]);client.world.lever_sys.restore_row(TORCH,[0,0.0,true])
		host.state.set_var(0,"z.gz1d1",1)
		run_script("TorchBase#1")
		s.game.selected.assign([s.party_units(owner)[0]])
		s.game.order_on(null,false,cp if s==client else hp)
		var u:GameUnit=host.party_units(owner)[0]
		check(await until(func():return u.has_meta("interact")),"player %d click reaches authority as a use order"%owner)
		for tick in 400:
			# Keep combat and unrelated NPC scripts out of this interaction
			# fixture; the operator uses the real route and animation code.
			host.world.time+=GameUnit.TICK;host.world._logic_step+=1
			host.world.vm.tick(GameUnit.TICK);u.tick(GameUnit.TICK)
			host.world.lever_sys.tick()
			if int(host.world.levers[TORCH].state)==1 and host.state.get_var(0,"z.gz1d1")==2:break
			if tick%10==0:await frames(1)
		print("TORCH_USE ",owner," ",u.pos," ",u.order," failed=",u.order_failed," dead=",u.dead," blocked=",u.blocked," reach=",host.world.vm._interact_reach(u,obj)," interact=",u.get_meta("interact",[]))
		check(int(host.world.levers[TORCH].state)==1,"player %d walks and performs original use action"%owner)
		check(host.state.get_var(0,"z.gz1d1")==2,"player %d use runs original entrance-unlock script"%owner)
		check(int(host.world.levers[TORCH].state)==1 and await until(func():return int(client.world.levers[TORCH].state)==1),"player %d torch activation reaches guest"%owner)
		check(not host.world.lever_sys.usable(TORCH) and not client.world.lever_sys.usable(TORCH),"original one-shot torch cannot be used again")
	await capture("activated")
	FileAccess.open("user://astral-torch.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations},"\t"))
	host.online=false;client.online=false
	client.multiplayer.multiplayer_peer.close();host.multiplayer.multiplayer_peer.close()
	for root in roots:root.queue_free()
	await frames()
	print("ASTRAL_TORCH ",checks," checks ",failures," failures")
	TexUpscale.shutdown();get_tree().quit(1 if failures else 0)
